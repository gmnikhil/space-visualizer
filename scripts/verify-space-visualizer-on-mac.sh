#!/bin/zsh
set -e
set -o pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LOG="$ROOT/.build/space-visualizer-verification.log"
mkdir -p "$ROOT/.build"
cd "$ROOT"

# Prefer an installed Xcode over Command Line Tools for XCTest and macOS SDKs.
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

{
    echo "Space Visualizer macOS verification"
    echo "Started: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "Repository: $ROOT"
    echo
    echo "=== Environment ==="
    uname -a
    sw_vers
    xcode-select -p
    if xcodebuild -version; then
        echo "Full Xcode is available."
    else
        echo "Full Xcode is not selected; continuing with Swift Package Manager. Install/select Xcode before native UI-test tooling."
    fi
    swift --version
    echo
    echo "=== Package description ==="
    swift package describe
    echo
    echo "=== Swift tests ==="
    swift test --parallel
    echo
    echo "=== Optimized Swift tests ==="
    swift test -c release --parallel
    echo
    echo "=== Control fixture ==="
    "$ROOT/scripts/generate-space-visualizer-control-fixture.sh"
    ls -lh "$ROOT/.build/SpaceVisualizerControl.wav"
    echo
    echo "=== App bundle build ==="
    "$ROOT/scripts/build-space-visualizer-app.sh"
    echo
    echo "Built app bundle: $ROOT/.build/Space Visualizer.app"
    echo "Launch manually with: open \"$ROOT/.build/Space Visualizer.app\""
    echo
    echo "Completed: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} 2>&1 | tee "$LOG"

# zsh's first pipeline status is the verification block, not tee.
exit $pipestatus[1]
