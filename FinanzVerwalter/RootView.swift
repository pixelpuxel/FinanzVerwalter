import SwiftUI

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case cockpit
    case accounts
    case categories
    case register
    case combinedRegister
    case banking
    case payments
    case calendar
    case budget
    case reports
    case taxAllowances
    case investments
    case assets
    case contracts
    case inventory
    case addresses
    case rules
    case importExport
    case settings

    var id: Self { self }
    var title: String {
        switch self {
        case .cockpit: "Cockpit"
        case .accounts: "Konten"
        case .categories: "Kategorien"
        case .register: "Kontoblatt"
        case .combinedRegister: "Sammelkontoblätter"
        case .banking: "Banking-Abruf"
        case .payments: "Zahlungsverkehr"
        case .calendar: "Kalender & Prognose"
        case .budget: "Budget"
        case .reports: "Auswertungen"
        case .taxAllowances: "Freistellungsaufträge"
        case .investments: "Wertpapiere & Depots"
        case .assets: "Kredite & Vermögen"
        case .contracts: "Verträge"
        case .inventory: "Inventar"
        case .addresses: "Adressen & Mandate"
        case .rules: "Regeln"
        case .importExport: "Import/Export"
        case .settings: "Einstellungen"
        }
    }
    var icon: String {
        switch self {
        case .cockpit: "gauge.with.dots.needle.50percent"
        case .accounts: "building.columns"
        case .categories: "folder"
        case .register: "list.bullet.rectangle"
        case .combinedRegister: "rectangle.stack"
        case .banking: "arrow.triangle.2.circlepath"
        case .payments: "arrow.left.arrow.right"
        case .calendar: "calendar"
        case .budget: "chart.pie"
        case .reports: "chart.bar.xaxis"
        case .taxAllowances: "eurosign.circle"
        case .investments: "chart.line.uptrend.xyaxis"
        case .assets: "house"
        case .contracts: "doc.text"
        case .inventory: "shippingbox"
        case .addresses: "person.2"
        case .rules: "wand.and.stars"
        case .importExport: "square.and.arrow.down.on.square"
        case .settings: "gearshape"
        }
    }

    static let financeSections: [WorkspaceSection] = [
        .cockpit, .accounts, .register, .combinedRegister, .categories,
        .banking, .payments, .calendar, .budget, .reports, .taxAllowances
    ]

    static let organizationSections: [WorkspaceSection] = [
        .investments, .assets, .contracts, .inventory, .addresses,
        .rules, .importExport, .settings
    ]
}

struct RootView: View {
    @EnvironmentObject private var store: FinanceAppStore
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.light.rawValue
    @State private var selectedSection: WorkspaceSection = .cockpit
    @State private var showNewAccount = false
    @State private var showNewTransaction = false
    @State private var showTransfer = false
    @State private var showReconciliation = false
    @State private var newTransactionStartsWithSplits = false
    @State private var reportLaunchQuery: TransactionReportQuery?
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topToolbar
            Divider()
            NavigationSplitView {
                List(selection: $selectedSection) {
                    Section("Finanzen") {
                        ForEach(WorkspaceSection.financeSections) { section in
                            Label(section.title, systemImage: section.icon).tag(section)
                        }
                    }
                    Section("Vermögen & Organisation") {
                        ForEach(WorkspaceSection.organizationSections) { section in
                            Label(section.title, systemImage: section.icon).tag(section)
                        }
                    }
                    if !store.accounts.isEmpty {
                        Section("Konten") {
                            ForEach(store.accountGroups.filter(\.isActive)) { group in
                                let accounts = store.accounts.filter {
                                    $0.groupID == group.id && !$0.isHidden && !$0.isClosed
                                }
                                if !accounts.isEmpty {
                                    DisclosureGroup(group.name) {
                                        ForEach(accounts) { account in
                                            accountSidebarButton(account)
                                        }
                                    }
                                }
                            }
                            let ungrouped = store.accounts.filter {
                                $0.groupID == nil && !$0.isHidden && !$0.isClosed
                            }
                            ForEach(ungrouped) { account in
                                accountSidebarButton(account)
                            }
                        }
                    }
                }
                .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 300)
                .listStyle(.sidebar)
            } detail: {
                sectionView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Label(store.fileInfo?.name ?? "Keine Finanzdatei", systemImage: "internaldrive")
                Spacer()
                Text("\(store.filteredTransactions.count) Buchungen")
                Divider().frame(height: 14)
                Text(store.statusText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .sheet(isPresented: $showNewAccount) { AccountEditorView() }
        .sheet(isPresented: $showNewTransaction) {
            TransactionEditorView(
                startWithSplits: newTransactionStartsWithSplits
            )
        }
        .sheet(isPresented: $showTransfer) { TransferEditorView() }
        .sheet(isPresented: $showReconciliation) { ReconciliationView() }
        .alert(
            "Hinweis",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTransaction)) { _ in
            if !store.accounts.isEmpty {
                newTransactionStartsWithSplits = false
                showNewTransaction = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reconcileAccount)) { _ in
            if !store.accounts.isEmpty { showReconciliation = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            searchIsFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSplitEditor)) { _ in
            if !store.accounts.isEmpty, !showNewTransaction {
                newTransactionStartsWithSplits = true
                showNewTransaction = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cancelCurrentEditor)) { _ in
            showNewAccount = false
            showNewTransaction = false
            showTransfer = false
            showReconciliation = false
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .openTransactionReport)
        ) { notification in
            guard let query = notification.object as? TransactionReportQuery
            else { return }
            reportLaunchQuery = query
            selectedSection = .reports
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .openAccountRegister)
        ) { notification in
            guard let accountID = notification.object as? UUID,
                  store.accounts.contains(where: { $0.id == accountID }) else { return }
            store.selectedAccountID = accountID
            selectedSection = .register
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .openAccountBanking)
        ) { notification in
            guard let accountID = notification.object as? UUID,
                  store.accounts.contains(where: { $0.id == accountID }) else { return }
            store.selectedAccountID = accountID
            selectedSection = .banking
        }
    }

    private func accountSidebarButton(_ account: FinanceAccount) -> some View {
        Button {
            store.selectedAccountID = account.id
            selectedSection = .register
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(account.name)
                Text(
                    Money(
                        minorUnits: store.balances[account.id] ?? 0,
                        currency: account.currency
                    ).formatted
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var topToolbar: some View {
        HStack(spacing: 8) {
            Text("FinanzVerwalter")
                .font(.title2.bold())
                .foregroundStyle(Color(red: 0.05, green: 0.31, blue: 0.18))
                .padding(.trailing, 12)
            ToolbarButton("Konto", icon: "plus.rectangle.on.folder") { showNewAccount = true }
            ToolbarButton("Buchung", icon: "plus") {
                if !store.accounts.isEmpty {
                    newTransactionStartsWithSplits = false
                    showNewTransaction = true
                }
            }
            ToolbarButton("Umbuchung", icon: "arrow.left.arrow.right") {
                if store.accounts.count >= 2 { showTransfer = true }
            }
            Divider().frame(height: 28)
            ToolbarButton("Speichern", icon: "square.and.arrow.down") {
                NotificationCenter.default.post(name: .saveCurrentEditor, object: nil)
            }
            ToolbarButton("Aktualisieren", icon: "arrow.clockwise") { store.reload() }
            ToolbarButton("Abgleichen", icon: "checkmark.seal") {
                if !store.accounts.isEmpty { showReconciliation = true }
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Suchen", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 220)
                    .focused($searchIsFocused)
                    .accessibilityIdentifier("globalSearch")
                if !store.searchText.isEmpty {
                    Button { store.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            Menu {
                Picker("Darstellung", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.icon).tag(mode.rawValue)
                    }
                }
            } label: {
                let mode = AppearanceMode(rawValue: appearanceMode) ?? .light
                Label(mode.title, systemImage: mode.icon)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Hell-/Dunkelmodus umschalten")
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(
            LinearGradient(
                colors: [Color(nsColor: .controlBackgroundColor), Color(nsColor: .windowBackgroundColor)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    @ViewBuilder
    private var sectionView: some View {
        switch selectedSection {
        case .cockpit: CockpitView()
        case .accounts: AccountsView()
        case .categories: CategoriesView()
        case .register: RegisterView()
        case .combinedRegister: CombinedRegisterView()
        case .banking: BankingView()
        case .payments: PaymentsView()
        case .calendar: CalendarForecastView()
        case .budget: BudgetView()
        case .reports: ReportsView(launchQuery: reportLaunchQuery)
        case .taxAllowances: TaxAllowancesView()
        case .investments: InvestmentsView()
        case .assets: AssetsView()
        case .contracts: ContractsView()
        case .inventory: InventoryView()
        case .rules: RulesView()
        case .importExport: ImportExportView()
        case .settings: SettingsView()
        default: ModuleOverviewView(section: selectedSection)
        }
    }
}

private struct ToolbarButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    init(_ title: String, icon: String, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption2)
            }
            .frame(minWidth: 58)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
