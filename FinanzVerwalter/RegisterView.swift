import SwiftUI

struct RegisterView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var selection = Set<UUID>()
    @State private var showEditor = false
    @State private var showBulkEditor = false
    @State private var editingTransaction: FinanceTransaction?
    @State private var statusFilter: TransactionStatus?
    @State private var categoryFilter: RegisterCategoryFilter = .all
    @State private var periodFilter: RegisterPeriodFilter = .all
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var customEnd = Date.now
    @State private var selectedSavedViewID: UUID?
    @State private var showSaveView = false
    @State private var savedViewName = ""
    @AppStorage("registerRowMode") private var rowModeRaw = RegisterRowMode.single.rawValue
    @AppStorage("registerVisibleColumnsV1") private var visibleColumnsRaw = ""
    @AppStorage("savedRegisterViewsV1") private var savedViewsRaw = ""

    private var rowMode: RegisterRowMode {
        get { RegisterRowMode(rawValue: rowModeRaw) ?? .single }
        nonmutating set { rowModeRaw = newValue.rawValue }
    }

    private var visibleColumns: Set<RegisterColumn> {
        get { RegisterPreferencesCodec.decodeColumns(visibleColumnsRaw) }
        nonmutating set {
            visibleColumnsRaw = RegisterPreferencesCodec.encodeColumns(newValue)
        }
    }

    private var savedViews: [SavedRegisterView] {
        RegisterPreferencesCodec.decodeViews(savedViewsRaw)
    }

    private var visibleTransactions: [FinanceTransaction] {
        store.filteredTransactions.filter { transaction in
            let statusMatches = statusFilter == nil || transaction.status == statusFilter
            let categoryMatches: Bool
            switch categoryFilter {
            case .all:
                categoryMatches = true
            case .uncategorized:
                categoryMatches = transaction.categoryID == nil && transaction.transferID == nil
            case .category(let id):
                categoryMatches = transaction.categoryID == id
                    || transaction.splits.contains { $0.categoryID == id }
            }
            return statusMatches && categoryMatches && periodFilter.contains(
                transaction.bookingDate,
                customStart: customStart,
                customEnd: customEnd
            )
        }
    }

    var body: some View {
        let runningBalances = store.runningBalances(accountID: store.selectedAccountID)
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

            HStack(spacing: 12) {
                Picker("Status", selection: $statusFilter) {
                    Text("Alle Status").tag(TransactionStatus?.none)
                    ForEach(TransactionStatus.allCases, id: \.self) {
                        Text($0.title).tag(Optional($0))
                    }
                }
                .frame(width: 150)
                Picker("Kategorie", selection: $categoryFilter) {
                    Text("Alle Kategorien").tag(RegisterCategoryFilter.all)
                    Text("Nicht kategorisiert").tag(RegisterCategoryFilter.uncategorized)
                    Divider()
                    ForEach(store.categoriesByPath.filter(\.isActive)) {
                        Text(store.categoryPath($0.id))
                            .tag(RegisterCategoryFilter.category($0.id))
                    }
                }
                .frame(width: 210)
                Picker("Zeitraum", selection: $periodFilter) {
                    ForEach(RegisterPeriodFilter.allCases) {
                        Text($0.title).tag($0)
                    }
                }
                .frame(width: 150)
                Picker(
                    "Zeilen",
                    selection: Binding(get: { rowMode }, set: { rowMode = $0 })
                ) {
                    ForEach(RegisterRowMode.allCases) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 175)
                registerViewMenu
                if periodFilter == .custom {
                    DatePicker("Von", selection: $customStart, displayedComponents: .date)
                        .labelsHidden()
                    Text("bis").foregroundStyle(.secondary)
                    DatePicker("Bis", selection: $customEnd, displayedComponents: .date)
                        .labelsHidden()
                }
                Spacer()
                Button("Filter zurücksetzen", systemImage: "line.3.horizontal.decrease.circle") {
                    statusFilter = nil
                    categoryFilter = .all
                    periodFilter = .all
                }
                .disabled(statusFilter == nil && categoryFilter == .all && periodFilter == .all)
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            Table(visibleTransactions, selection: $selection) {
                TableColumnForEach(orderedVisibleColumns) { column in
                    TableColumn(column.title) { value in
                        registerCell(
                            value,
                            column: column,
                            runningBalances: runningBalances
                        )
                    }
                    .width(min: column.minimumWidth, ideal: column.idealWidth)
                }
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if ids.count == 1 {
                    Button("Bearbeiten") {
                        editingTransaction = store.transactions.first { ids.contains($0.id) }
                        showEditor = editingTransaction != nil
                    }
                }
                Button("Kategorie für Auswahl ändern …") {
                    selection = ids
                    showBulkEditor = true
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
                if visibleTransactions.isEmpty {
                    ContentUnavailableView(
                        "Keine Buchungen",
                        systemImage: "list.bullet.rectangle",
                        description: Text(
                            store.transactions.isEmpty
                                ? "Lege eine Buchung an oder importiere Umsätze."
                                : "Die gewählten Filter liefern keine Treffer."
                        )
                    )
                }
            }
            Divider()
            HStack {
                Text("\(visibleTransactions.count) Buchungen")
                if !selection.isEmpty {
                    Divider().frame(height: 14)
                    Text("\(selection.count) ausgewählt")
                        .fontWeight(.semibold)
                    Button("Kategorie ändern …", systemImage: "tag") {
                        showBulkEditor = true
                    }
                }
                Spacer()
                Text(filteredTotalsText)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .sheet(isPresented: $showEditor) {
            TransactionEditorView(transaction: editingTransaction)
        }
        .sheet(isPresented: $showBulkEditor) {
            BulkCategoryEditorView(transactionIDs: selection) {
                selection.removeAll()
            }
        }
        .sheet(isPresented: $showSaveView) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Kontoblatt-Ansicht speichern")
                    .font(.title2.bold())
                Text(
                    "Gespeichert werden Konto, Filter, Zeitraum, Zeilenmodus "
                        + "und die sichtbaren Spalten."
                )
                .foregroundStyle(.secondary)
                TextField("Name der Ansicht", text: $savedViewName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Abbrechen", role: .cancel) { showSaveView = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Speichern") { saveCurrentView() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(
                            savedViewName.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                        )
                }
            }
            .padding(24)
            .frame(width: 480)
        }
        .onChange(of: visibleTransactions.map(\.id)) {
            selection.formIntersection(Set(visibleTransactions.map(\.id)))
        }
    }

    private var orderedVisibleColumns: [RegisterColumn] {
        RegisterColumn.allCases.filter(visibleColumns.contains)
    }

    @ViewBuilder
    private func registerCell(
        _ value: FinanceTransaction,
        column: RegisterColumn,
        runningBalances: [UUID: Int64]
    ) -> some View {
        switch column {
        case .date:
            Text(
                value.bookingDate,
                format: .dateTime.day().month(.twoDigits).year()
            )
            .monospacedDigit()
            .frame(height: rowMode.rowHeight)
        case .valueDate:
            Text(
                value.valueDate ?? value.bookingDate,
                format: .dateTime.day().month(.twoDigits).year()
            )
            .monospacedDigit()
            .foregroundStyle(value.valueDate == nil ? .secondary : .primary)
            .frame(height: rowMode.rowHeight)
        case .reference:
            Text(value.reference.isEmpty ? "–" : value.reference)
                .lineLimit(1)
                .help(value.reference)
                .frame(height: rowMode.rowHeight, alignment: .leading)
        case .status:
            Image(systemName: statusIcon(value.status))
                .foregroundStyle(statusColor(value.status))
                .help(value.status.title)
                .frame(height: rowMode.rowHeight)
        case .payee:
            VStack(alignment: .leading, spacing: 1) {
                Text(value.payee)
                    .lineLimit(rowMode == .twoLines ? 2 : 1)
                if rowMode == .twoLines,
                   let valueDate = value.valueDate,
                   !Calendar.current.isDate(
                    valueDate,
                    inSameDayAs: value.bookingDate
                   ) {
                    Text(
                        "Wertstellung "
                            + valueDate.formatted(date: .numeric, time: .omitted)
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(height: rowMode.rowHeight, alignment: .leading)
        case .purpose:
            let detail = transactionDetail(value)
            VStack(alignment: .leading, spacing: 1) {
                Text(value.purpose)
                    .lineLimit(rowMode == .twoLines && detail.isEmpty ? 2 : 1)
                if rowMode == .twoLines, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(height: rowMode.rowHeight, alignment: .leading)
            .help(
                [value.purpose, detail]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            )
        case .category:
            let path = store.transactionCategoryPath(value)
            Text(path)
                .lineLimit(rowMode == .twoLines ? 2 : 1)
                .truncationMode(.middle)
                .help(path)
                .frame(height: rowMode.rowHeight, alignment: .leading)
        case .tags:
            let tags = value.tagIDs.map(store.tagName).joined(separator: ", ")
            Text(tags.isEmpty ? "–" : tags)
                .lineLimit(rowMode == .twoLines ? 2 : 1)
                .truncationMode(.middle)
                .help(tags)
                .frame(height: rowMode.rowHeight, alignment: .leading)
        case .account:
            Text(store.accountName(value.accountID))
                .frame(height: rowMode.rowHeight, alignment: .leading)
        case .amount:
            Text(
                Money(
                    minorUnits: value.amountMinor,
                    currency: value.currency
                ).formatted
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
            .monospacedDigit()
            .foregroundStyle(value.amountMinor < 0 ? .primary : Color.green)
            .frame(height: rowMode.rowHeight)
        case .balance:
            Text(
                Money(
                    minorUnits: runningBalances[value.id] ?? 0,
                    currency: value.currency
                ).formatted
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
            .monospacedDigit()
            .frame(height: rowMode.rowHeight)
        }
    }

    private var registerViewMenu: some View {
        Menu {
            if savedViews.isEmpty {
                Text("Noch keine gespeicherte Ansicht")
            } else {
                ForEach(savedViews) { view in
                    Button {
                        apply(view)
                    } label: {
                        if selectedSavedViewID == view.id {
                            Label(view.name, systemImage: "checkmark")
                        } else {
                            Text(view.name)
                        }
                    }
                }
                Divider()
            }
            Button("Aktuelle Ansicht speichern …", systemImage: "plus") {
                savedViewName = selectedSavedViewID.flatMap { id in
                    savedViews.first { $0.id == id }?.name
                } ?? ""
                showSaveView = true
            }
            Button("Ausgewählte Ansicht löschen", systemImage: "trash", role: .destructive) {
                deleteSelectedView()
            }
            .disabled(selectedSavedViewID == nil)
            Divider()
            Menu("Sichtbare Spalten", systemImage: "rectangle.split.3x1") {
                ForEach(RegisterColumn.allCases) { column in
                    Toggle(
                        column.title,
                        isOn: Binding(
                            get: { visibleColumns.contains(column) },
                            set: { _ in toggle(column) }
                        )
                    )
                    .disabled(
                        visibleColumns.count == 1 && visibleColumns.contains(column)
                    )
                }
                Divider()
                Button("Standardspalten wiederherstellen") {
                    visibleColumns = RegisterColumn.defaultSet
                }
            }
        } label: {
            Label(
                selectedSavedViewID.flatMap { id in
                    savedViews.first { $0.id == id }?.name
                } ?? "Ansicht",
                systemImage: "tablecells.badge.ellipsis"
            )
        }
    }

    private func toggle(_ column: RegisterColumn) {
        var columns = visibleColumns
        if columns.contains(column), columns.count > 1 {
            columns.remove(column)
        } else {
            columns.insert(column)
        }
        visibleColumns = columns
        selectedSavedViewID = nil
    }

    private func saveCurrentView() {
        let name = savedViewName.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingID = savedViews.first {
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }?.id
        let id = selectedSavedViewID ?? existingID ?? UUID()
        let view = SavedRegisterView(
            id: id,
            name: name,
            accountID: store.selectedAccountID,
            statusRawValue: statusFilter?.rawValue,
            categorySelection: categoryFilter.savedSelection,
            periodRawValue: periodFilter.rawValue,
            customStart: customStart,
            customEnd: customEnd,
            rowModeRawValue: rowMode.rawValue,
            visibleColumns: visibleColumns
        )
        var values = savedViews.filter { $0.id != id }
        values.append(view)
        values.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        do {
            savedViewsRaw = try RegisterPreferencesCodec.encodeViews(values)
            selectedSavedViewID = id
            showSaveView = false
            store.statusText = "Kontoblatt-Ansicht „\(view.name)“ gespeichert"
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func apply(_ view: SavedRegisterView) {
        if let accountID = view.accountID,
           store.accounts.contains(where: { $0.id == accountID }) {
            store.selectedAccountID = accountID
        } else if view.accountID == nil {
            store.selectedAccountID = nil
        }
        statusFilter = view.statusRawValue.flatMap(TransactionStatus.init(rawValue:))
        let savedCategoryFilter = RegisterCategoryFilter(view.categorySelection)
        if case .category(let categoryID) = savedCategoryFilter,
           !store.categories.contains(where: { $0.id == categoryID }) {
            categoryFilter = .all
        } else {
            categoryFilter = savedCategoryFilter
        }
        periodFilter = RegisterPeriodFilter(rawValue: view.periodRawValue) ?? .all
        customStart = view.customStart
        customEnd = view.customEnd
        rowMode = RegisterRowMode(rawValue: view.rowModeRawValue) ?? .single
        visibleColumns = view.visibleColumns
        selectedSavedViewID = view.id
        selection.removeAll()
    }

    private func deleteSelectedView() {
        guard let selectedSavedViewID else { return }
        let values = savedViews.filter { $0.id != selectedSavedViewID }
        do {
            savedViewsRaw = try RegisterPreferencesCodec.encodeViews(values)
            self.selectedSavedViewID = nil
            store.statusText = "Kontoblatt-Ansicht gelöscht"
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private var filteredTotalsText: String {
        let totals = Dictionary(grouping: visibleTransactions, by: \.currency)
            .mapValues { $0.reduce(Int64.zero) { $0 + $1.amountMinor } }
        return totals.keys.sorted().map {
            Money(minorUnits: totals[$0] ?? 0, currency: $0).formatted
        }.joined(separator: " · ")
    }

    private func transactionDetail(_ value: FinanceTransaction) -> String {
        var parts: [String] = []
        if !value.memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(value.memo)
        }
        if !value.reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Ref. \(value.reference)")
        }
        if !value.tagIDs.isEmpty {
            parts.append(value.tagIDs.map(store.tagName).joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
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

private enum RegisterCategoryFilter: Hashable {
    case all
    case uncategorized
    case category(UUID)

    init(_ saved: RegisterCategorySelection) {
        switch saved {
        case .all: self = .all
        case .uncategorized: self = .uncategorized
        case .category(let id): self = .category(id)
        }
    }

    var savedSelection: RegisterCategorySelection {
        switch self {
        case .all: .all
        case .uncategorized: .uncategorized
        case .category(let id): .category(id)
        }
    }
}

private enum RegisterPeriodFilter: String, CaseIterable, Identifiable {
    case all
    case currentMonth
    case currentYear
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "Gesamter Zeitraum"
        case .currentMonth: "Dieser Monat"
        case .currentYear: "Dieses Jahr"
        case .custom: "Benutzerdefiniert"
        }
    }

    func contains(_ date: Date, customStart: Date, customEnd: Date) -> Bool {
        let calendar = Calendar.current
        switch self {
        case .all:
            return true
        case .currentMonth:
            return calendar.isDate(date, equalTo: .now, toGranularity: .month)
        case .currentYear:
            return calendar.isDate(date, equalTo: .now, toGranularity: .year)
        case .custom:
            let start = calendar.startOfDay(for: min(customStart, customEnd))
            let end = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: max(customStart, customEnd))
            ) ?? max(customStart, customEnd)
            return date >= start && date < end
        }
    }

}

private enum RegisterRowMode: String, CaseIterable, Identifiable {
    case single
    case twoLines

    var id: Self { self }
    var title: String {
        switch self {
        case .single: "Einzeilig"
        case .twoLines: "Zweizeilig"
        }
    }

    var rowHeight: CGFloat {
        self == .twoLines ? 38 : 20
    }
}

private struct BulkCategoryEditorView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    let transactionIDs: Set<UUID>
    let onCompletion: () -> Void

    @State private var categoryID: UUID?
    @State private var showConfirmation = false

    private var transactions: [FinanceTransaction] {
        store.transactions.filter { transactionIDs.contains($0.id) }
    }

    private var protectedTransactions: [FinanceTransaction] {
        transactions.filter {
            $0.status == .reconciled || $0.transferID != nil || !$0.splits.isEmpty
        }
    }

    private var totals: [(currency: String, amount: Int64)] {
        Dictionary(grouping: transactions, by: \.currency)
            .map { ($0.key, $0.value.reduce(Int64.zero) { $0 + $1.amountMinor }) }
            .sorted { $0.currency < $1.currency }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Kategorie für Auswahl ändern")
                .font(.title2.bold())
            Text("\(transactions.count) Buchungen werden gemeinsam geprüft und atomar geändert.")
                .foregroundStyle(.secondary)

            LabeledContent("Ausgewählte Summe") {
                VStack(alignment: .trailing) {
                    ForEach(totals, id: \.currency) {
                        Text(Money(minorUnits: $0.amount, currency: $0.currency).formatted)
                            .monospacedDigit()
                    }
                }
            }

            Picker("Neue Kategorie", selection: $categoryID) {
                Text("Nicht kategorisiert").tag(UUID?.none)
                ForEach(store.categoriesByPath.filter(\.isActive)) {
                    Text(store.categoryPath($0.id)).tag(UUID?.some($0.id))
                }
            }

            if !protectedTransactions.isEmpty {
                Label(
                    "\(protectedTransactions.count) geschützte Buchungen in der Auswahl. "
                        + "Abgeglichene Buchungen, Umbuchungen und Splitbuchungen werden nicht massenweise geändert.",
                    systemImage: "lock.trianglebadge.exclamationmark"
                )
                .foregroundStyle(.orange)
            } else {
                Label(
                    "Die Änderung betrifft ausschließlich die Kategorie. Beträge, Konten und Status bleiben unverändert.",
                    systemImage: "checkmark.shield"
                )
                .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Änderung prüfen …") {
                    showConfirmation = true
                }
                .keyboardShortcut(.defaultAction)
                .disabled(transactions.isEmpty || !protectedTransactions.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
        .confirmationDialog(
            "Kategorie wirklich für \(transactions.count) Buchungen ändern?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Für \(transactions.count) Buchungen anwenden") {
                if store.bulkAssignCategory(
                    transactionIDs: transactionIDs,
                    categoryID: categoryID
                ) {
                    onCompletion()
                    dismiss()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Änderung wird in einem Datenbankvorgang durchgeführt und protokolliert.")
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
    @AppStorage("registerRowMode") private var rowModeRaw = RegisterRowMode.single.rawValue
    @AppStorage("registerVisibleColumnsV1") private var visibleColumnsRaw = ""

    private var rowMode: RegisterRowMode {
        get { RegisterRowMode(rawValue: rowModeRaw) ?? .single }
        nonmutating set { rowModeRaw = newValue.rawValue }
    }

    private var visibleColumns: Set<RegisterColumn> {
        get { RegisterPreferencesCodec.decodeColumns(visibleColumnsRaw) }
        nonmutating set {
            visibleColumnsRaw = RegisterPreferencesCodec.encodeColumns(newValue)
        }
    }

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
        let runningBalances = store.runningBalances()
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sammelkontoblatt").font(.title2.bold())
                    Text("Alle normalen Buchungskonten · Vergangenheit, Heute und erwartete Zukunft")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker(
                    "Zeilen",
                    selection: Binding(get: { rowMode }, set: { rowMode = $0 })
                ) {
                    ForEach(RegisterRowMode.allCases) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 175)
                registerColumnMenu
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
                TableColumnForEach(orderedVisibleColumns) { column in
                    TableColumn(column.title) { value in
                        combinedRegisterCell(
                            value,
                            column: column,
                            runningBalances: runningBalances
                        )
                    }
                    .width(min: column.minimumWidth, ideal: column.idealWidth)
                }
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

    private var orderedVisibleColumns: [RegisterColumn] {
        RegisterColumn.allCases.filter(visibleColumns.contains)
    }

    @ViewBuilder
    private func combinedRegisterCell(
        _ value: FinanceTransaction,
        column: RegisterColumn,
        runningBalances: [UUID: Int64]
    ) -> some View {
        switch column {
        case .date:
            Text(
                value.bookingDate,
                format: .dateTime.day().month(.twoDigits).year()
            )
            .foregroundStyle(value.bookingDate > Date() ? .blue : .primary)
            .frame(height: rowMode.rowHeight)
        case .valueDate:
            Text(
                value.valueDate ?? value.bookingDate,
                format: .dateTime.day().month(.twoDigits).year()
            )
            .foregroundStyle(value.valueDate == nil ? .secondary : .primary)
            .frame(height: rowMode.rowHeight)
        case .reference:
            Text(value.reference.isEmpty ? "–" : value.reference)
                .lineLimit(1)
                .help(value.reference)
                .frame(height: rowMode.rowHeight, alignment: .leading)
        case .status:
            Text(value.status.title)
                .frame(height: rowMode.rowHeight, alignment: .leading)
        case .payee:
            Text(value.payee)
                .lineLimit(rowMode == .twoLines ? 2 : 1)
                .frame(height: rowMode.rowHeight, alignment: .leading)
        case .purpose:
            VStack(alignment: .leading, spacing: 1) {
                Text(value.purpose)
                    .lineLimit(rowMode == .twoLines ? 2 : 1)
                if rowMode == .twoLines,
                   !value.memo.trimmingCharacters(
                    in: .whitespacesAndNewlines
                   ).isEmpty {
                    Text(value.memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(height: rowMode.rowHeight, alignment: .leading)
        case .category:
            let path = store.transactionCategoryPath(value)
            Text(path)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(path)
                .frame(height: rowMode.rowHeight, alignment: .leading)
        case .tags:
            let tags = value.tagIDs.map(store.tagName).joined(separator: ", ")
            Text(tags.isEmpty ? "–" : tags)
                .lineLimit(rowMode == .twoLines ? 2 : 1)
                .truncationMode(.middle)
                .help(tags)
                .frame(height: rowMode.rowHeight, alignment: .leading)
        case .account:
            Text(store.accountName(value.accountID))
                .frame(height: rowMode.rowHeight, alignment: .leading)
        case .amount:
            Text(
                Money(
                    minorUnits: value.amountMinor,
                    currency: value.currency
                ).formatted
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
            .monospacedDigit()
            .frame(height: rowMode.rowHeight)
        case .balance:
            Text(
                Money(
                    minorUnits: runningBalances[value.id] ?? 0,
                    currency: value.currency
                ).formatted
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
            .monospacedDigit()
            .frame(height: rowMode.rowHeight)
        }
    }

    private var registerColumnMenu: some View {
        Menu {
            ForEach(RegisterColumn.allCases) { column in
                Toggle(
                    column.title,
                    isOn: Binding(
                        get: { visibleColumns.contains(column) },
                        set: { _ in toggle(column) }
                    )
                )
                .disabled(
                    visibleColumns.count == 1 && visibleColumns.contains(column)
                )
            }
            Divider()
            Button("Standardspalten wiederherstellen") {
                visibleColumns = RegisterColumn.defaultSet
            }
        } label: {
            Label("Spalten", systemImage: "rectangle.split.3x1")
        }
    }

    private func toggle(_ column: RegisterColumn) {
        var columns = visibleColumns
        if columns.contains(column), columns.count > 1 {
            columns.remove(column)
        } else {
            columns.insert(column)
        }
        visibleColumns = columns
    }
}
