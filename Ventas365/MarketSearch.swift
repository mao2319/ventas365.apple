import SwiftUI

/// Textos del buscador y de "Los más buscados".
struct SearchText {
    let language: AppLanguage
    private func pick(_ es: String, _ en: String) -> String { language == .es ? es : en }

    var title: String { pick("Buscar", "Search") }
    var prompt: String { pick("Productos en todas las tiendas", "Products in all stores") }
    var popular: String { pick("Búsquedas populares", "Popular searches") }
    var recent: String { pick("Recientes", "Recent") }
    var clear: String { pick("Borrar", "Clear") }
    var trending: String { pick("Los más buscados", "Most searched") }
    var seeAll: String { pick("Ver todos", "See all") }
    var related: String { pick("Búsquedas relacionadas", "Related searches") }
    var noResults: String { pick("No encontramos productos con esa búsqueda.", "No products match your search.") }
    var loadError: String { pick("No pudimos completar la búsqueda.", "We couldn't complete the search.") }
    var retry: String { pick("Reintentar", "Try again") }
    var filters: String { pick("Filtros", "Filters") }
    var sort: String { pick("Ordenar", "Sort") }
    var relevance: String { pick("Relevancia", "Relevance") }
    var nameAsc: String { pick("Nombre A-Z", "Name A-Z") }
    var priceAsc: String { pick("Precio: menor a mayor", "Price: low to high") }
    var priceDesc: String { pick("Precio: mayor a menor", "Price: high to low") }
    var categories: String { pick("Categorías", "Categories") }
    var price: String { pick("Precio", "Price") }
    var min: String { pick("Mínimo", "Min") }
    var max: String { pick("Máximo", "Max") }
    var clearFilters: String { pick("Quitar filtros", "Clear filters") }
    var done: String { pick("Listo", "Done") }
    var uncategorized: String { pick("Sin categoría", "Uncategorized") }
    var searched: String { pick("búsquedas", "searches") }

    func summary(count: Int, stores: Int, query: String) -> String {
        if language == .es {
            return "\(count) resultado\(count == 1 ? "" : "s") para \"\(query)\" en \(stores) tienda\(stores == 1 ? "" : "s")"
        }
        return "\(count) result\(count == 1 ? "" : "s") for \"\(query)\" in \(stores) store\(stores == 1 ? "" : "s")"
    }
}

/// Búsquedas sugeridas (las mismas del sitio).
private let popularSearches = ["Pizza", "Café", "Mercado", "Postres", "Cerveza", "Pollo"]

enum SearchRoute: Hashable {
    case trending
}

private enum SearchSort: CaseIterable {
    case relevance, nameAsc, priceAsc, priceDesc
}

@MainActor
final class MarketSearchModel: ObservableObject {
    enum State {
        case loading
        case loaded
        case failed
    }

    @Published var state = State.loading
    @Published var stores: [MarketStore] = []
    @Published var openStates: [String: Bool] = [:]
    @Published var products: [MarketProduct] = []
    @Published var trending: [MostSearchedProduct] = []
    @Published var recents: [String] = []

    private static let recentsKey = "market-recent-searches"

    init() {
        recents = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
    }

    func load() async {
        if state == .loaded { return }
        state = .loading
        do {
            stores = try await MarketAPI.stores()
            products = try await MarketAPI.allProducts(storeIds: stores.map(\.storeId))
        } catch {
            state = .failed
            return
        }
        state = .loaded
        async let states = try? MarketAPI.openStates()
        async let top = try? MarketAPI.mostSearched(limit: 40)
        openStates = (await states) ?? [:]
        trending = (await top) ?? []
    }

    func remember(_ query: String) {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        recents.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        recents.insert(term, at: 0)
        recents = Array(recents.prefix(8))
        UserDefaults.standard.set(recents, forKey: Self.recentsKey)
    }

    func clearRecents() {
        recents = []
        UserDefaults.standard.removeObject(forKey: Self.recentsKey)
    }

    /// Productos que contienen todas las palabras escritas (sin tildes ni mayúsculas).
    func matches(_ query: String) -> [MarketProduct] {
        let words = MarketAPI.fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return products.filter { product in
            let haystack = MarketAPI.fold("\(product.code) \(product.description) \(product.brand ?? "")")
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}

/// Pestaña Buscar: búsqueda en todas las tiendas con filtros, orden, recientes,
/// búsquedas populares y los productos más buscados.
struct SearchScreen: View {
    let language: AppLanguage

    @StateObject private var model = MarketSearchModel()
    @State private var query = ""
    @State private var committed = ""
    @State private var sort = SearchSort.relevance
    @State private var selectedCategories = Set<String>()
    @State private var priceMin = ""
    @State private var priceMax = ""
    @State private var showFilters = false
    @State private var detail: ProductDetailItem?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let text = SearchText(language: language)
        NavigationStack {
            content(text)
                .background(Color.paper.ignoresSafeArea())
                .navigationTitle(text.title)
                .searchable(text: $query, prompt: text.prompt)
                .onSubmit(of: .search) { commit(query) }
                .navigationDestination(for: MarketStore.self) { store in
                    MarketStoreScreen(store: store, language: language, isOpen: model.openStates[store.storeId])
                }
                .navigationDestination(for: SearchRoute.self) { _ in
                    TrendingScreen(items: model.trending, stores: model.stores, language: language)
                }
        }
        .tint(.brandOrange)
        .task { await model.load() }
        .onChange(of: query) { newValue in
            // Al cambiar el texto se reinician los filtros de la búsqueda anterior.
            if MarketAPI.fold(newValue) != MarketAPI.fold(committed) {
                selectedCategories = []
                priceMin = ""
                priceMax = ""
            }
        }
        .sheet(item: $detail) { item in
            ProductDetailSheet(product: item.product, store: item.store, language: language)
        }
        .sheet(isPresented: $showFilters) {
            FiltersSheet(
                language: language,
                categories: categoryCounts(),
                selected: $selectedCategories,
                priceMin: $priceMin,
                priceMax: $priceMax
            )
        }
    }

    private func commit(_ term: String) {
        let clean = term.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        query = clean
        committed = clean
        model.remember(clean)
        let found = model.matches(clean)
        Task { await MarketAPI.recordSearchHits(found, query: clean) }
    }

    @ViewBuilder
    private func content(_ text: SearchText) -> some View {
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
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                suggestions(text)
            } else {
                results(text)
            }
        }
    }

    // MARK: Sugerencias

    private func suggestions(_ text: SearchText) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !model.recents.isEmpty {
                    HStack {
                        Text(text.recent).font(.system(size: 20, weight: .bold))
                        Spacer()
                        Button(text.clear) { model.clearRecents() }.font(.system(size: 15))
                    }
                    .padding(.horizontal, 16)
                    chips(model.recents)
                }
                Text(text.popular).font(.system(size: 20, weight: .bold)).padding(.horizontal, 16)
                chips(popularSearches)
                if !model.trending.isEmpty {
                    HStack {
                        Text(text.trending).font(.system(size: 20, weight: .bold))
                        Spacer()
                        NavigationLink(value: SearchRoute.trending) {
                            Text(text.seeAll).font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 16)
                    TrendingRail(items: Array(model.trending.prefix(12)), stores: model.stores, language: language) { item in
                        detail = item
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }

    private func chips(_ terms: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(terms, id: \.self) { term in
                    Button(term) { commit(term) }
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

    // MARK: Resultados

    private func baseMatches() -> [MarketProduct] {
        model.matches(query)
    }

    private func categoryCounts() -> [(name: String, count: Int)] {
        let counts = Dictionary(grouping: baseMatches()) { $0.categoryName }.mapValues(\.count)
        return counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var hasActiveFilters: Bool {
        !selectedCategories.isEmpty || Double(priceMin) != nil || Double(priceMax) != nil
    }

    private func filtered() -> [MarketProduct] {
        var list = baseMatches()
        if !selectedCategories.isEmpty { list = list.filter { selectedCategories.contains($0.categoryName) } }
        if let low = Double(priceMin) { list = list.filter { $0.unitPrice >= low } }
        if let high = Double(priceMax) { list = list.filter { $0.unitPrice <= high } }
        switch sort {
        case .relevance: break
        case .nameAsc: list.sort { $0.description.localizedCaseInsensitiveCompare($1.description) == .orderedAscending }
        case .priceAsc: list.sort { $0.unitPrice < $1.unitPrice }
        case .priceDesc: list.sort { $0.unitPrice > $1.unitPrice }
        }
        return list
    }

    private func label(_ sort: SearchSort, _ text: SearchText) -> String {
        switch sort {
        case .relevance: return text.relevance
        case .nameAsc: return text.nameAsc
        case .priceAsc: return text.priceAsc
        case .priceDesc: return text.priceDesc
        }
    }

    private func results(_ text: SearchText) -> some View {
        let list = filtered()
        let byStore = Dictionary(grouping: list) { $0.storeId ?? "" }
        let ordered = model.stores.filter { byStore[$0.storeId] != nil }
        // Con orden por precio o nombre la lista va plana; si no, agrupada por tienda.
        let flat = sort != .relevance
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if list.isEmpty {
                    Text(text.noResults).foregroundColor(.inkMuted).padding(32).frame(maxWidth: .infinity)
                } else {
                    Text(text.summary(count: list.count, stores: ordered.count, query: query.trimmingCharacters(in: .whitespaces)))
                        .font(.system(size: 14))
                        .foregroundColor(.inkMuted)
                        .padding(.horizontal, 16)
                }
                controls(text)
                if flat {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(list) { product in
                            if let store = model.stores.first(where: { $0.storeId == product.storeId }) {
                                ProductCard(product: product, store: store) {
                                    detail = ProductDetailItem(product: product, store: store)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    ForEach(ordered) { store in
                        VStack(alignment: .leading, spacing: 10) {
                            NavigationLink(value: store) {
                                HStack(spacing: 8) {
                                    RemoteImage(url: store.logoUrl)
                                        .frame(width: 28, height: 28)
                                        .clipShape(Circle())
                                    Text(store.displayName).font(.system(size: 18, weight: .bold))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.inkMuted)
                                    Spacer()
                                    if let isOpen = model.openStates[store.storeId] {
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
                Text(text.related).font(.system(size: 17, weight: .bold)).padding(.horizontal, 16).padding(.top, 8)
                chips(popularSearches.filter { $0.caseInsensitiveCompare(query) != .orderedSame })
            }
            .padding(.vertical, 12)
        }
    }

    private func controls(_ text: SearchText) -> some View {
        HStack(spacing: 10) {
            Button { showFilters = true } label: {
                Label(text.filters, systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.bordered)
            Menu {
                Picker(text.sort, selection: $sort) {
                    ForEach(SearchSort.allCases, id: \.self) { Text(label($0, text)).tag($0) }
                }
            } label: {
                Label(label(sort, text), systemImage: "arrow.up.arrow.down")
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .font(.system(size: 14, weight: .semibold))
        .padding(.horizontal, 16)
    }
}

// MARK: - Filtros

private struct FiltersSheet: View {
    let language: AppLanguage
    let categories: [(name: String, count: Int)]
    @Binding var selected: Set<String>
    @Binding var priceMin: String
    @Binding var priceMax: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let text = SearchText(language: language)
        NavigationStack {
            Form {
                Section(text.categories) {
                    ForEach(categories, id: \.name) { entry in
                        Button {
                            if selected.contains(entry.name) { selected.remove(entry.name) } else { selected.insert(entry.name) }
                        } label: {
                            HStack {
                                Text(entry.name.isEmpty ? text.uncategorized : entry.name).foregroundColor(.ink)
                                Spacer()
                                Text("\(entry.count)").foregroundColor(.inkMuted)
                                if selected.contains(entry.name) {
                                    Image(systemName: "checkmark").foregroundColor(.brandOrange)
                                }
                            }
                        }
                    }
                }
                Section(text.price) {
                    TextField(text.min, text: $priceMin).keyboardType(.decimalPad)
                    TextField(text.max, text: $priceMax).keyboardType(.decimalPad)
                }
                Section {
                    Button(text.clearFilters, role: .destructive) {
                        selected = []
                        priceMin = ""
                        priceMax = ""
                    }
                }
            }
            .navigationTitle(text.filters)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(text.done) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Los más buscados

/// Fila horizontal de los productos más buscados.
struct TrendingRail: View {
    let items: [MostSearchedProduct]
    let stores: [MarketStore]
    let language: AppLanguage
    let onOpen: (ProductDetailItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(items) { item in
                    if let store = stores.first(where: { $0.storeId == item.storeId }) {
                        Button { onOpen(ProductDetailItem(product: item.asProduct, store: store)) } label: {
                            TrendingCard(item: item, currency: store.currencyCode)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

private struct TrendingCard: View {
    let item: MostSearchedProduct
    let currency: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: item.imageUrl)
                .frame(width: 140, height: 110)
                .clipped()
            Text(item.description)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(width: 120, height: 36, alignment: .topLeading)
                .padding(.horizontal, 10)
            Text(Money.format(item.unitPrice, currency: currency))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.ink)
                .padding(.horizontal, 10)
            Text(item.storeName.capitalized)
                .font(.system(size: 12))
                .foregroundColor(.inkMuted)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .frame(width: 140)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Lista completa de los más buscados.
struct TrendingScreen: View {
    let items: [MostSearchedProduct]
    let stores: [MarketStore]
    let language: AppLanguage

    @State private var detail: ProductDetailItem?
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let text = SearchText(language: language)
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { item in
                    if let store = stores.first(where: { $0.storeId == item.storeId }) {
                        ProductCard(product: item.asProduct, store: store) {
                            detail = ProductDetailItem(product: item.asProduct, store: store)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle(text.trending)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { item in
            ProductDetailSheet(product: item.product, store: item.store, language: language)
        }
    }
}
