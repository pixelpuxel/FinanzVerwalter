import SwiftUI
import UniformTypeIdentifiers
import AppKit
import Charts

private func transactionFlagColor(_ flag: TransactionFlag) -> Color {
    switch flag {
    case .red: .red
    case .orange: .orange
    case .yellow: .yellow
    case .green: .green
    case .blue: .blue
    case .purple: .purple
    }
}

struct RegisterView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var selection = Set<UUID>()
    @State private var showEditor = false
    @State private var showBulkEditor = false
    @State private var editingTransaction: FinanceTransaction?
    @State private var editingTransferID: UUID?
    @State private var showTransferEditor = false
    @State private var movingTransaction: FinanceTransaction?
    @State private var editorTemplate: TransactionTemplate?
    @State private var editorTemplateUsageID: UUID?
    @State private var showTemplateNameEditor = false
    @State private var templateName = ""
    @State private var templateSource: FinanceTransaction?
    @State private var templateFields = Set(TransactionTemplateField.allCases)
    @State private var scheduledDraft: ScheduledTransaction?
    @State private var showDeleteConfirmation = false
    @State private var showTransactionUndoConfirmation = false
    @State private var statusFilter: TransactionStatus?
    @State private var flagFilterRaw = "all"
    @State private var categoryFilter: RegisterCategoryFilter = .all
    @State private var tagFilterID: UUID?
    @State private var periodFilter: RegisterPeriodFilter = .all
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var customEnd = Date.now
    @State private var selectedSavedViewID: UUID?
    @State private var showSaveView = false
    @State private var savedViewName = ""
    @State private var showPDFExporter = false
    @State private var registerPDFDocument = RegisterPDFDocument(data: Data())
    @State private var showCSVExporter = false
    @State private var registerCSVDocument = RegisterCSVDocument(data: Data())
    @State private var quickEntryAccountID: UUID?
    @State private var quickEntryDate = Date()
    @State private var quickEntryPayee = ""
    @State private var quickEntryPurpose = ""
    @State private var quickEntryCategoryID: UUID?
    @State private var quickEntryAmount = ""
    @State private var quickEntryStatus: TransactionStatus = .booked
    @FocusState private var quickEntryPayeeFocused: Bool
    @AppStorage("registerMiniReportVisibleV1")
    private var showMiniReport = true
    @AppStorage("registerMiniReportDimensionV1")
    private var miniReportDimensionRaw =
        RegisterMiniReportDimension.payee.rawValue
    @AppStorage("registerSplitViewVisibleV1")
    private var showSplitRegister = false
    @AppStorage("registerSecondaryAccountIDV1")
    private var secondaryAccountIDRaw = ""
    @AppStorage("registerRowMode") private var rowModeRaw = RegisterRowMode.single.rawValue
    @AppStorage("registerVisibleColumnsV1") private var visibleColumnsRaw = ""
    @AppStorage("registerAmountColumnModeV1")
    private var amountColumnModeRaw = RegisterAmountColumnMode.amount.rawValue
    @AppStorage("registerVisibleColumnsIncludesBalanceV4")
    private var visibleColumnsIncludesBalance = false
    @AppStorage("registerVisibleColumnsIncludesFlagV5")
    private var visibleColumnsIncludesFlag = false
    @AppStorage("savedRegisterViewsV1") private var savedViewsRaw = ""
    @AppStorage("registerOpenAccountTabsV1") private var openAccountTabsRaw = ""
    @AppStorage("registerF3FieldV1")
    private var f3FieldRaw = RegisterF3Field.payee.rawValue
    @AppStorage("registerSortColumnV1")
    private var sortColumnRaw = RegisterColumn.date.rawValue
    @AppStorage("registerSortAscendingV1")
    private var sortAscending = true
    @AppStorage("registerQuickEntryVisibleV1")
    private var showQuickEntry = true

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

    private var amountColumnMode: RegisterAmountColumnMode {
        get {
            RegisterAmountColumnMode(rawValue: amountColumnModeRaw) ?? .amount
        }
        nonmutating set {
            amountColumnModeRaw = newValue.rawValue
            let current = RegisterColumn(rawValue: sortColumnRaw) ?? .date
            if newValue == .debitCredit, current == .amount {
                sortColumnRaw = RegisterColumn.debit.rawValue
            } else if newValue == .amount,
                      current == .debit || current == .credit {
                sortColumnRaw = RegisterColumn.amount.rawValue
            }
        }
    }

    private var savedViews: [SavedRegisterView] {
        RegisterPreferencesCodec.decodeViews(savedViewsRaw)
    }

    private var openAccountTabIDs: [UUID] {
        get {
            RegisterPreferencesCodec.decodeTabAccountIDs(
                openAccountTabsRaw,
                availableAccountIDs: Set(store.accounts.map(\.id))
            )
        }
        nonmutating set {
            openAccountTabsRaw = RegisterPreferencesCodec.encodeTabAccountIDs(newValue)
        }
    }

    private var openAccountTabs: [FinanceAccount] {
        openAccountTabIDs.compactMap { id in
            store.accounts.first { $0.id == id }
        }
    }

    private var visibleTransactions: [FinanceTransaction] {
        let filtered = store.filteredTransactions.filter { transaction in
            let statusMatches = statusFilter == nil || transaction.status == statusFilter
            let flagMatches = flagFilterRaw == "all"
                || (flagFilterRaw == "none" && transaction.flag == nil)
                || transaction.flag?.rawValue == flagFilterRaw
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
            let tagMatches: Bool
            if let tagFilterID {
                tagMatches = transaction.tagIDs.contains(tagFilterID)
                    || transaction.splits.contains { $0.tagIDs.contains(tagFilterID) }
            } else {
                tagMatches = true
            }
            return statusMatches && flagMatches && categoryMatches && tagMatches && periodFilter.contains(
                transaction.bookingDate,
                customStart: customStart,
                customEnd: customEnd
            )
        }
        let runningBalances = store.runningBalances(
            accountID: store.selectedAccountID
        )
        let labels = registerSortLabels(for: filtered)
        return RegisterSorter.sorted(
            filtered,
            by: RegisterColumn(rawValue: sortColumnRaw) ?? .date,
            ascending: sortAscending,
            runningBalances: runningBalances,
            labels: labels
        )
    }

    var body: some View {
        let runningBalances = store.runningBalances(accountID: store.selectedAccountID)
        let visibleRows = visibleTransactions
        let sortLabels = registerSortLabels(for: visibleRows)
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
                .accessibilityIdentifier("register.accountPicker")
                if let undo = store.latestTransactionUndo {
                    Button("Rückgängig", systemImage: "arrow.uturn.backward") {
                        showTransactionUndoConfirmation = true
                    }
                    .help(
                        "\(undo.title) (\(undo.transactionCount) Buchungen) konfliktgeschützt zurücknehmen"
                    )
                    .accessibilityLabel("Letzte Buchungsänderung rückgängig machen")
                    .accessibilityValue(undo.title)
                    .accessibilityIdentifier("register.transactionUndo")
                }
                if let account = store.selectedAccount {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Aktueller Saldo").font(.caption).foregroundStyle(.secondary)
                        Text(Money(minorUnits: store.balances[account.id] ?? 0).formatted)
                            .font(.title3.bold().monospacedDigit())
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Aktueller Saldo \(account.name)")
                    .accessibilityValue(
                        Money(
                            minorUnits: store.balances[account.id] ?? 0,
                            currency: account.currency
                        ).formatted
                    )
                    .accessibilityIdentifier("register.currentBalance")
                }
            }
            .padding(14)

            Divider()
            accountTabs
            Divider()

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                Picker("Status", selection: $statusFilter) {
                    Text("Alle Status").tag(TransactionStatus?.none)
                    ForEach(TransactionStatus.allCases, id: \.self) {
                        Text($0.title).tag(Optional($0))
                    }
                }
                .frame(width: 150)
                .accessibilityIdentifier("register.statusFilter")
                Picker("Kennzeichen", selection: $flagFilterRaw) {
                    Text("Alle Kennzeichen").tag("all")
                    Text("Ohne Kennzeichen").tag("none")
                    Divider()
                    ForEach(TransactionFlag.allCases) { flag in
                        Label(flag.title, systemImage: "flag.fill").tag(flag.rawValue)
                    }
                }
                .frame(width: 170)
                .accessibilityIdentifier("register.flagFilter")
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
                .accessibilityIdentifier("register.categoryFilter")
                Picker("Klasse/Tag", selection: $tagFilterID) {
                    Text("Alle Klassen/Tags").tag(UUID?.none)
                    ForEach(store.tagsByPath.filter(\.isActive)) { tag in
                        Text(store.tagPath(tag.id)).tag(UUID?.some(tag.id))
                    }
                }
                .frame(width: 160)
                .accessibilityIdentifier("register.tagFilter")
                Picker("Zeitraum", selection: $periodFilter) {
                    ForEach(RegisterPeriodFilter.allCases) {
                        Text($0.title).tag($0)
                    }
                }
                .frame(width: 150)
                .accessibilityIdentifier("register.periodFilter")
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
                .accessibilityIdentifier("register.rowMode")
                Menu {
                    Picker(
                        "Betragsspalten",
                        selection: Binding(
                            get: { amountColumnMode },
                            set: {
                                amountColumnMode = $0
                                selectedSavedViewID = nil
                            }
                        )
                    ) {
                        ForEach(RegisterAmountColumnMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                } label: {
                    Label(
                        amountColumnMode.title,
                        systemImage: amountColumnMode == .amount
                            ? "eurosign" : "rectangle.split.2x1"
                    )
                }
                .help("Eine Betragsspalte oder getrennte Soll-/Haben-Spalten")
                .accessibilityIdentifier("register.amountColumnMode")
                Menu {
                    Picker(
                        "Sortieren nach",
                        selection: Binding(
                            get: {
                                RegisterColumn(rawValue: sortColumnRaw) ?? .date
                            },
                            set: {
                                sortColumnRaw = $0.rawValue
                                selectedSavedViewID = nil
                            }
                        )
                    ) {
                        ForEach(
                            RegisterColumnLayout.columns(
                                visible: Set(RegisterColumn.configurableCases),
                                amountMode: amountColumnMode
                            )
                        ) { column in
                            Text(column.title).tag(column)
                        }
                    }
                    Divider()
                    Picker(
                        "Richtung",
                        selection: Binding(
                            get: { sortAscending },
                            set: {
                                sortAscending = $0
                                selectedSavedViewID = nil
                            }
                        )
                    ) {
                        Text("Aufsteigend").tag(true)
                        Text("Absteigend").tag(false)
                    }
                } label: {
                    Label(
                        "Sortierung",
                        systemImage: sortAscending
                            ? "arrow.up.arrow.down.square"
                            : "arrow.down.arrow.up.square"
                    )
                }
                .help(
                    "Sortiert nach \((RegisterColumn(rawValue: sortColumnRaw) ?? .date).title) "
                        + (sortAscending ? "aufsteigend" : "absteigend")
                )
                .accessibilityIdentifier("register.sortMenu")
                registerViewMenu
                transactionTemplateMenu
                registerOutputMenu(runningBalances: runningBalances)
                f3FilterMenu
                Button {
                    showQuickEntry.toggle()
                    if showQuickEntry { quickEntryPayeeFocused = true }
                } label: {
                    Label(
                        "Schnellbuchung",
                        systemImage: showQuickEntry
                            ? "rectangle.and.pencil.and.ellipsis"
                            : "rectangle.and.pencil.and.ellipsis"
                    )
                }
                .help(
                    showQuickEntry
                        ? "Inline-Buchungszeile ausblenden"
                        : "Normale Buchung direkt im Kontoblatt erfassen"
                )
                Button {
                    if !showMiniReport { showSplitRegister = false }
                    showMiniReport.toggle()
                } label: {
                    Label(
                        "Minireport",
                        systemImage: showMiniReport
                            ? "sidebar.right" : "sidebar.right"
                    )
                }
                .help(
                    showMiniReport
                        ? "Minireport ausblenden"
                        : "Minireport für die markierte Buchung einblenden"
                )
                Button {
                    if !showSplitRegister {
                        showMiniReport = false
                        ensureSecondaryAccount()
                    }
                    showSplitRegister.toggle()
                } label: {
                    Label(
                        "Teilen",
                        systemImage: "rectangle.split.2x1"
                    )
                }
                .help(
                    showSplitRegister
                        ? "Zweites Kontoblatt schließen"
                        : "Zweites Kontoblatt daneben öffnen"
                )
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
                        flagFilterRaw = "all"
                        categoryFilter = .all
                        tagFilterID = nil
                        periodFilter = .all
                    }
                    .disabled(
                        statusFilter == nil && flagFilterRaw == "all" && categoryFilter == .all
                            && tagFilterID == nil && periodFilter == .all
                    )
                }
            }
            .scrollIndicators(.hidden)
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            if showQuickEntry {
                quickEntryRow
                Divider()
            }

            HStack(spacing: 0) {
                Table(
                    visibleRows,
                    selection: $selection,
                    sortOrder: registerSortOrderBinding(
                        runningBalances: runningBalances,
                        labels: sortLabels
                    )
                ) {
                    TableColumnForEach(orderedVisibleColumns) { column in
                        TableColumn(
                            column.title,
                            sortUsing: RegisterTableComparator(
                                column: column,
                                runningBalances: runningBalances,
                                labels: sortLabels
                            )
                        ) { value in
                            accessibleRegisterCell(
                                value,
                                column: column,
                                runningBalances: runningBalances
                            )
                        }
                        .width(min: column.minimumWidth, ideal: column.idealWidth)
                    }
                }
                .accessibilityLabel("Kontoblatt Buchungstabelle")
                .accessibilityValue(
                    RegisterAccessibility.tableValue(
                        visibleCount: visibleTransactions.count,
                        selectedCount: selection.count
                    )
                )
                .accessibilityHint(
                    "Mit den Pfeiltasten navigieren; Eingabe öffnet die markierte Buchung."
                )
                .accessibilityIdentifier("register.transactionTable")
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if ids.count == 1,
                       let transaction = store.transactions.first(where: {
                           ids.contains($0.id)
                        }) {
                        Button("Bearbeiten") {
                            edit(transaction)
                        }
                        Button("Duplizieren …", systemImage: "plus.square.on.square") {
                            prepareDuplicate(transaction)
                        }
                        .disabled(transaction.transferID != nil)
                        Button("Kopieren", systemImage: "doc.on.doc") {
                            copyToPasteboard(transaction)
                        }
                        Button("In anderes Konto verschieben …", systemImage: "tray.and.arrow.down") {
                            movingTransaction = transaction
                        }
                        .disabled(
                            transaction.status == .reconciled
                                || transaction.transferID != nil
                        )
                        Divider()
                        Button("Als Vorlage merken …") {
                            selection = ids
                            prepareTemplateFromSelection()
                        }
                        Button(
                            "Als regelmäßigen Vorgang …",
                            systemImage: "calendar.badge.plus"
                        ) {
                            prepareScheduledTransaction(from: transaction)
                        }
                        .disabled(transaction.transferID != nil)
                        if transaction.categoryID != nil,
                           transaction.splits.isEmpty {
                            Button("Regel aus Buchung erstellen") {
                                _ = store.createRule(from: transaction)
                            }
                        }
                    }
                    Button("Kategorie/Klassen für Auswahl ändern …") {
                        selection = ids
                        showBulkEditor = true
                    }
                    Button("Löschen", role: .destructive) {
                        selection = ids
                        prepareDeletion()
                    }
                } primaryAction: { ids in
                    edit(store.transactions.first { ids.contains($0.id) })
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
                if showSplitRegister {
                    Divider()
                    SecondaryRegisterPane(
                        selectedAccountID: Binding(
                            get: { secondaryAccountID },
                            set: {
                                secondaryAccountIDRaw =
                                    $0?.uuidString ?? ""
                            }
                        ),
                        excludedAccountID: store.selectedAccountID,
                        edit: { transaction in
                            edit(transaction)
                        }
                    )
                    .frame(minWidth: 380, idealWidth: 520)
                }
                if showMiniReport {
                    Divider()
                    RegisterMiniReportPanel(
                        selectedTransaction: selectedTransaction,
                        dimension: Binding(
                            get: {
                                RegisterMiniReportDimension(
                                    rawValue: miniReportDimensionRaw
                                ) ?? .payee
                            },
                            set: { miniReportDimensionRaw = $0.rawValue }
                        )
                    )
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)
                }
            }
            Divider()
            HStack {
                Text("\(visibleTransactions.count) Buchungen")
                if !selection.isEmpty {
                    Divider().frame(height: 14)
                    Text("\(selection.count) ausgewählt")
                        .fontWeight(.semibold)
                    Button("Kategorie/Klassen ändern …", systemImage: "tag") {
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
            TransactionEditorView(
                transaction: editingTransaction,
                template: editorTemplate,
                templateUsageID: editorTemplateUsageID
            )
        }
        .sheet(isPresented: $showTransferEditor) {
            TransferEditorView(transferID: editingTransferID)
        }
        .sheet(isPresented: $showBulkEditor) {
            BulkCategoryEditorView(transactionIDs: selection) {
                selection.removeAll()
            }
        }
        .sheet(item: $movingTransaction) { transaction in
            MoveTransactionView(transaction: transaction) {
                selection.removeAll()
            }
        }
        .sheet(item: $scheduledDraft) { value in
            ScheduledTransactionEditor(value: value)
        }
        .sheet(isPresented: $showSaveView) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Kontoblatt-Ansicht speichern")
                    .font(.title2.bold())
                Text(
                    "Gespeichert werden Konto, Filter, Zeitraum, Zeilenmodus, "
                        + "Betragsdarstellung, Sortierung und sichtbare Spalten."
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
        .sheet(isPresented: $showTemplateNameEditor) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Buchung als Vorlage merken")
                    .font(.title2.bold())
                Text(
                    "Betrag, Konto, Empfänger, Kategorie, Tags und Splits werden "
                        + "gespeichert. Datum, Belegnummer und Importkennung werden "
                        + "bei einer neuen Buchung nicht übernommen."
                )
                .foregroundStyle(.secondary)
                TextField("Vorlagenname", text: $templateName)
                    .textFieldStyle(.roundedBorder)
                GroupBox("Gespeicherte Felder") {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(TransactionTemplateField.allCases) { field in
                            Toggle(
                                field.title,
                                isOn: Binding(
                                    get: { templateFields.contains(field) },
                                    set: { setTemplateField(field, enabled: $0) }
                                )
                            )
                        }
                    }
                    .padding(6)
                }
                Text(
                    templateFields.count == TransactionTemplateField.allCases.count
                        ? "Vollständige Vorlage"
                        : "Teilvorlage · \(templateFields.count) von \(TransactionTemplateField.allCases.count) Feldern"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Abbrechen", role: .cancel) {
                        showTemplateNameEditor = false
                    }
                    Button("Vorlage speichern") {
                        guard let templateSource else { return }
                        if store.saveTransactionTemplate(
                            name: templateName,
                            from: templateSource,
                            includedFields: templateFields
                        ) {
                            showTemplateNameEditor = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        templateName.trimmingCharacters(
                            in: .whitespacesAndNewlines
                            ).isEmpty || templateFields.isEmpty
                    )
                }
            }
            .padding(24)
            .frame(width: 520)
        }
        .fileExporter(
            isPresented: $showCSVExporter,
            document: registerCSVDocument,
            contentType: .commaSeparatedText,
            defaultFilename: registerPDFFilename
        ) { result in
            switch result {
            case .success:
                store.statusText = "Kontoblatt als CSV exportiert"
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showPDFExporter,
            document: registerPDFDocument,
            contentType: .pdf,
            defaultFilename: registerPDFFilename
        ) { result in
            switch result {
            case .success:
                store.statusText = "Kontoblatt als PDF exportiert"
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
        .onChange(of: visibleTransactions.map(\.id)) {
            selection.formIntersection(Set(visibleTransactions.map(\.id)))
        }
        .onChange(of: store.selectedAccountID) {
            addSelectedAccountTabIfNeeded()
            synchronizeQuickEntryAccount(preferSelected: true)
            if showSplitRegister { ensureSecondaryAccount() }
        }
        .onChange(of: store.accounts.map(\.id)) {
            synchronizeAccountTabs()
            synchronizeQuickEntryAccount(preferSelected: false)
        }
        .onAppear {
            migrateBalanceColumnIfNeeded()
            migrateFlagColumnIfNeeded()
            synchronizeAccountTabs()
            addSelectedAccountTabIfNeeded()
            synchronizeQuickEntryAccount(preferSelected: false)
            if showSplitRegister { ensureSecondaryAccount() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .filterRegisterSelection)
        ) { _ in
            applyF3SelectionFilter()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .rememberTransactionTemplate)
        ) { _ in
            prepareTemplateFromSelection()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .deleteRegisterSelection)
        ) { _ in
            prepareDeletion()
        }
        .confirmationDialog(
            "Ausgewählte Buchungen wirklich löschen?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                selection.count == 1
                    ? "Buchung löschen"
                    : "\(selection.count) Buchungen löschen",
                role: .destructive
            ) {
                let values = selection.compactMap { id in
                    store.transactions.first { $0.id == id }
                }
                if store.deleteTransactions(values) {
                    selection.removeAll()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(
                "Umbuchungen werden immer auf beiden Konten gelöscht. "
                    + "Abgeglichene Buchungen bleiben geschützt."
            )
        }
        .confirmationDialog(
            "Letzte Buchungsänderung rückgängig machen?",
            isPresented: $showTransactionUndoConfirmation,
            titleVisibility: .visible
        ) {
            Button("Rückgängig machen", role: .destructive) {
                _ = store.undoLatestTransactionMutation()
                selection.removeAll()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            if let undo = store.latestTransactionUndo {
                Text(
                    "„\(undo.title)“ betrifft \(undo.transactionCount) Buchungen. "
                        + "Zwischenzeitliche Änderungen brechen das gesamte Undo ab."
                )
            }
        }
    }

    private var transactionTemplateMenu: some View {
        Menu {
            if activeTransactionTemplates.isEmpty {
                Text("Keine aktiven Vorlagen")
            } else {
                ForEach(activeTransactionTemplates) { template in
                    Button(transactionTemplateLabel(template)) {
                        editingTransaction = nil
                        editorTemplate = template
                        editorTemplateUsageID = template.id
                        showEditor = true
                    }
                }
            }
            if !store.transactionTemplates.isEmpty {
                Divider()
                Menu("Vorlagen verwalten") {
                    ForEach(store.transactionTemplates) { template in
                        Button(
                            template.effectiveIsActive
                                ? "\(template.name) deaktivieren"
                                : "\(template.name) aktivieren"
                        ) {
                            store.setTransactionTemplateActive(
                                template,
                                isActive: !template.effectiveIsActive
                            )
                        }
                    }
                }
                Menu("Vorlage löschen") {
                    ForEach(store.transactionTemplates) { template in
                        Button(template.name, role: .destructive) {
                            store.deleteTransactionTemplate(template)
                        }
                    }
                }
            }
        } label: {
            Label("Vorlagen", systemImage: "doc.on.doc")
        }
        .help("Buchung aus einer gespeicherten Vorlage beginnen")
    }

    private var quickEntryRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                Label("Neue Buchung", systemImage: "plus.rectangle.on.rectangle")
                    .font(.callout.weight(.semibold))
                    .fixedSize()
                DatePicker(
                    "Datum",
                    selection: $quickEntryDate,
                    displayedComponents: .date
                )
                .labelsHidden()
                .frame(width: 118)
                .accessibilityLabel("Schnellbuchung Datum")
                Picker("Konto", selection: $quickEntryAccountID) {
                    Text("Konto wählen").tag(UUID?.none)
                    ForEach(store.accounts.filter { !$0.isClosed }) { account in
                        Text(account.name).tag(UUID?.some(account.id))
                    }
                }
                .frame(width: 180)
                .accessibilityIdentifier("register.quickEntry.account")
                TextField("Empfänger", text: $quickEntryPayee)
                    .frame(width: 180)
                    .focused($quickEntryPayeeFocused)
                    .accessibilityIdentifier("register.quickEntry.payee")
                TextField("Verwendungszweck", text: $quickEntryPurpose)
                    .frame(width: 220)
                    .accessibilityIdentifier("register.quickEntry.purpose")
                Picker("Kategorie", selection: $quickEntryCategoryID) {
                    Text("Nicht kategorisiert").tag(UUID?.none)
                    ForEach(store.categoriesByPath.filter(\.isActive)) { category in
                        Text(store.categoryPath(category.id))
                            .tag(UUID?.some(category.id))
                    }
                }
                .frame(width: 225)
                .accessibilityIdentifier("register.quickEntry.category")
                Picker("Status", selection: $quickEntryStatus) {
                    ForEach(
                        TransactionStatus.allCases.filter { $0 != .reconciled },
                        id: \.self
                    ) {
                        Text($0.title).tag($0)
                    }
                }
                .frame(width: 125)
                TextField(
                    "Betrag",
                    text: $quickEntryAmount,
                    prompt: Text("-123,45")
                )
                .frame(width: 125)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .onSubmit { saveQuickEntry() }
                .help("Grundrechenarten +, −, ×, ÷ und Klammern sind erlaubt.")
                .accessibilityIdentifier("register.quickEntry.amount")
                Text(quickEntryCurrency)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Button("Speichern", systemImage: "checkmark") {
                    saveQuickEntry()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    quickEntryAccountID == nil
                        || quickEntryAmount.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                )
                .accessibilityIdentifier("register.quickEntry.save")
                Button("Leeren", systemImage: "xmark") {
                    resetQuickEntry()
                }
                .accessibilityIdentifier("register.quickEntry.clear")
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Schnellbuchung im Kontoblatt")
        .onExitCommand {
            resetQuickEntry()
            quickEntryPayeeFocused = false
        }
    }

    private var quickEntryCurrency: String {
        quickEntryAccountID.flatMap { id in
            store.accounts.first { $0.id == id }?.currency
        } ?? "—"
    }

    private func saveQuickEntry() {
        do {
            let resolved = try RegisterQuickEntryDraft(
                accountID: quickEntryAccountID,
                bookingDate: quickEntryDate,
                payee: quickEntryPayee,
                purpose: quickEntryPurpose,
                categoryID: quickEntryCategoryID,
                amountText: quickEntryAmount,
                status: quickEntryStatus
            ).resolved(accounts: store.accounts)
            if store.saveQuickEntry(resolved) {
                resetQuickEntry()
                quickEntryPayeeFocused = true
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func resetQuickEntry() {
        quickEntryPayee = ""
        quickEntryPurpose = ""
        quickEntryCategoryID = nil
        quickEntryAmount = ""
        quickEntryStatus = .booked
    }

    private func synchronizeQuickEntryAccount(preferSelected: Bool) {
        let openIDs = Set(store.accounts.filter { !$0.isClosed }.map(\.id))
        if preferSelected,
           let selectedAccountID = store.selectedAccountID,
           openIDs.contains(selectedAccountID) {
            quickEntryAccountID = selectedAccountID
            return
        }
        if let quickEntryAccountID, openIDs.contains(quickEntryAccountID) {
            return
        }
        quickEntryAccountID = store.selectedAccountID.flatMap { selected in
            openIDs.contains(selected) ? selected : nil
        } ?? store.accounts.first { !$0.isClosed }?.id
    }

    private var selectedTransaction: FinanceTransaction? {
        guard selection.count == 1, let id = selection.first else {
            return nil
        }
        return store.transactions.first { $0.id == id }
    }

    private func edit(_ transaction: FinanceTransaction?) {
        guard let transaction else { return }
        editorTemplate = nil
        editorTemplateUsageID = nil
        if let transferID = transaction.transferID {
            editingTransaction = nil
            editingTransferID = transferID
            showTransferEditor = true
        } else {
            editingTransferID = nil
            editingTransaction = transaction
            showEditor = true
        }
    }

    private var secondaryAccountID: UUID? {
        UUID(uuidString: secondaryAccountIDRaw)
    }

    private func ensureSecondaryAccount() {
        let available = store.accounts.filter {
            !$0.isClosed && $0.id != store.selectedAccountID
        }
        if let secondaryAccountID,
           available.contains(where: { $0.id == secondaryAccountID }) {
            return
        }
        secondaryAccountIDRaw = available.first?.id.uuidString ?? ""
    }

    private func prepareTemplateFromSelection() {
        guard selection.count == 1,
              let id = selection.first,
              let value = store.transactions.first(where: { $0.id == id })
        else {
            store.statusText = "Für eine Vorlage bitte genau eine Buchung markieren"
            return
        }
        guard value.transferID == nil else {
            store.errorMessage = "Eine Umbuchung kann nicht als einzelne Buchungsvorlage gespeichert werden."
            return
        }
        templateSource = value
        let suggested = value.payee.isEmpty ? value.purpose : value.payee
        templateName = suggested.isEmpty ? "Neue Buchungsvorlage" : suggested
        templateFields = Set(TransactionTemplateField.allCases)
        showTemplateNameEditor = true
    }

    private func prepareDuplicate(_ value: FinanceTransaction) {
        guard value.transferID == nil else {
            store.errorMessage = "Eine einzelne Umbuchungsseite kann nicht dupliziert werden."
            return
        }
        editingTransaction = nil
        editorTemplate = TransactionTemplate(
            name: "Duplikat",
            transaction: value
        )
        editorTemplateUsageID = nil
        showEditor = true
    }

    private var activeTransactionTemplates: [TransactionTemplate] {
        TransactionTemplateLibrary.orderedForUse(
            store.transactionTemplates,
            selectedAccountID: store.selectedAccountID
        )
    }

    private func transactionTemplateLabel(_ template: TransactionTemplate) -> String {
        var details: [String] = []
        if template.isPartial { details.append("Teilvorlage") }
        if template.effectiveUsageCount > 0 {
            details.append("\(template.effectiveUsageCount)× verwendet")
        }
        return details.isEmpty
            ? template.name
            : "\(template.name) · \(details.joined(separator: " · "))"
    }

    private func setTemplateField(
        _ field: TransactionTemplateField,
        enabled: Bool
    ) {
        if enabled {
            templateFields.insert(field)
            if [.splits, .vat, .foreignCurrency].contains(field) {
                templateFields.insert(.amount)
            }
        } else {
            templateFields.remove(field)
            if field == .amount {
                templateFields.remove(.splits)
                templateFields.remove(.foreignCurrency)
                templateFields.remove(.vat)
            }
        }
    }

    private func prepareScheduledTransaction(from value: FinanceTransaction) {
        do {
            scheduledDraft = try ScheduledTransaction.draft(from: value)
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func copyToPasteboard(_ value: FinanceTransaction) {
        let text = RegisterClipboard.tsv(
            transaction: value,
            categoryPath: store.transactionCategoryPath(value)
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        store.statusText = "Buchung in die Zwischenablage kopiert"
    }

    private func prepareDeletion() {
        guard !selection.isEmpty else {
            store.statusText = "Zum Löschen bitte mindestens eine Buchung markieren"
            return
        }
        showDeleteConfirmation = true
    }

    private var accountTabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(openAccountTabs) { account in
                    RegisterAccountTab(
                        account: account,
                        balanceMinor: store.balances[account.id] ?? 0,
                        isSelected: store.selectedAccountID == account.id,
                        select: {
                            store.selectedAccountID = account.id
                        },
                        close: {
                            closeAccountTab(account.id)
                        }
                    )
                }
                Menu {
                    let closedAccounts = store.accounts.filter {
                        !openAccountTabIDs.contains($0.id)
                    }
                    if closedAccounts.isEmpty {
                        Text("Alle Konten sind geöffnet")
                    } else {
                        ForEach(closedAccounts) { account in
                            Button(account.name) {
                                var ids = openAccountTabIDs
                                ids.append(account.id)
                                openAccountTabIDs = ids
                                store.selectedAccountID = account.id
                            }
                        }
                    }
                } label: {
                    Label("Kontoblatt öffnen", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .padding(6)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Weiteres Konto als Tab öffnen")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .scrollIndicators(.hidden)
        .frame(minHeight: 42)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func addSelectedAccountTabIfNeeded() {
        guard let selectedAccountID = store.selectedAccountID,
              store.accounts.contains(where: { $0.id == selectedAccountID }),
              !openAccountTabIDs.contains(selectedAccountID)
        else { return }
        openAccountTabIDs = openAccountTabIDs + [selectedAccountID]
    }

    private func synchronizeAccountTabs() {
        let valid = RegisterPreferencesCodec.decodeTabAccountIDs(
            openAccountTabsRaw,
            availableAccountIDs: Set(store.accounts.map(\.id))
        )
        if valid.isEmpty, let selectedAccountID = store.selectedAccountID {
            openAccountTabIDs = [selectedAccountID]
        } else if RegisterPreferencesCodec.encodeTabAccountIDs(valid)
                    != openAccountTabsRaw {
            openAccountTabIDs = valid
        }
    }

    private func closeAccountTab(_ accountID: UUID) {
        let previous = openAccountTabIDs
        guard let index = previous.firstIndex(of: accountID) else { return }
        let remaining = previous.filter { $0 != accountID }
        openAccountTabIDs = remaining
        guard store.selectedAccountID == accountID else { return }
        if remaining.isEmpty {
            store.selectedAccountID = nil
        } else {
            store.selectedAccountID = remaining[min(index, remaining.count - 1)]
        }
    }

    private var orderedVisibleColumns: [RegisterColumn] {
        RegisterColumnLayout.columns(
            visible: visibleColumns,
            amountMode: amountColumnMode
        )
    }

    private var registerSortState: RegisterSortState {
        RegisterSortState(
            column: RegisterColumn(rawValue: sortColumnRaw) ?? .date,
            ascending: sortAscending
        )
    }

    private func registerSortOrderBinding(
        runningBalances: [UUID: Int64],
        labels: [UUID: RegisterSortLabels]
    ) -> Binding<[RegisterTableComparator]> {
        Binding(
            get: {
                [
                    RegisterTableComparator(
                        column: registerSortState.column,
                        order: registerSortState.ascending ? .forward : .reverse,
                        runningBalances: runningBalances,
                        labels: labels
                    )
                ]
            },
            set: { order in
                let next = RegisterSortInteraction.state(
                    from: order,
                    fallback: registerSortState
                )
                sortColumnRaw = next.column.rawValue
                sortAscending = next.ascending
                selectedSavedViewID = nil
            }
        )
    }

    private func registerSortLabels(
        for transactions: [FinanceTransaction]
    ) -> [UUID: RegisterSortLabels] {
        Dictionary(uniqueKeysWithValues: transactions.map { value in
            (
                value.id,
                RegisterSortLabels(
                    account: store.accountName(value.accountID),
                    category: store.transactionCategoryPath(value),
                    tags: value.tagIDs.map(store.tagPath)
                        .sorted {
                            $0.localizedCaseInsensitiveCompare($1)
                                == .orderedAscending
                        }
                        .joined(separator: ", ")
                )
            )
        })
    }

    private func migrateBalanceColumnIfNeeded() {
        guard !visibleColumnsIncludesBalance else { return }
        visibleColumnsRaw = RegisterPreferencesCodec.addingBalanceColumn(
            to: visibleColumnsRaw
        )
        savedViewsRaw = RegisterPreferencesCodec.addingBalanceColumnToViews(
            savedViewsRaw
        )
        visibleColumnsIncludesBalance = true
    }

    private func migrateFlagColumnIfNeeded() {
        guard !visibleColumnsIncludesFlag else { return }
        visibleColumnsRaw = RegisterPreferencesCodec.addingFlagColumn(
            to: visibleColumnsRaw
        )
        savedViewsRaw = RegisterPreferencesCodec.addingFlagColumnToViews(
            savedViewsRaw
        )
        visibleColumnsIncludesFlag = true
    }

    private func accessibleRegisterCell(
        _ value: FinanceTransaction,
        column: RegisterColumn,
        runningBalances: [UUID: Int64]
    ) -> some View {
        registerCell(
            value,
            column: column,
            runningBalances: runningBalances
        )
        .accessibilityLabel(
            RegisterAccessibility.cellLabel(
                column: column,
                value: registerCellText(
                    value,
                    column: column,
                    runningBalances: runningBalances
                )
            )
        )
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
        case .flag:
            Image(systemName: value.flag == nil ? "flag" : "flag.fill")
                .foregroundStyle(value.flag.map(transactionFlagColor) ?? .secondary)
                .help(value.flag?.title ?? "Ohne Kennzeichen")
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
            let tags = value.tagIDs.map(store.tagPath).joined(separator: ", ")
            Text(tags.isEmpty ? "–" : tags)
                .lineLimit(rowMode == .twoLines ? 2 : 1)
                .truncationMode(.middle)
                .help(tags)
                .frame(height: rowMode.rowHeight, alignment: .leading)
        case .account:
            Text(store.accountName(value.accountID))
                .frame(height: rowMode.rowHeight, alignment: .leading)
        case .amount, .debit, .credit:
            let presentedAmount = RegisterAmountPresentation.minorUnits(
                for: column,
                amountMinor: value.amountMinor
            )
            Text(
                presentedAmount.map {
                    Money(minorUnits: $0, currency: value.currency).formatted
                } ?? ""
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
            .monospacedDigit()
            .foregroundStyle(
                column == .credit || (column == .amount && value.amountMinor > 0)
                    ? Color.green : .primary
            )
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
                ForEach(RegisterColumn.configurableCases) { column in
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

    private var f3FilterMenu: some View {
        Menu {
            Picker(
                "F3 übernimmt",
                selection: Binding(
                    get: {
                        RegisterF3Field(rawValue: f3FieldRaw) ?? .payee
                    },
                    set: { f3FieldRaw = $0.rawValue }
                )
            ) {
                ForEach(RegisterF3Field.allCases) { field in
                    Text(field.title).tag(field)
                }
            }
            Divider()
            Button("Auswahl als Filter übernehmen") {
                applyF3SelectionFilter()
            }
            .disabled(selection.count != 1)
        } label: {
            Label(
                "F3: \((RegisterF3Field(rawValue: f3FieldRaw) ?? .payee).title)",
                systemImage: "line.3.horizontal.decrease"
            )
        }
        .help("F3 filtert nach dem gewählten Feld der markierten Buchung")
    }

    private func registerOutputMenu(
        runningBalances: [UUID: Int64]
    ) -> some View {
        Menu {
            Button("Drucken …", systemImage: "printer") {
                do {
                    let data = try RegisterPDFExporter.data(
                        snapshot: registerPrintSnapshot(
                            runningBalances: runningBalances
                        )
                    )
                    try RegisterPrintService.printPDF(data)
                } catch {
                    store.errorMessage = error.localizedDescription
                }
            }
            Button("Als PDF exportieren …", systemImage: "doc.richtext") {
                do {
                    registerPDFDocument = RegisterPDFDocument(
                        data: try RegisterPDFExporter.data(
                            snapshot: registerPrintSnapshot(
                                runningBalances: runningBalances
                            )
                        )
                    )
                    showPDFExporter = true
                } catch {
                    store.errorMessage = error.localizedDescription
                }
            }
            Menu("Als CSV exportieren …", systemImage: "tablecells") {
                ForEach(RegisterCSVFormat.allCases) { format in
                    Button(format.title) {
                        exportCSV(
                            snapshot: registerPrintSnapshot(
                                runningBalances: runningBalances
                            ),
                            format: format
                        )
                    }
                }
            }
        } label: {
            Label("Ausgabe", systemImage: "printer")
        }
        .help("Druckt oder exportiert die aktuell sichtbaren Buchungen und Spalten")
    }

    private func exportCSV(
        snapshot: RegisterPrintSnapshot,
        format: RegisterCSVFormat
    ) {
        do {
            registerCSVDocument = RegisterCSVDocument(
                data: try RegisterCSVExporter.data(
                    snapshot: snapshot,
                    format: format
                )
            )
            showCSVExporter = true
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private var registerPDFFilename: String {
        let account = store.selectedAccount?.name ?? "Alle Konten"
        return "Kontoblatt \(account)"
            .replacingOccurrences(of: "/", with: "-")
    }

    private func registerPrintSnapshot(
        runningBalances: [UUID: Int64]
    ) -> RegisterPrintSnapshot {
        RegisterPrintSnapshot(
            title: store.selectedAccount.map {
                "Kontoblatt – \($0.name)"
            } ?? "Kontoblatt – Alle Konten",
            filterSummary: registerFilterSummary,
            generatedAt: .now,
            columns: orderedVisibleColumns,
            rows: visibleTransactions.map { transaction in
                orderedVisibleColumns.map { column in
                    registerCellText(
                        transaction,
                        column: column,
                        runningBalances: runningBalances
                    )
                }
            }
        )
    }

    private var registerFilterSummary: String {
        var parts: [String] = []
        if let statusFilter {
            parts.append("Status: \(statusFilter.title)")
        }
        switch categoryFilter {
        case .all:
            break
        case .uncategorized:
            parts.append("Kategorie: Nicht kategorisiert")
        case .category(let id):
            parts.append("Kategorie: \(store.categoryPath(id))")
        }
        if let tagFilterID {
            parts.append("Klasse/Tag: \(store.tagPath(tagFilterID))")
        }
        if periodFilter != .all {
            parts.append("Zeitraum: \(periodFilter.title)")
        }
        let search = store.searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !search.isEmpty {
            parts.append("Suche: \(search)")
        }
        return parts.isEmpty ? "Keine zusätzlichen Filter" : parts.joined(separator: " · ")
    }

    private func registerCellText(
        _ value: FinanceTransaction,
        column: RegisterColumn,
        runningBalances: [UUID: Int64]
    ) -> String {
        switch column {
        case .date:
            return value.bookingDate.formatted(date: .numeric, time: .omitted)
        case .valueDate:
            return (value.valueDate ?? value.bookingDate)
                .formatted(date: .numeric, time: .omitted)
        case .reference:
            return value.reference.isEmpty ? "–" : value.reference
        case .status:
            return value.status.title
        case .flag:
            return value.flag?.title ?? "Ohne Kennzeichen"
        case .payee:
            return value.payee
        case .purpose:
            return value.purpose
        case .category:
            return store.transactionCategoryPath(value)
        case .tags:
            let tags = value.tagIDs.map(store.tagPath).joined(separator: ", ")
            return tags.isEmpty ? "–" : tags
        case .account:
            return store.accountName(value.accountID)
        case .amount, .debit, .credit:
            guard let presentedAmount = RegisterAmountPresentation.minorUnits(
                for: column,
                amountMinor: value.amountMinor
            ) else { return "" }
            return Money(
                minorUnits: presentedAmount,
                currency: value.currency
            ).formatted
        case .balance:
            return Money(
                minorUnits: runningBalances[value.id] ?? 0,
                currency: value.currency
            ).formatted
        }
    }

    private func applyF3SelectionFilter() {
        guard selection.count == 1,
              let transactionID = selection.first,
              let transaction = store.transactions.first(where: {
                  $0.id == transactionID
              })
        else {
            store.statusText = "F3: Bitte genau eine Buchung markieren"
            return
        }
        let field = RegisterF3Field(rawValue: f3FieldRaw) ?? .payee
        guard let filter = field.selection(for: transaction) else {
            store.statusText = "F3: Das Feld „\(field.title)“ ist leer"
            return
        }
        switch filter {
        case .search(let text):
            store.searchText = text
        case .category(let category):
            categoryFilter = RegisterCategoryFilter(category)
        case .account(let accountID):
            store.selectedAccountID = accountID
        case .status(let status):
            statusFilter = status
        }
        store.statusText = "F3-Filter „\(field.title)“ übernommen"
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
            tagID: tagFilterID,
            periodRawValue: periodFilter.rawValue,
            customStart: customStart,
            customEnd: customEnd,
            rowModeRawValue: rowMode.rawValue,
            visibleColumns: visibleColumns,
            sortColumnRawValue: sortColumnRaw,
            sortAscending: sortAscending,
            amountColumnModeRawValue: amountColumnMode.rawValue,
            flagFilterRawValue: flagFilterRaw
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
        let savedFlag = view.flagFilterRawValue ?? "all"
        flagFilterRaw = savedFlag == "all" || savedFlag == "none"
            || TransactionFlag(rawValue: savedFlag) != nil ? savedFlag : "all"
        let savedCategoryFilter = RegisterCategoryFilter(view.categorySelection)
        if case .category(let categoryID) = savedCategoryFilter,
           !store.categories.contains(where: { $0.id == categoryID }) {
            categoryFilter = .all
        } else {
            categoryFilter = savedCategoryFilter
        }
        tagFilterID = view.tagID.flatMap { id in
            store.tags.contains(where: { $0.id == id }) ? id : nil
        }
        periodFilter = RegisterPeriodFilter(rawValue: view.periodRawValue) ?? .all
        customStart = view.customStart
        customEnd = view.customEnd
        rowMode = RegisterRowMode(rawValue: view.rowModeRawValue) ?? .single
        visibleColumns = view.visibleColumns
        amountColumnMode = RegisterAmountColumnMode(
            rawValue: view.amountColumnModeRawValue ?? ""
        ) ?? .amount
        sortColumnRaw = RegisterColumn(
            rawValue: view.sortColumnRawValue ?? ""
        )?.rawValue ?? RegisterColumn.date.rawValue
        sortAscending = view.sortAscending ?? true
        if amountColumnMode == .debitCredit, sortColumnRaw == RegisterColumn.amount.rawValue {
            sortColumnRaw = RegisterColumn.debit.rawValue
        } else if amountColumnMode == .amount,
                  sortColumnRaw == RegisterColumn.debit.rawValue
                    || sortColumnRaw == RegisterColumn.credit.rawValue {
            sortColumnRaw = RegisterColumn.amount.rawValue
        }
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
            parts.append(value.tagIDs.map(store.tagPath).joined(separator: ", "))
        }
        if value.vatMode != .none, let vatCodeID = value.vatCodeID {
            let code = store.vatCodes.first { $0.id == vatCodeID }
            let label = code.map {
                "MwSt. \($0.percentageText)"
            } ?? "MwSt."
            parts.append(
                "\(label): Netto "
                    + Money(
                        minorUnits: value.netMinor,
                        currency: value.currency
                    ).formatted
                    + " · Steuer "
                    + Money(
                        minorUnits: value.taxMinor,
                        currency: value.currency
                    ).formatted
            )
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

private struct RegisterPDFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    var data: Data

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

private struct RegisterCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var data: Data

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

enum RegisterCategoryFilter: Hashable {
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

enum RegisterPeriodFilter: String, CaseIterable, Identifiable {
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

enum RegisterSecondaryQuery {
    static func visible(
        transactions: [FinanceTransaction],
        accountID: UUID?,
        status: TransactionStatus?,
        category: RegisterCategoryFilter,
        period: RegisterPeriodFilter,
        customStart: Date,
        customEnd: Date,
        searchText: String,
        searchMatches: ((FinanceTransaction, RegisterSearchQuery) -> Bool)? = nil,
        categoryPath: (FinanceTransaction) -> String
    ) -> [FinanceTransaction] {
        guard let accountID else { return [] }
        let search = RegisterSearchQuery(searchText)
        return transactions.filter { transaction in
            guard transaction.accountID == accountID else { return false }
            let statusMatches = status == nil || transaction.status == status
            let categoryMatches: Bool
            switch category {
            case .all:
                categoryMatches = true
            case .uncategorized:
                categoryMatches = transaction.categoryID == nil
                    && transaction.transferID == nil
            case .category(let id):
                categoryMatches = transaction.categoryID == id
                    || transaction.splits.contains { $0.categoryID == id }
            }
            let matchesText: Bool
            if search.isEmpty {
                matchesText = true
            } else if let searchMatches {
                matchesText = searchMatches(transaction, search)
            } else {
                matchesText = RegisterSearchIndex.document(
                    transaction: transaction,
                    accountName: "",
                    categoryPath: categoryPath(transaction),
                    tagPaths: [],
                    runningBalanceMinor: nil
                ).matches(search)
            }
            return statusMatches && categoryMatches && matchesText
                && period.contains(
                    transaction.bookingDate,
                    customStart: customStart,
                    customEnd: customEnd
                )
        }
    }
}

private struct RegisterAccountTab: View {
    let account: FinanceAccount
    let balanceMinor: Int64
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void

    private var balanceText: String {
        Money(
            minorUnits: balanceMinor,
            currency: account.currency
        ).formatted
    }

    var body: some View {
        HStack(spacing: 5) {
            Button(action: select) {
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.stack")
                    Text(account.name)
                        .lineLimit(1)
                    Text(balanceText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kontoblatt \(account.name)")
            .accessibilityValue(
                "Saldo \(balanceText)\(isSelected ? ", ausgewählt" : "")"
            )
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.caption2.bold())
            }
            .buttonStyle(.plain)
            .help("Kontoblatt schließen")
            .accessibilityLabel("Kontoblatt \(account.name) schließen")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.16)
                : Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isSelected
                        ? Color.accentColor.opacity(0.55)
                        : Color.secondary.opacity(0.18)
                )
        )
        .accessibilityElement(children: .contain)
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

private struct RegisterAmountCell: View {
    let transaction: FinanceTransaction
    let column: RegisterColumn
    let rowMode: RegisterRowMode

    var body: some View {
        let presented = RegisterAmountPresentation.minorUnits(
            for: column,
            amountMinor: transaction.amountMinor
        )
        VStack(alignment: .trailing, spacing: 1) {
            Text(
                presented.map {
                    Money(
                        minorUnits: $0,
                        currency: transaction.currency
                    ).formatted
                } ?? ""
            )
            if rowMode == .twoLines,
               let original = transaction.originalAmountMinor,
               let presentedOriginal = RegisterAmountPresentation.minorUnits(
                for: column,
                amountMinor: original
               ) {
                Text(
                    "Orig. " + Money(
                        minorUnits: presentedOriginal,
                        currency: transaction.originalCurrency
                    ).formatted
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .monospacedDigit()
        .frame(
            maxWidth: .infinity,
            minHeight: rowMode.rowHeight,
            alignment: .trailing
        )
    }
}

private struct MoveTransactionView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    let transaction: FinanceTransaction
    let onCompletion: () -> Void

    @State private var destinationAccountID: UUID?

    private var destinationAccounts: [FinanceAccount] {
        store.accounts
            .filter {
                !$0.isClosed
                    && $0.id != transaction.accountID
                    && $0.currency == transaction.currency
            }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.name.localizedStandardCompare($1.name)
                        == .orderedAscending
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Buchung verschieben")
                .font(.title2.bold())
            Text(
                "Die Buchung wird vollständig einschließlich Kategorien, "
                    + "Klassen/Tags und Splitzeilen in ein anderes Konto verschoben."
            )
            .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Buchung", value: transaction.payee)
                    LabeledContent("Quellkonto", value: store.accountName(transaction.accountID))
                    LabeledContent("Betrag") {
                        Text(
                            Money(
                                minorUnits: transaction.amountMinor,
                                currency: transaction.currency
                            ).formatted
                        )
                        .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if destinationAccounts.isEmpty {
                ContentUnavailableView(
                    "Kein passendes Zielkonto",
                    systemImage: "tray.and.arrow.down",
                    description: Text(
                        "Benötigt wird ein weiteres offenes Konto in "
                            + transaction.currency + "."
                    )
                )
            } else {
                Picker("Zielkonto", selection: $destinationAccountID) {
                    ForEach(destinationAccounts) { account in
                        Text(account.name).tag(UUID?.some(account.id))
                    }
                }
                .accessibilityIdentifier("register.move.destinationAccount")

                Label(
                    "Abgeglichene Buchungen und einzelne Seiten einer Umbuchung "
                        + "können nicht verschoben werden.",
                    systemImage: "checkmark.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Verschieben") {
                    guard let destinationAccountID else { return }
                    if store.moveTransaction(
                        transaction,
                        toAccountID: destinationAccountID
                    ) {
                        onCompletion()
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(destinationAccountID == nil)
                .accessibilityIdentifier("register.move.confirm")
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            if destinationAccountID == nil {
                destinationAccountID = destinationAccounts.first?.id
            }
        }
    }
}

private struct BulkCategoryEditorView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Environment(\.dismiss) private var dismiss
    let transactionIDs: Set<UUID>
    let onCompletion: () -> Void

    @State private var categoryID: UUID?
    @State private var updateCategory = true
    @State private var updateTags = false
    @State private var updateFlag = false
    @State private var flag: TransactionFlag?
    @State private var selectedTagIDs = Set<UUID>()
    @State private var showConfirmation = false

    private var transactions: [FinanceTransaction] {
        store.transactions.filter { transactionIDs.contains($0.id) }
    }

    private var protectedTransactions: [FinanceTransaction] {
        transactions.filter {
            $0.status == .reconciled || $0.transferID != nil
                || (updateCategory && !$0.splits.isEmpty)
        }
    }

    private var totals: [(currency: String, amount: Int64)] {
        Dictionary(grouping: transactions, by: \.currency)
            .map { ($0.key, $0.value.reduce(Int64.zero) { $0 + $1.amountMinor }) }
            .sorted { $0.currency < $1.currency }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Kategorie und Klassen/Tags ändern")
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

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Kategorie ersetzen", isOn: $updateCategory)
                    Picker("Neue Kategorie", selection: $categoryID) {
                        Text("Nicht kategorisiert").tag(UUID?.none)
                        ForEach(store.categoriesByPath.filter(\.isActive)) {
                            Text(store.categoryPath($0.id)).tag(UUID?.some($0.id))
                        }
                    }
                    .disabled(!updateCategory)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Kennzeichen ersetzen", isOn: $updateFlag)
                    Picker("Neues Kennzeichen", selection: $flag) {
                        Text("Kennzeichen entfernen").tag(TransactionFlag?.none)
                        ForEach(TransactionFlag.allCases) { value in
                            Label(value.title, systemImage: "flag.fill")
                                .tag(TransactionFlag?.some(value))
                        }
                    }
                    .disabled(!updateFlag)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Klassen/Tags vollständig ersetzen", isOn: $updateTags)
                    if updateTags {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(store.tagsByPath.filter(\.isActive)) { tag in
                                    Toggle(
                                        store.tagPath(tag.id),
                                        isOn: Binding(
                                            get: { selectedTagIDs.contains(tag.id) },
                                            set: { selected in
                                                if selected { selectedTagIDs.insert(tag.id) }
                                                else { selectedTagIDs.remove(tag.id) }
                                            }
                                        )
                                    )
                                }
                                if store.tagsByPath.filter(\.isActive).isEmpty {
                                    Text("Noch keine aktiven Klassen/Tags vorhanden.")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        Text(
                            selectedTagIDs.isEmpty
                                ? "Die vorhandenen Klassen/Tags werden entfernt."
                                : "\(selectedTagIDs.count) Klassen/Tags werden gesetzt."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            if !protectedTransactions.isEmpty {
                Label(
                    "\(protectedTransactions.count) geschützte Buchungen in der Auswahl. "
                        + "Abgeglichene Buchungen und Umbuchungen sind geschützt; "
                        + "Splitbuchungen zusätzlich bei einer Kategorieänderung.",
                    systemImage: "lock.trianglebadge.exclamationmark"
                )
                .foregroundStyle(.orange)
            } else {
                Label(
                    "Beträge, Konten, Status und Splitzeilen bleiben unverändert.",
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
                .disabled(
                    transactions.isEmpty || !protectedTransactions.isEmpty
                        || (!updateCategory && !updateTags && !updateFlag)
                )
            }
        }
        .padding(24)
        .frame(width: 520)
        .confirmationDialog(
            "Organisation wirklich für \(transactions.count) Buchungen ändern?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Für \(transactions.count) Buchungen anwenden") {
                if store.bulkAssignOrganization(
                    transactionIDs: transactionIDs,
                    updateCategory: updateCategory,
                    categoryID: categoryID,
                    replacementTagIDs: updateTags ? selectedTagIDs : nil,
                    updateFlag: updateFlag,
                    flag: flag
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
    let template: TransactionTemplate?
    let templateUsageID: UUID?
    let startWithSplits: Bool

    @State private var accountID: UUID?
    @State private var date = Date()
    @State private var payee = ""
    @State private var payeeID: UUID?
    @State private var selectedMandateID: UUID?
    @State private var creditorID = ""
    @State private var mandateReference = ""
    @State private var purpose = ""
    @State private var categoryID: UUID?
    @State private var amount = ""
    @State private var useForeignCurrency = false
    @State private var originalAmount = ""
    @State private var originalCurrency = "USD"
    @State private var vatCodeID: UUID?
    @State private var vatMode: VATMode = .none
    @State private var manualTax = ""
    @State private var status: TransactionStatus = .booked
    @State private var flag: TransactionFlag?
    @State private var memo = ""
    @State private var selectedTagIDs = Set<UUID>()
    @State private var useSplits = false
    @State private var splitDrafts: [SplitDraft] = []
    @State private var initialized = false

    init(
        transaction: FinanceTransaction? = nil,
        template: TransactionTemplate? = nil,
        templateUsageID: UUID? = nil,
        startWithSplits: Bool = false
    ) {
        self.transaction = transaction
        self.template = template
        self.templateUsageID = templateUsageID
        self.startWithSplits = startWithSplits
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(transaction == nil ? "Neue Buchung" : "Buchung bearbeiten")
                .font(.title2.bold())
            if let template {
                Label("Vorlage: \(template.name)", systemImage: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Form {
                Picker("Konto", selection: $accountID) {
                    Text("Bitte wählen").tag(UUID?.none)
                    ForEach(store.accounts) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                DatePicker("Datum", selection: $date, displayedComponents: .date)
                TextField("Empfänger", text: $payee)
                    .onChange(of: payee) {
                        guard let payeeID,
                              let selected = store.payees.first(where: {
                                  $0.id == payeeID
                              })
                        else { return }
                        let entered = payee.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        if entered.compare(
                            selected.canonicalName,
                            options: [.caseInsensitive, .diacriticInsensitive]
                        ) != .orderedSame {
                            self.payeeID = nil
                        }
                    }
                Picker("SmartFill-Empfänger", selection: $payeeID) {
                    Text("Nur Freitext").tag(UUID?.none)
                    ForEach(store.payeeSmartFillSuggestions(for: payee)) {
                        Text(smartFillLabel($0)).tag(Optional($0.payee.id))
                    }
                }
                .help(
                    "Filtert Empfängernamen und Aliase; Präfixtreffer und häufig verwendete Akten stehen zuerst."
                )
                .onChange(of: payeeID) {
                    guard let selected = store.payees.first(where: { $0.id == payeeID }) else {
                        selectedMandateID = nil
                        return
                    }
                    payee = selected.canonicalName
                    categoryID = categoryID ?? selected.defaultCategoryID
                    accountID = accountID ?? selected.preferredAccountID
                    if selectedTagIDs.isEmpty {
                        selectedTagIDs = Set(selected.defaultTagIDs)
                    }
                    creditorID = selected.creditorID
                    selectedMandateID = nil
                    mandateReference = ""
                    let mandates = activeMandates(for: selected.id)
                    if mandates.count == 1, let mandate = mandates.first {
                        selectedMandateID = mandate.id
                        mandateReference = mandate.reference
                    }
                }
                TextField("Verwendungszweck", text: $purpose)
                Section("SEPA-Lastschrift") {
                    TextField("Gläubiger-ID", text: $creditorID)
                    Picker("Mandat", selection: $selectedMandateID) {
                        Text("Keine Mandatsakte").tag(UUID?.none)
                        ForEach(activeMandates(for: payeeID)) { mandate in
                            Text(mandate.reference).tag(Optional(mandate.id))
                        }
                    }
                    .disabled(payeeID == nil || activeMandates(for: payeeID).isEmpty)
                    .onChange(of: selectedMandateID) {
                        guard let selectedMandateID,
                              let mandate = store.sepaMandates.first(where: {
                                  $0.id == selectedMandateID
                              })
                        else { return }
                        mandateReference = mandate.reference
                    }
                    TextField("Mandatsreferenz", text: $mandateReference)
                    Text(
                        "Gläubiger-ID und Mandatsreferenz werden mit der Buchung gespeichert. "
                            + "Mandate verwaltest du unter Empfänger & Zahler."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Picker("Kategorie", selection: $categoryID) {
                    Text("Nicht kategorisiert").tag(UUID?.none)
                    ForEach(store.categoriesByPath.filter(\.isActive)) {
                        Text(store.categoryPath($0.id)).tag(UUID?.some($0.id))
                    }
                }
                .onChange(of: categoryID) {
                    if let value = categoryVATDefault(categoryID) {
                        vatCodeID = value.codeID
                        vatMode = .automatic
                    }
                }
                TextField("Betrag", text: $amount, prompt: Text("-123,45 oder 100 + 23,45"))
                    .help("Grundrechenarten +, −, ×, ÷ und Klammern sind erlaubt.")
                Text("Rechner: +, −, ×, ÷ und Klammern; gerechnet wird exakt mit Decimal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Section("Fremdwährung") {
                    Toggle("Originalbetrag in anderer Währung", isOn: $useForeignCurrency)
                    if useForeignCurrency {
                        HStack {
                            TextField(
                                "Originalbetrag",
                                text: $originalAmount,
                                prompt: Text("125,00")
                            )
                            TextField("ISO-Währung", text: $originalCurrency)
                                .textCase(.uppercase)
                                .frame(width: 110)
                        }
                        if let preview = foreignCurrencyPreview {
                            LabeledContent(
                                "Reproduzierbarer Kurs",
                                value: "1 \(preview.originalCurrency) = \(preview.rate.formatted) \(accountCurrency)"
                            )
                        }
                        Text(
                            "Der Kontobetrag bleibt in \(accountCurrency). Der Originalbetrag und der daraus mit acht Dezimalstellen abgeleitete Kurs werden gemeinsam gespeichert."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                if !useSplits {
                    Section("Mehrwertsteuer") {
                        Picker("MwSt.-Schlüssel", selection: $vatCodeID) {
                            Text("Keine MwSt.").tag(UUID?.none)
                            ForEach(activeVATCodes(including: vatCodeID)) { code in
                                Text("\(code.name) · \(code.percentageText)")
                                    .tag(Optional(code.id))
                            }
                        }
                        .onChange(of: vatCodeID) {
                            if vatCodeID == nil {
                                vatMode = .none
                                manualTax = ""
                            } else if vatMode == .none {
                                vatMode = .automatic
                            }
                        }
                        if vatCodeID != nil {
                            Picker("Berechnung", selection: $vatMode) {
                                Text(VATMode.automatic.title).tag(VATMode.automatic)
                                Text(VATMode.manual.title).tag(VATMode.manual)
                            }
                            .pickerStyle(.segmented)
                            if vatMode == .manual {
                                TextField(
                                    "Steuerbetrag",
                                    text: $manualTax,
                                    prompt: Text("-19,00")
                                )
                            }
                            if let breakdown = try? vatBreakdown(
                                grossText: amount,
                                vatCodeID: vatCodeID,
                                mode: vatMode,
                                manualTaxText: manualTax
                            ) {
                                LabeledContent(
                                    "Brutto",
                                    value: Money(
                                        minorUnits: breakdown.grossMinor,
                                        currency: accountCurrency
                                    ).formatted
                                )
                                LabeledContent(
                                    "Netto",
                                    value: Money(
                                        minorUnits: breakdown.netMinor,
                                        currency: accountCurrency
                                    ).formatted
                                )
                                LabeledContent(
                                    "Steuer",
                                    value: Money(
                                        minorUnits: breakdown.taxMinor,
                                        currency: accountCurrency
                                    ).formatted
                                )
                            }
                        }
                    }
                }
                Picker("Status", selection: $status) {
                    ForEach(TransactionStatus.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Kennzeichen", selection: $flag) {
                    Text("Ohne Kennzeichen").tag(TransactionFlag?.none)
                    ForEach(TransactionFlag.allCases) { value in
                        Label(value.title, systemImage: "flag.fill")
                            .tag(TransactionFlag?.some(value))
                    }
                }
                TextField("Notiz", text: $memo)
                SecureNoteView(text: memo, showsText: false)
                if let transaction {
                    Section("Anhänge") {
                        AttachmentManagerView(
                            entityType: .transaction,
                            entityID: transaction.id
                        )
                    }
                }
                if !store.tags.filter(\.isActive).isEmpty {
                    Section("Klassen & Tags") {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(store.tagsByPath.filter(\.isActive)) { tag in
                                    Toggle(
                                        store.tagPath(tag.id),
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
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Picker("Kategorie", selection: $draft.categoryID) {
                                        Text("Ohne Kategorie").tag(UUID?.none)
                                        ForEach(store.categoriesByPath.filter(\.isActive)) {
                                            Text(store.categoryPath($0.id)).tag(UUID?.some($0.id))
                                        }
                                    }
                                    .labelsHidden()
                                    .onChange(of: draft.categoryID) {
                                        if let value = categoryVATDefault(
                                            draft.categoryID
                                        ) {
                                            draft.vatCodeID = value.codeID
                                            draft.vatMode = .automatic
                                        }
                                    }
                                    TextField("Betrag", text: $draft.amount)
                                        .frame(width: 110)
                                    TextField("Notiz", text: $draft.memo)
                                    Menu("Tags") {
                                        ForEach(store.tagsByPath.filter(\.isActive)) { tag in
                                            Button {
                                                if draft.tagIDs.contains(tag.id) {
                                                    draft.tagIDs.remove(tag.id)
                                                } else {
                                                    draft.tagIDs.insert(tag.id)
                                                }
                                            } label: {
                                                Label(
                                                    store.tagPath(tag.id),
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
                                HStack {
                                    Picker("MwSt.", selection: $draft.vatCodeID) {
                                        Text("Keine MwSt.").tag(UUID?.none)
                                        ForEach(activeVATCodes(including: draft.vatCodeID)) { code in
                                            Text("\(code.name) · \(code.percentageText)")
                                                .tag(Optional(code.id))
                                        }
                                    }
                                    .frame(width: 190)
                                    .onChange(of: draft.vatCodeID) {
                                        if draft.vatCodeID == nil {
                                            draft.vatMode = .none
                                            draft.manualTax = ""
                                        } else if draft.vatMode == .none {
                                            draft.vatMode = .automatic
                                        }
                                    }
                                    if draft.vatCodeID != nil {
                                        Picker("Berechnung", selection: $draft.vatMode) {
                                            Text("Auto").tag(VATMode.automatic)
                                            Text("Manuell").tag(VATMode.manual)
                                        }
                                        .pickerStyle(.segmented)
                                        .frame(width: 170)
                                        if draft.vatMode == .manual {
                                            TextField("Steuerbetrag", text: $draft.manualTax)
                                                .frame(width: 120)
                                        }
                                        if let breakdown = try? vatBreakdown(
                                            grossText: draft.amount,
                                            vatCodeID: draft.vatCodeID,
                                            mode: draft.vatMode,
                                            manualTaxText: draft.manualTax
                                        ) {
                                            Text(
                                                "Netto \(Money(minorUnits: breakdown.netMinor, currency: accountCurrency).formatted) · "
                                                    + "Steuer \(Money(minorUnits: breakdown.taxMinor, currency: accountCurrency).formatted)"
                                            )
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
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
                Button("Speichern") {
                    save()
                }
                .disabled(accountID == nil || amount.isEmpty)
            }
        }
        .padding(24)
        .frame(width: useSplits ? 860 : 680)
        .onAppear {
            guard !initialized else { return }
            initialized = true
            let compatibleAccountID = template.flatMap { template in
                store.selectedAccountID.flatMap { selectedID in
                    store.accounts.first(where: {
                        $0.id == selectedID && $0.currency == template.currency
                    })?.id
                }
            }
            let source = transaction ?? template?.appliedTransaction(
                compatibleAccountID: compatibleAccountID
            )
            accountID = source?.accountID ?? store.selectedAccountID ?? store.accounts.first?.id
            date = transaction?.bookingDate ?? Date()
            payee = source?.payee ?? ""
            payeeID = source?.payeeID
            creditorID = source?.creditorID ?? ""
            mandateReference = source?.mandateReference ?? ""
            selectedMandateID = source.flatMap { transaction in
                store.sepaMandates.first {
                    $0.payeeID == transaction.payeeID
                        && $0.reference == transaction.mandateReference
                }?.id
            }
            purpose = source?.purpose ?? ""
            categoryID = source?.categoryID
            if transaction == nil,
               let template,
               !template.effectiveFields.contains(.amount) {
                amount = ""
            } else {
                amount = source.map {
                    Money(
                        minorUnits: $0.amountMinor,
                        currency: $0.currency
                    ).editingString
                } ?? ""
            }
            useForeignCurrency = source?.originalAmountMinor != nil
            originalAmount = source.flatMap { value in
                value.originalAmountMinor.map {
                    Money(
                        minorUnits: $0,
                        currency: value.originalCurrency
                    ).editingString
                }
            } ?? ""
            originalCurrency = source?.originalCurrency.isEmpty == false
                ? (source?.originalCurrency ?? "USD") : "USD"
            vatCodeID = source?.vatCodeID
            vatMode = source?.vatMode ?? .none
            manualTax = source?.vatMode == .manual
                ? Money(
                    minorUnits: source?.taxMinor ?? 0,
                    currency: source?.currency ?? accountCurrency
                ).editingString
                : ""
            status = source?.status ?? .booked
            flag = source?.flag
            memo = source?.memo ?? ""
            selectedTagIDs = Set(source?.tagIDs ?? [])
            useSplits = startWithSplits || !(source?.splits.isEmpty ?? true)
            splitDrafts = source?.splits.map {
                SplitDraft(
                    id: $0.id,
                    categoryID: $0.categoryID,
                    amount: Money(
                        minorUnits: $0.amountMinor,
                        currency: source?.currency ?? accountCurrency
                    ).editingString,
                    memo: $0.memo,
                    tagIDs: Set($0.tagIDs),
                    vatCodeID: $0.vatCodeID,
                    vatMode: $0.vatMode,
                    manualTax: $0.vatMode == .manual
                        ? Money(
                            minorUnits: $0.taxMinor,
                            currency: source?.currency ?? accountCurrency
                        ).editingString
                        : ""
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
        .onReceive(NotificationCenter.default.publisher(for: .saveCurrentEditor)) { _ in
            guard accountID != nil, !amount.isEmpty else { return }
            save()
        }
        .onReceive(NotificationCenter.default.publisher(for: .acceptCurrentEditor)) { _ in
            guard accountID != nil, !amount.isEmpty else { return }
            save()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cancelCurrentEditor)) { _ in
            dismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSplitEditor)) { _ in
            useSplits = true
        }
    }

    private var accountCurrency: String {
        accountID.flatMap { id in
            store.accounts.first(where: { $0.id == id })?.currency
        } ?? "EUR"
    }

    private var totalMinor: Int64 {
        (try? Money(evaluating: amount, currency: accountCurrency).minorUnits) ?? 0
    }

    private var splitSumMinor: Int64 {
        splitDrafts.reduce(Int64.zero) {
            $0 + ((try? Money(
                evaluating: $1.amount,
                currency: accountCurrency
            ).minorUnits) ?? 0)
        }
    }

    private var remainingSplitMinor: Int64 { totalMinor - splitSumMinor }
    private var remainingSplitText: String {
        Money(minorUnits: remainingSplitMinor, currency: accountCurrency).formatted
    }

    private var foreignCurrencyPreview: (
        originalCurrency: String,
        rate: ExchangeRate
    )? {
        guard useForeignCurrency,
              let booked = try? Money(evaluating: amount, currency: accountCurrency),
              let values = try? resolvedForeignCurrency(booked: booked)
        else { return nil }
        return (values.currency, values.rate)
    }

    private func assignRemainder() {
        guard let index = splitDrafts.indices.last else { return }
        let adjusted = ((try? Money(
            evaluating: splitDrafts[index].amount,
            currency: accountCurrency
        ).minorUnits) ?? 0)
            + remainingSplitMinor
        splitDrafts[index].amount = Money(
            minorUnits: adjusted,
            currency: accountCurrency
        ).editingString
    }

    private func save() {
        guard let accountID else {
            store.errorMessage = FinanceError.missingAccount.localizedDescription
            return
        }
        let normalizedCreditorID = SEPACreditorIDValidator.normalized(
            creditorID
        )
        guard normalizedCreditorID.isEmpty
                || SEPACreditorIDValidator.isValid(normalizedCreditorID)
        else {
            store.errorMessage = "Die SEPA-Gläubiger-ID ist ungültig."
            return
        }
        guard mandateReference.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).count <= 35 else {
            store.errorMessage = "Die Mandatsreferenz darf höchstens 35 Zeichen lang sein."
            return
        }
        if useSplits {
            saveSplit(accountID: accountID)
        } else {
            do {
                let booked = try Money(evaluating: amount, currency: accountCurrency)
                let normalizedOriginalAmount = useForeignCurrency
                    ? try Money(
                        evaluating: originalAmount,
                        currency: originalCurrency.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).uppercased()
                    ).editingString
                    : ""
                let vatValues = try resolvedSimpleVAT()
                if store.saveTransaction(
                    id: transaction?.id, accountID: accountID, date: date, payee: payee,
                    purpose: purpose, categoryID: categoryID,
                    amount: booked.editingString,
                    status: status, memo: memo,
                    flag: flag,
                    reference: transaction?.reference ?? "",
                    payeeID: payeeID, tagIDs: Array(selectedTagIDs),
                    creditorID: creditorID,
                    mandateReference: mandateReference,
                    vatCodeID: vatValues?.codeID,
                    vatMode: vatValues?.mode ?? .none,
                    netMinor: vatValues?.breakdown.netMinor ?? 0,
                    taxMinor: vatValues?.breakdown.taxMinor ?? 0,
                    originalAmount: normalizedOriginalAmount,
                    originalCurrency: useForeignCurrency ? originalCurrency : ""
                ) {
                    recordTemplateUseIfNeeded()
                    dismiss()
                }
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
    }

    private func smartFillLabel(
        _ suggestion: PayeeSmartFillSuggestion
    ) -> String {
        var details: [String] = []
        if let alias = suggestion.matchedAlias {
            details.append("Alias: \(alias)")
        }
        if suggestion.usageCount > 0 {
            details.append("\(suggestion.usageCount)× verwendet")
        }
        guard !details.isEmpty else { return suggestion.payee.canonicalName }
        return suggestion.payee.canonicalName
            + " — " + details.joined(separator: " · ")
    }

    private func activeMandates(for payeeID: UUID?) -> [FinanceSEPAMandate] {
        guard let payeeID else { return [] }
        return store.sepaMandates
            .filter { $0.payeeID == payeeID && $0.isActive }
            .sorted {
                $0.reference.localizedStandardCompare($1.reference)
                    == .orderedAscending
            }
    }

    private func resolvedSimpleVAT() throws -> (
        codeID: UUID,
        mode: VATMode,
        breakdown: VATBreakdown
    )? {
        guard vatMode != .none else { return nil }
        guard let vatCodeID else {
            throw FinanceError.invalidVAT("Bitte wähle einen MwSt.-Schlüssel.")
        }
        return (
            vatCodeID,
            vatMode,
            try vatBreakdown(
                grossText: amount,
                vatCodeID: vatCodeID,
                mode: vatMode,
                manualTaxText: manualTax
            )
        )
    }

    private func vatBreakdown(
        grossText: String,
        vatCodeID: UUID?,
        mode: VATMode,
        manualTaxText: String
    ) throws -> VATBreakdown {
        let gross = try Money(
            evaluating: grossText,
            currency: accountCurrency
        ).minorUnits
        switch mode {
        case .none:
            return VATBreakdown(
                grossMinor: gross,
                netMinor: gross,
                taxMinor: 0
            )
        case .automatic:
            guard let vatCodeID,
                  let code = store.vatCodes.first(where: { $0.id == vatCodeID })
            else {
                throw FinanceError.invalidVAT("Der MwSt.-Schlüssel fehlt.")
            }
            return try VATCalculator.automatic(
                grossMinor: gross,
                rateBasisPoints: code.rateBasisPoints
            )
        case .manual:
            guard vatCodeID != nil else {
                throw FinanceError.invalidVAT("Der MwSt.-Schlüssel fehlt.")
            }
            return try VATCalculator.manual(
                grossMinor: gross,
                taxMinor: try Money(
                    evaluating: manualTaxText,
                    currency: accountCurrency
                ).minorUnits
            )
        }
    }

    private func activeVATCodes(including id: UUID?) -> [VATCode] {
        store.vatCodes.filter { $0.isActive || $0.id == id }
    }

    private func categoryVATDefault(
        _ categoryID: UUID?
    ) -> (codeID: UUID, mode: VATMode)? {
        guard
            let categoryID,
            let defaultID = store.categories.first(where: {
                $0.id == categoryID
            })?.defaultVATCodeID
        else { return nil }
        return (defaultID, .automatic)
    }

    private func saveSplit(accountID: UUID) {
        do {
            let total = try Money(evaluating: amount, currency: accountCurrency)
            let foreignCurrency = try resolvedForeignCurrency(booked: total)
            let splits = try splitDrafts.enumerated().map { offset, draft in
                let breakdown = try vatBreakdown(
                    grossText: draft.amount,
                    vatCodeID: draft.vatCodeID,
                    mode: draft.vatMode,
                    manualTaxText: draft.manualTax
                )
                return FinanceSplit(
                    id: draft.id,
                    categoryID: draft.categoryID,
                    amountMinor: try Money(
                        evaluating: draft.amount,
                        currency: accountCurrency
                    ).minorUnits,
                    memo: draft.memo,
                    sortOrder: offset,
                    tagIDs: Array(draft.tagIDs),
                    vatCodeID: draft.vatCodeID,
                    vatMode: draft.vatMode,
                    netMinor: draft.vatMode == .none ? 0 : breakdown.netMinor,
                    taxMinor: draft.vatMode == .none ? 0 : breakdown.taxMinor
                )
            }
            let hasVAT = splits.contains { $0.vatMode != .none }
            let receipt = try VATCalculator.receipt(
                splits.map {
                    VATBreakdown(
                        grossMinor: $0.amountMinor,
                        netMinor: $0.vatMode == .none ? $0.amountMinor : $0.netMinor,
                        taxMinor: $0.taxMinor
                    )
                }
            )
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
                tagIDs: Array(selectedTagIDs),
                vatCodeID: nil,
                vatMode: .none,
                netMinor: hasVAT ? receipt.netMinor : 0,
                taxMinor: hasVAT ? receipt.taxMinor : 0,
                origin: transaction?.origin ?? .manual,
                externalProvider: transaction?.externalProvider ?? "",
                externalTransactionID: transaction?.externalTransactionID ?? "",
                counterpartyIBAN: transaction?.counterpartyIBAN ?? "",
                endToEndID: transaction?.endToEndID ?? "",
                mandateReference: mandateReference,
                duplicateFingerprint: transaction?.duplicateFingerprint ?? "",
                bankBalanceAfterMinor: transaction?.bankBalanceAfterMinor,
                counterpartyBIC: transaction?.counterpartyBIC ?? "",
                creditorID: SEPACreditorIDValidator.normalized(creditorID),
                bookingText: transaction?.bookingText ?? "",
                originalAmountMinor: foreignCurrency?.amountMinor,
                originalCurrency: foreignCurrency?.currency ?? "",
                exchangeRateScaled: foreignCurrency?.rate.scaledValue,
                flag: flag
            )
            if store.saveSplitTransaction(value) {
                recordTemplateUseIfNeeded()
                dismiss()
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func recordTemplateUseIfNeeded() {
        guard transaction == nil, let templateUsageID else { return }
        store.recordTransactionTemplateUse(id: templateUsageID)
    }

    private func resolvedForeignCurrency(
        booked: Money
    ) throws -> (amountMinor: Int64, currency: String, rate: ExchangeRate)? {
        guard useForeignCurrency else { return nil }
        let currency = originalCurrency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard currency.count == 3, currency != booked.currency else {
            throw FinanceError.invalidExchangeRate(
                "Bitte gib eine von der Kontowährung abweichende dreistellige ISO-Währung an."
            )
        }
        let input = try Money(evaluating: originalAmount, currency: currency)
        let signedAmount = booked.minorUnits < 0
            ? -abs(input.minorUnits) : abs(input.minorUnits)
        let rate = try ExchangeRate.derived(
            originalMinor: signedAmount,
            originalCurrency: currency,
            bookedMinor: booked.minorUnits,
            bookedCurrency: booked.currency
        )
        return (signedAmount, currency, rate)
    }
}

private struct SplitDraft: Identifiable {
    let id: UUID
    var categoryID: UUID?
    var amount: String
    var memo: String
    var tagIDs: Set<UUID>
    var vatCodeID: UUID?
    var vatMode: VATMode
    var manualTax: String

    init(
        id: UUID = UUID(),
        categoryID: UUID? = nil,
        amount: String = "",
        memo: String = "",
        tagIDs: Set<UUID> = [],
        vatCodeID: UUID? = nil,
        vatMode: VATMode = .none,
        manualTax: String = ""
    ) {
        self.id = id
        self.categoryID = categoryID
        self.amount = amount
        self.memo = memo
        self.tagIDs = tagIDs
        self.vatCodeID = vatCodeID
        self.vatMode = vatMode
        self.manualTax = manualTax
    }
}

private struct SecondaryRegisterPane: View {
    @EnvironmentObject private var store: FinanceAppStore
    @Binding var selectedAccountID: UUID?
    let excludedAccountID: UUID?
    let edit: (FinanceTransaction) -> Void
    @State private var selection = Set<UUID>()
    @State private var statusFilter: TransactionStatus?
    @State private var categoryFilter = RegisterCategoryFilter.all
    @State private var tagFilterID: UUID?
    @State private var periodFilter = RegisterPeriodFilter.all
    @State private var customStart = Calendar.current.date(
        byAdding: .month,
        value: -1,
        to: .now
    ) ?? .now
    @State private var customEnd = Date.now
    @AppStorage("registerRowMode")
    private var rowModeRaw = RegisterRowMode.single.rawValue
    @AppStorage("registerAmountColumnModeV1")
    private var amountColumnModeRaw = RegisterAmountColumnMode.amount.rawValue

    private var rowMode: RegisterRowMode {
        RegisterRowMode(rawValue: rowModeRaw) ?? .single
    }

    private var amountColumnMode: RegisterAmountColumnMode {
        RegisterAmountColumnMode(rawValue: amountColumnModeRaw) ?? .amount
    }

    private var availableAccounts: [FinanceAccount] {
        store.accounts.filter { !$0.isClosed && $0.id != excludedAccountID }
    }

    private var account: FinanceAccount? {
        selectedAccountID.flatMap { id in
            store.accounts.first { $0.id == id }
        }
    }

    private var visibleTransactions: [FinanceTransaction] {
        let runningBalances = store.runningBalances(
            accountID: selectedAccountID
        )
        let searchQuery = RegisterSearchQuery(store.searchText)
        let indexedMatches = store.registerSearchIndex
            .matchingTransactionIDs(searchQuery)
        let base = RegisterSecondaryQuery.visible(
            transactions: store.transactions,
            accountID: selectedAccountID,
            status: statusFilter,
            category: categoryFilter,
            period: periodFilter,
            customStart: customStart,
            customEnd: customEnd,
            searchText: store.searchText,
            searchMatches: { transaction, query in
                store.matchesRegisterSearch(
                    transaction,
                    query: query,
                    runningBalanceMinor: runningBalances[transaction.id],
                    indexedMatches: indexedMatches
                )
            }
        ) { transaction in
            store.transactionCategoryPath(transaction)
        }
        guard let tagFilterID else { return base }
        return base.filter {
            $0.tagIDs.contains(tagFilterID)
                || $0.splits.contains { $0.tagIDs.contains(tagFilterID) }
        }
    }

    var body: some View {
        let runningBalances = store.runningBalances(
            accountID: selectedAccountID
        )
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account?.name ?? "Zweites Kontoblatt")
                        .font(.headline)
                    if let account {
                        Text(
                            Money(
                                minorUnits: store.balances[account.id] ?? 0,
                                currency: account.currency
                            ).formatted
                        )
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Picker("Zweites Konto", selection: $selectedAccountID) {
                    ForEach(availableAccounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            }
            .padding(10)
            HStack(spacing: 8) {
                Picker("Status", selection: $statusFilter) {
                    Text("Alle Status").tag(TransactionStatus?.none)
                    ForEach(TransactionStatus.allCases, id: \.self) {
                        Text($0.title).tag(Optional($0))
                    }
                }
                .frame(maxWidth: 130)
                Picker("Kategorie", selection: $categoryFilter) {
                    Text("Alle Kategorien").tag(RegisterCategoryFilter.all)
                    Text("Nicht kategorisiert")
                        .tag(RegisterCategoryFilter.uncategorized)
                    Divider()
                    ForEach(store.categoriesByPath.filter(\.isActive)) {
                        Text(store.categoryPath($0.id))
                            .tag(RegisterCategoryFilter.category($0.id))
                    }
                }
                .frame(maxWidth: 170)
                Picker("Zeitraum", selection: $periodFilter) {
                    ForEach(RegisterPeriodFilter.allCases) {
                        Text($0.title).tag($0)
                    }
                }
                .frame(maxWidth: 130)
                Picker("Klasse/Tag", selection: $tagFilterID) {
                    Text("Alle Klassen/Tags").tag(UUID?.none)
                    ForEach(store.tagsByPath.filter(\.isActive)) { tag in
                        Text(store.tagPath(tag.id)).tag(UUID?.some(tag.id))
                    }
                }
                .frame(maxWidth: 150)
            }
            .controlSize(.mini)
            .padding(.horizontal, 8)
            .padding(.bottom, 7)
            Divider()
            Table(visibleTransactions, selection: $selection) {
                TableColumn("Datum") { transaction in
                    Text(
                        transaction.bookingDate,
                        format: .dateTime.day().month(.twoDigits).year()
                    )
                    .monospacedDigit()
                    .frame(height: rowMode.rowHeight)
                }
                .width(min: 78, ideal: 86)
                TableColumn("Empfänger / Zweck") { transaction in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(transaction.payee).lineLimit(1)
                        if rowMode == .twoLines {
                            Text(transaction.purpose)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(height: rowMode.rowHeight, alignment: .leading)
                    .help(
                        [transaction.payee, transaction.purpose]
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n")
                    )
                }
                .width(min: 120, ideal: 190)
                TableColumn("Kategorie") { transaction in
                    let path = store.transactionCategoryPath(transaction)
                    Text(path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                        .frame(height: rowMode.rowHeight, alignment: .leading)
                }
                .width(min: 100, ideal: 145)
                if amountColumnMode == .amount {
                    TableColumn("Betrag") { transaction in
                        RegisterAmountCell(
                            transaction: transaction,
                            column: .amount,
                            rowMode: rowMode
                        )
                    }
                    .width(min: 90, ideal: 120)
                } else {
                    TableColumn("Soll") { transaction in
                        RegisterAmountCell(
                            transaction: transaction,
                            column: .debit,
                            rowMode: rowMode
                        )
                    }
                    .width(min: 85, ideal: 105)
                    TableColumn("Haben") { transaction in
                        RegisterAmountCell(
                            transaction: transaction,
                            column: .credit,
                            rowMode: rowMode
                        )
                    }
                    .width(min: 85, ideal: 105)
                }
                TableColumn("Saldo") { transaction in
                    Text(
                        Money(
                            minorUnits: runningBalances[transaction.id] ?? 0,
                            currency: transaction.currency
                        ).formatted
                    )
                    .monospacedDigit()
                    .frame(
                        maxWidth: .infinity,
                        minHeight: rowMode.rowHeight,
                        alignment: .trailing
                    )
                }
                .width(min: 85, ideal: 105)
            }
            .accessibilityLabel("Zweites Kontoblatt Buchungstabelle")
            .accessibilityValue(
                RegisterAccessibility.tableValue(
                    visibleCount: visibleTransactions.count,
                    selectedCount: selection.count
                )
            )
            .accessibilityIdentifier("register.secondaryTransactionTable")
            .contextMenu(forSelectionType: UUID.self) { ids in
                if ids.count == 1,
                   let transaction = store.transactions.first(where: {
                       ids.contains($0.id)
                   }) {
                    Button("Bearbeiten") { edit(transaction) }
                }
            } primaryAction: { ids in
                if let transaction = store.transactions.first(where: {
                    ids.contains($0.id)
                }) {
                    edit(transaction)
                }
            }
            .overlay {
                if visibleTransactions.isEmpty {
                    ContentUnavailableView(
                        "Keine Buchungen",
                        systemImage: "rectangle.split.2x1",
                        description: Text(
                            account == nil
                                ? "Ein zweites Konto ist nicht verfügbar."
                                : "Die eigenen Filter liefern keine Treffer."
                        )
                    )
                }
            }
            Divider()
            HStack {
                Text("\(visibleTransactions.count) Buchungen")
                Spacer()
                Text(filteredTotalText)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
        }
        .onChange(of: availableAccounts.map(\.id)) {
            if let selectedAccountID,
               availableAccounts.contains(where: {
                   $0.id == selectedAccountID
               }) {
                return
            }
            selectedAccountID = availableAccounts.first?.id
        }
        .onChange(of: visibleTransactions.map(\.id)) {
            selection.formIntersection(Set(visibleTransactions.map(\.id)))
        }
    }

    private var filteredTotalText: String {
        let totals = Dictionary(grouping: visibleTransactions.filter {
            $0.transferID == nil && $0.status != .cancelled
        }) { $0.currency }
        .mapValues { values in
            values.reduce(Int64.zero) { $0 + $1.amountMinor }
        }
        return totals.keys.sorted().map { currency in
            Money(
                minorUnits: totals[currency] ?? 0,
                currency: currency
            ).formatted
        }.joined(separator: " · ")
    }
}

enum RegisterMiniReportDimension: String, CaseIterable, Identifiable {
    case payee
    case category
    case tag

    var id: Self { self }
    var title: String {
        switch self {
        case .payee: "Empfänger"
        case .category: "Kategorie"
        case .tag: "Klasse/Tag"
        }
    }
}

enum RegisterMiniReportSubject: Equatable {
    case payee(String)
    case category(UUID)
    case tag(UUID)
    case unavailable
}

struct RegisterMiniReportEntry: Identifiable, Equatable {
    let transaction: FinanceTransaction
    let contributionMinor: Int64
    var id: UUID { transaction.id }
}

struct RegisterMiniReportCurrencyTotal: Identifiable, Equatable {
    let currency: String
    let incomeMinor: Int64
    let expenseMinor: Int64
    let netMinor: Int64
    let transactionCount: Int
    var id: String { currency }
}

struct RegisterMiniReportSnapshot: Equatable {
    let dimension: RegisterMiniReportDimension
    let subject: RegisterMiniReportSubject
    let entries: [RegisterMiniReportEntry]
    let totals: [RegisterMiniReportCurrencyTotal]

    static func make(
        selected: FinanceTransaction?,
        dimension: RegisterMiniReportDimension,
        transactions: [FinanceTransaction]
    ) -> Self {
        guard let selected else {
            return Self(
                dimension: dimension,
                subject: .unavailable,
                entries: [],
                totals: []
            )
        }
        let subject: RegisterMiniReportSubject
        switch dimension {
        case .payee:
            let payee = selected.payee.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            subject = payee.isEmpty ? .unavailable : .payee(payee)
        case .category:
            let categoryID = selected.categoryID
                ?? selected.splits.sorted { $0.sortOrder < $1.sortOrder }
                    .compactMap(\.categoryID).first
            subject = categoryID.map(RegisterMiniReportSubject.category)
                ?? .unavailable
        case .tag:
            let tagID = (selected.tagIDs
                + selected.splits.flatMap(\.tagIDs))
                .sorted { $0.uuidString < $1.uuidString }
                .first
            subject = tagID.map(RegisterMiniReportSubject.tag)
                ?? .unavailable
        }
        let entries: [RegisterMiniReportEntry] = transactions.compactMap {
            (transaction: FinanceTransaction) -> RegisterMiniReportEntry? in
            guard transaction.status != .cancelled else { return nil }
            let contribution: Int64?
            switch subject {
            case .payee(let payee):
                contribution = normalized(transaction.payee)
                    == normalized(payee) ? transaction.amountMinor : nil
            case .category(let categoryID):
                if transaction.categoryID == categoryID {
                    contribution = transaction.amountMinor
                } else {
                    let splitAmount = transaction.splits
                        .filter { $0.categoryID == categoryID }
                        .reduce(Int64.zero) { $0 + $1.amountMinor }
                    contribution = splitAmount == 0 ? nil : splitAmount
                }
            case .tag(let tagID):
                if transaction.tagIDs.contains(tagID) {
                    contribution = transaction.amountMinor
                } else {
                    let splitAmount = transaction.splits
                        .filter { $0.tagIDs.contains(tagID) }
                        .reduce(Int64.zero) { $0 + $1.amountMinor }
                    contribution = splitAmount == 0 ? nil : splitAmount
                }
            case .unavailable:
                contribution = nil
            }
            guard let contribution else { return nil }
            return RegisterMiniReportEntry(
                transaction: transaction,
                contributionMinor: contribution
            )
        }.sorted {
            if $0.transaction.bookingDate != $1.transaction.bookingDate {
                return $0.transaction.bookingDate > $1.transaction.bookingDate
            }
            return $0.id.uuidString > $1.id.uuidString
        }
        let entriesByCurrency: [String: [RegisterMiniReportEntry]] =
            Dictionary(grouping: entries) { entry in
                entry.transaction.currency
            }
        let totals: [RegisterMiniReportCurrencyTotal] =
            entriesByCurrency.map { currency, values in
            let income = values.reduce(Int64.zero) {
                $0 + max($1.contributionMinor, 0)
            }
            let expense = values.reduce(Int64.zero) {
                $0 + min($1.contributionMinor, 0)
            }
            return RegisterMiniReportCurrencyTotal(
                currency: currency,
                incomeMinor: income,
                expenseMinor: expense,
                netMinor: income + expense,
                transactionCount: values.count
            )
        }.sorted { $0.currency < $1.currency }
        return Self(
            dimension: dimension,
            subject: subject,
            entries: entries,
            totals: totals
        )
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "de_DE")
            )
    }
}

private struct RegisterMiniReportPanel: View {
    @EnvironmentObject private var store: FinanceAppStore
    let selectedTransaction: FinanceTransaction?
    @Binding var dimension: RegisterMiniReportDimension

    private var snapshot: RegisterMiniReportSnapshot {
        RegisterMiniReportSnapshot.make(
            selected: selectedTransaction,
            dimension: dimension,
            transactions: store.transactions
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Minireport", systemImage: "chart.bar.doc.horizontal")
                    .font(.headline)
                Spacer()
            }
            Picker("Auswertung", selection: $dimension) {
                ForEach(RegisterMiniReportDimension.allCases) {
                    Text($0.title).tag($0)
                }
            }
            .pickerStyle(.segmented)
            if snapshot.subject == .unavailable {
                ContentUnavailableView(
                    "Eine Buchung markieren",
                    systemImage: "cursorarrow.click.2",
                    description: Text(
                        selectedTransaction == nil
                            ? "Der Minireport folgt genau einer markierten Buchung."
                            : "Die markierte Buchung besitzt keinen Wert für \(dimension.title)."
                    )
                )
            } else {
                Text(subjectTitle)
                    .font(.title3.bold())
                    .lineLimit(2)
                    .help(subjectTitle)
                ForEach(snapshot.totals) { total in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("\(total.transactionCount) Buchungen")
                            Spacer()
                            Text(total.currency).fontWeight(.semibold)
                        }
                        miniTotal("Einnahmen", total.incomeMinor, total.currency)
                        miniTotal("Ausgaben", total.expenseMinor, total.currency)
                        Divider()
                        miniTotal("Saldo", total.netMinor, total.currency)
                            .fontWeight(.semibold)
                    }
                    .padding(9)
                    .background(
                        .quaternary.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                Text("Letzte Buchungen")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(snapshot.entries.prefix(8)) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(
                                        entry.transaction.bookingDate,
                                        format: .dateTime.day().month().year()
                                    )
                                    Spacer()
                                    Text(
                                        Money(
                                            minorUnits: entry.contributionMinor,
                                            currency: entry.transaction.currency
                                        ).formatted
                                    )
                                    .monospacedDigit()
                                }
                                Text(entry.transaction.payee)
                                    .lineLimit(1)
                                Text(entry.transaction.purpose)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 7)
                            Divider()
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var subjectTitle: String {
        switch snapshot.subject {
        case .payee(let name): name
        case .category(let id): store.categoryPath(id)
        case .tag(let id): store.tagPath(id)
        case .unavailable: "Kein Wert"
        }
    }

    private func miniTotal(
        _ title: String,
        _ amountMinor: Int64,
        _ currency: String
    ) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(
                Money(
                    minorUnits: amountMinor,
                    currency: currency
                ).formatted
            )
            .monospacedDigit()
        }
    }
}

private struct CombinedRegisterChartPanel: View {
    let snapshot: CombinedRegisterChartSnapshot
    let accessibilityIdentifier: String
    @Binding var transactionSelection: Set<UUID>

    var body: some View {
        Group {
            if snapshot.series.isEmpty {
                HStack {
                    Label(
                        "Keine Diagrammdaten",
                        systemImage: "chart.xyaxis.line"
                    )
                    Spacer()
                    Text("Die aktuelle Sicht enthält keine wirksamen Bewegungen.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(height: 44)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        ForEach(snapshot.series) { series in
                            CombinedRegisterCurrencyChart(
                                mode: snapshot.mode,
                                series: series,
                                showsPoints: snapshot.pointCount < 30,
                                transactionSelection: $transactionSelection
                            )
                            .frame(minWidth: 330, idealWidth: 440)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct CombinedRegisterCurrencyChart: View {
    let mode: CombinedRegisterChartMode
    let series: CombinedRegisterChartSeries
    let showsPoints: Bool
    @Binding var transactionSelection: Set<UUID>
    @State private var hoveredPoint: CombinedRegisterChartPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(mode.title, systemImage: "chart.xyaxis.line")
                    .font(.caption.bold())
                Spacer()
                Text(series.currency)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            Chart(series.points) { point in
                LineMark(
                    x: .value("Tag", point.date),
                    y: .value("Wert", chartValue(point.valueMinor))
                )
                .interpolationMethod(.linear)
                .foregroundStyle(.blue)
                if showsPoints {
                    PointMark(
                        x: .value("Tag", point.date),
                        y: .value("Wert", chartValue(point.valueMinor))
                    )
                    .foregroundStyle(.blue)
                }
                if hoveredPoint?.id == point.id {
                    RuleMark(x: .value("Gewählter Tag", point.date))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.day().month())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let anchor = proxy.plotFrame else { return }
                                let frame = geometry[anchor]
                                let plotX = location.x - frame.origin.x
                                guard plotX >= 0, plotX <= frame.width,
                                      let date: Date = proxy.value(atX: plotX),
                                      let nearest = nearestPoint(to: date)
                                else { return }
                                hoveredPoint = nearest
                                transactionSelection = [nearest.lastTransactionID]
                            case .ended:
                                hoveredPoint = nil
                            }
                        }
                }
            }
            .frame(height: 112)
            .accessibilityLabel("\(mode.title) \(series.currency)")
            .accessibilityValue(
                "\(series.points.count) Tageswerte; letzter Wert "
                    + lastValueText
            )
            if let hoveredPoint {
                Text(
                    "\(hoveredPoint.date.formatted(.dateTime.day().month().year())) · "
                        + Money(
                            minorUnits: hoveredPoint.valueMinor,
                            currency: series.currency
                        ).formatted
                        + " · letzte Buchung des Tages ausgewählt"
                )
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            } else {
                Text(
                    mode == .balance
                        ? "Echter Kontostand; über einem Tag verweilen wählt dessen letzte Buchung."
                        : "Kein Kontostand: kumulierte wirksame Bewegungen der Filtermenge."
                )
                .font(.caption2)
                .foregroundStyle(
                    mode == .balance
                        ? Color(nsColor: .secondaryLabelColor)
                        : Color.orange
                )
            }
        }
    }

    private var lastValueText: String {
        guard let point = series.points.last else { return "—" }
        return Money(
            minorUnits: point.valueMinor,
            currency: series.currency
        ).formatted
    }

    private func chartValue(_ minorUnits: Int64) -> Double {
        Double(minorUnits) / Double(Money.minorUnitFactor(for: series.currency))
    }

    private func nearestPoint(to date: Date) -> CombinedRegisterChartPoint? {
        series.points.min {
            abs($0.date.timeIntervalSince(date))
                < abs($1.date.timeIntervalSince(date))
        }
    }
}

private struct SecondaryCombinedRegisterPane: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var selection = Set<UUID>()
    @State private var statusFilter: TransactionStatus?
    @State private var categoryFilter = RegisterCategoryFilter.all
    @State private var tagFilterID: UUID?
    @State private var periodFilter = RegisterPeriodFilter.all
    @State private var customStart = Calendar.current.date(
        byAdding: .month,
        value: -1,
        to: .now
    ) ?? .now
    @State private var customEnd = Date.now
    @AppStorage("combinedRegisterSecondaryAccountIDsV1")
    private var includedAccountIDsRaw = ""
    @AppStorage("combinedRegisterSecondaryForecastV1")
    private var includeForecast = true
    @AppStorage("registerRowMode")
    private var rowModeRaw = RegisterRowMode.single.rawValue
    @AppStorage("registerAmountColumnModeV1")
    private var amountColumnModeRaw = RegisterAmountColumnMode.amount.rawValue

    private var rowMode: RegisterRowMode {
        RegisterRowMode(rawValue: rowModeRaw) ?? .single
    }

    private var amountColumnMode: RegisterAmountColumnMode {
        RegisterAmountColumnMode(rawValue: amountColumnModeRaw) ?? .amount
    }

    private var includedAccountIDs: Set<UUID> {
        get {
            Set(includedAccountIDsRaw.split(separator: ",").compactMap {
                UUID(uuidString: String($0))
            }).intersection(Set(store.accounts.map(\.id)))
        }
        nonmutating set {
            includedAccountIDsRaw = newValue.sorted {
                $0.uuidString < $1.uuidString
            }.map(\.uuidString).joined(separator: ",")
        }
    }

    private var result: CombinedRegisterQueryResult {
        let forecast = includeForecast
            ? store.forecastOccurrences(days: 365) : []
        let runningBalances = CombinedRegisterQuery.runningBalances(
            accounts: store.accounts,
            transactions: store.transactions + forecast
        )
        let searchQuery = RegisterSearchQuery(store.searchText)
        let indexedMatches = store.registerSearchIndex
            .matchingTransactionIDs(searchQuery)
        return CombinedRegisterQuery.evaluate(
            transactions: store.transactions,
            forecastTransactions: forecast,
            allAccountIDs: Set(store.accounts.filter {
                !$0.isClosed
            }.map(\.id)),
            includedAccountIDs: includedAccountIDs,
            status: statusFilter,
            category: categoryFilter,
            tagID: tagFilterID,
            period: periodFilter,
            customStart: customStart,
            customEnd: customEnd,
            searchText: store.searchText,
            includeForecast: includeForecast,
            searchMatches: { transaction, query in
                store.matchesRegisterSearch(
                    transaction,
                    query: query,
                    runningBalanceMinor: runningBalances[transaction.id],
                    indexedMatches: indexedMatches
                )
            }
        ) { transaction in
            store.transactionCategoryPath(transaction)
        }
    }

    private var chartSnapshot: CombinedRegisterChartSnapshot {
        CombinedRegisterChartEngine.make(
            accounts: store.accounts.filter {
                !$0.isClosed
                    && (includedAccountIDs.isEmpty
                        || includedAccountIDs.contains($0.id))
            },
            rows: result.rows,
            isFiltered: result.isFiltered
        )
    }

    var body: some View {
        let balances = CombinedRegisterQuery.runningBalances(
            accounts: store.accounts,
            transactions: store.transactions
                + (includeForecast ? store.forecastOccurrences(days: 365) : [])
        )
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sammelansicht B").font(.headline)
                    Text(result.isFiltered ? "Gefilterte Summe" : "Alle Konten")
                        .font(.caption)
                        .foregroundStyle(result.isFiltered ? .orange : .secondary)
                }
                Spacer()
                Text(totalsText)
                    .font(.headline.monospacedDigit())
            }
            .padding(10)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    accountMenu
                    Picker("Status", selection: $statusFilter) {
                        Text("Alle Status").tag(TransactionStatus?.none)
                        ForEach(TransactionStatus.allCases, id: \.self) {
                            Text($0.title).tag(Optional($0))
                        }
                    }
                    .frame(width: 125)
                    Picker("Kategorie", selection: $categoryFilter) {
                        Text("Alle Kategorien").tag(RegisterCategoryFilter.all)
                        Text("Nicht kategorisiert")
                            .tag(RegisterCategoryFilter.uncategorized)
                        Divider()
                        ForEach(store.categoriesByPath.filter(\.isActive)) {
                            Text(store.categoryPath($0.id))
                                .tag(RegisterCategoryFilter.category($0.id))
                        }
                    }
                    .frame(width: 160)
                    Picker("Klasse/Tag", selection: $tagFilterID) {
                        Text("Alle Klassen/Tags").tag(UUID?.none)
                        ForEach(store.tagsByPath.filter(\.isActive)) { tag in
                            Text(store.tagPath(tag.id)).tag(UUID?.some(tag.id))
                        }
                    }
                    .frame(width: 150)
                    Picker("Zeitraum", selection: $periodFilter) {
                        ForEach(RegisterPeriodFilter.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .frame(width: 135)
                    Toggle("Zukunft", isOn: $includeForecast)
                        .toggleStyle(.checkbox)
                    Button("Bericht") {
                        NotificationCenter.default.post(
                            name: .openTransactionReport,
                            object: TransactionReportQuery(
                                statuses: Set(TransactionStatus.allCases),
                                includeHiddenAccounts: true,
                                includeAccountsExcludedFromReports: true,
                                includeTransfers: true,
                                expandSplits: true,
                                grouping: .account,
                                sort: .dateAscending,
                                transactionIDs: Set(result.rows.map(\.id)),
                                includeForecast: includeForecast
                            )
                        )
                    }
                    .disabled(result.rows.isEmpty)
                }
                .controlSize(.mini)
                .padding(.horizontal, 8)
                .padding(.bottom, 7)
            }
            .scrollIndicators(.hidden)
            Divider()
            CombinedRegisterChartPanel(
                snapshot: chartSnapshot,
                accessibilityIdentifier: "combinedRegister.secondaryBalanceChart",
                transactionSelection: $selection
            )
            Divider()
            Table(result.rows, selection: $selection) {
                TableColumn("Datum") { transaction in
                    Text(
                        transaction.bookingDate,
                        format: .dateTime.day().month(.twoDigits).year()
                    )
                    .foregroundStyle(transaction.bookingDate > Date() ? .blue : .primary)
                    .frame(height: rowMode.rowHeight)
                }
                .width(min: 78, ideal: 88)
                TableColumn("Konto") { transaction in
                    Text(store.accountName(transaction.accountID))
                        .lineLimit(1)
                        .frame(height: rowMode.rowHeight, alignment: .leading)
                }
                .width(min: 95, ideal: 125)
                TableColumn("Empfänger / Zweck") { transaction in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(transaction.payee).lineLimit(1)
                        if rowMode == .twoLines {
                            Text(transaction.purpose)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(height: rowMode.rowHeight, alignment: .leading)
                }
                .width(min: 115, ideal: 170)
                TableColumn("Kategorie") { transaction in
                    let path = store.transactionCategoryPath(transaction)
                    Text(path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                        .frame(height: rowMode.rowHeight, alignment: .leading)
                }
                .width(min: 100, ideal: 140)
                if amountColumnMode == .amount {
                    TableColumn("Betrag") { transaction in
                        RegisterAmountCell(
                            transaction: transaction,
                            column: .amount,
                            rowMode: rowMode
                        )
                    }
                    .width(min: 90, ideal: 120)
                } else {
                    TableColumn("Soll") { transaction in
                        RegisterAmountCell(
                            transaction: transaction,
                            column: .debit,
                            rowMode: rowMode
                        )
                    }
                    .width(min: 85, ideal: 105)
                    TableColumn("Haben") { transaction in
                        RegisterAmountCell(
                            transaction: transaction,
                            column: .credit,
                            rowMode: rowMode
                        )
                    }
                    .width(min: 85, ideal: 105)
                }
                TableColumn("Saldo") { transaction in
                    Text(
                        Money(
                            minorUnits: balances[transaction.id] ?? 0,
                            currency: transaction.currency
                        ).formatted
                    )
                    .monospacedDigit()
                    .frame(
                        maxWidth: .infinity,
                        minHeight: rowMode.rowHeight,
                        alignment: .trailing
                    )
                }
                .width(min: 85, ideal: 105)
            }
            .overlay {
                if result.rows.isEmpty {
                    ContentUnavailableView(
                        "Keine Buchungen",
                        systemImage: "rectangle.split.2x1",
                        description: Text("Die Filter der zweiten Ansicht liefern keine Treffer.")
                    )
                }
            }
            Divider()
            HStack {
                if result.isFiltered {
                    Label(
                        "Kein Kontostand",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
                Spacer()
                Text("\(result.rows.count) Buchungen")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
        }
        .onChange(of: result.rows.map(\.id)) {
            selection.formIntersection(Set(result.rows.map(\.id)))
        }
    }

    private var totalsText: String {
        let text = result.totalsByCurrency.keys.sorted().map { currency in
            Money(
                minorUnits: result.totalsByCurrency[currency] ?? 0,
                currency: currency
            ).formatted
        }.joined(separator: " · ")
        return text.isEmpty ? "—" : text
    }

    private var accountMenu: some View {
        Menu {
            Button("Alle offenen Konten") { includedAccountIDs = [] }
            Divider()
            ForEach(store.accounts.filter { !$0.isClosed }) { account in
                Toggle(
                    account.name,
                    isOn: Binding(
                        get: {
                            includedAccountIDs.isEmpty
                                || includedAccountIDs.contains(account.id)
                        },
                        set: { selected in
                            var ids = includedAccountIDs.isEmpty
                                ? Set(store.accounts.filter {
                                    !$0.isClosed
                                }.map(\.id))
                                : includedAccountIDs
                            if selected { ids.insert(account.id) }
                            else { ids.remove(account.id) }
                            includedAccountIDs = ids
                        }
                    )
                )
            }
        } label: {
            Label(
                includedAccountIDs.isEmpty
                    ? "Alle Konten" : "\(includedAccountIDs.count) Konten",
                systemImage: "building.columns"
            )
        }
    }
}

struct CombinedRegisterQueryResult: Equatable {
    let rows: [FinanceTransaction]
    let isFiltered: Bool
    let totalsByCurrency: [String: Int64]
}

enum CombinedRegisterQuery {
    static func evaluate(
        transactions: [FinanceTransaction],
        forecastTransactions: [FinanceTransaction],
        allAccountIDs: Set<UUID>,
        includedAccountIDs: Set<UUID>,
        status: TransactionStatus?,
        category: RegisterCategoryFilter,
        tagID: UUID? = nil,
        period: RegisterPeriodFilter,
        customStart: Date,
        customEnd: Date,
        searchText: String,
        includeForecast: Bool,
        searchMatches: ((FinanceTransaction, RegisterSearchQuery) -> Bool)? = nil,
        categoryPath: (FinanceTransaction) -> String
    ) -> CombinedRegisterQueryResult {
        let effectiveAccounts = includedAccountIDs.isEmpty
            ? allAccountIDs : includedAccountIDs
        let combined = transactions + (includeForecast ? forecastTransactions : [])
        let search = RegisterSearchQuery(searchText)
        let rows = combined.filter { transaction in
            guard effectiveAccounts.contains(transaction.accountID) else {
                return false
            }
            let statusMatches = status == nil || transaction.status == status
            let categoryMatches: Bool
            switch category {
            case .all:
                categoryMatches = true
            case .uncategorized:
                categoryMatches = transaction.categoryID == nil
                    && transaction.transferID == nil
            case .category(let id):
                categoryMatches = transaction.categoryID == id
                    || transaction.splits.contains { $0.categoryID == id }
            }
            let tagMatches: Bool
            if let tagID {
                tagMatches = transaction.tagIDs.contains(tagID)
                    || transaction.splits.contains { $0.tagIDs.contains(tagID) }
            } else {
                tagMatches = true
            }
            let matchesText: Bool
            if search.isEmpty {
                matchesText = true
            } else if let searchMatches {
                matchesText = searchMatches(transaction, search)
            } else {
                matchesText = RegisterSearchIndex.document(
                    transaction: transaction,
                    accountName: "",
                    categoryPath: categoryPath(transaction),
                    tagPaths: [],
                    runningBalanceMinor: nil
                ).matches(search)
            }
            return statusMatches && categoryMatches && tagMatches && matchesText
                && period.contains(
                    transaction.bookingDate,
                    customStart: customStart,
                    customEnd: customEnd
                )
        }.sorted {
            if $0.bookingDate != $1.bookingDate {
                return $0.bookingDate < $1.bookingDate
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        let isFiltered = effectiveAccounts != allAccountIDs
            || status != nil
            || category != .all
            || tagID != nil
            || period != .all
            || !search.isEmpty
        let totals = Dictionary(grouping: rows.filter {
            $0.transferID == nil && $0.status != .cancelled
        }) { $0.currency }.mapValues { values in
            values.reduce(Int64.zero) { $0 + $1.amountMinor }
        }
        return CombinedRegisterQueryResult(
            rows: rows,
            isFiltered: isFiltered,
            totalsByCurrency: totals
        )
    }

    static func runningBalances(
        accounts: [FinanceAccount],
        transactions: [FinanceTransaction]
    ) -> [UUID: Int64] {
        let openingByAccount = Dictionary(
            uniqueKeysWithValues: accounts.map {
                ($0.id, $0.openingBalanceMinor)
            }
        )
        let grouped = Dictionary(grouping: transactions) { $0.accountID }
        var result: [UUID: Int64] = [:]
        for (accountID, values) in grouped {
            var balance = openingByAccount[accountID] ?? 0
            for transaction in values.sorted(by: {
                if $0.bookingDate != $1.bookingDate {
                    return $0.bookingDate < $1.bookingDate
                }
                return $0.id.uuidString < $1.id.uuidString
            }) {
                if transaction.status != .cancelled {
                    balance += transaction.amountMinor
                }
                result[transaction.id] = balance
            }
        }
        return result
    }
}

struct CombinedRegisterView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @State private var selection = Set<UUID>()
    @State private var showBulkEditor = false
    @State private var statusFilter: TransactionStatus?
    @State private var categoryFilter = RegisterCategoryFilter.all
    @State private var tagFilterID: UUID?
    @State private var periodFilter = RegisterPeriodFilter.all
    @State private var customStart = Calendar.current.date(
        byAdding: .month,
        value: -1,
        to: .now
    ) ?? .now
    @State private var customEnd = Date.now
    @State private var includeForecast = true
    @State private var showPDFExporter = false
    @State private var registerPDFDocument = RegisterPDFDocument(data: Data())
    @State private var showCSVExporter = false
    @State private var registerCSVDocument = RegisterCSVDocument(data: Data())
    @State private var showSaveView = false
    @State private var savedViewName = ""
    @State private var selectedSavedViewID: UUID?
    @AppStorage("registerRowMode") private var rowModeRaw = RegisterRowMode.single.rawValue
    @AppStorage("registerVisibleColumnsV1") private var visibleColumnsRaw = ""
    @AppStorage("registerAmountColumnModeV1")
    private var amountColumnModeRaw = RegisterAmountColumnMode.amount.rawValue
    @AppStorage("combinedRegisterAccountIDsV1")
    private var includedAccountIDsRaw = ""
    @AppStorage("savedCombinedRegisterViewsV1")
    private var savedViewsRaw = ""
    @AppStorage("combinedRegisterSplitVisibleV1")
    private var showSecondCombinedRegister = false

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

    private var amountColumnMode: RegisterAmountColumnMode {
        get {
            RegisterAmountColumnMode(rawValue: amountColumnModeRaw) ?? .amount
        }
        nonmutating set { amountColumnModeRaw = newValue.rawValue }
    }

    private var includedAccountIDs: Set<UUID> {
        get {
            Set(includedAccountIDsRaw.split(separator: ",").compactMap {
                UUID(uuidString: String($0))
            }).intersection(Set(store.accounts.map(\.id)))
        }
        nonmutating set {
            includedAccountIDsRaw = newValue.sorted {
                $0.uuidString < $1.uuidString
            }.map(\.uuidString).joined(separator: ",")
        }
    }

    private var queryResult: CombinedRegisterQueryResult {
        let forecast = includeForecast
            ? store.forecastOccurrences(days: 365) : []
        let runningBalances = CombinedRegisterQuery.runningBalances(
            accounts: store.accounts,
            transactions: store.transactions + forecast
        )
        let searchQuery = RegisterSearchQuery(store.searchText)
        let indexedMatches = store.registerSearchIndex
            .matchingTransactionIDs(searchQuery)
        return CombinedRegisterQuery.evaluate(
            transactions: store.transactions,
            forecastTransactions: forecast,
            allAccountIDs: Set(store.accounts.filter {
                !$0.isClosed
            }.map(\.id)),
            includedAccountIDs: includedAccountIDs,
            status: statusFilter,
            category: categoryFilter,
            tagID: tagFilterID,
            period: periodFilter,
            customStart: customStart,
            customEnd: customEnd,
            searchText: store.searchText,
            includeForecast: includeForecast,
            searchMatches: { transaction, query in
                store.matchesRegisterSearch(
                    transaction,
                    query: query,
                    runningBalanceMinor: runningBalances[transaction.id],
                    indexedMatches: indexedMatches
                )
            }
        ) { transaction in
            store.transactionCategoryPath(transaction)
        }
    }

    private var chartSnapshot: CombinedRegisterChartSnapshot {
        CombinedRegisterChartEngine.make(
            accounts: store.accounts.filter {
                !$0.isClosed
                    && (includedAccountIDs.isEmpty
                        || includedAccountIDs.contains($0.id))
            },
            rows: queryResult.rows,
            isFiltered: queryResult.isFiltered
        )
    }

    private var savedViews: [SavedCombinedRegisterView] {
        RegisterPreferencesCodec.decodeCombinedViews(savedViewsRaw)
    }

    private var persistentSelection: Set<UUID> {
        selection.intersection(Set(store.transactions.map(\.id)))
    }

    var body: some View {
        let runningBalances = CombinedRegisterQuery.runningBalances(
            accounts: store.accounts,
            transactions: store.transactions
                + (includeForecast ? store.forecastOccurrences(days: 365) : [])
        )
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sammelkontoblatt").font(.title2.bold())
                    Text("Alle normalen Buchungskonten · Vergangenheit, Heute und erwartete Zukunft")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showSecondCombinedRegister.toggle()
                } label: {
                    Label("Zweite Ansicht", systemImage: "rectangle.split.2x1")
                }
                .help(
                    showSecondCombinedRegister
                        ? "Zweite Sammelansicht schließen"
                        : "Zweite unabhängige Sammelansicht öffnen"
                )
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
                Menu {
                    Picker("Betragsspalten", selection: $amountColumnModeRaw) {
                        ForEach(RegisterAmountColumnMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                } label: {
                    Label(
                        amountColumnMode.title,
                        systemImage: amountColumnMode == .amount
                            ? "eurosign" : "rectangle.split.2x1"
                    )
                }
                .help("Eine Betragsspalte oder getrennte Soll-/Haben-Spalten")
                .accessibilityIdentifier("combinedRegister.amountColumnMode")
                combinedViewMenu
                registerColumnMenu
                VStack(alignment: .trailing) {
                    Text(
                        queryResult.isFiltered
                            ? "Gefilterte Summe ohne Umbuchungen"
                            : "Bewegungssumme ohne Umbuchungen"
                    )
                        .font(.caption).foregroundStyle(.secondary)
                    Text(queryTotalsText)
                        .font(.title3.bold().monospacedDigit())
                }
            }
            .padding(14)
            Divider()
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    combinedAccountMenu
                Picker("Status", selection: $statusFilter) {
                    Text("Alle Status").tag(TransactionStatus?.none)
                    ForEach(TransactionStatus.allCases, id: \.self) {
                        Text($0.title).tag(Optional($0))
                    }
                }
                .frame(width: 140)
                Picker("Kategorie", selection: $categoryFilter) {
                    Text("Alle Kategorien").tag(RegisterCategoryFilter.all)
                    Text("Nicht kategorisiert")
                        .tag(RegisterCategoryFilter.uncategorized)
                    Divider()
                    ForEach(store.categoriesByPath.filter(\.isActive)) {
                        Text(store.categoryPath($0.id))
                            .tag(RegisterCategoryFilter.category($0.id))
                    }
                }
                .frame(width: 190)
                Picker("Klasse/Tag", selection: $tagFilterID) {
                    Text("Alle Klassen/Tags").tag(UUID?.none)
                    ForEach(store.tagsByPath.filter(\.isActive)) { tag in
                        Text(store.tagPath(tag.id)).tag(UUID?.some(tag.id))
                    }
                }
                .frame(width: 165)
                Picker("Zeitraum", selection: $periodFilter) {
                    ForEach(RegisterPeriodFilter.allCases) {
                        Text($0.title).tag($0)
                    }
                }
                .frame(width: 150)
                Toggle("Regelmäßige Zukunft", isOn: $includeForecast)
                    .toggleStyle(.checkbox)
                if periodFilter == .custom {
                    DatePicker(
                        "Von",
                        selection: $customStart,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    Text("bis").foregroundStyle(.secondary)
                    DatePicker(
                        "Bis",
                        selection: $customEnd,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                }
                    Spacer()
                    combinedReportMenu
                    combinedOutputMenu
                    Button("Filter zurücksetzen") {
                        includedAccountIDs = []
                        statusFilter = nil
                        categoryFilter = .all
                        tagFilterID = nil
                        periodFilter = .all
                        store.searchText = ""
                    }
                    .disabled(!queryResult.isFiltered)
                }
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .scrollIndicators(.hidden)
            Divider()
            CombinedRegisterChartPanel(
                snapshot: chartSnapshot,
                accessibilityIdentifier: "combinedRegister.balanceChart",
                transactionSelection: $selection
            )
            Divider()
            HStack(spacing: 0) {
                Table(queryResult.rows, selection: $selection) {
                    TableColumnForEach(orderedVisibleColumns) { column in
                        TableColumn(column.title) { value in
                            combinedRegisterCell(
                                value,
                                column: column,
                                runningBalances: runningBalances
                            )
                            .accessibilityLabel(
                                RegisterAccessibility.cellLabel(
                                    column: column,
                                    value: combinedCellText(
                                        value,
                                        column: column,
                                        runningBalances: runningBalances
                                    )
                                )
                            )
                        }
                        .width(min: column.minimumWidth, ideal: column.idealWidth)
                    }
                }
                .accessibilityLabel("Sammelkontoblatt Buchungstabelle")
                .accessibilityValue(
                    RegisterAccessibility.tableValue(
                        visibleCount: queryResult.rows.count,
                        selectedCount: selection.count
                    )
                )
                .accessibilityIdentifier("combinedRegister.transactionTable")
                .contextMenu(forSelectionType: UUID.self) { ids in
                    Button("Kategorie/Klassen für Auswahl ändern …") {
                        selection = ids
                        showBulkEditor = true
                    }
                    .disabled(
                        ids.intersection(Set(store.transactions.map(\.id))).isEmpty
                    )
                }
                .overlay {
                    if queryResult.rows.isEmpty {
                        ContentUnavailableView(
                            "Keine Buchungen",
                            systemImage: "rectangle.stack.badge.person.crop",
                            description: Text(
                                "Die gewählten Konten und Filter liefern keine Treffer."
                            )
                        )
                    }
                }
                if showSecondCombinedRegister {
                    Divider()
                    SecondaryCombinedRegisterPane()
                        .frame(minWidth: 410, idealWidth: 560)
                }
            }
            HStack {
                Rectangle().fill(.blue).frame(width: 36, height: 2)
                Text("Heute-Grenze: \(Date.now.formatted(.dateTime.day().month().year()))")
                if queryResult.isFiltered {
                    Label(
                        "Gefilterte Summe ist kein Kontostand",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
                Spacer()
                if !selection.isEmpty {
                    Button("Kategorie/Klassen ändern …") {
                        showBulkEditor = true
                    }
                    .disabled(persistentSelection.isEmpty)
                    Text("\(selection.count) ausgewählt")
                }
                Text("\(queryResult.rows.count) sichtbare Buchungen")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
        }
        .sheet(isPresented: $showBulkEditor) {
            BulkCategoryEditorView(transactionIDs: persistentSelection) {
                selection.removeAll()
            }
        }
        .sheet(isPresented: $showSaveView) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Sammelkontoblatt-Ansicht speichern")
                    .font(.title2.bold())
                Text(
                    "Gespeichert werden Kontenauswahl, Filter, Zukunft, "
                        + "Zeilenmodus, Betragsdarstellung und sichtbare Spalten."
                )
                .foregroundStyle(.secondary)
                TextField("Name der Ansicht", text: $savedViewName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Abbrechen", role: .cancel) {
                        showSaveView = false
                    }
                    Button("Speichern") { saveCombinedView() }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            savedViewName.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                        )
                }
            }
            .padding(24)
            .frame(width: 500)
        }
        .fileExporter(
            isPresented: $showCSVExporter,
            document: registerCSVDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "Sammelkontoblatt"
        ) { result in
            switch result {
            case .success:
                store.statusText = "Sammelkontoblatt als CSV exportiert"
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showPDFExporter,
            document: registerPDFDocument,
            contentType: .pdf,
            defaultFilename: "Sammelkontoblatt"
        ) { result in
            switch result {
            case .success:
                store.statusText = "Sammelkontoblatt als PDF exportiert"
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
        .onChange(of: queryResult.rows.map(\.id)) {
            selection.formIntersection(Set(queryResult.rows.map(\.id)))
        }
    }

    private var queryTotalsText: String {
        let text = queryResult.totalsByCurrency.keys.sorted().map { currency in
            Money(
                minorUnits: queryResult.totalsByCurrency[currency] ?? 0,
                currency: currency
            ).formatted
        }.joined(separator: " · ")
        return text.isEmpty ? "—" : text
    }

    private var combinedViewMenu: some View {
        Menu {
            if savedViews.isEmpty {
                Text("Noch keine gespeicherte Ansicht")
            } else {
                ForEach(savedViews) { view in
                    Button {
                        applyCombinedView(view)
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
            Button(
                "Ausgewählte Ansicht löschen",
                systemImage: "trash",
                role: .destructive
            ) {
                deleteCombinedView()
            }
            .disabled(selectedSavedViewID == nil)
        } label: {
            Label(
                selectedSavedViewID.flatMap { id in
                    savedViews.first { $0.id == id }?.name
                } ?? "Ansicht",
                systemImage: "rectangle.stack.badge.plus"
            )
        }
    }

    private func saveCombinedView() {
        let name = savedViewName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let existingID = savedViews.first {
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }?.id
        let id = selectedSavedViewID ?? existingID ?? UUID()
        let view = SavedCombinedRegisterView(
            id: id,
            name: name,
            includedAccountIDs: includedAccountIDs,
            statusRawValue: statusFilter?.rawValue,
            categorySelection: categoryFilter.savedSelection,
            tagID: tagFilterID,
            periodRawValue: periodFilter.rawValue,
            customStart: customStart,
            customEnd: customEnd,
            includeForecast: includeForecast,
            rowModeRawValue: rowMode.rawValue,
            visibleColumns: visibleColumns,
            amountColumnModeRawValue: amountColumnMode.rawValue
        )
        var values = savedViews.filter { $0.id != id }
        values.append(view)
        values.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name)
                == .orderedAscending
        }
        do {
            savedViewsRaw = try RegisterPreferencesCodec
                .encodeCombinedViews(values)
            selectedSavedViewID = id
            showSaveView = false
            store.statusText = "Sammelkontoblatt-Ansicht „\(name)“ gespeichert"
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func applyCombinedView(_ view: SavedCombinedRegisterView) {
        let validAccountIDs = Set(store.accounts.map(\.id))
        includedAccountIDs = view.includedAccountIDs
            .intersection(validAccountIDs)
        statusFilter = view.statusRawValue.flatMap(
            TransactionStatus.init(rawValue:)
        )
        categoryFilter = RegisterCategoryFilter(view.categorySelection)
        tagFilterID = view.tagID.flatMap { id in
            store.tags.contains(where: { $0.id == id }) ? id : nil
        }
        periodFilter = RegisterPeriodFilter(
            rawValue: view.periodRawValue
        ) ?? .all
        customStart = view.customStart
        customEnd = view.customEnd
        includeForecast = view.includeForecast
        rowMode = RegisterRowMode(
            rawValue: view.rowModeRawValue
        ) ?? .single
        visibleColumns = view.visibleColumns
        amountColumnMode = RegisterAmountColumnMode(
            rawValue: view.amountColumnModeRawValue ?? ""
        ) ?? .amount
        selectedSavedViewID = view.id
        store.statusText = "Sammelkontoblatt-Ansicht „\(view.name)“ geladen"
    }

    private func deleteCombinedView() {
        guard let selectedSavedViewID else { return }
        do {
            savedViewsRaw = try RegisterPreferencesCodec.encodeCombinedViews(
                savedViews.filter { $0.id != selectedSavedViewID }
            )
            self.selectedSavedViewID = nil
            store.statusText = "Sammelkontoblatt-Ansicht gelöscht"
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private var combinedAccountMenu: some View {
        Menu {
            Button("Alle offenen Konten") {
                includedAccountIDs = []
            }
            Divider()
            ForEach(store.accounts.filter { !$0.isClosed }) { account in
                Toggle(
                    account.name,
                    isOn: Binding(
                        get: {
                            includedAccountIDs.isEmpty
                                || includedAccountIDs.contains(account.id)
                        },
                        set: { selected in
                            var ids = includedAccountIDs.isEmpty
                                ? Set(store.accounts.filter {
                                    !$0.isClosed
                                }.map(\.id))
                                : includedAccountIDs
                            if selected {
                                ids.insert(account.id)
                            } else {
                                ids.remove(account.id)
                            }
                            includedAccountIDs = ids
                        }
                    )
                )
            }
        } label: {
            Label(
                includedAccountIDs.isEmpty
                    ? "Alle Konten"
                    : "\(includedAccountIDs.count) Konten",
                systemImage: "building.columns"
            )
        }
    }

    private var combinedOutputMenu: some View {
        Menu {
            Button("Drucken …", systemImage: "printer") {
                do {
                    try RegisterPrintService.printPDF(
                        try RegisterPDFExporter.data(
                            snapshot: combinedPrintSnapshot
                        )
                    )
                } catch {
                    store.errorMessage = error.localizedDescription
                }
            }
            Button("Als PDF exportieren …", systemImage: "doc.richtext") {
                do {
                    registerPDFDocument = RegisterPDFDocument(
                        data: try RegisterPDFExporter.data(
                            snapshot: combinedPrintSnapshot
                        )
                    )
                    showPDFExporter = true
                } catch {
                    store.errorMessage = error.localizedDescription
                }
            }
            Menu("Als CSV exportieren …", systemImage: "tablecells") {
                ForEach(RegisterCSVFormat.allCases) { format in
                    Button(format.title) {
                        do {
                            registerCSVDocument = RegisterCSVDocument(
                                data: try RegisterCSVExporter.data(
                                    snapshot: combinedPrintSnapshot,
                                    format: format
                                )
                            )
                            showCSVExporter = true
                        } catch {
                            store.errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        } label: {
            Label("Ausgabe", systemImage: "printer")
        }
    }

    private var combinedReportMenu: some View {
        Menu {
            Button("Alle sichtbaren Buchungen") {
                openReport(
                    TransactionReportQuery(
                        statuses: Set(TransactionStatus.allCases),
                        includeHiddenAccounts: true,
                        includeAccountsExcludedFromReports: true,
                        includeTransfers: true,
                        expandSplits: true,
                        grouping: .account,
                        sort: .dateAscending,
                        transactionIDs: Set(queryResult.rows.map(\.id)),
                        includeForecast: includeForecast
                    )
                )
            }
            .disabled(queryResult.rows.isEmpty)
            Divider()
            Button("Empfänger der Auswahl") {
                guard let transaction = selectedCombinedTransaction else {
                    return
                }
                openReport(
                    TransactionReportQuery(
                        exactPayee: transaction.payee,
                        includeForecast: includeForecast
                    )
                )
            }
            .disabled(
                selectedCombinedTransaction?.payee.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty != false
            )
            Button("Kategorie der Auswahl") {
                guard let transaction = selectedCombinedTransaction,
                      let categoryID = transaction.categoryID
                        ?? transaction.splits.sorted(by: {
                            $0.sortOrder < $1.sortOrder
                        }).compactMap(\.categoryID).first
                else { return }
                openReport(
                    TransactionReportQuery(
                        categoryIDs: [categoryID],
                        grouping: .category,
                        includeForecast: includeForecast
                    )
                )
            }
            .disabled(selectedCombinedCategoryID == nil)
            Button("Klasse/Tag der Auswahl") {
                guard let tagID = selectedCombinedTagID else { return }
                openReport(
                    TransactionReportQuery(
                        tagIDs: [tagID],
                        grouping: .tag,
                        includeForecast: includeForecast
                    )
                )
            }
            .disabled(selectedCombinedTagID == nil)
        } label: {
            Label("Bericht", systemImage: "chart.bar.xaxis")
        }
    }

    private var selectedCombinedTransaction: FinanceTransaction? {
        guard selection.count == 1, let id = selection.first else {
            return nil
        }
        return queryResult.rows.first { $0.id == id }
    }

    private var selectedCombinedCategoryID: UUID? {
        guard let transaction = selectedCombinedTransaction else { return nil }
        return transaction.categoryID
            ?? transaction.splits.sorted {
                $0.sortOrder < $1.sortOrder
            }.compactMap(\.categoryID).first
    }

    private var selectedCombinedTagID: UUID? {
        guard let transaction = selectedCombinedTransaction else { return nil }
        return (transaction.tagIDs + transaction.splits.flatMap(\.tagIDs))
            .sorted { $0.uuidString < $1.uuidString }
            .first
    }

    private func openReport(_ query: TransactionReportQuery) {
        NotificationCenter.default.post(
            name: .openTransactionReport,
            object: query
        )
        store.statusText = "Bericht aus Sammelkontoblatt geöffnet"
    }

    private var combinedPrintSnapshot: RegisterPrintSnapshot {
        let runningBalances = CombinedRegisterQuery.runningBalances(
            accounts: store.accounts,
            transactions: store.transactions
                + (includeForecast ? store.forecastOccurrences(days: 365) : [])
        )
        return RegisterPrintSnapshot(
            title: "Sammelkontoblatt",
            filterSummary: combinedFilterSummary,
            generatedAt: .now,
            columns: orderedVisibleColumns,
            rows: queryResult.rows.map { transaction in
                orderedVisibleColumns.map { column in
                    combinedCellText(
                        transaction,
                        column: column,
                        runningBalances: runningBalances
                    )
                }
            }
        )
    }

    private var combinedFilterSummary: String {
        var parts: [String] = []
        if !includedAccountIDs.isEmpty {
            parts.append("Konten: \(includedAccountIDs.count)")
        }
        if let statusFilter { parts.append("Status: \(statusFilter.title)") }
        switch categoryFilter {
        case .all: break
        case .uncategorized: parts.append("Kategorie: Nicht kategorisiert")
        case .category(let id):
            parts.append("Kategorie: \(store.categoryPath(id))")
        }
        if let tagFilterID {
            parts.append("Klasse/Tag: \(store.tagPath(tagFilterID))")
        }
        if periodFilter != .all {
            parts.append("Zeitraum: \(periodFilter.title)")
        }
        let search = store.searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !search.isEmpty { parts.append("Suche: \(search)") }
        if includeForecast { parts.append("einschließlich regelmäßiger Zukunft") }
        return parts.isEmpty ? "Keine zusätzlichen Filter" : parts.joined(separator: " · ")
    }

    private var orderedVisibleColumns: [RegisterColumn] {
        RegisterColumnLayout.columns(
            visible: visibleColumns,
            amountMode: amountColumnMode
        )
    }

    @ViewBuilder
    private func combinedRegisterCell(
        _ value: FinanceTransaction,
        column: RegisterColumn,
        runningBalances: [UUID: Int64]
    ) -> some View {
        switch column {
        case .date:
            HStack(spacing: 4) {
                if isFirstFutureTransaction(value) {
                    Rectangle()
                        .fill(.blue)
                        .frame(width: 3, height: rowMode.rowHeight - 4)
                        .help("Beginn der erwarteten Zukunft")
                }
                Text(
                    value.bookingDate,
                    format: .dateTime.day().month(.twoDigits).year()
                )
            }
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
        case .flag:
            Label(value.flag?.title ?? "Ohne", systemImage: value.flag == nil ? "flag" : "flag.fill")
                .foregroundStyle(value.flag.map(transactionFlagColor) ?? .secondary)
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
            let tags = value.tagIDs.map(store.tagPath).joined(separator: ", ")
            Text(tags.isEmpty ? "–" : tags)
                .lineLimit(rowMode == .twoLines ? 2 : 1)
                .truncationMode(.middle)
                .help(tags)
                .frame(height: rowMode.rowHeight, alignment: .leading)
        case .account:
            Text(store.accountName(value.accountID))
                .frame(height: rowMode.rowHeight, alignment: .leading)
        case .amount, .debit, .credit:
            let presentedAmount = RegisterAmountPresentation.minorUnits(
                for: column,
                amountMinor: value.amountMinor
            )
            Text(
                presentedAmount.map {
                    Money(minorUnits: $0, currency: value.currency).formatted
                } ?? ""
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

    private func isFirstFutureTransaction(
        _ transaction: FinanceTransaction
    ) -> Bool {
        guard transaction.bookingDate > Date() else { return false }
        return queryResult.rows.first(where: {
            $0.bookingDate > Date()
        })?.id == transaction.id
    }

    private func combinedCellText(
        _ value: FinanceTransaction,
        column: RegisterColumn,
        runningBalances: [UUID: Int64]
    ) -> String {
        switch column {
        case .date:
            return value.bookingDate.formatted(date: .numeric, time: .omitted)
        case .valueDate:
            return (value.valueDate ?? value.bookingDate)
                .formatted(date: .numeric, time: .omitted)
        case .reference:
            return value.reference.isEmpty ? "–" : value.reference
        case .status:
            return value.status.title
        case .flag:
            return value.flag?.title ?? "Ohne Kennzeichen"
        case .payee:
            return value.payee
        case .purpose:
            return value.purpose
        case .category:
            return store.transactionCategoryPath(value)
        case .tags:
            let tags = value.tagIDs.map(store.tagPath).joined(separator: ", ")
            return tags.isEmpty ? "–" : tags
        case .account:
            return store.accountName(value.accountID)
        case .amount, .debit, .credit:
            guard let presentedAmount = RegisterAmountPresentation.minorUnits(
                for: column,
                amountMinor: value.amountMinor
            ) else { return "" }
            return Money(
                minorUnits: presentedAmount,
                currency: value.currency
            ).formatted
        case .balance:
            return Money(
                minorUnits: runningBalances[value.id] ?? 0,
                currency: value.currency
            ).formatted
        }
    }

    private var registerColumnMenu: some View {
        Menu {
            ForEach(RegisterColumn.configurableCases) { column in
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
