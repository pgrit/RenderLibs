$rootPath = Get-Location

try {

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

    # Patch OIDN CMake files for cross-compile on Mac
    $patch = (Get-Content -path oidn/cmake/oidn_platform.cmake -Raw)
    $patch = $patch.Replace('set(OIDN_ARCH "ARM64")', 'set(OIDN_ARCH "ARM64" CACHE STRING " ")')
    $patch = $patch.Replace('set(OIDN_ARCH "X64")', 'set(OIDN_ARCH "X64" CACHE STRING " ")')
    Set-Content -path oidn/cmake/oidn_platform.cmake $patch

    # Patch embree CMake files for cross-compile on Mac
    $patch = (Get-Content -path embree/CMakeLists.txt -Raw)
    $patch = $patch.Replace('SET(EMBREE_ARM ON)', 'OPTION(EMBREE_ARM " " ON)')
    Set-Content -path embree/CMakeLists.txt $patch

    # Patch openpgl CMake files for cross-compile on Mac
    $patch = (Get-Content -path openpgl/CMakeLists.txt -Raw)
    $patch = $patch.Replace('SET(OPENPGL_ARM ON)', ' ')
    $patch = $patch.Replace('SET(OPENPGL_ARM OFF)', 'OPTION(OPENPGL_ARM " " OFF)')
    Set-Content -path openpgl/CMakeLists.txt $patch

    # Patch DLL flags for windows to find the DLL also next to the linking one
    # (roughly the equivalent of RPATH = '.')
    function dllLoadPatch($filename)
    {
        $oldLoadFlags = '/DEPENDENTLOADFLAG:0x2000'
        $newLoadFlags = '/DEPENDENTLOADFLAG:0x2100'

        $patch = (Get-Content -path $filename -Raw)
        $patch = $patch.Replace($oldLoadFlags, $newLoadFlags)
        Set-Content -path $filename $patch
    }
    dllLoadPatch("embree/common/cmake/dpcpp.cmake")
    dllLoadPatch("embree/common/cmake/msvc.cmake")
    dllLoadPatch("oidn/cmake/oidn_platform.cmake")
    dllLoadPatch("openpgl/CMakeLists.txt")

    cd build

    # Download ISPC
    $ispcVersion = "1.23.0"
    if ([environment]::OSVersion::IsLinux())
    {
        $OS = "linux"

        if (-not(Test-Path -Path "ispc.zip" -PathType Leaf))
        {
            wget -q "https://github.com/ispc/ispc/releases/download/v$ispcVersion/ispc-v$ispcVersion-linux.tar.gz" -O "ispc.tar.gz"
            tar -xf ispc.tar.gz
        }
        $ispc = Resolve-Path "./ispc-v$ispcVersion-linux/bin/ispc"
    }
    elseif ([environment]::OSVersion::IsMacOS())
    {
        $OS = "osx"

        if (-not(Test-Path -Path "ispc.zip" -PathType Leaf))
        {
            wget -q "https://github.com/ispc/ispc/releases/download/v$ispcVersion/ispc-v$ispcVersion-macOS.universal.tar.gz" -O "ispc.tar.gz"
            tar -xf ispc.tar.gz
        }
        $ispc = Resolve-Path "./ispc-v$ispcVersion-macOS.universal/bin/ispc"
    }
    elseif ([environment]::OSVersion::IsWindows())
    {
        $OS = "win"

        if (-not(Test-Path -Path "ispc.zip" -PathType Leaf))
        {
            Invoke-WebRequest -Uri "https://github.com/ispc/ispc/releases/download/v$ispcVersion/ispc-v$ispcVersion-windows.zip" -OutFile "ispc.zip"
            Expand-Archive "ispc.zip" -DestinationPath .
        }
        $ispc = Resolve-Path "./ispc-v$ispcVersion-windows/bin/ispc.exe"
    }
    else
    {
        echo "Unsupported OS"
        cd ..
        exit -1
    }

    # Check that ISPC was downloaded correctly and the path is fine
    &$ispc --version
    if (-not $?) { throw "ISPC path invalid" }

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

    if ([environment]::OSVersion::IsLinux())
    {
        $rpath = '-DCMAKE_INSTALL_RPATH=$ORIGIN'
    }
    elseif ([environment]::OSVersion::IsMacOS())
    {
        $rpath = '-DCMAKE_INSTALL_RPATH=@loader_path'
    }

    if ([environment]::OSVersion::IsMacOS())
    {
        build "oneTBB" @(
            "-DTBB_TEST=OFF"
            '-DCMAKE_OSX_ARCHITECTURES="x86_64;arm64"'
            "-DCMAKE_INSTALL_PREFIX=../../install/$OS"
        )

        build "oidn" @(
            "-DTBB_ROOT=../../install/$OS"
            "-DISPC_EXECUTABLE=$ispc"
            "-DISPC_VERSION=$ispcVersion"
            "-DOIDN_APPS=OFF"
            "-DOIDN_ZIP_MODE=ON"
            '-DCMAKE_OSX_ARCHITECTURES="x86_64"'
            "-DCMAKE_INSTALL_PREFIX=../../install/$OS"
            '-DOIDN_ARCH="X64"'
            "-DOIDN_FILTER_RTLIGHTMAP=OFF"
        )

        build "oidn" @(
            "-DTBB_ROOT=../../install/$OS"
            "-DISPC_EXECUTABLE=$ispc"
            "-DISPC_VERSION=$ispcVersion"
            "-DOIDN_APPS=OFF"
            "-DOIDN_ZIP_MODE=ON"
            '-DCMAKE_OSX_ARCHITECTURES="arm64"'
            "-DCMAKE_INSTALL_PREFIX=../../install/$OS-arm64"
            '-DOIDN_ARCH="ARM64"'
            "-DOIDN_FILTER_RTLIGHTMAP=OFF"
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

            "-DEMBREE_ARM=OFF"

            '-DCMAKE_OSX_ARCHITECTURES="x86_64"'
            "-DCMAKE_INSTALL_PREFIX=../../install/$OS"
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

            "-DEMBREE_ARM=ON"

            '-DCMAKE_OSX_ARCHITECTURES="arm64"'
            "-DCMAKE_INSTALL_PREFIX=../../install/$OS-arm64"
        )

        build "openpgl" @(
            "-DTBB_ROOT=../../install/$OS"
            "-DOPENPGL_TBB_ROOT=../../install/$OS"
            "-DCMAKE_PREFIX_PATH=../../install/$OS"
            '-DCMAKE_OSX_ARCHITECTURES="x86_64"'
            "-DCMAKE_INSTALL_PREFIX=../../install/$OS"
            "-DOPENPGL_ARM=OFF"
            $rpath
        )

        build "openpgl" @(
            "-DTBB_ROOT=../../install/$OS-arm64"
            "-DOPENPGL_TBB_ROOT=../../install/$OS-arm64"
            "-DCMAKE_PREFIX_PATH=../../install/$OS-arm64"
            '-DCMAKE_OSX_ARCHITECTURES="arm64"'
            "-DCMAKE_INSTALL_PREFIX=../../install/$OS-arm64"
            "-DOPENPGL_ARM=ON"
            $rpath
        )
    }
    else
    {
        build "oneTBB" @(
            "-DTBB_TEST=OFF"
            "-DCMAKE_INSTALL_PREFIX=../../install/$OS"
        )

        build "oidn" @(
            "-DTBB_ROOT=../../install/$OS"
            "-DISPC_EXECUTABLE=$ispc"
            "-DISPC_VERSION=$ispcVersion"
            "-DOIDN_APPS=OFF"
            "-DOIDN_ZIP_MODE=ON"
            "-DCMAKE_INSTALL_PREFIX=../../install/$OS"
            "-DOIDN_FILTER_RTLIGHTMAP=OFF"
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

            "-DCMAKE_INSTALL_PREFIX=../../install/$OS"
        )

        build "openpgl" @(
            "-DTBB_ROOT=../../install/$OS"
            "-DOPENPGL_TBB_ROOT=../../install/$OS"
            "-DCMAKE_PREFIX_PATH=../../install/$OS"
            "-DCMAKE_INSTALL_PREFIX=../../install/$OS"
            $rpath
        )
    }

    cd ..

    # Read TBB version numbers from its version.h file so we know the required .so and .dylib names
    $versionContent = Get-Content -path oneTBB/include/oneapi/tbb/version.h -Raw
    $tbbMajorVersion = ([regex]".*#define __TBB_BINARY_VERSION ([0-9]+).*").Match($versionContent).Groups[1].Value
    $tbbMinorVersion = ([regex]".*#define TBB_VERSION_MINOR ([0-9]+).*").Match($versionContent).Groups[1].Value
    $tbbVersion = "$tbbMajorVersion.$tbbMinorVersion"

    echo "TBB Version: $tbbVersion"

    # Delete symlinks because GitHub Actions will replace them by copies of the file
    # We deliberately create a second copy of TBB, because its CMake setup works in mysterious ways.
    if ([environment]::OSVersion::IsLinux())
    {
        find ./install -type l -delete
        cp ./install/linux/lib/libtbb.so.$tbbVersion ./install/linux/lib/libtbb.so.$tbbMajorVersion
    }
    elseif ([environment]::OSVersion::IsMacOS())
    {
        find ./install -type l -delete
        cp "./install/osx/lib/libtbb.$tbbVersion.dylib" "./install/osx/lib/libtbb.$tbbMajorVersion.dylib"
    }

}
finally {
    cd $rootPath
}