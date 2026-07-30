# Fallout 1in2 + RPU setup for Linux

One script for the Steam versions of Fallout 1 and Fallout 2.

- Fallout's normal Steam button launches [Fallout Et Tu / Fallout 1in2](https://github.com/rotators/Fo1in2).
- Fallout 2's normal Steam button launches [Restoration Project Updated](https://github.com/BGforgeNet/Fallout2_Restoration_Project).

Both games must already be installed through Steam. The script downloads the mods; it does not include any game files.

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

Launch both games once before running the script. Clean installs are recommended.

## What it does

- Finds both games, including games in extra Steam libraries.
- Backs up Fallout 1, then replaces it with Fallout 1in2.
- Installs RPU into Fallout 2.
- Sets the `ddraw.dll` override needed by both mods.

The Fallout 1 backup is left next to the game folder with a `.vanilla-DATE` suffix.

## Restore

For Fallout 1, close Steam, remove the modded folder, and rename the `.vanilla-*` backup to the original folder name.

For Fallout 2, use **Verify integrity of game files** in Steam. A clean reinstall may be needed to remove leftover mod files.

Both mods need a new game. Do not use old vanilla saves.

## Overrides

Custom paths or download URLs can be passed as environment variables:

```bash
FALLOUT1_DIR="/path/to/Fallout" \
FALLOUT2_DIR="/path/to/Fallout 2" \
FO1IN2_URL="https://example.com/Fallout1in2.zip" \
RPU_URL="https://example.com/rpu.zip" \
./fallout-linux-mod-setup.sh
```

Unofficial community script. You need legitimate copies of both games. Code is MIT licensed; downloaded mods keep their own licenses.
