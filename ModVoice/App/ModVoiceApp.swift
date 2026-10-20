import SwiftUI

@main
struct ModVoiceApp: App {
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("-harness") {
                HarnessScreen()
            } else {
                SetupView()
            }
        }
    }
}

let uiTest = ProcessInfo.processInfo.arguments.contains("-uitest")
let sampleTone = CustomTone(id: "sample", name: "Chill", how: "Short and chill, like I'm talking to friends. A bit funny, never rude.")

struct HarnessScreen: View {
    var body: some View {
        VStack {
            HarnessField()
                .frame(height: 160)
                .padding()
            Spacer()
        }
    }
}

struct HarnessField: UIViewRepresentable {
    func makeUIView(context: Context) -> HarnessTextView {
        let v = HarnessTextView()
        v.font = .systemFont(ofSize: 20)
        v.layer.borderColor = UIColor.separator.cgColor
        v.layer.borderWidth = 1
        v.layer.cornerRadius = 8
        v.accessibilityIdentifier = "harness"
        return v
    }

    func updateUIView(_ view: HarnessTextView, context: Context) {}
}

final class HarnessTextView: UITextView {
    private lazy var keyboard: KeyboardViewController = {
        let kb = KeyboardViewController()
        kb.model.customTones = [sampleTone]
        return kb
    }()

    override var inputViewController: UIInputViewController? { keyboard }
}

@MainActor
final class ToneList: ObservableObject {
    @Published var tones: [CustomTone] = []
    @Published var status = ""

    func load() async {
        if uiTest {
            tones = [sampleTone]
            return
        }
        do {
            tones = try await Api.tones()
            status = ""
        } catch {
            status = (error as? ApiError)?.message ?? "Couldn't load your tones."
        }
    }

    func save() async {
        do {
            try await Api.save(tones)
            status = "Saved. The keyboard picks it up next time it opens."
        } catch {
            status = (error as? ApiError)?.message ?? "Couldn't save your tones."
        }
    }
}

struct SetupView: View {
    @StateObject private var list = ToneList()
    @State private var test = ""
    @State private var editing: CustomTone?
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
                Section {
                    ForEach(list.tones) { tone in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tone.name)
                                Text(tone.how).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editing = tone }
                        .accessibilityAddTraits(.isButton)
                    }
                    .onDelete { rows in
                        list.tones.remove(atOffsets: rows)
                        Task { await list.save() }
                    }
                    if list.tones.count < 12 {
                        Button("Add a tone") { editing = CustomTone(name: "", how: "") }
                    }
                } header: {
                    Text("Your tones")
                } footer: {
                    Text(list.status.isEmpty ? "Describe how you want to sound. They show up in the keyboard after the built-in ones." : list.status)
                }
                Section("How to use it") {
                    Step(n: 1, text: "Type your message.")
                    Step(n: 2, text: "Tap the tone button on the left of the bar to pick a tone.")
                    Step(n: 3, text: "Tap Fix. Your message is replaced with the fixed one. Tap Undo to get yours back.")
                }
                Section("Try it here") {
                    TextField("type something rough, then tap Fix", text: $test, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Mod Voice")
            .task { await list.load() }
            .refreshable { await list.load() }
            .sheet(item: $editing) { tone in
                ToneEditor(tone: tone) { saved in
                    if let i = list.tones.firstIndex(where: { $0.id == saved.id }) {
                        list.tones[i] = saved
                    } else {
                        list.tones.append(saved)
                    }
                    Task { await list.save() }
                }
            }
        }
    }
}

private struct ToneEditor: View {
    @State var tone: CustomTone
    let onSave: (CustomTone) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Chill", text: $tone.name)
                        .onChange(of: tone.name) { _, v in if v.count > 24 { tone.name = String(v.prefix(24)) } }
                }
                Section {
                    TextField("e.g. Short and chill, like I'm talking to friends. A bit funny, never rude.", text: $tone.how, axis: .vertical)
                        .lineLimit(3...8)
                        .onChange(of: tone.how) { _, v in if v.count > 300 { tone.how = String(v.prefix(300)) } }
                } header: {
                    Text("How should it sound?")
                } footer: {
                    Text("\(tone.how.count)/300")
                }
            }
            .navigationTitle(tone.name.isEmpty ? "New tone" : tone.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(CustomTone(id: tone.id, name: tone.name.trimmingCharacters(in: .whitespaces), how: tone.how.trimmingCharacters(in: .whitespacesAndNewlines)))
                        dismiss()
                    }
                    .disabled(tone.name.trimmingCharacters(in: .whitespaces).isEmpty || tone.how.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
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
