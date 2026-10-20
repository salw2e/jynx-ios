import SwiftUI

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    let kb: KeyboardViewController

    var body: some View {
        VStack(spacing: 0) {
            Bar(model: model, kb: kb)
                .frame(height: 46)
            Keys(model: model, kb: kb)
                .padding(.horizontal, 3)
                .padding(.bottom, 4)
        }
    }
}

private struct Bar: View {
    @ObservedObject var model: KeyboardModel
    let kb: KeyboardViewController

    var body: some View {
        HStack(spacing: 8) {
            switch model.bar {
            case .tones:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Tone.allCases, id: \.self) { t in
                            Button(t.label) { model.tone = t }
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(model.tone == t ? Color.accentColor : Color.primary.opacity(0.08)))
                                .foregroundStyle(model.tone == t ? Color.white : Color.primary)
                        }
                    }
                    .padding(.leading, 8)
                }
                Button(action: kb.fix) {
                    Label("Fix", systemImage: "checkmark")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(.white)
                }
                .padding(.trailing, 8)
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

private struct Keys: View {
    @ObservedObject var model: KeyboardModel
    let kb: KeyboardViewController

    private let gap: CGFloat = 6
    private let height: CGFloat = 43

    private var rows: [String] {
        switch model.layer {
        case .letters: ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        case .numbers: ["1234567890", "-/:;()$&@\"", ".,?!'"]
        case .symbols: ["[]{}#%^*+=", "_\\|~<>€£¥•", ".,?!'"]
        }
    }

    var body: some View {
        GeometryReader { geo in
            let u = geo.size.width / 10
            VStack(spacing: 10) {
                row(rows[0], width: u - gap)
                row(rows[1], width: u - gap)
                HStack(spacing: gap) {
                    thirdRowLeft.frame(width: u * 1.3)
                    if model.layer == .letters {
                        Spacer(minLength: 0)
                        row(rows[2], width: u - gap)
                        Spacer(minLength: 0)
                    } else {
                        ForEach(Array(rows[2]), id: \.self) { c in
                            charKey(String(c)).frame(maxWidth: .infinity)
                        }
                    }
                    DeleteKey(kb: kb).frame(width: u * 1.3)
                }
                .frame(height: height)
                HStack(spacing: gap) {
                    Button(model.layer == .letters ? "123" : "ABC") {
                        kb.setLayer(model.layer == .letters ? .numbers : .letters)
                    }
                    .buttonStyle(KeyStyle(special: true))
                    .frame(width: u * 1.3)
                    if model.showsGlobe {
                        Button(action: kb.nextKeyboard) { Image(systemName: "globe") }
                            .buttonStyle(KeyStyle(special: true))
                            .frame(width: u * 1.1)
                    }
                    Button("space", action: kb.space).buttonStyle(KeyStyle())
                    Button("return", action: kb.newline)
                        .buttonStyle(KeyStyle(special: true))
                        .frame(width: u * 2.2)
                }
                .frame(height: height)
            }
            .font(.system(size: 16))
        }
        .frame(height: height * 4 + 30)
        .padding(.top, 4)
    }

    private func row(_ keys: String, width: CGFloat) -> some View {
        HStack(spacing: gap) {
            ForEach(Array(keys), id: \.self) { c in
                charKey(String(c)).frame(width: width)
            }
        }
        .frame(height: height)
    }

    private func charKey(_ c: String) -> some View {
        Button { kb.type(c) } label: {
            Text(model.layer == .letters && model.shift != .off ? c.uppercased() : c)
                .font(.system(size: 22))
        }
        .buttonStyle(KeyStyle())
    }

    @ViewBuilder private var thirdRowLeft: some View {
        switch model.layer {
        case .letters:
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
