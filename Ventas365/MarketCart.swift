import Foundation

/// Renglón del carrito de una tienda (mismos datos que `SaleItem` del sitio).
struct CartLine: Codable, Identifiable, Hashable {
    let code: String
    let description: String
    let unitPrice: Double
    var quantity: Int
    let imageUrl: String?
    let stock: Int?

    var id: String { code }
    var subtotal: Double { unitPrice * Double(quantity) }
}

/// Carrito de una tienda: el Market arma un pedido por tienda.
struct StoreCart: Codable, Identifiable, Hashable {
    let storeId: String
    let storeName: String
    let currency: String?
    var lines: [CartLine]

    var id: String { storeId }
    var itemCount: Int { lines.reduce(0) { $0 + $1.quantity } }
    var total: Double { lines.reduce(0) { $0 + $1.subtotal } }
}

/// Carritos del Market en el dispositivo, un pedido por tienda. Se guardan
/// localmente (como en el sitio) para retomarlos al volver a abrir la app.
@MainActor
final class MarketCart: ObservableObject {
    @Published private(set) var carts: [StoreCart] = []

    private static let storageKey = "market-carts"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([StoreCart].self, from: data) {
            carts = saved
        }
    }

    var itemCount: Int { carts.reduce(0) { $0 + $1.itemCount } }

    func quantity(storeId: String, code: String) -> Int {
        carts.first { $0.storeId == storeId }?.lines.first { $0.code == code }?.quantity ?? 0
    }

    func add(_ product: MarketProduct, from store: MarketStore) {
        set(quantity(storeId: store.storeId, code: product.code) + 1, product: product, store: store)
    }

    func remove(_ product: MarketProduct, from store: MarketStore) {
        set(quantity(storeId: store.storeId, code: product.code) - 1, product: product, store: store)
    }

    /// Cambia la cantidad de un renglón del carrito (desde la pestaña Carrito).
    func setQuantity(_ quantity: Int, storeId: String, code: String) {
        guard let cartIndex = carts.firstIndex(where: { $0.storeId == storeId }),
              let lineIndex = carts[cartIndex].lines.firstIndex(where: { $0.code == code }) else { return }
        var amount = max(0, quantity)
        if let stock = carts[cartIndex].lines[lineIndex].stock { amount = min(amount, stock) }
        if amount == 0 {
            carts[cartIndex].lines.remove(at: lineIndex)
            if carts[cartIndex].lines.isEmpty { carts.remove(at: cartIndex) }
        } else {
            carts[cartIndex].lines[lineIndex].quantity = amount
        }
        save()
    }

    func clear(storeId: String) {
        carts.removeAll { $0.storeId == storeId }
        save()
    }

    private func set(_ quantity: Int, product: MarketProduct, store: MarketStore) {
        var amount = max(0, quantity)
        if let stock = product.stock { amount = min(amount, stock) }
        let line = CartLine(
            code: product.code,
            description: product.description,
            unitPrice: product.unitPrice,
            quantity: amount,
            imageUrl: product.imageUrl,
            stock: product.stock
        )
        if let cartIndex = carts.firstIndex(where: { $0.storeId == store.storeId }) {
            if let lineIndex = carts[cartIndex].lines.firstIndex(where: { $0.code == product.code }) {
                if amount == 0 {
                    carts[cartIndex].lines.remove(at: lineIndex)
                } else {
                    carts[cartIndex].lines[lineIndex].quantity = amount
                }
            } else if amount > 0 {
                carts[cartIndex].lines.append(line)
            }
            if carts[cartIndex].lines.isEmpty { carts.remove(at: cartIndex) }
        } else if amount > 0 {
            carts.append(StoreCart(storeId: store.storeId, storeName: store.displayName, currency: store.currencyCode, lines: [line]))
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(carts) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

/// Id anónimo del dispositivo: con él se guardan los favoritos de quien aún
/// no inició sesión (igual que `getOrCreateAnonId` del sitio).
enum MarketDevice {
    private static let key = "market-anon-id"

    static var anonId: String {
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}
