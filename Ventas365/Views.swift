import SwiftUI

// Los mismos tonos del sitio: violeta de Negocios, naranja del Market.
extension Color {
    static let brandViolet = Color(red: 0x6D / 255, green: 0x3F / 255, blue: 0xD1 / 255)
    static let brandOrange = Color(red: 0xFF / 255, green: 0x6A / 255, blue: 0x00 / 255)
    /// Domicilios: verde del Market.
    static let brandGreen = Color(red: 0x1A / 255, green: 0x7F / 255, blue: 0x4B / 255)
    static let brandGreenDeep = Color(red: 0x13 / 255, green: 0x62 / 255, blue: 0x39 / 255)
    static let brandGreenTint = Color(red: 0xE7 / 255, green: 0xF4 / 255, blue: 0xEC / 255)
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

/// Inicio de la app: las formas de usar Ventas365 (comprar, vender, repartir).
struct HomeView: View {
    let language: AppLanguage
    let onLanguage: (AppLanguage) -> Void
    let onOpen: (AppSection) -> Void

    var body: some View {
        let strings = language.strings
        ZStack(alignment: .topTrailing) {
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
                    Text(strings.tagline)
                        .font(.system(size: 15))
                        .foregroundColor(.inkMuted)
                    Text(strings.question)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 36)
                        .padding(.bottom, 12)
                    SectionCard(
                        title: "Market",
                        description: strings.marketDescription,
                        openLabel: strings.open,
                        systemImage: "bag",
                        accent: .brandOrange
                    ) { onOpen(.market) }
                    SectionCard(
                        title: strings.businessTitle,
                        description: strings.businessDescription,
                        openLabel: strings.open,
                        systemImage: "building.2",
                        accent: .brandViolet
                    ) { onOpen(.negocios) }
                    .padding(.top, 14)
                    SectionCard(
                        title: strings.couriersTitle,
                        description: strings.couriersDescription,
                        openLabel: strings.open,
                        systemImage: "scooter",
                        accent: .brandGreen
                    ) { onOpen(.domicilios) }
                    .padding(.top, 14)
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, 24)
                .padding(.vertical, 64)
                .frame(maxWidth: .infinity)
            }
            LanguageToggle(current: language, label: strings.language, onSelect: onLanguage)
                .padding(.top, 8)
                .padding(.trailing, 16)
        }
    }
}

/// Selector de idioma del inicio: los dos idiomas a la vista, el actual resaltado.
private struct LanguageToggle: View {
    let current: AppLanguage
    let label: String
    let onSelect: (AppLanguage) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppLanguage.allCases) { language in
                let selected = language == current
                Button { onSelect(language) } label: {
                    Text(language.rawValue.uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(selected ? .white : .inkMuted)
                        .frame(minWidth: 48, minHeight: 40)
                        .background(Capsule().fill(selected ? Color.ink : Color.clear))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white))
        .overlay(Capsule().stroke(Color.ink.opacity(0.14), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

private struct SectionCard: View {
    let title: String
    let description: String
    let openLabel: String
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
        .accessibilityLabel("\(openLabel) \(title)")
    }
}

/// El sitio con una barra propia: en iPhone no hay botón "atrás" del
/// sistema, así que volver al sitio anterior y al inicio de la app van aquí.
struct WebScreen: View {
    @ObservedObject var web: WebStore
    let section: AppSection
    /// Si se indica, abre esa página del sitio en lugar de la sección.
    var path: String?
    let onExit: () -> Void
    /// Menú ☰: inicio de la app y las otras secciones (Market, Negocios, Domicilios).
    var onNavigate: ((AppSection?) -> Void)? = nil

    var body: some View {
        let strings = web.language.strings
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Menu {
                    Button { onExit() } label: { Label(web.language == .es ? "Inicio" : "Home", systemImage: "house") }
                    ForEach([AppSection.market, .negocios, .domicilios].filter { $0 != section }, id: \.self) { other in
                        Button { onNavigate?(other) ?? onExit() } label: {
                            Label(other.title(strings), systemImage: other == .market ? "bag" : other == .negocios ? "briefcase" : "bicycle")
                        }
                    }
                } label: {
                    // Mismo botón ☰ del Market: círculo de cristal.
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(accent)
                        .frame(width: 44, height: 44)
                        .modifier(GlassCircle())
                }
                .accessibilityLabel(web.language == .es ? "Menú" : "Menu")
                Spacer()
                Text(section.title(strings))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.ink)
                Spacer()
                // Mismo ancho que el ☰, para centrar el título.
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.paper)
            .overlay(alignment: .bottom) {
                if web.isLoading && !web.failed {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(.brandViolet)
                        .frame(height: 2)
                } else {
                    // Sin línea divisoria, como el encabezado del Market.
                    Color.clear.frame(height: 1)
                }
            }

            ZStack {
                WebViewContainer(webView: web.webView)
                if web.failed {
                    OfflineView(strings: strings, onRetry: { web.reload() }, onHome: onExit)
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
        .onAppear {
            if let path { web.openPath(path) } else { web.open(section) }
        }
        // Cambio de sección desde el menú ☰ (la misma pantalla sigue en uso).
        .onChange(of: section) { web.open($0) }
    }

    private func barButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(accent)
                .frame(width: 44, height: 44)
                .modifier(GlassCircle())
        }
        .accessibilityLabel(label)
    }

    /// Color de la sección, como en el inicio de la app.
    private var accent: Color {
        switch section {
        case .market: return .brandOrange
        case .negocios: return .brandViolet
        case .domicilios: return .brandGreen
        }
    }
}

/// Botón redondo de cristal (Liquid Glass en iOS 26; blanco con borde antes),
/// igual al ☰ del Market nativo.
struct GlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
                .background(Circle().fill(Color.white))
                .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
    }
}

/// Cuando el sitio no carga: en vez de una página en blanco.
struct OfflineView: View {
    let strings: AppStrings
    let onRetry: () -> Void
    let onHome: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
            Text(strings.offlineTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.ink)
                .padding(.top, 20)
            Text(strings.offlineBody)
                .font(.system(size: 15))
                .foregroundColor(.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            Button(strings.retry, action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(.brandViolet)
                .padding(.top, 24)
            Button(strings.backHome, action: onHome)
                .foregroundColor(.brandViolet)
                .padding(.top, 12)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
    }
}
