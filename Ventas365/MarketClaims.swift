import SwiftUI
import PhotosUI
import UserNotifications

// MARK: - Modelos (función `market-order-claims`)

struct ClaimAttachment: Decodable, Hashable {
    let name: String?
    let contentType: String?
    let url: String?

    var isImage: Bool { (contentType ?? "").hasPrefix("image/") && contentType != "image/heic" }
}

struct ClaimMessage: Decodable, Hashable, Identifiable {
    let id: String
    let author: String
    let kind: String
    let decision: String?
    let body: String
    let createdAt: String
    let attachments: [ClaimAttachment]
}

/// Reclamo de un pedido recibido. `enviado` → espera respuesta de la tienda ·
/// `aceptado` / `rechazado` → la tienda respondió · `cerrado` → el cliente
/// aceptó la respuesta.
struct OrderClaim: Decodable, Hashable, Identifiable {
    let id: String
    let storeId: String
    let storeName: String
    let orderKind: String
    let orderId: String
    let orderNumber: Int?
    let status: String
    let round: Int
    let updatedAt: String
    let seen: Bool
    let messages: [ClaimMessage]

    var isOpen: Bool { status != "cerrado" }
    var awaitsCustomer: Bool { status == "aceptado" || status == "rechazado" }
}

struct ClaimsResponse: Decodable {
    let success: Bool?
    let error: String?
    let claims: [OrderClaim]?
}

struct ClaimResponse: Decodable {
    let success: Bool?
    let error: String?
    let claim: OrderClaim?
}

extension MarketAPI {
    private struct ClaimJSON: Encodable {
        let action: String
        let token: String
        var claimId: String?
        var ids: [String]?
    }

    static func myClaims(token: String) async throws -> [OrderClaim] {
        let response: ClaimsResponse = try await invoke("market-order-claims", ClaimJSON(action: "mine", token: token))
        guard response.success == true else { throw APIError.badResponse }
        return response.claims ?? []
    }

    static func createClaim(token: String, saleId: String, body: String, files: [UploadFile]) async throws -> ClaimResponse {
        try await invokeMultipart(
            "market-order-claims",
            fields: [("action", "create"), ("token", token), ("kind", "venta"), ("id", saleId), ("body", body)],
            files: files
        )
    }

    static func replyClaim(token: String, claimId: String, body: String, files: [UploadFile]) async throws -> ClaimResponse {
        try await invokeMultipart(
            "market-order-claims",
            fields: [("action", "reply"), ("token", token), ("claimId", claimId), ("body", body)],
            files: files
        )
    }

    static func acceptClaim(token: String, claimId: String) async throws -> ClaimResponse {
        try await invoke("market-order-claims", ClaimJSON(action: "accept", token: token, claimId: claimId))
    }

    static func markClaimsSeen(token: String, ids: [String]) async {
        guard !ids.isEmpty else { return }
        let _: ClaimsResponse? = try? await invoke("market-order-claims", ClaimJSON(action: "seen", token: token, ids: ids))
    }
}

// MARK: - Textos

struct ClaimText {
    let language: AppLanguage
    private func pick(_ es: String, _ en: String) -> String { language == .es ? es : en }

    var section: String { pick("Reclamo", "Claim") }
    var problem: String { pick("Tengo un problema con este pedido", "I have a problem with this order") }
    var problemHint: String { pick("Cuéntale a la tienda qué pasó y adjunta fotos como evidencia.", "Tell the store what happened and attach photos as evidence.") }
    var another: String { pick("Enviar otro reclamo", "Send another claim") }
    var newTitle: String { pick("Nuevo reclamo", "New claim") }
    var resendTitle: String { pick("Reenviar reclamo", "Resend claim") }
    var describe: String { pick("Describe el problema con tu pedido", "Describe the problem with your order") }
    var explain: String { pick("Explica por qué no estás de acuerdo con la respuesta", "Explain why you disagree with the reply") }
    var evidence: String { pick("Evidencias", "Evidence") }
    var addPhotos: String { pick("Agregar fotos", "Add photos") }
    var evidenceHint: String { pick("Hasta 5 fotos. Adjunta al menos una.", "Up to 5 photos. Attach at least one.") }
    var evidenceOptional: String { pick("Hasta 5 fotos con más soportes (opcional).", "Up to 5 photos with more support (optional).") }
    var send: String { pick("Enviar reclamo", "Send claim") }
    var resend: String { pick("Reenviar con más soportes", "Resend with more support") }
    var accept: String { pick("Aceptar respuesta", "Accept reply") }
    var close: String { pick("Cancelar", "Cancel") }
    var sending: String { pick("Enviando…", "Sending…") }
    var error: String { pick("No se pudo completar. Intenta de nuevo.", "Couldn't complete. Try again.") }
    var reviewing: String { pick("La tienda está revisando tu reclamo. Te avisaremos cuando responda.", "The store is reviewing your claim. We'll let you know when it replies.") }
    var acceptedHint: String { pick("La tienda aceptó tu reclamo. Acepta la respuesta para cerrarlo.", "The store accepted your claim. Accept the reply to close it.") }
    var rejectedHint: String { pick("Puedes aceptar la respuesta o reenviar el reclamo con más soportes.", "You can accept the reply or resend the claim with more support.") }
    var yourClaim: String { pick("Tu reclamo", "Your claim") }
    var resent: String { pick("Reenviaste el reclamo", "You resent the claim") }
    var closedByYou: String { pick("Aceptaste la respuesta y cerraste el reclamo", "You accepted the reply and closed the claim") }
    var storeAccepted: String { pick("La tienda aceptó el reclamo", "The store accepted the claim") }
    var storeRejected: String { pick("La tienda rechazó el reclamo", "The store rejected the claim") }
    var notifyTitle: String { pick("Respuesta a tu reclamo", "Reply to your claim") }

    func status(_ raw: String) -> String {
        switch raw {
        case "enviado": return pick("Reclamo enviado", "Claim sent")
        case "aceptado": return pick("Reclamo aceptado", "Claim accepted")
        case "rechazado": return pick("Reclamo rechazado", "Claim rejected")
        default: return pick("Reclamo cerrado", "Claim closed")
        }
    }

    func statusColor(_ raw: String) -> Color {
        switch raw {
        case "enviado": return .orange
        case "aceptado": return .brandGreen
        case "rechazado": return .red
        default: return .inkMuted
        }
    }

    func notifyBody(store: String, status: String) -> String {
        status == "aceptado"
            ? pick("\(store) aceptó tu reclamo.", "\(store) accepted your claim.")
            : pick("\(store) rechazó tu reclamo. Puedes reenviarlo con más soportes.", "\(store) rejected your claim. You can resend it with more support.")
    }
}

// MARK: - Elegibilidad

extension CustomerPurchase {
    /// Recibido (entregado, o sin domicilio) en los últimos 30 días.
    var canClaim: Bool {
        guard kind == "venta" else { return false }
        if let status = delivery?.status, status != "entregado" { return false }
        let iso = delivery?.deliveredAt ?? date
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let received = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return true }
        return Date().timeIntervalSince(received) <= 30 * 24 * 60 * 60
    }
}

// MARK: - Sección del reclamo en el detalle del pedido

struct ClaimSection: View {
    let purchase: CustomerPurchase
    let language: AppLanguage

    @EnvironmentObject private var session: MarketSession
    @State private var claim: OrderClaim?
    @State private var loaded = false
    @State private var composer: ClaimComposerMode?
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        let text = ClaimText(language: language)
        Group {
            if let claim {
                Section {
                    HStack {
                        Text(text.status(claim.status))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(text.statusColor(claim.status))
                        Spacer()
                    }
                    ForEach(Array(claim.messages.enumerated()), id: \.element.id) { index, message in
                        ClaimMessageRow(message: message, isFirst: index == 0, language: language)
                    }
                    if claim.status == "enviado" {
                        Text(text.reviewing).font(.system(size: 13)).foregroundColor(.inkMuted)
                    }
                    if let errorText { Text(errorText).font(.system(size: 14)).foregroundColor(.red) }
                    if claim.awaitsCustomer {
                        Button { Task { await accept(claim) } } label: {
                            Text(busy ? text.sending : text.accept).font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 28)
                        }
                        .modifier(PrimaryActionStyle())
                        .disabled(busy)
                        if claim.status == "rechazado" {
                            Button { composer = .reply(claim.id) } label: {
                                Label(text.resend, systemImage: "arrow.uturn.forward").frame(maxWidth: .infinity, minHeight: 28)
                            }
                            .modifier(SecondaryActionStyle())
                        }
                    } else if !claim.isOpen, purchase.canClaim {
                        Button { composer = .create } label: { Label(text.another, systemImage: "exclamationmark.bubble") }
                    }
                } header: {
                    Text(text.section)
                } footer: {
                    if claim.status == "aceptado" { Text(text.acceptedHint) }
                    if claim.status == "rechazado" { Text(text.rejectedHint) }
                }
            } else if loaded, purchase.canClaim {
                Section {
                    Button { composer = .create } label: { Label(text.problem, systemImage: "exclamationmark.bubble") }
                } footer: {
                    Text(text.problemHint)
                }
            }
        }
        .task(id: purchase.id) { await load() }
        .sheet(item: $composer) { mode in
            ClaimComposerSheet(mode: mode, saleId: purchase.id, language: language) { updated in
                claim = updated
            }
        }
    }

    private func load() async {
        guard let token = session.token else {
            loaded = true
            return
        }
        if let claims = try? await MarketAPI.myClaims(token: token) {
            claim = claims.first { $0.orderId == purchase.id }
            if let claim, !claim.seen { await MarketAPI.markClaimsSeen(token: token, ids: [claim.id]) }
        }
        loaded = true
    }

    private func accept(_ current: OrderClaim) async {
        guard let token = session.token else { return }
        busy = true
        errorText = nil
        defer { busy = false }
        do {
            let response = try await MarketAPI.acceptClaim(token: token, claimId: current.id)
            if response.success == true, let updated = response.claim {
                claim = updated
            } else {
                errorText = response.error ?? ClaimText(language: language).error
            }
        } catch {
            errorText = ClaimText(language: language).error
        }
    }
}

private struct ClaimMessageRow: View {
    let message: ClaimMessage
    let isFirst: Bool
    let language: AppLanguage

    var body: some View {
        let text = ClaimText(language: language)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title(text))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(message.author == "tienda" ? (message.decision == "aceptado" ? .brandGreen : .red) : .ink)
                Spacer()
                Text(OrderDate.short(message.createdAt, language: language)).font(.system(size: 12)).foregroundColor(.inkMuted)
            }
            if !message.body.isEmpty {
                Text(message.body).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
            }
            if !message.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(message.attachments.enumerated()), id: \.offset) { _, file in
                            attachment(file)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func title(_ text: ClaimText) -> String {
        switch message.kind {
        case "cierre": return text.closedByYou
        case "respuesta": return message.decision == "aceptado" ? text.storeAccepted : text.storeRejected
        default: return isFirst ? text.yourClaim : text.resent
        }
    }

    @ViewBuilder
    private func attachment(_ file: ClaimAttachment) -> some View {
        if let raw = file.url, let url = URL(string: raw) {
            Link(destination: url) {
                Group {
                    if file.isImage {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.gray.opacity(0.15)
                        }
                    } else {
                        Image(systemName: "doc.richtext").font(.system(size: 22)).foregroundColor(.inkMuted)
                    }
                }
                .frame(width: 64, height: 64)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

// MARK: - Nuevo reclamo / reenvío

enum ClaimComposerMode: Identifiable, Hashable {
    case create
    case reply(String)

    var id: String {
        switch self {
        case .create: return "create"
        case .reply(let claimId): return "reply-\(claimId)"
        }
    }
}

struct ClaimComposerSheet: View {
    let mode: ClaimComposerMode
    let saleId: String
    let language: AppLanguage
    let onDone: (OrderClaim) -> Void

    @EnvironmentObject private var session: MarketSession
    @Environment(\.dismiss) private var dismiss
    @State private var body_ = ""
    @State private var picked: [PhotosPickerItem] = []
    @State private var photos: [UIImage] = []
    @State private var busy = false
    @State private var errorText: String?

    private var isCreate: Bool { mode == .create }

    var body: some View {
        let text = ClaimText(language: language)
        NavigationStack {
            Form {
                Section {
                    TextField(isCreate ? text.describe : text.explain, text: $body_, axis: .vertical)
                        .lineLimit(4...8)
                        .onChange(of: body_) { body_ = String($0.prefix(1000)) }
                }
                Section {
                    PhotosPicker(selection: $picked, maxSelectionCount: 5, matching: .images) {
                        Label(text.addPhotos, systemImage: "photo.on.rectangle.angled")
                    }
                    if !photos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(photos.enumerated()), id: \.offset) { _, image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }
                    }
                } header: {
                    Text(text.evidence)
                } footer: {
                    Text(isCreate ? text.evidenceHint : text.evidenceOptional)
                }
                Section {
                    if let errorText { Text(errorText).font(.system(size: 14)).foregroundColor(.red) }
                    Button { Task { await submit(text) } } label: {
                        Text(busy ? text.sending : (isCreate ? text.send : text.resendTitle))
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .modifier(PrimaryActionStyle())
                    .disabled(!canSend)
                }
            }
            .navigationTitle(isCreate ? text.newTitle : text.resendTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(text.close) { dismiss() } } }
            .onChange(of: picked) { items in
                Task {
                    var loaded: [UIImage] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                            loaded.append(image)
                        }
                    }
                    photos = loaded
                }
            }
        }
    }

    private var canSend: Bool {
        !busy && body_.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5 && (!isCreate || !photos.isEmpty)
    }

    private func submit(_ text: ClaimText) async {
        guard let token = session.token else { return }
        busy = true
        errorText = nil
        defer { busy = false }
        let files = photos.enumerated().compactMap { index, image -> MarketAPI.UploadFile? in
            guard let jpeg = image.resizedJpeg(maxSide: 1600) else { return nil }
            return MarketAPI.UploadFile(filename: "evidencia-\(index + 1).jpg", contentType: "image/jpeg", data: jpeg)
        }
        let message = body_.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let response: ClaimResponse
            switch mode {
            case .create:
                response = try await MarketAPI.createClaim(token: token, saleId: saleId, body: message, files: files)
            case .reply(let claimId):
                response = try await MarketAPI.replyClaim(token: token, claimId: claimId, body: message, files: files)
            }
            if response.success == true, let claim = response.claim {
                // Para avisarle cuando la tienda responda.
                ClaimNotifier.requestPermission()
                onDone(claim)
                dismiss()
            } else {
                errorText = response.error ?? text.error
            }
        } catch {
            errorText = text.error
        }
    }
}

// MARK: - Aviso de la respuesta de la tienda

/// Cuando la tienda acepta o rechaza un reclamo, avisa con una notificación
/// local (con la app abierta o al volver a ella). Con la app cerrada llega el
/// correo; las notificaciones push requieren configurar APNs.
@MainActor
enum ClaimNotifier {
    private static var notified = Set<String>()

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func refresh(token: String, language: AppLanguage) async {
        guard let claims = try? await MarketAPI.myClaims(token: token) else { return }
        let text = ClaimText(language: language)
        let fresh = claims.filter { $0.awaitsCustomer && !$0.seen && !notified.contains("\($0.id)-\($0.updatedAt)") }
        for claim in fresh {
            notified.insert("\(claim.id)-\(claim.updatedAt)")
            let content = UNMutableNotificationContent()
            content.title = text.notifyTitle
            content.body = text.notifyBody(store: claim.storeName.capitalized, status: claim.status)
            content.sound = .default
            content.userInfo = ["section": AppSection.market.rawValue]
            // "cancel-" para que el aviso se vea también con la app abierta (ver CourierShift).
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "cancel-claim-\(claim.id)-\(claim.round)", content: content, trigger: nil),
                withCompletionHandler: nil
            )
        }
    }
}
