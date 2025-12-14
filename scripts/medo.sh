#!/usr/bin/env bash
# Dependencies
rm -rf kernel
git clone $REPO -b $BRANCH kernel
cd kernel
curl -LSs curl -LSs "https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh" | bash -s v3.0.0-20-legacy
make mrproper
echo "# CONFIG_CC_STACKPROTECTOR_STRONG is not set" >> ./arch/arm64/configs/mido_defconfig
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

clang() {
    echo "Cloning clang"
    if [ ! -d "clang" ]; then
      mkdir -p "clang"
      curl -Lo WeebX-Clang-20.0.0git.tar.gz "https://github.com/XSans0/WeebX-Clang/releases/download/WeebX-Clang-20.0.0git-release/WeebX-Clang-20.0.0git.tar.gz "
      tar -zxf WeebX-Clang-20.0.0git.tar.gz -C "clang" --strip-components=1
        KBUILD_COMPILER_STRING="WeebX-Clang"
        PATH="${PWD}/clang/bin:${PATH}"
    fi
    sudo apt install -y ccache
    echo "Done"
}

IMAGE=$(pwd)/out/arch/arm64/boot/Image.gz-dtb
DATE=$(date +"%Y%m%d-%H%M")
START=$(date +"%s")
KERNEL_DIR=$(pwd)
#Ccache
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
source "${HOME}"/.bashrc && source "${HOME}"/.profile
if [ $CACHE = 1 ]; then
    ccache -M 100G
    export USE_CCACHE=1
fi
LC_ALL=C
export LC_ALL

# Compile
compile() {
    if [ -d "out" ]; then
        rm -rf out && mkdir -p out
    fi

    make O=out ARCH="${ARCH}" "${DEFCONFIG}"
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
        CROSS_COMPILE_ARM32=arm-linux-gnueabi-

    if ! [ -a "$IMAGE" ]; then
        echo "ERROR: Kernel image was not built successfully!"
        exit 1
    fi

    git clone --depth=1 https://github.com/EunoiaMetanoia/AnyKernel3.git AnyKernel -b master
    cp out/arch/arm64/boot/Image.gz-dtb AnyKernel
}

# Zipping
zipping() {
    cd AnyKernel || exit 1
    ZIP_NAME="AfterMidnight-${BRANCH}-${CODENAME}-${DATE}.zip"
    zip -r9 "$ZIP_NAME" ./*
    # Copy the zip to a location that can be easily accessed by GitHub Actions
    mkdir -p ../artifacts
    cp "$ZIP_NAME" ../artifacts/
    echo "Kernel zip created at: ../artifacts/$ZIP_NAME"
    cd ..
    # Output the path for GitHub Actions to use
    echo "ARTIFACT_PATH=artifacts/$ZIP_NAME" >> $GITHUB_ENV
}

clang
compile
zipping
END=$(date +"%s")
DIFF=$((END - START))
echo "Build completed in $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)."

# Output artifact paths for GitHub Actions
if [ -n "${GITHUB_ENV+x}" ]; then
    echo "ARTIFACT_PATH=${KERNEL_DIR}/artifacts" >> $GITHUB_ENV
    echo "ZIP_NAME=$(ls ${KERNEL_DIR}/artifacts/*.zip 2>/dev/null || echo 'not found')" >> $GITHUB_ENV
    echo "BUILD_LOG=${KERNEL_DIR}/artifacts/build.log" >> $GITHUB_ENV
fi

echo "Artifacts have been prepared for upload directly from AnyKernel."
