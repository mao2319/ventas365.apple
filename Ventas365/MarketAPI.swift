import Foundation

/// Lectura pública del Market (tiendas y productos) directo desde Supabase,
/// igual que el sitio: la clave publicable es pública por diseño y las
/// políticas de la base de datos limitan lo que se puede leer.
enum MarketAPI {
    private static let baseURL = URL(string: "https://pcutoqboolsopzqvdiqe.supabase.co")!
    private static let publishableKey = "sb_publishable_DXo6m_HKi14P7xP5J_aU1A__WwI0au2"

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    enum APIError: Error { case badResponse }

    private static func get<T: Decodable>(_ table: String, _ items: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badResponse
        }
        return try decoder.decode(T.self, from: data)
    }

    /// Llama a una función de Supabase (`/functions/v1/<nombre>`) con cuerpo
    /// JSON. Las funciones del Market responden 200 con `success: false` en los
    /// errores esperados; un 4xx/5xx con cuerpo legible también se decodifica.
    static func invoke<Body: Encodable, Response: Decodable>(_ function: String, _ body: Body) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent("functions/v1/\(function)"))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard response is HTTPURLResponse else { throw APIError.badResponse }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.badResponse
        }
    }

    private static let storeColumns = "store_id,name,logo_url,cover_url,department,city,address,phone_number,country_iso,currency_code,delivery_time_min,delivery_time_max,delivery_cost,minimum_order,latitude,longitude"

    /// Una tienda del Market por su id.
    static func store(storeId: String) async throws -> MarketStore? {
        let rows: [MarketStore] = try await get("stores", [
            URLQueryItem(name: "select", value: storeColumns),
            URLQueryItem(name: "store_id", value: "eq.\(storeId)"),
            URLQueryItem(name: "market_enabled", value: "eq.true"),
        ])
        return rows.first
    }

    /// Tiendas visibles en el Market (con ciudad y visibilidad activada).
    static func stores() async throws -> [MarketStore] {
        try await get("stores", [
            URLQueryItem(name: "select", value: storeColumns),
            URLQueryItem(name: "city", value: "not.is.null"),
            URLQueryItem(name: "city", value: "neq."),
            URLQueryItem(name: "market_enabled", value: "eq.true"),
            URLQueryItem(name: "order", value: "name"),
        ])
    }

    /// Productos que se pueden comprar: con stock o sin control de stock.
    static func products(storeId: String) async throws -> [MarketProduct] {
        try await get("products", [
            URLQueryItem(name: "select", value: "code,description,unit_price,compare_at_price,stock,image_url,category,brand"),
            URLQueryItem(name: "store_id", value: "eq.\(storeId)"),
            URLQueryItem(name: "or", value: "(stock.is.null,stock.gt.0)"),
            URLQueryItem(name: "order", value: "category"),
            URLQueryItem(name: "order", value: "description"),
        ])
    }

    // MARK: - Estado de las tiendas, categorías y calificaciones

    private struct Empty: Encodable {}
    private struct OpenRow: Decodable { let storeId: String; let isOpen: Bool }

    private static func rpc<Response: Decodable>(_ name: String) async throws -> Response {
        try await rpc(name, Empty())
    }

    private static func rpc<Body: Encodable, Response: Decodable>(_ name: String, _ body: Body) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/rpc/\(name)"))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badResponse
        }
        return try decoder.decode(Response.self, from: data)
    }

    /// Tiendas abiertas ahora (según su horario), por id de tienda.
    static func openStates() async throws -> [String: Bool] {
        let rows: [OpenRow] = try await rpc("market_store_open_states")
        return Dictionary(rows.map { ($0.storeId, $0.isOpen) }, uniquingKeysWith: { _, last in last })
    }

    private struct CategoryRow: Decodable { let category: String?; let storeId: String }
    private struct NamedImage: Decodable { let name: String; let imageUrl: String? }
    private struct GlobalImage: Decodable { let categoryName: String; let imageUrl: String? }

    private static func inList(_ ids: [String]) -> String { "in.(\(ids.joined(separator: ",")))" }

    /// Categorías con productos disponibles, las más comunes entre tiendas primero.
    static func categories(storeIds: [String]) async throws -> [MarketCategory] {
        guard !storeIds.isEmpty else { return [] }
        async let rowsTask: [CategoryRow] = get("products", [
            URLQueryItem(name: "select", value: "category,store_id"),
            URLQueryItem(name: "store_id", value: inList(storeIds)),
            URLQueryItem(name: "or", value: "(stock.is.null,stock.gt.0)"),
        ])
        async let storeImagesTask: [NamedImage] = get("categories", [
            URLQueryItem(name: "select", value: "name,image_url"),
            URLQueryItem(name: "store_id", value: inList(storeIds)),
            URLQueryItem(name: "image_url", value: "not.is.null"),
        ])
        async let globalImagesTask: [GlobalImage] = get("global_category_images", [
            URLQueryItem(name: "select", value: "category_name,image_url"),
        ])
        let rows = try await rowsTask
        // Las imágenes son un adorno: si fallan, las categorías se muestran igual.
        let storeImages = (try? await storeImagesTask) ?? []
        let globalImages = (try? await globalImagesTask) ?? []

        var images: [String: String] = [:]
        // Los SVG embebidos (data:) no se pueden mostrar como imagen remota.
        for entry in storeImages {
            if let url = entry.imageUrl, !url.hasPrefix("data:"), images[fold(entry.name)] == nil { images[fold(entry.name)] = url }
        }
        for entry in globalImages {
            if let url = entry.imageUrl, !url.hasPrefix("data:"), images[fold(entry.categoryName)] == nil { images[fold(entry.categoryName)] = url }
        }

        var storesByCategory: [String: Set<String>] = [:]
        for row in rows {
            let name = (row.category ?? "").trimmingCharacters(in: .whitespaces)
            if name.isEmpty { continue }
            storesByCategory[name, default: []].insert(row.storeId)
        }
        return storesByCategory
            .map { MarketCategory(name: $0.key, storeCount: $0.value.count, imageUrl: images[fold($0.key)]) }
            .sorted { a, b in
                a.storeCount != b.storeCount
                    ? a.storeCount > b.storeCount
                    : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    /// Texto sin tildes ni mayúsculas, para comparar nombres.
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
    }

    /// Productos disponibles de una categoría en todas las tiendas dadas.
    static func products(storeIds: [String], category: String) async throws -> [MarketProduct] {
        guard !storeIds.isEmpty else { return [] }
        let escaped = category.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
        return try await get("products", [
            URLQueryItem(name: "select", value: "code,description,unit_price,compare_at_price,stock,image_url,category,brand,store_id"),
            URLQueryItem(name: "store_id", value: inList(storeIds)),
            URLQueryItem(name: "category", value: "ilike.\(escaped)"),
            URLQueryItem(name: "or", value: "(stock.is.null,stock.gt.0)"),
            URLQueryItem(name: "order", value: "description"),
        ])
    }

    private struct RatingRow: Decodable { let rating: Int }

    /// Promedio y cantidad de calificaciones publicadas de una tienda.
    static func ratingSummary(storeId: String) async throws -> MarketRating {
        let rows: [RatingRow] = try await get("store_ratings", [
            URLQueryItem(name: "select", value: "rating"),
            URLQueryItem(name: "store_id", value: "eq.\(storeId)"),
            URLQueryItem(name: "published", value: "eq.true"),
        ])
        guard !rows.isEmpty else { return MarketRating(average: 0, count: 0) }
        return MarketRating(average: Double(rows.reduce(0) { $0 + $1.rating }) / Double(rows.count), count: rows.count)
    }

    // MARK: - Búsqueda y más buscados

    /// Todos los productos disponibles de las tiendas dadas (el buscador los
    /// filtra en el teléfono, igual que el sitio).
    static func allProducts(storeIds: [String]) async throws -> [MarketProduct] {
        guard !storeIds.isEmpty else { return [] }
        return try await get("products", [
            URLQueryItem(name: "select", value: "code,description,unit_price,compare_at_price,stock,image_url,category,brand,store_id"),
            URLQueryItem(name: "store_id", value: inList(storeIds)),
            URLQueryItem(name: "or", value: "(stock.is.null,stock.gt.0)"),
            URLQueryItem(name: "order", value: "description"),
        ])
    }

    private struct LimitBody: Encodable {
        let limitCount: Int
        enum CodingKeys: String, CodingKey { case limitCount = "limit_count" }
    }

    /// Productos con más coincidencias de búsqueda entre todas las tiendas.
    static func mostSearched(limit: Int) async throws -> [MostSearchedProduct] {
        try await rpc("top_searched_products", LimitBody(limitCount: limit))
    }

    private struct SearchHit: Encodable {
        let storeId: String
        let productCode: String
        let query: String
        enum CodingKeys: String, CodingKey {
            case storeId = "store_id"
            case productCode = "product_code"
            case query
        }
    }

    /// Suma una coincidencia por producto encontrado (alimenta "Más buscados").
    /// No bloquea nada: si falla, se ignora.
    static func recordSearchHits(_ products: [MarketProduct], query: String) async {
        let rows = products.compactMap { product -> SearchHit? in
            guard let storeId = product.storeId else { return nil }
            return SearchHit(storeId: storeId, productCode: product.code, query: query)
        }
        guard !rows.isEmpty else { return }
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/product_search_hits"))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONEncoder().encode(rows)
        request.timeoutInterval = 20
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Pedido

    /// Medios QR que la tienda tiene configurados y activos.
    static func enabledQrMethods(storeId: String) async throws -> Set<String> {
        struct Row: Decodable { let method: String; let accountLabel: String?; let qrImageUrl: String?; let enabled: Bool }
        let rows: [Row] = try await get("store_payment_methods", [
            URLQueryItem(name: "select", value: "method,account_label,qr_image_url,enabled"),
            URLQueryItem(name: "store_id", value: "eq.\(storeId)"),
        ])
        return Set(rows.filter { $0.enabled && !(($0.accountLabel ?? "").isEmpty && ($0.qrImageUrl ?? "").isEmpty) }.map(\.method))
    }

    /// Genera el pedido en el servidor (función `market-place-order`).
    static func placeOrder(_ request: PlaceOrderRequest) async throws -> PlaceOrderResponse {
        try await invoke("market-place-order", request)
    }

    private struct AddressRequest: Encodable {
        let action: String
        let token: String
        var label: String?
        var address: String?
        var city: String?
        var department: String?
        var isDefault: Bool?
    }

    private struct AddressesResponse: Decodable {
        let success: Bool?
        let addresses: [SavedAddress]?
    }

    /// Direcciones guardadas del cliente. Si el servicio no responde, lista vacía.
    static func addresses(token: String) async -> [SavedAddress] {
        let response: AddressesResponse? = try? await invoke("market-customer-addresses", AddressRequest(action: "list", token: token))
        return response?.addresses ?? []
    }

    /// Guarda una dirección nueva en la cuenta (no bloquea el pedido si falla).
    static func saveAddress(token: String, label: String, address: String, city: String, department: String) async {
        let body = AddressRequest(action: "save", token: token, label: label, address: address, city: city, department: department, isDefault: false)
        let _: AddressesResponse? = try? await invoke("market-customer-addresses", body)
    }

    private struct TokenBody: Encodable { let token: String }

    /// Pedidos y compras del cliente en todas las tiendas.
    static func purchases(token: String) async throws -> [CustomerPurchase] {
        let response: PurchasesResponse = try await invoke("market-customer-purchases", TokenBody(token: token))
        guard response.success == true else { throw APIError.badResponse }
        return response.purchases ?? []
    }
}
