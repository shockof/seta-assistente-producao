import SwiftUI
import AuthenticationServices
import GoogleSignIn
import GoogleSignInSwift
import CryptoKit

struct LoginView: View {
    @AppStorage("isProducerLoggedIn") private var isLoggedIn = false
    @AppStorage("producerName") private var producerName = ""
    @AppStorage("producerEmail") private var producerEmail = ""
    @AppStorage("producerRole") private var producerRole = "Produtor geral"
    @AppStorage("producerPhone") private var producerPhone = ""
    @AppStorage("authProvider") private var authProvider = "local"
    @AppStorage("appleUserIdentifier") private var appleUserIdentifier = ""
    @AppStorage("authCallbackError") private var authCallbackError = ""
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var selectedRole = "Produtor geral"
    @State private var phoneNumber = ""
    @State private var isCreatingAccount = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.title2).foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 15))
                        Text("Seta").font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(AppTheme.ink)
                    }.padding(.top, 42)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(isCreatingAccount ? "Sua produção,\nem boas mãos." : "Bom ter você\nde volta.")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                        Text(isCreatingAccount ? "Crie seu acesso e organize seu time." : "Entre para acompanhar suas equipes e produções.")
                            .font(.body).foregroundStyle(AppTheme.muted)
                    }.padding(.top, 10)

                    VStack(spacing: 16) {
                        if isCreatingAccount {
                            inputField("Seu nome", icon: "person", text: $name, content: .name)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Função").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                                Picker("Função", selection: $selectedRole) {
                                    ForEach(producerRoles, id: \.self) { role in
                                        Text(role).tag(role)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(15).background(.white, in: RoundedRectangle(cornerRadius: 13))
                            }
                            inputField("WhatsApp / telefone (com DDD)", icon: "phone", text: $phoneNumber, content: .telephoneNumber)
                                .keyboardType(.phonePad)
                        }
                        inputField("E-mail", icon: "envelope", text: $email, content: .emailAddress)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Senha").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                            SecureField("Mínimo de 6 caracteres", text: $password)
                                .padding(15).background(.white, in: RoundedRectangle(cornerRadius: 13))
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                    VStack(spacing: 17) {
                        PrimaryButton(title: isCreatingAccount ? "Criar meu acesso" : "Entrar", icon: "arrow.right") {
                            submit()
                        }
                        HStack(spacing: 12) {
                            Rectangle().fill(AppTheme.muted.opacity(0.2)).frame(height: 1)
                            Text("ou continue com").font(.caption).foregroundStyle(AppTheme.muted).fixedSize()
                            Rectangle().fill(AppTheme.muted.opacity(0.2)).frame(height: 1)
                        }
                        GoogleSignInButton(action: signInWithGoogle)
                            .frame(height: 50)
                        if isAppleSignInEnabled {
                            SignInWithAppleButton(isCreatingAccount ? .signUp : .signIn, onRequest: { request in
                                request.requestedScopes = [.fullName, .email]
                            }, onCompletion: handleAppleSignIn)
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            Label("Entrar com Apple requer uma equipe Apple Developer", systemImage: "apple.logo")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(AppTheme.muted)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        }
                        Button(isCreatingAccount ? "Já tenho uma conta — entrar" : "Criar acesso") {
                            errorMessage = nil
                            isCreatingAccount.toggle()
                        }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                        Text("Acesso local demonstrativo, sem envio de dados.")
                    }
                    .font(.caption).foregroundStyle(AppTheme.muted).padding(.top, 8)
                }
                .padding(.horizontal, 26).padding(.bottom, 32)
                .frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if !authCallbackError.isEmpty {
                errorMessage = authCallbackError
                authCallbackError = ""
            }
        }
    }

    private func inputField(_ title: String, icon: String, text: Binding<String>, content: UITextContentType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(AppTheme.muted)
                TextField(title, text: text).textContentType(content)
            }
            .padding(15).background(.white, in: RoundedRectangle(cornerRadius: 13))
        }
    }

    private var isAppleSignInEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "AppleSignInEnabled") as? String)?.lowercased() == "yes"
    }

    private func submit() {
        guard email.contains("@"), email.contains(".") else {
            errorMessage = "Informe um e-mail válido."
            return
        }
        guard password.count >= 6 else {
            errorMessage = "A senha deve ter pelo menos 6 caracteres."
            return
        }
        Task { @MainActor in
        do {
        if isCreatingAccount {
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                errorMessage = "Informe seu nome."
                return
            }
            let cleanName = name.trimmingCharacters(in: .whitespaces)
            let cleanEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
            guard let user = try await SupabaseService.shared.signUp(email: cleanEmail, password: password,
                    name: cleanName, role: selectedRole, phone: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                errorMessage = "Cadastro enviado. Confirme seu e-mail para liberar o acesso e depois entre no app."
                return
            }
            producerName = user.name.isEmpty ? cleanName : user.name
            producerEmail = user.email.isEmpty ? cleanEmail : user.email
            authProvider = "email"; producerRole = selectedRole
            producerPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let user = try await SupabaseService.shared.signIn(email: email.trimmingCharacters(in: .whitespaces).lowercased(), password: password)
            producerName = user.name.isEmpty ? (user.email.components(separatedBy: "@").first ?? "Produtor") : user.name
            producerEmail = user.email
            let profile = try await SupabaseService.shared.loadProfile()
            if !profile.name.isEmpty { producerName = profile.name }
            producerRole = profile.role; producerPhone = profile.phone
            authProvider = "email"
        }
        isLoggedIn = true
        } catch { errorMessage = error.localizedDescription }
        }
    }

    @MainActor
    private func signInWithGoogle() {
        errorMessage = nil
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.isEmpty,
              !clientID.contains("YOUR_IOS_CLIENT_ID") else {
            errorMessage = "Configure o OAuth Client ID do Google em GoogleOAuth-Info.plist antes de usar este botão."
            return
        }
        guard let presenter = UIApplication.shared.activeRootViewController else {
            errorMessage = "Não foi possível abrir a janela de autenticação do Google."
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let rawNonce = UUID().uuidString
        let hashedNonce = SHA256.hash(data: Data(rawNonce.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil, additionalScopes: nil, nonce: hashedNonce) { result, error in
            Task { @MainActor in
                if let error {
                    let signInError = error as NSError
                    if signInError.domain == kGIDSignInErrorDomain,
                       signInError.code == -5 { // kGIDSignInErrorCodeCanceled
                        errorMessage = nil
                        return
                    }
                    errorMessage = error.localizedDescription
                    return
                }
                guard let profile = result?.user.profile,
                      !profile.email.isEmpty else {
                    errorMessage = "O Google não retornou um endereço de e-mail para esta conta."
                    return
                }
                guard let idToken = result?.user.idToken?.tokenString else {
                    errorMessage = "O Google não retornou o token de autenticação."
                    return
                }
                do {
                let user = try await SupabaseService.shared.signInWithIDToken(provider: "google", idToken: idToken, nonce: rawNonce)
                let googleEmail = user.email.isEmpty ? profile.email : user.email
                producerName = user.name.isEmpty ? (profile.name ?? googleEmail.components(separatedBy: "@").first ?? "Produtor") : user.name
                producerEmail = googleEmail.lowercased()
                if isCreatingAccount {
                    producerRole = selectedRole
                    producerPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                    try await SupabaseService.shared.updateProfile(name: producerName, role: producerRole, phone: producerPhone)
                }
                let savedProfile = try await SupabaseService.shared.loadProfile()
                if !savedProfile.name.isEmpty { producerName = savedProfile.name }
                producerRole = savedProfile.role; producerPhone = savedProfile.phone
                authProvider = "google"
                isLoggedIn = true
                } catch { errorMessage = error.localizedDescription }
            }
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Não foi possível validar a resposta da Apple."
                return
            }
            guard let identityToken = credential.identityToken, let token = String(data: identityToken, encoding: .utf8) else {
                errorMessage = "A Apple não retornou um token de identidade."
                return
            }
            Task { @MainActor in
            do {
            let user = try await SupabaseService.shared.signInWithIDToken(provider: "apple", idToken: token)
            appleUserIdentifier = credential.user
            if let fullName = credential.fullName {
                let formattedName = PersonNameComponentsFormatter().string(from: fullName).trimmingCharacters(in: .whitespacesAndNewlines)
                if !formattedName.isEmpty { producerName = formattedName }
            }
            producerEmail = user.email.isEmpty ? (credential.email ?? producerEmail).lowercased() : user.email
            if producerName.isEmpty { producerName = name.isEmpty ? "Produtor" : name }
            if isCreatingAccount {
                producerRole = selectedRole
                producerPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                try await SupabaseService.shared.updateProfile(name: producerName, role: producerRole, phone: producerPhone)
            }
            let savedProfile = try await SupabaseService.shared.loadProfile()
            if !savedProfile.name.isEmpty { producerName = savedProfile.name }
            producerRole = savedProfile.role; producerPhone = savedProfile.phone
            authProvider = "apple"
            isLoggedIn = true
            } catch { errorMessage = error.localizedDescription }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private let producerRoles = [
        "Produtor geral", "Produtor (a)", "Assistente de produção", "Câmera",
        "Operador de TP", "Assistente de câmera (AC)", "Arte", "Direção",
        "Áudio", "Maquinário", "Gaffer", "Eletricista", "Motorista"
    ]
}

private extension UIApplication {
    var activeRootViewController: UIViewController? {
        let windowScene = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return windowScene?.windows.first(where: \.isKeyWindow)?.rootViewController
    }
}
