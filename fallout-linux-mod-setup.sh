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
want_ettu=0
want_rpu=0

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

choose_install() {
    local choice=${INSTALL_MODE:-}
    local selected answer

    while true; do
        if [[ -z $choice ]]; then
            printf '\nWhat do you want to install?\n'
            printf '  1) Restoration Project Updated (Fallout 2)\n'
            printf '  2) Fallout Et Tu (Fallout 1in2)\n'
            printf '  3) Both\n'
            printf '  4) Cancel\n\n'
            read -r -p 'Choose [1-4]: ' choice || die "no option selected"
        fi

        case ${choice,,} in
            1|rpu|restoration)
                want_rpu=1
                selected="Restoration Project Updated for Fallout 2"
                ;;
            2|ettu|et-tu|fo1in2|fallout1in2)
                want_ettu=1
                selected="Fallout Et Tu / Fallout 1in2"
                ;;
            3|both|all)
                want_ettu=1
                want_rpu=1
                selected="Fallout Et Tu and Restoration Project Updated"
                ;;
            4|cancel|quit|exit)
                say "cancelled"
                exit 0
                ;;
            *)
                warn "choose 1, 2, 3, or 4"
                choice=""
                continue
                ;;
        esac
        break
    done

    printf '\nYou selected: %s\n' "$selected"
    case ${ASSUME_YES:-} in
        1|y|Y|yes|YES|true|TRUE) return ;;
    esac

    read -r -p 'Continue? [y/N]: ' answer || answer=""
    case ${answer,,} in
        y|yes) ;;
        *)
            say "cancelled"
            exit 0
            ;;
    esac
}

choose_install

required=(curl unzip python3 pgrep)
((want_ettu)) && required+=(wine)
for cmd in "${required[@]}"; do
    command -v "$cmd" >/dev/null || die "missing command: $cmd"
done

steam_running() {
    pgrep -x steam >/dev/null 2>&1 || pgrep -f '[s]teamwebhelper' >/dev/null 2>&1
}

stop_steam() {
    steam_running || return 0

    say "closing Steam"
    if command -v steam >/dev/null; then
        steam -shutdown >/dev/null 2>&1 || true
    fi
    if command -v flatpak >/dev/null; then
        flatpak kill com.valvesoftware.Steam >/dev/null 2>&1 || true
    fi

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

FALLOUT2_DIR=${FALLOUT2_DIR:-}
[[ -n $FALLOUT2_DIR ]] || FALLOUT2_DIR=$(find_game "$FO2_ID" || true)
[[ -d $FALLOUT2_DIR ]] || die "Fallout 2 is not installed"

if ((want_ettu)); then
    FALLOUT1_DIR=${FALLOUT1_DIR:-}
    [[ -n $FALLOUT1_DIR ]] || FALLOUT1_DIR=$(find_game "$FO1_ID" || true)
    [[ -d $FALLOUT1_DIR ]] || die "Fallout 1 is not installed"
    [[ ! -e $FALLOUT1_DIR/.fallout1in2 && ! -e $FALLOUT1_DIR/.fallout1in2-steam-takeover ]] || die "Fallout Et Tu is already installed"

    fo1_master=$(find_file "$FALLOUT1_DIR" master.dat)
    fo2_master=$(find_file "$FALLOUT2_DIR" master.dat)
    fo2_critter=$(find_file "$FALLOUT2_DIR" critter.dat)
    [[ -n $fo1_master ]] || die "Fallout 1 master.dat was not found"
    [[ -n $fo2_master ]] || die "Fallout 2 master.dat was not found"
    [[ -n $fo2_critter ]] || die "Fallout 2 critter.dat was not found"
fi

if ((want_rpu)); then
    [[ ! -e $FALLOUT2_DIR/.rpu-linux && ! -e $FALLOUT2_DIR/.rpu-linux-setup ]] || die "RPU is already installed"
fi

((want_ettu)) && printf 'Fallout 1: %s\n' "$FALLOUT1_DIR"
printf 'Fallout 2: %s\n' "$FALLOUT2_DIR"
stop_steam
workdir=$(mktemp -d -t fallout-setup.XXXXXXXX)

install_ettu() {
    cp -a "$fo1_master" "$workdir/fo1-master.dat"
    cp -a "$fo2_master" "$workdir/master.dat"
    cp -a "$fo2_critter" "$workdir/critter.dat"

    say "downloading Fallout Et Tu"
    curl -fL --retry 3 -o "$workdir/fo1in2.zip" "$FO1IN2_URL"

    mkdir "$workdir/fo1in2"
    unzip -q "$workdir/fo1in2.zip" -d "$workdir/fo1in2"
    local payload
    payload=$(find "$workdir/fo1in2" -type f -iname Fallout2.exe -print -quit)
    [[ -n $payload ]] || die "Fallout Et Tu archive layout was not recognized"
    payload=$(dirname "$payload")
    [[ -f $payload/undat.sh ]] || die "undat.sh is missing from Fallout Et Tu"

    say "installing Fallout Et Tu"
    fo1_backup="${FALLOUT1_DIR}.vanilla-$(date +%Y%m%d-%H%M%S)"
    mv "$FALLOUT1_DIR" "$fo1_backup"
    mkdir -p "$FALLOUT1_DIR"
    fo1_moved=1

    cp -a "$payload/." "$FALLOUT1_DIR/"
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
    pattern = re.compile(rf"(?im)^{key}\s*=.*$")
    text, count = pattern.subn(lambda _match: f"{key}={value}", text)
    if not count:
        raise SystemExit(f"missing setting in Fallout2.cfg: {key}")
path.write_text(text, encoding="utf-8", newline="\r\n")
PY

    cp "$FALLOUT1_DIR/Fallout2.exe" "$FALLOUT1_DIR/falloutlauncher.exe"
    printf 'backup=%s\n' "$fo1_backup" > "$FALLOUT1_DIR/.fallout1in2"
    fo1_moved=0
}

resolve_rpu_url() {
    [[ -n $RPU_URL ]] && return

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
}

lowercase_tree() {
    python3 - "$1" <<'PY'
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
}

install_rpu() {
    resolve_rpu_url
    say "downloading RPU"
    curl -fL --retry 3 -o "$workdir/rpu.zip" "$RPU_URL"

    say "installing RPU"
    lowercase_tree "$FALLOUT2_DIR"
    mkdir "$workdir/rpu"
    unzip -q "$workdir/rpu.zip" -d "$workdir/rpu"

    local installer payload
    installer=$(find "$workdir/rpu" -type f -iname rpu-install.sh -print -quit)
    [[ -n $installer ]] || die "rpu-install.sh was not found"
    payload=$(dirname "$installer")
    cp -a "$payload/." "$FALLOUT2_DIR/"
    chmod +x "$FALLOUT2_DIR/rpu-install.sh"
    (
        cd "$FALLOUT2_DIR"
        ./rpu-install.sh
    )
    printf 'release=%s\n' "$RPU_URL" > "$FALLOUT2_DIR/.rpu-linux"
}

((want_ettu)) && install_ettu
((want_rpu)) && install_rpu

patch_vdf() {
    local vdf=$1
    shift
    python3 - "$vdf" "$LAUNCH_OPTIONS" "$@" <<'PY'
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

appids=()
((want_ettu)) && appids+=("$FO1_ID")
((want_rpu)) && appids+=("$FO2_ID")

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
        patch_vdf "$file" "${appids[@]}"
    done
else
    warn "Steam config was not found. Add this launch option to the selected game(s):"
    printf '%s\n' "$LAUNCH_OPTIONS"
fi

say "done"
((want_ettu)) && printf 'Fallout 1 backup: %s\n' "$fo1_backup"
((want_ettu)) && printf 'Fallout now launches Fallout Et Tu.\n'
((want_rpu)) && printf 'Fallout 2 now launches RPU.\n'
printf 'Restart Steam and start a new game.\n'
