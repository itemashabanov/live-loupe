import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?

    func applicationWillTerminate(_ notification: Notification) {
        appState?.prepareForTermination()
    }
}

@main
struct LiveLoupeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                .onAppear {
                    appDelegate.appState = appState
                }
                .onOpenURL { url in
                    appState.applyLaunchURL(url)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 680, height: 460)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
