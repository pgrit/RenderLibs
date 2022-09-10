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

# Path OIDN CMake files for cross-compile on Mac
$patch = (Get-Content -path oidn/cmake/oidn_platform.cmake -Raw)
$patch = $patch.Replace('set(OIDN_ARCH "ARM64")', 'set(OIDN_ARCH "ARM64" CACHE STRING " ")')
$patch = $patch.Replace('set(OIDN_ARCH "X64")', 'set(OIDN_ARCH "X64" CACHE STRING " ")')
Set-Content -path oidn/cmake/oidn_platform.cmake $patch

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

    cmake -DCMAKE_BUILD_TYPE=Release $cmakeArgs "../../$name"
    if (-not $?) { throw "CMake configure failed" }
    cmake --build . --config Release
    if (-not $?) { throw "Build failed" }
    cmake --install . --config Release
    if (-not $?) { throw "Install failed" }
    cd ..
}

build "oneTBB" @(
    "-DTBB_TEST=OFF"
    '-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"'
    '-DCMAKE_INSTALL_PREFIX="../../install/'+"$OS"+'"'
)

# Neural runtimes for OIDN on Mac require separate binaries for arm64 and x86-64
if ([environment]::OSVersion::IsMacOS())
{
    # Build once for x86-64 with DNNL
    build "oidn" @(
        "-DTBB_ROOT=../../install/$OS"
        "-DISPC_EXECUTABLE=$ispc"
        "-DISPC_VERSION=$ispcVersion"
        "-DOIDN_APPS=OFF"
        "-DOIDN_ZIP_MODE=ON"
        '-DOIDN_NEURAL_RUNTIME="DNNL"'
        '-DCMAKE_OSX_ARCHITECTURES="x86_64"'
        '-DCMAKE_INSTALL_PREFIX="../../install/'+"$OS"+'"'
        '-DOIDN_ARCH="X64"'
    )

    # And separately for ARM64 with BNNS
    build "oidn" @(
        "-DTBB_ROOT=../../install/$OS"
        "-DISPC_EXECUTABLE=$ispc"
        "-DISPC_VERSION=$ispcVersion"
        "-DOIDN_APPS=OFF"
        "-DOIDN_ZIP_MODE=ON"
        '-DOIDN_NEURAL_RUNTIME="BNNS"'
        '-DCMAKE_OSX_ARCHITECTURES="arm64"'
        '-DCMAKE_INSTALL_PREFIX="../../install/'+"$OS"+'-arm64"'
        '-DOIDN_ARCH="ARM64"'
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

        # Enable only AVX and AVX2 for faster github actions deployment
        "-DEMBREE_MAX_ISA=NONE"
        "-DEMBREE_ISA_AVX2=ON"
        "-DEMBREE_ISA_SSE2=OFF"
        "-DEMBREE_ISA_SSE42=OFF"
        "-DEMBREE_ISA_AVX512=OFF"
        "-DEMBREE_ISA_AVX=ON"

        '-DCMAKE_OSX_ARCHITECTURES="x86_64"'
        '-DCMAKE_INSTALL_PREFIX="../../install/'+"$OS"+'"'
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

        '-DCMAKE_OSX_ARCHITECTURES="arm64"'
        '-DCMAKE_INSTALL_PREFIX="../../install/'+"$OS"+'-arm64"'
    )
}
else
{
    build "oidn" @(
        "-DTBB_ROOT=../../install/$OS"
        "-DISPC_EXECUTABLE=$ispc"
        "-DISPC_VERSION=$ispcVersion"
        "-DOIDN_APPS=OFF"
        "-DOIDN_ZIP_MODE=ON"
        '-DCMAKE_INSTALL_PREFIX="../../install/'+"$OS"+'"'
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

        '-DCMAKE_INSTALL_PREFIX="../../install/'+"$OS"+'"'
    )
}

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
    '-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"'
    '-DCMAKE_INSTALL_PREFIX="../../install/'+"$OS"+'"'
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
elseif ([environment]::OSVersion::IsMacOS())
{
    find ./install -type l -delete
    mv ./install/osx/lib/libtbb.12.8.dylib ./install/osx/lib/libtbb.12.dylib
}