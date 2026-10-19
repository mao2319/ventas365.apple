import SwiftUI
import PhotosUI

private struct FlexibleDouble: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = Double(text)
        } else {
            value = nil
        }
    }
}

/// Comprobante de pago enviado a una tienda (respuesta de `payment-proofs` → `mine`).
struct PaymentProof: Decodable, Identifiable, Hashable {
    struct StoreRef: Decodable, Hashable {
        let name: String?
        let logoUrl: String?
    }

    let id: String
    let storeId: String
    let method: String
    let orderNumber: Int?
    let orderTotal: Double?
    let amount: Double?
    let note: String?
    let fileUrl: String
    let status: String
    let rejectionReason: String?
    let customerSeenAt: String?
    let createdAt: String
    let stores: StoreRef?

    private enum CodingKeys: String, CodingKey {
        case id, storeId, method, orderNumber, orderTotal, amount, note, fileUrl, status, rejectionReason, customerSeenAt, createdAt, stores
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        storeId = try c.decode(String.self, forKey: .storeId)
        method = try c.decode(String.self, forKey: .method)
        orderNumber = try? c.decode(Int.self, forKey: .orderNumber)
        orderTotal = (try? c.decode(FlexibleDouble.self, forKey: .orderTotal))?.value
        amount = (try? c.decode(FlexibleDouble.self, forKey: .amount))?.value
        note = try? c.decode(String.self, forKey: .note)
        fileUrl = try c.decode(String.self, forKey: .fileUrl)
        status = try c.decode(String.self, forKey: .status)
        rejectionReason = try? c.decode(String.self, forKey: .rejectionReason)
        customerSeenAt = try? c.decode(String.self, forKey: .customerSeenAt)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        stores = try? c.decode(StoreRef.self, forKey: .stores)
    }

    var storeName: String { (stores?.name ?? "").capitalized }
    var value: Double? { amount ?? orderTotal }
    /// Respuesta de la tienda que el cliente aún no ha visto.
    var isUnseen: Bool { status != "nuevo" && customerSeenAt == nil }
    var methodLabel: String {
        switch method {
        case "LLAVE_BREB": return "Llave Bre-B"
        case "NEQUI": return "Nequi"
        case "DAVIPLATA": return "Daviplata"
        default: return method
        }
    }
}

struct AccountText {
    let language: AppLanguage
    private func pick(_ es: String, _ en: String) -> String { language == .es ? es : en }

    var phone: String { pick("Celular", "Phone") }
    var document: String { pick("Documento", "ID number") }
    var city: String { pick("Ciudad", "City") }
    var country: String { pick("País", "Country") }
    var email: String { pick("Email", "Email") }
    var fullName: String { pick("Nombre completo", "Full name") }
    var myInfo: String { pick("Ver mi información", "My information") }
    var deleteAccount: String { pick("Eliminar mi cuenta", "Delete my account") }
    var myPurchases: String { pick("Mis compras", "My purchases") }
    var myProofs: String { pick("Mis comprobantes de pago", "My payment proofs") }
    var changePhoto: String { pick("Cambiar foto", "Change photo") }
    var uploadPhoto: String { pick("Subir foto", "Upload photo") }
    var removePhoto: String { pick("Quitar foto", "Remove photo") }
    var uploading: String { pick("Subiendo…", "Uploading…") }
    var alternatePhone: String { pick("Celular alternativo (opcional)", "Alternate phone (optional)") }
    var alternateHint: String { pick("Puedes dejarlo vacío. Si lo agregas, escribe entre 6 y 15 dígitos.", "You can leave it empty. If you add it, enter 6 to 15 digits.") }
    var save: String { pick("Guardar cambios", "Save changes") }
    var saving: String { pick("Guardando…", "Saving…") }
    var saved: String { pick("Tu información se actualizó correctamente.", "Your information was updated.") }
    var saveError: String { pick("No se pudo actualizar tu información.", "We couldn't update your information.") }
    var photoError: String { pick("No se pudo subir la foto. Intenta de nuevo.", "The photo couldn't be uploaded. Try again.") }
    var supportTitle: String { pick("¿Necesitas actualizar tus datos principales?", "Need to update your main details?") }
    var supportBody: String { pick("Nombre, documento, email, país y celular principal se actualizan con revisión de soporte.", "Name, ID number, email, country and main phone are updated after support review.") }
    var supportButton: String { pick("Solicitar actualización por WhatsApp", "Request an update on WhatsApp") }
    var supportMessage: String { pick("Hola, necesito solicitar una revisión y autorización para actualizar mis datos.", "Hello, I need to request a review to update my details.") }
    var noProofs: String { pick("Aún no has enviado comprobantes de pago.", "You haven't sent any payment proofs yet.") }
    var proofsError: String { pick("No pudimos cargar tus comprobantes.", "We couldn't load your payment proofs.") }
    var retry: String { pick("Reintentar", "Try again") }
    var seeAll: String { pick("Ver todos", "See all") }
    var order: String { pick("Pedido", "Order") }
    var reason: String { pick("Motivo", "Reason") }
    var rejectedDefault: String { pick("La tienda no aceptó este comprobante. Puedes enviar uno nuevo.", "The store didn't accept this proof. You can send a new one.") }
    var accepted: String { pick("La tienda confirmó tu pago.", "The store confirmed your payment.") }
    var inReview: String { pick("La tienda está revisando tu comprobante.", "The store is reviewing your proof.") }
    var file: String { pick("Comprobante enviado", "Proof sent") }
    var amount: String { pick("Valor", "Amount") }
    var note: String { pick("Nota", "Note") }

    func status(_ status: String) -> String {
        switch status {
        case "aceptado": return pick("Aceptado", "Accepted")
        case "rechazado": return pick("Rechazado", "Rejected")
        default: return pick("En revisión", "In review")
        }
    }
}

func proofStatusColor(_ status: String) -> Color {
    switch status {
    case "aceptado": return .brandGreen
    case "rechazado": return .red
    default: return .orange
    }
}

/// Foto de perfil, o la inicial del nombre si no hay.
struct AvatarView: View {
    let customer: MarketCustomer
    var urlOverride: String?? = nil
    var size: CGFloat = 64

    var body: some View {
        let url = urlOverride ?? customer.avatarUrl
        ZStack {
            Circle().fill(Color.brandGreenTint)
            if let url, !url.isEmpty {
                RemoteImage(url: url).clipShape(Circle())
            } else {
                Text(customer.initial)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundColor(.brandGreen)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Comprobantes

@MainActor
final class PaymentProofsModel: ObservableObject {
    enum State {
        case loading
        case loaded([PaymentProof])
        case failed
    }

    @Published var state = State.loading

    var proofs: [PaymentProof] {
        if case .loaded(let list) = state { return list }
        return []
    }

    func load(token: String?) async {
        guard let token else {
            state = .loaded([])
            return
        }
        do {
            state = .loaded(try await MarketAPI.paymentProofs(token: token))
        } catch {
            if case .loaded = state { return }
            state = .failed
        }
    }
}

struct ProofRow: View {
    let proof: PaymentProof
    let language: AppLanguage

    var body: some View {
        let text = AccountText(language: language)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(proof.storeName).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(text.status(proof.status))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(proofStatusColor(proof.status))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(proofStatusColor(proof.status).opacity(0.12)))
            }
            Text(summary(text)).font(.system(size: 13)).foregroundColor(.inkMuted)
            if proof.status == "rechazado" {
                Text("\(text.reason): \(proof.rejectionReason ?? text.rejectedDefault)")
                    .font(.system(size: 13))
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .topLeading) {
            if proof.isUnseen {
                Circle().fill(Color.red).frame(width: 8, height: 8).offset(x: -14, y: 6)
            }
        }
    }

    private func summary(_ text: AccountText) -> String {
        var parts = [proof.methodLabel]
        if let number = proof.orderNumber { parts.append("\(text.order) #\(number)") }
        if let value = proof.value { parts.append(Money.format(value, currency: nil)) }
        parts.append(OrderDate.short(proof.createdAt, language: language))
        return parts.joined(separator: " · ")
    }
}

struct PaymentProofsScreen: View {
    let language: AppLanguage

    @EnvironmentObject private var session: MarketSession
    @StateObject private var model = PaymentProofsModel()

    var body: some View {
        let text = AccountText(language: language)
        Group {
            switch model.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                VStack(spacing: 8) {
                    Text(text.proofsError).foregroundColor(.inkMuted)
                    Button(text.retry) { Task { await model.load(token: session.token) } }.buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let proofs):
                if proofs.isEmpty {
                    Text(text.noProofs).foregroundColor(.inkMuted).padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(proofs) { proof in
                        NavigationLink { ProofDetail(proof: proof, language: language) } label: {
                            ProofRow(proof: proof, language: language)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await model.load(token: session.token) }
                }
            }
        }
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle(text.myProofs)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load(token: session.token)
            if let token = session.token, model.proofs.contains(where: \.isUnseen) {
                await MarketAPI.markProofsSeen(token: token)
            }
        }
    }
}

struct ProofDetail: View {
    let proof: PaymentProof
    let language: AppLanguage

    var body: some View {
        let text = AccountText(language: language)
        List {
            Section {
                LabeledContent(text.status(proof.status), value: OrderDate.short(proof.createdAt, language: language))
                LabeledContent(language == .es ? "Medio" : "Method", value: proof.methodLabel)
                if let number = proof.orderNumber { LabeledContent(text.order, value: "#\(number)") }
                if let value = proof.value { LabeledContent(text.amount, value: Money.format(value, currency: nil)) }
                if let note = proof.note, !note.isEmpty { LabeledContent(text.note, value: note) }
            }
            Section {
                switch proof.status {
                case "rechazado":
                    Text("\(text.reason): \(proof.rejectionReason ?? text.rejectedDefault)").foregroundColor(.red)
                case "aceptado":
                    Text(text.accepted).foregroundColor(.brandGreen)
                default:
                    Text(text.inReview).foregroundColor(.inkMuted)
                }
            }
            if let url = URL(string: proof.fileUrl) {
                Section(text.file) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFit()
                        case .failure: Link(destination: url) { Label(text.file, systemImage: "doc.richtext") }
                        default: ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(proof.storeName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Ver mi información

struct ProfileScreen: View {
    let language: AppLanguage

    @EnvironmentObject private var session: MarketSession
    @State private var picked: PhotosPickerItem?
    @State private var avatarUrl: String?
    @State private var avatarChanged = false
    @State private var uploading = false
    @State private var country = DialCountry.common[0]
    @State private var alternate = ""
    @State private var saving = false
    @State private var message: String?
    @State private var failed = false
    @State private var ready = false

    var body: some View {
        let text = AccountText(language: language)
        Group {
            if let customer = session.customer {
                form(customer, text)
            } else {
                EmptyView()
            }
        }
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle(text.myInfo)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: prepare)
        .onChange(of: picked) { item in
            guard let item else { return }
            Task { await upload(item, text) }
        }
    }

    private func form(_ customer: MarketCustomer, _ text: AccountText) -> some View {
        List {
            Section {
                HStack(spacing: 16) {
                    AvatarView(customer: customer, urlOverride: .some(avatarUrl), size: 72)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(customer.fullName).font(.system(size: 17, weight: .semibold))
                        PhotosPicker(selection: $picked, matching: .images) {
                            Label(uploading ? text.uploading : (avatarUrl == nil ? text.uploadPhoto : text.changePhoto), systemImage: "photo")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .disabled(uploading)
                        if avatarUrl != nil {
                            Button(text.removePhoto, role: .destructive) {
                                avatarUrl = nil
                                avatarChanged = true
                            }
                            .font(.system(size: 13))
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                LabeledContent(text.fullName, value: customer.fullName)
                if let document = customer.documentNumber, !document.isEmpty {
                    LabeledContent(text.document, value: document)
                }
                LabeledContent(text.country, value: countryLabel(customer))
                LabeledContent(text.phone, value: customer.phoneLabel)
                LabeledContent(text.email, value: customer.email)
                if let city = customer.city, !city.isEmpty { LabeledContent(text.city, value: city) }
                if let address = customer.address, !address.isEmpty {
                    LabeledContent(language == .es ? "Dirección" : "Address", value: address)
                }
            }
            Section {
                Picker(text.country, selection: $country) {
                    ForEach(DialCountry.common) { item in
                        Text("\(flagEmoji(item.iso2)) \(item.dialCode) \(item.name)").tag(item)
                    }
                }
                TextField(text.alternatePhone, text: $alternate)
                    .keyboardType(.numberPad)
                    .onChange(of: alternate) { value in
                        let digits = String(value.filter(\.isNumber).prefix(15))
                        if digits != value { alternate = digits }
                    }
            } footer: {
                Text(text.alternateHint)
            }
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text.supportTitle).font(.system(size: 15, weight: .semibold))
                    Text(text.supportBody).font(.system(size: 13)).foregroundColor(.inkMuted)
                    if let url = supportUrl(customer, text) {
                        Link(destination: url) { Label(text.supportButton, systemImage: "message.fill") }
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                if let message {
                    Text(message).foregroundColor(failed ? .red : .brandGreen).font(.system(size: 14))
                }
                Button { Task { await save(text) } } label: {
                    HStack {
                        Spacer()
                        Text(saving ? text.saving : text.save).font(.system(size: 17, weight: .semibold))
                        Spacer()
                    }
                }
                .disabled(saving || uploading)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func countryLabel(_ customer: MarketCustomer) -> String {
        guard let iso = customer.countryIso else { return "" }
        let name = DialCountry.common.first { $0.iso2 == iso }?.name ?? iso
        return "\(flagEmoji(iso)) \(name)"
    }

    private func prepare() {
        guard !ready, let customer = session.customer else { return }
        ready = true
        avatarUrl = customer.avatarUrl
        alternate = customer.alternatePhone ?? ""
        country = DialCountry.common.first { $0.iso2 == (customer.alternatePhoneCountryIso ?? customer.countryIso) } ?? DialCountry.common[0]
    }

    private func supportUrl(_ customer: MarketCustomer, _ text: AccountText) -> URL? {
        let body = "\(text.supportMessage)\n\n• \(text.fullName): \(customer.fullName)\n• \(text.document): \(customer.documentNumber ?? "")\n• \(text.email): \(customer.email)\n• \(text.phone): \(customer.phoneLabel)\n\n"
        var components = URLComponents(string: "https://wa.me/573016226348")
        components?.queryItems = [URLQueryItem(name: "text", value: body)]
        return components?.url
    }

    private func upload(_ item: PhotosPickerItem, _ text: AccountText) async {
        defer { picked = nil }
        guard let customer = session.customer else { return }
        uploading = true
        failed = false
        message = nil
        defer { uploading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = Self.resized(image).jpegData(compressionQuality: 0.85) else { throw MarketAPI.APIError.badResponse }
            avatarUrl = try await MarketAPI.uploadAvatar(customerId: customer.id, jpeg: jpeg)
            avatarChanged = true
        } catch {
            failed = true
            message = text.photoError
        }
    }

    /// La foto se reduce a 800 px para que suba rápido.
    private static func resized(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > 800 else { return image }
        let scale = 800 / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    private func save(_ text: AccountText) async {
        guard let token = session.token else { return }
        saving = true
        failed = false
        message = nil
        defer { saving = false }
        let digits = alternate.filter(\.isNumber)
        if !digits.isEmpty && !(6...15).contains(digits.count) {
            failed = true
            message = text.alternateHint
            return
        }
        do {
            let response = try await MarketAPI.updateProfile(
                token: token,
                alternatePhoneCountryIso: digits.isEmpty ? nil : country.iso2,
                alternatePhone: digits.isEmpty ? nil : digits,
                avatarUrl: avatarUrl
            )
            if response.success == true, let customer = response.customer {
                session.apply(customer)
                message = text.saved
            } else {
                failed = true
                message = response.error ?? text.saveError
            }
        } catch {
            failed = true
            message = text.saveError
        }
    }
}

// MARK: - Pedidos en progreso (Inicio)

/// Pedidos activos del cliente, arriba del Inicio del Market.
struct ActiveOrdersRail: View {
    let language: AppLanguage

    @EnvironmentObject private var session: MarketSession
    @StateObject private var model = MyOrdersModel()

    private var active: [CustomerPurchase] {
        if case .loaded(let list) = model.state { return list.filter(\.isActive) }
        return []
    }

    var body: some View {
        let text = OrderText(language: language)
        Group {
            if !active.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(language == .es ? "Pedidos en progreso" : "Orders in progress")
                        .font(.system(size: 22, weight: .bold))
                        .padding(.horizontal, 16)
                    ForEach(active) { purchase in
                        NavigationLink { PurchaseDetail(purchase: purchase, language: language) } label: {
                            HStack(spacing: 12) {
                                RemoteImage(url: purchase.storeLogoUrl)
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(purchase.storeName.capitalized) \(purchase.numberLabel)")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.ink)
                                    Text(text.stage(purchase.stage))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.brandGreen)
                                }
                                Spacer()
                                Text(Money.format(purchase.total, currency: nil))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.ink)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.inkMuted)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task(id: session.customer?.id) { await model.load(token: session.token) }
    }
}

// MARK: - Eliminar cuenta

/// Confirmación con contraseña para eliminar la cuenta (lo exigen Apple y Google).
struct DeleteAccountSheet: View {
    let language: AppLanguage

    @EnvironmentObject private var session: MarketSession
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var working = false
    @State private var message: String?

    private func pick(_ es: String, _ en: String) -> String { language == .es ? es : en }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(pick(
                        "Se eliminarán tu perfil, direcciones, favoritos, calificaciones y comprobantes. Los pedidos que ya enviaste quedan en el historial de cada tienda. Esta acción no se puede deshacer.",
                        "Your profile, addresses, favorites, ratings and payment proofs will be deleted. Orders you already sent stay in each store's history. This can't be undone."
                    ))
                    .font(.system(size: 14))
                }
                Section(pick("Confirma con tu contraseña", "Confirm with your password")) {
                    SecureField(pick("Contraseña", "Password"), text: $password)
                        .textContentType(.password)
                    if let message {
                        Text(message).font(.system(size: 14)).foregroundColor(.red)
                    }
                }
                Section {
                    Button(role: .destructive) { Task { await delete() } } label: {
                        HStack {
                            Spacer()
                            if working { ProgressView() } else { Text(pick("Eliminar mi cuenta", "Delete my account")).font(.system(size: 17, weight: .semibold)) }
                            Spacer()
                        }
                    }
                    .disabled(password.isEmpty || working)
                }
            }
            .navigationTitle(pick("Eliminar cuenta", "Delete account"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(pick("Cancelar", "Cancel")) { dismiss() } }
            }
        }
    }

    private func delete() async {
        working = true
        message = nil
        defer { working = false }
        if let error = await session.deleteAccount(password: password) {
            message = error == "network" ? pick("No pudimos conectarnos. Inténtalo de nuevo.", "We couldn't connect. Try again.") : error
        } else {
            dismiss()
        }
    }
}
