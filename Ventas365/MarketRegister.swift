import SwiftUI

private struct RegisterText {
    let language: AppLanguage
    private func pick(_ es: String, _ en: String) -> String { language == .es ? es : en }

    var title: String { pick("Crea tu cuenta", "Create your account") }
    var subtitle: String { pick("Para pedir, seguir tus pedidos y guardar tus favoritos.", "To order, track your orders and save your favorites.") }
    var fullName: String { pick("Nombre completo", "Full name") }
    var document: String { pick("Número de documento", "ID number") }
    var country: String { pick("País", "Country") }
    var phone: String { pick("Celular", "Mobile") }
    var email: String { pick("Correo electrónico", "Email") }
    var department: String { pick("Departamento / estado", "State / department") }
    var city: String { pick("Ciudad", "City") }
    var address: String { pick("Dirección de entrega", "Delivery address") }
    var optional: String { pick("(opcional)", "(optional)") }
    var password: String { pick("Contraseña (mínimo 8 caracteres)", "Password (at least 8 characters)") }
    var confirm: String { pick("Repite la contraseña", "Repeat password") }
    var next: String { pick("Continuar", "Continue") }
    var create: String { pick("Crear cuenta", "Create account") }
    var haveAccount: String { pick("¿Ya tienes cuenta? Inicia sesión", "Already have an account? Sign in") }
    var privacy: String { pick("Al crear tu cuenta aceptas la política de privacidad.", "By creating your account you accept the privacy policy.") }
    var privacyLink: String { pick("Ver política de privacidad", "View privacy policy") }
    var codeTitle: String { pick("Confirma tu correo", "Confirm your email") }
    func codeBody(_ email: String) -> String { pick("Te enviamos un código de 4 dígitos a \(email). Vence en 5 minutos.", "We sent a 4-digit code to \(email). It expires in 5 minutes.") }
    var code: String { pick("Código", "Code") }
    var resend: String { pick("Reenviar código", "Resend code") }
    var resent: String { pick("Te enviamos un código nuevo.", "We sent you a new code.") }
    var back: String { pick("Cambiar mis datos", "Edit my details") }
    var network: String { pick("No pudimos conectarnos. Revisa tu conexión e inténtalo de nuevo.", "We couldn't connect. Check your connection and try again.") }
    var required: String { pick("Completa nombre, documento, celular, correo y contraseña.", "Fill in name, ID number, mobile, email and password.") }
    var invalidEmail: String { pick("Ingresa un correo válido.", "Enter a valid email.") }
    var shortPassword: String { pick("La contraseña debe tener al menos 8 caracteres.", "The password must be at least 8 characters.") }
    var mismatch: String { pick("Las contraseñas no coinciden.", "The passwords don't match.") }
    var docTaken: String { pick("Ya existe una cuenta con ese documento.", "An account with that ID number already exists.") }
    var phoneTaken: String { pick("Ya existe una cuenta con ese celular.", "An account with that mobile already exists.") }
    var emailTaken: String { pick("Ya existe una cuenta con ese correo.", "An account with that email already exists.") }

    func message(_ raw: String) -> String { raw == "network" ? network : raw }
}

private enum RegisterStep { case form, code }

/// Registro de un cliente nuevo del Market: datos → código por correo → cuenta creada.
struct RegisterScreen: View {
    let language: AppLanguage

    @EnvironmentObject private var session: MarketSession
    @Environment(\.dismiss) private var dismiss

    @State private var step = RegisterStep.form
    @State private var data = RegisterData()
    @State private var country = DialCountry.all[0]
    @State private var repeatPassword = ""
    @State private var showPassword = false
    @State private var code = ""
    @State private var working = false
    @State private var message: String?
    @State private var info: String?

    var body: some View {
        let text = RegisterText(language: language)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch step {
                case .form: form(text)
                case .code: codeStep(text)
                }
                if let message { banner(message, symbol: "exclamationmark.triangle.fill", color: .red) }
                if let info { banner(info, symbol: "checkmark.circle.fill", color: .brandGreen) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: session.isSignedIn) { signedIn in
            if signedIn { dismiss() }
        }
    }

    // MARK: Paso 1: datos

    private func form(_ text: RegisterText) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(text.title).font(.system(size: 30, weight: .bold))
                Text(text.subtitle).font(.system(size: 16)).foregroundColor(.inkMuted)
            }
            .padding(.top, 8)

            field(text.fullName, "person") {
                TextField(text.fullName, text: $data.fullName)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
            }
            field(text.document, "person.text.rectangle") {
                TextField(text.document, text: $data.documentNumber)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
            }
            field(text.phone, "phone") {
                Menu {
                    Picker(text.country, selection: $country) {
                        ForEach(DialCountry.all) { option in
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
                TextField(text.phone, text: $data.phone)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .onChange(of: data.phone) { value in
                        let digits = String(value.filter(\.isNumber).prefix(15))
                        if digits != value { data.phone = digits }
                    }
            }
            field(text.email, "envelope") {
                TextField(text.email, text: $data.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            field("\(text.department) \(text.optional)", "map") {
                TextField("\(text.department) \(text.optional)", text: $data.department)
            }
            field("\(text.city) \(text.optional)", "building.2") {
                TextField("\(text.city) \(text.optional)", text: $data.city)
            }
            field("\(text.address) \(text.optional)", "mappin.and.ellipse") {
                TextField("\(text.address) \(text.optional)", text: $data.address)
                    .textContentType(.fullStreetAddress)
            }
            field(text.password, "lock") {
                Group {
                    if showPassword {
                        TextField(text.password, text: $data.password)
                    } else {
                        SecureField(text.password, text: $data.password)
                    }
                }
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye").foregroundColor(.inkMuted)
                }
            }
            field(text.confirm, "lock.rotation") {
                SecureField(text.confirm, text: $repeatPassword)
                    .textContentType(.newPassword)
                    .textInputAutocapitalization(.never)
            }

            primaryButton(text.next) { Task { await continueToCode(text) } }
            VStack(spacing: 4) {
                Text(text.privacy).font(.system(size: 13)).foregroundColor(.inkMuted).multilineTextAlignment(.center)
                if let url = URL(string: "https://ventas365.app/privacidad") {
                    Link(text.privacyLink, destination: url).font(.system(size: 13, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            Button(text.haveAccount) { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.brandOrange)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Paso 2: código

    private func codeStep(_ text: RegisterText) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(text.codeTitle).font(.system(size: 30, weight: .bold))
                Text(text.codeBody(data.email)).font(.system(size: 16)).foregroundColor(.inkMuted)
            }
            .padding(.top, 8)
            field(text.code, "number") {
                TextField(text.code, text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .onChange(of: code) { value in
                        let digits = String(value.filter(\.isNumber).prefix(4))
                        if digits != value { code = digits }
                    }
            }
            primaryButton(text.create) { Task { await createAccount(text) } }
                .disabled(code.count != 4)
            Button(text.resend) { Task { await sendCode(text, resend: true) } }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.brandOrange)
                .frame(maxWidth: .infinity)
                .disabled(working)
            Button(text.back) {
                message = nil
                info = nil
                code = ""
                step = .form
            }
            .font(.system(size: 15))
            .foregroundColor(.inkMuted)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Piezas

    private func field<Content: View>(_ label: String, _ symbol: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundColor(.inkMuted).frame(width: 22)
            content()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.black.opacity(0.08), lineWidth: 1))
        .accessibilityLabel(label)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if working { ProgressView() } else { Text(title) }
            }
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 28)
        }
        .modifier(PrimaryActionStyle())
        .disabled(working)
    }

    private func banner(_ message: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundColor(color)
            Text(message).font(.system(size: 14, weight: .medium)).foregroundColor(.ink)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.1)))
    }

    // MARK: Acciones

    private func continueToCode(_ text: RegisterText) async {
        message = nil
        info = nil
        data.fullName = data.fullName.trimmingCharacters(in: .whitespaces)
        data.documentNumber = data.documentNumber.trimmingCharacters(in: .whitespaces)
        data.email = data.email.trimmingCharacters(in: .whitespaces)
        data.countryIso = country.iso2
        guard !data.fullName.isEmpty, !data.documentNumber.isEmpty, data.phone.count >= 6, !data.email.isEmpty, !data.password.isEmpty else {
            message = text.required
            return
        }
        guard data.email.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil else {
            message = text.invalidEmail
            return
        }
        guard data.password.trimmingCharacters(in: .whitespaces).count >= 8 else {
            message = text.shortPassword
            return
        }
        guard data.password == repeatPassword else {
            message = text.mismatch
            return
        }
        working = true
        defer { working = false }
        async let document = session.exists(field: "documentNumber", value: data.documentNumber)
        async let phone = session.exists(field: "phone", value: data.phone, countryIso: data.countryIso)
        async let email = session.exists(field: "email", value: data.email)
        let (hasDocument, hasPhone, hasEmail) = await (document, phone, email)
        if hasDocument { message = text.docTaken; return }
        if hasPhone { message = text.phoneTaken; return }
        if hasEmail { message = text.emailTaken; return }
        await sendCode(text, resend: false)
    }

    private func sendCode(_ text: RegisterText, resend: Bool) async {
        working = true
        message = nil
        info = nil
        defer { working = false }
        if let error = await session.requestRegistrationCode(email: data.email, language: language) {
            message = text.message(error)
            return
        }
        if resend { info = text.resent } else { step = .code }
    }

    private func createAccount(_ text: RegisterText) async {
        working = true
        message = nil
        info = nil
        defer { working = false }
        if let error = await session.verifyRegistrationCode(email: data.email, code: code) {
            message = text.message(error)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        do {
            try await session.register(data)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch let error as MarketSession.RegisterError {
            // El código ya se consumió: si algo falla ahora, se vuelve a los datos.
            message = text.message(error.message)
            code = ""
            step = .form
        } catch {
            message = text.network
        }
    }
}
