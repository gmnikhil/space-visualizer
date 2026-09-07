import Foundation

public enum CaptureRouteChange: Equatable, Sendable {
    case routeChanged(String)
    case routeRemoved(String)
    case formatChanged(AudioFormatFacts)
}

/// Monitoring runs only for an active visible capture session. It never selects
/// a different source itself; the coordinator tears down and revalidates first.
public protocol AudioCaptureChangeMonitoring: AnyObject {
    @discardableResult
    func startMonitoring(
        route: AudioRouteFacts,
        format: AudioFormatFacts,
        onChange: @escaping (CaptureRouteChange) -> Void
    ) -> LifecycleCancellationToken
}

/// Bounded active-session route monitor. It compares the explicitly selected
/// route with current Core Audio facts once per second and emits at most one
/// invalidation; it is canceled with the session and never runs while idle.
public final class CoreAudioRouteChangeMonitor: AudioCaptureChangeMonitoring {
    private let routeProvider: AudioRouteProviding
    private let queue: DispatchQueue

    public init(
        routeProvider: AudioRouteProviding,
        queue: DispatchQueue = DispatchQueue(label: "com.spacevisualizer.route-monitor", qos: .utility)
    ) {
        self.routeProvider = routeProvider
        self.queue = queue
    }

    @discardableResult
    public func startMonitoring(
        route: AudioRouteFacts,
        format: AudioFormatFacts,
        onChange: @escaping (CaptureRouteChange) -> Void
    ) -> LifecycleCancellationToken {
        let token = LifecycleCancellationToken()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1), leeway: .milliseconds(100))
        timer.setEventHandler { [weak self, weak token] in
            guard let self, let token, !token.isCancelled else { return }
            let event = self.detectChange(route: route, format: format)
            guard let event else { return }
            token.cancel()
            onChange(event)
        }
        token.addCancellationHandler { timer.cancel() }
        timer.resume()
        return token
    }

    private func detectChange(route: AudioRouteFacts, format: AudioFormatFacts) -> CaptureRouteChange? {
        guard let current = (try? routeProvider.availableRoutes())?.first(where: { $0.id == route.id }) else {
            return .routeRemoved(route.name)
        }
        guard current.isActive else { return .routeChanged(current.name) }
        if current.sampleRate != route.sampleRate || current.channelCount != route.channelCount {
            let changedFormat = AudioFormatFacts(
                sampleRate: current.sampleRate ?? format.sampleRate,
                channelCount: current.channelCount ?? format.channelCount,
                isInterleaved: format.isInterleaved,
                sampleFormat: format.sampleFormat
            )
            return .formatChanged(changedFormat)
        }
        return nil
    }
}

public enum DirectTapSessionFactoryError: Error, Equatable, LocalizedError, Sendable {
    case ambiguousSource([String])
    case unavailableSource(String)

    public var errorDescription: String? {
        switch self {
        case let .ambiguousSource(names):
            return "Music audio source is ambiguous: \(names.joined(separator: ", ")). Choose a route in settings."
        case let .unavailableSource(message):
            return message
        }
    }
}

public protocol DirectTapSessionBuilding: AnyObject {
    func makeSession(route: AudioRouteFacts, generation: UInt64) throws -> VisualizerSessionResources
}

/// Resolves exactly one Music route, then delegates resource construction. No
/// fallback source is ever passed to the builder.
public final class DirectTapVisualizerSessionFactory: VisualizerSessionFactory {
    private let routeProvider: AudioRouteProviding
    private let sessionBuilder: DirectTapSessionBuilding
    private let preferredRouteID: () -> String?
    private let queue: DispatchQueue

    public init(
        routeProvider: AudioRouteProviding,
        sessionBuilder: DirectTapSessionBuilding,
        preferredRouteID: @escaping () -> String? = { nil },
        queue: DispatchQueue = DispatchQueue(label: "com.spacevisualizer.direct-tap-factory", qos: .utility)
    ) {
        self.routeProvider = routeProvider
        self.sessionBuilder = sessionBuilder
        self.preferredRouteID = preferredRouteID
        self.queue = queue
    }

    public convenience init(
        routeProvider: AudioRouteProviding,
        preferredRouteID: @escaping () -> String? = { nil }
    ) {
        self.init(
            routeProvider: routeProvider,
            sessionBuilder: CoreAudioDirectTapSessionBuilder(routeProvider: routeProvider),
            preferredRouteID: preferredRouteID
        )
    }

    @discardableResult
    public func makeSession(
        for observation: PlaybackObservation,
        generation: UInt64,
        completion: @escaping (Result<VisualizerSessionResources, Error>) -> Void
    ) -> LifecycleCancellationToken {
        let token = LifecycleCancellationToken()
        queue.async { [weak self] in
            guard let self, !token.isCancelled else { return }
            let resolver = AudioRouteResolver(provider: self.routeProvider)
            let resolution = resolver.resolve(preferredID: self.preferredRouteID())
            let route: AudioRouteFacts
            switch resolution {
            case let .selected(selected): route = selected
            case let .ambiguous(names):
                completion(.failure(DirectTapSessionFactoryError.ambiguousSource(names)))
                return
            case let .unavailable(message):
                completion(.failure(DirectTapSessionFactoryError.unavailableSource(message)))
                return
            }

            do {
                let resources = try self.sessionBuilder.makeSession(route: route, generation: generation)
                guard !token.isCancelled else {
                    resources.destroy()
                    return
                }
                completion(.success(resources))
            } catch {
                guard !token.isCancelled else { return }
                completion(.failure(error))
            }
        }
        return token
    }
}

/// Builds the one supported automatic capture route: a private Music process
/// tap, its private aggregate, a bounded analysis worker, and no-op renderer
/// lifecycle handle until the display shell owns its display link.
public final class CoreAudioDirectTapSessionBuilder: DirectTapSessionBuilding {
    private let routeMonitor: AudioCaptureChangeMonitoring
    private let clock: AudioTimestampClock

    public init(
        routeProvider: AudioRouteProviding,
        clock: AudioTimestampClock = SystemAudioTimestampClock()
    ) {
        self.routeMonitor = CoreAudioRouteChangeMonitor(routeProvider: routeProvider)
        self.clock = clock
    }

    public init(
        routeMonitor: AudioCaptureChangeMonitoring,
        clock: AudioTimestampClock = SystemAudioTimestampClock()
    ) {
        self.routeMonitor = routeMonitor
        self.clock = clock
    }

    public func makeSession(route: AudioRouteFacts, generation: UInt64) throws -> VisualizerSessionResources {
        let sampleRate = max(8_000, route.sampleRate ?? 48_000)
        let channels = max(1, route.channelCount ?? 2)
        let capacity = min(4_000_000, max(16_384, Int(sampleRate * Double(channels) * 2)))
        let collector = PCMBufferCollector(capacity: capacity)
        let capture = CoreAudioProcessTapCapture(
            route: route,
            collector: collector,
            generation: generation,
            clock: clock
        )
        let worker = DirectTapAnalysisWorkerResource(
            capture: capture,
            generation: generation,
            routeMonitor: routeMonitor,
            clock: clock
        )
        return VisualizerSessionResources(
            capture: capture,
            worker: worker,
            renderer: PassiveRendererResource()
        )
    }
}

/// Starts analysis only after the direct tap has supplied its actual PCM
/// format. Features and route/format invalidations are forwarded to the
/// coordinator; no capture callback allocates, blocks, or touches the UI.
public final class DirectTapAnalysisWorkerResource: LifecycleWorkerResource, LifecycleSessionEventStreaming {
    private let capture: CoreAudioProcessTapCapture
    private let generation: UInt64
    private let routeMonitor: AudioCaptureChangeMonitoring
    private let clock: AudioTimestampClock
    public let telemetry = AnalysisTelemetry()
    private let lock = NSLock()
    private var worker: AnalysisWorker?
    private var routeMonitorToken: LifecycleCancellationToken?
    private var sink: ((LifecycleSessionEvent) -> Void)?

    public init(
        capture: CoreAudioProcessTapCapture,
        generation: UInt64,
        routeMonitor: AudioCaptureChangeMonitoring,
        clock: AudioTimestampClock = SystemAudioTimestampClock()
    ) {
        self.capture = capture
        self.generation = generation
        self.routeMonitor = routeMonitor
        self.clock = clock
    }

    public func setSessionEventSink(_ sink: @escaping (LifecycleSessionEvent) -> Void) {
        lock.lock()
        self.sink = sink
        lock.unlock()
    }

    public func start() {
        guard worker == nil else { return }
        // A missing format is treated as no usable input. The coordinator's
        // one- and five-second deadlines expose and tear it down without a
        // re-entrant event while `VisualizerSessionResources.start()` runs.
        guard let format = capture.format else { return }
        let analyzer = AudioAnalyzer(configuration: AudioAnalyzerConfiguration(
            sampleRate: format.sampleRate,
            channelCount: format.channelCount,
            isInterleaved: format.isInterleaved,
            sampleFormat: format.sampleFormat,
            fftSize: AudioAnalyzerConfiguration.windowSize(sampleRate: format.sampleRate)
        ))
        let pipeline = AudioFeaturePipeline(collector: capture.collector, analyzer: analyzer, clock: clock)
        let nextWorker = AnalysisWorker(
            pipeline: pipeline,
            onFeatures: { [weak self] features in
                guard let self, features.generation == self.generation else { return }
                self.emit(.audio(features))
            },
            clock: clock,
            telemetry: telemetry
        )
        worker = nextWorker
        routeMonitorToken = routeMonitor.startMonitoring(route: capture.route, format: format) { [weak self] change in
            guard let self else { return }
            switch change {
            case let .routeChanged(name): self.emit(.routeChanged(name))
            case let .routeRemoved(name): self.emit(.routeRemoved(name))
            case let .formatChanged(next): self.emit(.formatChanged(next))
            }
        }
        nextWorker.start()
    }

    public func stop() {
        routeMonitorToken?.cancel()
        routeMonitorToken = nil
        worker?.stop()
        worker = nil
    }

    private func emit(_ event: LifecycleSessionEvent) {
        lock.lock()
        let sink = self.sink
        lock.unlock()
        sink?(event)
    }
}

/// Display ownership is wired in the presentation slice. This resource exists
/// now so coordinator teardown has a single renderer handle and cannot leave a
/// future display link alive after capture stops.
public final class PassiveRendererResource: LifecycleRendererResource {
    public init() {}
    public func start() {}
    public func stop() {}
    public func clear() {}
}
