Warning: truncated output (original token count: 6006)
Total output lines: 530

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct FinanceAccessCard: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(AppTheme.ink)
                Text(subtitle).font(.caption).foregroundStyle(AppTheme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(AppTheme.muted)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct ExpenseControlView: View {
    @Query(sort: \ProductionTeam.createdAt, order: .reverse) private var teams: [ProductionTeam]
    @State private var memberForBudget: TeamMember?

    private var producers: [TeamMember] {
        teams.flatMap(\.members).filter { isTeamProducerRole($0.role) }
    }

    private var totalReleased: Double { producers.reduce(0) { $0 + $1.releasedBudget } }
    private var totalSpent: Double { producers.reduce(0) { total, member in total + member.expenses.reduce(0) { $0 + $1.amount } } }

    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Prestação de contas").font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(AppTheme.ink)
                        Text("Acompanhe as verbas, despesas e comprovantes dos produtores.").font(.subheadline).foregroundStyle(AppTheme.muted)
                    }

                    HStack(spacing: 12) {
                        FinanceSummaryCard(title: "Liberado", amount: totalReleased, tint: AppTheme.accent)
                        FinanceSummaryCard(title: "Utilizado", amount: totalSpent, tint: AppTheme.mint)
                    }

                    if producers.isEmpty {
                        ContentUnavailableView("Nenhum produtor cadastrado", systemImage: "person.2", description: Text("Adicione integrantes com a função Produtor (a) às equipes para controlar a verba e as despesas."))
                            .padding(.top, 28)
                    } else {
                        ForEach(teams) { team in
                            let teamProducers = team.members.filter { isTeamProducerRole($0.role) }
                            if !teamProducers.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    SectionHeading(title: team.name, trailing: "\(teamProducers.count) produtores")
                                    ForEach(teamProducers) { member in
                                        producerCard(member)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Controle de verba")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $memberForBudget) { member in
            BudgetEditorView(member: member)
        }
    }

    private func producerCard(_ member: TeamMember) -> some View {
        VStack(spacing: 12) {
            NavigationLink {
                TeamExpenseReportView(member: member, allowsSubmission: false)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 38)).foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(member.name).font(.headline).foregroundStyle(AppTheme.ink)
                        Text(member.email ?? "Sem e-mail cadastrado").font(.caption).foregroundStyle(AppTheme.muted)
                        Text("\(member.expenses.count) despesas · Saldo \(money(member.releasedBudget - spent(by: member)))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(member.releasedBudget - spent(by: member) < 0 ? .red : AppTheme.mint)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(AppTheme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack {
                Text("Verba: \(money(member.releasedBudget))")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                Spacer()
                Button { memberForBudget = member } label: {
                    Label("Definir verba", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accent)
            }
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private func spent(by member: TeamMember) -> Double {
        member.expenses.reduce(0) { $0 + $1.amount }
    }

}

struct TeamProducerExpensesHomeView: View {
    @Query(sort: \ProductionTeam.createdAt, order: .reverse) private var teams: [ProductionTeam]
    @AppStorage("producerEmail") private var producerEmail = ""

    private var memberships: [TeamMember] {
        guard !producerEmail.isEmpty else { return [] }
        return teams.flatMap(\.members).filter {
            $0.email.map { $0.caseInsensitiveCompare(producerEmail) == .orderedSame } == true
                && isTeamProducerRole($0.role)
        }
    }

    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Minhas despesas").font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(AppTheme.ink)
                        Text("Adicione pagamentos e comprovantes para atualizar o saldo da verba.").font(.subheadline).foregroundStyle(AppTheme.muted)
                    }
                    if memberships.isEmpty {
                        ContentUnavailableView("Nenhuma equipe vinculada", systemImage: "person.3", description: Text("O produtor geral precisa adicionar este e-mail a uma equipe para liberar o envio da prestação de contas."))
                            .padding(.top, 30)
                    } else {
                        ForEach(memberships) { member in
                            NavigationLink {
                                TeamExpenseReportView(member: member, allowsSubmission: true)
                            } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(member.team?.name ?? "Equipe").font(.headline).foregroundStyle(AppTheme.ink)
                                            Text(member.role).font(.caption).foregroundStyle(AppTheme.muted)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(AppTheme.muted)
                                    }
                                    HStack {
                                        Label("Verba \(money(member.releasedBudget))", systemImage: "banknote")
                                        Spacer()
                                        Text("Saldo \(money(member.releasedBudget - spent(by: member)))")
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.accent)
                                }
                                .padding(16)
                                .background(.white, in: RoundedRectangle(cornerRadius: 17))
                                .contentShape(RoundedRectangle(cornerRadius: 17))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Prestação de contas")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func spent(by member: TeamMember) -> Double {
        member.expenses.reduce(0) { $0 + $1.amount }
    }
}

struct TeamExpenseReportView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingNewExpense = false
    @State private var selectedReceipt: ExpenseReceipt?

    let member: TeamMember
    let allowsSubmission: Bool

    private var expenses: [TeamExpense] { member.expenses.sorted { $0.createdAt > $1.createdAt } }
    private var spent: Double { expenses.reduce(0) { $0 + $1.amount } }
    private var remaining: Double { member.releasedBudget - spent }

    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(member.name).font(.title2.bold()).foregroundStyle(AppTheme.ink)
                        Text("\(member.team?.name ?? "Equipe") · \(member.role)").font(.subheadline).foregroundStyle(AppTheme.muted)
                    }
                    HStack(spacing: 10) {
                        FinanceSummaryCard(title: "Verba", amount: member.releasedBudget, tint: AppTheme.accent)
                        FinanceSummaryCard(title: "Gasto", amount: spent, tint: AppTheme.mint)
                        FinanceSummaryCard(title: "Saldo", amount: remaining, tint: remaining < 0 ? .red : AppTheme.accent)
                    }

                    HStack {
                        SectionHeading(title: "Despesas", trailing: "\(expenses.count) registros")
                        if allowsSubmission {
                            Button { showingNewExpense = true } label: {
                                Image(systemName: "plus").font(.headline.weight(.bold)).foregroundStyle(.white)
                                    .frame(width: 40, height: 40).background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 13))
                            }
                            .accessibilityLabel("Adicionar despesa")
                        }
                    }

                    if expenses.isEmpty {
                        ContentUnavailableView("Nenhuma despesa registrada", systemImage: "doc.text.image", description: Text(allowsSubmission ? "Adicione o primeiro pagamento e seus comprovantes." : "As despesas enviadas pelo produtor aparecerão aqui."))
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(expenses) { expense in
                                ExpenseEntryCard(expense: expense) { receipt in selectedReceipt = receipt }
                            }
                        }
                    }
                }
                .padding(20)
                .…6 tokens truncated…              .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Relatório de despesas")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingNewExpense) {
            NewExpenseView(member: member)
        }
        .sheet(item: $selectedReceipt) { receipt in
            ReceiptPreviewView(receipt: receipt)
        }
    }
}

private struct NewExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("producerName") private var producerName = "Produtor"
    @AppStorage("producerEmail") private var producerEmail = ""
    @State private var descriptionText = ""
    @State private var amountText = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var receiptImages: [Data] = []
    @State private var errorMessage: String?
    @State private var isSaving = false

    let member: TeamMember

    var body: some View {
        NavigationStack {
            Form {
                Section("Pagamento") {
                    TextField("Valor em reais", text: $amountText)
                        .keyboardType(.decimalPad)
                    TextField("Descrição do pagamento", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Notas e comprovantes") {
                    PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 8, matching: .images) {
                        Label("Adicionar fotos ou prints", systemImage: "photo.badge.plus")
                    }
                    .onChange(of: selectedPhotos) { _, items in
                        Task { await loadImages(from: items) }
                    }
                    if !receiptImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(receiptImages.indices, id: \.self) { index in
                                    if let image = UIImage(data: receiptImages[index]) {
                                        Image(uiImage: image)
                                            .resizable().scaledToFill()
                                            .frame(width: 76, height: 76)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Text("Você pode selecionar até 8 imagens da fototeca, incluindo fotos de notas e capturas de tela.")
                        .font(.footnote).foregroundStyle(AppTheme.muted)
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Nova despesa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Enviando…" : "Adicionar") { save() }.fontWeight(.semibold).disabled(isSaving)
                }
            }
        }
    }

    private func loadImages(from items: [PhotosPickerItem]) async {
        var loaded: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), UIImage(data: data) != nil {
                loaded.append(data)
            }
        }
        receiptImages = loaded
    }

    private func save() {
        let cleanDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = parseAmount(amountText), amount > 0 else {
            errorMessage = "Informe um valor maior que zero."
            return
        }
        guard !cleanDescription.isEmpty else {
            errorMessage = "Descreva o pagamento."
            return
        }
        guard let memberID = member.remoteID else {
            errorMessage = "Este integrante ainda não está sincronizado com o Supabase."
            return
        }
        isSaving = true
        Task { @MainActor in
        do {
        let jpegImages = receiptImages.compactMap { UIImage(data: $0)?.jpegData(compressionQuality: 0.85) }
        let (remoteExpenseID, remotePaths) = try await SupabaseService.shared.submitExpense(memberID: memberID, description: cleanDescription, amount: amount, images: jpegImages)
        let expense = TeamExpense(
            descriptionText: cleanDescription,
            amount: amount,
            producerName: producerName,
            producerEmail: producerEmail,
            producer: member
        )
        expense.remoteID = remoteExpenseID
        modelContext.insert(expense)
        member.expenses.append(expense)
        for (index, data) in receiptImages.enumerated() {
            let receipt = ExpenseReceipt(imageData: data, fileName: "Comprovante \(index + 1)", expense: expense)
            if remotePaths.indices.contains(index) { receipt.remotePath = remotePaths[index] }
            modelContext.insert(receipt)
            expense.receipts.append(receipt)
        }
        dismiss()
        } catch { errorMessage = error.localizedDescription; isSaving = false }
        }
    }
}

private struct ExpenseEntryCard: View {
    let expense: TeamExpense
    let onSelectReceipt: (ExpenseReceipt) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(expense.descriptionText).font(.headline).foregroundStyle(AppTheme.ink)
                    Text(expense.createdAt.formatted(date: .numeric, time: .shortened)).font(.caption).foregroundStyle(AppTheme.muted)
                    Text(expense.producerName).font(.caption.weight(.medium)).foregroundStyle(AppTheme.accent)
                }
                Spacer(minLength: 8)
                Text(money(expense.amount)).font(.headline.weight(.bold)).foregroundStyle(AppTheme.ink)
            }
            if !expense.receipts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(expense.receipts) { receipt in
                            Button { onSelectReceipt(receipt) } label: {
                                if let image = UIImage(data: receipt.imageData) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                        .frame(width: 74, height: 74).clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Abrir comprovante")
                        }
                    }
                }
            }
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 17))
    }
}

private struct BudgetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    let member: TeamMember

    var body: some View {
        NavigationStack {
            Form {
                Section("Produtor") {
                    LabeledContent("Nome", value: member.name)
                    LabeledContent("Equipe", value: member.team?.name ?? "Equipe")
                }
                Section("Verba liberada") {
                    TextField("Valor em reais", text: $amountText)
                        .keyboardType(.decimalPad)
                    Text("O saldo será calculado subtraindo as despesas registradas.")
                        .font(.footnote).foregroundStyle(AppTheme.muted)
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Definir verba")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Salvando…" : "Salvar") {
                        guard let value = parseAmount(amountText), value >= 0 else {
                            errorMessage = "Informe uma verba válida, igual ou maior que zero."
                            return
                        }
                        guard let memberID = member.remoteID else { errorMessage = "Este integrante ainda não está sincronizado."; return }
                        isSaving = true
                        Task { @MainActor in
                            do {
                                try await SupabaseService.shared.setBudget(memberID: memberID, amount: value)
                                member.releasedBudget = value; dismiss()
                            } catch { errorMessage = error.localizedDescription; isSaving = false }
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { amountText = amountTextForEntry(member.releasedBudget) }
        }
    }
}

private struct FinanceSummaryCard: View {
    let title: String
    let amount: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.muted)
            Text(money(amount)).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(.white, in: RoundedRectangle(cornerRadius: 15))
    }
}

private struct ReceiptPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let receipt: ExpenseReceipt

    var body: some View {
        NavigationStack {
            Group {
                if let image = UIImage(data: receipt.imageData) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)
                } else {
                    ContentUnavailableView("Não foi possível abrir a imagem", systemImage: "photo")
                }
            }
            .navigationTitle(receipt.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fechar") { dismiss() } }
            }
        }
    }
}

private func money(_ value: Double) -> String {
    value.formatted(.currency(code: "BRL").locale(Locale(identifier: "pt_BR")))
}

private func isTeamProducerRole(_ value: String) -> Bool {
    let role = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    return role.contains("produtor") && !role.contains("geral")
}

private func parseAmount(_ text: String) -> Double? {
    let cleaned = text
        .replacingOccurrences(of: "R$", with: "")
        .replacingOccurrences(of: " ", with: "")
    let normalized: String
    if cleaned.contains(",") {
        normalized = cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
    } else {
        normalized = cleaned
    }
    return Double(normalized)
}

private func amountTextForEntry(_ amount: Double) -> String {
    amount.formatted(.number.locale(Locale(identifier: "pt_BR")))
}
