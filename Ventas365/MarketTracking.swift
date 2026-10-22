import SwiftUI
import MapKit
import PhotosUI

private struct TrackText {
    let language: AppLanguage
    private func pick(_ es: String, _ en: String) -> String { language == .es ? es : en }

    var status: String { pick("Estado del pedido", "Order status") }
    var delivery: String { pick("Entrega", "Delivery") }
    var map: String { pick("Seguimiento en el mapa", "Live map") }
    var store: String { pick("Tienda", "Store") }
    var courier: String { pick("Domiciliario", "Courier") }
    var call: String { pick("Llamar al domiciliario", "Call the courier") }
    var chat: String { pick("Chat con el domiciliario", "Chat with the courier") }
    var sendProof: String { pick("Enviar comprobante de pago", "Send payment proof") }
    var proofHint: String { pick("Pagaste por Nequi, Daviplata o Llave Bre-B: envía la captura o foto del pago a la tienda.", "Paid with Nequi, Daviplata or Bre-B Key: send the payment screenshot or photo to the store.") }
    var rateTitle: String { pick("Califica la entrega", "Rate the delivery") }
    var rated: String { pick("Gracias por calificar.", "Thanks for rating.") }
    var comment: String { pick("Comentario (opcional)", "Comment (optional)") }
    var sendRating: String { pick("Enviar calificación", "Send rating") }
    var updated: String { pick("Se actualiza solo", "Updates automatically") }
    var message: String { pick("Escribe un mensaje", "Write a message") }
    var send: String { pick("Enviar", "Send") }
    var noMessages: String { pick("Aún no hay mensajes. Escríbele al domiciliario si necesitas algo.", "No messages yet. Write to the courier if you need anything.") }
    var close: String { pick("Cerrar", "Close") }
    var you: String { pick("Tú", "You") }
    var method: String { pick("Medio de pago", "Payment method") }
    var amount: String { pick("Valor pagado", "Amount paid") }
    var note: String { pick("Nota (opcional)", "Note (optional)") }
    var choosePhoto: String { pick("Elegir foto del comprobante", "Choose proof photo") }
    var changePhoto: String { pick("Cambiar foto", "Change photo") }
    var submit: String { pick("Enviar comprobante", "Send proof") }
    var submitting: String { pick("Enviando…", "Sending…") }
    var proofSent: String { pick("¡Comprobante enviado! La tienda lo revisará.", "Proof sent! The store will review it.") }
    var needPhoto: String { pick("Adjunta la foto del comprobante.", "Attach the proof photo.") }
    var error: String { pick("No se pudo completar. Intenta de nuevo.", "Couldn't complete. Try again.") }
    var yourLocation: String { pick("Domiciliario", "Courier") }
    var destination: String { pick("Tu dirección", "Your address") }
}

// MARK: - Línea de estados

private struct StepState: Identifiable {
    let stage: CustomerPurchase.Stage
    let reached: Bool
    var id: Int { stage.hashValue }
}

extension CustomerPurchase {
    /// Pedido de domicilio (lo sabe el pedido, o ya tiene entrega).
    var isDelivery: Bool { orderType == "domicilio" || delivery != nil || courier != nil }

    /// Etapa real, usando el estado de la entrega cuando la compra ya se facturó.
    var trackingStage: Stage {
        if kind == "venta" {
            switch delivery?.status {
            case "entregado": return .delivered
            case "en_camino": return .onTheWay
            case .some(let status) where status != "cancelado" && delivery?.pickedUpAt != nil && status != "entregado": return .onTheWay
            default: return delivery == nil ? .completed : .ready
            }
        }
        return stage
    }

    var steps: [Stage] {
        isDelivery ? [.sent, .accepted, .preparing, .ready, .onTheWay, .delivered] : [.sent, .accepted, .preparing, .ready, .completed]
    }
}

// MARK: - Detalle con seguimiento

struct PurchaseDetail: View {
    let language: AppLanguage

    @EnvironmentObject private var session: MarketSession
    @State private var purchase: CustomerPurchase
    @State private var showChat = false
    @ObservedObject private var chatSeen = ChatSeen.shared
    @State private var showProof = false
    @State private var stars = 0
    @State private var ratingComment = ""
    @State private var ratingBusy = false
    @State private var ratingDone = false
    @State private var showCancel = false
    @State private var cancelNotice: String?

    init(purchase: CustomerPurchase, language: AppLanguage) {
        self.language = language
        _purchase = State(initialValue: purchase)
    }

    var body: some View {
        let text = OrderText(language: language)
        let track = TrackText(language: language)
        List {
            if purchase.stage == .cancelled {
                Section(track.status) {
                    if let cancellation = purchase.cancellation {
                        CancellationStatusView(cancellation: cancellation, language: language)
                    } else {
                        Label(text.stage(.cancelled), systemImage: "xmark.circle.fill").foregroundColor(.red)
                    }
                }
            } else {
                if let code = purchase.delivery?.deliveryCode, !code.isEmpty, purchase.isActive {
                    Section {
                        DeliveryCodeCard(code: code, language: language)
                    }
                }
                Section(track.status) { timeline(text) }
                if let cancellation = purchase.cancellation {
                    Section { CancellationStatusView(cancellation: cancellation, language: language) }
                }
            }
            if let location = mapCenter {
                Section(track.map) {
                    TrackingMap(purchase: purchase, center: location, storeName: purchase.storeName.capitalized, courierLabel: track.yourLocation, destinationLabel: track.destination)
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                }
            }
            Section {
                LabeledContent(text.stage(purchase.trackingStage), value: OrderDate.short(purchase.date, language: language))
                if !text.type(purchase.orderType).isEmpty {
                    LabeledContent(language == .es ? "Entrega" : "Delivery type", value: text.type(purchase.orderType))
                }
                if let raw = purchase.paymentMethod, let kind = PaymentMethodKind(rawValue: raw) {
                    LabeledContent(text.payWith, value: kind.label(language))
                }
                if let name = purchase.delivery?.courierName ?? purchase.courier?.name {
                    LabeledContent(text.courier, value: name)
                }
                if let vehicle = purchase.delivery?.vehicle ?? purchase.courier?.vehicle, !vehicle.isEmpty {
                    LabeledContent(language == .es ? "Vehículo" : "Vehicle", value: vehicle)
                }
            }
            actions(track)
            rating(track)
            cancelSection()
            // Reclamo de un pedido ya recibido (con evidencias).
            ClaimSection(purchase: purchase, language: language)
            Section(text.products) {
                ForEach(purchase.items, id: \.self) { item in
                    HStack {
                        Text("\(item.quantity) × \(item.description)").font(.system(size: 15))
                        Spacer()
                        Text(Money.format(item.unitPrice * Double(item.quantity), currency: nil)).font(.system(size: 15))
                    }
                }
                HStack {
                    Text(text.total).font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text(Money.format(purchase.total, currency: nil)).font(.system(size: 16, weight: .bold))
                }
            }
            if purchase.isActive {
                Section { Label(track.updated, systemImage: "arrow.triangle.2.circlepath").font(.system(size: 13)).foregroundColor(.inkMuted) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("\(purchase.storeName.capitalized) \(purchase.numberLabel)")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task { await autoRefresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await refresh() }
        }
        .sheet(isPresented: $showChat) {
            if let id = purchase.delivery?.id { DeliveryChatSheet(deliveryId: id, language: language) }
        }
        .sheet(isPresented: $showProof) { PaymentProofSheet(storeId: purchase.storeId, purchase: purchase, language: language) }
        .sheet(isPresented: $showCancel) {
            CancelOrderSheet(purchase: purchase, language: language) { immediate in
                let cancelText = CancelText(language: language)
                cancelNotice = immediate ? cancelText.cancelledDone : cancelText.requestSent
                Task { await refresh() }
            }
        }
    }

    // MARK: Piezas

    private var mapCenter: CLLocationCoordinate2D? {
        guard purchase.isActive, purchase.isDelivery || purchase.orderType == "llevar" else { return nil }
        if let courier = purchase.liveCourier { return CLLocationCoordinate2D(latitude: courier.lat, longitude: courier.lng) }
        if let store = purchase.storeLocation { return CLLocationCoordinate2D(latitude: store.lat, longitude: store.lng) }
        return nil
    }

    private func timeline(_ text: OrderText) -> some View {
        let steps = purchase.steps
        let current = steps.firstIndex(of: purchase.trackingStage) ?? (steps.count - 1)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Image(systemName: index <= current ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundColor(index <= current ? .brandGreen : Color.gray.opacity(0.4))
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(index < current ? Color.brandGreen : Color.gray.opacity(0.25))
                                .frame(width: 2, height: 22)
                        }
                    }
                    Text(text.stage(step))
                        .font(.system(size: 15, weight: index == current ? .bold : .regular))
                        .foregroundColor(index <= current ? .ink : .inkMuted)
                        .padding(.top, 1)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func actions(_ track: TrackText) -> some View {
        let phone = purchase.delivery?.courierPhone ?? purchase.courier?.phone
        let hasChat = purchase.delivery?.id != nil && purchase.isActive
        let needsProof = purchase.isActive && ["NEQUI", "DAVIPLATA", "LLAVE_BREB"].contains(purchase.paymentMethod ?? "")
        if (phone != nil && purchase.isActive) || hasChat || needsProof {
            Section {
                if let phone, purchase.isActive, let url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) {
                    Link(destination: url) { Label(track.call, systemImage: "phone.fill") }
                }
                if hasChat {
                    Button { showChat = true } label: {
                        HStack {
                            Label(track.chat, systemImage: "bubble.left.and.bubble.right.fill")
                            Spacer()
                            UnreadBadge(count: chatSeen.unread(purchase))
                        }
                    }
                }
                if needsProof {
                    Button { showProof = true } label: { Label(track.sendProof, systemImage: "doc.badge.plus") }
                }
            } footer: {
                if needsProof { Text(track.proofHint) }
            }
        }
    }

    @ViewBuilder
    private func rating(_ track: TrackText) -> some View {
        if purchase.delivery?.status == "entregado", let id = purchase.delivery?.id {
            Section(track.rateTitle) {
                if let given = purchase.delivery?.rating {
                    HStack {
                        Text(String(repeating: "★", count: given.stars) + String(repeating: "☆", count: 5 - given.stars)).foregroundColor(.orange)
                        Spacer()
                        Text(track.rated).font(.system(size: 13)).foregroundColor(.inkMuted)
                    }
                } else if ratingDone {
                    Text(track.rated).foregroundColor(.brandGreen)
                } else {
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { value in
                            Button { stars = value } label: {
                                Image(systemName: value <= stars ? "star.fill" : "star").font(.system(size: 28)).foregroundColor(.orange)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    TextField(track.comment, text: $ratingComment, axis: .vertical).lineLimit(1...4)
                    Button { Task { await sendRating(id) } } label: {
                        HStack { Spacer(); Text(ratingBusy ? "…" : track.sendRating).font(.system(size: 16, weight: .semibold)); Spacer() }
                    }
                    .disabled(stars == 0 || ratingBusy)
                }
            }
        }
    }

    @ViewBuilder
    private func cancelSection() -> some View {
        let text = CancelText(language: language)
        if let cancelNotice {
            Section { Label(cancelNotice, systemImage: "checkmark.circle").foregroundColor(.brandGreen) }
        }
        if purchase.canCancel {
            Section {
                Button(role: .destructive) { showCancel = true } label: {
                    Label(purchase.cancelsImmediately ? text.cancelNow : text.requestCancel, systemImage: "xmark.circle")
                }
            } footer: {
                Text(purchase.cancelsImmediately ? text.cancelNowHint : text.requestHint)
            }
        }
    }

    // MARK: Datos

    private func refresh() async {
        guard let token = session.token, let list = try? await MarketAPI.purchases(token: token),
              let fresh = list.first(where: { $0.id == purchase.id && $0.kind == purchase.kind })
                ?? list.first(where: { $0.id == purchase.id }) else { return }
        purchase = fresh
        if let token = session.token { CancellationNotifier.check(list, token: token, language: language) }
    }

    private func autoRefresh() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if Task.isCancelled { break }
            if purchase.isActive { await refresh() }
        }
    }

    private func sendRating(_ deliveryId: String) async {
        guard let token = session.token else { return }
        ratingBusy = true
        defer { ratingBusy = false }
        let response = try? await MarketAPI.rateDelivery(token: token, deliveryId: deliveryId, stars: stars, comment: ratingComment.trimmingCharacters(in: .whitespacesAndNewlines))
        if response?.success == true {
            ratingDone = true
            await refresh()
        }
    }
}

// MARK: - Mapa

/// Mapa del seguimiento: tienda, domiciliario y destino, con la ruta
/// recomendada (Apple Maps) del domiciliario —o de la tienda, mientras no
/// sale— hasta la dirección de entrega.
///
/// Rendimiento: el domiciliario reporta su posición cada ~20 s y el detalle
/// la consulta cada 10 s. La dirección se ubica una sola vez (queda en
/// caché) y la ruta solo se vuelve a pedir si el domiciliario se movió más de
/// 150 m o pasó un minuto desde la anterior.
private struct TrackingMap: UIViewRepresentable {
    let purchase: CustomerPurchase
    let center: CLLocationCoordinate2D
    let storeName: String
    let courierLabel: String
    let destinationLabel: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsCompass = false
        map.pointOfInterestFilter = .excludingAll
        map.setRegion(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)), animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.map = map
        coordinator.update(
            store: purchase.storeLocation.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) },
            courier: purchase.liveCourier.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) },
            destination: purchase.liveDestination,
            showRoute: purchase.isDelivery && purchase.isActive,
            labels: (storeName, courierLabel, destinationLabel)
        )
    }

    final class Pin: NSObject, MKAnnotation {
        let kind: String
        @objc dynamic var coordinate: CLLocationCoordinate2D
        let title: String?
        init(kind: String, coordinate: CLLocationCoordinate2D, title: String) {
            self.kind = kind
            self.coordinate = coordinate
            self.title = title
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var map: MKMapView?
        private var pins: [String: Pin] = [:]
        private var route: MKPolyline?
        private var routeFrom: CLLocation?
        private var routeAt: Date?
        private var routing = false
        private var fitted = false
        private var destinationCoordinate: CLLocationCoordinate2D?
        private var geocodedQuery: String?
        private static var geocodeCache: [String: CLLocationCoordinate2D] = [:]

        func update(store: CLLocationCoordinate2D?, courier: CLLocationCoordinate2D?, destination: DeliveryDestination?,
                    showRoute: Bool, labels: (String, String, String)) {
            place("store", store, labels.0)
            place("courier", courier, labels.1)
            if let destination, showRoute {
                resolve(destination) { [weak self] coordinate in
                    guard let self else { return }
                    self.place("destination", coordinate, labels.2)
                    self.updateRoute(from: courier ?? store, to: coordinate)
                    self.fit()
                }
            } else {
                place("destination", nil, labels.2)
                fit()
            }
        }

        private func place(_ kind: String, _ coordinate: CLLocationCoordinate2D?, _ title: String) {
            guard let map else { return }
            if let coordinate {
                if let pin = pins[kind] {
                    UIView.animate(withDuration: 0.6) { pin.coordinate = coordinate }
                } else {
                    let pin = Pin(kind: kind, coordinate: coordinate, title: title)
                    pins[kind] = pin
                    map.addAnnotation(pin)
                }
            } else if let pin = pins.removeValue(forKey: kind) {
                map.removeAnnotation(pin)
            }
        }

        /// La dirección se ubica una vez por pedido (y queda en caché entre pantallas).
        private func resolve(_ destination: DeliveryDestination, done: @escaping (CLLocationCoordinate2D) -> Void) {
            let query = destination.query
            if let cached = Self.geocodeCache[query] {
                destinationCoordinate = cached
                done(cached)
                return
            }
            guard geocodedQuery != query else {
                if let destinationCoordinate { done(destinationCoordinate) }
                return
            }
            geocodedQuery = query
            CLGeocoder().geocodeAddressString(query) { [weak self] placemarks, _ in
                guard let coordinate = placemarks?.first?.location?.coordinate else { return }
                Self.geocodeCache[query] = coordinate
                self?.destinationCoordinate = coordinate
                DispatchQueue.main.async { done(coordinate) }
            }
        }

        private func updateRoute(from origin: CLLocationCoordinate2D?, to destination: CLLocationCoordinate2D) {
            guard let origin, !routing else { return }
            let here = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            if let routeFrom, let routeAt, here.distance(from: routeFrom) < 150, Date().timeIntervalSince(routeAt) < 60 { return }
            routing = true
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
            request.transportType = .automobile
            MKDirections(request: request).calculate { [weak self] response, _ in
                guard let self else { return }
                self.routing = false
                guard let polyline = response?.routes.first?.polyline, let map = self.map else { return }
                if let old = self.route { map.removeOverlay(old) }
                self.route = polyline
                self.routeFrom = here
                self.routeAt = Date()
                map.addOverlay(polyline, level: .aboveRoads)
                self.fitted = false
                self.fit()
            }
        }

        /// Encuadra tienda, domiciliario, destino y ruta (una vez, y al cambiar la ruta).
        private func fit() {
            guard let map, !fitted, !pins.isEmpty else { return }
            var rect = MKMapRect.null
            for pin in pins.values {
                let point = MKMapPoint(pin.coordinate)
                rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
            }
            if let route { rect = rect.union(route.boundingMapRect) }
            guard pins.count > 1 || route != nil else { return }
            map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 44, left: 36, bottom: 36, right: 36), animated: true)
            fitted = true
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor(red: 0x1A / 255, green: 0x7F / 255, blue: 0x4B / 255, alpha: 0.9)
            renderer.lineWidth = 5
            renderer.lineCap = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? Pin else { return nil }
            let view = MKMarkerAnnotationView(annotation: pin, reuseIdentifier: pin.kind)
            view.titleVisibility = .visible
            view.displayPriority = .required
            switch pin.kind {
            case "store":
                view.markerTintColor = UIColor(red: 1, green: 0x6A / 255, blue: 0, alpha: 1)
                view.glyphImage = UIImage(systemName: "storefront.fill")
            case "courier":
                view.markerTintColor = UIColor(red: 0x1A / 255, green: 0x7F / 255, blue: 0x4B / 255, alpha: 1)
                view.glyphImage = UIImage(systemName: "bicycle")
                view.zPriority = .max
            default:
                view.markerTintColor = UIColor(red: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255, alpha: 1)
                view.glyphImage = UIImage(systemName: "house.fill")
            }
            return view
        }
    }
}

// MARK: - Chat con el domiciliario

/// Código de entrega: el cliente se lo dicta al domiciliario al recibir el
/// pedido; sin él, el domiciliario no puede cerrar la entrega.
struct DeliveryCodeCard: View {
    let code: String
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 6) {
            Label(language == .es ? "Código de entrega" : "Delivery code", systemImage: "key.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.inkMuted)
            Text(code.map(String.init).joined(separator: " "))
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundColor(.ink)
                .textSelection(.enabled)
                .accessibilityLabel(code.map(String.init).joined(separator: " "))
            Text(language == .es
                 ? "Díctaselo al domiciliario cuando recibas tu pedido. No lo compartas antes."
                 : "Tell it to the courier when you receive your order. Don't share it before.")
                .font(.system(size: 13))
                .foregroundColor(.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// Cuántos mensajes del domiciliario ya vio el cliente, por entrega (en el
/// teléfono). Lo que el servidor cuenta de más son los mensajes sin leer.
final class ChatSeen: ObservableObject {
    static let shared = ChatSeen()
    private let key = "market.chatSeen"
    @Published private var seen: [String: Int]

    private init() {
        seen = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    func unread(_ purchase: CustomerPurchase) -> Int {
        guard let delivery = purchase.delivery, let id = delivery.id, purchase.isActive else { return 0 }
        return max(0, (delivery.courierMessages ?? 0) - (seen[id] ?? 0))
    }

    func markSeen(deliveryId: String, count: Int) {
        guard count > (seen[deliveryId] ?? 0) else { return }
        seen[deliveryId] = count
        UserDefaults.standard.set(seen, forKey: key)
    }
}

/// Burbuja roja con el número de mensajes sin leer.
struct UnreadBadge: View {
    let count: Int
    var body: some View {
        if count > 0 {
            Text(count > 9 ? "9+" : "\(count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(Capsule().fill(Color.red))
                .accessibilityLabel("\(count)")
        }
    }
}

struct DeliveryChatSheet: View {
    let deliveryId: String
    let language: AppLanguage

    @EnvironmentObject private var session: MarketSession
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [MarketAPI.ChatMessage] = []
    @State private var draft = ""
    @State private var picked: PhotosPickerItem?
    @State private var sending = false
    @State private var errorText: String?

    var body: some View {
        let text = TrackText(language: language)
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            if messages.isEmpty {
                                Text(text.noMessages).font(.system(size: 14)).foregroundColor(.inkMuted).multilineTextAlignment(.center).padding(32)
                            }
                            ForEach(messages) { message in
                                bubble(message, text).id(message.id)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                if let errorText { Text(errorText).font(.system(size: 13)).foregroundColor(.red).padding(.horizontal, 12) }
                HStack(spacing: 8) {
                    PhotosPicker(selection: $picked, matching: .images) {
                        Image(systemName: "photo").font(.system(size: 20)).frame(width: 36, height: 36)
                    }
                    TextField(text.message, text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white))
                    Button { Task { await send(jpeg: nil) } } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).foregroundColor(.brandGreen)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || sending)
                }
                .padding(10)
                .background(Color.paper)
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle(text.chat)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(text.close) { dismiss() } } }
            .onChange(of: picked) { item in
                guard let item else { return }
                Task {
                    defer { picked = nil }
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                       let jpeg = image.resizedJpeg(maxSide: 1280) {
                        await send(jpeg: jpeg)
                    }
                }
            }
            .task { await poll() }
        }
    }

    private func bubble(_ message: MarketAPI.ChatMessage, _ text: TrackText) -> some View {
        let mine = message.sender == "cliente"
        return HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                if !mine {
                    Text(message.senderName ?? (message.sender == "tienda" ? text.store : text.courier))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.inkMuted)
                }
                if let url = message.imageUrl, let parsed = URL(string: url) {
                    AsyncImage(url: parsed) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() } else { ProgressView() }
                    }
                    .frame(maxWidth: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if let body = message.body, !body.isEmpty {
                    Text(body).font(.system(size: 15)).foregroundColor(mine ? .white : .ink)
                }
                Text(OrderDate.chatStamp(message.createdAt, language: language))
                    .font(.system(size: 11))
                    .foregroundColor(mine ? .white.opacity(0.75) : .inkMuted)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(mine ? Color.brandGreen : Color.white))
            if !mine { Spacer(minLength: 40) }
        }
    }

    private func load() async {
        guard let token = session.token else { return }
        if let response = try? await MarketAPI.deliveryChat(token: token, deliveryId: deliveryId), response.success == true {
            messages = response.messages ?? []
            ChatSeen.shared.markSeen(deliveryId: deliveryId, count: messages.filter { $0.sender != "cliente" }.count)
        }
    }

    private func poll() async {
        while !Task.isCancelled {
            await load()
            try? await Task.sleep(nanoseconds: 8_000_000_000)
        }
    }

    private func send(jpeg: Data?) async {
        guard let token = session.token else { return }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard jpeg != nil || !body.isEmpty else { return }
        sending = true
        errorText = nil
        defer { sending = false }
        do {
            let response = try await MarketAPI.sendDeliveryMessage(token: token, deliveryId: deliveryId, body: body, jpeg: jpeg)
            if response.success == true {
                draft = ""
                messages = response.messages ?? messages
            } else {
                errorText = response.error
            }
        } catch {
            errorText = TrackText(language: language).error
        }
    }
}

// MARK: - Comprobante de pago

struct PaymentProofSheet: View {
    let storeId: String
    let language: AppLanguage

    @EnvironmentObject private var session: MarketSession
    @Environment(\.dismiss) private var dismiss
    @State private var method: String
    @State private var amount: String
    @State private var note = ""
    @State private var picked: PhotosPickerItem?
    @State private var jpeg: Data?
    @State private var preview: UIImage?
    @State private var working = false
    @State private var message: String?
    @State private var failed = false
    @State private var orders: [MarketAPI.ProofOrderOption] = []
    @State private var orderId: String

    /// Desde el seguimiento del pedido (`purchase`) llega con la compra elegida;
    /// desde "Medios de pago" de la tienda, con el medio y sin compra.
    init(storeId: String, purchase: CustomerPurchase? = nil, initialMethod: String? = nil, language: AppLanguage) {
        self.storeId = storeId
        self.language = language
        let qr = ["NEQUI", "DAVIPLATA", "LLAVE_BREB"]
        let preferred = purchase?.paymentMethod ?? initialMethod ?? ""
        _method = State(initialValue: qr.contains(preferred) ? preferred : "NEQUI")
        _amount = State(initialValue: purchase.map { String(Int($0.total.rounded())) } ?? "")
        _orderId = State(initialValue: purchase.map { "\($0.kind):\($0.id)" } ?? "")
    }

    private var selectedOrder: MarketAPI.ProofOrderOption? { orders.first { $0.id == orderId } }

    var body: some View {
        let text = TrackText(language: language)
        NavigationStack {
            Form {
                Section(text.method) {
                    Picker(text.method, selection: $method) {
                        Text("Nequi").tag("NEQUI")
                        Text("Daviplata").tag("DAVIPLATA")
                        Text("Llave Bre-B").tag("LLAVE_BREB")
                    }
                    .pickerStyle(.segmented)
                    if !orders.isEmpty {
                        Picker(language == .es ? "Compra" : "Purchase", selection: $orderId) {
                            Text(language == .es ? "Sin compra" : "No purchase").tag("")
                            ForEach(orders) { order in
                                Text(orderTitle(order)).tag(order.id)
                            }
                        }
                        .onChange(of: orderId) { _ in
                            if let order = selectedOrder { amount = String(Int(order.total.rounded())) }
                        }
                    }
                    TextField(text.amount, text: $amount).keyboardType(.numberPad)
                    TextField(text.note, text: $note)
                }
                Section {
                    PhotosPicker(selection: $picked, matching: .images) {
                        Label(preview == nil ? text.choosePhoto : text.changePhoto, systemImage: "photo.on.rectangle")
                    }
                    if let preview {
                        Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                Section {
                    if let message { Text(message).foregroundColor(failed ? .red : .brandGreen).font(.system(size: 14)) }
                    Button { Task { await submit(text) } } label: {
                        HStack { Spacer(); Text(working ? text.submitting : text.submit).font(.system(size: 17, weight: .semibold)); Spacer() }
                    }
                    .disabled(working)
                }
            }
            .navigationTitle(text.sendProof)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(text.close) { dismiss() } } }
            .task {
                guard let token = session.token else { return }
                orders = await MarketAPI.proofOrders(token: token, storeId: storeId)
            }
            .onChange(of: picked) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        jpeg = image.resizedJpeg(maxSide: 1600)
                        preview = image
                    }
                }
            }
        }
    }

    private func orderTitle(_ order: MarketAPI.ProofOrderOption) -> String {
        let total = Money.format(order.total, currency: nil)
        if let number = order.orderNumber { return (language == .es ? "Pedido #" : "Order #") + "\(number) · \(total)" }
        return (language == .es ? "Compra · " : "Purchase · ") + total
    }

    private func submit(_ text: TrackText) async {
        guard let token = session.token else { return }
        guard let jpeg else {
            failed = true
            message = text.needPhoto
            return
        }
        working = true
        failed = false
        message = nil
        defer { working = false }
        do {
            let response = try await MarketAPI.submitProof(
                token: token, storeId: storeId, method: method,
                orderKind: selectedOrder?.kind ?? "", orderRef: selectedOrder?.ref ?? "",
                amount: Double(amount.filter(\.isNumber)), note: note.trimmingCharacters(in: .whitespaces), jpeg: jpeg
            )
            if response.success == true {
                message = text.proofSent
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { dismiss() }
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

extension UIImage {
    /// JPEG con el lado mayor limitado (sube rápido y cabe en los 5 MB del servidor).
    func resizedJpeg(maxSide: CGFloat, quality: CGFloat = 0.8) -> Data? {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return jpegData(compressionQuality: quality) }
        let scale = maxSide / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let image = UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return image.jpegData(compressionQuality: quality)
    }
}
