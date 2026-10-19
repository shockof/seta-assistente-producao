import SwiftUI
import SwiftData
import Contacts
import ContactsUI

struct TeamRow: View {
    let team: ProductionTeam
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.3.fill").font(.headline).foregroundStyle(AppTheme.accent)
                .frame(width: 48, height: 48).background(AppTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 5) {
                Text(team.name).font(.headline).foregroundStyle(AppTheme.ink)
                Text(team.teamDescription.isEmpty ? "Sem descrição" : team.teamDescription)
                    .font(.caption).foregroundStyle(AppTheme.muted).lineLimit(1)
            }
            Spacer()
            Text("\(team.members.count)").font(.subheadline.weight(.bold)).foregroundStyle(AppTheme.ink)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(AppTheme.muted)
        }
        .padding(15).background(.white, in: RoundedRectangle(cornerRadius: 17))
    }
}

struct TeamFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var details = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Sobre a equipe") {
                    TextField("Nome da equipe", text: $name)
                    TextField("Descrição (opcional)", text: $details, axis: .vertical).lineLimit(2...4)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                Section {
                    Text("Você poderá adicionar integrantes e definir suas funções depois de criar a equipe.")
                        .font(.footnote).foregroundStyle(AppTheme.muted)
                }
            }
            .navigationTitle("Nova equipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Salvando…" : "Criar") { save() }.fontWeight(.semibold).disabled(isSaving)
                }
            }
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { errorMessage = "Digite um nome para a equipe."; return }
        isSaving = true
        Task { @MainActor in
            do {
                let cleanDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
                let remoteID = try await SupabaseService.shared.createTeam(name: cleanName, description: cleanDetails)
                let team = ProductionTeam(name: cleanName, teamDescription: cleanDetails)
                team.remoteID = remoteID
                modelContext.insert(team)
                dismiss()
            } catch { errorMessage = error.localizedDescription; isSaving = false }
        }
    }
}

struct TeamDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddMember = false
    @State private var showingEditTeam = false
    @State private var memberToRemove: TeamMember?
    @State private var actionError: String?
    let team: ProductionTeam

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(team.name).font(.title2.bold()).foregroundStyle(AppTheme.ink)
                    Text(team.teamDescription.isEmpty ? "Adicione uma descrição para esta equipe." : team.teamDescription)
                        .font(.subheadline).foregroundStyle(AppTheme.muted)
                }.padding(.vertical, 8)
            }
            Section {
                NavigationLink {
                    TeamChatView(team: team)
                } label: {
                    Label("Chat da equipe", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.headline).foregroundStyle(AppTheme.accent)
                }
            }
            Section {
                if team.members.isEmpty {
                    ContentUnavailableView("Nenhum integrante", systemImage: "person.crop.circle.badge.plus", description: Text("Adicione pessoas e defina suas funções."))
                } else {
                    ForEach(team.members) { member in
                        HStack(spacing: 12) {
                            Image(systemName: "person.fill").foregroundStyle(AppTheme.accent)
                                .frame(width: 38, height: 38).background(AppTheme.accent.opacity(0.09), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(member.name).font(.subheadline.weight(.semibold))
                                Text(member.email.map { "\(member.role) · \($0)" } ?? member.role)
                                    .font(.caption).foregroundStyle(AppTheme.muted)
                            }
                            Spacer()
                            if let phone = member.phoneNumber {
                                let digits = phone.filter { $0.isNumber }
                                if digits.count >= 8, let whatsappURL = URL(string: "https://wa.me/\(digits)") {
                                    Link(destination: whatsappURL) {
                                        Image(systemName: "message.fill").foregroundStyle(AppTheme.mint)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Conversar com \(member.name) no WhatsApp")
                                }
                            }
                            Button(role: .destructive) { memberToRemove = member } label: {
                                Image(systemName: "minus.circle").font(.title3)
                            }.buttonStyle(.borderless).accessibilityLabel("Remover \(member.name)")
                        }.padding(.vertical, 3)
                    }
                }
            } header: {
                HStack {
                    Text("Integrantes · \(team.members.count)")
                    Spacer()
                    Button { showingAddMember = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                        .accessibilityLabel("Adicionar integrante")
                }
            }
        }
        .navigationTitle("Equipe")
        .alert("Não foi possível sincronizar", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Editar equipe", systemImage: "pencil") { showingEditTeam = true }
                    Button("Excluir equipe", systemImage: "trash", role: .destructive) { deleteTeam() }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showingAddMember) { AddMemberView(team: team) }
        .sheet(isPresented: $showingEditTeam) { EditTeamView(team: team) }
        .confirmationDialog("Remover integrante?", isPresented: Binding(
            get: { memberToRemove != nil },
            set: { if !$0 { memberToRemove = nil } }
        ), titleVisibility: .visible) {
            Button("Remover", role: .destructive) { removeMember() }
            Button("Cancelar", role: .cancel) { memberToRemove = nil }
        } message: {
            Text("O integrante será removido desta equipe.")
        }
    }

    private func removeMember() {
        guard let memberToRemove else { return }
        let member = memberToRemove
        Task { @MainActor in
            do {
                if let remoteID = member.remoteID { try await SupabaseService.shared.deactivateMember(memberID: remoteID) }
                modelContext.delete(member)
            } catch { actionError = error.localizedDescription }
        }
        self.memberToRemove = nil
    }

    private func deleteTeam() {
        modelContext.delete(team)
    }
}

struct TeamChatView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("producerName") private var producerName = "Produtor"
    @State private var draft = ""
    let team: ProductionTeam

    private var sortedMessages: [TeamMessage] {
        team.messages.sorted { $0.sentAt < $1.sentAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            if sortedMessages.isEmpty {
                ContentUnavailableView(
                    "Conversa começando",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("As mensagens desta equipe aparecerão aqui.")
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(sortedMessages) { message in
                            messageBubble(message)
                        }
                    }
                    .padding(16)
                }
            }
            composer
        }
        .background(AppTheme.canvas)
        .navigationTitle("Chat da equipe")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func messageBubble(_ message: TeamMessage) -> some View {
        let isOwnMessage = message.senderName == producerName
        return HStack {
            if isOwnMessage { Spacer(minLength: 44) }
            VStack(alignment: .leading, spacing: 5) {
                if !isOwnMessage {
                    Text(message.senderName).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
                }
                Text(message.text).font(.body).foregroundStyle(isOwnMessage ? .white : AppTheme.ink)
                Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(isOwnMessage ? .white.opacity(0.75) : AppTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(isOwnMessage ? AppTheme.accent : .white, in: RoundedRectangle(cornerRadius: 17))
            if !isOwnMessage { Spacer(minLength: 44) }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Mensagem para a equipe", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)).foregroundStyle(AppTheme.accent)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Enviar mensagem")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func sendMessage() {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        guard let remoteID = team.remoteID else { return }
        Task { @MainActor in
            do {
                let remoteMessageID = try await SupabaseService.shared.sendMessage(teamID: remoteID, authorName: producerName, body: content)
                let message = TeamMessage(text: content, senderName: producerName)
                message.remoteID = remoteMessageID
                modelContext.insert(message); team.messages.append(message); draft = ""
            } catch { draft = content }
        }
    }
}

struct AddMemberView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let team: ProductionTeam
    @State private var entryMethod = MemberEntryMethod.email
    @State private var name = ""
    @State private var email = ""
    @State private var phoneNumber = ""
    @State private var role = ""
    @State private var errorMessage: String?
    @State private var showingContacts = false
    @State private var isSaving = false
    private let suggestedRoles = ["Produtor (a)", "Assistente de produção", "Produção", "Direção", "Câmera", "Som", "Arte", "Edição"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Forma de adicionar", selection: $entryMethod) {
                        ForEach(MemberEntryMethod.allCases) { method in
                            Text(method.title).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Dados do integrante") {
                    if entryMethod == .contacts {
                        Button {
                            showingContacts = true
                        } label: {
                            Label(name.isEmpty ? "Escolher dos Contatos" : "Trocar contato", systemImage: "person.crop.circle.badge.plus")
                        }
                        if !name.isEmpty {
                            LabeledContent("Nome", value: name)
                        }
                    } else {
                        TextField("Nome", text: $name).textContentType(.name)
                    }
                    TextField("E-mail", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("WhatsApp / telefone (com DDI)", text: $phoneNumber)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Função", text: $role)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(suggestedRoles, id: \.self) { suggestion in
                                Button(suggestion) { role = suggestion }
                                    .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(AppTheme.accent.opacity(0.1), in: Capsule())
                            }
                        }.padding(.vertical, 3)
                    }
                }
                Section {
                    Text(entryMethod == .email
                         ? "Use o e-mail associado à conta da pessoa no Seta."
                         : "Escolha um contato e confirme o e-mail usado na conta Seta.")
                        .font(.footnote).foregroundStyle(AppTheme.muted)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("Novo integrante")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: entryMethod) { _, method in
                errorMessage = nil
                if method == .email { name = "" }
            }
            .sheet(isPresented: $showingContacts) {
                SystemContactPicker { contact in
                    guard let contact else { return }
                    name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
                    email = contact.emailAddresses.first.map { String($0.value) } ?? ""
                    phoneNumber = contact.phoneNumbers.first?.value.stringValue ?? ""
                    if email.isEmpty {
                        errorMessage = "Esse contato não tem um e-mail salvo. Digite o e-mail da conta Seta."
                    } else {
                        errorMessage = nil
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(isSaving ? "Salvando…" : "Adicionar") { save() }.fontWeight(.semibold).disabled(isSaving) }
            }
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { errorMessage = "Digite o nome do integrante."; return }
        guard cleanEmail.contains("@"), cleanEmail.split(separator: "@").last?.contains(".") == true else {
            errorMessage = "Digite um e-mail válido da conta Seta."; return
        }
        guard !cleanRole.isEmpty else { errorMessage = "Informe a função do integrante."; return }
        guard !team.members.contains(where: { $0.email?.lowercased() == cleanEmail }) else {
            errorMessage = "Esse e-mail já está nesta equipe."; return
        }
        isSaving = true
        Task { @MainActor in
            do {
                let teamID: UUID
                if let remoteID = team.remoteID {
                    teamID = remoteID
                } else {
                    teamID = try await SupabaseService.shared.linkOrCreateTeam(
                        name: team.name,
                        description: team.teamDescription
                    )
                    team.remoteID = teamID
                    try modelContext.save()
                }
                let remoteID = try await SupabaseService.shared.addMember(teamID: teamID, email: cleanEmail, name: cleanName, phone: cleanPhone, role: cleanRole)
                let member = TeamMember(name: cleanName, email: cleanEmail, phoneNumber: cleanPhone.isEmpty ? nil : cleanPhone, role: cleanRole)
                member.remoteID = remoteID
                modelContext.insert(member); team.members.append(member); dismiss()
            } catch { errorMessage = error.localizedDescription; isSaving = false }
        }
    }
}

private enum MemberEntryMethod: String, CaseIterable, Identifiable {
    case email
    case contacts

    var id: Self { self }
    var title: String { self == .email ? "Por e-mail" : "Contatos" }
}

private struct SystemContactPicker: UIViewControllerRepresentable {
    let onSelect: (CNContact?) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactEmailAddressesKey, CNContactPhoneNumbersKey]
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: (CNContact?) -> Void

        init(onSelect: @escaping (CNContact?) -> Void) {
            self.onSelect = onSelect
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onSelect(contact)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onSelect(nil)
        }
    }
}

struct EditTeamView: View {
    @Environment(\.dismiss) private var dismiss
    let team: ProductionTeam
    @State private var name: String
    @State private var details: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(team: ProductionTeam) {
        self.team = team
        _name = State(initialValue: team.name)
        _details = State(initialValue: team.teamDescription)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sobre a equipe") {
                    TextField("Nome", text: $name)
                    TextField("Descrição", text: $details, axis: .vertical).lineLimit(2...4)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("Editar equipe").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(isSaving ? "Salvando…" : "Salvar") { save() }.fontWeight(.semibold).disabled(isSaving) }
            }
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { errorMessage = "Digite um nome para a equipe."; return }
        let cleanDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let remoteID = team.remoteID else { errorMessage = "Equipe sem vínculo remoto."; return }
        isSaving = true
        Task { @MainActor in
            do {
                try await SupabaseService.shared.updateTeam(id: remoteID, name: cleanName, description: cleanDetails)
                team.name = cleanName; team.teamDescription = cleanDetails; dismiss()
            } catch { errorMessage = error.localizedDescription; isSaving = false }
        }
    }
}
