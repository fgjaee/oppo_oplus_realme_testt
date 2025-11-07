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

function normalize_android_version() {
  local raw="$1"
  # Trim whitespace and convert to lowercase for consistent comparisons
  raw="${raw//[$'\t\n\r ']}"
  raw="${raw,,}"
  # Strip common prefixes such as android/a/v that may appear in inputs
  raw="${raw#android}"
  raw="${raw#a}"
  raw="${raw#v}"
  # Normalize versions that include a trailing .0
  if [[ "$raw" == "13.0" ]]; then
    raw="13"
  elif [[ "$raw" == "14.0" ]]; then
    raw="14"
  fi
  case "$raw" in
  "13" | "14")
    echo "$raw"
    return 0
    ;;
  esac
  echo ""
  return 1
}

function download_latest_patch_linux() {
  local output_path="$1"
  local asset_url
  asset_url=$(curl -fsSL "https://api.github.com/repos/ShirkNeko/SukiSU_KernelPatch_patch/releases/latest" |
    python3 -c "import json,sys; data=json.load(sys.stdin);\nfor asset in data.get('assets', []):\n    if asset.get('name') == 'patch_linux':\n        print(asset.get('browser_download_url', ''));\n        break") || asset_url=""
  if [[ -z "${asset_url}" ]]; then
    echo ">>> Failed to fetch the latest patch_linux release, falling back to 0.12.0"
    asset_url="https://github.com/ShirkNeko/SukiSU_KernelPatch_patch/releases/download/0.12.0/patch_linux"
  fi
  curl -fL --output "$output_path" "$asset_url"
  echo ">>> patch_linux download source: $asset_url"
}

# ===== Locate script directory =====
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

# ===== Configure build parameters =====
echo "===== OnePlus SM8550 universal 5.15.167 A15 OKI kernel local build script by Coolapk@cctv18 ====="
echo ">>> Loading user configuration..."
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
echo "Supported OnePlus SM8550 devices: ${SUPPORTED_ONEPLUS_8550_DEVICES[*]}"
if [[ -z "${MANIFEST:-}" ]]; then
  read -p "Enter target device list (use + as the separator, default: ${DEFAULT_MANIFEST}): " INPUT_MANIFEST
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
    echo ">>> Warning: unrecognized device $device skipped"
  fi
done

if [[ ${#VALID_DEVICES[@]} -eq 0 ]]; then
  echo ">>> No valid OnePlus SM8550 devices provided, aborting."
  exit 1
fi

MANIFEST_DEVICES=("${VALID_DEVICES[@]}")
MANIFEST=$(IFS='+'; echo "${MANIFEST_DEVICES[*]}")

DEFAULT_BRANCH="${DEVICE_BRANCH_MAP[${MANIFEST_DEVICES[0]}]}"
DEFAULT_BRANCH=${DEFAULT_BRANCH:-oneplus/sm8550_v_15.0.0_oneplus11}
if contains_device "oneplus12r" "${MANIFEST_DEVICES[@]}"; then
  echo ">>> OnePlus 12R detected, applying the Android 13 / SUSFS / KPM defaults"
fi
if [[ "${KERNEL_BRANCH+x}" == "x" ]]; then
  if [[ -z "$KERNEL_BRANCH" ]]; then
    KERNEL_BRANCH="$DEFAULT_BRANCH"
  fi
  echo ">>> Using kernel branch from environment: $KERNEL_BRANCH"
else
  read -p "Enter kernel branch (default: ${DEFAULT_BRANCH}): " INPUT_KERNEL_BRANCH
  KERNEL_BRANCH=${INPUT_KERNEL_BRANCH:-$DEFAULT_BRANCH}
fi

DEFAULT_SUFFIX="android14-12-o-gc462ef8ffab7"
if [[ "$DEFAULT_BRANCH" == *"oneplus_12r"* ]]; then
  DEFAULT_SUFFIX="android13-oneplus12r"
fi

if [[ "${CUSTOM_SUFFIX+x}" == "x" ]]; then
  if [[ -z "$CUSTOM_SUFFIX" ]]; then
    CUSTOM_SUFFIX="$DEFAULT_SUFFIX"
  fi
  echo ">>> Using custom kernel suffix from environment: -$CUSTOM_SUFFIX"
else
  read -p "Enter custom kernel suffix (default: ${DEFAULT_SUFFIX}): " INPUT_CUSTOM_SUFFIX
  CUSTOM_SUFFIX=${INPUT_CUSTOM_SUFFIX:-$DEFAULT_SUFFIX}
fi

DEFAULT_SUSFS_ANDROID_VERSION=14
if contains_device "oneplus12r" "${MANIFEST_DEVICES[@]}"; then
  DEFAULT_SUSFS_ANDROID_VERSION=13
fi

if [[ "${SUSFS_ANDROID_VERSION+x}" == "x" ]]; then
  if [[ -z "$SUSFS_ANDROID_VERSION" ]]; then
    SUSFS_ANDROID_VERSION="$DEFAULT_SUSFS_ANDROID_VERSION"
  fi
  echo ">>> Using SUSFS Android version from environment: $SUSFS_ANDROID_VERSION"
else
  read -p "Select SUSFS patch Android version (13/14, default: ${DEFAULT_SUSFS_ANDROID_VERSION}): " INPUT_SUSFS_ANDROID_VERSION
  SUSFS_ANDROID_VERSION=${INPUT_SUSFS_ANDROID_VERSION:-$DEFAULT_SUSFS_ANDROID_VERSION}
fi
NORMALIZED_SUSFS_ANDROID_VERSION=$(normalize_android_version "$SUSFS_ANDROID_VERSION")
if [[ -z "$NORMALIZED_SUSFS_ANDROID_VERSION" ]]; then
  if contains_device "oneplus12r" "${MANIFEST_DEVICES[@]}"; then
    echo ">>> Unrecognized Android version input, forcing Android 13 defaults for OnePlus 12R"
    NORMALIZED_SUSFS_ANDROID_VERSION=13
  else
    echo ">>> Unrecognized Android version input, defaulting to Android 14"
    NORMALIZED_SUSFS_ANDROID_VERSION=14
  fi
fi
SUSFS_ANDROID_VERSION="$NORMALIZED_SUSFS_ANDROID_VERSION"
SUSFS_BRANCH="gki-android${SUSFS_ANDROID_VERSION}-5.15"
SUSFS_PATCH_FILE="50_add_susfs_in_${SUSFS_BRANCH}.patch"
DEFAULT_USE_PATCH_LINUX=n
if contains_device "oneplus12r" "${MANIFEST_DEVICES[@]}"; then
  DEFAULT_USE_PATCH_LINUX=y
fi
if [[ "${USE_PATCH_LINUX+x}" == "x" ]]; then
  if [[ -z "$USE_PATCH_LINUX" ]]; then
    USE_PATCH_LINUX="$DEFAULT_USE_PATCH_LINUX"
  fi
  echo ">>> Using KPM toggle from environment: $USE_PATCH_LINUX"
else
  read -p "Enable KPM? (y/n, default: ${DEFAULT_USE_PATCH_LINUX}): " INPUT_USE_PATCH_LINUX
  USE_PATCH_LINUX=${INPUT_USE_PATCH_LINUX:-$DEFAULT_USE_PATCH_LINUX}
fi
if [[ "${KSU_BRANCH+x}" == "x" ]]; then
  if [[ -z "$KSU_BRANCH" ]]; then
    KSU_BRANCH=y
  fi
  echo ">>> Using KernelSU branch choice from environment: $KSU_BRANCH"
else
  read -p "KSU branch (y=SukiSU Ultra, n=KernelSU Next, default: y): " KSU_BRANCH
  KSU_BRANCH=${KSU_BRANCH:-y}
fi
if [[ "${APPLY_HOOKS+x}" == "x" ]]; then
  if [[ -z "$APPLY_HOOKS" ]]; then
    APPLY_HOOKS=m
  fi
  echo ">>> Using hook implementation from environment: $APPLY_HOOKS"
else
  read -p "Hook implementation (manual/syscall/kprobes, m/s/k, default m): " APPLY_HOOKS
  APPLY_HOOKS=${APPLY_HOOKS:-m}
fi
if [[ "${APPLY_LZ4+x}" == "x" ]]; then
  if [[ -z "$APPLY_LZ4" ]]; then
    APPLY_LZ4=y
  fi
  echo ">>> Using LZ4/ZSTD toggle from environment: $APPLY_LZ4"
else
  read -p "Apply lz4 1.9.4 & zstd 1.5.7 patches? (y/n, default: y): " APPLY_LZ4
  APPLY_LZ4=${APPLY_LZ4:-y}
fi
if [[ "${APPLY_LZ4KD+x}" == "x" ]]; then
  if [[ -z "$APPLY_LZ4KD" ]]; then
    APPLY_LZ4KD=n
  fi
  echo ">>> Using LZ4KD toggle from environment: $APPLY_LZ4KD"
else
  read -p "Apply the lz4kd patch? (y/n, default: n): " APPLY_LZ4KD
  APPLY_LZ4KD=${APPLY_LZ4KD:-n}
fi
if [[ "${APPLY_BETTERNET+x}" == "x" ]]; then
  if [[ -z "$APPLY_BETTERNET" ]]; then
    APPLY_BETTERNET=y
  fi
  echo ">>> Using enhanced network toggle from environment: $APPLY_BETTERNET"
else
  read -p "Enable enhanced network configuration? (y/n, default: y): " APPLY_BETTERNET
  APPLY_BETTERNET=${APPLY_BETTERNET:-y}
fi
if [[ "${APPLY_BBR+x}" == "x" ]]; then
  if [[ -z "$APPLY_BBR" ]]; then
    APPLY_BBR=n
  fi
  echo ">>> Using BBR toggle from environment: $APPLY_BBR"
else
  read -p "Add BBR and related congestion control algorithms? (y=enable/n=disable/d=default, default: n): " APPLY_BBR
  APPLY_BBR=${APPLY_BBR:-n}
fi
if [[ "${APPLY_SSG+x}" == "x" ]]; then
  if [[ -z "$APPLY_SSG" ]]; then
    APPLY_SSG=y
  fi
  echo ">>> Using Samsung SSG toggle from environment: $APPLY_SSG"
else
  read -p "Enable Samsung SSG IO scheduler? (y/n, default: y): " APPLY_SSG
  APPLY_SSG=${APPLY_SSG:-y}
fi
if [[ "${APPLY_REKERNEL+x}" == "x" ]]; then
  if [[ -z "$APPLY_REKERNEL" ]]; then
    APPLY_REKERNEL=n
  fi
  echo ">>> Using Re-Kernel toggle from environment: $APPLY_REKERNEL"
else
  read -p "Enable Re-Kernel? (y/n, default: n): " APPLY_REKERNEL
  APPLY_REKERNEL=${APPLY_REKERNEL:-n}
fi
if [[ "${APPLY_BBG+x}" == "x" ]]; then
  if [[ -z "$APPLY_BBG" ]]; then
    APPLY_BBG=y
  fi
  echo ">>> Using baseband guard toggle from environment: $APPLY_BBG"
else
  read -p "Enable in-kernel baseband guard? (y/n, default: y): " APPLY_BBG
  APPLY_BBG=${APPLY_BBG:-y}
fi

if [[ "$KSU_BRANCH" == "y" || "$KSU_BRANCH" == "Y" ]]; then
  KSU_TYPE="SukiSU Ultra"
else
  KSU_TYPE="KernelSU Next"
fi

echo
echo "===== Configuration summary ====="
echo "Target devices: $MANIFEST"
echo "Kernel branch: $KERNEL_BRANCH"
echo "Custom kernel suffix: -$CUSTOM_SUFFIX"
echo "SUSFS patch baseline: Android $SUSFS_ANDROID_VERSION ($SUSFS_BRANCH)"
echo "KSU branch: $KSU_TYPE"
echo "Enable KPM: $USE_PATCH_LINUX"
echo "Hook type: $APPLY_HOOKS"
echo "Apply lz4 & zstd patches: $APPLY_LZ4"
echo "Apply lz4kd patch: $APPLY_LZ4KD"
echo "Enable enhanced network configuration: $APPLY_BETTERNET"
echo "Apply BBR and related algorithms: $APPLY_BBR"
echo "Enable Samsung SSG IO scheduler: $APPLY_SSG"
echo "Enable Re-Kernel: $APPLY_REKERNEL"
echo "Enable in-kernel baseband guard: $APPLY_BBG"
echo "===================="
echo

# ===== Create working directory =====
WORKDIR="$SCRIPT_DIR"
cd "$WORKDIR"

# ===== Install build dependencies =====
echo ">>> Installing build dependencies..."
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

# ===== Initialize repositories =====
echo ">>> Initializing repositories..."
rm -rf kernel_workspace
mkdir kernel_workspace
cd kernel_workspace
git clone --depth=1 https://github.com/OnePlusOSS/android_kernel_oneplus_sm8550 -b "$KERNEL_BRANCH" common
echo ">>> Repository initialization complete"

# ===== Remove ABI files and strip -dirty suffix =====
echo ">>> Removing ABI files and stripping dirty suffix..."
rm common/android/abi_gki_protected_exports_* || true

for f in common/scripts/setlocalversion; do
  sed -i 's/ -dirty//g' "$f"
  sed -i '$i res=$(echo "$res" | sed '\''s/-dirty//g'\'')' "$f"
done

# ===== Replace version suffix =====
echo ">>> Replacing kernel version suffix..."
for f in ./common/scripts/setlocalversion; do
  sed -i "\$s|echo \"\\\$res\"|echo \"-${CUSTOM_SUFFIX}\"|" "$f"
done

# ===== Fetch KSU and set version =====
if [[ "$KSU_BRANCH" == "y" ]]; then
  echo ">>> Fetching SukiSU-Ultra and setting version..."
  curl -LSs "https://raw.githubusercontent.com/ShirkNeko/SukiSU-Ultra/main/kernel/setup.sh" | bash -s susfs-main
  cd KernelSU
  KSU_VERSION=$(expr $(/usr/bin/git rev-list --count main) "+" 10700)
  export KSU_VERSION=$KSU_VERSION
  sed -i "s/DKSU_VERSION=12800/DKSU_VERSION=${KSU_VERSION}/" kernel/Makefile
else
  echo ">>> Fetching KernelSU Next and setting version..."
  curl -LSs "https://raw.githubusercontent.com/pershoot/KernelSU-Next/next-susfs/kernel/setup.sh" | bash -s next-susfs
  cd KernelSU-Next
  KSU_VERSION=$(expr $(curl -sI "https://api.github.com/repos/pershoot/KernelSU-Next/commits?sha=next&per_page=1" | grep -i "link:" | sed -n 's/.*page=\([0-9]*\)>; rel="last".*/\1/p') "+" 10200)
  sed -i "s/DKSU_VERSION=11998/DKSU_VERSION=${KSU_VERSION}/" kernel/Makefile
fi

# ===== Clone patch repositories & apply SUSFS patches =====
echo ">>> Cloning patch repositories..."
cd "$WORKDIR/kernel_workspace"
echo ">>> Applying SUSFS and hook patches..."
if [[ "$KSU_BRANCH" == "y" ]]; then
  git clone https://github.com/shirkneko/susfs4ksu.git -b "$SUSFS_BRANCH"
  git clone https://github.com/ShirkNeko/SukiSU_patch.git
  cp "./susfs4ksu/kernel_patches/$SUSFS_PATCH_FILE" ./common/ || {
    echo ">>> SUSFS patch file not found: $SUSFS_PATCH_FILE"; exit 1; }
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
    echo ">>> SUSFS patch file not found: $SUSFS_PATCH_FILE"; exit 1; }
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
  # Add WildKSU manager support for KernelSU Next
  cd ./drivers/kernelsu
  wget https://github.com/WildKernels/kernel_patches/raw/refs/heads/main/next/susfs_fix_patches/v1.5.12/fix_apk_sign.c.patch
  patch -p2 -N -F 3 < fix_apk_sign.c.patch || true
  cd ../../
fi
cd ../

# ===== Apply LZ4 & ZSTD patches =====
if [[ "$APPLY_LZ4" == "y" || "$APPLY_LZ4" == "Y" ]]; then
  echo ">>> Applying lz4 1.9.4 & zstd 1.5.7 patches..."
  cp "$REPO_ROOT/zram_patch/001-lz4-old.patch" ./common/
  cp "$REPO_ROOT/zram_patch/002-zstd.patch" ./common/
  cd "$WORKDIR/kernel_workspace/common"
  if patch -p1 -F 3 < 001-lz4-old.patch; then
    patch -p1 -F 3 < 002-zstd.patch || true
  else
    echo ">>> Failed to apply the lz4 patch, skipping."
  fi
  cd "$WORKDIR/kernel_workspace"
else
  echo ">>> Skipping LZ4 & ZSTD patches..."
  cd "$WORKDIR/kernel_workspace"
fi

# ===== Apply LZ4KD patch =====
if [[ "$APPLY_LZ4KD" == "y" || "$APPLY_LZ4KD" == "Y" ]]; then
  echo ">>> Applying LZ4KD patch..."
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
  echo ">>> Skipping LZ4KD patch..."
  cd "$WORKDIR/kernel_workspace"
fi

# ===== Append defconfig options =====
echo ">>> Appending defconfig options..."
DEFCONFIG_FILE=./common/arch/arm64/configs/gki_defconfig

# Write common SUSFS/KSU options
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
# Add support for the Mountify (backslashxx/mountify) module
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
# Enable O2 compilation optimizations
echo "CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y" >> "$DEFCONFIG_FILE"
# Skip installing UAPI headers into usr/include to save build time
echo "CONFIG_HEADERS_INSTALL=n" >> "$DEFCONFIG_FILE"

# Only add KPM support when KPM is enabled
if [[ "$USE_PATCH_LINUX" == "y" || "$USE_PATCH_LINUX" == "Y" ]]; then
  echo "CONFIG_KPM=y" >> "$DEFCONFIG_FILE"
fi

# Only add related algorithms when the LZ4KD patch is enabled
if [[ "$APPLY_LZ4KD" == "y" || "$APPLY_LZ4KD" == "Y" ]]; then
  cat >> "$DEFCONFIG_FILE" <<EOF
CONFIG_ZSMALLOC=y
CONFIG_CRYPTO_LZ4HC=y
CONFIG_CRYPTO_LZ4K=y
CONFIG_CRYPTO_LZ4KD=y
CONFIG_CRYPTO_842=y
EOF

fi

# ===== Enable enhanced network configuration =====
if [[ "$APPLY_BETTERNET" == "y" || "$APPLY_BETTERNET" == "Y" ]]; then
  echo ">>> Enabling enhanced network configuration..."
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
  # Some devices fail VINTF validation when CONFIG_IP6_NF_NAT is visible, triggering the warning "There is an internal problem with your device. Please contact your device manufacturer for details."# Apply a config fix so CONFIG_IP6_NF_NAT=y stays hidden during builds without affecting functionality
  cd common
  cp "$REPO_ROOT/other_patch/config.patch" ./
  patch -p1 -F 3 < config.patch || true
  cd ..
fi

# ===== Add BBR and other congestion control algorithms =====
if [[ "$APPLY_BBR" == "y" || "$APPLY_BBR" == "Y" || "$APPLY_BBR" == "d" || "$APPLY_BBR" == "D" ]]; then
  echo ">>> Adding BBR and related congestion control algorithms..."
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

# ===== Enable Samsung SSG IO scheduler =====
if [[ "$APPLY_SSG" == "y" || "$APPLY_SSG" == "Y" ]]; then
  echo ">>> Enabling Samsung SSG IO scheduler..."
  echo "CONFIG_MQ_IOSCHED_SSG=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_MQ_IOSCHED_SSG_CGROUP=y" >> "$DEFCONFIG_FILE"
fi

# ===== Enable Re-Kernel =====
if [[ "$APPLY_REKERNEL" == "y" || "$APPLY_REKERNEL" == "Y" ]]; then
  echo ">>> Enabling Re-Kernel..."
  echo "CONFIG_REKERNEL=y" >> "$DEFCONFIG_FILE"
fi

# ===== Enable in-kernel baseband guard =====
if [[ "$APPLY_BBG" == "y" || "$APPLY_BBG" == "Y" ]]; then
  echo ">>> Enabling in-kernel baseband guard..."
  echo "CONFIG_BBG=y" >> "$DEFCONFIG_FILE"
  cd ./common/security
  wget https://github.com/cctv18/Baseband-guard/archive/refs/heads/master.zip
  unzip -q master.zip
  mv "Baseband-guard-master" baseband-guard
  printf '\nobj-$(CONFIG_BBG) += baseband-guard/\n' >> ./Makefile
  sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/lockdown/lockdown,baseband_guard/ } }' ./Kconfig
  python3 - <<'PY'
from pathlib import Path

kconfig_path = Path('Kconfig')
lines = kconfig_path.read_text().splitlines()
insert_line = 'source "security/baseband-guard/Kconfig"'

for index in range(len(lines) - 1, -1, -1):
    if lines[index].strip() == 'endmenu':
        lines.insert(index, insert_line)
        break
else:
    lines.append(insert_line)

kconfig_path.write_text('\n'.join(lines) + '\n')
PY
  sed -i 's/selinuxfs.o //g' "./selinux/Makefile"
  sed -i 's/hooks.o //g' "./selinux/Makefile"
  cat "./baseband-guard/sepatch.txt" >> "./selinux/Makefile"
  cd ../../
fi

# ===== Disable defconfig checks =====
echo ">>> Disabling defconfig checks..."
sed -i 's/check_defconfig//' ./common/build.config.gki

# ===== Build kernel =====
echo ">>> Starting kernel build..."
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
echo ">>> Kernel build completed!"

# ===== Optionally run patch_linux (KPM patch) =====
OUT_DIR="$WORKDIR/kernel_workspace/common/out/arch/arm64/boot"
if [[ "$USE_PATCH_LINUX" == "y" || "$USE_PATCH_LINUX" == "Y" ]]; then
  echo ">>> Processing build output with patch_linux..."
  cd "$OUT_DIR"
  download_latest_patch_linux patch_linux
  chmod +x patch_linux
  ./patch_linux
  rm -f Image
  mv oImage Image
  echo ">>> KPM patch applied successfully"
else
  echo ">>> Skipping patch_linux step"
fi

# ===== Clone and package AnyKernel3 =====
cd "$WORKDIR/kernel_workspace"
echo ">>> Cloning the AnyKernel3 project..."
git clone https://github.com/cctv18/AnyKernel3 --depth=1

echo ">>> Cleaning AnyKernel3 git metadata..."
rm -rf ./AnyKernel3/.git

echo ">>> Copying kernel image into the AnyKernel3 directory..."
cp "$OUT_DIR/Image" ./AnyKernel3/

echo ">>> Entering the AnyKernel3 directory and creating the zip..."
cd "$WORKDIR/kernel_workspace/AnyKernel3"

# ===== Download zram.zip when LZ4KD is enabled =====
if [[ "$APPLY_LZ4KD" == "y" || "$APPLY_LZ4KD" == "Y" ]]; then
  cp "$REPO_ROOT/zram.zip" ./zram.zip
fi

# ===== Generate ZIP filename =====
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

# ===== Package ZIP archive (including zram.zip when present) =====
echo ">>> Packaging file: $ZIP_NAME"
zip -r "../$ZIP_NAME" ./*

ZIP_PATH="$(realpath "../$ZIP_NAME")"
echo ">>> Packaging complete. Output directory: $ZIP_PATH"
