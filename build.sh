#!/bin/sh
# Build the mainline kernel, DTB and modules for dream2lte into ./build and
# ./out/modules.
#
#   BUSYBOX=/path/to/static/aarch64/busybox ./build.sh
#
# Environment:
#   BUSYBOX    static aarch64 busybox for the initramfs (required)
#   INITRAMFS  boot (default) or test
#   DEV=1      add config/dev.fragment (verbose log, bring-up init wrapper)
set -e
cd "$(dirname "$0")"
TOP=$PWD
CROSS=${CROSS_COMPILE:-aarch64-linux-gnu-}
M="make -C linux O=$TOP/build ARCH=arm64 CROSS_COMPILE=$CROSS LOCALVERSION= -j$(nproc)"

[ -d linux ] || tools/get-linux.sh
if [ -z "$BUSYBOX" ] || [ ! -f "$BUSYBOX" ]; then
	echo "set BUSYBOX to a static aarch64 busybox" >&2
	exit 1
fi

# initramfs helpers
[ tools/rbt -nt tools/rbt.c ] ||
	${CROSS}gcc -Os -static -nostdlib -fno-stack-protector -o tools/rbt tools/rbt.c
[ tools/devmem -nt tools/devmem.c ] ||
	${CROSS}gcc -O2 -static -o tools/devmem tools/devmem.c

V=${INITRAMFS:-boot}
mkdir -p build
{
	echo "dir /bin 755 0 0"
	echo "dir /dev 755 0 0"
	echo "dir /proc 755 0 0"
	echo "dir /sys 755 0 0"
	echo "dir /tmp 755 0 0"
	echo "dir /mnt 755 0 0"
	echo "nod /dev/console 600 0 0 c 5 1"
	echo "nod /dev/kmsg 644 0 0 c 1 11"
	echo "file /bin/busybox $(realpath "$BUSYBOX") 755 0 0"
	echo "file /bin/rbt $TOP/tools/rbt 755 0 0"
	echo "file /bin/devmem $TOP/tools/devmem 755 0 0"
	echo "file /init $TOP/initramfs/$V/init 755 0 0"
} > initramfs/list.txt.new
cmp -s initramfs/list.txt.new initramfs/list.txt || mv initramfs/list.txt.new initramfs/list.txt
rm -f initramfs/list.txt.new
touch initramfs/$V/init

FRAGS="config/dream2lte.fragment"
[ "${DEV:-0}" = 1 ] && FRAGS="$FRAGS config/dev.fragment"
echo "CONFIG_INITRAMFS_SOURCE=\"$TOP/initramfs/list.txt\"" > build/local.fragment.new
cmp -s build/local.fragment.new build/local.fragment ||
	mv build/local.fragment.new build/local.fragment
rm -f build/local.fragment.new
if [ ! -f build/.config ] || [ "$(cat build/.frags 2>/dev/null)" != "$FRAGS" ] ||
   [ -n "$(find $FRAGS build/local.fragment -newer build/.config)" ]; then
	$M defconfig
	linux/scripts/kconfig/merge_config.sh -m -O build build/.config \
		$FRAGS build/local.fragment >/dev/null
	$M olddefconfig
	echo "$FRAGS" > build/.frags
fi

$M Image modules exynos/exynos8895-dream2lte.dtb
rm -rf out/modules
$M INSTALL_MOD_PATH=$TOP/out/modules INSTALL_MOD_STRIP=1 modules_install >/dev/null
ls -l build/arch/arm64/boot/Image
du -sh out/modules
