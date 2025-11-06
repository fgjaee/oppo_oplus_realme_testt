#!/bin/bash
set -euo pipefail

function contains_device() {
  local needle="$1"
  shift
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

function download_latest_patch_linux() {
  local output_path="$1"
  local asset_url
  asset_url=$(curl -fsSL "https://api.github.com/repos/ShirkNeko/SukiSU_KernelPatch_patch/releases/latest" |
    python3 -c "import json,sys; data=json.load(sys.stdin);\nfor asset in data.get('assets', []):\n    if asset.get('name') == 'patch_linux':\n        print(asset.get('browser_download_url', ''));\n        break") || asset_url=""
  if [[ -z "${asset_url}" ]]; then
    echo ">>> 未能获取最新 patch_linux 版本，将回退到 0.12.0"
    asset_url="https://github.com/ShirkNeko/SukiSU_KernelPatch_patch/releases/download/0.12.0/patch_linux"
  fi
  curl -fL --output "$output_path" "$asset_url"
  echo ">>> patch_linux 下载来源: $asset_url"
}

# ===== 获取脚本目录 =====
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

# ===== 设置自定义参数 =====
echo "===== 欧加真SM8550通用5.15.167 A15 OKI内核本地编译脚本 By Coolapk@cctv18 ====="
echo ">>> 读取用户配置..."
SUPPORTED_ONEPLUS_8550_DEVICES=(
  "oneplus11"
  "oneplus12r"
  "oneplusace2pro"
  "oneplusace3"
  "oneplusopen"
)
DEFAULT_MANIFEST="oneplus11+oneplus12r+oneplusace2pro+oneplusace3+oneplusopen"
declare -A DEVICE_BRANCH_MAP=(
  ["oneplus11"]="oneplus/sm8550_v_15.0.0_oneplus11"
  ["oneplus12r"]="oneplus/sm8550_v_15.0.0_oneplus_12r"
  ["oneplusace2pro"]="oneplus/sm8550_v_15.0.0_ace_2_pro"
  ["oneplusace3"]="oneplus/sm8550_v_15.0.0_ace_3"
  ["oneplusopen"]="oneplus/sm8550_v_15.0.0_oneplus_open"
)
echo "支持的一加 SM8550 机型: ${SUPPORTED_ONEPLUS_8550_DEVICES[*]}"
if [[ -z "${MANIFEST:-}" ]]; then
  read -p "请输入目标机型列表（使用+分隔，默认：${DEFAULT_MANIFEST}）: " INPUT_MANIFEST
  MANIFEST=${INPUT_MANIFEST:-$DEFAULT_MANIFEST}
else
  MANIFEST="$MANIFEST"
fi
IFS='+' read -r -a MANIFEST_DEVICES <<< "$MANIFEST"

VALID_DEVICES=()
for device in "${MANIFEST_DEVICES[@]}"; do
  if [[ -n "${DEVICE_BRANCH_MAP[$device]:-}" ]]; then
    VALID_DEVICES+=("$device")
  else
    echo ">>> 警告: 未识别的机型 $device 已忽略"
  fi
done

if [[ ${#VALID_DEVICES[@]} -eq 0 ]]; then
  echo ">>> 未提供有效的一加 SM8550 机型，脚本终止。"
  exit 1
fi

MANIFEST_DEVICES=("${VALID_DEVICES[@]}")
MANIFEST=$(IFS='+'; echo "${MANIFEST_DEVICES[*]}")

DEFAULT_BRANCH="${DEVICE_BRANCH_MAP[${MANIFEST_DEVICES[0]}]}"
DEFAULT_BRANCH=${DEFAULT_BRANCH:-oneplus/sm8550_v_15.0.0_oneplus11}
if contains_device "oneplus12r" "${MANIFEST_DEVICES[@]}"; then
  echo ">>> 检测到一加 12R，将自动套用 Android 13 / SUSFS / KPM 默认组合"
fi
if [[ -z "${KERNEL_BRANCH:-}" ]]; then
  read -p "请输入内核分支（默认：${DEFAULT_BRANCH}）: " INPUT_KERNEL_BRANCH
  KERNEL_BRANCH=${INPUT_KERNEL_BRANCH:-$DEFAULT_BRANCH}
else
  KERNEL_BRANCH="$KERNEL_BRANCH"
fi

DEFAULT_SUFFIX="android14-12-o-gc462ef8ffab7"
if [[ "$DEFAULT_BRANCH" == *"oneplus_12r"* ]]; then
  DEFAULT_SUFFIX="android13-oneplus12r"
fi

read -p "请输入自定义内核后缀（默认：${DEFAULT_SUFFIX}）: " INPUT_CUSTOM_SUFFIX
CUSTOM_SUFFIX=${INPUT_CUSTOM_SUFFIX:-$DEFAULT_SUFFIX}

DEFAULT_SUSFS_ANDROID_VERSION=14
if contains_device "oneplus12r" "${MANIFEST_DEVICES[@]}"; then
  DEFAULT_SUSFS_ANDROID_VERSION=13
fi

read -p "请选择 SUSFS 补丁安卓版本 (13/14，默认：${DEFAULT_SUSFS_ANDROID_VERSION}): " INPUT_SUSFS_ANDROID_VERSION
SUSFS_ANDROID_VERSION=${INPUT_SUSFS_ANDROID_VERSION:-$DEFAULT_SUSFS_ANDROID_VERSION}
if [[ "$SUSFS_ANDROID_VERSION" != "13" && "$SUSFS_ANDROID_VERSION" != "14" ]]; then
  echo ">>> 未识别的安卓版本，已回退至 14"
  SUSFS_ANDROID_VERSION=14
fi
SUSFS_BRANCH="gki-android${SUSFS_ANDROID_VERSION}-5.15"
SUSFS_PATCH_FILE="50_add_susfs_in_${SUSFS_BRANCH}.patch"
DEFAULT_USE_PATCH_LINUX=n
if contains_device "oneplus12r" "${MANIFEST_DEVICES[@]}"; then
  DEFAULT_USE_PATCH_LINUX=y
fi
read -p "是否启用 KPM？(y/n，默认：${DEFAULT_USE_PATCH_LINUX}): " INPUT_USE_PATCH_LINUX
USE_PATCH_LINUX=${INPUT_USE_PATCH_LINUX:-$DEFAULT_USE_PATCH_LINUX}
read -p "KSU分支版本(y=SukiSU Ultra, n=KernelSU Next, 默认：y): " KSU_BRANCH
KSU_BRANCH=${KSU_BRANCH:-y}
read -p "应用钩子类型 (manual/syscall/kprobes, m/s/k, 默认m): " APPLY_HOOKS
APPLY_HOOKS=${APPLY_HOOKS:-m}
read -p "是否应用 lz4 1.9.4 & zstd 1.5.7 补丁？(y/n，默认：y): " APPLY_LZ4
APPLY_LZ4=${APPLY_LZ4:-y}
read -p "是否应用 lz4kd 补丁？(y/n，默认：n): " APPLY_LZ4KD
APPLY_LZ4KD=${APPLY_LZ4KD:-n}
read -p "是否启用网络功能增强优化配置？(y/n，默认：y): " APPLY_BETTERNET
APPLY_BETTERNET=${APPLY_BETTERNET:-y}
read -p "是否添加 BBR 等一系列拥塞控制算法？(y添加/n禁用/d默认，默认：n): " APPLY_BBR
APPLY_BBR=${APPLY_BBR:-n}
read -p "是否启用三星SSG IO调度器？(y/n，默认：y): " APPLY_SSG
APPLY_SSG=${APPLY_SSG:-y}
read -p "是否启用Re-Kernel？(y/n，默认：n): " APPLY_REKERNEL
APPLY_REKERNEL=${APPLY_REKERNEL:-n}
read -p "是否启用内核级基带保护？(y/n，默认：y): " APPLY_BBG
APPLY_BBG=${APPLY_BBG:-y}

if [[ "$KSU_BRANCH" == "y" || "$KSU_BRANCH" == "Y" ]]; then
  KSU_TYPE="SukiSU Ultra"
else
  KSU_TYPE="KernelSU Next"
fi

echo
echo "===== 配置信息 ====="
echo "适用机型: $MANIFEST"
echo "内核分支: $KERNEL_BRANCH"
echo "自定义内核后缀: -$CUSTOM_SUFFIX"
echo "SUSFS 补丁基线: Android $SUSFS_ANDROID_VERSION ($SUSFS_BRANCH)"
echo "KSU分支版本: $KSU_TYPE"
echo "启用 KPM: $USE_PATCH_LINUX"
echo "钩子类型: $APPLY_HOOKS"
echo "应用 lz4&zstd 补丁: $APPLY_LZ4"
echo "应用 lz4kd 补丁: $APPLY_LZ4KD"
echo "应用网络功能增强优化配置: $APPLY_BETTERNET"
echo "应用 BBR 等算法: $APPLY_BBR"
echo "启用三星SSG IO调度器: $APPLY_SSG"
echo "启用Re-Kernel: $APPLY_REKERNEL"
echo "启用内核级基带保护: $APPLY_BBG"
echo "===================="
echo

# ===== 创建工作目录 =====
WORKDIR="$SCRIPT_DIR"
cd "$WORKDIR"

# ===== 安装构建依赖 =====
echo ">>> 安装构建依赖..."
if command -v apt-mark >/dev/null 2>&1; then
  sudo apt-mark hold firefox libc-bin man-db || true
fi
sudo rm -rf /var/lib/man-db/auto-update
sudo apt-get update
sudo apt-get install --no-install-recommends -y \
  bc \
  binutils \
  binutils-aarch64-linux-gnu \
  binutils-arm-linux-gnueabihf \
  bison \
  clang \
  curl \
  dwarves \
  flex \
  g++-aarch64-linux-gnu \
  g++-arm-linux-gnueabihf \
  gcc \
  gcc-aarch64-linux-gnu \
  gcc-arm-linux-gnueabihf \
  git \
  lld \
  make \
  pahole \
  perl \
  python-is-python3 \
  python3 \
  zip \
  libelf-dev \
  libssl-dev
sudo rm -rf ./llvm.sh && wget https://apt.llvm.org/llvm.sh && chmod +x llvm.sh
sudo ./llvm.sh 20 all

# ===== 初始化仓库 =====
echo ">>> 初始化仓库..."
rm -rf kernel_workspace
mkdir kernel_workspace
cd kernel_workspace
git clone --depth=1 https://github.com/OnePlusOSS/android_kernel_oneplus_sm8550 -b "$KERNEL_BRANCH" common
echo ">>> 初始化仓库完成"

# ===== 清除 abi 文件、去除 -dirty 后缀 =====
echo ">>> 正在清除 ABI 文件及去除 dirty 后缀..."
rm common/android/abi_gki_protected_exports_* || true

for f in common/scripts/setlocalversion; do
  sed -i 's/ -dirty//g' "$f"
  sed -i '$i res=$(echo "$res" | sed '\''s/-dirty//g'\'')' "$f"
done

# ===== 替换版本后缀 =====
echo ">>> 替换内核版本后缀..."
for f in ./common/scripts/setlocalversion; do
  sed -i "\$s|echo \"\\\$res\"|echo \"-${CUSTOM_SUFFIX}\"|" "$f"
done

# ===== 拉取 KSU 并设置版本号 =====
if [[ "$KSU_BRANCH" == "y" ]]; then
  echo ">>> 拉取 SukiSU-Ultra 并设置版本..."
  curl -LSs "https://raw.githubusercontent.com/ShirkNeko/SukiSU-Ultra/main/kernel/setup.sh" | bash -s susfs-main
  cd KernelSU
  KSU_VERSION=$(expr $(/usr/bin/git rev-list --count main) "+" 10700)
  export KSU_VERSION=$KSU_VERSION
  sed -i "s/DKSU_VERSION=12800/DKSU_VERSION=${KSU_VERSION}/" kernel/Makefile
else
  echo ">>> 拉取 KernelSU Next 并设置版本..."
  curl -LSs "https://raw.githubusercontent.com/pershoot/KernelSU-Next/next-susfs/kernel/setup.sh" | bash -s next-susfs
  cd KernelSU-Next
  KSU_VERSION=$(expr $(curl -sI "https://api.github.com/repos/pershoot/KernelSU-Next/commits?sha=next&per_page=1" | grep -i "link:" | sed -n 's/.*page=\([0-9]*\)>; rel="last".*/\1/p') "+" 10200)
  sed -i "s/DKSU_VERSION=11998/DKSU_VERSION=${KSU_VERSION}/" kernel/Makefile
fi

# ===== 克隆补丁仓库&应用 SUSFS 补丁 =====
echo ">>> 克隆补丁仓库..."
cd "$WORKDIR/kernel_workspace"
echo ">>> 应用 SUSFS&hook 补丁..."
if [[ "$KSU_BRANCH" == "y" ]]; then
  git clone https://github.com/shirkneko/susfs4ksu.git -b "$SUSFS_BRANCH"
  git clone https://github.com/ShirkNeko/SukiSU_patch.git
  cp "./susfs4ksu/kernel_patches/$SUSFS_PATCH_FILE" ./common/ || {
    echo ">>> 未找到 SUSFS 补丁文件: $SUSFS_PATCH_FILE"; exit 1; }
  if [[ "$APPLY_HOOKS" == "m" || "$APPLY_HOOKS" == "M" ]]; then
    cp ./SukiSU_patch/hooks/scope_min_manual_hooks_v1.5.patch ./common/
  fi
  if [[ "$APPLY_HOOKS" == "s" || "$APPLY_HOOKS" == "S" ]]; then
    cp ./SukiSU_patch/hooks/syscall_hooks.patch ./common/
  fi
  cp ./SukiSU_patch/69_hide_stuff.patch ./common/
  cp ./susfs4ksu/kernel_patches/fs/* ./common/fs/
  cp ./susfs4ksu/kernel_patches/include/linux/* ./common/include/linux/
  cd ./common
  patch -p1 < "$SUSFS_PATCH_FILE" || true
  if [[ "$APPLY_HOOKS" == "m" || "$APPLY_HOOKS" == "M" ]]; then
    patch -p1 < scope_min_manual_hooks_v1.5.patch || true
  fi
  if [[ "$APPLY_HOOKS" == "s" || "$APPLY_HOOKS" == "S" ]]; then
    patch -p1 < syscall_hooks.patch || true
  fi
  patch -p1 -F 3 < 69_hide_stuff.patch || true
else
  git clone https://gitlab.com/simonpunk/susfs4ksu.git -b "$SUSFS_BRANCH"
  git clone https://github.com/WildKernels/kernel_patches.git
  cp "./susfs4ksu/kernel_patches/$SUSFS_PATCH_FILE" ./common/ || {
    echo ">>> 未找到 SUSFS 补丁文件: $SUSFS_PATCH_FILE"; exit 1; }
  cp ./susfs4ksu/kernel_patches/fs/* ./common/fs/
  cp ./susfs4ksu/kernel_patches/include/linux/* ./common/include/linux/
  if [[ "$APPLY_HOOKS" == "m" || "$APPLY_HOOKS" == "M" ]]; then
    cp ./kernel_patches/next/scope_min_manual_hooks_v1.5.patch ./common/
  fi
  if [[ "$APPLY_HOOKS" == "s" || "$APPLY_HOOKS" == "S" ]]; then
    cp ./kernel_patches/next/syscall_hooks.patch ./common/
  fi
  cp ./kernel_patches/69_hide_stuff.patch ./common/
  cd ./common
  patch -p1 < "$SUSFS_PATCH_FILE" || true
  if [[ "$APPLY_HOOKS" == "m" || "$APPLY_HOOKS" == "M" ]]; then
    patch -p1 -N -F 3 < scope_min_manual_hooks_v1.5.patch || true
  fi
  if [[ "$APPLY_HOOKS" == "s" || "$APPLY_HOOKS" == "S" ]]; then
    patch -p1 -N -F 3 < syscall_hooks.patch || true
  fi
  patch -p1 -N -F 3 < 69_hide_stuff.patch || true
  #为KernelSU Next添加WildKSU管理器支持
  cd ./drivers/kernelsu
  wget https://github.com/WildKernels/kernel_patches/raw/refs/heads/main/next/susfs_fix_patches/v1.5.12/fix_apk_sign.c.patch
  patch -p2 -N -F 3 < fix_apk_sign.c.patch || true
  cd ../../
fi
cd ../

# ===== 应用 LZ4 & ZSTD 补丁 =====
if [[ "$APPLY_LZ4" == "y" || "$APPLY_LZ4" == "Y" ]]; then
  echo ">>> 正在添加lz4 1.9.4 & zstd 1.5.7补丁..."
  cp "$REPO_ROOT/zram_patch/001-lz4-old.patch" ./common/
  cp "$REPO_ROOT/zram_patch/002-zstd.patch" ./common/
  cd "$WORKDIR/kernel_workspace/common"
  if patch -p1 -F 3 < 001-lz4-old.patch; then
    patch -p1 -F 3 < 002-zstd.patch || true
  else
    echo ">>> lz4 补丁应用失败，已跳过。"
  fi
  cd "$WORKDIR/kernel_workspace"
else
  echo ">>> 跳过 LZ4&ZSTD 补丁..."
  cd "$WORKDIR/kernel_workspace"
fi

# ===== 应用 LZ4KD 补丁 =====
if [[ "$APPLY_LZ4KD" == "y" || "$APPLY_LZ4KD" == "Y" ]]; then
  echo ">>> 应用 LZ4KD 补丁..."
  if [[ "$KSU_BRANCH" == "n" || "$KSU_BRANCH" == "N" ]]; then
    git clone https://github.com/ShirkNeko/SukiSU_patch.git
  fi
  mkdir -p ./common/include/linux ./common/lib ./common/crypto
  cp -r ./SukiSU_patch/other/zram/lz4k/include/linux/* ./common/include/linux/
  cp -r ./SukiSU_patch/other/zram/lz4k/lib/* ./common/lib/
  cp -r ./SukiSU_patch/other/zram/lz4k/crypto/* ./common/crypto/
  cp ./SukiSU_patch/other/zram/zram_patch/5.15/lz4kd.patch ./common/
  cd "$WORKDIR/kernel_workspace/common"
  patch -p1 -F 3 < lz4kd.patch || true
  cd "$WORKDIR/kernel_workspace"
else
  echo ">>> 跳过 LZ4KD 补丁..."
  cd "$WORKDIR/kernel_workspace"
fi

# ===== 添加 defconfig 配置项 =====
echo ">>> 添加 defconfig 配置项..."
DEFCONFIG_FILE=./common/arch/arm64/configs/gki_defconfig

# 写入通用 SUSFS/KSU 配置
cat >> "$DEFCONFIG_FILE" <<EOF
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
#CONFIG_KSU_SUSFS_SUS_OVERLAYFS is not set
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
#添加对 Mountify (backslashxx/mountify) 模块的支持
CONFIG_TMPFS_XATTR=y
CONFIG_TMPFS_POSIX_ACL=y
EOF

if [[ "$APPLY_HOOKS" == "k" || "$APPLY_HOOKS" == "K" ]]; then
  echo "CONFIG_KSU_SUSFS_SUS_SU=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_KSU_MANUAL_HOOK=n" >> "$DEFCONFIG_FILE"
  echo "CONFIG_KSU_KPROBES_HOOK=y" >> "$DEFCONFIG_FILE"
else
  echo "CONFIG_KSU_MANUAL_HOOK=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_KSU_SUSFS_SUS_SU=n" >>  "$DEFCONFIG_FILE"
fi
# 开启O2编译优化配置
echo "CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y" >> "$DEFCONFIG_FILE"
#跳过将uapi标准头安装到 usr/include 目录的不必要操作，节省编译时间
echo "CONFIG_HEADERS_INSTALL=n" >> "$DEFCONFIG_FILE"

# 仅在启用了 KPM 时添加 KPM 支持
if [[ "$USE_PATCH_LINUX" == "y" || "$USE_PATCH_LINUX" == "Y" ]]; then
  echo "CONFIG_KPM=y" >> "$DEFCONFIG_FILE"
fi

# 仅在启用了 LZ4KD 补丁时添加相关算法支持
if [[ "$APPLY_LZ4KD" == "y" || "$APPLY_LZ4KD" == "Y" ]]; then
  cat >> "$DEFCONFIG_FILE" <<EOF
CONFIG_ZSMALLOC=y
CONFIG_CRYPTO_LZ4HC=y
CONFIG_CRYPTO_LZ4K=y
CONFIG_CRYPTO_LZ4KD=y
CONFIG_CRYPTO_842=y
EOF

fi

# ===== 启用网络功能增强优化配置 =====
if [[ "$APPLY_BETTERNET" == "y" || "$APPLY_BETTERNET" == "Y" ]]; then
  echo ">>> 正在启用网络功能增强优化配置..."
  echo "CONFIG_BPF_STREAM_PARSER=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_NETFILTER_XT_SET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_MAX=65534" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_BITMAP_IP=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_BITMAP_IPMAC=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_BITMAP_PORT=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_IP=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_IPMARK=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_IPPORT=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_IPPORTIP=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_IPPORTNET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_IPMAC=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_MAC=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_NETPORTNET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_NET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_NETNET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_NETPORT=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_NETIFACE=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_LIST_SET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP6_NF_NAT=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP6_NF_TARGET_MASQUERADE=y" >> "$DEFCONFIG_FILE"
  #由于部分机型的vintf兼容性检测规则，在开启CONFIG_IP6_NF_NAT后开机会出现"您的设备内部出现了问题。请联系您的设备制造商了解详情。"的提示，故添加一个配置修复补丁，在编译内核时隐藏CONFIG_IP6_NF_NAT=y但不影响对应功能编译
  cd common
  cp "$REPO_ROOT/other_patch/config.patch" ./
  patch -p1 -F 3 < config.patch || true
  cd ..
fi

# ===== 添加 BBR 等一系列拥塞控制算法 =====
if [[ "$APPLY_BBR" == "y" || "$APPLY_BBR" == "Y" || "$APPLY_BBR" == "d" || "$APPLY_BBR" == "D" ]]; then
  echo ">>> 正在添加 BBR 等一系列拥塞控制算法..."
  echo "CONFIG_TCP_CONG_ADVANCED=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_BBR=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_CUBIC=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_VEGAS=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_NV=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_WESTWOOD=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_HTCP=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_BRUTAL=y" >> "$DEFCONFIG_FILE"
  if [[ "$APPLY_BBR" == "d" || "$APPLY_BBR" == "D" ]]; then
    echo "CONFIG_DEFAULT_TCP_CONG=bbr" >> "$DEFCONFIG_FILE"
  else
    echo "CONFIG_DEFAULT_TCP_CONG=cubic" >> "$DEFCONFIG_FILE"
  fi
fi

# ===== 启用三星SSG IO调度器 =====
if [[ "$APPLY_SSG" == "y" || "$APPLY_SSG" == "Y" ]]; then
  echo ">>> 正在启用三星SSG IO调度器..."
  echo "CONFIG_MQ_IOSCHED_SSG=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_MQ_IOSCHED_SSG_CGROUP=y" >> "$DEFCONFIG_FILE"
fi

# ===== 启用Re-Kernel =====
if [[ "$APPLY_REKERNEL" == "y" || "$APPLY_REKERNEL" == "Y" ]]; then
  echo ">>> 正在启用Re-Kernel..."
  echo "CONFIG_REKERNEL=y" >> "$DEFCONFIG_FILE"
fi

# ===== 启用内核级基带保护 =====
if [[ "$APPLY_BBG" == "y" || "$APPLY_BBG" == "Y" ]]; then
  echo ">>> 正在启用内核级基带保护..."
  echo "CONFIG_BBG=y" >> "$DEFCONFIG_FILE"
  cd ./common/security
  wget https://github.com/cctv18/Baseband-guard/archive/refs/heads/master.zip
  unzip -q master.zip
  mv "Baseband-guard-master" baseband-guard
  printf '\nobj-$(CONFIG_BBG) += baseband-guard/\n' >> ./Makefile
  sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/lockdown/lockdown,baseband_guard/ } }' ./Kconfig
  awk '
  /endmenu/ { last_endmenu_line = NR }
  { lines[NR] = $0 }
  END {
    for (i=1; i<=NR; i++) {
      if (i == last_endmenu_line) {
        sub(/endmenu/, "", lines[i]);
        print lines[i] "source \"security/baseband-guard/Kconfig\""
        print ""
        print "endmenu"
      } else {
          print lines[i]
      }
    }
  }
  ' ./Kconfig > Kconfig.tmp && mv Kconfig.tmp ./Kconfig
  sed -i 's/selinuxfs.o //g' "./selinux/Makefile"
  sed -i 's/hooks.o //g' "./selinux/Makefile"
  cat "./baseband-guard/sepatch.txt" >> "./selinux/Makefile"
  cd ../../
fi

# ===== 禁用 defconfig 检查 =====
echo ">>> 禁用 defconfig 检查..."
sed -i 's/check_defconfig//' ./common/build.config.gki

# ===== 编译内核 =====
echo ">>> 开始编译内核..."
cd common
make -j"$(nproc --all)" LLVM=1 LLVM_IAS=1 ARCH=arm64 \
  CROSS_COMPILE=aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=arm-linux-gnueabihf- \
  CC=clang \
  LD=ld.lld \
  HOSTCC=clang \
  HOSTLD=ld.lld \
  O=out \
  KCFLAGS+=-O2 \
  KCFLAGS+=-Wno-error \
  gki_defconfig all
echo ">>> 内核编译成功！"

# ===== 选择使用 patch_linux (KPM补丁)=====
OUT_DIR="$WORKDIR/kernel_workspace/common/out/arch/arm64/boot"
if [[ "$USE_PATCH_LINUX" == "y" || "$USE_PATCH_LINUX" == "Y" ]]; then
  echo ">>> 使用 patch_linux 工具处理输出..."
  cd "$OUT_DIR"
  download_latest_patch_linux patch_linux
  chmod +x patch_linux
  ./patch_linux
  rm -f Image
  mv oImage Image
  echo ">>> 已成功打上KPM补丁"
else
  echo ">>> 跳过 patch_linux 操作"
fi

# ===== 克隆并打包 AnyKernel3 =====
cd "$WORKDIR/kernel_workspace"
echo ">>> 克隆 AnyKernel3 项目..."
git clone https://github.com/cctv18/AnyKernel3 --depth=1

echo ">>> 清理 AnyKernel3 Git 信息..."
rm -rf ./AnyKernel3/.git

echo ">>> 拷贝内核镜像到 AnyKernel3 目录..."
cp "$OUT_DIR/Image" ./AnyKernel3/

echo ">>> 进入 AnyKernel3 目录并打包 zip..."
cd "$WORKDIR/kernel_workspace/AnyKernel3"

# ===== 如果启用 lz4kd，则下载 zram.zip 并放入当前目录 =====
if [[ "$APPLY_LZ4KD" == "y" || "$APPLY_LZ4KD" == "Y" ]]; then
  cp "$REPO_ROOT/zram.zip" ./zram.zip
fi

# ===== 生成 ZIP 文件名 =====
ZIP_NAME="Anykernel3-${MANIFEST}"

if [[ "$APPLY_HOOKS" == "m" || "$APPLY_HOOKS" == "M" ]]; then
  ZIP_NAME="${ZIP_NAME}-manual"
elif [[ "$APPLY_HOOKS" == "s" || "$APPLY_HOOKS" == "S" ]]; then
  ZIP_NAME="${ZIP_NAME}-syscall"
else
  ZIP_NAME="${ZIP_NAME}-kprobe"
fi
if [[ "$APPLY_LZ4KD" == "y" || "$APPLY_LZ4KD" == "Y" ]]; then
  ZIP_NAME="${ZIP_NAME}-lz4kd"
fi
if [[ "$APPLY_LZ4" == "y" || "$APPLY_LZ4" == "Y" ]]; then
  ZIP_NAME="${ZIP_NAME}-lz4-zstd"
fi
if [[ "$USE_PATCH_LINUX" == "y" || "$USE_PATCH_LINUX" == "Y" ]]; then
  ZIP_NAME="${ZIP_NAME}-kpm"
fi
if [[ "$APPLY_BBR" == "y" || "$APPLY_BBR" == "Y" ]]; then
  ZIP_NAME="${ZIP_NAME}-bbr"
fi
if [[ "$APPLY_SSG" == "y" || "$APPLY_SSG" == "Y" ]]; then
  ZIP_NAME="${ZIP_NAME}-ssg"
fi
if [[ "$APPLY_REKERNEL" == "y" || "$APPLY_REKERNEL" == "Y" ]]; then
  ZIP_NAME="${ZIP_NAME}-rek"
fi
if [[ "$APPLY_BBG" == "y" || "$APPLY_BBG" == "Y" ]]; then
  ZIP_NAME="${ZIP_NAME}-bbg"
fi

ZIP_NAME="${ZIP_NAME}-v$(date +%Y%m%d).zip"

# ===== 打包 ZIP 文件，包括 zram.zip（如果存在） =====
echo ">>> 打包文件: $ZIP_NAME"
zip -r "../$ZIP_NAME" ./*

ZIP_PATH="$(realpath "../$ZIP_NAME")"
echo ">>> 打包完成 文件所在目录: $ZIP_PATH"

