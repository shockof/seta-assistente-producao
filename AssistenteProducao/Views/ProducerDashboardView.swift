import SwiftUI
import SwiftData
import GoogleSignIn

struct ProducerDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProductionTeam.createdAt, order: .reverse) private var teams: [ProductionTeam]
    @AppStorage("producerName") private var producerName = "Produtor"
    @AppStorage("producerRole") private var producerRole = "Produtor geral"
    @AppStorage("isProducerLoggedIn") private var isLoggedIn = false
    @AppStorage("authProvider") private var authProvider = "local"
    @State private var showingCreateTeam = false
    @State private var showingProfile = false
    @State private var syncError: String?

    private var firstName: String { producerName.split(separator: " ").first.map(String.init) ?? "Produtor" }
    private var memberCount: Int { teams.reduce(0) { $0 + $1.members.count } }
    private var isGeneralProducer: Bool {
        producerRole.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Produtor geral") == .orderedSame
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        header
                        if let syncError { Text(syncError).font(.caption).foregroundStyle(.red) }
                        welcome
                        summaryCards
                        if isGeneralProducer {
                            NavigationLink {
                                ExpenseControlView()
                            } label: {
                                FinanceAccessCard(
                                    title: "Controle de prestação de contas",
                                    subtitle: "Verbas, despesas e comprovantes por produtor",
                                    icon: "doc.text.magnifyingglass"
                                )
                            }.buttonStyle(.plain)
                        } else {
                            NavigationLink {
                                TeamProducerExpensesHomeView()
                            } label: {
                                FinanceAccessCard(
                                    title: "Minha prestação de contas",
                                    subtitle: "Registrar pagamentos e enviar comprovantes",
                                    icon: "receipt"
                                )
                            }.buttonStyle(.plain)
                        }
                        HStack {
                            SectionHeading(title: "Suas equipes", trailing: teams.isEmpty ? nil : "\(teams.count) no total")
                            Spacer()
                            Button { showingCreateTeam = true } label: {
                                Image(systemName: "plus").font(.headline.weight(.bold))
                                    .foregroundStyle(.white).frame(width: 40, height: 40)
                                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 13))
                            }.accessibilityLabel("Criar equipe")
                        }
                        if teams.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(teams) { team in
                                    NavigationLink {
                                        TeamDetailView(team: team)
                                    } label: {
                                        TeamRow(team: team)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }.padding(EdgeInsets(top: 22, leading: 22, bottom: 46, trailing: 22))
                    .frame(maxWidth: 650).frame(maxWidth: .infinity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await synchronizeRemoteTeams() }
            .sheet(isPresented: $showingCreateTeam) {
                TeamFormView()
            }
            .sheet(isPresented: $showingProfile) {
                ProducerProfileView(onSignOut: signOut)
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 9) {
                Image(systemName: "sparkles.rectangle.stack.fill").foregroundStyle(AppTheme.accent)
                Text("SETA").font(.caption.weight(.heavy)).tracking(2).foregroundStyle(AppTheme.ink)
            }
            Spacer()
            Button {
                showingProfile = true
            } label: {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 31)).foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir perfil")
        }.padding(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
    }

    private func signOut() {
        Task { await SupabaseService.shared.signOut() }
        if authProvider == "google" {
            GIDSignIn.sharedInstance.signOut()
        }
        isLoggedIn = false
    }

    @MainActor
    private func synchronizeRemoteTeams() async {
        guard isLoggedIn else { return }
        syncError = nil
        do {
            let rows = try await SupabaseService.shared.fetchTeams()
            for row in rows {
                guard let idText = row["id"] as? String, let remoteID = UUID(uuidString: idText) else { continue }
                let team = teams.first(where: { $0.remoteID == remoteID }) ?? {
                    let created = ProductionTeam(name: row["name"] as? String ?? "Equipe",
                                                teamDescription: row["description"] as? String ?? "")
                    created.remoteID = remoteID
                    modelContext.insert(created)
                    return created
                }()
                team.name = row["name"] as? String ?? team.name
                team.teamDescription = row["description"] as? String ?? team.teamDescription
                team.createdAt = parseRemoteDate(row["created_at"] as? String) ?? team.createdAt

                let remoteMembers = row["team_members"] as? [[String: Any]] ?? []
                for memberRow in remoteMembers where (memberRow["is_active"] as? Bool ?? true) {
                    guard let memberIDText = memberRow["id"] as? String, let memberID = UUID(uuidString: memberIDText) else { continue }
                    let member = team.members.first(where: { $0.remoteID == memberID }) ?? {
                        let created = TeamMember(name: memberRow["full_name"] as? String ?? "Integrante",
                            email: memberRow["email"] as? String ?? "",
                            phoneNumber: memberRow["phone_number"] as? String,
                            role: memberRow["role"] as? String ?? "", team: team)
                        created.remoteID = memberID
                        modelContext.insert(created); team.members.append(created)
                        return created
                    }()
                    member.name = memberRow["full_name"] as? String ?? member.name
                    member.email = memberRow["email"] as? String ?? member.email
                    member.phoneNumber = memberRow["phone_number"] as? String ?? member.phoneNumber
                    member.role = memberRow["role"] as? String ?? member.role
                    member.releasedBudget = (memberRow["released_budget"] as? NSNumber)?.doubleValue ?? member.releasedBudget

                    for expenseRow in memberRow["expenses"] as? [[String: Any]] ?? [] {
                        guard let expenseIDText = expenseRow["id"] as? String, let expenseID = UUID(uuidString: expenseIDText) else { continue }
                        if !member.expenses.contains(where: { $0.remoteID == expenseID }) {
                            let expense = TeamExpense(descriptionText: expenseRow["description"] as? String ?? "",
                                amount: (expenseRow["amount"] as? NSNumber)?.doubleValue ?? 0,
                                producerName: member.name, producerEmail: member.email ?? "", producer: member)
                            expense.remoteID = expenseID
                            expense.createdAt = parseRemoteDate(expenseRow["created_at"] as? String) ?? .now
                            modelContext.insert(expense); member.expenses.append(expense)
                            for receiptRow in expenseRow["expense_receipts"] as? [[String: Any]] ?? [] {
                                guard let path = receiptRow["storage_path"] as? String,
                                      !expense.receipts.contains(where: { $0.remotePath == path }) else { continue }
                                do {
                                    let image = try await SupabaseService.shared.downloadReceipt(path: path)
                                    let receipt = ExpenseReceipt(imageData: image, fileName: receiptRow["file_name"] as? String ?? "Comprovante", expense: expense)
                                    receipt.remotePath = path; modelContext.insert(receipt); expense.receipts.append(receipt)
                                } catch { syncError = "Alguns comprovantes não puderam ser baixados." }
                            }
                        }
                    }
                }

                for messageRow in row["team_messages"] as? [[String: Any]] ?? [] {
                    guard let messageIDText = messageRow["id"] as? String, let messageID = UUID(uuidString: messageIDText),
                          !team.messages.contains(where: { $0.remoteID == messageID }) else { continue }
                    let message = TeamMessage(text: messageRow["body"] as? String ?? "",
                        senderName: messageRow["author_name"] as? String ?? "Integrante",
                        sentAt: parseRemoteDate(messageRow["created_at"] as? String) ?? .now, team: team)
                    message.remoteID = messageID; modelContext.insert(message); team.messages.append(message)
                }
            }
        } catch { syncError = "Não foi possível sincronizar com o servidor: \(error.localizedDescription)" }
    }

    private func parseRemoteDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Olá, \(firstName) 👋").font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(AppTheme.ink)
            Text("\(producerRole) · Vamos colocar sua próxima produção em movimento.")
                .font(.subheadline).foregroundStyle(AppTheme.muted)
        }.padding(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            SummaryCard(value: "\(teams.count)", title: "Equipes", icon: "person.3.fill", tint: AppTheme.accent)
            SummaryCard(value: "\(memberCount)", title: "Integrantes", icon: "person.2.fill", tint: AppTheme.mint)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.3.sequence.fill").font(.system(size: 32)).foregroundStyle(AppTheme.accent)
                .frame(width: 68, height: 68).background(AppTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 22))
            Text("Sua primeira equipe começa aqui").font(.headline).foregroundStyle(AppTheme.ink)
            Text("Reúna as pessoas certas e defina as funções de cada integrante.")
                .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(AppTheme.muted)
            PrimaryButton(title: "Criar equipe", icon: "plus") { showingCreateTeam = true }
                .padding(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
        }
        .padding(22).frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct ProducerProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("producerName") private var producerName = "Produtor"
    @AppStorage("producerEmail") private var producerEmail = ""
    @AppStorage("producerRole") private var producerRole = "Produtor geral"
    @AppStorage("producerPhone") private var producerPhone = ""
    @State private var editedPhone = ""
    @State private var editedRole = "Produtor geral"
    @State private var saveError: String?
    @State private var isSaving = false

    let onSignOut: () -> Void

    private let roles = [
        "Produtor geral", "Produtor (a)", "Assistente de produção", "Câmera",
        "Operador de TP", "Assistente de câmera (AC)", "Arte", "Direção",
        "Áudio", "Maquinário", "Gaffer", "Eletricista", "Motorista"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(spacing: 15) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 56)).foregroundStyle(AppTheme.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(producerName).font(.title3.bold()).foregroundStyle(AppTheme.ink)
                                Text(producerEmail).font(.subheadline).foregroundStyle(AppTheme.muted)
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Função").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                            Picker("Função", selection: $editedRole) {
                                ForEach(roles, id: \.self) { role in
                                    Text(role).tag(role)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(15)
                            .background(.white, in: RoundedRectangle(cornerRadius: 13))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Telefone / WhatsApp").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                            HStack(spacing: 10) {
                                Image(systemName: "phone").foregroundStyle(AppTheme.muted)
                                TextField("Adicionar telefone com DDD", text: $editedPhone)
                                    .keyboardType(.phonePad)
                                    .textContentType(.telephoneNumber)
                            }
                            .padding(15)
                            .background(.white, in: RoundedRectangle(cornerRadius: 13))
                            Text("Use o número com DDD para facilitar o contato pelo WhatsApp.")
                                .font(.caption).foregroundStyle(AppTheme.muted)
                        }

                        if let saveError {
                            Text(saveError).font(.footnote).foregroundStyle(.red)
                        }

                        Button(role: .destructive) {
                            dismiss()
                            onSignOut()
                        } label: {
                            Label("Sair da conta", systemImage: "rectangle.portrait.and.arrow.right")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(.white, in: RoundedRectangle(cornerRadius: 13))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                    .padding(22)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Meu perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Salvando…" : "Salvar") {
                        isSaving = true
                        Task { @MainActor in
                            let phone = editedPhone.trimmingCharacters(in: .whitespacesAndNewlines)
                            do {
                                try await SupabaseService.shared.updateProfile(name: producerName, role: editedRole, phone: phone)
                                producerPhone = phone; producerRole = editedRole; dismiss()
                            } catch { saveError = error.localizedDescription; isSaving = false }
                        }
                    }
                    .fontWeight(.semibold).disabled(isSaving)
                }
            }
            .onAppear {
                editedPhone = producerPhone
                editedRole = roles.contains(producerRole) ? producerRole : roles[0]
            }
        }
        .preferredColorScheme(.light)
    }
}

private struct SummaryCard: View {
    let value: String
    let title: String
    let icon: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Image(systemName: icon).font(.headline).foregroundStyle(tint)
                .frame(width: 38, height: 38).background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            Text(value).font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(AppTheme.ink)
            Text(title).font(.caption.weight(.medium)).foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }
}
