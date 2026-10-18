import SwiftUI

/// Textos de la bienvenida y del inicio de sesión.
struct AuthText {
    let language: AppLanguage
    private func pick(_ es: String, _ en: String) -> String { language == .es ? es : en }

    var welcomeTitle: String { pick("Tu cuenta del Market", "Your Market account") }
    var welcomeBody: String { pick("Entra para pedir, seguir tus pedidos y tener todo a la mano.", "Sign in to order, track your orders and keep everything at hand.") }
    var benefitOrders: String { pick("Pide a domicilio o para recoger", "Order for delivery or pickup") }
    var benefitTrack: String { pick("Sigue el estado de tus pedidos", "Track the status of your orders") }
    var benefitAddresses: String { pick("Guarda tus direcciones", "Save your addresses") }
    var signIn: String { pick("Iniciar sesión", "Sign in") }
    var title: String { pick("Bienvenido de nuevo", "Welcome back") }
    var subtitle: String { pick("Entra con tu cuenta del Market.", "Sign in with your Market account.") }
    var email: String { pick("Correo electrónico", "Email") }
    var phone: String { pick("Celular", "Mobile") }
    var phoneTab: String { pick("Celular", "Mobile") }
    var emailTab: String { pick("Correo", "Email") }
    var password: String { pick("Contraseña", "Password") }
    var forgot: String { pick("¿Olvidaste tu contraseña?", "Forgot your password?") }
    var showPassword: String { pick("Mostrar contraseña", "Show password") }
    var hidePassword: String { pick("Ocultar contraseña", "Hide password") }
    var cancel: String { pick("Cancelar", "Cancel") }
    var invalid: String { pick("Correo/celular o contraseña incorrectos.", "Incorrect email/mobile or password.") }
    var networkError: String { pick("No pudimos conectarnos. Revisa tu conexión e inténtalo de nuevo.", "We couldn't connect. Check your connection and try again.") }
    var needEmail: String { pick("Escribe tu correo para recuperar tu contraseña.", "Enter your email to recover your password.") }
    var resetSent: String { pick("Si el correo existe, te enviamos un enlace para cambiar tu contraseña.", "If the email exists, we sent you a link to reset your password.") }
    var country: String { pick("País", "Country") }
}

enum AuthRoute: Hashable {
    case login
}

/// Bandera a partir del código ISO de dos letras.
func flagEmoji(_ iso: String) -> String {
    iso.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map { String($0) }.joined()
}

/// Pantalla de la pestaña Cuenta sin sesión: invita a entrar.
struct AccountWelcome: View {
    let language: AppLanguage

    var body: some View {
        let text = AuthText(language: language)
        VStack(spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.brandOrange.opacity(0.14))
                    .frame(width: 92, height: 92)
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.brandOrange)
            }
            .padding(.top, 28)
            VStack(spacing: 8) {
                Text(text.welcomeTitle).font(.system(size: 26, weight: .bold))
                Text(text.welcomeBody)
                    .font(.system(size: 16))
                    .foregroundColor(.inkMuted)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 14) {
                benefit("bag", text.benefitOrders)
                benefit("shippingbox", text.benefitTrack)
                benefit("mappin.and.ellipse", text.benefitAddresses)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white))
            NavigationLink(value: AuthRoute.login) {
                Text(text.signIn)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .modifier(PrimaryActionStyle())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func benefit(_ symbol: String, _ label: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.brandOrange)
                .frame(width: 28)
            Text(label).font(.system(size: 16, weight: .medium))
        }
    }
}

/// Inicio de sesión del Market: correo o celular y contraseña. Se abre con
/// botón "atrás" desde Cuenta o como hoja (con "Cancelar") desde el pedido.
struct LoginScreen: View {
    let language: AppLanguage
    var presentedAsSheet = false

    @EnvironmentObject private var session: MarketSession
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case email, phone, password }

    @FocusState private var focus: Field?
    @State private var byPhone = false
    @State private var email = ""
    @State private var country = DialCountry.common[0]
    @State private var phone = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var working = false
    @State private var message: String?
    @State private var info: String?

    var body: some View {
        let text = AuthText(language: language)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(text.title).font(.system(size: 30, weight: .bold))
                    Text(text.subtitle).font(.system(size: 16)).foregroundColor(.inkMuted)
                }
                .padding(.top, 8)

                modePicker(text)

                VStack(spacing: 12) {
                    if byPhone { phoneRow(text) } else { emailField(text) }
                    passwordField(text)
                }

                HStack {
                    Spacer()
                    Button(text.forgot) { Task { await forgotPassword(text) } }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.brandOrange)
                }

                if let message { banner(message, symbol: "exclamationmark.triangle.fill", color: .red) }
                if let info { banner(info, symbol: "checkmark.circle.fill", color: .brandGreen) }

                Button {
                    Task { await submit(text) }
                } label: {
                    Group {
                        if working { ProgressView() } else { Text(text.signIn) }
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
                .modifier(PrimaryActionStyle())
                .disabled(!canSubmit || working)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presentedAsSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text.cancel) { dismiss() }
                }
            }
        }
        .onChange(of: session.isSignedIn) { signedIn in
            if signedIn { dismiss() }
        }
    }

    // MARK: Piezas

    private func modePicker(_ text: AuthText) -> some View {
        HStack(spacing: 4) {
            modeButton(text.emailTab, symbol: "envelope", selected: !byPhone) { byPhone = false }
            modeButton(text.phoneTab, symbol: "phone", selected: byPhone) { byPhone = true }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.gray.opacity(0.14)))
    }

    private func modeButton(_ label: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { action() }
            message = nil
        } label: {
            Label(label, systemImage: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 38)
                .foregroundColor(selected ? .ink : .inkMuted)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(selected ? Color.white : Color.clear)
                        .shadow(color: .black.opacity(selected ? 0.08 : 0), radius: 3, y: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func fieldBox<Content: View>(focused: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) { content() }
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(focused ? Color.brandOrange : Color.black.opacity(0.08), lineWidth: focused ? 2 : 1)
            )
    }

    private func emailField(_ text: AuthText) -> some View {
        fieldBox(focused: focus == .email) {
            Image(systemName: "envelope").foregroundColor(.inkMuted).frame(width: 22)
            TextField(text.email, text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focus, equals: .email)
                .onSubmit { focus = .password }
        }
    }

    private func phoneRow(_ text: AuthText) -> some View {
        fieldBox(focused: focus == .phone) {
            Menu {
                Picker(text.country, selection: $country) {
                    ForEach(DialCountry.common) { option in
                        Text("\(flagEmoji(option.iso2)) \(option.name) \(option.dialCode)").tag(option)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(flagEmoji(country.iso2))
                    Text(country.dialCode).font(.system(size: 16, weight: .medium)).foregroundColor(.ink)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundColor(.inkMuted)
                }
            }
            Divider().frame(height: 24)
            TextField(text.phone, text: $phone)
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
                .focused($focus, equals: .phone)
        }
    }

    private func passwordField(_ text: AuthText) -> some View {
        fieldBox(focused: focus == .password) {
            Image(systemName: "lock").foregroundColor(.inkMuted).frame(width: 22)
            Group {
                if showPassword {
                    TextField(text.password, text: $password)
                } else {
                    SecureField(text.password, text: $password)
                }
            }
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($focus, equals: .password)
            .onSubmit { Task { await submit(text) } }
            Button { showPassword.toggle() } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye").foregroundColor(.inkMuted)
            }
            .accessibilityLabel(showPassword ? text.hidePassword : text.showPassword)
        }
    }

    private func banner(_ message: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundColor(color)
            Text(message).font(.system(size: 14, weight: .medium)).foregroundColor(.ink)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.1)))
        .accessibilityElement(children: .combine)
    }

    // MARK: Acciones

    private var canSubmit: Bool {
        !password.isEmpty && (byPhone ? phone.filter(\.isNumber).count >= 6 : email.contains("@"))
    }

    private func submit(_ text: AuthText) async {
        guard canSubmit, !working else { return }
        focus = nil
        working = true
        message = nil
        info = nil
        defer { working = false }
        do {
            if byPhone {
                try await session.signIn(country: country, phone: phone.filter(\.isNumber), password: password)
            } else {
                try await session.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch MarketSession.LoginError.rejected(let reason) {
            message = reason ?? text.invalid
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        } catch {
            message = text.networkError
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func forgotPassword(_ text: AuthText) async {
        message = nil
        info = nil
        let address = email.trimmingCharacters(in: .whitespaces)
        guard address.contains("@") else {
            // La recuperación llega por correo: se pide el correo primero.
            withAnimation { byPhone = false }
            message = text.needEmail
            focus = .email
            return
        }
        if await session.requestPasswordReset(email: address, language: language) {
            info = text.resetSent
        } else {
            message = text.networkError
        }
    }
}
