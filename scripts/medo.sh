#!/usr/bin/env bash

# Set environment variables jika belum diset
if [ -z "$REPO" ]; then
    echo "Error: REPO environment variable is not set!"
    exit 1
fi

if [ -z "$BRANCH" ]; then
    echo "Error: BRANCH environment variable is not set!"
    exit 1
fi

# Dependencies
rm -rf kernel
git clone "$REPO" -b "$BRANCH" kernel
cd kernel

# Setup KernelSU
curl -LSs "https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh" | bash -s main
make mrproper

# Konfigurasi kernel
echo "CONFIG_LOCAL_VERSION=Chaotic" >> ./arch/arm64/configs/mido_defconfig
echo "# CONFIG_LOCAL_VERSION_AUTO is not set" >> ./arch/arm64/configs/mido_defconfig
echo "CONFIG_LINUX_COMPILE_BY=After" >> ./arch/arm64/configs/mido_defconfig
echo "CONFIG_LINUX_COMPILE_HOST=Midnight" >> ./arch/arm64/configs/mido_defconfig

# Setup Clang dari GitLab
setup_clang() {
    echo "Setting up Clang from GitLab (kei-space/clang/r522817)..."
    
    if [ ! -d "clang" ]; then
        echo "Cloning Kei-Space Clang r522817..."
        
        # Clone clang dari GitLab
        git clone --depth=1 https://gitlab.com/kei-space/clang/r522817.git clang
        
        if [ $? -ne 0 ]; then
            echo "Failed to clone clang repository!"
            exit 1
        fi
        
        # Verifikasi clang
        if [ -f "clang/bin/clang" ]; then
            echo "Clang setup successfully!"
        else
            echo "Searching for clang binary..."
            # Cari binary clang di dalam folder clang
            CLANG_BIN=$(find clang -name "clang" -type f | grep -v ".so" | head -1)
            if [ -n "$CLANG_BIN" ]; then
                echo "Found clang at: $CLANG_BIN"
                # Buat symlink jika perlu
                if [ ! -f "clang/bin/clang" ]; then
                    mkdir -p clang/bin
                    ln -sf "$(realpath "$CLANG_BIN")" clang/bin/clang
                fi
            else
                echo "Error: Could not find clang binary in the repository!"
                exit 1
            fi
        fi
    else
        echo "Clang directory already exists, skipping clone..."
    fi
    
    # Install LLVM tools dan dependencies
    echo "Installing dependencies..."
    sudo apt update
    sudo apt install -y ccache llvm lld binutils-aarch64-linux-gnu binutils-arm-linux-gnueabi
    
    # Setup environment variables
    export PATH="${PWD}/clang/bin:${PATH}"
    export KBUILD_COMPILER_STRING="Kei-Clang-r522817"
    
    echo "Clang setup complete. Version:"
    "${PWD}/clang/bin/clang" --version 2>/dev/null || {
        echo "Trying to find and use available clang binary..."
        # Coba cari clang di PATH atau di folder clang
        FOUND_CLANG=$(which clang 2>/dev/null || find "${PWD}/clang" -name "clang" -type f | head -1)
        if [ -n "$FOUND_CLANG" ] && [ -x "$FOUND_CLANG" ]; then
            "$FOUND_CLANG" --version 2>/dev/null || echo "Could not get clang version"
        else
            echo "Could not get clang version"
        fi
    }
}

# Variabel build
IMAGE=$(pwd)/out/arch/arm64/boot/Image.gz-dtb
DATE=$(date +"%Y%m%d-%H%M")
START=$(date +"%s")
KERNEL_DIR=$(pwd)

# Ccache configuration
export USE_CCACHE=1
export CCACHE_COMPILER_CHECK="%compiler% -dumpversion"
export CCACHE_MAXFILES="0"
export CCACHE_NOHASHDIR="true"
export CCACHE_UMASK="0002"
export CCACHE_COMPRESSION="true"
export CCACHE_COMPRESSION_LEVEL="-3"
export CCACHE_NOINODECACHE="true"
export CCACHE_COMPILERTYPE="auto"
export CCACHE_RUN_SECOND_CPP="true"
export CCACHE_SLOPPINESS="file_macro,time_macros,include_file_mtime,include_file_ctime,file_stat_matches"

# Build environment
export TZ=Asia/Jakarta
ARCH=arm64
export ARCH
KBUILD_BUILD_HOST="Midnight"
export KBUILD_BUILD_HOST
KBUILD_BUILD_USER="After"
export KBUILD_BUILD_USER
DEVICE="Xiaomi Redmi Note 4"
export DEVICE
CODENAME="mido"
export CODENAME
DEFCONFIG="mido_defconfig"
export DEFCONFIG
COMMIT_HASH=$(git rev-parse --short HEAD)
export COMMIT_HASH
PROCS=$(nproc --all)
export PROCS
STATUS=STABLE
export STATUS
LC_ALL=C
export LC_ALL

# Setup ccache jika CACHE=1
if [ "${CACHE:-0}" = "1" ]; then
    ccache -M 100G
    export USE_CCACHE=1
fi

# Compile kernel
compile() {
    echo "Starting kernel compilation..."
    
    if [ -d "out" ]; then
        rm -rf out
    fi
    mkdir -p out
    
    # Buat konfigurasi
    make O=out ARCH="${ARCH}" "${DEFCONFIG}"
    
    # Verifikasi toolchain
    echo "Verifying toolchain..."
    
    # Cari clang di PATH
    if ! command -v clang >/dev/null 2>&1; then
        echo "Clang not found in PATH! Searching in clang directory..."
        # Cari clang di folder clang
        CLANG_PATH=$(find "${PWD}/clang" -name "clang" -type f -executable | head -1)
        if [ -n "$CLANG_PATH" ]; then
            echo "Found clang at: $CLANG_PATH"
            # Tambahkan ke PATH
            export PATH="${PWD}/clang/bin:${PATH}"
            # Buat symlink jika belum ada
            if [ ! -f "clang/bin/clang" ]; then
                mkdir -p clang/bin
                ln -sf "$CLANG_PATH" clang/bin/clang
                ln -sf "$(dirname "$CLANG_PATH")/clang++" clang/bin/clang++ 2>/dev/null || true
            fi
        else
            echo "Error: Clang not found!"
            exit 1
        fi
    fi
    
    command -v ld.lld >/dev/null 2>&1 || { echo "ld.lld not found!"; exit 1; }
    
    # Build kernel dengan LLVM tools
    make -j"${PROCS}" O=out \
         ARCH="$ARCH" \
         CC="clang" \
         CXX="clang++" \
         HOSTCC="clang" \
         HOSTCXX="clang++" \
         AR="llvm-ar" \
         AS="llvm-as" \
         NM="llvm-nm" \
         OBJCOPY="llvm-objcopy" \
         OBJDUMP="llvm-objdump" \
         STRIP="llvm-strip" \
         LD="ld.lld" \
         LLVM=1 \
         LLVM_IAS=1 \
         CROSS_COMPILE="aarch64-linux-gnu-" \
         CROSS_COMPILE_ARM32="arm-linux-gnueabi-"

    # Cek apakah kernel berhasil dibangun
    if [ ! -f "$IMAGE" ]; then
        echo "ERROR: Kernel image was not built successfully!"
        echo "Build log errors:"
        tail -50 out/.config >&2 || true
        exit 1
    fi

    echo "Kernel built successfully!"
    
    # Clone AnyKernel3
    if [ ! -d "AnyKernel" ]; then
        git clone --depth=1 https://github.com/EunoiaMetanoia/AnyKernel3.git AnyKernel -b master
    fi
    
    cp "$IMAGE" AnyKernel/
    echo "Kernel image copied to AnyKernel/"
}

# Zipping kernel
zipping() {
    cd AnyKernel || exit 1
    ZIP_NAME="AfterMidnight-${BRANCH}-${CODENAME}-${DATE}.zip"
    zip -r9 "$ZIP_NAME" ./*
    mkdir -p ../artifacts
    cp "$ZIP_NAME" ../artifacts/
    echo "Kernel zip created at: ../artifacts/$ZIP_NAME"
    cd ..
    
    # Output untuk GitHub Actions
    if [ -n "${GITHUB_ENV+x}" ]; then
        echo "ARTIFACT_PATH=artifacts/$ZIP_NAME" >> "$GITHUB_ENV"
    fi
}

# Main execution
setup_clang
compile
zipping

END=$(date +"%s")
DIFF=$((END - START))
echo "Build completed in $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)."

# Output artifact paths for GitHub Actions
if [ -n "${GITHUB_ENV+x}" ]; then
    echo "ARTIFACT_PATH=${KERNEL_DIR}/artifacts" >> "$GITHUB_ENV"
    echo "ZIP_NAME=$(ls ${KERNEL_DIR}/artifacts/*.zip 2>/dev/null || echo 'not found')" >> "$GITHUB_ENV"
    echo "BUILD_LOG=${KERNEL_DIR}/artifacts/build.log" >> "$GITHUB_ENV"
fi

echo "Artifacts have been prepared for upload directly from AnyKernel."
