import Foundation

/// Las entradas de la app: cada una abre su parte del sitio.
enum AppSection: String {
    case market
    case negocios
    case domicilios

    var path: String {
        switch self {
        case .market: return "/"
        case .negocios: return "/negocios"
        case .domicilios: return "/domicilios"
        }
    }

    func title(_ strings: AppStrings) -> String {
        switch self {
        case .market: return "Market"
        case .negocios: return strings.businessTitle
        case .domicilios: return strings.couriersTitle
        }
    }
}

enum AppConfig {
    /// Sitio que carga la app.
    static let baseURL = URL(string: "https://ventas365.app")!
    static let siteHosts: Set<String> = ["ventas365.app", "www.ventas365.app"]

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// El cliente OAuth de iOS se crea en Google Cloud y se pone en
    /// project.yml (GOOGLE_IOS_CLIENT_ID). Mientras no esté, el inicio de
    /// sesión con Google no se intenta.
    static var googleConfigured: Bool {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else { return false }
        return !clientID.isEmpty && !clientID.contains("PENDIENTE")
    }

    /// El idioma va en la ruta (/en) y además en ?idioma=, que le dice al
    /// sitio que esa es la elección de la persona (reemplaza la que tuviera
    /// guardada).
    static func url(for section: AppSection, language: AppLanguage) -> URL {
        url(path: section.path, language: language)
    }

    static func url(path sitePath: String, language: AppLanguage) -> URL {
        var path = language.urlPrefix + sitePath
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        components.queryItems = [URLQueryItem(name: "idioma", value: language.rawValue)]
        return components.url!
    }
}
