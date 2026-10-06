#!/bin/bash
set -euo pipefail
set -x

# ========================================
# REPO & KERNEL PATHS
# ========================================
export WDIR="$(pwd)"
export KERNEL_DIR="kernel-5.10"
export DIST_DIR="${WDIR}/dist"
export DEFCONFIG="a24_defconfig"
export KCFLAGS="-Wno-error"
export EXTRA_CFLAGS="-Wno-error"

mkdir -p "${DIST_DIR}"

# ========================================
# TELEGRAM CONFIG
# ========================================
# *

# ========================================
# BUILD VERSION
# ========================================
export BUILD_KERNEL_VERSION="${BUILD_KERNEL_VERSION:-Tanjiro-DEV}"

# ========================================
# INIT SUBMODULES
# ========================================
git clone --depth=1 https://github.com/KernelSU-Next/KernelSU-Next.git KernelSU-Next

# ========================================
# INSTALL REQUIREMENTS
# ========================================
if [ ! -f ".requirements" ]; then
    echo -e "\n[INFO]: INSTALLING REQUIREMENTS..!\n"
    sudo apt update
    sudo apt install -y rsync python3 curl tar bc bison build-essential \
        ccache clang flex gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi \
        libelf-dev libssl-dev lld llvm make zip unzip
    touch .requirements
fi

# ========================================
# INIT TOOLCHAIN (Samsung NDK)
# ========================================
if [[ ! -d "${WDIR}/kernel/prebuilts" || ! -d "${WDIR}/prebuilts" ]]; then
    echo -e "\n[INFO] Cloning Samsung's NDK...\n"
    curl -LO "https://github.com/ravindu644/android_kernel_a165f/releases/download/toolchain/toolchain.tar.gz"
    tar -xf toolchain.tar.gz
    rm toolchain.tar.gz
fi

# ========================================
# LOCALVERSION
# ========================================
mkdir -p "${WDIR}/custom_defconfigs"
echo -e "CONFIG_LOCALVERSION_AUTO=n\nCONFIG_LOCALVERSION=\"-KKRT-${BUILD_KERNEL_VERSION}\"\n" > "${WDIR}/custom_defconfigs/version_defconfig"

# ========================================
# OEM BUILD VARIABLES
# ========================================
export ARCH=arm64
export PLATFORM_VERSION=13
export CROSS_COMPILE="aarch64-linux-gnu-"
export CROSS_COMPILE_COMPAT="arm-linux-gnueabi-"
export OUT_DIR="../out/target/product/a24/obj/KERNEL_OBJ"
export DIST_DIR="../out/target/product/a24/obj/KERNEL_OBJ"
export BUILD_CONFIG="../out/target/product/a24/obj/KERNEL_OBJ/build.config"
export MERGE_CONFIG="${WDIR}/kernel-5.10/scripts/kconfig/merge_config.sh"

# ========================================
# FAILSAFE BUILD CONFIG
# ========================================
mkdir -p "${WDIR}/out/target/product/a24/obj/KERNEL_OBJ"
if [ ! -f "${WDIR}/out/target/product/a24/obj/KERNEL_OBJ/build.config" ]; then
    echo "Creating dummy build.config..."
    cat > "${WDIR}/out/target/product/a24/obj/KERNEL_OBJ/build.config" <<EOF
DEFCONFIG=a24_defconfig
ARCH=arm64
CROSS_COMPILE=aarch64-linux-gnu-
EOF
fi

# Build options
export GKI_KERNEL_BUILD_OPTIONS="
    SKIP_MRPROPER=1 \
    KMI_SYMBOL_LIST_STRICT_MODE=0 \
    SKIP_ABI_CHECKS=1 \
    ABI_DEFINITION= \
    BUILD_BOOT_IMG=1 \
    MKBOOTIMG_PATH=${WDIR}/mkbootimg/mkbootimg.py \
    KERNEL_BINARY=Image.gz \
    BOOT_IMAGE_HEADER_VERSION=4 \
    SKIP_VENDOR_BOOT=1 \
    AVB_SIGN_BOOT_IMG=1 \
    AVB_BOOT_PARTITION_SIZE=67108864 \
    AVB_BOOT_KEY=${WDIR}/mkbootimg/tests/data/testkey_rsa2048.pem \
    AVB_BOOT_ALGORITHM=SHA256_RSA2048 \
    AVB_BOOT_PARTITION_NAME=boot \
    GKI_RAMDISK_PREBUILT_BINARY=${WDIR}/oem_prebuilt_images/gki-ramdisk.lz4 \
    LTO=thin \
"

export MKBOOTIMG_EXTRA_ARGS="
    --os_version 12.0.0 \
    --os_patch_level 2025-05-00 \
    --pagesize 4096 \
"
export GKI_RAMDISK_PREBUILT_BINARY="${WDIR}/oem_prebuilt_images/gki-ramdisk.lz4"

# Menuconfig flag
export MAKE_MENUCONFIG=0
if [ "$MAKE_MENUCONFIG" = "1" ]; then
    export HERMETIC_TOOLCHAIN=0
fi


# ========================================
# FIX SAMSUNG HARDCODED ABI PATH
# ========================================
sudo mkdir -p /home/dpi/qb5_8814/workspace/P4_1716/android/out/target/product/a24/obj/KERNEL_OBJ/kernel-5.10
sudo touch /home/dpi/qb5_8814/workspace/P4_1716/android/out/target/product/a24/obj/KERNEL_OBJ/kernel-5.10/abi_symbollist.raw

# ========================================
# BUILD KERNEL
# ========================================
build_kernel(){
    cd "${WDIR}/kernel"
    ( env ${GKI_KERNEL_BUILD_OPTIONS} \
    EXTRA_CFLAGS="-Wno-error" \
    KCFLAGS="-Wno-error -Wno-error=format -Wno-error=return-type -Wno-error=stringop-overflow -Wno-error=array-bounds" \
    ./build/build.sh || exit 1 )
    cp "${WDIR}/out/target/product/a24/obj/KERNEL_OBJ/boot.img" "${WDIR}/dist" 2>/dev/null || true
    cp "${WDIR}/out/target/product/a24/obj/KERNEL_OBJ/kernel-5.10/arch/arm64/boot/Image.gz" "${WDIR}/dist" 2>/dev/null || true
    cd "${WDIR}"
}

# ========================================
# CREATE TAR
# ========================================
build_tar(){
    echo -e "\n[INFO] Creating an Odin flashable tar..\n"
    cd "${WDIR}/dist"
    tar -cvf "KernelSU-Next-SM-a245F-${BUILD_KERNEL_VERSION}.tar" boot.img
    echo -e "\n[INFO] Build Finished..!\n"
    cd "${WDIR}"
}

# ========================================
# PATCH ALL MAKEFILES (SAFE)
# ========================================
echo "Patching MediaTek audio Makefile..."
sed -i 's/-Werror//g' "${WDIR}/kernel-5.10/sound/soc/mediatek/common/Makefile" || true
sed -i 's/-Werror//g' "${WDIR}/kernel-5.10/drivers/gpu/drm/mediatek/mediatek_v2/Makefile" || true

# ========================================
# MAIN EXECUTION
# ========================================
build_kernel
build_tar
