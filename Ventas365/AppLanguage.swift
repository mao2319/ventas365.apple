import Foundation

/// Idiomas de la app. El sitio decide el suyo por la dirección: lo que va bajo
/// /en está en inglés y el resto en español, así que aquí cada idioma lleva el
/// prefijo con el que se abren sus páginas.
enum AppLanguage: String, CaseIterable, Identifiable {
    case es
    case en

    var id: String { rawValue }
    var label: String { self == .es ? "Español" : "English" }
    var urlPrefix: String { self == .es ? "" : "/en" }

    /// Idioma de una página del sitio, según su ruta.
    static func fromPath(_ path: String) -> AppLanguage {
        path == "/en" || path.hasPrefix("/en/") ? .en : .es
    }

    private static let storageKey = "idioma"

    /// El que eligió la persona; la primera vez, el del teléfono (español si
    /// está en español, inglés en cualquier otro caso).
    static func stored() -> AppLanguage {
        if let saved = UserDefaults.standard.string(forKey: storageKey), let language = AppLanguage(rawValue: saved) {
            return language
        }
        let device = Locale.preferredLanguages.first ?? "es"
        return device.hasPrefix("es") ? .es : .en
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.storageKey)
    }

    var strings: AppStrings { self == .es ? .spanish : .english }
}

/// Textos de las pantallas propias de la app (el resto lo trae el sitio).
struct AppStrings {
    let tagline: String
    let question: String
    let marketDescription: String
    let businessTitle: String
    let businessDescription: String
    let open: String
    let language: String
    let back: String
    let appHome: String
    let reload: String
    let offlineTitle: String
    let offlineBody: String
    let retry: String
    let backHome: String

    static let spanish = AppStrings(
        tagline: "Abierto todos los días del año",
        question: "¿Qué quieres hacer hoy?",
        marketDescription: "Compra en las tiendas cerca de ti y pide a domicilio o para recoger.",
        businessTitle: "Negocios",
        businessDescription: "Administra tu tienda: ventas, inventario, caja y pedidos.",
        open: "Abrir",
        language: "Idioma",
        back: "Atrás",
        appHome: "Inicio de la app",
        reload: "Recargar",
        offlineTitle: "No pudimos conectarnos",
        offlineBody: "Revisa tu conexión a internet e inténtalo de nuevo.",
        retry: "Reintentar",
        backHome: "Volver al inicio"
    )

    static let english = AppStrings(
        tagline: "Open every day of the year",
        question: "What would you like to do today?",
        marketDescription: "Shop at the stores near you and order for delivery or pickup.",
        businessTitle: "Business",
        businessDescription: "Manage your store: sales, inventory, cash and orders.",
        open: "Open",
        language: "Language",
        back: "Back",
        appHome: "App home",
        reload: "Reload",
        offlineTitle: "We couldn't connect",
        offlineBody: "Check your internet connection and try again.",
        retry: "Try again",
        backHome: "Back to home"
    )
}
