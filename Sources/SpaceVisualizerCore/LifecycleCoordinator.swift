import Foundation

/// A cancellation token shared by timers, playback queries, and asynchronous
/// session creation. Cancellation is best effort: a provider may still call a
/// completion, so the coordinator also validates its generation and request id.
public final class LifecycleCancellationToken {
    private let lock = NSLock()
    private var cancellationHandlers: [() -> Void] = []
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    public func addCancellationHandler(_ handler: @escaping () -> Void) {
        let runNow: Bool
        lock.lock()
        if cancelled {
            runNow = true
        } else {
            cancellationHandlers.append(handler)
            runNow = false
        }
        lock.unlock()
        if runNow { handler() }
    }

    public func cancel() {
        let handlers: [() -> Void]
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        handlers = cancellationHandlers
        cancellationHandlers.removeAll()
        lock.unlock()
        handlers.forEach { $0() }
    }
}

/// Monotonic scheduling is injected so lifecycle behavior can be tested
/// without sleeping or relying on wall-clock/calendar changes.
public protocol MonotonicScheduler: AnyObject {
    var nowNanoseconds: UInt64 { get }

    @discardableResult
    func schedule(
        after nanoseconds: UInt64,
        repeating: UInt64?,
        _ action: @escaping () -> Void
    ) -> LifecycleCancellationToken
}

public final class DispatchMonotonicScheduler: MonotonicScheduler {
    private let queue: DispatchQueue

    public init(queue: DispatchQueue = DispatchQueue(label: "com.spacevisualizer.lifecycle.scheduler")) {
        self.queue = queue
    }

    public var nowNanoseconds: UInt64 { DispatchTime.now().uptimeNanoseconds }

    @discardableResult
    public func schedule(
        after nanoseconds: UInt64,
        repeating: UInt64? = nil,
        _ action: @escaping () -> Void
    ) -> LifecycleCancellationToken {
        let token = LifecycleCancellationToken()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let initial = DispatchTime.now() + .nanoseconds(Int(min(nanoseconds, UInt64(Int.max))))
        if let repeating, repeating > 0 {
            timer.schedule(
                deadline: initial,
                repeating: .nanoseconds(Int(min(repeating, UInt64(Int.max)))),
                leeway: .milliseconds(1)
            )
        } else {
            timer.schedule(deadline: initial, leeway: .milliseconds(1))
        }
        timer.setEventHandler { [weak token] in
            guard let token, !token.isCancelled else { return }
            action()
        }
        token.addCancellationHandler { timer.cancel() }
        timer.resume()
        return token
    }
}

/// Deterministic scheduler used by unit tests. Advancing over multiple missed
/// periods fires a repeating action once and moves its next deadline forward
/// from the new monotonic time; it never creates catch-up work.
public final class FakeMonotonicScheduler: MonotonicScheduler {
    private final class Entry {
        let token: LifecycleCancellationToken
        let repeating: UInt64?
        let action: () -> Void
        var due: UInt64

        init(token: LifecycleCancellationToken, due: UInt64, repeating: UInt64?, action: @escaping () -> Void) {
            self.token = token
            self.due = due
            self.repeating = repeating
            self.action = action
        }
    }

    private var entries: [Entry] = []
    public private(set) var nowNanoseconds: UInt64 = 0
    public private(set) var scheduledDelays: [UInt64] = []

    public init() {}

    public var activeHandleCount: Int {
        entries.reduce(into: 0) { count, entry in
            if !entry.token.isCancelled { count += 1 }
        }
    }

    public var pendingHandleCount: Int { activeHandleCount }

    @discardableResult
    public func schedule(
        after nanoseconds: UInt64,
        repeating: UInt64? = nil,
        _ action: @escaping () -> Void
    ) -> LifecycleCancellationToken {
        precondition(nanoseconds > 0, "FakeMonotonicScheduler requires a positive delay")
        if let repeating { precondition(repeating > 0, "Repeating interval must be positive") }
        let token = LifecycleCancellationToken()
        entries.append(Entry(token: token, due: nowNanoseconds &+ nanoseconds,
                             repeating: repeating, action: action))
        scheduledDelays.append(nanoseconds)
        return token
    }

    public func advance(by nanoseconds: UInt64) {
        advance(to: nowNanoseconds &+ nanoseconds)
    }

    public func advance(to target: UInt64) {
        precondition(target >= nowNanoseconds, "FakeMonotonicScheduler cannot move backwards")
        guard target > nowNanoseconds else { return }

        // Snapshot all timers that became due. Repeating timers are advanced
        // from target before callbacks run, which is the no-catch-up rule.
        nowNanoseconds = target
        let dueEntries = entries.filter { !$0.token.isCancelled && $0.due <= target }
        for entry in dueEntries {
            guard !entry.token.isCancelled else { continue }
            if let repeating = entry.repeating {
                entry.due = target &+ repeating
            } else {
                entry.token.cancel()
            }
        }
        dueEntries.forEach { entry in
            // A one-shot token is canceled before its action so it cannot be
            // fired twice; it still must run once for deterministic tests.
            guard entry.repeating != nil || entry.due <= target else { return }
            entry.action()
        }
        entries.removeAll { $0.token.isCancelled && $0.repeating == nil }
        entries.removeAll { $0.token.isCancelled }
    }

    public func fire(_ token: LifecycleCancellationToken) {
        guard !token.isCancelled,
              let entry = entries.first(where: { $0.token === token }) else { return }
        if let repeating = entry.repeating {
            entry.due = nowNanoseconds &+ repeating
        } else {
            token.cancel()
        }
        entry.action()
        entries.removeAll { $0.token.isCancelled }
    }
}

public enum LifecyclePermissionStatus: String, Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

public struct LifecyclePermissionSnapshot: Equatable, Sendable {
    public var automation: AudioPermissionStatus
    public var systemAudio: AudioPermissionStatus

    public init(
        automation: AudioPermissionStatus = .notDetermined,
        systemAudio: AudioPermissionStatus = .notDetermined
    ) {
        self.automation = automation
        self.systemAudio = systemAudio
    }

    public var isAuthorized: Bool {
        automation == .authorized && systemAudio == .authorized
    }

    /// `.notDetermined` is not authorization. It is only eligible to trigger
    /// a platform prompt after explicit user consent.
    public var canAttemptAfterUserConsent: Bool {
        automation != .denied && automation != .unavailable &&
            systemAudio != .denied && systemAudio != .unavailable
    }
}

public protocol LifecyclePermissionProviding: AnyObject {
    var permissions: LifecyclePermissionSnapshot { get }
    func requestAutomationPermission() -> AudioPermissionStatus
    func requestSystemAudioPermission() -> AudioPermissionStatus
}

/// Records outcomes from real platform work without treating a stored user
/// preference as proof of the current TCC authorization.
public protocol LifecyclePermissionOutcomeRecording: AnyObject {
    func recordPlaybackQueryResult(_ result: PlaybackQueryResult)
}

public struct PlaybackObservation: Equatable, Sendable {
    public var state: PlaybackState
    public var track: TrackSnapshot?
    public var isPlayerAvailable: Bool
    /// Wall-clock anchor for displaying the last Music-reported position. It
    /// never drives lifecycle decisions or audio visualization.
    public var positionObservedAt: Date?

    public init(
        state: PlaybackState,
        track: TrackSnapshot? = nil,
        isPlayerAvailable: Bool = true,
        positionObservedAt: Date? = nil
    ) {
        self.state = state
        self.track = track
        self.isPlayerAvailable = isPlayerAvailable
        self.positionObservedAt = positionObservedAt
    }

    public var isPlaying: Bool {
        isPlayerAvailable && state == .playing
    }
}

public enum PlaybackQueryResult: Equatable, Sendable {
    case success(PlaybackObservation)
    case denied(String)
    case timedOut
    case canceled
    case failed(String)
}

public protocol PlaybackStateQuerying: AnyObject {
    @discardableResult
    func query(completion: @escaping (PlaybackQueryResult) -> Void) -> LifecycleCancellationToken
}

public protocol LifecycleWorkerResource: AnyObject {
    func start()
    func stop()
}

public protocol LifecycleRendererResource: AnyObject {
    func start()
    func stop()
    func clear()
}

public enum LifecycleSessionEvent: Equatable, Sendable {
    case audio(AudioFeatures)
    case routeChanged(String)
    case routeRemoved(String)
    case formatChanged(AudioFormatFacts)
}

/// A session resource may emit analysis and capture-invalidation events from
/// its own non-UI queue. The coordinator serializes their state transitions.
public protocol LifecycleSessionEventStreaming: AnyObject {
    func setSessionEventSink(_ sink: @escaping (LifecycleSessionEvent) -> Void)
}

public enum LifecycleResourceError: Error, Equatable, LocalizedError, Sendable {
    case destroyed

    public var errorDescription: String? {
        "The visualizer session resource has already been destroyed."
    }
}

/// Groups the only resources allowed to exist for one visible listening
/// session. Start and teardown are idempotent and partial starts clean up all
/// resources before reporting failure.
public final class VisualizerSessionResources {
    public let capture: CaptureResourceLifecycle
    public let worker: LifecycleWorkerResource
    public let renderer: LifecycleRendererResource

    private var didStop = false
    private var didDestroy = false
    public private(set) var isStarted = false

    public init(
        capture: CaptureResourceLifecycle,
        worker: LifecycleWorkerResource,
        renderer: LifecycleRendererResource
    ) {
        self.capture = capture
        self.worker = worker
        self.renderer = renderer
    }

    public func setSessionEventSink(_ sink: @escaping (LifecycleSessionEvent) -> Void) {
        (capture as? LifecycleSessionEventStreaming)?.setSessionEventSink(sink)
        (worker as? LifecycleSessionEventStreaming)?.setSessionEventSink(sink)
        (renderer as? LifecycleSessionEventStreaming)?.setSessionEventSink(sink)
    }

    public func start() throws {
        guard !didDestroy else { throw LifecycleResourceError.destroyed }
        guard !isStarted else { return }
        do {
            try capture.start()
            worker.start()
            renderer.start()
            isStarted = true
        } catch {
            destroy()
            throw error
        }
    }

    public func stop() {
        guard !didStop else { return }
        didStop = true
        renderer.clear()
        renderer.stop()
        worker.stop()
        capture.stop()
        isStarted = false
    }

    public func destroy() {
        guard !didDestroy else { return }
        didDestroy = true
        stop()
        capture.destroy()
    }
}

public protocol VisualizerSessionFactory: AnyObject {
    @discardableResult
    func makeSession(
        for observation: PlaybackObservation,
        generation: UInt64,
        completion: @escaping (Result<VisualizerSessionResources, Error>) -> Void
    ) -> LifecycleCancellationToken
}

public enum SpaceVisualizerLifecycleState: String, Equatable, Codable, Sendable {
    case onboarding
    case waiting
    case starting
    case visualizing
    case silent
    case suspended
    case recovering
    case permissionBlocked
    case failed
    case terminated
}

public struct LifecyclePresentation: Equatable, Sendable {
    public let state: SpaceVisualizerLifecycleState
    public let message: String
    public let consentIntent: Bool
    public let isWindowVisible: Bool
    public let playback: PlaybackObservation?

    public init(
        state: SpaceVisualizerLifecycleState,
        message: String,
        consentIntent: Bool,
        isWindowVisible: Bool,
        playback: PlaybackObservation?
    ) {
        self.state = state
        self.message = message
        self.consentIntent = consentIntent
        self.isWindowVisible = isWindowVisible
        self.playback = playback
    }
}

/// Owns the visible window's playback discovery, active observation, and
/// session generation. All resource mutation is serialized on one queue; UI
/// callers only submit lifecycle events and never perform driver work.
public final class SpaceVisualizerLifecycleCoordinator {
    public static let idleIntervalNanoseconds: UInt64 = 5_000_000_000
    public static let activeWatchdogIntervalNanoseconds: UInt64 = 2_000_000_000

    public private(set) var state: SpaceVisualizerLifecycleState = .onboarding
    public private(set) var generation: UInt64 = 0
    public private(set) var playback: PlaybackObservation?
    public private(set) var message = "Enable automatic following to begin."
    public private(set) var consentIntent = false
    public private(set) var isWindowVisible = false
    /// This coordinator observes Music only. No code path increments this.
    public private(set) var playbackCommandsIssued = 0

    /// Called on the lifecycle queue after an event has been processed. UI
    /// adapters must hop to the main queue before mutating view state.
    public var stateDidChange: ((LifecyclePresentation) -> Void)?

    /// Latest audio is delivered through a non-publishing mailbox adapter for
    /// display cadence. Status callbacks remain transition-deduplicated.
    public var audioFeaturesDidChange: ((AudioFeatures) -> Void)?

    private let scheduler: MonotonicScheduler
    private let playbackQuery: PlaybackStateQuerying
    private let permissions: LifecyclePermissionProviding
    private let sessionFactory: VisualizerSessionFactory
    private let consentStore: AutomaticFollowingConsentStoring
    private let lifecycleQueue = DispatchQueue(label: "com.spacevisualizer.lifecycle.coordinator", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<UInt8>()

    private var idleTimer: LifecycleCancellationToken?
    private var activeWatchdog: LifecycleCancellationToken?
    private var queryToken: LifecycleCancellationToken?
    private var queryInFlight = false
    private var queryID: UInt64 = 0
    private var queryGeneration: UInt64 = 0
    private var pendingNotificationHint = false
    private var startToken: LifecycleCancellationToken?
    private var startInFlight = false
    private var activeResources: VisualizerSessionResources?
    private var noInputStatusTimer: LifecycleCancellationToken?
    private var noInputTeardownTimer: LifecycleCancellationToken?
    private var hasReceivedFreshInput = false
    private var latestAudioFeatures: AudioFeatures = .settled
    private var lastNotifiedPresentation: LifecyclePresentation?

    public init(
        scheduler: MonotonicScheduler,
        playbackQuery: PlaybackStateQuerying,
        permissions: LifecyclePermissionProviding,
        sessionFactory: VisualizerSessionFactory,
        consentStore: AutomaticFollowingConsentStoring = InMemoryAutomaticFollowingConsentStore()
    ) {
        self.scheduler = scheduler
        self.playbackQuery = playbackQuery
        self.permissions = permissions
        self.sessionFactory = sessionFactory
        self.consentStore = consentStore
        self.consentIntent = consentStore.automaticFollowingEnabled
        lifecycleQueue.setSpecific(key: queueKey, value: 1)
    }

    public var hasIdleTimer: Bool { idleTimer != nil && idleTimer?.isCancelled == false }
    public var hasActiveWatchdog: Bool { activeWatchdog != nil && activeWatchdog?.isCancelled == false }
    public var isQueryInFlight: Bool { queryInFlight }
    public var activeSessionCount: Int { activeResources == nil ? 0 : 1 }

    public var presentation: LifecyclePresentation {
        if DispatchQueue.getSpecific(key: queueKey) != nil { return makePresentation() }
        return lifecycleQueue.sync { makePresentation() }
    }

    public func openWindow() {
        onLifecycleQueue {
            guard self.state != .terminated else { return }
            let wasVisible = self.isWindowVisible
            self.isWindowVisible = true
            if wasVisible && self.state != .suspended { return }
            guard self.consentIntent else {
                self.state = .onboarding
                self.message = "Enable automatic following to begin."
                return
            }
            if self.permissions.permissions.canAttemptAfterUserConsent {
                self.enterWaiting(runInitialCheck: true)
            } else {
                self.state = .permissionBlocked
                self.message = self.permissionMessage(for: self.permissions.permissions)
            }
        }
    }

    /// Explicit user action. Permission providers may present their platform
    /// prompts here, never from an idle timer or an automatic retry.
    public func enableAutomaticFollowing() {
        onLifecycleQueue {
            guard self.state != .terminated else { return }
            self.consentIntent = true
            self.consentStore.automaticFollowingEnabled = true
            let automation = self.permissions.requestAutomationPermission()
            let systemAudio = self.permissions.requestSystemAudioPermission()
            let requestedPermissions = LifecyclePermissionSnapshot(automation: automation, systemAudio: systemAudio)
            guard requestedPermissions.canAttemptAfterUserConsent else {
                self.cancelRuntime(invalidateGeneration: true)
                self.state = .permissionBlocked
                self.message = self.permissionMessage(for: requestedPermissions)
                return
            }
            guard self.isWindowVisible else {
                self.state = .suspended
                self.message = "Automatic following is enabled; open the window to begin."
                return
            }
            self.enterWaiting(runInitialCheck: true)
        }
    }

    public func retryPermission() {
        enableAutomaticFollowing()
    }

    public func retryAfterFailure() {
        onLifecycleQueue {
            guard self.state == .failed, self.consentIntent,
                  self.permissions.permissions.canAttemptAfterUserConsent, self.isWindowVisible else { return }
            self.enterWaiting(runInitialCheck: true)
        }
    }

    public func closeWindow() {
        setWindowVisible(false)
    }

    public func setWindowVisible(_ visible: Bool) {
        onLifecycleQueue {
            guard self.state != .terminated else { return }
            let wasVisible = self.isWindowVisible
            self.isWindowVisible = visible
            if !visible && !wasVisible && self.state == .suspended { return }
            guard !visible else {
                if wasVisible && self.state != .suspended { return }

                guard self.consentIntent else {
                    self.state = .onboarding
                    self.message = "Enable automatic following to begin."
                    return
                }
                guard self.permissions.permissions.canAttemptAfterUserConsent else {
                    self.state = .permissionBlocked
                    self.message = self.permissionMessage(for: self.permissions.permissions)
                    return
                }
                self.enterWaiting(runInitialCheck: true)
                return
            }
            self.cancelRuntime(invalidateGeneration: true)
            self.state = .suspended
            self.message = "Visualizer is suspended while the window is hidden."
        }
    }

    public func sleep() {
        onLifecycleQueue {
            guard self.state != .terminated, self.state != .suspended else { return }
            self.cancelRuntime(invalidateGeneration: true)
            self.state = .suspended
            self.message = "Visualizer is suspended while the Mac is asleep."
        }
    }

    public func wake() {
        onLifecycleQueue {
            guard self.state != .terminated, self.isWindowVisible else { return }
            guard self.consentIntent else {
                self.state = .onboarding
                self.message = "Enable automatic following to begin."
                return
            }
            guard self.permissions.permissions.canAttemptAfterUserConsent else {
                self.state = .permissionBlocked
                self.message = self.permissionMessage(for: self.permissions.permissions)
                return
            }
            guard self.state == .suspended else { return }
            self.enterWaiting(runInitialCheck: true)
        }
    }

    public func quit() {
        onLifecycleQueue {
            guard self.state != .terminated else { return }
            self.isWindowVisible = false
            self.cancelRuntime(invalidateGeneration: true)
            self.state = .terminated
            self.message = "Space Visualizer has terminated."
        }
    }

    /// Optional platform notification hint. It is never authoritative and is
    /// coalesced behind the same one-query-in-flight guard as the watchdog.
    public func playbackNotificationHint() {
        onLifecycleQueue {
            guard self.isActiveObservation else { return }
            guard !self.queryInFlight else {
                self.pendingNotificationHint = true
                return
            }
            self.beginPlaybackQuery()
        }
    }

    /// Fresh silent PCM is a valid active result. It settles the scene but does
    /// not tear down or infer that Music has paused.
    public func receiveAudio(_ features: AudioFeatures) {
        onLifecycleQueue { self.acceptAudio(features) }
    }

    private func acceptAudio(_ features: AudioFeatures) {
        guard isWindowVisible, activeResources != nil,
              isActiveObservation,
              features.generation == generation,
              features.isFresh else { return }
        if latestAudioFeatures != features {
            latestAudioFeatures = features
            audioFeaturesDidChange?(features)
        }
        hasReceivedFreshInput = true
        cancelNoInputDeadlines()
        if features.isSilent {
            state = .silent
            message = "Music is playing, but the latest audio is quiet."
        } else {
            state = .visualizing
            message = "Live signal available."
        }
    }

    private func handleExpiredAudioInput() {
        guard isWindowVisible, activeResources != nil, isActiveObservation else { return }
        hasReceivedFreshInput = false
        if latestAudioFeatures != .settled {
            latestAudioFeatures = .settled
            audioFeaturesDidChange?(.settled)
        }
        state = .recovering
        message = "Fresh Music audio expired. Waiting for input without changing playback."
        scheduleNoInputDeadlines(for: generation)
    }

    private var isActiveObservation: Bool {
        state == .starting || state == .visualizing || state == .silent || state == .recovering
    }

    private func enterWaiting(runInitialCheck: Bool) {
        guard state != .terminated else { return }
        cancelRuntime(invalidateGeneration: true)
        guard isWindowVisible, consentIntent, permissions.permissions.canAttemptAfterUserConsent else {
            state = .suspended
            message = "Automatic following is enabled; open the window to begin."
            return
        }
        state = .waiting
        message = "Waiting for Music playback. Checking every five seconds."
        scheduleIdleTimer()
        if runInitialCheck { beginPlaybackQuery() }
    }

    private func scheduleIdleTimer() {
        guard idleTimer == nil || idleTimer?.isCancelled == true else { return }
        idleTimer = scheduler.schedule(
            after: Self.idleIntervalNanoseconds,
            repeating: Self.idleIntervalNanoseconds
        ) { [weak self] in
            self?.onLifecycleQueue {
                guard let self, self.state == .waiting, self.isWindowVisible else { return }
                self.beginPlaybackQuery()
            }
        }
    }

    private func scheduleActiveWatchdog() {
        guard activeWatchdog == nil || activeWatchdog?.isCancelled == true else { return }
        activeWatchdog = scheduler.schedule(
            after: Self.activeWatchdogIntervalNanoseconds,
            repeating: Self.activeWatchdogIntervalNanoseconds
        ) { [weak self] in
            self?.onLifecycleQueue {
                guard let self, self.isActiveObservation, self.isWindowVisible else { return }
                self.beginPlaybackQuery()
            }
        }
    }

    private func beginPlaybackQuery() {
        guard isWindowVisible, consentIntent else { return }
        guard permissions.permissions.canAttemptAfterUserConsent else {
            blockForKnownPermissionChange()
            return
        }
        guard !queryInFlight else { return }

        queryID &+= 1
        let requestID = queryID
        let requestGeneration = generation
        let requestStartedAt = Date()
        queryGeneration = requestGeneration
        queryInFlight = true
        var callbackReturned = false
        let token = playbackQuery.query { [weak self] result in
            self?.onLifecycleQueue {
                self?.finishPlaybackQuery(
                    id: requestID,
                    generation: requestGeneration,
                    positionObservedAt: requestStartedAt,
                    result: result
                )
            }
        }
        callbackReturned = true
        if callbackReturned, queryInFlight, queryID == requestID {
            queryToken = token
        } else {
            token.cancel()
        }
    }

    private func finishPlaybackQuery(
        id: UInt64,
        generation requestGeneration: UInt64,
        positionObservedAt: Date,
        result: PlaybackQueryResult
    ) {
        guard queryInFlight, id == queryID else { return }
        queryInFlight = false
        queryToken = nil
        (permissions as? LifecyclePermissionOutcomeRecording)?.recordPlaybackQueryResult(result)
        let shouldRunHint = pendingNotificationHint
        pendingNotificationHint = false

        // A canceled/obsolete query cannot mutate a newly opened window.
        guard requestGeneration == generation, state != .terminated else { return }

        switch result {
        case let .success(observation):
            var observedPlayback = observation
            observedPlayback.positionObservedAt = positionObservedAt
            playback = observedPlayback
            handlePlayback(observedPlayback)
        case let .denied(reason):
            cancelRuntime(invalidateGeneration: true)
            state = .permissionBlocked
            message = reason
        case .timedOut:
            handleQueryFailure("Music playback check timed out.")
        case .canceled:
            handleQueryFailure("Music playback check was canceled.")
        case let .failed(reason):
            handleQueryFailure(reason)
        }

        if shouldRunHint, isActiveObservation, !queryInFlight {
            beginPlaybackQuery()
        }
    }

    private func handleQueryFailure(_ reason: String) {
        guard isActiveObservation else {
            state = .waiting
            message = reason
            scheduleIdleTimer()
            return
        }
        returnToWaiting(message: reason)
    }

    private func handlePlayback(_ observation: PlaybackObservation) {
        guard observation.isPlaying else {
            if isActiveObservation || activeResources != nil || startInFlight {
                returnToWaiting(message: observation.isPlayerAvailable
                    ? "Music is not playing. Capture stopped; checking again every five seconds."
                    : "Music is unavailable. Waiting without launching it.")
            } else {
                state = .waiting
                message = observation.isPlayerAvailable
                    ? "Music is not playing. Checking every five seconds."
                    : "Music is unavailable. Waiting without launching it."
                scheduleIdleTimer()
            }
            return
        }

        guard isWindowVisible else { return }
        if state == .waiting {
            startSession(for: observation)
        } else if isActiveObservation || activeResources != nil {
            // Track changes update metadata through playback without creating a
            // second capture, worker, watchdog, or renderer.
            message = state == .silent
                ? "Music is playing, but the latest audio is quiet."
                : message
        }
    }

    private func startSession(for observation: PlaybackObservation) {
        guard activeResources == nil, !startInFlight else { return }
        idleTimer?.cancel()
        idleTimer = nil
        state = .starting
        message = "Music is playing. Starting the visualizer."
        generation &+= 1
        let startGeneration = generation
        startInFlight = true
        scheduleActiveWatchdog()

        let token = sessionFactory.makeSession(for: observation, generation: startGeneration) { [weak self] result in
            self?.onLifecycleQueue {
                self?.finishSessionStart(generation: startGeneration, result: result)
            }
        }
        if startInFlight, generation == startGeneration {
            startToken = token
        } else {
            token.cancel()
        }
    }

    private func finishSessionStart(
        generation startGeneration: UInt64,
        result: Result<VisualizerSessionResources, Error>
    ) {
        guard startInFlight, startGeneration == generation,
              state == .starting, isWindowVisible, state != .terminated else {
            if case let .success(resources) = result { resources.destroy() }
            return
        }
        startInFlight = false
        startToken = nil

        switch result {
        case let .success(resources):
            hasReceivedFreshInput = false
            activeResources = resources
            resources.setSessionEventSink { [weak self] event in
                self?.enqueueSessionEvent(event, generation: startGeneration)
            }
            do {
                try resources.start()
                scheduleNoInputDeadlines(for: startGeneration)
                message = "Visualizer started; waiting for fresh audio."
            } catch {
                resources.destroy()
                activeResources = nil
                generation &+= 1
                activeWatchdog?.cancel()
                activeWatchdog = nil
                cancelNoInputDeadlines()
                state = .failed
                message = error.localizedDescription
            }
        case let .failure(error):
            generation &+= 1
            activeWatchdog?.cancel()
            activeWatchdog = nil
            cancelNoInputDeadlines()
            state = .failed
            message = error.localizedDescription
        }
    }

    private func enqueueSessionEvent(_ event: LifecycleSessionEvent, generation eventGeneration: UInt64) {
        lifecycleQueue.async { [weak self] in
            guard let self else { return }
            self.handleSessionEvent(event, generation: eventGeneration)
            self.notifyStateChange()
        }
    }

    private func handleSessionEvent(_ event: LifecycleSessionEvent, generation eventGeneration: UInt64) {
        guard eventGeneration == generation, activeResources != nil,
              state != .terminated else { return }
        switch event {
        case let .audio(features):
            guard features.generation == generation else { return }
            if features.isFresh {
                acceptAudio(features)
            } else {
                handleExpiredAudioInput()
            }
        case let .routeChanged(name):
            restartAfterCaptureInvalidation("Music audio route changed: \(name).")
        case let .routeRemoved(name):
            restartAfterCaptureInvalidation("Music audio route is unavailable: \(name).")
        case let .formatChanged(format):
            restartAfterCaptureInvalidation(
                "Music audio format changed to \(Int(format.sampleRate)) Hz / \(format.channelCount) channels."
            )
        }
    }

    private func scheduleNoInputDeadlines(for sessionGeneration: UInt64) {
        cancelNoInputDeadlines()
        noInputStatusTimer = scheduler.schedule(after: 1_000_000_000, repeating: nil) { [weak self] in
            self?.onLifecycleQueue {
                guard let self, sessionGeneration == self.generation,
                      self.activeResources != nil, !self.hasReceivedFreshInput,
                      self.isActiveObservation else { return }
                self.state = .recovering
                self.message = "Capture started, but no usable Music audio arrived within one second."
            }
        }
        noInputTeardownTimer = scheduler.schedule(after: 5_000_000_000, repeating: nil) { [weak self] in
            self?.onLifecycleQueue {
                guard let self, sessionGeneration == self.generation,
                      self.activeResources != nil, !self.hasReceivedFreshInput else { return }
                self.cancelRuntime(invalidateGeneration: true)
                self.state = .failed
                self.message = "No usable Music audio arrived within five seconds. Choose Retry after checking the route and permissions."
            }
        }
    }

    private func cancelNoInputDeadlines() {
        noInputStatusTimer?.cancel()
        noInputStatusTimer = nil
        noInputTeardownTimer?.cancel()
        noInputTeardownTimer = nil
    }

    private func restartAfterCaptureInvalidation(_ reason: String) {
        cancelRuntime(invalidateGeneration: true)
        guard isWindowVisible, consentIntent else {
            state = .suspended
            message = reason
            return
        }
        guard permissions.permissions.canAttemptAfterUserConsent else {
            state = .permissionBlocked
            message = permissionMessage(for: permissions.permissions)
            return
        }
        state = .recovering
        message = reason
        enterWaiting(runInitialCheck: true)
    }

    private func returnToWaiting(message: String) {
        cancelRuntime(invalidateGeneration: true)
        guard isWindowVisible, consentIntent else {
            state = .suspended
            self.message = message
            return
        }
        guard permissions.permissions.canAttemptAfterUserConsent else {
            state = .permissionBlocked
            self.message = permissionMessage(for: permissions.permissions)
            return
        }
        state = .waiting
        self.message = message
        scheduleIdleTimer()
    }

    private func blockForKnownPermissionChange() {
        cancelRuntime(invalidateGeneration: true)
        state = .permissionBlocked
        message = permissionMessage(for: permissions.permissions)
    }

    private func cancelRuntime(invalidateGeneration: Bool) {
        idleTimer?.cancel()
        idleTimer = nil
        activeWatchdog?.cancel()
        activeWatchdog = nil
        queryToken?.cancel()
        queryToken = nil
        queryInFlight = false
        queryID &+= 1
        pendingNotificationHint = false
        startToken?.cancel()
        startToken = nil
        startInFlight = false
        activeResources?.destroy()
        activeResources = nil
        cancelNoInputDeadlines()
        hasReceivedFreshInput = false
        if latestAudioFeatures != .settled {
            latestAudioFeatures = .settled
            audioFeaturesDidChange?(.settled)
        }
        if invalidateGeneration { generation &+= 1 }
    }

    private func permissionMessage(for permissions: LifecyclePermissionSnapshot) -> String {
        if permissions.automation == .denied {
            return "Automation permission is denied. Enable Music access in System Settings, then choose Retry."
        }
        if permissions.systemAudio == .denied {
            return "System-audio permission is denied. Enable it in System Settings, then choose Retry."
        }
        if permissions.automation == .unavailable || permissions.systemAudio == .unavailable {
            return "Required local permissions are unavailable on this Mac."
        }
        return "Enable Automation and System Audio access to follow Music playback."
    }

    private func makePresentation() -> LifecyclePresentation {
        LifecyclePresentation(
            state: state,
            message: message,
            consentIntent: consentIntent,
            isWindowVisible: isWindowVisible,
            playback: playback
        )
    }

    private func notifyStateChange() {
        let next = makePresentation()
        guard next != lastNotifiedPresentation else { return }
        lastNotifiedPresentation = next
        stateDidChange?(next)
    }

    /// Test-only synchronization point for asynchronous session events.
    /// Production callers submit events and never need to block on this queue.
    internal func drainPendingLifecycleWork() {
        if DispatchQueue.getSpecific(key: queueKey) != nil { return }
        lifecycleQueue.sync {}
    }

    private func onLifecycleQueue(_ work: @escaping () -> Void) {
        let workAndNotify = {
            work()
            self.notifyStateChange()
        }
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            workAndNotify()
        } else {
            lifecycleQueue.sync(execute: workAndNotify)
        }
    }
}
