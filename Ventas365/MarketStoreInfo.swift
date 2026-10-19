import SwiftUI
import MapKit
import CoreImage.CIFilterBuiltins

private struct StoreInfoText {
    let language: AppLanguage
    private func pick(_ es: String, _ en: String) -> String { language == .es ? es : en }

    var follow: String { pick("Favorita", "Favorite") }
    var following: String { pick("Guardada", "Saved") }
    var rate: String { pick("Calificar", "Rate") }
    var map: String { pick("Ver en el mapa", "View on map") }
    var share: String { pick("Compartir", "Share") }
    var qr: String { pick("QR de la tienda", "Store QR") }
    var hours: String { pick("Horario", "Hours") }
    var today: String { pick("Hoy", "Today") }
    var closed: String { pick("Cerrado", "Closed") }
    var delivery: String { pick("Entrega", "Delivery") }
    var homeDelivery: String { pick("Domicilio", "Home delivery") }
    var pickup: String { pick("Recoger en tienda", "Store pickup") }
    var seeMapHow: String { pick("Ver mapa y cómo llegar", "See map and directions") }
    var social: String { pick("Redes y canales", "Social and channels") }
    var payments: String { pick("Medios de pago", "Payment methods") }
    var sendProof: String { pick("Enviar comprobante de pago", "Send payment proof") }
    var copy: String { pick("Copiar", "Copy") }
    var copied: String { pick("Copiado", "Copied") }
    var directions: String { pick("Cómo llegar", "Directions") }
    var qrHint: String { pick("Escanéalo para abrir esta tienda en Ventas365.", "Scan it to open this store on Ventas365.") }
    var ratings: String { pick("Calificaciones", "Ratings") }
    var yourRating: String { pick("Tu calificación", "Your rating") }
    var comment: String { pick("Comentario (opcional)", "Comment (optional)") }
    var send: String { pick("Enviar calificación", "Send rating") }
    var sending: String { pick("Enviando…", "Sending…") }
    var sent: String { pick("¡Gracias! La tienda revisará tu calificación antes de publicarla.", "Thanks! The store will review your rating before it's published.") }
    var signInToRate: String { pick("Inicia sesión desde la pestaña Cuenta para calificar esta tienda.", "Sign in from the Account tab to rate this store.") }
    var noRatings: String { pick("Esta tienda aún no tiene calificaciones.", "This store has no ratings yet.") }
    var error: String { pick("No se pudo enviar la calificación. Intenta de nuevo.", "The rating couldn't be sent. Try again.") }
    var close: String { pick("Cerrar", "Close") }
    var whatsapp: String { "WhatsApp" }

    func shareMessage(_ name: String) -> String { pick("Mira \(name) en Ventas365", "Check out \(name) on Ventas365") }
    func day(_ index: Int) -> String {
        let es = ["Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado"]
        let en = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return language == .es ? es[index] : en[index]
    }
}

/// Hora "08:00" → "8 a.m.".
private func formatTime(_ value: String?) -> String {
    guard let value else { return "" }
    let parts = value.split(separator: ":")
    guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return value }
    let period = hour < 12 ? "a.m." : "p.m."
    let display = hour % 12 == 0 ? 12 : hour % 12
    return minute == 0 ? "\(display) \(period)" : "\(display):" + String(format: "%02d", minute) + " \(period)"
}

private func hoursLabel(_ day: DayHours?) -> String? {
    guard let day, day.closed != true, let open = day.open, let close = day.close, !open.isEmpty, !close.isEmpty else { return nil }
    return "\(formatTime(open)) – \(formatTime(close))"
}

@MainActor
final class StoreInfoModel: ObservableObject {
    @Published var apps: [MarketAPI.StoreDeliveryApp] = []
    @Published var payments: [MarketAPI.StorePaymentInfo] = []
    @Published var ratings: [MarketAPI.PublicRating] = []

    func load(storeId: String) async {
        async let loadedApps = try? MarketAPI.deliveryApps(storeId: storeId)
        async let loadedPayments = try? MarketAPI.paymentInfo(storeId: storeId)
        apps = (await loadedApps) ?? []
        payments = (await loadedPayments) ?? []
    }

    func loadRatings(storeId: String) async {
        ratings = (try? await MarketAPI.publicRatings(storeId: storeId)) ?? []
    }
}

/// Acciones, horario, entrega, redes y medios de pago de una tienda.
struct StoreInfoPanel: View {
    let store: MarketStore
    let language: AppLanguage
    let isOpen: Bool?
    let rating: MarketRating?

    @StateObject private var model = StoreInfoModel()
    @EnvironmentObject private var favorites: MarketFavorites
    @State private var showMap = false
    @State private var showRatings = false
    @State private var showQr = false
    @State private var showHours = false
    @State private var copiedMethod: String?
    @State private var proofMethod: String?
    @State private var showLogin = false
    @EnvironmentObject private var session: MarketSession

    var body: some View {
        let text = StoreInfoText(language: language)
        VStack(alignment: .leading, spacing: 18) {
            actions(text)
            if store.businessHours != nil { hours(text) }
            deliverySection(text)
            channels(text)
            paymentSection(text)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .task { await model.load(storeId: store.storeId) }
        .sheet(isPresented: $showMap) { StoreMapSheet(store: store, language: language) }
        .sheet(isPresented: $showQr) { StoreQrSheet(store: store, language: language) }
        .sheet(isPresented: $showRatings) { StoreRatingsSheet(store: store, language: language, model: model) }
        .sheet(isPresented: Binding(get: { proofMethod != nil }, set: { if !$0 { proofMethod = nil } })) {
            PaymentProofSheet(storeId: store.storeId, initialMethod: proofMethod, language: language)
        }
        .sheet(isPresented: $showLogin) {
            NavigationStack { LoginScreen(language: language, presentedAsSheet: true) }
        }
    }

    // MARK: Acciones

    private func actions(_ text: StoreInfoText) -> some View {
        let liked = favorites.isFavorite(store: store.storeId)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(liked ? text.following : text.follow, liked ? "heart.fill" : "heart", tint: liked ? .red : nil) {
                    favorites.toggle(store: store.storeId)
                }
                chip(text.rate, "star") { showRatings = true }
                chip(text.map, "map") { openMap() }
                ShareLink(item: store.shareUrl, message: Text(text.shareMessage(store.displayName))) {
                    chipLabel(text.share, "square.and.arrow.up", tint: nil)
                }
                chip(text.qr, "qrcode") { showQr = true }
            }
        }
    }

    private func chipLabel(_ title: String, _ symbol: String, tint: Color?) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(tint ?? .ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.white))
            .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
    }

    private func chip(_ title: String, _ symbol: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(title, symbol, tint: tint) }.buttonStyle(.plain)
    }

    private func openMap() {
        if store.hasGps {
            showMap = true
        } else if !store.fullAddress.isEmpty,
                  let query = (store.addressForMap ?? store.fullAddress).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "http://maps.apple.com/?q=\(query)") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: Horario

    private func hours(_ text: StoreInfoText) -> some View {
        let week = store.businessHours ?? []
        let todayIndex = Calendar.current.component(.weekday, from: Date()) - 1
        let todayLabel = week.indices.contains(todayIndex) ? (hoursLabel(week[todayIndex]) ?? text.closed) : text.closed
        return VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { showHours.toggle() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock").foregroundColor(.brandGreen)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(text.hours).font(.system(size: 12)).foregroundColor(.inkMuted)
                        Text("\(text.today): \(todayLabel)").font(.system(size: 15, weight: .semibold)).foregroundColor(.ink)
                    }
                    Spacer()
                    if let isOpen { OpenBadge(isOpen: isOpen, language: language) }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.inkMuted)
                        .rotationEffect(.degrees(showHours ? 180 : 0))
                }
                .padding(14)
            }
            .buttonStyle(.plain)
            if showHours && week.count == 7 {
                VStack(spacing: 0) {
                    ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { index in
                        let label = hoursLabel(week[index])
                        HStack {
                            Text(text.day(index))
                                .fontWeight(index == todayIndex ? .bold : .regular)
                            Spacer()
                            Text(label ?? text.closed)
                                .foregroundColor(label == nil ? .inkMuted : .ink)
                                .fontWeight(index == todayIndex ? .bold : .regular)
                        }
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(index == todayIndex ? Color.brandGreenTint : Color.clear)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
    }

    // MARK: Entrega

    private func deliverySection(_ text: StoreInfoText) -> some View {
        var facts: [String] = []
        if let low = store.deliveryTimeMin, let high = store.deliveryTimeMax {
            facts.append("\(low)–\(high) min")
        }
        if let cost = store.deliveryCost {
            facts.append(cost == 0 ? (language == .es ? "Domicilio gratis" : "Free delivery") : Money.format(cost, currency: store.currencyCode))
        }
        if let minimum = store.minimumOrder, minimum > 0 {
            facts.append((language == .es ? "Pedido mínimo " : "Minimum order ") + Money.format(minimum, currency: store.currencyCode))
        }
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle(text.delivery)
            VStack(spacing: 0) {
                infoRow("truck.box", text.homeDelivery, facts.isEmpty ? nil : facts.joined(separator: " · "))
                Divider().padding(.leading, 52)
                Button { openMap() } label: {
                    infoRow(
                        "bag",
                        text.pickup,
                        store.hasGps ? text.seeMapHow : (store.fullAddress.isEmpty ? nil : store.fullAddress),
                        chevron: store.hasGps || !store.fullAddress.isEmpty
                    )
                }
                .buttonStyle(.plain)
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
        }
    }

    private func infoRow(_ symbol: String, _ title: String, _ detail: String?, chevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundColor(.brandGreen)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(.ink)
                if let detail { Text(detail).font(.system(size: 13)).foregroundColor(.inkMuted).multilineTextAlignment(.leading) }
            }
            Spacer()
            if chevron { Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(.inkMuted) }
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(.inkMuted).textCase(.uppercase)
    }

    // MARK: Redes y canales

    private var whatsappUrl: URL? {
        guard let phone = store.phoneNumber, !phone.isEmpty else { return nil }
        let dial = DialCountry.common.first { $0.iso2 == (store.phoneCountryIso ?? store.countryIso) }?.dialCode ?? "+57"
        let digits = (dial + phone).filter(\.isNumber)
        return URL(string: "https://wa.me/\(digits)")
    }

    private var instagram: (handle: String, url: URL)? {
        if let raw = store.instagramUrl, let url = URL(string: raw), !raw.isEmpty {
            return (store.instagramHandle.map { "@\($0)" } ?? "Instagram", url)
        }
        if let handle = store.instagramHandle, !handle.isEmpty, let url = URL(string: "https://www.instagram.com/\(handle)") {
            return ("@\(handle)", url)
        }
        return nil
    }

    @ViewBuilder
    private func channels(_ text: StoreInfoText) -> some View {
        let hasAny = whatsappUrl != nil || instagram != nil || !model.apps.isEmpty
        if hasAny {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(text.social)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let url = whatsappUrl {
                            Link(destination: url) { chipLabel(text.whatsapp, "message.fill", tint: .brandGreen) }
                        }
                        if let instagram {
                            Link(destination: instagram.url) { chipLabel(instagram.handle, "camera", tint: nil) }
                        }
                        ForEach(model.apps) { app in
                            if let url = URL(string: app.url) {
                                Link(destination: url) { chipLabel(app.name, "bicycle", tint: nil) }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Medios de pago

    private func paymentSection(_ text: StoreInfoText) -> some View {
        let enabled = Set(model.payments.map(\.method))
        let kinds = PaymentMethodKind.available(countryIso: store.countryIso, enabledQr: enabled)
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle(text.payments)
            VStack(spacing: 0) {
                ForEach(Array(kinds.enumerated()), id: \.element.id) { offset, kind in
                    if offset > 0 { Divider().padding(.leading, 52) }
                    paymentRow(kind, info: model.payments.first { $0.method == kind.rawValue }, text)
                }
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
        }
    }

    private func paymentRow(_ kind: PaymentMethodKind, info: MarketAPI.StorePaymentInfo?, _ text: StoreInfoText) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: symbol(kind)).foregroundColor(.brandGreen).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.label(language)).font(.system(size: 15, weight: .semibold))
                    if let label = info?.accountLabel, !label.isEmpty {
                        Text(label).font(.system(size: 13)).foregroundColor(.inkMuted)
                    }
                }
                Spacer()
                if let label = info?.accountLabel, !label.isEmpty {
                    Button {
                        UIPasteboard.general.string = label
                        copiedMethod = kind.rawValue
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copiedMethod == kind.rawValue { copiedMethod = nil } }
                    } label: {
                        Label(copiedMethod == kind.rawValue ? text.copied : text.copy, systemImage: copiedMethod == kind.rawValue ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            if kind.isQr && info != nil {
                Button {
                    if session.isSignedIn { proofMethod = kind.rawValue } else { showLogin = true }
                } label: {
                    Label(text.sendProof, systemImage: "paperplane")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .tint(.brandGreen)
                .controlSize(.small)
                .padding(.leading, 40)
            }
            if let qr = info?.qrImageUrl, !qr.isEmpty {
                RemoteImage(url: qr)
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.leading, 40)
            }
        }
        .padding(14)
    }

    private func symbol(_ kind: PaymentMethodKind) -> String {
        switch kind {
        case .cash: return "banknote"
        case .creditCard, .debitCard: return "creditcard"
        case .nequi, .daviplata, .llave: return "qrcode"
        }
    }
}

// MARK: - Mapa

struct StoreMapSheet: View {
    let store: MarketStore
    let language: AppLanguage

    @Environment(\.dismiss) private var dismiss
    @State private var region: MKCoordinateRegion

    init(store: MarketStore, language: AppLanguage) {
        self.store = store
        self.language = language
        _region = State(initialValue: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: store.latitude ?? 0, longitude: store.longitude ?? 0),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }

    private var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: store.latitude ?? 0, longitude: store.longitude ?? 0) }

    var body: some View {
        let text = StoreInfoText(language: language)
        NavigationStack {
            VStack(spacing: 0) {
                Map(coordinateRegion: $region, annotationItems: [store]) { item in
                    MapMarker(coordinate: coordinate, tint: .red)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.displayName).font(.system(size: 18, weight: .bold))
                    if !store.fullAddress.isEmpty { Text(store.fullAddress).font(.system(size: 14)).foregroundColor(.inkMuted) }
                    Button {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
                        item.name = store.displayName
                        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                    } label: {
                        Label(text.directions, systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .modifier(PrimaryActionStyle())
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.paper)
            }
            .navigationTitle(text.map)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(text.close) { dismiss() } } }
        }
    }
}

// MARK: - QR

struct StoreQrSheet: View {
    let store: MarketStore
    let language: AppLanguage

    @Environment(\.dismiss) private var dismiss

    private func qrImage() -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(store.shareUrl.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    var body: some View {
        let text = StoreInfoText(language: language)
        NavigationStack {
            VStack(spacing: 18) {
                Text(store.displayName).font(.system(size: 22, weight: .bold))
                if let image = qrImage() {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white))
                }
                Text(text.qrHint).font(.system(size: 14)).foregroundColor(.inkMuted).multilineTextAlignment(.center)
                Text(store.shareUrl.absoluteString).font(.system(size: 13)).foregroundColor(.inkMuted)
                ShareLink(item: store.shareUrl, message: Text(text.shareMessage(store.displayName))) {
                    Label(text.share, systemImage: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .modifier(PrimaryActionStyle())
                Spacer()
            }
            .padding(24)
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle(text.qr)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(text.close) { dismiss() } } }
        }
    }
}

// MARK: - Calificaciones

struct StoreRatingsSheet: View {
    let store: MarketStore
    let language: AppLanguage
    @ObservedObject var model: StoreInfoModel

    @EnvironmentObject private var session: MarketSession
    @Environment(\.dismiss) private var dismiss
    @State private var stars = 0
    @State private var comment = ""
    @State private var sending = false
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        let text = StoreInfoText(language: language)
        NavigationStack {
            List {
                Section(text.yourRating) {
                    if session.isSignedIn {
                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { value in
                                Button { stars = value } label: {
                                    Image(systemName: value <= stars ? "star.fill" : "star")
                                        .font(.system(size: 30))
                                        .foregroundColor(.orange)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        TextField(text.comment, text: $comment, axis: .vertical)
                            .lineLimit(2...5)
                            .onChange(of: comment) { value in if value.count > 500 { comment = String(value.prefix(500)) } }
                        if let message {
                            Text(message).font(.system(size: 14)).foregroundColor(failed ? .red : .brandGreen)
                        }
                        Button { Task { await send(text) } } label: {
                            HStack {
                                Spacer()
                                Text(sending ? text.sending : text.send).font(.system(size: 16, weight: .semibold))
                                Spacer()
                            }
                        }
                        .disabled(stars == 0 || sending)
                    } else {
                        Text(text.signInToRate).foregroundColor(.inkMuted)
                    }
                }
                Section(text.ratings) {
                    if model.ratings.isEmpty {
                        Text(text.noRatings).foregroundColor(.inkMuted)
                    } else {
                        ForEach(model.ratings) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(item.firstName).font(.system(size: 15, weight: .semibold))
                                    Spacer()
                                    Text(String(repeating: "★", count: item.rating) + String(repeating: "☆", count: 5 - item.rating))
                                        .foregroundColor(.orange)
                                }
                                if let note = item.comment, !note.isEmpty {
                                    Text(note).font(.system(size: 14))
                                }
                                Text(OrderDate.short(item.createdAt, language: language)).font(.system(size: 12)).foregroundColor(.inkMuted)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(store.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(text.close) { dismiss() } } }
            .task { await model.loadRatings(storeId: store.storeId) }
        }
    }

    private func send(_ text: StoreInfoText) async {
        guard let token = session.token else { return }
        sending = true
        failed = false
        message = nil
        defer { sending = false }
        do {
            let response = try await MarketAPI.submitRating(token: token, storeId: store.storeId, rating: stars, comment: comment.trimmingCharacters(in: .whitespacesAndNewlines))
            if response.success == true {
                message = text.sent
            } else {
                failed = true
                message = response.error ?? text.error
            }
        } catch {
            failed = true
            message = text.error
        }
    }
}
