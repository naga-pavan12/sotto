import SwiftUI
import AppKit

@main
struct SottoApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        // A normal window (and dock icon) so the app is always findable — even on a
        // crowded/notched menu bar where the MenuBarExtra icon can be hidden.
        Window("Sotto", id: "main") {
            MenuView(model: model)
                .frame(width: 300)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.willQuit()
                }
        }
        .windowResizability(.contentSize)

        // Also available from the menu bar.
        MenuBarExtra("Sotto", systemImage: model.enabled ? "waveform.circle.fill" : "waveform.circle") {
            MenuView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
