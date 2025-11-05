# Universal 6.1 kernel automation build scripts for OnePlus SM8550 / MT6989 / MT6897
# Universal 6.1 kernel automation build scripts for OPPO / OnePlus / realme SM8550 / MT6989 / MT6897

[![STAR](https://img.shields.io/github/stars/cctv18/oppo_oplus_realme_sm8550?style=flat&logo=github)](https://github.com/cctv18/oppo_oplus_realme_sm8550/stargazers)
[![FORK](https://img.shields.io/github/forks/cctv18/oppo_oplus_realme_sm8550?style=flat&logo=greasyfork&color=%2394E61A)](https://github.com/cctv18/oppo_oplus_realme_sm8550/forks)
[![COOLAPK](https://img.shields.io/badge/cctv18_2-cctv18_2?style=flat&logo=android&logoColor=FF4500&label=Coolapk&color=FF4500)](http://www.coolapk.com/u/22650293)
[![DISCUSSION](https://img.shields.io/badge/Discussion-discussions?logo=livechat&logoColor=FFBBFF&color=3399ff)](https://github.com/cctv18/oppo_oplus_realme_sm8550/discussions)

A faster and more convenient automation script for compiling universal kernels for OnePlus devices based on Snapdragon 8 Gen 2 (SM8550), Dimensity 9400e (MT6989), and Dimensity 8350 (MT6897).

## Why this project exists
- Several vendor source drops shipped without a complete configuration XML, making successful builds nearly impossible.
- The stock Bazel toolchain used by the vendor is unstable and inefficient. Builds often fail with obscure errors and there is very little public documentation, which is especially painful for newcomers.
- The vendor customised the F2FS implementation in their kernels. After flashing a GKI kernel you must wipe the data partition or the device fails to boot.
A faster and more convenient automation script for compiling universal kernels for OPPO / OnePlus / realme devices based on Snapdragon 8 Gen 2 (SM8550), Dimensity 9400e (MT6989), and Dimensity 8350 (MT6897).

## Why this project exists
- OPPO released incomplete source drops, leaving several kernels without a complete configuration XML and making successful builds nearly impossible.
- The stock Bazel toolchain used by OPPO is unstable and inefficient. Builds often fail with obscure errors and there is very little public documentation, which is especially painful for newcomers.
- OPPO customised the F2FS implementation in their kernels. After flashing a GKI kernel you must wipe the data partition or the device fails to boot.

## Project scope and roadmap
- Provide OKI (official sources) and GKI (Google Generic Kernel Image sources) build modes. OKI retains the vendor drivers and schedulers, while GKI offers greater compatibility (no need to match kernel patch levels exactly).
- Port the vendor F2FS sources to the GKI kernel so the data partition stays intact after flashing, just like the original OKI kernel.
- Build with LLVM/Clang 20 and exclude unnecessary vendor code to streamline the workflow. Compared with the original Bazel pipeline, the optimised flow cuts build time by roughly two thirds (from over one hour down to ~20 minutes) and produces cleaner logs.
- Fix upstream bugs and missing patches, and integrate the WindChill kernel scheduler (work in progress).
- Provide both GitHub Actions workflows and local shell scripts for compiling the kernels.

## Implemented
- [x] OnePlus SM8550 universal OKI kernel (based on the OnePlus 11 5.15.167 source; other devices on the same kernel version can be tested as needed).
- [x] OnePlus MT6989 universal OKI kernel (based on the OnePlus Ace 5 Racing Edition 6.1.115 source; devices on the same kernel version can be tested).
- [x] OnePlus MT6897 universal OKI kernel (based on the OnePlus Pad 6.1.128 source; devices on the same kernel version can be tested).
- [x] OPPO / OnePlus / realme SM8550 universal OKI kernel (based on the OnePlus 11 5.15.167 source; other devices on the same kernel version can be tested as needed).
- [x] OPPO / OnePlus / realme MT6989 universal OKI kernel (based on the OnePlus Ace 5 Racing Edition 6.1.115 source; devices on the same kernel version can be tested).
- [x] OPPO / OnePlus / realme MT6897 universal OKI kernel (based on the OnePlus Pad 6.1.128 source; devices on the same kernel version can be tested).
- [x] Optional SukiSU Ultra and KernelSU Next variants.
- [x] Integrated `ccache` and extensive pipeline optimisations. A cached build completes in ~6 minutes (the first run takes ~22 minutes to populate the cache). Changing kernel config options invalidates much of the cache and increases subsequent builds to ~10 minutes. Returning to the original configuration restores the ~6 minute build time. GitHub Actions may evict caches after long periods of inactivity; the pipeline automatically recreates them when needed.
- [x] O2 compilation optimisations for better runtime performance.
- [x] Optional manual / kprobe / syscall hook modes (with kprobe mode supporting SUS SU switching).
- [x] LZ4 1.10.0 & Zstd 1.5.7 performance patches (ported from [@ferstar](https://github.com/ferstar) by [@Xiaomichael](https://github.com/Xiaomichael)).
- [x] Optional BBR / Brutal and additional TCP congestion control algorithms.
- [x] Samsung SSG IO scheduler port (known issue: boot failure on OnePlus 12, pending investigation).
- [x] Additional networking configuration options to support ipset/iptables based tooling.
- [x] Support for the [Mountify](https://github.com/backslashxx/mountify) module.
- [x] Re:Kernel integration to reduce power consumption alongside tools like Freezer and NoActive.
- [x] Baseband Guard integration (by [@showdo](https://github.com/showdo)) to protect system partitions against malicious flashing tools.

## Planned
- [ ] Complete WindChill scheduler support for unofficial devices (work in progress).
- [ ] Bundle zram in-tree to remove the external `zram.ko` requirement (may no longer be necessary with the newer LZ4 & Zstd patches).
- [ ] LXC / Docker support.
- [ ] Nethunter driver port.
- [ ] Port newer OnePlus schedulers (schedhorizon, etc.).
- [ ] OnePlus 6.1 universal GKI kernel (port OnePlus F2FS sources to enable data-preserving flashes).
- [ ] OPPO / OnePlus / realme 6.1 universal GKI kernel (port OnePlus F2FS sources to enable data-preserving flashes).
- ~~Consolidate multi-version build scripts (skipped for usability and GitHub Actions input limits).~~
- More optimisations and feature ports to come.

## Acknowledgements
- SukiSU Ultra: [SukiSU-Ultra/SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra)
- susfs4ksu: [ShirkNeko/susfs4ksu](https://github.com/ShirkNeko/susfs4ksu)
- SukiSU kernel patches: [SukiSU-Ultra/SukiSU_patch](https://github.com/SukiSU-Ultra/SukiSU_patch)
- KernelSU Next maintained by pershoot: [pershoot/KernelSU-Next](https://github.com/pershoot/KernelSU-Next)
- KernelSU Next patches: [WildKernels/kernel_patches](https://github.com/WildKernels/kernel_patches)
- Baseband Guard module: [vc-teahouse/Baseband-guard](https://github.com/vc-teahouse/Baseband-guard)
- GKI kernel build script: (TBD)
- ~~Localized kernel build script (deprecated): [Suxiaoqinx/kernel_manifest_OnePlus_Sukisu_Ultra](https://github.com/Suxiaoqinx/kernel_manifest_OnePlus_Sukisu_Ultra)~~
- ~~WindChill kernel sources (incomplete, under revision): [HanKuCha/sched_ext](https://github.com/HanKuCha/sched_ext)~~
