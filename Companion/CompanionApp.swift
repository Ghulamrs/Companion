import SwiftUI

@main
struct CompanionApp: App {
    init() {
        // Also goes to the Xcode console, so the problem is visible whether you
        // launched from Xcode or straight from the Simulator.
        for warning in AppEnvironment.configurationWarnings {
            print("⚠️ Companion config: \(warning)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ChatView()
        }
    }
}
