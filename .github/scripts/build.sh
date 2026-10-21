#!/bin/bash
# Build the akatsuki kernel the way the LineageOS build system does
# (TARGET_KERNEL_CONFIG := tama_akatsuki_defconfig, clang + LLVM binutils,
# Image.gz-dtb with appended DTBs, separate dtbo.img).
#
# usage: build.sh <clang dir> <out dir> <dist dir>
# Needs: GNU binutils prefixes aarch64-linux-gnu- and arm-linux-gnueabi- in
# PATH (only used for --gcc-toolchain and the compat vDSO), dtc, python3 and
# mkdtboimg.py in $MKDTBOIMG (default: <out dir>/../mkdtboimg.py).
set -euo pipefail

CLANG=$(cd "$1" && pwd)
OUT=$(mkdir -p "$2" && cd "$2" && pwd)
DIST=$(mkdir -p "$3" && cd "$3" && pwd)
SRC=$(cd "$(dirname "$0")/../.." && pwd)
DEFCONFIG=${DEFCONFIG:-tama_akatsuki_defconfig}
MKDTBOIMG=${MKDTBOIMG:-$OUT/../mkdtboimg.py}

export PATH="$CLANG/bin:$PATH"
export LD_LIBRARY_PATH="$CLANG/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export KBUILD_BUILD_USER=${KBUILD_BUILD_USER:-nobody}
export KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST:-android-build}
export KBUILD_BUILD_VERSION=${KBUILD_BUILD_VERSION:-1}
# reproducible version string: commit time of the source tree
if [ -z "${KBUILD_BUILD_TIMESTAMP:-}" ]; then
	KBUILD_BUILD_TIMESTAMP=$(LC_ALL=C date -u -d "@$(git -C "$SRC" log -1 --format=%ct)")
	export KBUILD_BUILD_TIMESTAMP
fi

MAKE=(make -C "$SRC" O="$OUT" ARCH=arm64 -j"$(nproc)"
	CC=clang CLANG_TRIPLE=aarch64-linux-gnu-
	CROSS_COMPILE=aarch64-linux-gnu-
	CROSS_COMPILE_ARM32=arm-linux-gnueabi-
	CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
	HOSTCC=clang HOSTCXX=clang++ LD=ld.lld AR=llvm-ar
	LLVM=1 LLVM_IAS=1 DTC_EXT="$(command -v dtc)"
	HOSTCFLAGS="-I/usr/include -I/usr/include/x86_64-linux-gnu"
	HOSTLDFLAGS="-L/usr/lib/x86_64-linux-gnu -L/usr/lib64 -fuse-ld=lld")

"${MAKE[@]}" "$DEFCONFIG"
"${MAKE[@]}" Image.gz-dtb dtbs

boot="$OUT/arch/arm64/boot"
mapfile -t dtbos < <(find "$boot/dts" -name '*.dtbo' | LC_ALL=C sort)
python3 "$MKDTBOIMG" create "$DIST/dtbo.img" --page_size=4096 "${dtbos[@]}"

cp "$boot/Image.gz-dtb" "$OUT/vmlinux" "$OUT/System.map" \
	"$OUT/Module.symvers" "$DIST/"
cp "$OUT/.config" "$DIST/kernel.config"
cat "$OUT/include/config/kernel.release" > "$DIST/kernel.release"
strings "$OUT/vmlinux" | grep -m1 '^Linux version ' > "$DIST/version.txt" || true
echo "$(cat "$DIST/kernel.release"): ${#dtbos[@]} overlays in dtbo.img"
