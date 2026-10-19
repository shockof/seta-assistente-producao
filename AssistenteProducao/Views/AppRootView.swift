import SwiftUI
import GoogleSignIn

struct AppRootView: View {
    @AppStorage("isProducerLoggedIn") private var isLoggedIn = false
    @AppStorage("producerName") private var producerName = ""
    @AppStorage("producerEmail") private var producerEmail = ""
    @AppStorage("producerRole") private var producerRole = "Produtor geral"
    @AppStorage("producerPhone") private var producerPhone = ""
    @AppStorage("authProvider") private var authProvider = "local"
    @AppStorage("authCallbackError") private var authCallbackError = ""

    var body: some View {
        Group {
            if isLoggedIn {
                ProducerDashboardView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLoggedIn)
        .preferredColorScheme(.light)
        .onAppear {
            if isLoggedIn && !SupabaseService.shared.hasActiveSession { isLoggedIn = false }
        }
        .onOpenURL { url in
            _ = GIDSignIn.sharedInstance.handle(url)
            guard url.scheme == SupabaseService.authRedirectURL.scheme,
                  url.host == SupabaseService.authRedirectURL.host else { return }
            Task { @MainActor in
                do {
                    guard let user = try await SupabaseService.shared.handleAuthCallback(url) else { return }
                    producerName = user.name.isEmpty ? (user.email.components(separatedBy: "@").first ?? "Produtor") : user.name
                    producerEmail = user.email
                    if let profile = try? await SupabaseService.shared.loadProfile() {
                        producerRole = profile.role
                        producerPhone = profile.phone
                        if !profile.name.isEmpty { producerName = profile.name }
                    }
                    authProvider = "email"
                    authCallbackError = ""
                    isLoggedIn = true
                } catch {
                    authCallbackError = "A confirmação foi concluída, mas não foi possível abrir sua sessão. Entre com seu e-mail e senha."
                }
            }
        }
    }
}
