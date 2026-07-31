import SwiftUI

struct RegisterView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var selection = Set<UUID>()
    @State private var showEditor = false
    @State private var editingTransaction: FinanceTransaction?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.selectedAccount?.name ?? "Kontoblatt")
                        .font(.title2.bold())
                    if let account = store.selectedAccount {
                        Text("\(account.institution) · \(account.type.title)")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Picker("Konto", selection: $store.selectedAccountID) {
                    Text("Alle Konten").tag(UUID?.none)
                    ForEach(store.accounts) { account in
                        Text(account.name).tag(UUID?.some(account.id))
                    }
                }
                .frame(width: 220)
                if let account = store.selectedAccount {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Aktueller Saldo").font(.caption).foregroundStyle(.secondary)
                        Text(Money(minorUnits: store.balances[account.id] ?? 0).formatted)
                            .font(.title3.bold().monospacedDigit())
                    }
                }
            }
            .padding(14)

            Divider()

            Table(store.filteredTransactions, selection: $selection) {
                TableColumn("Datum") { value in
                    Text(value.bookingDate, format: .dateTime.day().month(.twoDigits).year())
                        .monospacedDigit()
                }
                .width(min: 82, ideal: 92)
                TableColumn("Status") { value in
                    Image(systemName: statusIcon(value.status))
                        .foregroundStyle(statusColor(value.status))
                        .help(value.status.title)
                }
                .width(44)
                TableColumn("Empfänger") { value in Text(value.payee) }
                    .width(min: 130, ideal: 180)
                TableColumn("Verwendungszweck") { value in Text(value.purpose) }
                    .width(min: 170, ideal: 260)
                TableColumn("Kategorie") { value in
                    Text(value.transferID == nil ? store.categoryName(value.categoryID) : "Umbuchung")
                }
                .width(min: 120, ideal: 160)
                TableColumn("Konto") { value in Text(store.accountName(value.accountID)) }
                    .width(min: 100, ideal: 140)
                TableColumn("Betrag") { value in
                    Text(Money(minorUnits: value.amountMinor, currency: value.currency).formatted)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .monospacedDigit()
                        .foregroundStyle(value.amountMinor < 0 ? .primary : Color.green)
                }
                .width(min: 105, ideal: 120)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                Button("Bearbeiten") {
                    editingTransaction = store.transactions.first { ids.contains($0.id) }
                    showEditor = editingTransaction != nil
                }
                Button("Löschen", role: .destructive) {
                    ids.compactMap { id in store.transactions.first { $0.id == id } }
                        .forEach(store.deleteTransaction)
                    selection.removeAll()
                }
            } primaryAction: { ids in
                editingTransaction = store.transactions.first { ids.contains($0.id) }
                showEditor = editingTransaction != nil
            }
            .overlay {
                if store.filteredTransactions.isEmpty {
                    ContentUnavailableView(
                        "Keine Buchungen",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Lege eine Buchung an oder importiere Umsätze.")
                    )
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            TransactionEditorView(transaction: editingTransaction)
        }
    }

    private func statusIcon(_ status: TransactionStatus) -> String {
        switch status {
        case .expected: "clock"
        case .pending: "hourglass"
        case .booked: "circle"
        case .cleared: "checkmark.circle"
        case .reconciled: "checkmark.seal.fill"
        case .cancelled: "xmark.circle"
        }
    }

    private func statusColor(_ status: TransactionStatus) -> Color {
        switch status {
        case .expected: .blue
        case .pending: .orange
        case .booked: .secondary
        case .cleared: .green
        case .reconciled: .green
        case .cancelled: .red
        }
    }
}

struct TransactionEditorView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    let transaction: FinanceTransaction?

    @State private var accountID: UUID?
    @State private var date = Date()
    @State private var payee = ""
    @State private var payeeID: UUID?
    @State private var purpose = ""
    @State private var categoryID: UUID?
    @State private var amount = ""
    @State private var status: TransactionStatus = .booked
    @State private var memo = ""
    @State private var selectedTagIDs = Set<UUID>()
    @State private var useSplits = false
    @State private var splitDrafts: [SplitDraft] = []
    @State private var initialized = false

    init(transaction: FinanceTransaction? = nil) {
        self.transaction = transaction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(transaction == nil ? "Neue Buchung" : "Buchung bearbeiten")
                .font(.title2.bold())
            Form {
                Picker("Konto", selection: $accountID) {
                    Text("Bitte wählen").tag(UUID?.none)
                    ForEach(store.accounts) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                DatePicker("Datum", selection: $date, displayedComponents: .date)
                TextField("Empfänger", text: $payee)
                Picker("Empfängerakte", selection: $payeeID) {
                    Text("Nur Freitext").tag(UUID?.none)
                    ForEach(store.payeeSuggestions(for: payee)) {
                        Text($0.canonicalName).tag(Optional($0.id))
                    }
                }
                .onChange(of: payeeID) {
                    guard let selected = store.payees.first(where: { $0.id == payeeID }) else {
                        return
                    }
                    payee = selected.canonicalName
                    categoryID = categoryID ?? selected.defaultCategoryID
                    accountID = accountID ?? selected.preferredAccountID
                }
                TextField("Verwendungszweck", text: $purpose)
                Picker("Kategorie", selection: $categoryID) {
                    Text("Nicht kategorisiert").tag(UUID?.none)
                    ForEach(store.categoriesByPath.filter(\.isActive)) {
                        Text(store.categoryPath($0.id)).tag(UUID?.some($0.id))
                    }
                }
                TextField("Betrag", text: $amount, prompt: Text("-123,45"))
                Picker("Status", selection: $status) {
                    ForEach(TransactionStatus.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Notiz", text: $memo)
                if !store.tags.filter(\.isActive).isEmpty {
                    Section("Klassen & Tags") {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(store.tags.filter(\.isActive)) { tag in
                                    Toggle(
                                        tag.name,
                                        isOn: Binding(
                                            get: { selectedTagIDs.contains(tag.id) },
                                            set: {
                                                if $0 { selectedTagIDs.insert(tag.id) }
                                                else { selectedTagIDs.remove(tag.id) }
                                            }
                                        )
                                    )
                                    .toggleStyle(.button)
                                }
                            }
                        }
                    }
                }
                Toggle("Betrag aufteilen", isOn: $useSplits)
                if useSplits {
                    Section("Splits") {
                        ForEach($splitDrafts) { $draft in
                            HStack {
                                Picker("Kategorie", selection: $draft.categoryID) {
                                    Text("Ohne Kategorie").tag(UUID?.none)
                                    ForEach(store.categoriesByPath.filter(\.isActive)) {
                                        Text(store.categoryPath($0.id)).tag(UUID?.some($0.id))
                                    }
                                }
                                .labelsHidden()
                                TextField("Betrag", text: $draft.amount)
                                    .frame(width: 110)
                                TextField("Notiz", text: $draft.memo)
                                Menu("Tags") {
                                    ForEach(store.tags.filter(\.isActive)) { tag in
                                        Button {
                                            if draft.tagIDs.contains(tag.id) {
                                                draft.tagIDs.remove(tag.id)
                                            } else {
                                                draft.tagIDs.insert(tag.id)
                                            }
                                        } label: {
                                            Label(
                                                tag.name,
                                                systemImage: draft.tagIDs.contains(tag.id)
                                                    ? "checkmark" : "tag"
                                            )
                                        }
                                    }
                                }
                                Button(role: .destructive) {
                                    splitDrafts.removeAll { $0.id == draft.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        HStack {
                            Button("Zeile hinzufügen", systemImage: "plus") {
                                splitDrafts.append(SplitDraft())
                            }
                            Spacer()
                            Text("Rest: \(remainingSplitText)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(remainingSplitMinor == 0 ? Color.secondary : Color.red)
                            Button("Rest zuweisen") {
                                assignRemainder()
                            }
                            .disabled(splitDrafts.isEmpty || remainingSplitMinor == 0)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Speichern") {
                    guard let accountID else {
                        store.errorMessage = FinanceError.missingAccount.localizedDescription
                        return
                    }
                    if useSplits {
                        saveSplit(accountID: accountID)
                    } else {
                        if store.saveTransaction(
                            id: transaction?.id, accountID: accountID, date: date, payee: payee,
                            purpose: purpose, categoryID: categoryID, amount: amount,
                            status: status, memo: memo,
                            reference: transaction?.reference ?? "",
                            payeeID: payeeID, tagIDs: Array(selectedTagIDs)
                        ) {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(accountID == nil || amount.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            guard !initialized else { return }
            initialized = true
            accountID = transaction?.accountID ?? store.selectedAccountID ?? store.accounts.first?.id
            date = transaction?.bookingDate ?? Date()
            payee = transaction?.payee ?? ""
            payeeID = transaction?.payeeID
            purpose = transaction?.purpose ?? ""
            categoryID = transaction?.categoryID
            amount = transaction.map {
                NSDecimalNumber(decimal: Decimal($0.amountMinor) / Decimal(100)).stringValue
            } ?? ""
            status = transaction?.status ?? .booked
            memo = transaction?.memo ?? ""
            selectedTagIDs = Set(transaction?.tagIDs ?? [])
            useSplits = !(transaction?.splits.isEmpty ?? true)
            splitDrafts = transaction?.splits.map {
                SplitDraft(
                    id: $0.id,
                    categoryID: $0.categoryID,
                    amount: NSDecimalNumber(decimal: Decimal($0.amountMinor) / Decimal(100)).stringValue,
                    memo: $0.memo,
                    tagIDs: Set($0.tagIDs)
                )
            } ?? []
            if useSplits, splitDrafts.isEmpty {
                splitDrafts = [SplitDraft(), SplitDraft()]
            }
        }
        .onChange(of: useSplits) {
            if useSplits, splitDrafts.isEmpty {
                splitDrafts = [SplitDraft(), SplitDraft()]
            }
        }
    }

    private var totalMinor: Int64 {
        (try? Money(parsing: amount).minorUnits) ?? 0
    }

    private var splitSumMinor: Int64 {
        splitDrafts.reduce(Int64.zero) {
            $0 + ((try? Money(parsing: $1.amount).minorUnits) ?? 0)
        }
    }

    private var remainingSplitMinor: Int64 { totalMinor - splitSumMinor }
    private var remainingSplitText: String { Money(minorUnits: remainingSplitMinor).formatted }

    private func assignRemainder() {
        guard let index = splitDrafts.indices.last else { return }
        let adjusted = ((try? Money(parsing: splitDrafts[index].amount).minorUnits) ?? 0)
            + remainingSplitMinor
        splitDrafts[index].amount = NSDecimalNumber(
            decimal: Decimal(adjusted) / Decimal(100)
        ).stringValue
    }

    private func saveSplit(accountID: UUID) {
        do {
            let total = try Money(parsing: amount)
            let splits = try splitDrafts.enumerated().map { offset, draft in
                FinanceSplit(
                    id: draft.id,
                    categoryID: draft.categoryID,
                    amountMinor: try Money(parsing: draft.amount).minorUnits,
                    memo: draft.memo,
                    sortOrder: offset,
                    tagIDs: Array(draft.tagIDs)
                )
            }
            let value = FinanceTransaction(
                id: transaction?.id ?? UUID(),
                accountID: accountID,
                bookingDate: date,
                valueDate: transaction?.valueDate ?? date,
                payee: payee,
                purpose: purpose,
                categoryID: nil,
                amountMinor: total.minorUnits,
                currency: total.currency,
                status: status,
                memo: memo,
                reference: transaction?.reference ?? "",
                transferID: transaction?.transferID,
                importFingerprint: transaction?.importFingerprint,
                splits: splits,
                payeeID: payeeID,
                tagIDs: Array(selectedTagIDs)
            )
            if store.saveSplitTransaction(value) {
                dismiss()
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}

private struct SplitDraft: Identifiable {
    let id: UUID
    var categoryID: UUID?
    var amount: String
    var memo: String
    var tagIDs: Set<UUID>

    init(
        id: UUID = UUID(),
        categoryID: UUID? = nil,
        amount: String = "",
        memo: String = "",
        tagIDs: Set<UUID> = []
    ) {
        self.id = id
        self.categoryID = categoryID
        self.amount = amount
        self.memo = memo
        self.tagIDs = tagIDs
    }
}

struct CombinedRegisterView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var selection = Set<UUID>()

    private var visible: [FinanceTransaction] {
        store.transactions.filter {
            store.searchText.isEmpty
                || $0.payee.localizedCaseInsensitiveContains(store.searchText)
                || $0.purpose.localizedCaseInsensitiveContains(store.searchText)
        }
    }

    private var visibleSum: Int64 {
        visible.filter { $0.transferID == nil && $0.status != .cancelled }
            .reduce(Int64.zero) { $0 + $1.amountMinor }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sammelkontoblatt").font(.title2.bold())
                    Text("Alle normalen Buchungskonten · Vergangenheit, Heute und erwartete Zukunft")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(store.searchText.isEmpty ? "Summe ohne Umbuchungen" : "Gefilterte Summe")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(Money(minorUnits: visibleSum).formatted)
                        .font(.title3.bold().monospacedDigit())
                }
            }
            .padding(14)
            Divider()
            Table(visible, selection: $selection) {
                TableColumn("Datum") {
                    Text($0.bookingDate, format: .dateTime.day().month(.twoDigits).year())
                        .foregroundStyle($0.bookingDate > Date() ? .blue : .primary)
                }
                .width(90)
                TableColumn("Konto") { Text(store.accountName($0.accountID)) }
                TableColumn("Empfänger", value: \.payee)
                TableColumn("Verwendungszweck", value: \.purpose)
                TableColumn("Kategorie") {
                    Text($0.transferID == nil ? store.categoryName($0.categoryID) : "Umbuchung")
                }
                TableColumn("Status") { Text($0.status.title) }.width(90)
                TableColumn("Betrag") {
                    Text(Money(minorUnits: $0.amountMinor).formatted)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .monospacedDigit()
                }
                .width(115)
            }
            HStack {
                Rectangle().fill(.blue).frame(width: 36, height: 2)
                Text("Heute-Grenze: \(Date.now.formatted(.dateTime.day().month().year()))")
                Spacer()
                Text("\(visible.count) sichtbare Buchungen")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
        }
    }
}
