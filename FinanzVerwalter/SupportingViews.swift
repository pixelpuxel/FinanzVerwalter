import Charts
import SwiftUI
import UniformTypeIdentifiers

struct CockpitView: View {
    @EnvironmentObject private var store: FinanceAppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Finanzübersicht")
                            .font(.largeTitle.bold())
                        Text(store.fileInfo?.name ?? "Lokale Finanzdatei")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Nettovermögen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(
                            Money(
                                minorUnits: store.totalBalanceMinor,
                                currency: store.fileInfo?.baseCurrency ?? "EUR"
                            ).formatted
                        )
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        let foreignCount = store.accounts.filter {
                            !$0.isHidden && $0.includeNetWorth
                                && $0.currency != (store.fileInfo?.baseCurrency ?? "EUR")
                        }.count
                        if foreignCount > 0 {
                            Text("\(foreignCount) Fremdwährungskonten nicht ohne FX-Kurs summiert")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                    DashboardCard(title: "Konten", icon: "building.columns") {
                        ForEach(store.accounts.prefix(5)) { account in
                            HStack {
                                Text(account.name)
                                Spacer()
                                Text(
                                    Money(
                                        minorUnits: store.balances[account.id] ?? 0,
                                        currency: account.currency
                                    ).formatted
                                )
                                    .monospacedDigit()
                            }
                            .font(.callout)
                        }
                        if store.accounts.isEmpty {
                            Text("Noch keine Konten angelegt.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    DashboardCard(title: "Einnahmen & Ausgaben", icon: "chart.bar.xaxis") {
                        Chart(store.reportRows.prefix(7)) { row in
                            BarMark(
                                x: .value("Kategorie", row.name),
                                y: .value("Ausgaben", Decimal(row.expenseMinor) / Decimal(100))
                            )
                            .foregroundStyle(Color(red: 0.12, green: 0.48, blue: 0.27).gradient)
                        }
                        .chartXAxis(.hidden)
                        .frame(height: 145)
                    }

                    DashboardCard(title: "Letzte Buchungen", icon: "clock") {
                        ForEach(store.transactions.prefix(5)) { value in
                            HStack(spacing: 8) {
                                Text(value.bookingDate, format: .dateTime.day().month())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 45, alignment: .leading)
                                Text(value.payee.isEmpty ? value.purpose : value.payee)
                                    .lineLimit(1)
                                Spacer()
                                Text(Money(minorUnits: value.amountMinor).formatted)
                                    .monospacedDigit()
                            }
                            .font(.callout)
                        }
                        if store.transactions.isEmpty {
                            Text("Noch keine Buchungen vorhanden.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    DashboardCard(title: "Status", icon: "checkmark.shield") {
                        Label("Lokale Finanzdatei", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Label("Offline verfügbar", systemImage: "wifi.slash")
                        Label("SQLite im WAL-Modus", systemImage: "cylinder.split.1x2")
                        Label("Beträge centgenau", systemImage: "eurosign.circle")
                    }
                }
            }
            .padding(22)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct DashboardCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(Color(red: 0.05, green: 0.31, blue: 0.18))
            Divider()
            content
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }
}

struct AccountsView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var showEditor = false
    @State private var showGroups = false
    @State private var editingAccount: FinanceAccount?
    @State private var selectedAccountID: UUID?
    @State private var selectedGroupID: UUID?
    @State private var showHidden = false

    private var visibleAccounts: [FinanceAccount] {
        store.accounts.filter {
            (showHidden || (!$0.isHidden && !$0.isClosed))
                && (selectedGroupID == nil || $0.groupID == selectedGroupID)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Kontenübersicht").font(.title2.bold())
                Spacer()
                Picker("Gruppe", selection: $selectedGroupID) {
                    Text("Alle Gruppen").tag(UUID?.none)
                    ForEach(store.accountGroups.filter(\.isActive)) {
                        Text($0.name).tag(UUID?.some($0.id))
                    }
                }
                .frame(width: 210)
                Toggle("Ausgeblendete", isOn: $showHidden)
                    .toggleStyle(.checkbox)
                Button("Gruppen …", systemImage: "folder") { showGroups = true }
                Button("Bearbeiten", systemImage: "pencil") {
                    editingAccount = store.accounts.first { $0.id == selectedAccountID }
                    showEditor = editingAccount != nil
                }
                .disabled(selectedAccountID == nil)
                Button("Konto hinzufügen", systemImage: "plus") {
                    editingAccount = nil
                    showEditor = true
                }
            }
            .padding(16)
            Divider()
            if !store.accountGroups.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(store.accountGroups.filter(\.isActive)) { group in
                            let accounts = store.accounts.filter {
                                $0.groupID == group.id && !$0.isHidden && !$0.isClosed
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.name).font(.headline)
                                Text("\(accounts.count) Konten")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(groupBalanceText(accounts))
                                .font(.title3.monospacedDigit())
                            }
                            .padding(12)
                            .frame(width: 190, alignment: .leading)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(12)
                }
                Divider()
            }
            Table(visibleAccounts, selection: $selectedAccountID) {
                TableColumn("Konto") { account in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(account.name, systemImage: icon(account.type))
                        if !account.shortName.isEmpty {
                            Text(account.shortName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                TableColumn("Gruppe") { Text(store.accountGroupName($0.groupID)) }
                TableColumn("Institut", value: \.institution)
                TableColumn("Typ") { Text($0.type.title) }
                TableColumn("Währung", value: \.currency).width(75)
                TableColumn("Saldo") { account in
                    Text(
                        Money(
                            minorUnits: store.balances[account.id] ?? 0,
                            currency: account.currency
                        ).formatted
                    )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .monospacedDigit()
                }
                TableColumn("Verfügbar") { account in
                    Text(
                        Money(
                            minorUnits: (store.balances[account.id] ?? 0)
                                + account.creditLimitMinor,
                            currency: account.currency
                        ).formatted
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .monospacedDigit()
                }
                TableColumn("Abruf") { account in
                    Label(
                        account.syncStatus.title,
                        systemImage: account.isOnline ? "network" : "internaldrive"
                    )
                    .foregroundStyle(account.syncStatus == .failed ? .red : .secondary)
                }
            }
            .overlay {
                if visibleAccounts.isEmpty {
                    ContentUnavailableView(
                        "Keine Konten",
                        systemImage: "building.columns",
                        description: Text(
                            store.accounts.isEmpty
                                ? "Lege dein erstes Konto an."
                                : "Für den gewählten Filter sind keine Konten sichtbar."
                        )
                    )
                }
            }
            .contextMenu(forSelectionType: UUID.self) { selection in
                if let id = selection.first,
                   let account = store.accounts.first(where: { $0.id == id }) {
                    Button("Konto bearbeiten") {
                        editingAccount = account
                        showEditor = true
                    }
                    Button("Im Kontoblatt öffnen") {
                        store.selectedAccountID = account.id
                    }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            AccountEditorView(account: editingAccount)
        }
        .sheet(isPresented: $showGroups) { AccountGroupsEditorView() }
    }

    private func icon(_ type: AccountType) -> String {
        switch type {
        case .checking: "building.columns"
        case .savings: "banknote"
        case .fixedDeposit: "calendar.badge.clock"
        case .cash: "wallet.bifold"
        case .creditCard: "creditcard"
        case .clearing: "arrow.left.arrow.right"
        case .foreignCurrency: "eurosign.arrow.circlepath"
        case .investment: "chart.line.uptrend.xyaxis"
        case .loan: "percent"
        case .asset: "house"
        case .liability: "exclamationmark.triangle"
        case .receivable: "doc.text"
        case .inventory: "shippingbox"
        case .rewards: "giftcard"
        }
    }

    private func groupBalanceText(_ accounts: [FinanceAccount]) -> String {
        let byCurrency = Dictionary(grouping: accounts, by: \.currency)
        return byCurrency.keys.sorted().map { currency in
            Money(
                minorUnits: byCurrency[currency, default: []].reduce(0) {
                    $0 + (store.balances[$1.id] ?? 0)
                },
                currency: currency
            ).formatted
        }
        .joined(separator: " · ")
    }
}

struct AccountEditorView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    private let account: FinanceAccount?
    @State private var name: String
    @State private var shortName: String
    @State private var descriptionText: String
    @State private var institution: String
    @State private var type: AccountType
    @State private var currency: String
    @State private var groupID: UUID?
    @State private var openingBalance: String
    @State private var hasOpeningDate: Bool
    @State private var openingDate: Date
    @State private var creditLimit: String
    @State private var iban: String
    @State private var bic: String
    @State private var accountNumberMasked: String
    @State private var ownerName: String
    @State private var isOnline: Bool
    @State private var isHidden: Bool
    @State private var isClosed: Bool
    @State private var includeNetWorth: Bool
    @State private var includeBudget: Bool
    @State private var includeReports: Bool
    @State private var includeForecast: Bool

    init(account: FinanceAccount? = nil) {
        self.account = account
        _name = State(initialValue: account?.name ?? "")
        _shortName = State(initialValue: account?.shortName ?? "")
        _descriptionText = State(initialValue: account?.description ?? "")
        _institution = State(initialValue: account?.institution ?? "")
        _type = State(initialValue: account?.type ?? .checking)
        _currency = State(initialValue: account?.currency ?? "EUR")
        _groupID = State(initialValue: account?.groupID)
        _openingBalance = State(
            initialValue: Money(minorUnits: account?.openingBalanceMinor ?? 0).editingString
        )
        _hasOpeningDate = State(initialValue: account?.openingDate != nil)
        _openingDate = State(initialValue: account?.openingDate ?? Date())
        _creditLimit = State(
            initialValue: Money(minorUnits: account?.creditLimitMinor ?? 0).editingString
        )
        _iban = State(initialValue: account?.iban ?? "")
        _bic = State(initialValue: account?.bic ?? "")
        _accountNumberMasked = State(initialValue: account?.accountNumberMasked ?? "")
        _ownerName = State(initialValue: account?.ownerName ?? "")
        _isOnline = State(initialValue: account?.isOnline ?? false)
        _isHidden = State(initialValue: account?.isHidden ?? false)
        _isClosed = State(initialValue: account?.isClosed ?? false)
        _includeNetWorth = State(initialValue: account?.includeNetWorth ?? true)
        _includeBudget = State(initialValue: account?.includeBudget ?? true)
        _includeReports = State(initialValue: account?.includeReports ?? true)
        _includeForecast = State(initialValue: account?.includeForecast ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(account == nil ? "Neues Konto" : "Konto bearbeiten")
                .font(.title2.bold())
            Form {
                Section("Stammdaten") {
                    TextField("Kontoname", text: $name)
                    TextField("Kurzname", text: $shortName)
                    TextField("Beschreibung", text: $descriptionText, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("Kontogruppe", selection: $groupID) {
                        Text("Ohne Gruppe").tag(UUID?.none)
                        ForEach(store.accountGroups.filter(\.isActive)) {
                            Text($0.name).tag(UUID?.some($0.id))
                        }
                    }
                    Picker("Kontotyp", selection: $type) {
                        ForEach(AccountType.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Währung", text: $currency)
                    TextField("Kontoinhaber", text: $ownerName)
                }
                Section("Bankdaten") {
                    TextField("Institut", text: $institution)
                    TextField("IBAN", text: $iban)
                    TextField("BIC", text: $bic)
                    TextField("Kontonummer (maskiert)", text: $accountNumberMasked)
                    Toggle("Onlinekonto", isOn: $isOnline)
                    if let account {
                        LabeledContent("Abrufstatus", value: account.syncStatus.title)
                        if let date = account.lastSyncAt {
                            LabeledContent("Letzter Abruf") {
                                Text(date, format: .dateTime.day().month().year().hour().minute())
                            }
                        }
                    }
                }
                Section("Saldo und Gültigkeit") {
                    TextField("Eröffnungssaldo", text: $openingBalance)
                    TextField("Kreditlimit/Dispo", text: $creditLimit)
                    Toggle("Eröffnungsdatum festlegen", isOn: $hasOpeningDate)
                    if hasOpeningDate {
                        DatePicker("Eröffnungsdatum", selection: $openingDate, displayedComponents: .date)
                    }
                    Toggle("Konto ausgeblendet", isOn: $isHidden)
                    Toggle("Konto geschlossen", isOn: $isClosed)
                }
                Section("Einbeziehung") {
                    Toggle("Im Vermögen berücksichtigen", isOn: $includeNetWorth)
                    Toggle("Im Budget berücksichtigen", isOn: $includeBudget)
                    Toggle("In Berichten berücksichtigen", isOn: $includeReports)
                    Toggle("In der Prognose berücksichtigen", isOn: $includeForecast)
                }
            }
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(account == nil ? "Anlegen" : "Speichern") {
                    do {
                        let openingMoney = try Money(
                            parsing: openingBalance,
                            currency: currency
                        )
                        let creditMoney = try Money(
                            parsing: creditLimit.isEmpty ? "0" : creditLimit,
                            currency: currency
                        )
                        let value = FinanceAccount(
                            id: account?.id ?? UUID(),
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            institution: institution.trimmingCharacters(in: .whitespacesAndNewlines),
                            type: type,
                            currency: currency.uppercased(),
                            openingBalanceMinor: openingMoney.minorUnits,
                            isHidden: isHidden,
                            isClosed: isClosed,
                            sortOrder: account?.sortOrder ?? store.accounts.count,
                            shortName: shortName.trimmingCharacters(in: .whitespacesAndNewlines),
                            description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
                            groupID: groupID,
                            iban: iban,
                            bic: bic,
                            accountNumberMasked: accountNumberMasked,
                            ownerName: ownerName,
                            openingDate: hasOpeningDate ? openingDate : nil,
                            creditLimitMinor: creditMoney.minorUnits,
                            isOnline: isOnline,
                            includeNetWorth: includeNetWorth,
                            includeBudget: includeBudget,
                            includeReports: includeReports,
                            includeForecast: includeForecast,
                            lastSyncAt: account?.lastSyncAt,
                            lastBankBalanceMinor: account?.lastBankBalanceMinor,
                            syncStatus: isOnline ? (account?.syncStatus ?? .ready) : .offline
                        )
                        if store.saveAccount(value) { dismiss() }
                    } catch {
                        store.errorMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    name.trimmingCharacters(in: .whitespaces).isEmpty
                        || currency.trimmingCharacters(in: .whitespaces).isEmpty
                )
            }
        }
        .padding(24)
        .frame(width: 640, height: 760)
        .onAppear {
            if account == nil, groupID == nil {
                groupID = store.accountGroups.first {
                    $0.name == type.defaultGroupName
                }?.id
            }
        }
        .onChange(of: type) {
            if account == nil {
                groupID = store.accountGroups.first {
                    $0.name == type.defaultGroupName
                }?.id
            }
        }
    }
}

struct AccountGroupsEditorView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Kontengruppen").font(.title2.bold())
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            Text("Gruppen ordnen die Kontenübersicht. Deaktivierte Gruppen bleiben in bestehenden Konten erhalten.")
                .foregroundStyle(.secondary)
            List {
                ForEach(store.accountGroups) { group in
                    AccountGroupEditorRow(group: group)
                }
            }
            HStack {
                TextField("Neue Gruppe", text: $newName)
                Button("Hinzufügen", systemImage: "plus") {
                    let value = AccountGroup(
                        id: UUID(),
                        name: newName.trimmingCharacters(in: .whitespacesAndNewlines),
                        sortOrder: store.accountGroups.count,
                        isActive: true
                    )
                    if store.saveAccountGroup(value) { newName = "" }
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560, height: 500)
    }
}

private struct AccountGroupEditorRow: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var name: String
    @State private var sortOrder: Int
    @State private var isActive: Bool
    let id: UUID

    init(group: AccountGroup) {
        id = group.id
        _name = State(initialValue: group.name)
        _sortOrder = State(initialValue: group.sortOrder)
        _isActive = State(initialValue: group.isActive)
    }

    var body: some View {
        HStack {
            TextField("Name", text: $name)
            Stepper("Position \(sortOrder + 1)", value: $sortOrder, in: 0...999)
                .frame(width: 135)
            Toggle("Aktiv", isOn: $isActive)
                .toggleStyle(.checkbox)
            Button("Speichern") {
                _ = store.saveAccountGroup(
                    AccountGroup(
                        id: id, name: name,
                        sortOrder: sortOrder, isActive: isActive
                    )
                )
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

struct TransferEditorView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var sourceID: UUID?
    @State private var destinationID: UUID?
    @State private var amount = ""
    @State private var date = Date()
    @State private var purpose = "Umbuchung"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Umbuchung").font(.title2.bold())
            Text("Beide Kontoseiten werden als ein atomarer Vorgang gespeichert.")
                .foregroundStyle(.secondary)
            Form {
                Picker("Von Konto", selection: $sourceID) {
                    Text("Bitte wählen").tag(UUID?.none)
                    ForEach(store.accounts) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                Picker("Auf Konto", selection: $destinationID) {
                    Text("Bitte wählen").tag(UUID?.none)
                    ForEach(store.accounts.filter { $0.id != sourceID }) {
                        Text($0.name).tag(UUID?.some($0.id))
                    }
                }
                TextField("Betrag", text: $amount, prompt: Text("250,00"))
                DatePicker("Datum", selection: $date, displayedComponents: .date)
                TextField("Verwendungszweck", text: $purpose)
            }
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Umbuchen") {
                    guard let sourceID, let destinationID else { return }
                    if store.createTransfer(
                        from: sourceID, to: destinationID,
                        amount: amount, date: date, purpose: purpose
                    ) {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    sourceID == nil || destinationID == nil
                        || sourceID == destinationID || amount.isEmpty
                )
            }
        }
        .padding(24)
        .frame(width: 500)
        .onAppear {
            sourceID = store.selectedAccountID ?? store.accounts.first?.id
            destinationID = store.accounts.first { $0.id != sourceID }?.id
        }
        .onChange(of: sourceID) {
            if destinationID == sourceID {
                destinationID = store.accounts.first { $0.id != sourceID }?.id
            }
        }
    }
}

struct ReconciliationView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var accountID: UUID?
    @State private var statementDate = Date()
    @State private var endingBalance = ""
    @State private var snapshot: ReconciliationSnapshot?
    @State private var selectedTransactionIDs = Set<UUID>()
    @State private var history: [ReconciliationRecord] = []
    @State private var createAdjustment = false
    @State private var showAdjustmentConfirmation = false
    @State private var reconciliationToRevert: ReconciliationRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Konto abgleichen")
                    .font(.title2.bold())
                Text(
                    "Markiere nur die Buchungen des Bankauszugs. "
                        + "Anfangssaldo, markierte Summe und Endsaldo "
                        + "müssen sich exakt ausgleichen."
                )
                .foregroundStyle(.secondary)
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 18) {
                        Picker("Konto", selection: $accountID) {
                            Text("Bitte wählen").tag(UUID?.none)
                            ForEach(store.accounts.filter { !$0.isClosed }) {
                                Text($0.name).tag(UUID?.some($0.id))
                            }
                        }
                        .frame(width: 280)
                        DatePicker(
                            "Auszugsdatum",
                            selection: $statementDate,
                            displayedComponents: .date
                        )
                        .frame(width: 230)
                        Spacer()
                    }

                    reconciliationSummary

                    if let snapshot {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Buchungen auf dem Auszug")
                                    .font(.headline)
                                Text("\(selectedTransactionIDs.count) von \(snapshot.candidates.count) markiert")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Alle markieren") {
                                    selectedTransactionIDs = Set(
                                        snapshot.candidates.map(\.id)
                                    )
                                }
                                Button("Keine markieren") {
                                    selectedTransactionIDs.removeAll()
                                }
                            }
                            Table(
                                snapshot.candidates,
                                selection: $selectedTransactionIDs
                            ) {
                                TableColumn("Datum") { transaction in
                                    Text(
                                        transaction.bookingDate,
                                        format: .dateTime
                                            .day()
                                            .month(.twoDigits)
                                            .year()
                                    )
                                    .monospacedDigit()
                                }
                                .width(90)
                                TableColumn("Empfänger") { transaction in
                                    Text(transaction.payee)
                                        .lineLimit(1)
                                }
                                TableColumn("Verwendungszweck") { transaction in
                                    Text(transaction.purpose)
                                        .lineLimit(1)
                                }
                                TableColumn("Status") { transaction in
                                    Text(transaction.status.title)
                                }
                                .width(80)
                                TableColumn("Betrag") { transaction in
                                    Text(
                                        Money(
                                            minorUnits: transaction.amountMinor,
                                            currency: selectedAccount?.currency ?? "EUR"
                                        ).formatted
                                    )
                                    .monospacedDigit()
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .trailing
                                    )
                                }
                                .width(110)
                            }
                            .frame(minHeight: 260)
                        }
                    }

                    if differenceMinor != 0 {
                        Toggle(
                            "Differenz ausdrücklich als Ausgleichsbuchung anlegen",
                            isOn: $createAdjustment
                        )
                        Text(
                            "Die Ausgleichsbuchung wird mit Referenz "
                                + "„ABGLEICH“ protokolliert. Bei einer "
                                + "Rücknahme bleibt sie storniert als Auditspur erhalten."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    reconciliationHistory
                }
                .padding(24)
            }

            Divider()

            HStack {
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Abgleich abschließen") {
                    if differenceMinor != 0 && createAdjustment {
                        showAdjustmentConfirmation = true
                    } else {
                        completeReconciliation()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    accountID == nil
                        || endingBalanceMinor == nil
                        || (differenceMinor != 0 && !createAdjustment)
                )
            }
            .padding(18)
        }
        .frame(width: 900, height: 720)
        .onAppear {
            accountID = store.selectedAccountID ?? store.accounts.first?.id
            reload()
        }
        .onChange(of: accountID) { reload() }
        .onChange(of: statementDate) { reload() }
        .alert(
            "Ausgleichsbuchung bestätigen",
            isPresented: $showAdjustmentConfirmation
        ) {
            Button("Abbrechen", role: .cancel) {}
            Button("Differenz buchen und abgleichen") {
                completeReconciliation()
            }
        } message: {
            Text(
                "Es wird eine Ausgleichsbuchung über "
                    + formatted(differenceMinor)
                    + " angelegt. Diese Aktion wird auditiert."
            )
        }
        .confirmationDialog(
            "Jüngsten Kontoabgleich zurücknehmen?",
            isPresented: Binding(
                get: { reconciliationToRevert != nil },
                set: { if !$0 { reconciliationToRevert = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Abgleich zurücknehmen", role: .destructive) {
                guard let reconciliationToRevert else { return }
                if store.revertReconciliation(reconciliationToRevert) {
                    self.reconciliationToRevert = nil
                    reload()
                }
            }
            Button("Abbrechen", role: .cancel) {
                reconciliationToRevert = nil
            }
        } message: {
            Text(
                "Die Buchungen erhalten ihren vorherigen Status. "
                    + "Eine Ausgleichsbuchung wird storniert, nicht gelöscht."
            )
        }
    }

    private var selectedAccount: FinanceAccount? {
        accountID.flatMap { id in
            store.accounts.first { $0.id == id }
        }
    }

    private var endingBalanceMinor: Int64? {
        guard let account = selectedAccount else { return nil }
        return try? Money(
            parsing: endingBalance,
            currency: account.currency
        ).minorUnits
    }

    private var selectedSumMinor: Int64 {
        snapshot?.selectedSumMinor(selectedTransactionIDs) ?? 0
    }

    private var calculatedBalanceMinor: Int64 {
        (snapshot?.startingBalanceMinor ?? 0) + selectedSumMinor
    }

    private var differenceMinor: Int64 {
        guard let endingBalanceMinor else { return 0 }
        return endingBalanceMinor - calculatedBalanceMinor
    }

    private var reconciliationSummary: some View {
        Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 10) {
            GridRow {
                Text("Anfangssaldo")
                Text("Markierte Summe")
                Text("Berechneter Saldo")
                Text("Endsaldo des Auszugs")
                Text("Differenz")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            GridRow {
                Text(formatted(snapshot?.startingBalanceMinor ?? 0))
                Text(formatted(selectedSumMinor))
                Text(formatted(calculatedBalanceMinor))
                TextField("0,00", text: $endingBalance)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                Text(formatted(differenceMinor))
                    .foregroundStyle(differenceMinor == 0 ? .green : .red)
                    .fontWeight(.semibold)
            }
            .monospacedDigit()
        }
        .padding(14)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var reconciliationHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Abgleichshistorie")
                .font(.headline)
            if history.isEmpty {
                Text("Für dieses Konto gibt es noch keinen Kontoabgleich.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(history.prefix(6)) { value in
                    HStack {
                        Image(
                            systemName: value.revertedAt == nil
                                ? "checkmark.seal.fill"
                                : "arrow.uturn.backward.circle"
                        )
                        .foregroundStyle(
                            value.revertedAt == nil ? Color.green : .secondary
                        )
                        Text(
                            value.statementDate,
                            format: .dateTime
                                .day()
                                .month(.twoDigits)
                                .year()
                        )
                        Text(formatted(value.endingBalanceMinor))
                            .monospacedDigit()
                        if value.adjustmentTransactionID != nil {
                            Text("mit Ausgleichsbuchung")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if value.revertedAt != nil {
                            Text("zurückgenommen")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if value.canRevert {
                            Button("Zurücknehmen") {
                                reconciliationToRevert = value
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    private func formatted(_ value: Int64) -> String {
        Money(
            minorUnits: value,
            currency: selectedAccount?.currency ?? "EUR"
        ).formatted
    }

    private func reload() {
        guard let accountID else {
            snapshot = nil
            history = []
            selectedTransactionIDs.removeAll()
            return
        }
        guard let value = store.reconciliationSnapshot(
            accountID: accountID,
            date: statementDate
        ) else { return }
        snapshot = value
        history = store.reconciliationHistory(accountID: accountID)
        selectedTransactionIDs = Set(
            value.candidates.filter { $0.status == .cleared }.map(\.id)
        )
        let suggested = value.startingBalanceMinor
            + value.candidates.reduce(Int64.zero) { $0 + $1.amountMinor }
        endingBalance = NSDecimalNumber(
            decimal: Decimal(suggested) / Decimal(100)
        ).stringValue
        createAdjustment = false
    }

    private func completeReconciliation() {
        guard let accountID else { return }
        if store.reconcile(
            accountID: accountID,
            endingBalance: endingBalance,
            date: statementDate,
            selectedTransactionIDs: selectedTransactionIDs,
            createAdjustment: createAdjustment
        ) {
            reload()
        }
    }
}

struct ReportsView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var period: ReportPeriodPreset = .all
    @State private var customStart = Calendar.current.date(
        byAdding: .month,
        value: -1,
        to: .now
    ) ?? .now
    @State private var customEnd = Date.now
    @State private var selectedAccountIDs = Set<UUID>()
    @State private var selectedGroupIDs = Set<UUID>()
    @State private var selectedCategoryIDs = Set<UUID>()
    @State private var includeCategoryDescendants = true
    @State private var selectedTagIDs = Set<UUID>()
    @State private var selectedPayeeIDs = Set<UUID>()
    @State private var statuses = Set(
        TransactionStatus.allCases.filter { $0 != .cancelled }
    )
    @State private var selectedCurrencies = Set<String>()
    @State private var minimumAmount = ""
    @State private var maximumAmount = ""
    @State private var reportText = ""
    @State private var includeHiddenAccounts = false
    @State private var includeExcludedAccounts = false
    @State private var includeTransfers = false
    @State private var expandSplits = true
    @State private var grouping: ReportGrouping = .category
    @State private var sort: ReportSort = .amountDescending
    @State private var selectedReportGroupID: String?
    @State private var selectedTemplateID: UUID?
    @State private var showTemplateSave = false
    @State private var templateName = ""
    @State private var csvSeparator: ReportCSVSeparator = .semicolon
    @State private var csvEncoding: ReportCSVEncoding = .utf8
    @State private var csvDocument = ReportCSVDocument(data: Data())
    @State private var showCSVExporter = false
    @State private var pdfOrientation: ReportPDFOrientation = .landscape
    @State private var pdfDocument = ReportPDFDocument(data: Data())
    @State private var showPDFExporter = false

    private var query: TransactionReportQuery {
        let range = period.range(customStart: customStart, customEnd: customEnd)
        return TransactionReportQuery(
            dateFrom: range.start,
            dateThrough: range.end,
            accountIDs: selectedAccountIDs,
            accountGroupIDs: selectedGroupIDs,
            categoryIDs: selectedCategoryIDs,
            includeCategoryDescendants: includeCategoryDescendants,
            tagIDs: selectedTagIDs,
            payeeIDs: selectedPayeeIDs,
            statuses: statuses,
            minimumAmountMinor: parsedAbsoluteAmount(minimumAmount),
            maximumAmountMinor: parsedAbsoluteAmount(maximumAmount),
            text: reportText,
            currencies: selectedCurrencies,
            includeHiddenAccounts: includeHiddenAccounts,
            includeAccountsExcludedFromReports: includeExcludedAccounts,
            includeTransfers: includeTransfers,
            expandSplits: expandSplits,
            grouping: grouping,
            sort: sort
        )
    }

    var body: some View {
        let snapshot = store.transactionReport(query)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Berichtswerkstatt")
                        .font(.title2.bold())
                    Text("Live-Auswertung mit Filtern, Gruppierung und Buchungs-Drill-down")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(snapshot.facts.count) Auswertungspositionen")
                        .font(.headline)
                    Text(
                        expandSplits
                            ? "Splitbuchungen werden nach Splitzeilen ausgewertet."
                            : "Splitbuchungen werden als Gesamtbuchung ausgewertet."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            Divider()

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Picker("Vorlage", selection: $selectedTemplateID) {
                        Text("Keine Vorlage").tag(UUID?.none)
                        ForEach(store.reportTemplates) { template in
                            Text(template.name).tag(UUID?.some(template.id))
                        }
                    }
                    .frame(width: 270)
                    Button("Vorlage laden", systemImage: "doc.text.magnifyingglass") {
                        loadSelectedTemplate()
                    }
                    .disabled(selectedTemplateID == nil)
                    Button("Vorlage speichern …", systemImage: "square.and.arrow.down") {
                        templateName = selectedTemplateID.flatMap { id in
                            store.reportTemplates.first { $0.id == id }?.name
                        } ?? ""
                        showTemplateSave = true
                    }
                    Button("Vorlage löschen", systemImage: "trash", role: .destructive) {
                        deleteSelectedTemplate()
                    }
                    .disabled(selectedTemplateID == nil)
                    Spacer()
                    Picker("Trennzeichen", selection: $csvSeparator) {
                        ForEach(ReportCSVSeparator.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .frame(width: 145)
                    Picker("Encoding", selection: $csvEncoding) {
                        ForEach(ReportCSVEncoding.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .frame(width: 130)
                    Button("CSV exportieren …", systemImage: "tablecells") {
                        prepareCSVExport(snapshot)
                    }
                    Menu {
                        Picker("Papierausrichtung", selection: $pdfOrientation) {
                            ForEach(ReportPDFOrientation.allCases) {
                                Text($0.title).tag($0)
                            }
                        }
                        Divider()
                        Button("PDF exportieren …", systemImage: "doc.richtext") {
                            preparePDFExport(snapshot)
                        }
                    } label: {
                        Label("PDF · \(pdfOrientation.title)", systemImage: "printer")
                    }
                }

                HStack(spacing: 10) {
                    Picker("Zeitraum", selection: $period) {
                        ForEach(ReportPeriodPreset.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .frame(width: 175)
                    if period == .custom {
                        DatePicker("Von", selection: $customStart, displayedComponents: .date)
                            .labelsHidden()
                        Text("bis").foregroundStyle(.secondary)
                        DatePicker("Bis", selection: $customEnd, displayedComponents: .date)
                            .labelsHidden()
                    }
                    accountFilterMenu
                    categoryFilterMenu
                    tagFilterMenu
                    payeeFilterMenu
                    statusFilterMenu
                    currencyFilterMenu
                    Spacer()
                }

                HStack(spacing: 10) {
                    TextField("Volltext: Empfänger, Zweck, Memo, Kategorie …", text: $reportText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 240, maxWidth: 390)
                    TextField("Betrag von", text: $minimumAmount)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    TextField("bis", text: $maximumAmount)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Picker("Gruppieren", selection: $grouping) {
                        ForEach(ReportGrouping.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .frame(width: 175)
                    Picker("Sortieren", selection: $sort) {
                        ForEach(ReportSort.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .frame(width: 185)
                    optionsMenu
                    Spacer()
                    Button("Zurücksetzen", systemImage: "arrow.counterclockwise") {
                        resetFilters()
                    }
                    .disabled(!hasActiveFilter)
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if grouping == .none {
                reportFactsTable(snapshot.facts)
            } else {
                HSplitView {
                    reportGroupsTable(snapshot.groups)
                        .frame(minWidth: 370, idealWidth: 470)
                    VStack(spacing: 0) {
                        if let selectedReportGroupID,
                           let group = snapshot.groups.first(where: {
                               $0.id == selectedReportGroupID
                           }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.label).font(.headline)
                                    Text(
                                        "\(group.bookingCount) Positionen · "
                                            + Money(
                                                minorUnits: group.netMinor,
                                                currency: group.currency
                                            ).formatted
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("Drill-down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            Divider()
                            reportFactsTable(snapshot.facts(inGroupID: selectedReportGroupID))
                        } else {
                            ContentUnavailableView(
                                "Gruppe auswählen",
                                systemImage: "cursorarrow.click.2",
                                description: Text(
                                    "Wähle links eine Gruppe, um die zugrunde liegenden "
                                        + "Buchungen und Splitzeilen zu sehen."
                                )
                            )
                        }
                    }
                    .frame(minWidth: 500)
                }
            }

            Divider()
            reportTotals(snapshot.totals)
        }
        .onChange(of: grouping) {
            selectedReportGroupID = nil
        }
        .onChange(of: snapshot.groups.map(\.id)) {
            if let selectedReportGroupID,
               !snapshot.groups.contains(where: { $0.id == selectedReportGroupID }) {
                self.selectedReportGroupID = nil
            }
        }
        .sheet(isPresented: $showTemplateSave) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Berichtsvorlage speichern")
                    .font(.title2.bold())
                Text(
                    "Gespeichert werden alle aktuellen Filter, die Splitbehandlung, "
                        + "Gruppierung und Sortierung."
                )
                .foregroundStyle(.secondary)
                TextField("Name der Vorlage", text: $templateName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Abbrechen", role: .cancel) { showTemplateSave = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Speichern") { saveCurrentTemplate() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(
                            templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
            }
            .padding(24)
            .frame(width: 480)
        }
        .fileExporter(
            isPresented: $showCSVExporter,
            document: csvDocument,
            contentType: .commaSeparatedText,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                store.statusText = "Bericht als CSV exportiert"
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showPDFExporter,
            document: pdfDocument,
            contentType: .pdf,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                store.statusText = "Druckfertigen Bericht als PDF exportiert"
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
    }

    private var accountFilterMenu: some View {
        Menu {
            Button("Alle Konten") {
                selectedAccountIDs.removeAll()
                selectedGroupIDs.removeAll()
            }
            if !store.accountGroups.isEmpty {
                Section("Kontengruppen") {
                    ForEach(store.accountGroups.filter(\.isActive)) { group in
                        Toggle(
                            group.name,
                            isOn: memberBinding(group.id, in: $selectedGroupIDs)
                        )
                    }
                }
            }
            Section("Einzelkonten") {
                ForEach(store.accounts) { account in
                    Toggle(
                        account.name,
                        isOn: memberBinding(account.id, in: $selectedAccountIDs)
                    )
                }
            }
        } label: {
            Label(
                filterTitle(
                    "Konten",
                    count: selectedAccountIDs.count + selectedGroupIDs.count
                ),
                systemImage: "building.columns"
            )
        }
    }

    private var categoryFilterMenu: some View {
        Menu {
            Button("Alle Kategorien") { selectedCategoryIDs.removeAll() }
            Toggle("Unterkategorien einbeziehen", isOn: $includeCategoryDescendants)
            Divider()
            ForEach(store.categoriesByPath.filter(\.isActive)) { category in
                Toggle(
                    store.categoryPath(category.id),
                    isOn: memberBinding(category.id, in: $selectedCategoryIDs)
                )
            }
        } label: {
            Label(
                filterTitle("Kategorien", count: selectedCategoryIDs.count),
                systemImage: "tag"
            )
        }
    }

    private var tagFilterMenu: some View {
        Menu {
            Button("Alle Klassen/Tags") { selectedTagIDs.removeAll() }
            ForEach(store.tags.filter(\.isActive)) { tag in
                Toggle(
                    store.tagName(tag.id),
                    isOn: memberBinding(tag.id, in: $selectedTagIDs)
                )
            }
        } label: {
            Label(
                filterTitle("Klassen/Tags", count: selectedTagIDs.count),
                systemImage: "number"
            )
        }
    }

    private var payeeFilterMenu: some View {
        Menu {
            Button("Alle Empfänger") { selectedPayeeIDs.removeAll() }
            ForEach(store.payees.filter(\.isActive)) { payee in
                Toggle(
                    payee.canonicalName,
                    isOn: memberBinding(payee.id, in: $selectedPayeeIDs)
                )
            }
        } label: {
            Label(
                filterTitle("Empfänger", count: selectedPayeeIDs.count),
                systemImage: "person"
            )
        }
    }

    private var statusFilterMenu: some View {
        Menu {
            Button("Alle regulären Status") {
                statuses = Set(TransactionStatus.allCases.filter { $0 != .cancelled })
            }
            Button("Alle einschließlich Storniert") {
                statuses = Set(TransactionStatus.allCases)
            }
            Divider()
            ForEach(TransactionStatus.allCases, id: \.self) { status in
                Toggle(
                    status.title,
                    isOn: memberBinding(status, in: $statuses)
                )
            }
        } label: {
            Label(
                "Status \(statuses.count)/\(TransactionStatus.allCases.count)",
                systemImage: "checkmark.circle"
            )
        }
    }

    private var currencyFilterMenu: some View {
        let currencies = Set(store.transactions.map { $0.currency.uppercased() }).sorted()
        return Menu {
            Button("Alle Währungen") { selectedCurrencies.removeAll() }
            ForEach(currencies, id: \.self) { currency in
                Toggle(
                    currency,
                    isOn: memberBinding(currency, in: $selectedCurrencies)
                )
            }
        } label: {
            Label(
                filterTitle("Währungen", count: selectedCurrencies.count),
                systemImage: "eurosign.arrow.circlepath"
            )
        }
    }

    private var optionsMenu: some View {
        Menu {
            Toggle("Umbuchungen einbeziehen", isOn: $includeTransfers)
            Toggle("Splitzeilen einzeln auswerten", isOn: $expandSplits)
            Toggle("Ausgeblendete/geschlossene Konten", isOn: $includeHiddenAccounts)
            Toggle(
                "Von Berichten ausgeschlossene Konten",
                isOn: $includeExcludedAccounts
            )
        } label: {
            Label("Optionen", systemImage: "slider.horizontal.3")
        }
    }

    private func reportGroupsTable(
        _ groups: [TransactionReportGroup]
    ) -> some View {
        Table(groups, selection: $selectedReportGroupID) {
            TableColumn(grouping.title) { group in
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.label)
                        .lineLimit(2)
                    Text("\(group.bookingCount) Positionen · \(group.currency)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 150, ideal: 220)
            TableColumn("Einnahmen") { group in
                reportMoney(group.incomeMinor, currency: group.currency)
            }
            .width(105)
            TableColumn("Ausgaben") { group in
                reportMoney(group.expenseMinor, currency: group.currency)
            }
            .width(105)
            TableColumn("Saldo") { group in
                reportMoney(group.netMinor, currency: group.currency)
            }
            .width(105)
        }
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView(
                    "Keine Gruppen",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("Die gewählten Filter liefern keine auswertbaren Positionen.")
                )
            }
        }
    }

    private func reportFactsTable(
        _ facts: [TransactionReportFact]
    ) -> some View {
        Table(facts) {
            TableColumn("Datum") {
                Text($0.bookingDate, format: .dateTime.day().month(.twoDigits).year())
                    .monospacedDigit()
            }
            .width(90)
            TableColumn("Konto") {
                Text($0.accountName).lineLimit(1)
            }
            .width(min: 105, ideal: 135)
            TableColumn("Empfänger") {
                Text($0.payee.isEmpty ? "—" : $0.payee).lineLimit(1)
            }
            .width(min: 115, ideal: 155)
            TableColumn("Verwendungszweck") { fact in
                Text(fact.purpose)
                    .lineLimit(1)
                    .help([fact.purpose, fact.detail].filter { !$0.isEmpty }.joined(separator: "\n"))
            }
            .width(min: 150, ideal: 220)
            TableColumn("Kategorie") {
                Text($0.categoryPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help($0.categoryPath)
            }
            .width(min: 150, ideal: 210)
            TableColumn("Status") {
                Text($0.splitID == nil ? $0.status.title : "\($0.status.title) · Split")
            }
            .width(105)
            TableColumn("Betrag") { fact in
                reportMoney(fact.amountMinor, currency: fact.currency)
            }
            .width(115)
        }
        .overlay {
            if facts.isEmpty {
                ContentUnavailableView(
                    "Keine Buchungen",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Passe die Filter an oder wähle eine andere Gruppe.")
                )
            }
        }
    }

    private func reportTotals(
        _ totals: [TransactionReportCurrencyTotal]
    ) -> some View {
        HStack(spacing: 14) {
            Text("Gesamtsummen")
                .fontWeight(.semibold)
            ForEach(totals) { total in
                Text(
                    "\(total.currency): "
                        + "Einnahmen \(Money(minorUnits: total.incomeMinor, currency: total.currency).formatted) · "
                        + "Ausgaben \(Money(minorUnits: total.expenseMinor, currency: total.currency).formatted) · "
                        + "Saldo \(Money(minorUnits: total.netMinor, currency: total.currency).formatted)"
                )
                .monospacedDigit()
            }
            if totals.isEmpty {
                Text("Keine Werte").foregroundStyle(.secondary)
            }
            Spacer()
            Text("Live-Momentaufnahme")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func reportMoney(_ amount: Int64, currency: String) -> some View {
        Text(Money(minorUnits: amount, currency: currency).formatted)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .monospacedDigit()
    }

    private func memberBinding<Value: Hashable>(
        _ value: Value,
        in selection: Binding<Set<Value>>
    ) -> Binding<Bool> {
        Binding(
            get: { selection.wrappedValue.contains(value) },
            set: { isSelected in
                if isSelected {
                    selection.wrappedValue.insert(value)
                } else {
                    selection.wrappedValue.remove(value)
                }
            }
        )
    }

    private func filterTitle(_ title: String, count: Int) -> String {
        count == 0 ? title : "\(title) (\(count))"
    }

    private func parsedAbsoluteAmount(_ value: String) -> Int64? {
        guard let parsed = try? Money(parsing: value).minorUnits else { return nil }
        return parsed == Int64.min ? Int64.max : abs(parsed)
    }

    private var hasActiveFilter: Bool {
        period != .all
            || !selectedAccountIDs.isEmpty
            || !selectedGroupIDs.isEmpty
            || !selectedCategoryIDs.isEmpty
            || !selectedTagIDs.isEmpty
            || !selectedPayeeIDs.isEmpty
            || statuses != Set(TransactionStatus.allCases.filter { $0 != .cancelled })
            || !selectedCurrencies.isEmpty
            || !minimumAmount.isEmpty
            || !maximumAmount.isEmpty
            || !reportText.isEmpty
            || includeHiddenAccounts
            || includeExcludedAccounts
            || includeTransfers
            || !expandSplits
            || grouping != .category
            || sort != .amountDescending
    }

    private func resetFilters() {
        period = .all
        selectedAccountIDs.removeAll()
        selectedGroupIDs.removeAll()
        selectedCategoryIDs.removeAll()
        includeCategoryDescendants = true
        selectedTagIDs.removeAll()
        selectedPayeeIDs.removeAll()
        statuses = Set(TransactionStatus.allCases.filter { $0 != .cancelled })
        selectedCurrencies.removeAll()
        minimumAmount = ""
        maximumAmount = ""
        reportText = ""
        includeHiddenAccounts = false
        includeExcludedAccounts = false
        includeTransfers = false
        expandSplits = true
        grouping = .category
        sort = .amountDescending
        selectedReportGroupID = nil
        selectedTemplateID = nil
    }

    private func saveCurrentTemplate() {
        let id = selectedTemplateID ?? UUID()
        let template = SavedReportTemplate(
            id: id,
            name: templateName,
            definitionVersion: 1,
            query: query
        )
        if store.saveReportTemplate(template) {
            selectedTemplateID = id
            showTemplateSave = false
        }
    }

    private func loadSelectedTemplate() {
        guard let selectedTemplateID,
              let template = store.reportTemplates.first(where: { $0.id == selectedTemplateID })
        else { return }
        apply(template.query)
    }

    private func deleteSelectedTemplate() {
        guard let selectedTemplateID,
              let template = store.reportTemplates.first(where: { $0.id == selectedTemplateID })
        else { return }
        store.deleteReportTemplate(template)
        self.selectedTemplateID = nil
    }

    private func apply(_ savedQuery: TransactionReportQuery) {
        if savedQuery.dateFrom == nil && savedQuery.dateThrough == nil {
            period = .all
        } else {
            period = .custom
            customStart = savedQuery.dateFrom ?? savedQuery.dateThrough ?? .now
            customEnd = savedQuery.dateThrough ?? savedQuery.dateFrom ?? .now
        }
        selectedAccountIDs = savedQuery.accountIDs
        selectedGroupIDs = savedQuery.accountGroupIDs
        selectedCategoryIDs = savedQuery.categoryIDs
        includeCategoryDescendants = savedQuery.includeCategoryDescendants
        selectedTagIDs = savedQuery.tagIDs
        selectedPayeeIDs = savedQuery.payeeIDs
        statuses = savedQuery.statuses
        selectedCurrencies = savedQuery.currencies
        minimumAmount = savedQuery.minimumAmountMinor.map(decimalAmount) ?? ""
        maximumAmount = savedQuery.maximumAmountMinor.map(decimalAmount) ?? ""
        reportText = savedQuery.text
        includeHiddenAccounts = savedQuery.includeHiddenAccounts
        includeExcludedAccounts = savedQuery.includeAccountsExcludedFromReports
        includeTransfers = savedQuery.includeTransfers
        expandSplits = savedQuery.expandSplits
        grouping = savedQuery.grouping
        sort = savedQuery.sort
        selectedReportGroupID = nil
    }

    private func prepareCSVExport(_ snapshot: TransactionReportSnapshot) {
        do {
            let options = ReportCSVOptions(
                separator: csvSeparator,
                encoding: csvEncoding
            )
            let metadata = ReportExportMetadata(
                title: selectedTemplateID.flatMap { id in
                    store.reportTemplates.first { $0.id == id }?.name
                } ?? "\(grouping.title)-Bericht",
                dateLabel: reportDateLabel,
                filterSummary: reportFilterSummary,
                baseCurrency: store.fileInfo?.baseCurrency ?? "EUR",
                generatedAt: .now
            )
            csvDocument = ReportCSVDocument(
                data: try TransactionReportCSVExporter.data(
                    snapshot: snapshot,
                    metadata: metadata,
                    options: options
                )
            )
            showCSVExporter = true
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func preparePDFExport(_ snapshot: TransactionReportSnapshot) {
        do {
            pdfDocument = ReportPDFDocument(
                data: try TransactionReportPDFExporter.data(
                    snapshot: snapshot,
                    metadata: reportExportMetadata,
                    options: ReportPDFOptions(orientation: pdfOrientation)
                )
            )
            showPDFExporter = true
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private var reportExportMetadata: ReportExportMetadata {
        ReportExportMetadata(
            title: selectedTemplateID.flatMap { id in
                store.reportTemplates.first { $0.id == id }?.name
            } ?? "\(grouping.title)-Bericht",
            dateLabel: reportDateLabel,
            filterSummary: reportFilterSummary,
            baseCurrency: store.fileInfo?.baseCurrency ?? "EUR",
            generatedAt: .now
        )
    }

    private var reportDateLabel: String {
        guard period == .custom else { return period.title }
        return "\(customStart.formatted(date: .numeric, time: .omitted))"
            + " – \(customEnd.formatted(date: .numeric, time: .omitted))"
    }

    private var reportFilterSummary: String {
        [
            selectedAccountIDs.isEmpty && selectedGroupIDs.isEmpty
                ? "alle Berichtskonten"
                : "\(selectedAccountIDs.count) Konten, \(selectedGroupIDs.count) Gruppen",
            selectedCategoryIDs.isEmpty
                ? "alle Kategorien"
                : "\(selectedCategoryIDs.count) Kategorien",
            selectedTagIDs.isEmpty ? "alle Klassen/Tags" : "\(selectedTagIDs.count) Klassen/Tags",
            selectedPayeeIDs.isEmpty ? "alle Empfänger" : "\(selectedPayeeIDs.count) Empfänger",
            "Status \(statuses.count)/\(TransactionStatus.allCases.count)",
            reportText.isEmpty ? "kein Volltext" : "Volltext: \(reportText)",
            includeTransfers ? "mit Umbuchungen" : "ohne Umbuchungen",
            expandSplits ? "Splitzeilen" : "Gesamtbuchungen"
        ].joined(separator: " · ")
    }

    private var exportFilename: String {
        let raw = selectedTemplateID.flatMap { id in
            store.reportTemplates.first { $0.id == id }?.name
        } ?? "FinanzVerwalter-Bericht"
        let safe = raw.replacingOccurrences(
            of: #"[^A-Za-z0-9ÄÖÜäöüß_-]+"#,
            with: "-",
            options: .regularExpression
        )
        return safe.isEmpty ? "FinanzVerwalter-Bericht" : safe
    }

    private func decimalAmount(_ minorUnits: Int64) -> String {
        let magnitude = minorUnits.magnitude
        return "\(magnitude / 100),\(magnitude % 100 < 10 ? "0" : "")\(magnitude % 100)"
    }
}

private enum ReportPeriodPreset: String, CaseIterable, Identifiable {
    case all
    case currentMonth
    case currentQuarter
    case currentYear
    case previousYear
    case rolling30
    case rolling90
    case rolling365
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "Gesamter Zeitraum"
        case .currentMonth: "Aktueller Monat"
        case .currentQuarter: "Aktuelles Quartal"
        case .currentYear: "Aktuelles Jahr"
        case .previousYear: "Vorjahr"
        case .rolling30: "Letzte 30 Tage"
        case .rolling90: "Letzte 90 Tage"
        case .rolling365: "Letzte 365 Tage"
        case .custom: "Benutzerdefiniert"
        }
    }

    func range(
        now: Date = .now,
        customStart: Date,
        customEnd: Date
    ) -> (start: Date?, end: Date?) {
        let calendar = Calendar.current
        switch self {
        case .all:
            return (nil, nil)
        case .currentMonth:
            return intervalRange(calendar.dateInterval(of: .month, for: now), calendar: calendar)
        case .currentQuarter:
            let components = calendar.dateComponents([.year, .month], from: now)
            let month = components.month ?? 1
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            let start = calendar.date(
                from: DateComponents(year: components.year, month: quarterStartMonth, day: 1)
            ) ?? now
            let end = calendar.date(byAdding: .month, value: 3, to: start) ?? now
            return (start, end.addingTimeInterval(-0.001))
        case .currentYear:
            return intervalRange(calendar.dateInterval(of: .year, for: now), calendar: calendar)
        case .previousYear:
            let prior = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return intervalRange(calendar.dateInterval(of: .year, for: prior), calendar: calendar)
        case .rolling30:
            return rollingRange(days: 30, now: now, calendar: calendar)
        case .rolling90:
            return rollingRange(days: 90, now: now, calendar: calendar)
        case .rolling365:
            return rollingRange(days: 365, now: now, calendar: calendar)
        case .custom:
            let start = calendar.startOfDay(for: min(customStart, customEnd))
            let nextDay = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: max(customStart, customEnd))
            ) ?? max(customStart, customEnd)
            return (start, nextDay.addingTimeInterval(-0.001))
        }
    }

    private func intervalRange(
        _ interval: DateInterval?,
        calendar: Calendar
    ) -> (start: Date?, end: Date?) {
        guard let interval else { return (nil, nil) }
        return (interval.start, interval.end.addingTimeInterval(-0.001))
    }

    private func rollingRange(
        days: Int,
        now: Date,
        calendar: Calendar
    ) -> (start: Date?, end: Date?) {
        let endOfToday = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        )?.addingTimeInterval(-0.001) ?? now
        let start = calendar.date(
            byAdding: .day,
            value: -(days - 1),
            to: calendar.startOfDay(for: now)
        )
        return (start, endOfToday)
    }
}

private struct ReportCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct ReportPDFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct ImportExportView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @AppStorage("importMatchDateWindowDaysV1")
    private var importMatchDateWindowDays =
        ImportMatcher.defaultDateWindowDays
    @State private var selectedAccountID: UUID?
    @State private var showImporter = false
    @State private var preview: ImportPreview?
    @State private var qifPackagePreview: QIFPackagePreview?
    @State private var importResolutions: [UUID: ImportResolution] = [:]
    @State private var showBackupExporter = false
    @State private var backupDocument = BackupDocument(data: Data())
    @State private var showRestoreImporter = false
    @State private var stagedRestoreURL: URL?
    @State private var confirmRestore = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Import, Export & Sicherung").font(.largeTitle.bold())

                GroupBox("CSV-/TSV- und QIF-Import") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CSV/TSV und einzelne QIF-Kontoblätter benötigen ein Zielkonto. Vollständige QIF-Pakete werden automatisch erkannt und kontoweise vorbereitet.")
                            .foregroundStyle(.secondary)
                        HStack {
                            Picker("Zielkonto für Einzeldatei", selection: $selectedAccountID) {
                                Text("Bitte wählen").tag(UUID?.none)
                                ForEach(store.accounts) { Text($0.name).tag(UUID?.some($0.id)) }
                            }
                            .frame(maxWidth: 360)
                            Button("Datei auswählen …", systemImage: "doc.badge.plus") {
                                showImporter = true
                            }
                        }
                        Stepper(
                            "Abgleichsfenster: \(importMatchDateWindowDays) "
                                + "Tag\(importMatchDateWindowDays == 1 ? "" : "e")",
                            value: $importMatchDateWindowDays,
                            in: 0...14
                        )
                        .help(
                            "Buchungen mit abweichendem Buchungs- oder "
                                + "Wertstellungsdatum werden nur innerhalb "
                                + "dieses Fensters als mögliche Treffer gezeigt."
                        )
                        Text("Bei einem Mehrkonten-QIF ist keine vorherige Kontoauswahl nötig.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                if let package = qifPackagePreview {
                    GroupBox("QIF-Paketvorschau") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 20) {
                                Label(
                                    "\(package.summary.accountDefinitions) Konten erkannt",
                                    systemImage: "building.columns"
                                )
                                Label(
                                    "\(package.categoriesToCreate.count) neue Kategorien",
                                    systemImage: "tag"
                                )
                                Label(
                                    "\(package.importPreview.rows.count) Buchungen",
                                    systemImage: "list.bullet.rectangle"
                                )
                            }
                            if !package.accountsToCreate.isEmpty {
                                Text("Neu anzulegende Konten")
                                    .font(.headline)
                                Text(package.accountsToCreate.map(\.name).joined(separator: " · "))
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .lineLimit(3)
                            }
                            ForEach(package.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                            matchingSummary(package.importPreview)
                            Table(package.importPreview.rows.prefix(100)) {
                                TableColumn("Datum") {
                                    Text($0.bookingDate, format: .dateTime.day().month().year())
                                }
                                TableColumn("Konto") { transaction in
                                    Text(
                                        package.accountsToCreate.first { account in
                                            account.id == transaction.accountID
                                        }?.name ?? store.accountName(transaction.accountID)
                                    )
                                }
                                TableColumn("Empfänger", value: \.payee)
                                TableColumn("Zweck", value: \.purpose)
                                TableColumn("Betrag") {
                                    Text(Money(minorUnits: $0.amountMinor).formatted)
                                        .monospacedDigit()
                                }
                                TableColumn("Importentscheidung") { transaction in
                                    importResolutionPicker(
                                        transaction,
                                        preview: package.importPreview
                                    )
                                }
                                .width(min: 190, ideal: 260)
                            }
                            .frame(height: 260)
                            HStack {
                                Button("Verwerfen") { qifPackagePreview = nil }
                                Button("Alle weichen Treffer als neu") {
                                    markSoftCandidatesAsNew(
                                        package.importPreview
                                    )
                                }
                                Button("Paket ausdrücklich übernehmen") {
                                    if store.commitQIFPackage(
                                        package,
                                        resolutions: importResolutions
                                    ) {
                                        qifPackagePreview = nil
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(package.importPreview.rows.isEmpty)
                            }
                        }
                        .padding(8)
                    }
                }

                if let preview {
                    GroupBox("Importvorschau") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(preview.rows.count) gültige · \(preview.rejectedRows.count) fehlerhafte Zeilen")
                            matchingSummary(preview)
                            Table(preview.rows.prefix(100)) {
                                TableColumn("Datum") {
                                    Text($0.bookingDate, format: .dateTime.day().month().year())
                                }
                                TableColumn("Empfänger", value: \.payee)
                                TableColumn("Zweck", value: \.purpose)
                                TableColumn("Betrag") {
                                    Text(Money(minorUnits: $0.amountMinor).formatted)
                                        .monospacedDigit()
                                }
                                TableColumn("Importentscheidung") { transaction in
                                    importResolutionPicker(
                                        transaction,
                                        preview: preview
                                    )
                                }
                                .width(min: 190, ideal: 260)
                            }
                            .frame(height: 220)
                            HStack {
                                Button("Verwerfen") { self.preview = nil }
                                Button("Alle weichen Treffer als neu") {
                                    markSoftCandidatesAsNew(preview)
                                }
                                Button("Import ausdrücklich übernehmen") {
                                    if store.commitImport(
                                        preview,
                                        resolutions: importResolutions
                                    ) {
                                        self.preview = nil
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(8)
                    }
                }

                GroupBox("Datensicherheit") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Vollständige SQLite-Sicherung")
                            Text("Die Sicherung wird atomar erstellt und anschließend mit SQLite geprüft.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Integrität prüfen") { store.checkIntegrity() }
                        Button("Sicherung erstellen …") {
                            guard let data = store.backupData() else { return }
                            backupDocument = BackupDocument(data: data)
                            showBackupExporter = true
                        }
                        Button("Wiederherstellen …") { showRestoreImporter = true }
                    }
                    .padding(8)
                }
            }
            .padding(22)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [
                .commaSeparatedText, .tabSeparatedText, .plainText,
                UTType(filenameExtension: "qif") ?? .data
            ]
        ) { result in
            guard
                let url = try? result.get(),
                url.startAccessingSecurityScopedResource()
            else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { return }
            if url.pathExtension.lowercased() == "qif" {
                if QIFPackageImporter.isPackage(data: data) {
                    qifPackagePreview = store.previewQIFPackage(
                        data: data,
                        dateWindowDays: importMatchDateWindowDays
                    )
                    preview = nil
                    if let qifPackagePreview {
                        prepareResolutions(qifPackagePreview.importPreview)
                    }
                } else if let selectedAccountID {
                    preview = store.importQIF(
                        data: data,
                        accountID: selectedAccountID,
                        dateWindowDays: importMatchDateWindowDays
                    )
                    qifPackagePreview = nil
                    if let preview { prepareResolutions(preview) }
                } else {
                    store.errorMessage = FinanceError.missingAccount.localizedDescription
                }
            } else if let selectedAccountID {
                preview = store.importCSV(
                    data: data,
                    accountID: selectedAccountID,
                    dateWindowDays: importMatchDateWindowDays
                )
                qifPackagePreview = nil
                if let preview { prepareResolutions(preview) }
            } else {
                store.errorMessage = FinanceError.missingAccount.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showBackupExporter,
            document: backupDocument,
            contentType: .database,
            defaultFilename: "FinanzVerwalter-Sicherung-\(Date.now.formatted(.iso8601.year().month().day())).qbackup"
        ) { _ in }
        .fileImporter(
            isPresented: $showRestoreImporter,
            allowedContentTypes: [.database, .data]
        ) { result in
            guard
                let source = try? result.get(),
                source.startAccessingSecurityScopedResource()
            else { return }
            defer { source.stopAccessingSecurityScopedResource() }
            let staged = FileManager.default.temporaryDirectory
                .appendingPathComponent("finanzverwalter-restore-\(UUID().uuidString).qbackup")
            do {
                try FileManager.default.copyItem(at: source, to: staged)
                try SQLiteFinanceStore.validateBackup(at: staged)
                stagedRestoreURL = staged
                confirmRestore = true
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
        .alert("Sicherung wiederherstellen?", isPresented: $confirmRestore) {
            Button("Abbrechen", role: .cancel) { stagedRestoreURL = nil }
            Button("Validiert wiederherstellen", role: .destructive) {
                if let stagedRestoreURL {
                    _ = store.restoreBackup(from: stagedRestoreURL)
                }
                self.stagedRestoreURL = nil
            }
        } message: {
            Text("Vor dem Austausch wird automatisch eine geprüfte Sicherung der aktuellen Finanzdatei angelegt.")
        }
    }

    @ViewBuilder
    private func matchingSummary(_ preview: ImportPreview) -> some View {
        let assessments = Array(preview.matches.values)
        let exact = assessments.filter {
            $0.bestCandidate?.tier == .exactExternalID
        }.count
        let suggested = assessments.filter {
            if case .match = importResolutions[$0.rowID]
                ?? $0.suggestedResolution {
                return true
            }
            return false
        }.count
        let candidates = assessments.filter { !$0.candidates.isEmpty }.count
        HStack(spacing: 18) {
            Label("\(exact) bereits vorhanden", systemImage: "checkmark.shield")
            Label("\(suggested) zum Abgleich", systemImage: "arrow.triangle.merge")
            Label("\(candidates) mit Kandidaten", systemImage: "person.2.crop.square.stack")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private func importResolutionPicker(
        _ transaction: FinanceTransaction,
        preview: ImportPreview
    ) -> some View {
        let assessment = preview.matches[transaction.id]
        return Picker(
            "Importentscheidung",
            selection: Binding(
                get: {
                    importResolutions[transaction.id]
                        ?? assessment?.suggestedResolution
                        ?? .importNew
                },
                set: { importResolutions[transaction.id] = $0 }
            )
        ) {
            Text("Neu importieren").tag(ImportResolution.importNew)
            Text("Überspringen").tag(ImportResolution.skip)
            ForEach(
                assessment?.candidates.filter(\.isFinanciallyCompatible)
                    ?? []
            ) { candidate in
                Text(candidateLabel(candidate))
                    .tag(ImportResolution.match(candidate.transactionID))
            }
        }
        .labelsHidden()
        .help(
            assessment?.bestCandidate?.reasons.joined(separator: "\n")
                ?? "Kein ähnlicher bestehender Umsatz gefunden"
        )
    }

    private func candidateLabel(_ candidate: ImportMatchCandidate) -> String {
        guard let value = store.transactions.first(where: {
            $0.id == candidate.transactionID
        }) else {
            return "\(candidate.tier.title) · \(candidate.score) Punkte"
        }
        let payee = value.payee.isEmpty ? value.purpose : value.payee
        let date = value.bookingDate.formatted(
            .dateTime.day().month().year()
        )
        let amount = Money(minorUnits: value.amountMinor).formatted
        return "Abgleichen: \(payee) · \(date) · \(amount) · "
            + "\(candidate.score)"
    }

    private func prepareResolutions(_ preview: ImportPreview) {
        importResolutions = Dictionary(
            uniqueKeysWithValues: preview.rows.map {
                (
                    $0.id,
                    preview.matches[$0.id]?.suggestedResolution
                        ?? .importNew
                )
            }
        )
    }

    private func markSoftCandidatesAsNew(_ preview: ImportPreview) {
        for row in preview.rows {
            let hasExactExternalID = preview.matches[row.id]?.candidates
                .contains { $0.tier == .exactExternalID } == true
            importResolutions[row.id] = hasExactExternalID
                ? .skip : .importNew
        }
    }
}

private struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.database] }
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw FinanceError.invalidBackup
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.light.rawValue
    @State private var categoryName = ""
    @State private var categoryKind: CategoryKind = .expense
    @State private var editedPayee: FinancePayee?
    @State private var editedTag: FinanceTag?
    @State private var editedVATCode: VATCode?

    var body: some View {
        Form {
            Section("Darstellung") {
                Picker("Erscheinungsbild", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.icon).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text("Die Auswahl gilt sofort für alle FinanzVerwalter-Fenster und bleibt nach dem Neustart erhalten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ShortcutSettingsSection()
            Section("Finanzdatei") {
                LabeledContent("Name", value: store.fileInfo?.name ?? "—")
                LabeledContent("Basiswährung", value: store.fileInfo?.baseCurrency ?? "—")
                LabeledContent("Locale", value: store.fileInfo?.locale ?? "—")
                LabeledContent("Zeitzone", value: store.fileInfo?.timeZone ?? "—")
            }
            Section("Kategorien") {
                HStack {
                    TextField("Neue Kategorie", text: $categoryName)
                    Picker("Art", selection: $categoryKind) {
                        ForEach(CategoryKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Button("Hinzufügen") {
                        if store.saveCategory(name: categoryName, kind: categoryKind) {
                            categoryName = ""
                        }
                    }
                    .disabled(categoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(store.categoriesByPath) { category in
                    LabeledContent(store.categoryPath(category.id), value: category.kind.title)
                }
            }
            Section("MwSt.-Schlüssel") {
                Button("MwSt.-Schlüssel anlegen", systemImage: "plus") {
                    editedVATCode = VATCode(
                        id: UUID(),
                        name: "",
                        rateBasisPoints: 1900,
                        description: "",
                        isActive: true
                    )
                }
                ForEach(store.vatCodes) { code in
                    Button {
                        editedVATCode = code
                    } label: {
                        LabeledContent(
                            code.name,
                            value: "\(code.percentageText) · \(code.isActive ? "Aktiv" : "Inaktiv")"
                        )
                    }
                    .buttonStyle(.plain)
                }
                Text(
                    "Auch eigene 0-%-Schlüssel bleiben eigenständig und werden nicht umgeleitet."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section("Klassen & Tags") {
                Button("Tag anlegen", systemImage: "plus") {
                    editedTag = FinanceTag(
                        id: UUID(), parentID: nil, name: "Neuer Tag",
                        color: "blue", description: "", isActive: true
                    )
                }
                ForEach(store.tags) { tag in
                    Button {
                        editedTag = tag
                    } label: {
                        LabeledContent(tag.name, value: tag.isActive ? "Aktiv" : "Inaktiv")
                    }
                    .buttonStyle(.plain)
                }
            }
            Section("Empfänger") {
                Button("Empfänger anlegen", systemImage: "plus") {
                    editedPayee = FinancePayee(
                        id: UUID(), canonicalName: "Neuer Empfänger", aliases: [],
                        address: "", email: "", phone: "", iban: "", bic: "",
                        defaultCategoryID: nil, preferredAccountID: nil,
                        note: "", isActive: true
                    )
                }
                ForEach(store.payees) { payee in
                    Button {
                        editedPayee = payee
                    } label: {
                        LabeledContent(
                            payee.canonicalName,
                            value: payee.aliases.isEmpty
                                ? "Keine Aliase" : payee.aliases.joined(separator: ", ")
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Einstellungen")
        .sheet(item: $editedPayee) { PayeeEditor(value: $0) }
        .sheet(item: $editedTag) { TagEditor(value: $0) }
        .sheet(item: $editedVATCode) { VATCodeEditor(value: $0) }
    }
}

private struct VATCodeEditor: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var value: VATCode
    @State private var rateText: String

    init(value: VATCode) {
        _value = State(initialValue: value)
        _rateText = State(
            initialValue: (Decimal(value.rateBasisPoints) / 100).formatted(
                .number
                    .locale(Locale(identifier: "de_DE"))
                    .precision(.fractionLength(0...2))
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(value.name.isEmpty ? "MwSt.-Schlüssel anlegen" : "MwSt.-Schlüssel bearbeiten")
                .font(.title2.bold())
            Form {
                TextField("Name", text: $value.name)
                TextField("Steuersatz in %", text: $rateText)
                TextField("Beschreibung", text: $value.description)
                Toggle("Aktiv", isOn: $value.isActive)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                Button("Speichern") {
                    do {
                        value.rateBasisPoints = try VATCalculator.basisPoints(
                            parsing: rateText
                        )
                        if store.saveVATCode(value) { dismiss() }
                    } catch {
                        store.errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    value.name.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}

struct CategoriesView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var selectedID: UUID?
    @State private var editedCategory: FinanceCategory?

    private var selected: FinanceCategory? {
        store.categories.first { $0.id == selectedID }
    }
    private var roots: [FinanceCategory] {
        store.categories.filter { $0.parentID == nil }.sorted {
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kategorien").font(.title2.bold())
                    Text("Einnahmen und Ausgaben in Ober- und Unterkategorien gliedern")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                InvestmentValue(
                    title: "Oberkategorien",
                    value: "\(roots.count)"
                )
                InvestmentValue(
                    title: "Unterkategorien",
                    value: "\(store.categories.filter { $0.parentID != nil }.count)"
                )
                Button("Oberkategorie", systemImage: "folder.badge.plus") {
                    editedCategory = FinanceCategory(
                        id: UUID(), parentID: nil, name: "",
                        kind: .expense, color: "blue", isActive: true
                    )
                }
                Button("Unterkategorie", systemImage: "plus") {
                    guard let selected else { return }
                    editedCategory = FinanceCategory(
                        id: UUID(), parentID: selected.id, name: "",
                        kind: selected.kind, color: selected.color, isActive: true
                    )
                }
                .disabled(selected == nil)
                Button("Bearbeiten", systemImage: "pencil") {
                    editedCategory = selected
                }
                .disabled(selected == nil)
            }
            .padding(14)
            Divider()
            HSplitView {
                List(selection: $selectedID) {
                    ForEach(CategoryKind.allCases, id: \.self) { kind in
                        Section(kind.title) {
                            ForEach(roots.filter { $0.kind == kind }) { category in
                                CategoryTreeRows(category: category, selectedID: $selectedID)
                            }
                        }
                    }
                }
                .frame(minWidth: 300, idealWidth: 360)

                Group {
                    if let selected {
                        categoryDetail(selected)
                    } else {
                        ContentUnavailableView(
                            "Keine Kategorie ausgewählt",
                            systemImage: "folder",
                            description: Text(
                                "Wähle eine Kategorie oder lege eine neue Oberkategorie an."
                            )
                        )
                    }
                }
                .frame(minWidth: 580)
            }
        }
        .onAppear {
            if selectedID == nil { selectedID = roots.first?.id }
        }
        .sheet(item: $editedCategory) { CategoryEditor(category: $0) }
    }

    private func categoryDetail(_ category: FinanceCategory) -> some View {
        let directTransactions = store.transactions.filter {
            $0.categoryID == category.id
                || $0.splits.contains { $0.categoryID == category.id }
        }
        let children = store.categories.filter { $0.parentID == category.id }
        let total = directTransactions.reduce(Int64.zero) { partial, transaction in
            if transaction.categoryID == category.id { return partial + transaction.amountMinor }
            return partial + transaction.splits
                .filter { $0.categoryID == category.id }
                .reduce(Int64.zero) { $0 + $1.amountMinor }
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Circle()
                        .fill(categoryColor(category.color))
                        .frame(width: 18, height: 18)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.name).font(.title2.bold())
                        Text(store.categoryPath(category.id))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(category.isActive ? "Aktiv" : "Inaktiv")
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(
                            category.isActive
                                ? Color.green.opacity(0.14) : Color.gray.opacity(0.14),
                            in: Capsule()
                        )
                }
                Divider()
                HStack(spacing: 36) {
                    categoryMetric("Art", category.kind.title)
                    categoryMetric("Unterkategorien", "\(children.count)")
                    categoryMetric("Direkte Buchungen", "\(directTransactions.count)")
                    categoryMetric("Direkte Summe", Money(minorUnits: total).formatted)
                }
                GroupBox("Steuer & Planung") {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        GridRow {
                            Text("Standard-MwSt.").foregroundStyle(.secondary)
                            Text(
                                store.vatCodes.first {
                                    $0.id == category.defaultVATCodeID
                                }.map { "\($0.name) (\($0.percentageText))" } ?? "Keine"
                            )
                        }
                        GridRow {
                            Text("Deutsche Steuerzuordnung").foregroundStyle(.secondary)
                            Text(category.germanTaxLine.isEmpty ? "Keine" : category.germanTaxLine)
                        }
                        GridRow {
                            Text("US-Tax-Line").foregroundStyle(.secondary)
                            Text(category.usTaxLine.isEmpty ? "Keine" : category.usTaxLine)
                        }
                        GridRow {
                            Text("Budgetfähig").foregroundStyle(.secondary)
                            Text(category.isBudgetable ? "Ja" : "Nein")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !children.isEmpty {
                    GroupBox("Unterkategorien") {
                        VStack(spacing: 0) {
                            ForEach(children.sorted {
                                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                            }) { child in
                                Button {
                                    selectedID = child.id
                                } label: {
                                    HStack {
                                        Image(systemName: "folder")
                                        Text(child.name)
                                        Spacer()
                                        Text("\(transactionCount(for: child.id)) Buchungen")
                                        .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 5)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                GroupBox("Zuordnung") {
                    Text(
                        "Diese Kategorie erscheint mit ihrem vollständigen Pfad in Buchungs-, Split-, Regel- und Serientermin-Dialogen."
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
    }

    private func categoryMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
    }

    private func transactionCount(for categoryID: UUID) -> Int {
        store.transactions.filter {
            $0.categoryID == categoryID
                || $0.splits.contains { $0.categoryID == categoryID }
        }.count
    }
}

private struct CategoryTreeRows: View {
    @EnvironmentObject private var store: FinanceAppStore
    let category: FinanceCategory
    @Binding var selectedID: UUID?

    private var children: [FinanceCategory] {
        store.categories.filter { $0.parentID == category.id }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        if children.isEmpty {
            categoryLabel
                .tag(category.id)
        } else {
            DisclosureGroup {
                ForEach(children) { child in
                    CategoryTreeRows(category: child, selectedID: $selectedID)
                        .padding(.leading, 8)
                }
            } label: {
                categoryLabel
                    .contentShape(Rectangle())
                    .onTapGesture { selectedID = category.id }
            }
        }
    }

    private var categoryLabel: some View {
        HStack {
            Circle()
                .fill(categoryColor(category.color))
                .frame(width: 8, height: 8)
            Text(category.name)
            if !category.isActive {
                Text("Inaktiv")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CategoryEditor: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var value: FinanceCategory

    init(category: FinanceCategory) {
        _value = State(initialValue: category)
    }

    private var parentCandidates: [FinanceCategory] {
        store.categoriesByPath.filter {
            $0.id != value.id && $0.kind == value.kind && !isDescendant($0, of: value.id)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AssetEditorHeader(
                title: value.name.isEmpty ? "Kategorie anlegen" : "Kategorie bearbeiten",
                saveDisabled: value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                if store.saveCategory(value) { dismiss() }
            }
            Form {
                TextField("Name", text: $value.name)
                Picker("Art", selection: $value.kind) {
                    ForEach(CategoryKind.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                .onChange(of: value.kind) {
                    if let parentID = value.parentID,
                       store.categories.first(where: { $0.id == parentID })?.kind != value.kind {
                        value.parentID = nil
                    }
                }
                Picker("Oberkategorie", selection: $value.parentID) {
                    Text("Keine – Oberkategorie").tag(UUID?.none)
                    ForEach(parentCandidates) {
                        Text(store.categoryPath($0.id)).tag(Optional($0.id))
                    }
                }
                Picker("Farbe", selection: $value.color) {
                    ForEach(["blue", "green", "orange", "red", "purple", "teal", "gray"], id: \.self) {
                        Text(colorTitle($0)).tag($0)
                    }
                }
                TextField("Beschreibung", text: $value.description)
                Toggle("Budgetfähig", isOn: $value.isBudgetable)
                Picker("Standard-MwSt.-Schlüssel", selection: $value.defaultVATCodeID) {
                    Text("Keine MwSt.").tag(UUID?.none)
                    ForEach(
                        store.vatCodes.filter {
                            $0.isActive || $0.id == value.defaultVATCodeID
                        }
                    ) { code in
                        Text("\(code.name) · \(code.percentageText)")
                            .tag(Optional(code.id))
                    }
                }
                TextField(
                    "Deutsche Steuerzuordnung",
                    text: $value.germanTaxLine,
                    prompt: Text("z. B. Anlage V · Werbungskosten")
                )
                TextField(
                    "Optionale US-Tax-Line",
                    text: $value.usTaxLine,
                    prompt: Text("z. B. Schedule E")
                )
                Toggle("Aktiv", isOn: $value.isActive)
                Text(
                    "Unterkategorien erben nicht automatisch Werte, erscheinen aber mit dem vollständigen Pfad in allen Buchungsdialogen."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
        }
        .frame(width: 620, height: 620)
    }

    private func isDescendant(_ candidate: FinanceCategory, of categoryID: UUID) -> Bool {
        var parentID = candidate.parentID
        var visited = Set<UUID>()
        while let currentID = parentID, visited.insert(currentID).inserted {
            if currentID == categoryID { return true }
            parentID = store.categories.first { $0.id == currentID }?.parentID
        }
        return false
    }

    private func colorTitle(_ value: String) -> String {
        switch value {
        case "blue": "Blau"
        case "green": "Grün"
        case "orange": "Orange"
        case "red": "Rot"
        case "purple": "Violett"
        case "teal": "Türkis"
        default: "Grau"
        }
    }
}

private func categoryColor(_ value: String) -> Color {
    switch value {
    case "blue": .blue
    case "green": .green
    case "orange": .orange
    case "red": .red
    case "purple": .purple
    case "teal": .teal
    default: .gray
    }
}

private struct TagEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    @State private var value: FinanceTag

    init(value: FinanceTag) { _value = State(initialValue: value) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Klasse/Tag").font(.title2.bold())
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Speichern") {
                    if store.saveTag(value) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
            Divider()
            Form {
                TextField("Name", text: $value.name)
                TextField("Farbe", text: $value.color)
                TextField("Beschreibung", text: $value.description)
                Picker("Übergeordneter Tag", selection: $value.parentID) {
                    Text("Keine Hierarchie").tag(UUID?.none)
                    ForEach(store.tags.filter { $0.id != value.id }) {
                        Text($0.name).tag(Optional($0.id))
                    }
                }
                Toggle("Aktiv", isOn: $value.isActive)
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 350)
    }
}

private struct PayeeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    @State private var value: FinancePayee
    @State private var aliasesText: String

    init(value: FinancePayee) {
        _value = State(initialValue: value)
        _aliasesText = State(initialValue: value.aliases.joined(separator: ", "))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Empfängerakte").font(.title2.bold())
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Speichern") {
                    value.aliases = aliasesText.split(separator: ",").map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if store.savePayee(value) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
            Divider()
            Form {
                Section("Stammdaten") {
                    TextField("Kanonischer Name", text: $value.canonicalName)
                    TextField("Aliase, kommagetrennt", text: $aliasesText)
                    TextField("Adresse", text: $value.address)
                    TextField("E-Mail", text: $value.email)
                    TextField("Telefon", text: $value.phone)
                    TextField("Notiz", text: $value.note)
                    Toggle("Aktiv", isOn: $value.isActive)
                }
                Section("Zahlung & Vorgaben") {
                    TextField("IBAN", text: $value.iban)
                    TextField("BIC", text: $value.bic)
                    Picker("Standardkategorie", selection: $value.defaultCategoryID) {
                        Text("Keine").tag(UUID?.none)
                        ForEach(store.categoriesByPath.filter(\.isActive)) {
                            Text(store.categoryPath($0.id)).tag(Optional($0.id))
                        }
                    }
                    Picker("Bevorzugtes Konto", selection: $value.preferredAccountID) {
                        Text("Keines").tag(UUID?.none)
                        ForEach(store.accounts) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 650, height: 620)
    }
}

struct RulesView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var selectedID: UUID?
    @State private var draft: CategorizationRule?
    @State private var confirmApply = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Regeln").font(.title2.bold())
                    Spacer()
                    Button {
                        guard let category = store.categories.first else { return }
                        draft = CategorizationRule(
                            id: UUID(), name: "Neue Regel",
                            priority: (store.categorizationRules.map(\.priority).max() ?? 0) + 10,
                            isActive: true, stopAfterMatch: true,
                            payeeContains: "", purposeContains: "",
                            minimumAmountMinor: nil, maximumAmountMinor: nil,
                            categoryID: category.id
                        )
                        selectedID = draft?.id
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Neue Regel")
                }
                .padding(12)
                Divider()
                List(selection: $selectedID) {
                    ForEach(store.categorizationRules) { rule in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name)
                                Text("Priorität \(rule.priority) · \(store.categoryName(rule.categoryID))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Circle()
                                .fill(rule.isActive ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                        }
                        .tag(rule.id)
                    }
                }
            }
            .frame(minWidth: 260, idealWidth: 310)

            if draft != nil {
                RuleEditor(
                    rule: Binding(
                        get: { draft! },
                        set: { draft = $0 }
                    ),
                    confirmApply: $confirmApply
                )
                    .frame(minWidth: 500)
            } else {
                ContentUnavailableView(
                    "Keine Regel ausgewählt",
                    systemImage: "wand.and.stars",
                    description: Text("Wähle eine Regel oder lege eine neue an.")
                )
            }
        }
        .onChange(of: selectedID) {
            guard let selectedID else { return }
            if let existing = store.categorizationRules.first(where: { $0.id == selectedID }) {
                draft = existing
            }
        }
        .alert("Regel anwenden?", isPresented: $confirmApply) {
            Button("Abbrechen", role: .cancel) {}
            Button("Auf Treffer anwenden") {
                if let draft { _ = store.applyRule(draft) }
            }
        } message: {
            Text("Die Vorschau umfasst \(draft.map(store.rulePreviewCount) ?? 0) Buchungen. Abgeglichene Buchungen bleiben unverändert.")
        }
    }
}

private struct RuleEditor: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Binding var rule: CategorizationRule
    @Binding var confirmApply: Bool

    var body: some View {
        Form {
            Section("Regel") {
                TextField("Name", text: $rule.name)
                Stepper("Priorität: \(rule.priority)", value: $rule.priority, in: 0...10_000)
                Toggle("Aktiv", isOn: $rule.isActive)
                Toggle("Nach Treffer stoppen", isOn: $rule.stopAfterMatch)
            }
            Section("Bedingungen – alle müssen zutreffen") {
                TextField("Empfänger enthält", text: $rule.payeeContains)
                TextField("Verwendungszweck enthält", text: $rule.purposeContains)
                LabeledContent("Betragsgrenzen") {
                    Text("Optional; im aktuellen Editor nicht gesetzt")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Aktion") {
                Picker("Kategorie setzen", selection: $rule.categoryID) {
                    ForEach(store.categoriesByPath.filter(\.isActive)) {
                        Text(store.categoryPath($0.id)).tag($0.id)
                    }
                }
            }
            Section("Vorschau") {
                LabeledContent("Betroffene Buchungen") {
                    Text("\(store.rulePreviewCount(rule))")
                        .font(.headline.monospacedDigit())
                }
                Text("Die Vorschau schreibt keine Daten. Abgeglichene und stornierte Buchungen sind ausgeschlossen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Regel speichern") {
                    _ = store.saveRule(rule)
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button("Auf bestehende Buchungen anwenden …") {
                    guard store.saveRule(rule) else { return }
                    confirmApply = true
                }
                .disabled(!rule.isActive || store.rulePreviewCount(rule) == 0)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Regel bearbeiten")
    }
}

struct CalendarForecastView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var editedSchedule: ScheduledTransaction?
    @State private var forecastDays = 90

    private var occurrences: [FinanceTransaction] {
        store.forecastOccurrences(days: forecastDays)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kalender & Prognose")
                        .font(.title2.bold())
                    Text("Regelmäßige Vorgänge und erwartete Kontostände")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Horizont", selection: $forecastDays) {
                    Text("30 Tage").tag(30)
                    Text("90 Tage").tag(90)
                    Text("180 Tage").tag(180)
                    Text("1 Jahr").tag(365)
                }
                .pickerStyle(.segmented)
                .frame(width: 340)
                Button {
                    guard let account = store.accounts.first else { return }
                    editedSchedule = ScheduledTransaction(
                        id: UUID(), name: "Neuer regelmäßiger Vorgang",
                        accountID: account.id, payee: "", purpose: "",
                        categoryID: nil, amountMinor: 0, currency: account.currency,
                        nextDueDate: Date(), endDate: nil, frequency: .monthly,
                        action: .remind, reminderDays: 3, isActive: true
                    )
                } label: {
                    Label("Neu", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.accounts.isEmpty)
            }
            .padding(12)
            Divider()

            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Text("Regelmäßige Vorgänge").font(.headline)
                        Spacer()
                        Text("\(store.scheduledTransactions.filter(\.isActive).count) aktiv")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    Divider()
                    if store.scheduledTransactions.isEmpty {
                        ContentUnavailableView(
                            "Noch keine Vorgänge",
                            systemImage: "calendar.badge.plus",
                            description: Text("Lege Gehalt, Miete oder andere regelmäßige Zahlungen an.")
                        )
                    } else {
                        List(store.scheduledTransactions) { value in
                            Button {
                                editedSchedule = value
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(value.name).fontWeight(.medium)
                                        Spacer()
                                        Text(Money(minorUnits: value.amountMinor).formatted)
                                            .monospacedDigit()
                                            .foregroundStyle(value.amountMinor < 0 ? .red : .green)
                                    }
                                    HStack {
                                        Text(value.frequency.title)
                                        Text("·")
                                        Text(value.nextDueDate, format: .dateTime.day().month().year())
                                        Spacer()
                                        Text(value.isActive ? value.action.title : "Inaktiv")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minWidth: 360, idealWidth: 430)

                VStack(spacing: 0) {
                    HStack {
                        Text("Liquiditätsvorschau").font(.headline)
                        Spacer()
                        Text("\(occurrences.count) erwartete Termine")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    Divider()
                    if occurrences.isEmpty {
                        ContentUnavailableView(
                            "Keine Termine im Zeitraum",
                            systemImage: "calendar",
                            description: Text("Aktive regelmäßige Vorgänge erscheinen hier ohne Doppelzählung.")
                        )
                    } else {
                        List(occurrences) { value in
                            HStack(spacing: 12) {
                                Text(value.bookingDate, format: .dateTime.day().month().year())
                                    .frame(width: 92, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(value.payee.isEmpty ? value.purpose : value.payee)
                                    Text("\(store.accountName(value.accountID)) · \(value.memo)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(Money(minorUnits: value.amountMinor).formatted)
                                        .monospacedDigit()
                                        .foregroundStyle(value.amountMinor < 0 ? .red : .green)
                                    Text(
                                        Money(
                                            minorUnits: store.projectedBalanceMinor(
                                                accountID: value.accountID,
                                                through: value.bookingDate
                                            )
                                        ).formatted
                                    )
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .frame(minWidth: 480)
            }
        }
        .sheet(item: $editedSchedule) { schedule in
            ScheduledTransactionEditor(value: schedule)
        }
    }
}

private struct ScheduledTransactionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    @State private var value: ScheduledTransaction
    @State private var amountText: String
    @State private var hasEndDate: Bool

    init(value: ScheduledTransaction) {
        _value = State(initialValue: value)
        _amountText = State(initialValue: Money(minorUnits: value.amountMinor).editingString)
        _hasEndDate = State(initialValue: value.endDate != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Regelmäßigen Vorgang bearbeiten").font(.title2.bold())
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Speichern") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(value.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14)
            Divider()
            Form {
                Section("Vorgang") {
                    TextField("Name", text: $value.name)
                    Picker("Konto", selection: $value.accountID) {
                        ForEach(store.accounts) { Text($0.name).tag($0.id) }
                    }
                    TextField("Empfänger", text: $value.payee)
                    TextField("Verwendungszweck", text: $value.purpose)
                    Picker("Kategorie", selection: $value.categoryID) {
                        Text("Nicht kategorisiert").tag(UUID?.none)
                        ForEach(store.categoriesByPath.filter(\.isActive)) {
                            Text(store.categoryPath($0.id)).tag(Optional($0.id))
                        }
                    }
                    TextField("Betrag", text: $amountText)
                        .multilineTextAlignment(.trailing)
                }
                Section("Zeitplan") {
                    DatePicker("Nächste Fälligkeit", selection: $value.nextDueDate, displayedComponents: .date)
                    Picker("Rhythmus", selection: $value.frequency) {
                        ForEach(RecurrenceFrequency.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    Toggle("Enddatum verwenden", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker(
                            "Enddatum",
                            selection: Binding(
                                get: { value.endDate ?? value.nextDueDate },
                                set: { value.endDate = $0 }
                            ),
                            in: value.nextDueDate...,
                            displayedComponents: .date
                        )
                    }
                    Picker("Aktion", selection: $value.action) {
                        ForEach(ScheduledAction.allCases, id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                    Stepper(
                        "Erinnerung: \(value.reminderDays) Tage vorher",
                        value: $value.reminderDays,
                        in: 0...365
                    )
                    Toggle("Aktiv", isOn: $value.isActive)
                }
                Section {
                    Text("Die Vorschau erzeugt keine echten Buchungen. Bereits materialisierte Termine mit derselben Herkunftskennung werden nicht doppelt gezählt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 620, height: 660)
    }

    private func save() {
        do {
            value.amountMinor = try Money(parsing: amountText, currency: value.currency).minorUnits
            if !hasEndDate { value.endDate = nil }
            if store.saveScheduledTransaction(value) {
                dismiss()
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}

struct BudgetView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var selectedBudgetID: UUID?
    @State private var selectedMonth = Date()
    @State private var showNewBudget = false
    @State private var editedRow: BudgetStatusRow?

    private var budget: FinanceBudget? {
        store.budgets.first { $0.id == selectedBudgetID }
    }

    private var rows: [BudgetStatusRow] {
        guard let selectedBudgetID else { return [] }
        return store.budgetStatusRows(budgetID: selectedBudgetID, month: selectedMonth)
    }

    private var plannedTotal: Int64 {
        rows.filter { $0.category.kind == .expense }.reduce(0) { $0 + $1.plannedMinor }
    }

    private var actualTotal: Int64 {
        abs(rows.filter { $0.category.kind == .expense }.reduce(0) { $0 + $1.actualMinor })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Budget").font(.title2.bold())
                    Text("Plan, Ist und Abweichung aus echten Buchungen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Budget", selection: $selectedBudgetID) {
                    Text("Budget wählen").tag(UUID?.none)
                    ForEach(store.budgets) { Text($0.name).tag(Optional($0.id)) }
                }
                .frame(width: 260)
                if let budget {
                    Picker("Monat", selection: $selectedMonth) {
                        ForEach(budget.months(), id: \.self) { month in
                            Text(month, format: .dateTime.month(.wide).year()).tag(month)
                        }
                    }
                    .frame(width: 190)
                }
                Button {
                    showNewBudget = true
                } label: {
                    Label("Neu", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
            Divider()
            if budget == nil {
                ContentUnavailableView(
                    "Noch kein Budget",
                    systemImage: "chart.pie",
                    description: Text("Lege ein Kalender- oder Geschäftsjahresbudget an.")
                )
            } else {
                HStack(spacing: 12) {
                    BudgetMetric(title: "Ausgabenplan", value: Money(minorUnits: plannedTotal).formatted)
                    BudgetMetric(title: "Ist-Ausgaben", value: Money(minorUnits: actualTotal).formatted)
                    BudgetMetric(
                        title: "Verfügbar",
                        value: Money(minorUnits: plannedTotal - actualTotal).formatted,
                        warning: actualTotal > plannedTotal
                    )
                }
                .padding(12)
                Divider()
                HStack {
                    Text("Kategorie").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Plan").frame(width: 120, alignment: .trailing)
                    Text("Ist").frame(width: 120, alignment: .trailing)
                    Text("Abweichung").frame(width: 120, alignment: .trailing)
                    Text("%").frame(width: 70, alignment: .trailing)
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .frame(height: 28)
                List(rows) { row in
                    Button {
                        editedRow = row
                    } label: {
                        HStack {
                            Label(
                                row.category.name,
                                systemImage: row.category.kind == .income
                                    ? "arrow.down.circle" : "arrow.up.circle"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(Money(minorUnits: row.plannedMinor).formatted)
                                .frame(width: 120, alignment: .trailing)
                            Text(Money(minorUnits: abs(row.actualMinor)).formatted)
                                .frame(width: 120, alignment: .trailing)
                            Text(Money(minorUnits: row.varianceMinor).formatted)
                                .foregroundStyle(row.varianceMinor < 0 ? .red : .green)
                                .frame(width: 120, alignment: .trailing)
                            Text(row.completionPercent.map { "\($0) %" } ?? "—")
                                .frame(width: 70, alignment: .trailing)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            if selectedBudgetID == nil {
                selectedBudgetID = store.budgets.first?.id
                if let first = store.budgets.first,
                   let current = first.months().first(where: {
                       Calendar.current.isDate($0, equalTo: Date(), toGranularity: .month)
                   }) {
                    selectedMonth = current
                }
            }
        }
        .onChange(of: selectedBudgetID) {
            if let budget, let first = budget.months().first {
                selectedMonth = budget.months().first(where: {
                    Calendar.current.isDate($0, equalTo: Date(), toGranularity: .month)
                }) ?? first
            }
        }
        .sheet(isPresented: $showNewBudget) {
            BudgetEditor()
        }
        .sheet(item: $editedRow) { row in
            if let selectedBudgetID {
                BudgetLineEditor(
                    budgetID: selectedBudgetID, month: selectedMonth, row: row
                )
            }
        }
    }
}

private struct BudgetMetric: View {
    let title: String
    let value: String
    var warning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(warning ? .red : .primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }
}

private struct BudgetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    @State private var name = "Neues Budget"
    @State private var startYear = Calendar.current.component(.year, from: Date())
    @State private var startMonth = 1

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Budget anlegen").font(.title2.bold())
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Anlegen") {
                    let value = FinanceBudget(
                        id: UUID(), name: name, startYear: startYear,
                        startMonth: startMonth, currency: "EUR", isActive: true
                    )
                    if store.saveBudget(value) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14)
            Divider()
            Form {
                TextField("Name", text: $name)
                Stepper("Startjahr: \(startYear)", value: $startYear, in: 1900...2200)
                Picker("Erster Monat des Geschäftsjahres", selection: $startMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text(
                            Calendar.current.monthSymbols[month - 1]
                        ).tag(month)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 300)
    }
}

private struct BudgetLineEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    let budgetID: UUID
    let month: Date
    let row: BudgetStatusRow
    @State private var amountText: String
    @State private var rolloverPositive: Bool
    @State private var rolloverNegative: Bool

    init(budgetID: UUID, month: Date, row: BudgetStatusRow) {
        self.budgetID = budgetID
        self.month = month
        self.row = row
        _amountText = State(initialValue: Money(minorUnits: row.plannedMinor).editingString)
        _rolloverPositive = State(initialValue: row.line?.rolloverPositive ?? false)
        _rolloverNegative = State(initialValue: row.line?.rolloverNegative ?? false)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(row.category.name).font(.title2.bold())
                    Text(month, format: .dateTime.month(.wide).year())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Plan speichern") {
                    if store.saveBudgetAmount(
                        budgetID: budgetID, categoryID: row.category.id, month: month,
                        amount: amountText, rolloverPositive: rolloverPositive,
                        rolloverNegative: rolloverNegative
                    ) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
            Divider()
            Form {
                Section("Plan") {
                    TextField("Monatsbetrag", text: $amountText)
                    Toggle("Positiven Rest übertragen", isOn: $rolloverPositive)
                    Toggle("Negativen Rest übertragen", isOn: $rolloverNegative)
                }
                Section("Ist – aus Buchungen, nicht editierbar") {
                    if store.budgetTransactions(categoryID: row.category.id, month: month).isEmpty {
                        Text("Keine Buchungen in diesem Monat")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.budgetTransactions(categoryID: row.category.id, month: month)) { value in
                            LabeledContent(
                                value.payee.isEmpty ? value.purpose : value.payee,
                                value: Money(minorUnits: value.amountMinor).formatted
                            )
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 620, height: 520)
    }
}

struct PaymentsView: View {
    private enum PaymentSection: String, CaseIterable, Identifiable {
        case payments = "Überweisungen"
        case standingOrders = "Daueraufträge"
        var id: Self { self }
    }

    @EnvironmentObject private var store: FinanceAppStore
    @State private var selectedID: UUID?
    @State private var selectedStandingOrderID: UUID?
    @State private var section: PaymentSection = .payments
    @State private var showNewPayment = false
    @State private var editedStandingOrder: StandingOrder?

    private var selectedOrder: PaymentOrder? {
        store.paymentOrders.first { $0.id == selectedID }
    }

    private var selectedStandingOrder: StandingOrder? {
        store.standingOrders.first { $0.id == selectedStandingOrderID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zahlungsverkehr").font(.title2.bold())
                    Text("Lokaler Banking-Simulator · keine echte Bankverbindung")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("SIMULATOR", systemImage: "testtube.2")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.orange.opacity(0.12), in: Capsule())
                Picker("Bereich", selection: $section) {
                    ForEach(PaymentSection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                Button {
                    switch section {
                    case .payments:
                        showNewPayment = true
                    case .standingOrders:
                        guard let account = store.accounts.first(where: {
                            !$0.isClosed && $0.currency == "EUR"
                        }) else {
                            return
                        }
                        let now = Date()
                        editedStandingOrder = StandingOrder(
                            id: UUID(), accountID: account.id,
                            name: "Neuer Dauerauftrag", recipientName: "",
                            iban: "", bic: "", amountMinor: 0,
                            currency: account.currency, purpose: "",
                            nextExecutionDate: now, endDate: nil,
                            frequency: .monthly,
                            businessDayAdjustment: .nextWeekday,
                            status: .active, createdAt: now, updatedAt: now
                        )
                    }
                } label: {
                    Label(
                        section == .payments ? "Überweisung" : "Dauerauftrag",
                        systemImage: "plus"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    section == PaymentSection.payments
                        ? store.accounts.isEmpty
                        : !store.accounts.contains(where: {
                            !$0.isClosed && $0.currency == "EUR"
                        })
                )
            }
            .padding(12)
            Divider()
            switch section {
            case .payments:
                paymentOrdersContent
            case .standingOrders:
                standingOrdersContent
            }
        }
        .onAppear {
            if selectedID == nil { selectedID = store.paymentOrders.first?.id }
            if selectedStandingOrderID == nil {
                selectedStandingOrderID = store.standingOrders.first?.id
            }
        }
        .sheet(isPresented: $showNewPayment) {
            PaymentDraftEditor()
        }
        .sheet(item: $editedStandingOrder) {
            StandingOrderEditor(value: $0)
        }
    }

    private var paymentOrdersContent: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Aufträge").font(.headline)
                    Spacer()
                    Text("\(store.paymentOrders.count)")
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                Divider()
                if store.paymentOrders.isEmpty {
                    ContentUnavailableView(
                        "Keine Zahlungsaufträge",
                        systemImage: "eurosign.arrow.circlepath",
                        description: Text("Lege eine simulierte SEPA-Überweisung an.")
                    )
                } else {
                    List(selection: $selectedID) {
                        ForEach(store.paymentOrders) { order in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(order.recipientName).fontWeight(.medium)
                                    Spacer()
                                    Text(Money(minorUnits: order.amountMinor).formatted)
                                        .monospacedDigit()
                                }
                                HStack {
                                    PaymentStatusBadge(status: order.status)
                                    Text(order.executionDate, format: .dateTime.day().month().year())
                                    Spacer()
                                    Text(order.type.title)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .tag(order.id)
                        }
                    }
                }
            }
            .frame(minWidth: 390, idealWidth: 470)

            if let selectedOrder {
                PaymentOrderDetail(order: selectedOrder)
                    .id(selectedOrder)
                    .frame(minWidth: 520)
            } else {
                ContentUnavailableView(
                    "Kein Auftrag ausgewählt",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Wähle links einen Zahlungsauftrag.")
                )
                .frame(minWidth: 520)
            }
        }
    }

    private var standingOrdersContent: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Daueraufträge").font(.headline)
                    Spacer()
                    Text("\(store.standingOrders.filter { $0.status == .active }.count) aktiv")
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                Divider()
                if store.standingOrders.isEmpty {
                    ContentUnavailableView(
                        "Keine Daueraufträge",
                        systemImage: "repeat.circle",
                        description: Text(
                            "Regelmäßige Zahlungstermine werden kontrolliert als einzelne Entwürfe vorbereitet."
                        )
                    )
                } else {
                    List(selection: $selectedStandingOrderID) {
                        ForEach(store.standingOrders) { value in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(value.name).fontWeight(.medium)
                                    Spacer()
                                    Text(Money(minorUnits: value.amountMinor).formatted)
                                        .monospacedDigit()
                                }
                                HStack {
                                    Text(value.status.title)
                                    Text("·")
                                    Text(value.frequency.title)
                                    Spacer()
                                    Text(
                                        value.nextExecutionDate,
                                        format: .dateTime.day().month().year()
                                    )
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .tag(value.id)
                        }
                    }
                }
            }
            .frame(minWidth: 390, idealWidth: 470)

            if let selectedStandingOrder {
                StandingOrderDetail(
                    value: selectedStandingOrder,
                    edit: { editedStandingOrder = selectedStandingOrder }
                )
                .id(selectedStandingOrder)
                .frame(minWidth: 520)
            } else {
                ContentUnavailableView(
                    "Kein Dauerauftrag ausgewählt",
                    systemImage: "repeat.circle",
                    description: Text("Wähle links einen Dauerauftrag.")
                )
                .frame(minWidth: 520)
            }
        }
    }
}

private struct PaymentStatusBadge: View {
    let status: PaymentStatus

    private var color: Color {
        switch status {
        case .accepted: .green
        case .rejected, .cancelled: .red
        case .unknown: .orange
        case .draft: .gray
        default: .blue
        }
    }

    var body: some View {
        Text(status.title)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct StandingOrderDetail: View {
    @EnvironmentObject private var store: FinanceAppStore
    let value: StandingOrder
    let edit: () -> Void
    @State private var runs: [StandingOrderRun] = []
    @State private var confirmMaterialization = false
    @State private var confirmSkip = false
    @State private var confirmCancellation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(value.name).font(.title2.bold())
                        Text(value.recipientName).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(value.status.title)
                        .font(.caption.bold())
                        .foregroundStyle(value.status == .active ? .green : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }

                GroupBox("Dauerauftragsvorlage") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                        GridRow {
                            Text("Auftraggeber").foregroundStyle(.secondary)
                            Text(store.accountName(value.accountID))
                        }
                        GridRow {
                            Text("Empfänger").foregroundStyle(.secondary)
                            Text(value.recipientName)
                        }
                        GridRow {
                            Text("IBAN").foregroundStyle(.secondary)
                            Text(value.iban).monospaced()
                        }
                        GridRow {
                            Text("Betrag").foregroundStyle(.secondary)
                            Text(Money(minorUnits: value.amountMinor).formatted).bold()
                        }
                        GridRow {
                            Text("Nächste Fälligkeit").foregroundStyle(.secondary)
                            Text(
                                value.nextExecutionDate,
                                format: .dateTime.day().month().year()
                            )
                        }
                        GridRow {
                            Text("Rhythmus").foregroundStyle(.secondary)
                            Text(value.frequency.title)
                        }
                        GridRow {
                            Text("Wochenende").foregroundStyle(.secondary)
                            Text(value.businessDayAdjustment.title)
                        }
                        GridRow {
                            Text("Verwendungszweck").foregroundStyle(.secondary)
                            Text(value.purpose)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }

                HStack {
                    Button("Bearbeiten", action: edit)
                        .disabled(value.status == .cancelled)
                    if value.status == .active {
                        Button("Nächsten Entwurf vorbereiten …") {
                            confirmMaterialization = true
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Fälligkeit überspringen …") {
                            confirmSkip = true
                        }
                        Button("Pausieren") {
                            _ = store.setStandingOrderStatus(value, to: .paused)
                        }
                    } else if value.status == .paused {
                        Button("Fortsetzen") {
                            _ = store.setStandingOrderStatus(value, to: .active)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                    if value.status != .cancelled {
                        Button("Beenden …", role: .destructive) {
                            confirmCancellation = true
                        }
                    }
                }

                Label(
                    "Jede Fälligkeit erhält genau eine dauerhafte Historienzeile. Ein erneuter Aufruf liefert denselben Zahlungsentwurf; übersprungene Termine können nicht nachträglich versendet werden.",
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                GroupBox("Ausführungshistorie") {
                    if runs.isEmpty {
                        Text("Noch keine Fälligkeit verarbeitet")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(runs) { run in
                                HStack {
                                    Image(
                                        systemName: run.status == .materialized
                                            ? "doc.badge.plus" : "forward.end"
                                    )
                                    Text(run.dueDate, format: .dateTime.day().month().year())
                                    if run.executionDate != run.dueDate {
                                        Text("→")
                                        Text(
                                            run.executionDate,
                                            format: .dateTime.day().month().year()
                                        )
                                    }
                                    Spacer()
                                    Text(run.status.title)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 6)
                                if run.id != runs.last?.id { Divider() }
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
        .onAppear { runs = store.standingOrderRuns(value) }
        .alert("Zahlungsentwurf vorbereiten?", isPresented: $confirmMaterialization) {
            Button("Abbrechen", role: .cancel) {}
            Button("Entwurf erzeugen") {
                _ = store.materializeStandingOrder(value)
            }
        } message: {
            Text(
                "Für \(value.recipientName) wird ein einzelner Terminüberweisungsentwurf über \(Money(minorUnits: value.amountMinor).formatted) erzeugt. Es erfolgt keine Bankübermittlung."
            )
        }
        .alert("Fälligkeit überspringen?", isPresented: $confirmSkip) {
            Button("Abbrechen", role: .cancel) {}
            Button("Überspringen", role: .destructive) {
                _ = store.skipStandingOrder(value)
            }
        } message: {
            Text("Der Termin wird dauerhaft als übersprungen protokolliert.")
        }
        .alert("Dauerauftrag beenden?", isPresented: $confirmCancellation) {
            Button("Abbrechen", role: .cancel) {}
            Button("Endgültig beenden", role: .destructive) {
                _ = store.setStandingOrderStatus(value, to: .cancelled)
            }
        } message: {
            Text("Bereits erzeugte Zahlungsentwürfe bleiben unverändert erhalten.")
        }
    }
}

private struct StandingOrderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    @State private var value: StandingOrder
    @State private var amountText: String
    @State private var hasEndDate: Bool

    init(value: StandingOrder) {
        _value = State(initialValue: value)
        _amountText = State(
            initialValue: Money(
                minorUnits: value.amountMinor, currency: value.currency
            ).editingString
        )
        _hasEndDate = State(initialValue: value.endDate != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Dauerauftrag bearbeiten").font(.title2.bold())
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Speichern") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || value.recipientName.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                            || value.purpose.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                            || amountText.isEmpty
                    )
            }
            .padding(14)
            Divider()
            Form {
                Section("Vorlage") {
                    TextField("Name", text: $value.name)
                    Picker("Auftraggeberkonto", selection: $value.accountID) {
                        ForEach(store.accounts.filter { !$0.isClosed && $0.currency == "EUR" }) {
                            Text($0.name).tag($0.id)
                        }
                    }
                    .onChange(of: value.accountID) {
                        if let account = store.accounts.first(where: {
                            $0.id == value.accountID
                        }) {
                            value.currency = account.currency
                        }
                    }
                    TextField("Empfänger", text: $value.recipientName)
                    TextField("IBAN", text: $value.iban)
                    TextField("BIC (optional)", text: $value.bic)
                    TextField("Betrag", text: $amountText)
                        .multilineTextAlignment(.trailing)
                    TextField("Verwendungszweck", text: $value.purpose)
                }
                Section("Zeitplan") {
                    DatePicker(
                        "Nächste Fälligkeit",
                        selection: $value.nextExecutionDate,
                        displayedComponents: .date
                    )
                    Picker("Rhythmus", selection: $value.frequency) {
                        ForEach(RecurrenceFrequency.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    Picker("Wochenendregel", selection: $value.businessDayAdjustment) {
                        ForEach(BusinessDayAdjustment.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    Toggle("Enddatum verwenden", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker(
                            "Enddatum",
                            selection: Binding(
                                get: { value.endDate ?? value.nextExecutionDate },
                                set: { value.endDate = $0 }
                            ),
                            in: value.nextExecutionDate...,
                            displayedComponents: .date
                        )
                    }
                    if value.status != .cancelled {
                        Picker("Status", selection: $value.status) {
                            Text(StandingOrderStatus.active.title)
                                .tag(StandingOrderStatus.active)
                            Text(StandingOrderStatus.paused.title)
                                .tag(StandingOrderStatus.paused)
                        }
                    }
                }
                Section {
                    Label(
                        "Speichern ändert nur künftige Fälligkeiten. Bereits vorbereitete Entwürfe und Historieneinträge bleiben unverändert.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 680, height: 720)
    }

    private func save() {
        do {
            value.amountMinor = abs(
                try Money(parsing: amountText, currency: value.currency).minorUnits
            )
            if !hasEndDate { value.endDate = nil }
            value.updatedAt = Date()
            if store.saveStandingOrder(value) {
                dismiss()
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}

private struct PaymentOrderDetail: View {
    @EnvironmentObject private var store: FinanceAppStore
    let order: PaymentOrder
    @State private var confirmInitiation = false
    @State private var authorizationCode = ""
    @State private var showPain001Exporter = false
    @State private var pain001Document = Pain001Document(data: Data())
    @State private var pain001FileName = "pain.001.xml"

    private var scaPath: [PaymentStatus] {
        var values: [PaymentStatus] = [
            .initiated, .challengeReceived, .awaitingUser, .submitted
        ]
        if [.accepted, .rejected, .unknown, .cancelled].contains(order.status) {
            values.append(order.status)
        }
        return values
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(order.recipientName).font(.title2.bold())
                    Text(order.type.title).foregroundStyle(.secondary)
                }
                Spacer()
                PaymentStatusBadge(status: order.status)
            }
            GroupBox("Unveränderliche Auftragszusammenfassung") {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow { Text("Auftraggeber").foregroundStyle(.secondary); Text(store.accountName(order.accountID)) }
                    GridRow { Text("Empfänger").foregroundStyle(.secondary); Text(order.recipientName) }
                    GridRow { Text("IBAN").foregroundStyle(.secondary); Text(order.iban).monospaced() }
                    GridRow { Text("Betrag").foregroundStyle(.secondary); Text(Money(minorUnits: order.amountMinor).formatted).bold() }
                    GridRow { Text("Ausführung").foregroundStyle(.secondary); Text(order.executionDate, format: .dateTime.day().month().year()) }
                    GridRow { Text("Zweck").foregroundStyle(.secondary); Text(order.purpose) }
                    GridRow { Text("End-to-End-ID").foregroundStyle(.secondary); Text(order.endToEndID).monospaced() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            GroupBox("SCA-Zustandsautomat") {
                HStack(spacing: 5) {
                    ForEach(scaPath, id: \.self) { status in
                        PaymentStatusBadge(status: status)
                        if status != scaPath.last {
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.top, 4)
            }
            actionArea
            Button("pain.001 exportieren …", systemImage: "doc.badge.arrow.up") {
                preparePain001Export()
            }
            .disabled(order.status != .draft)
            .help(
                order.status == .draft
                    ? "Erzeugt eine lokale SEPA-XML-Datei nach "
                        + Pain001RulePackage.epc2025.source
                    : "Nur unveränderte Entwürfe können als pain.001 initiiert werden."
            )
            if order.status == .unknown {
                Label(
                    "Der Status ist unbekannt. Der Auftrag wird niemals automatisch erneut gesendet. Zuerst muss der Bankstatus manuell geklärt werden.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                .padding(10)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            Spacer()
            Text("Idempotenz: \(order.idempotencyKey.prefix(20))…")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .alert("Zahlungsauftrag initialisieren?", isPresented: $confirmInitiation) {
            Button("Abbrechen", role: .cancel) {}
            Button("Im Simulator initialisieren") {
                _ = store.transitionPayment(order, to: .initiated)
            }
        } message: {
            Text("\(order.recipientName) erhält \(Money(minorUnits: order.amountMinor).formatted). Dies ist ausschließlich eine lokale Simulation.")
        }
        .fileExporter(
            isPresented: $showPain001Exporter,
            document: pain001Document,
            contentType: .xml,
            defaultFilename: pain001FileName
        ) { result in
            switch result {
            case .success:
                store.statusText = "Zahlungsauftrag als pain.001 exportiert"
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
    }

    private func preparePain001Export() {
        guard let account = store.accounts.first(where: { $0.id == order.accountID }) else {
            store.errorMessage = FinanceError.missingAccount.localizedDescription
            return
        }
        do {
            let result = try Pain001Exporter.export(order: order, account: account)
            pain001Document = Pain001Document(data: result.data)
            pain001FileName = result.fileName
            showPain001Exporter = true
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        switch order.status {
        case .draft:
            Button("Übermittlung vorbereiten …") { confirmInitiation = true }
                .buttonStyle(.borderedProminent)
        case .initiated:
            Button("Bank-Challenge simulieren") {
                _ = store.transitionPayment(order, to: .challengeReceived)
            }
            .buttonStyle(.borderedProminent)
        case .challengeReceived:
            Button("Freigabedialog öffnen") {
                _ = store.transitionPayment(order, to: .awaitingUser)
            }
            .buttonStyle(.borderedProminent)
        case .awaitingUser:
            VStack(alignment: .leading, spacing: 8) {
                SecureField("Simulierter Freigabecode", text: $authorizationCode)
                    .frame(maxWidth: 320)
                Text("Der Code wird nur im Arbeitsspeicher geprüft und niemals gespeichert oder protokolliert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Freigabe übermitteln") {
                    if store.submitPayment(order, authorizationCode: authorizationCode) {
                        authorizationCode = ""
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        case .submitted:
            VStack(alignment: .leading, spacing: 8) {
                Text("Simulator-Ergebnis").font(.headline)
                HStack {
                    ForEach(SimulatorOutcome.allCases) { outcome in
                        Button(outcome.title) {
                            _ = store.simulatePaymentDecision(order, outcome: outcome)
                        }
                    }
                }
            }
        case .accepted:
            Label("Angenommen · als vorgemerkte Buchung im Kontoblatt materialisiert", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .rejected:
            Label("Vom Simulator abgelehnt", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .unknown:
            EmptyView()
        case .cancelled:
            Label("Auftrag abgebrochen", systemImage: "nosign")
        }
    }
}

private struct Pain001Document: FileDocument {
    static var readableContentTypes: [UTType] { [.xml] }
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct PaymentDraftEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    @State private var accountID: UUID?
    @State private var type: PaymentType = .sepaCreditTransfer
    @State private var recipientName = ""
    @State private var iban = ""
    @State private var bic = ""
    @State private var amount = ""
    @State private var executionDate = Date()
    @State private var purpose = ""
    @State private var endToEndID = "NOTPROVIDED"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Zahlungsentwurf").font(.title2.bold())
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Entwurf anlegen") {
                    guard let accountID else { return }
                    if store.createPaymentOrder(
                        accountID: accountID, type: type, recipientName: recipientName,
                        iban: iban, bic: bic, amount: amount,
                        executionDate: executionDate, purpose: purpose,
                        endToEndID: endToEndID
                    ) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(accountID == nil || recipientName.isEmpty || purpose.isEmpty || amount.isEmpty)
            }
            .padding(14)
            Divider()
            Form {
                Section("Auftrag") {
                    Picker("Auftraggeberkonto", selection: $accountID) {
                        Text("Konto wählen").tag(UUID?.none)
                        ForEach(store.accounts.filter { !$0.isClosed }) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }
                    Picker("Zahlungsart", selection: $type) {
                        ForEach(PaymentType.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Empfänger", text: $recipientName)
                    TextField("IBAN", text: $iban)
                    TextField("BIC (optional)", text: $bic)
                    TextField("Betrag", text: $amount)
                    DatePicker("Ausführung", selection: $executionDate, displayedComponents: .date)
                    TextField("Verwendungszweck", text: $purpose)
                    TextField("End-to-End-ID", text: $endToEndID)
                }
                Section {
                    Label(
                        "Dieser Entwicklungsstand sendet niemals an eine Bank. Live-Banking bleibt deaktiviert.",
                        systemImage: "lock.shield"
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 650, height: 660)
        .onAppear { accountID = accountID ?? store.accounts.first?.id }
    }
}

struct InvestmentsView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var selectedSecurityID: UUID?
    @State private var showSecurityEditor = false
    @State private var showTradeEditor = false
    @State private var showPriceEditor = false
    @State private var showAllocationEditor = false

    private var selectedSecurity: Security? {
        store.securities.first { $0.id == selectedSecurityID }
    }

    private var positions: [PortfolioPosition] {
        store.portfolioPositions.filter {
            selectedSecurityID == nil || $0.security.id == selectedSecurityID
        }
    }

    private var totalCost: Int64 {
        store.portfolioPositions.reduce(0) { $0 + $1.costBasisMinor }
    }

    private var totalMarket: Int64 {
        store.portfolioPositions.compactMap(\.marketValueMinor).reduce(0, +)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wertpapiere & Depots").font(.title2.bold())
                    Text("Lots, FIFO-Kostenbasis, Kurse und Vermögensklassen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Wertpapier", systemImage: "plus") { showSecurityEditor = true }
                Button("Kauf/Verkauf", systemImage: "arrow.left.arrow.right") {
                    showTradeEditor = true
                }
                .disabled(store.securities.isEmpty || investmentAccounts.isEmpty)
                Button("Kurs", systemImage: "chart.line.uptrend.xyaxis") {
                    showPriceEditor = true
                }
                .disabled(selectedSecurity == nil)
                Button("Allokation", systemImage: "chart.pie") {
                    showAllocationEditor = true
                }
                .disabled(selectedSecurity == nil)
            }
            .padding(12)
            Divider()
            HStack(spacing: 12) {
                BudgetMetric(title: "Marktwert", value: Money(minorUnits: totalMarket).formatted)
                BudgetMetric(title: "Kostenbasis", value: Money(minorUnits: totalCost).formatted)
                BudgetMetric(
                    title: "Unrealisierter Gewinn",
                    value: Money(minorUnits: totalMarket - totalCost).formatted,
                    warning: totalMarket < totalCost
                )
            }
            .padding(12)
            Divider()
            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Text("Wertpapiere").font(.headline)
                        Spacer()
                        Text("\(store.securities.count)")
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    Divider()
                    List(selection: $selectedSecurityID) {
                        Text("Gesamtes Depot").tag(UUID?.none)
                        ForEach(store.securities) { security in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(security.name)
                                Text(
                                    [security.isin, security.ticker]
                                        .filter { !$0.isEmpty }.joined(separator: " · ")
                                )
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            }
                            .tag(Optional(security.id))
                        }
                    }
                }
                .frame(minWidth: 260, idealWidth: 320)

                VStack(spacing: 0) {
                    HStack {
                        Text("Depotpositionen").font(.headline)
                        Spacer()
                        Text("\(positions.count) Positionen")
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    Divider()
                    if positions.isEmpty {
                        ContentUnavailableView(
                            "Keine Positionen",
                            systemImage: "chart.line.uptrend.xyaxis",
                            description: Text("Erfasse einen Kauf oder wähle ein anderes Wertpapier.")
                        )
                    } else {
                        List(positions) { position in
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(position.security.name).fontWeight(.medium)
                                    Text(store.accountName(position.accountID))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                InvestmentValue(
                                    title: "Bestand",
                                    value: SecurityQuantity(
                                        microUnits: position.quantityMicro
                                    ).formatted
                                )
                                InvestmentValue(
                                    title: "Kurs",
                                    value: position.latestPriceMinor.map {
                                        Money(minorUnits: $0).formatted
                                    } ?? "—"
                                )
                                InvestmentValue(
                                    title: "Marktwert",
                                    value: position.marketValueMinor.map {
                                        Money(minorUnits: $0).formatted
                                    } ?? "—"
                                )
                                InvestmentValue(
                                    title: "Gewinn",
                                    value: position.unrealizedGainMinor.map {
                                        Money(minorUnits: $0).formatted
                                    } ?? "—",
                                    valueColor: (position.unrealizedGainMinor ?? 0) < 0 ? .red : .green
                                )
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    if let selectedSecurity {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Transaktionshistorie · \(selectedSecurity.name)")
                                .font(.headline)
                            ForEach(
                                store.securityTrades.filter { $0.securityID == selectedSecurity.id }.prefix(5)
                            ) { trade in
                                HStack {
                                    Text(trade.tradeDate, format: .dateTime.day().month().year())
                                        .frame(width: 90, alignment: .leading)
                                    Text(trade.type.title).frame(width: 70, alignment: .leading)
                                    Text(SecurityQuantity(microUnits: abs(trade.quantityMicro)).formatted)
                                    Spacer()
                                    Text(Money(minorUnits: trade.grossMinor).formatted)
                                    if trade.type == .sell {
                                        Text("Gewinn \(Money(minorUnits: trade.realizedGainMinor).formatted)")
                                            .foregroundStyle(trade.realizedGainMinor < 0 ? .red : .green)
                                    }
                                }
                                .font(.caption)
                            }
                        }
                        .padding(12)
                    }
                }
                .frame(minWidth: 600)
            }
        }
        .sheet(isPresented: $showSecurityEditor) { SecurityEditor() }
        .sheet(isPresented: $showTradeEditor) {
            SecurityTradeEditor(initialSecurityID: selectedSecurityID)
        }
        .sheet(isPresented: $showPriceEditor) {
            if let selectedSecurity { SecurityPriceEditor(security: selectedSecurity) }
        }
        .sheet(isPresented: $showAllocationEditor) {
            if let selectedSecurity { AllocationEditor(security: selectedSecurity) }
        }
    }

    private var investmentAccounts: [FinanceAccount] {
        store.accounts.filter { $0.type == .investment && !$0.isClosed }
    }
}

private struct InvestmentValue: View {
    let title: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).monospacedDigit().foregroundStyle(valueColor)
        }
        .frame(minWidth: 92, alignment: .trailing)
    }
}

private struct SecurityEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    @State private var value = Security(
        id: UUID(), name: "", shortName: "", isin: "", wkn: "", ticker: "",
        type: .etf, currency: "EUR", exchange: "Xetra", priceDecimals: 2,
        allowsShort: false, isActive: true, note: ""
    )

    var body: some View {
        VStack(spacing: 0) {
            editorHeader("Wertpapier anlegen") {
                if store.saveSecurity(value) { dismiss() }
            }
            Form {
                TextField("Name", text: $value.name)
                TextField("Kurzname", text: $value.shortName)
                Picker("Typ", selection: $value.type) {
                    ForEach(SecurityType.allCases) { Text($0.title).tag($0) }
                }
                TextField("ISIN", text: $value.isin)
                TextField("WKN", text: $value.wkn)
                TextField("Ticker", text: $value.ticker)
                TextField("Handelswährung", text: $value.currency)
                TextField("Börsenplatz", text: $value.exchange)
                Stepper("Kurs-Nachkommastellen: \(value.priceDecimals)", value: $value.priceDecimals, in: 0...8)
                Toggle(
                    "Short-Positionen (in diesem Stand deaktiviert)",
                    isOn: $value.allowsShort
                )
                .disabled(true)
                Toggle("Aktiv", isOn: $value.isActive)
                TextField("Notiz", text: $value.note)
            }
            .formStyle(.grouped)
        }
        .frame(width: 600, height: 600)
    }

    private func editorHeader(_ title: String, save: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Speichern", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(value.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14)
            Divider()
        }
    }
}

private struct SecurityTradeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    @State private var accountID: UUID?
    @State private var securityID: UUID?
    @State private var type: SecurityTradeType = .buy
    @State private var date = Date()
    @State private var quantity = ""
    @State private var price = ""
    @State private var fees = "0,00"
    @State private var taxes = "0,00"
    @State private var note = ""
    let initialSecurityID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Wertpapiertransaktion").font(.title2.bold())
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Speichern") {
                    guard let accountID, let securityID else { return }
                    if store.recordSecurityTrade(
                        accountID: accountID, securityID: securityID, type: type,
                        date: date, quantity: quantity, price: price,
                        fees: fees, taxes: taxes, note: note
                    ) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(accountID == nil || securityID == nil || quantity.isEmpty || price.isEmpty)
            }
            .padding(14)
            Divider()
            Form {
                Picker("Depot", selection: $accountID) {
                    Text("Bitte wählen").tag(UUID?.none)
                    ForEach(store.accounts.filter { $0.type == .investment && !$0.isClosed }) {
                        Text($0.name).tag(Optional($0.id))
                    }
                }
                Picker("Wertpapier", selection: $securityID) {
                    Text("Bitte wählen").tag(UUID?.none)
                    ForEach(store.securities.filter(\.isActive)) {
                        Text($0.name).tag(Optional($0.id))
                    }
                }
                Picker("Art", selection: $type) {
                    Text(SecurityTradeType.buy.title).tag(SecurityTradeType.buy)
                    Text(SecurityTradeType.sell.title).tag(SecurityTradeType.sell)
                }
                DatePicker("Handelstag", selection: $date, displayedComponents: .date)
                TextField("Stückzahl", text: $quantity)
                TextField("Kurs je Stück", text: $price)
                TextField("Gebühren", text: $fees)
                TextField("Steuern", text: $taxes)
                TextField("Notiz", text: $note)
                Text("Stückzahlen werden mit sechs Dezimalstellen, Geldwerte als Minor-Units gespeichert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
        }
        .frame(width: 600, height: 560)
        .onAppear {
            accountID = store.accounts.first { $0.type == .investment && !$0.isClosed }?.id
            securityID = initialSecurityID ?? store.securities.first?.id
        }
    }
}

private struct SecurityPriceEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    let security: Security
    @State private var date = Date()
    @State private var price = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Kurs · \(security.name)").font(.title2.bold())
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Speichern") {
                    if store.saveSecurityPrice(
                        securityID: security.id, date: date, price: price
                    ) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(price.isEmpty)
            }
            .padding(14)
            Divider()
            Form {
                DatePicker("Kursdatum", selection: $date, displayedComponents: .date)
                TextField("Kurs in \(security.currency)", text: $price)
                Text("Quelle: Manuell").foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 260)
    }
}

private struct AllocationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    let security: Security
    @State private var values: [UUID: String] = [:]

    private var basisPoints: [(assetClassID: UUID, basisPoints: Int)] {
        store.assetClasses.map { assetClass in
            let decimal = Decimal(
                string: (values[assetClass.id] ?? "0").replacingOccurrences(of: ",", with: "."),
                locale: Locale(identifier: "en_US_POSIX")
            ) ?? 0
            return (
                assetClass.id,
                NSDecimalNumber(decimal: decimal * 100).intValue
            )
        }
    }

    private var sum: Int { basisPoints.reduce(0) { $0 + $1.basisPoints } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Vermögensklassen · \(security.name)").font(.title2.bold())
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Speichern") {
                    if store.saveAllocations(securityID: security.id, values: basisPoints) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(sum != 10_000)
            }
            .padding(14)
            Divider()
            Form {
                ForEach(store.assetClasses.filter(\.isActive)) { assetClass in
                    TextField(
                        "\(assetClass.name) in %",
                        text: Binding(
                            get: { values[assetClass.id] ?? "0" },
                            set: { values[assetClass.id] = $0 }
                        )
                    )
                }
                LabeledContent("Summe") {
                    Text(verbatim: "\(Decimal(sum) / 100) %")
                        .foregroundStyle(sum == 10_000 ? .green : .red)
                }
                Text("Die Zuordnung kann nur mit exakt 100 % gespeichert werden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
        }
        .frame(width: 560, height: 450)
        .onAppear {
            for allocation in store.allocations(securityID: security.id) {
                values[allocation.assetClassID] =
                    (Decimal(allocation.basisPoints) / 100).formatted()
            }
        }
    }
}

struct AssetsView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var mode = 0
    @State private var selectedLoanID: UUID?
    @State private var selectedAssetID: UUID?
    @State private var showLoanEditor = false
    @State private var showRateEditor = false
    @State private var showExtraEditor = false
    @State private var showAssetEditor = false
    @State private var showValuationEditor = false

    private var selectedLoan: FinanceLoan? {
        store.loans.first { $0.id == selectedLoanID }
    }
    private var selectedAsset: PropertyAssetPosition? {
        store.propertyAssetPositions.first { $0.id == selectedAssetID }
    }
    private var totalLoanBalance: Int64 {
        store.loans.reduce(Int64.zero) { $0 + remainingBalance(for: $1) }
    }
    private var totalAssetValue: Int64 {
        store.propertyAssetPositions.reduce(Int64.zero) { $0 + $1.currentValueMinor }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kredite & Vermögen").font(.title2.bold())
                    Text("Tilgungspläne, variable Zinssätze, Sondertilgungen und Nettovermögen")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $mode) {
                    Text("Kredite").tag(0)
                    Text("Vermögenswerte").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 270)
                if mode == 0 {
                    Button("Darlehen", systemImage: "plus") { showLoanEditor = true }
                    Button("Zinsänderung", systemImage: "percent") {
                        showRateEditor = true
                    }
                    .disabled(selectedLoan == nil)
                    Button("Sondertilgung", systemImage: "arrow.down.circle") {
                        showExtraEditor = true
                    }
                    .disabled(selectedLoan == nil)
                } else {
                    Button("Vermögenswert", systemImage: "plus") { showAssetEditor = true }
                    Button("Bewertung", systemImage: "eurosign.arrow.circlepath") {
                        showValuationEditor = true
                    }
                    .disabled(selectedAsset == nil)
                }
            }
            .padding(14)

            HStack(spacing: 10) {
                InvestmentValue(
                    title: "Vermögenswerte",
                    value: Money(minorUnits: totalAssetValue).formatted
                )
                InvestmentValue(
                    title: "Restschulden",
                    value: Money(minorUnits: totalLoanBalance).formatted
                )
                InvestmentValue(
                    title: "Nettoanteil",
                    value: Money(minorUnits: totalAssetValue - totalLoanBalance).formatted,
                    valueColor: totalAssetValue >= totalLoanBalance ? .green : .red
                )
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider()
            if mode == 0 {
                loanWorkspace
            } else {
                assetWorkspace
            }
        }
        .onAppear {
            if selectedLoanID == nil { selectedLoanID = store.loans.first?.id }
            if selectedAssetID == nil { selectedAssetID = store.propertyAssetPositions.first?.id }
        }
        .sheet(isPresented: $showLoanEditor) { LoanEditor() }
        .sheet(isPresented: $showRateEditor) {
            if let selectedLoan { LoanRateEditor(loan: selectedLoan) }
        }
        .sheet(isPresented: $showExtraEditor) {
            if let selectedLoan { LoanExtraPaymentEditor(loan: selectedLoan) }
        }
        .sheet(isPresented: $showAssetEditor) { PropertyAssetEditor() }
        .sheet(isPresented: $showValuationEditor) {
            if let selectedAsset { AssetValuationEditor(asset: selectedAsset.asset) }
        }
    }

    private var loanWorkspace: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Darlehen").font(.headline)
                    Spacer()
                    Text("\(store.loans.count)").foregroundStyle(.secondary)
                }
                .padding(10)
                List(selection: $selectedLoanID) {
                    ForEach(store.loans) { loan in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(loan.name).fontWeight(.semibold)
                            HStack {
                                Text(loan.lender)
                                Spacer()
                                Text(Money(minorUnits: remainingBalance(for: loan)).formatted)
                                    .monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .tag(loan.id)
                    }
                }
            }
            .frame(minWidth: 250, idealWidth: 300)

            Group {
                if let loan = selectedLoan {
                    loanDetail(loan)
                } else {
                    ContentUnavailableView(
                        "Kein Darlehen ausgewählt",
                        systemImage: "building.columns",
                        description: Text("Lege ein Darlehen mit Ausgangszinssatz an.")
                    )
                }
            }
            .frame(minWidth: 650)
        }
    }

    private func loanDetail(_ loan: FinanceLoan) -> some View {
        let schedule = store.loanSchedule(loanID: loan.id)
        let rates = store.loanInterestRates(loanID: loan.id)
        let extras = store.loanExtraPayments(loanID: loan.id)
        let remaining = remainingBalance(for: loan)
        let totalInterest = schedule.reduce(Int64.zero) { $0 + $1.interestMinor }
        let totalFees = schedule.reduce(Int64.zero) { $0 + $1.feeMinor }
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(loan.name).font(.title3.bold())
                    Text("\(loan.lender) · Auszahlung \(loan.disbursementDate.formatted(date: .abbreviated, time: .omitted))")
                        .foregroundStyle(.secondary)
                    if let accountID = loan.linkedAccountID {
                        Label(store.accountName(accountID), systemImage: "link")
                            .font(.caption)
                    }
                }
                Spacer()
                loanMetric("Ursprung", loan.principalMinor)
                loanMetric("Restschuld", remaining)
                loanMetric("Zins + Gebühren", totalInterest + totalFees)
            }
            .padding(14)
            Divider()
            HStack(spacing: 18) {
                Label(
                    "\(loan.termMonths) Monate",
                    systemImage: "calendar"
                )
                Label(
                    "\(Money(minorUnits: loan.installmentMinor).formatted) Rate",
                    systemImage: "repeat"
                )
                if let last = schedule.last {
                    Label(
                        last.closingBalanceMinor == 0
                            ? "Schuldenfrei \(last.dueDate.formatted(date: .abbreviated, time: .omitted))"
                            : "\(Money(minorUnits: last.closingBalanceMinor).formatted) Ballonrest",
                        systemImage: last.closingBalanceMinor == 0 ? "checkmark.seal" : "exclamationmark.triangle"
                    )
                }
                Spacer()
                Text("\(rates.count) Zinssätze · \(extras.count) Sondertilgungen")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 14)
            .frame(height: 38)
            Divider()
            loanScheduleTable(schedule)
        }
    }

    private func loanScheduleTable(_ entries: [LoanScheduleEntry]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tilgungsplan").font(.headline)
                Spacer()
                Text("\(entries.count) Raten")
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            Grid(horizontalSpacing: 12, verticalSpacing: 0) {
                GridRow {
                    scheduleHeader("Nr.", alignment: .trailing)
                    scheduleHeader("Fälligkeit")
                    scheduleHeader("Sollzins", alignment: .trailing)
                    scheduleHeader("Rate", alignment: .trailing)
                    scheduleHeader("Tilgung", alignment: .trailing)
                    scheduleHeader("Zins", alignment: .trailing)
                    scheduleHeader("Sondertilgung", alignment: .trailing)
                    scheduleHeader("Restschuld", alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                Divider()
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.fixed(36), alignment: .trailing),
                            GridItem(.flexible(minimum: 86, maximum: 120), alignment: .leading),
                            GridItem(.flexible(minimum: 66, maximum: 90), alignment: .trailing),
                            GridItem(.flexible(minimum: 82, maximum: 110), alignment: .trailing),
                            GridItem(.flexible(minimum: 82, maximum: 110), alignment: .trailing),
                            GridItem(.flexible(minimum: 75, maximum: 100), alignment: .trailing),
                            GridItem(.flexible(minimum: 96, maximum: 125), alignment: .trailing),
                            GridItem(.flexible(minimum: 100, maximum: 140), alignment: .trailing)
                        ],
                        alignment: .leading, spacing: 0
                    ) {
                        ForEach(entries) { entry in
                            Text("\(entry.sequence)")
                            Text(entry.dueDate.formatted(date: .numeric, time: .omitted))
                            Text(
                                (Decimal(entry.annualBasisPoints) / 100).formatted(
                                    .number.locale(Locale(identifier: "de_DE"))
                                        .precision(.fractionLength(2))
                                ) + " %"
                            )
                            Text(Money(minorUnits: entry.installmentMinor).formatted)
                            Text(Money(minorUnits: entry.principalMinor).formatted)
                            Text(Money(minorUnits: entry.interestMinor).formatted)
                            Text(
                                entry.extraPaymentMinor == 0
                                    ? "–" : Money(minorUnits: entry.extraPaymentMinor).formatted
                            )
                            Text(Money(minorUnits: entry.closingBalanceMinor).formatted)
                                .fontWeight(entry.closingBalanceMinor == 0 ? .semibold : .regular)
                        }
                        .font(.caption.monospacedDigit())
                        .frame(height: 28)
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
    }

    private var assetWorkspace: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Vermögenswerte").font(.headline)
                    Spacer()
                    Text("\(store.propertyAssetPositions.count)")
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                List(selection: $selectedAssetID) {
                    ForEach(store.propertyAssetPositions) { position in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(position.asset.name).fontWeight(.semibold)
                            HStack {
                                Text(position.asset.type.title)
                                Spacer()
                                Text(Money(minorUnits: position.currentValueMinor).formatted)
                                    .monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .tag(position.id)
                    }
                }
            }
            .frame(minWidth: 250, idealWidth: 300)

            Group {
                if let position = selectedAsset {
                    assetDetail(position)
                } else {
                    ContentUnavailableView(
                        "Kein Vermögenswert ausgewählt",
                        systemImage: "house",
                        description: Text("Lege Immobilien, Fahrzeuge oder andere Werte an.")
                    )
                }
            }
            .frame(minWidth: 650)
        }
    }

    private func assetDetail(_ position: PropertyAssetPosition) -> some View {
        let history = store.assetValuations(assetID: position.id).reversed()
        return VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(position.asset.name).font(.title3.bold())
                    Text("\(position.asset.type.title) · \(position.asset.location)")
                        .foregroundStyle(.secondary)
                    Text("Kauf \(position.asset.purchaseDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                }
                Spacer()
                loanMetric("Aktueller Wert", position.currentValueMinor)
                loanMetric("Verknüpfter Kredit", position.linkedLoanBalanceMinor)
                loanMetric("Nettoanteil", position.netEquityMinor)
            }
            .padding(14)
            Divider()
            HStack {
                Text("Wertverlauf").font(.headline)
                Spacer()
                Text("Kaufwert \(Money(minorUnits: position.asset.purchaseValueMinor).formatted)")
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            List {
                ForEach(Array(history)) { valuation in
                    HStack {
                        Text(valuation.valuationDate.formatted(date: .abbreviated, time: .omitted))
                            .frame(width: 120, alignment: .leading)
                        Text(valuation.source.isEmpty ? "Manuell" : valuation.source)
                        Spacer()
                        Text(Money(minorUnits: valuation.valueMinor).formatted)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func remainingBalance(for loan: FinanceLoan) -> Int64 {
        store.loanSchedule(loanID: loan.id)
            .filter { $0.dueDate <= Date() }
            .last?.closingBalanceMinor ?? loan.principalMinor
    }

    private func loanMetric(_ title: String, _ value: Int64) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money(minorUnits: value).formatted)
                .font(.headline.monospacedDigit())
        }
        .frame(minWidth: 125, alignment: .trailing)
    }

    private func scheduleHeader(
        _ value: String,
        alignment: Alignment = .leading
    ) -> some View {
        Text(value)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}

private struct AssetEditorHeader: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let saveDisabled: Bool
    let save: () -> Void

    var body: some View {
        HStack {
            Text(title).font(.title2.bold())
            Spacer()
            Button("Abbrechen") { dismiss() }
            Button("Speichern", action: save)
                .buttonStyle(.borderedProminent)
                .disabled(saveDisabled)
        }
        .padding(14)
    }
}

private struct LoanEditor: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var lender = ""
    @State private var principal = ""
    @State private var annualRate = ""
    @State private var disbursementDate = Date()
    @State private var firstPaymentDate =
        Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var hasFixedRate = true
    @State private var fixedRateUntil =
        Calendar.current.date(byAdding: .year, value: 10, to: Date()) ?? Date()
    @State private var termMonths = 240
    @State private var installment = ""
    @State private var regularFee = "0"
    @State private var linkedAccountID: UUID?
    @State private var note = ""

    var body: some View {
        VStack(spacing: 0) {
            AssetEditorHeader(
                title: "Darlehen anlegen", saveDisabled: name.isEmpty, save: save
            )
            Form {
                TextField("Bezeichnung", text: $name)
                TextField("Kreditgeber", text: $lender)
                TextField("Darlehensbetrag", text: $principal)
                TextField("Sollzins p. a. (%)", text: $annualRate)
                DatePicker("Auszahlung", selection: $disbursementDate, displayedComponents: .date)
                DatePicker("Erste Fälligkeit", selection: $firstPaymentDate, displayedComponents: .date)
                Toggle("Zinsbindung", isOn: $hasFixedRate)
                if hasFixedRate {
                    DatePicker("Gebunden bis", selection: $fixedRateUntil, displayedComponents: .date)
                }
                Stepper("Laufzeit: \(termMonths) Monate", value: $termMonths, in: 1...600)
                TextField("Monatsrate", text: $installment)
                TextField("Gebühr je Rate", text: $regularFee)
                Picker("Zahlungskonto", selection: $linkedAccountID) {
                    Text("Nicht verknüpft").tag(UUID?.none)
                    ForEach(store.accounts.filter { $0.type != .investment }) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                TextField("Notiz", text: $note, axis: .vertical)
            }
            .formStyle(.grouped)
        }
        .frame(width: 600, height: 650)
    }

    private func save() {
        do {
            let principalMoney = try Money(parsing: principal)
            let installmentMoney = try Money(parsing: installment)
            let feeMoney = try Money(parsing: regularFee.isEmpty ? "0" : regularFee)
            let loan = FinanceLoan(
                id: UUID(), name: name, lender: lender,
                principalMinor: abs(principalMoney.minorUnits),
                disbursementDate: disbursementDate,
                firstPaymentDate: firstPaymentDate,
                fixedRateUntil: hasFixedRate ? fixedRateUntil : nil,
                termMonths: termMonths,
                installmentMinor: abs(installmentMoney.minorUnits),
                regularFeeMinor: abs(feeMoney.minorUnits),
                dueDay: Calendar.current.component(.day, from: firstPaymentDate),
                linkedAccountID: linkedAccountID, currency: "EUR",
                note: note, isActive: true
            )
            if store.saveLoan(loan, initialRate: annualRate) { dismiss() }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}

private struct LoanRateEditor: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    let loan: FinanceLoan
    @State private var effectiveFrom = Date()
    @State private var annualRate = ""
    @State private var note = ""

    var body: some View {
        VStack(spacing: 0) {
            AssetEditorHeader(
                title: "Zinsänderung · \(loan.name)",
                saveDisabled: annualRate.isEmpty
            ) {
                if store.saveLoanInterestRate(
                    loanID: loan.id, effectiveFrom: effectiveFrom,
                    annualRate: annualRate, note: note
                ) { dismiss() }
            }
            Form {
                DatePicker("Gültig ab", selection: $effectiveFrom, displayedComponents: .date)
                TextField("Neuer Sollzins p. a. (%)", text: $annualRate)
                TextField("Notiz", text: $note)
                Text("Der bisherige Zinssatz bleibt für frühere Raten erhalten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 280)
    }
}

private struct LoanExtraPaymentEditor: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    let loan: FinanceLoan
    @State private var date = Date()
    @State private var amount = ""
    @State private var note = ""

    var body: some View {
        VStack(spacing: 0) {
            AssetEditorHeader(
                title: "Sondertilgung · \(loan.name)", saveDisabled: amount.isEmpty
            ) {
                if store.saveLoanExtraPayment(
                    loanID: loan.id, date: date, amount: amount, note: note
                ) { dismiss() }
            }
            Form {
                DatePicker("Termin", selection: $date, displayedComponents: .date)
                TextField("Betrag", text: $amount)
                TextField("Notiz", text: $note)
                Text("Die Sondertilgung wird im Monat der Fälligkeit zusätzlich verrechnet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 280)
    }
}

private struct PropertyAssetEditor: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type: PropertyAssetType = .realEstate
    @State private var purchaseDate = Date()
    @State private var purchaseValue = ""
    @State private var linkedLoanID: UUID?
    @State private var location = ""
    @State private var note = ""

    var body: some View {
        VStack(spacing: 0) {
            AssetEditorHeader(
                title: "Vermögenswert anlegen", saveDisabled: name.isEmpty, save: save
            )
            Form {
                TextField("Bezeichnung", text: $name)
                Picker("Typ", selection: $type) {
                    ForEach(PropertyAssetType.allCases) { Text($0.title).tag($0) }
                }
                DatePicker("Kaufdatum", selection: $purchaseDate, displayedComponents: .date)
                TextField("Kaufwert", text: $purchaseValue)
                Picker("Verknüpfter Kredit", selection: $linkedLoanID) {
                    Text("Keiner").tag(UUID?.none)
                    ForEach(store.loans) { loan in
                        Text(loan.name).tag(Optional(loan.id))
                    }
                }
                TextField("Ort", text: $location)
                TextField("Notiz", text: $note, axis: .vertical)
            }
            .formStyle(.grouped)
        }
        .frame(width: 560, height: 500)
    }

    private func save() {
        do {
            let money = try Money(parsing: purchaseValue)
            let value = PropertyAsset(
                id: UUID(), name: name, type: type,
                purchaseDate: purchaseDate,
                purchaseValueMinor: abs(money.minorUnits),
                linkedLoanID: linkedLoanID, location: location,
                note: note, isActive: true
            )
            if store.savePropertyAsset(value) { dismiss() }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}

private struct AssetValuationEditor: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    let asset: PropertyAsset
    @State private var date = Date()
    @State private var value = ""
    @State private var source = "Eigene Schätzung"
    @State private var note = ""

    var body: some View {
        VStack(spacing: 0) {
            AssetEditorHeader(
                title: "Bewertung · \(asset.name)", saveDisabled: value.isEmpty
            ) {
                if store.saveAssetValuation(
                    assetID: asset.id, date: date, value: value,
                    source: source, note: note
                ) { dismiss() }
            }
            Form {
                DatePicker("Bewertungsdatum", selection: $date, displayedComponents: .date)
                TextField("Aktueller Wert", text: $value)
                TextField("Quelle", text: $source)
                TextField("Notiz", text: $note)
                Text("Die Bewertung ist eine Verwaltungshilfe und kein Gutachten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 320)
    }
}

struct ContractsView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var selectedID: UUID?
    @State private var showEditor = false

    private var selected: FinanceContract? {
        store.contracts.first { $0.id == selectedID }
    }
    private var annualCost: Int64 {
        store.contracts.filter(\.isActive)
            .reduce(Int64.zero) { $0 + $1.annualCostMinor }
    }
    private var nextDeadline: Date? {
        store.contracts.filter(\.isActive)
            .compactMap { $0.cancellationDeadline() }
            .filter { $0 >= Calendar.current.startOfDay(for: Date()) }
            .min()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Verträge").font(.title2.bold())
                    Text("Laufzeiten, Kündigungsfristen, Zahlungen und Erinnerungen")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                InvestmentValue(
                    title: "Aktive Verträge",
                    value: "\(store.contracts.filter(\.isActive).count)"
                )
                InvestmentValue(
                    title: "Erwartete Jahreskosten",
                    value: Money(minorUnits: annualCost).formatted
                )
                InvestmentValue(
                    title: "Nächste Kündigungsfrist",
                    value: nextDeadline?.formatted(date: .abbreviated, time: .omitted) ?? "–"
                )
                Button("Vertrag", systemImage: "plus") { showEditor = true }
            }
            .padding(14)
            Divider()
            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Text("Vertragsbestand").font(.headline)
                        Spacer()
                        Text("\(store.contracts.count)").foregroundStyle(.secondary)
                    }
                    .padding(10)
                    List(selection: $selectedID) {
                        ForEach(store.contracts) { contract in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(contract.name).fontWeight(.semibold)
                                HStack {
                                    Text(contract.provider)
                                    Spacer()
                                    Text(Money(minorUnits: contract.annualCostMinor).formatted + "/Jahr")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .tag(contract.id)
                        }
                    }
                }
                .frame(minWidth: 300, idealWidth: 360)
                Group {
                    if let selected {
                        contractDetail(selected)
                    } else {
                        ContentUnavailableView(
                            "Kein Vertrag ausgewählt",
                            systemImage: "doc.text",
                            description: Text("Lege einen Vertrag mit Fristen und Kosten an.")
                        )
                    }
                }
                .frame(minWidth: 580)
            }
        }
        .onAppear {
            if selectedID == nil { selectedID = store.contracts.first?.id }
        }
        .sheet(isPresented: $showEditor) { ContractEditor() }
    }

    private func contractDetail(_ contract: FinanceContract) -> some View {
        let renewal = contract.nextRenewal()
        let deadline = contract.cancellationDeadline()
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(contract.name).font(.title2.bold())
                        Text("\(contract.type.title) · \(contract.provider)")
                            .foregroundStyle(.secondary)
                        if !contract.contractNumber.isEmpty {
                            Text("Vertragsnummer \(contract.contractNumber)")
                                .font(.caption.monospaced())
                        }
                    }
                    Spacer()
                    Text(contract.isActive ? "Aktiv" : "Inaktiv")
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(
                            contract.isActive ? Color.green.opacity(0.14) : Color.gray.opacity(0.14),
                            in: Capsule()
                        )
                }
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 12) {
                    GridRow {
                        contractField("Beginn", contract.startDate.formatted(date: .long, time: .omitted))
                        contractField("Mindestlaufzeit", "\(contract.initialTermMonths) Monate")
                        contractField("Verlängerung", contract.renewalMonths == 0 ? "Keine" : "\(contract.renewalMonths) Monate")
                    }
                    GridRow {
                        contractField("Zahlbetrag", Money(minorUnits: contract.amountMinor).formatted)
                        contractField("Frequenz", contract.frequency.title)
                        contractField("Jahreskosten", Money(minorUnits: contract.annualCostMinor).formatted)
                    }
                    GridRow {
                        contractField("Nächste Verlängerung", renewal?.formatted(date: .long, time: .omitted) ?? "–")
                        contractField(
                            "Kündigungsfrist",
                            deadline?.formatted(date: .long, time: .omitted) ?? "–"
                        )
                        contractField("Erinnerung", "\(contract.reminderDays) Tage vorher")
                    }
                }
                Divider()
                if let accountID = contract.accountID {
                    Label("Zahlungskonto: \(store.accountName(accountID))", systemImage: "building.columns")
                }
                if let categoryID = contract.categoryID {
                    Label("Kategorie: \(store.categoryName(categoryID))", systemImage: "tag")
                }
                if !contract.note.isEmpty {
                    GroupBox("Notiz") {
                        Text(contract.note).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                GroupBox("Dokumente") {
                    Label(
                        "Dokumentmetadaten sind vorbereitet; die sichere Dateiauswahl folgt im Anhangsmodul.",
                        systemImage: "paperclip"
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }

    private func contractField(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium)
        }
        .frame(minWidth: 150, alignment: .leading)
    }
}

private struct ContractEditor: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var provider = ""
    @State private var contractNumber = ""
    @State private var name = ""
    @State private var type: ContractType = .insurance
    @State private var startDate = Date()
    @State private var initialTermMonths = 12
    @State private var renewalMonths = 12
    @State private var cancellationNoticeDays = 30
    @State private var amount = ""
    @State private var frequency: ContractPaymentFrequency = .monthly
    @State private var accountID: UUID?
    @State private var categoryID: UUID?
    @State private var reminderDays = 14
    @State private var note = ""

    var body: some View {
        VStack(spacing: 0) {
            AssetEditorHeader(
                title: "Vertrag anlegen",
                saveDisabled: name.isEmpty || provider.isEmpty,
                save: save
            )
            Form {
                TextField("Bezeichnung", text: $name)
                TextField("Anbieter", text: $provider)
                TextField("Vertragsnummer", text: $contractNumber)
                Picker("Typ", selection: $type) {
                    ForEach(ContractType.allCases) { Text($0.title).tag($0) }
                }
                DatePicker("Beginn", selection: $startDate, displayedComponents: .date)
                Stepper(
                    "Mindestlaufzeit: \(initialTermMonths) Monate",
                    value: $initialTermMonths, in: 1...600
                )
                Stepper(
                    "Verlängerung: \(renewalMonths) Monate",
                    value: $renewalMonths, in: 0...120
                )
                Stepper(
                    "Kündigungsfrist: \(cancellationNoticeDays) Tage",
                    value: $cancellationNoticeDays, in: 0...730
                )
                TextField("Zahlbetrag", text: $amount)
                Picker("Zahlungsfrequenz", selection: $frequency) {
                    ForEach(ContractPaymentFrequency.allCases) { Text($0.title).tag($0) }
                }
                Picker("Zahlungskonto", selection: $accountID) {
                    Text("Nicht zugeordnet").tag(UUID?.none)
                    ForEach(store.accounts) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Kategorie", selection: $categoryID) {
                    Text("Nicht zugeordnet").tag(UUID?.none)
                    ForEach(store.categoriesByPath) {
                        Text(store.categoryPath($0.id)).tag(Optional($0.id))
                    }
                }
                Stepper(
                    "Erinnerung: \(reminderDays) Tage vorher",
                    value: $reminderDays, in: 0...365
                )
                TextField("Notiz", text: $note, axis: .vertical)
            }
            .formStyle(.grouped)
        }
        .frame(width: 620, height: 720)
    }

    private func save() {
        do {
            let money = try Money(parsing: amount)
            let value = FinanceContract(
                id: UUID(), provider: provider, contractNumber: contractNumber,
                name: name, type: type, startDate: startDate,
                initialTermMonths: initialTermMonths, renewalMonths: renewalMonths,
                cancellationNoticeDays: cancellationNoticeDays,
                amountMinor: abs(money.minorUnits), frequency: frequency,
                accountID: accountID, categoryID: categoryID,
                reminderDays: reminderDays, note: note, isActive: true
            )
            if store.saveContract(value) { dismiss() }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}

struct InventoryView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var selectedID: UUID?
    @State private var showEditor = false

    private var selected: InventoryItem? {
        store.inventoryItems.first { $0.id == selectedID }
    }
    private var totalCurrent: Int64 {
        store.inventoryItems.filter(\.isActive)
            .reduce(Int64.zero) { $0 + $1.currentValueMinor }
    }
    private var totalInsurance: Int64 {
        store.inventoryItems.filter(\.isActive)
            .reduce(Int64.zero) { $0 + $1.insuranceValueMinor }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Inventar").font(.title2.bold())
                    Text("Gegenstände, Werte, Seriennummern, Garantien und Versicherungsübersicht")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                InvestmentValue(title: "Gegenstände", value: "\(store.inventoryItems.count)")
                InvestmentValue(
                    title: "Aktueller Wert",
                    value: Money(minorUnits: totalCurrent).formatted
                )
                InvestmentValue(
                    title: "Versicherungswert",
                    value: Money(minorUnits: totalInsurance).formatted
                )
                Button("Gegenstand", systemImage: "plus") { showEditor = true }
            }
            .padding(14)
            Divider()
            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Text("Inventarliste").font(.headline)
                        Spacer()
                        Text("\(store.inventoryItems.count)").foregroundStyle(.secondary)
                    }
                    .padding(10)
                    List(selection: $selectedID) {
                        ForEach(store.inventoryItems) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).fontWeight(.semibold)
                                HStack {
                                    Text("\(item.room) · \(item.category.title)")
                                    Spacer()
                                    Text(Money(minorUnits: item.currentValueMinor).formatted)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .tag(item.id)
                        }
                    }
                }
                .frame(minWidth: 320, idealWidth: 380)
                Group {
                    if let selected {
                        inventoryDetail(selected)
                    } else {
                        ContentUnavailableView(
                            "Kein Gegenstand ausgewählt",
                            systemImage: "shippingbox",
                            description: Text("Lege einen Inventargegenstand an.")
                        )
                    }
                }
                .frame(minWidth: 560)
            }
        }
        .onAppear {
            if selectedID == nil { selectedID = store.inventoryItems.first?.id }
        }
        .sheet(isPresented: $showEditor) { InventoryItemEditor() }
    }

    private func inventoryDetail(_ item: InventoryItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.title2.bold())
                        Text("\(item.category.title) · \(item.room)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Versicherungswert").font(.caption).foregroundStyle(.secondary)
                        Text(Money(minorUnits: item.insuranceValueMinor).formatted)
                            .font(.title3.bold().monospacedDigit())
                    }
                }
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 12) {
                    GridRow {
                        inventoryField("Kaufpreis", Money(minorUnits: item.purchasePriceMinor).formatted)
                        inventoryField("Aktueller Wert", Money(minorUnits: item.currentValueMinor).formatted)
                    }
                    GridRow {
                        inventoryField(
                            "Kaufdatum",
                            item.purchaseDate?.formatted(date: .long, time: .omitted) ?? "–"
                        )
                        inventoryField("Händler", item.retailer.isEmpty ? "–" : item.retailer)
                    }
                    GridRow {
                        inventoryField(
                            "Garantieende",
                            item.warrantyEnd?.formatted(date: .long, time: .omitted) ?? "–"
                        )
                        inventoryField(
                            "Seriennummer",
                            item.serialNumber.isEmpty ? "–" : item.serialNumber
                        )
                    }
                }
                if let warrantyEnd = item.warrantyEnd {
                    Label(
                        warrantyEnd >= Date()
                            ? "Garantie läuft noch"
                            : "Garantie abgelaufen",
                        systemImage: warrantyEnd >= Date()
                            ? "checkmark.shield" : "exclamationmark.triangle"
                    )
                    .foregroundStyle(warrantyEnd >= Date() ? .green : .orange)
                }
                if !item.note.isEmpty {
                    GroupBox("Notiz") {
                        Text(item.note).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                GroupBox("Fotos & Belege") {
                    Label(
                        "Anhangsmetadaten sind vorbereitet; die sichere Dateiauswahl folgt im Anhangsmodul.",
                        systemImage: "photo.on.rectangle"
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }

    private func inventoryField(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium)
        }
        .frame(minWidth: 180, alignment: .leading)
    }
}

private struct InventoryItemEditor: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category: InventoryCategory = .electronics
    @State private var room = ""
    @State private var hasPurchaseDate = true
    @State private var purchaseDate = Date()
    @State private var purchasePrice = ""
    @State private var currentValue = ""
    @State private var insuranceValue = ""
    @State private var retailer = ""
    @State private var serialNumber = ""
    @State private var hasWarranty = false
    @State private var warrantyEnd = Date()
    @State private var note = ""

    var body: some View {
        VStack(spacing: 0) {
            AssetEditorHeader(
                title: "Inventargegenstand anlegen",
                saveDisabled: name.isEmpty,
                save: save
            )
            Form {
                TextField("Gegenstand", text: $name)
                Picker("Kategorie", selection: $category) {
                    ForEach(InventoryCategory.allCases) { Text($0.title).tag($0) }
                }
                TextField("Raum/Ort", text: $room)
                Toggle("Kaufdatum bekannt", isOn: $hasPurchaseDate)
                if hasPurchaseDate {
                    DatePicker("Kaufdatum", selection: $purchaseDate, displayedComponents: .date)
                }
                TextField("Kaufpreis", text: $purchasePrice)
                TextField("Aktueller Wert", text: $currentValue)
                TextField("Versicherungswert", text: $insuranceValue)
                TextField("Händler", text: $retailer)
                TextField("Seriennummer", text: $serialNumber)
                Toggle("Garantieende erfassen", isOn: $hasWarranty)
                if hasWarranty {
                    DatePicker("Garantieende", selection: $warrantyEnd, displayedComponents: .date)
                }
                TextField("Notiz", text: $note, axis: .vertical)
            }
            .formStyle(.grouped)
        }
        .frame(width: 600, height: 680)
    }

    private func save() {
        do {
            let purchase = try Money(parsing: purchasePrice.isEmpty ? "0" : purchasePrice)
            let current = try Money(parsing: currentValue.isEmpty ? "0" : currentValue)
            let insurance = try Money(parsing: insuranceValue.isEmpty ? "0" : insuranceValue)
            let value = InventoryItem(
                id: UUID(), name: name, category: category, room: room,
                purchaseDate: hasPurchaseDate ? purchaseDate : nil,
                purchasePriceMinor: abs(purchase.minorUnits),
                currentValueMinor: abs(current.minorUnits),
                insuranceValueMinor: abs(insurance.minorUnits),
                retailer: retailer, serialNumber: serialNumber,
                warrantyEnd: hasWarranty ? warrantyEnd : nil,
                note: note, isActive: true
            )
            if store.saveInventoryItem(value) { dismiss() }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}

struct ModuleOverviewView: View {
    let section: WorkspaceSection

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(section.title, systemImage: section.icon)
                .font(.largeTitle.bold())
            Text(description)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 720, alignment: .leading)
            Divider()
            Label("Dieses Fachmodul wird als eigenständiger, getesteter vertikaler Slice ergänzt.", systemImage: "hammer")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var description: String {
        switch section {
        case .combinedRegister: "Kontenübergreifende Buchungen mit Heute-Grenze, Zeit- und Kategoriefiltern sowie Saldo- oder Summenverlauf."
        case .payments: "SEPA-Zahlungsaufträge, Daueraufträge und ein sicherer Banking-Simulator mit SCA-Zustandsautomat."
        case .calendar: "Erwartete und regelmäßige Vorgänge, Finanzkalender und nachvollziehbare Liquiditätsprognose."
        case .budget: "Mehrere Budgets mit Plan, Ist, Abweichung, Drill-down und optionalem Roll-over."
        case .investments: "Wertpapiere, Depots, Lots, Kurse, Kostenbasis, Performance und Asset Allocation."
        case .assets: "Kredite, Tilgungspläne, Vermögenswerte, Restschuld und Szenarien."
        case .contracts: "Verträge, Fristen, Zahlungen, Erinnerungen und erwartete Jahreskosten."
        case .inventory: "Inventargegenstände, Werte, Seriennummern, Garantien und Versicherungsübersicht."
        case .addresses: "Empfänger, Adressen, Bankverbindungen, Gläubiger-IDs und SEPA-Mandate."
        case .rules: "Deterministische Kategorisierungsregeln mit Priorität, Vorschau, Trockenlauf und Audit."
        default: "Lokales Finanzmodul."
        }
    }
}
