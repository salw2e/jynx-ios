import SwiftUI

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    let kb: KeyboardViewController

    var body: some View {
        VStack(spacing: 0) {
            Bar(model: model, kb: kb)
                .frame(height: model.metrics.bar)
            Group {
                if model.layer == .emoji {
                    EmojiPanel(model: model, kb: kb)
                } else {
                    Keys(model: model, kb: kb)
                }
            }
            .frame(height: model.metrics.area)
            .padding(.horizontal, 3)
            .padding(.top, 4)
            .padding(.bottom, 6)
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
                .frame(maxWidth: 110, alignment: .leading)
                .padding(.leading, 6)
                .accessibilityIdentifier("tone-button")
                Suggestions(model: model, kb: kb)
                Button(action: kb.fix) {
                    Text("Fix")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(.white)
                }
                .padding(.trailing, 6)
                .accessibilityIdentifier("fix")
            case .tones:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Tone.allCases, id: \.self) { t in
                            Chip(label: t.label, on: model.toneID == t.rawValue) { kb.chooseTone(t.rawValue) }
                        }
                        ForEach(model.customTones) { t in
                            Chip(label: t.name, on: model.toneID == t.id) { kb.chooseTone(t.id) }
                        }
                        Divider().frame(height: 22)
                        Chip(label: model.autocorrect ? "Autocorrect on" : "Autocorrect off", on: false, action: kb.toggleAutocorrect)
                            .accessibilityIdentifier("autocorrect")
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 4)
                }
                CloseButton(kb: kb)
            case .fixing:
                ProgressView().padding(.leading, 14)
                Text("Fixing…").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            case let .done(note, warning):
                Image(systemName: warning == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(warning == nil ? Color.green : Color.orange)
                    .padding(.leading, 14)
                Text(warning ?? note)
                    .font(.footnote)
                    .foregroundStyle(warning == nil ? Color.secondary : Color.orange)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                if model.canUndo {
                    Button("Undo", action: kb.undoFix).font(.subheadline.bold()).accessibilityIdentifier("undo")
                }
                CloseButton(kb: kb)
            case let .error(message):
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.orange)
                    .padding(.leading, 14)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .accessibilityIdentifier("bar-message")
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
            if !model.typed.isEmpty {
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

private struct Chip: View {
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(label, action: action)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
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
        .accessibilityIdentifier("close-bar")
    }
}

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
        let m = model.metrics
        GeometryReader { geo in
            let u = geo.size.width / 10
            VStack(spacing: m.gap) {
                row(rows[0], width: u - 6)
                row(rows[1], width: u - 6)
                HStack(spacing: 6) {
                    thirdRowLeft.frame(width: u * 1.3)
                    if model.layer == .letters {
                        Spacer(minLength: 0)
                        row(rows[2], width: u - 6)
                        Spacer(minLength: 0)
                    } else {
                        ForEach(Array(rows[2]), id: \.self) { c in
                            charKey(String(c), edge: 0).frame(maxWidth: .infinity)
                        }
                    }
                    DeleteKey(kb: kb).frame(width: u * 1.3)
                }
                .frame(height: m.key)
                HStack(spacing: 6) {
                    Key(kb, special: true, id: "key-layer", label: model.layer == .letters ? "numbers" : "letters", onDown: true,
                        action: { kb.setLayer(model.layer == .letters ? .numbers : .letters) }) {
                        Text(model.layer == .letters ? "123" : "ABC").font(.system(size: 16))
                    }
                    .frame(width: u * 1.3)
                    Key(kb, special: true, id: "key-emoji", label: "emoji", onDown: true, action: { kb.setLayer(.emoji) }) {
                        Image(systemName: "face.smiling").font(.system(size: 19))
                    }
                    .frame(width: u * 1.1)
                    if model.showsGlobe {
                        Key(kb, special: true, id: "key-globe", label: "next keyboard", action: kb.nextKeyboard) {
                            Image(systemName: "globe").font(.system(size: 19))
                        }
                        .frame(width: u * 1.1)
                    }
                    SpaceKey(kb: kb)
                    Key(kb, special: model.returnLabel == "return", accent: model.returnLabel != "return",
                        id: "key-return", label: model.returnLabel, action: kb.newline) {
                        Text(model.returnLabel).font(.system(size: 16))
                    }
                    .frame(width: u * 2.1)
                }
                .frame(height: m.key)
            }
        }
    }

    private func row(_ keys: String, width: CGFloat) -> some View {
        let chars = Array(keys)
        return HStack(spacing: 6) {
            ForEach(chars.indices, id: \.self) { i in
                charKey(String(chars[i]), edge: i == 0 ? 1 : i == chars.count - 1 ? -1 : 0).frame(width: width)
            }
        }
        .frame(height: model.metrics.key)
    }

    private func charKey(_ c: String, edge: CGFloat) -> some View {
        let shown = model.layer == .letters && model.shift != .off ? c.uppercased() : c
        return Key(kb, id: "key-\(c)", label: shown, popup: shown, popupShift: edge * 9, action: { kb.type(c) }) {
            Text(shown).font(.system(size: model.compact ? 19 : 22))
        }
    }

    @ViewBuilder private var thirdRowLeft: some View {
        switch model.layer {
        case .letters, .emoji:
            Key(kb, special: model.shift == .off, id: "key-shift", label: "shift", onDown: true, action: kb.tapShift) {
                Image(systemName: model.shift == .locked ? "capslock.fill" : model.shift == .once ? "shift.fill" : "shift")
                    .font(.system(size: 18))
            }
        case .numbers:
            Key(kb, special: true, id: "key-symbols", label: "more symbols", onDown: true, action: { kb.setLayer(.symbols) }) {
                Text("#+=").font(.system(size: 16))
            }
        case .symbols:
            Key(kb, special: true, id: "key-numbers", label: "numbers", onDown: true, action: { kb.setLayer(.numbers) }) {
                Text("123").font(.system(size: 16))
            }
        }
    }
}

private struct Key<Content: View>: View {
    let kb: KeyboardViewController
    let special: Bool
    let accent: Bool
    let ident: String
    let label: String
    let popup: String?
    let popupShift: CGFloat
    let onDown: Bool
    let action: () -> Void
    let content: Content
    @State private var down = false
    @State private var token = UUID()

    init(_ kb: KeyboardViewController, special: Bool = false, accent: Bool = false, id: String, label: String,
         popup: String? = nil, popupShift: CGFloat = 0, onDown: Bool = false,
         action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.kb = kb
        self.special = special
        self.accent = accent
        self.ident = id
        self.label = label
        self.popup = popup
        self.popupShift = popupShift
        self.onDown = onDown
        self.action = action
        self.content = content()
    }

    var body: some View {
        content
            .foregroundStyle(accent ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KeyFill(special: popup == nil && down ? !special : special, accent: accent))
            .overlay(alignment: .bottom) {
                if down, let popup {
                    Text(popup)
                        .font(.system(size: 34))
                        .foregroundStyle(Color.primary)
                        .frame(width: 52, height: 58)
                        .background(KeyFill(special: false))
                        .offset(x: popupShift, y: -kb.model.metrics.key + 2)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !down else { return }
                        down = true
                        if onDown { kb.pressNow(action) } else { kb.press(token, action) }
                    }
                    .onEnded { _ in
                        down = false
                        if !onDown { kb.release(token) }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityIdentifier(ident)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { kb.pressNow(action) }
    }
}

private struct SpaceKey: View {
    let kb: KeyboardViewController
    @State private var down = false
    @State private var moving = false
    @State private var anchor: CGFloat = 0
    @State private var token = UUID()

    var body: some View {
        Text("space")
            .font(.system(size: 16))
            .foregroundStyle(moving ? Color.secondary : Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KeyFill(special: down && !moving))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !down {
                            down = true
                            anchor = g.location.x
                            kb.press(token, kb.space)
                        }
                        let dx = g.location.x - anchor
                        if !moving, abs(dx) > 14 {
                            moving = true
                            kb.cancel(token)
                            anchor = g.location.x
                        } else if moving, abs(dx) >= 9 {
                            let steps = Int(dx / 9)
                            kb.moveCursor(steps)
                            anchor += CGFloat(steps) * 9
                        }
                    }
                    .onEnded { _ in
                        if !moving { kb.release(token) }
                        down = false
                        moving = false
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("space")
            .accessibilityIdentifier("key-space")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { kb.pressNow(kb.space) }
    }
}

private struct DeleteKey: View {
    let kb: KeyboardViewController
    @State private var timer: Timer?
    @State private var down = false

    var body: some View {
        Image(systemName: down ? "delete.left.fill" : "delete.left")
            .font(.system(size: 18))
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KeyFill(special: !down))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !down else { return }
                        down = true
                        kb.pressNow(kb.delete)
                        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { _ in
                            timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in kb.pressNow(kb.delete) }
                        }
                    }
                    .onEnded { _ in stop() }
            )
            .onDisappear(perform: stop)
            .accessibilityElement()
            .accessibilityLabel("delete")
            .accessibilityIdentifier("key-delete")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { kb.pressNow(kb.delete) }
    }

    private func stop() {
        down = false
        timer?.invalidate()
        timer = nil
    }
}

private struct EmojiPanel: View {
    @ObservedObject var model: KeyboardModel
    let kb: KeyboardViewController
    @State private var recent = Emoji.recent

    private var groups: [(name: String, icon: String, list: [String])] {
        (recent.isEmpty ? [] : [("Recent", "clock", recent)]) + Emoji.groups
    }

    var body: some View {
        let m = model.metrics
        let gridHeight = m.area - m.key - 6
        let cell = (gridHeight - 3 * 2) / 4
        ScrollViewReader { reader in
            VStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: Array(repeating: GridItem(.fixed(cell), spacing: 2), count: 4), spacing: 2) {
                        ForEach(groups, id: \.name) { g in
                            ForEach(g.list.indices, id: \.self) { i in
                                Button { kb.emoji(g.list[i]) } label: {
                                    Text(g.list[i]).font(.system(size: cell * 0.8)).frame(width: cell + 4, height: cell)
                                }
                                .id("\(g.name)-\(i)")
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: gridHeight)
                HStack(spacing: 6) {
                    Key(kb, special: true, id: "key-letters", label: "letters", onDown: true, action: { kb.setLayer(.letters) }) {
                        Text("ABC").font(.system(size: 16))
                    }
                    .frame(width: 58)
                    ForEach(groups, id: \.name) { g in
                        Button {
                            withAnimation { reader.scrollTo("\(g.name)-0", anchor: .leading) }
                        } label: {
                            Image(systemName: g.icon).font(.system(size: 15)).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(g.name)
                    }
                    DeleteKey(kb: kb).frame(width: 52)
                }
                .frame(height: m.key)
            }
        }
        .onAppear { recent = Emoji.recent }
    }
}

private struct KeyFill: View {
    var special: Bool
    var accent = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(accent ? Color.accentColor
                  : scheme == .dark ? (special ? Color(white: 0.27) : Color(white: 0.42))
                  : (special ? Color(red: 0.68, green: 0.70, blue: 0.74) : Color.white))
            .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 1)
    }
}
