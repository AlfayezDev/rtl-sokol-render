#!/bin/bash
set -e

OS=$(uname -s)
EMCC=$(command -v emcc 2>/dev/null)

declare -a libs=("log" "app" "gfx" "glue" "time" "audio" "debugtext" "shape" "gl")

# Linux functions
build_linux_static_release() {
    src=$1
    dst=$2
    backend=$3
    libs_extra=$4
    echo "Building $dst (Linux static release)"
    cc -c -O3 -DNDEBUG -DIMPL -D$backend c/$src.c
    ar rcs $dst.a $src.o
}

build_linux_static_debug() {
    src=$1
    dst=$2
    backend=$3
    libs_extra=$4
    echo "Building $dst (Linux static debug)"
    cc -c -g -DIMPL -D$backend c/$src.c
    ar rcs $dst.a $src.o
}

build_linux_shared_release() {
    src=$1
    dst=$2
    backend=$3
    libs_extra=$4
    echo "Building $dst (Linux shared release)"
    cc -pthread -shared -O3 -fPIC -DNDEBUG -DIMPL -D$backend -o $dst.so c/$src.c $libs_extra
}

build_linux_shared_debug() {
    src=$1
    dst=$2
    backend=$3
    libs_extra=$4
    echo "Building $dst (Linux shared debug)"
    cc -pthread -shared -g -fPIC -DIMPL -D$backend -o $dst.so c/$src.c $libs_extra
}

# macOS functions
FRAMEWORKS_METAL="-framework Metal -framework MetalKit"
FRAMEWORKS_OPENGL="-framework OpenGL"
FRAMEWORKS_CORE="-framework Foundation -framework CoreGraphics -framework Cocoa -framework QuartzCore -framework CoreAudio -framework AudioToolbox"

build_macos_static_release() {
    src=$1
    dst=$2
    backend=$3
    arch=$4
    echo "Building $dst (macOS static release)"
    MACOSX_DEPLOYMENT_TARGET=10.13 clang -c -O3 -x objective-c -arch $arch -DNDEBUG -DIMPL -D$backend c/$src.c
    ar rcs $dst.a $src.o
}

build_macos_static_debug() {
    src=$1
    dst=$2
    backend=$3
    arch=$4
    echo "Building $dst (macOS static debug)"
    MACOSX_DEPLOYMENT_TARGET=10.13 clang -c -g -x objective-c -arch $arch -DIMPL -D$backend c/$src.c
    ar rcs $dst.a $src.o
}

# Combined shared for macOS (since per-lib shared has dependencies)
build_macos_combined_shared_release() {
    backend=$1
    arch=$2
    frameworks=""
    if [ "$backend" = "SOKOL_METAL" ]; then
        frameworks="$FRAMEWORKS_METAL"
    else
        frameworks="$FRAMEWORKS_OPENGL"
    fi
    dst="dylib/sokol_dylib_macos_${arch}_${backend#SOKOL_}_release"
    echo "Building $dst (macOS combined shared release)"
    MACOSX_DEPLOYMENT_TARGET=10.13 clang -c -O3 -x objective-c -arch $arch -DNDEBUG -DIMPL -D$backend c/sokol.c
    clang -dynamiclib -arch $arch $FRAMEWORKS_CORE $frameworks -o $dst.dylib sokol.o
}

build_macos_combined_shared_debug() {
    backend=$1
    arch=$2
    frameworks=""
    if [ "$backend" = "SOKOL_METAL" ]; then
        frameworks="$FRAMEWORKS_METAL"
    else
        frameworks="$FRAMEWORKS_OPENGL"
    fi
    dst="dylib/sokol_dylib_macos_${arch}_${backend#SOKOL_}_debug"
    echo "Building $dst (macOS combined shared debug)"
    MACOSX_DEPLOYMENT_TARGET=10.13 clang -c -g -x objective-c -arch $arch -DIMPL -D$backend c/sokol.c
    clang -dynamiclib -arch $arch $FRAMEWORKS_CORE $frameworks -o $dst.dylib sokol.o
}

# WASM functions (static only)
build_wasm_static_release() {
    src=$1
    dst=$2
    backend=$3
    echo "Building $dst (WASM static release)"
    emcc -c -O3 -DNDEBUG -DIMPL -D$backend c/$src.c
    emar rcs $dst.a $src.o
    rm $src.o
}

build_wasm_static_debug() {
    src=$1
    dst=$2
    backend=$3
    echo "Building $dst (WASM static debug)"
    emcc -c -g -DIMPL -D$backend c/$src.c
    emar rcs $dst.a $src.o
    rm $src.o
}

# Main build logic
case $OS in
    Linux)
        echo "Building for Linux..."
        for lib in "${libs[@]}"; do
            src="sokol_$lib"
            dst="$lib/sokol_${lib}_linux_x64_gl"
            build_linux_static_release $src "${dst}_release" SOKOL_GLCORE
            build_linux_static_debug $src "${dst}_debug" SOKOL_GLCORE
            build_linux_shared_release $src "${dst}_release" SOKOL_GLCORE
            build_linux_shared_debug $src "${dst}_debug" SOKOL_GLCORE
        done
        # Special for audio with -lasound
        lib="audio"
        src="sokol_$lib"
        dst="$lib/sokol_${lib}_linux_x64_gl"
        build_linux_static_release $src "${dst}_release" SOKOL_GLCORE "-lasound"
        build_linux_static_debug $src "${dst}_debug" SOKOL_GLCORE "-lasound"
        build_linux_shared_release $src "${dst}_release" SOKOL_GLCORE "-lasound"
        build_linux_shared_debug $src "${dst}_debug" SOKOL_GLCORE "-lasound"
        rm *.o
        ;;
    Darwin)
        echo "Building for macOS..."
        mkdir -p dylib
        for lib in "${libs[@]}"; do
            src="sokol_$lib"
            for backend in SOKOL_METAL SOKOL_GLCORE; do
                for arch in arm64 x86_64; do
                    dst="$lib/sokol_${lib}_macos_${arch}_${backend#SOKOL_}"
                    dst_lower=$(echo $dst | tr '[:upper:]' '[:lower:]')
                    build_macos_static_release $src "${dst_lower}_release" $backend $arch
                    build_macos_static_debug $src "${dst_lower}_debug" $backend $arch
                done
            done
        done
        # Combined shared libs
        for backend in SOKOL_METAL SOKOL_GLCORE; do
            for arch in arm64 x86_64; do
                build_macos_combined_shared_release $backend $arch
                build_macos_combined_shared_debug $backend $arch
            done
        done
        rm *.o
        ;;
    *)
        if [ -n "$EMCC" ]; then
            echo "Building for WASM..."
            for lib in "${libs[@]}"; do
                src="sokol_$lib"
                dst="$lib/sokol_${lib}_wasm_gl"
                build_wasm_static_release $src "${dst}_release" SOKOL_GLES3
                build_wasm_static_debug $src "${dst}_debug" SOKOL_GLES3
            done
            rm *.o
        else
            echo "Unsupported platform or emcc not found"
            exit 1
        fi
        ;;
esac

echo "Build complete"