# Kernel for the Xperia XZ3 801SO (akatsuki, LineageOS 22.2)

This branch (`lineage-22.2-xz3`) is the LineageOS `android_kernel_sony_sdm845`
`lineage-22.2` kernel (4.9) with a small set of changes on top, built for
LineageOS 22.2 based ROMs (LineageOS, PixelOS) on the akatsuki device.

> **Device scope.** This kernel targets the **SoftBank 801SO** (Japan), the
> only model its NFC setup has been tested on. Its akatsuki device tree
> describes the 801SO NFC hardware: a Sony **CXD224x** FeliCa/NFC controller
> with a Rohm **BD7602** regulator.
>
> * The global XZ3 models (**H8416, H9436, H9493**) use an NXP **PN553**
>   instead. With this kernel they **lose NFC**. Use the upstream LineageOS
>   kernel on those devices.
> * The other Japanese models (docomo **SO-01L**, au **SOV39**) most likely
>   use the same Sony controller, but they have not been tested.

## Changes compared to upstream lineage-22.2

* **801SO NFC**: the akatsuki generic device tree (appended DTBs and the
  dtbo overlays) includes Sony's `somc-tama-nfc_carillon.dtsi`
  (`felica@29`, `felica_ldo@1e`, `felica,pm-ops`) with the 801SO pin
  configuration (GPIO63 FELICA_INT_N pull-up, GPIO12 unused) instead of the
  PN553 node. The Sony Carillon driver is built in (`CONFIG_NFC_CARILLON=y`);
  the NXP PN553 and NQ drivers are disabled. The ROM still needs the 801SO
  NFC HAL and firmware in userspace.
* **Tap to wake**: a double tap on the dark screen wakes the device. The
  Atmel mXT640U touch controller is switched to Sony's AOD gesture
  configuration while the display is off, touch power is kept on and a T93
  double tap reports `KEY_WAKEUP`. Enabled by default; switch it off with
  `echo 0 > /sys/devices/virtual/input/lge_touch/tap_to_wake` (or the module
  parameter `atmel_mxt640u.tap_to_wake=0` on the kernel command line). The
  setting is read each time the display turns off. There is no proximity
  (pocket) check.
* **KernelSU-Next**: root via KernelSU-Next from its non-GKI `legacy`
  branch (commit `465490a2`, `v3.4.0-legacy` + 20 fixes, reported version
  33314), vendored in `drivers/kernelsu` with two build fixes for 4.9 and
  integrated with manual hooks (`CONFIG_KSU_MANUAL_HOOK`, see
  `include/linux/ksu_hook.h`) because its kprobe hooks are not supported
  below 5.10. The small kernel backports it needs (`path_umount()`,
  `seccomp.filter_count`, SELinux `selinux_cred()`/`selinux_inode()`, a
  visible `policy_rwlock`) are separate commits, so the build does not
  modify the source tree. Use the KernelSU Next manager app.
* **Module symbol CRCs**: backport of upstream `56067812d5b0` and
  `71810db27c1c` (32-bit symbol CRCs). With clang/lld and KASLR the old
  64-bit CRC entries were adjusted by the KASLR offset at boot, so external
  modules failed to load with "disagrees about version of symbol".
* **Config cleanup** (`tama_akatsuki_defconfig`): debug options with no
  user in a release build are off (`DEBUG_INFO`, `CGROUP_DEBUG`,
  `DYNAMIC_DEBUG`, `QCOM_RTB`, SDE/rotator event log defaults,
  `MMC_CMD_DEBUG`, `RMNET_DATA_DEBUG_PKT`, `VSERVICES_LOCK_DEBUG`,
  `REGMAP_ALLOW_WRITE_DEBUGFS`, `DM_DEBUG`). TCP BBR and the `fq` qdisc are
  available; cubic stays the default congestion control.

The kernel release string stays `4.9.337-perf+`, as in the ROM build.

## Building

GitHub Actions (`.github/workflows/build.yml`) builds every push to this
branch on `ubuntu-latest`:

1. AOSP prebuilt clang `r536225` (linux-x86, cached), the compiler the
   LineageOS 22.2 build uses for this kernel, with the same make flags as the
   LineageOS kernel build (`CC=clang LLVM=1 LLVM_IAS=1`, `ld.lld`,
   `CROSS_COMPILE`/`CROSS_COMPILE_ARM32` for the GNU prefixes).
2. `tama_akatsuki_defconfig`, targets `Image.gz-dtb` and `dtbs`;
   `dtbo.img` is created from the built overlays with AOSP `mkdtboimg.py`
   (`--page_size=4096`).
3. Checks: the `__kcrctab` sections have 4-byte entries, no relocations and
   match `Module.symvers`; every akatsuki DTB and overlay has `felica@29`
   and no `nxp,pn553`.
4. Artifacts: `Image.gz-dtb`, `dtbo.img`, the kernel config, `System.map`,
   `Module.symvers`, `SHA256SUMS` (and `vmlinux` separately).

Locally, with the same host packages (see the workflow) and clang unpacked to
`<clang dir>`:

```sh
MKDTBOIMG=/path/to/mkdtboimg.py .github/scripts/build.sh <clang dir> out dist
python3 .github/scripts/check_kcrctab.py dist/vmlinux dist/Module.symvers
python3 .github/scripts/check_dt.py dist/Image.gz-dtb dist/dtbo.img
```

The build timestamp is the commit time of `HEAD`, so a build of the same
commit with the same toolchain reports the same version string.

## Boot image

`scripts/mkbootimg.sh` puts the built kernel into an existing boot.img of the
ROM, replacing only the kernel and keeping header, command line and ramdisk:

```sh
scripts/mkbootimg.sh stock-boot.img dist/Image.gz-dtb boot-new.img \
	stock-dtbo.img dist/dtbo.img dtbo-new.img
```

The dtbo arguments are optional; without them only the boot image is
produced. With the stock dtbo the overlay adds back the (unused) PN553 node
and its GPIO63 pull-down setting, so use the dtbo.img from the same build
together with the kernel.
