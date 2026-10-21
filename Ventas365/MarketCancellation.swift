import SwiftUI
import UserNotifications

/// Textos de la cancelación de pedidos.
struct CancelText {
    let language: AppLanguage
    private func pick(_ es: String, _ en: String) -> String { language == .es ? es : en }

    var cancelNow: String { pick("Cancelar pedido", "Cancel order") }
    var requestCancel: String { pick("Solicitar cancelación", "Request cancellation") }
    var cancelNowHint: String { pick("La tienda aún no acepta tu pedido: puedes cancelarlo de inmediato.", "The store hasn't accepted your order yet: you can cancel it right away.") }
    var requestHint: String { pick("La tienda ya está trabajando en tu pedido. Le enviaremos tu solicitud y ella confirma si se puede cancelar.", "The store is already working on your order. We'll send your request and the store confirms whether it can be canceled.") }
    var reasonTitle: String { pick("Motivo de la cancelación", "Reason for canceling") }
    var otherReason: String { pick("Cuéntale a la tienda el motivo", "Tell the store why") }
    var confirmCancel: String { pick("Cancelar el pedido", "Cancel the order") }
    var confirmRequest: String { pick("Enviar solicitud", "Send request") }
    var keep: String { pick("Volver", "Back") }
    var sending: String { pick("Enviando…", "Sending…") }
    var error: String { pick("No se pudo completar. Intenta de nuevo.", "Couldn't complete. Try again.") }
    var pendingTitle: String { pick("Cancelación solicitada", "Cancellation requested") }
    var pendingBody: String { pick("La tienda está revisando tu solicitud. Te avisaremos cuando responda.", "The store is reviewing your request. We'll let you know when it replies.") }
    var cancelledTitle: String { pick("Pedido cancelado", "Order canceled") }
    var rejectedTitle: String { pick("La tienda no pudo cancelar el pedido", "The store couldn't cancel the order") }
    var yourReason: String { pick("Tu motivo", "Your reason") }
    var storeReply: String { pick("Respuesta de la tienda", "Store's reply") }
    var cancelledNotice: String { pick("Tu pedido en %@ fue cancelado.", "Your order at %@ was canceled.") }
    var rejectedNotice: String { pick("%@ no pudo cancelar tu pedido: sigue en curso.", "%@ couldn't cancel your order: it's still in progress.") }
    var requestSent: String { pick("Solicitud enviada a la tienda.", "Request sent to the store.") }
    var cancelledDone: String { pick("Tu pedido quedó cancelado.", "Your order was canceled.") }

    var reasons: [String] {
        language == .es
            ? ["Me equivoqué de productos", "Ya no lo necesito", "Tarda demasiado", "Quiero cambiar la dirección o el pago"]
            : ["I ordered the wrong items", "I don't need it anymore", "It's taking too long", "I want to change the address or payment"]
    }
}

/// Hoja para cancelar (o pedir cancelar) un pedido con su motivo.
struct CancelOrderSheet: View {
    let purchase: CustomerPurchase
    let language: AppLanguage
    let onDone: (_ immediate: Bool) -> Void

    @EnvironmentObject private var session: MarketSession
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String?
    @State private var other = ""
    @State private var busy = false
    @State private var errorMessage: String?

    private var reason: String {
        let typed = other.trimmingCharacters(in: .whitespacesAndNewlines)
        if let selected { return typed.isEmpty ? selected : "\(selected). \(typed)" }
        return typed
    }

    var body: some View {
        let text = CancelText(language: language)
        let immediate = purchase.cancelsImmediately
        NavigationStack {
            Form {
                Section {
                    Text(immediate ? text.cancelNowHint : text.requestHint)
                        .font(.system(size: 14))
                        .foregroundColor(.inkMuted)
                }
                Section(text.reasonTitle) {
                    ForEach(text.reasons, id: \.self) { option in
                        Button {
                            selected = selected == option ? nil : option
                        } label: {
                            HStack {
                                Text(option).foregroundColor(.ink)
                                Spacer()
                                if selected == option { Image(systemName: "checkmark").foregroundColor(.brandGreen) }
                            }
                        }
                    }
                    TextField(text.otherReason, text: $other, axis: .vertical)
                        .lineLimit(2...4)
                        .onChange(of: other) { other = String($0.prefix(250)) }
                }
                Section {
                    if let errorMessage {
                        Text(errorMessage).font(.system(size: 14)).foregroundColor(.red)
                    }
                    Button(role: .destructive) {
                        Task { await submit(text) }
                    } label: {
                        Text(busy ? text.sending : (immediate ? text.confirmCancel : text.confirmRequest))
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .modifier(DestructiveActionStyle())
                    .disabled(busy || reason.count < 3)
                }
            }
            .navigationTitle(immediate ? text.cancelNow : text.requestCancel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(text.keep) { dismiss() } }
            }
        }
    }

    private func submit(_ text: CancelText) async {
        guard let token = session.token else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let response = try await MarketAPI.cancelOrder(token: token, kind: purchase.kind, id: purchase.id, reason: reason)
            if response.success == true {
                // Para avisarle cuando la tienda responda la solicitud.
                if response.immediate != true { CancellationNotifier.requestPermission() }
                dismiss()
                onDone(response.immediate == true)
            } else {
                errorMessage = response.error ?? text.error
            }
        } catch {
            errorMessage = text.error
        }
    }
}

/// Botón destructivo: cristal rojo en iOS 26, relleno rojo antes.
struct DestructiveActionStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent).tint(.red)
        } else {
            content.buttonStyle(.borderedProminent).tint(.red)
        }
    }
}

/// Estado de la cancelación dentro del detalle del pedido.
struct CancellationStatusView: View {
    let cancellation: PurchaseCancellation
    let language: AppLanguage

    var body: some View {
        let text = CancelText(language: language)
        VStack(alignment: .leading, spacing: 6) {
            Label(
                cancellation.isPending ? text.pendingTitle : cancellation.isCancelled ? text.cancelledTitle : text.rejectedTitle,
                systemImage: cancellation.isPending ? "hourglass" : cancellation.isCancelled ? "xmark.circle.fill" : "exclamationmark.circle.fill"
            )
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(cancellation.isPending ? .orange : cancellation.isCancelled ? .red : .ink)
            if cancellation.isPending {
                Text(text.pendingBody).font(.system(size: 14)).foregroundColor(.inkMuted)
            }
            Text("\(text.yourReason): \(cancellation.reason)").font(.system(size: 14))
            if let note = cancellation.storeNote, !note.isEmpty {
                Text("\(text.storeReply): \(note)").font(.system(size: 14)).foregroundColor(.ink)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Avisa al cliente cuando la tienda aprueba o rechaza su solicitud de
/// cancelación: notificación local (con la app abierta o al volver a ella)
/// y la marca como leída en el servidor. Sin notificaciones push (APNs) no
/// puede avisar con la app cerrada; para eso también llega un correo.
@MainActor
enum CancellationNotifier {
    private static var notified = Set<String>()

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func check(_ purchases: [CustomerPurchase], token: String, language: AppLanguage) {
        let text = CancelText(language: language)
        let resolved = purchases.compactMap { purchase -> (CustomerPurchase, PurchaseCancellation)? in
            guard let cancellation = purchase.cancellation, !cancellation.isPending, cancellation.seen != true,
                  !notified.contains(cancellation.id) else { return nil }
            return (purchase, cancellation)
        }
        guard !resolved.isEmpty else { return }
        for (purchase, cancellation) in resolved {
            notified.insert(cancellation.id)
            let content = UNMutableNotificationContent()
            let store = purchase.storeName.capitalized
            content.title = cancellation.isCancelled ? text.cancelledTitle : text.rejectedTitle
            content.body = String(format: cancellation.isCancelled ? text.cancelledNotice : text.rejectedNotice, store)
                + ((cancellation.storeNote ?? "").isEmpty ? "" : " \(cancellation.storeNote!)")
            content.sound = .default
            content.userInfo = ["section": AppSection.market.rawValue]
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "cancel-\(cancellation.id)", content: content, trigger: nil)
            )
        }
        let ids = resolved.map(\.1.id)
        Task { await MarketAPI.markCancellationsSeen(token: token, ids: ids) }
    }
}
