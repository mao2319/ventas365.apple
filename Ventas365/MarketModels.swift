import Foundation

struct MarketStore: Identifiable, Decodable, Hashable {
    let storeId: String
    let name: String
    let logoUrl: String?
    let coverUrl: String?
    let department: String?
    let city: String?
    let address: String?
    let phoneNumber: String?
    let currencyCode: String?
    let deliveryTimeMin: Int?
    let deliveryTimeMax: Int?
    let deliveryCost: Double?
    let minimumOrder: Double?

    var id: String { storeId }

    /// "Bogotá" o "Bogotá, Cundinamarca".
    var place: String {
        [city, department].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// El nombre se guarda en mayúsculas: se muestra como título.
    var displayName: String { name.capitalized }
}

struct MarketProduct: Identifiable, Decodable, Hashable {
    let code: String
    let description: String
    let unitPrice: Double
    let compareAtPrice: Double?
    let stock: Int?
    let imageUrl: String?
    let category: String?
    let brand: String?
    /// Solo viene en las consultas entre varias tiendas.
    var storeId: String? = nil

    var id: String { storeId.map { "\($0)-\(code)" } ?? code }

    var categoryName: String {
        let name = (category ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "" : name.capitalized
    }

    /// Porcentaje de descuento si tiene precio de comparación mayor.
    var discountPercent: Int? {
        guard let compare = compareAtPrice, compare > unitPrice, compare > 0 else { return nil }
        return Int(((compare - unitPrice) / compare * 100).rounded())
    }
}

enum Money {
    /// Precio en la moneda de la tienda, sin decimales (COP, CLP…) o con dos.
    static func format(_ value: Double, currency: String?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = (currency?.isEmpty == false) ? currency : "COP"
        formatter.locale = Locale(identifier: "es_CO")
        let whole = value.rounded() == value
        formatter.maximumFractionDigits = whole ? 0 : 2
        formatter.minimumFractionDigits = whole ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

struct MarketCategory: Identifiable, Hashable {
    let name: String
    let storeCount: Int
    let imageUrl: String?

    var id: String { name }
    var displayName: String { name.capitalized }
}

struct MarketRating: Hashable {
    let average: Double
    let count: Int
}

/// Fila de "Los más buscados" (respuesta de `top_searched_products`).
struct MostSearchedProduct: Decodable, Identifiable, Hashable {
    let storeId: String
    let productCode: String
    let description: String
    let unitPrice: Double
    let compareAtPrice: Double?
    let imageUrl: String?
    let storeName: String
    let searchCount: Int

    var id: String { "\(storeId)-\(productCode)" }

    /// Como producto de catálogo, para reutilizar tarjetas y detalle.
    var asProduct: MarketProduct {
        MarketProduct(code: productCode, description: description, unitPrice: unitPrice, compareAtPrice: compareAtPrice,
                      stock: nil, imageUrl: imageUrl, category: nil, brand: nil, storeId: storeId)
    }
}
