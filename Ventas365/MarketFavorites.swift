import SwiftUI

/// Favoritos del Market. Con sesión viven en la cuenta (se ven en cualquier
/// dispositivo); sin sesión se guardan con el id del dispositivo. Al iniciar
/// sesión los del dispositivo pasan a la cuenta.
@MainActor
final class MarketFavorites: ObservableObject {
    @Published private(set) var stores: Set<String> = []
    @Published private(set) var products: Set<String> = []

    private var token: String?

    func isFavorite(store id: String) -> Bool { stores.contains(id) }

    func isFavorite(product code: String, store id: String) -> Bool {
        products.contains(MarketAPI.favoriteKey(id, code))
    }

    /// Carga los favoritos que corresponden a la sesión actual.
    func reload(token: String?) async {
        self.token = token
        do {
            let snapshot: MarketAPI.FavoriteSnapshot
            if let token {
                snapshot = try await MarketAPI.accountFavorites(token: token)
            } else {
                snapshot = try await MarketAPI.deviceFavorites(anonId: MarketDevice.anonId)
            }
            stores = snapshot.stores
            products = snapshot.products
        } catch {
            // Sin conexión se conserva lo que ya se mostraba.
        }
    }

    /// Al entrar a la cuenta: pasa los favoritos del dispositivo y recarga.
    func attach(token: String) async {
        await MarketAPI.mergeDeviceFavorites(token: token, anonId: MarketDevice.anonId)
        await reload(token: token)
    }

    func toggle(store id: String) {
        let on = !stores.contains(id)
        if on { stores.insert(id) } else { stores.remove(id) }
        Task {
            do {
                if let token {
                    try await MarketAPI.setAccountFavorite(token: token, kind: "store", storeId: id, code: nil, on: on)
                } else {
                    try await MarketAPI.setDeviceStoreFavorite(storeId: id, anonId: MarketDevice.anonId, on: on)
                }
            } catch {
                if on { stores.remove(id) } else { stores.insert(id) }
            }
        }
    }

    func toggle(product code: String, store id: String) {
        let key = MarketAPI.favoriteKey(id, code)
        let on = !products.contains(key)
        if on { products.insert(key) } else { products.remove(key) }
        Task {
            do {
                if let token {
                    try await MarketAPI.setAccountFavorite(token: token, kind: "product", storeId: id, code: code, on: on)
                } else {
                    try await MarketAPI.setDeviceProductFavorite(storeId: id, code: code, anonId: MarketDevice.anonId, on: on)
                }
            } catch {
                if on { products.remove(key) } else { products.insert(key) }
            }
        }
    }
}

/// Corazón para marcar tiendas y productos.
struct HeartButton: View {
    let isOn: Bool
    var size: CGFloat = 32
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: isOn ? "heart.fill" : "heart")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundColor(isOn ? .red : .ink)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.92)))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isOn ? "Quitar de favoritos" : "Agregar a favoritos")
    }
}

private struct FavoritesText {
    let language: AppLanguage
    private func pick(_ es: String, _ en: String) -> String { language == .es ? es : en }

    var title: String { pick("Favoritos", "Favorites") }
    var stores: String { pick("Tiendas", "Stores") }
    var products: String { pick("Productos", "Products") }
    var emptyStores: String { pick("Aún no tienes tiendas favoritas. Toca el corazón en una tienda para guardarla.", "You have no favorite stores yet. Tap the heart on a store to save it.") }
    var emptyProducts: String { pick("Aún no tienes productos favoritos. Toca el corazón en un producto para guardarlo.", "You have no favorite products yet. Tap the heart on a product to save it.") }
    var signInHint: String { pick("Inicia sesión para ver tus favoritos en todos tus dispositivos.", "Sign in to see your favorites on all your devices.") }
    var signIn: String { pick("Iniciar sesión", "Sign in") }
    var loadError: String { pick("No pudimos cargar tus favoritos.", "We couldn't load your favorites.") }
    var retry: String { pick("Reintentar", "Try again") }
}

/// Pestaña Favoritos: tiendas y productos guardados.
struct FavoritesScreen: View {
    let language: AppLanguage

    private enum Mode { case stores, products }

    @EnvironmentObject private var favorites: MarketFavorites
    @EnvironmentObject private var session: MarketSession
    @EnvironmentObject private var nav: MarketNav
    @StateObject private var model = MarketSearchModel()
    @State private var mode = Mode.stores
    @State private var detail: ProductDetailItem?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let text = FavoritesText(language: language)
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    Text(text.stores).tag(Mode.stores)
                    Text(text.products).tag(Mode.products)
                }
                .pickerStyle(.segmented)
                .padding(16)
                content(text)
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle(text.title)
            .navigationDestination(for: MarketStore.self) { store in
                MarketStoreScreen(store: store, language: language, isOpen: model.openStates[store.storeId])
            }
        }
        .tint(.brandOrange)
        .task { await model.load() }
        .sheet(item: $detail) { item in
            ProductDetailSheet(product: item.product, store: item.store, language: language)
        }
    }

    @ViewBuilder
    private func content(_ text: FavoritesText) -> some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            VStack(spacing: 8) {
                Text(text.loadError).foregroundColor(.inkMuted)
                Button(text.retry) { Task { await model.load() } }.buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            ScrollView {
                VStack(spacing: 16) {
                    if !session.isSignedIn {
                        VStack(spacing: 10) {
                            Text(text.signInHint).font(.system(size: 14)).multilineTextAlignment(.center)
                            Button(text.signIn) { nav.tab = .account }
                                .buttonStyle(.bordered)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
                        .padding(.horizontal, 16)
                    }
                    if mode == .stores { storeList(text) } else { productGrid(text) }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private func storeList(_ text: FavoritesText) -> some View {
        let saved = model.stores.filter { favorites.isFavorite(store: $0.storeId) }
        return Group {
            if saved.isEmpty {
                empty(text.emptyStores, symbol: "heart")
            } else {
                VStack(spacing: 10) {
                    ForEach(saved) { store in
                        NavigationLink(value: store) {
                            StoreRow(store: store, isOpen: model.openStates[store.storeId], language: language)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func productGrid(_ text: FavoritesText) -> some View {
        let saved = model.products.filter { product in
            guard let storeId = product.storeId else { return false }
            return favorites.isFavorite(product: product.code, store: storeId)
        }
        return Group {
            if saved.isEmpty {
                empty(text.emptyProducts, symbol: "heart")
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(saved) { product in
                        if let store = model.stores.first(where: { $0.storeId == product.storeId }) {
                            ProductCard(product: product, store: store) {
                                detail = ProductDetailItem(product: product, store: store)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func empty(_ message: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 34)).foregroundColor(.inkMuted)
            Text(message).font(.system(size: 15)).foregroundColor(.inkMuted).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
