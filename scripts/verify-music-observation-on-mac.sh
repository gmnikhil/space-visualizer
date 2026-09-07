#!/bin/zsh
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LOG="$ROOT/.build/space-visualizer-music-observation.log"
CHECKLIST="$ROOT/.build/space-visualizer-music-observation-checklist.md"
APP="$ROOT/.build/Space Visualizer.app"
mkdir -p "$ROOT/.build"
cd "$ROOT"

# Match the main verification script: `sdef` is an Xcode tool and is not
# available when Command Line Tools remains the active developer directory.
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This verification must run on the target Mac." >&2
    exit 1
fi

{
    echo "Space Visualizer Music observation validation"
    echo "Started: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "Repository: $ROOT"
    echo
    echo "=== Environment ==="
    sw_vers
    uname -a
    echo
    echo "=== Installed Music dictionary ==="
    "$ROOT/scripts/inspect-music-interface.sh"
    echo
    for pattern in 'player state' 'current track' 'player position' 'duration'; do
        if grep -qi "$pattern" "$ROOT/.build/Music.sdef.xml"; then
            echo "Found dictionary text: $pattern"
        else
            echo "REVIEW REQUIRED: dictionary text not found: $pattern"
        fi
    done
    echo
    echo "=== Signed renamed bundle ==="
    "$ROOT/scripts/build-space-visualizer-app.sh"
    /usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist"
    codesign -dvv "$APP" 2>&1 || true
    echo "--- entitlements ---"
    codesign -d --entitlements :- "$APP" 2>&1 || true
    echo
    echo "=== Manual attribution and behavior required ==="
    echo "Launch with: open \"$APP\""
    echo "Complete $CHECKLIST; do not report this script alone as a TCC acceptance pass."
    echo
    echo "Completed: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} 2>&1 | tee "$LOG"

if [[ ! -f "$CHECKLIST" ]]; then
    cat > "$CHECKLIST" <<EOF
# Space Visualizer Music observation checklist

Run against the signed bundle: \
\`$APP\`

- [ ] If consent was already enabled, this button is intentionally absent. To repeat first-run onboarding, quit the app and run \`defaults delete com.spacevisualizer.app\` (this clears only the app's consent preference, not TCC permissions), then relaunch. Confirm Music does not launch.
- [ ] With Music running but no current track, confirm the app handles player state without requiring title, artist, album, duration, or artwork.
- [ ] With Music playing, confirm the Automation prompt (if shown) has acceptable attribution to Space Visualizer and matches the in-app consent explanation.
- [ ] Deny Automation, confirm the app stops observation and does not reprompt on the five-second idle interval; use explicit Retry only.
- [ ] Revoke Automation in System Settings while active, confirm safe cleanup and recoverable settings/retry guidance.
- [ ] **Required for capture acceptance:** with Music already playing, launch/restore Space Visualizer and allow the automatic follower to start its direct Music tap. If macOS presents a System Audio Recording prompt, record its exact attribution/wording; approve only if it refers to the signed Space Visualizer app and never approve microphone or screen capture. If no prompt appears because permission was already granted, record that fact and verify the session reaches fresh live samples.
- [ ] **Optional dictionary/notification check:** this is not needed to operate the app. If Music posts an accessible public playback notification while you play/pause manually, record whether it carries a reliable state; otherwise record “not observed/unsupported.” The two-second authoritative watchdog remains required regardless.

## Result

- Music version/build:
- macOS version:
- Automation attribution result:
- System-audio attribution result:
- Notification coverage/result:
- Unsupported or untested behavior:
EOF
    echo "Wrote new manual checklist: $CHECKLIST"
else
    echo "Preserved existing manual checklist: $CHECKLIST"
fi

printf '\nWrote log: %s\nChecklist: %s\n' "$LOG" "$CHECKLIST"
