ARMtix Linux (Artix, OpenRC) for Samsung Galaxy S8+ Exynos - SM-G955F "dream2lte"
Mainline Linux kernel, desktop image (sway, Mali GPU with Mesa panfrost)
===============================================================================

!!! Flashing this zip ERASES the phone's internal storage (USERDATA) !!!
    Back up first (TWRP -> Backup). The SD card is not touched.

Requirements
  - SM-G955F with an unlocked bootloader and TWRP.
  - VENDOR must still hold Samsung's vendor files (stock Android 9, ROMs based
    on it, or an AOSP build for dream2lte using the same blobs): the WiFi,
    Bluetooth, audio and video decoder firmware is copied from it during
    installation. The CPU frequency plugin is taken from the Samsung kernel in
    BOOT (or from TWRP's kernel). This zip contains no Samsung blobs.

Install
  1. TWRP -> Install -> select this zip -> swipe.  (takes a few minutes)
  2. TWRP -> Reboot -> System.

First boot
  - sway starts automatically (user armtix, password armtix; root: armtix).
    Change both with `passwd` / `sudo passwd root`.
  - Bottom bar: apps, on-screen keyboard, rotate, close window, power menu.
    Look: `armtix-theme` lists the themes (default: dusk), `armtix-theme
    minimal` switches (themes in ~/.config/armtix-themes).
    WiFi: "Wi-Fi" in the app menu. Power key: power menu. Volume keys: volume.
  - USB cable to a Linux PC: network, phone = 172.16.42.1
    (ssh armtix@172.16.42.1).

What works
  Touch, display (brightness, screen off), GPU (panfrost), WiFi, Bluetooth,
  headphone audio, hardware video decoding (also in Firefox, H.264/HEVC),
  CPU frequency scaling and idle, thermal, charging, battery, USB networking
  and USB host (OTG), microSD (slow, read at ~3 MB/s).

Known limitations
  - No calls/SMS, camera, GPS, fingerprint. Loudspeaker, earpiece and
    microphones are silent.
  - The screen does not turn off by itself (`armtix-screen off`).

Back to Android: restore your TWRP backup (at least BOOT + DATA).
