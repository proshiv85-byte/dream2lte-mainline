#!/bin/sh
# Fetch the mainline console log (pstore) from TWRP into out/$1-*.txt
cd "$(dirname "$0")/.."
adb shell 'mount | grep -q pstore || mount -t pstore pstore /sys/fs/pstore'
adb shell 'cat /sys/fs/pstore/pmsg-ramoops-0' > out/$1-console.txt 2>/dev/null
adb shell 'cat /sys/fs/pstore/dmesg-ramoops-0 2>/dev/null' > out/$1-dmesg.txt
wc -c out/$1-*.txt
