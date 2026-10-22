import CoreImage.CIFilterBuiltins
import PhotosUI
import SwiftUI
import JynxKit

struct PayView: View {
    enum Method: String, Identifiable { case bank, usdt, wallet; var id: String { rawValue } }

    let order: PayOrder
    let payment: PaymentSettings?
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var method: Method = .bank
    @State private var done: Done?

    enum Done: Equatable { case active(Date?), deposited, sent }

    private var auto: AutoQR? { payment?.autoQr.flatMap { $0 == .other ? nil : $0 } }
    private var methods: [Method] {
        var m: [Method] = []
        if auto != nil || payment?.abaQrPath != nil { m.append(.bank) }
        if !(payment?.usdtTrc20 ?? "").isEmpty { m.append(.usdt) }
        if case .plan = order { m.append(.wallet) }
        return m
    }
    private func label(_ m: Method) -> String {
        switch m {
        case .bank: auto == .khqr ? "Pay by KHQR (any bank)" : "Pay by ABA"
        case .usdt: "Pay by USDT (TRC20)"
        case .wallet: "Pay from wallet"
        }
    }

    var body: some View {
        Group {
            if let done { DoneView(done: done, order: order) { dismiss() } }
            else {
                ScrollView {
                    VStack(spacing: 0) {
                        dark.padding(.bottom, 28).frame(maxWidth: .infinity).background(Color(hex: 0x0d0f12))
                        if method != .bank || auto == nil { ManualSheet(order: order, method: method, finished: finish) }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .background {
                    VStack(spacing: 0) {
                        Color(hex: 0x0d0f12)
                        lowerBackdrop
                    }.ignoresSafeArea()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .onAppear { if !methods.contains(method), let first = methods.first { method = first } }
        .sensoryFeedback(trigger: done, feedback)
    }

    private static let panel = Color(hex: 0x0d0f12)
    private var lowerBackdrop: Color { method == .bank && auto != nil ? Self.panel : Theme.bg }

    private func feedback(_ old: Done?, _ new: Done?) -> SensoryFeedback? {
        guard let new else { return nil }
        return new == .sent ? .impact(weight: .medium) : .success
    }

    private var title: String {
        switch method {
        case .usdt: "Send \((Double(order.cents) / 100).formatted(.number.precision(.fractionLength(2)).grouping(.never))) USDT"
        case .wallet: "Pay \(Money.dollars(order.cents)) from your wallet"
        case .bank: auto == .khqr ? "Pay \(Money.dollars(order.cents)) with any bank app" : "Pay \(Money.dollars(order.cents)) by ABA"
        }
    }

    @ViewBuilder private var dark: some View {
        VStack(spacing: 18) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(Color.white.opacity(0.1), in: Circle())
                }
                .accessibilityLabel("Back")
                Spacer()
            }
            .padding(.horizontal, 16)
            Text(title).font(.open(24, .heavy)).foregroundStyle(.white).multilineTextAlignment(.center).padding(.horizontal, 20)
            if methods.count > 1 {
                Menu {
                    ForEach(methods) { m in Button(label(m)) { withAnimation(.snappy) { method = m } } }
                } label: {
                    HStack(spacing: 8) { Text(label(method)); Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)) }
                        .font(.open(15, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(height: 44)
                        .background(Color.white.opacity(0.1), in: Capsule()).overlay(Capsule().stroke(Color.white.opacity(0.15)))
                }
            }
            switch method {
            case .bank:
                if let auto { AutoQRPanel(order: order, kind: auto, finished: finish).id(order.id) }
                else {
                    Viewfinder { AsyncImage(url: session.api.base.appending(path: "api/plans/aba-qr")) { $0.resizable().scaledToFit() } placeholder: { ProgressView() } }
                    if let name = payment?.abaName, !name.isEmpty { Text("Pay to \(name)").font(.open(14, .semibold)).foregroundStyle(.white.opacity(0.8)) }
                }
            case .usdt:
                let address = payment?.usdtTrc20 ?? ""
                Viewfinder { QRImage(text: address) }
                Label("TRON network (TRC20) only", systemImage: "exclamationmark.triangle")
                    .font(.open(14, .bold)).foregroundStyle(Color(hex: 0xf7b928))
                    .padding(.horizontal, 14).padding(.vertical, 8).background(Color(hex: 0xf7b928).opacity(0.14), in: Capsule())
                Text(address).font(.system(size: 14, design: .monospaced)).foregroundStyle(.white).textSelection(.enabled)
                    .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 20)
                CopyButton(text: address, label: "Copy address")
            case .wallet:
                WalletPayPanel(order: order, finished: finish)
            }
        }
        .padding(.top, 12)
    }

    private func finish(_ d: Done) { Task { await session.refreshMe() }; withAnimation(.snappy) { done = d } }
}

struct Viewfinder<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22).fill(.white).frame(width: 220, height: 220)
            content.frame(width: 190, height: 190)
            if !reduceMotion {
                LinearGradient(colors: [.clear, Theme.primary.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: 210, height: 14).offset(y: sweep ? 95 : -95)
                    .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: sweep)
                    .onAppear { sweep = true }.allowsHitTesting(false)
            }
            Brackets().stroke(Theme.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)).frame(width: 252, height: 252)
        }
        .frame(width: 256, height: 256)
    }
}

private struct Brackets: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); let l: CGFloat = 36, c: CGFloat = 14
        for (x, y, dx, dy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX, r.minY, -1.0, 1.0), (r.minX, r.maxY, 1.0, -1.0), (r.maxX, r.maxY, -1.0, -1.0)] {
            p.move(to: CGPoint(x: x, y: y + dy * l)); p.addLine(to: CGPoint(x: x, y: y + dy * c))
            p.addQuadCurve(to: CGPoint(x: x + dx * c, y: y), control: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + dx * l, y: y))
        }
        return p
    }
}

struct QRImage: View {
    let text: String
    var body: some View {
        if let image = Self.make(text) { Image(uiImage: image).interpolation(.none).resizable().scaledToFit() }
        else { Color.clear }
    }
    static func make(_ text: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator(); f.message = Data(text.utf8); f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct CopyButton: View {
    let text: String
    let label: String
    @State private var copied = false
    var body: some View {
        Button {
            UIPasteboard.general.string = text; copied = true
            Task { try? await Task.sleep(for: .seconds(1.8)); copied = false }
        } label: {
            Label(copied ? "Copied" : label, systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.open(15, .bold)).foregroundStyle(.white).padding(.horizontal, 20).frame(height: 44)
                .background(Color.white.opacity(0.1), in: Capsule())
        }
    }
}

private struct AutoQRPanel: View {
    let order: PayOrder
    let kind: AutoQR
    let finished: (PayView.Done) -> Void
    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var qr: QRPayment?
    @State private var phase: PayPhase = .waiting
    @State private var error: String?
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 18) {
            Viewfinder {
                if let data = qr?.pngData, let image = UIImage(data: data) {
                    Image(uiImage: image).interpolation(.none).resizable().scaledToFit().opacity(phase == .expired ? 0.15 : 1)
                } else if error == nil { ProgressView().tint(.black) }
            }
            if let error {
                Text(error).font(.open(14)).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center).padding(.horizontal, 24)
                again("Try again")
            } else if let qr {
                switch phase {
                case .waiting:
                    if let link = qr.deeplink.flatMap(URL.init(string:)) {
                        Button { openURL(link) } label: {
                            Text(link.scheme == "abamobilebank" ? "Pay in ABA" : kind == .khqr ? "Open my bank app" : "Open ABA Mobile").font(.open(17, .heavy)).foregroundStyle(.black)
                                .frame(width: 220, height: 50).background(.white, in: Capsule())
                        }
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in   // 0:00 hands over to "checking" at the next poll
                        HStack(spacing: 8) {
                            Circle().fill(Theme.up).frame(width: 8, height: 8)
                            Text("Waiting for your payment · \(QRCountdown(expiresAt: qr.expiresAt).remaining(at: ctx.date))").monospacedDigit()
                        }.font(.open(15)).foregroundStyle(.white.opacity(0.8))
                    }
                case .checking:
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Checking for your payment…").font(.open(15)).foregroundStyle(.white.opacity(0.85))
                    }
                    Text("If you paid, it will show here in a moment.").font(.open(13.5)).foregroundStyle(.white.opacity(0.6))
                case .expired:
                    Text("This QR expired. Get a new one to pay.").font(.open(15)).foregroundStyle(.white.opacity(0.85))
                    again("New QR")
                case .rejected(let reason):
                    Text(reason.isEmpty ? "The payment did not go through." : reason).font(.open(15)).foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                    again("Try again")
                case .paid: EmptyView()
                }
            }
        }
        .task(id: attempt) { await run() }
    }

    private func again(_ title: String) -> some View {
        Button(title) { qr = nil; error = nil; phase = .waiting; attempt += 1 }
            .font(.open(16, .heavy)).foregroundStyle(.black).frame(width: 200, height: 48).background(.white, in: Capsule())
    }

    private func run() async {
        let api = session.api
        do {
            let q: QRPayment
            switch order {
            case let .plan(p, m): q = try await api.startQR(productId: p.id, months: m)
            case let .deposit(c): q = try await api.startQR(depositCents: c)
            }
            qr = q
            while !Task.isCancelled {
                var state: PaymentState?
                do { state = try await api.paymentState(q.id) }
                catch APIError.signedOut { session.handle(APIError.signedOut); return }
                catch is CancellationError { return }
                catch {}
                phase = PayPhase.of(state, expiresAt: q.expiresAt, now: .now)
                if case let .paid(endsAt) = phase {
                    if case .deposit = order { finished(.deposited) } else { finished(.active(endsAt)) }
                    return
                }
                guard phase.keepsPolling else { return }
                try await Task.sleep(for: .seconds(3))
            }
        } catch is CancellationError {
        } catch { session.handle(error); self.error = Copy.error(error) }
    }
}

private struct WalletPayPanel: View {
    let order: PayOrder
    let finished: (PayView.Done) -> Void
    @Environment(Session.self) private var session
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        VStack(spacing: 14) {
            let balance = session.me?.wallet.balance ?? 0
            Text("Balance \(Money.dollars(balance))").font(.open(16, .semibold)).foregroundStyle(.white.opacity(0.8))
            if let error { Text(error).font(.open(14)).foregroundStyle(Color(hex: 0xff6b81)).multilineTextAlignment(.center).padding(.horizontal, 24) }
            Button {
                Task {
                    guard case let .plan(p, m) = order else { return }
                    busy = true; error = nil
                    do { finished(.active(try await session.api.buyWithWallet(productId: p.id, months: m))) }
                    catch { session.handle(error); self.error = Copy.error(error) }
                    busy = false
                }
            } label: {
                ZStack { if busy { ProgressView().tint(.black) } else { Text("Pay \(Money.dollars(order.cents))") } }
                    .font(.open(17, .heavy)).foregroundStyle(.black).frame(width: 240, height: 52).background(.white, in: Capsule())
            }.disabled(busy)
        }
    }
}

private struct ManualSheet: View {
    let order: PayOrder
    let method: PayView.Method
    let finished: (PayView.Done) -> Void
    @Environment(Session.self) private var session
    @State private var item: PhotosPickerItem?
    @State private var receipt: Data?
    @State private var preview: UIImage?
    @State private var typing = false
    @State private var reference = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        if method == .wallet { EmptyView() } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 14).fill(Theme.bg).frame(width: 48, height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.borderSoft))
                        .overlay(Image(systemName: summary.symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.primary))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.title).font(.open(17, .bold)).foregroundStyle(Theme.fg).lineLimit(1)
                        Text(summary.subtitle).font(.open(14)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text(Money.dollars(order.cents)).font(.open(19, .heavy)).foregroundStyle(Theme.fg).monospacedDigit()
                }
                Divider()
                PhotosPicker(selection: $item, matching: .images) {
                    HStack(spacing: 14) {
                        Group {
                            if let preview { Image(uiImage: preview).resizable().scaledToFill() }
                            else { Image(systemName: "photo").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.primary) }
                        }
                        .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 14))
                        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.borderSoft))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(receipt == nil ? "Upload receipt" : "Receipt added").font(.open(16, .bold)).foregroundStyle(Theme.fg)
                            Text(receipt == nil ? "Screenshot from your \(method == .usdt ? "wallet or exchange" : "bank app")" : "Tap to change it")
                                .font(.open(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.leading)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                }
                if typing {
                    TextField(method == .usdt ? "Transaction ID (hash)" : "Transaction reference", text: $reference)
                        .font(.open(16)).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(.horizontal, 14).frame(minHeight: 48)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
                } else {
                    Button("No screenshot? Enter the transaction ID") { typing = true }
                        .font(.open(15, .semibold)).foregroundStyle(Theme.primary).frame(maxWidth: .infinity)
                }
                if let error { Text(error).font(.open(14)).foregroundStyle(Theme.down) }
                PrimaryButton(title: "Confirm Payment", busy: busy) { Task { await submit() } }
                    .disabled(receipt == nil && reference.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
            .background(Theme.bg, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
            .offset(y: -20).padding(.bottom, -20)
            .onChange(of: item) { Task { await load(item) } }
        }
    }

    private var summary: (title: String, subtitle: String, symbol: String) {
        switch order {
        case let .plan(p, m): (p.name, "\(m) \(m == 1 ? "month" : "months")", "chart.line.uptrend.xyaxis")
        case .deposit: ("Deposit", "Added to your wallet once checked", "arrow.down.to.line")
        }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        let scale = min(1, 2000 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { return }
        if let problem = Receipt.problem(jpeg) { error = problem; return }
        receipt = jpeg; preview = resized; error = nil
    }

    private func submit() async {
        busy = true; error = nil
        var fields: [(String, String)] = [("method", method == .usdt ? "usdt" : "aba"), ("reference", reference.trimmingCharacters(in: .whitespaces))]
        switch order {
        case let .plan(p, m): fields += [("productId", p.id), ("months", String(m))]
        case let .deposit(c): fields += [("kind", "deposit"), ("amountCents", String(c))]
        }
        do { _ = try await session.api.payManually(fields: fields, receipt: receipt); finished(.sent) }
        catch { session.handle(error); self.error = Copy.error(error) }
        busy = false
    }
}

private struct DoneView: View {
    let done: PayView.Done
    let order: PayOrder
    let close: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Circle().fill(done == .sent ? Theme.primary : Theme.up).frame(width: 84, height: 84)
                .overlay(Image(systemName: done == .sent ? "clock" : "checkmark").font(.system(size: 34, weight: .bold)).foregroundStyle(.white))
                .transition(.scale.combined(with: .opacity))
            Text(headline).font(.open(24, .heavy)).foregroundStyle(Theme.fg).multilineTextAlignment(.center)
            Text(detail).font(.open(15)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
            PrimaryButton(title: "Done", action: close).padding(.horizontal, 20).padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg)
        .navigationBarBackButtonHidden()
    }
    private var headline: String {
        switch done {
        case .active: "You're in"
        case .deposited: "Deposit added."
        case .sent: "Payment sent"
        }
    }
    private var detail: String {
        switch done {
        case .active(let end?): "Active until \(end.formatted(.dateTime.day().month(.abbreviated).year()))."
        case .active(nil): "Your plan is active."
        case .deposited: "\(Money.dollars(order.cents)) is in your wallet."
        case .sent: "We'll check it and approve it soon. You can follow it under Profile, Payments."
        }
    }
}
