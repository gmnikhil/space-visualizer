import Foundation
import Combine

public final class DiagnosticEngine: ObservableObject {
    @Published public private(set) var state: DiagnosticState
    @Published public private(set) var routes: [AudioRouteFacts] = []
    @Published public private(set) var events: [String] = []
    @Published public private(set) var phase: TestPhase = .unprotectedControl
    @Published public private(set) var isCapturing = false
    @Published public private(set) var isMetadataObservationEnabled = false
    public private(set) var lastFeatures: AudioFeatures = .settled
    public let visualFeatures = VisualFeatureStore()
    private var worker: AnalysisWorker?
    private var diagnosticUpdateLimiter = DiagnosticUpdateLimiter()
    @Published public private(set) var lastReport: DiagnosticReport?

    public let metadata: MusicMetadataCoordinator
    public let permission: AudioPermissionCoordinator
    public let routeResolver: AudioRouteResolver
    public let viewModel: DiagnosticViewModel

    private let routeProvider: AudioRouteProviding
    private let audioClock: AudioTimestampClock
    private var captureSession: CaptureSession?
    private var capture: CoreAudioProcessTapCapture?
    private var pipeline: AudioFeaturePipeline?
    private var generationController = StreamGenerationController()
    private var reportTests: [TestEvidence] = []
    @Published public private(set) var captureDiagnostics = "Capture not started."
    private var pollsWithoutFeatures = 0
    private var lastFrameTime = DispatchTime.now().uptimeNanoseconds
    private var lastTelemetryTime: UInt64 = 0

    public init(
        metadataQuery: MusicQuerying,
        routeProvider: AudioRouteProviding,
        permissionProvider: AudioPermissionProviding,
        audioClock: AudioTimestampClock = SystemAudioTimestampClock()
    ) {
        self.metadata = MusicMetadataCoordinator(query: metadataQuery)
        self.routeProvider = routeProvider
        self.audioClock = audioClock
        self.permission = AudioPermissionCoordinator(provider: permissionProvider)
        self.routeResolver = AudioRouteResolver(provider: routeProvider)
        self.viewModel = DiagnosticViewModel()
        self.state = viewModel.state
    }

    deinit {
        worker?.stop()
        captureSession?.stop()
        capture?.destroy()
    }

    public static func live() -> DiagnosticEngine {
        DiagnosticEngine(
            metadataQuery: UnavailableMusicMetadataQuery(),
            routeProvider: CoreAudioRouteProvider(),
            permissionProvider: SystemAudioPermissionProvider()
        )
    }

    public func refreshRoutes() {
        routes = routeResolver.routes()
        appendEvent(routes.isEmpty ? "No output routes found." : "Found \(routes.count) output route(s).")
    }

    public func beginMetadataObservation() {
        isMetadataObservationEnabled = true
        _ = refreshMetadata(force: true)
    }

    @discardableResult
    public func refreshMetadata(force: Bool = false) -> MetadataRefreshResult {
        guard isMetadataObservationEnabled || force else { return .throttled }
        isMetadataObservationEnabled = true
        let result = metadata.refresh(force: force)
        switch result {
        case let .available(snapshot):
            let becameAvailable = state.metadataHealth != .available
            if becameAvailable || state.track != snapshot { apply(.metadataAvailable(snapshot)) }
            if becameAvailable { appendEvent("Music metadata available.") }
        case let .permissionRequired(message):
            apply(.metadataPermissionRequired)
            appendEvent(message)
            isMetadataObservationEnabled = false
        case let .unavailable(message):
            if state.metadataHealth != .unavailable || state.message != message {
                apply(.metadataUnavailable(message))
                appendEvent(message)
            }
        case .throttled:
            break
        }
        return result
    }

    public func setPhase(_ phase: TestPhase) {
        self.phase = phase
        appendEvent("Test phase: \(phase.rawValue).")
    }

    public func start(routeID: String?) {
        stop()
        apply(.start)
        refreshRoutes()

        switch permission.ensurePermission() {
        case .authorized, .notDetermined:
            break
        case .denied, .unavailable:
            let message = permission.recoveryAction
            apply(.capturePermissionDenied(message))
            appendEvent(message)
            return
        }

        let resolution = routeResolver.resolve(preferredID: routeID)
        guard case let .selected(route) = resolution else {
            let message: String
            switch resolution {
            case let .ambiguous(names): message = "Choose one route: \(names.joined(separator: ", "))."
            case let .unavailable(reason): message = reason
            case .selected: message = ""
            }
            apply(.captureFailed(message))
            appendEvent(message)
            return
        }

        apply(.captureConnecting)
        let sampleRate = route.sampleRate ?? 48_000
        let channels = route.channelCount ?? 2
        let collector = PCMBufferCollector(capacity: Int(sampleRate * Double(channels) * 2))
        let capture = CoreAudioProcessTapCapture(route: route, collector: collector)
        let session = CaptureSession(resource: capture)

        do {
            try session.start()
            guard let format = capture.format else {
                session.stop()
                apply(.captureFailed("Capture started without a usable format."))
                appendEvent("Capture started without a usable format.")
                return
            }
            self.capture = capture
            self.captureSession = session
            let analyzer = AudioAnalyzer(configuration: AudioAnalyzerConfiguration(
                sampleRate: format.sampleRate,
                channelCount: format.channelCount,
                isInterleaved: format.isInterleaved,
                sampleFormat: format.sampleFormat,
                fftSize: AudioAnalyzerConfiguration.windowSize(sampleRate: format.sampleRate)
            ))
            self.pipeline = AudioFeaturePipeline(
                collector: collector,
                analyzer: analyzer,
                clock: audioClock
            )
            if let pipeline = self.pipeline {
                let worker = AnalysisWorker(pipeline: pipeline, clock: audioClock)
                self.worker = worker
                worker.start()
            }
            self.isCapturing = true
            permission.updateStatus(.authorized)
            apply(.captureStarted(route: route, format: format))
            appendEvent("Capture started for \(route.name). Waiting for fresh samples.")
        } catch {
            session.stop()
            apply(.captureFailed(error.localizedDescription))
            appendEvent(error.localizedDescription)
        }
    }

    public func stop() {
        isMetadataObservationEnabled = false
        captureSession?.stop()
        captureSession = nil
        capture?.destroy()
        capture = nil
        worker?.stop()
        worker = nil
        pipeline = nil
        visualFeatures.update(.settled)
        lastFeatures = .settled
        pollsWithoutFeatures = 0
        diagnosticUpdateLimiter.reset()
        lastFrameTime = DispatchTime.now().uptimeNanoseconds
        isCapturing = false
        if state.captureState != .idle && state.captureState != .stopped {
            apply(.stopped)
        }
    }

    /// Call from a display timer. It drains bounded samples and updates both
    /// the diagnostic state and the lightweight 2D/3D proof views.
    public func pollFeatures() {
        guard let worker else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        if now - lastTelemetryTime >= 250_000_000, let capture {
            let captureStats = capture.telemetry.snapshot()
            let bufferStats = capture.collector.snapshot()
            let analysisStats = worker.telemetry.snapshot()
            let duration = analysisStats.analysisDuration
            let mailbox = analysisStats.mailboxAge
            let memory = ProcessResourceSampler.snapshot(analysis: worker.telemetry).residentMemoryBytes
                .map(String.init) ?? "—"
            let analysisSummary = "analysis p50/p95: \(duration.p50Nanoseconds ?? 0)/\(duration.p95Nanoseconds ?? 0) ns · mailbox p50/p95: \(mailbox.p50Nanoseconds ?? 0)/\(mailbox.p95Nanoseconds ?? 0) ns · workers/tasks: \(analysisStats.activeWorkers)/\(analysisStats.activeTasks) · resident: \(memory)"
            captureDiagnostics = "\(captureStats.summary) · accepted/dropped: \(bufferStats.acceptedSamples)/\(bufferStats.droppedSamples) · discontinuities: \(bufferStats.discontinuities) · \(analysisSummary)"
            lastTelemetryTime = now
        }
        guard let features = worker.snapshot() else {
            visualFeatures.update(.settled)
            pollsWithoutFeatures += 1
            if now - lastFrameTime >= 1_000_000_000, state.audioHealth != .unavailable {
                apply(.captureNoSamples)
                lastFeatures = .settled
                appendEvent("No complete analysis frame. \(captureDiagnostics)")
            }
            return
        }
        pollsWithoutFeatures = 0
        lastFrameTime = now
        lastFeatures = features
        visualFeatures.update(features)
        if diagnosticUpdateLimiter.shouldPublish(at: now) {
            apply(.features(features))
        }
    }

    public var hasReceivedAudioCallback: Bool {
        (capture?.telemetry.snapshot().callbacks ?? 0) > 0
    }

    public func handleRouteChange(_ name: String) {
        generationController.routeChanged()
        // Stop producer and worker before invalidating the stream; no concurrent reset.
        stop()
        lastFeatures = .settled
        pollsWithoutFeatures = 0
        apply(.routeChanged(name))
        appendEvent("Route changed: \(name). Waiting for fresh samples.")
    }

    public var hasVerifiedControl: Bool {
        reportTests.contains { $0.phase == .unprotectedControl && $0.result == .pass }
    }

    public func recordAttempt(
        playbackAudible: Bool,
        expectedBand: String?,
        measuredBand: String?,
        controlVerified: Bool,
        notes: [String] = []
    ) {
        let audio = state.audioHealth
        let features = isCapturing ? (worker?.snapshot() ?? .settled) : (state.latestFeatures ?? lastFeatures)
        let verifiedControlForAttempt = phase == .unprotectedControl ? controlVerified : hasVerifiedControl
        let evidence = TestEvidence(
            phase: phase,
            buildContext: buildContext,
            route: state.route,
            format: state.format,
            automationPermission: metadata.health.rawValue,
            systemAudioPermission: permission.status.rawValue,
            metadataAvailable: metadata.health == .available,
            playbackAudible: playbackAudible,
            freshSamples: features.isFresh,
            controlVerified: verifiedControlForAttempt,
            signalPresent: audio == .live,
            expectedBand: expectedBand,
            measuredBand: measuredBand,
            rms: features.rms,
            events: events + notes,
            result: .inconclusive
        )
        var classified = evidence
        classified.result = FeasibilityClassifier.classify(evidence)
        reportTests.append(classified)
        lastReport = DiagnosticReport(appBuild: buildContext, tests: reportTests)
        appendEvent("Recorded \(phase.rawValue): \(classified.result.rawValue).")
    }

    public func clearReport() {
        reportTests.removeAll()
        lastReport = nil
    }

    public func apply(_ event: DiagnosticTransition) {
        var machine = DiagnosticStateMachine(state: state)
        machine.transition(event)
        state = machine.state
        viewModel.apply(event)
    }

    public func appendEvent(_ event: String) {
        events.append("[\(Self.timeFormatter.string(from: Date()))] \(event)")
        if events.count > 120 { events.removeFirst(events.count - 120) }
    }

    public var buildContext: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        return "SpaceVisualizer feasibility spike \(version)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
