#!/usr/bin/env bash
set -e

# Dependencies
rm -rf kernel
git clone $REPO -b $BRANCH kernel
cd kernel || exit 1
curl -LSs "https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh" | bash -s -- v3.0.0-20-legacy
make mrproper
echo "# CONFIG_KPM is not set" >> ./arch/arm64/configs/mido_defconfig
echo "CONFIG_KALLSYMS=y" >> ./arch/arm64/configs/mido_defconfig
echo "CONFIG_KALLSYMS_ALL=y" >> ./arch/arm64/configs/mido_defconfig
echo "CONFIG_LOCAL_VERSION=-AfterMidniht" >> ./arch/arm64/configs/mido_defconfig
echo "# CONFIG_LOCAL_VERSION_AUTO is not set" >> ./arch/arm64/configs/mido_defconfig
echo "CONFIG_LINUX_COMPILE_BY=After" >> ./arch/arm64/configs/mido_defconfig
echo "CONFIG_LINUX_COMPILE_HOST=Midnight" >> ./arch/arm64/configs/mido_defconfig
echo "# CONFIG_CC_STACKPROTECTOR_STRONG is not set" >> ./arch/arm64/configs/mido_defconfig
echo "Adding CONFIG_KSU.."
echo "CONFIG_KSU=y" >> ./arch/arm64/configs/mido_defconfig
echo "CONFIG_KSU_SUSFS=y" >> ./arch/arm64/configs/mido_defconfig

clang() {
    echo "Setting up Kei-Space Clang (r536225)"
    if [ ! -d "clang" ]; then
        echo "Cloning Kei-Space Clang repository..."
        git clone --depth=1 https://gitlab.com/kei-space/clang/r536225.git clang || {
            echo "ERROR: Failed to clone Kei-Space Clang repository"
            exit 1
        }
        
        # Verify the repository was cloned correctly
        if [ ! -d "clang/bin" ]; then
            echo "ERROR: Cloned repository doesn't contain expected bin directory structure"
            exit 1
        fi
        
        # Set up paths
        CLANG_DIR=$(pwd)/clang/bin
        export PATH="$CLANG_DIR:$PATH"
        
        # Get clang version for display
        CLANG_BINARY="$CLANG_DIR/clang"
        if [ -f "$CLANG_BINARY" ]; then
            CLANG_VERSION=$("$CLANG_BINARY" --version | head -n1)
            KBUILD_COMPILER_STRING="$CLANG_VERSION"
            echo "Clang version: $CLANG_VERSION"
        else
            echo "ERROR: Could not find clang binary in cloned repository"
            exit 1
        fi
        
        echo "Setting up LLVM tool symlinks..."
        # Create symlinks for essential LLVM tools if they don't exist
        for tool in ar nm objcopy objdump strip; do
            LLVM_TOOL="llvm-$tool"
            if [ ! -f "$CLANG_DIR/$LLVM_TOOL" ]; then
                echo "Creating symlink for $LLVM_TOOL"
                # Check if tool exists in the repository
                if [ -f "$CLANG_DIR/$tool" ]; then
                    ln -sf "$CLANG_DIR/$tool" "$CLANG_DIR/$LLVM_TOOL"
                else
                    echo "WARNING: Could not find $tool in clang repository"
                fi
            fi
        done
    else
        echo "Using existing Kei-Space Clang setup"
        CLANG_DIR=$(pwd)/clang/bin
        export PATH="$CLANG_DIR:$PATH"
        CLANG_BINARY="$CLANG_DIR/clang"
        if [ -f "$CLANG_BINARY" ]; then
            CLANG_VERSION=$("$CLANG_BINARY" --version | head -n1)
            KBUILD_COMPILER_STRING="$CLANG_VERSION"
        else
            echo "ERROR: Existing clang setup is invalid"
            exit 1
        fi
    fi
    
    # Install ccache and cross-compilers with proper non-interactive mode
    echo "Installing ccache and cross-compilers..."
    DEBIAN_FRONTEND=noninteractive sudo apt-get update -q
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -y -q ccache g++-aarch64-linux-gnu gcc-aarch64-linux-gnu g++-arm-linux-gnueabi gcc-arm-linux-gnueabi || {
        echo "WARNING: Failed to install packages using sudo. Trying without sudo..."
        DEBIAN_FRONTEND=noninteractive apt-get update -q
        DEBIAN_FRONTEND=noninteractive apt-get install -y -q ccache g++-aarch64-linux-gnu gcc-aarch64-linux-gnu g++-arm-linux-gnueabi gcc-arm-linux-gnueabi || {
            echo "ERROR: Failed to install required packages"
            exit 1
        }
    }
    
    # Setup ccache after installation
    echo "Setting up ccache..."
    export USE_CCACHE=1
    export CCACHE_DIR="${HOME}/.ccache"
    mkdir -p "${CCACHE_DIR}"
    ccache -M 100G || {
        echo "WARNING: Failed to set ccache size initially. Trying again..."
        ccache -M 100G || {
            echo "ERROR: Failed to initialize ccache after multiple attempts"
            exit 1
        }
    }
    export CCACHE_COMPRESS=1
    export CCACHE_COMPRESSLEVEL=6
    
    echo "Verifying toolchain availability..."
    for tool in clang clang++ llvm-ar llvm-nm llvm-objcopy llvm-objdump llvm-strip aarch64-linux-gnu-gcc arm-linux-gnueabi-gcc; do
        if ! command -v "$tool" &> /dev/null; then
            echo "WARNING: $tool not found in PATH"
        else
            echo "✓ $tool found"
        fi
    done
    
    echo "Done setting up Kei-Space Clang"
}

IMAGE=$(pwd)/out/arch/arm64/boot/Image.gz-dtb
DATE=$(date +"%Y%m%d-%H%M")
START=$(date +"%s")
KERNEL_DIR=$(pwd)

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
    
    # Verify the config was generated correctly
    if [ ! -f "out/.config" ]; then
        echo "ERROR: Kernel config was not generated properly"
        error_exit "config generation"
    fi
    
    echo "Verifying CONFIG_KSU is enabled in the config..."
    if ! grep -q "CONFIG_KSU=y" out/.config; then
        echo "ERROR: CONFIG_KSU is not enabled in the kernel config"
        error_exit "ksu config"
    fi
    
    echo "Building kernel with ${PROCS} threads..."
    
    # Use pipefail to catch errors in piped commands
    set -o pipefail
    
    # Build with verbose output to catch errors
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
         CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
         2>&1 | tee build.log || {
            echo "ERROR: Kernel compilation failed. Check build.log for details."
            # Show last 50 lines of the build log for immediate debugging
            echo "Last 50 lines of build.log:"
            tail -n 50 build.log
            error_exit "compilation"
         }
    
    if [ ! -f "$IMAGE" ]; then
        echo "ERROR: Kernel image not found at $IMAGE"
        echo "Checking for possible image locations..."
        find out -name "Image*" -type f -ls
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
    
    # Copy build log to artifacts for debugging
    if [ -f build.log ]; then
        cp build.log "${KERNEL_DIR}/artifacts/"
    fi
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
    echo "ZIP_NAME=$(ls ${KERNEL_DIR}/artifacts/*.zip 2>/dev/null || echo 'not found')" >> $GITHUB_ENV
    echo "IMAGE_NAME=$(ls ${KERNEL_DIR}/artifacts/Image.gz-dtb 2>/dev/null || echo 'not found')" >> $GITHUB_ENV
    echo "BUILD_LOG=${KERNEL_DIR}/artifacts/build.log" >> $GITHUB_ENV
fi

echo "Artifacts have been prepared for upload directly from AnyKernel."
