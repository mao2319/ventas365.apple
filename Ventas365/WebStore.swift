import GoogleSignIn
import SwiftUI
import UIKit
import WebKit

/// El WebView del sitio y todo lo que Safari hace solo y un WKWebView no:
/// enlaces externos, permiso de cámara y el inicio de sesión con Google (que
/// Google bloquea dentro de un WebView, así que se hace con el SDK nativo y
/// se le entrega el token al sitio).
@MainActor
final class WebStore: NSObject, ObservableObject {
    @Published var isLoading = false
    /// La página principal no cargó (sin conexión, sitio caído).
    @Published var failed = false
    /// Idioma elegido: en el inicio de la app o en el encabezado del sitio.
    @Published private(set) var language = AppLanguage.stored()

    let webView: WKWebView

    private var section: AppSection?
    private var loadedLanguage: AppLanguage?
    // Pagos (Wompi): el checkout salta por páginas del banco y vuelve al
    // sitio. Todo ese recorrido se queda aquí adentro para no perder la sesión.
    private var inPaymentFlow = false

    override init() {
        let configuration = WKWebViewConfiguration()
        // El sitio lo usa para ocultar lo que no aplica dentro de la app.
        configuration.applicationNameForUserAgent = "Ventas365App/\(AppConfig.version) iOS"
        // El escáner de códigos muestra la cámara dentro de la página.
        configuration.allowsInlineMediaPlayback = true
        let userContent = WKUserContentController()
        userContent.addUserScript(
            WKUserScript(source: Self.pageScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        configuration.userContentController = userContent
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        userContent.add(self, name: "ventas365")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        // Deslizar desde el borde retrocede dentro del sitio.
        webView.allowsBackForwardNavigationGestures = true
    }

    func select(_ newLanguage: AppLanguage) {
        guard newLanguage != language else { return }
        language = newLanguage
        newLanguage.save()
    }

    /// Abre la sección; si ya estaba abierta en ese idioma, se queda donde el
    /// usuario la dejó.
    func open(_ target: AppSection) {
        if section == target && loadedLanguage == language && !failed { return }
        section = target
        loadedLanguage = language
        failed = false
        webView.load(URLRequest(url: AppConfig.url(for: target, language: language)))
    }

    /// - Returns: false si ya no hay a dónde retroceder dentro del sitio.
    func goBack() -> Bool {
        guard !failed, webView.canGoBack else { return false }
        webView.goBack()
        return true
    }

    func reload() {
        failed = false
        if webView.url == nil, let section {
            webView.load(URLRequest(url: AppConfig.url(for: section, language: language)))
        } else {
            webView.reload()
        }
    }

    private func isSite(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host else { return false }
        return AppConfig.siteHosts.contains(host)
    }

    /// - Returns: true si la navegación se resolvió por fuera del WebView.
    private func route(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            if isSite(url) {
                inPaymentFlow = false
                return false
            }
            if let host = url.host, host.hasSuffix("wompi.co") { inPaymentFlow = true }
            if inPaymentFlow { return false }
            UIApplication.shared.open(url)
            return true
        }
        // Páginas internas del navegador: se quedan adentro.
        if ["about", "blob", "data"].contains(scheme) { return false }
        // tel:, mailto:, whatsapp:, waze:… las abre su app.
        UIApplication.shared.open(url)
        return true
    }

    private func dispatch(_ event: String, detail: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: detail),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.dispatchEvent(new CustomEvent('\(event)',{detail:\(json)}))")
    }

    private func signInWithGoogle() {
        guard AppConfig.googleConfigured, let presenter = Self.topViewController() else {
            dispatch("ventas365-google-error", detail: ["reason": "failed"])
            return
        }
        Task {
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
                if let token = result.user.idToken?.tokenString {
                    dispatch("ventas365-google-credential", detail: ["credential": token])
                } else {
                    dispatch("ventas365-google-error", detail: ["reason": "failed"])
                }
            } catch {
                let cancelled = (error as NSError).code == GIDSignInError.canceled.rawValue
                dispatch("ventas365-google-error", detail: ["reason": cancelled ? "cancelled" : "failed"])
            }
        }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    // Se ejecuta antes que el código del sitio. El sitio ya sabe hablar con
    // la app Android por window.Ventas365Android (ver utils/nativeApp.ts en
    // el repo web): aquí se expone ese mismo objeto, conectado a iOS, para
    // que el sitio no necesite distinguir entre las dos apps.
    private static let pageScript = """
    (function () {
      if (window.Ventas365Android) return;
      var post = function (message) { window.webkit.messageHandlers.ventas365.postMessage(message); };
      window.Ventas365Android = {
        googleSignIn: function () { post({ action: 'googleSignIn' }); },
        share: function (title, text, url) {
          if (navigator.share) navigator.share({ title: title, text: text, url: url });
        }
      };
    })();
    """
}

extension WebStore: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }
        // Sin marco de destino es una ventana nueva: la resuelve createWebViewWith.
        guard let target = navigationAction.targetFrame else { return .allow }
        // Lo que cargan los marcos internos (mapas, pagos) no se toca.
        if !target.isMainFrame { return .allow }
        return route(url) ? .cancel : .allow
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        // El selector de idioma del sitio recarga en la otra dirección (/en
        // o sin prefijo): la app toma ese idioma como el elegido.
        if let url = webView.url, isSite(url), !failed {
            let shown = AppLanguage.fromPath(url.path)
            loadedLanguage = shown
            select(shown)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        let failure = error as NSError
        // Cancelada por el usuario o porque el enlace se abrió en otra app: no es un fallo.
        let interrupted = failure.domain == "WebKitErrorDomain" && failure.code == 102
        if failure.code == NSURLErrorCancelled || interrupted { return }
        failed = true
    }
}

extension WebStore: WKUIDelegate {
    // target="_blank" / window.open: se enruta como cualquier otro enlace,
    // sin crear una segunda ventana.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url, !route(url) {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    // Cámara para el escáner de códigos: el sistema ya le pidió permiso a
    // la app; aquí solo se evita una segunda pregunta por cada página.
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType
    ) async -> WKPermissionDecision {
        AppConfig.siteHosts.contains(origin.host) && type == .camera ? .grant : .deny
    }
}

extension WebStore: WKScriptMessageHandler {
    /// Lo que el sitio puede pedirle a la app. Solo responde a páginas del sitio.
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              AppConfig.siteHosts.contains(message.frameInfo.securityOrigin.host),
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        if action == "googleSignIn" { signInWithGoogle() }
    }
}

/// El WKWebView dentro de SwiftUI. Es siempre la misma vista: volver al
/// inicio y entrar otra vez a la sección no recarga la página.
struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
