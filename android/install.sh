#!/bin/bash
# Install the Android-on-mainline test setup on the phone over adb, from TWRP
# or from a running test boot (adbd is root there), then reboot into it:
#
#  - /metadata/mainline/init.rc: the phone's own /system/etc/init/hw/init.rc
#    plus android/init/mainline.rc (loaded through androidboot.init_rc)
#  - /metadata/mainline/vendor/lib64: the graphics stack (android/gfx/build.sh),
#    overlaid onto /vendor/lib64 at early-init
#  - BOOT: out/android/boot-android.img (android/build.sh), verified
#
#   android/install.sh [--no-flash] [--no-reboot]
#
# SYSTEM, VENDOR and USERDATA are not written. To go back, write the stock
# boot image to BOOT (sda7) from TWRP.
set -e
cd "$(dirname "$0")/.."
FLASH=1 REBOOT=1
for a in "$@"; do
	case $a in
	--no-flash) FLASH=0 ;;
	--no-reboot) REBOOT=0 ;;
	*) echo "usage: $0 [--no-flash] [--no-reboot]" >&2; exit 1 ;;
	esac
done
IMG=out/android/boot-android.img
STAGE=out/android-gfx/stage
[ $FLASH = 0 ] || [ -f $IMG ] || { echo "$IMG missing (android/build.sh)" >&2; exit 1; }
[ -d $STAGE/lib64 ] || { echo "$STAGE missing (android/gfx/build.sh)" >&2; exit 1; }

case $(adb get-state 2>/dev/null) in
recovery) MODE=twrp ;;
device) MODE=android ;;
*) echo "phone not reachable over adb" >&2; exit 1 ;;
esac
ph() { adb shell "$@"; }
if [ $MODE = android ] && [ "$(ph id -u | tr -d '\r')" != 0 ]; then
	echo "adbd is not root (only the test boot runs it as root; use TWRP)" >&2; exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if [ $MODE = twrp ]; then
	M=/tmp/mainline-meta
	ph "mkdir -p $M /tmp/mainline-sys; mount | grep -q ' $M ' || mount /dev/block/by-name/HIDDEN $M"
	ph "mount | grep -q ' /tmp/mainline-sys ' || mount -o ro /dev/block/by-name/SYSTEM /tmp/mainline-sys"
	SYSRC=/tmp/mainline-sys/system/etc/init/hw/init.rc
	PUSHTMP=/tmp
else
	M=/metadata
	SYSRC=/system/etc/init/hw/init.rc
	PUSHTMP=/data/local/tmp
fi

# init.rc: the stock one plus ours
adb pull $SYSRC "$TMP/init.rc" >/dev/null
grep -q '^# ---- mainline test boot' "$TMP/init.rc" && { echo "$SYSRC already has our part?" >&2; exit 1; }
cat android/init/mainline.rc >> "$TMP/init.rc"
ph "mkdir -p $M/mainline/vendor"
adb push "$TMP/init.rc" $M/mainline/init.rc >/dev/null
tar -C $STAGE -cf "$TMP/gfx.tar" lib64
adb push "$TMP/gfx.tar" $PUSHTMP/mainline-gfx.tar >/dev/null
ph "cd $M/mainline/vendor && rm -rf lib64 && tar -xf $PUSHTMP/mainline-gfx.tar && rm $PUSHTMP/mainline-gfx.tar &&
    chown -R 0:0 lib64 && chmod -R u=rwX,go=rX lib64 $M/mainline/init.rc &&
    chcon -R u:object_r:vendor_file:s0 lib64 && chcon u:object_r:metadata_file:s0 $M/mainline/init.rc && sync"
echo "installed init.rc and $(du -sh $STAGE/lib64 | cut -f1) of libraries to /metadata/mainline"
if [ $MODE = twrp ]; then
	ph "cd /; umount $M; umount /tmp/mainline-sys" || true
fi

if [ $FLASH = 1 ]; then
	SIZE=$(stat -c %s $IMG)
	SUM=$(sha256sum $IMG | cut -d' ' -f1)
	adb push $IMG $PUSHTMP/boot-android.img >/dev/null
	ph "dd if=$PUSHTMP/boot-android.img of=/dev/block/by-name/BOOT bs=1M 2>/dev/null && sync && rm $PUSHTMP/boot-android.img"
	GOT=$(ph "head -c $SIZE /dev/block/by-name/BOOT | sha256sum" | cut -d' ' -f1)
	[ "$GOT" = "$SUM" ] || { echo "BOOT verify FAILED" >&2; exit 1; }
	echo "flashed and verified $IMG"
fi

if [ $REBOOT = 1 ]; then
	# "normal" sets S-Boot's reboot reason; a plain reboot keeps the shim's
	# DEV_RECOVERY preset and ends up in TWRP
	if [ $MODE = twrp ]; then adb reboot; else ph "reboot normal"; fi
fi
