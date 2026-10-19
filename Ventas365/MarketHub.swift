import SwiftUI

/// Textos del contenedor del Market (pestañas, carrito y cuenta).
struct HubText {
    let language: AppLanguage
    private func pick(_ es: String, _ en: String) -> String { language == .es ? es : en }

    var home: String { pick("Inicio", "Home") }
    var search: String { pick("Buscar", "Search") }
    var favorites: String { pick("Favoritos", "Favorites") }
    var cart: String { pick("Carrito", "Cart") }
    var account: String { pick("Cuenta", "Account") }
    var cartEmptyTitle: String { pick("Tu carrito está vacío", "Your cart is empty") }
    var cartEmptyBody: String { pick("Agrega productos desde el catálogo de una tienda.", "Add products from a store's catalog.") }
    var total: String { pick("Total", "Total") }
    var continueOrder: String { pick("Continuar pedido", "Continue order") }
    var myOrders: String { pick("Mis pedidos", "My orders") }
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
    var hello: String { pick("Hola", "Hi") }
}

enum HubTab: Hashable {
    case home, search, favorites, cart, account
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
    let onExit: () -> Void

    @StateObject private var cart = MarketCart()
    @StateObject private var session = MarketSession()
    @StateObject private var nav = MarketNav()
    @StateObject private var favorites = MarketFavorites()

    var body: some View {
        let text = HubText(language: language)
        TabView(selection: $nav.tab) {
            MarketScreen(language: language, onExit: onExit)
                .tabItem { Label(text.home, systemImage: "storefront") }
                .tag(HubTab.home)
            SearchScreen(language: language)
                .tabItem { Label(text.search, systemImage: "magnifyingglass") }
                .tag(HubTab.search)
            FavoritesScreen(language: language)
                .tabItem { Label(text.favorites, systemImage: "heart") }
                .tag(HubTab.favorites)
            CartScreen(language: language)
                .tabItem { Label(text.cart, systemImage: "cart") }
                .tag(HubTab.cart)
                .badge(cart.itemCount)
            AccountScreen(language: language)
                .tabItem { Label(text.account, systemImage: "person.crop.circle") }
                .tag(HubTab.account)
        }
        .tint(.brandOrange)
        .modifier(LiquidGlassTabs())
        .environmentObject(cart)
        .environmentObject(session)
        .environmentObject(nav)
        .environmentObject(favorites)
        .task { await session.refresh() }
        // Favoritos de la cuenta al entrar; los del dispositivo pasan a ella.
        .task(id: session.customer?.id) {
            if let token = session.token, session.isSignedIn {
                await favorites.attach(token: token)
            } else {
                await favorites.reload(token: nil)
            }
        }
    }
}

/// Con iOS 26 la barra de pestañas, las barras de navegación y la búsqueda ya
/// usan Liquid Glass sin hacer nada; aquí solo se pide que la barra de
/// pestañas se compacte al desplazar. En versiones anteriores no cambia.
struct LiquidGlassTabs: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

/// Botón principal: cristal en iOS 26, relleno de color en versiones anteriores.
struct PrimaryActionStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent).tint(.brandGreen)
        } else {
            content.buttonStyle(.borderedProminent).tint(.brandGreen)
        }
    }
}

// MARK: - Carrito

struct CartScreen: View {
    let language: AppLanguage

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
                                NavigationLink(value: OrderRoute(storeId: storeCart.storeId)) {
                                    Text("\(text.continueOrder) · \(storeCart.itemCount)")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.brandGreen)
                                }
                                Button(text.emptyCart, role: .destructive) { cart.clear(storeId: storeCart.storeId) }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle(text.cart)
            .navigationDestination(for: OrderRoute.self) { route in
                OrderScreen(storeId: route.storeId, language: language)
            }
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
        .background(Capsule().fill(Color.brandGreen))
        .foregroundColor(.white)
    }
}

// MARK: - Cuenta

struct AccountScreen: View {
    let language: AppLanguage

    @EnvironmentObject private var session: MarketSession
    @StateObject private var proofs = PaymentProofsModel()

    var body: some View {
        let text = HubText(language: language)
        NavigationStack {
            Group {
                if let customer = session.customer {
                    let info = AccountText(language: language)
                    List {
                        Section {
                            HStack(spacing: 14) {
                                AvatarView(customer: customer, size: 64)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(customer.fullName).font(.system(size: 18, weight: .bold))
                                    Text(customer.email).font(.system(size: 14)).foregroundColor(.inkMuted)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        Section {
                            if !customer.phoneLabel.isEmpty {
                                LabeledContent { Text(customer.phoneLabel) } label: { Label(info.phone, systemImage: "phone") }
                            }
                            if let document = customer.documentNumber, !document.isEmpty {
                                LabeledContent { Text(document) } label: { Label(info.document, systemImage: "person.text.rectangle") }
                            }
                            if let city = customer.city, !city.isEmpty {
                                LabeledContent { Text(city) } label: { Label(info.city, systemImage: "mappin.and.ellipse") }
                            }
                        }
                        if !proofs.proofs.isEmpty {
                            Section {
                                ForEach(proofs.proofs.prefix(3)) { proof in
                                    NavigationLink { ProofDetail(proof: proof, language: language) } label: {
                                        ProofRow(proof: proof, language: language)
                                    }
                                }
                            } header: {
                                Label(info.myProofs.uppercased(), systemImage: "doc.text")
                            }
                        }
                        Section {
                            NavigationLink { ProfileScreen(language: language) } label: { Label(info.myInfo, systemImage: "person") }
                            NavigationLink { MyOrdersScreen(language: language) } label: { Label(info.myPurchases, systemImage: "bag") }
                            NavigationLink { PaymentProofsScreen(language: language) } label: { Label(info.myProofs, systemImage: "doc.text") }
                        }
                        Section {
                            Button(text.signOut, role: .destructive) { session.signOut() }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .task(id: customer.id) { await proofs.load(token: session.token) }
                    .refreshable { await proofs.load(token: session.token) }
                } else {
                    ScrollView { AccountWelcome(language: language) }
                }
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle(text.account)
            .navigationDestination(for: AuthRoute.self) { _ in
                LoginScreen(language: language)
            }
        }
    }
}
