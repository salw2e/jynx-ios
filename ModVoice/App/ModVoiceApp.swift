import SwiftUI

@main
struct ModVoiceApp: App {
    var body: some Scene {
        WindowGroup { SetupView() }
    }
}

struct SetupView: View {
    @State private var test = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section("Turn it on") {
                    Step(n: 1, text: "Tap Open Settings, then Keyboards.")
                    Step(n: 2, text: "Turn on Mod Voice and Allow Full Access. Full Access lets it send your message to the fixer.")
                    Step(n: 3, text: "In Discord, hold the globe or emoji key and pick Mod Voice.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                Section("How to use it") {
                    Step(n: 1, text: "Type your message.")
                    Step(n: 2, text: "Pick a tone in the bar above the keys.")
                    Step(n: 3, text: "Tap Fix. Your message is replaced with the fixed one. Tap Undo to get yours back.")
                }
                Section("Try it here") {
                    TextField("type something rough, then tap Fix", text: $test, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Mod Voice")
        }
    }
}

private struct Step: View {
    let n: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.subheadline.bold()).foregroundStyle(.tint)
            Text(text)
        }
    }
}
