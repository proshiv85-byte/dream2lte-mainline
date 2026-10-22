#!/bin/sh
# Extract the ACPM DVFS plugin (loaded into the APM by exynos-acpm) from a
# Samsung Exynos8895 kernel source tree into out/firmware/.
#
#   tools/get-firmware.sh /path/to/samsung/kernel/source
set -e
cd "$(dirname "$0")/.."
SRC=${1:-$HOME/work/aosp-kernel/src}
mkdir -p out/firmware
${CROSS_COMPILE:-aarch64-linux-gnu-}objcopy -I ihex -O binary \
	"$SRC/firmware/exynos8895_acpm_dvfs.fw.ihex" out/firmware/exynos8895_acpm_dvfs.fw
sha256sum out/firmware/exynos8895_acpm_dvfs.fw
