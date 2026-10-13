import SwiftUI
import SottoCore

struct MenuView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sotto").font(.headline)
                Spacer()
                Toggle("", isOn: $model.enabled).labelsHidden().toggleStyle(.switch)
            }
            Divider()

            Text("Microphone").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { model.selectedMicUID },
                set: { model.selectMic($0) })) {
                ForEach(model.inputs, id: \.uid) { dev in
                    Text(dev.name).tag(dev.uid)
                }
            }.labelsHidden()

            Text("Strength: \(model.strength)%").font(.caption).foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { Double(model.strength) },
                set: { model.strength = Int($0) }), in: 0...100)

            Button {
            } label: {
                Text("Hold to hear original")
            }
            .buttonStyle(.bordered)
            .onLongPressGesture(minimumDuration: 0.01, pressing: { model.setBypass($0) }, perform: {})

            Divider()
            Text(model.statusLine).font(.caption).foregroundStyle(.secondary)
            Text("Select \"Sotto Microphone\" in your call app.").font(.caption2).foregroundStyle(.tertiary)

            Divider()
            Button("Quit Sotto") { model.willQuit(); NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 280)
    }
}
