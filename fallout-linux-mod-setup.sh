#!/usr/bin/env bash
set -Eeuo pipefail

FO1_ID=38400
FO2_ID=38410
FO1IN2_URL=${FO1IN2_URL:-https://github.com/rotators/Fo1in2/releases/latest/download/Fallout1in2.zip}
RPU_URL=${RPU_URL:-}
RPU_REPO=BGforgeNet/Fallout2_Restoration_Project
LAUNCH_OPTIONS='WINEDLLOVERRIDES="ddraw.dll=n,b" %command%'

workdir=""
fo1_backup=""
fo1_moved=0

say()  { printf '\n==> %s\n' "$*"; }
warn() { printf '\nwarning: %s\n' "$*" >&2; }
die()  { printf '\nerror: %s\n' "$*" >&2; exit 1; }

cleanup() {
    local status=$?

    if ((status != 0 && fo1_moved)); then
        warn "setup failed; restoring Fallout 1"
        rm -rf -- "${FALLOUT1_DIR:-}"
        mv -- "$fo1_backup" "$FALLOUT1_DIR" 2>/dev/null || true
    fi

    [[ -n $workdir ]] && rm -rf -- "$workdir"
    trap - EXIT
    exit "$status"
}
trap cleanup EXIT

for cmd in curl unzip python3 wine pgrep; do
    command -v "$cmd" >/dev/null || die "missing command: $cmd"
done

steam_running() {
    pgrep -x steam >/dev/null 2>&1 || pgrep -f '[s]teamwebhelper' >/dev/null 2>&1
}

stop_steam() {
    steam_running || return 0

    say "closing Steam"
    command -v steam >/dev/null && steam -shutdown >/dev/null 2>&1 || true
    command -v flatpak >/dev/null && flatpak kill com.valvesoftware.Steam >/dev/null 2>&1 || true

    for _ in {1..30}; do
        steam_running || return 0
        sleep 1
    done

    die "Steam is still running"
}

steam_libraries() {
    python3 <<'PY'
import re
from pathlib import Path

roots = [
    Path.home() / ".steam/steam",
    Path.home() / ".local/share/Steam",
    Path.home() / ".var/app/com.valvesoftware.Steam/.local/share/Steam",
]

found = []
seen = set()


def add(path):
    path = Path(path).expanduser()
    key = str(path.resolve(strict=False))
    if path.exists() and key not in seen:
        seen.add(key)
        found.append(path)


for root in roots:
    add(root)
    vdf = root / "steamapps/libraryfolders.vdf"
    if not vdf.is_file():
        continue
    text = vdf.read_text(encoding="utf-8", errors="replace")
    for match in re.finditer(r'"path"\s*"((?:\\.|[^"\\])*)"', text, re.I):
        add(match.group(1).replace(r"\\", "\\"))

print(*found, sep="\n")
PY
}

mapfile -t libraries < <(steam_libraries)
((${#libraries[@]})) || die "Steam was not found"

find_game() {
    local appid=$1 library manifest name

    for library in "${libraries[@]}"; do
        manifest="$library/steamapps/appmanifest_${appid}.acf"
        [[ -f $manifest ]] || continue
        name=$(sed -nE 's/^[[:space:]]*"installdir"[[:space:]]*"(.*)"[[:space:]]*$/\1/p' "$manifest" | head -n1)
        [[ -n $name ]] && printf '%s\n' "$library/steamapps/common/$name" && return
    done
}

find_file() {
    find "$1" -maxdepth 1 -type f -iname "$2" -print -quit
}

FALLOUT1_DIR=${FALLOUT1_DIR:-$(find_game "$FO1_ID")}
FALLOUT2_DIR=${FALLOUT2_DIR:-$(find_game "$FO2_ID")}

[[ -d $FALLOUT1_DIR ]] || die "Fallout 1 is not installed"
[[ -d $FALLOUT2_DIR ]] || die "Fallout 2 is not installed"
[[ ! -e $FALLOUT1_DIR/.fallout1in2 && ! -e $FALLOUT1_DIR/.fallout1in2-steam-takeover ]] || die "Fallout 1in2 is already installed"
[[ ! -e $FALLOUT2_DIR/.rpu-linux && ! -e $FALLOUT2_DIR/.rpu-linux-setup ]] || die "RPU is already installed"

fo1_master=$(find_file "$FALLOUT1_DIR" master.dat)
fo2_master=$(find_file "$FALLOUT2_DIR" master.dat)
fo2_critter=$(find_file "$FALLOUT2_DIR" critter.dat)

[[ -n $fo1_master ]] || die "Fallout 1 master.dat was not found"
[[ -n $fo2_master ]] || die "Fallout 2 master.dat was not found"
[[ -n $fo2_critter ]] || die "Fallout 2 critter.dat was not found"

printf 'Fallout 1: %s\nFallout 2: %s\n' "$FALLOUT1_DIR" "$FALLOUT2_DIR"
stop_steam
workdir=$(mktemp -d -t fallout-setup.XXXXXXXX)

cp -a "$fo1_master" "$workdir/fo1-master.dat"
cp -a "$fo2_master" "$workdir/master.dat"
cp -a "$fo2_critter" "$workdir/critter.dat"

say "downloading Fallout 1in2"
curl -fL --retry 3 -o "$workdir/fo1in2.zip" "$FO1IN2_URL"

if [[ -z $RPU_URL ]]; then
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

for asset in release.get("assets", []):
    if re.fullmatch(r"rpu_v.*\.zip", asset.get("name", ""), re.I):
        print(asset["browser_download_url"])
        break
else:
    raise SystemExit("no RPU zip found in the latest release")
PY
    ) || die "could not find the latest RPU release"
fi

say "downloading RPU"
curl -fL --retry 3 -o "$workdir/rpu.zip" "$RPU_URL"

say "installing Fallout 1in2"
mkdir "$workdir/fo1in2"
unzip -q "$workdir/fo1in2.zip" -d "$workdir/fo1in2"
fo1_payload=$(find "$workdir/fo1in2" -type f -iname Fallout2.exe -print -quit)
[[ -n $fo1_payload ]] || die "Fallout 1in2 archive layout was not recognized"
fo1_payload=$(dirname "$fo1_payload")
[[ -f $fo1_payload/undat.sh ]] || die "undat.sh is missing from Fallout 1in2"

fo1_backup="${FALLOUT1_DIR}.vanilla-$(date +%Y%m%d-%H%M%S)"
mv "$FALLOUT1_DIR" "$fo1_backup"
mkdir -p "$FALLOUT1_DIR"
fo1_moved=1

cp -a "$fo1_payload/." "$FALLOUT1_DIR/"
cp "$workdir/fo1-master.dat" "$FALLOUT1_DIR/MASTER.DAT"
chmod +x "$FALLOUT1_DIR/undat.sh"
(
    cd "$FALLOUT1_DIR"
    ./undat.sh MASTER.DAT
)
rm "$FALLOUT1_DIR/MASTER.DAT"
cp "$workdir/master.dat" "$FALLOUT1_DIR/master.dat"
cp "$workdir/critter.dat" "$FALLOUT1_DIR/critter.dat"

python3 - "$FALLOUT1_DIR/Fallout2.cfg" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="replace")
values = {
    "critter_dat": "critter.dat",
    "master_dat": "master.dat",
    "music_path2": "data\\sound\\music\\",
}
for key, value in values.items():
    text, count = re.subn(rf"(?im)^{key}\s*=.*$", f"{key}={value}", text)
    if not count:
        raise SystemExit(f"missing setting in Fallout2.cfg: {key}")
path.write_text(text, encoding="utf-8", newline="\r\n")
PY

cp "$FALLOUT1_DIR/Fallout2.exe" "$FALLOUT1_DIR/falloutlauncher.exe"
printf 'backup=%s\n' "$fo1_backup" > "$FALLOUT1_DIR/.fallout1in2"
fo1_moved=0

say "installing RPU"
python3 - "$FALLOUT2_DIR" <<'PY'
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
for current, dirs, files in os.walk(root, topdown=False):
    current = Path(current)
    for name in files + dirs:
        src = current / name
        dst = current / name.lower()
        if src == dst:
            continue
        if dst.exists():
            raise SystemExit(f"name conflict: {src} / {dst}")
        src.rename(dst)
PY

mkdir "$workdir/rpu"
unzip -q "$workdir/rpu.zip" -d "$workdir/rpu"
rpu_installer=$(find "$workdir/rpu" -type f -iname rpu-install.sh -print -quit)
[[ -n $rpu_installer ]] || die "rpu-install.sh was not found"
rpu_payload=$(dirname "$rpu_installer")
cp -a "$rpu_payload/." "$FALLOUT2_DIR/"
chmod +x "$FALLOUT2_DIR/rpu-install.sh"
(
    cd "$FALLOUT2_DIR"
    ./rpu-install.sh
)
printf 'release=%s\n' "$RPU_URL" > "$FALLOUT2_DIR/.rpu-linux"

patch_vdf() {
    python3 - "$1" "$LAUNCH_OPTIONS" "$FO1_ID" "$FO2_ID" <<'PY'
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

path = Path(sys.argv[1])
launch_options = sys.argv[2]
appids = sys.argv[3:]
text = path.read_text(encoding="utf-8")
raw = re.findall(r'"(?:\\.|[^"\\])*"|[{}]', text)
tokens = [bytes(x[1:-1], "utf-8").decode("unicode_escape") if x.startswith('"') else x for x in raw]
pos = 0


def parse():
    global pos
    out = {}
    while pos < len(tokens) and tokens[pos] != "}":
        key = tokens[pos]
        pos += 1
        if tokens[pos] == "{":
            pos += 1
            out[key] = parse()
            pos += 1
        else:
            out[key] = tokens[pos]
            pos += 1
    return out


def child(obj, wanted):
    for key, value in obj.items():
        if key.casefold() == wanted.casefold() and isinstance(value, dict):
            return value
    obj[wanted] = {}
    return obj[wanted]


def quote(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'


def dump(obj, depth=0):
    lines = []
    pad = "\t" * depth
    for key, value in obj.items():
        if isinstance(value, dict):
            lines += [f"{pad}{quote(key)}", f"{pad}{{", *dump(value, depth + 1), f"{pad}}}"]
        else:
            lines.append(f"{pad}{quote(key)}\t\t{quote(value)}")
    return lines

root = parse()
apps = root
for key in ("UserLocalConfigStore", "Software", "Valve", "Steam", "apps"):
    apps = child(apps, key)
for appid in appids:
    child(apps, appid)["LaunchOptions"] = launch_options

backup = path.with_name(f"{path.name}.backup-{datetime.now():%Y%m%d-%H%M%S}")
shutil.copy2(path, backup)
path.write_text("\n".join(dump(root)) + "\n", encoding="utf-8")
print(f"updated {path}")
PY
}

say "setting Steam launch options"
declare -A configs=()
for root in "${libraries[@]}" "$HOME/.steam/steam" "$HOME/.local/share/Steam" "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
    [[ -d $root/userdata ]] || continue
    while IFS= read -r -d '' file; do
        configs["$file"]=1
    done < <(find "$root/userdata" -type f -path '*/config/localconfig.vdf' -print0 2>/dev/null)
done

if ((${#configs[@]})); then
    for file in "${!configs[@]}"; do
        patch_vdf "$file"
    done
else
    warn "Steam config was not found. Add this launch option to both games:"
    printf '%s\n' "$LAUNCH_OPTIONS"
fi

say "done"
printf 'Fallout 1 backup: %s\n' "$fo1_backup"
printf 'Restart Steam and start a new game in both.\n'
