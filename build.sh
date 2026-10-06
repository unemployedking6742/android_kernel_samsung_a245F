#!/bin/bash
set -euo pipefail
set -x

# ========================================
# REPO & KERNEL PATHS
# ========================================
export WDIR="$(pwd)"
export KERNEL_DIR="${WDIR}/kernel-5.10"
export DIST_DIR="${WDIR}/dist"
export DEFCONFIG="a24_defconfig"

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
git submodule init && git submodule update

# ========================================
# INSTALL REQUIREMENTS
# ========================================
if [ ! -f ".requirements" ]; then
    echo -e "\n[INFO]: INSTALLING REQUIREMENTS..!\n"
    sudo apt update
    sudo apt install -y rsync python3 curl tar
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
# TELEGRAM: BUILD STARTED MESSAGE
# ========================================
send_build_started_telegram() {
    # Kernel version from Makefile
    local kernel_version
    kernel_version=$(awk '/^VERSION/ {v=$3} /^PATCHLEVEL/ {p=$3} /^SUBLEVEL/ {s=$3} END {print v"."p"."s}' "${KERNEL_DIR}/Makefile")

    # Git info
    local branch last_commit
    branch=$(git -C "${KERNEL_DIR}" rev-parse --abbrev-ref HEAD)
    last_commit=$(git -C "${KERNEL_DIR}" log -1 --pretty=format:'%h - %s')

    # Compose message
    local message="🛠 Kernel Build Started
Date: $(date '+%Y-%m-%d %H:%M:%S')
Branch: ${branch}
Last Commit: ${last_commit}
Defconfig: ${DEFCONFIG}
Kernel Version: ${kernel_version}
"

    # Send via Telegram
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
         -d chat_id="${G99_CHAT_ID}" \
         -d text="${message}" \
         -d parse_mode="Markdown" >/dev/null 2>&1
}

# Send build started message
send_build_started_telegram

# ========================================
# GENERATE BUILD CONFIG
# ========================================
cd "${KERNEL_DIR}"
python2 scripts/gen_build_config.py \
    --kernel-defconfig "${DEFCONFIG}" \
    --kernel-defconfig-overlays entry_level.config \
    -m user \
    -o "../out/target/product/a24/obj/KERNEL_OBJ/build.config"

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
export MERGE_CONFIG="${KERNEL_DIR}/scripts/kconfig/merge_config.sh"

# Build options
export GKI_KERNEL_BUILD_OPTIONS="
    SKIP_MRPROPER=1 \
    KMI_SYMBOL_LIST_STRICT_MODE=0 \
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


cd "${WDIR}/kernel"
# ========================================
# BUILD KERNEL
# ========================================

build_kernel(){
    ( env ${GKI_KERNEL_BUILD_OPTIONS} ./build/build.sh || exit 1 ) && \
        ( cp "${WDIR}/out/target/product/a24/obj/KERNEL_OBJ/boot.img" "${WDIR}/dist" 
        cp "${WDIR}/out/target/product/a24/obj/KERNEL_OBJ/kernel-5.10/arch/arm64/boot/Image.gz" "${WDIR}/dist" )
}
# ========================================
# CREATE TAR
# ========================================
build_tar(){
    echo -e "\n[INFO] Creating an Odin flashable tar..\n"

    cd "${WDIR}/dist"
    tar -cvf "KernelSU-Next-SM-a245F-${BUILD_KERNEL_VERSION}.tar" boot.img && rm boot.img
    echo -e "\n[INFO] Build Finished..!\n"
    cd "${WDIR}"
}

# ========================================
# MAIN EXECUTION
# ========================================
build_kernel
build_tar

