## Why

We need to remove the biggest uncertainty before building Resonant: whether a native macOS companion can observe the track playing in Apple Music and receive usable audio samples for a genuine visualizer. The user wants Apple Music to remain the player, with Resonant combining 2D and 3D motion, but a subscription and track metadata alone do not prove that protected playback can be analyzed.

## What Changes

- Add a narrowly scoped native macOS feasibility spike for the Resonant companion; do not implement the full visualizer product yet.
- Read the current Apple Music track, playback state, position, and best-effort artwork/identity through the supported macOS automation path, without requesting Apple ID credentials or taking over library ownership.
- Request and exercise the required Apple Events and system-audio permissions with clear user-facing explanations.
- Attempt private, nonmuting, Music-source audio capture through the supported Core Audio process-tap/aggregate-device path.
- Analyze only bounded in-memory PCM and expose diagnostic measurements for signal presence, sample format, channel count, route, timestamps, RMS, frequency bands, and silence.
- Compare an unprotected local audio control against streamed and downloaded Apple Music subscription playback on the user’s M5 Pro using built-in speakers and AirPlay where available.
- Produce an explicit pass, fail, or inconclusive result with evidence and route/permission failure guidance; never label a metadata-driven or synthetic animation as live audio reactivity.
- Record the follow-on visual direction as a combination of 2D and 3D motion/shape studies, without implementing the production Metal scene engine in this change.
- Keep the spike local-only: no microphone, audio recording, uploads, cloud processing, private MediaRemote APIs, DRM extraction, virtual-driver workaround, or silent fallback to another product.

## Capabilities

### New Capabilities

- `apple-music-audio-feasibility`: Validate the separated Music metadata and permitted audio-sample paths, expose honest diagnostic states, and produce a native go/no-go result for subscription playback.

### Modified Capabilities

- None. There are no existing capability specs in this repository.

## Impact

- New native macOS spike code and an executable diagnostic surface; the repository currently contains planning artifacts only.
- macOS Apple Events/automation permission and Hardened Runtime entitlement configuration, plus system-audio capture usage description and permission handling.
- Core Audio process taps, aggregate-device lifecycle, PCM buffering, timestamping, and Accelerate/vDSP-based diagnostic analysis.
- Apple Music’s current scriptable interface, protected subscription playback behavior, and audio routes (M5 Pro speakers and AirPlay) are external dependencies that must be measured rather than assumed.
- The existing HTML design review remains a proposal artifact; it is not changed into a working Apple Music integration and does not count as native feasibility evidence.
