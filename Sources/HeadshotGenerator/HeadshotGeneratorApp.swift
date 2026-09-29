import AppKit
import SwiftUI

@main
struct HeadshotGeneratorApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Lets `swift run` show a normal window and Dock icon without the .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("Headshot Generator", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 760)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
