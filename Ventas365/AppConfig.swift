import Foundation

/// Las dos entradas de la app: cada una abre su parte del sitio.
enum AppSection: String {
    case market
    case negocios

    var path: String { self == .market ? "/" : "/negocios" }
    var title: String { self == .market ? "Market" : "Negocios" }
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

    static func url(for section: AppSection) -> URL {
        URL(string: section.path, relativeTo: baseURL)!.absoluteURL
    }
}
