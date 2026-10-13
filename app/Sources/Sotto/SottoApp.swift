import SwiftUI
import AppKit

@main
struct SottoApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Sotto", id: "main") {
            MenuView(model: model)
                .frame(width: 300)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.willQuit()
                }
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuView(model: model)
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
