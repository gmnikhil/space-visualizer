## Purpose

This capability establishes whether a native companion can safely observe Apple Music metadata and analyze permitted playback audio on the user's Mac before a production visualizer is built.

## ADDED Requirements

### Requirement: Observe Apple Music identity independently from audio analysis

The diagnostic experience SHALL treat track metadata and audio samples as separate signals. When the user grants the required automation access and Music is available, it SHALL report the current track identity, playback state, and position when those values are exposed, and SHALL mark unavailable values as unknown rather than inventing them. It SHALL NOT require Apple ID credentials or replace Music as the playback owner.

#### Scenario: Music is playing and metadata access is granted

- **WHEN** the diagnostic is connected to the running Music app and the user has granted automation access
- **THEN** it reports the best-effort current track identity, playback state, and position, while keeping the audio-signal status independent

#### Scenario: Metadata access is denied or Music is unavailable

- **WHEN** automation permission is denied, revoked, or the Music app cannot be reached
- **THEN** the diagnostic reports a recoverable metadata-unavailable state, leaves unknown fields blank or explicitly unknown, and does not claim that audio capture has failed solely because metadata is unavailable

### Requirement: Request explicit, purpose-specific permissions

The diagnostic SHALL explain and request only the permissions required for the approved feasibility test: Apple Music automation and system-audio capture. It SHALL NOT request microphone access or screen-image capture for the preferred test path, SHALL show a useful recovery action after denial, and SHALL not repeatedly prompt without a user action.

#### Scenario: User starts the feasibility check

- **WHEN** the user explicitly starts the diagnostic
- **THEN** the app explains why each permission is needed, requests the relevant macOS permission, and identifies which permission is still pending or denied

#### Scenario: User denies system-audio access

- **WHEN** the user denies or revokes system-audio permission
- **THEN** no audio capture is attempted, the app presents a clear denied state and settings/retry guidance, and Music playback is not interrupted

### Requirement: Measure a permitted playback signal without recording it

When permission and a selectable Music audio source are available, the diagnostic SHALL consume the outgoing audio signal in real time and report observable signal facts including signal presence, sample rate, channel count, timestamps or freshness, relative RMS/level, frequency-band energy, and silence. Analysis data SHALL remain bounded and transient in memory; the diagnostic SHALL not save, upload, or expose reconstructed audio.

#### Scenario: A known unprotected control signal is playing

- **WHEN** the user plays the supplied or documented unprotected control fixture through the selected local output route
- **THEN** the measurements show fresh nonzero samples and the expected dominant frequency band without interrupting audible playback

#### Scenario: Genuine silence or a paused player is present

- **WHEN** the selected source is paused or produces sustained near-zero samples
- **THEN** signal energy decays to a quiet state and the diagnostic does not manufacture beats, spectrum, or motion from elapsed track time

#### Scenario: Audio format or output route changes

- **WHEN** the sample format, sample rate, channel count, or selected output route changes during the check
- **THEN** the diagnostic marks the signal as reconnecting or invalid, clears stale measurements, and reports fresh measurements only after the new stream is validated

### Requirement: Test actual Apple Music playback and classify evidence honestly

The feasibility check SHALL provide separate test records for an unprotected local control, streamed Apple Music subscription playback, and downloaded Apple Music subscription playback, and SHALL identify the output route used, including the user's built-in speakers and AirPlay attempts. It SHALL classify the result as pass, fail, or inconclusive based on measured correlation between audible playback and fresh samples; permission, process, route, or silence issues SHALL be distinguished from an unproven protected-content limitation.

#### Scenario: Subscription playback produces correlated samples

- **WHEN** a streamed or downloaded Apple Music track is audibly playing on the tested route and fresh measurements correlate with its changing signal
- **THEN** the record is eligible for a pass result and includes the route, format, permission state, metadata state, and diagnostic evidence

#### Scenario: Subscription playback is audible but samples are unavailable

- **WHEN** Music reports playback and the user can hear the track but no usable samples arrive after permission, source, route, and silence checks
- **THEN** the result is reported as fail or inconclusive with those checks and evidence, and the app does not claim a DRM diagnosis or substitute synthetic/metadata animation as live visualization

#### Scenario: The control signal fails

- **WHEN** the unprotected control does not produce the expected samples
- **THEN** the subscription result is blocked as inconclusive and the report directs investigation toward permissions, source selection, route, or capture lifecycle before drawing conclusions about Apple Music

### Requirement: Stop cleanly and preserve the user's listening session

The diagnostic SHALL stop its capture session, release temporary audio resources, and discard transient analysis data when the user stops or quits the check. It SHALL not mute, seek, pause, or otherwise alter Music playback except when the user explicitly invokes a tested transport action, and the spike SHALL not send audio or diagnostics to a remote service.

#### Scenario: User stops the diagnostic while Music is playing

- **WHEN** the user stops or closes the diagnostic
- **THEN** capture resources are released, in-memory audio data is discarded, and Music continues playing without a change caused by cleanup

#### Scenario: The diagnostic loses permission or encounters a capture error

- **WHEN** permission is revoked or capture fails unexpectedly
- **THEN** the app transitions to a visible recoverable error state, stops consuming the invalid stream, preserves the user's Music playback, and does not keep stale signal values running
