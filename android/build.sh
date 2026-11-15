#!/bin/bash
# Build the boot image for booting AOSP (the dream2lte AOSP 17 ROM) on the
# mainline kernel. See android/README.md.
#
#   android/build.sh <stock AOSP boot.img>    -> out/android/boot-android.img
#
# The stock boot image (from the phone's BOOT partition) provides the AOSP
# ramdisk (first stage init) and the Samsung DTBH S-Boot needs.
# Environment: CROSS_COMPILE (default aarch64-linux-gnu-),
#              DEV_RECOVERY (default 1: resets of the new kernel go to TWRP).
set -e
cd "$(dirname "$0")/.."
TOP=$PWD
STOCK=${1:?usage: android/build.sh <stock AOSP boot.img>}
STOCK=$(realpath "$STOCK")
CROSS=${CROSS_COMPILE:-aarch64-linux-gnu-}
B=$TOP/build-android
O=$TOP/out/android
mkdir -p "$B" "$O"
M="make -C linux O=$B ARCH=arm64 CROSS_COMPILE=$CROSS LOCALVERSION= -j$(nproc)"

[ -f out/firmware/exynos8895_acpm_dvfs.fw ] || {
	echo "out/firmware/exynos8895_acpm_dvfs.fw missing (tools/get-firmware.sh)" >&2; exit 1; }
[ -f initramfs/list.txt ] || { echo "run ./build.sh once first (initramfs/list.txt)" >&2; exit 1; }

# kernel: the ARMtix config plus the Android fragment, built into build-android/
sed "s|@FIRMWARE_DIR@|$TOP/out/firmware|" android/kernel.fragment > "$B/android.fragment"
echo "CONFIG_INITRAMFS_SOURCE=\"$TOP/initramfs/list.txt\"" > "$B/local.fragment"
if [ ! -f "$B/.config" ] || [ -n "$(find android/kernel.fragment config/dream2lte.fragment -newer "$B/.config")" ]; then
	$M defconfig >/dev/null
	linux/scripts/kconfig/merge_config.sh -m -O "$B" "$B/.config" config/dream2lte.fragment \
		"$B/local.fragment" "$B/android.fragment" >/dev/null
	$M olddefconfig >/dev/null
fi
$M Image exynos/exynos8895-dream2lte.dtb

# split the stock boot image (header v0 + Samsung dt_size)
python3 - "$STOCK" "$O" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
assert d[:8] == b'ANDROID!', 'not a boot image'
k, _, r, _, _, _, _, page, dt, _ = struct.unpack('<10I', d[8:48])
al = lambda n: (n + page - 1) // page * page
off = page + al(k)
open(sys.argv[2] + '/stock-ramdisk.gz', 'wb').write(d[off:off + r])
off += al(r)
open(sys.argv[2] + '/stock-dt.img', 'wb').write(d[off:off + dt])
PY

# ramdisk: stock first stage init, our fstab (by-name links, no USERDATA,
# CACHE or MISC, EFS read-only) and debug props. The cpio archive is edited
# in place, so the stock device nodes stay without root rights.
python3 android/ramdisk/repack.py "$O/stock-ramdisk.gz" "$O/ramdisk.gz" \
	fstab.samsungexynos8895=android/ramdisk/fstab.samsungexynos8895 \
	adb_debug.prop=android/ramdisk/adb_debug.prop force_debuggable=/dev/null

# DTB: rename the UFS node, so the vendor fstab's /dev/block/platform/11120000.ufs
# paths (USERDATA, CACHE, MISC) don't exist; reboot-to-bootloader goes to TWRP
# (keeps the ramoops log) instead of download mode
dtc -q -I dtb -O dts -o "$O/android.dts" "$B/arch/arm64/boot/dts/exynos/exynos8895-dream2lte.dtb"
sed -i 's/\bufs@11120000 {/ufshc@11120000 {/; s/mode-bootloader = <0x1234567d>;/mode-bootloader = <0x12345674>;/' "$O/android.dts"
grep -q 'ufshc@11120000 {' "$O/android.dts" || { echo "UFS node rename failed" >&2; exit 1; }
dtc -q -I dts -O dtb -o "$O/android.dtb" "$O/android.dts"

# shim + boot image (the shim is built in a copy, shim/ stays ARMtix's)
rm -rf "$O/shim" && cp -r shim "$O/shim" && rm -f "$O"/shim/shim.{elf,bin,dtb} "$O/shim/Image.lz4"
make -s -C "$O/shim" DEV_RECOVERY=${DEV_RECOVERY:-1} IMAGE="$B/arch/arm64/boot/Image" DTB="$O/android.dtb"
tools/mkbootimg.py --kernel "$O/shim/shim.bin" --ramdisk "$O/ramdisk.gz" --dt "$O/stock-dt.img" \
	-o "$O/boot-android.img"
