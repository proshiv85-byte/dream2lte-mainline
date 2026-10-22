# dream2lte-mainline

Mainline Linux for the **Samsung Galaxy S8+ (SM-G955F, "dream2lte", Exynos 8895)**,
made for the [ARMtix (Artix Linux) port](https://github.com/proshiv85-byte/armtix-on-s8plus).

> [!WARNING]
> **This is in early development.** It boots and is usable over USB, but a lot of
> hardware is not supported yet (see below). Expect breakage, and keep a working
> boot image and TWRP at hand. Nothing here is upstream yet.

The kernel is current mainline (7.3-rc) plus the patches in [`patches/`](patches/).
It boots the ARMtix root filesystem from the internal UFS (`sda27`, USERDATA).

## Status

| Hardware | State |
|---|---|
| CPUs (8 cores), RAM (3.5 GB usable) | works |
| CPU frequency scaling | works: A53 455–1690 MHz, Mongoose 741–2314 MHz, via the APM firmware (needs the DVFS plugin, see below) |
| GPU (Mali-G71 MP20) | works: `panfrost` + Mesa (OpenGL ES / OpenGL), DVFS 260–546 MHz, sway renders on it |
| WiFi (BCM4361) | works: scan and connect, 2.4 + 5 GHz, via `brcmfmac` (needs the Samsung firmware, see below) |
| Thermal | works: CPU, GPU and ISP sensors, CPUs throttle at 80 °C (big) / 90 °C (little), shutdown at 115 °C |
| Display | works: DRM driver (`exynosdrm`), GPU buffers flipped straight to the panel at 60 Hz; no brightness or screen off yet |
| Touchscreen (STM FTS8) | works |
| Buttons | works |
| UFS storage | works (HS-G3, 2 lanes), verified reads/writes |
| USB device mode | works, high-speed (RNDIS/NCM/... via configfs) |
| Battery fuel gauge | works (MAX77865 FG, `max17042` driver) |
| Charging | charger state reported; charges at the bootloader's settings |
| RTC | works (S2MPS17, through the APM firmware) |
| Reboot, reboot to recovery | works; hardware watchdog available |
| Power off | wired up, not tested yet |
| Bluetooth, audio, GPU, cameras, modem, USB 3 / host, suspend | not supported yet |

## What's in the patches

- `exynos8895-dream2lte.dts` (based on the upstream Galaxy S8 one), with the
  firmware's secure memory carve-outs reserved
- UFS: Exynos8895 host and PHY support for `ufs-exynos` / `phy-samsung-ufs`
  (+ a `get_upmcrs` hook in the UFS core: this host reports power mode
  results in its UniPro block)
- USB: Exynos8895 USB DRD PHY (`phy-exynos5-usbdrd`) and DWC3 glue
- PMIC access: the APM firmware drives the SPEEDY bus to the PMIC itself
  (voltage changes), so PMIC registers are read and written through it
  (`i2c-exynos-acpm-pmic`), as on the vendor kernel. Accessing SPEEDY
  directly from Linux while the firmware does DVFS hangs the phone. The
  direct SPEEDY driver (`i2c-exynos-speedy`) is still in the patches but
  unused.
- S2MPS17 PMIC: touchscreen regulators and RTC
- display: Exynos8895 DECON-F driver for `exynosdrm`. It keeps the display
  path set up by the bootloader (command mode panel, DSC, DSI) and only
  flips buffers; with the name `exynos`, Mesa scans out panfrost-rendered
  buffers directly
- watchdog: Exynos8895 variant of `s3c2410_wdt`; the APM firmware is
  stopped before a reset like on the vendor kernel
- MAX77865: charger state and USB routing of the MUIC
- `stmfts`: FTS8 variant (`st,stmfts8`)
- ACPM (the APM power-management firmware): loading of the firmware plugins
  the 8895 expects from the kernel, DVFS clocks for `clk-acpm`, mailbox and
  OPP tables, so `cpufreq-dt` drives the CPU clusters
- PCIe: Exynos8895 host driver (`pcie-exynos8895`, DesignWare based) for the
  WiFi chip; its outbound window is only 4 MiB, so the chip's 4 MiB RAM BAR
  is clipped and the register BAR moved above it on the bus
- `brcmfmac`: BCM4361 support (PCIe, Samsung's firmware)
- GPU: Mali-G71 node for `panfrost`, clocked through ACPM like the CPUs
- `exynos8895_tmu`: temperature sensors of the 8895 TMU, thermal zones with
  cpufreq cooling

The vendor kernel (Samsung 4.4) was used as the reference for the hardware
sequences; the code was written for mainline with an AI assistant (Claude),
see the `Assisted-by` tags. No `Signed-off-by` is added: these are not
submissions.

## Booting

S-Boot loads the boot.img kernel at `0x80080000` and only accepts boot images
with a Samsung DTBH. A mainline Image must sit on a 2 MiB boundary, so the
boot image carries a tiny shim ([`shim/shim.S`](shim/shim.S)) that

1. enables the display controller's trigger so the framebuffer keeps refreshing,
2. copies the DTB and the Image to aligned addresses and jumps to the kernel,
3. with `DEV_RECOVERY=1`, presets the Samsung reboot reason to "recovery" so a
   crash or reset of the new kernel lands in TWRP instead of boot looping.

The DTB passed by S-Boot is ignored, the kernel command line is built in.
A small initramfs mounts `/dev/sda27` and switches to `/sbin/init`.

## Building

Needs an `aarch64-linux-gnu-` cross toolchain, `dtc`, python3 and a static
aarch64 busybox (e.g. from the Alpine `busybox-static` package).

```sh
tools/get-linux.sh                     # mainline at patches/BASE + patches
BUSYBOX=/path/to/busybox.static ./build.sh
tools/extract-dtbh.py your-current-boot.img backup/dt-4.4.img
DEV_RECOVERY=0 make -C shim
tools/mkbootimg.py --kernel shim/shim.bin --dt backup/dt-4.4.img -o out/boot-mainline.img
```

Install `out/modules/lib/modules/<version>` to `/usr/lib/modules/` on the phone.

### CPU frequency firmware

CPU clocks and voltages are set by the APM firmware, which only accepts
requests after the kernel has loaded its DVFS plugin,
`exynos8895_acpm_dvfs.fw`. The plugin is Samsung's and is not included here.
It ships (as `firmware/exynos8895_acpm_dvfs.fw.ihex`) in Samsung's kernel
source releases for the S8/S8+ (opensource.samsung.com):

```sh
tools/get-firmware.sh /path/to/samsung/kernel/source   # -> out/firmware/
```

Install it as `/usr/lib/firmware/exynos8895_acpm_dvfs.fw` (`tools/flash-ssh.sh`
does that). Without it the CPUs stay at the bootloader's clocks, about half
of their top speed.

### WiFi firmware

The WiFi firmware is Samsung's and comes from the phone's vendor partition
(`/vendor/etc/wifi`). Which files fit depends on the WiFi module; the vendor
kernel prints its choice (`dhd_bus_download_firmware: firmware path=...`).
For the SM-G955F used here it is the B0 firmware with the `r02j` NVRAM:

```sh
cd /usr/lib/firmware/brcm
cp /vendor/etc/wifi/bcmdhd_sta.bin_b0    brcmfmac4361-pcie.bin
cp /vendor/etc/wifi/nvram.txt_r02j_b0    brcmfmac4361-pcie.txt
cp /vendor/etc/wifi/bcmdhd_clm.blob      brcmfmac4361-pcie.clm_blob
```

The `_b2` firmware loads but never starts on this module.

## Flashing

**Back up your BOOT partition first** (`dd if=/dev/block/sda7 of=...` in TWRP).

- from TWRP: `tools/flash-twrp.sh` (adb)
- from a running Linux on the phone: `tools/flash-ssh.sh` (also installs the
  modules)

To go back, write your old boot image to `sda7` from TWRP.

## Rootfs notes (ARMtix)

ARMtix was made for the 4.4 kernel. To run the same rootfs on both kernels:

- [`rootfs/usbnet`](rootfs/usbnet): the `usbnet` service uses the Samsung
  `android_usb` flow on 4.4 and plain configfs on mainline
- sway: on mainline the screen is the DRM output `Unknown-1` (simpledrm)
  instead of `FBDEV-fb0`; [`armtix-sway`](rootfs/armtix-sway) writes the right
  name to `~/.config/sway/output.conf`, which the sway config includes. It
  also picks the GPU driver: Mesa `panfrost` on mainline (no
  `GALLIUM_DRIVER=llvmpipe`, no libhybris), libhybris on 4.4
- PulseAudio: the speaker sink has to be optional (`.nofail`) while there is no
  sound driver, otherwise waybar's volume module hangs
- [`rootfs/init-wrapper`](rootfs/init-wrapper): bring-up helper used with
  `DEV=1` builds; collects logs and returns to TWRP if USB networking does not
  come up

## Development

`DEV=1 ./build.sh` builds with a verbose log and the init wrapper. Kernel
messages survive resets in ramoops at `0x92000000`, the same place as the
vendor kernel's pstore, so TWRP shows the last mainline log as
`/sys/fs/pstore/pmsg-ramoops-0` (`tools/getlog.sh`). `tools/i2c`, `tools/devmem`
and `tools/gpioget` are small static helpers for poking hardware on the phone.

## License

The kernel patches are GPL-2.0, like the kernel. Everything else here is
GPL-2.0 as well.
