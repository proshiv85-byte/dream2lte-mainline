#!/bin/sh
# Pack shim+kernel into boot.img and flash it to BOOT (sda7) from TWRP over
# adb, then reboot into it.
set -e
cd "$(dirname "$0")/.."
make -s -C shim DEV_RECOVERY=${DEV_RECOVERY:-1}
tools/mkbootimg.py --kernel shim/shim.bin --dt backup/dt-4.4.img -o out/boot-mainline.img
SUM=$(sha256sum out/boot-mainline.img | cut -d' ' -f1)
SIZE=$(stat -c %s out/boot-mainline.img)
if adb get-state 2>/dev/null | grep -q recovery; then
	adb push out/boot-mainline.img /tmp/b.img >/dev/null
	adb shell "dd if=/tmp/b.img of=/dev/block/sda7 bs=1M && sync"
	GOT=$(adb shell "head -c $SIZE /dev/block/sda7 | sha256sum" | cut -d' ' -f1)
	[ "$GOT" = "$SUM" ] || { echo "verify FAILED"; exit 1; }
	echo "flashed + verified ($SUM)"
	adb reboot
else
	echo "phone not in TWRP"; exit 1
fi
