import SwiftUI

// Los mismos tonos del sitio: violeta de Negocios, naranja del Market.
extension Color {
    static let brandViolet = Color(red: 0x6D / 255, green: 0x3F / 255, blue: 0xD1 / 255)
    static let brandOrange = Color(red: 0xFF / 255, green: 0x6A / 255, blue: 0x00 / 255)
    static let ink = Color(red: 0x1C / 255, green: 0x17 / 255, blue: 0x30 / 255)
    static let inkMuted = Color(red: 0x6B / 255, green: 0x67 / 255, blue: 0x76 / 255)
    static let paper = Color(red: 0xF6 / 255, green: 0xF4 / 255, blue: 0xF1 / 255)
}

/// Logo sobre blanco al abrir la app (continúa la pantalla de arranque del sistema).
struct SplashView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Image("LaunchLogo")
        }
    }
}

/// Inicio de la app: las dos formas de usar Ventas365.
struct HomeView: View {
    let onOpen: (AppSection) -> Void

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 104, height: 104)
                    Text("Ventas365")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundColor(.ink)
                        .padding(.top, 16)
                    Text("Abierto todos los días del año")
                        .font(.system(size: 15))
                        .foregroundColor(.inkMuted)
                    Text("¿Qué quieres hacer hoy?")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 36)
                        .padding(.bottom, 12)
                    SectionCard(
                        title: "Market",
                        description: "Compra en las tiendas cerca de ti y pide a domicilio o para recoger.",
                        systemImage: "bag",
                        accent: .brandOrange
                    ) { onOpen(.market) }
                    SectionCard(
                        title: "Negocios",
                        description: "Administra tu tienda: ventas, inventario, caja y pedidos.",
                        systemImage: "building.2",
                        accent: .brandViolet
                    ) { onOpen(.negocios) }
                    .padding(.top, 14)
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, 24)
                .padding(.vertical, 48)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct SectionCard: View {
    let title: String
    let description: String
    let systemImage: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.ink)
                    Text(description)
                        .font(.system(size: 14))
                        .foregroundColor(.inkMuted)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.ink)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(accent.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir \(title)")
    }
}

/// El sitio con una barra propia: en iPhone no hay botón "atrás" del
/// sistema, así que volver al sitio anterior y al inicio de la app van aquí.
struct WebScreen: View {
    @ObservedObject var web: WebStore
    let section: AppSection
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                barButton("chevron.left", label: "Atrás") { if !web.goBack() { onExit() } }
                barButton("house", label: "Inicio de la app", action: onExit)
                Spacer()
                Text(section.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.ink)
                Spacer()
                // Mismo ancho que los dos botones de la izquierda, para centrar el título.
                Color.clear.frame(width: 44, height: 44)
                barButton("arrow.clockwise", label: "Recargar") { web.reload() }
            }
            .padding(.horizontal, 6)
            .background(Color.white)
            .overlay(alignment: .bottom) {
                if web.isLoading && !web.failed {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(.brandViolet)
                        .frame(height: 2)
                } else {
                    Color.black.opacity(0.08).frame(height: 1)
                }
            }

            ZStack {
                WebViewContainer(webView: web.webView)
                if web.failed {
                    OfflineView(onRetry: { web.reload() }, onHome: onExit)
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
        .onAppear { web.open(section) }
    }

    private func barButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.brandViolet)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
    }
}

/// Cuando el sitio no carga: en vez de una página en blanco.
struct OfflineView: View {
    let onRetry: () -> Void
    let onHome: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
            Text("No pudimos conectarnos")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.ink)
                .padding(.top, 20)
            Text("Revisa tu conexión a internet e inténtalo de nuevo.")
                .font(.system(size: 15))
                .foregroundColor(.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            Button("Reintentar", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(.brandViolet)
                .padding(.top, 24)
            Button("Volver al inicio", action: onHome)
                .foregroundColor(.brandViolet)
                .padding(.top, 12)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
    }
}
