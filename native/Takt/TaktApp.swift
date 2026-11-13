import SwiftUI

@main
struct TaktApp: App {
    @StateObject private var game = GameStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(game)
                .tint(TaktTheme.green)
                .preferredColorScheme(.light)
                .onChange(of: phase) { _, value in game.setActive(value == .active) }
        }
    }
}
