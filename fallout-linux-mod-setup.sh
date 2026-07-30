#!/usr/bin/env bash
set -Eeuo pipefail

# Fallout Linux Steam mod setup
# - Fallout 1 (Steam app 38400) becomes Fallout Et Tu / Fallout 1in2.
# - Fallout 2 (Steam app 38410) receives Restoration Project Updated (RPU).
#
# Requirements: curl, unzip, python3, Wine, and both games installed through Steam.
# Optional directory overrides:
#   FALLOUT1_DIR="/path/to/Fallout" FALLOUT2_DIR="/path/to/Fallout 2" ./fallout-linux-mod-setup.sh

readonly FO1_APPID=38400
readonly FO2_APPID=38410
readonly FO1IN2_URL_DEFAULT="https://github.com/rotators/Fo1in2/releases/latest/download/Fallout1in2.zip"
readonly RPU_REPO="BGforgeNet/Fallout2_Restoration_Project"
FO1IN2_URL=${FO1IN2_URL:-$FO1IN2_URL_DEFAULT}
RPU_URL=${RPU_URL:-}
readonly DLL_OVERRIDE='WINEDLLOVERRIDES="ddraw.dll=n,b" %command%'

TMPDIR_SETUP=""
FO1_BACKUP=""
FO1_REPLACED=0
INSTALL_COMPLETE=0

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33mWARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

cleanup() {
    local status=$?

    if [[ $status -ne 0 && $FO1_REPLACED -eq 1 && -n ${FO1_BACKUP:-} ]]; then
        warn "The Fallout 1 takeover did not finish. Restoring the original Fallout directory."
        rm -rf -- "${FALLOUT1_DIR:-}" 2>/dev/null || true
        mv -- "$FO1_BACKUP" "${FALLOUT1_DIR:-}" 2>/dev/null || true
    fi

    [[ -n ${TMPDIR_SETUP:-} ]] && rm -rf -- "$TMPDIR_SETUP"
    exit "$status"
}
trap cleanup EXIT

need_command() {
    command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

for cmd in curl unzip python3 find cp mv sed awk pgrep; do
    need_command "$cmd"
done

if ! command -v wine >/dev/null 2>&1 && ! command -v wine64 >/dev/null 2>&1; then
    die "Wine is required because Fallout1in2's undat.sh uses it to extract Fallout 1 assets."
fi

stop_steam() {
    if pgrep -x steam >/dev/null 2>&1 || pgrep -f '[s]teamwebhelper' >/dev/null 2>&1; then
        log "Closing Steam so it cannot overwrite localconfig.vdf during setup"
        if command -v steam >/dev/null 2>&1; then
            steam -shutdown >/dev/null 2>&1 || true
        fi

        local i
        for i in {1..30}; do
            if ! pgrep -x steam >/dev/null 2>&1 && ! pgrep -f '[s]teamwebhelper' >/dev/null 2>&1; then
                return 0
            fi
            sleep 1
        done

        die "Steam is still running. Exit Steam completely, then run this script again."
    fi
}

collect_steam_libraries() {
    python3 - <<'PY'
import os
import re
from pathlib import Path

home = Path.home()
roots = [
    home / ".steam/steam",
    home / ".local/share/Steam",
    home / ".var/app/com.valvesoftware.Steam/.local/share/Steam",
]

seen = set()
libraries = []

def add(path):
    try:
        path = Path(path).expanduser()
        normalized = str(path.resolve(strict=False))
    except Exception:
        return
    if normalized not in seen and path.exists():
        seen.add(normalized)
        libraries.append(path)

for root in roots:
    add(root)

for root in list(roots):
    vdf = root / "steamapps/libraryfolders.vdf"
    if not vdf.is_file():
        continue
    text = vdf.read_text(encoding="utf-8", errors="replace")
    for match in re.finditer(r'"path"\s*"((?:\\.|[^"\\])*)"', text, re.I):
        value = match.group(1).replace(r"\\", "\\").replace(r'\"', '"')
        add(value)

for library in libraries:
    print(library)
PY
}

mapfile -t STEAM_LIBRARIES < <(collect_steam_libraries)
((${#STEAM_LIBRARIES[@]} > 0)) || die "Could not locate a Steam installation."

manifest_install_dir() {
    local appid=$1
    local library manifest installdir

    for library in "${STEAM_LIBRARIES[@]}"; do
        manifest="$library/steamapps/appmanifest_${appid}.acf"
        [[ -f $manifest ]] || continue
        installdir=$(sed -nE 's/^[[:space:]]*"installdir"[[:space:]]*"(.*)"[[:space:]]*$/\1/p' "$manifest" | head -n1)
        [[ -n $installdir ]] || continue
        printf '%s\n' "$library/steamapps/common/$installdir"
        return 0
    done

    return 1
}

FALLOUT1_DIR=${FALLOUT1_DIR:-$(manifest_install_dir "$FO1_APPID" || true)}
FALLOUT2_DIR=${FALLOUT2_DIR:-$(manifest_install_dir "$FO2_APPID" || true)}

[[ -n $FALLOUT1_DIR && -d $FALLOUT1_DIR ]] || die "Fallout 1 is not installed. Install Steam app $FO1_APPID first."
[[ -n $FALLOUT2_DIR && -d $FALLOUT2_DIR ]] || die "Fallout 2 is not installed. Install Steam app $FO2_APPID first."

find_file_ci() {
    local directory=$1
    local filename=$2
    find "$directory" -maxdepth 1 -type f -iname "$filename" -print -quit
}

FO1_MASTER=$(find_file_ci "$FALLOUT1_DIR" master.dat)
FO2_MASTER=$(find_file_ci "$FALLOUT2_DIR" master.dat)
FO2_CRITTER=$(find_file_ci "$FALLOUT2_DIR" critter.dat)

[[ -n $FO1_MASTER ]] || die "Could not find Fallout 1 MASTER.DAT in: $FALLOUT1_DIR"
[[ -n $FO2_MASTER ]] || die "Could not find Fallout 2 master.dat in: $FALLOUT2_DIR"
[[ -n $FO2_CRITTER ]] || die "Could not find Fallout 2 critter.dat in: $FALLOUT2_DIR"

printf '\nDetected installations:\n'
printf '  Fallout 1: %s\n' "$FALLOUT1_DIR"
printf '  Fallout 2: %s\n' "$FALLOUT2_DIR"

if [[ -e "$FALLOUT1_DIR/.fallout1in2-steam-takeover" ]]; then
    die "Fallout 1 already has this script's takeover marker. Restore/verify Fallout 1 in Steam before running a fresh installation."
fi

if [[ -e "$FALLOUT2_DIR/.rpu-linux-setup" || -f "$FALLOUT2_DIR/mods/rpu.ini" ]]; then
    die "Fallout 2 appears to already contain RPU. Steam-verify Fallout 2 for a clean install before rerunning this script."
fi

stop_steam
TMPDIR_SETUP=$(mktemp -d -t fallout-mod-setup.XXXXXXXX)

log "Saving clean Fallout 2 data files for the standalone Fallout1in2 build"
cp -a -- "$FO1_MASTER" "$TMPDIR_SETUP/fo1-master.dat"
cp -a -- "$FO2_MASTER" "$TMPDIR_SETUP/master.dat"
cp -a -- "$FO2_CRITTER" "$TMPDIR_SETUP/critter.dat"

log "Downloading the latest Fallout1in2 release"
curl --fail --location --retry 3 --retry-delay 2 \
    --output "$TMPDIR_SETUP/Fallout1in2.zip" \
    "$FO1IN2_URL"

if [[ -z $RPU_URL ]]; then
    log "Finding the latest Linux ZIP release of Fallout 2 Restoration Project Updated"
    RPU_URL=$(python3 - "$RPU_REPO" <<'PY'
import json
import re
import sys
import urllib.request

repo = sys.argv[1]
request = urllib.request.Request(
    f"https://api.github.com/repos/{repo}/releases/latest",
    headers={"Accept": "application/vnd.github+json", "User-Agent": "fallout-linux-mod-setup"},
)
with urllib.request.urlopen(request, timeout=30) as response:
    release = json.load(response)

matches = []
for asset in release.get("assets", []):
    name = asset.get("name", "")
    if re.fullmatch(r"rpu_v[0-9][0-9A-Za-z._-]*\.zip", name, re.I):
        matches.append((len(name), name, asset["browser_download_url"]))

if not matches:
    raise SystemExit("The latest RPU release does not contain an rpu_v*.zip asset")

matches.sort()
print(matches[0][2])
PY
    ) || die "Could not resolve the latest RPU ZIP download."
else
    log "Using the supplied RPU release URL"
fi

curl --fail --location --retry 3 --retry-delay 2 \
    --output "$TMPDIR_SETUP/RPU.zip" \
    "$RPU_URL"

log "Extracting Fallout1in2"
mkdir -p "$TMPDIR_SETUP/fo1in2-extracted"
unzip -q "$TMPDIR_SETUP/Fallout1in2.zip" -d "$TMPDIR_SETUP/fo1in2-extracted"

FO1IN2_PAYLOAD=$(find "$TMPDIR_SETUP/fo1in2-extracted" -type f -iname 'Fallout2.exe' -printf '%h\n' | awk '{ print length, $0 }' | sort -n | cut -d' ' -f2- | head -n1)
[[ -n $FO1IN2_PAYLOAD && -f "$FO1IN2_PAYLOAD/Fallout2.exe" ]] || die "The Fallout1in2 archive layout was not recognized."
[[ -f "$FO1IN2_PAYLOAD/undat.sh" ]] || die "Fallout1in2 archive is missing undat.sh."

stamp=$(date +%Y%m%d-%H%M%S)
FO1_BACKUP="${FALLOUT1_DIR}.vanilla-${stamp}"

log "Backing up vanilla Fallout 1"
mv -- "$FALLOUT1_DIR" "$FO1_BACKUP"
mkdir -p -- "$FALLOUT1_DIR"
FO1_REPLACED=1

log "Building a standalone Fallout1in2 installation in Fallout 1's Steam directory"
cp -a -- "$FO1IN2_PAYLOAD"/. "$FALLOUT1_DIR"/
cp -a -- "$TMPDIR_SETUP/fo1-master.dat" "$FALLOUT1_DIR/MASTER.DAT"
chmod +x "$FALLOUT1_DIR/undat.sh"

(
    cd "$FALLOUT1_DIR"
    ./undat.sh MASTER.DAT
)
rm -f -- "$FALLOUT1_DIR/MASTER.DAT"

cp -a -- "$TMPDIR_SETUP/master.dat" "$FALLOUT1_DIR/master.dat"
cp -a -- "$TMPDIR_SETUP/critter.dat" "$FALLOUT1_DIR/critter.dat"

[[ -f "$FALLOUT1_DIR/Fallout2.cfg" ]] || die "Fallout1in2 is missing Fallout2.cfg after extraction."
python3 - "$FALLOUT1_DIR/Fallout2.cfg" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="replace")
replacements = {
    "critter_dat": "critter.dat",
    "master_dat": "master.dat",
    "music_path2": "data\\sound\\music\\",
}
for key, value in replacements.items():
    pattern = re.compile(rf"(?im)^{re.escape(key)}\s*=.*$")
    if pattern.search(text):
        text = pattern.sub(lambda _match: f"{key}={value}", text)
    else:
        raise SystemExit(f"Required setting not found in Fallout2.cfg: {key}")
path.write_text(text, encoding="utf-8", newline="\r\n")
PY

cp -a -- "$FALLOUT1_DIR/Fallout2.exe" "$FALLOUT1_DIR/falloutlauncher.exe"
cat > "$FALLOUT1_DIR/.fallout1in2-steam-takeover" <<EOF
Installed by fallout-linux-mod-setup.sh on $(date --iso-8601=seconds)
Vanilla Fallout 1 backup: $FO1_BACKUP
EOF

# The original FO1 MASTER.DAT was referenced through the old path before the move.
# Re-resolve it now only for validation and future diagnostic output.
[[ -d $FO1_BACKUP ]] || die "Fallout 1 backup was not created correctly."

lowercase_tree() {
    python3 - "$1" <<'PY'
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
for current, dirs, files in os.walk(root, topdown=False):
    current_path = Path(current)
    for name in files + dirs:
        source = current_path / name
        lowered = name.lower()
        if lowered == name:
            continue
        destination = current_path / lowered
        if destination.exists() and destination != source:
            raise SystemExit(f"Cannot lowercase because both names exist: {source} and {destination}")
        source.rename(destination)
PY
}

log "Preparing Fallout 2's vanilla directory for the Linux RPU package"
lowercase_tree "$FALLOUT2_DIR"

log "Extracting and installing Fallout 2 Restoration Project Updated"
mkdir -p "$TMPDIR_SETUP/rpu-extracted"
unzip -q "$TMPDIR_SETUP/RPU.zip" -d "$TMPDIR_SETUP/rpu-extracted"
RPU_INSTALLER=$(find "$TMPDIR_SETUP/rpu-extracted" -type f -iname 'rpu-install.sh' -print -quit)
[[ -n $RPU_INSTALLER ]] || die "The RPU archive does not contain rpu-install.sh."
RPU_PAYLOAD=$(dirname "$RPU_INSTALLER")
cp -a -- "$RPU_PAYLOAD"/. "$FALLOUT2_DIR"/
chmod +x "$FALLOUT2_DIR/rpu-install.sh"
(
    cd "$FALLOUT2_DIR"
    ./rpu-install.sh
)

cat > "$FALLOUT2_DIR/.rpu-linux-setup" <<EOF
Installed by fallout-linux-mod-setup.sh on $(date --iso-8601=seconds)
Release asset: $RPU_URL
EOF

patch_localconfig() {
    local vdf=$1
    python3 - "$vdf" "$DLL_OVERRIDE" "$FO1_APPID" "$FO2_APPID" <<'PY'
import os
import re
import shutil
import stat
import sys
import tempfile
from datetime import datetime
from pathlib import Path

path = Path(sys.argv[1])
launch_options = sys.argv[2]
appids = sys.argv[3:]
text = path.read_text(encoding="utf-8", errors="strict")

TOKEN_RE = re.compile(r'''\s+|//[^\n]*|"(?:\\.|[^"\\])*"|[{}]|[^\s{}"]+''')

def decode_token(token):
    if not token.startswith('"'):
        return token
    body = token[1:-1]
    out = []
    i = 0
    while i < len(body):
        if body[i] == '\\' and i + 1 < len(body) and body[i + 1] in ('\\', '"'):
            out.append(body[i + 1])
            i += 2
        else:
            out.append(body[i])
            i += 1
    return ''.join(out)

tokens = []
for match in TOKEN_RE.finditer(text):
    token = match.group(0)
    if token.isspace() or token.startswith('//'):
        continue
    tokens.append(decode_token(token))

index = 0

def parse_object(expect_close=False):
    global index
    pairs = []
    while index < len(tokens):
        token = tokens[index]
        if token == '}':
            if not expect_close:
                raise ValueError('Unexpected closing brace')
            index += 1
            return pairs
        if token == '{':
            raise ValueError('Unexpected opening brace')
        key = token
        index += 1
        if index >= len(tokens):
            raise ValueError(f'Missing value for key {key!r}')
        token = tokens[index]
        if token == '{':
            index += 1
            value = parse_object(expect_close=True)
        else:
            if token == '}':
                raise ValueError(f'Missing value for key {key!r}')
            value = token
            index += 1
        pairs.append([key, value])
    if expect_close:
        raise ValueError('Missing closing brace')
    return pairs

root = parse_object()

def get_or_create_object(obj, key):
    for pair in obj:
        if pair[0].casefold() == key.casefold() and isinstance(pair[1], list):
            return pair[1]
    child = []
    obj.append([key, child])
    return child

def set_scalar(obj, key, value):
    for pair in obj:
        if pair[0].casefold() == key.casefold() and not isinstance(pair[1], list):
            pair[1] = value
            return
    obj.append([key, value])

node = root
for key in ('UserLocalConfigStore', 'Software', 'Valve', 'Steam', 'apps'):
    node = get_or_create_object(node, key)
for appid in appids:
    app = get_or_create_object(node, appid)
    set_scalar(app, 'LaunchOptions', launch_options)

def quote(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'

def emit(obj, depth=0):
    lines = []
    indent = '\t' * depth
    for key, value in obj:
        if isinstance(value, list):
            lines.append(f'{indent}{quote(key)}')
            lines.append(f'{indent}{{')
            lines.extend(emit(value, depth + 1))
            lines.append(f'{indent}}}')
        else:
            lines.append(f'{indent}{quote(key)}\t\t{quote(value)}')
    return lines

backup = path.with_name(path.name + '.backup-' + datetime.now().strftime('%Y%m%d-%H%M%S'))
shutil.copy2(path, backup)
mode = stat.S_IMODE(path.stat().st_mode)
new_text = '\n'.join(emit(root)) + '\n'
with tempfile.NamedTemporaryFile('w', encoding='utf-8', dir=path.parent, delete=False) as handle:
    handle.write(new_text)
    temp_name = handle.name
os.chmod(temp_name, mode)
os.replace(temp_name, path)
print(f'Patched {path}')
print(f'Backup  {backup}')
PY
}

log "Setting the required native ddraw override for both Steam entries"
localconfigs=()
for root in "${STEAM_LIBRARIES[@]}"; do
    while IFS= read -r -d '' file; do
        localconfigs+=("$file")
    done < <(find "$root/userdata" -mindepth 3 -maxdepth 3 -type f -path '*/config/localconfig.vdf' -print0 2>/dev/null || true)
done

# Also search the standard primary Steam roots, because userdata normally lives there
# even when a game itself is installed in a secondary library.
for root in "$HOME/.steam/steam" "$HOME/.local/share/Steam" "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
    [[ -d $root/userdata ]] || continue
    while IFS= read -r -d '' file; do
        localconfigs+=("$file")
    done < <(find "$root/userdata" -mindepth 3 -maxdepth 3 -type f -path '*/config/localconfig.vdf' -print0 2>/dev/null || true)
done

if ((${#localconfigs[@]} == 0)); then
    warn "No Steam localconfig.vdf was found. Set this launch option manually on both games: $DLL_OVERRIDE"
else
    mapfile -t unique_localconfigs < <(printf '%s\n' "${localconfigs[@]}" | awk '!seen[$0]++')
    for vdf in "${unique_localconfigs[@]}"; do
        patch_localconfig "$vdf"
    done
fi

FO1_REPLACED=0
INSTALL_COMPLETE=1

log "Installation complete"
printf '\nFallout 1 now launches Fallout Et Tu through the normal Fallout Steam entry.\n'
printf 'Fallout 2 now launches Restoration Project Updated through the normal Fallout 2 Steam entry.\n'
printf '\nVanilla Fallout 1 backup:\n  %s\n' "$FO1_BACKUP"
printf '\nStart Steam normally and launch each game. Both mods require a new game.\n'
