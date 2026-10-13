import SwiftUI
import SottoCore

private let sottoTeal = Color(red: 0.07, green: 0.63, blue: 0.53)

private let sottoWave: Image = {
    if let url = Bundle.main.url(forResource: "MenuIcon@2x", withExtension: "png"),
       let ns = NSImage(contentsOf: url) {
        ns.isTemplate = true
        return Image(nsImage: ns).renderingMode(.template)
    }
    return Image(systemName: "waveform")
}()

struct MenuView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            micSection
            strengthSection
            compareButton
            Divider()
            statusRow
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(sottoTeal)
                sottoWave.resizable().scaledToFit().frame(width: 24, height: 15).foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text("Sotto").font(.system(size: 16, weight: .semibold))
                Text("Noise cancellation").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $model.enabled).labelsHidden().toggleStyle(.switch).tint(sottoTeal)
        }
    }

    private var micSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MICROPHONE").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).tracking(0.5)
            Picker("", selection: Binding(get: { model.selectedMicUID }, set: { model.selectMic($0) })) {
                ForEach(model.inputs, id: \.uid) { Text($0.name).tag($0.uid) }
            }
            .labelsHidden()
            .disabled(!model.enabled)
        }
    }

    private var strengthSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("STRENGTH").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).tracking(0.5)
                Spacer()
                Text("\(model.strength)%").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(model.strength) }, set: { model.strength = Int($0) }), in: 0...100)
                .tint(sottoTeal)
                .disabled(!model.enabled)
        }
    }

    private var compareButton: some View {
        Text("Hold to hear original")
            .font(.system(size: 12))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.01, pressing: { model.setBypass($0) }, perform: {})
            .opacity(model.enabled ? 1 : 0.4)
    }

    private var statusRow: some View {
        HStack(spacing: 7) {
            Circle().fill(model.enabled ? sottoTeal : Color.secondary).frame(width: 7, height: 7)
            Text(model.statusLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var footer: some View {
        HStack {
            Text("Pick “Sotto Microphone” in your call app").font(.system(size: 10)).foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { model.willQuit(); NSApplication.shared.terminate(nil) }
                .font(.system(size: 11))
        }
    }
}
