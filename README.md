# Fallout Linux Mod Setup

A rerunnable Bash installer for Steam copies of the classic Fallout games on Linux.

It configures the normal Steam entries so that:

- **Fallout** launches **Fallout Et Tu / Fallout 1in2** using assets from both Fallout 1 and Fallout 2.
- **Fallout 2** launches **Fallout 2 Restoration Project Updated (RPU)**.

The installer downloads the mod releases directly from their upstream projects. It does **not** contain or redistribute Fallout game files or mod assets.

## What the installer changes

1. Finds Steam and any additional Steam library folders.
2. Confirms that Fallout 1 (`38400`) and Fallout 2 (`38410`) are installed.
3. Copies the required clean data files before modifying either installation.
4. Downloads the latest Fallout 1in2 release.
5. Moves the original Fallout 1 directory to a timestamped backup.
6. Builds Fallout 1in2 in Fallout 1's normal Steam directory and maps it to `falloutlauncher.exe`.
7. Downloads and installs the latest Linux RPU release into Fallout 2's normal Steam directory.
8. Adds the required native `ddraw.dll` launch override to both games in Steam.
9. Backs up every edited `localconfig.vdf` before changing it.

## Requirements

- Linux
- Steam, either native or Flatpak
- Fallout 1 and Fallout 2 installed through Steam
- Bash
- `curl`
- `unzip`
- Python 3
- Wine

Install the dependencies on Arch Linux, CachyOS, or SteamOS:

```bash
sudo pacman -S --needed curl unzip python wine
```

On Debian or Ubuntu:

```bash
sudo apt install curl unzip python3 wine
```

On Fedora:

```bash
sudo dnf install curl unzip python3 wine
```

## Before running

1. Install both games through Steam.
2. Launch each game once, then close it.
3. Use clean vanilla installations. Steam's **Verify integrity of game files** is recommended if either directory was previously modded.
4. Close any tools that may be using either game directory.

The installer shuts Steam down before editing its configuration.

## Installation

Clone the repository and run the installer:

```bash
git clone https://github.com/dankrr/fallout-linux-mod-setup.git
cd fallout-linux-mod-setup
./fallout-linux-mod-setup.sh
```

You can also download the script directly from the repository and run it with Bash.

After installation, restart Steam and use the normal **Play** button for each game.

- Fallout launches Fallout Et Tu.
- Fallout 2 launches Restoration Project Updated.

Start a new game in both mods. Existing vanilla saves are not supported.

## Custom game paths

Steam libraries are detected automatically. Paths can be supplied explicitly when needed:

```bash
FALLOUT1_DIR="/path/to/Fallout" \
FALLOUT2_DIR="/path/to/Fallout 2" \
./fallout-linux-mod-setup.sh
```

## Custom download URLs

The default Fallout 1in2 URL and automatically selected RPU release can be overridden:

```bash
FO1IN2_URL="https://example.invalid/Fallout1in2.zip" \
RPU_URL="https://example.invalid/rpu.zip" \
./fallout-linux-mod-setup.sh
```

This is mainly useful for testing a specific release.

## Backups and recovery

### Fallout 1

The original Fallout 1 directory is moved alongside the installation using a name similar to:

```text
Fallout.vanilla-20260730-183000
```

If the installer fails after moving the directory, it attempts to restore the original automatically.

To restore Fallout 1 manually:

1. Exit Steam completely.
2. Delete or rename the modified Fallout directory.
3. Rename the timestamped `.vanilla-*` directory back to the original Fallout directory name.
4. Remove the custom Steam launch option for Fallout if it is no longer needed.

Steam file verification also restores the original Fallout installation, but it may not remove the timestamped backup.

### Fallout 2

RPU modifies Fallout 2 in place. To return to vanilla Fallout 2:

1. Preserve any saves you care about.
2. Use Steam's **Verify integrity of game files**.
3. Remove files left behind by the mod if verification does not remove them, or reinstall into a clean directory.
4. Remove the custom Steam launch option if it is no longer needed.

## Steam launch option

The installer adds this to both games:

```text
WINEDLLOVERRIDES="ddraw.dll=n,b" %command%
```

If Steam configuration cannot be located, the installer prints a warning and asks you to add it manually under:

**Properties → General → Launch Options**

## Rerunning the installer

The script intentionally refuses to install over a setup that it previously modified. This prevents accidental nesting or corruption.

For a clean rerun:

1. Restore or Steam-verify Fallout 1.
2. Steam-verify or reinstall Fallout 2 into a clean directory.
3. Run the script again.

## Upstream projects

- Fallout Et Tu / Fallout 1in2: `rotators/Fo1in2`
- Fallout 2 Restoration Project Updated: `BGforgeNet/Fallout2_Restoration_Project`

Please report mod-specific gameplay bugs to the relevant upstream project. Issues involving detection, backups, downloads, or Steam integration belong in this repository.

## Disclaimer

This is an unofficial community installer and is not affiliated with Bethesda Softworks, Interplay Entertainment, Steam, Valve, the Fallout 1in2 team, or the Restoration Project Updated team. Fallout names and trademarks belong to their respective owners. You must own legitimate copies of both games.

## License

The installer and repository documentation are released under the MIT License. Downloaded third-party projects retain their own licenses and terms.
