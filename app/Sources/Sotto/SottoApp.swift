import SwiftUI

@main
struct SottoApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Sotto", systemImage: model.enabled ? "waveform.circle.fill" : "waveform.circle") {
            MenuView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
