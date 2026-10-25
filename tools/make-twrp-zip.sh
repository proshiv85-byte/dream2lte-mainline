#!/usr/bin/env bash
# Build a TWRP-flashable ARMtix zip with the mainline kernel:
#
#   tools/make-twrp-zip.sh [ssh-target]
#
# The rootfs is the RUNNING phone's (ssh-target, default root@172.16.42.1),
# sanitized with ARMtix's tools/rootfs_export.py (ARTIXP, default
# ~/work/artixp): no WiFi passwords, SSH host keys, logs, caches, personal
# data; passwords reset to "armtix". The home directory is ARMtix's curated
# overlay with the mainline fixes (sway output name, dusk theme). Samsung
# firmware is left out; the installer (tools/twrp/update-binary) copies it
# from the phone's own partitions.
#
# Output: out/ARMtix-dream2lte-mainline-<date>.zip
set -euo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TOP"
TARGET=${1:-root@172.16.42.1}
ARTIXP=${ARTIXP:-$HOME/work/artixp}
BUSYBOX=${BUSYBOX:-$ARTIXP/work/initramfs/dl/ex/bin/busybox.static}
DATE=$(date +%Y%m%d)
OUT=$TOP/out/ARMtix-dream2lte-mainline-$DATE.zip
STAGE=$TOP/out/twrp-zip
CROSS=${CROSS_COMPILE:-aarch64-linux-gnu-}
SSH=(ssh -o ConnectTimeout=10 "$TARGET")

[ -f "$ARTIXP/tools/rootfs_export.py" ] || { echo "no $ARTIXP/tools/rootfs_export.py (set ARTIXP)" >&2; exit 1; }
OVERLAY_HOME=$ARTIXP/work/rootfs/overlay/home/armtix
[ -d "$OVERLAY_HOME" ] || OVERLAY_HOME=$ARTIXP/rootfs/overlay/home/armtix
[ -d "$OVERLAY_HOME" ] || { echo "no ARMtix overlay home in $ARTIXP" >&2; exit 1; }

# Samsung firmware on the phone's rootfs: never in the zip
BLOBS="
usr/lib/firmware/brcm/brcmfmac4361-pcie.bin
usr/lib/firmware/brcm/brcmfmac4361-pcie.txt
usr/lib/firmware/brcm/brcmfmac4361-pcie.clm_blob
usr/lib/firmware/brcm/BCM4347B0.hcd
usr/lib/firmware/calliope_sram.bin
usr/lib/firmware/calliope_dram.bin
usr/lib/firmware/calliope_iva.bin
usr/lib/firmware/abox/SoundBoosterParam.bin
usr/lib/firmware/abox/dsm.bin
usr/lib/firmware/abox/dsm_tune.bin
usr/lib/firmware/abox/APBargeIn_AUDIO_SLSI.bin
usr/lib/firmware/abox/APBiBF_AUDIO_SLSI.bin
usr/lib/firmware/abox/AP_AUDIO_SLSI.bin
usr/lib/firmware/s5p-mfc-v11.fw
usr/lib/firmware/exynos8895_acpm_dvfs.fw
"
# development leftovers: my SD card's read-only rule (the image gets a
# generic one), a cpuidle test
DEV_FILES="
etc/udev/rules.d/10-microsd.rules
etc/modprobe.d/cpuidle-test.conf
"

echo ">> kernel"
BUSYBOX=$BUSYBOX INITRAMFS=boot DEV=0 ./build.sh > build.log 2>&1 || { tail -20 build.log; exit 1; }
make -s -C shim DEV_RECOVERY=0
KVER=$(cat build/include/config/kernel.release)
KBUILD=$(sed -n 's/.*UTS_VERSION "\(#[0-9]*\).*/\1/p' build/include/generated/utsversion.h)

rm -rf "$STAGE"; mkdir -p "$STAGE/META-INF/com/google/android" "$STAGE/armtix"
A=$STAGE/armtix
tools/mkbootimg.py --kernel shim/shim.bin --dt backup/dt-4.4.img -o "$A/boot.img"
cp tools/twrp/update-binary "$STAGE/META-INF/com/google/android/update-binary"
echo "# dummy - the installer is update-binary" > "$STAGE/META-INF/com/google/android/updater-script"
cp tools/twrp/README.txt "$STAGE/README.txt"
cp "$BUSYBOX" "$A/busybox"
${CROSS}gcc -O2 -static -Wall -o "$A/kfw" tools/twrp/kfw.c
printf 'BUILD_DATE=%s\nKERNEL_VERSION="%s %s"\n' "$DATE" "$KVER" "$KBUILD" > "$A/build-info"

echo ">> modules + mainline files"
M=$STAGE/mainline-root
mkdir -p "$M/usr/lib" "$M/etc/udev/rules.d"
cp -a out/modules/lib/modules "$M/usr/lib/"
cat > "$M/etc/udev/rules.d/60-microsd.rules" <<'EOF'
# The microSD card runs at a low clock on mainline for now: keep requests
# short enough for the dw_mmc read timeout.
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="mmcblk[0-9]", ATTR{queue/max_sectors_kb}="256"
EOF
tar -C "$M" --owner=0 --group=0 --numeric-owner -cf - . | xz -T0 -6 > "$A/mainline.tar.xz"

echo ">> home (ARMtix overlay + mainline fixes)"
H=$STAGE/home
cp -a "$OVERLAY_HOME" "$H"
# sway: the real output name (DSI-1) comes from output.conf, written by
# armtix-sway; restore the brightness at login
sed -i 's|^set \$out FBDEV-fb0$|&\n# real output name (DSI-1 on mainline), written by armtix-sway\ninclude ~/.config/sway/output.conf|' "$H/.config/sway/config"
sed -i 's|^exec armtix-screen apply$|exec armtix-brightness restore\n&|' "$H/.config/sway/config"
grep -q '^include ~/.config/sway/output.conf' "$H/.config/sway/config" || { echo "sway config: output.conf include not added" >&2; exit 1; }
# dusk theme, applied the way armtix-theme does
T=$H/.config/armtix-themes/dusk
mkdir -p "$T"
(cd rootfs/theme-dusk && find . -type f ! -name README.md ! -name bashrc ! -name wallpaper.py |
	cpio -pdm --quiet "$T")
python3 rootfs/theme-dusk/wallpaper.py 1440 2960 "$T/sway/wallpaper.png" >/dev/null
python3 rootfs/theme-dusk/wallpaper.py 2960 1440 "$T/sway/wallpaper-landscape.png" >/dev/null
(cd "$T" && find . -type f ! -name osk.conf | cpio -pdm --quiet "$H/.config")
cp -f "$T/osk.conf" "$H/.config/armtix-osk.conf"
echo dusk > "$H/.config/armtix-themes/current"
cp rootfs/theme-dusk/bashrc "$H/.bashrc"
mkdir -p "$H/.config/btop"
printf 'color_theme = "dusk"\n' > "$H/.config/btop/btop.conf"

echo ">> file capabilities"
"${SSH[@]}" 'getcap -r /usr 2>/dev/null' | awk '{print $1, $2}' > "$A/caps.txt"
cat "$A/caps.txt"

echo ">> rootfs (streamed from $TARGET, sanitized, xz)"
{
	printf '%s\n' $BLOBS $DEV_FILES
	# the phone's modules: the zip has the ones matching its kernel
	"${SSH[@]}" "find /usr/lib/modules/$KVER 2>/dev/null" | sed 's|^/||'
} > "$STAGE/drop-list.txt"
"${SSH[@]}" 'sync; tar -C / --one-file-system --numeric-owner -cpf - \
	--exclude=./swapfile --exclude=./vendor --exclude="./var/cache/pacman/pkg/*" \
	--exclude=./home/armtix/.config/mozilla --exclude=./home/armtix/.cache \
	--exclude="./tmp/*" --exclude="./var/tmp/*" --exclude="./mnt/system/*" . 2>/dev/null; true' |
	python3 "$ARTIXP/tools/rootfs_export.py" --shadow-hash "$(openssl passwd -6 armtix)" \
		--drop-list "$STAGE/drop-list.txt" --home "$H" |
	xz -T0 -6 > "$A/rootfs.tar.xz"

echo ">> checks"
# nothing from the drop list may be left, and no other Samsung firmware
xz -dc "$A/rootfs.tar.xz" | tar -t > "$STAGE/rootfs.list"
if grep -xF -f <(sed 's|^|./|' "$STAGE/drop-list.txt") "$STAGE/rootfs.list"; then
	echo "dropped files still in the rootfs" >&2; exit 1
fi
grep -E '^\./home/armtix/\.config/sway/(config|wallpaper\.png)$' "$STAGE/rootfs.list"
(cd "$A" && sha256sum boot.img rootfs.tar.xz mainline.tar.xz > sha256sums)
ls -la "$A"

echo ">> zip"
rm -f "$OUT"
(cd "$STAGE" && zip -r -0 -q "$OUT" META-INF armtix README.txt)
ls -la "$OUT"; (cd "$(dirname "$OUT")" && sha256sum "$(basename "$OUT")") | tee "$OUT.sha256"
