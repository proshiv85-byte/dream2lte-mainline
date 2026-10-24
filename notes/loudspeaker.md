# Loudspeaker (MAX98506 on ABOX UAIF4): state and findings

Status (2026-10-24): **silent on mainline**, works on the vendor 4.4 kernel.
Headphones work on mainline (see the ABOX/CS47L93 patches). The speaker code
is committed as WIP (patches "add a Maxim MAX98506 speaker amplifier driver",
"exynos8895-abox: play on UAIF0 or UAIF4", "dream2lte: add the loudspeaker",
"exynos8895-dream2lte: add the speaker amplifier").

## Hardware

- Amplifier: Maxim MAX98506, revision 0x80, I2C address 0x31 on HSI2C11
  (USI3 @ 0x104a0000, `USI_MODE_I2C`, pins gpd3-0/1). Mainline bus number
  `i2c-0`, vendor 4.4 `i2c-3`.
- I2S: ABOX UAIF4, pins gph0-5, gph0-6, gph0-7, function 2, pull-down
  (vendor `aud-spk-bus`). ABOX is the clock master (UAIF CTRL0 bit 2 = 1).
- Vendor DT also has `max98506-ctl` = gpa2-2 as an input without pull. On
  mainline it had the internal pull-down on and read low; without the pull it
  reads high (something on the board pulls it up). Releasing it changed
  nothing audible; what the pin is (amp IRQ?) is unknown.
- Vendor amp DT: `maxim,sysclk = <12288000>`, `maxim,spk-gain = <0x14>`,
  `maxim,registers-of-amp = <0x1f 0x00 0x21 0xc0 0x2d 0x14 0x2f 0x00>`.

## How the speaker works on 4.4 (ARMtix)

`/etc/init.d/armtix-audio` (4.4 branch) runs `armtix-audio-route speaker` and
then overrides: `ABOX ERAP info DSM On`=0, `ABOX UAIF SPK4`=SIFS0,
`ABOX UAIF SPK0`=RESERVED (only one UAIF may read SIFS0), `Speaker Gain`=10,
`ALC Enable`=on. PulseAudio sink `speaker` = `hw:CARD=Exynos8895Mader,DEV=0`.

**Volume gotcha:** at 30% PulseAudio volume the speaker is inaudible; at 70%
it plays. Test the speaker at 70% or more.

It still plays on 4.4 with the ABOX ASRC switched off
(`amixer -c0 cset name="ABOX SPUS ASRC0" Off`), so the ASRC is not needed.

## Measured on 4.4 while the speaker plays (70%, 440 Hz tone)

Amplifier (read over I2C, not the driver's cache):

    1a=40 1b=80 1f=00 20=42 21=c0 22=22 23=20 24=00 2a=f0 2c=d9 2d=0a 2e=02
    2f=00 30=2a 34=12 35=01 36=93 37=00 38=80 3a=f8   status 02=00 03=00 06=40

(0x1a bits 3:0, MDLL multiplier, read back 0 on both kernels: write-only; the
vendor cache says 0x46.)

ABOX SFR (vendor regmap debugfs): ROUTE_CTRL0 0x40 = 0x00010000 (SPK4 =
SIFS0), ROUTE_CTRL1 0x44 = 0x0000c980, SPUS_CTRL0 0x200 = 0x15333333 (ASRC
on), SPUS_CTRL1 0x204 = 0x00370009, UAIF4 CTRL0 0x540 = 0x01000005, CTRL1
0x544 = 0x0984f000.

Clocks (4.4 `/sys/kernel/debug/clk/<name>/clk_rate`, safe to read one by one):
DOUT_CLK_ABOX_AUDIF 6144000, DOUT_CLK_ABOX_UAIF4 1536000 (enabled),
GATE_UAIF4 enabled.

## Mainline state while "playing" to the speaker

- All amp registers 0x00-0x3f equal to the 4.4 values above (after setting
  0x2d to 0x0a; the driver uses 0x6a, (L+R)/2). No fault flags.
- ABOX: route 0x00010000, UAIF4 0x01000005 / 0x0984f000, CMU MUX_UAIF4
  (0x13e01014) 0, DIV_UAIF4 (0x13e01838) 3, gate 0x13e02034 = 0x00200000
  (same as UAIF0), AUDIF divider 191 (6.144 MHz).
- RDMA0 drains at exactly 48 kHz (170.7 ms per 32 KB period) with UAIF4 as the
  only reader, so UAIF4 does pull the samples.
- gph0 CON (0x13e60000) = 0x22222220, PUD 0x5555 (pull-down).

## Tried on mainline, no sound

- amp DAC input left only (0x2d = 0x0a, as 4.4) instead of (L+R)/2
- amp global enable off/on while BCLK runs; writing 0x1a = 0x46 (MDLL x8)
  with the amp off, then enabling
- UAIF0 disabled (only UAIF4 enabled, as on 4.4)
- ROUTE_CTRL1 0x44 = 0xc980 as 4.4
- gpa2-2 pull-down off
- volume 70% (PulseAudio) and amp gain 10 (+3 dB), limiter on

## Ideas for next time

1. Full register diff: 4.4 has no `/dev/mem` and its regmap debugfs only
   shows cached registers. Build a small 4.4 module (source in
   `~/work/aosp-kernel/src`, vermagic must match `4.4.194-gbaef4348-dirty`)
   that dumps ABOX SFR 0x13e50000-0x13e5ffff, CMU_ABOX 0x13e00000-0x13e03fff,
   the ABOX pinctrl 0x13e60000, gpa2 and the PMU while the speaker plays;
   then diff against mainline (`devmem`, `/root/devmem`).
2. Check what else the vendor driver does at speaker start: the ABOX ERAP /
   DSM IPCs (even with DSM off), `abox_uaif` set_fmt/hw_params for UAIF4 in
   `~/work/aosp-kernel/src/sound/soc/samsung/abox/abox.c`, and the
   `dream_madera.c` dai link ops for UAIF4.
3. Amp feedback: 4.4 routes UAIF4 capture (amp VMON/IMON on DOUT) to NSRC3;
   maybe the amp or UAIF4 needs the capture side running.
4. Check that the amp actually sees BCLK/LRCLK: the 4.4 DT pin list for the
   amp bus has 3 pins; confirm which is BCLK/LRCLK/SD and that the amp's
   DOUT (feedback) pin isn't fighting a pin we drive.

## Test commands (mainline)

    amixer -c dream2lte cset name=Output Speaker     # or Headphones
    U=$(id -u armtix); E="XDG_RUNTIME_DIR=/run/user/$U"
    S=alsa_output.platform-sound.stereo-fallback
    su armtix -c "$E pactl set-sink-volume $S 70%"
    su armtix -c "$E PULSE_SINK=$S speaker-test -D pulse -t sine -f 440 -c 2 -l 1"
    i2ctransfer -f -y 0 w1@0x31 0x38 r1              # amp global enable

On 4.4 the amp is `i2ctransfer -f -y 3 ... @0x31`; boot it by flashing
`backup/sda7-armtix-k37.img` to sda7 (the rootfs is shared). **Don't** read
`/sys/kernel/debug/clk/clk_summary` on 4.4: it panics (reads a powered-off
block).

Vendor dumps from 4.4 (headphone route) are in `notes/vendor-4.4-dumps/`.
