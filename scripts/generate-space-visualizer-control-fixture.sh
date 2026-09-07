#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT="$ROOT/.build/SpaceVisualizerControl.wav"
mkdir -p "$ROOT/.build"

# 12 seconds: 80 Hz bass, 1 kHz mids, 8 kHz highs, then silence.
# AudioToolbox/AVAudioFile generation lives in the app; this fixture uses
# Python's standard library so no package or network dependency is needed.
python3 - "$OUT" <<'PY'
import math, struct, sys, wave
out = sys.argv[1]
rate = 48000
seconds = 12
with wave.open(out, 'wb') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(rate)
    frames = bytearray()
    for i in range(rate * seconds):
        t = i / rate
        if t < 3:
            hz = 80
        elif t < 6:
            hz = 1000
        elif t < 9:
            hz = 8000
        else:
            hz = 0
        sample = math.sin(2 * math.pi * hz * t) * 0.16 if hz else 0.0
        frames += struct.pack('<h', round(sample * 32767))
    f.writeframes(frames)
print(out)
PY
