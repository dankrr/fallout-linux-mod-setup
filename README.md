# Fallout 1in2 + RPU setup for Linux

Installer for the Steam versions of Fallout 1 and Fallout 2.

It asks whether to install:

1. Restoration Project Updated for Fallout 2
2. Fallout Et Tu / Fallout 1in2
3. Both

## Install

Arch, CachyOS, or SteamOS:

```bash
sudo pacman -S --needed curl unzip python wine
```

Debian or Ubuntu:

```bash
sudo apt install curl unzip python3 wine
```

Then:

```bash
git clone https://github.com/dankrr/fallout-linux-mod-setup.git
cd fallout-linux-mod-setup
./fallout-linux-mod-setup.sh
```

Fallout 2 is required for every option. Fallout 1 and Wine are only needed for Fallout Et Tu.

Launch the games once before running the script. Clean installs are recommended.

## What it changes

- Fallout Et Tu replaces Fallout 1's normal Steam install. The original folder is backed up with a `.vanilla-DATE` suffix.
- RPU is installed into Fallout 2.
- The required `ddraw.dll` launch option is added only to the selected Steam entries.

Both mods need a new game. Do not use old vanilla saves.

## Non-interactive use

Skip the menu with `INSTALL_MODE`:

```bash
INSTALL_MODE=rpu ./fallout-linux-mod-setup.sh
INSTALL_MODE=ettu ./fallout-linux-mod-setup.sh
INSTALL_MODE=both ./fallout-linux-mod-setup.sh
```

Custom paths and download URLs can also be passed as environment variables:

```bash
FALLOUT1_DIR="/path/to/Fallout" \
FALLOUT2_DIR="/path/to/Fallout 2" \
FO1IN2_URL="https://example.com/Fallout1in2.zip" \
RPU_URL="https://example.com/rpu.zip" \
./fallout-linux-mod-setup.sh
```

Steam Deck note: leave the per-game frame limit disabled if the mouse feels sluggish.

Unofficial community script. You need legitimate copies of the games. Code is MIT licensed; downloaded mods keep their own licenses.
