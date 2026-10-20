import SwiftUI
import UIKit

enum Layer { case letters, numbers, symbols, emoji }
enum Shift { case off, once, locked }

enum BarState: Equatable {
    case main
    case tones
    case fixing
    case done(note: String, warning: String?)
    case error(String)
}

final class KeyboardModel: ObservableObject {
    @Published var layer = Layer.letters
    @Published var shift = Shift.once
    @Published var bar = BarState.main
    @Published var canUndo = false
    @Published var showsGlobe = true
    @Published var typed = ""
    @Published var suggestions: [String] = []
    @Published var correcting = false
    @Published var customTones: [CustomTone] = {
        guard let d = UserDefaults.standard.data(forKey: "customTones") else { return [] }
        return (try? JSONDecoder().decode([CustomTone].self, from: d)) ?? []
    }() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(customTones), forKey: "customTones") }
    }
    @Published var toneID = UserDefaults.standard.string(forKey: "tone") ?? Tone.keep.rawValue {
        didSet { UserDefaults.standard.set(toneID, forKey: "tone") }
    }

    var custom: CustomTone? { customTones.first { $0.id == toneID } }
    var toneLabel: String { custom?.name ?? (Tone(rawValue: toneID) ?? .keep).label }
}

final class KeyboardViewController: UIInputViewController {
    let model = KeyboardModel()
    private let speller = Speller()
    private var undo: (original: String, fixed: String)?
    private var pending: (word: String, fix: String)?
    private var lastCorrection: (original: String, corrected: String, sep: String)?
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
        typed()
        guard hasFullAccess else { return }
        Task { @MainActor in
            if let tones = try? await Api.tones() { model.customTones = tones }
            if model.custom == nil && Tone(rawValue: model.toneID) == nil { model.toneID = Tone.keep.rawValue }
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        autoShift()
        refreshSuggestions()
    }

    private var proxy: UITextDocumentProxy { textDocumentProxy }

    func type(_ key: String) {
        haptic.impactOccurred()
        lastCorrection = nil
        if ".,?!".contains(key) { autocorrect(before: key) }
        proxy.insertText(model.layer == .letters && model.shift != .off ? key.uppercased() : key)
        if model.shift == .once { model.shift = .off }
        typed()
    }

    func space() {
        haptic.impactOccurred()
        lastCorrection = nil
        autocorrect(before: " ")
        let before = proxy.documentContextBeforeInput ?? ""
        if lastCorrection == nil, Date().timeIntervalSince(lastSpace) < 0.4, before.hasSuffix(" "),
           let prev = before.dropLast().last, prev.isLetter || prev.isNumber {
            proxy.deleteBackward()
            proxy.insertText(". ")
            lastSpace = .distantPast
        } else {
            proxy.insertText(" ")
            lastSpace = Date()
        }
        if model.layer != .emoji { model.layer = .letters }
        typed()
    }

    func newline() {
        haptic.impactOccurred()
        lastCorrection = nil
        autocorrect(before: "\n")
        proxy.insertText("\n")
        typed()
    }

    func delete() {
        haptic.impactOccurred()
        let before = proxy.documentContextBeforeInput ?? ""
        if let c = lastCorrection, before.hasSuffix(c.corrected + c.sep) {
            replace((c.corrected + c.sep).count, with: c.original)
            speller.learn(c.original)
        } else {
            proxy.deleteBackward()
        }
        lastCorrection = nil
        typed()
    }

    func emoji(_ e: String) {
        haptic.impactOccurred()
        lastCorrection = nil
        proxy.insertText(e)
        Emoji.used(e)
        typed()
    }

    func pick(_ suggestion: String) {
        haptic.impactOccurred()
        guard !model.typed.isEmpty else { return }
        replace(model.typed.count, with: suggestion + " ")
        lastCorrection = nil
        pending = nil
        typed()
    }

    func keepTyped() {
        haptic.impactOccurred()
        guard !model.typed.isEmpty else { return }
        if model.correcting { speller.learn(model.typed) }
        pending = nil
        lastCorrection = nil
        proxy.insertText(" ")
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
        refreshSuggestions()
    }

    func nextKeyboard() {
        advanceToNextInputMode()
    }

    func openTones() {
        model.bar = .tones
    }

    func chooseTone(_ id: String) {
        model.toneID = id
        model.bar = .main
    }

    func closeBar() {
        model.bar = .main
    }

    private func typed() {
        if model.bar != .fixing {
            model.bar = .main
            undo = nil
            model.canUndo = false
        }
        autoShift()
        refreshSuggestions()
    }

    private func autoShift() {
        guard model.shift != .locked else { return }
        let before = proxy.documentContextBeforeInput ?? ""
        model.shift = atSentenceStart(Substring(before)) ? .once : .off
    }

    private func atSentenceStart(_ s: Substring) -> Bool {
        s.isEmpty || s.hasSuffix("\n") || [". ", "! ", "? "].contains { s.hasSuffix($0) }
    }

    private func currentWord() -> (word: String, sentenceStart: Bool)? {
        let before = proxy.documentContextBeforeInput ?? ""
        let word = String(before.reversed().prefix { $0.isLetter || $0 == "'" }.reversed())
        guard !word.isEmpty else { return nil }
        let rest = before.dropLast(word.count)
        if let p = rest.last, !(p.isWhitespace || "(\"".contains(p)) { return nil }
        return (word, atSentenceStart(rest))
    }

    private func refreshSuggestions() {
        guard model.layer != .emoji, let cur = currentWord() else {
            model.typed = ""
            model.suggestions = []
            model.correcting = false
            pending = nil
            return
        }
        let word = cur.word
        let fix = speller.correction(for: word, sentenceStart: cur.sentenceStart)
        model.typed = word
        model.suggestions = speller.suggestions(for: word, correction: fix)
        model.correcting = fix != nil
        pending = fix.map { (word, $0) }
    }

    private func autocorrect(before sep: String) {
        guard let p = pending, let word = currentWord()?.word, word == p.word else { return }
        replace(word.count, with: p.fix)
        lastCorrection = (word, p.fix, sep)
        pending = nil
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
                let r = try await Api.fix(original, tone: Tone(rawValue: model.toneID) ?? .keep, custom: model.custom)
                guard !Task.isCancelled else { return }
                guard proxy.documentContextBeforeInput == original else {
                    model.bar = .error("Your message changed while fixing. Tap Fix again.")
                    return
                }
                replace(original.count, with: r.fixed)
                undo = (original, r.fixed)
                lastCorrection = nil
                refreshSuggestions()
                model.canUndo = true
                model.bar = .done(note: r.changes.first ?? "Fixed.", warning: r.heads_up)
            } catch {
                model.bar = .error((error as? ApiError)?.message ?? "The fixer had a problem. Try again.")
            }
        }
    }

    func undoFix() {
        if let u = undo, proxy.documentContextBeforeInput?.hasSuffix(u.fixed) == true {
            replace(u.fixed.count, with: u.original)
        }
        undo = nil
        model.canUndo = false
        model.bar = .main
        autoShift()
        refreshSuggestions()
    }

    private func replace(_ count: Int, with text: String) {
        for _ in 0..<count { proxy.deleteBackward() }
        proxy.insertText(text)
    }
}
