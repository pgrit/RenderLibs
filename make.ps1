mkdir install
mkdir build

# Patch the Embree and OIDN CMake files to have a more useful RPATH
function rpathPatch($content)
{
    $oldMac = '"@loader_path/../'
    $newMac = '"@loader_path;@loader_path/../'
    $oldLinux = '"$ORIGIN/../'
    $newLinux = '"$ORIGIN;$ORIGIN/../'
    return $content.Replace("$oldMac", "$newMac").Replace("$oldLinux", "$newLinux")
}

rpathPatch(Get-Content -path embree/common/cmake/package.cmake -Raw) | Set-Content -path embree/common/cmake/package.cmake
rpathPatch(Get-Content -path oidn/cmake/oidn_package.cmake -Raw) | Set-Content -path oidn/cmake/oidn_package.cmake

cd build

# Download ISPC
$ispcVersion = "1.18.0"
if ([environment]::OSVersion::IsLinux())
{
    $OS = "linux"

    if (-not(Test-Path -Path "ispc.zip" -PathType Leaf))
    {
        wget -q "https://github.com/ispc/ispc/releases/download/v$ispcVersion/ispc-v$ispcVersion-linux.tar.gz" -O "ispc.tar.gz"
        tar -xf ispc.tar.gz
    }
    $ispc = "../ispc-v$ispcVersion-linux/bin/ispc"
}
elseif ([environment]::OSVersion::IsMacOS())
{
    $OS = "osx"

    if (-not(Test-Path -Path "ispc.zip" -PathType Leaf))
    {
        wget -q "https://github.com/ispc/ispc/releases/download/v$ispcVersion/ispc-v$ispcVersion-macOS.tar.gz" -O "ispc.tar.gz"
        tar -xf ispc.tar.gz
    }
    $ispc = "../ispc-v$ispcVersion-macOS/bin/ispc"
}
elseif ([environment]::OSVersion::IsWindows())
{
    $OS = "win"

    if (-not(Test-Path -Path "ispc.zip" -PathType Leaf))
    {
        Invoke-WebRequest -Uri "https://github.com/ispc/ispc/releases/download/v$ispcVersion/ispc-v$ispcVersion-windows.zip" -OutFile "ispc.zip"
        Expand-Archive "ispc.zip" -DestinationPath .
    }
    $ispc = "../ispc-v$ispcVersion-windows/bin/ispc.exe"
}
else
{
    echo "Unsupported OS"
    cd ..
    exit -1
}

function build($name, [String[]]$cmakeArgs)
{
    mkdir "$name"
    cd "$name"
    echo $cmakeArgs

    if ([environment]::OSVersion::IsMacOS())
    {
        # On OSX, we build a fat binary with both x86_64 and arm64 support
        # $extra = '-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"'
    }
    echo $extra

    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="../../install/$OS" $cmakeArgs "../../$name" $extra
    if (-not $?) { throw "CMake configure failed" }
    cmake --build . --config Release
    if (-not $?) { throw "Build failed" }
    cmake --install . --config Release
    if (-not $?) { throw "Install failed" }
    cd ..
}

build "oneTBB" "-DTBB_TEST=OFF"

build "oidn" @(
    "-DTBB_ROOT=../../install/$OS"
    "-DISPC_EXECUTABLE=$ispc"
    "-DISPC_VERSION=$ispcVersion"
    "-DOIDN_APPS=OFF"
    "-DOIDN_ZIP_MODE=ON"
)

build "embree" @(
    "-DEMBREE_ISPC_SUPPORT=OFF"
    "-DEMBREE_ZIP_MODE=ON"

    # Disable all unused features to shorten build times
    "-DEMBREE_TUTORIALS=OFF"
    "-DEMBREE_FILTER_FUNCTION=OFF"
    "-DEMBREE_GEOMETRY_QUAD=OFF"
    "-DEMBREE_GEOMETRY_CURVE=OFF"
    "-DEMBREE_GEOMETRY_GRID=OFF"
    "-DEMBREE_GEOMETRY_SUBDIVISION=OFF"
    "-DEMBREE_GEOMETRY_INSTANCE=OFF"
    "-DEMBREE_GEOMETRY_USER=ON"

    # Enable only AVX, AVX2 and NEON for faster github actions deployment
    "-DEMBREE_MAX_ISA=NONE"
    "-DEMBREE_ISA_AVX2=ON"
    "-DEMBREE_ISA_SSE2=OFF"
    "-DEMBREE_ISA_SSE42=OFF"
    "-DEMBREE_ISA_AVX512=OFF"
    "-DEMBREE_ISA_AVX=ON"
    "-DEMBREE_ISA_NEON=ON"
)

if ([environment]::OSVersion::IsLinux())
{
    $rpath = '-DCMAKE_INSTALL_RPATH=$ORIGIN'
}
elseif ([environment]::OSVersion::IsMacOS())
{
    $rpath = '-DCMAKE_INSTALL_RPATH=@loader_path'
}

build "openpgl" @(
    "-DOPENPGL_TBB_ROOT=../../install/$OS"
    "-DCMAKE_PREFIX_PATH=../../install/$OS"
    $rpath
)

cd ..

# Delete symlinks because GitHub Actions will replace them by copies of the file
# Instead, make sure that the filenames match what is required by the dependents
if ([environment]::OSVersion::IsLinux())
{
    find ./install -type l -delete
    mv ./install/linux/lib/libtbb.so.12.8 ./install/linux/lib/libtbb.so.12
}