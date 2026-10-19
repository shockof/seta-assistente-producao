import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct AssistenteProducaoApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        .modelContainer(for: [ProductionTeam.self, TeamMember.self, TeamMessage.self, TeamExpense.self, ExpenseReceipt.self])
    }
}
