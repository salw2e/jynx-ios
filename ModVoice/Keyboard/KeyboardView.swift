import SwiftUI

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    let kb: KeyboardViewController

    var body: some View {
        VStack(spacing: 0) {
            Bar(model: model, kb: kb)
                .frame(height: 46)
            Group {
                if model.layer == .emoji {
                    EmojiPanel(kb: kb)
                } else {
                    Keys(model: model, kb: kb)
                }
            }
            .padding(.horizontal, 3)
            .padding(.bottom, 4)
        }
    }
}

private struct Bar: View {
    @ObservedObject var model: KeyboardModel
    let kb: KeyboardViewController

    var body: some View {
        HStack(spacing: 6) {
            switch model.bar {
            case .main:
                Button(action: kb.openTones) {
                    HStack(spacing: 3) {
                        Text(model.toneLabel).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2.bold())
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .foregroundStyle(Color.primary)
                }
                .frame(maxWidth: 104, alignment: .leading)
                .padding(.leading, 6)
                Suggestions(model: model, kb: kb)
                FixButton(kb: kb)
            case .tones:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Tone.allCases, id: \.self) { t in
                            Chip(label: t.label, on: model.toneID == t.rawValue) { kb.chooseTone(t.rawValue) }
                        }
                        ForEach(model.customTones) { t in
                            Chip(label: t.name, on: model.toneID == t.id) { kb.chooseTone(t.id) }
                        }
                    }
                    .padding(.leading, 8)
                }
                CloseButton(kb: kb)
            case .fixing:
                ProgressView().padding(.leading, 12)
                Text("Fixing…").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            case let .done(note, warning):
                Image(systemName: warning == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(warning == nil ? Color.green : Color.orange)
                    .padding(.leading, 12)
                Text(warning ?? note)
                    .font(.footnote)
                    .foregroundStyle(warning == nil ? Color.secondary : Color.orange)
                    .lineLimit(2)
                Spacer(minLength: 4)
                if model.canUndo {
                    Button("Undo", action: kb.undoFix).font(.subheadline.bold())
                }
                CloseButton(kb: kb)
            case let .error(message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .padding(.leading, 12)
                Spacer(minLength: 4)
                CloseButton(kb: kb)
            }
        }
    }
}

private struct Suggestions: View {
    @ObservedObject var model: KeyboardModel
    let kb: KeyboardViewController

    var body: some View {
        HStack(spacing: 0) {
            if model.typed.isEmpty {
                Spacer()
            } else {
                slot(model.correcting ? "“\(model.typed)”" : model.typed, bold: false, action: kb.keepTyped)
                ForEach(Array(model.suggestions.enumerated()), id: \.offset) { i, s in
                    Divider().frame(height: 22)
                    slot(s, bold: i == 0 && model.correcting) { kb.pick(s) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func slot(_ text: String, bold: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 16, weight: bold ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .foregroundStyle(Color.primary)
    }
}

private struct FixButton: View {
    let kb: KeyboardViewController

    var body: some View {
        Button(action: kb.fix) {
            Text("Fix")
                .font(.subheadline.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.accentColor))
                .foregroundStyle(.white)
        }
        .padding(.trailing, 6)
    }
}

private struct Chip: View {
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(label, action: action)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(on ? Color.accentColor : Color.primary.opacity(0.08)))
            .foregroundStyle(on ? Color.white : Color.primary)
    }
}

private struct CloseButton: View {
    let kb: KeyboardViewController

    var body: some View {
        Button(action: kb.closeBar) {
            Image(systemName: "xmark").font(.subheadline.bold()).frame(width: 40, height: 40)
        }
        .foregroundStyle(.secondary)
        .padding(.trailing, 4)
    }
}

private let keyHeight: CGFloat = 43
private let keyGap: CGFloat = 6
private let areaHeight = keyHeight * 4 + 30

private struct Keys: View {
    @ObservedObject var model: KeyboardModel
    let kb: KeyboardViewController

    private var rows: [String] {
        switch model.layer {
        case .letters, .emoji: ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        case .numbers: ["1234567890", "-/:;()$&@\"", ".,?!'"]
        case .symbols: ["[]{}#%^*+=", "_\\|~<>€£¥•", ".,?!'"]
        }
    }

    var body: some View {
        GeometryReader { geo in
            let u = geo.size.width / 10
            VStack(spacing: 10) {
                row(rows[0], width: u - keyGap)
                row(rows[1], width: u - keyGap)
                HStack(spacing: keyGap) {
                    thirdRowLeft.frame(width: u * 1.3)
                    if model.layer == .letters {
                        Spacer(minLength: 0)
                        row(rows[2], width: u - keyGap)
                        Spacer(minLength: 0)
                    } else {
                        ForEach(Array(rows[2]), id: \.self) { c in
                            charKey(String(c)).frame(maxWidth: .infinity)
                        }
                    }
                    DeleteKey(kb: kb).frame(width: u * 1.3)
                }
                .frame(height: keyHeight)
                .zIndex(1)
                HStack(spacing: keyGap) {
                    Button(model.layer == .letters ? "123" : "ABC") {
                        kb.setLayer(model.layer == .letters ? .numbers : .letters)
                    }
                    .buttonStyle(KeyStyle(special: true))
                    .frame(width: u * 1.3)
                    Button { kb.setLayer(.emoji) } label: { Image(systemName: "face.smiling") }
                        .buttonStyle(KeyStyle(special: true))
                        .frame(width: u * 1.1)
                    if model.showsGlobe {
                        Button(action: kb.nextKeyboard) { Image(systemName: "globe") }
                            .buttonStyle(KeyStyle(special: true))
                            .frame(width: u * 1.1)
                    }
                    Button("space", action: kb.space).buttonStyle(KeyStyle())
                    Button("return", action: kb.newline)
                        .buttonStyle(KeyStyle(special: true))
                        .frame(width: u * 2.1)
                }
                .frame(height: keyHeight)
            }
            .font(.system(size: 16))
        }
        .frame(height: areaHeight)
        .padding(.top, 4)
    }

    private func row(_ keys: String, width: CGFloat) -> some View {
        HStack(spacing: keyGap) {
            ForEach(Array(keys), id: \.self) { c in
                charKey(String(c)).frame(width: width)
            }
        }
        .frame(height: keyHeight)
    }

    private func charKey(_ c: String) -> some View {
        let shown = model.layer == .letters && model.shift != .off ? c.uppercased() : c
        return Button { kb.type(c) } label: {
            Text(shown).font(.system(size: 22))
        }
        .buttonStyle(CharKeyStyle(popup: shown))
    }

    @ViewBuilder private var thirdRowLeft: some View {
        switch model.layer {
        case .letters, .emoji:
            Button(action: kb.tapShift) {
                Image(systemName: model.shift == .locked ? "capslock.fill" : model.shift == .once ? "shift.fill" : "shift")
            }
            .buttonStyle(KeyStyle(special: model.shift == .off))
        case .numbers:
            Button("#+=") { kb.setLayer(.symbols) }.buttonStyle(KeyStyle(special: true))
        case .symbols:
            Button("123") { kb.setLayer(.numbers) }.buttonStyle(KeyStyle(special: true))
        }
    }
}

private struct EmojiPanel: View {
    let kb: KeyboardViewController
    @State private var recent = Emoji.recent

    private let grid = Array(repeating: GridItem(.fixed(38), spacing: 4), count: 5)

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: grid, alignment: .top, spacing: 4, pinnedViews: [.sectionHeaders]) {
                    if !recent.isEmpty { section("Recent", recent) }
                    ForEach(Emoji.groups, id: \.name) { g in section(g.name, g.list) }
                }
                .padding(.horizontal, 4)
            }
            HStack(spacing: keyGap) {
                Button("ABC") { kb.setLayer(.letters) }
                    .buttonStyle(KeyStyle(special: true))
                    .frame(width: 70)
                Button("space", action: kb.space).buttonStyle(KeyStyle())
                DeleteKey(kb: kb).frame(width: 60)
            }
            .frame(height: keyHeight)
        }
        .frame(height: areaHeight)
        .padding(.top, 4)
        .onAppear { recent = Emoji.recent }
    }

    private func section(_ name: String, _ list: [String]) -> some View {
        Section {
            ForEach(Array(list.enumerated()), id: \.offset) { _, e in
                Button { kb.emoji(e) } label: {
                    Text(e).font(.system(size: 30)).frame(width: 40, height: 38)
                }
            }
        } header: {
            Text(name.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 14)
        }
    }
}

private struct DeleteKey: View {
    let kb: KeyboardViewController
    @State private var timer: Timer?
    @State private var down = false

    var body: some View {
        Image(systemName: down ? "delete.left.fill" : "delete.left")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KeyFill(special: !down))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !down else { return }
                        down = true
                        kb.delete()
                        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { _ in
                            timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in kb.delete() }
                        }
                    }
                    .onEnded { _ in
                        down = false
                        timer?.invalidate()
                        timer = nil
                    }
            )
    }
}

private struct KeyStyle: ButtonStyle {
    var special = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KeyFill(special: configuration.isPressed ? !special : special))
            .contentShape(Rectangle())
    }
}

private struct CharKeyStyle: ButtonStyle {
    let popup: String

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KeyFill(special: false))
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if configuration.isPressed {
                    Text(popup)
                        .font(.system(size: 34))
                        .foregroundStyle(Color.primary)
                        .frame(width: 50, height: 58)
                        .background(KeyFill(special: false))
                        .offset(y: -keyHeight + 4)
                        .allowsHitTesting(false)
                }
            }
            .zIndex(configuration.isPressed ? 1 : 0)
    }
}

private struct KeyFill: View {
    var special: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(scheme == .dark
                  ? (special ? Color(white: 0.27) : Color(white: 0.42))
                  : (special ? Color(red: 0.68, green: 0.70, blue: 0.74) : Color.white))
            .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 1)
    }
}
