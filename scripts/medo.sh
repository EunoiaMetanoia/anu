#!/usr/bin/env bash
set -e

# Dependencies
rm -rf kernel
git clone $REPO -b $BRANCH kernel
cd kernel || exit 1
git clone --depth=1 https://github.com/malkist01/patch  
curl -LSs "https://raw.githubusercontent.com/malkist01/patch/main/add/patch.sh " | bash -s main
curl -LSs "https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh " | bash -s -- v3.0.0-20-legacy
make mrproper
echo "# CONFIG_KPM is not set" >> ./arch/arm64/configs/mido_defconfig
echo "CONFIG_KALLSYMS=y" >> ./arch/arm64/configs/mido_defconfig
echo "CONFIG_KALLSYMS_ALL=y" >> ./arch/arm64/configs/mido_defconfig
echo "CONFIG_LOCAL_VERSION=-AfterMidniht" >> ./arch/arm64/configs/mido_defconfig
echo "# CONFIG_LOCAL_VERSION_AUTO is not set" >> ./arch/arm64/configs/mido_defconfig
echo "CONFIG_LINUX_COMPILE_BY=After" >> ./arch/arm64/configs/mido_defconfig
echo "CONFIG_LINUX_COMPILE_HOST=Midnight" >> ./arch/arm64/configs/mido_defconfig
echo "Adding CONFIG_KSU.."
echo "CONFIG_KSU=y" >> ./arch/arm64/configs/mido_defconfig

clang() {
    echo "Setting up Google Clang"
    if [ ! -d "clang" ]; then
        mkdir -p clang
        echo "Downloading Google Clang..."
        curl -Lo google_clang.tar.gz "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/192fe0d378bb9cd4d4271de3e87145a1956fef40.tar.gz"
        echo "Extracting Google Clang..."
        tar -zxf google_clang.tar.gz -C clang
        
        # Find the clang binary path
        CLANG_BINARY=$(find clang -name "clang" -type f | grep -v "/lib/" | head -n1)
        if [ -z "$CLANG_BINARY" ]; then
            echo "ERROR: Could not find clang binary in extracted archive"
            exit 1
        fi
        
        # Get directory containing clang binary
        CLANG_DIR=$(dirname "$CLANG_BINARY")
        export PATH="$CLANG_DIR:$PATH"
        
        # Create symlinks for LLVM tools if needed
        LLVM_TOOLS_DIR=$(dirname "$CLANG_DIR")
        for tool in ar nm objcopy objdump strip; do
            LLVM_TOOL="llvm-$tool"
            if [ ! -f "$CLANG_DIR/$LLVM_TOOL" ]; then
                LLVM_TOOL_PATH=$(find "$LLVM_TOOLS_DIR" -name "$LLVM_TOOL" -type f | head -n1)
                if [ -n "$LLVM_TOOL_PATH" ]; then
                    ln -s "$LLVM_TOOL_PATH" "$CLANG_DIR/$LLVM_TOOL"
                fi
            fi
        done
        
        CLANG_VERSION=$("$CLANG_BINARY" --version | head -n1)
        KBUILD_COMPILER_STRING="$CLANG_VERSION"
        echo "Clang version: $CLANG_VERSION"
    else
        echo "Using existing Google Clang setup"
    fi
    
    # Install ccache and cross-compilers
    sudo apt-get update
    sudo apt-get install -y ccache g++-aarch64-linux-gnu gcc-aarch64-linux-gnu g++-arm-linux-gnueabi gcc-arm-linux-gnueabi
    echo "Done setting up Google Clang"
}

IMAGE=$(pwd)/out/arch/arm64/boot/Image.gz-dtb
DATE=$(date +"%Y%m%d-%H%M")
START=$(date +"%s")
KERNEL_DIR=$(pwd)

# Ccache setup
export USE_CCACHE=1
export CCACHE_DIR="${HOME}/.ccache"
ccache -M 100G
export CCACHE_COMPRESS=1
export CCACHE_COMPRESSLEVEL=6

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

# Error handling function
error_exit() {
    echo "ERROR: Build failed at step: $1"
    exit 1
}

# Display build info locally
show_build_info() {
    echo "
╔═════════════════════════════════════════════╗
║          KERNEL BUILD INFORMATION           ║
╠═════════════════════════════════════════════╣
║ Building on: Github Actions                 ║
║ Date: $DATE                                ║
║ Device: ${DEVICE} (${CODENAME})            ║
║ Branch: $(git rev-parse --abbrev-ref HEAD) ║
║ Last Commit: ${COMMIT_HASH}                ║
║ Repository: ${REPO}                        ║
║ Compiler: ${KBUILD_COMPILER_STRING}        ║
║ Build Status: ${STATUS}                    ║
╚═════════════════════════════════════════════╝"
}

# Compile kernel
compile() {
    mkdir -p out
    
    echo "Starting compilation with config: ${DEFCONFIG}"
    make O=out ARCH="${ARCH}" "${DEFCONFIG}" || error_exit "defconfig"
    
    echo "Building kernel with ${PROCS} threads..."
    make -j"${PROCS}" O=out \
         ARCH=$ARCH \
         CC=clang \
         CXX=clang++ \
         HOSTCC=clang \
         HOSTCXX=clang++ \
         AR=llvm-ar \
         NM=llvm-nm \
         OBJCOPY=llvm-objcopy \
         OBJDUMP=llvm-objdump \
         STRIP=llvm-strip \
         LLVM=1 \
         LLVM_IAS=1 \
         CROSS_COMPILE=aarch64-linux-gnu- \
         CROSS_COMPILE_ARM32=arm-linux-gnueabi- || error_exit "compilation"
    
    if ! [ -f "$IMAGE" ]; then
        echo "ERROR: Kernel image not found at $IMAGE"
        error_exit "image not found"
    fi
    
    echo "Kernel image built successfully at $IMAGE"
    
    git clone --depth=1 https://github.com/EunoiaMetanoia/AnyKernel3.git AnyKernel -b master || error_exit "anykernel clone"
    cp "$IMAGE" AnyKernel/ || error_exit "copy image"
}

# Create zip package
zipping() {
    cd AnyKernel || error_exit "enter AnyKernel directory"
    
    ZIP_NAME="AfterMidnight-${BRANCH}-${CODENAME}-${DATE}.zip"
    echo "Creating flashable ZIP: ${ZIP_NAME}"
    zip -r9 "${ZIP_NAME}" ./* -x ".git*" "README.md" "LICENSE" || error_exit "zip creation"
    
    # Move ZIP directly to artifacts directory for GitHub Actions
    mkdir -p "${KERNEL_DIR}/artifacts"
    mv "${ZIP_NAME}" "${KERNEL_DIR}/artifacts/" || error_exit "move zip to artifacts"
    
    cd "${KERNEL_DIR}" || exit 1
    
    # Move the kernel image to artifacts as well
    mkdir -p "${KERNEL_DIR}/artifacts"
    cp "$IMAGE" "${KERNEL_DIR}/artifacts/" || error_exit "copy image to artifacts"
}

# Main execution
clang || error_exit "clang setup"
show_build_info
compile || error_exit "compile function"
zipping || error_exit "zipping function"

END=$(date +"%s")
DIFF=$((END - START))
echo "Build completed in $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)."
echo "Kernel ZIP file is ready at: ${KERNEL_DIR}/artifacts/*.zip"

# Output artifact paths for GitHub Actions
if [ -n "${GITHUB_ENV+x}" ]; then
    echo "ARTIFACT_PATH=${KERNEL_DIR}/artifacts" >> $GITHUB_ENV
    echo "ZIP_NAME=$(ls ${KERNEL_DIR}/artifacts/*.zip)" >> $GITHUB_ENV
    echo "IMAGE_NAME=$(ls ${KERNEL_DIR}/artifacts/Image.gz-dtb)" >> $GITHUB_ENV
fi

echo "Artifacts have been prepared for upload directly from AnyKernel."
