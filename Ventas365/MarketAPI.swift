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

    /// Tiendas visibles en el Market (con ciudad y visibilidad activada).
    static func stores() async throws -> [MarketStore] {
        try await get("stores", [
            URLQueryItem(name: "select", value: "store_id,name,logo_url,cover_url,department,city,address,phone_number,currency_code,delivery_time_min,delivery_time_max,delivery_cost,minimum_order"),
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
}
