import SwiftUI

/// Textos del Market nativo (la app solo trae español e inglés).
private struct MarketText {
    let language: AppLanguage
    private func pick(_ es: String, _ en: String) -> String { language == .es ? es : en }

    var title: String { "Market" }
    var searchPrompt: String { pick("Busca tiendas", "Search stores") }
    var storesHeader: String { pick("Tiendas cerca de ti", "Stores near you") }
    var empty: String { pick("No encontramos tiendas con esa búsqueda.", "No stores match your search.") }
    var errorTitle: String { pick("No pudimos cargar las tiendas", "We couldn't load the stores") }
    var errorBody: String { pick("Revisa tu conexión e inténtalo de nuevo.", "Check your connection and try again.") }
    var retry: String { pick("Reintentar", "Try again") }
    var appHome: String { pick("Inicio de la app", "App home") }
    var productsError: String { pick("No pudimos cargar los productos.", "We couldn't load the products.") }
    var noProducts: String { pick("Esta tienda aún no tiene productos disponibles.", "This store has no products available yet.") }
    var order: String { pick("Pedir en esta tienda", "Order from this store") }
    var delivery: String { pick("Domicilio", "Delivery") }
    var freeDelivery: String { pick("Domicilio gratis", "Free delivery") }
    var minimum: String { pick("Pedido mínimo", "Minimum order") }
    var minutes: String { "min" }
    var others: String { pick("Otros", "Other") }
}

@MainActor
final class MarketStoresModel: ObservableObject {
    enum State {
        case loading
        case loaded([MarketStore])
        case failed
    }

    @Published var state = State.loading

    func load() async {
        if case .loaded = state { return }
        state = .loading
        do {
            state = .loaded(try await MarketAPI.stores())
        } catch {
            state = .failed
        }
    }

    func reload() async {
        state = .loading
        await load()
    }
}

/// Market nativo: reemplaza al sitio dentro de la app. Lista de tiendas con
/// búsqueda y, al tocar una, su catálogo. Por ahora el pedido y el pago se
/// completan en el sitio (onOpenWeb).
struct MarketScreen: View {
    let language: AppLanguage
    let onExit: () -> Void
    let onOpenWeb: (String) -> Void

    @StateObject private var model = MarketStoresModel()
    @State private var query = ""

    var body: some View {
        let text = MarketText(language: language)
        NavigationStack {
            content(text)
                .background(Color.paper.ignoresSafeArea())
                .navigationTitle(text.title)
                .navigationBarTitleDisplayMode(.large)
                .searchable(text: $query, prompt: text.searchPrompt)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: onExit) { Image(systemName: "house") }
                            .accessibilityLabel(text.appHome)
                    }
                }
                .navigationDestination(for: MarketStore.self) { store in
                    MarketStoreScreen(store: store, language: language, onOrder: {
                        onOpenWeb("/tiendas/\(store.storeId)")
                    })
                }
        }
        .tint(.brandOrange)
        .task { await model.load() }
    }

    @ViewBuilder
    private func content(_ text: MarketText) -> some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            VStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 34))
                    .foregroundColor(.inkMuted)
                Text(text.errorTitle).font(.headline)
                Text(text.errorBody).font(.subheadline).foregroundColor(.inkMuted)
                Button(text.retry) { Task { await model.reload() } }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandOrange)
                    .padding(.top, 8)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let stores):
            let shown = filter(stores)
            if shown.isEmpty {
                Text(text.empty)
                    .foregroundColor(.inkMuted)
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section(text.storesHeader) {
                        ForEach(shown) { store in
                            NavigationLink(value: store) { StoreRow(store: store) }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await model.reload() }
            }
        }
    }

    private func filter(_ stores: [MarketStore]) -> [MarketStore] {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return stores }
        return stores.filter {
            $0.name.localizedCaseInsensitiveContains(term) || $0.place.localizedCaseInsensitiveContains(term)
        }
    }
}

struct RemoteImage: View {
    let url: String?

    var body: some View {
        if let url, let parsed = URL(string: url) {
            AsyncImage(url: parsed) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color.gray.opacity(0.12)
                }
            }
        } else {
            Color.gray.opacity(0.12)
        }
    }
}

private struct StoreRow: View {
    let store: MarketStore

    var body: some View {
        HStack(spacing: 14) {
            RemoteImage(url: store.logoUrl)
                .frame(width: 52, height: 52)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(store.displayName).font(.system(size: 17, weight: .semibold))
                if !store.place.isEmpty {
                    Text(store.place).font(.system(size: 14)).foregroundColor(.inkMuted)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

@MainActor
final class MarketProductsModel: ObservableObject {
    enum State {
        case loading
        case loaded([MarketProduct])
        case failed
    }

    @Published var state = State.loading

    func load(storeId: String) async {
        state = .loading
        do {
            state = .loaded(try await MarketAPI.products(storeId: storeId))
        } catch {
            state = .failed
        }
    }
}

/// Catálogo de una tienda: portada, datos de domicilio y productos por categoría.
struct MarketStoreScreen: View {
    let store: MarketStore
    let language: AppLanguage
    let onOrder: () -> Void

    @StateObject private var model = MarketProductsModel()

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let text = MarketText(language: language)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(text)
                products(text)
            }
            .padding(.bottom, 96)
        }
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle(store.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(action: onOrder) {
                Text(text.order)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandOrange)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
        .task { await model.load(storeId: store.storeId) }
    }

    @ViewBuilder
    private func products(_ text: MarketText) -> some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
        case .failed:
            VStack(spacing: 8) {
                Text(text.productsError).foregroundColor(.inkMuted)
                Button(text.retry) { Task { await model.load(storeId: store.storeId) } }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        case .loaded(let items):
            if items.isEmpty {
                Text(text.noProducts)
                    .foregroundColor(.inkMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                catalog(items, text)
            }
        }
    }

    private func header(_ text: MarketText) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RemoteImage(url: store.coverUrl)
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipped()
            HStack(spacing: 14) {
                RemoteImage(url: store.logoUrl)
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.displayName).font(.system(size: 22, weight: .bold))
                    if !store.place.isEmpty {
                        Text(store.place).font(.system(size: 14)).foregroundColor(.inkMuted)
                    }
                }
            }
            .padding(.horizontal, 16)
            let facts = deliveryFacts(text)
            if !facts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(facts, id: \.self) { fact in
                            Text(fact)
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.white))
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func deliveryFacts(_ text: MarketText) -> [String] {
        var facts: [String] = []
        if let low = store.deliveryTimeMin, let high = store.deliveryTimeMax {
            facts.append("\(low)–\(high) \(text.minutes)")
        }
        if let cost = store.deliveryCost {
            facts.append(cost == 0 ? text.freeDelivery : "\(text.delivery) \(Money.format(cost, currency: store.currencyCode))")
        }
        if let minimum = store.minimumOrder, minimum > 0 {
            facts.append("\(text.minimum) \(Money.format(minimum, currency: store.currencyCode))")
        }
        return facts
    }

    private func catalog(_ items: [MarketProduct], _ text: MarketText) -> some View {
        let groups = Dictionary(grouping: items) { $0.categoryName }
        let names = groups.keys.sorted { a, b in
            if a.isEmpty != b.isEmpty { return !a.isEmpty }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
        return VStack(alignment: .leading, spacing: 20) {
            ForEach(names, id: \.self) { name in
                VStack(alignment: .leading, spacing: 10) {
                    Text(name.isEmpty ? text.others : name)
                        .font(.system(size: 20, weight: .bold))
                        .padding(.horizontal, 16)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(groups[name] ?? []) { product in
                            ProductCard(product: product, store: store)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.top, 8)
    }
}

private struct ProductCard: View {
    let product: MarketProduct
    let store: MarketStore
    @EnvironmentObject private var cart: MarketCart

    private var currency: String? { store.currencyCode }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                RemoteImage(url: product.imageUrl)
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipped()
                if let discount = product.discountPercent {
                    Text("-\(discount)%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.red))
                        .padding(8)
                }
            }
            Text(product.description)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
                .frame(minHeight: 36, alignment: .topLeading)
                .padding(.horizontal, 10)
            VStack(alignment: .leading, spacing: 0) {
                if let compare = product.compareAtPrice, compare > product.unitPrice {
                    Text(Money.format(compare, currency: currency))
                        .font(.system(size: 12))
                        .strikethrough()
                        .foregroundColor(.inkMuted)
                }
                Text(Money.format(product.unitPrice, currency: currency))
                    .font(.system(size: 16, weight: .bold))
            }
            .padding(.horizontal, 10)
            cartControl
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// "Agregar" o, si ya está en el carrito, el control de cantidad.
    @ViewBuilder
    private var cartControl: some View {
        let quantity = cart.quantity(storeId: store.storeId, code: product.code)
        if quantity == 0 {
            Button { cart.add(product, from: store) } label: {
                Image(systemName: "plus").frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .tint(.brandOrange)
        } else {
            QuantityStepper(quantity: quantity) { next in
                if next > quantity { cart.add(product, from: store) } else { cart.remove(product, from: store) }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
