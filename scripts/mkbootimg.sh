#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# Put a kernel built from this tree into an existing LineageOS/PixelOS
# boot.img for akatsuki. Only the kernel (Image.gz-dtb) is replaced: header
# version, command line, offsets, OS version/patch level and ramdisk are
# taken from the original with AOSP unpack_bootimg/mkbootimg, and the AVB
# hash footer is re-added with the original partition size, name, salt and
# properties. Optionally adds the same kind of footer to a dtbo.img built
# from this tree, taking the parameters from the original dtbo.img.
#
# usage: mkbootimg.sh <orig boot.img> <Image.gz-dtb> <out boot.img>
#                     [<orig dtbo.img> <new dtbo.img> <out dtbo.img>]
#
# The AOSP tools are downloaded (pinned) into $AOSP_TOOLS, default
# ~/.cache/akatsuki-aosp-tools. Needs python3, curl, base64 and sha256sum.
set -euo pipefail

AOSP=https://android.googlesource.com/platform
MKBOOTIMG_REF=android-15.0.0_r1
AVB_REF=android-15.0.0_r36
TOOLS=${AOSP_TOOLS:-$HOME/.cache/akatsuki-aosp-tools}

if [ $# -ne 3 ] && [ $# -ne 6 ]; then
	echo "usage: $0 <orig boot.img> <Image.gz-dtb> <out boot.img>" \
		"[<orig dtbo.img> <new dtbo.img> <out dtbo.img>]" >&2
	exit 2
fi

fetch() { # <project path> <ref> <file> <sha256>
	local dest=$TOOLS/$3

	if ! echo "$4  $dest" | sha256sum -c --status - 2>/dev/null; then
		mkdir -p "$(dirname "$dest")"
		curl -fsSL --retry 3 "$AOSP/$1/+/refs/tags/$2/$3?format=TEXT" |
			base64 -d > "$dest"
		echo "$4  $dest" | sha256sum -c --quiet -
	fi
}

fetch system/tools/mkbootimg $MKBOOTIMG_REF mkbootimg.py \
	37d84b3d162e0bc62e36c1f4e1c63c85ea0caa9f29be023eb2f8efe006ad948c
fetch system/tools/mkbootimg $MKBOOTIMG_REF unpack_bootimg.py \
	a9d260978a63bd06a24b6347e7dee8a28ff96639793caea15dff6aa491316308
fetch system/tools/mkbootimg $MKBOOTIMG_REF gki/generate_gki_certificate.py \
	6ee0b2e3c3323ae8fccf326bf9a526451eac977005efabf7d129b3063bcfb945
fetch external/avb $AVB_REF avbtool.py \
	ff418b18d3b3b48dea2201124f62fc469c677bba93ca134829673254357ae17b

orig=$1 kernel=$2 out=$3
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT

# arguments for avbtool add_hash_footer taken from an existing image
footer_args() {
	local info
	info=$(python3 "$TOOLS/avbtool.py" info_image --image "$1")
	echo --partition_size
	echo "$info" | awk -F': *' '/^Image size/ { print $2 + 0; exit }'
	echo --partition_name
	echo "$info" | awk -F': *' '/Partition Name/ { print $2; exit }'
	echo --salt
	echo "$info" | awk -F': *' '/Salt/ { print $2; exit }'
	echo "$info" | sed -n "s/^ *Prop: \(.*\) -> '\(.*\)'$/--prop\n\1:\2/p"
}

python3 "$TOOLS/unpack_bootimg.py" --boot_img "$orig" --out "$t/unpacked" \
	--format mkbootimg -0 > "$t/args"

# same mkbootimg arguments, only --kernel replaced
python3 - "$t/args" "$kernel" "$t/args.new" <<'EOF'
import sys

args = open(sys.argv[1], 'rb').read().split(b'\0')
if args and args[-1] == b'':
    args.pop()
args[args.index(b'--kernel') + 1] = sys.argv[2].encode()
open(sys.argv[3], 'wb').write(b'\0'.join(args))
EOF

xargs -0 python3 "$TOOLS/mkbootimg.py" --output "$t/boot.img" < "$t/args.new"
mapfile -t fa < <(footer_args "$orig")
python3 "$TOOLS/avbtool.py" add_hash_footer --image "$t/boot.img" "${fa[@]}"
cp "$t/boot.img" "$out"
echo "boot: $out"

if [ $# -eq 6 ]; then
	cp "$5" "$t/dtbo.img"
	mapfile -t fd < <(footer_args "$4")
	python3 "$TOOLS/avbtool.py" add_hash_footer --image "$t/dtbo.img" \
		"${fd[@]}"
	cp "$t/dtbo.img" "$6"
	echo "dtbo: $6"
fi
