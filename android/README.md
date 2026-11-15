# AOSP on the mainline kernel (test setup)

> [!WARNING]
> **Experimental.** This boots the dream2lte AOSP 17 ROM (made for Samsung's
> 4.4 kernel) on this mainline kernel for testing. `/data` is a tmpfs, so
> nothing persists and every boot is a first boot. Keep TWRP and the stock
> AOSP boot image around.

Nothing in SYSTEM or VENDOR is changed, and no AOSP rebuild is needed. The
test setup consists of:

- **a boot image** (`build.sh`): the kernel with Android options
  ([`kernel.fragment`](kernel.fragment) on top of `config/dream2lte.fragment`,
  built into `build-android/`), the stock AOSP ramdisk with a first-stage
  fstab and debug props from [`ramdisk/`](ramdisk), and a test DTB.
- **files on `/metadata`** (HIDDEN partition, `install.sh`):
  - `/metadata/mainline/init.rc`: the phone's own `init.rc` plus
    [`init/mainline.rc`](init/mainline.rc), loaded instead of the stock one
    through `androidboot.init_rc`
  - `/metadata/mainline/vendor/lib64`: the graphics stack
    (`gfx/build.sh`), overlaid onto `/vendor/lib64` at early-init

## Safety

The phone's userdata (file-based encryption with keys in Samsung's TEE, which
mainline can't reach) is never mounted:

- The test DTB renames the UFS node (`ufshc@11120000`), so the vendor fstab's
  `/dev/block/platform/11120000.ufs/by-name/...` paths for USERDATA, CACHE
  and MISC don't exist. Android can't mount or format userdata, and can't
  write a "wipe data" command to MISC for TWRP to act on.
- The first-stage fstab mounts SYSTEM, VENDOR and METADATA (HIDDEN) through
  `/dev/block/by-name`, and EFS read-only.
- `/data` is a tmpfs, mounted at `late-fs`.
- `DEV_RECOVERY=1` (the default) makes every reset of the new kernel land in
  TWRP. Reboot-to-bootloader also goes to TWRP (test DTB), so the ramoops
  log survives (`tools/getlog.sh`).

## Building

Needs what the ARMtix kernel build needs (run `./build.sh` once, and
`tools/get-firmware.sh` for the ACPM plugin, which is built into this kernel),
plus the stock AOSP boot image, for example the backup of BOOT from TWRP:

```sh
android/build.sh backup/boot-aosp17.img     # -> out/android/boot-android.img
android/gfx/build.sh                        # -> out/android-gfx/stage
```

`gfx/build.sh` downloads the NDK, libdrm, Mesa, minigbm, drm_hwcomposer and a
few AOSP headers (pinned versions) into `out/android-gfx`, and pulls the
phone's liblog, libcutils, libsync, libhardware, libnativewindow and libz over
adb to link against (once).

## Installing

From TWRP, or from a running test boot (adbd runs as root there):

```sh
android/install.sh            # /metadata files, BOOT, reboot
```

To go back, write the stock boot image to BOOT (`sda7`) from TWRP. The files
in `/metadata/mainline` are only used by the test kernel and can stay.

On a running test boot, `adb shell reboot normal` reboots into it again
(a plain `adb reboot` ends up in TWRP because of `DEV_RECOVERY`), and
`adb shell setprop debug.mainline.reboot recovery` reboots without root.

## What it takes

- **Kernel options**: binder, SELinux (permissive through `androidboot.selinux`),
  netfilter and policy routing for netd, `PF_KEY` (netd's BPF map RCU sync),
  tracing and BPF events for the platform BPF programs, PSI for lmkd, overlayfs,
  and exynos-drm, panfrost and the ACPM PMIC access built in (Android doesn't
  load this kernel's modules). The cmdline is built in and carries the
  `androidboot.*` values S-Boot would pass.
- **memfd for shared memory**: libcutils only uses memfd when the kernel
  answers ashmem ioctls on memfds (Android common kernels do), otherwise it
  wants `/dev/ashmem`, which mainline removed. `CONFIG_MEMFD_ASHMEM_SHIM`
  (`mm/memfd-ashmem-shim.c`) does that; `sys.use_memfd=true` is set in
  `mainline.rc`.
- **Touch**: stmfts now ends each report with `input_mt_sync_frame()`.
  Without `BTN_TOUCH`, Android took every contact for hovering.
- **Graphics** (`gfx/`), built with the NDK, linking only C-ABI libraries:
  - Mesa panfrost EGL/GLES (`ro.hardware.egl=mesa`), with the G71 fix
  - minigbm gralloc0 (`ro.hardware.gralloc=minigbm`, loaded by the vendor's
    passthrough allocator/mapper 2.0): [`minigbm.patch`](gfx/minigbm.patch)
    adds an `exynos` backend. This DECON has no IOMMU, so exynos-drm
    buffers come from the 256 MB CMA pool; only the client composition target
    (`HW_FB`) is allocated there, everything else comes from the dma-buf
    system heap. It also opens card nodes first and gives up DRM master.
  - drm_hwcomposer's HWC2 module (`ro.hardware.hwcomposer=drm`, loaded by
    the vendor's composer 2.1 service), from its last revision with the HWC2
    frontend. [`drm-hwcomposer.patch`](gfx/drm-hwcomposer.patch) fixes the
    HWC2 two-call protocol in `getColorModes`, `getReleaseFences` and
    `getChangedCompositionTypes`; statsd reporters are no-ops and the few
    libui types are shimmed ([`shim/`](gfx/shim)).
- **lmkd** uses PSI (`ro.lmk.use_psi=true`, the ROM turns it off for 4.4).
- **No suspend**: system suspend panics in a driver's suspend callback, so
  `mainline.rc` holds a wakelock.

## Not working (yet)

Persistent `/data`, suspend, 32-bit apps' graphics (only 64-bit libraries),
camera, GPS, modem, the Samsung TEE (keymaster, fingerprint), Wi-Fi and
Bluetooth (their modules aren't loaded), GPU DVFS, BTF (the dmabuf BPF
iterator; the Image would not fit the 40 MB BOOT partition uncompressed).
