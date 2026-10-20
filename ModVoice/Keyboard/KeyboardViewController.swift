import SwiftUI
import UIKit

enum Layer { case letters, numbers, symbols }
enum Shift { case off, once, locked }

enum BarState: Equatable {
    case tones
    case fixing
    case done(note: String, warning: String?)
    case error(String)
}

final class KeyboardModel: ObservableObject {
    @Published var layer = Layer.letters
    @Published var shift = Shift.once
    @Published var bar = BarState.tones
    @Published var canUndo = false
    @Published var showsGlobe = true
    @Published var tone = Tone(rawValue: UserDefaults.standard.string(forKey: "tone") ?? "") ?? .keep {
        didSet { UserDefaults.standard.set(tone.rawValue, forKey: "tone") }
    }
}

final class KeyboardViewController: UIInputViewController {
    let model = KeyboardModel()
    private var undo: (original: String, fixed: String)?
    private var fixTask: Task<Void, Never>?
    private var lastShiftTap = Date.distantPast
    private var lastSpace = Date.distantPast
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: KeyboardView(model: model, kb: self))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let height = view.heightAnchor.constraint(equalToConstant: 272)
        height.priority = UILayoutPriority(999)
        height.isActive = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.showsGlobe = needsInputModeSwitchKey
        autoShift()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        autoShift()
    }

    private var proxy: UITextDocumentProxy { textDocumentProxy }

    func type(_ key: String) {
        haptic.impactOccurred()
        proxy.insertText(model.layer == .letters && model.shift != .off ? key.uppercased() : key)
        if model.shift == .once { model.shift = .off }
        typed()
    }

    func space() {
        haptic.impactOccurred()
        let before = proxy.documentContextBeforeInput ?? ""
        if Date().timeIntervalSince(lastSpace) < 0.4, before.hasSuffix(" "),
           let prev = before.dropLast().last, prev.isLetter || prev.isNumber {
            proxy.deleteBackward()
            proxy.insertText(". ")
            lastSpace = .distantPast
        } else {
            proxy.insertText(" ")
            lastSpace = Date()
        }
        model.layer = .letters
        typed()
    }

    func newline() {
        haptic.impactOccurred()
        proxy.insertText("\n")
        typed()
    }

    func delete() {
        haptic.impactOccurred()
        proxy.deleteBackward()
        typed()
    }

    func tapShift() {
        haptic.impactOccurred()
        let now = Date()
        if now.timeIntervalSince(lastShiftTap) < 0.3 {
            model.shift = .locked
        } else {
            model.shift = model.shift == .off ? .once : .off
        }
        lastShiftTap = now
    }

    func setLayer(_ layer: Layer) {
        haptic.impactOccurred()
        model.layer = layer
    }

    func nextKeyboard() {
        advanceToNextInputMode()
    }

    private func typed() {
        if model.bar != .fixing {
            model.bar = .tones
            undo = nil
            model.canUndo = false
        }
        autoShift()
    }

    private func autoShift() {
        guard model.shift != .locked else { return }
        let before = proxy.documentContextBeforeInput ?? ""
        let start = before.isEmpty || before.hasSuffix("\n") || [". ", "! ", "? "].contains { before.hasSuffix($0) }
        model.shift = start ? .once : .off
    }

    func closeBar() {
        model.bar = .tones
    }

    func fix() {
        guard hasFullAccess else {
            model.bar = .error("Turn on Allow Full Access: Settings › General › Keyboard › Keyboards › Mod Voice.")
            return
        }
        fixTask?.cancel()
        fixTask = Task { @MainActor in
            let after = proxy.documentContextAfterInput ?? ""
            if !after.isEmpty {
                proxy.adjustTextPosition(byCharacterOffset: after.count)
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            guard (proxy.documentContextAfterInput ?? "").isEmpty else {
                model.bar = .error("Move the cursor to the end of your message, then tap Fix.")
                return
            }
            let original = proxy.documentContextBeforeInput ?? ""
            guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                model.bar = .error("Type a message first.")
                return
            }
            model.bar = .fixing
            do {
                let r = try await Fixer.fix(original, tone: model.tone)
                guard !Task.isCancelled else { return }
                guard proxy.documentContextBeforeInput == original else {
                    model.bar = .error("Your message changed while fixing. Tap Fix again.")
                    return
                }
                replace(original.count, with: r.fixed)
                undo = (original, r.fixed)
                model.canUndo = true
                model.bar = .done(note: r.changes.first ?? "Fixed.", warning: r.heads_up)
            } catch {
                model.bar = .error((error as? FixError)?.message ?? "The fixer had a problem. Try again.")
            }
        }
    }

    func undoFix() {
        if let u = undo, proxy.documentContextBeforeInput?.hasSuffix(u.fixed) == true {
            replace(u.fixed.count, with: u.original)
        }
        undo = nil
        model.canUndo = false
        model.bar = .tones
        autoShift()
    }

    private func replace(_ count: Int, with text: String) {
        for _ in 0..<count { proxy.deleteBackward() }
        proxy.insertText(text)
    }
}
