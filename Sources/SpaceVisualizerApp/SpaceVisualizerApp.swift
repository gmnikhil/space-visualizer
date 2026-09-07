import SwiftUI
import SpaceVisualizerCore

@main
struct SpaceVisualizerApp: App {
    @StateObject private var engine = DiagnosticEngine.live()
    @StateObject private var automaticFollowing = AutomaticFollowingViewModel.live()

    var body: some Scene {
        Window("Space Visualizer", id: "main") {
            ContentView(engine: engine, automaticFollowing: automaticFollowing)
                .frame(minWidth: 1_040, minHeight: 760)
        }
    }
}
