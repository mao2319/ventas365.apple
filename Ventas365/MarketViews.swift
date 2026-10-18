import SwiftUI

/// Textos del Market nativo (la app solo trae español e inglés).
private struct MarketText {
    let language: AppLanguage
    private func pick(_ es: String, _ en: String) -> String { language == .es ? es : en }

    var title: String { "Market" }
    var stores: String { pick("Comercios", "Stores") }
    var categories: String { pick("Categorías", "Categories") }
    var seeAll: String { pick("Ver todos", "See all") }
    var seeAllFeminine: String { pick("Ver todas", "See all") }
    var searchStores: String { pick("Busca tiendas", "Search stores") }
    var searchProducts: String { pick("Busca en esta tienda", "Search this store") }
    var empty: String { pick("No encontramos tiendas con esa búsqueda.", "No stores match your search.") }
    var noCategories: String { pick("Todavía no hay categorías disponibles.", "No categories available yet.") }
    var errorTitle: String { pick("No pudimos cargar las tiendas", "We couldn't load the stores") }
    var errorBody: String { pick("Revisa tu conexión e inténtalo de nuevo.", "Check your connection and try again.") }
    var retry: String { pick("Reintentar", "Try again") }
    var appHome: String { pick("Inicio de la app", "App home") }
    var productsError: String { pick("No pudimos cargar los productos.", "We couldn't load the products.") }
    var noProducts: String { pick("Esta tienda aún no tiene productos disponibles.", "This store has no products available yet.") }
    var noMatches: String { pick("No hay productos con esa búsqueda.", "No products match your search.") }
    var delivery: String { pick("Domicilio", "Delivery") }
    var freeDelivery: String { pick("Domicilio gratis", "Free delivery") }
    var minimum: String { pick("Pedido mínimo", "Minimum order") }
    var minutes: String { "min" }
    var others: String { pick("Otros", "Other") }
    var open: String { pick("Abierto", "Open") }
    var closed: String { pick("Cerrado", "Closed") }
    var viewCart: String { pick("Ver carrito", "View cart") }
    var close: String { pick("Cerrar", "Close") }
    var inStock: String { pick("disponibles", "in stock") }

    func rating(_ average: Double, _ count: Int) -> String {
        String(format: "★ %.1f (%d)", average, count)
    }
}

/// Destinos de "Ver todos" del inicio.
enum MarketRoute: Hashable {
    case allStores
    case allCategories
}

@MainActor
final class MarketHomeModel: ObservableObject {
    enum State {
        case loading
        case loaded
        case failed
    }

    @Published var state = State.loading
    @Published var stores: [MarketStore] = []
    @Published var categories: [MarketCategory] = []
    @Published var openStates: [String: Bool] = [:]

    func load() async {
        if state == .loaded { return }
        state = .loading
        do {
            stores = try await MarketAPI.stores()
        } catch {
            state = .failed
            return
        }
        state = .loaded
        let ids = stores.map(\.storeId)
        async let loadedCategories = try? MarketAPI.categories(storeIds: ids)
        async let loadedStates = try? MarketAPI.openStates()
        categories = (await loadedCategories) ?? []
        openStates = (await loadedStates) ?? [:]
    }

    func reload() async {
        state = .loading
        await load()
    }
}

/// Inicio del Market nativo: categorías y comercios en filas, con "Ver todos".
/// El pedido y el pago se completan en el sitio por ahora (onOpenWeb).
struct MarketScreen: View {
    let language: AppLanguage
    let onExit: () -> Void
    let onOpenWeb: (String) -> Void

    @StateObject private var model = MarketHomeModel()

    var body: some View {
        let text = MarketText(language: language)
        NavigationStack {
            content(text)
                .background(Color.paper.ignoresSafeArea())
                .navigationTitle(text.title)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: onExit) { Image(systemName: "house") }
                            .accessibilityLabel(text.appHome)
                    }
                }
                .navigationDestination(for: MarketStore.self) { store in
                    MarketStoreScreen(store: store, language: language, isOpen: model.openStates[store.storeId])
                }
                .navigationDestination(for: MarketCategory.self) { category in
                    CategoryResultsScreen(category: category, stores: model.stores, openStates: model.openStates, language: language)
                }
                .navigationDestination(for: MarketRoute.self) { route in
                    switch route {
                    case .allStores:
                        StoresListScreen(stores: model.stores, openStates: model.openStates, language: language)
                    case .allCategories:
                        CategoriesGridScreen(categories: model.categories, language: language)
                    }
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
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !model.categories.isEmpty {
                        railHeader(text.categories, action: text.seeAllFeminine, route: .allCategories)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 14) {
                                ForEach(model.categories.prefix(14)) { category in
                                    NavigationLink(value: category) { CategoryTile(category: category) }
                                        .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.top, -12)
                    }
                    railHeader(text.stores, action: text.seeAll, route: .allStores)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(model.stores) { store in
                                NavigationLink(value: store) {
                                    StoreCard(store: store, isOpen: model.openStates[store.storeId], language: language)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, -12)
                }
                .padding(.vertical, 8)
            }
            .refreshable { await model.reload() }
        }
    }

    private func railHeader(_ title: String, action: String, route: MarketRoute) -> some View {
        HStack {
            Text(title).font(.system(size: 22, weight: .bold))
            Spacer()
            NavigationLink(value: route) {
                Text(action).font(.system(size: 15, weight: .semibold))
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Piezas compartidas

struct RemoteImage: View {
    let url: String?

    var body: some View {
        // Los SVG embebidos (data:) no se pueden mostrar como imagen remota.
        if let url, !url.hasPrefix("data:"), let parsed = URL(string: url) {
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

private struct OpenBadge: View {
    let isOpen: Bool
    let language: AppLanguage

    var body: some View {
        let text = MarketText(language: language)
        Text(isOpen ? text.open : text.closed)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(isOpen ? Color.brandGreen : Color.inkMuted))
    }
}

private struct StoreCard: View {
    let store: MarketStore
    let isOpen: Bool?
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                RemoteImage(url: store.coverUrl)
                    .frame(width: 240, height: 110)
                    .clipped()
                if let isOpen {
                    OpenBadge(isOpen: isOpen, language: language).padding(8)
                }
            }
            HStack(spacing: 10) {
                RemoteImage(url: store.logoUrl)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.displayName).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    if !store.place.isEmpty {
                        Text(store.place).font(.system(size: 13)).foregroundColor(.inkMuted).lineLimit(1)
                    }
                }
            }
            .padding(10)
        }
        .frame(width: 240)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct StoreRow: View {
    let store: MarketStore
    let isOpen: Bool?
    let language: AppLanguage

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
            Spacer()
            if let isOpen { OpenBadge(isOpen: isOpen, language: language) }
        }
        .padding(.vertical, 4)
    }
}

private struct CategoryTile: View {
    let category: MarketCategory

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(Color.gray.opacity(0.14))
                if category.imageUrl != nil {
                    RemoteImage(url: category.imageUrl).clipShape(Circle())
                } else {
                    Text(String(category.displayName.prefix(1)))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.inkMuted)
                }
            }
            .frame(width: 68, height: 68)
            .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 1))
            Text(category.displayName)
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 80)
        }
    }
}

// MARK: - Ver todos

private struct StoresListScreen: View {
    let stores: [MarketStore]
    let openStates: [String: Bool]
    let language: AppLanguage

    @State private var query = ""

    var body: some View {
        let text = MarketText(language: language)
        let term = query.trimmingCharacters(in: .whitespaces)
        let shown = term.isEmpty ? stores : stores.filter {
            $0.name.localizedCaseInsensitiveContains(term) || $0.place.localizedCaseInsensitiveContains(term)
        }
        Group {
            if shown.isEmpty {
                Text(text.empty)
                    .foregroundColor(.inkMuted)
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(shown) { store in
                        NavigationLink(value: store) {
                            StoreRow(store: store, isOpen: openStates[store.storeId], language: language)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle(text.stores)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: text.searchStores)
    }
}

private struct CategoriesGridScreen: View {
    let categories: [MarketCategory]
    let language: AppLanguage

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 16, alignment: .top)]

    var body: some View {
        let text = MarketText(language: language)
        ScrollView {
            if categories.isEmpty {
                Text(text.noCategories).foregroundColor(.inkMuted).padding(32)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(categories) { category in
                        NavigationLink(value: category) { CategoryTile(category: category) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle(text.categories)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Productos de una categoría (en todas las tiendas)

@MainActor
private final class CategoryResultsModel: ObservableObject {
    enum State {
        case loading
        case loaded([MarketProduct])
        case failed
    }

    @Published var state = State.loading

    func load(category: String, storeIds: [String]) async {
        state = .loading
        do {
            state = .loaded(try await MarketAPI.products(storeIds: storeIds, category: category))
        } catch {
            state = .failed
        }
    }
}

private struct CategoryResultsScreen: View {
    let category: MarketCategory
    let stores: [MarketStore]
    let openStates: [String: Bool]
    let language: AppLanguage

    @StateObject private var model = CategoryResultsModel()
    @State private var detail: ProductDetailItem?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let text = MarketText(language: language)
        ScrollView {
            switch model.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
            case .failed:
                VStack(spacing: 8) {
                    Text(text.productsError).foregroundColor(.inkMuted)
                    Button(text.retry) { Task { await load() } }.buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            case .loaded(let products):
                if products.isEmpty {
                    Text(text.noProducts).foregroundColor(.inkMuted).padding(32)
                } else {
                    results(products)
                }
            }
        }
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $detail) { item in
            ProductDetailSheet(product: item.product, store: item.store, language: language)
        }
    }

    private func load() async {
        await model.load(category: category.name, storeIds: stores.map(\.storeId))
    }

    private func results(_ products: [MarketProduct]) -> some View {
        let byStore = Dictionary(grouping: products) { $0.storeId ?? "" }
        let ordered = stores.filter { byStore[$0.storeId] != nil }
        return VStack(alignment: .leading, spacing: 22) {
            ForEach(ordered) { store in
                VStack(alignment: .leading, spacing: 10) {
                    NavigationLink(value: store) {
                        HStack(spacing: 8) {
                            RemoteImage(url: store.logoUrl)
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())
                            Text(store.displayName).font(.system(size: 18, weight: .bold))
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(.inkMuted)
                            Spacer()
                            if let isOpen = openStates[store.storeId] {
                                OpenBadge(isOpen: isOpen, language: language)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(byStore[store.storeId] ?? []) { product in
                            ProductCard(product: product, store: store) {
                                detail = ProductDetailItem(product: product, store: store)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Tienda

@MainActor
final class MarketProductsModel: ObservableObject {
    enum State {
        case loading
        case loaded([MarketProduct])
        case failed
    }

    @Published var state = State.loading
    @Published var rating: MarketRating?

    func load(storeId: String) async {
        state = .loading
        do {
            state = .loaded(try await MarketAPI.products(storeId: storeId))
        } catch {
            state = .failed
        }
        rating = try? await MarketAPI.ratingSummary(storeId: storeId)
    }
}

struct ProductDetailItem: Identifiable {
    let product: MarketProduct
    let store: MarketStore
    var id: String { "\(store.storeId)-\(product.code)" }
}

/// Catálogo de una tienda: portada, datos de entrega, calificación, buscador
/// propio, barra de categorías y productos con detalle.
struct MarketStoreScreen: View {
    let store: MarketStore
    let language: AppLanguage
    let isOpen: Bool?

    @StateObject private var model = MarketProductsModel()
    @EnvironmentObject private var cart: MarketCart
    @EnvironmentObject private var nav: MarketNav
    @State private var query = ""
    @State private var detail: ProductDetailItem?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let text = MarketText(language: language)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(text)
                    products(text, proxy: proxy)
                }
                .padding(.bottom, 96)
            }
        }
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle(store.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: text.searchProducts)
        .safeAreaInset(edge: .bottom) { cartBar(text) }
        .task { await model.load(storeId: store.storeId) }
        .sheet(item: $detail) { item in
            ProductDetailSheet(product: item.product, store: item.store, language: language)
        }
    }

    @ViewBuilder
    private func cartBar(_ text: MarketText) -> some View {
        if let storeCart = cart.carts.first(where: { $0.storeId == store.storeId }) {
            Button { nav.tab = .cart } label: {
                HStack {
                    Text("\(text.viewCart) · \(storeCart.itemCount)")
                    Spacer()
                    Text(Money.format(storeCart.total, currency: store.currencyCode))
                }
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandOrange)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
    }

    @ViewBuilder
    private func products(_ text: MarketText, proxy: ScrollViewProxy) -> some View {
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
                let term = MarketAPI.fold(query)
                if term.isEmpty {
                    catalog(items, text, proxy: proxy)
                } else {
                    let found = items.filter {
                        MarketAPI.fold($0.description).contains(term) || MarketAPI.fold($0.brand ?? "").contains(term)
                    }
                    if found.isEmpty {
                        Text(text.noMatches)
                            .foregroundColor(.inkMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        grid(found).padding(.top, 8)
                    }
                }
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
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.displayName).font(.system(size: 22, weight: .bold))
                    if !store.place.isEmpty {
                        Text(store.place).font(.system(size: 14)).foregroundColor(.inkMuted)
                    }
                    HStack(spacing: 8) {
                        if let isOpen { OpenBadge(isOpen: isOpen, language: language) }
                        if let rating = model.rating, rating.count > 0 {
                            Text(text.rating(rating.average, rating.count))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.inkMuted)
                        }
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

    private func grid(_ items: [MarketProduct]) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(items) { product in
                ProductCard(product: product, store: store) {
                    detail = ProductDetailItem(product: product, store: store)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func catalog(_ items: [MarketProduct], _ text: MarketText, proxy: ScrollViewProxy) -> some View {
        let groups = Dictionary(grouping: items) { $0.categoryName }
        let names = groups.keys.sorted { a, b in
            if a.isEmpty != b.isEmpty { return !a.isEmpty }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
        return VStack(alignment: .leading, spacing: 20) {
            if names.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(names, id: \.self) { name in
                            Button(name.isEmpty ? text.others : name) {
                                withAnimation { proxy.scrollTo(name, anchor: .top) }
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.white))
                            .foregroundColor(.ink)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            ForEach(names, id: \.self) { name in
                VStack(alignment: .leading, spacing: 10) {
                    Text(name.isEmpty ? text.others : name)
                        .font(.system(size: 20, weight: .bold))
                        .padding(.horizontal, 16)
                        .id(name)
                    grid(groups[name] ?? [])
                }
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Producto

struct ProductCard: View {
    let product: MarketProduct
    let store: MarketStore
    let onOpen: () -> Void

    private var currency: String? { store.currencyCode }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onOpen) {
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
                        .foregroundColor(.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .frame(minHeight: 36, alignment: .topLeading)
                        .padding(.horizontal, 10)
                    PriceLabel(product: product, currency: currency)
                        .padding(.horizontal, 10)
                }
            }
            .buttonStyle(.plain)
            CartControl(product: product, store: store)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct PriceLabel: View {
    let product: MarketProduct
    let currency: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let compare = product.compareAtPrice, compare > product.unitPrice {
                Text(Money.format(compare, currency: currency))
                    .font(.system(size: 12))
                    .strikethrough()
                    .foregroundColor(.inkMuted)
            }
            Text(Money.format(product.unitPrice, currency: currency))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.ink)
        }
    }
}

/// "Agregar" o, si ya está en el carrito, el control de cantidad.
struct CartControl: View {
    let product: MarketProduct
    let store: MarketStore

    @EnvironmentObject private var cart: MarketCart

    var body: some View {
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

/// Detalle de un producto en una hoja inferior.
struct ProductDetailSheet: View {
    let product: MarketProduct
    let store: MarketStore
    let language: AppLanguage

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let text = MarketText(language: language)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer()
                    Button(text.close) { dismiss() }.font(.system(size: 16, weight: .semibold))
                }
                RemoteImage(url: product.imageUrl)
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                if let brand = product.brand, !brand.isEmpty {
                    Text(brand.capitalized).font(.system(size: 13, weight: .semibold)).foregroundColor(.inkMuted)
                }
                Text(product.description).font(.system(size: 22, weight: .bold))
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Money.format(product.unitPrice, currency: store.currencyCode))
                        .font(.system(size: 26, weight: .bold))
                    if let compare = product.compareAtPrice, compare > product.unitPrice {
                        Text(Money.format(compare, currency: store.currencyCode))
                            .strikethrough()
                            .foregroundColor(.inkMuted)
                    }
                    if let discount = product.discountPercent {
                        Text("-\(discount)%").font(.system(size: 14, weight: .bold)).foregroundColor(.red)
                    }
                }
                if let stock = product.stock {
                    Text("\(stock) \(text.inStock)").font(.system(size: 14)).foregroundColor(.inkMuted)
                }
                Text(store.displayName).font(.system(size: 14, weight: .medium)).foregroundColor(.inkMuted)
                CartControl(product: product, store: store)
                    .padding(.top, 6)
            }
            .padding(20)
        }
        .background(Color.paper.ignoresSafeArea())
    }
}
