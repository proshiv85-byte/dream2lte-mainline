# What's next for the dream2lte mainline kernel

The things still missing or incomplete, roughly in the order I'd do them.
"Effort" is a guess: **S** = an evening, **M** = a day or two, **L** = many
days, **XL** = a project of its own. See the [README](README.md) for what
already works.

## Daily use

| # | Item | Why it matters | Effort | Notes |
|---|---|---|---|---|
| 1 | ~~Display brightness and screen off~~ | **Done.** Brightness through the panel's AOR on the bootloader's gamma; the panel sleeps when the screen is off. | — | Follow-up: calibrated gamma curves (vendor computes them from the panel's MTP) for the full brightness range. |
| 2 | ~~Charger driver (MAX77865)~~ | **Done.** Charger type detection, 0.5 / 1.5 / 2.1 A, battery temperature limits, charger watchdog. | — | Follow-ups: 9 V adaptive fast charging (AFC, through the MUIC), interrupts instead of the 5 s poll, keeping the charger watchdog fed during suspend. |
| 3 | **Vibration motor** | Haptic feedback, notifications. | S–M | Likely the MAX77865 haptic block (PWM) or a GPIO-driven motor; check the vendor DT. |
| 4 | **Notification LED** | Small, easy win. | S | Check the vendor DT for which chip drives it. |
| 5 | **Bluetooth (BCM4361)** | Headphones, keyboards. Same chip as WiFi, BT side is on a UART. | M | `hci_bcm` over serdev + the Samsung `.hcd` patch firmware; needs the UART node, BT_REG_ON / wake GPIOs. |
| 6 | **Power off** | Wired up but never tested. | S | Just test `poweroff` and check it really cuts power (no drain). |
| 7 | **Suspend (s2idle, then deep sleep)** | The big one for battery life. | L–XL | Needs the screen off (#1), power domains (#9), wakeup sources (power key, RTC, USB), and the APM firmware's sleep path. s2idle first, it doesn't need the firmware. |

## Speed and power

| # | Item | Why it matters | Effort | Notes |
|---|---|---|---|---|
| 8 | **microSD above 7 MHz** | Reads at 3.3 MB/s; a normal card does 20+ MB/s. | M–L | Already ruled out: sample phases, clock source/divider, I/O voltage, drive strength, clock gating, FIFO quirk. Next: vendor dw_mmc init registers and tuning, the high-speed switch (CMD6), pin pulls. **Writes are off-limits on the current card**: write testing needs a spare card. |
| 9 | **Power domains (G3D first)** | GPU and other blocks stay powered even when idle. | M | G3D PMU config 0x164840e0 / status 0x164840e4; vendor also turns PLL_G3D on in CMU_G3D. Mainline `exynos-pm-domains` may work with a new compatible. |
| 10 | ~~Hardware video decode (MFC)~~ | **Done** (H.264, HEVC, VP8, VP9 via V4L2; Firefox H.264/HEVC with the patched libavcodec). | — | Follow-ups: VP9 in Firefox (its bundled decoder has no V4L2), the encoder (untested). |
| 11 | **GPU AFBC warning** | Mesa prints "Tile size is smaller than AFBC superblock"; harmless so far. | S | Check Mesa's panfrost AFBC handling for G71 / disable AFBC for scanout. |

## Bigger hardware

| # | Item | Why it matters | Effort | Notes |
|---|---|---|---|---|
| 12 | **USB host / OTG, USB 3** | Plug in keyboards, drives; faster USB networking. | M–L | Needs the MUIC (#2) to detect OTG cables and switch the DWC3 role; USB 3 needs the SuperSpeed PHY. |
| 13 | **Audio** | Speaker, earpiece, headphone jack, mics. | XL | Cirrus Logic codec + Samsung ABOX DSP, no mainline support for ABOX. Hardest of the useful items. |
| 14 | **Sensors** (accelerometer, gyro, light, proximity) | Auto-rotate, auto-brightness. | L–XL | They sit behind a sensor hub MCU with Samsung's own protocol. |
| 15 | **NFC** | Low value on Linux. | M | Samsung S3NRN82; mainline `s3fwrn5` might cover it. |
| 16 | **Modem, cameras, fingerprint, iris** | — | XL | Proprietary firmware/protocols or secure-world only. Probably not worth it. |

## Known glitches

- **"CPU1 failed to come online"**: seen once in about 16 boots; not reproduced since.
- **WiFi**: hotspot / P2P and power saving not tried.
- **Display**: no plane blend-mode property; full power-up from off is missing, which suspend will need.

## Housekeeping

- Run checkpatch on all patches and write dt-binding docs, before any of this goes upstream.
- Remove the dev-loop leftovers from the phone at the end: the autorecovery flag and `/root/mainline/init-wrapper`.
- The original 4.4 kernel is backed up at `backup/sda7-armtix-k37.img` if you want to go back.

## Suggested order

6 → 5 → 7. Brightness/screen-off and the charger are done; power off is a
quick check, Bluetooth is the next useful feature, and suspend is the
biggest battery win.
