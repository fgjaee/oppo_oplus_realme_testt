#!/bin/bash
set -e

# ===== Locate script directory =====
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ===== Configure build parameters =====
echo "===== OPPO/OnePlus/realme MT6989 universal 6.1.115 A15 (Dimensity edition) OKI kernel local build script by Coolapk@cctv18 ====="
echo ">>> Loading user configuration..."
MANIFEST=${MANIFEST:-oppo+oplus+realme}
read -p "Enter a custom kernel suffix (default: android14-11-o-gca13bffobf09): " CUSTOM_SUFFIX
CUSTOM_SUFFIX=${CUSTOM_SUFFIX:-android14-11-o-gca13bffobf09}
read -p "Enable KPM? (y/n, default: n): " USE_PATCH_LINUX
USE_PATCH_LINUX=${USE_PATCH_LINUX:-n}
read -p "KSU branch (y=SukiSU Ultra, n=KernelSU Next, default: y): " KSU_BRANCH
KSU_BRANCH=${KSU_BRANCH:-y}
read -p "Hook implementation (manual/syscall/kprobes, m/s/k, default m): " APPLY_HOOKS
APPLY_HOOKS=${APPLY_HOOKS:-m}
read -p "Apply lz4 1.10.0 & zstd 1.5.7 patches? (y/n, default: y): " APPLY_LZ4
APPLY_LZ4=${APPLY_LZ4:-y}
read -p "Apply the lz4kd patch? (y/n, default: n): " APPLY_LZ4KD
APPLY_LZ4KD=${APPLY_LZ4KD:-n}
read -p "Enable enhanced network configuration? (y/n, may cause issues on Dimensity devices; default: n): " APPLY_BETTERNET
APPLY_BETTERNET=${APPLY_BETTERNET:-n}
read -p "Add BBR and related congestion control algorithms? (y=enable/n=disable/d=default, default: n): " APPLY_BBR
APPLY_BBR=${APPLY_BBR:-n}
read -p "Enable Samsung SSG IO scheduler? (y/n, default: y): " APPLY_SSG
APPLY_SSG=${APPLY_SSG:-y}
read -p "Enable Re-Kernel? (y/n, default: n): " APPLY_REKERNEL
APPLY_REKERNEL=${APPLY_REKERNEL:-n}
read -p "Enable in-kernel baseband guard? (y/n, default: y): " APPLY_BBG
APPLY_BBG=${APPLY_BBG:-y}

if [[ "$KSU_BRANCH" == "y" || "$KSU_BRANCH" == "Y" ]]; then
  KSU_TYPE="SukiSU Ultra"
else
  KSU_TYPE="KernelSU Next"
fi

echo
echo "===== Configuration summary ====="
echo "Target devices: $MANIFEST"
echo "Custom kernel suffix: -$CUSTOM_SUFFIX"
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
sudo apt-mark hold firefox && apt-mark hold libc-bin && apt-mark hold man-db
sudo rm -rf /var/lib/man-db/auto-update
sudo apt-get update
sudo apt-get install --no-install-recommends -y curl bison flex clang binutils dwarves git lld pahole zip perl make gcc python3 python-is-python3 bc libssl-dev libelf-dev
sudo rm -rf ./llvm.sh && wget https://apt.llvm.org/llvm.sh && chmod +x llvm.sh
sudo ./llvm.sh 20 all

# ===== Initialize repositories =====
echo ">>> Initializing repositories..."
rm -rf kernel_workspace
mkdir kernel_workspace
cd kernel_workspace
git clone --depth=1 https://github.com/cctv18/android_kernel_oneplus_mt6989 -b oneplus/mt6989_v_15.0.2_ace5_race common
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
  git clone https://github.com/shirkneko/susfs4ksu.git -b gki-android14-6.1
  git clone https://github.com/ShirkNeko/SukiSU_patch.git
  cp ./susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch ./common/
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
  patch -p1 < 50_add_susfs_in_gki-android14-6.1.patch || true
  if [[ "$APPLY_HOOKS" == "m" || "$APPLY_HOOKS" == "M" ]]; then
    patch -p1 < scope_min_manual_hooks_v1.5.patch || true
  fi
  if [[ "$APPLY_HOOKS" == "s" || "$APPLY_HOOKS" == "S" ]]; then
    patch -p1 < syscall_hooks.patch || true
  fi
  patch -p1 -F 3 < 69_hide_stuff.patch || true
else
  git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-android14-6.1
  git clone https://github.com/WildKernels/kernel_patches.git
  cp ./susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch ./common/
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
  patch -p1 < 50_add_susfs_in_gki-android14-6.1.patch || true
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
  echo ">>> Applying lz4 1.10.0 & zstd 1.5.7 patches..."
  git clone https://github.com/cctv18/oppo_oplus_realme_sm8550.git
  cp ./oppo_oplus_realme_sm8550/zram_patch/001-lz4.patch ./common/
  cp ./oppo_oplus_realme_sm8550/zram_patch/lz4armv8.S ./common/lib
  cp ./oppo_oplus_realme_sm8550/zram_patch/002-zstd.patch ./common/
  cd "$WORKDIR/kernel_workspace/common"
  git apply -p1 < 001-lz4.patch || true
  patch -p1 < 002-zstd.patch || true
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
  cp -r ./SukiSU_patch/other/zram/lz4k/include/linux/* ./common/include/linux/
  cp -r ./SukiSU_patch/other/zram/lz4k/lib/* ./common/lib
  cp -r ./SukiSU_patch/other/zram/lz4k/crypto/* ./common/crypto
  cp ./SukiSU_patch/other/zram/zram_patch/6.1/lz4kd.patch ./common/
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
  wget https://github.com/cctv18/oppo_oplus_realme_sm8550/raw/refs/heads/main/other_patch/config.patch
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

# ===== Disable defconfig checks =====
echo ">>> Disabling defconfig checks..."
sed -i 's/check_defconfig//' ./common/build.config.gki

# ===== Build kernel =====
echo ">>> Starting kernel build..."
cd common
make -j$(nproc --all) LLVM=-20 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC=clang LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error gki_defconfig all
echo ">>> Kernel build completed!"

# ===== Optionally run patch_linux (KPM patch) =====
OUT_DIR="$WORKDIR/kernel_workspace/common/out/arch/arm64/boot"
if [[ "$USE_PATCH_LINUX" == "y" || "$USE_PATCH_LINUX" == "Y" ]]; then
  echo ">>> Processing build output with patch_linux..."
  cd "$OUT_DIR"
  wget https://github.com/ShirkNeko/SukiSU_KernelPatch_patch/releases/download/0.12.0/patch_linux
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
  wget https://raw.githubusercontent.com/cctv18/oppo_oplus_realme_sm8550/refs/heads/main/zram.zip
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
