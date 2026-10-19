import SwiftUI

/// Destino al continuar el pedido de una tienda desde el carrito.
struct OrderRoute: Hashable {
    let storeId: String
}

/// Textos de pedido, confirmación y Mis pedidos.
struct OrderText {
    let language: AppLanguage
    private func pick(_ es: String, _ en: String) -> String { language == .es ? es : en }

    var confirmTitle: String { pick("Confirmar pedido", "Confirm order") }
    var yourOrder: String { pick("Tu pedido", "Your order") }
    var receiveHow: String { pick("¿Cómo quieres recibir tu pedido?", "How would you like to receive it?") }
    var pickup: String { pick("Recoger en tienda", "Store pickup") }
    var delivery: String { pick("Domicilio", "Delivery") }
    var customerData: String { pick("Datos del cliente", "Customer details") }
    var name: String { pick("Nombre completo", "Full name") }
    var document: String { pick("Número de documento", "ID number") }
    var phone: String { pick("Celular", "Mobile") }
    var signInToOrder: String { pick("Para poder comprar, entra con tu cuenta de cliente del Market.", "To place an order, sign in with your Market customer account.") }
    var signIn: String { pick("Entrar a mi cuenta", "Sign in") }
    var otherPerson: String { pick("¿Recibe otra persona?", "Is someone else receiving it?") }
    var otherPersonHint: String { pick("Indica quién recibirá el pedido en tu lugar.", "Tell us who will receive the order for you.") }
    var receiverName: String { pick("Nombre completo de quien recibe", "Receiver's full name") }
    var receiverDocument: String { pick("Documento de quien recibe", "Receiver's ID number") }
    var receiverPhone: String { pick("Celular de quien recibe", "Receiver's mobile") }
    var deliveryData: String { pick("Datos de entrega", "Delivery details") }
    var pickupData: String { pick("Datos de recogida", "Pickup details") }
    var myAddress: String { pick("Mi dirección registrada", "My registered address") }
    var otherAddress: String { pick("Otra dirección", "Another address") }
    var city: String { pick("Ciudad", "City") }
    var address: String { pick("Dirección", "Address") }
    var complement: String { pick("Apartamento, torre, indicaciones (opcional)", "Apartment, tower, notes (optional)") }
    var saveAddress: String { pick("Guardar esta dirección en mi cuenta", "Save this address to my account") }
    var directions: String { pick("Cómo llegar", "Directions") }
    var payment: String { pick("Forma de pago", "Payment method") }
    var paymentHint: String { pick("Elige cómo pagarás tu pedido. El pago se hace con la tienda.", "Choose how you'll pay. Payment is made with the store.") }
    var send: String { pick("Confirmar pedido", "Place order") }
    var sending: String { pick("Enviando…", "Sending…") }
    var total: String { pick("Total", "Total") }
    var storeClosed: String { pick("La tienda está cerrada en este momento. Puedes armar el pedido y enviarlo cuando abra.", "The store is closed right now. You can build your order and send it when it opens.") }
    var belowMinimum: String { pick("El pedido mínimo de esta tienda es", "This store's minimum order is") }
    var loadError: String { pick("No pudimos cargar la tienda.", "We couldn't load the store.") }
    var retry: String { pick("Reintentar", "Try again") }
    var emptyOrder: String { pick("Este pedido ya no tiene productos.", "This order has no products left.") }
    var genericError: String { pick("No se pudo enviar tu pedido. Intenta de nuevo.", "Your order couldn't be sent. Please try again.") }
    var received: String { pick("¡Pedido enviado!", "Order sent!") }
    var receivedBody: String { pick("La tienda recibió tu pedido. Te avisaremos cuando avance.", "The store received your order. We'll let you know as it moves along.") }
    var share: String { pick("Compartir pedido", "Share order") }
    var writeStore: String { pick("Escribir a la tienda", "Message the store") }
    var viewOrders: String { pick("Ver mis pedidos", "View my orders") }
    var done: String { pick("Listo", "Done") }
    var products: String { pick("Productos", "Products") }
    var payWith: String { pick("Pago", "Payment") }
    var receiver: String { pick("Recibe", "Receiver") }
    var myOrders: String { pick("Mis pedidos", "My orders") }
    var inProgress: String { pick("En curso", "In progress") }
    var previous: String { pick("Anteriores", "Previous") }
    var noOrders: String { pick("Aún no tienes pedidos.", "You have no orders yet.") }
    var ordersError: String { pick("No pudimos cargar tus pedidos.", "We couldn't load your orders.") }
    var courier: String { pick("Domiciliario", "Courier") }

    func summaryLine(count: Int) -> String {
        language == .es ? "\(count) producto\(count == 1 ? "" : "s")" : "\(count) product\(count == 1 ? "" : "s")"
    }

    func type(_ raw: String?) -> String {
        switch raw {
        case "domicilio": return delivery
        case "llevar": return pickup
        case "local": return pick("En la tienda", "In store")
        default: return ""
        }
    }

    func stage(_ stage: CustomerPurchase.Stage) -> String {
        switch stage {
        case .sent: return pick("Enviado a la tienda", "Sent to the store")
        case .accepted: return pick("Aceptado", "Accepted")
        case .preparing: return pick("Preparando", "Preparing")
        case .ready: return pick("Listo", "Ready")
        case .onTheWay: return pick("En camino", "On the way")
        case .delivered: return pick("Entregado", "Delivered")
        case .completed: return pick("Completado", "Completed")
        }
    }

    /// Mensajes del servidor traducidos por código; el resto llega ya en español.
    func serverError(code: String?, message: String?) -> String {
        if language == .es { return message ?? genericError }
        switch code {
        case "login_required": return "Your session expired. Please sign in again."
        case "store_closed": return "The store is closed right now."
        case "below_minimum": return "The order doesn't reach the store's minimum."
        case "out_of_stock": return "There isn't enough stock for one of your products."
        case "product_unavailable": return "A product in your order is no longer available."
        case "profile_incomplete": return "Complete your name, ID and mobile in your account to order."
        default: return genericError
        }
    }
}

@MainActor
final class OrderModel: ObservableObject {
    @Published var store: MarketStore?
    @Published var isOpen: Bool?
    @Published var methods: [PaymentMethodKind] = []
    @Published var addresses: [SavedAddress] = []
    @Published var loading = true
    @Published var failed = false

    func load(storeId: String, token: String?) async {
        loading = true
        failed = false
        do {
            guard let found = try await MarketAPI.store(storeId: storeId) else {
                failed = true
                loading = false
                return
            }
            store = found
        } catch {
            failed = true
            loading = false
            return
        }
        async let qr = try? MarketAPI.enabledQrMethods(storeId: storeId)
        async let states = try? MarketAPI.openStates()
        methods = PaymentMethodKind.available(countryIso: store?.countryIso, enabledQr: (await qr) ?? [])
        isOpen = (await states)?[storeId]
        if let token { addresses = await MarketAPI.addresses(token: token) }
        loading = false
    }
}

private enum AddressChoice: Hashable {
    case saved(String)
    case registered
    case other
}

/// Resumen y confirmación del pedido de una tienda, todo dentro de la app.
struct OrderScreen: View {
    let storeId: String
    let language: AppLanguage

    @EnvironmentObject private var cart: MarketCart
    @EnvironmentObject private var session: MarketSession
    @EnvironmentObject private var nav: MarketNav
    @Environment(\.dismiss) private var dismiss

    @StateObject private var model = OrderModel()
    @State private var orderType = OrderType.pickup
    @State private var method: PaymentMethodKind?
    @State private var receivesOther = false
    @State private var receiverName = ""
    @State private var receiverDocument = ""
    @State private var receiverPhone = ""
    @State private var choice = AddressChoice.other
    @State private var city = ""
    @State private var address = ""
    @State private var complement = ""
    @State private var saveNewAddress = true
    @State private var submitting = false
    @State private var errorMessage: String?
    @State private var placed: PlacedOrder?
    @State private var showLogin = false

    private var storeCart: StoreCart? { cart.carts.first { $0.storeId == storeId } }

    var body: some View {
        let text = OrderText(language: language)
        Group {
            if let placed, let store = model.store {
                OrderConfirmation(order: placed, store: store, language: language, onDone: { dismiss() })
            } else if model.loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.failed {
                VStack(spacing: 8) {
                    Text(text.loadError).foregroundColor(.inkMuted)
                    Button(text.retry) { Task { await load() } }.buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let store = model.store, let storeCart {
                form(text, store: store, storeCart: storeCart)
            } else {
                Text(text.emptyOrder).foregroundColor(.inkMuted).padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle(placed == nil ? text.confirmTitle : text.received)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(placed != nil)
        .task { await load() }
        .sheet(isPresented: $showLogin) {
            NavigationStack { LoginScreen(language: language, presentedAsSheet: true) }
        }
    }

    private func load() async {
        await model.load(storeId: storeId, token: session.token)
        if let preferred = model.addresses.first(where: \.isDefault) ?? model.addresses.first {
            choice = .saved(preferred.id)
        } else if hasRegisteredAddress {
            choice = .registered
        }
    }

    private var hasRegisteredAddress: Bool {
        guard let customer = session.customer else { return false }
        return !(customer.address ?? "").isEmpty && !(customer.city ?? "").isEmpty
    }

    // MARK: Formulario

    private func form(_ text: OrderText, store: MarketStore, storeCart: StoreCart) -> some View {
        let currency = store.currencyCode
        let minimum = store.minimumOrder ?? 0
        let belowMinimum = minimum > 0 && storeCart.total < minimum
        let closed = model.isOpen == false
        return Form {
            Section {
                ForEach(storeCart.lines) { line in
                    HStack(spacing: 12) {
                        RemoteImage(url: line.imageUrl)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.description).font(.system(size: 15, weight: .medium)).lineLimit(2)
                            Text(Money.format(line.subtotal, currency: currency)).font(.system(size: 13)).foregroundColor(.inkMuted)
                        }
                        Spacer()
                        QuantityStepper(quantity: line.quantity) { next in
                            cart.setQuantity(next, storeId: storeId, code: line.code)
                        }
                    }
                }
                HStack {
                    Text(text.total).font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text(Money.format(storeCart.total, currency: currency)).font(.system(size: 16, weight: .bold))
                }
            } header: {
                Text("\(text.yourOrder) · \(store.displayName)")
            } footer: {
                if closed { Text(text.storeClosed).foregroundColor(.red) }
                if belowMinimum {
                    Text("\(text.belowMinimum) \(Money.format(minimum, currency: currency)).").foregroundColor(.red)
                }
            }

            Section(text.receiveHow) {
                Picker(text.receiveHow, selection: $orderType) {
                    Text(text.pickup).tag(OrderType.pickup)
                    Text(text.delivery).tag(OrderType.delivery)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            customerSection(text)

            if orderType == .delivery {
                deliverySection(text)
            } else {
                pickupSection(text, store: store)
            }

            Section {
                ForEach(model.methods) { option in
                    Button {
                        method = option
                    } label: {
                        HStack {
                            Text(option.label(language)).foregroundColor(.ink)
                            Spacer()
                            if method == option { Image(systemName: "checkmark").foregroundColor(.brandGreen) }
                        }
                    }
                }
            } header: {
                Text(text.payment)
            } footer: {
                Text(text.paymentHint)
            }

            Section {
                if let errorMessage {
                    Text(errorMessage).font(.system(size: 14)).foregroundColor(.red)
                }
                Button {
                    Task { await submit(text, storeCart: storeCart) }
                } label: {
                    Text(submitting ? text.sending : "\(text.send) · \(Money.format(storeCart.total, currency: currency))")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .modifier(PrimaryActionStyle())
                .disabled(!canConfirm || submitting || closed || belowMinimum)
            }
        }
    }

    private func customerSection(_ text: OrderText) -> some View {
        Section {
            if let customer = session.customer {
                LabeledContent(text.name, value: customer.fullName)
                LabeledContent(text.document, value: customer.documentNumber ?? "")
                LabeledContent(text.phone, value: customer.phone ?? "")
                Toggle(isOn: $receivesOther) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(text.otherPerson).font(.system(size: 16, weight: .semibold))
                        Text(text.otherPersonHint).font(.system(size: 13)).foregroundColor(.inkMuted)
                    }
                }
                .tint(.brandGreen)
                if receivesOther {
                    TextField(text.receiverName, text: $receiverName)
                        .textContentType(.name)
                        .onChange(of: receiverName) { receiverName = String($0.prefix(120)) }
                    TextField(text.receiverDocument, text: $receiverDocument)
                        .onChange(of: receiverDocument) { receiverDocument = String($0.prefix(60)) }
                    TextField(text.receiverPhone, text: $receiverPhone)
                        .keyboardType(.numberPad)
                        .onChange(of: receiverPhone) { value in
                            let digits = value.filter(\.isNumber)
                            receiverPhone = String(digits.prefix(15))
                        }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(text.signInToOrder).font(.system(size: 15))
                    Button(text.signIn) { showLogin = true }
                        .modifier(PrimaryActionStyle())
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text(text.customerData)
        }
    }

    private func deliverySection(_ text: OrderText) -> some View {
        Section(text.deliveryData) {
            ForEach(model.addresses) { saved in
                addressRow(choice: .saved(saved.id), title: saved.label.isEmpty ? saved.address : saved.label, detail: "\(saved.address), \(saved.city)")
            }
            if hasRegisteredAddress, let customer = session.customer {
                addressRow(choice: .registered, title: text.myAddress, detail: "\(customer.address ?? ""), \(customer.city ?? "")")
            }
            if !model.addresses.isEmpty || hasRegisteredAddress {
                addressRow(choice: .other, title: text.otherAddress, detail: nil)
            }
            if choice == .other {
                TextField(text.city, text: $city).textContentType(.addressCity)
                TextField(text.address, text: $address).textContentType(.fullStreetAddress)
                Toggle(text.saveAddress, isOn: $saveNewAddress).tint(.brandGreen)
            }
            TextField(text.complement, text: $complement)
        }
    }

    private func addressRow(choice option: AddressChoice, title: String, detail: String?) -> some View {
        Button {
            choice = option
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .medium)).foregroundColor(.ink)
                    if let detail { Text(detail).font(.system(size: 13)).foregroundColor(.inkMuted) }
                }
                Spacer()
                if choice == option { Image(systemName: "checkmark").foregroundColor(.brandGreen) }
            }
        }
    }

    private func pickupSection(_ text: OrderText, store: MarketStore) -> some View {
        Section(text.pickupData) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.displayName).font(.system(size: 16, weight: .semibold))
                if let address = store.address, !address.isEmpty {
                    Text(address).font(.system(size: 14)).foregroundColor(.inkMuted)
                }
                if !store.place.isEmpty {
                    Text(store.place).font(.system(size: 14)).foregroundColor(.inkMuted)
                }
            }
            if let url = mapsURL(store) {
                Link(destination: url) { Label(text.directions, systemImage: "location") }
            }
        }
    }

    // MARK: Envío

    /// Ciudad y dirección que se enviarán, según lo elegido.
    private var resolvedAddress: (city: String, address: String) {
        switch choice {
        case .saved(let id):
            if let saved = model.addresses.first(where: { $0.id == id }) { return (saved.city, saved.address) }
            return ("", "")
        case .registered:
            return (session.customer?.city ?? "", session.customer?.address ?? "")
        case .other:
            return (city.trimmingCharacters(in: .whitespaces), address.trimmingCharacters(in: .whitespaces))
        }
    }

    private var canConfirm: Bool {
        guard let customer = session.customer, method != nil else { return false }
        guard !(customer.documentNumber ?? "").isEmpty, !(customer.phone ?? "").isEmpty, !customer.fullName.isEmpty else { return false }
        if receivesOther {
            guard !receiverName.trimmingCharacters(in: .whitespaces).isEmpty,
                  !receiverDocument.trimmingCharacters(in: .whitespaces).isEmpty,
                  receiverPhone.count >= 7 else { return false }
        }
        if orderType == .delivery {
            let resolved = resolvedAddress
            return !resolved.city.isEmpty && !resolved.address.isEmpty
        }
        return true
    }

    private func submit(_ text: OrderText, storeCart: StoreCart) async {
        guard let token = session.token, let method else { return }
        submitting = true
        errorMessage = nil
        defer { submitting = false }
        let resolved = resolvedAddress
        let request = PlaceOrderRequest(
            token: token,
            storeId: storeId,
            items: storeCart.lines.map { .init(code: $0.code, quantity: $0.quantity) },
            orderType: orderType.rawValue,
            requestedPaymentMethod: method.rawValue,
            city: orderType == .delivery ? resolved.city : nil,
            address: orderType == .delivery ? resolved.address : nil,
            addressComplement: orderType == .delivery ? complement : nil,
            receiverName: receivesOther ? receiverName.trimmingCharacters(in: .whitespaces) : nil,
            receiverDocumentNumber: receivesOther ? receiverDocument.trimmingCharacters(in: .whitespaces) : nil,
            receiverPhone: receivesOther ? receiverPhone : nil
        )
        do {
            let response = try await MarketAPI.placeOrder(request)
            if response.success == true, let order = response.order {
                if orderType == .delivery, choice == .other, saveNewAddress {
                    let department = model.store?.department ?? ""
                    Task { await MarketAPI.saveAddress(token: token, label: "", address: resolved.address, city: resolved.city, department: department) }
                }
                cart.clear(storeId: storeId)
                placed = order
            } else {
                errorMessage = text.serverError(code: response.code, message: response.error)
            }
        } catch {
            errorMessage = text.genericError
        }
    }

    private func mapsURL(_ store: MarketStore) -> URL? {
        if let latitude = store.latitude, let longitude = store.longitude {
            return URL(string: "http://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(store.displayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        }
        let query = [store.address, store.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        guard !query.isEmpty, let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "http://maps.apple.com/?q=\(encoded)")
    }
}

// MARK: - Pedido enviado

struct OrderConfirmation: View {
    let order: PlacedOrder
    let store: MarketStore
    let language: AppLanguage
    let onDone: () -> Void

    @EnvironmentObject private var nav: MarketNav

    var body: some View {
        let text = OrderText(language: language)
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 54))
                    .foregroundColor(.brandGreen)
                    .padding(.top, 24)
                Text(text.received).font(.system(size: 24, weight: .bold))
                Text(text.receivedBody).font(.system(size: 15)).foregroundColor(.inkMuted).multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(store.displayName) \(order.numberLabel)").font(.system(size: 17, weight: .semibold))
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        chip(text.type(order.orderType))
                        if let kind = PaymentMethodKind(rawValue: order.requestedPaymentMethod) {
                            chip(kind.label(language))
                        }
                    }
                    Divider()
                    ForEach(order.items, id: \.code) { item in
                        HStack(alignment: .top) {
                            Text("\(item.quantity) × \(item.description)").font(.system(size: 15))
                            Spacer()
                            Text(Money.format(item.unitPrice * Double(item.quantity), currency: store.currencyCode))
                                .font(.system(size: 15, weight: .medium))
                        }
                    }
                    Divider()
                    HStack {
                        Text(text.total).font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Text(Money.format(order.total, currency: store.currencyCode)).font(.system(size: 17, weight: .bold))
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                ShareLink(item: summary(text)) {
                    Label(text.share, systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.bordered)
                if order.orderType == "llevar", let url = whatsappURL(text) {
                    Link(destination: url) {
                        Label(text.writeStore, systemImage: "message").frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.bordered)
                }
                Button(text.viewOrders) {
                    onDone()
                    nav.tab = .account
                }
                .buttonStyle(.bordered)
                Button(text.done, action: onDone)
                    .modifier(PrimaryActionStyle())
            }
            .padding(16)
        }
    }

    private func chip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.gray.opacity(0.14)))
    }

    private func summary(_ text: OrderText) -> String {
        var lines = ["\(store.displayName) \(order.numberLabel)", text.type(order.orderType)]
        lines += order.items.map { "\($0.quantity) × \($0.description)" }
        lines.append("\(text.total): \(Money.format(order.total, currency: store.currencyCode))")
        return lines.joined(separator: "\n")
    }

    private func whatsappURL(_ text: OrderText) -> URL? {
        guard var phone = store.phoneNumber?.filter(\.isNumber), !phone.isEmpty else { return nil }
        while phone.hasPrefix("0") { phone.removeFirst() }
        if let dial = DialCountry.common.first(where: { $0.iso2 == (store.countryIso ?? "CO") })?.dialCode.filter(\.isNumber),
           !phone.hasPrefix(dial) {
            phone = dial + phone
        }
        let message = summary(text).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://wa.me/\(phone)?text=\(message)")
    }
}

// MARK: - Mis pedidos

@MainActor
final class MyOrdersModel: ObservableObject {
    enum State {
        case loading
        case loaded([CustomerPurchase])
        case failed
    }

    @Published var state = State.loading

    func load(token: String?) async {
        guard let token else {
            state = .loaded([])
            return
        }
        do {
            state = .loaded(try await MarketAPI.purchases(token: token))
        } catch {
            state = .failed
        }
    }
}

struct MyOrdersScreen: View {
    let language: AppLanguage

    @EnvironmentObject private var session: MarketSession
    @StateObject private var model = MyOrdersModel()

    var body: some View {
        let text = OrderText(language: language)
        Group {
            switch model.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                VStack(spacing: 8) {
                    Text(text.ordersError).foregroundColor(.inkMuted)
                    Button(text.retry) { Task { await model.load(token: session.token) } }.buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let purchases):
                if purchases.isEmpty {
                    Text(text.noOrders).foregroundColor(.inkMuted).padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list(purchases, text)
                }
            }
        }
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle(text.myOrders)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(token: session.token) }
    }

    private func list(_ purchases: [CustomerPurchase], _ text: OrderText) -> some View {
        let active = purchases.filter(\.isActive)
        let previous = purchases.filter { !$0.isActive }
        return List {
            if !active.isEmpty {
                Section(text.inProgress) {
                    ForEach(active) { purchase in
                        NavigationLink { PurchaseDetail(purchase: purchase, language: language) } label: {
                            PurchaseRow(purchase: purchase, language: language)
                        }
                    }
                }
            }
            if !previous.isEmpty {
                Section(text.previous) {
                    ForEach(previous) { purchase in
                        NavigationLink { PurchaseDetail(purchase: purchase, language: language) } label: {
                            PurchaseRow(purchase: purchase, language: language)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await model.load(token: session.token) }
    }
}

struct PurchaseRow: View {
    let purchase: CustomerPurchase
    let language: AppLanguage

    var body: some View {
        let text = OrderText(language: language)
        HStack(spacing: 12) {
            RemoteImage(url: purchase.storeLogoUrl)
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("\(purchase.storeName.capitalized) \(purchase.numberLabel)").font(.system(size: 16, weight: .semibold))
                Text(text.stage(purchase.stage)).font(.system(size: 14)).foregroundColor(.brandGreen)
                Text(OrderDate.short(purchase.date, language: language)).font(.system(size: 13)).foregroundColor(.inkMuted)
            }
            Spacer()
            Text(Money.format(purchase.total, currency: nil)).font(.system(size: 15, weight: .semibold))
        }
        .padding(.vertical, 4)
    }
}
