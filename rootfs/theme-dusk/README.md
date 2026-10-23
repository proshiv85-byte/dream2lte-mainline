# dusk theme for ARMtix

Plum night, peach sun, lavender accents. A theme for `armtix-theme`: copy
this folder to `~/.config/armtix-themes/dusk`, generate the wallpapers, then
`armtix-theme dusk` (`armtix-theme minimal` switches back).

```sh
python3 wallpaper.py 1440 2960 sway/wallpaper.png
python3 wallpaper.py 2960 1440 sway/wallpaper-landscape.png
```

Needs numpy and Pillow. Also used with it:

- `bashrc` → `~/.bashrc` (prompt in the theme colors)
- `../armtix-battery` (battery on mainline too) and `../armtix-brightness`
  (brightness button in waybar, remembered across reboots; add
  `exec armtix-brightness restore` to the sway config) → `/usr/local/bin`
- `../90-backlight.rules` → `/etc/udev/rules.d` (brightness writable by the
  `video` group)
- `../armtix-power-menu` → `/usr/local/bin`: power menu that fits the portrait
  screen (fuzzel), with screen off; the power key turns the screen back on
- btop: `color_theme = "dusk"` in `~/.config/btop/btop.conf`
