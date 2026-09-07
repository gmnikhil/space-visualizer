import XCTest
@testable import SpaceVisualizerCore

final class DirectTapVisualizerSessionFactoryTests: XCTestCase {
    func testFactoryBuildsOnlyTheUniqueActiveRoute() {
        let provider = DirectFactoryRouteProvider(routes: [.fixtureInactiveAirPlay, .fixtureActiveSpeaker])
        let builder = DirectFactoryBuilder()
        let factory = DirectTapVisualizerSessionFactory(routeProvider: provider, sessionBuilder: builder)
        let finished = expectation(description: "Session built")
        var result: Result<VisualizerSessionResources, Error>?

        _ = factory.makeSession(for: .playing, generation: 7) {
            result = $0
            finished.fulfill()
        }

        wait(for: [finished], timeout: 1)
        guard case .success? = result else {
            return XCTFail("Expected a direct-tap session resource")
        }
        XCTAssertEqual(builder.routes, [.fixtureActiveSpeaker])
        XCTAssertEqual(builder.generations, [7])
    }

    func testFactoryRejectsAmbiguousActiveSourcesWithoutCreatingCapture() {
        let provider = DirectFactoryRouteProvider(routes: [.fixtureActiveSpeaker, .fixtureActiveAirPlay])
        let builder = DirectFactoryBuilder()
        let factory = DirectTapVisualizerSessionFactory(routeProvider: provider, sessionBuilder: builder)
        let finished = expectation(description: "Ambiguity reported")
        var result: Result<VisualizerSessionResources, Error>?

        _ = factory.makeSession(for: .playing, generation: 1) {
            result = $0
            finished.fulfill()
        }

        wait(for: [finished], timeout: 1)
        guard case let .failure(error)? = result,
              let directError = error as? DirectTapSessionFactoryError else {
            return XCTFail("Expected an explicit source ambiguity error")
        }
        XCTAssertEqual(directError, .ambiguousSource(["Built-in Speakers", "Living Room AirPlay"]))
        XCTAssertTrue(builder.routes.isEmpty)
    }

    func testFactoryCancellationBeforeConstructionCreatesNoSession() {
        let provider = DirectFactoryRouteProvider(routes: [.fixtureActiveSpeaker])
        let builder = DirectFactoryBuilder()
        let queue = DispatchQueue(label: "test.factory.gate")
        queue.suspend()
        let factory = DirectTapVisualizerSessionFactory(routeProvider: provider, sessionBuilder: builder, queue: queue)
        let noCompletion = expectation(description: "No canceled completion")
        noCompletion.isInverted = true

        let token = factory.makeSession(for: .playing, generation: 1) { _ in noCompletion.fulfill() }
        token.cancel()
        queue.resume()

        wait(for: [noCompletion], timeout: 0.1)
        XCTAssertTrue(builder.routes.isEmpty)
    }
}

private final class DirectFactoryRouteProvider: AudioRouteProviding {
    let routes: [AudioRouteFacts]
    init(routes: [AudioRouteFacts]) { self.routes = routes }
    func availableRoutes() throws -> [AudioRouteFacts] { routes }
}

private final class DirectFactoryBuilder: DirectTapSessionBuilding {
    private(set) var routes: [AudioRouteFacts] = []
    private(set) var generations: [UInt64] = []

    func makeSession(route: AudioRouteFacts, generation: UInt64) throws -> VisualizerSessionResources {
        routes.append(route)
        generations.append(generation)
        return VisualizerSessionResources(
            capture: DirectFactoryCapture(),
            worker: DirectFactoryWorker(),
            renderer: DirectFactoryRenderer()
        )
    }
}

private final class DirectFactoryCapture: CaptureResourceLifecycle {
    func start() throws {}
    func stop() {}
    func destroy() {}
}

private final class DirectFactoryWorker: LifecycleWorkerResource {
    func start() {}
    func stop() {}
}

private final class DirectFactoryRenderer: LifecycleRendererResource {
    func start() {}
    func stop() {}
    func clear() {}
}

private extension PlaybackObservation {
    static let playing = PlaybackObservation(state: .playing)
}

private extension AudioRouteFacts {
    static let fixtureActiveSpeaker = AudioRouteFacts(
        id: "speaker",
        name: "Built-in Speakers",
        kind: .builtInSpeaker,
        isActive: true,
        sampleRate: 48_000,
        channelCount: 2
    )

    static let fixtureInactiveAirPlay = AudioRouteFacts(
        id: "airplay",
        name: "Living Room AirPlay",
        kind: .airPlay,
        isActive: false,
        sampleRate: 44_100,
        channelCount: 2
    )

    static let fixtureActiveAirPlay = AudioRouteFacts(
        id: "airplay",
        name: "Living Room AirPlay",
        kind: .airPlay,
        isActive: true,
        sampleRate: 44_100,
        channelCount: 2
    )
}
