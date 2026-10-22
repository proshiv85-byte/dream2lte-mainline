#!/bin/sh
# Pack shim+kernel, install the modules and flash BOOT (sda7) on a phone
# running Linux and reachable over ssh (PHONE=host, default 172.16.42.1),
# reboot into it and wait until ssh answers again.
# DEV_RECOVERY=1 (default) makes every reset of the new kernel boot TWRP.
set -e
cd "$(dirname "$0")/.."
PH=${PH:-ssh root@${PHONE:-172.16.42.1}}
make -s -C shim DEV_RECOVERY=${DEV_RECOVERY:-1}
tools/mkbootimg.py --kernel shim/shim.bin --dt backup/dt-4.4.img -o out/boot-mainline.img
SUM=$(sha256sum out/boot-mainline.img | cut -d' ' -f1)
SIZE=$(stat -c %s out/boot-mainline.img)
KREL=$(ls out/modules/lib/modules/)
tar -C out/modules/lib -c modules/$KREL | $PH "rm -rf /usr/lib/modules/$KREL && tar -C /usr/lib -x && depmod $KREL && echo modules $KREL installed"
for f in out/firmware/*.fw; do
	[ -f "$f" ] && $PH "mkdir -p /usr/lib/firmware && cat > /usr/lib/firmware/${f##*/}" < "$f" && echo "firmware ${f##*/} installed"
done
$PH "cat > /tmp/b.img" < out/boot-mainline.img
$PH "dd if=/tmp/b.img of=/dev/sda7 bs=1M conv=fsync 2>/dev/null; [ \$(head -c $SIZE /dev/sda7 | sha256sum | cut -c1-64) = $SUM ] && echo verified"
[ "${NOREBOOT:-0}" = 1 ] && exit 0
$PH "(sleep 1; reboot) >/dev/null 2>&1 &"
sleep 15
for i in $(seq 1 60); do
	if $PH true 2>/dev/null; then echo "back after $((15 + i * 3))s: $($PH uname -r)"; exit 0; fi
	sleep 3
done
echo "phone did not come back over ssh"; exit 1
