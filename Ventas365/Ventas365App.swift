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
    @State private var section: AppSection?
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if let section {
                WebScreen(web: web, section: section, onExit: { self.section = nil })
            } else {
                HomeView(onOpen: { section = $0 })
            }
            if showSplash {
                SplashView().transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: splashNanoseconds)
            withAnimation(.easeOut(duration: 0.25)) { showSplash = false }
        }
        // Regreso del inicio de sesión de Google a la app.
        .onOpenURL { url in
            _ = GIDSignIn.sharedInstance.handle(url)
        }
    }
}
