import SwiftUI

/// Textos del contenedor del Market (pestañas, carrito y cuenta).
struct HubText {
    let language: AppLanguage
    private func pick(_ es: String, _ en: String) -> String { language == .es ? es : en }

    var home: String { pick("Inicio", "Home") }
    var cart: String { pick("Carrito", "Cart") }
    var account: String { pick("Cuenta", "Account") }
    var cartEmptyTitle: String { pick("Tu carrito está vacío", "Your cart is empty") }
    var cartEmptyBody: String { pick("Agrega productos desde el catálogo de una tienda.", "Add products from a store's catalog.") }
    var total: String { pick("Total", "Total") }
    var continueOnSite: String { pick("Continuar en el sitio", "Continue on the site") }
    var emptyCart: String { pick("Vaciar carrito", "Empty cart") }
    var signInTitle: String { pick("Inicia sesión", "Sign in") }
    var signInBody: String { pick("Para hacer pedidos y guardar tus favoritos en todos tus dispositivos.", "To place orders and keep your favorites on all your devices.") }
    var email: String { pick("Correo", "Email") }
    var phone: String { pick("Celular", "Mobile") }
    var password: String { pick("Contraseña", "Password") }
    var signIn: String { pick("Iniciar sesión", "Sign in") }
    var signOut: String { pick("Cerrar sesión", "Sign out") }
    var invalid: String { pick("Correo/celular o contraseña incorrectos.", "Incorrect email/mobile or password.") }
    var networkError: String { pick("No pudimos conectarnos. Inténtalo de nuevo.", "We couldn't connect. Please try again.") }
    var language_: String { pick("Idioma", "Language") }
    var hello: String { pick("Hola", "Hi") }
}

enum HubTab: Hashable {
    case home, cart, account
}

/// Pestaña activa del Market; las pantallas internas la usan para saltar al carrito.
@MainActor
final class MarketNav: ObservableObject {
    @Published var tab = HubTab.home
}

/// Market nativo: pestañas Inicio, Carrito y Cuenta. Las demás (buscador,
/// favoritos) se suman en las siguientes etapas del plan.
struct MarketHub: View {
    let language: AppLanguage
    let onLanguage: (AppLanguage) -> Void
    let onExit: () -> Void
    let onOpenWeb: (String) -> Void

    @StateObject private var cart = MarketCart()
    @StateObject private var session = MarketSession()
    @StateObject private var nav = MarketNav()

    var body: some View {
        let text = HubText(language: language)
        TabView(selection: $nav.tab) {
            MarketScreen(language: language, onExit: onExit, onOpenWeb: onOpenWeb)
                .tabItem { Label(text.home, systemImage: "storefront") }
                .tag(HubTab.home)
            CartScreen(language: language, onOpenWeb: onOpenWeb)
                .tabItem { Label(text.cart, systemImage: "cart") }
                .tag(HubTab.cart)
                .badge(cart.itemCount)
            AccountScreen(language: language, onLanguage: onLanguage)
                .tabItem { Label(text.account, systemImage: "person.crop.circle") }
                .tag(HubTab.account)
        }
        .tint(.brandOrange)
        .environmentObject(cart)
        .environmentObject(session)
        .environmentObject(nav)
        .task { await session.refresh() }
    }
}

// MARK: - Carrito

struct CartScreen: View {
    let language: AppLanguage
    let onOpenWeb: (String) -> Void

    @EnvironmentObject private var cart: MarketCart

    var body: some View {
        let text = HubText(language: language)
        NavigationStack {
            Group {
                if cart.carts.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "cart").font(.system(size: 34)).foregroundColor(.inkMuted)
                        Text(text.cartEmptyTitle).font(.headline)
                        Text(text.cartEmptyBody).font(.subheadline).foregroundColor(.inkMuted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(cart.carts) { storeCart in
                            Section(storeCart.storeName) {
                                ForEach(storeCart.lines) { line in
                                    CartLineRow(line: line, currency: storeCart.currency) { quantity in
                                        cart.setQuantity(quantity, storeId: storeCart.storeId, code: line.code)
                                    }
                                }
                                HStack {
                                    Text(text.total).font(.system(size: 16, weight: .semibold))
                                    Spacer()
                                    Text(Money.format(storeCart.total, currency: storeCart.currency))
                                        .font(.system(size: 16, weight: .bold))
                                }
                                Button(text.continueOnSite) { onOpenWeb("/tiendas/\(storeCart.storeId)") }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.brandOrange)
                                Button(text.emptyCart, role: .destructive) { cart.clear(storeId: storeCart.storeId) }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle(text.cart)
        }
    }
}

private struct CartLineRow: View {
    let line: CartLine
    let currency: String?
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: line.imageUrl)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(line.description).font(.system(size: 15, weight: .medium)).lineLimit(2)
                Text(Money.format(line.subtotal, currency: currency)).font(.system(size: 14)).foregroundColor(.inkMuted)
            }
            Spacer()
            QuantityStepper(quantity: line.quantity, onChange: onChange)
        }
    }
}

/// Control − cantidad + (los botones tienen su propia zona de toque para que
/// funcionen dentro de listas y tarjetas).
struct QuantityStepper: View {
    let quantity: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button { onChange(quantity - 1) } label: {
                Image(systemName: quantity <= 1 ? "trash" : "minus").frame(width: 34, height: 34)
            }
            .buttonStyle(.borderless)
            Text("\(quantity)").font(.system(size: 15, weight: .semibold)).frame(minWidth: 22)
            Button { onChange(quantity + 1) } label: {
                Image(systemName: "plus").frame(width: 34, height: 34)
            }
            .buttonStyle(.borderless)
        }
        .background(Capsule().fill(Color.brandOrange.opacity(0.12)))
        .foregroundColor(.brandOrange)
    }
}

// MARK: - Cuenta

struct AccountScreen: View {
    let language: AppLanguage
    let onLanguage: (AppLanguage) -> Void

    @EnvironmentObject private var session: MarketSession

    var body: some View {
        let text = HubText(language: language)
        NavigationStack {
            List {
                if let customer = session.customer {
                    Section {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(text.hello), \(customer.fullName)").font(.system(size: 17, weight: .semibold))
                            Text(customer.email).font(.system(size: 14)).foregroundColor(.inkMuted)
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    Section {
                        LoginForm(language: language)
                    } header: {
                        Text(text.signInTitle)
                    } footer: {
                        Text(text.signInBody)
                    }
                }
                Section(text.language_) {
                    Picker(text.language_, selection: Binding(get: { language }, set: onLanguage)) {
                        ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if session.isSignedIn {
                    Section {
                        Button(text.signOut, role: .destructive) { session.signOut() }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle(text.account)
        }
    }
}

private struct LoginForm: View {
    let language: AppLanguage

    @EnvironmentObject private var session: MarketSession
    @State private var byPhone = false
    @State private var email = ""
    @State private var country = DialCountry.common[0]
    @State private var phone = ""
    @State private var password = ""
    @State private var working = false
    @State private var message: String?

    var body: some View {
        let text = HubText(language: language)
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $byPhone) {
                Text(text.email).tag(false)
                Text(text.phone).tag(true)
            }
            .pickerStyle(.segmented)
            if byPhone {
                HStack {
                    Picker("", selection: $country) {
                        ForEach(DialCountry.common) { Text("\($0.iso2) \($0.dialCode)").tag($0) }
                    }
                    .labelsHidden()
                    TextField(text.phone, text: $phone)
                        .keyboardType(.numberPad)
                        .textContentType(.telephoneNumber)
                }
            } else {
                TextField(text.email, text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            SecureField(text.password, text: $password)
                .textContentType(.password)
            if let message {
                Text(message).font(.system(size: 13)).foregroundColor(.red)
            }
            Button {
                Task { await submit(text) }
            } label: {
                if working {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 28)
                } else {
                    Text(text.signIn).frame(maxWidth: .infinity, minHeight: 28)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandOrange)
            .disabled(working || password.isEmpty || (byPhone ? phone.isEmpty : email.isEmpty))
        }
        .padding(.vertical, 4)
    }

    private func submit(_ text: HubText) async {
        working = true
        message = nil
        defer { working = false }
        do {
            if byPhone {
                try await session.signIn(country: country, phone: phone.trimmingCharacters(in: .whitespaces), password: password)
            } else {
                try await session.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            }
            password = ""
        } catch MarketSession.LoginError.rejected(let reason) {
            message = reason ?? text.invalid
        } catch {
            message = text.networkError
        }
    }
}
