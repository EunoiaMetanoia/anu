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
echo "# CONFIG_KPM is not set" >> ./arch/arm64/configs/mido_defconfig
echo "CONFIG_KALLSYMS=y" >> ./arch/arm64/configs/mido_defconfig
echo "CONFIG_KALLSYMS_ALL=y" >> ./arch/arm64/configs/mido_defconfig
echo "CONFIG_LOCAL_VERSION=Black-RX" >> ./arch/arm64/configs/mido_defconfig
echo "# CONFIG_LOCAL_VERSION_AUTO is not set" >> ./arch/arm64/configs/mido_defconfig
echo "CONFIG_LINUX_COMPILE_BY=After" >> ./arch/arm64/configs/mido_defconfig
echo "CONFIG_LINUX_COMPILE_HOST=Midnight" >> ./arch/arm64/configs/mido_defconfig
echo "Adding CONFIG_KSU.."
echo "CONFIG_KSU=y" >> ./arch/arm64/configs/mido_defconfig
echo "CONFIG_KSU_MANUAL_HOOK=y" >> ./arch/arm64/configs/mido_defconfig

# Setup Clang dari Google AOSP
setup_clang() {
    echo "Setting up Clang from Google AOSP..."
    
    if [ ! -d "clang" ]; then
        mkdir -p clang
        echo "Downloading AOSP Clang r536225..."
        
        # Download clang dari Google AOSP
        wget -q --show-progress "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/192fe0d378bb9cd4d4271de3e87145a1956fef40/clang-r536225.tar.gz" -O clang.tar.gz
        
        if [ $? -ne 0 ]; then
            echo "Failed to download clang. Trying with curl..."
            curl -L "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/192fe0d378bb9cd4d4271de3e87145a1956fef40/clang-r536225.tar.gz" -o clang.tar.gz
        fi
        
        if [ -f "clang.tar.gz" ]; then
            echo "Extracting clang..."
            tar -xzf clang.tar.gz -C clang
            rm -f clang.tar.gz
            
            # Verifikasi clang
            if [ -f "clang/bin/clang" ]; then
                echo "Clang extracted successfully!"
            else
                echo "Warning: Clang binary not found in expected location."
                echo "Searching for clang binary..."
                find clang -name "clang" -type f | head -5
            fi
        else
            echo "Error: Failed to download clang archive!"
            exit 1
        fi
    fi
    
    # Install LLVM tools dan dependencies
    echo "Installing dependencies..."
    sudo apt update
    sudo apt install -y ccache llvm lld binutils-aarch64-linux-gnu binutils-arm-linux-gnueabi
    
    # Setup environment variables
    export PATH="${PWD}/clang/bin:${PATH}"
    export KBUILD_COMPILER_STRING="AOSP-Clang-r536225"
    
    echo "Clang setup complete. Version:"
    "${PWD}/clang/bin/clang" --version 2>/dev/null || echo "Could not get clang version"
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
    command -v clang >/dev/null 2>&1 || { echo "Clang not found in PATH!"; exit 1; }
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
