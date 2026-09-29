import AppKit
import SwiftUI

@main
struct HeadshotGeneratorApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    init() {
        // Lets `swift run` show a normal window and Dock icon without the .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("Headshot Generator", id: "main") {
            ContentView()
                .environmentObject(appDelegate.model)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 760)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

/// Receives photos dropped on the Dock icon or opened with Finder's "Open With", including at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func application(_ application: NSApplication, open urls: [URL]) {
        // One photo at a time: if several are dropped, open the first image.
        guard let url = urls.first(where: { (try? $0.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .image) == true }) else {
            return
        }
        model.load(url)
        NSApp.activate()
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }
}
