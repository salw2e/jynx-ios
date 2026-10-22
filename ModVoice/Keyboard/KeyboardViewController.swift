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

struct Metrics {
    let bar: CGFloat
    let key: CGFloat
    let gap: CGFloat
    var area: CGFloat { key * 4 + gap * 3 }
    var total: CGFloat { bar + area + 10 }
}

final class KeyboardModel: ObservableObject {
    @Published var layer = Layer.letters
    @Published var shift = Shift.once
    @Published var bar = BarState.main
    @Published var canUndo = false
    @Published var showsGlobe = true
    @Published var compact = false
    @Published var returnLabel = "return"
    @Published var typed = ""
    @Published var suggestions: [String] = []
    @Published var correcting = false
    // Off by default: this speller doesn't know slang, names or Khmer-romanised words, so auto-replacing while typing
    // changed words the user meant ("anh", "hg", "kdmv"...). The Autocorrect chip in the tone bar turns it on.
    @Published var autocorrect = UserDefaults.standard.object(forKey: "autocorrect") as? Bool ?? false {
        didSet { UserDefaults.standard.set(autocorrect, forKey: "autocorrect") }
    }
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
    var metrics: Metrics { compact ? Metrics(bar: 38, key: 32, gap: 6) : Metrics(bar: 46, key: 43, gap: 10) }
}

final class ClickInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

final class KeyboardViewController: UIInputViewController {
    let model = KeyboardModel()
    private let speller = Speller()
    private var height: NSLayoutConstraint?
    private var held: [(id: UUID, fire: () -> Void)] = []
    private var undo: (original: String, fixed: String)?
    private var pending: (word: String, fix: String)?
    private var lastCorrection: (original: String, corrected: String, sep: String)?
    private var fixTask: Task<Void, Never>?
    private var lastShiftTap = Date.distantPast
    private var lastSpace = Date.distantPast
    private var guessWork: DispatchWorkItem?
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    // The standard keyboard click plus a light tap, fired the moment a key goes down. The click only sounds when the
    // user has Keyboard Clicks on (same as the system keyboard); the haptic is subtle, like the stock keys.
    func click() {
        UIDevice.current.playInputClick()
        haptic.impactOccurred(intensity: 0.6)
    }

    override func loadView() {
        view = ClickInputView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: model.metrics.total),
                              inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isMultipleTouchEnabled = true
        let host = UIHostingController(rootView: KeyboardView(model: model, kb: self))
        host.view.backgroundColor = .clear
        host.view.isMultipleTouchEnabled = true
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
        let h = view.heightAnchor.constraint(equalToConstant: model.metrics.total)
        h.priority = UILayoutPriority(999)
        h.isActive = true
        height = h
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let compact = traitCollection.verticalSizeClass == .compact
        if compact != model.compact {
            model.compact = compact
            height?.constant = model.metrics.total
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        haptic.prepare()
        model.showsGlobe = needsInputModeSwitchKey
        model.bar = .main
        model.layer = .letters
        refresh()
        guard hasFullAccess else { return }
        Task { @MainActor in
            if let tones = try? await Api.tones() { model.customTones = tones }
            if model.custom == nil && Tone(rawValue: model.toneID) == nil { model.toneID = Tone.keep.rawValue }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        held.removeAll()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        refresh()
    }

    private var proxy: UITextDocumentProxy { textDocumentProxy }

    func press(_ id: UUID, _ fire: @escaping () -> Void) {
        let earlier = held
        held = [(id, fire)]
        earlier.forEach { $0.fire() }
        click()
    }

    func release(_ id: UUID) {
        guard let i = held.firstIndex(where: { $0.id == id }) else { return }
        held.remove(at: i).fire()
    }

    func cancel(_ id: UUID) {
        held.removeAll { $0.id == id }
    }

    func pressNow(_ action: () -> Void) {
        let earlier = held
        held = []
        earlier.forEach { $0.fire() }
        click()
        action()
    }

    func type(_ key: String) {
        lastCorrection = nil
        if ".,?!".contains(key) { autocorrect(before: key) }
        proxy.insertText(model.layer == .letters && model.shift != .off ? key.uppercased() : key)
        if model.shift == .once { model.shift = .off }
        if key == "'" && model.layer != .letters { model.layer = .letters }
        typed()
    }

    func space() {
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
        if model.layer == .numbers || model.layer == .symbols { model.layer = .letters }
        typed()
    }

    func newline() {
        lastCorrection = nil
        autocorrect(before: "\n")
        proxy.insertText("\n")
        typed()
    }

    func delete() {
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

    func moveCursor(_ by: Int) {
        proxy.adjustTextPosition(byCharacterOffset: by)
        lastCorrection = nil
        refresh()
    }

    func emoji(_ e: String) {
        click()
        lastCorrection = nil
        proxy.insertText(e)
        Emoji.used(e)
        typed()
    }

    func pick(_ suggestion: String) {
        click()
        guard !model.typed.isEmpty else { return }
        replace(model.typed.count, with: suggestion + " ")
        lastCorrection = nil
        pending = nil
        typed()
    }

    func keepTyped() {
        click()
        guard !model.typed.isEmpty else { return }
        if model.correcting { speller.learn(model.typed) }
        pending = nil
        lastCorrection = nil
        proxy.insertText(" ")
        typed()
    }

    func tapShift() {
        let now = Date()
        if now.timeIntervalSince(lastShiftTap) < 0.3 {
            model.shift = .locked
        } else {
            model.shift = model.shift == .off ? .once : .off
        }
        lastShiftTap = now
    }

    func setLayer(_ layer: Layer) {
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

    func toggleAutocorrect() {
        model.autocorrect.toggle()
        refreshSuggestions()
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
        refresh()
    }

    private func refresh() {
        autoShift()
        refreshSuggestions()
        model.returnLabel = switch proxy.returnKeyType ?? .default {
        case .send: "send"
        case .go: "go"
        case .search, .google, .yahoo: "search"
        case .done: "done"
        case .next: "next"
        case .join: "join"
        case .route: "route"
        default: "return"
        }
    }

    private func autoShift() {
        guard model.shift != .locked else { return }
        let before = proxy.documentContextBeforeInput ?? ""
        let s: Shift = atSentenceStart(Substring(before)) ? .once : .off
        if model.shift != s { model.shift = s }   // don't churn @Published (and the key grid) when unchanged
    }

    private func atSentenceStart(_ s: Substring) -> Bool {
        s.isEmpty || s.hasSuffix("\n") || [". ", "! ", "? "].contains { s.hasSuffix($0) }
    }

    private func currentWord() -> (word: String, sentenceStart: Bool)? {
        let before = proxy.documentContextBeforeInput ?? ""
        let word = String(before.reversed().prefix { $0.isLetter || $0 == "'" }.reversed())
        guard !word.isEmpty, (proxy.documentContextAfterInput ?? "").first?.isLetter != true else { return nil }
        let rest = before.dropLast(word.count)
        if let p = rest.last, !(p.isWhitespace || "(\"".contains(p)) { return nil }
        return (word, atSentenceStart(rest))
    }

    private func refreshSuggestions() {
        guessWork?.cancel()
        guard model.layer != .emoji, let cur = currentWord() else {
            model.typed = ""
            model.suggestions = []
            model.correcting = false
            pending = nil
            return
        }
        model.typed = cur.word   // the word itself is cheap; show it right away
        // UITextChecker (guesses/completions) costs tens of ms. Running it on every keystroke blocks the main thread,
        // so fast taps land on a stalled thread and get dropped. The suggestion slots are cosmetic, so defer the
        // checker until typing pauses; a burst keeps cancelling and rescheduling it, and it never runs mid-burst.
        let work = DispatchWorkItem { [weak self] in self?.computeGuesses(cur) }
        guessWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func computeGuesses(_ cur: (word: String, sentenceStart: Bool)) {
        guard currentWord()?.word == cur.word else { return }   // word moved on; drop this stale result
        let fix = model.autocorrect ? speller.correction(for: cur.word, sentenceStart: cur.sentenceStart) : nil
        model.suggestions = speller.suggestions(for: cur.word, correction: fix)
        model.correcting = fix != nil
        pending = fix.map { (cur.word, $0) }
    }

    private func autocorrect(before sep: String) {
        // Compute the fix on the spot: the per-keystroke guess is debounced and may not have run yet.
        guard model.autocorrect, let cur = currentWord(),
              let fix = speller.correction(for: cur.word, sentenceStart: cur.sentenceStart) else { return }
        replace(cur.word.count, with: fix)
        lastCorrection = (cur.word, fix, sep)
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
                refresh()
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
        refresh()
    }

    private func replace(_ count: Int, with text: String) {
        for _ in 0..<count { proxy.deleteBackward() }
        proxy.insertText(text)
    }
}
