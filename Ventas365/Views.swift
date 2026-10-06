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
    let onExit: () -> Void

    var body: some View {
        let strings = web.language.strings
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                barButton("chevron.left", label: strings.back) { if !web.goBack() { onExit() } }
                barButton("house", label: strings.appHome, action: onExit)
                Spacer()
                Text(section.title(strings))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.ink)
                Spacer()
                // Mismo ancho que los dos botones de la izquierda, para centrar el título.
                Color.clear.frame(width: 44, height: 44)
                barButton("arrow.clockwise", label: strings.reload) { web.reload() }
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
                    OfflineView(strings: strings, onRetry: { web.reload() }, onHome: onExit)
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
