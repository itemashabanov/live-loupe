import SwiftUI

@main
struct LiveLoupeApp: App {
    @StateObject private var appState = AppState()

    init() {
        HeadlessMode.runIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(appState.appearanceMode.colorScheme)
                .frame(width: 680, height: 460)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 680, height: 460)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
