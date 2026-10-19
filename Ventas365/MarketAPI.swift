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

    static func get<T: Decodable>(_ table: String, _ items: [URLQueryItem]) async throws -> T {
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

    private static let storeColumns = "store_id,name,logo_url,cover_url,department,city,address,phone_number,country_iso,currency_code,delivery_time_min,delivery_time_max,delivery_cost,minimum_order,latitude,longitude,phone_country_iso,instagram_handle,instagram_url,address_for_map,business_hours"

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

    // MARK: - Favoritos

    /// Llamada genérica a PostgREST para escrituras (favoritos del dispositivo).
    @discardableResult
    private static func rest(_ method: String, _ table: String, _ items: [URLQueryItem], body: Data? = nil, prefer: String? = nil) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = items.isEmpty ? nil : items
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        request.httpBody = body
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badResponse
        }
        return data
    }

    struct FavoriteSnapshot {
        var stores: Set<String> = []
        var products: Set<String> = []
    }

    static func favoriteKey(_ storeId: String, _ code: String) -> String { "\(storeId)|\(code)" }

    private struct FavStoreRow: Decodable { let storeId: String }
    private struct FavProductRow: Decodable { let storeId: String; let productCode: String }

    /// Favoritos de quien no ha iniciado sesión: se guardan con el id del dispositivo.
    static func deviceFavorites(anonId: String) async throws -> FavoriteSnapshot {
        async let storeRows: [FavStoreRow] = get("store_favorites", [
            URLQueryItem(name: "select", value: "store_id"),
            URLQueryItem(name: "anon_id", value: "eq.\(anonId)"),
        ])
        async let productRows: [FavProductRow] = get("product_favorites", [
            URLQueryItem(name: "select", value: "store_id,product_code"),
            URLQueryItem(name: "anon_id", value: "eq.\(anonId)"),
        ])
        let stores = try await storeRows
        let products = try await productRows
        return FavoriteSnapshot(
            stores: Set(stores.map(\.storeId)),
            products: Set(products.map { favoriteKey($0.storeId, $0.productCode) })
        )
    }

    private struct DeviceStoreFavorite: Encodable {
        let storeId: String
        let anonId: String
        enum CodingKeys: String, CodingKey { case storeId = "store_id", anonId = "anon_id" }
    }

    private struct DeviceProductFavorite: Encodable {
        let storeId: String
        let productCode: String
        let anonId: String
        enum CodingKeys: String, CodingKey { case storeId = "store_id", productCode = "product_code", anonId = "anon_id" }
    }

    static func setDeviceStoreFavorite(storeId: String, anonId: String, on: Bool) async throws {
        if on {
            let body = try JSONEncoder().encode(DeviceStoreFavorite(storeId: storeId, anonId: anonId))
            try await rest("POST", "store_favorites", [URLQueryItem(name: "on_conflict", value: "store_id,anon_id")], body: body, prefer: "resolution=ignore-duplicates,return=minimal")
        } else {
            try await rest("DELETE", "store_favorites", [
                URLQueryItem(name: "store_id", value: "eq.\(storeId)"),
                URLQueryItem(name: "anon_id", value: "eq.\(anonId)"),
            ])
        }
    }

    static func setDeviceProductFavorite(storeId: String, code: String, anonId: String, on: Bool) async throws {
        if on {
            let body = try JSONEncoder().encode(DeviceProductFavorite(storeId: storeId, productCode: code, anonId: anonId))
            try await rest("POST", "product_favorites", [URLQueryItem(name: "on_conflict", value: "store_id,product_code,anon_id")], body: body, prefer: "resolution=ignore-duplicates,return=minimal")
        } else {
            try await rest("DELETE", "product_favorites", [
                URLQueryItem(name: "store_id", value: "eq.\(storeId)"),
                URLQueryItem(name: "product_code", value: "eq.\(code)"),
                URLQueryItem(name: "anon_id", value: "eq.\(anonId)"),
            ])
        }
    }

    private struct FavoritesRequest: Encodable {
        let action: String
        let token: String
        var kind: String?
        var storeId: String?
        var productCode: String?
        var on: Bool?
        var anonId: String?
    }

    private struct FavoritesResponse: Decodable {
        struct Product: Decodable { let storeId: String; let productCode: String }
        let success: Bool?
        let stores: [String]?
        let products: [Product]?
    }

    /// Favoritos de la cuenta (función `market-favorites`).
    static func accountFavorites(token: String) async throws -> FavoriteSnapshot {
        let response: FavoritesResponse = try await invoke("market-favorites", FavoritesRequest(action: "list", token: token))
        guard response.success == true else { throw APIError.badResponse }
        return FavoriteSnapshot(
            stores: Set(response.stores ?? []),
            products: Set((response.products ?? []).map { favoriteKey($0.storeId, $0.productCode) })
        )
    }

    static func setAccountFavorite(token: String, kind: String, storeId: String, code: String?, on: Bool) async throws {
        let response: FavoritesResponse = try await invoke(
            "market-favorites",
            FavoritesRequest(action: "toggle", token: token, kind: kind, storeId: storeId, productCode: code, on: on)
        )
        guard response.success == true else { throw APIError.badResponse }
    }

    /// Pasa los favoritos que el dispositivo tenía sin sesión a la cuenta.
    static func mergeDeviceFavorites(token: String, anonId: String) async {
        let _: FavoritesResponse? = try? await invoke("market-favorites", FavoritesRequest(action: "merge", token: token, anonId: anonId))
    }

    private struct TopFavoriteRow: Decodable {
        let storeId: String
        let productCode: String
        let description: String
        let unitPrice: Double
        let compareAtPrice: Double?
        let imageUrl: String?
        let storeName: String
        let favoriteCount: Int
    }

    /// Productos con más favoritos entre todos los clientes.
    static func topFavorites(limit: Int) async throws -> [MostSearchedProduct] {
        let rows: [TopFavoriteRow] = try await rpc("top_favorite_products", LimitBody(limitCount: limit))
        return rows.map {
            MostSearchedProduct(storeId: $0.storeId, productCode: $0.productCode, description: $0.description,
                                unitPrice: $0.unitPrice, compareAtPrice: $0.compareAtPrice, imageUrl: $0.imageUrl,
                                storeName: $0.storeName, searchCount: $0.favoriteCount)
        }
    }

    // MARK: - Ficha de la tienda

    struct StoreDeliveryApp: Decodable, Identifiable, Hashable {
        let id: String
        let platform: String
        let url: String

        var name: String {
            let key = platform.lowercased()
            if key.contains("rappi") { return "Rappi" }
            if key.contains("didi") { return "DiDi Food" }
            if key.contains("pedidos") { return "PedidosYa" }
            if key.contains("ifood") { return "iFood" }
            if key.contains("uber") { return "Uber Eats" }
            return platform.capitalized
        }
    }

    /// Enlaces de la tienda en apps de domicilio.
    static func deliveryApps(storeId: String) async throws -> [StoreDeliveryApp] {
        try await get("store_delivery_apps", [
            URLQueryItem(name: "select", value: "id,platform,url"),
            URLQueryItem(name: "store_id", value: "eq.\(storeId)"),
            URLQueryItem(name: "order", value: "created_at"),
        ])
    }

    /// Medio de pago digital configurado por la tienda (número o llave, y QR).
    struct StorePaymentInfo: Decodable, Identifiable, Hashable {
        let method: String
        let accountLabel: String?
        let qrImageUrl: String?
        let enabled: Bool

        var id: String { method }
    }

    static func paymentInfo(storeId: String) async throws -> [StorePaymentInfo] {
        let rows: [StorePaymentInfo] = try await get("store_payment_methods", [
            URLQueryItem(name: "select", value: "method,account_label,qr_image_url,enabled"),
            URLQueryItem(name: "store_id", value: "eq.\(storeId)"),
        ])
        return rows.filter { $0.enabled && !((($0.accountLabel ?? "").isEmpty) && (($0.qrImageUrl ?? "").isEmpty)) }
    }

    // MARK: - Calificaciones

    struct PublicRating: Decodable, Identifiable, Hashable {
        let id: String
        let rating: Int
        let comment: String?
        let createdAt: String
        let firstName: String
    }

    private struct StoreIdBody: Encodable { let storeId: String }
    private struct PublicRatingsResponse: Decodable { let ratings: [PublicRating]? }

    static func publicRatings(storeId: String) async throws -> [PublicRating] {
        let response: PublicRatingsResponse = try await invoke("list-public-store-ratings", StoreIdBody(storeId: storeId))
        return response.ratings ?? []
    }

    private struct RateBody: Encodable { let token: String; let storeId: String; let rating: Int; let comment: String }
    struct SimpleResponse: Decodable { let success: Bool?; let error: String? }

    /// Envía o actualiza la calificación del cliente; la tienda la revisa antes de publicarla.
    static func submitRating(token: String, storeId: String, rating: Int, comment: String) async throws -> SimpleResponse {
        try await invoke("submit-store-rating", RateBody(token: token, storeId: storeId, rating: rating, comment: comment))
    }

    // MARK: - Perfil y comprobantes del cliente

    private struct ProfileBody: Encodable {
        let token: String
        let alternatePhoneCountryIso: String?
        let alternatePhone: String?
        let avatarUrl: String?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(token, forKey: .token)
            try container.encode(alternatePhoneCountryIso, forKey: .alternatePhoneCountryIso)
            try container.encode(alternatePhone, forKey: .alternatePhone)
            try container.encode(avatarUrl, forKey: .avatarUrl)
        }

        enum CodingKeys: String, CodingKey { case token, alternatePhoneCountryIso, alternatePhone, avatarUrl }
    }

    struct ProfileResponse: Decodable {
        let success: Bool?
        let error: String?
        let customer: MarketCustomer?
    }

    /// Guarda foto y celular alternativo (los datos principales los cambia soporte).
    static func updateProfile(token: String, alternatePhoneCountryIso: String?, alternatePhone: String?, avatarUrl: String?) async throws -> ProfileResponse {
        try await invoke("market-customer-update-profile", ProfileBody(
            token: token, alternatePhoneCountryIso: alternatePhoneCountryIso, alternatePhone: alternatePhone, avatarUrl: avatarUrl
        ))
    }

    /// Sube la foto de perfil al almacenamiento público y devuelve su URL.
    static func uploadAvatar(customerId: String, jpeg: Data) async throws -> String {
        let path = "\(customerId)/avatar-\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        var request = URLRequest(url: baseURL.appendingPathComponent("storage/v1/object/market-customer-avatars/\(path)"))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("3600", forHTTPHeaderField: "Cache-Control")
        request.httpBody = jpeg
        request.timeoutInterval = 60
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badResponse
        }
        return baseURL.appendingPathComponent("storage/v1/object/public/market-customer-avatars/\(path)").absoluteString
    }

    private struct ProofsRequest: Encodable { let action: String; let token: String }
    struct ProofsResponse: Decodable { let success: Bool?; let proofs: [PaymentProof]? }

    static func paymentProofs(token: String) async throws -> [PaymentProof] {
        let response: ProofsResponse = try await invoke("payment-proofs", ProofsRequest(action: "mine", token: token))
        guard response.success == true else { throw APIError.badResponse }
        return response.proofs ?? []
    }

    /// Marca como leídas las respuestas de las tiendas a los comprobantes.
    static func markProofsSeen(token: String) async {
        let _: SimpleResponse? = try? await invoke("payment-proofs", ProofsRequest(action: "seen", token: token))
    }

    // MARK: - Seguimiento: chat con el domiciliario, calificación y comprobantes

    struct ChatMessage: Decodable, Identifiable, Hashable {
        let id: String
        let sender: String
        let senderName: String?
        let body: String?
        let imageUrl: String?
        let isProof: Bool?
        let createdAt: String
    }

    struct ChatResponse: Decodable {
        let success: Bool?
        let error: String?
        let status: String?
        let messages: [ChatMessage]?
    }

    private struct ChatImage: Encodable { let data: String; let contentType: String }
    private struct ChatRequest: Encodable {
        let action: String
        let role = "customer"
        let token: String
        let deliveryId: String
        var body: String?
        var image: ChatImage?
        var stars: Int?
        var comment: String?
    }

    static func deliveryChat(token: String, deliveryId: String) async throws -> ChatResponse {
        try await invoke("delivery-chat", ChatRequest(action: "list", token: token, deliveryId: deliveryId))
    }

    static func sendDeliveryMessage(token: String, deliveryId: String, body: String, jpeg: Data?) async throws -> ChatResponse {
        var request = ChatRequest(action: "send", token: token, deliveryId: deliveryId)
        request.body = body
        if let jpeg { request.image = ChatImage(data: jpeg.base64EncodedString(), contentType: "image/jpeg") }
        return try await invoke("delivery-chat", request)
    }

    static func rateDelivery(token: String, deliveryId: String, stars: Int, comment: String) async throws -> ChatResponse {
        var request = ChatRequest(action: "rate", token: token, deliveryId: deliveryId)
        request.stars = stars
        request.comment = comment
        return try await invoke("delivery-chat", request)
    }

    /// Envía el comprobante de un pago por Nequi, Daviplata o Llave Bre-B (multipart).
    static func submitProof(token: String, storeId: String, method: String, orderKind: String, orderRef: String,
                            amount: Double?, note: String, jpeg: Data) async throws -> SimpleResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("token", token)
        field("storeId", storeId)
        field("method", method)
        field("orderKind", orderKind)
        field("orderRef", orderRef)
        if let amount { field("amount", String(Int(amount.rounded()))) }
        if !note.isEmpty { field("note", note) }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"comprobante.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: baseURL.appendingPathComponent("functions/v1/payment-proofs"))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 60
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let decoded = try? decoder.decode(SimpleResponse.self, from: data) else { throw APIError.badResponse }
        return decoded
    }
}
