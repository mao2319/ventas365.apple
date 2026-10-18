import Foundation
import Security

/// Llavero del sistema: ahí se guarda el token de la sesión del cliente.
enum Keychain {
    private static let service = "app.ventas365.market"

    private static func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    static func set(_ value: String, for key: String) {
        SecItemDelete(query(key) as CFDictionary)
        var item = query(key)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        var request = query(key)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}

/// Cliente del Market (mismos campos que `MarketCustomer` del sitio).
struct MarketCustomer: Codable, Equatable {
    let id: String
    let fullName: String
    let documentNumber: String?
    let countryIso: String?
    let phone: String?
    let alternatePhoneCountryIso: String?
    let alternatePhone: String?
    let department: String?
    let city: String?
    let address: String?
    let email: String
    let avatarUrl: String?
}

/// País para iniciar sesión con celular (la lista completa llega con el registro).
struct DialCountry: Identifiable, Hashable {
    let iso2: String
    let name: String
    let dialCode: String
    var id: String { iso2 }

    static let common: [DialCountry] = [
        DialCountry(iso2: "CO", name: "Colombia", dialCode: "+57"),
        DialCountry(iso2: "MX", name: "México", dialCode: "+52"),
        DialCountry(iso2: "PE", name: "Perú", dialCode: "+51"),
        DialCountry(iso2: "EC", name: "Ecuador", dialCode: "+593"),
        DialCountry(iso2: "CL", name: "Chile", dialCode: "+56"),
        DialCountry(iso2: "AR", name: "Argentina", dialCode: "+54"),
        DialCountry(iso2: "US", name: "Estados Unidos", dialCode: "+1"),
        DialCountry(iso2: "ES", name: "España", dialCode: "+34"),
    ]
}

private struct LoginResponse: Decodable {
    let success: Bool?
    let error: String?
    let customer: MarketCustomer?
    let sessionToken: String?
}

private struct SessionResponse: Decodable {
    let valid: Bool
    let customer: MarketCustomer?
}

private struct EmailLogin: Encodable {
    let identifierType = "email"
    let email: String
    let password: String
}

private struct PhoneLogin: Encodable {
    let identifierType = "phone"
    let countryIso: String
    let phone: String
    let password: String
}

private struct ResetBody: Encodable {
    let email: String
    let language: String
}

private struct ResetResponse: Decodable {
    let success: Bool?
}

private struct TokenBody: Encodable {
    let token: String
}

/// Sesión del cliente del Market. El inicio de sesión es el mismo del sitio
/// (funciones `market-customer-login` y `market-customer-session`).
@MainActor
final class MarketSession: ObservableObject {
    enum LoginError: Error {
        case rejected(String?)
        case network
    }

    @Published private(set) var customer: MarketCustomer?
    private(set) var token: String?

    private static let tokenKey = "customer-token"
    private static let customerKey = "market-customer"

    var isSignedIn: Bool { customer != nil }

    init() {
        token = Keychain.get(Self.tokenKey)
        if token != nil,
           let data = UserDefaults.standard.data(forKey: Self.customerKey),
           let saved = try? JSONDecoder().decode(MarketCustomer.self, from: data) {
            customer = saved
        }
    }

    /// Revisa con el servidor que el token siga vigente (30 días); si ya no,
    /// cierra la sesión. Sin conexión se conserva lo guardado.
    func refresh() async {
        guard let token else { return }
        do {
            let response: SessionResponse = try await MarketAPI.invoke("market-customer-session", TokenBody(token: token))
            if response.valid, let fresh = response.customer {
                store(token: token, customer: fresh)
            } else {
                signOut()
            }
        } catch {
            // Sin red: se queda con la sesión guardada.
        }
    }

    func signIn(email: String, password: String) async throws {
        try await finishLogin(EmailLogin(email: email, password: password))
    }

    func signIn(country: DialCountry, phone: String, password: String) async throws {
        try await finishLogin(PhoneLogin(countryIso: country.iso2, phone: phone, password: password))
    }

    private func finishLogin<Body: Encodable>(_ body: Body) async throws {
        let response: LoginResponse
        do {
            response = try await MarketAPI.invoke("market-customer-login", body)
        } catch {
            throw LoginError.network
        }
        guard response.success == true, let customer = response.customer, let token = response.sessionToken else {
            throw LoginError.rejected(response.error)
        }
        store(token: token, customer: customer)
    }

    /// Envía el correo para cambiar la contraseña (`market-customer-request-reset`).
    func requestPasswordReset(email: String, language: AppLanguage) async -> Bool {
        let response: ResetResponse? = try? await MarketAPI.invoke(
            "market-customer-request-reset",
            ResetBody(email: email, language: language.rawValue)
        )
        return response?.success == true
    }

    func signOut() {
        token = nil
        customer = nil
        Keychain.remove(Self.tokenKey)
        UserDefaults.standard.removeObject(forKey: Self.customerKey)
    }

    private func store(token: String, customer: MarketCustomer) {
        self.token = token
        self.customer = customer
        Keychain.set(token, for: Self.tokenKey)
        if let data = try? JSONEncoder().encode(customer) {
            UserDefaults.standard.set(data, forKey: Self.customerKey)
        }
    }
}
