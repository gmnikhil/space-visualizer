#!/bin/zsh
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$ROOT/.build"

if [[ -d /System/Applications/Music.app ]]; then
    MUSIC_APP=/System/Applications/Music.app
elif [[ -d /Applications/Music.app ]]; then
    MUSIC_APP=/Applications/Music.app
else
    echo "Music.app was not found in /System/Applications or /Applications." >&2
    exit 1
fi

OUTPUT="$ROOT/.build/Music.sdef.xml"
if ! command -v sdef >/dev/null 2>&1; then
    echo "The sdef utility is unavailable. Install/select the Xcode command-line tools." >&2
    exit 1
fi

sdef "$MUSIC_APP" | tee "$OUTPUT"
printf '\nSaved installed Music dictionary to %s\n' "$OUTPUT"
