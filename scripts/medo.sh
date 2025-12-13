#!/usr/bin/env bash
# Dependencies
rm -rf kernel
git clone $REPO -b $BRANCH kernel
cd kernel || exit 1
git clone --depth=1 https://github.com/malkist01/patch
curl -LSs "https://raw.githubusercontent.com/malkist01/patch/main/add/patch.sh" | bash -s main
curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s next
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
echo "CONFIG_KSUSFS=y" >> ./arch/arm64/configs/mido_defconfig

clang() {
    echo "Cloning clang"
    if [ ! -d "clang" ]; then
      mkdir -p "clang"
      curl -Lo WeebX-Clang-20.0.0git.tar.gz "https://github.com/XSans0/WeebX-Clang/releases/download/WeebX-Clang-20.0.0git-release/WeebX-Clang-20.0.0git.tar.gz"
      tar -zxf WeebX-Clang-20.0.0git.tar.gz -C "clang" --strip-components=1
        KBUILD_COMPILER_STRING="WeebX-Clang"
        PATH="${PWD}/clang/bin:${PATH}"
    fi
    sudo apt-get install -y ccache
    echo "Done"
}

IMAGE=$(pwd)/out/arch/arm64/boot/Image.gz-dtb
DATE=$(date +"%Y%m%d-%H%M")
START=$(date +"%s")
KERNEL_DIR=$(pwd)

# Ccache setup
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
export TZ=Asia/Jakarta
export KBUILD_COMPILER_STRING

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

# Setup ccache if enabled
if [ "$CACHE" = 1 ]; then
    ccache -M 100G
    export USE_CCACHE=1
fi

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
    if [ -d "out" ]; then
        rm -rf out
    fi
    mkdir -p out
    
    echo "Starting compilation with config: ${DEFCONFIG}"
    make O=out ARCH="${ARCH}" "${DEFCONFIG}" || error_exit "defconfig"
    
    echo "Building kernel with ${PROCS} threads..."
    make -j"${PROCS}" O=out \
         ARCH=$ARCH \
         CC="clang" \
         CXX="clang++" \
         HOSTCC="clang" \
         HOSTCXX="clang++" \
         AR=llvm-ar \
         AS=llvm-as \
         NM=llvm-nm \
         OBJCOPY=llvm-objcopy \
         OBJDUMP=llvm-objdump \
         STRIP=llvm-strip \
         LLVM=1 \
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
    zip -r9 "${ZIP_NAME}" ./* || error_exit "zip creation"
    
    # Copy ZIP back to kernel directory for artifact upload
    cp "${ZIP_NAME}" "${KERNEL_DIR}/" || error_exit "copy zip"
    
    cd "${KERNEL_DIR}" || exit 1
}

# Main execution
clang || error_exit "clang setup"
show_build_info
compile || error_exit "compile function"
zipping || error_exit "zipping function"

END=$(date +"%s")
DIFF=$((END - START))
echo "Build completed in $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)."
echo "Kernel ZIP file is ready at: ${KERNEL_DIR}/AnyKernel/*.zip"

# Keep the ZIP file accessible in the workspace root for GitHub Actions artifact upload
mkdir -p "${KERNEL_DIR}/../artifacts"
cp "${KERNEL_DIR}/AnyKernel"/*.zip "${KERNEL_DIR}/../artifacts/" 2>/dev/null || echo "No ZIP file found to copy to artifacts directory"
cp "$IMAGE" "${KERNEL_DIR}/../artifacts/" 2>/dev/null || echo "No Image.gz-dtb found to copy to artifacts directory"

echo "Artifacts have been prepared for upload."
