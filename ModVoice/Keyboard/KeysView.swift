import Combine
import SwiftUI
import UIKit

/// The key grid, in UIKit instead of SwiftUI. Each key is a view that owns its touches, so a press registers on
/// touch-DOWN in the order fingers land, multitouch rollover works, and nothing is dropped when SwiftUI re-renders the
/// surrounding chrome after every keystroke (the old SwiftUI gestures were being cancelled mid-tap). Hit areas tile the
/// row with no dead gaps; the visible cap is inset. The top bar and the emoji panel stay in SwiftUI.
struct UIKitKeys: UIViewRepresentable {
    let kb: KeyboardViewController

    func makeUIView(context: Context) -> KeysView { KeysView(kb: kb) }
    func updateUIView(_ view: KeysView, context: Context) { view.sync() }
}

final class KeysView: UIView {
    unowned let kb: KeyboardViewController
    private var model: KeyboardModel { kb.model }
    private var rows: [[KeyButton]] = []
    private var signature = ""
    private var active = 0            // keys currently held
    private var pendingRebuild = false
    private var bag: AnyCancellable?

    // A held key (delete-repeat, space-slide) must not be yanked out from under the finger by a rebuild, so defer any
    // rebuild until every finger is up.
    func beginTouch() { active += 1 }
    func endTouch() {
        active = max(0, active - 1)
        if active == 0, pendingRebuild { pendingRebuild = false; rebuild() }
    }

    init(kb: KeyboardViewController) {
        self.kb = kb
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        rebuild()
        applyShift()
        // Observe the model directly: SwiftUI does not call updateUIView when the model changes (this view's value
        // doesn't depend on it), so a layer or shift change has to drive the rebuild from here.
        bag = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.sync() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var structure: String { "\(model.layer)-\(model.returnLabel)-\(model.showsGlobe)-\(model.compact)" }

    /// Rebuilds only when the set of keys differs (layer, return label, globe, compact). Shift flips at every sentence
    /// start, and tearing the grid down for it left a moment with no keys under the finger, so case is updated in place.
    func sync() {
        if structure != signature {
            if active > 0 { pendingRebuild = true } else { rebuild() }
        }
        applyShift()
    }

    private func applyShift() {
        let up = model.layer == .letters && model.shift != .off
        rows.forEach { $0.forEach { $0.applyShift(up: up, shift: model.shift) } }
    }

    private func rebuild() {
        signature = structure
        rows.forEach { $0.forEach { $0.removeFromSuperview() } }
        rows = layout().map { row in
            row.map { desc in
                let b = KeyButton(kb: kb, desc: desc)
                b.grid = self
                addSubview(b)
                return b
            }
        }
        // Lay the new keys out now; left to the next pass they sit at zero size and a tap in between hits nothing.
        setNeedsLayout()
        layoutIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let m = model.metrics
        let u = bounds.width / 10
        var y: CGFloat = 0
        for row in rows {
            let units = row.reduce(0) { $0 + $1.units }
            var x = (units < 9.99) ? (bounds.width - units * u) / 2 : 0   // row of 9 (asdf...) is centred
            for b in row {
                let w = b.units * u
                b.frame = CGRect(x: x, y: y, width: w, height: m.key)
                x += w
            }
            y += m.key + m.gap
        }
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        rows.forEach { $0.forEach { $0.restyle() } }
    }

    // One row's worth of key descriptions, by layer. `units` is width in key-columns (the grid is 10 wide).
    private func layout() -> [[KeyDesc]] {
        let letters = model.layer == .letters
        let caseUp = letters && model.shift != .off
        func chars(_ s: String, _ w: CGFloat = 1) -> [KeyDesc] {
            s.map { KeyDesc(.char(String($0)), id: "key-\($0)", label: String($0),
                            display: caseUp ? String($0).uppercased() : String($0), units: w, popup: true) }
        }
        let del = KeyDesc(.delete, id: "key-delete", label: "delete", symbol: "delete.left", units: 1.5, special: true)
        let bottom = bottomRow()

        switch model.layer {
        case .letters, .emoji:
            let shift = KeyDesc(.shift, id: "key-shift", label: "shift",
                                symbol: model.shift == .locked ? "capslock.fill" : model.shift == .once ? "shift.fill" : "shift",
                                units: 1.5, special: model.shift == .off)
            return [chars("qwertyuiop"), chars("asdfghjkl"), [shift] + chars("zxcvbnm") + [del], bottom]
        case .numbers:
            let toSym = KeyDesc(.go(.symbols), id: "key-symbols", label: "more symbols", display: "#+=", units: 1.5, special: true)
            return [chars("1234567890"), chars("-/:;()$&@\""), [toSym] + chars(".,?!'", 1.4) + [del], bottom]
        case .symbols:
            let toNum = KeyDesc(.go(.numbers), id: "key-numbers", label: "numbers", display: "123", units: 1.5, special: true)
            return [chars("[]{}#%^*+="), chars("_\\|~<>€£¥•"), [toNum] + chars(".,?!'", 1.4) + [del], bottom]
        }
    }

    private func bottomRow() -> [KeyDesc] {
        let letters = model.layer == .letters
        let switchKey = KeyDesc(.go(letters ? .numbers : .letters), id: "key-layer",
                                label: letters ? "numbers" : "letters", display: letters ? "123" : "ABC", units: 1.5, special: true)
        let emoji = KeyDesc(.emoji, id: "key-emoji", label: "emoji", symbol: "face.smiling", units: 1.25, special: true)
        let globe = KeyDesc(.globe, id: "key-globe", label: "next keyboard", symbol: "globe", units: 1.25, special: true)
        let retAccent = model.returnLabel != "return"
        let ret = KeyDesc(.ret, id: "key-return", label: model.returnLabel,
                          display: model.returnLabel == "return" ? nil : model.returnLabel,
                          symbol: model.returnLabel == "return" ? "return" : nil,
                          units: 1.5, special: !retAccent, accent: retAccent)
        var fixed: CGFloat = 1.5 + 1.25 + 1.5   // switch + emoji + return
        var keys = [switchKey, emoji]
        if model.showsGlobe { keys.append(globe); fixed += 1.25 }
        let space = KeyDesc(.space, id: "key-space", label: "space", display: "space", units: 10 - fixed)
        keys.append(space)
        keys.append(ret)
        return keys
    }
}

enum KeyKind {
    case char(String), space, delete, shift, ret, go(Layer), emoji, globe
}

struct KeyDesc {
    let kind: KeyKind
    let id: String
    let label: String
    var display: String?
    var symbol: String?
    let units: CGFloat
    var special = false
    var accent = false
    var popup = false

    init(_ kind: KeyKind, id: String, label: String, display: String? = nil, symbol: String? = nil,
         units: CGFloat, special: Bool = false, accent: Bool = false, popup: Bool = false) {
        self.kind = kind; self.id = id; self.label = label; self.display = display
        self.symbol = symbol; self.units = units; self.special = special; self.accent = accent; self.popup = popup
    }
}

final class KeyButton: UIView {
    unowned let kb: KeyboardViewController
    weak var grid: KeysView?
    let desc: KeyDesc
    var units: CGFloat { desc.units }

    private let cap = UIView()
    private let title = UILabel()
    private let glyph = UIImageView()
    private var popup: UIView?
    private var repeatTimer: Timer?
    private var spaceAnchor: CGFloat = 0
    private var spaceMoved = false
    private var held = 0              // fingers on this key; a second can land before the first lifts
    private var special: Bool

    init(kb: KeyboardViewController, desc: KeyDesc) {
        self.kb = kb
        self.desc = desc
        self.special = desc.special
        super.init(frame: .zero)
        isMultipleTouchEnabled = true

        cap.layer.cornerRadius = 5
        cap.layer.cornerCurve = .continuous
        cap.isUserInteractionEnabled = false
        cap.layer.shadowColor = UIColor.black.cgColor
        cap.layer.shadowOpacity = 0.3
        cap.layer.shadowRadius = 0
        cap.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(cap)

        title.textAlignment = .center
        title.text = desc.display
        title.isUserInteractionEnabled = false
        addSubview(title)

        if let s = desc.symbol {
            glyph.image = UIImage(systemName: s)
            glyph.contentMode = .center
            glyph.isUserInteractionEnabled = false
            addSubview(glyph)
        }

        isAccessibilityElement = true
        accessibilityIdentifier = desc.id
        accessibilityLabel = desc.label
        accessibilityTraits = .button   // .button so XCUITest app.buttons[...] matches these keys
        restyle()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Visible cap is inset 3pt horizontally so a 6pt gap shows between caps, while the whole cell takes the touch.
        cap.frame = bounds.insetBy(dx: 3, dy: 1)
        title.frame = bounds
        glyph.frame = bounds
    }

    func restyle() {
        let dark = traitCollection.userInterfaceStyle == .dark
        let capColor: UIColor
        if desc.accent {
            capColor = UIColor(named: "AccentColor") ?? .systemBlue
        } else if dark {
            capColor = special ? UIColor(white: 0.27, alpha: 1) : UIColor(white: 0.42, alpha: 1)
        } else {
            capColor = special ? UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1) : .white
        }
        cap.backgroundColor = capColor
        let fg: UIColor = desc.accent ? .white : .label
        title.textColor = fg
        glyph.tintColor = fg

        let size: CGFloat
        switch desc.kind {
        case .char: size = model.compact ? 19 : 22
        default: size = desc.symbol != nil ? 19 : 16
        }
        title.font = .systemFont(ofSize: size)
    }

    private var model: KeyboardModel { kb.model }

    func applyShift(up: Bool, shift: Shift) {
        switch desc.kind {
        case .char:
            title.text = up ? desc.label.uppercased() : desc.label
        case .shift:
            glyph.image = UIImage(systemName: shift == .locked ? "capslock.fill" : shift == .once ? "shift.fill" : "shift")
            if special != (shift == .off) {
                special = shift == .off
                if held == 0 { restyle() }
            }
        default: break
        }
    }

    // MARK: touches — all commit on DOWN (except space, which may be a cursor slide, and so acts on up).

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let fresh = held == 0
        held += touches.count
        touches.forEach { _ in grid?.beginTouch() }
        if case let .char(c) = desc.kind {
            // Every finger that lands types, even if another is still on this key ("ll" with two thumbs).
            touches.forEach { _ in kb.click(); kb.type(c) }
            showPopup()
            return
        }
        guard fresh else { return }
        setDown(true)
        switch desc.kind {
        case .char:
            break
        case .shift:
            kb.click(); kb.tapShift()
        case let .go(layer):
            kb.click(); kb.setLayer(layer)
        case .emoji:
            kb.click(); kb.setLayer(.emoji)
        case .globe:
            kb.click(); kb.nextKeyboard()
        case .ret:
            kb.click(); kb.newline()
        case .delete:
            kb.click(); kb.delete()
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                    self?.kb.click(); self?.kb.delete()
                }
            }
        case .space:
            spaceAnchor = touches.first?.location(in: self).x ?? 0
            spaceMoved = false
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard case .space = desc.kind, let t = touches.first else { return }
        let dx = t.location(in: self).x - spaceAnchor
        if !spaceMoved, abs(dx) > 14 {
            spaceMoved = true
            spaceAnchor = t.location(in: self).x
        } else if spaceMoved, abs(dx) >= 9 {
            let steps = Int(dx / 9)
            kb.moveCursor(steps)
            spaceAnchor += CGFloat(steps) * 9
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if case .space = desc.kind, !spaceMoved, held - touches.count == 0 { kb.click(); kb.space() }
        finish(touches.count)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches.count)
    }

    private func finish(_ n: Int) {
        guard held > 0 else { return }
        let lifted = min(n, held)
        held -= lifted
        for _ in 0..<lifted { grid?.endTouch() }
        guard held == 0 else { return }
        setDown(false)
        hidePopup()
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    private func setDown(_ down: Bool) {
        // Special keys darken while held, like the stock keyboard; char keys don't (only the popup shows).
        guard special, !desc.accent else { return }
        let dark = traitCollection.userInterfaceStyle == .dark
        if down {
            cap.backgroundColor = dark ? UIColor(white: 0.42, alpha: 1) : .white
        } else {
            restyle()
        }
    }

    // MARK: popup — the letter balloon that pops up out of the key, like iOS.

    private func showPopup() {
        guard desc.popup, let text = title.text else { return }
        hidePopup()
        let w = bounds.width * 1.2, h = bounds.height * 1.35
        // Positioned in the grid's coordinates (the popup is added to the superview so it can sit above the key).
        let cx = frame.minX + cap.frame.midX
        let topY = frame.minY + cap.frame.minY
        let p = UIView(frame: CGRect(x: cx - w / 2, y: topY - h - 4, width: w, height: h))
        p.backgroundColor = cap.backgroundColor
        p.layer.cornerRadius = 7
        p.layer.cornerCurve = .continuous
        p.layer.shadowColor = UIColor.black.cgColor
        p.layer.shadowOpacity = 0.25
        p.layer.shadowRadius = 6
        p.layer.shadowOffset = CGSize(width: 0, height: 2)
        p.isUserInteractionEnabled = false
        let l = UILabel(frame: p.bounds)
        l.text = text
        l.textAlignment = .center
        l.textColor = .label
        l.font = .systemFont(ofSize: 28)
        p.addSubview(l)
        superview?.addSubview(p)   // added to the grid so it can overflow above the key
        popup = p
        // Full size at once, like iOS: a grow-in animation never finished on a quick tap, so nothing showed.
    }

    private func hidePopup() {
        // Hold it a beat after release so a fast tap still flashes the letter.
        let p = popup
        popup = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { p?.removeFromSuperview() }
    }

    // The UI test drives keys through accessibility, not raw touch. Route that to the same actions.
    override func accessibilityActivate() -> Bool {
        switch desc.kind {
        case let .char(c): kb.type(c)
        case .space: kb.space()
        case .delete: kb.delete()
        case .shift: kb.tapShift()
        case let .go(layer): kb.setLayer(layer)
        case .emoji: kb.setLayer(.emoji)
        case .globe: kb.nextKeyboard()
        case .ret: kb.newline()
        }
        return true
    }
}
