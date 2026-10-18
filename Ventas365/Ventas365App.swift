import GoogleSignIn
import SwiftUI

// Cuánto se mantiene la pantalla de inicio con el logo.
private let splashNanoseconds: UInt64 = 1_500_000_000

@main
struct Ventas365App: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // Siempre claro: el sitio que se muestra adentro no tiene modo oscuro.
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    // Un solo WebView para toda la vida de la app.
    @StateObject private var web = WebStore()
    // Turno de Domicilios: se crea al abrir la app para recibir el toque en
    // sus avisos (abre Domicilios).
    @StateObject private var courier = CourierShift.shared
    @State private var section: AppSection?
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if section == .market {
                // Market nativo: el pedido se genera en la app, sin pasar por el sitio.
                MarketHub(language: web.language, onExit: { section = nil })
            } else if let section {
                WebScreen(web: web, section: section, onExit: { self.section = nil })
            } else {
                HomeView(language: web.language, onLanguage: web.select, onOpen: { section = $0 })
            }
            if showSplash {
                SplashView().transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: splashNanoseconds)
            withAnimation(.easeOut(duration: 0.25)) { showSplash = false }
        }
        .onReceive(courier.$requestedSection) { requested in
            guard let requested else { return }
            section = requested
            courier.requestedSection = nil
        }
        // Regreso del inicio de sesión de Google a la app.
        .onOpenURL { url in
            _ = GIDSignIn.sharedInstance.handle(url)
        }
    }
}
