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

struct PlacedCustomer: Decodable, Hashable {
    let fullName: String?
    let documentNumber: String?
    let phone: String?
    let email: String?
}

struct PlacedDelivery: Decodable, Hashable {
    let city: String?
    let address: String?
    let addressComplement: String?
}

struct PlacedReceiver: Decodable, Hashable {
    let name: String?
    let documentNumber: String?
    let phone: String?
}

struct PlacedOrder: Decodable, Hashable {
    let id: String
    let orderNumber: Int?
    let savedAt: String
    let orderType: String
    let requestedPaymentMethod: String
    let total: Double
    let items: [PlacedItem]
    /// Datos del cliente y de la entrega (los devuelve `market-place-order`).
    var customer: PlacedCustomer? = nil
    var delivery: PlacedDelivery? = nil
    var receiver: PlacedReceiver? = nil

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

struct GeoPoint: Decodable, Hashable {
    let lat: Double
    let lng: Double
    let at: String?
}

/// Dirección de entrega (para la ruta del mapa en vivo).
struct DeliveryDestination: Decodable, Hashable {
    let address: String
    let city: String?

    var query: String { [address, city ?? ""].filter { !$0.isEmpty }.joined(separator: ", ") }
}

struct DeliveryRating: Decodable, Hashable {
    let stars: Int
    let comment: String?
}

struct PurchaseDelivery: Decodable, Hashable {
    let id: String?
    let status: String?
    let deliveredAt: String?
    let courierName: String?
    let courierPhone: String?
    let vehicle: String?
    let dispatchedAt: String?
    let pickedUpAt: String?
    let courierLocation: GeoPoint?
    let proofNote: String?
    let rating: DeliveryRating?
    var destination: DeliveryDestination? = nil
    /// Mensajes que el domiciliario (o la tienda) escribió en el chat.
    var courierMessages: Int? = nil
    /// Código que el cliente le dicta al domiciliario al recibir (solo en camino).
    var deliveryCode: String? = nil
    /// La lleva un domiciliario del Market (no uno de la tienda).
    var marketCourier: Bool? = nil
}

/// Cancelación que pidió el cliente (ver `market-order-cancellations`).
/// `solicitada`: la tienda la está revisando · `cancelado` · `rechazada`.
struct PurchaseCancellation: Decodable, Hashable {
    let id: String
    let status: String
    let reason: String
    let stage: String?
    let requestedAt: String?
    let resolvedAt: String?
    let storeNote: String?
    let seen: Bool?

    var isPending: Bool { status == "solicitada" }
    var isCancelled: Bool { status == "cancelado" }
    var isRejected: Bool { status == "rechazada" }
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
    let storeLocation: GeoPoint?
    let delivery: PurchaseDelivery?
    var cancellation: PurchaseCancellation? = nil
    /// Pedido aún sin facturar con domiciliario del Market: su última posición.
    var courierLocation: GeoPoint? = nil
    var destination: DeliveryDestination? = nil

    /// Posición del domiciliario y a dónde va, venga de la entrega o del pedido.
    var liveCourier: GeoPoint? { delivery?.courierLocation ?? courierLocation }
    var liveDestination: DeliveryDestination? { delivery?.destination ?? destination }

    var numberLabel: String {
        guard let orderNumber else { return "" }
        return "#" + String(format: "%04d", orderNumber)
    }

    /// Pedido aún pendiente de entrega o de que la tienda lo facture.
    var isActive: Bool {
        if kind == "cancelado" { return false }
        if kind == "pedido" { return true }
        guard let status = delivery?.status else { return false }
        return status != "entregado" && status != "cancelado"
    }

    /// Entregado por un domiciliario y aún sin calificar (hasta 3 días después):
    /// sigue en "Órdenes en progreso" para que el cliente califique el servicio.
    var awaitsRating: Bool {
        guard kind == "venta", let delivery, delivery.status == "entregado", delivery.rating == nil,
              delivery.courierName != nil else { return false }
        guard let iso = delivery.deliveredAt, let date = OrderDate.parse(iso) else { return true }
        return Date().timeIntervalSince(date) < 3 * 24 * 60 * 60
    }

    enum Stage { case sent, accepted, preparing, ready, onTheWay, delivered, completed, cancelled }

    var stage: Stage {
        if kind == "cancelado" || cancellation?.isCancelled == true { return .cancelled }
        if kind == "venta" {
            return delivery?.status == "entregado" ? .delivered : .completed
        }
        // Que un domiciliario tome el pedido no lo pone en camino: la tienda lo
        // sigue preparando y él va a recogerlo (ver `courierHeadingToStore`).
        if readyAt != nil { return .ready }
        if preparingAt != nil { return .preparing }
        if acceptedAt != nil { return .accepted }
        return .sent
    }
}

extension CustomerPurchase {
    /// Se puede cancelar mientras siga en curso y no haya una solicitud abierta.
    var canCancel: Bool {
        guard isActive, cancellation?.isPending != true else { return false }
        if kind == "pedido" { return true }
        guard kind == "venta", let status = delivery?.status else { return false }
        return ["pendiente", "en_preparacion", "listo", "en_camino", "novedad"].contains(status)
    }

    /// Recién enviado: la tienda aún no lo acepta, así que se cancela de una vez.
    /// Después, el cliente solo puede pedirle a la tienda que lo cancele.
    var cancelsImmediately: Bool { kind == "pedido" && stage == .sent }
}

struct CancelOrderResponse: Decodable {
    let success: Bool?
    let error: String?
    let immediate: Bool?
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

    /// Hora del mensaje del chat; con la fecha si ya pasó más de un día.
    static func parse(_ iso: String) -> Date? {
        parser.date(from: iso) ?? plainParser.date(from: iso)
    }

    static func chatStamp(_ iso: String, language: AppLanguage) -> String {
        guard let date = parser.date(from: iso) ?? plainParser.date(from: iso) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .es ? "es_CO" : "en_US")
        formatter.timeStyle = .short
        if Date().timeIntervalSince(date) > 24 * 60 * 60 {
            formatter.setLocalizedDateFormatFromTemplate("d MMM jj:mm")
        }
        return formatter.string(from: date)
    }
}
