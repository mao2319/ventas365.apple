import Foundation

/// Cómo recibe el cliente su pedido.
enum OrderType: String, CaseIterable, Identifiable {
    case pickup = "llevar"
    case delivery = "domicilio"

    var id: String { rawValue }
}

/// Formas de pago que puede pedir el cliente (las mismas del sitio). El pago
/// no se hace en la app: la tienda cobra al entregar o al recibir el comprobante.
enum PaymentMethodKind: String, CaseIterable, Identifiable {
    case cash = "EFECTIVO"
    case creditCard = "TARJETA_CREDITO"
    case debitCard = "TARJETA_DEBITO"
    case nequi = "NEQUI"
    case daviplata = "DAVIPLATA"
    case llave = "LLAVE_BREB"

    var id: String { rawValue }

    /// Nequi, Daviplata y Llave Bre-B solo existen en Colombia y la tienda
    /// debe haberlos configurado.
    var isQr: Bool { self == .nequi || self == .daviplata || self == .llave }

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .cash: return language == .es ? "Efectivo" : "Cash"
        case .creditCard: return language == .es ? "Tarjeta de crédito" : "Credit card"
        case .debitCard: return language == .es ? "Tarjeta débito" : "Debit card"
        case .nequi: return "Nequi"
        case .daviplata: return "Daviplata"
        case .llave: return "Llave Bre-B"
        }
    }

    /// Los medios que ofrece una tienda.
    static func available(countryIso: String?, enabledQr: Set<String>) -> [PaymentMethodKind] {
        let isColombia = (countryIso ?? "CO") == "CO"
        return allCases.filter { !$0.isQr || (isColombia && enabledQr.contains($0.rawValue)) }
    }
}

/// Dirección guardada en la cuenta del cliente.
struct SavedAddress: Decodable, Identifiable, Hashable {
    let id: String
    let label: String
    let address: String
    let city: String
    let department: String
    let isDefault: Bool
}

struct PlaceOrderRequest: Encodable {
    struct Line: Encodable {
        let code: String
        let quantity: Int
    }

    let token: String
    let storeId: String
    let items: [Line]
    let orderType: String
    let requestedPaymentMethod: String
    var city: String?
    var address: String?
    var addressComplement: String?
    var receiverName: String?
    var receiverDocumentNumber: String?
    var receiverPhone: String?
}

struct PlacedItem: Decodable, Hashable {
    let code: String
    let description: String
    let unitPrice: Double
    let quantity: Int
    let imageUrl: String?
}

struct PlacedOrder: Decodable, Hashable {
    let id: String
    let orderNumber: Int?
    let savedAt: String
    let orderType: String
    let requestedPaymentMethod: String
    let total: Double
    let items: [PlacedItem]

    /// "#0007".
    var numberLabel: String {
        guard let orderNumber else { return "" }
        return "#" + String(format: "%04d", orderNumber)
    }
}

struct PlaceOrderResponse: Decodable {
    let success: Bool?
    let error: String?
    let code: String?
    let order: PlacedOrder?
}

// MARK: - Mis pedidos

struct PurchaseItem: Decodable, Hashable {
    let code: String?
    let description: String
    let unitPrice: Double
    let quantity: Int
    let imageUrl: String?
}

struct PurchaseCourier: Decodable, Hashable {
    let name: String?
    let phone: String?
    let vehicle: String?
}

struct PurchaseDelivery: Decodable, Hashable {
    let status: String?
    let deliveredAt: String?
    let courierName: String?
    let courierPhone: String?
}

/// Pedido o compra del cliente (respuesta de `market-customer-purchases`).
struct CustomerPurchase: Decodable, Identifiable, Hashable {
    let kind: String
    let id: String
    let storeId: String
    let storeName: String
    let storeLogoUrl: String?
    let date: String
    let orderNumber: Int?
    let orderType: String?
    let paymentMethod: String?
    let total: Double
    let items: [PurchaseItem]
    let acceptedAt: String?
    let preparingAt: String?
    let readyAt: String?
    let courier: PurchaseCourier?
    let delivery: PurchaseDelivery?

    var numberLabel: String {
        guard let orderNumber else { return "" }
        return "#" + String(format: "%04d", orderNumber)
    }

    /// Pedido aún pendiente de entrega o de que la tienda lo facture.
    var isActive: Bool {
        if kind == "pedido" { return true }
        guard let status = delivery?.status else { return false }
        return status != "entregado" && status != "cancelado"
    }

    enum Stage { case sent, accepted, preparing, ready, onTheWay, delivered, completed }

    var stage: Stage {
        if kind == "venta" {
            return delivery?.status == "entregado" ? .delivered : .completed
        }
        if courier != nil { return .onTheWay }
        if readyAt != nil { return .ready }
        if preparingAt != nil { return .preparing }
        if acceptedAt != nil { return .accepted }
        return .sent
    }
}

struct PurchasesResponse: Decodable {
    let success: Bool?
    let purchases: [CustomerPurchase]?
    let error: String?
}

/// Fecha ISO del servidor en formato corto y local.
enum OrderDate {
    private static let parser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainParser = ISO8601DateFormatter()

    static func short(_ iso: String, language: AppLanguage) -> String {
        guard let date = parser.date(from: iso) ?? plainParser.date(from: iso) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .es ? "es_CO" : "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
