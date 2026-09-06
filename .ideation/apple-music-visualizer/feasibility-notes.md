# Apple Music visualizer — feasibility notes

Status: documentation research, not a successful native capture test. Reviewed 2026-09-05. The workspace runs Linux; no macOS runtime, Music scripting dictionary, Apple account, or Apple Music subscription playback is available here.

## Answer

A custom native macOS music visualizer is feasible. The precise requirement—accurately visualizing subscription audio already playing in Apple's Music app—is **conditional on receiving usable, permitted audio samples on the user's Mac**. A subscription alone does not provide an audio-analysis API. Do not promise that Core Audio or ScreenCaptureKit will expose all protected playback, all formats, or all output routes.

Metadata and sound are separate inputs. Artwork, artist, playback position, and titles cannot yield a truthful live frequency spectrum. MusicKit supports catalog/library access and authorized playback; its public player API does not expose decoded subscription PCM for an FFT. No private MediaRemote APIs, stream decryption, protected-file extraction, or DRM workarounds are proposed.

## Recommended first direction (not yet approved)

- A native SwiftUI + Metal **companion**; the user continues playing music in Music.
- Proposed baseline: macOS 14.2+, initially quality-targeted at Apple Silicon. Confirm the user's Mac, OS, and output route before implementation.
- Music's AppleScript dictionary via Apple events / ScriptingBridge for current track, playback state, position, and basic transport. Inspect the installed dictionary during the native spike. Artwork is best effort; a generated palette is the fallback. Bound background polling; do not make audio reactivity depend on it.
- Private, nonmuting Core Audio process tap, attached to a private aggregate device, capturing only the relevant Music audio process(es). Validate process ownership rather than assuming that the visible UI PID owns all audio. Do not mix every system app as an invisible fallback.
- Permissioned PCM → preallocated bounded ring buffer → serial DSP worker using Accelerate/vDSP → timestamped features → Metal renderer. No recording or cloud processing.
- ScreenCaptureKit is a possible alternative capture adapter, not a guaranteed protected-content fallback; only consider it if the initial test justifies the extra permission/complexity.
- Start with locally built development software. Signed/notarized direct distribution is the proposed shipping route; Mac App Store sandbox and automation compatibility require a separate assessment. Developer Program membership is separate from an Apple Music subscription.
- MusicKit catalog/search and in-app playback are optional later scope, not necessary to follow the already-running Mac Music app. `SystemMusicPlayer` is not a native-macOS now-playing bridge; `ApplicationMusicPlayer` has its own playback state.

## Mandatory native feasibility gate, after approval

This is a product go/no-go gate, not an approved full test strategy.

1. Request automation and system-audio permissions with clear purpose strings; verify the installed Music scripting dictionary and metadata from a real track.
2. Establish tap behavior with an unprotected local audio fixture. Verify nonzero samples, correct sample format, channel count, timestamps, band energy, source isolation, and uninterrupted listening.
3. Try the user's actual streamed subscription track and a downloaded subscription track. Downloading a subscription track does not make it DRM-free. Compare with a purchased/unprotected file as a control.
4. Check the actual listening route (speakers / wired / Bluetooth / AirPlay), sample-rate changes, and relevant lossless / Spatial Audio settings. Begin with local stereo output as a baseline; do not claim remote-output support before measuring it.
5. If samples are absent, silent, or errors occur while playback is reported: diagnose permissions, source processes, route, and genuine silence. Silence alone does not prove DRM blocking.
6. PASS only if permitted samples correlate with audible music and metadata follows the correct source, without interrupting playback. Then proceed to design confirmation and a separate test-strategy discussion.
7. If protected playback remains inaccessible, stop and ask the user to revise scope. Choices: unprotected local files, an explicitly labeled non-audio-reactive ambient mode, or Apple's built-in visualizer. None silently substitutes for the requested Apple Music visualizer.

## Documented facts and limits

| Topic | What the source supports | What it does NOT establish |
| --- | --- | --- |
| MusicKit | Apple Music integration, catalog/library, authorized playback | Raw decoded subscription audio or a native-Mac global now-playing feed |
| Core Audio taps | Outgoing per-process/group audio capture, private taps, mute behavior, aggregate device input; sample instructions require macOS 14.2+ | Capture eligibility of every protected Apple Music track/output route |
| System audio permission | `NSAudioCaptureUsageDescription`, introduced macOS 14.2; tap sample describes a system prompt when capture starts | Permission overrides protected-content restrictions |
| Apple events | Purpose string and Hardened Runtime automation entitlement; scriptable app integration | All Music track types expose artwork; App Store distribution is already approved |
| ScreenCaptureKit | Audio sample delivery; `capturesAudio` is available on macOS 13+ | A way around DRM or a reason to collect screen imagery for the preferred tap design |
| Built-in visualizer | Apple's Music app offers Window → Visualizer for music including Apple Music | A supported extension point to replace its renderer |

## Primary sources

1. [Apple MusicKit overview](https://developer.apple.com/musickit/)
2. [Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps). The current downloadable sample's metadata lists newer SDK tooling, but its configuration text explicitly says macOS 14.2 or later. Check symbol availability and deployment build on the supported SDK; do not confuse sample tooling with API baseline.
3. [CATapDescription](https://developer.apple.com/documentation/coreaudio/catapdescription)
4. [NSAudioCaptureUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsaudiocaptureusagedescription)
5. [NSAppleEventsUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription)
6. [Apple Events entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events)
7. [Scripting Bridge programming guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ScriptingBridgeConcepts/Introduction/Introduction.html) (archived; verify Music's current dictionary locally)
8. [MusicKit ApplicationMusicPlayer](https://developer.apple.com/documentation/musickit/applicationmusicplayer) — available on native macOS 14+; playback does not affect the Music app's state.
9. [MusicKit SystemMusicPlayer](https://developer.apple.com/documentation/musickit/systemmusicplayer) — platform listing does not include native macOS; do not confuse Mac Catalyst with native macOS.
10. [ScreenCaptureKit audio capture setting](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturesaudio)
11. [ScreenCaptureKit sample: capturing screen content](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
12. [Music on Mac: turn on visual effects](https://support.apple.com/guide/music/turn-on-visual-effects-muse3aa39574/mac)

## HTML review boundaries

`design-and-architecture.html` is an offline, self-contained design document. The canvas projects 3D coordinates into 2D; it is not the proposed native Metal renderer. Its default input is explicitly synthetic and makes no sound. Optional browser-supported unprotected local audio uses Web Audio FFT analysis, stays on the device, and is audible only after a user action. It does not connect to Apple Music, capture system audio, establish native performance, or prove subscription-capture feasibility. Setup, track controls, diagnostics, and native permissions shown in screen mockups are examples, not working macOS integrations. Review choices are browser-local when storage is available; export and send them to the agent to communicate approval.
