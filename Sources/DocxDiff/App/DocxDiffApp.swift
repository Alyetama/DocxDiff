import AppKit
import SwiftUI
import DocxDiffCore

@main
struct DocxDiffApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate

    init() {
        try? TemporaryExtractionSession.shared.prepare()
    }

    var body: some Scene {
        WindowGroup("DocxDiff") {
            ContentView(store: ComparisonStore())
                .frame(minWidth: 840, minHeight: 620)
        }
        .defaultSize(width: 1040, height: 760)
    }
}

private final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        TemporaryExtractionSession.shared.cleanup()
    }
}
