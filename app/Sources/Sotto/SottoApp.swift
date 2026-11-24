import SwiftUI
import AppKit

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) { model.willQuit() }
}

@main
struct SottoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: delegate.model)
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    // Custom template icon matching the app logo's wave motif; falls back to an SF
    // Symbol if the bundled image is missing.
    static let menuBarIcon: NSImage = {
        let image: NSImage
        if let url = Bundle.main.url(forResource: "MenuIcon@2x", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            image = img
        } else {
            image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Sotto")
                ?? NSImage()
        }
        image.isTemplate = true
        image.size = NSSize(width: 26, height: 16)
        return image
    }()
}
