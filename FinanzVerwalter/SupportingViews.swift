import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

struct AttachmentManagerView: View {
    @EnvironmentObject private var store: FinanceAppStore
    let entityType: AttachmentEntityType
    let entityID: UUID
    var emptyText = "Noch keine Anhänge"
    var icon = "paperclip"

    @State private var attachments: [FinanceAttachment] = []
    @State private var showImporter = false
    @State private var pendingOpen: FinanceAttachment?
    @State private var pendingRemoval: FinanceAttachment?
    @State private var confirmOpen = false
    @State private var confirmRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if attachments.isEmpty {
                Label(emptyText, systemImage: icon)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(attachments) { attachment in
                    HStack(spacing: 10) {
                        Image(systemName: icon)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.fileName)
                                .lineLimit(1)
                            Text(
                                "\(attachment.mimeType) · \(ByteCountFormatter.string(fromByteCount: attachment.byteCount, countStyle: .file))"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Öffnen") {
                            pendingOpen = attachment
                            confirmOpen = true
                        }
                        .accessibilityLabel("Anhang \(attachment.fileName) öffnen")
                        Button("Exportieren …") {
                            exportAttachment(attachment)
                        }
                        .accessibilityLabel("Anhang \(attachment.fileName) exportieren")
                        Button(role: .destructive) {
                            pendingRemoval = attachment
                            confirmRemoval = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("Anhang entfernen")
                        .accessibilityLabel("Anhang \(attachment.fileName) entfernen")
                    }
                }
            }
            Button("Datei hinzufügen …", systemImage: "paperclip.badge.plus") {
                showImporter = true
            }
            Text(
                "Erlaubt: PDF, PNG, JPEG, TXT, CSV, QIF und XML bis 50 MB. "
                    + "Dateien können auch hierher gezogen werden; vor dem Öffnen wird SHA-256 erneut geprüft."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(
            "attachments.\(entityType.rawValue).\(entityID.uuidString)"
        )
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            return importAttachment(url)
        }
        .onAppear(perform: reload)
        .onChange(of: entityID) {
            pendingOpen = nil
            pendingRemoval = nil
            reload()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: allowedAttachmentTypes,
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                _ = importAttachment(url)
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Anhang sicher öffnen?",
            isPresented: $confirmOpen,
            titleVisibility: .visible
        ) {
            Button("Nach SHA-256-Prüfung öffnen") {
                guard let pendingOpen,
                      let url = store.attachmentPreviewURL(pendingOpen) else { return }
                NSWorkspace.shared.open(url)
                self.pendingOpen = nil
            }
            Button("Abbrechen", role: .cancel) { pendingOpen = nil }
        } message: {
            if let pendingOpen {
                Text(
                    "„\(pendingOpen.fileName)“ wird als lokale Vorschau an die für diesen Dateityp registrierte App übergeben."
                )
            }
        }
        .confirmationDialog(
            "Anhang wirklich entfernen?",
            isPresented: $confirmRemoval,
            titleVisibility: .visible
        ) {
            Button("Anhang entfernen", role: .destructive) {
                guard let pendingRemoval else { return }
                if store.removeAttachment(pendingRemoval) {
                    attachments.removeAll { $0.id == pendingRemoval.id }
                }
                self.pendingRemoval = nil
            }
            Button("Abbrechen", role: .cancel) { pendingRemoval = nil }
        } message: {
            if let pendingRemoval {
                Text("„\(pendingRemoval.fileName)“ wird aus dieser Finanzdatei entfernt.")
            }
        }
    }

    private var allowedAttachmentTypes: [UTType] {
        ["pdf", "png", "jpg", "jpeg", "txt", "csv", "qif", "xml"]
            .map {
                UTType(filenameExtension: $0)
                    ?? UTType(importedAs: "de.pixelpuxel.attachment.\($0)")
            }
    }

    private func reload() {
        attachments = store.attachments(
            entityType: entityType, entityID: entityID
        )
    }

    private func importAttachment(_ url: URL) -> Bool {
        guard store.addAttachment(
            from: url, to: entityType, entityID: entityID
        ) else { return false }
        reload()
        return true
    }

    private func exportAttachment(_ attachment: FinanceAttachment) {
        let panel = NSSavePanel()
        panel.title = "Anhang exportieren"
        panel.prompt = "Exportieren"
        panel.nameFieldStringValue = attachment.fileName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let suffix = URL(fileURLWithPath: attachment.fileName).pathExtension
        if let contentType = UTType(filenameExtension: suffix) {
            panel.allowedContentTypes = [contentType]
        }
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let replaceExisting = FileManager.default.fileExists(atPath: destination.path)
        _ = store.exportAttachment(
            attachment,
            to: destination,
            replaceExisting: replaceExisting
        )
    }
}

struct SecureNoteView: View {
    @EnvironmentObject private var store: FinanceAppStore
    let text: String
    var showsText = true

    @State private var pendingLink: SecureNoteLink?
    @State private var confirmOpen = false

    private var links: [SecureNoteLink] {
        SecureNoteLinkPolicy.links(in: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsText {
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(links) { link in
                Button {
                    pendingLink = link
                    confirmOpen = true
                } label: {
                    Label(
                        link.displayName,
                        systemImage: link.kind == .https ? "globe" : "doc"
                    )
                }
                .buttonStyle(.link)
                .accessibilityLabel(
                    link.kind == .https
                        ? "HTTPS-Link \(link.displayName) nach Bestätigung öffnen"
                        : "Lokale Datei \(link.displayName) nach Bestätigung öffnen"
                )
            }
            if !links.isEmpty {
                Text(
                    "Links öffnen nie automatisch. Erlaubt sind HTTPS-Webseiten und "
                        + "reguläre, nicht ausführbare lokale Dateien."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(
            "Notizlink sicher öffnen?",
            isPresented: $confirmOpen,
            titleVisibility: .visible
        ) {
            Button("Nach Sicherheitsprüfung öffnen") {
                openPendingLink()
            }
            Button("Abbrechen", role: .cancel) {
                pendingLink = nil
            }
        } message: {
            if let pendingLink {
                switch pendingLink.kind {
                case .https:
                    Text(
                        "Die App wird verlassen und die HTTPS-Seite „\(pendingLink.displayName)“ im Standardbrowser geöffnet."
                    )
                case .localFile:
                    Text(
                        "„\(pendingLink.url.path)“ wird unmittelbar vor dem Öffnen erneut als reguläre, nicht ausführbare Datei geprüft."
                    )
                }
            }
        }
        .onChange(of: text) {
            pendingLink = nil
            confirmOpen = false
        }
    }

    private func openPendingLink() {
        guard let pendingLink else { return }
        defer { self.pendingLink = nil }
        do {
            let validated = try SecureNoteLinkPolicy.validatedURLForOpening(
                pendingLink.url
            )
            guard NSWorkspace.shared.open(validated) else {
                throw FinanceError.database(
                    "Für diesen bestätigten Notizlink ist keine Anwendung registriert."
                )
            }
            store.statusText = pendingLink.kind == .https
                ? "Bestätigten HTTPS-Link geöffnet"
                : "Bestätigte lokale Datei geöffnet"
        } catch {
            store.errorMessage = error.localizedDescription
            store.statusText = "Notizlink blockiert"
        }
    }
}

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
    @State private var accountPendingClosure: FinanceAccount?

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
                Toggle("Ausgeblendete/geschlossene", isOn: $showHidden)
                    .toggleStyle(.checkbox)
                Button("Gruppen …", systemImage: "folder") { showGroups = true }
                Button("Öffnen", systemImage: "list.bullet.rectangle") {
                    if let account = selectedAccount { openRegister(account) }
                }
                .disabled(selectedAccount == nil)
                Button("Abrufen", systemImage: "arrow.triangle.2.circlepath") {
                    if let account = selectedAccount { openBanking(account) }
                }
                .disabled(selectedAccount?.isOnline != true || selectedAccount?.isClosed == true)
                Button("Abgleichen", systemImage: "checkmark.seal") {
                    if let account = selectedAccount { reconcile(account) }
                }
                .disabled(selectedAccount == nil || selectedAccount?.isClosed == true)
                Button("Bearbeiten", systemImage: "pencil") {
                    if let account = selectedAccount { edit(account) }
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
                TableColumn("Typ") { account in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.type.title)
                        if !account.subtype.isEmpty {
                            Text(account.subtype)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
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
                TableColumn("Letzter Abruf") { account in
                    if let date = account.lastSyncAt {
                        Text(date, format: .dateTime.day().month().year().hour().minute())
                    } else {
                        Text("–").foregroundStyle(.tertiary)
                    }
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
                        edit(account)
                    }
                    Button("Im Kontoblatt öffnen") {
                        openRegister(account)
                    }
                    Button("Umsätze und Salden abrufen") {
                        openBanking(account)
                    }
                    .disabled(!account.isOnline || account.isClosed)
                    Button("Konto abgleichen") { reconcile(account) }
                        .disabled(account.isClosed)
                    Divider()
                    Button(account.isHidden ? "Einblenden" : "Ausblenden") {
                        setHidden(account, !account.isHidden)
                    }
                    if account.isClosed {
                        Button("Konto wieder öffnen") { reopen(account) }
                    } else {
                        Button("Konto schließen …", role: .destructive) {
                            accountPendingClosure = account
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            AccountEditorView(account: editingAccount)
        }
        .sheet(isPresented: $showGroups) { AccountGroupsEditorView() }
        .alert(
            "Konto schließen?",
            isPresented: Binding(
                get: { accountPendingClosure != nil },
                set: { if !$0 { accountPendingClosure = nil } }
            ),
            presenting: accountPendingClosure
        ) { account in
            Button("Konto schließen", role: .destructive) { close(account) }
            Button("Abbrechen", role: .cancel) { accountPendingClosure = nil }
        } message: { account in
            Text(closureMessage(account))
        }
    }

    private var selectedAccount: FinanceAccount? {
        selectedAccountID.flatMap { id in store.accounts.first { $0.id == id } }
    }

    private func edit(_ account: FinanceAccount) {
        editingAccount = account
        showEditor = true
    }

    private func openRegister(_ account: FinanceAccount) {
        store.selectedAccountID = account.id
        NotificationCenter.default.post(name: .openAccountRegister, object: account.id)
    }

    private func openBanking(_ account: FinanceAccount) {
        guard account.isOnline, !account.isClosed else { return }
        store.selectedAccountID = account.id
        NotificationCenter.default.post(name: .openAccountBanking, object: account.id)
    }

    private func reconcile(_ account: FinanceAccount) {
        guard !account.isClosed else { return }
        store.selectedAccountID = account.id
        NotificationCenter.default.post(name: .reconcileAccount, object: account.id)
    }

    private func setHidden(_ account: FinanceAccount, _ hidden: Bool) {
        var updated = account
        updated.isHidden = hidden
        if store.saveAccount(updated), hidden, !showHidden {
            selectedAccountID = nil
            store.selectedAccountID = nil
        }
    }

    private func close(_ account: FinanceAccount) {
        var updated = account
        updated.isClosed = true
        updated.closingDate = Calendar.current.startOfDay(for: Date())
        if store.saveAccount(updated) {
            accountPendingClosure = nil
            if !showHidden {
                selectedAccountID = nil
                store.selectedAccountID = nil
            }
        }
    }

    private func reopen(_ account: FinanceAccount) {
        var updated = account
        updated.isClosed = false
        updated.closingDate = nil
        _ = store.saveAccount(updated)
    }

    private func closureMessage(_ account: FinanceAccount) -> String {
        let balance = Money(
            minorUnits: store.balances[account.id] ?? 0,
            currency: account.currency
        ).formatted
        let impact = AccountClosureImpact.evaluate(
            accountID: account.id,
            scheduledTransactions: store.scheduledTransactions,
            standingOrders: store.standingOrders,
            paymentOrders: store.paymentOrders
        )
        var details = ["Aktueller Saldo: \(balance)."]
        if impact.openItemCount > 0 {
            details.append(
                "Offen verknüpft: \(impact.activeScheduledTransactions) regelmäßige Vorgänge, "
                    + "\(impact.activeStandingOrders) Daueraufträge und "
                    + "\(impact.openPaymentOrders) Zahlungsaufträge."
            )
        }
        details.append(
            "Buchungen bleiben erhalten. Das Konto wird aus normalen Auswahllisten, "
                + "Prognosen und neuen Zahlungsaufträgen entfernt und kann später wieder geöffnet werden."
        )
        return details.joined(separator: "\n\n")
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
    @State private var subtype: String
    @State private var currency: String
    @State private var groupID: UUID?
    @State private var linkedAccountID: UUID?
    @State private var openingBalance: String
    @State private var hasOpeningDate: Bool
    @State private var openingDate: Date
    @State private var hasOpeningBalanceDate: Bool
    @State private var openingBalanceDate: Date
    @State private var hasClosingDate: Bool
    @State private var closingDate: Date
    @State private var creditLimit: String
    @State private var iban: String
    @State private var bic: String
    @State private var bankCode: String
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
        _subtype = State(initialValue: account?.subtype ?? "")
        _currency = State(initialValue: account?.currency ?? "EUR")
        _groupID = State(initialValue: account?.groupID)
        _linkedAccountID = State(initialValue: account?.linkedAccountID)
        _openingBalance = State(
            initialValue: Money(minorUnits: account?.openingBalanceMinor ?? 0).editingString
        )
        _hasOpeningDate = State(initialValue: account?.openingDate != nil)
        _openingDate = State(initialValue: account?.openingDate ?? Date())
        _hasOpeningBalanceDate = State(
            initialValue: account?.openingBalanceDate != nil
        )
        _openingBalanceDate = State(
            initialValue: account?.openingBalanceDate ?? account?.openingDate ?? Date()
        )
        _hasClosingDate = State(initialValue: account?.closingDate != nil)
        _closingDate = State(initialValue: account?.closingDate ?? Date())
        _creditLimit = State(
            initialValue: Money(minorUnits: account?.creditLimitMinor ?? 0).editingString
        )
        _iban = State(initialValue: account?.iban ?? "")
        _bic = State(initialValue: account?.bic ?? "")
        _bankCode = State(initialValue: account?.bankCode ?? "")
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
                    SecureNoteView(text: descriptionText, showsText: false)
                    Picker("Kontogruppe", selection: $groupID) {
                        Text("Ohne Gruppe").tag(UUID?.none)
                        ForEach(store.accountGroups.filter(\.isActive)) {
                            Text($0.name).tag(UUID?.some($0.id))
                        }
                    }
                    Picker("Kontotyp", selection: $type) {
                        ForEach(AccountType.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Kontountertyp", text: $subtype)
                    TextField("Währung", text: $currency)
                    TextField("Kontoinhaber", text: $ownerName)
                    Picker("Zugeordnetes Gegenkonto", selection: $linkedAccountID) {
                        Text("Keines").tag(UUID?.none)
                        ForEach(store.accounts.filter { $0.id != account?.id }) {
                            Text($0.name).tag(UUID?.some($0.id))
                        }
                    }
                }
                Section("Bankdaten") {
                    TextField("Institut", text: $institution)
                    TextField("IBAN", text: $iban)
                    TextField("BIC", text: $bic)
                    TextField("Bankleitzahl (BLZ)", text: $bankCode)
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
                    Toggle("Stichtag des Eröffnungssaldos", isOn: $hasOpeningBalanceDate)
                    if hasOpeningBalanceDate {
                        DatePicker(
                            "Saldo-Stichtag", selection: $openingBalanceDate,
                            displayedComponents: .date
                        )
                    }
                    Toggle("Konto ausgeblendet", isOn: $isHidden)
                    Toggle("Konto geschlossen", isOn: $isClosed)
                    if isClosed {
                        Toggle("Schließdatum festlegen", isOn: $hasClosingDate)
                        if hasClosingDate {
                            DatePicker(
                                "Schließdatum", selection: $closingDate,
                                displayedComponents: .date
                            )
                        }
                    }
                }
                Section("Einbeziehung") {
                    Toggle("Im Vermögen berücksichtigen", isOn: $includeNetWorth)
                    Toggle("Im Budget berücksichtigen", isOn: $includeBudget)
                    Toggle("In Berichten berücksichtigen", isOn: $includeReports)
                    Toggle("In der Prognose berücksichtigen", isOn: $includeForecast)
                }
                if let account {
                    Section("Dokumente") {
                        AttachmentManagerView(
                            entityType: .account,
                            entityID: account.id,
                            emptyText: "Noch keine Kontodokumente",
                            icon: "doc.text"
                        )
                    }
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
                            syncStatus: isOnline ? (account?.syncStatus ?? .ready) : .offline,
                            subtype: subtype,
                            bankCode: bankCode,
                            openingBalanceDate: hasOpeningBalanceDate
                                ? openingBalanceDate : nil,
                            closingDate: isClosed && hasClosingDate ? closingDate : nil,
                            linkedAccountID: linkedAccountID
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
        .frame(width: 680, height: 820)
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
    @State private var sourceAmount = ""
    @State private var destinationAmount = ""
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
                    ForEach(openAccounts) {
                        Text("\($0.name) · \($0.currency)")
                            .tag(UUID?.some($0.id))
                    }
                }
                Picker("Auf Konto", selection: $destinationID) {
                    Text("Bitte wählen").tag(UUID?.none)
                    ForEach(openAccounts.filter { $0.id != sourceID }) {
                        Text("\($0.name) · \($0.currency)")
                            .tag(UUID?.some($0.id))
                    }
                }
                TextField(
                    "Abgang \(sourceAccount?.currency ?? "")",
                    text: $sourceAmount,
                    prompt: Text("250,00")
                )
                if isForeignCurrency {
                    TextField(
                        "Gutschrift \(destinationAccount?.currency ?? "")",
                        text: $destinationAmount,
                        prompt: Text("275,00")
                    )
                    if let transferRatePreview {
                        LabeledContent("Wechselkurs") {
                            Text(transferRatePreview)
                                .monospacedDigit()
                        }
                    }
                } else if sourceAccount != nil, destinationAccount != nil {
                    LabeledContent("Gutschrift") {
                        Text(
                            (try? Money(
                                parsing: sourceAmount,
                                currency: sourceAccount?.currency ?? "EUR"
                            ).formatted) ?? "–"
                        )
                        .monospacedDigit()
                    }
                }
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
                        sourceAmount: sourceAmount,
                        destinationAmount: isForeignCurrency
                            ? destinationAmount : sourceAmount,
                        date: date, purpose: purpose
                    ) {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    sourceID == nil || destinationID == nil
                        || sourceID == destinationID
                        || sourceAmount.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                        || (isForeignCurrency
                            && destinationAmount.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty)
                )
            }
        }
        .padding(24)
        .frame(width: 500)
        .onAppear {
            sourceID = store.selectedAccountID.flatMap { selectedID in
                openAccounts.contains(where: { $0.id == selectedID })
                    ? selectedID : nil
            } ?? openAccounts.first?.id
            destinationID = openAccounts.first { $0.id != sourceID }?.id
        }
        .onChange(of: sourceID) {
            if destinationID == sourceID {
                destinationID = openAccounts.first { $0.id != sourceID }?.id
            }
            synchronizeAmountsIfNeeded()
        }
        .onChange(of: destinationID) {
            synchronizeAmountsIfNeeded()
        }
        .onChange(of: sourceAmount) {
            synchronizeAmountsIfNeeded()
        }
    }

    private var openAccounts: [FinanceAccount] {
        store.accounts.filter { !$0.isClosed }
    }

    private var sourceAccount: FinanceAccount? {
        sourceID.flatMap { id in openAccounts.first { $0.id == id } }
    }

    private var destinationAccount: FinanceAccount? {
        destinationID.flatMap { id in openAccounts.first { $0.id == id } }
    }

    private var isForeignCurrency: Bool {
        guard let sourceAccount, let destinationAccount else { return false }
        return sourceAccount.currency.uppercased()
            != destinationAccount.currency.uppercased()
    }

    private var transferRatePreview: String? {
        guard isForeignCurrency,
              let sourceAccount, let destinationAccount,
              let source = try? Money(
                parsing: sourceAmount,
                currency: sourceAccount.currency
              ),
              let destination = try? Money(
                parsing: destinationAmount,
                currency: destinationAccount.currency
              ),
              let rate = try? ExchangeRate.derived(
                originalMinor: source.minorUnits,
                originalCurrency: source.currency,
                bookedMinor: destination.minorUnits,
                bookedCurrency: destination.currency
              )
        else { return nil }
        return "1 \(source.currency) = \(rate.formatted) \(destination.currency)"
    }

    private func synchronizeAmountsIfNeeded() {
        guard !isForeignCurrency else { return }
        destinationAmount = sourceAmount
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

struct ExternalReportWindow: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismissWindow) private var dismissWindow
    let request: ReportWindowRequest?

    var body: some View {
        Group {
            if let request {
                if !request.belongs(to: store.currentFinanceFileURL) {
                    ContentUnavailableView(
                        "Andere Finanzdatei geöffnet",
                        systemImage: "doc.badge.exclamationmark",
                        description: Text(
                            "Dieses Auswertungsfenster gehört zu „\(request.financeFilePath)“. "
                                + "Öffne diese Finanzdatei erneut oder schließe das Fenster."
                        )
                    )
                } else if let query = try? request.decodedQuery() {
                    ReportsView(
                        launchQuery: query,
                        launchTitle: request.title,
                        onIntegrateIntoMainWindow: { query, title in
                            integrateIntoMainWindow(query: query, title: title)
                        }
                    )
                } else {
                    ContentUnavailableView(
                        "Auswertung nicht lesbar",
                        systemImage: "exclamationmark.triangle",
                        description: Text(
                            "Die gespeicherte Abfrage dieses Fensters ist beschädigt oder inkompatibel."
                        )
                    )
                }
            } else {
                ContentUnavailableView(
                    "Keine Auswertung gewählt",
                    systemImage: "chart.bar.doc.horizontal"
                )
            }
        }
        .frame(minWidth: 1040, minHeight: 680)
        .navigationTitle(request?.title ?? "Auswertung")
        .accessibilityIdentifier("externalReportWindow")
    }

    private func integrateIntoMainWindow(
        query: TransactionReportQuery,
        title: String
    ) {
        guard let request,
              request.belongs(to: store.currentFinanceFileURL) else { return }
        NotificationCenter.default.post(
            name: .openTransactionReport,
            object: TransactionReportLaunchRequest(
                title: title,
                query: query
            )
        )
        dismissWindow(value: request)
        DispatchQueue.main.async {
            MainWindowCoordinator.shared.activate()
        }
        store.statusText = "Auswertung ins Hauptfenster übernommen"
    }
}

struct SpecializedReportWindow: View {
    @EnvironmentObject private var store: FinanceAppStore
    let request: SpecializedReportWindowRequest?

    var body: some View {
        Group {
            if let request {
                if !request.belongs(to: store.currentFinanceFileURL) {
                    ContentUnavailableView(
                        "Andere Finanzdatei geöffnet",
                        systemImage: "doc.badge.exclamationmark",
                        description: Text(
                            "Dieses Auswertungsfenster gehört zu „\(request.financeFilePath)“. "
                                + "Öffne diese Finanzdatei erneut oder schließe das Fenster."
                        )
                    )
                } else {
                    specializedContent(for: request)
                }
            } else {
                ContentUnavailableView(
                    "Keine Fachauswertung gewählt",
                    systemImage: "chart.bar.doc.horizontal"
                )
            }
        }
        .frame(minWidth: 1040, minHeight: 680)
        .navigationTitle(request?.kind.title ?? "Fachauswertung")
        .accessibilityIdentifier("externalSpecializedReportWindow")
    }

    @ViewBuilder
    private func specializedContent(
        for request: SpecializedReportWindowRequest
    ) -> some View {
        switch request.kind {
        case .accountBalances:
            if let query = try? request.decodedPayload(
                as: AccountBalanceReportQuery.self
            ) {
                AccountBalanceReportView(initialQuery: query)
            } else { invalidQuery }
        case .valueAddedTax:
            if let query = try? request.decodedPayload(as: VATReportQuery.self) {
                VATReportView(initialQuery: query)
            } else { invalidQuery }
        case .loans:
            if let query = try? request.decodedPayload(as: LoanReportQuery.self) {
                LoanReportView(initialQuery: query)
            } else { invalidQuery }
        case .periodComparison:
            if let query = try? request.decodedPayload(
                as: PeriodComparisonQuery.self
            ) {
                PeriodComparisonReportView(initialQuery: query)
            } else { invalidQuery }
        case .budgetComparison:
            if let payload = try? request.decodedPayload(
                as: BudgetReportWindowPayload.self
            ) {
                BudgetComparisonReportView(
                    initialBudgetID: payload.budgetID,
                    initialQuery: payload.query
                )
            } else { invalidQuery }
        case .assetRegister:
            if let query = try? request.decodedPayload(
                as: AssetRegisterReportQuery.self
            ) {
                AssetRegisterReportView(initialQuery: query)
            } else { invalidQuery }
        case .taxAllowances:
            if let query = try? request.decodedPayload(
                as: TaxAllowanceReportQuery.self
            ) {
                TaxAllowancesView(showCloseButton: true, initialQuery: query)
            } else { invalidQuery }
        }
    }

    private var invalidQuery: some View {
        ContentUnavailableView(
            "Auswertung nicht lesbar",
            systemImage: "exclamationmark.triangle",
            description: Text(
                "Die gespeicherte Abfrage dieses Fensters ist beschädigt oder inkompatibel."
            )
        )
    }
}

@MainActor
private func openSpecializedReportWindow<Payload: Encodable>(
    kind: SpecializedReportKind,
    payload: Payload,
    store: FinanceAppStore,
    openWindow: OpenWindowAction
) {
    guard let financeFileURL = store.currentFinanceFileURL else {
        store.errorMessage = "Bitte öffne zuerst eine Finanzdatei."
        return
    }
    do {
        openWindow(
            value: try SpecializedReportWindowRequest(
                kind: kind,
                financeFileURL: financeFileURL,
                payload: payload
            )
        )
    } catch {
        store.errorMessage = error.localizedDescription
    }
}

struct ReportsView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.openWindow) private var openWindow
    let launchQuery: TransactionReportQuery?
    let onIntegrateIntoMainWindow: ((TransactionReportQuery, String) -> Void)?
    @State private var launchTitle: String?
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
    @State private var includeDetailRows = true
    @State private var includeSubtotals = true
    @State private var includeGrandTotals = true
    @State private var requireGermanTaxAssignment = false
    @State private var visualization: ReportVisualization = .table
    @State private var chartMetric: ReportChartMetric = .expense
    @State private var grouping: ReportGrouping = .category
    @State private var secondaryGrouping: ReportGrouping = .none
    @State private var sort: ReportSort = .amountDescending
    @State private var selectedReportGroupID: String?
    @State private var selectedStandardReport: TransactionReportStandardPreset?
    @State private var selectedTemplateID: UUID?
    @State private var showTemplateSave = false
    @State private var showAccountBalanceReport = false
    @State private var showVATReport = false
    @State private var showLoanReport = false
    @State private var showPeriodComparisonReport = false
    @State private var showBudgetReport = false
    @State private var showAssetRegisterReport = false
    @State private var showTaxAllowanceReport = false
    @State private var templateName = ""
    @State private var csvSeparator: ReportCSVSeparator = .semicolon
    @State private var csvEncoding: ReportCSVEncoding = .utf8
    @State private var csvDocument = ReportCSVDocument(data: Data())
    @State private var showCSVExporter = false
    @State private var pdfOrientation: ReportPDFOrientation = .landscape
    @State private var pdfDocument = ReportPDFDocument(data: Data())
    @State private var showPDFExporter = false
    @State private var htmlDocument = ReportHTMLDocument(data: Data())
    @State private var showHTMLExporter = false
    @State private var xlsxDocument = ReportXLSXDocument(data: Data())
    @State private var showXLSXExporter = false
    @State private var constrainedTransactionIDs: Set<UUID>?
    @State private var exactPayee: String?
    @State private var includeForecast = false

    init(
        launchQuery: TransactionReportQuery?,
        launchTitle: String? = nil,
        onIntegrateIntoMainWindow: ((TransactionReportQuery, String) -> Void)? = nil
    ) {
        self.launchQuery = launchQuery
        self.onIntegrateIntoMainWindow = onIntegrateIntoMainWindow
        _launchTitle = State(initialValue: launchTitle)
    }

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
            secondaryGrouping: secondaryGrouping == .none
                ? nil : secondaryGrouping,
            sort: sort,
            transactionIDs: constrainedTransactionIDs,
            exactPayee: exactPayee,
            includeForecast: includeForecast,
            includeDetailRows: includeDetailRows,
            includeSubtotals: includeSubtotals,
            includeGrandTotals: includeGrandTotals,
            requireGermanTaxAssignment: requireGermanTaxAssignment,
            visualization: visualization,
            chartMetric: chartMetric
        )
    }

    var body: some View {
        let snapshot = store.transactionReport(query)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(activeReportTitle)
                        .font(.title2.bold())
                    Text(
                        selectedStandardReport?.summary
                            ?? "Live-Auswertung mit Filtern, Gruppierung und Buchungs-Drill-down"
                    )
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let onIntegrateIntoMainWindow {
                        Button(
                            "Ins Hauptfenster",
                            systemImage: "arrow.down.left.and.arrow.up.right"
                        ) {
                            onIntegrateIntoMainWindow(query, activeReportTitle)
                        }
                        .help("Diese Auswertung im Hauptfenster weiterbearbeiten")
                        .accessibilityIdentifier(
                            "integrateExternalReportIntoMainWindow"
                        )
                    }
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

            if constrainedTransactionIDs != nil || exactPayee != nil {
                HStack {
                    Label(
                        "Direkt aus dem Kontenblatt aufgerufene Auswahl",
                        systemImage: "arrow.turn.down.right"
                    )
                    if let exactPayee {
                        Text("Empfänger: \(exactPayee)")
                            .foregroundStyle(.secondary)
                    }
                    if let count = constrainedTransactionIDs?.count {
                        Text("\(count) Buchungen")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Direktauswahl lösen") {
                        constrainedTransactionIDs = nil
                        exactPayee = nil
                        includeForecast = false
                    }
                }
                .font(.caption)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.blue.opacity(0.08))
                Divider()
            }

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Menu {
                        ForEach(TransactionReportStandardPreset.allCases) { preset in
                            Button {
                                applyStandardReport(preset)
                            } label: {
                                Label(preset.title, systemImage: preset.systemImage)
                            }
                            .help(preset.summary)
                        }
                        Divider()
                        Button {
                            showAccountBalanceReport = true
                        } label: {
                            Label("Kontosalden und Nettovermögen …", systemImage: "scalemass")
                        }
                        Button {
                            showVATReport = true
                        } label: {
                            Label("Umsatzsteuerbericht …", systemImage: "percent")
                        }
                        Button {
                            showLoanReport = true
                        } label: {
                            Label("Kredit-, Zins- und Tilgungsbericht …", systemImage: "building.columns")
                        }
                        Button {
                            showPeriodComparisonReport = true
                        } label: {
                            Label("Zeitvergleich …", systemImage: "arrow.left.arrow.right.square")
                        }
                        Button {
                            showBudgetReport = true
                        } label: {
                            Label("Budget Plan/Ist/Abweichung …", systemImage: "chart.bar.xaxis")
                        }
                        Button {
                            showAssetRegisterReport = true
                        } label: {
                            Label("Vertrags- und Inventarübersicht …", systemImage: "doc.text.magnifyingglass")
                        }
                        Button {
                            showTaxAllowanceReport = true
                        } label: {
                            Label("Freistellungsaufträge …", systemImage: "eurosign.circle")
                        }
                    } label: {
                        Label("Standardberichte", systemImage: "chart.bar.doc.horizontal")
                    }
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
                        } ?? selectedStandardReport?.title ?? ""
                        showTemplateSave = true
                    }
                    Button("Neues Fenster", systemImage: "macwindow.badge.plus") {
                        openCurrentReportWindow()
                    }
                    .disabled(store.currentFinanceFileURL == nil)
                    .help("Aktuelle Auswertung unabhängig in einem eigenen Fenster öffnen")
                    .accessibilityIdentifier("openExternalReportWindow")
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
                    Button("HTML exportieren …", systemImage: "chevron.left.forwardslash.chevron.right") {
                        prepareHTMLExport(snapshot)
                    }
                    Button("XLSX exportieren …", systemImage: "tablecells.badge.ellipsis") {
                        prepareXLSXExport(snapshot)
                    }
                    Button("Kopieren", systemImage: "doc.on.doc") {
                        copyReport(snapshot)
                    }
                    Menu {
                        Picker("Papierausrichtung", selection: $pdfOrientation) {
                            ForEach(ReportPDFOrientation.allCases) {
                                Text($0.title).tag($0)
                            }
                        }
                        Divider()
                        Button("Drucken …", systemImage: "printer.fill") {
                            printReport(snapshot)
                        }
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
                    Picker("Dann nach", selection: $secondaryGrouping) {
                        ForEach(ReportGrouping.allCases.filter { $0 != grouping }) {
                            Text($0.title).tag($0)
                        }
                    }
                    .frame(width: 175)
                    .disabled(grouping == .none)
                    Picker("Sortieren", selection: $sort) {
                        ForEach(ReportSort.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .frame(width: 185)
                    Picker("Darstellung", selection: $visualization) {
                        ForEach(ReportVisualization.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .frame(width: 125)
                    Picker("Diagrammwert", selection: $chartMetric) {
                        ForEach(ReportChartMetric.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .frame(width: 130)
                    .disabled(visualization == .table)
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

            if visualization != .table {
                reportCharts(snapshot)
                Divider()
            }

            if grouping == .none {
                if includeDetailRows {
                    reportFactsTable(snapshot.facts)
                } else {
                    ContentUnavailableView(
                        "Detailzeilen ausgeblendet",
                        systemImage: "list.bullet.rectangle",
                        description: Text(
                            "Aktiviere „Buchungsdetails“, um einzelne Buchungen anzuzeigen."
                        )
                    )
                }
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
                            if includeDetailRows {
                                reportFactsTable(snapshot.facts(inGroupID: selectedReportGroupID))
                            } else {
                                ContentUnavailableView(
                                    "Detailzeilen ausgeblendet",
                                    systemImage: "list.bullet.rectangle",
                                    description: Text(
                                        "Die Gruppensumme bleibt sichtbar; Buchungsdetails sind deaktiviert."
                                    )
                                )
                            }
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
            if includeGrandTotals {
                reportTotals(snapshot.totals)
            }
        }
        .onChange(of: grouping) {
            selectedReportGroupID = nil
            if grouping == .none || secondaryGrouping == grouping {
                secondaryGrouping = .none
            }
        }
        .onChange(of: secondaryGrouping) { selectedReportGroupID = nil }
        .onChange(of: snapshot.groups.map(\.id)) {
            if let selectedReportGroupID,
               !snapshot.groups.contains(where: { $0.id == selectedReportGroupID }) {
                self.selectedReportGroupID = nil
            }
        }
        .onAppear {
            if let launchQuery { apply(launchQuery) }
        }
        .onChange(of: launchQuery) {
            if let launchQuery { apply(launchQuery) }
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
        .sheet(isPresented: $showAccountBalanceReport) {
            AccountBalanceReportView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showVATReport) {
            VATReportView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showLoanReport) {
            LoanReportView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showPeriodComparisonReport) {
            PeriodComparisonReportView(baseQuery: query)
                .environmentObject(store)
        }
        .sheet(isPresented: $showBudgetReport) {
            BudgetComparisonReportView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showAssetRegisterReport) {
            AssetRegisterReportView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showTaxAllowanceReport) {
            TaxAllowancesView(showCloseButton: true)
                .environmentObject(store)
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
        .fileExporter(
            isPresented: $showHTMLExporter,
            document: htmlDocument,
            contentType: .html,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                store.statusText = "Bericht als HTML exportiert"
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showXLSXExporter,
            document: xlsxDocument,
            contentType: .finanzVerwalterXLSX,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                store.statusText = "Bericht als XLSX exportiert"
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
            ForEach(store.tagsByPath.filter(\.isActive)) { tag in
                Toggle(
                    store.tagPath(tag.id),
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
            Toggle(
                "Nur deutsche Steuerzuordnungen",
                isOn: $requireGermanTaxAssignment
            )
            Divider()
            Toggle("Buchungsdetails", isOn: $includeDetailRows)
            Toggle("Zwischensummen", isOn: $includeSubtotals)
                .disabled(grouping == .none || secondaryGrouping == .none)
            Toggle("Gesamtsummen", isOn: $includeGrandTotals)
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
            TableColumn(reportGroupingTitle) { group in
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.label)
                        .font(group.level == .subtotal ? .headline : .body)
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

    @ViewBuilder
    private func reportCharts(_ snapshot: TransactionReportSnapshot) -> some View {
        let isTimeSeries = visualization == .line || visualization == .area
        let series = ReportChartEngine.series(
            snapshot: snapshot,
            metric: chartMetric,
            order: isTimeSeries ? .labelAscending : .amountDescending,
            maximumSegments: isTimeSeries ? nil : 12
        )
        if series.isEmpty {
            ContentUnavailableView(
                "Keine Diagrammwerte",
                systemImage: chartSystemImage,
                description: Text(
                    "Die gewählten Filter enthalten keine \(chartMetric.title.lowercased())."
                )
            )
            .frame(minHeight: 190)
        } else {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(series) { currencySeries in
                        GroupBox {
                            if visualization == .bar {
                                Chart(currencySeries.values) { datum in
                                    BarMark(
                                        x: .value(chartMetric.title, chartAmount(datum)),
                                        y: .value("Gruppe", datum.label)
                                    )
                                    .foregroundStyle(
                                        datum.isRemainder
                                            ? Color.secondary.gradient
                                            : Color.accentColor.gradient
                                    )
                                    .accessibilityLabel(datum.label)
                                    .accessibilityValue(
                                        Money(
                                            minorUnits: datum.amountMinor,
                                            currency: datum.currency
                                        ).formatted
                                    )
                                }
                                .chartXAxisLabel(chartMetric.title)
                                .frame(
                                    width: 620,
                                    height: max(190, CGFloat(currencySeries.values.count * 31))
                                )
                            } else if visualization == .pie {
                                Chart(currencySeries.values) { datum in
                                    SectorMark(
                                        angle: .value(chartMetric.title, chartAmount(datum)),
                                        innerRadius: .ratio(0.46),
                                        angularInset: 1
                                    )
                                    .foregroundStyle(by: .value("Gruppe", datum.label))
                                    .accessibilityLabel(datum.label)
                                    .accessibilityValue(
                                        Money(
                                            minorUnits: datum.amountMinor,
                                            currency: datum.currency
                                        ).formatted
                                    )
                                }
                                .chartLegend(position: .trailing, alignment: .center)
                                .frame(width: 620, height: 270)
                            } else if visualization == .line {
                                Chart(currencySeries.values) { datum in
                                    LineMark(
                                        x: .value("Zeitraum", datum.label),
                                        y: .value(chartMetric.title, chartAmount(datum))
                                    )
                                    .interpolationMethod(.linear)
                                    .foregroundStyle(Color.accentColor)
                                    PointMark(
                                        x: .value("Zeitraum", datum.label),
                                        y: .value(chartMetric.title, chartAmount(datum))
                                    )
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityLabel(datum.label)
                                    .accessibilityValue(
                                        Money(
                                            minorUnits: datum.amountMinor,
                                            currency: datum.currency
                                        ).formatted
                                    )
                                }
                                .chartYAxisLabel(chartMetric.title)
                                .frame(
                                    width: max(
                                        620,
                                        CGFloat(currencySeries.values.count * 72)
                                    ),
                                    height: 270
                                )
                            } else {
                                Chart(currencySeries.values) { datum in
                                    AreaMark(
                                        x: .value("Zeitraum", datum.label),
                                        y: .value(chartMetric.title, chartAmount(datum))
                                    )
                                    .interpolationMethod(.linear)
                                    .foregroundStyle(Color.accentColor.opacity(0.28))
                                    LineMark(
                                        x: .value("Zeitraum", datum.label),
                                        y: .value(chartMetric.title, chartAmount(datum))
                                    )
                                    .interpolationMethod(.linear)
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityLabel(datum.label)
                                    .accessibilityValue(
                                        Money(
                                            minorUnits: datum.amountMinor,
                                            currency: datum.currency
                                        ).formatted
                                    )
                                }
                                .chartYAxisLabel(chartMetric.title)
                                .frame(
                                    width: max(
                                        620,
                                        CGFloat(currencySeries.values.count * 72)
                                    ),
                                    height: 270
                                )
                            }
                        } label: {
                            HStack {
                                Text("\(chartMetric.title) · \(currencySeries.currency)")
                                    .font(.headline)
                                Spacer()
                                Text(
                                    Money(
                                        minorUnits: currencySeries.totalMinor,
                                        currency: currencySeries.currency
                                    ).formatted
                                )
                                .monospacedDigit()
                            }
                        }
                        .frame(width: 650)
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 380)
            .accessibilityLabel(
                "Diagramm \(chartMetric.title), nach Währung getrennt"
            )
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
            TableColumn("Kategorie") { fact in
                VStack(alignment: .leading, spacing: 1) {
                    Text(fact.categoryPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !fact.germanTaxLine.isEmpty {
                        Text(fact.germanTaxLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .help(
                    [fact.categoryPath, fact.germanTaxLine]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                )
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

    private func chartAmount(_ datum: ReportChartDatum) -> Decimal {
        Decimal(datum.amountMinor)
            / Decimal(Money.minorUnitFactor(for: datum.currency))
    }

    private var chartSystemImage: String {
        switch visualization {
        case .table, .bar: "chart.bar"
        case .line: "chart.xyaxis.line"
        case .area: "chart.line.uptrend.xyaxis"
        case .pie: "chart.pie"
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
            || !includeDetailRows
            || !includeSubtotals
            || !includeGrandTotals
            || requireGermanTaxAssignment
            || visualization != .table
            || chartMetric != .expense
            || grouping != .category
            || secondaryGrouping != .none
            || sort != .amountDescending
            || constrainedTransactionIDs != nil
            || exactPayee != nil
            || includeForecast
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
        includeDetailRows = true
        includeSubtotals = true
        includeGrandTotals = true
        requireGermanTaxAssignment = false
        visualization = .table
        chartMetric = .expense
        grouping = .category
        secondaryGrouping = .none
        sort = .amountDescending
        constrainedTransactionIDs = nil
        exactPayee = nil
        includeForecast = false
        selectedReportGroupID = nil
        selectedStandardReport = nil
        selectedTemplateID = nil
        launchTitle = nil
    }

    private func saveCurrentTemplate() {
        let id = selectedTemplateID ?? UUID()
        let template = SavedReportTemplate(
            id: id,
            name: templateName,
            definitionVersion: 4,
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
        launchTitle = nil
    }

    private func applyStandardReport(_ preset: TransactionReportStandardPreset) {
        apply(preset.query())
        selectedStandardReport = preset
        selectedTemplateID = nil
        launchTitle = nil
    }

    private func deleteSelectedTemplate() {
        guard let selectedTemplateID,
              let template = store.reportTemplates.first(where: { $0.id == selectedTemplateID })
        else { return }
        store.deleteReportTemplate(template)
        self.selectedTemplateID = nil
    }

    private func apply(_ savedQuery: TransactionReportQuery) {
        selectedStandardReport = nil
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
        secondaryGrouping = savedQuery.secondaryGrouping ?? .none
        if secondaryGrouping == grouping { secondaryGrouping = .none }
        sort = savedQuery.sort
        constrainedTransactionIDs = savedQuery.transactionIDs
        exactPayee = savedQuery.exactPayee
        includeForecast = savedQuery.includeForecast == true
        includeDetailRows = savedQuery.showsDetailRows
        includeSubtotals = savedQuery.showsSubtotals
        includeGrandTotals = savedQuery.showsGrandTotals
        requireGermanTaxAssignment = savedQuery.requireGermanTaxAssignment == true
        visualization = savedQuery.selectedVisualization
        chartMetric = savedQuery.selectedChartMetric
        selectedReportGroupID = nil
    }

    private func prepareCSVExport(_ snapshot: TransactionReportSnapshot) {
        do {
            let options = ReportCSVOptions(
                separator: csvSeparator,
                encoding: csvEncoding
            )
            let metadata = ReportExportMetadata(
                title: activeReportTitle,
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
            pdfDocument = ReportPDFDocument(data: try reportPDFData(snapshot))
            showPDFExporter = true
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func prepareHTMLExport(_ snapshot: TransactionReportSnapshot) {
        htmlDocument = ReportHTMLDocument(
            data: TransactionReportHTMLExporter.data(
                snapshot: snapshot,
                metadata: reportExportMetadata
            )
        )
        showHTMLExporter = true
    }

    private func prepareXLSXExport(_ snapshot: TransactionReportSnapshot) {
        xlsxDocument = ReportXLSXDocument(
            data: TransactionReportXLSXExporter.data(
                snapshot: snapshot,
                metadata: reportExportMetadata
            )
        )
        showXLSXExporter = true
    }

    private func copyReport(_ snapshot: TransactionReportSnapshot) {
        do {
            let payload = try TransactionReportClipboardExporter.payload(
                snapshot: snapshot,
                metadata: reportExportMetadata
            )
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(payload.plainText, forType: .string)
            pasteboard.setData(payload.html, forType: .html)
            store.statusText = "Bericht als Tabelle und HTML kopiert"
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func printReport(_ snapshot: TransactionReportSnapshot) {
        do {
            try RegisterPrintService.printPDF(try reportPDFData(snapshot))
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func reportPDFData(_ snapshot: TransactionReportSnapshot) throws -> Data {
        try TransactionReportPDFExporter.data(
            snapshot: snapshot,
            metadata: reportExportMetadata,
            options: ReportPDFOptions(orientation: pdfOrientation)
        )
    }

    private var reportExportMetadata: ReportExportMetadata {
        ReportExportMetadata(
            title: activeReportTitle,
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
            requireGermanTaxAssignment
                ? "nur deutsche Steuerzuordnungen"
                : "alle Steuerzuordnungen",
            expandSplits ? "Splitzeilen" : "Gesamtbuchungen",
            "Gruppierung \(reportGroupingTitle)",
            "Darstellung \(visualization.title)",
            visualization == .table ? nil : "Diagrammwert \(chartMetric.title)",
            includeDetailRows ? "mit Buchungsdetails" : "ohne Buchungsdetails",
            includeSubtotals ? "mit Zwischensummen" : "ohne Zwischensummen",
            includeGrandTotals ? "mit Gesamtsummen" : "ohne Gesamtsummen"
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private var reportGroupingTitle: String {
        guard secondaryGrouping != .none, secondaryGrouping != grouping else {
            return grouping.title
        }
        return "\(grouping.title) nach \(secondaryGrouping.title)"
    }

    private var activeReportTitle: String {
        launchTitle ?? selectedTemplateID.flatMap { id in
            store.reportTemplates.first { $0.id == id }?.name
        } ?? selectedStandardReport?.title ?? "\(reportGroupingTitle)-Bericht"
    }

    private func openCurrentReportWindow() {
        guard let financeFileURL = store.currentFinanceFileURL else {
            store.errorMessage = "Bitte öffne zuerst eine Finanzdatei."
            return
        }
        do {
            openWindow(
                value: try ReportWindowRequest(
                    title: activeReportTitle,
                    financeFileURL: financeFileURL,
                    query: query
                )
            )
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private var exportFilename: String {
        let raw = activeReportTitle
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

private struct PeriodComparisonReportView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    let baseQuery: TransactionReportQuery
    @State private var currentFrom: Date
    @State private var currentThrough: Date
    @State private var referenceFrom: Date
    @State private var referenceThrough: Date
    @State private var grouping: ReportGrouping = .category
    @State private var metric: PeriodComparisonMetric = .expense
    @State private var referenceMode: PeriodComparisonReferenceMode = .total
    @State private var selectedRowID: String?
    @State private var showCurrentFacts = true
    @State private var orientation: ReportPDFOrientation = .landscape
    @State private var csvDocument = ReportCSVDocument(data: Data())
    @State private var pdfDocument = ReportPDFDocument(data: Data())
    @State private var showCSVExporter = false
    @State private var showPDFExporter = false

    init(baseQuery: TransactionReportQuery) {
        self.baseQuery = baseQuery
        let calendar = Calendar.current
        let month = calendar.dateInterval(of: .month, for: .now)
        let start = baseQuery.dateFrom ?? month?.start ?? .now
        let end = baseQuery.dateThrough
            ?? month?.end.addingTimeInterval(-0.001)
            ?? .now
        let referenceEnd = start.addingTimeInterval(-0.001)
        let duration = max(0, end.timeIntervalSince(start))
        _currentFrom = State(initialValue: start)
        _currentThrough = State(initialValue: end)
        _referenceThrough = State(initialValue: referenceEnd)
        _referenceFrom = State(initialValue: referenceEnd.addingTimeInterval(-duration))
    }

    init(initialQuery: PeriodComparisonQuery) {
        self.baseQuery = initialQuery.baseQuery
        _currentFrom = State(initialValue: initialQuery.currentFrom)
        _currentThrough = State(initialValue: initialQuery.currentThrough)
        _referenceFrom = State(initialValue: initialQuery.referenceFrom)
        _referenceThrough = State(initialValue: initialQuery.referenceThrough)
        _grouping = State(initialValue: initialQuery.grouping)
        _metric = State(initialValue: initialQuery.metric)
        _referenceMode = State(initialValue: initialQuery.referenceMode)
    }

    private var snapshot: PeriodComparisonSnapshot {
        store.periodComparisonReport(
            PeriodComparisonQuery(
                currentFrom: currentFrom, currentThrough: currentThrough,
                referenceFrom: referenceFrom, referenceThrough: referenceThrough,
                grouping: grouping, metric: metric, referenceMode: referenceMode,
                baseQuery: baseQuery
            )
        )
    }

    private var selectedRow: PeriodComparisonRow? {
        selectedRowID.flatMap { id in snapshot.rows.first { $0.id == id } }
    }

    private var drilldownFacts: [TransactionReportFact] {
        guard let selectedRow else { return [] }
        let ids = showCurrentFacts
            ? selectedRow.currentFactIDs : selectedRow.referenceFactIDs
        let source = showCurrentFacts ? snapshot.currentFacts : snapshot.referenceFacts
        return source.filter { ids.contains($0.id) }
    }

    var body: some View {
        let value = snapshot
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Zeitvergleich").font(.title2.bold())
                    Text("Betrag und Prozent aus derselben gefilterten Buchungsmomentaufnahme")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Neues Fenster", systemImage: "macwindow.badge.plus") {
                    openSpecializedReportWindow(
                        kind: .periodComparison,
                        payload: PeriodComparisonQuery(
                            currentFrom: currentFrom,
                            currentThrough: currentThrough,
                            referenceFrom: referenceFrom,
                            referenceThrough: referenceThrough,
                            grouping: grouping,
                            metric: metric,
                            referenceMode: referenceMode,
                            baseQuery: baseQuery
                        ),
                        store: store,
                        openWindow: openWindow
                    )
                }
                .accessibilityIdentifier("openPeriodComparisonReportWindow")
                Button("Schließen") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Text("Aktuell").fontWeight(.semibold)
                    DatePicker("Von", selection: $currentFrom, displayedComponents: .date)
                    DatePicker("Bis", selection: $currentThrough, displayedComponents: .date)
                    Divider().frame(height: 20)
                    Text("Vergleich").fontWeight(.semibold)
                    DatePicker("Von", selection: $referenceFrom, displayedComponents: .date)
                    DatePicker("Bis", selection: $referenceThrough, displayedComponents: .date)
                }
                HStack(spacing: 10) {
                    Picker("Kennzahl", selection: $metric) {
                        ForEach(PeriodComparisonMetric.allCases) { Text($0.title).tag($0) }
                    }
                    .frame(width: 170)
                    Picker("Zeilen", selection: $grouping) {
                        ForEach(ReportGrouping.allCases) { Text($0.title).tag($0) }
                    }
                    .frame(width: 180)
                    Picker("Vergleichswert", selection: $referenceMode) {
                        ForEach(PeriodComparisonReferenceMode.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .frame(width: 210)
                    Spacer()
                    Button("CSV exportieren …", systemImage: "tablecells") {
                        csvDocument = ReportCSVDocument(data:
                            ComparisonReportCSVExporter.periodData(
                                snapshot: value, metadata: metadata
                            )
                        )
                        showCSVExporter = true
                    }
                    outputMenu(value)
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            Divider()
            VSplitView {
                VStack(spacing: 0) {
                    Table(value.rows, selection: $selectedRowID) {
                        TableColumn(grouping.title) { Text($0.label).lineLimit(1) }
                            .width(min: 190, ideal: 280)
                        TableColumn("Aktuell") { row in amount(row.currentMinor, row.currency) }
                            .width(135)
                        TableColumn(referenceMode == .monthlyAverage ? "Ø Vergleich" : "Vergleich") {
                            row in amount(row.referenceMinor, row.currency)
                        }
                        .width(135)
                        TableColumn("Abweichung") {
                            row in amount(row.differenceMinor, row.currency)
                        }.width(135)
                        TableColumn("Abweichung %") { row in
                            Text(percent(row.percentBasisPoints))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .monospacedDigit()
                        }.width(105)
                        TableColumn("Währung") { Text($0.currency) }.width(70)
                    }
                    .overlay {
                        if value.rows.isEmpty {
                            ContentUnavailableView(
                                "Keine Vergleichswerte",
                                systemImage: "arrow.left.arrow.right.square",
                                description: Text(
                                    "Die gewählten Zeiträume und Filter enthalten keine Buchungen."
                                )
                            )
                        }
                    }
                    Divider()
                    ScrollView(.horizontal) {
                        HStack(spacing: 18) {
                            Text("Gesamtsummen").fontWeight(.semibold)
                            ForEach(value.totals) { total in
                                Text(
                                    "\(total.currency): aktuell "
                                        + Money(minorUnits: total.currentMinor,
                                                currency: total.currency).formatted
                                        + " · Vergleich "
                                        + Money(minorUnits: total.referenceMinor,
                                                currency: total.currency).formatted
                                        + " · Δ "
                                        + Money(minorUnits: total.differenceMinor,
                                                currency: total.currency).formatted
                                ).monospacedDigit()
                            }
                        }.font(.caption).padding(.horizontal, 12).padding(.vertical, 7)
                    }
                }
                VStack(spacing: 0) {
                    HStack {
                        Text(selectedRow?.label ?? "Drill-down")
                            .font(.headline).lineLimit(1)
                        Spacer()
                        Picker("Zeitraum", selection: $showCurrentFacts) {
                            Text("Aktuell").tag(true)
                            Text("Vergleich").tag(false)
                        }
                        .pickerStyle(.segmented).frame(width: 190)
                        Text("\(drilldownFacts.count) Positionen")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(8)
                    Divider()
                    Table(drilldownFacts) {
                        TableColumn("Datum") {
                            Text($0.bookingDate, format: .dateTime.day().month().year())
                        }.width(95)
                        TableColumn("Empfänger") { Text($0.payee).lineLimit(1) }
                        TableColumn("Kategorie") { Text($0.categoryPath).lineLimit(1) }
                        TableColumn("Betrag") { fact in amount(fact.amountMinor, fact.currency) }
                            .width(130)
                    }
                }
            }
        }
        .frame(minWidth: 1_120, minHeight: 720)
        .fileExporter(
            isPresented: $showCSVExporter, document: csvDocument,
            contentType: .commaSeparatedText, defaultFilename: filename
        ) { if case .failure(let error) = $0 { store.errorMessage = error.localizedDescription } }
        .fileExporter(
            isPresented: $showPDFExporter, document: pdfDocument,
            contentType: .pdf, defaultFilename: filename
        ) { if case .failure(let error) = $0 { store.errorMessage = error.localizedDescription } }
        .onChange(of: value.rows.map(\.id)) {
            if selectedRowID.map({ id in value.rows.contains { $0.id == id } }) != true {
                selectedRowID = value.rows.first?.id
            }
        }
        .onAppear { selectedRowID = value.rows.first?.id }
    }

    private func outputMenu(_ snapshot: PeriodComparisonSnapshot) -> some View {
        Menu {
            Picker("Papierausrichtung", selection: $orientation) {
                ForEach(ReportPDFOrientation.allCases) { Text($0.title).tag($0) }
            }
            Divider()
            Button("Drucken …", systemImage: "printer.fill") {
                do {
                    try RegisterPrintService.printPDF(
                        try ComparisonReportPDFExporter.periodData(
                            snapshot: snapshot, metadata: metadata, orientation: orientation
                        )
                    )
                } catch { store.errorMessage = error.localizedDescription }
            }
            Button("PDF exportieren …", systemImage: "doc.richtext") {
                do {
                    pdfDocument = ReportPDFDocument(data:
                        try ComparisonReportPDFExporter.periodData(
                            snapshot: snapshot, metadata: metadata, orientation: orientation
                        )
                    )
                    showPDFExporter = true
                } catch { store.errorMessage = error.localizedDescription }
            }
        } label: {
            Label("PDF · \(orientation.title)", systemImage: "printer")
        }
    }

    private var metadata: ComparisonReportExportMetadata {
        ComparisonReportExportMetadata(
            title: "Zeitvergleich \(metric.title)",
            currentLabel: intervalLabel(currentFrom, currentThrough),
            referenceLabel: (referenceMode == .monthlyAverage ? "Ø " : "")
                + intervalLabel(referenceFrom, referenceThrough),
            generatedAt: .now
        )
    }

    private var filename: String { "FinanzVerwalter-Zeitvergleich-\(metric.rawValue)" }

    private func intervalLabel(_ from: Date, _ through: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .medium
        return "\(formatter.string(from: min(from, through)))–\(formatter.string(from: max(from, through)))"
    }

    private func amount(_ minor: Int64, _ currency: String) -> some View {
        Text(Money(minorUnits: minor, currency: currency).formatted)
            .frame(maxWidth: .infinity, alignment: .trailing).monospacedDigit()
    }

    private func percent(_ basisPoints: Int64?) -> String {
        guard let basisPoints else { return "—" }
        let sign = basisPoints < 0 ? "−" : ""
        let magnitude = basisPoints.magnitude
        return "\(sign)\(magnitude / 100),\(String(format: "%02llu", magnitude % 100)) %"
    }
}

private struct BudgetComparisonReportView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var selectedBudgetID: UUID?
    @State private var selectedMonthKey = ""
    @State private var includeZeroRows = false
    @State private var selectedCategoryID: UUID?
    @State private var orientation: ReportPDFOrientation = .landscape
    @State private var csvDocument = ReportCSVDocument(data: Data())
    @State private var pdfDocument = ReportPDFDocument(data: Data())
    @State private var showCSVExporter = false
    @State private var showPDFExporter = false

    init(
        initialBudgetID: UUID? = nil,
        initialQuery: BudgetReportQuery = BudgetReportQuery()
    ) {
        _selectedBudgetID = State(initialValue: initialBudgetID)
        _selectedMonthKey = State(
            initialValue: initialQuery.monthKeys.sorted().first ?? ""
        )
        _includeZeroRows = State(initialValue: initialQuery.includeZeroRows)
    }

    private var budget: FinanceBudget? {
        selectedBudgetID.flatMap { id in store.budgets.first { $0.id == id } }
    }

    private var query: BudgetReportQuery {
        BudgetReportQuery(
            monthKeys: selectedMonthKey.isEmpty ? [] : [selectedMonthKey],
            includeZeroRows: includeZeroRows
        )
    }

    private var snapshot: BudgetReportSnapshot? {
        guard let selectedBudgetID else { return nil }
        return store.budgetReport(
            budgetID: selectedBudgetID,
            query: query
        )
    }

    private var selectedRow: BudgetReportRow? {
        selectedCategoryID.flatMap { id in snapshot?.rows.first { $0.categoryID == id } }
    }

    private var drilldownFacts: [TransactionReportFact] {
        guard let selectedRow, let snapshot else { return [] }
        return snapshot.facts.filter { selectedRow.factIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Budget Plan/Ist/Abweichung").font(.title2.bold())
                    Text("Geschäftsjahr, Monatsauswahl und Buchungs-Drill-down")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Neues Fenster", systemImage: "macwindow.badge.plus") {
                    openSpecializedReportWindow(
                        kind: .budgetComparison,
                        payload: BudgetReportWindowPayload(
                            budgetID: selectedBudgetID,
                            query: query
                        ),
                        store: store,
                        openWindow: openWindow
                    )
                }
                .accessibilityIdentifier("openBudgetReportWindow")
                Button("Schließen") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            HStack(spacing: 10) {
                Picker("Budget", selection: $selectedBudgetID) {
                    Text("Budget wählen").tag(UUID?.none)
                    ForEach(store.budgets) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                .frame(width: 260)
                if let budget {
                    Picker("Zeitraum", selection: $selectedMonthKey) {
                        Text("Gesamtes Geschäftsjahr").tag("")
                        ForEach(budget.months(), id: \.self) { month in
                            Text(month, format: .dateTime.month(.wide).year())
                                .tag(BudgetReportEngine.monthKey(month))
                        }
                    }
                    .frame(width: 230)
                }
                Toggle("Nullzeilen", isOn: $includeZeroRows).toggleStyle(.checkbox)
                Spacer()
                if let snapshot {
                    Button("CSV exportieren …", systemImage: "tablecells") {
                        csvDocument = ReportCSVDocument(data:
                            ComparisonReportCSVExporter.budgetData(
                                snapshot: snapshot, metadata: metadata(snapshot)
                            )
                        )
                        showCSVExporter = true
                    }
                    budgetOutputMenu(snapshot)
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            Divider()
            if let snapshot {
                HStack(spacing: 12) {
                    comparisonMetric("Einnahmen Plan", snapshot.plannedIncomeMinor,
                                     snapshot.budget.currency)
                    comparisonMetric("Einnahmen Ist", snapshot.actualIncomeMinor,
                                     snapshot.budget.currency)
                    comparisonMetric("Ausgaben verfügbar", snapshot.effectiveExpenseMinor,
                                     snapshot.budget.currency)
                    comparisonMetric("Ausgaben Ist", snapshot.actualExpenseMinor,
                                     snapshot.budget.currency,
                                     warning: snapshot.actualExpenseMinor > snapshot.effectiveExpenseMinor)
                    comparisonMetric("Roll-over-Reserve", snapshot.rolloverReserveMinor,
                                     snapshot.budget.currency,
                                     warning: snapshot.rolloverReserveMinor < 0)
                }
                .padding(10)
                Divider()
                VSplitView {
                    Table(snapshot.rows, selection: $selectedCategoryID) {
                        TableColumn("Kategorie") { Text($0.categoryPath).lineLimit(1) }
                            .width(min: 220, ideal: 320)
                        TableColumn("Art") {
                            Text($0.kind == .income ? "Einnahme" : "Ausgabe")
                        }.width(90)
                        TableColumn("Plan") { row in amount(row.plannedMinor, row.currency) }
                            .width(105)
                        TableColumn("Übertrag") { row in
                            amount(row.rolloverMinor, row.currency)
                        }.width(105)
                        TableColumn("Verfügbar") { row in
                            amount(row.effectivePlannedMinor, row.currency)
                        }.width(105)
                        TableColumn("Ist") { row in amount(row.actualMinor, row.currency) }
                            .width(105)
                        TableColumn("Abweichung") { row in
                            amount(row.varianceMinor, row.currency)
                                .foregroundStyle(row.varianceMinor > 0 && row.kind == .expense
                                    ? Color.red : Color.primary)
                        }.width(105)
                        TableColumn("Zielerreichung") { row in
                            Text(percent(row.completionBasisPoints))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .monospacedDigit()
                        }.width(110)
                    }
                    VStack(spacing: 0) {
                        HStack {
                            Text(selectedRow?.categoryPath ?? "Drill-down").font(.headline)
                            Spacer()
                            Text("\(drilldownFacts.count) Positionen")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(8)
                        Divider()
                        Table(drilldownFacts) {
                            TableColumn("Datum") {
                                Text($0.bookingDate, format: .dateTime.day().month().year())
                            }.width(95)
                            TableColumn("Empfänger") { Text($0.payee).lineLimit(1) }
                            TableColumn("Zweck") { Text($0.purpose).lineLimit(1) }
                            TableColumn("Betrag") { fact in amount(fact.amountMinor, fact.currency) }
                                .width(130)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    store.budgets.isEmpty ? "Noch kein Budget" : "Budget wählen",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Budgetwerte werden unverändert aus der lokalen Finanzdatei gelesen.")
                )
            }
        }
        .frame(minWidth: 1_280, minHeight: 720)
        .fileExporter(
            isPresented: $showCSVExporter, document: csvDocument,
            contentType: .commaSeparatedText, defaultFilename: filename
        ) { if case .failure(let error) = $0 { store.errorMessage = error.localizedDescription } }
        .fileExporter(
            isPresented: $showPDFExporter, document: pdfDocument,
            contentType: .pdf, defaultFilename: filename
        ) { if case .failure(let error) = $0 { store.errorMessage = error.localizedDescription } }
        .onAppear { selectedBudgetID = selectedBudgetID ?? store.budgets.first?.id }
        .onChange(of: selectedBudgetID) {
            selectedMonthKey = ""
            selectedCategoryID = snapshot?.rows.first?.categoryID
        }
        .onChange(of: snapshot?.rows.map(\.id) ?? []) {
            if selectedCategoryID.map({ id in snapshot?.rows.contains { $0.id == id } }) != true {
                selectedCategoryID = snapshot?.rows.first?.categoryID
            }
        }
    }

    private func budgetOutputMenu(_ snapshot: BudgetReportSnapshot) -> some View {
        Menu {
            Picker("Papierausrichtung", selection: $orientation) {
                ForEach(ReportPDFOrientation.allCases) { Text($0.title).tag($0) }
            }
            Divider()
            Button("Drucken …", systemImage: "printer.fill") {
                do {
                    try RegisterPrintService.printPDF(
                        try ComparisonReportPDFExporter.budgetData(
                            snapshot: snapshot, metadata: metadata(snapshot),
                            orientation: orientation
                        )
                    )
                } catch { store.errorMessage = error.localizedDescription }
            }
            Button("PDF exportieren …", systemImage: "doc.richtext") {
                do {
                    pdfDocument = ReportPDFDocument(data:
                        try ComparisonReportPDFExporter.budgetData(
                            snapshot: snapshot, metadata: metadata(snapshot),
                            orientation: orientation
                        )
                    )
                    showPDFExporter = true
                } catch { store.errorMessage = error.localizedDescription }
            }
        } label: { Label("PDF · \(orientation.title)", systemImage: "printer") }
    }

    private func metadata(_ snapshot: BudgetReportSnapshot) -> ComparisonReportExportMetadata {
        ComparisonReportExportMetadata(
            title: "Budget Plan/Ist/Abweichung – \(snapshot.budget.name)",
            currentLabel: selectedMonthKey.isEmpty ? "Gesamtes Geschäftsjahr" : periodLabel(snapshot),
            referenceLabel: "Plan gegenüber Ist", generatedAt: .now
        )
    }

    private func periodLabel(_ snapshot: BudgetReportSnapshot) -> String {
        guard let month = snapshot.includedMonths.first else { return "Kein Zeitraum" }
        return month.formatted(.dateTime.month(.wide).year())
    }

    private var filename: String { "FinanzVerwalter-Budget-Plan-Ist" }

    private func comparisonMetric(
        _ title: String, _ minor: Int64, _ currency: String, warning: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money(minorUnits: minor, currency: currency).formatted)
                .font(.headline).monospacedDigit()
                .foregroundStyle(warning ? .red : .primary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private func amount(_ minor: Int64, _ currency: String) -> some View {
        Text(Money(minorUnits: minor, currency: currency).formatted)
            .frame(maxWidth: .infinity, alignment: .trailing).monospacedDigit()
    }

    private func percent(_ basisPoints: Int64?) -> String {
        guard let basisPoints else { return "—" }
        let magnitude = basisPoints.magnitude
        let sign = basisPoints < 0 ? "−" : ""
        return "\(sign)\(magnitude / 100),\(String(format: "%02llu", magnitude % 100)) %"
    }
}

private struct LoanReportView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var limitPeriod = false
    @State private var dateFrom: Date
    @State private var dateThrough: Date
    @State private var loanIDs = Set<UUID>()
    @State private var currencies = Set<String>()
    @State private var includeInactive = false
    @State private var selectedLoanID: UUID?
    @State private var orientation: ReportPDFOrientation = .landscape
    @State private var csvDocument = ReportCSVDocument(data: Data())
    @State private var pdfDocument = ReportPDFDocument(data: Data())
    @State private var showCSVExporter = false
    @State private var showPDFExporter = false

    init(
        initialQuery: LoanReportQuery? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        if let initialQuery {
            let interval = calendar.dateInterval(of: .year, for: now)
            _limitPeriod = State(
                initialValue: initialQuery.dateFrom != nil
                    || initialQuery.dateThrough != nil
            )
            _dateFrom = State(
                initialValue: initialQuery.dateFrom ?? interval?.start ?? now
            )
            _dateThrough = State(
                initialValue: initialQuery.dateThrough
                    ?? interval?.end.addingTimeInterval(-0.001)
                    ?? now
            )
            _loanIDs = State(initialValue: initialQuery.loanIDs)
            _currencies = State(initialValue: initialQuery.currencies)
            _includeInactive = State(
                initialValue: initialQuery.includeInactiveLoans
            )
        } else {
            let interval = calendar.dateInterval(of: .year, for: now)
            _dateFrom = State(initialValue: interval?.start ?? now)
            _dateThrough = State(
                initialValue: interval?.end.addingTimeInterval(-0.001) ?? now
            )
        }
    }

    private var query: LoanReportQuery {
        let calendar = Calendar.current
        let first = min(dateFrom, dateThrough)
        let last = max(dateFrom, dateThrough)
        let start = calendar.startOfDay(for: first)
        let end = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: last)
        )?.addingTimeInterval(-0.001) ?? last
        return LoanReportQuery(
            dateFrom: limitPeriod ? start : nil,
            dateThrough: limitPeriod ? end : nil,
            loanIDs: loanIDs, currencies: currencies,
            includeInactiveLoans: includeInactive
        )
    }

    var body: some View {
        let snapshot = store.loanReport(query)
        let selectedRows = snapshot.rows(forLoanID: selectedLoanID)
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kredit-, Zins- und Tilgungsbericht")
                        .font(.title2.bold())
                    Text("Planwerte mit Restschuldverlauf und abgeglichenen Ist-Zahlungen")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(snapshot.summaries.count) Darlehen · \(snapshot.rows.count) Raten")
                    .font(.headline)
                Button("Neues Fenster", systemImage: "macwindow.badge.plus") {
                    openSpecializedReportWindow(
                        kind: .loans,
                        payload: query,
                        store: store,
                        openWindow: openWindow
                    )
                }
                .accessibilityIdentifier("openLoanReportWindow")
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            HStack(spacing: 10) {
                Toggle("Zeitraum", isOn: $limitPeriod)
                    .toggleStyle(.switch)
                DatePicker("Von", selection: $dateFrom, displayedComponents: .date)
                    .disabled(!limitPeriod)
                DatePicker("Bis", selection: $dateThrough, displayedComponents: .date)
                    .disabled(!limitPeriod)
                loanMenu
                currencyMenu
                Toggle("Inaktive Darlehen", isOn: $includeInactive)
                Spacer()
                Button("CSV exportieren …", systemImage: "tablecells") {
                    csvDocument = ReportCSVDocument(
                        data: LoanReportCSVExporter.data(snapshot: snapshot, metadata: metadata)
                    )
                    showCSVExporter = true
                }
                Menu {
                    Picker("Papierausrichtung", selection: $orientation) {
                        ForEach(ReportPDFOrientation.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    Divider()
                    Button("Drucken …", systemImage: "printer.fill") {
                        printReport(snapshot)
                    }
                    Button("PDF exportieren …", systemImage: "doc.richtext") {
                        exportPDF(snapshot)
                    }
                } label: {
                    Label("PDF · \(orientation.title)", systemImage: "printer")
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            VSplitView {
                ScrollView(.horizontal) {
                    Table(snapshot.summaries, selection: $selectedLoanID) {
                        TableColumn("Darlehen") { summary in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(summary.loanName).fontWeight(.semibold).lineLimit(1)
                                Text(
                                    "\(summary.lender) · \(summary.matchedPaymentCount) von \(summary.paymentCount) Raten abgeglichen"
                                )
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }.width(190)
                        TableColumn("Anfangssaldo") {
                            loanMoney($0.openingBalanceMinor, $0.currency)
                        }.width(125)
                        TableColumn("Plan / Ist") { summary in
                            VStack(alignment: .trailing, spacing: 1) {
                                loanMoney(summary.paymentMinor, summary.currency)
                                Text(Money(minorUnits: summary.actualPaymentMinor,
                                           currency: summary.currency).formatted)
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }.width(125)
                        TableColumn("Abweichung") {
                            loanVariance($0.paymentVarianceMinor, $0.currency)
                        }.width(115)
                        TableColumn("Tilgung") {
                            loanMoney($0.principalMinor, $0.currency)
                        }.width(110)
                        TableColumn("Zins + Gebühr") {
                            loanMoney($0.interestMinor + $0.feeMinor, $0.currency)
                        }.width(120)
                        TableColumn("Sondertilgung") {
                            loanMoney($0.extraPaymentMinor, $0.currency)
                        }.width(115)
                        TableColumn("Restschuld") {
                            loanMoney($0.closingBalanceMinor, $0.currency)
                        }.width(120)
                        TableColumn("Schuldenfrei") { summary in
                            Text(summary.payoffDate.map(reportDate) ?? "Ballonrest")
                        }.width(105)
                    }
                    .frame(width: 1_470, height: 245)
                }
                .overlay {
                    if snapshot.summaries.isEmpty {
                        ContentUnavailableView(
                            "Keine Kreditplanwerte", systemImage: "building.columns",
                            description: Text(
                                "Lege ein Darlehen mit wirksamem Zinssatz an oder passe die Berichtsfilter an."
                            )
                        )
                    }
                }

                VStack(spacing: 0) {
                    if !selectedRows.isEmpty {
                        ScrollView(.horizontal) {
                            Chart(selectedRows) { row in
                                LineMark(
                                    x: .value("Fälligkeit", row.dueDate),
                                    y: .value("Restschuld", chartAmount(row.closingBalanceMinor,
                                                                         row.currency))
                                )
                                .interpolationMethod(.linear)
                                .foregroundStyle(Color.accentColor)
                                PointMark(
                                    x: .value("Fälligkeit", row.dueDate),
                                    y: .value("Restschuld", chartAmount(row.closingBalanceMinor,
                                                                         row.currency))
                                )
                                .foregroundStyle(Color.accentColor)
                                .accessibilityLabel("Rate \(row.sequence), \(reportDate(row.dueDate))")
                                .accessibilityValue(
                                    Money(minorUnits: row.closingBalanceMinor,
                                          currency: row.currency).formatted
                                )
                            }
                            .chartYAxisLabel("Plan-Restschuld")
                            .frame(
                                width: max(760, CGFloat(selectedRows.count * 46)),
                                height: 180
                            )
                            .padding(.horizontal, 14)
                            .padding(.top, 8)
                        }
                        Divider()
                    }
                    Table(selectedRows) {
                        TableColumn("Nr.") { Text("\($0.sequence)") }.width(45)
                        TableColumn("Fälligkeit") { Text(reportDate($0.dueDate)) }.width(90)
                        TableColumn("Sollzins") { Text(rate($0.annualBasisPoints)) }.width(75)
                        TableColumn("Anfangssaldo") {
                            loanMoney($0.openingBalanceMinor, $0.currency)
                        }.width(115)
                        TableColumn("Plan / Ist") { row in
                            VStack(alignment: .trailing, spacing: 1) {
                                loanMoney(row.installmentMinor + row.extraPaymentMinor,
                                          row.currency)
                                Text(row.actualPaymentMinor.map {
                                    Money(minorUnits: $0, currency: row.currency).formatted
                                } ?? "Offen")
                                .font(.caption2).foregroundStyle(.secondary)
                            }
                        }.width(105)
                        TableColumn("Abweichung") { row in
                            if let variance = row.paymentVarianceMinor {
                                loanVariance(variance, row.currency)
                            } else {
                                Text("—").foregroundStyle(.secondary)
                            }
                        }.width(105)
                        TableColumn("Quelle") { row in
                            Text(row.matchSource?.title ?? "Nicht zugeordnet")
                                .foregroundStyle(row.matchSource == nil ? .secondary : .primary)
                        }.width(155)
                        TableColumn("Tilgung / Sonder") { row in
                            VStack(alignment: .trailing, spacing: 1) {
                                loanMoney(row.principalMinor, row.currency)
                                Text(Money(minorUnits: row.extraPaymentMinor,
                                           currency: row.currency).formatted)
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }.width(115)
                        TableColumn("Zins + Gebühr") {
                            loanMoney($0.interestMinor + $0.feeMinor, $0.currency)
                        }.width(115)
                        TableColumn("Restschuld") {
                            loanMoney($0.closingBalanceMinor, $0.currency)
                        }.width(115)
                    }
                    .frame(minHeight: 220)
                    .overlay {
                        if selectedLoanID == nil && !snapshot.summaries.isEmpty {
                            ContentUnavailableView(
                                "Darlehen auswählen", systemImage: "arrow.up",
                                description: Text("Tilgungsplan und Restschuldverlauf erscheinen hier.")
                            )
                        }
                    }
                }
            }
            Divider()
            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    Text("Plan-Summen").fontWeight(.semibold)
                    ForEach(snapshot.totals) { total in
                        Text(loanTotalDescription(total))
                        .monospacedDigit()
                    }
                    if snapshot.totals.count > 1 {
                        Label("Keine Addition ohne FX-Kurs", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 1_260, minHeight: 760)
        .onAppear {
            if selectedLoanID == nil { selectedLoanID = snapshot.summaries.first?.loanID }
        }
        .fileExporter(
            isPresented: $showCSVExporter, document: csvDocument,
            contentType: .commaSeparatedText, defaultFilename: filename
        ) { result in
            switch result {
            case .success: store.statusText = "Kreditbericht als CSV exportiert"
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showPDFExporter, document: pdfDocument,
            contentType: .pdf, defaultFilename: filename
        ) { result in
            switch result {
            case .success: store.statusText = "Kreditbericht als PDF exportiert"
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
    }

    private var loanMenu: some View {
        Menu {
            Button("Alle Darlehen") { loanIDs.removeAll() }
            ForEach(store.loans) { loan in
                Toggle(loan.name, isOn: member(loan.id, in: $loanIDs))
            }
        } label: {
            Label(loanIDs.isEmpty ? "Alle Darlehen" : "Darlehen (\(loanIDs.count))",
                  systemImage: "building.columns")
        }
    }

    private var currencyMenu: some View {
        Menu {
            Button("Alle Währungen") { currencies.removeAll() }
            ForEach(Set(store.loans.map { $0.currency.uppercased() }).sorted(), id: \.self) {
                currency in
                Toggle(currency, isOn: member(currency, in: $currencies))
            }
        } label: {
            Label(currencies.isEmpty ? "Alle Währungen" : "Währungen (\(currencies.count))",
                  systemImage: "eurosign.arrow.circlepath")
        }
    }

    private func member<Value: Hashable>(
        _ value: Value, in selection: Binding<Set<Value>>
    ) -> Binding<Bool> {
        Binding(
            get: { selection.wrappedValue.contains(value) },
            set: { included in
                if included { selection.wrappedValue.insert(value) }
                else { selection.wrappedValue.remove(value) }
            }
        )
    }

    private func loanMoney(_ minor: Int64, _ currency: String) -> some View {
        Text(Money(minorUnits: minor, currency: currency).formatted)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .monospacedDigit()
    }

    private func loanVariance(_ minor: Int64, _ currency: String) -> some View {
        Text(Money(minorUnits: minor, currency: currency).formatted)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .monospacedDigit()
            .foregroundStyle(minor == 0 ? Color.secondary : Color.orange)
    }

    private func loanTotalDescription(_ total: LoanReportCurrencyTotal) -> String {
        let currency = total.currency
        let principal = Money(minorUnits: total.principalMinor, currency: currency).formatted
        let cost = Money(minorUnits: total.interestMinor + total.feeMinor,
                         currency: currency).formatted
        let balance = Money(minorUnits: total.closingBalanceMinor, currency: currency).formatted
        let actual = Money(minorUnits: total.actualPaymentMinor, currency: currency).formatted
        let variance = Money(minorUnits: total.paymentVarianceMinor, currency: currency).formatted
        return "\(currency): Tilgung \(principal) · Zins/Gebühr \(cost) · Restschuld \(balance) · Ist \(actual) · Abweichung \(variance)"
    }

    private func chartAmount(_ minor: Int64, _ currency: String) -> Decimal {
        Decimal(minor) / Decimal(Money.minorUnitFactor(for: currency))
    }

    private func rate(_ basisPoints: Int) -> String {
        let whole = basisPoints / 100
        let remainder = abs(basisPoints % 100)
        return remainder == 0
            ? "\(whole) %"
            : "\(whole),\(String(format: "%02d", remainder)) %"
    }

    private func reportDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }

    private var dateLabel: String {
        limitPeriod
            ? "\(reportDate(query.dateFrom ?? dateFrom))–\(reportDate(query.dateThrough ?? dateThrough))"
            : "gesamter Tilgungsplan"
    }

    private var filterSummary: String {
        let loans = loanIDs.isEmpty ? "alle Darlehen" : "\(loanIDs.count) Darlehen"
        let currency = currencies.isEmpty ? "alle Währungen" : currencies.sorted().joined(separator: ", ")
        return "\(loans); \(currency); \(includeInactive ? "inklusive inaktiv" : "nur aktiv")"
    }

    private var metadata: LoanReportExportMetadata {
        LoanReportExportMetadata(
            title: "Kredit-, Zins- und Tilgungsbericht",
            dateLabel: dateLabel, filterSummary: filterSummary, generatedAt: .now
        )
    }

    private func pdfData(_ snapshot: LoanReportSnapshot) throws -> Data {
        try ComparisonReportPDFExporter.loanData(
            snapshot: snapshot, metadata: metadata, orientation: orientation
        )
    }

    private func printReport(_ snapshot: LoanReportSnapshot) {
        do { try RegisterPrintService.printPDF(try pdfData(snapshot)) }
        catch { store.errorMessage = error.localizedDescription }
    }

    private func exportPDF(_ snapshot: LoanReportSnapshot) {
        do {
            pdfDocument = ReportPDFDocument(data: try pdfData(snapshot))
            showPDFExporter = true
        } catch { store.errorMessage = error.localizedDescription }
    }

    private var filename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return limitPeriod
            ? "FinanzVerwalter-Kreditbericht-\(formatter.string(from: query.dateFrom ?? dateFrom))-bis-"
                + formatter.string(from: query.dateThrough ?? dateThrough)
            : "FinanzVerwalter-Kreditbericht-Gesamtplan"
    }
}

private struct VATReportView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var dateFrom: Date
    @State private var dateThrough: Date
    @State private var accountIDs = Set<UUID>()
    @State private var accountGroupIDs = Set<UUID>()
    @State private var currencies = Set<String>()
    @State private var statuses = Set(
        TransactionStatus.allCases.filter { $0 != .cancelled }
    )
    @State private var includeHidden = false
    @State private var includeExcluded = false
    @State private var includeTransfers = false
    @State private var selectedRowID: String?
    @State private var orientation: ReportPDFOrientation = .landscape
    @State private var csvDocument = ReportCSVDocument(data: Data())
    @State private var pdfDocument = ReportPDFDocument(data: Data())
    @State private var showCSVExporter = false
    @State private var showPDFExporter = false

    init(
        initialQuery: VATReportQuery? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        if let initialQuery {
            _dateFrom = State(initialValue: initialQuery.dateFrom)
            _dateThrough = State(initialValue: initialQuery.dateThrough)
            _accountIDs = State(initialValue: initialQuery.accountIDs)
            _accountGroupIDs = State(
                initialValue: initialQuery.accountGroupIDs
            )
            _currencies = State(initialValue: initialQuery.currencies)
            _statuses = State(initialValue: initialQuery.statuses)
            _includeHidden = State(
                initialValue: initialQuery.includeHiddenAccounts
            )
            _includeExcluded = State(
                initialValue: initialQuery.includeAccountsExcludedFromReports
            )
            _includeTransfers = State(
                initialValue: initialQuery.includeTransfers
            )
        } else {
            let interval = calendar.dateInterval(of: .year, for: now)
            _dateFrom = State(initialValue: interval?.start ?? now)
            _dateThrough = State(
                initialValue: interval?.end.addingTimeInterval(-0.001) ?? now
            )
        }
    }

    private var query: VATReportQuery {
        let calendar = Calendar.current
        let first = min(dateFrom, dateThrough)
        let last = max(dateFrom, dateThrough)
        let start = calendar.startOfDay(for: first)
        let end = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: last)
        )?.addingTimeInterval(-0.001) ?? last
        return VATReportQuery(
            dateFrom: start, dateThrough: end,
            accountIDs: accountIDs, accountGroupIDs: accountGroupIDs,
            currencies: currencies, statuses: statuses,
            includeHiddenAccounts: includeHidden,
            includeAccountsExcludedFromReports: includeExcluded,
            includeTransfers: includeTransfers
        )
    }

    var body: some View {
        let snapshot = store.vatReport(query)
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Umsatzsteuerbericht")
                        .font(.title2.bold())
                    Text("Brutto, Netto, Umsatzsteuer, Vorsteuer und Zahllast je Schlüssel")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(snapshot.facts.count) MwSt.-Positionen")
                    .font(.headline)
                Button("Neues Fenster", systemImage: "macwindow.badge.plus") {
                    openSpecializedReportWindow(
                        kind: .valueAddedTax,
                        payload: query,
                        store: store,
                        openWindow: openWindow
                    )
                }
                .accessibilityIdentifier("openVATReportWindow")
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            HStack(spacing: 10) {
                DatePicker("Von", selection: $dateFrom, displayedComponents: .date)
                DatePicker("Bis", selection: $dateThrough, displayedComponents: .date)
                accountMenu
                currencyMenu
                statusMenu
                Menu {
                    Toggle("Ausgeblendete/geschlossene Konten", isOn: $includeHidden)
                    Toggle("Von Berichten ausgeschlossene Konten", isOn: $includeExcluded)
                    Toggle("Umbuchungen einbeziehen", isOn: $includeTransfers)
                } label: {
                    Label("Optionen", systemImage: "slider.horizontal.3")
                }
                Spacer()
                Button("CSV exportieren …", systemImage: "tablecells") {
                    csvDocument = ReportCSVDocument(
                        data: VATReportCSVExporter.data(snapshot: snapshot, metadata: metadata)
                    )
                    showCSVExporter = true
                }
                Menu {
                    Picker("Papierausrichtung", selection: $orientation) {
                        ForEach(ReportPDFOrientation.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    Divider()
                    Button("Drucken …", systemImage: "printer.fill") {
                        printReport(snapshot)
                    }
                    Button("PDF exportieren …", systemImage: "doc.richtext") {
                        exportPDF(snapshot)
                    }
                } label: {
                    Label("PDF · \(orientation.title)", systemImage: "printer")
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            VSplitView {
                ScrollView(.horizontal) {
                    Table(snapshot.rows, selection: $selectedRowID) {
                        TableColumn("MwSt.-Schlüssel") { row in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.vatCodeName).lineLimit(1)
                                Text("\(row.bookingCount) Positionen")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .width(180)
                        TableColumn("Satz") { row in Text(rate(row.rateBasisPoints)) }
                            .width(70)
                        TableColumn("Bruttoumsatz") {
                            reportMoney($0.grossSalesMinor, $0.currency)
                        }.width(125)
                        TableColumn("Nettoumsatz") {
                            reportMoney($0.netSalesMinor, $0.currency)
                        }.width(125)
                        TableColumn("Umsatzsteuer") {
                            reportMoney($0.outputTaxMinor, $0.currency)
                        }.width(115)
                        TableColumn("Bruttoeinkauf") {
                            reportMoney($0.grossPurchasesMinor, $0.currency)
                        }.width(125)
                        TableColumn("Nettoeinkauf") {
                            reportMoney($0.netPurchasesMinor, $0.currency)
                        }.width(125)
                        TableColumn("Vorsteuer") {
                            reportMoney($0.inputTaxMinor, $0.currency)
                        }.width(110)
                        TableColumn("Zahllast") {
                            reportMoney($0.payableMinor, $0.currency)
                        }.width(115)
                        TableColumn("Währung") { Text($0.currency) }.width(70)
                    }
                    .frame(width: 1_285, height: 300)
                }
                .overlay {
                    if snapshot.rows.isEmpty {
                        ContentUnavailableView(
                            "Keine MwSt.-Positionen", systemImage: "percent",
                            description: Text(
                                "Im gewählten Zeitraum sind keine Buchungs- oder Splitzeilen mit MwSt.-Schlüssel vorhanden."
                            )
                        )
                    }
                }

                Table(snapshot.facts(inRowID: selectedRowID)) {
                    TableColumn("Datum") { Text(reportDate($0.bookingDate)) }.width(90)
                    TableColumn("Konto") { Text($0.accountName).lineLimit(1) }.width(135)
                    TableColumn("Empfänger") { Text($0.payee).lineLimit(1) }.width(150)
                    TableColumn("Kategorie") { Text($0.categoryPath).lineLimit(2) }.width(220)
                    TableColumn("Brutto") { reportMoney($0.grossMinor, $0.currency) }.width(110)
                    TableColumn("Netto") { reportMoney($0.netMinor, $0.currency) }.width(110)
                    TableColumn("Steuer") { reportMoney($0.taxMinor, $0.currency) }.width(100)
                    TableColumn("Split") { Text($0.splitID == nil ? "Nein" : "Ja") }.width(60)
                }
                .frame(minHeight: 190)
                .overlay {
                    if selectedRowID == nil && !snapshot.rows.isEmpty {
                        ContentUnavailableView(
                            "MwSt.-Schlüssel auswählen", systemImage: "arrow.up",
                            description: Text("Die zugehörigen Buchungs- und Splitpositionen erscheinen hier.")
                        )
                    }
                }
            }
            Divider()
            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    Text("Summen").fontWeight(.semibold)
                    ForEach(snapshot.totals) { total in
                        Text(
                            "\(total.currency): Umsatzsteuer "
                                + Money(minorUnits: total.outputTaxMinor,
                                        currency: total.currency).formatted
                                + " · Vorsteuer "
                                + Money(minorUnits: total.inputTaxMinor,
                                        currency: total.currency).formatted
                                + " · Zahllast "
                                + Money(minorUnits: total.payableMinor,
                                        currency: total.currency).formatted
                        )
                        .monospacedDigit()
                    }
                    if snapshot.totals.count > 1 {
                        Label("Keine Addition ohne FX-Kurs", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 1_260, minHeight: 720)
        .fileExporter(
            isPresented: $showCSVExporter, document: csvDocument,
            contentType: .commaSeparatedText, defaultFilename: filename
        ) { result in
            switch result {
            case .success: store.statusText = "Umsatzsteuerbericht als CSV exportiert"
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showPDFExporter, document: pdfDocument,
            contentType: .pdf, defaultFilename: filename
        ) { result in
            switch result {
            case .success: store.statusText = "Umsatzsteuerbericht als PDF exportiert"
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
    }

    private var accountMenu: some View {
        Menu {
            Button("Alle Konten") { accountIDs.removeAll(); accountGroupIDs.removeAll() }
            Section("Kontengruppen") {
                ForEach(store.accountGroups.filter(\.isActive)) { group in
                    Toggle(group.name, isOn: member(group.id, in: $accountGroupIDs))
                }
            }
            Section("Einzelkonten") {
                ForEach(store.accounts) { account in
                    Toggle(account.name, isOn: member(account.id, in: $accountIDs))
                }
            }
        } label: {
            Label(
                accountIDs.isEmpty && accountGroupIDs.isEmpty
                    ? "Alle Konten" : "Konten (\(accountIDs.count + accountGroupIDs.count))",
                systemImage: "building.columns"
            )
        }
    }

    private var currencyMenu: some View {
        Menu {
            Button("Alle Währungen") { currencies.removeAll() }
            ForEach(Set(store.transactions.map { $0.currency.uppercased() }).sorted(), id: \.self) {
                currency in
                Toggle(currency, isOn: member(currency, in: $currencies))
            }
        } label: {
            Label(currencies.isEmpty ? "Alle Währungen" : "Währungen (\(currencies.count))",
                  systemImage: "eurosign.arrow.circlepath")
        }
    }

    private var statusMenu: some View {
        Menu {
            Button("Alle regulären Status") {
                statuses = Set(TransactionStatus.allCases.filter { $0 != .cancelled })
            }
            Button("Alle einschließlich Storniert") {
                statuses = Set(TransactionStatus.allCases)
            }
            Divider()
            ForEach(TransactionStatus.allCases, id: \.self) { status in
                Toggle(status.title, isOn: member(status, in: $statuses))
            }
        } label: {
            Label("Status \(statuses.count)/\(TransactionStatus.allCases.count)",
                  systemImage: "checkmark.circle")
        }
    }

    private func member<Value: Hashable>(
        _ value: Value, in selection: Binding<Set<Value>>
    ) -> Binding<Bool> {
        Binding(
            get: { selection.wrappedValue.contains(value) },
            set: { included in
                if included { selection.wrappedValue.insert(value) }
                else { selection.wrappedValue.remove(value) }
            }
        )
    }

    private func reportMoney(_ minor: Int64, _ currency: String) -> some View {
        Text(Money(minorUnits: minor, currency: currency).formatted)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .monospacedDigit()
    }

    private func rate(_ basisPoints: Int) -> String {
        let whole = basisPoints / 100
        let remainder = abs(basisPoints % 100)
        return remainder == 0
            ? "\(whole) %"
            : "\(whole),\(String(format: "%02d", remainder)) %"
    }

    private func reportDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }

    private var metadata: VATReportExportMetadata {
        VATReportExportMetadata(
            title: "Umsatzsteuerbericht", dateLabel: dateLabel,
            filterSummary: filterSummary, generatedAt: .now
        )
    }

    private var filterSummary: String {
        let accounts = accountIDs.isEmpty && accountGroupIDs.isEmpty
            ? "alle Konten"
            : "\(accountIDs.count) Konten, \(accountGroupIDs.count) Gruppen"
        let currency = currencies.isEmpty ? "alle Währungen" : currencies.sorted().joined(separator: ", ")
        return "\(accounts); \(currency); \(statuses.count) Status"
    }

    private var dateLabel: String {
        "\(reportDate(query.dateFrom))–\(reportDate(query.dateThrough))"
    }

    private func pdfData(_ snapshot: VATReportSnapshot) throws -> Data {
        try ComparisonReportPDFExporter.vatData(
            snapshot: snapshot, metadata: metadata, orientation: orientation
        )
    }

    private func printReport(_ snapshot: VATReportSnapshot) {
        do { try RegisterPrintService.printPDF(try pdfData(snapshot)) }
        catch { store.errorMessage = error.localizedDescription }
    }

    private func exportPDF(_ snapshot: VATReportSnapshot) {
        do {
            pdfDocument = ReportPDFDocument(data: try pdfData(snapshot))
            showPDFExporter = true
        } catch { store.errorMessage = error.localizedDescription }
    }

    private var filename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "FinanzVerwalter-Umsatzsteuer-\(formatter.string(from: query.dateFrom))-bis-"
            + formatter.string(from: query.dateThrough)
    }
}

private struct AssetRegisterReportView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var referenceDate = Date()
    @State private var horizon: AssetRegisterReportHorizon = .all
    @State private var includeInactive = false
    @State private var contractTypes = Set<ContractType>()
    @State private var inventoryCategories = Set<InventoryCategory>()
    @State private var searchText = ""
    @State private var selectedContractID: UUID?
    @State private var selectedInventoryID: UUID?
    @State private var orientation: ReportPDFOrientation = .landscape
    @State private var csvDocument = ReportCSVDocument(data: Data())
    @State private var pdfDocument = ReportPDFDocument(data: Data())
    @State private var showCSVExporter = false
    @State private var showPDFExporter = false

    init(initialQuery: AssetRegisterReportQuery? = nil) {
        if let initialQuery {
            _referenceDate = State(initialValue: initialQuery.referenceDate)
            _horizon = State(initialValue: initialQuery.horizon)
            _includeInactive = State(initialValue: initialQuery.includeInactive)
            _contractTypes = State(initialValue: initialQuery.contractTypes)
            _inventoryCategories = State(
                initialValue: initialQuery.inventoryCategories
            )
            _searchText = State(initialValue: initialQuery.text)
        }
    }

    private var query: AssetRegisterReportQuery {
        AssetRegisterReportQuery(
            referenceDate: referenceDate, horizon: horizon,
            includeInactive: includeInactive, contractTypes: contractTypes,
            inventoryCategories: inventoryCategories, text: searchText
        )
    }

    private var snapshot: AssetRegisterReportSnapshot {
        AssetRegisterReportEngine.snapshot(
            query: query, contracts: store.contracts,
            inventory: store.inventoryItems, accounts: store.accounts,
            categories: store.categories
        )
    }

    var body: some View {
        let value = snapshot
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Vertrags- und Inventarübersicht").font(.title2.bold())
                    Text("Jahreskosten, Kündigungsfristen, Werte und Garantien")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                InvestmentValue(
                    title: "Vertragskosten/Jahr",
                    value: Money(minorUnits: value.annualContractCostMinor).formatted
                )
                InvestmentValue(
                    title: "Inventar aktuell",
                    value: Money(minorUnits: value.currentValueMinor).formatted
                )
                InvestmentValue(
                    title: "Versicherungswert",
                    value: Money(minorUnits: value.insuranceValueMinor).formatted
                )
                Button("Neues Fenster", systemImage: "macwindow.badge.plus") {
                    openSpecializedReportWindow(
                        kind: .assetRegister,
                        payload: query,
                        store: store,
                        openWindow: openWindow
                    )
                }
                .accessibilityIdentifier("openAssetRegisterReportWindow")
                Button("Schließen") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            HStack(spacing: 10) {
                DatePicker("Stichtag", selection: $referenceDate, displayedComponents: .date)
                Picker("Fristen", selection: $horizon) {
                    ForEach(AssetRegisterReportHorizon.allCases) {
                        Text($0.title).tag($0)
                    }
                }
                .frame(width: 175)
                contractTypeMenu
                inventoryCategoryMenu
                Toggle("Inaktive", isOn: $includeInactive).toggleStyle(.checkbox)
                TextField("Suche", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 150, maxWidth: 230)
                Spacer()
                Button("CSV exportieren …", systemImage: "tablecells") {
                    csvDocument = ReportCSVDocument(
                        data: AssetRegisterReportCSVExporter.data(
                            snapshot: value, metadata: metadata
                        )
                    )
                    showCSVExporter = true
                }
                Menu {
                    Picker("Papierausrichtung", selection: $orientation) {
                        ForEach(ReportPDFOrientation.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    Divider()
                    Button("Drucken …", systemImage: "printer.fill") { printReport(value) }
                    Button("PDF exportieren …", systemImage: "doc.richtext") {
                        exportPDF(value)
                    }
                } label: {
                    Label("PDF · \(orientation.title)", systemImage: "printer")
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            VSplitView {
                VStack(spacing: 0) {
                    sectionHeader(
                        "Verträge", count: value.contracts.count,
                        detail: "\(Money(minorUnits: value.annualContractCostMinor).formatted) pro Jahr"
                    )
                    Table(value.contracts, selection: $selectedContractID) {
                        TableColumn("Vertrag") { row in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.name).fontWeight(.semibold)
                                Text(row.provider).font(.caption2).foregroundStyle(.secondary)
                            }
                        }.width(min: 170, ideal: 220)
                        TableColumn("Typ") { Text($0.type.title) }.width(115)
                        TableColumn("Status") { Text($0.isActive ? "Aktiv" : "Inaktiv") }.width(65)
                        TableColumn("Jahreskosten") { reportMoney($0.annualCostMinor) }.width(110)
                        TableColumn("Kündigungsfrist") {
                            deadlineText($0.cancellationDeadline)
                        }.width(105)
                        TableColumn("Verlängerung") { Text(reportDate($0.nextRenewal)) }.width(100)
                        TableColumn("Konto") { Text($0.accountName).lineLimit(1) }.width(130)
                        TableColumn("Kategorie") { Text($0.categoryPath).lineLimit(1) }
                            .width(min: 160, ideal: 240)
                    }
                    .overlay {
                        if value.contracts.isEmpty {
                            ContentUnavailableView(
                                "Keine Verträge", systemImage: "doc.text",
                                description: Text("Für die gewählten Filter sind keine Verträge enthalten.")
                            )
                        }
                    }
                }
                .frame(minHeight: 230)
                VStack(spacing: 0) {
                    sectionHeader(
                        "Inventar", count: value.inventory.count,
                        detail: "\(Money(minorUnits: value.currentValueMinor).formatted) aktuell"
                    )
                    Table(value.inventory, selection: $selectedInventoryID) {
                        TableColumn("Gegenstand") { row in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.name).fontWeight(.semibold)
                                Text(row.room.isEmpty ? "Ohne Raum" : row.room)
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }.width(min: 170, ideal: 220)
                        TableColumn("Kategorie") { Text($0.category.title) }.width(105)
                        TableColumn("Status") { Text($0.isActive ? "Aktiv" : "Inaktiv") }.width(65)
                        TableColumn("Kaufpreis") { reportMoney($0.purchasePriceMinor) }.width(105)
                        TableColumn("Aktueller Wert") { reportMoney($0.currentValueMinor) }.width(110)
                        TableColumn("Versicherungswert") { reportMoney($0.insuranceValueMinor) }.width(125)
                        TableColumn("Garantieende") { warrantyText($0.warrantyEnd) }.width(105)
                        TableColumn("Händler") { Text($0.retailer).lineLimit(1) }.width(120)
                        TableColumn("Seriennummer") { Text($0.serialNumber).lineLimit(1) }
                            .width(min: 120, ideal: 180)
                    }
                    .overlay {
                        if value.inventory.isEmpty {
                            ContentUnavailableView(
                                "Kein Inventar", systemImage: "shippingbox",
                                description: Text("Für die gewählten Filter sind keine Gegenstände enthalten.")
                            )
                        }
                    }
                }
                .frame(minHeight: 230)
            }
            Divider()
            drillDown(value)
                .frame(height: 54)
                .padding(.horizontal, 14)
        }
        .frame(minWidth: 1_180, minHeight: 760)
        .fileExporter(
            isPresented: $showCSVExporter, document: csvDocument,
            contentType: .commaSeparatedText, defaultFilename: filename
        ) { result in
            switch result {
            case .success: store.statusText = "Vertrags- und Inventarbericht als CSV exportiert"
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showPDFExporter, document: pdfDocument,
            contentType: .pdf, defaultFilename: filename
        ) { result in
            switch result {
            case .success: store.statusText = "Vertrags- und Inventarbericht als PDF exportiert"
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
    }

    private var contractTypeMenu: some View {
        Menu {
            Button("Alle Vertragstypen") { contractTypes.removeAll() }
            ForEach(ContractType.allCases) { type in
                Toggle(type.title, isOn: member(type, in: $contractTypes))
            }
        } label: {
            Label(
                contractTypes.isEmpty ? "Alle Vertragstypen" : "Vertragstypen (\(contractTypes.count))",
                systemImage: "doc.text"
            )
        }
    }

    private var inventoryCategoryMenu: some View {
        Menu {
            Button("Alle Inventarkategorien") { inventoryCategories.removeAll() }
            ForEach(InventoryCategory.allCases) { category in
                Toggle(category.title, isOn: member(category, in: $inventoryCategories))
            }
        } label: {
            Label(
                inventoryCategories.isEmpty
                    ? "Alle Inventarkategorien" : "Inventar (\(inventoryCategories.count))",
                systemImage: "shippingbox"
            )
        }
    }

    private func sectionHeader(_ title: String, count: Int, detail: String) -> some View {
        HStack {
            Text(title).font(.headline)
            Text("\(count)").foregroundStyle(.secondary)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.25))
    }

    @ViewBuilder
    private func drillDown(_ snapshot: AssetRegisterReportSnapshot) -> some View {
        if let id = selectedContractID,
           let row = snapshot.contracts.first(where: { $0.id == id }) {
            HStack {
                Label(row.name, systemImage: "doc.text")
                Text("\(row.provider) · \(row.type.title)").foregroundStyle(.secondary)
                Spacer()
                Text("Kündigung: \(reportDate(row.cancellationDeadline))")
                Text("Jahreskosten: \(Money(minorUnits: row.annualCostMinor).formatted)")
                    .monospacedDigit()
            }
        } else if let id = selectedInventoryID,
                  let row = snapshot.inventory.first(where: { $0.id == id }) {
            HStack {
                Label(row.name, systemImage: "shippingbox")
                Text("\(row.category.title) · \(row.room)").foregroundStyle(.secondary)
                Spacer()
                Text("Garantie: \(reportDate(row.warrantyEnd))")
                Text("Aktuell: \(Money(minorUnits: row.currentValueMinor).formatted)")
                    .monospacedDigit()
            }
        } else {
            Label(
                "Zeile auswählen, um die wichtigsten Stammdaten im Drill-down zu sehen.",
                systemImage: "cursorarrow.click"
            )
            .foregroundStyle(.secondary)
        }
    }

    private func member<Value: Hashable>(
        _ value: Value, in selection: Binding<Set<Value>>
    ) -> Binding<Bool> {
        Binding(
            get: { selection.wrappedValue.contains(value) },
            set: { included in
                if included { selection.wrappedValue.insert(value) }
                else { selection.wrappedValue.remove(value) }
            }
        )
    }

    private func reportMoney(_ minor: Int64) -> some View {
        Text(Money(minorUnits: minor).formatted)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .monospacedDigit()
    }

    private func deadlineText(_ date: Date?) -> some View {
        Text(reportDate(date))
            .foregroundStyle(
                date.map { $0 < Calendar.current.startOfDay(for: referenceDate) } == true
                    ? Color.red : Color.primary
            )
    }

    private func warrantyText(_ date: Date?) -> some View {
        Text(reportDate(date))
            .foregroundStyle(
                date.map { $0 < Calendar.current.startOfDay(for: referenceDate) } == true
                    ? Color.orange : Color.primary
            )
    }

    private func reportDate(_ date: Date?) -> String {
        guard let date else { return "–" }
        return date.formatted(.dateTime.day().month().year())
    }

    private var filterSummary: String {
        let deadline = horizon.title
        let status = includeInactive ? "inklusive inaktiv" : "nur aktiv"
        let contract = contractTypes.isEmpty
            ? "alle Vertragstypen" : contractTypes.map(\.title).sorted().joined(separator: ", ")
        let inventory = inventoryCategories.isEmpty
            ? "alle Inventarkategorien"
            : inventoryCategories.map(\.title).sorted().joined(separator: ", ")
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return [deadline, status, contract, inventory, text.isEmpty ? nil : "Suche: \(text)"]
            .compactMap { $0 }.joined(separator: "; ")
    }

    private var metadata: AssetRegisterReportExportMetadata {
        AssetRegisterReportExportMetadata(
            title: "Vertrags- und Inventarübersicht",
            filterSummary: filterSummary, generatedAt: .now
        )
    }

    private func pdfData(_ snapshot: AssetRegisterReportSnapshot) throws -> Data {
        try ComparisonReportPDFExporter.assetRegisterData(
            snapshot: snapshot, metadata: metadata, orientation: orientation
        )
    }

    private func printReport(_ snapshot: AssetRegisterReportSnapshot) {
        do { try RegisterPrintService.printPDF(try pdfData(snapshot)) }
        catch { store.errorMessage = error.localizedDescription }
    }

    private func exportPDF(_ snapshot: AssetRegisterReportSnapshot) {
        do {
            pdfDocument = ReportPDFDocument(data: try pdfData(snapshot))
            showPDFExporter = true
        } catch { store.errorMessage = error.localizedDescription }
    }

    private var filename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "FinanzVerwalter-Vertraege-Inventar-\(formatter.string(from: referenceDate))"
    }
}

private struct AccountBalanceReportView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var asOf = Date.now
    @State private var accountIDs = Set<UUID>()
    @State private var groupIDs = Set<UUID>()
    @State private var currencies = Set<String>()
    @State private var includeHidden = false
    @State private var includeClosed = false
    @State private var includeExcluded = false
    @State private var orientation: ReportPDFOrientation = .landscape
    @State private var csvDocument = ReportCSVDocument(data: Data())
    @State private var pdfDocument = ReportPDFDocument(data: Data())
    @State private var showCSVExporter = false
    @State private var showPDFExporter = false

    init(initialQuery: AccountBalanceReportQuery? = nil) {
        if let initialQuery {
            _asOf = State(initialValue: initialQuery.asOf)
            _accountIDs = State(initialValue: initialQuery.accountIDs)
            _groupIDs = State(initialValue: initialQuery.accountGroupIDs)
            _currencies = State(initialValue: initialQuery.currencies)
            _includeHidden = State(
                initialValue: initialQuery.includeHiddenAccounts
            )
            _includeClosed = State(
                initialValue: initialQuery.includeClosedAccounts
            )
            _includeExcluded = State(
                initialValue: initialQuery.includeAccountsExcludedFromNetWorth
            )
        }
    }

    private var query: AccountBalanceReportQuery {
        AccountBalanceReportQuery(
            asOf: asOf,
            accountIDs: accountIDs,
            accountGroupIDs: groupIDs,
            currencies: currencies,
            includeHiddenAccounts: includeHidden,
            includeClosedAccounts: includeClosed,
            includeAccountsExcludedFromNetWorth: includeExcluded
        )
    }

    var body: some View {
        let snapshot = store.accountBalanceReport(query)
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kontosalden und Nettovermögen")
                        .font(.title2.bold())
                    Text("Historischer Tagesabschluss mit getrennten Währungssummen")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Neues Fenster", systemImage: "macwindow.badge.plus") {
                    openSpecializedReportWindow(
                        kind: .accountBalances,
                        payload: query,
                        store: store,
                        openWindow: openWindow
                    )
                }
                .accessibilityIdentifier("openAccountBalanceReportWindow")
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            HStack(spacing: 12) {
                DatePicker("Stichtag", selection: $asOf, displayedComponents: .date)
                balanceAccountMenu
                balanceCurrencyMenu
                Menu {
                    Toggle("Ausgeblendete Konten", isOn: $includeHidden)
                    Toggle("Geschlossene Konten", isOn: $includeClosed)
                    Toggle("Nicht im Vermögen enthaltene Konten", isOn: $includeExcluded)
                } label: {
                    Label("Optionen", systemImage: "slider.horizontal.3")
                }
                Spacer()
                Button("CSV exportieren …", systemImage: "tablecells") {
                    csvDocument = ReportCSVDocument(
                        data: AccountBalanceReportCSVExporter.data(
                            snapshot: snapshot, metadata: metadata
                        )
                    )
                    showCSVExporter = true
                }
                Menu {
                    Picker("Papierausrichtung", selection: $orientation) {
                        ForEach(ReportPDFOrientation.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    Divider()
                    Button("Drucken …", systemImage: "printer.fill") {
                        printReport(snapshot)
                    }
                    Button("PDF exportieren …", systemImage: "doc.richtext") {
                        exportPDF(snapshot)
                    }
                } label: {
                    Label("PDF · \(orientation.title)", systemImage: "printer")
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            Table(snapshot.rows) {
                TableColumn("Gruppe") { Text($0.groupName).lineLimit(1) }
                    .width(min: 110, ideal: 145)
                TableColumn("Konto") { Text($0.accountName).lineLimit(1) }
                    .width(min: 130, ideal: 180)
                TableColumn("Kontotyp") { Text($0.accountType.title).lineLimit(1) }
                    .width(min: 115, ideal: 145)
                TableColumn("Eröffnung") { row in balanceMoney(row.openingBalanceMinor, row.currency) }
                    .width(125)
                TableColumn("Bewegungen") { row in balanceMoney(row.movementMinor, row.currency) }
                    .width(125)
                TableColumn("Saldo") { row in balanceMoney(row.balanceMinor, row.currency) }
                    .width(125)
                TableColumn("Währung") { Text($0.currency) }
                    .width(70)
            }
            .overlay {
                if snapshot.rows.isEmpty {
                    ContentUnavailableView(
                        "Keine Kontosalden",
                        systemImage: "scalemass",
                        description: Text("Die gewählten Filter enthalten am Stichtag keine Konten.")
                    )
                }
            }
            Divider()
            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    Text("Summen").fontWeight(.semibold)
                    ForEach(snapshot.totals) { total in
                        Text(
                            "\(total.currency): Aktiva "
                                + Money(minorUnits: total.assetsMinor, currency: total.currency).formatted
                                + " · Passiva "
                                + Money(minorUnits: total.liabilitiesMinor, currency: total.currency).formatted
                                + " · Netto "
                                + Money(minorUnits: total.netWorthMinor, currency: total.currency).formatted
                        )
                        .monospacedDigit()
                    }
                    if snapshot.totals.count > 1 {
                        Label("Keine Addition ohne FX-Kurs", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 1_050, minHeight: 650)
        .fileExporter(
            isPresented: $showCSVExporter,
            document: csvDocument,
            contentType: .commaSeparatedText,
            defaultFilename: filename
        ) { result in
            if case .failure(let error) = result { store.errorMessage = error.localizedDescription }
        }
        .fileExporter(
            isPresented: $showPDFExporter,
            document: pdfDocument,
            contentType: .pdf,
            defaultFilename: filename
        ) { result in
            if case .failure(let error) = result { store.errorMessage = error.localizedDescription }
        }
    }

    private var balanceAccountMenu: some View {
        Menu {
            Button("Alle Vermögenskonten") { accountIDs.removeAll(); groupIDs.removeAll() }
            Section("Kontengruppen") {
                ForEach(store.accountGroups.filter(\.isActive)) { group in
                    Toggle(group.name, isOn: member(group.id, in: $groupIDs))
                }
            }
            Section("Einzelkonten") {
                ForEach(store.accounts) { account in
                    Toggle(account.name, isOn: member(account.id, in: $accountIDs))
                }
            }
        } label: {
            Label(
                accountIDs.isEmpty && groupIDs.isEmpty
                    ? "Alle Konten" : "Konten (\(accountIDs.count + groupIDs.count))",
                systemImage: "building.columns"
            )
        }
    }

    private var balanceCurrencyMenu: some View {
        Menu {
            Button("Alle Währungen") { currencies.removeAll() }
            ForEach(Set(store.accounts.map { $0.currency.uppercased() }).sorted(), id: \.self) {
                currency in
                Toggle(currency, isOn: member(currency, in: $currencies))
            }
        } label: {
            Label(currencies.isEmpty ? "Alle Währungen" : "Währungen (\(currencies.count))",
                  systemImage: "eurosign.arrow.circlepath")
        }
    }

    private func member<Value: Hashable>(
        _ value: Value, in selection: Binding<Set<Value>>
    ) -> Binding<Bool> {
        Binding(
            get: { selection.wrappedValue.contains(value) },
            set: { included in
                if included { selection.wrappedValue.insert(value) }
                else { selection.wrappedValue.remove(value) }
            }
        )
    }

    private func balanceMoney(_ minor: Int64, _ currency: String) -> some View {
        Text(Money(minorUnits: minor, currency: currency).formatted)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .monospacedDigit()
    }

    private var metadata: AccountBalanceReportExportMetadata {
        AccountBalanceReportExportMetadata(
            title: "Kontosalden und Nettovermögen",
            filterSummary: accountIDs.isEmpty && groupIDs.isEmpty
                ? "alle Vermögenskonten" : "\(accountIDs.count) Konten, \(groupIDs.count) Gruppen",
            generatedAt: .now
        )
    }

    private func pdfData(_ snapshot: AccountBalanceReportSnapshot) throws -> Data {
        try AccountBalanceReportPDFExporter.data(
            snapshot: snapshot, metadata: metadata, orientation: orientation
        )
    }

    private func printReport(_ snapshot: AccountBalanceReportSnapshot) {
        do { try RegisterPrintService.printPDF(try pdfData(snapshot)) }
        catch { store.errorMessage = error.localizedDescription }
    }

    private func exportPDF(_ snapshot: AccountBalanceReportSnapshot) {
        do {
            pdfDocument = ReportPDFDocument(data: try pdfData(snapshot))
            showPDFExporter = true
        } catch { store.errorMessage = error.localizedDescription }
    }

    private var filename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "FinanzVerwalter-Kontosalden-\(formatter.string(from: asOf))"
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

private struct ReportHTMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.html] }
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

private extension UTType {
    static let finanzVerwalterXLSX = UTType(filenameExtension: "xlsx")
        ?? UTType(
            importedAs: "org.openxmlformats.spreadsheetml.sheet",
            conformingTo: .zip
        )
}

private struct ReportXLSXDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.finanzVerwalterXLSX] }
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
    @State private var pendingCSVData: Data?
    @State private var pendingCSVName = ""
    @State private var pendingCSVProfile = CSVImportProfile()
    @State private var showCSVProfileAssistant = false
    @State private var csvProfiles: [CSVImportProfile] = []
    @State private var qifPackagePreview: QIFPackagePreview?
    @State private var bankStatementPackage: BankStatementPackage?
    @State private var bankStatementMappings: [String: UUID] = [:]
    @State private var importResolutions: [UUID: ImportResolution] = [:]
    @State private var showBackupExporter = false
    @State private var backupDocument = BackupDocument(data: Data())
    @State private var showRestoreImporter = false
    @State private var stagedRestoreURL: URL?
    @State private var restorePreview: FinanceBackupPreview?
    @State private var restoreSourceName: String?
    @State private var confirmRestore = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Import, Export & Sicherung").font(.largeTitle.bold())

                GroupBox("CSV-/TSV-, QIF- und Kontoauszugsimport") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CSV/TSV und einzelne QIF-Kontoblätter benötigen ein Zielkonto. Vollständige QIF-Pakete sowie OFX/QFX-, MT940- und camt-Kontoauszüge werden kontoweise vorbereitet.")
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
                        Text("Bei Mehrkonten-QIF und Kontoauszugsformaten ist keine vorherige Kontoauswahl nötig.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                if let package = bankStatementPackage {
                    GroupBox("\(package.format.rawValue)-Kontenzuordnung") {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(
                                "\(package.accounts.count) externe Konten · \(package.records.count) Buchungen erkannt",
                                systemImage: "building.columns"
                            )
                            Text("Ordnen Sie jedes externe Konto einem vorhandenen FinanzVerwalter-Konto zu. Erst danach wird die Treffer- und Duplikatprüfung ausgeführt.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            ForEach(package.accounts) { external in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(external.displayName)
                                        Text("\(external.accountType.isEmpty ? "Konto" : external.accountType) · \(external.currency)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Picker(
                                        "Zielkonto",
                                        selection: Binding(
                                            get: { bankStatementMappings[external.id] },
                                            set: { bankStatementMappings[external.id] = $0 }
                                        )
                                    ) {
                                        Text("Nicht zugeordnet").tag(UUID?.none)
                                        ForEach(store.accounts.filter {
                                            $0.currency.caseInsensitiveCompare(external.currency) == .orderedSame
                                        }) { account in
                                            Text(account.name).tag(UUID?.some(account.id))
                                        }
                                    }
                                    .frame(width: 300)
                                }
                            }
                            ForEach(package.rejectedRows, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                            HStack {
                                Button("Verwerfen") {
                                    bankStatementPackage = nil
                                    bankStatementMappings = [:]
                                    preview = nil
                                }
                                Button("Vorschau und Abgleich erstellen") {
                                    preview = store.previewBankStatement(
                                        package,
                                        mappings: bankStatementMappings,
                                        dateWindowDays: importMatchDateWindowDays
                                    )
                                    if let preview { prepareResolutions(preview) }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(package.accounts.contains {
                                    bankStatementMappings[$0.id] == nil
                                })
                            }
                        }
                        .padding(8)
                    }
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
                            if !preview.rejectedRows.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(Array(preview.rejectedRows.prefix(10)), id: \.self) { reason in
                                        Label(reason, systemImage: "exclamationmark.triangle")
                                            .foregroundStyle(.orange)
                                            .textSelection(.enabled)
                                    }
                                    if preview.rejectedRows.count > 10 {
                                        Text("… und \(preview.rejectedRows.count - 10) weitere Ablehnungen")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
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
                                        bankStatementPackage = nil
                                        bankStatementMappings = [:]
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(preview.rows.isEmpty)
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
                UTType(filenameExtension: "qif") ?? .data,
                UTType(filenameExtension: "ofx") ?? .data,
                UTType(filenameExtension: "qfx") ?? .data,
                UTType(filenameExtension: "sta") ?? .data,
                UTType(filenameExtension: "mt940") ?? .data,
                UTType(filenameExtension: "c53") ?? .data,
                UTType(filenameExtension: "c54") ?? .data,
                .xml
            ]
        ) { result in
            guard
                let url = try? result.get(),
                url.startAccessingSecurityScopedResource()
            else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { return }
            let fileExtension = url.pathExtension.lowercased()
            if ["ofx", "qfx", "sta", "mt940", "c53", "c54", "xml"]
                .contains(fileExtension) {
                let format: BankStatementFormat
                switch fileExtension {
                case "qfx": format = .qfx
                case "sta", "mt940": format = .mt940
                case "c53", "c54", "xml": format = .camt
                default: format = .ofx
                }
                bankStatementPackage = store.parseBankStatement(
                    data: data,
                    format: format
                )
                bankStatementMappings = [:]
                preview = nil
                qifPackagePreview = nil
                if let package = bankStatementPackage {
                    autoMapBankStatement(package)
                }
            } else if fileExtension == "qif" {
                bankStatementPackage = nil
                bankStatementMappings = [:]
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
                    bankStatementPackage = nil
                    if let preview { prepareResolutions(preview) }
                } else {
                    store.errorMessage = FinanceError.missingAccount.localizedDescription
                }
            } else if selectedAccountID != nil {
                do {
                    pendingCSVData = data
                    pendingCSVName = url.lastPathComponent
                    pendingCSVProfile = try CSVFinanceImporter.suggestedProfile(
                        data: data
                    )
                    qifPackagePreview = nil
                    bankStatementPackage = nil
                    preview = nil
                    showCSVProfileAssistant = true
                } catch {
                    store.errorMessage = error.localizedDescription
                }
            } else {
                store.errorMessage = FinanceError.missingAccount.localizedDescription
            }
        }
        .sheet(isPresented: $showCSVProfileAssistant) {
            if let pendingCSVData, let selectedAccountID,
               let account = store.accounts.first(where: { $0.id == selectedAccountID }) {
                CSVImportProfileAssistant(
                    data: pendingCSVData,
                    fileName: pendingCSVName,
                    account: account,
                    initialProfile: pendingCSVProfile,
                    profiles: $csvProfiles,
                    cancel: {
                        clearPendingCSV()
                        showCSVProfileAssistant = false
                    },
                    importPreview: { profile in
                        guard let result = store.importCSV(
                            data: pendingCSVData,
                            accountID: selectedAccountID,
                            profile: profile,
                            dateWindowDays: importMatchDateWindowDays
                        ) else { return }
                        preview = result
                        prepareResolutions(result)
                        clearPendingCSV()
                        showCSVProfileAssistant = false
                    }
                )
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
                cleanupStagedRestore()
                try FileManager.default.copyItem(at: source, to: staged)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: staged.path
                )
                let preview = try SQLiteFinanceStore.backupPreview(at: staged)
                stagedRestoreURL = staged
                restorePreview = preview
                restoreSourceName = source.lastPathComponent
                confirmRestore = true
            } catch {
                try? FileManager.default.removeItem(at: staged)
                cleanupStagedRestore()
                store.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $confirmRestore, onDismiss: cleanupStagedRestore) {
            if let restorePreview {
                RestoreBackupPreviewSheet(
                    preview: restorePreview,
                    sourceName: restoreSourceName ?? restorePreview.url.lastPathComponent,
                    cancel: { confirmRestore = false },
                    restore: {
                        if let stagedRestoreURL {
                            _ = store.restoreBackup(from: stagedRestoreURL)
                        }
                        confirmRestore = false
                    }
                )
            }
        }
        .onAppear(perform: loadCSVProfiles)
        .onChange(of: csvProfiles) { persistCSVProfiles() }
    }

    private func clearPendingCSV() {
        pendingCSVData = nil
        pendingCSVName = ""
    }

    private func loadCSVProfiles() {
        guard let data = UserDefaults.standard.data(
            forKey: "csvImportProfilesV1"
        ) else { return }
        do {
            csvProfiles = try CSVImportProfileLibrary.decode(data)
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func persistCSVProfiles() {
        do {
            UserDefaults.standard.set(
                try CSVImportProfileLibrary.encode(csvProfiles),
                forKey: "csvImportProfilesV1"
            )
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func cleanupStagedRestore() {
        if let stagedRestoreURL {
            try? FileManager.default.removeItem(at: stagedRestoreURL)
        }
        stagedRestoreURL = nil
        restorePreview = nil
        restoreSourceName = nil
    }

    private func autoMapBankStatement(_ package: BankStatementPackage) {
        for external in package.accounts {
            let number = external.accountNumber
            let candidates = store.accounts.filter { account in
                account.currency.caseInsensitiveCompare(external.currency) == .orderedSame
                    && !number.isEmpty
                    && (
                        account.iban.replacingOccurrences(of: " ", with: "").hasSuffix(number)
                            || account.accountNumberMasked.hasSuffix(String(number.suffix(4)))
                    )
            }
            if candidates.count == 1 {
                bankStatementMappings[external.id] = candidates[0].id
            } else if package.accounts.count == 1,
                      let selectedAccountID,
                      store.accounts.first(where: { $0.id == selectedAccountID })?.currency
                        .caseInsensitiveCompare(external.currency) == .orderedSame {
                bankStatementMappings[external.id] = selectedAccountID
            }
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

private struct CSVImportProfileAssistant: View {
    let data: Data
    let fileName: String
    let account: FinanceAccount
    @Binding var profiles: [CSVImportProfile]
    let cancel: () -> Void
    let importPreview: (CSVImportProfile) -> Void
    private let detectedProfile: CSVImportProfile

    @State private var profile: CSVImportProfile
    @State private var selectedProfileID: UUID?
    @State private var inspection: CSVImportInspection?
    @State private var inspectionError = ""

    init(
        data: Data,
        fileName: String,
        account: FinanceAccount,
        initialProfile: CSVImportProfile,
        profiles: Binding<[CSVImportProfile]>,
        cancel: @escaping () -> Void,
        importPreview: @escaping (CSVImportProfile) -> Void
    ) {
        self.data = data
        self.fileName = fileName
        self.account = account
        self._profiles = profiles
        self.cancel = cancel
        self.importPreview = importPreview
        self.detectedProfile = initialProfile
        _profile = State(initialValue: initialProfile)
    }

    private var mappedFields: [CSVImportField] {
        CSVImportField.allCases.filter { field in
            switch (profile.amountMode, field) {
            case (.signed, .debit), (.signed, .credit): false
            case (.debitCredit, .amount): false
            default: true
            }
        }
    }

    private var canPreview: Bool {
        guard validColumn(for: .bookingDate) else {
            return false
        }
        switch profile.amountMode {
        case .signed:
            return validColumn(for: .amount)
        case .debitCredit:
            return validColumn(for: .debit) || validColumn(for: .credit)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CSV-/TSV-Profilassistent")
                        .font(.title2.bold())
                    Text("\(fileName) → \(account.name) (\(account.currency))")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Text("\(inspection?.rowCount ?? 0) Datenzeilen")
                    .font(.headline.monospacedDigit())
            }
            .padding(18)
            Divider()

            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        GroupBox("Gespeichertes Profil") {
                            VStack(alignment: .leading, spacing: 10) {
                                Picker("Profil laden", selection: $selectedProfileID) {
                                    Text("Automatisch erkannt").tag(UUID?.none)
                                    ForEach(profiles) { saved in
                                        Text("\(saved.name) · Revision \(saved.revision)")
                                            .tag(UUID?.some(saved.id))
                                    }
                                }
                                .accessibilityIdentifier("csvProfilePicker")
                                .onChange(of: selectedProfileID) {
                                    if let selectedProfileID,
                                       let saved = profiles.first(where: {
                                           $0.id == selectedProfileID
                                       }) {
                                        profile = saved
                                    } else {
                                        profile = detectedProfile
                                    }
                                }
                                TextField("Profilname", text: $profile.name)
                                    .accessibilityIdentifier("csvProfileName")
                                HStack {
                                    Button("Profil speichern", systemImage: "square.and.arrow.down") {
                                        saveProfile()
                                    }
                                    .disabled(
                                        profile.name.trimmingCharacters(
                                            in: .whitespacesAndNewlines
                                        ).isEmpty
                                    )
                                    Button("Profil löschen", role: .destructive) {
                                        deleteSelectedProfile()
                                    }
                                    .disabled(selectedProfileID == nil)
                                }
                                Text(
                                    "Profile werden versioniert lokal gespeichert und enthalten keine Buchungsdaten."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(6)
                        }

                        GroupBox("Dateiformat") {
                            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                                GridRow {
                                    Text("Encoding")
                                    Picker("Encoding", selection: $profile.encoding) {
                                        ForEach(CSVImportEncoding.allCases, id: \.self) {
                                            Text($0.title).tag($0)
                                        }
                                    }
                                    .labelsHidden()
                                }
                                GridRow {
                                    Text("Trennzeichen")
                                    Picker("Trennzeichen", selection: $profile.separator) {
                                        ForEach(CSVImportSeparator.allCases, id: \.self) {
                                            Text($0.title).tag($0)
                                        }
                                    }
                                    .labelsHidden()
                                }
                                GridRow {
                                    Text("Kopfzeile")
                                    Toggle("Erste Zeile enthält Feldnamen", isOn: $profile.hasHeader)
                                }
                                GridRow {
                                    Text("Datumsformat")
                                    Picker("Datumsformat", selection: $profile.dateFormat) {
                                        ForEach(CSVImportDateFormat.allCases, id: \.self) {
                                            Text($0.title).tag($0)
                                        }
                                    }
                                    .labelsHidden()
                                }
                                GridRow {
                                    Text("Betragsaufbau")
                                    Picker("Betragsaufbau", selection: $profile.amountMode) {
                                        ForEach(CSVImportAmountMode.allCases, id: \.self) {
                                            Text($0.title).tag($0)
                                        }
                                    }
                                    .labelsHidden()
                                }
                                GridRow {
                                    Text("Dezimalzeichen")
                                    Picker("Dezimalzeichen", selection: $profile.decimalSeparator) {
                                        Text("Komma").tag(",")
                                        Text("Punkt").tag(".")
                                    }
                                    .labelsHidden()
                                }
                                GridRow {
                                    Text("Tausenderzeichen")
                                    Picker("Tausenderzeichen", selection: $profile.thousandsSeparator) {
                                        Text("Keines").tag("")
                                        Text("Punkt").tag(".")
                                        Text("Komma").tag(",")
                                    }
                                    .labelsHidden()
                                }
                            }
                            .padding(6)
                        }

                        GroupBox("Feldzuordnung") {
                            VStack(spacing: 8) {
                                ForEach(mappedFields) { field in
                                    HStack {
                                        Text(field.title)
                                            .frame(width: 180, alignment: .leading)
                                        if field == .bookingDate || field == .amount {
                                            Text("Pflicht")
                                                .font(.caption2)
                                                .foregroundStyle(.orange)
                                        } else if field == .debit || field == .credit {
                                            Text("Mind. eins")
                                                .font(.caption2)
                                                .foregroundStyle(.orange)
                                        }
                                        Spacer()
                                        Picker(
                                            field.title,
                                            selection: Binding(
                                                get: { profile.column(for: field) },
                                                set: { profile.setColumn($0, for: field) }
                                            )
                                        ) {
                                            Text("Nicht übernehmen").tag(Int?.none)
                                            ForEach(
                                                Array((inspection?.columns ?? []).enumerated()),
                                                id: \.offset
                                            ) { index, name in
                                                Text("\(index + 1): \(name)")
                                                    .tag(Int?.some(index))
                                            }
                                        }
                                        .labelsHidden()
                                        .frame(width: 260)
                                    }
                                }
                            }
                            .padding(6)
                        }
                    }
                    .padding(16)
                }
                .frame(minWidth: 500, idealWidth: 540)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Rohdatenvorschau")
                        .font(.headline)
                    if !inspectionError.isEmpty {
                        ContentUnavailableView(
                            "Datei kann nicht gelesen werden",
                            systemImage: "exclamationmark.triangle",
                            description: Text(inspectionError)
                        )
                    } else if let inspection {
                        ScrollView([.horizontal, .vertical]) {
                            Grid(
                                alignment: .leading,
                                horizontalSpacing: 18,
                                verticalSpacing: 7
                            ) {
                                GridRow {
                                    ForEach(Array(inspection.columns.enumerated()), id: \.offset) {
                                        Text("\($0.offset + 1): \($0.element)")
                                            .font(.caption.bold())
                                            .lineLimit(1)
                                    }
                                }
                                Divider()
                                ForEach(Array(inspection.sampleRows.enumerated()), id: \.offset) { row in
                                    GridRow {
                                        ForEach(Array(inspection.columns.indices), id: \.self) { column in
                                            Text(column < row.element.count ? row.element[column] : "")
                                                .lineLimit(2)
                                                .frame(maxWidth: 260, alignment: .leading)
                                        }
                                    }
                                }
                            }
                            .textSelection(.enabled)
                            .padding(10)
                        }
                        .background(
                            Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    } else {
                        ProgressView()
                    }
                    Text(
                        "Nach dem nächsten Schritt erscheinen gültige Buchungen, zeilengenaue Fehler und mögliche Dubletten vor jeder Übernahme."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            HStack {
                Button("Abbrechen", role: .cancel, action: cancel)
                Spacer()
                if !canPreview {
                    Text("Buchungsdatum und Betrag beziehungsweise Soll/Haben zuordnen")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button("Importvorschau erstellen") {
                    importPreview(profile)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canPreview)
                .accessibilityIdentifier("csvCreateImportPreview")
            }
            .padding(16)
        }
        .frame(minWidth: 960, minHeight: 700)
        .onAppear(perform: refreshInspection)
        .onChange(of: profile) { refreshInspection() }
        .onChange(of: profile.decimalSeparator) {
            if profile.thousandsSeparator == profile.decimalSeparator {
                profile.thousandsSeparator = profile.decimalSeparator == ","
                    ? "." : ","
            }
        }
        .interactiveDismissDisabled()
    }

    private func validColumn(for field: CSVImportField) -> Bool {
        guard let inspection, let column = profile.column(for: field) else {
            return false
        }
        return inspection.columns.indices.contains(column)
    }

    private func refreshInspection() {
        do {
            inspection = try CSVFinanceImporter.inspect(
                data: data, profile: profile
            )
            inspectionError = ""
        } catch {
            inspection = nil
            inspectionError = error.localizedDescription
        }
    }

    private func saveProfile() {
        profile.name = profile.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        profiles = CSVImportProfileLibrary.upserting(profile, into: profiles)
        if let saved = profiles.first(where: { $0.id == profile.id }) {
            profile = saved
            selectedProfileID = saved.id
        }
    }

    private func deleteSelectedProfile() {
        guard let selectedProfileID else { return }
        profiles.removeAll { $0.id == selectedProfileID }
        self.selectedProfileID = nil
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
    @AppStorage(AutomaticBackupPreferences.enabledKey)
    private var automaticBackupEnabled = true
    @AppStorage(AutomaticBackupPreferences.intervalHoursKey)
    private var automaticBackupIntervalHours = 24
    @AppStorage(AutomaticBackupPreferences.maximumCountKey)
    private var automaticBackupMaximumCount = 14
    @AppStorage(AutomaticBackupPreferences.maximumAgeDaysKey)
    private var automaticBackupMaximumAgeDays = 90
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
            Section("Automatische Datensicherung") {
                Toggle("Automatische Sicherungen aktivieren", isOn: $automaticBackupEnabled)
                Picker("Mindestabstand", selection: $automaticBackupIntervalHours) {
                    Text("1 Stunde").tag(1)
                    Text("6 Stunden").tag(6)
                    Text("12 Stunden").tag(12)
                    Text("Täglich").tag(24)
                    Text("Alle 3 Tage").tag(72)
                    Text("Wöchentlich").tag(168)
                }
                .disabled(!automaticBackupEnabled)
                Stepper(
                    "Höchstens \(automaticBackupMaximumCount) Sicherungen",
                    value: $automaticBackupMaximumCount,
                    in: 1...100
                )
                .disabled(!automaticBackupEnabled)
                Stepper(
                    "Aufbewahrung höchstens \(automaticBackupMaximumAgeDays) Tage",
                    value: $automaticBackupMaximumAgeDays,
                    in: 1...3_650
                )
                .disabled(!automaticBackupEnabled)
                LabeledContent("Status", value: store.automaticBackupStatusText)
                if let directory = store.automaticBackupDirectory {
                    LabeledContent("Ordner") {
                        Text(directory.path(percentEncoded: false))
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                }
                Button("Jetzt geprüfte Autosicherung erstellen") {
                    _ = store.createAutomaticBackup(
                        force: true,
                        policy: AutomaticBackupPolicy(
                            isEnabled: automaticBackupEnabled,
                            minimumIntervalHours: automaticBackupIntervalHours,
                            maximumBackupCount: automaticBackupMaximumCount,
                            maximumAgeDays: automaticBackupMaximumAgeDays
                        )
                    )
                }
                Text(
                    "Beim Start und Beenden wird nur gesichert, wenn die Finanzdatei seit der letzten Sicherung geändert wurde und der Mindestabstand abgelaufen ist. Vor jeder Schema-Migration entsteht unabhängig davon eine eigene geprüfte Sicherung."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
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
                ForEach(store.tagsByPath) { tag in
                    Button {
                        editedTag = tag
                    } label: {
                        LabeledContent(
                            store.tagPath(tag.id),
                            value: tag.isActive ? "Aktiv" : "Inaktiv"
                        )
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

enum CategoryHierarchyFilter {
    static func visibleIDs(
        categories: [FinanceCategory],
        searchText: String,
        includeInactive: Bool
    ) -> Set<UUID> {
        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let tokens = normalized(searchText)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        var visible = Set<UUID>()
        for category in categories where includeInactive || category.isActive {
            let searchable = normalized(
                [
                    path(for: category, byID: byID), category.description,
                    category.kind.title, category.germanTaxLine, category.usTaxLine
                ].joined(separator: " ")
            )
            guard tokens.allSatisfy(searchable.contains) else { continue }
            var currentID: UUID? = category.id
            var visited = Set<UUID>()
            while let id = currentID, visited.insert(id).inserted {
                visible.insert(id)
                currentID = byID[id]?.parentID
            }
        }
        return visible
    }

    static func path(
        for category: FinanceCategory,
        categories: [FinanceCategory]
    ) -> String {
        path(
            for: category,
            byID: Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        )
    }

    private static func path(
        for category: FinanceCategory,
        byID: [UUID: FinanceCategory]
    ) -> String {
        var names = [category.name]
        var parentID = category.parentID
        var visited = Set<UUID>([category.id])
        while let id = parentID,
              visited.insert(id).inserted,
              let parent = byID[id] {
            names.append(parent.name)
            parentID = parent.parentID
        }
        return names.reversed().joined(separator: ":")
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "de_DE")
        )
    }
}

struct CategoriesView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var selectedID: UUID?
    @State private var editedCategory: FinanceCategory?
    @State private var searchText = ""
    @State private var includeInactive = true

    private var selected: FinanceCategory? {
        store.categories.first { $0.id == selectedID }
    }
    private var roots: [FinanceCategory] {
        store.categories.filter { $0.parentID == nil }.sorted {
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    private var visibleIDs: Set<UUID> {
        CategoryHierarchyFilter.visibleIDs(
            categories: store.categories,
            searchText: searchText,
            includeInactive: includeInactive
        )
    }
    private var visibleRoots: [FinanceCategory] {
        roots.filter { visibleIDs.contains($0.id) }
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
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    "Name, vollständiger Pfad, Beschreibung oder Steuerzuordnung",
                    text: $searchText
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("categorySearchField")
                if !searchText.isEmpty {
                    Button("Suche leeren", systemImage: "xmark.circle.fill") {
                        searchText = ""
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                }
                Toggle("Inaktive anzeigen", isOn: $includeInactive)
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("categoryIncludeInactiveToggle")
                    .help(
                        "Blendet inaktive Kategorien ein. Inaktive Oberkategorien "
                            + "bleiben als Pfad sichtbar, wenn darunter eine aktive "
                            + "Kategorie gefunden wird."
                    )
                Text("\(visibleIDs.count) von \(store.categories.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        "\(visibleIDs.count) von \(store.categories.count) Kategorien sichtbar"
                    )
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            Divider()
            HSplitView {
                List(selection: $selectedID) {
                    if visibleRoots.isEmpty {
                        ContentUnavailableView(
                            "Keine Kategorien gefunden",
                            systemImage: "magnifyingglass",
                            description: Text(
                                includeInactive
                                    ? "Ändere den Suchtext."
                                    : "Ändere den Suchtext oder zeige inaktive Kategorien an."
                            )
                        )
                        .listRowSeparator(.hidden)
                    }
                    ForEach(CategoryKind.allCases, id: \.self) { kind in
                        Section(kind.title) {
                            ForEach(visibleRoots.filter { $0.kind == kind }) { category in
                                CategoryTreeRows(
                                    category: category,
                                    selectedID: $selectedID,
                                    visibleIDs: visibleIDs,
                                    showFullPath: !searchText.isEmpty
                                )
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
            if selectedID == nil { selectedID = visibleRoots.first?.id }
        }
        .onChange(of: visibleIDs) {
            if let selectedID, !visibleIDs.contains(selectedID) {
                self.selectedID = visibleRoots.first?.id
            }
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
    let visibleIDs: Set<UUID>
    let showFullPath: Bool

    private var children: [FinanceCategory] {
        store.categories.filter {
            $0.parentID == category.id && visibleIDs.contains($0.id)
        }.sorted {
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
                    CategoryTreeRows(
                        category: child,
                        selectedID: $selectedID,
                        visibleIDs: visibleIDs,
                        showFullPath: showFullPath
                    )
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
            VStack(alignment: .leading, spacing: 1) {
                Text(category.name)
                if showFullPath {
                    Text(store.categoryPath(category.id))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(store.categoryPath(category.id))
                }
            }
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
                    ForEach(store.tagsByPath.filter { $0.id != value.id }) {
                        Text(store.tagPath($0.id)).tag(Optional($0.id))
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
    @State private var editedBankAccount: FinancePayeeBankAccount?
    @State private var editedMandate: FinanceSEPAMandate?

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
                    TextField("SEPA-Gläubiger-ID", text: $value.creditorID)
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
                    if !store.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Standardklassen/Tags")
                            ScrollView(.horizontal) {
                                HStack {
                                    ForEach(store.tagsByPath.filter {
                                        $0.isActive
                                            || value.defaultTagIDs.contains($0.id)
                                    }) { tag in
                                        Toggle(
                                            store.tagPath(tag.id)
                                                + (tag.isActive ? "" : " (inaktiv)"),
                                            isOn: Binding(
                                                get: {
                                                    value.defaultTagIDs.contains(tag.id)
                                                },
                                                set: { selected in
                                                    if selected {
                                                        if !value.defaultTagIDs.contains(tag.id) {
                                                            value.defaultTagIDs.append(tag.id)
                                                        }
                                                    } else {
                                                        value.defaultTagIDs.removeAll {
                                                            $0 == tag.id
                                                        }
                                                    }
                                                }
                                            )
                                        )
                                        .toggleStyle(.button)
                                    }
                                }
                            }
                        }
                    }
                }
                Section("Bankverbindungen") {
                    Button("Bankverbindung anlegen", systemImage: "plus") {
                        editedBankAccount = FinancePayeeBankAccount(
                            id: UUID(), payeeID: value.id,
                            label: "Neue Bankverbindung",
                            accountHolder: value.canonicalName,
                            iban: "", bic: "", bankName: "",
                            isDefault: store.payeeBankAccounts.allSatisfy {
                                $0.payeeID != value.id || !$0.isActive
                            },
                            isActive: true
                        )
                    }
                    .disabled(!store.payees.contains { $0.id == value.id })
                    .help(
                        store.payees.contains { $0.id == value.id }
                            ? "Neue Bankverbindung für diese Empfängerakte"
                            : "Speichere die neue Empfängerakte zuerst und öffne sie anschließend erneut."
                    )
                    ForEach(store.payeeBankAccounts.filter {
                        $0.payeeID == value.id
                    }) { bankAccount in
                        Button {
                            editedBankAccount = bankAccount
                        } label: {
                            LabeledContent(
                                bankAccount.label,
                                value: bankAccount.iban
                                    + (bankAccount.isDefault ? " · Standard" : "")
                                    + (bankAccount.isActive ? "" : " · Inaktiv")
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if store.payeeBankAccounts.allSatisfy({
                        $0.payeeID != value.id
                    }) {
                        Text("Noch keine Bankverbindung vorhanden.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("SEPA-Mandate") {
                    Button("Mandat anlegen", systemImage: "plus") {
                        editedMandate = FinanceSEPAMandate(
                            id: UUID(), payeeID: value.id, reference: "",
                            signedOn: Date(), sequenceType: .recurring,
                            note: "", isActive: true
                        )
                    }
                    .disabled(!store.payees.contains { $0.id == value.id })
                    .help(
                        store.payees.contains { $0.id == value.id }
                            ? "Neues SEPA-Mandat für diese Empfängerakte"
                            : "Speichere die neue Empfängerakte zuerst und öffne sie anschließend erneut."
                    )
                    ForEach(store.sepaMandates.filter {
                        $0.payeeID == value.id
                    }) { mandate in
                        Button {
                            editedMandate = mandate
                        } label: {
                            LabeledContent(
                                mandate.reference,
                                value: mandate.sequenceType.title
                                    + (mandate.isActive ? " · Aktiv" : " · Inaktiv")
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if store.sepaMandates.allSatisfy({
                        $0.payeeID != value.id
                    }) {
                        Text("Noch kein Mandat vorhanden.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 680, height: 720)
        .sheet(item: $editedBankAccount) {
            PayeeBankAccountEditor(value: $0)
        }
        .sheet(item: $editedMandate) {
            SEPAMandateEditor(value: $0)
        }
    }
}

private struct PayeeBankAccountEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    @State private var value: FinancePayeeBankAccount

    init(value: FinancePayeeBankAccount) {
        _value = State(initialValue: value)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Empfänger-Bankverbindung")
                    .font(.title2.bold())
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Speichern") {
                    if store.savePayeeBankAccount(value) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    value.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || value.accountHolder.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                        || value.iban.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                )
            }
            .padding(14)
            Divider()
            Form {
                TextField("Bezeichnung", text: $value.label)
                TextField("Kontoinhaber", text: $value.accountHolder)
                TextField("IBAN", text: $value.iban)
                TextField("BIC (optional)", text: $value.bic)
                TextField("Bankname (optional)", text: $value.bankName)
                Toggle("Standardverbindung", isOn: $value.isDefault)
                    .disabled(!value.isActive)
                Toggle("Aktiv", isOn: $value.isActive)
                    .onChange(of: value.isActive) {
                        if !value.isActive { value.isDefault = false }
                    }
                Text(
                    "Genau eine aktive Verbindung wird als Standard geführt. "
                        + "Zahlungsaufträge speichern zusätzlich einen unveränderlichen "
                        + "Schnappschuss aus Name, IBAN und BIC."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
        }
        .frame(width: 560, height: 500)
    }
}

private struct SEPAMandateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    @State private var value: FinanceSEPAMandate
    @State private var hasSignedOn: Bool
    @State private var signedOn: Date

    init(value: FinanceSEPAMandate) {
        _value = State(initialValue: value)
        _hasSignedOn = State(initialValue: value.signedOn != nil)
        _signedOn = State(initialValue: value.signedOn ?? Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SEPA-Mandat").font(.title2.bold())
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Speichern") {
                    value.signedOn = hasSignedOn ? signedOn : nil
                    if store.saveSEPAMandate(value) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
            Divider()
            Form {
                TextField("Mandatsreferenz", text: $value.reference)
                Toggle("Unterschriftsdatum vorhanden", isOn: $hasSignedOn)
                if hasSignedOn {
                    DatePicker(
                        "Unterschrieben am",
                        selection: $signedOn,
                        displayedComponents: .date
                    )
                }
                Picker("Sequenztyp", selection: $value.sequenceType) {
                    ForEach(SEPAMandateSequenceType.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                TextField("Notiz", text: $value.note)
                Toggle("Aktiv", isOn: $value.isActive)
            }
            .formStyle(.grouped)
        }
        .frame(width: 560, height: 390)
    }
}

struct RulesView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var selectedID: UUID?
    @State private var draft: CategorizationRule?
    @State private var previewRule: CategorizationRule?
    @State private var confirmUndo = false

    var body: some View {
        let allConflicts = store.ruleConflicts
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Regeln").font(.title2.bold())
                    Spacer()
                    if let undo = store.latestRuleUndo {
                        Button("Undo \(undo.transactionCount)", systemImage: "arrow.uturn.backward") {
                            confirmUndo = true
                        }
                        .help(
                            "Letzte Regelanwendung „\(undo.ruleName)“ "
                                + "vollständig zurücknehmen"
                        )
                    }
                    Button {
                        guard let category = store.categories.first else { return }
                        let condition = RuleCondition(
                            field: .payee,
                            operation: .contains
                        )
                        draft = CategorizationRule(
                            id: UUID(), name: "Neue Regel",
                            priority: (store.categorizationRules.map(\.priority).max() ?? 0) + 10,
                            isActive: true, stopAfterMatch: true,
                            payeeContains: "", purposeContains: "",
                            minimumAmountMinor: nil, maximumAmountMinor: nil,
                            categoryID: category.id,
                            expression: .group(
                                .all,
                                [.condition(condition)]
                            ),
                            actions: [.setCategory(category.id)]
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
                            let conflicts = allConflicts.filter {
                                $0.ruleNames.contains(rule.name)
                            }.count
                            if conflicts > 0 {
                                Text("\(conflicts)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .background(.orange, in: Capsule())
                                    .help("Mögliche Konflikte mit anderen Regeln")
                            }
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
                    previewRule: $previewRule
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
        .sheet(item: $previewRule) { rule in
            RuleApplicationPreviewSheet(rule: rule)
                .environmentObject(store)
        }
        .alert("Letzte Regelanwendung zurücknehmen?", isPresented: $confirmUndo) {
            Button("Abbrechen", role: .cancel) {}
            Button("Vollständig zurücknehmen", role: .destructive) {
                _ = store.undoLatestRuleApplication()
            }
        } message: {
            if let undo = store.latestRuleUndo {
                Text(
                    "\(undo.transactionCount) Buchungen aus „\(undo.ruleName)“ "
                        + "werden atomar auf den vorherigen Stand gesetzt. "
                        + "Zwischenzeitliche Änderungen brechen das gesamte Undo ab."
                )
            }
        }
    }
}

private struct RuleEditor: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Binding var rule: CategorizationRule
    @Binding var previewRule: CategorizationRule?

    var body: some View {
        Form {
            Section("Regel") {
                TextField("Name", text: $rule.name)
                Stepper("Priorität: \(rule.priority)", value: $rule.priority, in: 0...10_000)
                Toggle("Aktiv", isOn: $rule.isActive)
                Toggle("Nach Treffer stoppen", isOn: $rule.stopAfterMatch)
            }
            Section("Bedingungsgruppe") {
                Picker("Verknüpfung", selection: rootLogicBinding) {
                    ForEach(RuleGroupLogic.allCases) {
                        Text($0.title).tag($0)
                    }
                }
                ForEach(rootConditions) { condition in
                    HStack {
                        Picker(
                            "Feld",
                            selection: conditionBinding(condition.id).field
                        ) {
                            ForEach(RuleField.allCases) {
                                Text($0.title).tag($0)
                            }
                        }
                        Picker(
                            "Operator",
                            selection: conditionBinding(condition.id).operation
                        ) {
                            ForEach(RuleOperator.allCases) {
                                Text($0.title).tag($0)
                            }
                        }
                        if condition.operation.needsValue {
                            TextField(
                                condition.field == .amount
                                    ? "Centbetrag" : "Wert",
                                text: conditionBinding(condition.id).value
                            )
                        }
                        if condition.operation.needsSecondValue {
                            TextField(
                                condition.field == .amount
                                    ? "Bis Cent" : "Bis",
                                text: conditionBinding(condition.id)
                                    .secondValue
                            )
                        }
                        Button(role: .destructive) {
                            removeCondition(condition.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("Bedingung hinzufügen", systemImage: "plus") {
                    appendCondition()
                }
                Text(
                    "Regex-Ausdrücke werden vor dem Schreiben nur für die "
                        + "Vorschau ausgewertet. Leere Gruppen treffen alle "
                        + "änderbaren Buchungen."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section("Aktion") {
                Picker("Kategorie setzen", selection: categoryActionBinding) {
                    ForEach(store.categoriesByPath.filter(\.isActive)) {
                        Text(store.categoryPath($0.id)).tag($0.id)
                    }
                }
                TextField(
                    "Empfänger normalisieren (optional)",
                    text: textActionBinding(
                        read: {
                            if case .normalizePayee(let value) = $0 {
                                return value
                            }
                            return nil
                        },
                        make: RuleAction.normalizePayee
                    )
                )
                TextField(
                    "Notiz setzen (optional)",
                    text: textActionBinding(
                        read: {
                            if case .setMemo(let value) = $0 { return value }
                            return nil
                        },
                        make: RuleAction.setMemo
                    )
                )
                Toggle(
                    "Verwendungszweck in Notiz kopieren",
                    isOn: booleanActionBinding(.copyPurposeToMemo)
                )
                HStack {
                    TextField(
                        "Text im Verwendungszweck",
                        text: purposeReplacementSearchBinding
                    )
                    TextField(
                        "Ersetzen durch",
                        text: purposeReplacementValueBinding
                    )
                    Toggle(
                        "Regex",
                        isOn: purposeReplacementRegexBinding
                    )
                    .toggleStyle(.checkbox)
                }
                Menu {
                    ForEach(store.tagsByPath.filter(\.isActive)) { tag in
                        Toggle(
                            store.tagPath(tag.id),
                            isOn: tagActionBinding(tag.id)
                        )
                    }
                } label: {
                    Label(
                        tagActionIDs.isEmpty
                            ? "Klassen/Tags ergänzen"
                            : "\(tagActionIDs.count) Klassen/Tags ergänzen",
                        systemImage: "tag"
                    )
                }
                Toggle(
                    "Statt einfacher Kategorie einen vollständigen "
                        + "Einzeilen-Split erzeugen",
                    isOn: splitActionBinding
                )
                Text(
                    "Split-Erzeugung ist nur bei ungeteilten Buchungen ohne "
                        + "MwSt. zulässig; andernfalls erscheint sie nicht in "
                        + "der anwendbaren Vorschau."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
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
                    previewRule = rule
                }
                .disabled(!rule.isActive || store.rulePreviewCount(rule) == 0)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Regel bearbeiten")
    }

    private var rootLogicBinding: Binding<RuleGroupLogic> {
        Binding(
            get: {
                if case .group(let logic, _) = rule.effectiveExpression {
                    return logic
                }
                return .all
            },
            set: { newValue in
                rule.expression = .group(
                    newValue,
                    rootConditions.map(RuleExpression.condition)
                )
            }
        )
    }

    private var rootConditions: [RuleCondition] {
        guard case .group(_, let children) = rule.effectiveExpression else {
            return []
        }
        return children.compactMap {
            if case .condition(let value) = $0 { return value }
            return nil
        }
    }

    private func conditionBinding(
        _ id: UUID
    ) -> Binding<RuleCondition> {
        Binding(
            get: {
                rootConditions.first { $0.id == id }
                    ?? RuleCondition(field: .payee, operation: .contains)
            },
            set: { newValue in
                let updated = rootConditions.map {
                    $0.id == id ? newValue : $0
                }
                rule.expression = .group(
                    rootLogicBinding.wrappedValue,
                    updated.map(RuleExpression.condition)
                )
            }
        )
    }

    private func appendCondition() {
        var updated = rootConditions
        updated.append(
            RuleCondition(field: .purpose, operation: .contains)
        )
        rule.expression = .group(
            rootLogicBinding.wrappedValue,
            updated.map(RuleExpression.condition)
        )
    }

    private func removeCondition(_ id: UUID) {
        rule.expression = .group(
            rootLogicBinding.wrappedValue,
            rootConditions.filter { $0.id != id }
                .map(RuleExpression.condition)
        )
    }

    private var categoryActionBinding: Binding<UUID> {
        Binding(
            get: {
                rule.effectiveActions.compactMap {
                    if case .setCategory(let id) = $0 { return id }
                    if case .createSingleSplit(let id, _) = $0 {
                        return id
                    }
                    return nil
                }.first ?? rule.categoryID
            },
            set: { categoryID in
                rule.categoryID = categoryID
                let usesSplit = splitActionBinding.wrappedValue
                rule.actions.removeAll { $0.fieldKey == "category" }
                rule.actions.insert(
                    usesSplit
                        ? .createSingleSplit(
                            categoryID: categoryID,
                            memo: ""
                        )
                        : .setCategory(categoryID),
                    at: 0
                )
            }
        )
    }

    private func textActionBinding(
        read: @escaping (RuleAction) -> String?,
        make: @escaping (String) -> RuleAction
    ) -> Binding<String> {
        Binding(
            get: {
                rule.actions.compactMap(read).first ?? ""
            },
            set: { value in
                rule.actions.removeAll { read($0) != nil }
                if !value.isEmpty { rule.actions.append(make(value)) }
            }
        )
    }

    private func booleanActionBinding(
        _ action: RuleAction
    ) -> Binding<Bool> {
        Binding(
            get: { rule.actions.contains(action) },
            set: { enabled in
                rule.actions.removeAll { $0 == action }
                if enabled { rule.actions.append(action) }
            }
        )
    }

    private var purposeReplacement: (
        search: String,
        replacement: String,
        useRegex: Bool
    ) {
        rule.actions.compactMap {
            if case .replacePurpose(
                let search,
                let replacement,
                let useRegex
            ) = $0 {
                return (search, replacement, useRegex)
            }
            return nil
        }.first ?? ("", "", false)
    }

    private var purposeReplacementSearchBinding: Binding<String> {
        Binding(
            get: { purposeReplacement.search },
            set: { value in
                var replacement = purposeReplacement
                replacement.search = value
                setPurposeReplacement(replacement)
            }
        )
    }

    private var purposeReplacementValueBinding: Binding<String> {
        Binding(
            get: { purposeReplacement.replacement },
            set: { value in
                var replacement = purposeReplacement
                replacement.replacement = value
                setPurposeReplacement(replacement)
            }
        )
    }

    private var purposeReplacementRegexBinding: Binding<Bool> {
        Binding(
            get: { purposeReplacement.useRegex },
            set: { value in
                var replacement = purposeReplacement
                replacement.useRegex = value
                setPurposeReplacement(replacement)
            }
        )
    }

    private func setPurposeReplacement(
        _ value: (
            search: String,
            replacement: String,
            useRegex: Bool
        )
    ) {
        rule.actions.removeAll {
            if case .replacePurpose = $0 { return true }
            return false
        }
        if !value.search.isEmpty {
            rule.actions.append(
                .replacePurpose(
                    search: value.search,
                    replacement: value.replacement,
                    useRegex: value.useRegex
                )
            )
        }
    }

    private var tagActionIDs: Set<UUID> {
        Set(
            rule.actions.compactMap {
                if case .addTags(let ids) = $0 { return ids }
                return nil
            }.flatMap { $0 }
        )
    }

    private func tagActionBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { tagActionIDs.contains(id) },
            set: { enabled in
                var ids = tagActionIDs
                if enabled { ids.insert(id) } else { ids.remove(id) }
                rule.actions.removeAll {
                    if case .addTags = $0 { return true }
                    return false
                }
                if !ids.isEmpty {
                    rule.actions.append(
                        .addTags(
                            ids.sorted {
                                $0.uuidString < $1.uuidString
                            }
                        )
                    )
                }
            }
        )
    }

    private var splitActionBinding: Binding<Bool> {
        Binding(
            get: {
                rule.actions.contains {
                    if case .createSingleSplit = $0 { return true }
                    return false
                }
            },
            set: { enabled in
                let categoryID = categoryActionBinding.wrappedValue
                rule.actions.removeAll { $0.fieldKey == "category" }
                rule.actions.insert(
                    enabled
                        ? .createSingleSplit(
                            categoryID: categoryID,
                            memo: ""
                        )
                        : .setCategory(categoryID),
                    at: 0
                )
            }
        )
    }
}

private struct RuleApplicationPreviewSheet: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    let rule: CategorizationRule
    @State private var selectedIDs: Set<UUID> = []

    private var rows: [RuleTransactionPreview] {
        store.rulePreview(rule)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Regelvorschau: \(rule.name)")
                .font(.title2.bold())
            Text(
                "Wähle ausdrücklich die Buchungen aus. Betrag, Konto und "
                    + "Abgleichstatus werden durch Regeln nie verändert."
            )
            .foregroundStyle(.secondary)
            Table(rows, selection: $selectedIDs) {
                TableColumn("Datum") {
                    Text(
                        $0.before.bookingDate,
                        format: .dateTime.day().month().year()
                    )
                }
                TableColumn("Empfänger") {
                    Text($0.before.payee)
                }
                TableColumn("Vorher") {
                    Text(changeSummary($0, before: true))
                        .lineLimit(2)
                        .help(changeSummary($0, before: true))
                }
                TableColumn("Nachher") {
                    Text(changeSummary($0, before: false))
                        .lineLimit(2)
                        .help(changeSummary($0, before: false))
                }
            }
            .frame(minHeight: 300)
            let conflicts = store.ruleConflicts.filter {
                selectedIDs.contains($0.transactionID)
                    && $0.ruleNames.contains(rule.name)
            }
            if !conflicts.isEmpty {
                Label(
                    "\(conflicts.count) mögliche Überschneidung"
                        + "\(conflicts.count == 1 ? "" : "en") mit anderen Regeln",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }
            HStack {
                Button("Alle auswählen") {
                    selectedIDs = Set(rows.map(\.id))
                }
                Button("Auswahl aufheben") { selectedIDs = [] }
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Auswahl atomar anwenden") {
                    if store.applyRule(
                        rule,
                        transactionIDs: selectedIDs
                    ) != nil {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedIDs.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 470)
        .onAppear {
            selectedIDs = Set(rows.map(\.id))
        }
    }

    private func changeSummary(
        _ row: RuleTransactionPreview,
        before: Bool
    ) -> String {
        row.changes.map {
            "\($0.field): \(before ? $0.before : $0.after)"
        }.joined(separator: " · ")
    }
}

private extension FinanceCalendarEntryKind {
    var color: Color {
        switch self {
        case .recurring: .purple
        case .expected: .blue
        case .pending: .orange
        case .booked: .green
        case .cancelled: .secondary
        }
    }
}

private struct CalendarDisplayEntry: Identifiable {
    let transaction: FinanceTransaction
    let kind: FinanceCalendarEntryKind

    var id: String {
        kind == .recurring && !transaction.reference.isEmpty
            ? transaction.reference : transaction.id.uuidString
    }
}

private struct CalendarMoveRequest: Identifiable {
    var id: String { "\(entry.id):\(Int(destination.timeIntervalSince1970))" }
    let entry: CalendarDisplayEntry
    let destination: Date
}

struct CalendarForecastView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var editedSchedule: ScheduledTransaction?
    @State private var editedOccurrence: ScheduledOccurrenceEditRequest?
    @State private var forecastDays = 90
    @State private var viewMode = FinanceCalendarViewMode.list
    @State private var focusedDate = Date()
    @State private var selectedAccountID: UUID?
    @State private var selectedCategoryID: UUID?
    @State private var selectedTagID: UUID?
    @State private var pendingMove: CalendarMoveRequest?
    @State private var moveErrorMessage = ""
    @State private var showLiquidityScenarios = false

    private var occurrences: [FinanceTransaction] {
        store.forecastOccurrences(days: forecastDays).filter(matchesFilters)
    }

    private var calendarEntries: [CalendarDisplayEntry] {
        let real = store.transactions
            .filter(matchesFilters)
            .map {
                CalendarDisplayEntry(
                    transaction: $0,
                    kind: calendarKind(for: $0, virtual: false)
                )
            }
        let virtual = occurrences.map {
            CalendarDisplayEntry(transaction: $0, kind: .recurring)
        }
        return (real + virtual).sorted {
            if $0.transaction.bookingDate != $1.transaction.bookingDate {
                return $0.transaction.bookingDate < $1.transaction.bookingDate
            }
            return $0.id < $1.id
        }
    }

    private var calendarDays: [FinanceCalendarDay] {
        FinanceCalendarLayout.days(containing: focusedDate, mode: viewMode)
    }

    private var visibleCalendarEntries: [CalendarDisplayEntry] {
        guard let first = calendarDays.first?.date,
              let last = calendarDays.last?.date,
              let exclusiveEnd = Calendar.current.date(byAdding: .day, value: 1, to: last)
        else { return [] }
        return calendarEntries.filter {
            $0.transaction.bookingDate >= first && $0.transaction.bookingDate < exclusiveEnd
        }
    }

    private var categoryFilterIDs: Set<UUID>? {
        selectedCategoryID.map { descendantCategoryIDs(of: $0) }
    }

    private var tagFilterIDs: Set<UUID>? {
        selectedTagID.map { descendantTagIDs(of: $0) }
    }

    private var visibleExceptions: [ScheduledTransactionException] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: forecastDays, to: Date()) ?? Date()
        let includedSchedules = Set(store.scheduledTransactions.filter { schedule in
            store.accounts.contains {
                $0.id == schedule.accountID && $0.includeForecast && !$0.isClosed
            }
                && (selectedAccountID == nil || schedule.accountID == selectedAccountID)
        }.map(\.id))
        return store.scheduledTransactionExceptions.filter {
            includedSchedules.contains($0.scheduledTransactionID)
                && $0.originalDueDate >= start
                && $0.originalDueDate <= end
                && categoryMatches($0.categoryID)
                && selectedTagID == nil
        }
    }

    private var visibleRevisions: [ScheduledTransactionRevision] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: forecastDays, to: Date()) ?? Date()
        let includedSchedules = Set(store.scheduledTransactions.filter { schedule in
            store.accounts.contains {
                $0.id == schedule.accountID && $0.includeForecast && !$0.isClosed
            }
                && (selectedAccountID == nil || schedule.accountID == selectedAccountID)
        }.map(\.id))
        return store.scheduledTransactionRevisions.filter {
            includedSchedules.contains($0.scheduledTransactionID)
                && $0.originalDueDate >= start
                && $0.originalDueDate <= end
                && categoryMatches($0.categoryID)
                && selectedTagID == nil
        }
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
                Button {
                    showLiquidityScenarios = true
                } label: {
                    Label("Szenarien", systemImage: "chart.line.uptrend.xyaxis")
                }
            }
            .padding(12)
            Divider()
            calendarToolbar
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
                        Text(viewMode == .list ? "Liquiditätsvorschau" : "Finanzkalender")
                            .font(.headline)
                        Spacer()
                        Text(
                            viewMode == .list
                                ? "\(occurrences.count) erwartete Termine"
                                : "\(visibleCalendarEntries.count) Vorgänge"
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    Divider()
                    if viewMode == .list {
                        forecastList
                    } else {
                        calendarPeriodView
                    }
                }
                .frame(minWidth: 480)
            }
        }
        .sheet(item: $editedSchedule) { schedule in
            ScheduledTransactionEditor(value: schedule)
        }
        .sheet(item: $editedOccurrence) { request in
            ScheduledOccurrenceEditor(request: request)
        }
        .sheet(isPresented: $showLiquidityScenarios) {
            LiquidityScenarioView()
                .environmentObject(store)
        }
        .alert(
            "Prognosetermin verschieben?",
            isPresented: Binding(
                get: { pendingMove != nil },
                set: { if !$0 { pendingMove = nil } }
            ),
            presenting: pendingMove
        ) { request in
            Button("Verschieben") { applyCalendarMove(request) }
            Button("Abbrechen", role: .cancel) { pendingMove = nil }
        } message: { request in
            Text(
                "„\(entryTitle(request.entry.transaction))“ wird vom "
                    + "\(request.entry.transaction.bookingDate.formatted(.dateTime.day().month().year())) auf den "
                    + "\(request.destination.formatted(.dateTime.day().month().year())) verschoben."
            )
        }
        .alert(
            "Termin nicht verschiebbar",
            isPresented: Binding(
                get: { !moveErrorMessage.isEmpty },
                set: { if !$0 { moveErrorMessage = "" } }
            )
        ) {
            Button("OK", role: .cancel) { moveErrorMessage = "" }
        } message: {
            Text(moveErrorMessage)
        }
    }

    private var calendarToolbar: some View {
        HStack(spacing: 10) {
            Picker("Ansicht", selection: $viewMode) {
                ForEach(FinanceCalendarViewMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 230)

            Picker("Konto", selection: $selectedAccountID) {
                Text("Alle Konten").tag(UUID?.none)
                ForEach(store.accounts.filter { !$0.isClosed }) { account in
                    Text(account.name).tag(Optional(account.id))
                }
            }
            .frame(maxWidth: 190)

            Picker("Kategorie", selection: $selectedCategoryID) {
                Text("Alle Kategorien").tag(UUID?.none)
                ForEach(store.categoriesByPath.filter(\.isActive)) { category in
                    Text(store.categoryPath(category.id)).tag(Optional(category.id))
                }
            }
            .frame(maxWidth: 230)

            Picker("Klasse", selection: $selectedTagID) {
                Text("Alle Klassen/Tags").tag(UUID?.none)
                ForEach(store.tagsByPath.filter(\.isActive)) { tag in
                    Text(store.tagPath(tag.id)).tag(Optional(tag.id))
                }
            }
            .frame(maxWidth: 210)

            Spacer(minLength: 6)
            if viewMode != .list {
                Button { movePeriod(-1) } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Vorheriger Zeitraum")
                Button("Heute") { focusedDate = Date() }
                Button { movePeriod(1) } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Nächster Zeitraum")
                Text(periodTitle)
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 150, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var forecastList: some View {
        if occurrences.isEmpty && visibleExceptions.isEmpty && visibleRevisions.isEmpty {
            ContentUnavailableView(
                "Keine Termine im Zeitraum",
                systemImage: "calendar",
                description: Text("Aktive regelmäßige Vorgänge erscheinen hier ohne Doppelzählung.")
            )
        } else {
            List {
                Section("Erwartete Termine") {
                    ForEach(occurrences) { value in
                        Button { editedOccurrence = occurrenceRequest(for: value) } label: {
                            HStack(spacing: 12) {
                                Text(value.bookingDate, format: .dateTime.day().month().year())
                                    .frame(width: 92, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(entryTitle(value))
                                        if store.scheduledTransactionException(
                                            forReference: value.reference
                                        ) != nil {
                                            revisionBadge("Geändert", color: .blue)
                                        } else if store.scheduledTransactionRevision(
                                            forReference: value.reference
                                        ) != nil {
                                            revisionBadge("Serie geändert", color: .purple)
                                        }
                                    }
                                    Text("\(store.accountName(value.accountID)) · \(store.transactionCategoryPath(value))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(Money(minorUnits: value.amountMinor).formatted)
                                        .monospacedDigit()
                                        .foregroundStyle(value.amountMinor < 0 ? .red : .green)
                                    Text(Money(minorUnits: store.projectedBalanceMinor(
                                        accountID: value.accountID, through: value.bookingDate
                                    )).formatted)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "Serientermin \(entryTitle(value)), \(Money(minorUnits: value.amountMinor).formatted)"
                        )
                    }
                }
                if !visibleExceptions.isEmpty {
                    Section("Serienausnahmen") {
                        ForEach(visibleExceptions) { exception in
                            Button { editedOccurrence = occurrenceRequest(for: exception) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(scheduleName(exception.scheduledTransactionID))
                                        Text(exception.originalDueDate, format: .dateTime.day().month().year())
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(exception.disposition.title)
                                        .foregroundStyle(exception.disposition == .skipped ? .orange : .blue)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !visibleRevisions.isEmpty {
                    Section("Serienänderungen") {
                        ForEach(visibleRevisions) { revision in
                            Button { editedOccurrence = occurrenceRequest(for: revision) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(scheduleName(revision.scheduledTransactionID))
                                        Text("Ab \(revision.originalDueDate.formatted(.dateTime.day().month().year()))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(Money(minorUnits: revision.amountMinor).formatted)
                                        .monospacedDigit()
                                        .foregroundStyle(.purple)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var calendarPeriodView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ForEach(FinanceCalendarEntryKind.allCases, id: \.self) { kind in
                    Label {
                        Text(kind.title)
                    } icon: {
                        Circle().fill(kind.color).frame(width: 8, height: 8)
                    }
                }
                .font(.caption)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            LazyVGrid(columns: calendarColumns, spacing: 4) {
                ForEach(["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"], id: \.self) {
                    Text($0)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)

            ScrollView {
                LazyVGrid(columns: calendarColumns, spacing: 4) {
                    ForEach(calendarDays) { day in
                        calendarDayCell(day)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 70), spacing: 4), count: 7)
    }

    private func calendarDayCell(_ day: FinanceCalendarDay) -> some View {
        let entries = visibleCalendarEntries.filter {
            Calendar.current.isDate($0.transaction.bookingDate, inSameDayAs: day.date)
        }
        let visibleLimit = viewMode == .week ? 8 : 3
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(day.date, format: .dateTime.day())
                    .font(.caption.weight(Calendar.current.isDateInToday(day.date) ? .bold : .regular))
                Spacer()
                if !day.isInFocusedPeriod {
                    Text(day.date, format: .dateTime.month(.abbreviated))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(Array(entries.prefix(visibleLimit))) { entry in
                calendarEntryButton(entry, day: day)
            }
            if entries.count > visibleLimit {
                Text("+ \(entries.count - visibleLimit) weitere")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: viewMode == .week ? 330 : 112, alignment: .topLeading)
        .background(day.isInFocusedPeriod ? Color.primary.opacity(0.025) : Color.secondary.opacity(0.035))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(
                    Calendar.current.isDateInToday(day.date) ? Color.accentColor : Color.secondary.opacity(0.2),
                    lineWidth: Calendar.current.isDateInToday(day.date) ? 2 : 1
                )
        }
        .opacity(day.isInFocusedPeriod ? 1 : 0.62)
        .dropDestination(for: String.self) { identifiers, _ in
            guard let identifier = identifiers.first else { return false }
            return prepareCalendarMove(entryID: identifier, to: day.date)
        }
    }

    @ViewBuilder
    private func calendarEntryButton(
        _ entry: CalendarDisplayEntry,
        day: FinanceCalendarDay
    ) -> some View {
        if canMoveCalendarEntry(entry) {
            calendarEntryButtonBase(entry, day: day)
                .draggable(entry.id)
        } else {
            calendarEntryButtonBase(entry, day: day)
        }
    }

    private func calendarEntryButtonBase(
        _ entry: CalendarDisplayEntry,
        day: FinanceCalendarDay
    ) -> some View {
        Button { openCalendarEntry(entry) } label: {
            HStack(spacing: 4) {
                Circle().fill(entry.kind.color).frame(width: 6, height: 6)
                Text(entryTitle(entry.transaction)).lineLimit(1)
                Spacer(minLength: 2)
                Text(Money(minorUnits: entry.transaction.amountMinor).formatted)
                    .monospacedDigit()
            }
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(entry.kind.color.opacity(0.11), in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(entry.kind.title): \(store.accountName(entry.transaction.accountID)) · \(store.transactionCategoryPath(entry.transaction))")
        .accessibilityLabel(
            "\(entry.kind.title), \(entryTitle(entry.transaction)), \(Money(minorUnits: entry.transaction.amountMinor).formatted), \(day.date.formatted(.dateTime.day().month().year()))"
        )
    }

    private func revisionBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.bold())
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var periodTitle: String {
        if viewMode == .month {
            return focusedDate.formatted(
                Date.FormatStyle().month(.wide).year().locale(Locale(identifier: "de_DE"))
            )
        }
        guard let first = calendarDays.first?.date, let last = calendarDays.last?.date else {
            return ""
        }
        return "\(first.formatted(.dateTime.day().month())) – \(last.formatted(.dateTime.day().month().year()))"
    }

    private func movePeriod(_ offset: Int) {
        focusedDate = FinanceCalendarLayout.shiftedFocus(
            from: focusedDate, mode: viewMode, offset: offset
        )
    }

    private func calendarKind(
        for transaction: FinanceTransaction,
        virtual: Bool
    ) -> FinanceCalendarEntryKind {
        .classify(status: transaction.status, isRecurring: virtual)
    }

    private func entryTitle(_ transaction: FinanceTransaction) -> String {
        if !transaction.payee.isEmpty { return transaction.payee }
        if !transaction.purpose.isEmpty { return transaction.purpose }
        return "Vorgang"
    }

    private func openCalendarEntry(_ entry: CalendarDisplayEntry) {
        guard entry.kind == .recurring else { return }
        editedOccurrence = occurrenceRequest(for: entry.transaction)
    }

    private func canMoveCalendarEntry(_ entry: CalendarDisplayEntry) -> Bool {
        entry.kind == .recurring
            || (entry.transaction.status == .expected
                && entry.transaction.transferID == nil)
    }

    private func prepareCalendarMove(entryID: String, to destination: Date) -> Bool {
        guard let entry = calendarEntries.first(where: { $0.id == entryID }) else {
            return false
        }
        do {
            if entry.kind == .recurring {
                _ = try FinanceCalendarMovePolicy.movedRecurringException(
                    for: entry.transaction,
                    existing: store.scheduledTransactionException(
                        forReference: entry.transaction.reference
                    ),
                    to: destination
                )
            } else {
                _ = try FinanceCalendarMovePolicy.movedExpectedTransaction(
                    entry.transaction, to: destination
                )
            }
            pendingMove = CalendarMoveRequest(entry: entry, destination: destination)
            return true
        } catch {
            moveErrorMessage = error.localizedDescription
            return true
        }
    }

    private func applyCalendarMove(_ request: CalendarMoveRequest) {
        defer { pendingMove = nil }
        do {
            if request.entry.kind == .recurring {
                let exception = try FinanceCalendarMovePolicy.movedRecurringException(
                    for: request.entry.transaction,
                    existing: store.scheduledTransactionException(
                        forReference: request.entry.transaction.reference
                    ),
                    to: request.destination
                )
                _ = store.saveScheduledTransactionException(exception)
            } else {
                let transaction = try FinanceCalendarMovePolicy.movedExpectedTransaction(
                    request.entry.transaction, to: request.destination
                )
                if store.saveSplitTransaction(transaction) {
                    store.statusText = "Prognosetermin verschoben"
                }
            }
        } catch {
            moveErrorMessage = error.localizedDescription
        }
    }

    private func matchesFilters(_ transaction: FinanceTransaction) -> Bool {
        guard selectedAccountID == nil || transaction.accountID == selectedAccountID else {
            return false
        }
        if let categoryFilterIDs {
            let directMatch = transaction.categoryID.map(categoryFilterIDs.contains) ?? false
            let splitMatch = transaction.splits.contains {
                $0.categoryID.map(categoryFilterIDs.contains) ?? false
            }
            guard directMatch || splitMatch else { return false }
        }
        if let tagFilterIDs {
            let directMatch = !Set(transaction.tagIDs).isDisjoint(with: tagFilterIDs)
            let splitMatch = transaction.splits.contains {
                !Set($0.tagIDs).isDisjoint(with: tagFilterIDs)
            }
            guard directMatch || splitMatch else { return false }
        }
        return true
    }

    private func categoryMatches(_ categoryID: UUID?) -> Bool {
        guard let categoryFilterIDs else { return true }
        return categoryID.map(categoryFilterIDs.contains) ?? false
    }

    private func descendantCategoryIDs(of rootID: UUID) -> Set<UUID> {
        var result: Set<UUID> = [rootID]
        var changed = true
        while changed {
            let oldCount = result.count
            for category in store.categories where category.parentID.map(result.contains) == true {
                result.insert(category.id)
            }
            changed = result.count != oldCount
        }
        return result
    }

    private func descendantTagIDs(of rootID: UUID) -> Set<UUID> {
        var result: Set<UUID> = [rootID]
        var changed = true
        while changed {
            let oldCount = result.count
            for tag in store.tags where tag.parentID.map(result.contains) == true {
                result.insert(tag.id)
            }
            changed = result.count != oldCount
        }
        return result
    }

    private func occurrenceRequest(
        for transaction: FinanceTransaction
    ) -> ScheduledOccurrenceEditRequest? {
        guard let identity = ScheduledTransaction.occurrenceIdentity(
            from: transaction.reference
        ), let schedule = store.scheduledTransactions.first(where: {
            $0.id == identity.scheduledTransactionID
        }) else { return nil }
        return ScheduledOccurrenceEditRequest(
            schedule: schedule, originalDueDate: identity.originalDueDate,
            effectiveDate: transaction.bookingDate,
            exception: store.scheduledTransactionException(forReference: transaction.reference),
            inheritedRevision: store.scheduledTransactionRevision(forReference: transaction.reference),
            startingRevision: store.scheduledTransactionRevision(
                forReference: transaction.reference, startingExactly: true
            )
        )
    }

    private func occurrenceRequest(
        for exception: ScheduledTransactionException
    ) -> ScheduledOccurrenceEditRequest? {
        guard let schedule = store.scheduledTransactions.first(where: {
            $0.id == exception.scheduledTransactionID
        }) else { return nil }
        return ScheduledOccurrenceEditRequest(
            schedule: schedule, originalDueDate: exception.originalDueDate,
            effectiveDate: exception.effectiveDate, exception: exception,
            inheritedRevision: store.scheduledTransactionRevision(
                forReference: schedule.occurrenceReference(for: exception.originalDueDate)
            ),
            startingRevision: store.scheduledTransactionRevision(
                forReference: schedule.occurrenceReference(for: exception.originalDueDate),
                startingExactly: true
            )
        )
    }

    private func occurrenceRequest(
        for revision: ScheduledTransactionRevision
    ) -> ScheduledOccurrenceEditRequest? {
        guard let schedule = store.scheduledTransactions.first(where: {
            $0.id == revision.scheduledTransactionID
        }) else { return nil }
        let reference = schedule.occurrenceReference(for: revision.originalDueDate)
        return ScheduledOccurrenceEditRequest(
            schedule: schedule, originalDueDate: revision.originalDueDate,
            effectiveDate: revision.effectiveDate,
            exception: store.scheduledTransactionException(forReference: reference),
            inheritedRevision: revision, startingRevision: revision
        )
    }

    private func scheduleName(_ id: UUID) -> String {
        store.scheduledTransactions.first { $0.id == id }?.name ?? "Regelmäßiger Vorgang"
    }
}

private enum ForecastScope: String, CaseIterable {
    case all
    case account
    case group

    var title: String {
        switch self {
        case .all: "Alle Konten"
        case .account: "Konto"
        case .group: "Kontengruppe"
        }
    }
}

private struct LiquidityScenarioView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    @State private var selectedScenarioID: UUID?
    @State private var interval = ForecastInterval.weekly
    @State private var horizon = 90
    @State private var scope = ForecastScope.all
    @State private var scopeID: UUID?
    @State private var currency = "EUR"
    @State private var editedScenario: ForecastScenario?
    @State private var editedEntry: ForecastScenarioEntry?
    @State private var deleteScenarioID: UUID?
    @State private var deleteEntryID: UUID?

    private var currencies: [String] {
        Array(Set(store.accounts.filter { !$0.isClosed && $0.includeForecast }.map {
            $0.currency.uppercased()
        })).sorted()
    }

    private var accountIDs: Set<UUID> {
        Set(store.accounts.filter { account in
            guard !account.isClosed, account.includeForecast,
                  account.currency.uppercased() == currency else { return false }
            switch scope {
            case .all: return true
            case .account: return account.id == scopeID
            case .group: return account.groupID == scopeID
            }
        }.map(\.id))
    }

    private var buckets: [ForecastBucket] {
        store.liquidityForecast(
            accountIDs: accountIDs, scenarioID: selectedScenarioID,
            from: Calendar.current.startOfDay(for: Date()),
            through: Calendar.current.date(byAdding: .day, value: horizon, to: Date()) ?? Date(),
            interval: interval
        )
    }

    private var baselineBuckets: [ForecastBucket] {
        store.liquidityForecast(
            accountIDs: accountIDs, scenarioID: nil,
            from: Calendar.current.startOfDay(for: Date()),
            through: Calendar.current.date(byAdding: .day, value: horizon, to: Date()) ?? Date(),
            interval: interval
        )
    }

    private var selectedScenario: ForecastScenario? {
        selectedScenarioID.flatMap { id in store.forecastScenarios.first { $0.id == id } }
    }

    private var selectedEntries: [ForecastScenarioEntry] {
        guard let selectedScenarioID else { return [] }
        return store.forecastScenarioEntries.filter { $0.scenarioID == selectedScenarioID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Liquiditätsprognose & Szenarien").font(.title2.bold())
                    Text("Basisverlauf und Was-wäre-wenn-Positionen mit nachvollziehbarer Herkunft")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Schließen") { dismiss() }
            }
            .padding(14)
            Divider()

            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Text("Szenarien").font(.headline)
                        Spacer()
                        Button { newScenario() } label: { Image(systemName: "plus") }
                            .help("Neues Szenario")
                    }
                    .padding(10)
                    Divider()
                    List(selection: $selectedScenarioID) {
                        Text("Basis ohne Szenario").tag(UUID?.none)
                        ForEach(store.forecastScenarios) { scenario in
                            HStack {
                                Circle().fill(scenario.isActive ? .green : .secondary)
                                    .frame(width: 7, height: 7)
                                Text(scenario.name)
                                Spacer()
                                Text("\(store.forecastScenarioEntries.filter { $0.scenarioID == scenario.id }.count)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(Optional(scenario.id))
                            .contextMenu {
                                Button("Bearbeiten") { editedScenario = scenario }
                                Button("Löschen", role: .destructive) { deleteScenarioID = scenario.id }
                            }
                        }
                    }
                    if let scenario = selectedScenario {
                        Divider()
                        HStack {
                            Text("Positionen").font(.headline)
                            Spacer()
                            Button { newEntry(scenarioID: scenario.id) } label: {
                                Image(systemName: "plus")
                            }
                            .disabled(store.accounts.filter { !$0.isClosed }.isEmpty)
                        }
                        .padding(10)
                        List(selectedEntries) { entry in
                            Button { editedEntry = entry } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(entry.name).lineLimit(1)
                                        Spacer()
                                        Text(Money(minorUnits: entry.amountMinor, currency: store.accounts.first { $0.id == entry.accountID }?.currency ?? "EUR").formatted)
                                            .monospacedDigit()
                                    }
                                    Text("\(store.accountName(entry.accountID)) · \(entry.date.formatted(.dateTime.day().month().year()))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Löschen", role: .destructive) { deleteEntryID = entry.id }
                            }
                        }
                        .frame(minHeight: 180)
                    }
                }
                .frame(minWidth: 280, idealWidth: 330)

                VStack(spacing: 0) {
                    forecastControls
                    Divider()
                    if accountIDs.isEmpty {
                        ContentUnavailableView(
                            "Keine passenden Prognosekonten", systemImage: "building.columns",
                            description: Text("Wähle eine Währung und einen Bereich mit offenen Prognosekonten.")
                        )
                    } else {
                        forecastSummary
                        Divider()
                        forecastList
                    }
                }
                .frame(minWidth: 720)
            }
        }
        .frame(minWidth: 1100, minHeight: 720)
        .onAppear {
            if !currencies.contains(currency) { currency = currencies.first ?? "EUR" }
        }
        .sheet(item: $editedScenario) { value in
            ForecastScenarioEditor(value: value).environmentObject(store)
        }
        .sheet(item: $editedEntry) { value in
            ForecastScenarioEntryEditor(value: value).environmentObject(store)
        }
        .alert("Szenario löschen?", isPresented: Binding(
            get: { deleteScenarioID != nil }, set: { if !$0 { deleteScenarioID = nil } }
        )) {
            Button("Löschen", role: .destructive) {
                if let id = deleteScenarioID { _ = store.deleteForecastScenario(id: id) }
                selectedScenarioID = nil
                deleteScenarioID = nil
            }
            Button("Abbrechen", role: .cancel) { deleteScenarioID = nil }
        } message: { Text("Alle Positionen dieses Szenarios werden ebenfalls gelöscht.") }
        .alert("Position löschen?", isPresented: Binding(
            get: { deleteEntryID != nil }, set: { if !$0 { deleteEntryID = nil } }
        )) {
            Button("Löschen", role: .destructive) {
                if let id = deleteEntryID { _ = store.deleteForecastScenarioEntry(id: id) }
                deleteEntryID = nil
            }
            Button("Abbrechen", role: .cancel) { deleteEntryID = nil }
        }
    }

    private var forecastControls: some View {
        HStack(spacing: 10) {
            Picker("Intervall", selection: $interval) {
                ForEach(ForecastInterval.allCases, id: \.self) { Text($0.title).tag($0) }
            }.frame(width: 150)
            Picker("Horizont", selection: $horizon) {
                Text("30 Tage").tag(30); Text("90 Tage").tag(90); Text("1 Jahr").tag(365)
            }.frame(width: 130)
            Picker("Währung", selection: $currency) {
                ForEach(currencies, id: \.self) { Text($0).tag($0) }
            }.frame(width: 105)
            Picker("Bereich", selection: $scope) {
                ForEach(ForecastScope.allCases, id: \.self) { Text($0.title).tag($0) }
            }.frame(width: 150)
            if scope == .account {
                Picker("Konto", selection: $scopeID) {
                    Text("Bitte wählen").tag(UUID?.none)
                    ForEach(store.accounts.filter { !$0.isClosed && $0.includeForecast && $0.currency.uppercased() == currency }) {
                        Text($0.name).tag(Optional($0.id))
                    }
                }.frame(maxWidth: 210)
            } else if scope == .group {
                Picker("Gruppe", selection: $scopeID) {
                    Text("Bitte wählen").tag(UUID?.none)
                    ForEach(store.accountGroups.filter(\.isActive)) {
                        Text($0.name).tag(Optional($0.id))
                    }
                }.frame(maxWidth: 210)
            }
            Spacer()
        }
        .padding(10)
        .onChange(of: scope) { _, _ in scopeID = nil }
        .onChange(of: currency) { _, _ in scopeID = nil }
    }

    private var forecastSummary: some View {
        let minimum = buckets.map(\.minimumBalanceMinor).min() ?? 0
        let maximum = buckets.map(\.maximumBalanceMinor).max() ?? 0
        let underfunded = buckets.filter { $0.minimumBalanceMinor < 0 }.count
        let closing = buckets.last?.closingBalanceMinor ?? 0
        let baselineClosing = baselineBuckets.last?.closingBalanceMinor ?? closing
        return HStack(spacing: 24) {
            summaryValue("Schlusssaldo", closing)
            summaryValue("Minimum", minimum, warning: minimum < 0)
            summaryValue("Maximum", maximum)
            VStack(alignment: .leading) {
                Text("Unterdeckung").font(.caption).foregroundStyle(.secondary)
                Text(underfunded == 0 ? "Keine" : "\(underfunded) Intervalle")
                    .foregroundStyle(underfunded == 0 ? Color.primary : Color.red).fontWeight(.semibold)
            }
            summaryValue("Szenarioeffekt", closing - baselineClosing)
            Spacer()
        }
        .padding(12)
    }

    private func summaryValue(_ title: String, _ value: Int64, warning: Bool = false) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money(minorUnits: value, currency: currency).formatted)
                .monospacedDigit().fontWeight(.semibold)
                .foregroundStyle(warning ? .red : .primary)
        }
    }

    private var forecastList: some View {
        List {
            ForEach(buckets) { bucket in
                Section {
                    ForEach(bucket.positions) { position in
                        HStack {
                            Text(position.date, format: .dateTime.day().month().year())
                                .frame(width: 90, alignment: .leading)
                            Text(position.origin.title)
                                .font(.caption.bold()).foregroundStyle(originColor(position.origin))
                                .frame(width: 85, alignment: .leading)
                            VStack(alignment: .leading) {
                                Text(position.title)
                                Text(store.accountName(position.accountID))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Money(minorUnits: position.amountMinor, currency: currency).formatted)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    HStack {
                        Text(periodTitle(bucket))
                        Spacer()
                        Text("Anfang \(Money(minorUnits: bucket.openingBalanceMinor, currency: currency).formatted)")
                        Text("Änderung \(Money(minorUnits: bucket.changeMinor, currency: currency).formatted)")
                        Text("Schluss \(Money(minorUnits: bucket.closingBalanceMinor, currency: currency).formatted)")
                            .foregroundStyle(bucket.closingBalanceMinor < 0 ? .red : .secondary)
                    }.font(.caption)
                }
            }
        }
    }

    private func periodTitle(_ bucket: ForecastBucket) -> String {
        if Calendar.current.isDate(bucket.startDate, inSameDayAs: bucket.endDate) {
            return bucket.startDate.formatted(.dateTime.day().month().year())
        }
        return "\(bucket.startDate.formatted(.dateTime.day().month())) – \(bucket.endDate.formatted(.dateTime.day().month().year()))"
    }

    private func originColor(_ origin: ForecastPositionOrigin) -> Color {
        switch origin {
        case .booked: .green
        case .pending: .orange
        case .expected: .blue
        case .paymentOrder: .cyan
        case .standingOrder: .indigo
        case .recurring: .purple
        case .scenario: .pink
        }
    }

    private func newScenario() {
        let now = Date()
        editedScenario = ForecastScenario(
            id: UUID(), name: "Neues Szenario", note: "", isActive: true,
            createdAt: now, updatedAt: now
        )
    }

    private func newEntry(scenarioID: UUID) {
        let eligible = store.accounts.filter {
            !$0.isClosed && $0.includeForecast && $0.currency.uppercased() == currency
        }
        guard let account = eligible.first(where: { accountIDs.contains($0.id) })
                ?? eligible.first else { return }
        let now = Date()
        editedEntry = ForecastScenarioEntry(
            id: UUID(), scenarioID: scenarioID, accountID: account.id,
            date: now, name: "Neue Annahme", amountMinor: 0, isEnabled: true,
            note: "", createdAt: now, updatedAt: now
        )
    }
}

private struct ForecastScenarioEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    @State var value: ForecastScenario

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Szenario").font(.title2.bold()); Spacer(); Button("Abbrechen") { dismiss() }; Button("Speichern") { if store.saveForecastScenario(value) { dismiss() } }.buttonStyle(.borderedProminent) }
                .padding(14)
            Divider()
            Form {
                TextField("Name", text: $value.name)
                TextField("Notiz", text: $value.note, axis: .vertical).lineLimit(3...6)
                Toggle("Aktiv", isOn: $value.isActive)
            }.padding(14)
        }.frame(width: 520, height: 300)
    }
}

private struct ForecastScenarioEntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    @State var value: ForecastScenarioEntry
    @State private var amountText: String

    init(value: ForecastScenarioEntry) {
        _value = State(initialValue: value)
        _amountText = State(initialValue: "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Szenarioposition").font(.title2.bold()); Spacer(); Button("Abbrechen") { dismiss() }; Button("Speichern") { save() }.buttonStyle(.borderedProminent) }
                .padding(14)
            Divider()
            Form {
                TextField("Bezeichnung", text: $value.name)
                Picker("Konto", selection: $value.accountID) {
                    ForEach(store.accounts.filter { !$0.isClosed && $0.includeForecast }) {
                        Text("\($0.name) (\($0.currency))").tag($0.id)
                    }
                }
                DatePicker("Datum", selection: $value.date, displayedComponents: .date)
                TextField("Betrag", text: $amountText)
                Toggle("In Berechnung einbeziehen", isOn: $value.isEnabled)
                TextField("Notiz", text: $value.note, axis: .vertical).lineLimit(2...5)
            }.padding(14)
        }
        .frame(width: 560, height: 430)
        .onAppear {
            guard amountText.isEmpty else { return }
            let currency = store.accounts.first { $0.id == value.accountID }?.currency ?? "EUR"
            amountText = Money(minorUnits: value.amountMinor, currency: currency).editingString
        }
    }

    private func save() {
        guard let account = store.accounts.first(where: { $0.id == value.accountID }),
              let money = try? Money(parsing: amountText, currency: account.currency) else {
            store.errorMessage = "Bitte gib einen gültigen Betrag ein."
            return
        }
        value.amountMinor = money.minorUnits
        if store.saveForecastScenarioEntry(value) { dismiss() }
    }
}

private struct ScheduledOccurrenceEditRequest: Identifiable {
    var id: String {
        "\(schedule.id.uuidString):\(Int(originalDueDate.timeIntervalSince1970))"
    }
    let schedule: ScheduledTransaction
    let originalDueDate: Date
    let effectiveDate: Date
    let exception: ScheduledTransactionException?
    let inheritedRevision: ScheduledTransactionRevision?
    let startingRevision: ScheduledTransactionRevision?
}

private struct ScheduledOccurrenceEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    let request: ScheduledOccurrenceEditRequest
    @State private var effectiveDate: Date
    @State private var payee: String
    @State private var purpose: String
    @State private var categoryID: UUID?
    @State private var amountText: String
    @State private var note: String
    @State private var showFutureConfirmation = false

    init(request: ScheduledOccurrenceEditRequest) {
        self.request = request
        let value = request.exception
        let inherited = request.inheritedRevision
        _effectiveDate = State(initialValue: value?.effectiveDate ?? request.effectiveDate)
        _payee = State(initialValue: value?.payee ?? inherited?.payee ?? request.schedule.payee)
        _purpose = State(initialValue: value?.purpose ?? inherited?.purpose ?? request.schedule.purpose)
        _categoryID = State(
            initialValue: value.map { $0.categoryID }
                ?? inherited.map { $0.categoryID } ?? request.schedule.categoryID
        )
        _amountText = State(
            initialValue: Money(
                minorUnits: value?.amountMinor
                    ?? inherited?.amountMinor ?? request.schedule.amountMinor,
                currency: request.schedule.currency
            ).editingString
        )
        _note = State(initialValue: value?.note ?? request.startingRevision?.note ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Einzelne Fälligkeit bearbeiten").font(.title2.bold())
                    Text(request.schedule.name).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Änderung speichern") { save(.modified) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(14)
            Divider()
            Form {
                Section("Fälligkeit") {
                    LabeledContent("Ursprünglich") {
                        Text(request.originalDueDate, format: .dateTime.day().month().year())
                    }
                    DatePicker(
                        "Neues Datum", selection: $effectiveDate,
                        displayedComponents: .date
                    )
                }
                Section("Werte nur für diesen Termin") {
                    TextField("Empfänger", text: $payee)
                    TextField("Verwendungszweck", text: $purpose)
                    Picker("Kategorie", selection: $categoryID) {
                        Text("Nicht kategorisiert").tag(UUID?.none)
                        ForEach(store.categoriesByPath.filter(\.isActive)) {
                            Text(store.categoryPath($0.id)).tag(Optional($0.id))
                        }
                    }
                    TextField("Betrag", text: $amountText)
                        .multilineTextAlignment(.trailing)
                    TextField("Begründung/Notiz", text: $note)
                }
                Section {
                    Button("Diese Fälligkeit überspringen") { save(.skipped) }
                        .foregroundStyle(.orange)
                    Button("Diesen und alle folgenden ändern") {
                        showFutureConfirmation = true
                    }
                    .foregroundStyle(.purple)
                    if request.exception != nil {
                        Button("Einzelausnahme zurücksetzen") { reset() }
                    }
                    if request.startingRevision != nil {
                        Button("Serienänderung ab hier zurücksetzen") {
                            resetFutureRevision()
                        }
                    }
                } footer: {
                    Text("Einzelausnahmen gelten nur für diesen Termin. Eine Serienänderung verwendet die neuen Werte ab diesem Termin und führt dieselbe Frequenz vom neuen Datum aus fort; die stabile Herkunftskennung bleibt erhalten.")
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 620, height: 680)
        .confirmationDialog(
            "Diesen und alle folgenden Termine ändern?",
            isPresented: $showFutureConfirmation,
            titleVisibility: .visible
        ) {
            Button("Ab diesem Termin ändern") { saveFutureRevision() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Datum, Empfänger, Verwendungszweck, Kategorie und Betrag gelten ab diesem Termin für alle folgenden Fälligkeiten. Eine Einzelausnahme genau an diesem Termin wird ersetzt.")
        }
    }

    private func save(_ disposition: ScheduledOccurrenceDisposition) {
        do {
            let amount = try Money(
                parsing: amountText, currency: request.schedule.currency
            ).minorUnits
            let now = Date()
            let exception = ScheduledTransactionException(
                id: request.exception?.id ?? UUID(),
                scheduledTransactionID: request.schedule.id,
                originalDueDate: request.originalDueDate,
                effectiveDate: effectiveDate, payee: payee, purpose: purpose,
                categoryID: categoryID, amountMinor: amount,
                disposition: disposition, note: note,
                createdAt: request.exception?.createdAt ?? now, updatedAt: now
            )
            if store.saveScheduledTransactionException(exception) { dismiss() }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func reset() {
        if store.resetScheduledTransactionException(
            scheduledTransactionID: request.schedule.id,
            originalDueDate: request.originalDueDate
        ) { dismiss() }
    }

    private func saveFutureRevision() {
        do {
            let amount = try Money(
                parsing: amountText, currency: request.schedule.currency
            ).minorUnits
            let now = Date()
            let revision = ScheduledTransactionRevision(
                id: request.startingRevision?.id ?? UUID(),
                scheduledTransactionID: request.schedule.id,
                originalDueDate: request.originalDueDate,
                effectiveDate: effectiveDate, payee: payee, purpose: purpose,
                categoryID: categoryID, amountMinor: amount, note: note,
                createdAt: request.startingRevision?.createdAt ?? now,
                updatedAt: now
            )
            if store.saveScheduledTransactionRevision(revision) { dismiss() }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func resetFutureRevision() {
        if store.resetScheduledTransactionRevision(
            scheduledTransactionID: request.schedule.id,
            originalDueDate: request.originalDueDate
        ) { dismiss() }
    }
}

struct ScheduledTransactionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    @State private var value: ScheduledTransaction
    @State private var amountText: String
    @State private var hasEndDate: Bool

    private var template: TransactionTemplate? { value.transactionTemplate }

    private var locksAmount: Bool {
        guard let template else { return false }
        return !template.splits.isEmpty
            || (template.vatMode ?? .none) != .none
            || template.originalAmountMinor != nil
    }

    private var availableAccounts: [FinanceAccount] {
        store.accounts.filter {
            !$0.isClosed && $0.currency == value.currency
        }
    }

    init(value: ScheduledTransaction) {
        _value = State(initialValue: value)
        _amountText = State(
            initialValue: Money(
                minorUnits: value.amountMinor,
                currency: value.currency
            ).editingString
        )
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
                        ForEach(availableAccounts) { Text($0.name).tag($0.id) }
                    }
                    TextField("Empfänger", text: $value.payee)
                    TextField("Verwendungszweck", text: $value.purpose)
                    Picker("Kategorie", selection: $value.categoryID) {
                        Text("Nicht kategorisiert").tag(UUID?.none)
                        ForEach(store.categoriesByPath.filter(\.isActive)) {
                            Text(store.categoryPath($0.id)).tag(Optional($0.id))
                        }
                    }
                    .disabled(template?.splits.isEmpty == false)
                    TextField("Betrag", text: $amountText)
                        .multilineTextAlignment(.trailing)
                        .disabled(locksAmount)
                        .help(
                            locksAmount
                                ? "Der Betrag ist geschützt, damit übernommene Splits, MwSt. oder Fremdwährung exakt bleiben."
                                : "Grundrechenarten und Klammern sind erlaubt."
                        )
                    if locksAmount {
                        Text(
                            "Betrag und Aufteilung stammen vollständig aus der Buchung. "
                                + "Splits, MwSt. und Fremdwährung bleiben dadurch unverändert."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                if let template, !template.splits.isEmpty {
                    Section("Übernommene Aufteilung") {
                        ForEach(template.splits.indices, id: \.self) { index in
                            let split = template.splits[index]
                            HStack {
                                Text(
                                    split.categoryID.map(store.categoryPath)
                                        ?? "Nicht kategorisiert"
                                )
                                Spacer()
                                Text(
                                    Money(
                                        minorUnits: split.amountMinor,
                                        currency: value.currency
                                    ).formatted
                                )
                                .monospacedDigit()
                            }
                        }
                    }
                }
                if let template, let originalAmount = template.originalAmountMinor,
                   let originalCurrency = template.originalCurrency {
                    Section("Übernommene Fremdwährung") {
                        LabeledContent(
                            "Originalbetrag",
                            value: Money(
                                minorUnits: originalAmount,
                                currency: originalCurrency
                            ).formatted
                        )
                    }
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
            value.amountMinor = try Money(
                evaluating: amountText,
                currency: value.currency
            ).minorUnits
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
    @State private var editedBudget: FinanceBudget?
    @State private var annualBudget: FinanceBudget?
    @State private var copyRequest: BudgetCopyRequest?
    @State private var showDeleteConfirmation = false

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
        rows.filter { $0.category.kind == .expense }.reduce(0) { $0 + $1.actualMinor }
    }

    private var rolloverReserve: Int64 {
        guard let selectedBudgetID else { return 0 }
        return store.budgetPlanningSnapshot(budgetID: selectedBudgetID)?.rolloverReserve(
            after: BudgetPlanningEngine.monthKey(selectedMonth)
        ) ?? 0
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
                if let budget {
                    Menu {
                        Button("Jahreswerte …", systemImage: "calendar") {
                            annualBudget = budget
                        }
                        Button("Umbenennen …", systemImage: "pencil") {
                            editedBudget = budget
                        }
                        Divider()
                        Button("Duplizieren …", systemImage: "plus.square.on.square") {
                            copyRequest = BudgetCopyRequest(source: budget, derivesNextYear: false)
                        }
                        Button("Folgejahr ableiten …", systemImage: "calendar.badge.plus") {
                            copyRequest = BudgetCopyRequest(source: budget, derivesNextYear: true)
                        }
                        Divider()
                        Button("Budget löschen …", systemImage: "trash", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    } label: {
                        Label("Aktionen", systemImage: "ellipsis.circle")
                    }
                }
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
                    BudgetMetric(
                        title: "Roll-over-Reserve",
                        value: Money(minorUnits: rolloverReserve).formatted,
                        warning: rolloverReserve < 0
                    )
                }
                .padding(12)
                Divider()
                HStack {
                    Text("Kategorie").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Basisplan").frame(width: 105, alignment: .trailing)
                    Text("Übertrag").frame(width: 105, alignment: .trailing)
                    Text("Verfügbar").frame(width: 105, alignment: .trailing)
                    Text("Ist").frame(width: 105, alignment: .trailing)
                    Text("Saldo").frame(width: 105, alignment: .trailing)
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
                                store.categoryPath(row.category.id),
                                systemImage: row.category.kind == .income
                                    ? "arrow.down.circle" : "arrow.up.circle"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(Money(minorUnits: row.basePlannedMinor).formatted)
                                .frame(width: 105, alignment: .trailing)
                            Text(Money(minorUnits: row.rolloverMinor).formatted)
                                .foregroundStyle(row.rolloverMinor < 0 ? .red : .secondary)
                                .frame(width: 105, alignment: .trailing)
                            Text(Money(minorUnits: row.plannedMinor).formatted)
                                .frame(width: 105, alignment: .trailing)
                            Text(Money(minorUnits: row.actualMinor).formatted)
                                .frame(width: 105, alignment: .trailing)
                            Text(Money(minorUnits: row.varianceMinor).formatted)
                                .foregroundStyle(row.varianceMinor < 0 ? .red : .green)
                                .frame(width: 105, alignment: .trailing)
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
            BudgetEditor(budget: nil)
        }
        .sheet(item: $editedBudget) { BudgetEditor(budget: $0) }
        .sheet(item: $annualBudget) { BudgetYearEditor(budget: $0) }
        .sheet(item: $copyRequest) { BudgetCopyEditor(request: $0) }
        .sheet(item: $editedRow) { row in
            if let selectedBudgetID {
                BudgetLineEditor(
                    budgetID: selectedBudgetID, month: selectedMonth, row: row
                )
            }
        }
        .confirmationDialog(
            "Budget „\(budget?.name ?? "")“ wirklich löschen?",
            isPresented: $showDeleteConfirmation, titleVisibility: .visible
        ) {
            Button("Budget und Monatswerte löschen", role: .destructive) {
                if let selectedBudgetID, store.deleteBudget(id: selectedBudgetID) {
                    self.selectedBudgetID = store.budgets.first?.id
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Buchungen bleiben erhalten. Nur das Budget und seine Planwerte werden gelöscht.")
        }
    }
}

private struct BudgetCopyRequest: Identifiable {
    let id = UUID()
    let source: FinanceBudget
    let derivesNextYear: Bool
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
    let budget: FinanceBudget?
    @State private var name: String
    @State private var startYear: Int
    @State private var startMonth: Int
    @State private var isActive: Bool

    init(budget: FinanceBudget?) {
        self.budget = budget
        _name = State(initialValue: budget?.name ?? "Neues Budget")
        _startYear = State(initialValue:
            budget?.startYear ?? Calendar.current.component(.year, from: Date()))
        _startMonth = State(initialValue: budget?.startMonth ?? 1)
        _isActive = State(initialValue: budget?.isActive ?? true)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(budget == nil ? "Budget anlegen" : "Budget umbenennen")
                    .font(.title2.bold())
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button(budget == nil ? "Anlegen" : "Speichern") {
                    let value = FinanceBudget(
                        id: budget?.id ?? UUID(), name: name, startYear: startYear,
                        startMonth: startMonth, currency: budget?.currency ?? "EUR",
                        isActive: isActive
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
                if budget == nil {
                    Stepper("Startjahr: \(startYear)", value: $startYear, in: 1900...2200)
                    Picker("Erster Monat des Geschäftsjahres", selection: $startMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text(Calendar.current.monthSymbols[month - 1]).tag(month)
                        }
                    }
                } else {
                    LabeledContent("Geschäftsjahr", value:
                        "\(Calendar.current.monthSymbols[startMonth - 1]) \(startYear)")
                }
                Toggle("Aktiv", isOn: $isActive)
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 300)
    }
}

private struct BudgetCopyEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    let request: BudgetCopyRequest
    @State private var name: String
    @State private var startYear: Int
    @State private var startMonth: Int

    init(request: BudgetCopyRequest) {
        self.request = request
        let year = request.source.startYear + (request.derivesNextYear ? 1 : 0)
        _name = State(initialValue: request.derivesNextYear
            ? "\(request.source.name) \(year)"
            : "\(request.source.name) – Kopie")
        _startYear = State(initialValue: year)
        _startMonth = State(initialValue: request.source.startMonth)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(request.derivesNextYear ? "Folgejahr ableiten" : "Budget duplizieren")
                        .font(.title2.bold())
                    Text("Alle zwölf Monatswerte und Roll-over-Einstellungen werden kopiert.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Kopie anlegen") {
                    if store.duplicateBudget(
                        sourceID: request.source.id, name: name,
                        startYear: startYear, startMonth: startMonth
                    ) != nil { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
            Divider()
            Form {
                TextField("Name", text: $name)
                Stepper("Startjahr: \(startYear)", value: $startYear, in: 1900...2200)
                Picker("Erster Monat des Geschäftsjahres", selection: $startMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text(Calendar.current.monthSymbols[month - 1]).tag(month)
                    }
                }
                LabeledContent("Währung", value: request.source.currency.uppercased())
            }
            .formStyle(.grouped)
        }
        .frame(width: 580, height: 350)
    }
}

private struct BudgetYearEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    let budget: FinanceBudget
    @State private var categoryID: UUID?
    @State private var amountTexts = Array(repeating: "0,00", count: 12)
    @State private var rolloverMode = BudgetRolloverMode.none

    private var categories: [FinanceCategory] {
        store.categories.filter { $0.isActive && $0.isBudgetable && $0.kind != .transfer }
            .sorted { store.categoryPath($0.id).localizedCaseInsensitiveCompare(
                store.categoryPath($1.id)) == .orderedAscending }
    }

    private var planningRows: [BudgetPlanningMonthRow] {
        guard let categoryID else { return [] }
        return store.budgetPlanningSnapshot(budgetID: budget.id)?.rows
            .filter { $0.categoryID == categoryID }
            .sorted { $0.month < $1.month } ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Jahreswerte").font(.title2.bold())
                    Text("\(budget.name) · zwölf Monate ab \(businessYearStart)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Jahr speichern") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(categoryID == nil)
            }
            .padding(14)
            Divider()
            HStack {
                Picker("Kategorie", selection: $categoryID) {
                    Text("Kategorie wählen").tag(UUID?.none)
                    ForEach(categories) { category in
                        Text(store.categoryPath(category.id)).tag(UUID?.some(category.id))
                    }
                }
                .frame(maxWidth: 420)
                Picker("Roll-over", selection: $rolloverMode) {
                    ForEach(BudgetRolloverMode.allCases) { Text($0.title).tag($0) }
                }
                .frame(width: 250)
                Spacer()
                Button("Ersten Wert auf alle Monate") {
                    guard let first = amountTexts.first else { return }
                    amountTexts = Array(repeating: first, count: 12)
                }
            }
            .padding(12)
            Divider()
            HStack {
                Text("Monat").frame(width: 150, alignment: .leading)
                Text("Basisplan").frame(width: 130, alignment: .trailing)
                Text("Ist").frame(width: 130, alignment: .trailing)
                Text("Übertrag hinein").frame(width: 130, alignment: .trailing)
                Text("Verfügbar").frame(width: 130, alignment: .trailing)
                Text("Saldo").frame(width: 130, alignment: .trailing)
            }
            .font(.caption.bold()).foregroundStyle(.secondary)
            .padding(.horizontal, 16).frame(height: 30)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(budget.months().enumerated()), id: \.offset) { index, month in
                        let row = planningRows.indices.contains(index) ? planningRows[index] : nil
                        HStack {
                            Text(month, format: .dateTime.month(.wide).year())
                                .frame(width: 150, alignment: .leading)
                            TextField("0,00", text: Binding(
                                get: { amountTexts[index] },
                                set: { amountTexts[index] = $0 }
                            ))
                            .multilineTextAlignment(.trailing).frame(width: 130)
                            Text(Money(minorUnits: row?.actualMinor ?? 0).formatted)
                                .frame(width: 130, alignment: .trailing)
                            Text(Money(minorUnits: row?.rolloverInMinor ?? 0).formatted)
                                .frame(width: 130, alignment: .trailing)
                            Text(Money(minorUnits: row?.effectivePlannedMinor ?? 0).formatted)
                                .frame(width: 130, alignment: .trailing)
                            Text(Money(minorUnits: row?.balanceMinor ?? 0).formatted)
                                .foregroundStyle((row?.balanceMinor ?? 0) < 0 ? .red : .green)
                                .frame(width: 130, alignment: .trailing)
                        }
                        .padding(.horizontal, 16).frame(height: 34)
                        Divider()
                    }
                }
            }
        }
        .frame(width: 930, height: 610)
        .onAppear {
            categoryID = categoryID ?? categories.first?.id
            loadCategory()
        }
        .onChange(of: categoryID) { loadCategory() }
    }

    private var businessYearStart: String {
        budget.months().first?.formatted(.dateTime.month(.wide).year()) ?? "—"
    }

    private func loadCategory() {
        let rows = planningRows
        amountTexts = (0..<12).map { index in
            Money(minorUnits: rows.indices.contains(index) ? rows[index].basePlannedMinor : 0)
                .editingString
        }
        rolloverMode = rows.first?.rolloverMode ?? .none
    }

    private func save() {
        guard let categoryID else { return }
        do {
            let months = budget.months()
            let values = try Dictionary(uniqueKeysWithValues: months.enumerated().map { index, month in
                (month, try Money(parsing: amountTexts[index], currency: budget.currency).minorUnits)
            })
            if store.saveBudgetYear(
                budgetID: budget.id, categoryID: categoryID,
                amounts: values, rolloverMode: rolloverMode
            ) { dismiss() }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}

private struct BudgetLineEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    let budgetID: UUID
    let month: Date
    let row: BudgetStatusRow
    @State private var amountText: String
    @State private var rolloverMode: BudgetRolloverMode

    init(budgetID: UUID, month: Date, row: BudgetStatusRow) {
        self.budgetID = budgetID
        self.month = month
        self.row = row
        _amountText = State(initialValue: Money(minorUnits: row.basePlannedMinor).editingString)
        _rolloverMode = State(initialValue: row.rolloverMode)
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
                        amount: amountText,
                        rolloverPositive: rolloverMode.rolloverPositive,
                        rolloverNegative: rolloverMode.rolloverNegative
                    ) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
            Divider()
            Form {
                Section("Plan") {
                    TextField("Monatsbetrag", text: $amountText)
                    Picker("Roll-over", selection: $rolloverMode) {
                        ForEach(BudgetRolloverMode.allCases) { Text($0.title).tag($0) }
                    }
                    LabeledContent(
                        "Übertrag aus Vormonat",
                        value: Money(minorUnits: row.rolloverMinor).formatted
                    )
                    LabeledContent(
                        "Verfügbar einschließlich Übertrag",
                        value: Money(minorUnits: row.plannedMinor).formatted
                    )
                }
                Section("Ist – aus Buchungen, nicht editierbar") {
                    if store.budgetTransactions(
                        budgetID: budgetID, categoryID: row.category.id, month: month
                    ).isEmpty {
                        Text("Keine Buchungen in diesem Monat")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.budgetTransactions(
                            budgetID: budgetID, categoryID: row.category.id, month: month
                        )) { value in
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

struct BankingView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var selectedConnectionID: UUID?
    @State private var selectedExternalAccountIDs = Set<String>()
    @State private var operations: Set<BankingOperation> = [
        .accounts, .balances, .transactions, .pendingTransactions,
        .standingOrders, .scheduledPayments
    ]
    @State private var preview: BankingDownloadPreview?
    @State private var fetchTask: Task<Void, Never>?
    @AppStorage("bankingMatchDateWindowDaysV1")
    private var dateWindowDays = ImportMatcher.defaultDateWindowDays

    private var selectedConnection: BankingConnection? {
        store.bankingConnections.first { $0.id == selectedConnectionID }
    }

    private var selectedMappings: [BankingAccountMapping] {
        guard let selectedConnectionID else { return [] }
        return store.bankingMappings.filter {
            $0.connectionID == selectedConnectionID
        }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Banking-Abruf")
                        .font(.title2.bold())
                    Spacer()
                    Button("Simulator", systemImage: "plus") {
                        if let connection = store
                            .createSimulatorBankingConnection() {
                            selectedConnectionID = connection.id
                            synchronizeSelection()
                        }
                    }
                    .help(
                        "Lokale Testverbindung ohne Zugangsdaten anlegen"
                    )
                }
                .padding(12)
                Divider()
                List(selection: $selectedConnectionID) {
                    ForEach(store.bankingConnections) { connection in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(connection.name)
                            Text(
                                "\(connection.providerKind.title) · "
                                    + connection.status.title
                            )
                            .font(.caption)
                            .foregroundStyle(
                                connection.status == .failed
                                    ? .red : .secondary
                            )
                        }
                        .tag(connection.id)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        "LIVE-BANKING DEAKTIVIERT",
                        systemImage: "lock.shield"
                    )
                    .font(.caption.bold())
                    Text(
                        "FinTS, PSD2 und Web-Connector sind als getrennte "
                            + "Adaptertypen definiert, aber nicht freigeschaltet."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(12)
            }
            .frame(minWidth: 260, idealWidth: 300)

            if let connection = selectedConnection {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        connectionHeader(connection)
                        mappingsSection(connection)
                        operationsSection
                        remoteOrdersSection(connection)
                        historySection(connection)
                    }
                    .padding(20)
                }
            } else {
                ContentUnavailableView(
                    "Keine Banking-Verbindung",
                    systemImage: "building.columns",
                    description: Text(
                        "Richte den lokalen Simulator ein. Dabei werden "
                            + "keine Zugangsdaten benötigt oder gespeichert."
                    )
                )
            }
        }
        .onAppear {
            if selectedConnectionID == nil {
                selectedConnectionID = store.bankingConnections.first?.id
            }
            synchronizeSelection()
        }
        .onChange(of: selectedConnectionID) {
            synchronizeSelection()
        }
        .sheet(item: $preview) { value in
            BankingDownloadPreviewSheet(preview: value)
                .environmentObject(store)
        }
        .onDisappear {
            fetchTask?.cancel()
        }
    }

    @ViewBuilder
    private func connectionHeader(
        _ connection: BankingConnection
    ) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(connection.name).font(.largeTitle.bold())
                Text(connection.institutionName)
                    .foregroundStyle(.secondary)
                Text(connection.adapterIdentifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Label(
                connection.status.title,
                systemImage: connection.status == .failed
                    ? "exclamationmark.triangle" : "checkmark.shield"
            )
            .foregroundStyle(
                connection.status == .failed ? .red : .green
            )
        }
        if !connection.lastUserMessage.isEmpty {
            Text(connection.lastUserMessage)
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func mappingsSection(
        _ connection: BankingConnection
    ) -> some View {
        GroupBox("Kontenliste und lokale Zuordnung") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(selectedMappings) { mapping in
                    HStack {
                        Toggle(
                            "",
                            isOn: mappingEnabledBinding(mapping)
                        )
                        .labelsHidden()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mapping.remoteName)
                            Text(
                                mapping.remoteIBAN.isEmpty
                                    ? mapping.externalAccountID
                                    : mapping.remoteIBAN
                            )
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 220, alignment: .leading)
                        Text(mapping.currency)
                            .font(.caption.monospaced())
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        Picker(
                            "Lokales Konto",
                            selection: localAccountBinding(mapping)
                        ) {
                            Text("Nicht zugeordnet").tag(UUID?.none)
                            ForEach(store.accounts.filter {
                                !$0.isClosed
                                    && $0.currency == mapping.currency
                            }) { account in
                                Text(account.name).tag(UUID?.some(account.id))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 280)
                    }
                }
                if selectedMappings.isEmpty {
                    Text("Diese Verbindung enthält noch keine Bankkonten.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }

    private var operationsSection: some View {
        GroupBox("Senden/Empfangen – nur lesen") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 190), alignment: .leading)
                    ],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(BankingOperation.allCases) { operation in
                        Toggle(
                            operation.title,
                            isOn: operationBinding(operation)
                        )
                        .disabled(
                            operation == .holdings || operation == .prices
                        )
                    }
                }
                Stepper(
                    "Matching-Datumsfenster: \(dateWindowDays) "
                        + "Tag\(dateWindowDays == 1 ? "" : "e")",
                    value: $dateWindowDays,
                    in: 0...14
                )
                HStack {
                    if store.isBusy {
                        ProgressView()
                        Text(store.bankingProgressText)
                        Button("Abruf abbrechen") {
                            fetchTask?.cancel()
                        }
                    } else {
                        Button(
                            "Abrufvorschau starten",
                            systemImage: "arrow.clockwise"
                        ) {
                            startFetch()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            selectedExternalAccountIDs.isEmpty
                                || operations.isEmpty
                        )
                    }
                    Spacer()
                    Label(
                        "Keine TAN · keine Übermittlung",
                        systemImage: "eye"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func remoteOrdersSection(
        _ connection: BankingConnection
    ) -> some View {
        let orders = store.bankingRemoteOrders.filter { order in
            selectedMappings.contains {
                $0.externalAccountID == order.externalAccountID
            }
        }
        GroupBox("Zuletzt abgerufene Daueraufträge und Terminzahlungen") {
            if orders.isEmpty {
                Text("Noch kein Bestand übernommen.")
                    .foregroundStyle(.secondary)
                    .padding(8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(orders) { order in
                        HStack {
                            Image(
                                systemName: order.isScheduledPayment
                                    ? "calendar.badge.clock"
                                    : "repeat"
                            )
                            VStack(alignment: .leading) {
                                Text(order.recipientName)
                                Text(order.purpose)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(
                                Money(
                                    minorUnits: order.amountMinor,
                                    currency: order.currency
                                ).formatted
                            )
                            .monospacedDigit()
                            Text(
                                order.nextExecutionDate,
                                format: .dateTime.day().month().year()
                            )
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private func historySection(
        _ connection: BankingConnection
    ) -> some View {
        let runs = store.bankingSyncRuns.filter {
            $0.connectionID == connection.id
        }.prefix(10)
        GroupBox("Abrufprotokoll") {
            if runs.isEmpty {
                Text("Noch kein Abruf protokolliert.")
                    .foregroundStyle(.secondary)
                    .padding(8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(runs)) { run in
                        HStack {
                            Text(
                                run.startedAt,
                                format: .dateTime.day().month().year()
                                    .hour().minute()
                            )
                            Text(run.status.title)
                                .foregroundStyle(
                                    run.status == .failed ? .red : .green
                                )
                            Text(run.userMessage)
                            Spacer()
                            Text(
                                "\(run.importedCount)/\(run.matchedCount)/"
                                    + "\(run.skippedCount)"
                            )
                            .font(.caption.monospaced())
                            .help("Neu / abgeglichen / übersprungen")
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private func synchronizeSelection() {
        selectedExternalAccountIDs = Set(
            selectedMappings.filter(\.isEnabled).map(\.externalAccountID)
        )
    }

    private func mappingEnabledBinding(
        _ mapping: BankingAccountMapping
    ) -> Binding<Bool> {
        Binding(
            get: {
                store.bankingMappings.first { $0.id == mapping.id }?
                    .isEnabled ?? false
            },
            set: { enabled in
                var updated = mapping
                updated.isEnabled = enabled
                if store.saveBankingMapping(updated) {
                    if enabled {
                        selectedExternalAccountIDs.insert(
                            mapping.externalAccountID
                        )
                    } else {
                        selectedExternalAccountIDs.remove(
                            mapping.externalAccountID
                        )
                    }
                }
            }
        )
    }

    private func localAccountBinding(
        _ mapping: BankingAccountMapping
    ) -> Binding<UUID?> {
        Binding(
            get: {
                store.bankingMappings.first { $0.id == mapping.id }?
                    .localAccountID
            },
            set: { localAccountID in
                var updated = mapping
                updated.localAccountID = localAccountID
                _ = store.saveBankingMapping(updated)
            }
        )
    }

    private func operationBinding(
        _ operation: BankingOperation
    ) -> Binding<Bool> {
        Binding(
            get: { operations.contains(operation) },
            set: { enabled in
                if enabled {
                    operations.insert(operation)
                } else {
                    operations.remove(operation)
                }
            }
        )
    }

    private func startFetch() {
        guard let selectedConnectionID else { return }
        fetchTask?.cancel()
        fetchTask = Task {
            let result = await store.previewSimulatorBankingDownload(
                connectionID: selectedConnectionID,
                externalAccountIDs: selectedExternalAccountIDs,
                operations: operations,
                dateWindowDays: dateWindowDays
            )
            guard !Task.isCancelled else { return }
            preview = result
        }
    }
}

private struct BankingDownloadPreviewSheet: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    let preview: BankingDownloadPreview
    @State private var resolutions: [UUID: ImportResolution] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Banking-Abrufvorschau")
                .font(.title2.bold())
            HStack(spacing: 18) {
                Label(
                    "\(preview.package.accounts.count) Konten",
                    systemImage: "building.columns"
                )
                Label(
                    "\(preview.package.balances.count) Salden",
                    systemImage: "equal.circle"
                )
                Label(
                    "\(preview.importPreview.rows.count) Umsätze",
                    systemImage: "list.bullet.rectangle"
                )
                Label(
                    "\(preview.package.standingOrders.count) Aufträge",
                    systemImage: "repeat"
                )
            }
            Text(
                "Noch wurde nichts gespeichert. Alle Entscheidungen, Salden "
                    + "und Bestände werden nur gemeinsam oder gar nicht übernommen."
            )
            .foregroundStyle(.secondary)
            ForEach(preview.ruleWarnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if !preview.balancesByLocalAccountID.isEmpty {
                HStack(spacing: 18) {
                    ForEach(
                        preview.balancesByLocalAccountID.keys.sorted {
                            store.accountName($0)
                                < store.accountName($1)
                        },
                        id: \.self
                    ) { accountID in
                        if let balance = preview
                            .balancesByLocalAccountID[accountID] {
                            VStack(alignment: .leading) {
                                Text(store.accountName(accountID))
                                    .font(.caption)
                                Text(
                                    Money(
                                        minorUnits: balance.bookedMinor,
                                        currency: balance.currency
                                    ).formatted
                                )
                                .font(.headline.monospacedDigit())
                            }
                        }
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }
            Table(preview.importPreview.rows) {
                TableColumn("Datum") {
                    Text(
                        $0.bookingDate,
                        format: .dateTime.day().month().year()
                    )
                }
                TableColumn("Konto") {
                    Text(store.accountName($0.accountID))
                }
                TableColumn("Empfänger", value: \.payee)
                TableColumn("Zweck", value: \.purpose)
                TableColumn("Betrag") {
                    Text(
                        Money(
                            minorUnits: $0.amountMinor,
                            currency: $0.currency
                        ).formatted
                    )
                    .monospacedDigit()
                }
                TableColumn("Status") {
                    Text($0.status.title)
                }
                TableColumn("Regeln") { transaction in
                    Text(
                        preview.appliedRuleNamesByTransactionID[
                            transaction.id
                        ]?.joined(separator: ", ") ?? "—"
                    )
                    .lineLimit(1)
                    .help(
                        preview.appliedRuleNamesByTransactionID[
                            transaction.id
                        ]?.joined(separator: "\n") ?? "Keine Regel angewandt"
                    )
                }
                TableColumn("Entscheidung") { transaction in
                    decisionPicker(transaction)
                }
                .width(min: 190, ideal: 280)
            }
            .frame(minHeight: 280)
            DisclosureGroup("Technische Abrufdiagnose") {
                ForEach(preview.package.diagnostics) { diagnostic in
                    HStack {
                        Image(
                            systemName: diagnostic.isSuccess
                                ? "checkmark.circle" : "xmark.octagon"
                        )
                        Text(diagnostic.operation.title)
                        Text(diagnostic.userMessage)
                        Spacer()
                        Text(diagnostic.technicalCode)
                            .font(.caption.monospaced())
                    }
                }
                Text(
                    "Rohpayload-Hash: "
                        + preview.package.rawPayloadHash
                )
                .font(.caption.monospaced())
                .textSelection(.enabled)
            }
            HStack {
                Button("Abbrechen") { dismiss() }
                Spacer()
                Button("Paket atomar übernehmen") {
                    if store.commitBankingDownload(
                        preview,
                        resolutions: resolutions
                    ) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 1050, minHeight: 620)
        .onAppear {
            resolutions = Dictionary(
                uniqueKeysWithValues: preview.importPreview.rows.map {
                    (
                        $0.id,
                        preview.importPreview.matches[$0.id]?
                            .suggestedResolution ?? .importNew
                    )
                }
            )
        }
    }

    private func decisionPicker(
        _ transaction: FinanceTransaction
    ) -> some View {
        let assessment = preview.importPreview.matches[transaction.id]
        return Picker(
            "Entscheidung",
            selection: Binding(
                get: {
                    resolutions[transaction.id]
                        ?? assessment?.suggestedResolution
                        ?? .importNew
                },
                set: { resolutions[transaction.id] = $0 }
            )
        ) {
            Text("Neu importieren").tag(ImportResolution.importNew)
            Text("Überspringen").tag(ImportResolution.skip)
            ForEach(
                assessment?.candidates.filter(\.isFinanciallyCompatible)
                    ?? []
            ) { candidate in
                Text(candidateText(candidate))
                .tag(ImportResolution.match(candidate.transactionID))
            }
        }
        .labelsHidden()
        .help(
            assessment?.bestCandidate?.reasons.joined(separator: "\n")
                ?? "Kein vorhandener Kandidat"
        )
    }

    private func candidateText(
        _ candidate: ImportMatchCandidate
    ) -> String {
        let payee = store.transactions.first {
            $0.id == candidate.transactionID
        }?.payee ?? candidate.tier.title
        return "Abgleichen: \(payee) · \(candidate.score)"
    }
}

struct PaymentsView: View {
    private enum PaymentSection: String, CaseIterable, Identifiable {
        case payments = "Überweisungen"
        case directDebits = "Lastschriften"
        case batches = "Sammler"
        case instructionImports = "Dateiimporte"
        case statusReports = "Statusberichte"
        case standingOrders = "Daueraufträge"
        var id: Self { self }
    }

    @EnvironmentObject private var store: FinanceAppStore
    @State private var selectedID: UUID?
    @State private var selectedDirectDebitID: UUID?
    @State private var selectedStandingOrderID: UUID?
    @State private var selectedBatchID: UUID?
    @State private var selectedStatusReportID: String?
    @State private var selectedInstructionImportID: String?
    @State private var section: PaymentSection = .payments
    @State private var showNewPayment = false
    @State private var showNewDirectDebit = false
    @State private var showNewBatch = false
    @State private var showStatusImporter = false
    @State private var showInstructionImporter = false
    @State private var statusPreview: Pain002Preview?
    @State private var instructionPreview: PainInstructionPreview?
    @State private var editedPaymentOrder: PaymentOrder?
    @State private var editedStandingOrder: StandingOrder?

    private var selectedOrder: PaymentOrder? {
        store.paymentOrders.first { $0.id == selectedID }
    }

    private var selectedStandingOrder: StandingOrder? {
        store.standingOrders.first { $0.id == selectedStandingOrderID }
    }

    private var selectedDirectDebit: DirectDebitOrder? {
        store.directDebitOrders.first { $0.id == selectedDirectDebitID }
    }

    private var selectedBatch: PaymentBatch? {
        store.paymentBatches.first { $0.id == selectedBatchID }
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
                .frame(width: 760)
                Button {
                    switch section {
                    case .payments:
                        showNewPayment = true
                    case .directDebits:
                        showNewDirectDebit = true
                    case .batches:
                        showNewBatch = true
                    case .instructionImports:
                        showInstructionImporter = true
                    case .statusReports:
                        showStatusImporter = true
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
                        section == .payments
                            ? "Überweisung"
                            : (section == .directDebits
                                ? "Lastschrift"
                                : (section == .batches
                                    ? "Sammler"
                                    : (section == .instructionImports
                                        ? "pain.001/.008"
                                        : (section == .statusReports
                                            ? "pain.002" : "Dauerauftrag")))),
                        systemImage: section == .statusReports
                            || section == .instructionImports
                            ? "doc.badge.arrow.down" : "plus"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    section == .statusReports || section == .instructionImports
                        ? false
                        : (section == PaymentSection.standingOrders
                        ? !store.accounts.contains(where: {
                            !$0.isClosed && $0.currency == "EUR"
                        })
                        : (section == .batches
                            ? (
                                store.paymentOrders.filter({ $0.status == .draft }).count < 2
                                    && store.directDebitOrders.filter({ $0.status == .draft }).count < 2
                            )
                            : store.accounts.isEmpty))
                )
            }
            .padding(12)
            Divider()
            switch section {
            case .payments:
                paymentOrdersContent
            case .directDebits:
                directDebitsContent
            case .batches:
                batchesContent
            case .instructionImports:
                instructionImportsContent
            case .statusReports:
                statusReportsContent
            case .standingOrders:
                standingOrdersContent
            }
        }
        .onAppear {
            if selectedID == nil { selectedID = store.paymentOrders.first?.id }
            if selectedDirectDebitID == nil {
                selectedDirectDebitID = store.directDebitOrders.first?.id
            }
            if selectedStandingOrderID == nil {
                selectedStandingOrderID = store.standingOrders.first?.id
            }
            if selectedBatchID == nil {
                selectedBatchID = store.paymentBatches.first?.id
            }
            if selectedStatusReportID == nil {
                selectedStatusReportID = store.paymentStatusReports.first?.id
            }
            if selectedInstructionImportID == nil {
                selectedInstructionImportID = store.paymentInstructionImports.first?.id
            }
        }
        .sheet(isPresented: $showNewPayment) {
            PaymentDraftEditor()
        }
        .sheet(item: $editedPaymentOrder) {
            PaymentDraftEditor(order: $0)
        }
        .sheet(isPresented: $showNewDirectDebit) {
            DirectDebitDraftEditor()
        }
        .sheet(isPresented: $showNewBatch) {
            PaymentBatchDraftEditor()
        }
        .sheet(item: $statusPreview) { preview in
            Pain002PreviewSheet(preview: preview)
        }
        .sheet(item: $instructionPreview) { preview in
            PainInstructionPreviewSheet(preview: preview)
        }
        .fileImporter(
            isPresented: $showStatusImporter,
            allowedContentTypes: [.xml], allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                statusPreview = store.previewPaymentStatusReport(
                    data: try Data(contentsOf: url)
                )
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $showInstructionImporter,
            allowedContentTypes: [.xml], allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                instructionPreview = store.previewPaymentInstructionImport(
                    data: try Data(contentsOf: url)
                )
            } catch {
                store.errorMessage = error.localizedDescription
            }
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
                PaymentOrderDetail(
                    order: selectedOrder,
                    edit: { editedPaymentOrder = selectedOrder }
                )
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

    private var directDebitsContent: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("SEPA-Basislastschriften").font(.headline)
                    Spacer()
                    Text("\(store.directDebitOrders.count)")
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                Divider()
                if store.directDebitOrders.isEmpty {
                    ContentUnavailableView(
                        "Keine Lastschriftaufträge",
                        systemImage: "arrow.down.to.line.compact",
                        description: Text(
                            "Lege einen lokalen Entwurf aus Zahlerakte, Bankverbindung und aktivem Mandat an."
                        )
                    )
                } else {
                    List(selection: $selectedDirectDebitID) {
                        ForEach(store.directDebitOrders) { order in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(order.debtorName).fontWeight(.medium)
                                    Spacer()
                                    Text(Money(minorUnits: order.amountMinor).formatted)
                                        .monospacedDigit()
                                }
                                HStack {
                                    PaymentStatusBadge(status: order.status)
                                    Text(
                                        order.collectionDate,
                                        format: .dateTime.day().month().year()
                                    )
                                    Spacer()
                                    Text(order.sequenceType.title)
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

            if let selectedDirectDebit {
                DirectDebitOrderDetail(order: selectedDirectDebit)
                    .id(selectedDirectDebit)
                    .frame(minWidth: 520)
            } else {
                ContentUnavailableView(
                    "Keine Lastschrift ausgewählt",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Wähle links einen Lastschriftauftrag.")
                )
                .frame(minWidth: 520)
            }
        }
    }

    private var batchesContent: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("SEPA-Sammler").font(.headline)
                    Spacer()
                    Text("\(store.paymentBatches.count)")
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                Divider()
                if store.paymentBatches.isEmpty {
                    ContentUnavailableView(
                        "Keine Sammler",
                        systemImage: "square.stack.3d.up",
                        description: Text(
                            "Fasse mindestens zwei kompatible Entwürfe zu einer Sammelüberweisung oder Sammellastschrift zusammen."
                        )
                    )
                } else {
                    List(selection: $selectedBatchID) {
                        ForEach(store.paymentBatches) { batch in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(batch.name).fontWeight(.medium)
                                    Spacer()
                                    Text(
                                        Money(
                                            minorUnits: batchTotal(batch),
                                            currency: "EUR"
                                        ).formatted
                                    )
                                    .monospacedDigit()
                                }
                                HStack {
                                    PaymentStatusBadge(status: batch.status)
                                    Text("\(batch.memberOrderIDs.count) Aufträge")
                                    Spacer()
                                    Text(batch.kind.title)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .tag(batch.id)
                        }
                    }
                }
            }
            .frame(minWidth: 390, idealWidth: 470)

            if let selectedBatch {
                PaymentBatchDetail(batch: selectedBatch)
                    .id(selectedBatch)
                    .frame(minWidth: 520)
            } else {
                ContentUnavailableView(
                    "Kein Sammler ausgewählt",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Wähle links einen SEPA-Sammler.")
                )
                .frame(minWidth: 520)
            }
        }
    }

    private var statusReportsContent: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("pain.002-Importhistorie").font(.headline)
                    Spacer()
                    Text("\(store.paymentStatusReports.count)")
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                Divider()
                if store.paymentStatusReports.isEmpty {
                    ContentUnavailableView(
                        "Keine Statusberichte",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(
                            "Importiere einen pain.002.001.10-Bericht. Vor jeder Übernahme erscheint eine unveränderliche Vorschau."
                        )
                    )
                } else {
                    List(selection: $selectedStatusReportID) {
                        ForEach(store.paymentStatusReports) { report in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(report.messageID).fontWeight(.medium)
                                HStack {
                                    Text("\(report.recordCount) Positionen")
                                    Text("·")
                                    Text("\(report.appliedCount) übernommen")
                                    Spacer()
                                    Text(
                                        report.importedAt,
                                        format: .dateTime.day().month().year()
                                            .hour().minute()
                                    )
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .tag(report.id)
                        }
                    }
                }
            }
            .frame(minWidth: 390, idealWidth: 470)
            if let reportID = selectedStatusReportID,
               let report = store.paymentStatusReports.first(where: {
                   $0.id == reportID
               }) {
                PaymentStatusReportDetail(
                    report: report,
                    items: store.paymentStatusReportItems(reportID: reportID)
                )
                .id(reportID)
                .frame(minWidth: 520)
            } else {
                ContentUnavailableView(
                    "Kein Statusbericht ausgewählt",
                    systemImage: "doc.text.magnifyingglass"
                )
                .frame(minWidth: 520)
            }
        }
    }

    private var instructionImportsContent: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("pain.001/.008-Importhistorie").font(.headline)
                    Spacer()
                    Text("\(store.paymentInstructionImports.count)")
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                Divider()
                if store.paymentInstructionImports.isEmpty {
                    ContentUnavailableView(
                        "Keine Auftragsimporte",
                        systemImage: "doc.badge.arrow.down",
                        description: Text(
                            "Importiere pain.001.001.09 oder pain.008.001.08 als lokale Entwürfe."
                        )
                    )
                } else {
                    List(selection: $selectedInstructionImportID) {
                        ForEach(store.paymentInstructionImports) { value in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(value.messageID).fontWeight(.medium)
                                HStack {
                                    Text(value.kind.title)
                                    Text("· \(value.importedCount)/\(value.recordCount) übernommen")
                                    Spacer()
                                    Text(
                                        value.importedAt,
                                        format: .dateTime.day().month().year().hour().minute()
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
            if let importID = selectedInstructionImportID,
               let value = store.paymentInstructionImports.first(where: {
                   $0.id == importID
               }) {
                PaymentInstructionImportDetail(
                    summary: value,
                    items: store.paymentInstructionImportItems(importID: importID)
                )
                .id(importID)
                .frame(minWidth: 520)
            } else {
                ContentUnavailableView(
                    "Kein Auftragsimport ausgewählt",
                    systemImage: "doc.text.magnifyingglass"
                )
                .frame(minWidth: 520)
            }
        }
    }

    private func batchTotal(_ batch: PaymentBatch) -> Int64 {
        switch batch.kind {
        case .creditTransfer:
            return store.paymentOrders
                .filter { batch.memberOrderIDs.contains($0.id) }
                .reduce(Int64.zero) { $0 + $1.amountMinor }
        case .directDebit:
            return store.directDebitOrders
                .filter { batch.memberOrderIDs.contains($0.id) }
                .reduce(Int64.zero) { $0 + $1.amountMinor }
        }
    }
}

private struct PainInstructionPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    let preview: PainInstructionPreview
    @State private var selectedIDs: Set<UUID>
    @State private var confirmImport = false

    init(preview: PainInstructionPreview) {
        self.preview = preview
        _selectedIDs = State(
            initialValue: Set(preview.matches.filter(\.canImport).map(\.id))
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(preview.document.kind.title)sdatei prüfen")
                        .font(.title2.bold())
                    Text("Nachricht \(preview.document.messageID)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Auswahl als Entwürfe importieren …") {
                    confirmImport = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedIDs.isEmpty)
            }
            .padding(14)
            Divider()
            HStack(spacing: 18) {
                LabeledContent("Positionen", value: "\(preview.matches.count)")
                LabeledContent("Importierbar", value: "\(preview.importableCount)")
                LabeledContent("Ausgewählt", value: "\(selectedIDs.count)")
                Spacer()
            }
            .padding(12)
            Divider()
            List {
                ForEach(preview.matches) { match in
                    Toggle(isOn: selection(match)) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(match.record.counterpartyName).fontWeight(.medium)
                                Text(match.record.purpose)
                                Text(
                                    "\(match.accountTitle) · \(match.record.counterpartyIBAN) · \(match.explanation)"
                                )
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(
                                    Money(
                                        minorUnits: match.record.amountMinor,
                                        currency: "EUR"
                                    ).formatted
                                )
                                .monospacedDigit()
                                Text(
                                    match.record.requestedDate,
                                    format: .dateTime.day().month().year()
                                )
                                .font(.caption)
                            }
                        }
                    }
                    .disabled(!match.canImport)
                }
                if !preview.document.warnings.isEmpty {
                    Section("Hinweise") {
                        ForEach(preview.document.warnings, id: \.self) {
                            Label($0, systemImage: "exclamationmark.triangle")
                        }
                    }
                }
            }
            Text(
                "Der Import erzeugt ausschließlich lokale Entwürfe. Er sendet nichts, erzeugt keine Buchung und speichert keine Freigabedaten. Vollständig gewählte Mehrpositionsblöcke werden als Sammler rekonstruiert."
            )
            .font(.caption).foregroundStyle(.secondary).padding(12)
        }
        .frame(width: 980, height: 720)
        .alert("Zahlungsdatei verbindlich importieren?", isPresented: $confirmImport) {
            Button("Abbrechen", role: .cancel) {}
            Button("\(selectedIDs.count) Entwürfe importieren") {
                if store.commitPaymentInstructionImport(
                    preview, importing: selectedIDs
                ) { dismiss() }
            }
        } message: {
            Text(
                "Zuordnungen werden unmittelbar vor dem atomaren Commit erneut geprüft. Derselbe Dateifingerprint kann nur einmal importiert werden."
            )
        }
    }

    private func selection(_ match: PainInstructionMatch) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(match.id) },
            set: { value in
                if value { selectedIDs.insert(match.id) }
                else { selectedIDs.remove(match.id) }
            }
        )
    }
}

private struct RestoreBackupPreviewSheet: View {
    let preview: FinanceBackupPreview
    let sourceName: String
    let cancel: () -> Void
    let restore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Sicherung wiederherstellen", systemImage: "clock.arrow.circlepath")
                .font(.title2.bold())
            Text(
                "Prüfe den Inhalt, bevor die aktive Finanzdatei ersetzt wird. "
                    + "Unmittelbar davor erstellt FinanzVerwalter eine zusätzliche Sicherung."
            )
            .foregroundStyle(.secondary)
            GroupBox("Geprüfter Inhalt") {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    previewRow("Datei", sourceName)
                    previewRow("Finanzdatei", preview.financeFileName)
                    previewRow("Basiswährung", preview.baseCurrency)
                    previewRow("Datenbankschema", "\(preview.schemaVersion)")
                    previewRow("Konten", "\(preview.accountCount)")
                    previewRow("Kategorien", "\(preview.categoryCount)")
                    previewRow("Buchungen", "\(preview.transactionCount)")
                    previewRow(
                        "Jüngste Buchung",
                        preview.latestBookingDate?.formatted(
                            date: .long, time: .omitted
                        ) ?? "Keine Buchung"
                    )
                    previewRow(
                        "Dateigröße",
                        ByteCountFormatter.string(
                            fromByteCount: preview.byteCount, countStyle: .file
                        )
                    )
                    previewRow(
                        "Dateistand",
                        preview.modifiedAt?.formatted(
                            date: .abbreviated, time: .shortened
                        ) ?? "Unbekannt"
                    )
                }
                .padding(8)
            }
            Label(
                "Die Sicherung ist integer und mit dieser App-Version kompatibel.",
                systemImage: "checkmark.shield"
            )
            .foregroundStyle(.green)
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Geprüft wiederherstellen", role: .destructive, action: restore)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 560)
        .interactiveDismissDisabled()
        .accessibilityIdentifier("restoreBackupPreview")
    }

    @ViewBuilder
    private func previewRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

private struct PaymentInstructionImportDetail: View {
    let summary: PaymentInstructionImportSummary
    let items: [PaymentInstructionImportItem]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(summary.messageID).font(.title2.bold())
                GroupBox("Unveränderlicher Importnachweis") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                        GridRow { Text("Format"); Text(summary.kind.title) }
                        GridRow { Text("Fingerprint"); Text(summary.id).font(.caption.monospaced()) }
                        GridRow { Text("Importiert"); Text(summary.importedAt.formatted()) }
                        GridRow { Text("Positionen"); Text("\(summary.recordCount)") }
                        GridRow { Text("Entwürfe"); Text("\(summary.importedCount)") }
                        GridRow { Text("Hinweise"); Text("\(summary.warningCount)") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                GroupBox("Auftragspositionen") {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.imported ? "checkmark.circle.fill" : "minus.circle")
                                    .foregroundStyle(item.imported ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.counterpartyName).fontWeight(.medium)
                                    Text(item.purpose)
                                    Text("\(item.accountTitle) · \(item.counterpartyIBAN)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Money(minorUnits: item.amountMinor, currency: "EUR").formatted)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 7)
                            if item.id != items.last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .padding(20)
        }
    }
}

private struct Pain002PreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    let preview: Pain002Preview
    @State private var selectedIDs: Set<UUID>
    @State private var confirmImport = false

    init(preview: Pain002Preview) {
        self.preview = preview
        _selectedIDs = State(
            initialValue: Set(preview.matches.filter(\.canApply).map(\.id))
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("pain.002-Vorschau").font(.title2.bold())
                    Text("Nachricht \(preview.document.messageID)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Auswahl übernehmen …") { confirmImport = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(14)
            Divider()
            HStack(spacing: 18) {
                LabeledContent("Positionen", value: "\(preview.matches.count)")
                LabeledContent("Final anwendbar", value: "\(preview.applicableCount)")
                LabeledContent("Nicht zugeordnet", value: "\(preview.unresolvedCount)")
                LabeledContent("Ausgewählt", value: "\(selectedIDs.count)")
                Spacer()
            }
            .padding(12)
            Divider()
            List {
                ForEach(preview.matches) { match in
                    Toggle(isOn: selection(match)) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(match.record.statusCode)
                                .font(.caption.bold().monospaced())
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(statusColor(match).opacity(0.14), in: Capsule())
                                .foregroundStyle(statusColor(match))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(match.targetTitle).fontWeight(.medium)
                                Text(match.explanation)
                                    .font(.caption).foregroundStyle(.secondary)
                                if !match.record.reasonCode.isEmpty
                                    || !match.record.reasonText.isEmpty {
                                    Text(
                                        [match.record.reasonCode, match.record.reasonText]
                                            .filter { !$0.isEmpty }.joined(separator: " · ")
                                    )
                                    .font(.caption)
                                }
                            }
                            Spacer()
                            if let current = match.currentStatus {
                                Text(current.title)
                                Image(systemName: "arrow.right")
                                Text(match.proposedStatus?.title ?? "nur Historie")
                            }
                        }
                    }
                    .disabled(!match.canApply)
                }
                if !preview.document.warnings.isEmpty {
                    Section("Hinweise") {
                        ForEach(preview.document.warnings, id: \.self) {
                            Label($0, systemImage: "exclamationmark.triangle")
                        }
                    }
                }
            }
            Text(
                "Alle Positionen werden unveränderlich historisiert. Nur ausdrücklich ausgewählte finale ACSC-/RJCT-Positionen ändern lokale Aufträge; der gesamte Commit ist atomar."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
        }
        .frame(width: 980, height: 720)
        .alert("Statusbericht verbindlich importieren?", isPresented: $confirmImport) {
            Button("Abbrechen", role: .cancel) {}
            Button("\(selectedIDs.count) Status übernehmen") {
                if store.commitPaymentStatusReport(
                    preview, applying: selectedIDs
                ) { dismiss() }
            }
        } message: {
            Text(
                "Die Datei wird einmalig anhand ihres SHA-256-Fingerprints importiert. Finale Status und daraus entstehende Buchungen werden gemeinsam oder gar nicht übernommen."
            )
        }
    }

    private func selection(_ match: Pain002Match) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(match.id) },
            set: { selected in
                if selected { selectedIDs.insert(match.id) }
                else { selectedIDs.remove(match.id) }
            }
        )
    }

    private func statusColor(_ match: Pain002Match) -> Color {
        switch match.proposedStatus {
        case .accepted: .green
        case .rejected: .red
        default: .orange
        }
    }
}

private struct PaymentStatusReportDetail: View {
    let report: PaymentStatusReportSummary
    let items: [PaymentStatusReportItem]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(report.messageID).font(.title2.bold())
                GroupBox("Unveränderlicher Importnachweis") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                        GridRow { Text("Fingerprint"); Text(report.id).font(.caption.monospaced()) }
                        GridRow { Text("Importiert"); Text(report.importedAt.formatted()) }
                        GridRow { Text("Positionen"); Text("\(report.recordCount)") }
                        GridRow { Text("Übernommen"); Text("\(report.appliedCount)") }
                        GridRow { Text("Hinweise"); Text("\(report.warningCount)") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                GroupBox("Statuspositionen") {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Text(item.statusCode).font(.caption.bold().monospaced())
                                    .frame(width: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.targetTitle).fontWeight(.medium)
                                    Text(
                                        [item.reasonCode, item.reasonText]
                                            .filter { !$0.isEmpty }.joined(separator: " · ")
                                    )
                                    .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.appliedStatus?.title ?? "nur historisiert")
                                    .font(.caption)
                            }
                            .padding(.vertical, 7)
                            if item.id != items.last?.id { Divider() }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(18)
        }
    }
}

private struct PaymentBatchDraftEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    @State private var name = "Neuer SEPA-Sammler"
    @State private var kind = PaymentBatchKind.creditTransfer
    @State private var selectedIDs: Set<UUID> = []

    private var alreadyBatchedIDs: Set<UUID> {
        Set(store.paymentBatches.flatMap(\.memberOrderIDs))
    }

    private var creditCandidates: [PaymentOrder] {
        store.paymentOrders.filter { order in
            order.status == .draft
                && order.currency.uppercased() == "EUR"
                && !alreadyBatchedIDs.contains(order.id)
                && store.accounts.contains { account in
                    account.id == order.accountID && !account.isClosed
                }
        }
    }

    private var debitCandidates: [DirectDebitOrder] {
        store.directDebitOrders.filter {
            $0.status == .draft && !alreadyBatchedIDs.contains($0.id)
        }
    }

    private var totalMinor: Int64 {
        switch kind {
        case .creditTransfer:
            creditCandidates.filter { selectedIDs.contains($0.id) }
                .reduce(Int64.zero) { $0 + $1.amountMinor }
        case .directDebit:
            debitCandidates.filter { selectedIDs.contains($0.id) }
                .reduce(Int64.zero) { $0 + $1.amountMinor }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SEPA-Sammler anlegen").font(.title2.bold())
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Entwurf anlegen") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || selectedIDs.count < 2
                    )
            }
            .padding(14)
            Divider()
            Form {
                Section("Sammler") {
                    TextField("Bezeichnung", text: $name)
                    Picker("Art", selection: $kind) {
                        ForEach(PaymentBatchKind.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) {
                        selectedIDs.removeAll()
                        name = kind == .creditTransfer
                            ? "Neue Sammelüberweisung" : "Neue Sammellastschrift"
                    }
                }
                Section("Kompatible Entwürfe") {
                    if kind == .creditTransfer {
                        if creditCandidates.isEmpty {
                            Text("Keine freien Überweisungsentwürfe vorhanden.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(creditCandidates) { order in
                            Toggle(isOn: selectionBinding(order.id)) {
                                batchCandidateLabel(
                                    name: order.recipientName,
                                    amount: order.amountMinor,
                                    date: order.executionDate,
                                    detail: store.accountName(order.accountID)
                                        + " · " + order.type.title
                                )
                            }
                            .disabled(!isCompatible(order))
                        }
                    } else {
                        if debitCandidates.isEmpty {
                            Text("Keine freien Lastschriftentwürfe vorhanden.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(debitCandidates) { order in
                            Toggle(isOn: selectionBinding(order.id)) {
                                batchCandidateLabel(
                                    name: order.debtorName,
                                    amount: order.amountMinor,
                                    date: order.collectionDate,
                                    detail: store.accountName(order.creditorAccountID)
                                        + " · " + order.sequenceType.title
                                )
                            }
                            .disabled(!isCompatible(order))
                        }
                    }
                }
                Section("Unveränderliche Vorschau") {
                    LabeledContent("Aufträge", value: "\(selectedIDs.count)")
                    LabeledContent(
                        "Gesamtsumme",
                        value: Money(minorUnits: totalMinor, currency: "EUR").formatted
                    )
                    Label(
                        "Nach dem Anlegen sind Mitglieder, Reihenfolge, gemeinsames Konto und Datum eingefroren.",
                        systemImage: "lock.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 760, height: 760)
    }

    @ViewBuilder
    private func batchCandidateLabel(
        name: String,
        amount: Int64,
        date: Date,
        detail: String
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money(minorUnits: amount, currency: "EUR").formatted)
                    .monospacedDigit()
                Text(date, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func selectionBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { selected in
                if selected { selectedIDs.insert(id) }
                else { selectedIDs.remove(id) }
            }
        )
    }

    private func isCompatible(_ order: PaymentOrder) -> Bool {
        guard let selectedID = selectedIDs.sorted(by: {
            $0.uuidString < $1.uuidString
        }).first,
              let baseline = creditCandidates.first(where: {
                  $0.id == selectedID
              }) else { return true }
        return order.accountID == baseline.accountID
            && order.type == baseline.type
            && Calendar.current.isDate(
                order.executionDate, inSameDayAs: baseline.executionDate
            )
    }

    private func isCompatible(_ order: DirectDebitOrder) -> Bool {
        guard let selectedID = selectedIDs.sorted(by: {
            $0.uuidString < $1.uuidString
        }).first,
              let baseline = debitCandidates.first(where: {
                  $0.id == selectedID
              }) else { return true }
        return order.creditorAccountID == baseline.creditorAccountID
            && order.sequenceType == baseline.sequenceType
            && order.creditorID == baseline.creditorID
            && order.creditorName == baseline.creditorName
            && order.creditorIBAN == baseline.creditorIBAN
            && order.creditorBIC == baseline.creditorBIC
            && Calendar.current.isDate(
                order.collectionDate, inSameDayAs: baseline.collectionDate
            )
    }

    private func save() {
        if store.createPaymentBatch(
            name: name, kind: kind, memberOrderIDs: selectedIDs
        ) {
            dismiss()
        }
    }
}

private struct PaymentBatchDetail: View {
    @EnvironmentObject private var store: FinanceAppStore
    let batch: PaymentBatch
    @State private var confirmInitiation = false
    @State private var confirmCancellation = false
    @State private var authorizationCode = ""
    @State private var showExporter = false
    @State private var exportDocument = Pain001Document(data: Data())
    @State private var exportFileName = "SEPA-Sammler.xml"

    private var paymentMembers: [PaymentOrder] {
        batch.memberOrderIDs.compactMap { id in
            store.paymentOrders.first { $0.id == id }
        }
    }

    private var debitMembers: [DirectDebitOrder] {
        batch.memberOrderIDs.compactMap { id in
            store.directDebitOrders.first { $0.id == id }
        }
    }

    private var totalMinor: Int64 {
        switch batch.kind {
        case .creditTransfer:
            paymentMembers.reduce(Int64.zero) { $0 + $1.amountMinor }
        case .directDebit:
            debitMembers.reduce(Int64.zero) { $0 + $1.amountMinor }
        }
    }

    private var statusPath: [PaymentStatus] {
        var values: [PaymentStatus] = [
            .initiated, .challengeReceived, .awaitingUser, .submitted
        ]
        if [.accepted, .rejected, .unknown, .cancelled].contains(batch.status) {
            values.append(batch.status)
        }
        return values
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(batch.name).font(.title2.bold())
                        Text(batch.kind.title).foregroundStyle(.secondary)
                    }
                    Spacer()
                    PaymentStatusBadge(status: batch.status)
                }
                GroupBox("Unveränderliche Sammlerzusammenfassung") {
                    Grid(
                        alignment: .leading,
                        horizontalSpacing: 18,
                        verticalSpacing: 8
                    ) {
                        GridRow {
                            Text("Konto").foregroundStyle(.secondary)
                            Text(store.accountName(batch.accountID))
                        }
                        GridRow {
                            Text("Datum").foregroundStyle(.secondary)
                            Text(
                                batch.requestedDate,
                                format: .dateTime.day().month().year()
                            )
                        }
                        GridRow {
                            Text("Aufträge").foregroundStyle(.secondary)
                            Text("\(batch.memberOrderIDs.count)")
                        }
                        GridRow {
                            Text("Gesamtsumme").foregroundStyle(.secondary)
                            Text(
                                Money(minorUnits: totalMinor, currency: "EUR").formatted
                            )
                            .bold()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                GroupBox("Enthaltene Aufträge") {
                    VStack(spacing: 0) {
                        if batch.kind == .creditTransfer {
                            ForEach(Array(paymentMembers.enumerated()), id: \.element.id) {
                                index, order in
                                memberRow(
                                    index: index, name: order.recipientName,
                                    purpose: order.purpose,
                                    amount: order.amountMinor
                                )
                                if index != paymentMembers.indices.last { Divider() }
                            }
                        } else {
                            ForEach(Array(debitMembers.enumerated()), id: \.element.id) {
                                index, order in
                                memberRow(
                                    index: index, name: order.debtorName,
                                    purpose: order.purpose,
                                    amount: order.amountMinor
                                )
                                if index != debitMembers.indices.last { Divider() }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                GroupBox("Lokaler Übermittlungszustand") {
                    HStack(spacing: 5) {
                        ForEach(statusPath, id: \.self) { status in
                            PaymentStatusBadge(status: status)
                            if status != statusPath.last {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                actionArea
                Button(
                    batch.kind == .creditTransfer
                        ? "Sammel-pain.001 exportieren …"
                        : "Sammel-pain.008 exportieren …",
                    systemImage: "doc.badge.arrow.up"
                ) {
                    prepareExport()
                }
                .disabled(batch.status != .draft)
                if batch.status == .unknown {
                    Label(
                        "Der Status ist unbekannt. Der Sammler wird niemals automatisch erneut eingereicht.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
                Text("Idempotenz: \(batch.idempotencyKey.prefix(20))…")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
        }
        .alert("SEPA-Sammler vorbereiten?", isPresented: $confirmInitiation) {
            Button("Abbrechen", role: .cancel) {}
            Button("Im Simulator initialisieren") {
                _ = store.transitionPaymentBatch(batch, to: .initiated)
            }
        } message: {
            Text(
                "\(batch.memberOrderIDs.count) Aufträge über insgesamt "
                    + Money(minorUnits: totalMinor, currency: "EUR").formatted
                    + " werden gemeinsam vorbereitet. Dies ist ausschließlich eine lokale Simulation."
            )
        }
        .alert("SEPA-Sammler abbrechen?", isPresented: $confirmCancellation) {
            Button("Nicht abbrechen", role: .cancel) {}
            Button("Sammler abbrechen", role: .destructive) {
                _ = store.transitionPaymentBatch(batch, to: .cancelled)
            }
        } message: {
            Text(
                "Der Sammler und alle \(batch.memberOrderIDs.count) enthaltenen Aufträge bleiben mit ihrem Auditverlauf erhalten und werden gemeinsam abgebrochen."
            )
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .xml,
            defaultFilename: exportFileName
        ) { result in
            switch result {
            case .success:
                store.statusText = "SEPA-Sammler exportiert"
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
    }

    private func memberRow(
        index: Int,
        name: String,
        purpose: String,
        amount: Int64
    ) -> some View {
        HStack(alignment: .top) {
            Text("\(index + 1).")
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).fontWeight(.medium)
                Text(purpose).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money(minorUnits: amount, currency: "EUR").formatted)
                .monospacedDigit()
        }
        .padding(.vertical, 7)
    }

    private func prepareExport() {
        guard let account = store.accounts.first(where: {
            $0.id == batch.accountID
        }) else {
            store.errorMessage = FinanceError.missingAccount.localizedDescription
            return
        }
        do {
            switch batch.kind {
            case .creditTransfer:
                let result = try Pain001Exporter.export(
                    batch: batch, orders: paymentMembers, account: account
                )
                exportDocument = Pain001Document(data: result.data)
                exportFileName = result.fileName
            case .directDebit:
                let result = try Pain008Exporter.export(
                    batch: batch, orders: debitMembers, account: account
                )
                exportDocument = Pain001Document(data: result.data)
                exportFileName = result.fileName
            }
            showExporter = true
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        switch batch.status {
        case .draft:
            HStack {
                Button("Gemeinsame Einreichung vorbereiten …") {
                    confirmInitiation = true
                }
                .buttonStyle(.borderedProminent)
                Button("Sammler abbrechen …", role: .destructive) {
                    confirmCancellation = true
                }
            }
        case .initiated:
            Button("Bank-Challenge simulieren") {
                _ = store.transitionPaymentBatch(batch, to: .challengeReceived)
            }
            .buttonStyle(.borderedProminent)
        case .challengeReceived:
            Button("Freigabedialog öffnen") {
                _ = store.transitionPaymentBatch(batch, to: .awaitingUser)
            }
            .buttonStyle(.borderedProminent)
        case .awaitingUser:
            VStack(alignment: .leading, spacing: 8) {
                SecureField("Simulierter Freigabecode", text: $authorizationCode)
                    .frame(maxWidth: 320)
                Text("Der Code wird niemals gespeichert oder protokolliert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Sammler freigeben") {
                    if store.submitPaymentBatch(
                        batch, authorizationCode: authorizationCode
                    ) {
                        authorizationCode = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Sammler abbrechen …", role: .destructive) {
                    confirmCancellation = true
                }
            }
        case .submitted:
            VStack(alignment: .leading, spacing: 8) {
                Text("Simulator-Ergebnis").font(.headline)
                HStack {
                    ForEach(SimulatorOutcome.allCases) { outcome in
                        Button(outcome.title) {
                            _ = store.simulatePaymentBatchDecision(
                                batch, outcome: outcome
                            )
                        }
                    }
                }
            }
        case .accepted:
            Label(
                "Angenommen · alle Aufträge wurden atomar vorgemerkt",
                systemImage: "checkmark.seal.fill"
            )
            .foregroundStyle(.green)
        case .rejected:
            Label("Vom Simulator vollständig abgelehnt", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .unknown:
            EmptyView()
        case .cancelled:
            Label("Sammler abgebrochen", systemImage: "nosign")
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
                            Text("Verschiebung").foregroundStyle(.secondary)
                            Text(value.businessDayAdjustment.title)
                        }
                        GridRow {
                            Text("Bankkalender").foregroundStyle(.secondary)
                            Text(value.bankingCalendar.title)
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
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(run.status.title)
                                            .foregroundStyle(.secondary)
                                        Text("\(run.bankingCalendarID) · v\(run.bankingCalendarVersion)")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.tertiary)
                                    }
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
                    Picker("Verschiebungsregel", selection: $value.businessDayAdjustment) {
                        ForEach(BusinessDayAdjustment.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    Picker("Bankkalender", selection: $value.bankingCalendar) {
                        ForEach(BankingCalendarProfile.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    Text(value.bankingCalendar.sourceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
    let edit: () -> Void
    @State private var confirmInitiation = false
    @State private var confirmCancellation = false
    @State private var authorizationCode = ""
    @State private var showPain001Exporter = false
    @State private var pain001Document = Pain001Document(data: Data())
    @State private var pain001FileName = "pain.001.xml"

    private var containingBatch: PaymentBatch? {
        store.paymentBatches.first { $0.memberOrderIDs.contains(order.id) }
    }

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
                    if !order.purposeCode.isEmpty {
                        GridRow { Text("SEPA-Zweckcode").foregroundStyle(.secondary); Text(order.purposeCode).monospaced() }
                    }
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
            .disabled(order.status != .draft || containingBatch != nil)
            .help(
                containingBatch != nil
                    ? "Dieser Auftrag wird ausschließlich als Teil seines Sammlers exportiert."
                    : (order.status == .draft
                    ? "Erzeugt eine lokale SEPA-XML-Datei nach "
                        + Pain001RulePackage.epc2025.source
                    : "Nur unveränderte Entwürfe können als pain.001 initiiert werden.")
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
        .alert("Zahlungsauftrag abbrechen?", isPresented: $confirmCancellation) {
            Button("Nicht abbrechen", role: .cancel) {}
            Button("Auftrag abbrechen", role: .destructive) {
                _ = store.transitionPayment(order, to: .cancelled)
            }
        } message: {
            Text(
                "Der Entwurf bleibt mit seinem Auditverlauf erhalten, kann aber nicht mehr übermittelt oder bearbeitet werden."
            )
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
        if let containingBatch {
            Label(
                "Mitglied von „\(containingBatch.name)“. Status und Export werden ausschließlich im Sammler gesteuert.",
                systemImage: "square.stack.3d.up.fill"
            )
            .foregroundStyle(.blue)
        } else {
            switch order.status {
        case .draft:
            HStack {
                Button("Entwurf bearbeiten …", systemImage: "pencil") {
                    edit()
                }
                Button("Übermittlung vorbereiten …") {
                    confirmInitiation = true
                }
                .buttonStyle(.borderedProminent)
                Button("Entwurf abbrechen …", role: .destructive) {
                    confirmCancellation = true
                }
            }
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
                Button("Auftrag abbrechen …", role: .destructive) {
                    confirmCancellation = true
                }
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

private struct DirectDebitDraftEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    @State private var creditorAccountID: UUID?
    @State private var debtorPayeeID: UUID?
    @State private var debtorBankAccountID: UUID?
    @State private var mandateID: UUID?
    @State private var creditorID = ""
    @State private var amount = ""
    @State private var collectionDate = Date()
    @State private var purpose = ""
    @State private var endToEndID = "NOTPROVIDED"

    private var creditorAccounts: [FinanceAccount] {
        store.accounts.filter { !$0.isClosed && $0.currency == "EUR" }
    }

    private var debtorBankAccounts: [FinancePayeeBankAccount] {
        guard let debtorPayeeID else { return [] }
        return store.payeeBankAccounts.filter {
            $0.payeeID == debtorPayeeID && $0.isActive
        }
    }

    private var mandates: [FinanceSEPAMandate] {
        guard let debtorPayeeID else { return [] }
        return store.sepaMandates.filter {
            $0.payeeID == debtorPayeeID
                && $0.isActive
                && $0.signedOn != nil
        }
    }

    private var eligiblePayees: [FinancePayee] {
        store.payees.filter { payee in
            payee.isActive
                && store.payeeBankAccounts.contains {
                    $0.payeeID == payee.id && $0.isActive
                }
                && store.sepaMandates.contains {
                    $0.payeeID == payee.id && $0.isActive && $0.signedOn != nil
                }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SEPA-Basislastschrift").font(.title2.bold())
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Entwurf anlegen") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        creditorAccountID == nil
                            || debtorPayeeID == nil
                            || debtorBankAccountID == nil
                            || mandateID == nil
                            || creditorID.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                            || amount.isEmpty
                            || purpose.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                    )
            }
            .padding(14)
            Divider()
            Form {
                Section("Gläubiger") {
                    Picker("Gutschrift auf Konto", selection: $creditorAccountID) {
                        Text("Konto wählen").tag(UUID?.none)
                        ForEach(creditorAccounts) { account in
                            Text(account.name).tag(UUID?.some(account.id))
                        }
                    }
                    TextField("SEPA-Gläubiger-ID", text: $creditorID)
                    if let account = creditorAccounts.first(where: {
                        $0.id == creditorAccountID
                    }) {
                        LabeledContent("Gläubigername", value: account.ownerName)
                        LabeledContent("Gläubiger-IBAN", value: account.iban)
                    }
                    Text(
                        "Die Gläubiger-ID gehört zum Kontoinhaber, der den Betrag einzieht."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Section("Zahler und Mandat") {
                    Picker("Zahlerakte", selection: $debtorPayeeID) {
                        Text("Zahler wählen").tag(UUID?.none)
                        ForEach(eligiblePayees) { payee in
                            Text(payee.canonicalName).tag(UUID?.some(payee.id))
                        }
                    }
                    .onChange(of: debtorPayeeID) { applySelectedPayee() }
                    Picker("Bankverbindung", selection: $debtorBankAccountID) {
                        Text("Bankverbindung wählen").tag(UUID?.none)
                        ForEach(debtorBankAccounts) { bankAccount in
                            Text(
                                bankAccount.label
                                    + (bankAccount.isDefault ? " · Standard" : "")
                                    + " · " + bankAccount.iban
                            )
                            .tag(UUID?.some(bankAccount.id))
                        }
                    }
                    .disabled(debtorPayeeID == nil)
                    Picker("SEPA-Mandat", selection: $mandateID) {
                        Text("Mandat wählen").tag(UUID?.none)
                        ForEach(mandates) { mandate in
                            Text(
                                mandate.reference + " · " + mandate.sequenceType.title
                            )
                            .tag(UUID?.some(mandate.id))
                        }
                    }
                    .disabled(debtorPayeeID == nil)
                    if let mandate = mandates.first(where: { $0.id == mandateID }),
                       let signedOn = mandate.signedOn {
                        LabeledContent("Unterzeichnet") {
                            Text(signedOn, format: .dateTime.day().month().year())
                        }
                    }
                }
                Section("Einzug") {
                    TextField("Betrag", text: $amount)
                        .multilineTextAlignment(.trailing)
                    DatePicker(
                        "Fälligkeit", selection: $collectionDate,
                        displayedComponents: .date
                    )
                    if let closure = BankingCalendarProfile.targetEuroV1.closureName(
                        on: collectionDate
                    ) {
                        Label(
                            "Am gewählten Tag ist TARGET wegen \(closure) geschlossen. Bitte einen Bankarbeitstag wählen.",
                            systemImage: "calendar.badge.exclamationmark"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    TextField("Verwendungszweck", text: $purpose)
                    TextField("End-to-End-ID", text: $endToEndID)
                }
                Section {
                    Label(
                        "Der Entwurf speichert Konto-, Zahler-, Bank- und Mandatsdaten unveränderlich. Es erfolgt keine echte Bankübermittlung.",
                        systemImage: "lock.shield"
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 700, height: 780)
        .onAppear {
            creditorAccountID = creditorAccountID ?? creditorAccounts.first?.id
        }
    }

    private func applySelectedPayee() {
        debtorBankAccountID = debtorBankAccounts.first(where: \.isDefault)?.id
            ?? debtorBankAccounts.first?.id
        mandateID = mandates.count == 1 ? mandates.first?.id : nil
    }

    private func save() {
        guard let creditorAccountID,
              let debtorPayeeID,
              let debtorBankAccountID,
              let mandateID else { return }
        if store.createDirectDebitOrder(
            creditorAccountID: creditorAccountID,
            debtorPayeeID: debtorPayeeID,
            debtorBankAccountID: debtorBankAccountID,
            mandateID: mandateID,
            creditorID: creditorID,
            amount: amount,
            collectionDate: collectionDate,
            purpose: purpose,
            endToEndID: endToEndID
        ) {
            dismiss()
        }
    }
}

private struct DirectDebitOrderDetail: View {
    @EnvironmentObject private var store: FinanceAppStore
    let order: DirectDebitOrder
    @State private var confirmInitiation = false
    @State private var confirmCancellation = false
    @State private var authorizationCode = ""
    @State private var showPain008Exporter = false
    @State private var pain008Document = Pain001Document(data: Data())
    @State private var pain008FileName = "pain.008.xml"

    private var containingBatch: PaymentBatch? {
        store.paymentBatches.first { $0.memberOrderIDs.contains(order.id) }
    }

    private var statusPath: [PaymentStatus] {
        var values: [PaymentStatus] = [
            .initiated, .challengeReceived, .awaitingUser, .submitted
        ]
        if [.accepted, .rejected, .unknown, .cancelled].contains(order.status) {
            values.append(order.status)
        }
        return values
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(order.debtorName).font(.title2.bold())
                        Text("SEPA-Basislastschrift · \(order.sequenceType.title)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    PaymentStatusBadge(status: order.status)
                }
                GroupBox("Unveränderliche Lastschriftzusammenfassung") {
                    Grid(
                        alignment: .leading,
                        horizontalSpacing: 18,
                        verticalSpacing: 8
                    ) {
                        GridRow {
                            Text("Gläubigerkonto").foregroundStyle(.secondary)
                            Text(store.accountName(order.creditorAccountID))
                        }
                        GridRow {
                            Text("Gläubiger").foregroundStyle(.secondary)
                            Text(order.creditorName)
                        }
                        GridRow {
                            Text("Gläubiger-ID").foregroundStyle(.secondary)
                            Text(order.creditorID).monospaced()
                        }
                        GridRow {
                            Text("Zahler").foregroundStyle(.secondary)
                            Text(order.debtorName)
                        }
                        GridRow {
                            Text("Zahler-IBAN").foregroundStyle(.secondary)
                            Text(order.debtorIBAN).monospaced()
                        }
                        GridRow {
                            Text("Betrag").foregroundStyle(.secondary)
                            Text(Money(minorUnits: order.amountMinor).formatted).bold()
                        }
                        GridRow {
                            Text("Fälligkeit").foregroundStyle(.secondary)
                            Text(
                                order.collectionDate,
                                format: .dateTime.day().month().year()
                            )
                        }
                        GridRow {
                            Text("Mandatsreferenz").foregroundStyle(.secondary)
                            Text(order.mandateReference).monospaced()
                        }
                        GridRow {
                            Text("Mandatsdatum").foregroundStyle(.secondary)
                            Text(
                                order.mandateSignedOn,
                                format: .dateTime.day().month().year()
                            )
                        }
                        GridRow {
                            Text("Verwendungszweck").foregroundStyle(.secondary)
                            Text(order.purpose)
                        }
                        GridRow {
                            Text("End-to-End-ID").foregroundStyle(.secondary)
                            Text(order.endToEndID).monospaced()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                GroupBox("Lokaler Übermittlungszustand") {
                    HStack(spacing: 5) {
                        ForEach(statusPath, id: \.self) { status in
                            PaymentStatusBadge(status: status)
                            if status != statusPath.last {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                actionArea
                Button("pain.008 exportieren …", systemImage: "doc.badge.arrow.up") {
                    preparePain008Export()
                }
                .disabled(order.status != .draft || containingBatch != nil)
                .help(
                    containingBatch != nil
                        ? "Diese Lastschrift wird ausschließlich als Teil ihres Sammlers exportiert."
                        : (order.status == .draft
                        ? "Erzeugt eine lokale SEPA-XML-Datei nach "
                            + Pain008RulePackage.epc2025.source
                        : "Nur unveränderte Entwürfe können als pain.008 exportiert werden.")
                )
                if order.status == .unknown {
                    Label(
                        "Der Status ist unbekannt. Die Lastschrift wird niemals automatisch erneut eingereicht.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
                Text("Idempotenz: \(order.idempotencyKey.prefix(20))…")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
        }
        .alert("Lastschrift vorbereiten?", isPresented: $confirmInitiation) {
            Button("Abbrechen", role: .cancel) {}
            Button("Im Simulator initialisieren") {
                _ = store.transitionDirectDebit(order, to: .initiated)
            }
        } message: {
            Text(
                "Von \(order.debtorName) werden \(Money(minorUnits: order.amountMinor).formatted) eingezogen. Dies ist ausschließlich eine lokale Simulation."
            )
        }
        .alert("Lastschrift abbrechen?", isPresented: $confirmCancellation) {
            Button("Nicht abbrechen", role: .cancel) {}
            Button("Auftrag abbrechen", role: .destructive) {
                _ = store.transitionDirectDebit(order, to: .cancelled)
            }
        } message: {
            Text(
                "Der Lastschriftauftrag bleibt mit seinem unveränderlichen Schnappschuss und Auditverlauf erhalten, kann aber nicht mehr eingereicht werden."
            )
        }
        .fileExporter(
            isPresented: $showPain008Exporter,
            document: pain008Document,
            contentType: .xml,
            defaultFilename: pain008FileName
        ) { result in
            switch result {
            case .success:
                store.statusText = "Lastschrift als pain.008 exportiert"
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
    }

    private func preparePain008Export() {
        guard let account = store.accounts.first(where: {
            $0.id == order.creditorAccountID
        }) else {
            store.errorMessage = FinanceError.missingAccount.localizedDescription
            return
        }
        do {
            let result = try Pain008Exporter.export(order: order, account: account)
            pain008Document = Pain001Document(data: result.data)
            pain008FileName = result.fileName
            showPain008Exporter = true
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        if let containingBatch {
            Label(
                "Mitglied von „\(containingBatch.name)“. Status und Export werden ausschließlich im Sammler gesteuert.",
                systemImage: "square.stack.3d.up.fill"
            )
            .foregroundStyle(.blue)
        } else {
            switch order.status {
        case .draft:
            HStack {
                Button("Einreichung vorbereiten …") {
                    confirmInitiation = true
                }
                .buttonStyle(.borderedProminent)
                Button("Lastschrift abbrechen …", role: .destructive) {
                    confirmCancellation = true
                }
            }
        case .initiated:
            Button("Bank-Challenge simulieren") {
                _ = store.transitionDirectDebit(order, to: .challengeReceived)
            }
            .buttonStyle(.borderedProminent)
        case .challengeReceived:
            Button("Freigabedialog öffnen") {
                _ = store.transitionDirectDebit(order, to: .awaitingUser)
            }
            .buttonStyle(.borderedProminent)
        case .awaitingUser:
            VStack(alignment: .leading, spacing: 8) {
                SecureField("Simulierter Freigabecode", text: $authorizationCode)
                    .frame(maxWidth: 320)
                Text("Der Code wird niemals gespeichert oder protokolliert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Freigabe übermitteln") {
                    if store.submitDirectDebit(
                        order, authorizationCode: authorizationCode
                    ) {
                        authorizationCode = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Lastschrift abbrechen …", role: .destructive) {
                    confirmCancellation = true
                }
            }
        case .submitted:
            VStack(alignment: .leading, spacing: 8) {
                Text("Simulator-Ergebnis").font(.headline)
                HStack {
                    ForEach(SimulatorOutcome.allCases) { outcome in
                        Button(outcome.title) {
                            _ = store.simulateDirectDebitDecision(
                                order, outcome: outcome
                            )
                        }
                    }
                }
            }
        case .accepted:
            Label(
                "Angenommen · als erwartete Gutschrift im Kontoblatt materialisiert",
                systemImage: "checkmark.seal.fill"
            )
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
}

private struct PaymentDraftEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FinanceAppStore
    private let order: PaymentOrder?
    @State private var accountID: UUID?
    @State private var type: PaymentType
    @State private var payeeID: UUID?
    @State private var payeeBankAccountID: UUID?
    @State private var recipientName: String
    @State private var iban: String
    @State private var bic: String
    @State private var amount: String
    @State private var executionDate: Date
    @State private var purpose: String
    @State private var endToEndID: String
    @State private var purposeCode: String
    @State private var showEPCQRImporter = false
    @State private var epcInformation = ""

    init(order: PaymentOrder? = nil) {
        self.order = order
        _accountID = State(initialValue: order?.accountID)
        _type = State(initialValue: order?.type ?? .sepaCreditTransfer)
        _payeeID = State(initialValue: order?.payeeID)
        _payeeBankAccountID = State(initialValue: order?.payeeBankAccountID)
        _recipientName = State(initialValue: order?.recipientName ?? "")
        _iban = State(initialValue: order?.iban ?? "")
        _bic = State(initialValue: order?.bic ?? "")
        _amount = State(initialValue: order.map {
            Money(minorUnits: $0.amountMinor, currency: $0.currency).editingString
        } ?? "")
        _executionDate = State(initialValue: order?.executionDate ?? Date())
        _purpose = State(initialValue: order?.purpose ?? "")
        _endToEndID = State(initialValue: order?.endToEndID ?? "NOTPROVIDED")
        _purposeCode = State(initialValue: order?.purposeCode ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(order == nil ? "Zahlungsentwurf" : "Zahlungsentwurf bearbeiten")
                    .font(.title2.bold())
                Spacer()
                Button("EPC-QR einlesen …", systemImage: "qrcode.viewfinder") {
                    showEPCQRImporter = true
                }
                Button("Abbrechen") { dismiss() }
                Button(order == nil ? "Entwurf anlegen" : "Änderungen speichern") {
                    save()
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
                        ForEach(store.accounts.filter {
                            !$0.isClosed && $0.currency == "EUR"
                        }) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }
                    Picker("Zahlungsart", selection: $type) {
                        ForEach(PaymentType.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Empfängerakte", selection: $payeeID) {
                        Text("Manuelle Eingabe").tag(UUID?.none)
                        ForEach(store.payees.filter(\.isActive)) { payee in
                            Text(payee.canonicalName).tag(UUID?.some(payee.id))
                        }
                    }
                    .onChange(of: payeeID) { applySelectedPayee() }
                    if payeeID != nil {
                        Picker("Bankverbindung", selection: $payeeBankAccountID) {
                            Text("Manuelle Eingabe").tag(UUID?.none)
                            ForEach(selectedPayeeBankAccounts) { bankAccount in
                                Text(
                                    bankAccount.label
                                        + (bankAccount.isDefault ? " · Standard" : "")
                                        + " · " + bankAccount.iban
                                )
                                .tag(UUID?.some(bankAccount.id))
                            }
                        }
                        .onChange(of: payeeBankAccountID) {
                            applySelectedBankAccount()
                        }
                    }
                    TextField("Empfänger", text: $recipientName)
                    TextField("IBAN", text: $iban)
                    TextField("BIC (optional)", text: $bic)
                    TextField("Betrag", text: $amount)
                    DatePicker("Ausführung", selection: $executionDate, displayedComponents: .date)
                    TextField("Verwendungszweck", text: $purpose)
                    TextField("SEPA-Zweckcode (optional)", text: $purposeCode)
                    TextField("End-to-End-ID", text: $endToEndID)
                    if let executionCalendarNotice {
                        Label(executionCalendarNotice, systemImage: "calendar.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                if !epcInformation.isEmpty {
                    Section("Hinweis aus dem EPC-QR-Code") {
                        Text(epcInformation)
                            .textSelection(.enabled)
                    }
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
        .frame(width: 700, height: 760)
        .onAppear {
            accountID = accountID ?? store.accounts.first(where: {
                !$0.isClosed && $0.currency == "EUR"
            })?.id
        }
        .fileImporter(
            isPresented: $showEPCQRImporter,
            allowedContentTypes: [.image], allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                Task {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let payload = try await Task.detached(priority: .userInitiated) {
                            try EPCQRImporter.decodeImage(at: url)
                        }.value
                        apply(payload)
                    } catch {
                        store.errorMessage = error.localizedDescription
                    }
                }
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
    }

    private var selectedPayeeBankAccounts: [FinancePayeeBankAccount] {
        guard let payeeID else { return [] }
        return store.payeeBankAccounts.filter {
            $0.payeeID == payeeID && $0.isActive
        }
    }

    private var executionCalendarNotice: String? {
        if type == .instantCreditTransfer {
            return "Echtzeitüberweisungen sind laut Bundesbank unabhängig von TARGET-Schließtagen rund um die Uhr möglich."
        }
        guard let closure = BankingCalendarProfile.targetEuroV1.closureName(
            on: executionDate
        ) else { return nil }
        return "Am gewählten Tag ist TARGET wegen \(closure) geschlossen. Bitte einen Bankarbeitstag wählen."
    }

    private func applySelectedPayee() {
        guard let payeeID,
              let payee = store.payees.first(where: { $0.id == payeeID })
        else {
            payeeBankAccountID = nil
            return
        }
        recipientName = payee.canonicalName
        let preferred = selectedPayeeBankAccounts.first(where: \.isDefault)
            ?? selectedPayeeBankAccounts.first
        payeeBankAccountID = preferred?.id
        applySelectedBankAccount()
    }

    private func applySelectedBankAccount() {
        guard let payeeBankAccountID,
              let bankAccount = selectedPayeeBankAccounts.first(where: {
                  $0.id == payeeBankAccountID
              })
        else { return }
        recipientName = bankAccount.accountHolder
        iban = bankAccount.iban
        bic = bankAccount.bic
    }

    private func apply(_ payload: EPCQRPayload) {
        type = .sepaCreditTransfer
        recipientName = payload.recipientName
        iban = payload.iban
        bic = payload.bic
        amount = payload.amountMinor.map {
            Money(minorUnits: $0, currency: "EUR").editingString
        } ?? ""
        purpose = payload.paymentPurpose
        purposeCode = payload.purposeCode
        epcInformation = payload.information

        let candidates = store.payeeBankAccounts.filter { bank in
            bank.isActive
                && bank.accountHolder == payload.recipientName
                && IBANValidator.normalized(bank.iban) == payload.iban
                && (payload.bic.isEmpty || bank.bic.uppercased() == payload.bic)
                && store.payees.contains { $0.id == bank.payeeID && $0.isActive }
        }
        if candidates.count == 1, let bank = candidates.first {
            payeeID = bank.payeeID
            payeeBankAccountID = bank.id
        } else {
            payeeID = nil
            payeeBankAccountID = nil
        }
    }

    private func save() {
        guard let accountID else { return }
        let success: Bool
        if let order {
            success = store.updatePaymentOrderDraft(
                order, accountID: accountID, type: type,
                recipientName: recipientName, iban: iban, bic: bic,
                amount: amount, executionDate: executionDate,
                purpose: purpose, endToEndID: endToEndID,
                payeeID: payeeID,
                payeeBankAccountID: payeeBankAccountID,
                purposeCode: purposeCode
            )
        } else {
            success = store.createPaymentOrder(
                accountID: accountID, type: type,
                recipientName: recipientName, iban: iban, bic: bic,
                amount: amount, executionDate: executionDate,
                purpose: purpose, endToEndID: endToEndID,
                payeeID: payeeID,
                payeeBankAccountID: payeeBankAccountID,
                purposeCode: purposeCode
            )
        }
        if success { dismiss() }
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
                            GroupBox("Dokumente") {
                                AttachmentManagerView(
                                    entityType: .security,
                                    entityID: selectedSecurity.id,
                                    emptyText: "Noch keine Wertpapierdokumente",
                                    icon: "doc.text"
                                )
                            }
                            .padding(.top, 6)
                            if !selectedSecurity.note.isEmpty {
                                GroupBox("Notiz") {
                                    SecureNoteView(text: selectedSecurity.note)
                                }
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
                SecureNoteView(text: value.note, showsText: false)
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

private struct LoanPaymentActionContext: Identifiable {
    var id: String { entry.id }
    let loan: FinanceLoan
    let entry: LoanScheduleEntry
    let match: LoanPaymentMatch?
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
    @State private var loanPaymentAction: LoanPaymentActionContext?

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
        .sheet(item: $loanPaymentAction) { context in
            LoanPaymentMatchSheet(
                loan: context.loan, entry: context.entry, match: context.match
            )
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
                loanMetric("Ursprung", loan.principalMinor, currency: loan.currency)
                loanMetric("Restschuld", remaining, currency: loan.currency)
                loanMetric("Zins + Gebühren", totalInterest + totalFees, currency: loan.currency)
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
            loanScheduleTable(schedule, loan: loan)
        }
    }

    private func loanScheduleTable(
        _ entries: [LoanScheduleEntry],
        loan: FinanceLoan
    ) -> some View {
        let matches = store.loanPaymentMatches.filter { $0.loanID == loan.id }
        return VStack(spacing: 0) {
            HStack {
                Text("Tilgungsplan").font(.headline)
                let matchedCount = matches.count
                Text("\(matchedCount) von \(entries.count) abgeglichen")
                    .font(.caption)
                    .foregroundStyle(matchedCount == 0 ? Color.secondary : Color.green)
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
                    scheduleHeader("Ist / Abweichung", alignment: .trailing)
                    Color.clear
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
                            GridItem(.flexible(minimum: 100, maximum: 140), alignment: .trailing),
                            GridItem(.flexible(minimum: 105, maximum: 145), alignment: .trailing),
                            GridItem(.fixed(28), alignment: .center)
                        ],
                        alignment: .leading, spacing: 0
                    ) {
                        ForEach(entries) { entry in
                            let match = matches.first {
                                Calendar.current.isDate(
                                    $0.scheduledDate, inSameDayAs: entry.dueDate
                                )
                            }
                            Text("\(entry.sequence)")
                            Text(entry.dueDate.formatted(date: .numeric, time: .omitted))
                            Text(
                                (Decimal(entry.annualBasisPoints) / 100).formatted(
                                    .number.locale(Locale(identifier: "de_DE"))
                                        .precision(.fractionLength(2))
                                ) + " %"
                            )
                            Text(Money(minorUnits: entry.installmentMinor,
                                       currency: loan.currency).formatted)
                            Text(Money(minorUnits: entry.principalMinor,
                                       currency: loan.currency).formatted)
                            Text(Money(minorUnits: entry.interestMinor,
                                       currency: loan.currency).formatted)
                            Text(
                                entry.extraPaymentMinor == 0
                                    ? "–" : Money(minorUnits: entry.extraPaymentMinor,
                                                    currency: loan.currency).formatted
                            )
                            Text(Money(minorUnits: entry.closingBalanceMinor,
                                       currency: loan.currency).formatted)
                                .fontWeight(entry.closingBalanceMinor == 0 ? .semibold : .regular)
                            if let match {
                                let planned = entry.installmentMinor + entry.extraPaymentMinor
                                let difference = match.actualPaymentMinor - planned
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(Money(minorUnits: match.actualPaymentMinor,
                                               currency: loan.currency).formatted)
                                        .foregroundStyle(.green)
                                    Text(
                                        difference == 0
                                            ? "planmäßig"
                                            : "Δ \(Money(minorUnits: difference, currency: loan.currency).formatted)"
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(difference == 0 ? Color.secondary : Color.orange)
                                }
                            } else {
                                Text("Offen").foregroundStyle(.secondary)
                            }
                            Button {
                                loanPaymentAction = LoanPaymentActionContext(
                                    loan: loan, entry: entry, match: match
                                )
                            } label: {
                                Image(systemName: match == nil ? "link.badge.plus" : "checkmark.circle.fill")
                                    .foregroundStyle(match == nil ? Color.accentColor : Color.green)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                match == nil
                                    ? "Rate \(entry.sequence) abgleichen"
                                    : "Abgleich für Rate \(entry.sequence) anzeigen"
                            )
                        }
                        .font(.caption.monospacedDigit())
                        .frame(height: 38)
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

    private func loanMetric(
        _ title: String, _ value: Int64, currency: String = "EUR"
    ) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money(minorUnits: value, currency: currency).formatted)
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

private struct LoanPaymentMatchSheet: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss

    let loan: FinanceLoan
    let entry: LoanScheduleEntry
    let match: LoanPaymentMatch?

    @State private var bookingDate: Date
    @State private var selectedCandidate: LoanPaymentCandidate?
    @State private var confirmGeneratedBooking = false
    @State private var confirmRemoval = false

    init(
        loan: FinanceLoan,
        entry: LoanScheduleEntry,
        match: LoanPaymentMatch?
    ) {
        self.loan = loan
        self.entry = entry
        self.match = match
        _bookingDate = State(initialValue: entry.dueDate)
    }

    private var candidates: [LoanPaymentCandidate] {
        store.loanPaymentCandidates(loan: loan, entry: entry)
    }

    private var matchedTransaction: FinanceTransaction? {
        guard let match else { return nil }
        return store.transactions.first { $0.id == match.transactionID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kreditrate abgleichen").font(.title2.bold())
                    Text(
                        "\(loan.name) · Rate \(entry.sequence) · \(entry.dueDate.formatted(date: .long, time: .omitted))"
                    )
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Schließen") { dismiss() }
            }
            .padding(16)

            Divider()
            HStack(spacing: 18) {
                paymentMetric("Planrate", entry.installmentMinor + entry.extraPaymentMinor)
                paymentMetric("Tilgung", entry.principalMinor)
                paymentMetric("Zins", entry.interestMinor)
                paymentMetric("Gebühr", entry.feeMinor)
                paymentMetric("Sondertilgung", entry.extraPaymentMinor)
            }
            .padding(16)

            Divider()
            if let match {
                matchedContent(match)
            } else {
                unmatchedContent
            }
        }
        .frame(width: 760, height: 590)
        .confirmationDialog(
            "Reale Buchung aufteilen und fest zuordnen?",
            isPresented: Binding(
                get: { selectedCandidate != nil },
                set: { if !$0 { selectedCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let selectedCandidate {
                Button("Buchung zuordnen und splitten") {
                    if store.matchLoanPayment(
                        loanID: loan.id, scheduleEntryID: entry.id,
                        transactionID: selectedCandidate.id
                    ) { dismiss() }
                }
            }
            Button("Abbrechen", role: .cancel) { selectedCandidate = nil }
        } message: {
            if let selectedCandidate {
                Text(
                    "\(selectedCandidate.transaction.bookingDate.formatted(date: .numeric, time: .omitted)) · \(selectedCandidate.transaction.payee) · \(Money(minorUnits: selectedCandidate.transaction.amountMinor, currency: selectedCandidate.transaction.currency).formatted). Die Buchung wird in Tilgung, Zins, Gebühr und gegebenenfalls Sondertilgung zerlegt."
                )
            }
        }
        .confirmationDialog(
            "Planrate als neue Splitbuchung anlegen?",
            isPresented: $confirmGeneratedBooking,
            titleVisibility: .visible
        ) {
            Button("Splitbuchung anlegen") {
                if store.postLoanScheduleEntry(
                    loanID: loan.id, scheduleEntryID: entry.id,
                    bookingDate: bookingDate
                ) { dismiss() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(
                "Auf \(linkedAccountName) wird am \(bookingDate.formatted(date: .long, time: .omitted)) eine Belastung über \(Money(minorUnits: entry.installmentMinor + entry.extraPaymentMinor, currency: loan.currency).formatted) erzeugt."
            )
        }
        .confirmationDialog(
            match?.source == .generated
                ? "Automatisch erzeugte Rate entfernen?"
                : "Zuordnung lösen und Originalbuchung wiederherstellen?",
            isPresented: $confirmRemoval,
            titleVisibility: .visible
        ) {
            if let match {
                Button(
                    match.source == .generated
                        ? "Splitbuchung entfernen" : "Original wiederherstellen",
                    role: .destructive
                ) {
                    if store.removeLoanPaymentMatch(id: match.id) { dismiss() }
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(
                match?.source == .generated
                    ? "Die von FinanzVerwalter erzeugte Buchung wird entfernt."
                    : "Die automatische Aufteilung wird entfernt und der exakt gespeicherte Zustand vor der Zuordnung wiederhergestellt."
            )
        }
    }

    private var linkedAccountName: String {
        guard let accountID = loan.linkedAccountID else { return "kein Zahlungskonto" }
        return store.accountName(accountID)
    }

    private var unmatchedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reale Belastung zuordnen").font(.headline)
                    Text("Geeignete ungeteilte Buchungen im Zahlungskonto, höchstens 45 Tage entfernt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(candidates.count) Treffer").foregroundStyle(.secondary)
            }
            .padding(14)

            if candidates.isEmpty {
                ContentUnavailableView(
                    "Keine geeignete reale Belastung",
                    systemImage: "link.badge.plus",
                    description: Text(
                        "Du kannst die Planrate als neue Splitbuchung anlegen oder später eine Bankbuchung zuordnen."
                    )
                )
                .frame(maxHeight: .infinity)
            } else {
                List(candidates) { candidate in
                    Button { selectedCandidate = candidate } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(candidate.transaction.payee.isEmpty
                                     ? candidate.transaction.purpose
                                     : candidate.transaction.payee)
                                    .fontWeight(.semibold)
                                Text(
                                    "\(candidate.transaction.bookingDate.formatted(date: .numeric, time: .omitted)) · \(candidate.transaction.purpose)"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(Money(minorUnits: candidate.transaction.amountMinor,
                                           currency: candidate.transaction.currency).formatted)
                                    .monospacedDigit()
                                Text(candidateSummary(candidate))
                                    .font(.caption)
                                    .foregroundStyle(
                                        candidate.amountDifferenceMinor == 0 ? .green : .orange
                                    )
                            }
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
            HStack {
                DatePicker(
                    "Buchungsdatum", selection: $bookingDate,
                    displayedComponents: .date
                )
                .frame(width: 250)
                Spacer()
                Button("Planrate als Splitbuchung buchen", systemImage: "plus.rectangle.on.rectangle") {
                    confirmGeneratedBooking = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(loan.linkedAccountID == nil)
            }
            .padding(14)
        }
    }

    private func matchedContent(_ match: LoanPaymentMatch) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(match.source.title, systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
                Text("Zugeordnet \(match.matchedAt.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundStyle(.secondary)
            }
            GroupBox("Ist-Zahlung") {
                HStack(spacing: 20) {
                    paymentMetric("Gesamt", match.actualPaymentMinor)
                    paymentMetric("Tilgung", match.principalMinor)
                    paymentMetric("Zins", match.interestMinor)
                    paymentMetric("Gebühr", match.feeMinor)
                    paymentMetric("Sondertilgung", match.extraPaymentMinor)
                }
                .padding(.vertical, 8)
            }
            if let transaction = matchedTransaction {
                GroupBox("Buchung") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow { Text("Datum").foregroundStyle(.secondary); Text(transaction.bookingDate.formatted(date: .long, time: .omitted)) }
                        GridRow { Text("Empfänger").foregroundStyle(.secondary); Text(transaction.payee) }
                        GridRow { Text("Verwendungszweck").foregroundStyle(.secondary); Text(transaction.purpose) }
                        GridRow { Text("Konto").foregroundStyle(.secondary); Text(store.accountName(transaction.accountID)) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
            }
            Text(
                "Zugeordnete Kreditraten sind vor versehentlichem Bearbeiten oder Löschen geschützt. Löse zuerst diesen Abgleich."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            HStack {
                Spacer()
                Button(
                    match.source == .generated
                        ? "Erzeugte Splitbuchung entfernen"
                        : "Zuordnung lösen und Original wiederherstellen",
                    role: .destructive
                ) { confirmRemoval = true }
                .disabled(match.source == .legacy)
            }
        }
        .padding(16)
    }

    private func paymentMetric(_ title: String, _ value: Int64) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money(minorUnits: value, currency: loan.currency).formatted)
                .font(.headline.monospacedDigit())
        }
        .frame(minWidth: 100, alignment: .trailing)
    }

    private func candidateSummary(_ candidate: LoanPaymentCandidate) -> String {
        let date = candidate.dayDistance == 0
            ? "Fälligkeitstag"
            : "\(abs(candidate.dayDistance)) Tage \(candidate.dayDistance < 0 ? "vorher" : "später")"
        let amount = candidate.amountDifferenceMinor == 0
            ? "Betrag passend"
            : "Δ \(Money(minorUnits: candidate.amountDifferenceMinor, currency: candidate.transaction.currency).formatted)"
        return "\(amount) · \(date)"
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
                        SecureNoteView(text: contract.note)
                    }
                }
                GroupBox("Dokumente") {
                    AttachmentManagerView(
                        entityType: .contract,
                        entityID: contract.id,
                        emptyText: "Noch keine Vertragsdokumente",
                        icon: "doc.text"
                    )
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
                SecureNoteView(text: note, showsText: false)
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
                        SecureNoteView(text: item.note)
                    }
                }
                GroupBox("Fotos & Belege") {
                    AttachmentManagerView(
                        entityType: .inventory,
                        entityID: item.id,
                        emptyText: "Noch keine Fotos oder Belege",
                        icon: "photo.on.rectangle"
                    )
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
                SecureNoteView(text: note, showsText: false)
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

private func taxAllowanceInputString(_ minor: Int64) -> String {
    let magnitude = minor.magnitude
    return "\(magnitude / 100),\(String(format: "%02llu", magnitude % 100))"
}

struct TaxAllowancesView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    let showCloseButton: Bool
    @State private var taxYear = Calendar.current.component(.year, from: .now)
    @State private var selectedPersonIDs = Set<UUID>()
    @State private var institutionText = ""
    @State private var includeInactive = false
    @State private var selectedOrderID: UUID?
    @State private var editingPerson: TaxPerson?
    @State private var showPersonEditor = false
    @State private var editingOrder: TaxAllowanceOrder?
    @State private var showOrderEditor = false
    @State private var usageAmount = ""
    @State private var csvDocument = ReportCSVDocument(data: Data())
    @State private var pdfDocument = ReportPDFDocument(data: Data())
    @State private var showCSVExporter = false
    @State private var showPDFExporter = false
    @State private var orientation: ReportPDFOrientation = .landscape

    init(
        showCloseButton: Bool = false,
        initialQuery: TaxAllowanceReportQuery? = nil
    ) {
        self.showCloseButton = showCloseButton
        if let initialQuery {
            _taxYear = State(initialValue: initialQuery.taxYear)
            _selectedPersonIDs = State(initialValue: initialQuery.personIDs)
            _institutionText = State(initialValue: initialQuery.institutionText)
            _includeInactive = State(initialValue: initialQuery.includeInactive)
        }
    }

    private var query: TaxAllowanceReportQuery {
        TaxAllowanceReportQuery(
            taxYear: taxYear, personIDs: selectedPersonIDs,
            institutionText: institutionText, includeInactive: includeInactive
        )
    }

    private var selectedOrder: TaxAllowanceOrder? {
        store.taxAllowanceOrders.first { $0.id == selectedOrderID }
    }

    private var selectedUsage: TaxAllowanceUsage? {
        guard let selectedOrderID else { return nil }
        return store.taxAllowanceUsages.first {
            $0.orderID == selectedOrderID && $0.taxYear == taxYear
        }
    }

    var body: some View {
        let snapshot = store.taxAllowanceReport(query)
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Freistellungsaufträge").font(.title2.bold())
                    Text("Sparer-Pauschbetrag nach Personen und Instituten verteilen und Nutzung überwachen")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                allowanceValue("Verteilt", snapshot.allocatedMinor)
                allowanceValue("Genutzt", snapshot.usedMinor)
                allowanceValue("In Aufträgen frei", snapshot.unusedOrderMinor)
                Button("Neues Fenster", systemImage: "macwindow.badge.plus") {
                    openSpecializedReportWindow(
                        kind: .taxAllowances,
                        payload: query,
                        store: store,
                        openWindow: openWindow
                    )
                }
                .accessibilityIdentifier("openTaxAllowanceReportWindow")
                if showCloseButton {
                    Button("Schließen") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
            .padding(14)
            Divider()
            HStack(spacing: 10) {
                Stepper("Steuerjahr \(taxYear)", value: $taxYear, in: 2009...2200)
                    .fixedSize()
                Menu {
                    Button("Alle Personen") { selectedPersonIDs.removeAll() }
                    ForEach(store.taxPeople.filter(\.isActive)) { person in
                        Toggle(person.displayName, isOn: allowanceMember(person.id, in: $selectedPersonIDs))
                    }
                } label: {
                    Label(selectedPersonIDs.isEmpty ? "Alle Personen" : "Personen (\(selectedPersonIDs.count))",
                          systemImage: "person.2")
                }
                TextField("Institut filtern", text: $institutionText)
                    .textFieldStyle(.roundedBorder).frame(width: 190)
                Toggle("Inaktive", isOn: $includeInactive)
                Spacer()
                Menu {
                    Button("Neue Person …") { editingPerson = nil; showPersonEditor = true }
                    if !store.taxPeople.isEmpty { Divider() }
                    ForEach(store.taxPeople) { person in
                        Button("\(person.displayName) bearbeiten …") {
                            editingPerson = person; showPersonEditor = true
                        }
                    }
                } label: { Label("Personen", systemImage: "person.crop.circle.badge.plus") }
                Button("Auftrag", systemImage: "plus") {
                    editingOrder = nil; showOrderEditor = true
                }
                .disabled(store.taxPeople.filter(\.isActive).isEmpty)
                Button("Bearbeiten", systemImage: "pencil") {
                    editingOrder = selectedOrder; showOrderEditor = selectedOrder != nil
                }
                .disabled(selectedOrder == nil)
                Button("CSV", systemImage: "tablecells") {
                    csvDocument = ReportCSVDocument(
                        data: TaxAllowanceReportCSVExporter.data(snapshot: snapshot, generatedAt: .now)
                    )
                    showCSVExporter = true
                }
                Menu {
                    Picker("Papierausrichtung", selection: $orientation) {
                        ForEach(ReportPDFOrientation.allCases) { Text($0.title).tag($0) }
                    }
                    Divider()
                    Button("Drucken …", systemImage: "printer.fill") { printReport(snapshot) }
                    Button("PDF exportieren …", systemImage: "doc.richtext") { exportPDF(snapshot) }
                } label: { Label("PDF · \(orientation.title)", systemImage: "printer") }
            }
            .controlSize(.small)
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            HSplitView {
                Table(snapshot.rows, selection: $selectedOrderID) {
                    TableColumn("Institut") { Text($0.institution).lineLimit(1) }
                        .width(min: 120, ideal: 160)
                    TableColumn("Person/en") { Text($0.holderNames).lineLimit(1) }
                        .width(min: 120, ideal: 160)
                    TableColumn("Art") { Text($0.assessmentType.title).lineLimit(1) }
                        .width(min: 110, ideal: 125)
                    TableColumn("Auftrag") { allowanceMoney($0.allowanceMinor) }.width(105)
                    TableColumn("Genutzt") { allowanceMoney($0.usedMinor) }.width(105)
                    TableColumn("Rest") { allowanceMoney($0.remainingMinor) }.width(105)
                    TableColumn("Gültigkeit") { Text($0.validity) }.width(95)
                    TableColumn("Steuer-ID") { row in
                        Label(row.taxIDComplete ? "Bestätigt" : "Prüfen",
                              systemImage: row.taxIDComplete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(row.taxIDComplete ? .green : .orange)
                            .labelStyle(.iconOnly)
                            .help(row.taxIDComplete ? "Steuer-ID bestätigt" : "Steuer-ID noch nicht bestätigt")
                    }.width(65)
                }
                .overlay {
                    if snapshot.rows.isEmpty {
                        ContentUnavailableView(
                            "Keine Freistellungsaufträge",
                            systemImage: "eurosign.circle",
                            description: Text("Lege zuerst eine Person und anschließend einen Auftrag an.")
                        )
                    }
                }
                .frame(minWidth: 780)
                allowanceDetail(snapshot)
                    .frame(minWidth: 310, idealWidth: 350, maxWidth: 430)
            }
            Divider()
            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    Text("Gesetzliche Verteilung").fontWeight(.semibold)
                    ForEach(snapshot.subjectTotals) { total in
                        Text("\(total.holderNames): \(Money(minorUnits: total.allocatedMinor).formatted) von \(Money(minorUnits: total.legalLimitMinor).formatted) verteilt · \(Money(minorUnits: total.remainingAllocationMinor).formatted) offen")
                            .monospacedDigit()
                            .foregroundStyle(total.remainingAllocationMinor < 0 ? .red : .secondary)
                    }
                }
                .font(.caption).padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
        .frame(minWidth: showCloseButton ? 1_140 : 980, minHeight: showCloseButton ? 700 : 600)
        .sheet(isPresented: $showPersonEditor) { TaxPersonEditor(person: editingPerson) }
        .sheet(isPresented: $showOrderEditor) { TaxAllowanceOrderEditor(order: editingOrder) }
        .fileExporter(
            isPresented: $showCSVExporter, document: csvDocument,
            contentType: .commaSeparatedText, defaultFilename: allowanceFilename
        ) { if case .failure(let error) = $0 { store.errorMessage = error.localizedDescription } }
        .fileExporter(
            isPresented: $showPDFExporter, document: pdfDocument,
            contentType: .pdf, defaultFilename: allowanceFilename
        ) { if case .failure(let error) = $0 { store.errorMessage = error.localizedDescription } }
        .onChange(of: selectedOrderID) { _, _ in loadUsage() }
        .onChange(of: taxYear) { _, _ in loadUsage() }
        .onAppear {
            if selectedOrderID == nil { selectedOrderID = snapshot.rows.first?.id }
            loadUsage()
        }
    }

    @ViewBuilder
    private func allowanceDetail(_ snapshot: TaxAllowanceReportSnapshot) -> some View {
        if let order = selectedOrder,
           let row = snapshot.rows.first(where: { $0.id == order.id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(order.institution).font(.title3.bold())
                    Text(row.holderNames).foregroundStyle(.secondary)
                    Divider()
                    allowanceDetailLine("Auftragsbetrag", row.allowanceMinor)
                    allowanceDetailLine("Genutzt \(taxYear)", row.usedMinor)
                    allowanceDetailLine("Verbleibend", row.remainingMinor)
                    allowanceDetailLine("Gesetzliches Maximum", row.legalLimitMinor)
                    Divider()
                    Text("Jährliche Nutzung").font(.headline)
                    TextField("Genutzter Betrag", text: $usageAmount)
                    Button("Nutzung speichern", systemImage: "checkmark") { saveUsage(order) }
                        .disabled(!order.applies(to: taxYear))
                    Text("Kontenabdeckung").font(.headline)
                    Text(row.accountNames).foregroundStyle(.secondary)
                    Text("Die Kontenzuordnung dient ausschließlich der Übersicht. Der Auftrag gilt institutsweit und kann nicht auf einzelne Konten oder Depots desselben Instituts beschränkt werden.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !row.taxIDComplete {
                        Label("Steuer-ID-Bestätigung fehlt", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    if !order.note.isEmpty { GroupBox("Notiz") { Text(order.note) } }
                    Link("Amtliche Rechtsgrundlage: § 20 Abs. 9 EStG",
                         destination: URL(string: "https://www.gesetze-im-internet.de/estg/__20.html")!)
                    Text("Verwaltungshilfe – keine Steuerberatung.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
            }
        } else {
            ContentUnavailableView("Kein Auftrag ausgewählt", systemImage: "eurosign.circle")
        }
    }

    private func allowanceValue(_ title: String, _ minor: Int64) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money(minorUnits: minor).formatted).font(.headline.monospacedDigit())
        }
        .padding(.horizontal, 8)
    }

    private func allowanceMoney(_ minor: Int64) -> some View {
        Text(Money(minorUnits: minor).formatted)
            .frame(maxWidth: .infinity, alignment: .trailing).monospacedDigit()
    }

    private func allowanceDetailLine(_ title: String, _ minor: Int64) -> some View {
        HStack { Text(title); Spacer(); Text(Money(minorUnits: minor).formatted).monospacedDigit() }
    }

    private func allowanceMember<Value: Hashable>(
        _ value: Value, in selection: Binding<Set<Value>>
    ) -> Binding<Bool> {
        Binding(
            get: { selection.wrappedValue.contains(value) },
            set: { included in
                if included { selection.wrappedValue.insert(value) }
                else { selection.wrappedValue.remove(value) }
            }
        )
    }

    private func loadUsage() {
        usageAmount = selectedUsage.map { taxAllowanceInputString($0.usedMinor) } ?? "0,00"
    }

    private func saveUsage(_ order: TaxAllowanceOrder) {
        do {
            let amount = try Money(parsing: usageAmount)
            let value = TaxAllowanceUsage(
                id: selectedUsage?.id ?? UUID(), orderID: order.id,
                taxYear: taxYear, usedMinor: abs(amount.minorUnits)
            )
            if store.saveTaxAllowanceUsage(value) { loadUsage() }
        } catch { store.errorMessage = error.localizedDescription }
    }

    private func pdfData(_ snapshot: TaxAllowanceReportSnapshot) throws -> Data {
        try ComparisonReportPDFExporter.taxAllowanceData(
            snapshot: snapshot, generatedAt: .now, orientation: orientation
        )
    }

    private func printReport(_ snapshot: TaxAllowanceReportSnapshot) {
        do { try RegisterPrintService.printPDF(try pdfData(snapshot)) }
        catch { store.errorMessage = error.localizedDescription }
    }

    private func exportPDF(_ snapshot: TaxAllowanceReportSnapshot) {
        do { pdfDocument = ReportPDFDocument(data: try pdfData(snapshot)); showPDFExporter = true }
        catch { store.errorMessage = error.localizedDescription }
    }

    private var allowanceFilename: String { "FinanzVerwalter-Freistellungsauftraege-\(taxYear)" }
}

private struct TaxPersonEditor: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    let person: TaxPerson?
    @State private var displayName: String
    @State private var taxIDLastFour: String
    @State private var taxIDConfirmed: Bool
    @State private var isActive: Bool

    init(person: TaxPerson?) {
        self.person = person
        _displayName = State(initialValue: person?.displayName ?? "")
        _taxIDLastFour = State(initialValue: person?.taxIDLastFour ?? "")
        _taxIDConfirmed = State(initialValue: person?.taxIDConfirmed ?? false)
        _isActive = State(initialValue: person?.isActive ?? true)
    }

    var body: some View {
        VStack(spacing: 0) {
            AssetEditorHeader(
                title: person == nil ? "Steuerperson anlegen" : "Steuerperson bearbeiten",
                saveDisabled: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                save: save
            )
            Form {
                TextField("Name", text: $displayName)
                TextField("Letzte 4 Ziffern der Steuer-ID", text: $taxIDLastFour)
                Toggle("Steuer-ID beim Institut bestätigt", isOn: $taxIDConfirmed)
                Toggle("Aktiv", isOn: $isActive)
                Text("Aus Datenschutzgründen speichert FinanzVerwalter nur die letzten vier Ziffern und den Bestätigungsstatus, nicht die vollständige Steuer-ID.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
        }
        .frame(width: 540, height: 330)
    }

    private func save() {
        let value = TaxPerson(
            id: person?.id ?? UUID(), displayName: displayName,
            taxIDLastFour: taxIDLastFour, taxIDConfirmed: taxIDConfirmed, isActive: isActive
        )
        if store.saveTaxPerson(value) { dismiss() }
    }
}

private struct TaxAllowanceOrderEditor: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    let order: TaxAllowanceOrder?
    @State private var institution: String
    @State private var assessmentType: TaxAssessmentType
    @State private var primaryPersonID: UUID?
    @State private var partnerPersonID: UUID?
    @State private var amount: String
    @State private var validFromYear: Int
    @State private var hasEndYear: Bool
    @State private var validThroughYear: Int
    @State private var accountIDs: Set<UUID>
    @State private var note: String
    @State private var isActive: Bool

    init(order: TaxAllowanceOrder?) {
        let currentYear = Calendar.current.component(.year, from: .now)
        self.order = order
        _institution = State(initialValue: order?.institution ?? "")
        _assessmentType = State(initialValue: order?.assessmentType ?? .individual)
        _primaryPersonID = State(initialValue: order?.primaryPersonID)
        _partnerPersonID = State(initialValue: order?.partnerPersonID)
        _amount = State(initialValue: order.map { taxAllowanceInputString($0.allowanceMinor) } ?? "1.000,00")
        _validFromYear = State(initialValue: order?.validFromYear ?? currentYear)
        _hasEndYear = State(initialValue: order?.validThroughYear != nil)
        _validThroughYear = State(initialValue: order?.validThroughYear ?? currentYear)
        _accountIDs = State(initialValue: order?.accountIDs ?? [])
        _note = State(initialValue: order?.note ?? "")
        _isActive = State(initialValue: order?.isActive ?? true)
    }

    private var activePeople: [TaxPerson] { store.taxPeople.filter(\.isActive) }
    private var matchingAccounts: [FinanceAccount] {
        let key = institution.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return store.accounts.filter {
            $0.institution.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines) == key
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AssetEditorHeader(
                title: order == nil ? "Freistellungsauftrag anlegen" : "Freistellungsauftrag bearbeiten",
                saveDisabled: institution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || primaryPersonID == nil,
                save: save
            )
            Form {
                TextField("Institut", text: $institution)
                Picker("Art", selection: $assessmentType) {
                    ForEach(TaxAssessmentType.allCases) { Text($0.title).tag($0) }
                }
                Picker("Person", selection: $primaryPersonID) {
                    Text("Bitte wählen").tag(UUID?.none)
                    ForEach(activePeople) { Text($0.displayName).tag(UUID?.some($0.id)) }
                }
                if assessmentType == .joint {
                    Picker("Zweite Person", selection: $partnerPersonID) {
                        Text("Bitte wählen").tag(UUID?.none)
                        ForEach(activePeople.filter { $0.id != primaryPersonID }) {
                            Text($0.displayName).tag(UUID?.some($0.id))
                        }
                    }
                }
                TextField("Freistellungsbetrag", text: $amount)
                Stepper("Gültig ab \(validFromYear)", value: $validFromYear, in: 2009...2200)
                Toggle("Zum Kalenderjahresende befristet", isOn: $hasEndYear)
                if hasEndYear {
                    Stepper("Gültig bis Ende \(validThroughYear)", value: $validThroughYear,
                            in: validFromYear...2200)
                }
                Menu {
                    Button("Keine Konten hinterlegen") { accountIDs.removeAll() }
                    ForEach(matchingAccounts) { account in
                        Toggle(account.name, isOn: orderAccountMember(account.id))
                    }
                } label: {
                    Label(accountIDs.isEmpty ? "Kontenabdeckung: institutsweit" : "Kontenabdeckung (\(accountIDs.count))",
                          systemImage: "building.columns")
                }
                Text("Die Auswahl dokumentiert vorhandene Konten. Sie begrenzt den Auftrag nicht; er gilt immer für das gesamte Institut.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Notiz", text: $note, axis: .vertical)
                Toggle("Aktiv", isOn: $isActive)
            }
            .formStyle(.grouped)
        }
        .frame(width: 620, height: 650)
        .onChange(of: institution) { _, _ in
            accountIDs.formIntersection(Set(matchingAccounts.map(\.id)))
        }
        .onChange(of: assessmentType) { _, type in
            if type == .individual { partnerPersonID = nil }
        }
    }

    private func orderAccountMember(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { accountIDs.contains(id) },
            set: { included in
                if included { accountIDs.insert(id) }
                else { accountIDs.remove(id) }
            }
        )
    }

    private func save() {
        do {
            guard let primaryPersonID else { return }
            let money = try Money(parsing: amount)
            let value = TaxAllowanceOrder(
                id: order?.id ?? UUID(), institution: institution,
                assessmentType: assessmentType, primaryPersonID: primaryPersonID,
                partnerPersonID: assessmentType == .joint ? partnerPersonID : nil,
                allowanceMinor: abs(money.minorUnits), validFromYear: validFromYear,
                validThroughYear: hasEndYear ? max(validFromYear, validThroughYear) : nil,
                accountIDs: accountIDs, note: note, isActive: isActive
            )
            if store.saveTaxAllowanceOrder(value) { dismiss() }
        } catch { store.errorMessage = error.localizedDescription }
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
