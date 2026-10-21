import AudioToolbox
import CoreLocation
import Foundation
import UIKit
import UserNotifications

/// Lo que el turno necesita para hablar con Supabase como el domiciliario.
struct ShiftConfig: Equatable {
    let token: String
    let supabaseURL: URL
    let anonKey: String
    let language: String

    /// Solo acepta un proyecto de Supabase por https.
    init?(token: String?, supabaseURL: String?, anonKey: String?, language: String?) {
        guard let token, !token.isEmpty, token.count <= 128,
              let anonKey, !anonKey.isEmpty,
              let raw = supabaseURL, let url = URL(string: raw.hasSuffix("/") ? String(raw.dropLast()) : raw),
              url.scheme == "https", let host = url.host, host.hasSuffix(".supabase.co") else { return nil }
        self.token = token
        self.supabaseURL = url
        self.anonKey = anonKey
        self.language = language == "en" ? "en" : "es"
    }
}

/// Turno del domiciliario (módulo Domicilios). Mientras está conectado:
///  - toma la ubicación (también con la app en segundo plano: iOS muestra el
///    indicador azul) y la envía a Supabase cada 20 s (courier_ping_location),
///    así la tienda y quien espera el pedido lo ven moverse en el mapa;
///  - cada 30 s revisa los domicilios disponibles y sus pedidos en curso y
///    avisa con una notificación local cuando hay uno nuevo o un mensaje
///    nuevo del cliente, aunque la app no esté a la vista.
@MainActor
final class CourierShift: NSObject, ObservableObject {
    static let shared = CourierShift()

    /// Sección que se debe abrir (al tocar un aviso de Domicilios).
    @Published var requestedSection: AppSection?

    private let locationManager = CLLocationManager()
    private var config: ShiftConfig?
    private var lastLocation: CLLocation?
    private var lastPingAt = Date.distantPast
    private var pollTimer: Timer?
    private var knownJobs: Set<String>?
    private var knownMessages: [String: Int]?

    private static let pingInterval: TimeInterval = 20
    private static let pollInterval: TimeInterval = 30

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 15
        locationManager.activityType = .otherNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Lo que pide el sitio

    func start(_ shift: ShiftConfig) {
        let wasRunning = config != nil
        config = shift
        if wasRunning { return }
        knownJobs = nil
        knownMessages = nil
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            beginLocation()
        default:
            break
        }
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkJobs() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            checkJobs()
        }
    }

    func stop() {
        config = nil
        pollTimer?.invalidate()
        pollTimer = nil
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func keepAwake(_ on: Bool) {
        UIApplication.shared.isIdleTimerDisabled = on
    }

    func vibrate() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    /// Aviso local que abre Domicilios al tocarlo. Con la app a la vista no
    /// se muestra (la página ya avisa).
    func notify(title: String, body: String, id: String = "domicilios") {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["section": AppSection.domicilios.rawValue]
        content.threadIdentifier = "ventas365-domicilios"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: - Ubicación

    private func beginLocation() {
        guard config != nil else { return }
        // Requiere UIBackgroundModes: location (project.yml). Con permiso
        // "Al usar la app" iOS lo permite si el turno empezó con la app
        // abierta, y muestra el indicador azul.
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.startUpdatingLocation()
    }

    private func handle(_ location: CLLocation) {
        lastLocation = location
        guard let config, Date().timeIntervalSince(lastPingAt) >= Self.pingInterval else { return }
        lastPingAt = Date()
        Task {
            let result = await rpc(config, "courier_ping_location", [
                "p_token": config.token,
                "p_lat": location.coordinate.latitude,
                "p_lng": location.coordinate.longitude,
            ])
            if result.sessionExpired { stop() }
        }
    }

    // MARK: - Domicilios nuevos y mensajes

    private func checkJobs() {
        guard let config else { return }
        var position: [String: Any] = ["p_token": config.token, "p_lat": NSNull(), "p_lng": NSNull()]
        if let location = lastLocation {
            position["p_lat"] = location.coordinate.latitude
            position["p_lng"] = location.coordinate.longitude
        }
        Task {
            let strings = CourierStrings.of(config.language)
            let available = await rpc(config, "courier_available_orders", position)
            if available.sessionExpired {
                stop()
                return
            }
            if let jobs = available.body as? [[String: Any]] {
                let ids = Set(jobs.compactMap { $0["id"] as? String })
                if let previous = knownJobs {
                    let fresh = jobs.filter { !previous.contains(($0["id"] as? String) ?? "") }
                    if let first = fresh.first {
                        let store = (first["store"] as? [String: Any])?["name"] as? String ?? ""
                        let body = fresh.count == 1
                            ? strings.newJobBody(store: store, km: first["distanceKm"] as? Double)
                            : strings.newJobsBody(fresh.count)
                        notify(title: strings.newJobTitle, body: body, id: "domicilios-nuevos")
                    }
                }
                knownJobs = ids
            }
            let mine = await rpc(config, "courier_my_orders", position)
            if let jobs = mine.body as? [[String: Any]] {
                var counts: [String: Int] = [:]
                for job in jobs {
                    if let id = job["id"] as? String { counts[id] = job["customerMessages"] as? Int ?? 0 }
                }
                if let previous = knownMessages, counts.contains(where: { $0.value > (previous[$0.key] ?? 0) }) {
                    notify(title: strings.messageTitle, body: strings.messageBody, id: "domicilios-mensajes")
                }
                knownMessages = counts
            }
        }
    }

    private struct RpcResult {
        let body: Any?
        let sessionExpired: Bool
    }

    private func rpc(_ config: ShiftConfig, _ function: String, _ args: [String: Any]) async -> RpcResult {
        var request = URLRequest(url: config.supabaseURL.appendingPathComponent("rest/v1/rpc/\(function)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: args)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                // La sesión del domiciliario venció o se cerró en otro lado.
                let text = String(data: data, encoding: .utf8) ?? ""
                return RpcResult(body: nil, sessionExpired: text.uppercased().contains("SESION"))
            }
            return RpcResult(body: try? JSONSerialization.jsonObject(with: data), sessionExpired: false)
        } catch {
            return RpcResult(body: nil, sessionExpired: false)
        }
    }
}

extension CourierShift: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: beginLocation()
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in handle(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

extension CourierShift: UNUserNotificationCenterDelegate {
    /// Al tocar el aviso: abre Domicilios.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let raw = response.notification.request.content.userInfo["section"] as? String
        Task { @MainActor in
            if let raw, let section = AppSection(rawValue: raw) { requestedSection = section }
            completionHandler()
        }
    }

    /// Con la app abierta la página ya avisa (sonido y vibración). Los avisos
    /// de cancelación del Market sí se muestran: no hay otro aviso en pantalla.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.identifier.hasPrefix("cancel-") {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([])
        }
    }
}

/// Textos de los avisos del turno.
struct CourierStrings {
    let newJobTitle: String
    let messageTitle: String
    let messageBody: String
    private let oneJob: String
    private let oneJobNear: String
    private let manyJobs: String

    func newJobBody(store: String, km: Double?) -> String {
        guard let km else { return String(format: oneJob, store) }
        let distance = km < 1 ? "\(Int(km * 1000)) m" : String(format: "%.1f km", km)
        return String(format: oneJobNear, store, distance)
    }

    func newJobsBody(_ count: Int) -> String { String(format: manyJobs, count) }

    static func of(_ language: String) -> CourierStrings { language == "en" ? english : spanish }

    private static let spanish = CourierStrings(
        newJobTitle: "🛵 Nuevo domicilio disponible",
        messageTitle: "💬 Nuevo mensaje del cliente",
        messageBody: "Toca para ver el mensaje de tu pedido en curso.",
        oneJob: "%@ tiene un pedido para llevar. Tómalo antes que otro.",
        oneJobNear: "%@ · a %@. Tómalo antes que otro.",
        manyJobs: "Hay %d domicilios nuevos disponibles."
    )

    private static let english = CourierStrings(
        newJobTitle: "🛵 New delivery available",
        messageTitle: "💬 New message from the customer",
        messageBody: "Tap to see the message about your active order.",
        oneJob: "%@ has an order to deliver. Take it before someone else does.",
        oneJobNear: "%@ · %@ away. Take it before someone else does.",
        manyJobs: "There are %d new deliveries available."
    )
}
