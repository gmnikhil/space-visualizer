## Why

The user has confirmed that Resonant visualizes both the unprotected control and Apple Music playback on their Mac. They now want a daily-use Space Visualizer that automatically follows Music playback, without manual capture controls or idle CPU/GPU activity, while preserving the existing app in Git rather than maintaining a second application.

## What Changes

- Rename and evolve the existing application into **Space Visualizer** in place. Checkpoint `7c4b0b5` preserves the predecessor; no duplicate app or parallel source tree is created.
- Replace the diagnostic-first window with a full-canvas spatial visualizer and compact status/settings surface; keep diagnostics available on demand.
- After explicit first-run permission setup, check whether the already-running Music app is playing every five seconds while idle. Never launch Music as a side effect of polling.
- Suspend the idle poller during visualization. Observe playback changes with validated local notifications where available and a separate bounded active-state watchdog; silence alone is not proof that playback stopped.
- When playback pauses/stops or Music quits, release capture resources, stop analysis/display scheduling, settle the scene, and resume idle checks. Quit cancels all work.
- Preserve the private, nonmuting Music-only direct-tap path, serial FFT worker, latest-only feature delivery, overlapping windows, and display-synchronized rendering requesting up to 120 Hz on capable displays.
- Harden lifecycle, concurrency, stale-data rejection, permissions, and performance with test-first implementation and target-Mac acceptance evidence.
- **BREAKING:** User-facing app/bundle and executable names change. Document the new launch/build commands and possible renewed macOS permission prompts. Old source remains recoverable from Git.

## Capabilities

### New Capabilities

- `space-visualizer-lifecycle`: Automatic playback-following behavior, bounded idle polling, permission gating, failures, and deterministic cleanup.
- `space-visualizer-experience`: Renamed product, full-canvas spatial experience, truthful signal/format status, display-rate handling, and measurable responsiveness/resource budgets.

### Modified Capabilities

None. There are no published main specs in `openspec/specs`; the unarchived feasibility change is historical context, not a production compatibility guarantee.

## Impact

SwiftPM targets, source/test names, app plist/entitlements, build and verification scripts, README, metadata adapter, lifecycle coordinator, capture ownership, analysis worker, and visual presentation will change. Use only local public macOS APIs, with no remote dependencies, network requests, microphone, screen capture, recordings, uploads, Apple ID credentials, playback mutation, private MediaRemote APIs, or DRM workarounds.

This is the first production-oriented local app iteration, not automatic App Store/notarization readiness. Downloaded content, AirPlay, long-running performance, and lifecycle reliability remain acceptance gates; source Lossless/Hi-Res/Atmos identification remains unknown unless a supported interface actually exposes it.
