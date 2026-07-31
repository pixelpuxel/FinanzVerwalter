import CryptoKit
import Foundation
import SQLite3

final class SQLiteFinanceStore {
    private var database: OpaquePointer?
    let fileURL: URL

    init(fileURL: URL = SQLiteFinanceStore.defaultFileURL()) throws {
        self.fileURL = fileURL
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard sqlite3_open_v2(
            fileURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            throw FinanceError.database("Die Finanzdatei konnte nicht geöffnet werden.")
        }
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = FULL")
        try migrate()
    }

    deinit {
        close()
    }

    func close() {
        if let database {
            sqlite3_close(database)
            self.database = nil
        }
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("FinanzVerwalter", isDirectory: true)
            .appendingPathComponent("Meine Finanzen.qdata")
    }

    static func validateBackup(at url: URL) throws {
        var checkDatabase: OpaquePointer?
        guard sqlite3_open_v2(url.path, &checkDatabase, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw FinanceError.invalidBackup
        }
        defer { sqlite3_close(checkDatabase) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            checkDatabase,
            "SELECT name FROM sqlite_master WHERE type='table' AND name='finance_files'",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else { throw FinanceError.invalidBackup }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            sqlite3_finalize(statement)
            throw FinanceError.invalidBackup
        }
        sqlite3_finalize(statement)
        statement = nil
        guard sqlite3_prepare_v2(checkDatabase, "PRAGMA integrity_check", -1, &statement, nil) == SQLITE_OK else {
            throw FinanceError.invalidBackup
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, Self.text(statement, 0) == "ok" else {
            throw FinanceError.invalidBackup
        }
    }

    private func migrate() throws {
        let version = try scalarInt("PRAGMA user_version")
        if version < 1 {
            try transaction {
                try execute(
                    """
                    CREATE TABLE finance_files (
                        id TEXT PRIMARY KEY,
                        name TEXT NOT NULL,
                        base_currency TEXT NOT NULL,
                        locale TEXT NOT NULL,
                        time_zone TEXT NOT NULL,
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL,
                        version INTEGER NOT NULL DEFAULT 1
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE accounts (
                        id TEXT PRIMARY KEY,
                        finance_file_id TEXT NOT NULL REFERENCES finance_files(id),
                        name TEXT NOT NULL,
                        institution TEXT NOT NULL DEFAULT '',
                        type TEXT NOT NULL,
                        currency TEXT NOT NULL,
                        opening_balance_minor INTEGER NOT NULL,
                        is_hidden INTEGER NOT NULL DEFAULT 0,
                        is_closed INTEGER NOT NULL DEFAULT 0,
                        sort_order INTEGER NOT NULL DEFAULT 0,
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL,
                        version INTEGER NOT NULL DEFAULT 1
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE categories (
                        id TEXT PRIMARY KEY,
                        finance_file_id TEXT NOT NULL REFERENCES finance_files(id),
                        parent_id TEXT REFERENCES categories(id),
                        name TEXT NOT NULL,
                        kind TEXT NOT NULL,
                        color TEXT NOT NULL DEFAULT 'blue',
                        is_active INTEGER NOT NULL DEFAULT 1,
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL,
                        version INTEGER NOT NULL DEFAULT 1,
                        UNIQUE(finance_file_id, parent_id, name)
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE transactions (
                        id TEXT PRIMARY KEY,
                        account_id TEXT NOT NULL REFERENCES accounts(id),
                        booking_date TEXT NOT NULL,
                        value_date TEXT,
                        payee TEXT NOT NULL DEFAULT '',
                        purpose TEXT NOT NULL DEFAULT '',
                        category_id TEXT REFERENCES categories(id),
                        amount_minor INTEGER NOT NULL,
                        currency TEXT NOT NULL,
                        status TEXT NOT NULL,
                        memo TEXT NOT NULL DEFAULT '',
                        reference TEXT NOT NULL DEFAULT '',
                        transfer_id TEXT,
                        import_fingerprint TEXT,
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL,
                        version INTEGER NOT NULL DEFAULT 1
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE transaction_splits (
                        id TEXT PRIMARY KEY,
                        transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
                        category_id TEXT REFERENCES categories(id),
                        amount_minor INTEGER NOT NULL,
                        memo TEXT NOT NULL DEFAULT '',
                        sort_order INTEGER NOT NULL
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE import_packages (
                        fingerprint TEXT PRIMARY KEY,
                        imported_at TEXT NOT NULL,
                        row_count INTEGER NOT NULL
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE audit_events (
                        id TEXT PRIMARY KEY,
                        occurred_at TEXT NOT NULL,
                        entity_type TEXT NOT NULL,
                        entity_id TEXT NOT NULL,
                        action TEXT NOT NULL,
                        correlation_id TEXT NOT NULL,
                        details TEXT NOT NULL
                    )
                    """
                )
                try execute("CREATE INDEX transactions_account_date ON transactions(account_id, booking_date, id)")
                try execute("CREATE UNIQUE INDEX transfer_account_side ON transactions(transfer_id, account_id) WHERE transfer_id IS NOT NULL")
                try execute("PRAGMA user_version = 1")

                let id = UUID()
                let now = Self.timestamp(Date())
                try run(
                    "INSERT INTO finance_files(id,name,base_currency,locale,time_zone,created_at,updated_at) VALUES(?,?,?,?,?,?,?)",
                    [.text(id.uuidString), .text("Meine Finanzen"), .text("EUR"), .text("de-DE"), .text(TimeZone.current.identifier), .text(now), .text(now)]
                )
                try seedCategories(financeFileID: id)
            }
        }
        if version < 2 {
            try transaction {
                try execute(
                    """
                    CREATE TABLE reconciliations (
                        id TEXT PRIMARY KEY,
                        account_id TEXT NOT NULL REFERENCES accounts(id),
                        statement_date TEXT NOT NULL,
                        ending_balance_minor INTEGER NOT NULL,
                        completed_at TEXT NOT NULL,
                        reverted_at TEXT
                    )
                    """
                )
                try execute("PRAGMA user_version = 2")
            }
        }
        if version < 3 {
            try transaction {
                try execute(
                    """
                    CREATE TABLE categorization_rules (
                        id TEXT PRIMARY KEY,
                        finance_file_id TEXT NOT NULL REFERENCES finance_files(id),
                        name TEXT NOT NULL,
                        priority INTEGER NOT NULL,
                        is_active INTEGER NOT NULL DEFAULT 1,
                        stop_after_match INTEGER NOT NULL DEFAULT 1,
                        payee_contains TEXT NOT NULL DEFAULT '',
                        purpose_contains TEXT NOT NULL DEFAULT '',
                        minimum_amount_minor INTEGER,
                        maximum_amount_minor INTEGER,
                        category_id TEXT NOT NULL REFERENCES categories(id),
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL,
                        version INTEGER NOT NULL DEFAULT 1
                    )
                    """
                )
                try execute("CREATE INDEX categorization_rules_priority ON categorization_rules(is_active,priority,id)")
                try execute("PRAGMA user_version = 3")
            }
        }
        if version < 4 {
            try transaction {
                try execute(
                    """
                    CREATE TABLE scheduled_transactions (
                        id TEXT PRIMARY KEY,
                        finance_file_id TEXT NOT NULL REFERENCES finance_files(id),
                        name TEXT NOT NULL,
                        account_id TEXT NOT NULL REFERENCES accounts(id),
                        payee TEXT NOT NULL DEFAULT '',
                        purpose TEXT NOT NULL DEFAULT '',
                        category_id TEXT REFERENCES categories(id),
                        amount_minor INTEGER NOT NULL,
                        currency TEXT NOT NULL,
                        next_due_date TEXT NOT NULL,
                        end_date TEXT,
                        frequency TEXT NOT NULL,
                        action TEXT NOT NULL,
                        reminder_days INTEGER NOT NULL DEFAULT 0,
                        is_active INTEGER NOT NULL DEFAULT 1,
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL,
                        version INTEGER NOT NULL DEFAULT 1
                    )
                    """
                )
                try execute("CREATE INDEX scheduled_transactions_due ON scheduled_transactions(is_active,next_due_date,id)")
                try execute("PRAGMA user_version = 4")
            }
        }
        if version < 5 {
            try transaction {
                try execute(
                    """
                    CREATE TABLE budgets (
                        id TEXT PRIMARY KEY,
                        finance_file_id TEXT NOT NULL REFERENCES finance_files(id),
                        name TEXT NOT NULL,
                        start_year INTEGER NOT NULL,
                        start_month INTEGER NOT NULL CHECK(start_month BETWEEN 1 AND 12),
                        currency TEXT NOT NULL,
                        is_active INTEGER NOT NULL DEFAULT 1,
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL,
                        version INTEGER NOT NULL DEFAULT 1
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE budget_lines (
                        id TEXT PRIMARY KEY,
                        budget_id TEXT NOT NULL REFERENCES budgets(id) ON DELETE CASCADE,
                        category_id TEXT NOT NULL REFERENCES categories(id),
                        year INTEGER NOT NULL,
                        month INTEGER NOT NULL CHECK(month BETWEEN 1 AND 12),
                        planned_minor INTEGER NOT NULL,
                        rollover_positive INTEGER NOT NULL DEFAULT 0,
                        rollover_negative INTEGER NOT NULL DEFAULT 0,
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL,
                        version INTEGER NOT NULL DEFAULT 1,
                        UNIQUE(budget_id,category_id,year,month)
                    )
                    """
                )
                try execute("CREATE INDEX budget_lines_period ON budget_lines(budget_id,year,month,category_id)")
                try execute("PRAGMA user_version = 5")
            }
        }
        if version < 6 {
            try transaction {
                try execute(
                    """
                    CREATE TABLE payment_orders (
                        id TEXT PRIMARY KEY,
                        finance_file_id TEXT NOT NULL REFERENCES finance_files(id),
                        account_id TEXT NOT NULL REFERENCES accounts(id),
                        type TEXT NOT NULL,
                        recipient_name TEXT NOT NULL,
                        iban TEXT NOT NULL,
                        bic TEXT NOT NULL DEFAULT '',
                        amount_minor INTEGER NOT NULL CHECK(amount_minor > 0),
                        currency TEXT NOT NULL,
                        execution_date TEXT NOT NULL,
                        purpose TEXT NOT NULL,
                        end_to_end_id TEXT NOT NULL,
                        status TEXT NOT NULL,
                        idempotency_key TEXT NOT NULL UNIQUE,
                        bank_reference TEXT NOT NULL DEFAULT '',
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL,
                        version INTEGER NOT NULL DEFAULT 1
                    )
                    """
                )
                try execute("CREATE INDEX payment_orders_status_date ON payment_orders(status,execution_date,id)")
                try execute("PRAGMA user_version = 6")
            }
        }
        if version < 7 {
            try transaction {
                try execute(
                    """
                    CREATE TABLE payees (
                        id TEXT PRIMARY KEY,
                        finance_file_id TEXT NOT NULL REFERENCES finance_files(id),
                        canonical_name TEXT NOT NULL,
                        address TEXT NOT NULL DEFAULT '',
                        email TEXT NOT NULL DEFAULT '',
                        phone TEXT NOT NULL DEFAULT '',
                        iban TEXT NOT NULL DEFAULT '',
                        bic TEXT NOT NULL DEFAULT '',
                        default_category_id TEXT REFERENCES categories(id),
                        preferred_account_id TEXT REFERENCES accounts(id),
                        note TEXT NOT NULL DEFAULT '',
                        is_active INTEGER NOT NULL DEFAULT 1,
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL,
                        version INTEGER NOT NULL DEFAULT 1,
                        UNIQUE(finance_file_id,canonical_name)
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE payee_aliases (
                        payee_id TEXT NOT NULL REFERENCES payees(id) ON DELETE CASCADE,
                        alias TEXT NOT NULL COLLATE NOCASE,
                        PRIMARY KEY(payee_id,alias)
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE tags (
                        id TEXT PRIMARY KEY,
                        finance_file_id TEXT NOT NULL REFERENCES finance_files(id),
                        parent_id TEXT REFERENCES tags(id),
                        name TEXT NOT NULL,
                        color TEXT NOT NULL DEFAULT 'blue',
                        description TEXT NOT NULL DEFAULT '',
                        is_active INTEGER NOT NULL DEFAULT 1,
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL,
                        version INTEGER NOT NULL DEFAULT 1,
                        UNIQUE(finance_file_id,parent_id,name)
                    )
                    """
                )
                try execute("ALTER TABLE transactions ADD COLUMN payee_id TEXT REFERENCES payees(id)")
                try execute(
                    """
                    CREATE TABLE transaction_tags (
                        transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
                        tag_id TEXT NOT NULL REFERENCES tags(id),
                        PRIMARY KEY(transaction_id,tag_id)
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE split_tags (
                        split_id TEXT NOT NULL REFERENCES transaction_splits(id) ON DELETE CASCADE,
                        tag_id TEXT NOT NULL REFERENCES tags(id),
                        PRIMARY KEY(split_id,tag_id)
                    )
                    """
                )
                try execute("PRAGMA user_version = 7")
            }
        }
        if version < 8 {
            try transaction {
                try execute(
                    """
                    CREATE TABLE securities (
                        id TEXT PRIMARY KEY,
                        finance_file_id TEXT NOT NULL REFERENCES finance_files(id),
                        name TEXT NOT NULL,
                        short_name TEXT NOT NULL DEFAULT '',
                        isin TEXT NOT NULL DEFAULT '',
                        wkn TEXT NOT NULL DEFAULT '',
                        ticker TEXT NOT NULL DEFAULT '',
                        type TEXT NOT NULL,
                        currency TEXT NOT NULL,
                        exchange TEXT NOT NULL DEFAULT '',
                        price_decimals INTEGER NOT NULL DEFAULT 4,
                        allows_short INTEGER NOT NULL DEFAULT 0,
                        is_active INTEGER NOT NULL DEFAULT 1,
                        note TEXT NOT NULL DEFAULT '',
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL,
                        version INTEGER NOT NULL DEFAULT 1
                    )
                    """
                )
                try execute("CREATE UNIQUE INDEX securities_isin ON securities(finance_file_id,isin) WHERE isin!=''")
                try execute(
                    """
                    CREATE TABLE asset_classes (
                        id TEXT PRIMARY KEY,
                        finance_file_id TEXT NOT NULL REFERENCES finance_files(id),
                        name TEXT NOT NULL,
                        color TEXT NOT NULL,
                        is_active INTEGER NOT NULL DEFAULT 1,
                        UNIQUE(finance_file_id,name)
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE security_allocations (
                        id TEXT PRIMARY KEY,
                        security_id TEXT NOT NULL REFERENCES securities(id) ON DELETE CASCADE,
                        asset_class_id TEXT NOT NULL REFERENCES asset_classes(id),
                        basis_points INTEGER NOT NULL CHECK(basis_points BETWEEN 0 AND 10000),
                        UNIQUE(security_id,asset_class_id)
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE security_trades (
                        id TEXT PRIMARY KEY,
                        account_id TEXT NOT NULL REFERENCES accounts(id),
                        security_id TEXT NOT NULL REFERENCES securities(id),
                        type TEXT NOT NULL,
                        trade_date TEXT NOT NULL,
                        quantity_micro INTEGER NOT NULL,
                        price_minor INTEGER NOT NULL,
                        fees_minor INTEGER NOT NULL,
                        taxes_minor INTEGER NOT NULL,
                        gross_minor INTEGER NOT NULL,
                        realized_gain_minor INTEGER NOT NULL,
                        currency TEXT NOT NULL,
                        note TEXT NOT NULL DEFAULT '',
                        created_at TEXT NOT NULL
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE portfolio_lots (
                        id TEXT PRIMARY KEY,
                        account_id TEXT NOT NULL REFERENCES accounts(id),
                        security_id TEXT NOT NULL REFERENCES securities(id),
                        acquisition_trade_id TEXT NOT NULL REFERENCES security_trades(id),
                        acquisition_date TEXT NOT NULL,
                        quantity_micro INTEGER NOT NULL CHECK(quantity_micro > 0),
                        remaining_quantity_micro INTEGER NOT NULL CHECK(remaining_quantity_micro >= 0),
                        total_cost_minor INTEGER NOT NULL,
                        remaining_cost_minor INTEGER NOT NULL,
                        currency TEXT NOT NULL
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE lot_disposals (
                        sale_trade_id TEXT NOT NULL REFERENCES security_trades(id),
                        lot_id TEXT NOT NULL REFERENCES portfolio_lots(id),
                        quantity_micro INTEGER NOT NULL,
                        allocated_cost_minor INTEGER NOT NULL,
                        PRIMARY KEY(sale_trade_id,lot_id)
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE security_prices (
                        security_id TEXT NOT NULL REFERENCES securities(id) ON DELETE CASCADE,
                        price_date TEXT NOT NULL,
                        price_minor INTEGER NOT NULL CHECK(price_minor >= 0),
                        currency TEXT NOT NULL,
                        source TEXT NOT NULL,
                        PRIMARY KEY(security_id,price_date,source)
                    )
                    """
                )
                let classSeeds = [
                    (UUID(), "Aktien", "blue"), (UUID(), "Anleihen", "green"),
                    (UUID(), "Liquidität", "teal"), (UUID(), "Immobilien", "orange"),
                    (UUID(), "Sonstiges", "gray")
                ]
                for seed in classSeeds {
                    try run(
                        """
                        INSERT INTO asset_classes(id,finance_file_id,name,color)
                        SELECT ?,id,?,? FROM finance_files LIMIT 1
                        """,
                        [.text(seed.0.uuidString), .text(seed.1), .text(seed.2)]
                    )
                }
                try execute("CREATE INDEX portfolio_lots_fifo ON portfolio_lots(account_id,security_id,acquisition_date,id)")
                try execute("PRAGMA user_version = 8")
            }
        }
        if version < 9 {
            try transaction {
                try execute(
                    """
                    CREATE TABLE loans (
                        id TEXT PRIMARY KEY,
                        finance_file_id TEXT NOT NULL REFERENCES finance_files(id),
                        name TEXT NOT NULL,
                        lender TEXT NOT NULL DEFAULT '',
                        principal_minor INTEGER NOT NULL CHECK(principal_minor > 0),
                        disbursement_date TEXT NOT NULL,
                        first_payment_date TEXT NOT NULL,
                        fixed_rate_until TEXT,
                        term_months INTEGER NOT NULL CHECK(term_months > 0),
                        installment_minor INTEGER NOT NULL CHECK(installment_minor > 0),
                        regular_fee_minor INTEGER NOT NULL DEFAULT 0 CHECK(regular_fee_minor >= 0),
                        due_day INTEGER NOT NULL CHECK(due_day BETWEEN 1 AND 31),
                        linked_account_id TEXT REFERENCES accounts(id),
                        currency TEXT NOT NULL,
                        note TEXT NOT NULL DEFAULT '',
                        is_active INTEGER NOT NULL DEFAULT 1,
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL,
                        version INTEGER NOT NULL DEFAULT 1
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE loan_interest_rates (
                        id TEXT PRIMARY KEY,
                        loan_id TEXT NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
                        annual_basis_points INTEGER NOT NULL
                            CHECK(annual_basis_points BETWEEN 0 AND 100000),
                        effective_from TEXT NOT NULL,
                        note TEXT NOT NULL DEFAULT '',
                        UNIQUE(loan_id,effective_from)
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE loan_extra_payments (
                        id TEXT PRIMARY KEY,
                        loan_id TEXT NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
                        payment_date TEXT NOT NULL,
                        amount_minor INTEGER NOT NULL CHECK(amount_minor > 0),
                        note TEXT NOT NULL DEFAULT ''
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE loan_payment_matches (
                        id TEXT PRIMARY KEY,
                        loan_id TEXT NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
                        transaction_id TEXT NOT NULL UNIQUE REFERENCES transactions(id),
                        scheduled_date TEXT NOT NULL,
                        principal_minor INTEGER NOT NULL,
                        interest_minor INTEGER NOT NULL,
                        fee_minor INTEGER NOT NULL,
                        matched_at TEXT NOT NULL,
                        UNIQUE(loan_id,scheduled_date)
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE property_assets (
                        id TEXT PRIMARY KEY,
                        finance_file_id TEXT NOT NULL REFERENCES finance_files(id),
                        name TEXT NOT NULL,
                        type TEXT NOT NULL,
                        purchase_date TEXT NOT NULL,
                        purchase_value_minor INTEGER NOT NULL CHECK(purchase_value_minor >= 0),
                        linked_loan_id TEXT REFERENCES loans(id),
                        location TEXT NOT NULL DEFAULT '',
                        note TEXT NOT NULL DEFAULT '',
                        is_active INTEGER NOT NULL DEFAULT 1,
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL,
                        version INTEGER NOT NULL DEFAULT 1
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE asset_valuations (
                        id TEXT PRIMARY KEY,
                        asset_id TEXT NOT NULL REFERENCES property_assets(id) ON DELETE CASCADE,
                        valuation_date TEXT NOT NULL,
                        value_minor INTEGER NOT NULL CHECK(value_minor >= 0),
                        source TEXT NOT NULL DEFAULT '',
                        note TEXT NOT NULL DEFAULT '',
                        UNIQUE(asset_id,valuation_date)
                    )
                    """
                )
                try execute("CREATE INDEX loan_rates_date ON loan_interest_rates(loan_id,effective_from)")
                try execute("CREATE INDEX loan_extras_date ON loan_extra_payments(loan_id,payment_date)")
                try execute("CREATE INDEX asset_values_date ON asset_valuations(asset_id,valuation_date)")
                try execute("PRAGMA user_version = 9")
            }
        }
        if version < 10 {
            try transaction {
                try execute(
                    """
                    CREATE TABLE contracts (
                        id TEXT PRIMARY KEY,
                        finance_file_id TEXT NOT NULL REFERENCES finance_files(id),
                        provider TEXT NOT NULL,
                        contract_number TEXT NOT NULL DEFAULT '',
                        name TEXT NOT NULL,
                        type TEXT NOT NULL,
                        start_date TEXT NOT NULL,
                        initial_term_months INTEGER NOT NULL CHECK(initial_term_months > 0),
                        renewal_months INTEGER NOT NULL DEFAULT 0 CHECK(renewal_months >= 0),
                        cancellation_notice_days INTEGER NOT NULL DEFAULT 0
                            CHECK(cancellation_notice_days >= 0),
                        amount_minor INTEGER NOT NULL CHECK(amount_minor >= 0),
                        frequency TEXT NOT NULL,
                        account_id TEXT REFERENCES accounts(id),
                        category_id TEXT REFERENCES categories(id),
                        reminder_days INTEGER NOT NULL DEFAULT 30 CHECK(reminder_days >= 0),
                        note TEXT NOT NULL DEFAULT '',
                        is_active INTEGER NOT NULL DEFAULT 1,
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL,
                        version INTEGER NOT NULL DEFAULT 1
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE contract_documents (
                        id TEXT PRIMARY KEY,
                        contract_id TEXT NOT NULL REFERENCES contracts(id) ON DELETE CASCADE,
                        name TEXT NOT NULL,
                        file_name TEXT NOT NULL,
                        bookmark_data BLOB,
                        added_at TEXT NOT NULL
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE inventory_items (
                        id TEXT PRIMARY KEY,
                        finance_file_id TEXT NOT NULL REFERENCES finance_files(id),
                        name TEXT NOT NULL,
                        category TEXT NOT NULL,
                        room TEXT NOT NULL DEFAULT '',
                        purchase_date TEXT,
                        purchase_price_minor INTEGER NOT NULL DEFAULT 0
                            CHECK(purchase_price_minor >= 0),
                        current_value_minor INTEGER NOT NULL DEFAULT 0
                            CHECK(current_value_minor >= 0),
                        insurance_value_minor INTEGER NOT NULL DEFAULT 0
                            CHECK(insurance_value_minor >= 0),
                        retailer TEXT NOT NULL DEFAULT '',
                        serial_number TEXT NOT NULL DEFAULT '',
                        warranty_end TEXT,
                        note TEXT NOT NULL DEFAULT '',
                        is_active INTEGER NOT NULL DEFAULT 1,
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL,
                        version INTEGER NOT NULL DEFAULT 1
                    )
                    """
                )
                try execute(
                    """
                    CREATE TABLE inventory_attachments (
                        id TEXT PRIMARY KEY,
                        item_id TEXT NOT NULL REFERENCES inventory_items(id) ON DELETE CASCADE,
                        kind TEXT NOT NULL,
                        file_name TEXT NOT NULL,
                        bookmark_data BLOB,
                        added_at TEXT NOT NULL
                    )
                    """
                )
                try execute("CREATE INDEX contracts_active_start ON contracts(is_active,start_date)")
                try execute("CREATE INDEX inventory_room ON inventory_items(room,name)")
                try execute("PRAGMA user_version = 10")
            }
        }
        if version < 11 {
            try transaction {
                try execute(
                    """
                    CREATE TABLE account_groups (
                        id TEXT PRIMARY KEY,
                        finance_file_id TEXT NOT NULL REFERENCES finance_files(id),
                        name TEXT NOT NULL,
                        sort_order INTEGER NOT NULL DEFAULT 0,
                        is_active INTEGER NOT NULL DEFAULT 1,
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL,
                        version INTEGER NOT NULL DEFAULT 1,
                        UNIQUE(finance_file_id,name)
                    )
                    """
                )
                try execute("ALTER TABLE accounts ADD COLUMN short_name TEXT NOT NULL DEFAULT ''")
                try execute("ALTER TABLE accounts ADD COLUMN description TEXT NOT NULL DEFAULT ''")
                try execute("ALTER TABLE accounts ADD COLUMN group_id TEXT REFERENCES account_groups(id)")
                try execute("ALTER TABLE accounts ADD COLUMN iban TEXT NOT NULL DEFAULT ''")
                try execute("ALTER TABLE accounts ADD COLUMN bic TEXT NOT NULL DEFAULT ''")
                try execute("ALTER TABLE accounts ADD COLUMN account_number_masked TEXT NOT NULL DEFAULT ''")
                try execute("ALTER TABLE accounts ADD COLUMN owner_name TEXT NOT NULL DEFAULT ''")
                try execute("ALTER TABLE accounts ADD COLUMN opening_date TEXT")
                try execute("ALTER TABLE accounts ADD COLUMN credit_limit_minor INTEGER NOT NULL DEFAULT 0")
                try execute("ALTER TABLE accounts ADD COLUMN is_online INTEGER NOT NULL DEFAULT 0")
                try execute("ALTER TABLE accounts ADD COLUMN include_net_worth INTEGER NOT NULL DEFAULT 1")
                try execute("ALTER TABLE accounts ADD COLUMN include_budget INTEGER NOT NULL DEFAULT 1")
                try execute("ALTER TABLE accounts ADD COLUMN include_reports INTEGER NOT NULL DEFAULT 1")
                try execute("ALTER TABLE accounts ADD COLUMN include_forecast INTEGER NOT NULL DEFAULT 1")
                try execute("ALTER TABLE accounts ADD COLUMN last_sync_at TEXT")
                try execute("ALTER TABLE accounts ADD COLUMN last_bank_balance_minor INTEGER")
                try execute("ALTER TABLE accounts ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'offline'")
                let now = Self.timestamp(Date())
                for (index, name) in ["Bankkonten", "Bargeld", "Vermögen", "Verbindlichkeiten"].enumerated() {
                    try run(
                        """
                        INSERT INTO account_groups(id,finance_file_id,name,sort_order,is_active,created_at,updated_at)
                        SELECT ?,id,?,?,1,?,? FROM finance_files LIMIT 1
                        """,
                        [
                            .text(UUID().uuidString), .text(name), .integer(Int64(index)),
                            .text(now), .text(now)
                        ]
                    )
                }
                try execute("CREATE INDEX accounts_group_sort ON accounts(group_id,sort_order,name)")
                try execute("PRAGMA user_version = 11")
            }
        }
        if version < 12 {
            try transaction {
                let groupNames = [
                    "Bankkonten", "Kreditkarten", "Bargeld", "Depots", "Kredite",
                    "Vermögen", "Verbindlichkeiten", "Forderungen", "Sonstige"
                ]
                let now = Self.timestamp(Date())
                for (index, name) in groupNames.enumerated() {
                    try run(
                        """
                        INSERT INTO account_groups(
                            id,finance_file_id,name,sort_order,is_active,created_at,updated_at
                        )
                        SELECT ?,id,?,?,1,?,? FROM finance_files LIMIT 1
                        ON CONFLICT(finance_file_id,name)
                        DO UPDATE SET sort_order=excluded.sort_order,is_active=1,
                                      updated_at=excluded.updated_at,version=version+1
                        """,
                        [
                            .text(UUID().uuidString), .text(name), .integer(Int64(index)),
                            .text(now), .text(now)
                        ]
                    )
                }
                try execute(
                    """
                    UPDATE accounts
                    SET group_id=(
                        SELECT id FROM account_groups
                        WHERE finance_file_id=accounts.finance_file_id
                          AND name=CASE
                            WHEN accounts.type IN (
                                'checking','savings','fixedDeposit','clearing','foreignCurrency'
                            ) THEN 'Bankkonten'
                            WHEN accounts.type='creditCard' THEN 'Kreditkarten'
                            WHEN accounts.type='cash' THEN 'Bargeld'
                            WHEN accounts.type='investment' THEN 'Depots'
                            WHEN accounts.type='loan' THEN 'Kredite'
                            WHEN accounts.type IN ('asset','inventory') THEN 'Vermögen'
                            WHEN accounts.type='liability' THEN 'Verbindlichkeiten'
                            WHEN accounts.type='receivable' THEN 'Forderungen'
                            ELSE 'Sonstige'
                          END
                        LIMIT 1
                    ),
                    updated_at='\(now)',
                    version=version+1
                    WHERE group_id IS NULL
                    """
                )
                try execute("PRAGMA user_version = 12")
            }
        }
        if version < 13 {
            try transaction {
                try execute(
                    """
                    CREATE TABLE report_templates (
                        id TEXT PRIMARY KEY,
                        finance_file_id TEXT NOT NULL REFERENCES finance_files(id) ON DELETE CASCADE,
                        name TEXT NOT NULL COLLATE NOCASE,
                        definition_version INTEGER NOT NULL,
                        query_json TEXT NOT NULL,
                        created_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL,
                        version INTEGER NOT NULL DEFAULT 1,
                        UNIQUE(finance_file_id,name)
                    )
                    """
                )
                try execute(
                    "CREATE INDEX report_templates_name ON report_templates(finance_file_id,name)"
                )
                try execute("PRAGMA user_version = 13")
            }
        }
    }

    func financeFileInfo() throws -> FinanceFileInfo {
        var result: FinanceFileInfo?
        try query("SELECT id,name,base_currency,locale,time_zone FROM finance_files LIMIT 1") { statement in
            guard let id = UUID(uuidString: Self.text(statement, 0)) else { return }
            result = FinanceFileInfo(
                id: id,
                name: Self.text(statement, 1),
                baseCurrency: Self.text(statement, 2),
                locale: Self.text(statement, 3),
                timeZone: Self.text(statement, 4)
            )
        }
        guard let result else { throw FinanceError.database("Finanzdatei-Kopf fehlt.") }
        return result
    }

    func accounts() throws -> [FinanceAccount] {
        var values: [FinanceAccount] = []
        try query(
            """
            SELECT id,name,institution,type,currency,opening_balance_minor,is_hidden,is_closed,sort_order,
                   short_name,description,group_id,iban,bic,account_number_masked,owner_name,
                   opening_date,credit_limit_minor,is_online,include_net_worth,include_budget,
                   include_reports,include_forecast,last_sync_at,last_bank_balance_minor,sync_status
            FROM accounts ORDER BY sort_order,name COLLATE NOCASE
            """
        ) { statement in
            guard
                let id = UUID(uuidString: Self.text(statement, 0)),
                let type = AccountType(rawValue: Self.text(statement, 3)),
                let syncStatus = AccountSyncStatus(rawValue: Self.text(statement, 25))
            else { return }
            values.append(
                FinanceAccount(
                    id: id,
                    name: Self.text(statement, 1),
                    institution: Self.text(statement, 2),
                    type: type,
                    currency: Self.text(statement, 4),
                    openingBalanceMinor: sqlite3_column_int64(statement, 5),
                    isHidden: sqlite3_column_int(statement, 6) != 0,
                    isClosed: sqlite3_column_int(statement, 7) != 0,
                    sortOrder: Int(sqlite3_column_int(statement, 8)),
                    shortName: Self.text(statement, 9),
                    description: Self.text(statement, 10),
                    groupID: Self.optionalText(statement, 11).flatMap(UUID.init(uuidString:)),
                    iban: Self.text(statement, 12),
                    bic: Self.text(statement, 13),
                    accountNumberMasked: Self.text(statement, 14),
                    ownerName: Self.text(statement, 15),
                    openingDate: Self.optionalText(statement, 16).flatMap(Self.date),
                    creditLimitMinor: sqlite3_column_int64(statement, 17),
                    isOnline: sqlite3_column_int(statement, 18) != 0,
                    includeNetWorth: sqlite3_column_int(statement, 19) != 0,
                    includeBudget: sqlite3_column_int(statement, 20) != 0,
                    includeReports: sqlite3_column_int(statement, 21) != 0,
                    includeForecast: sqlite3_column_int(statement, 22) != 0,
                    lastSyncAt: Self.optionalText(statement, 23).flatMap(Self.timestampDate),
                    lastBankBalanceMinor: sqlite3_column_type(statement, 24) == SQLITE_NULL
                        ? nil
                        : sqlite3_column_int64(statement, 24),
                    syncStatus: syncStatus
                )
            )
        }
        return values
    }

    func accountGroups() throws -> [AccountGroup] {
        var values: [AccountGroup] = []
        try query(
            "SELECT id,name,sort_order,is_active FROM account_groups ORDER BY sort_order,name COLLATE NOCASE"
        ) { statement in
            guard let id = UUID(uuidString: Self.text(statement, 0)) else { return }
            values.append(
                AccountGroup(
                    id: id, name: Self.text(statement, 1),
                    sortOrder: Int(sqlite3_column_int(statement, 2)),
                    isActive: sqlite3_column_int(statement, 3) != 0
                )
            )
        }
        return values
    }

    func categories() throws -> [FinanceCategory] {
        var values: [FinanceCategory] = []
        try query(
            "SELECT id,parent_id,name,kind,color,is_active FROM categories ORDER BY kind,name COLLATE NOCASE"
        ) { statement in
            guard
                let id = UUID(uuidString: Self.text(statement, 0)),
                let kind = CategoryKind(rawValue: Self.text(statement, 3))
            else { return }
            values.append(
                FinanceCategory(
                    id: id,
                    parentID: Self.optionalText(statement, 1).flatMap(UUID.init(uuidString:)),
                    name: Self.text(statement, 2),
                    kind: kind,
                    color: Self.text(statement, 4),
                    isActive: sqlite3_column_int(statement, 5) != 0
                )
            )
        }
        return values
    }

    func categorizationRules() throws -> [CategorizationRule] {
        var values: [CategorizationRule] = []
        try query(
            """
            SELECT id,name,priority,is_active,stop_after_match,payee_contains,purpose_contains,
                   minimum_amount_minor,maximum_amount_minor,category_id
            FROM categorization_rules ORDER BY priority,id
            """
        ) {
            guard
                let id = UUID(uuidString: Self.text($0, 0)),
                let categoryID = UUID(uuidString: Self.text($0, 9))
            else { return }
            values.append(
                CategorizationRule(
                    id: id,
                    name: Self.text($0, 1),
                    priority: Int(sqlite3_column_int($0, 2)),
                    isActive: sqlite3_column_int($0, 3) != 0,
                    stopAfterMatch: sqlite3_column_int($0, 4) != 0,
                    payeeContains: Self.text($0, 5),
                    purposeContains: Self.text($0, 6),
                    minimumAmountMinor: sqlite3_column_type($0, 7) == SQLITE_NULL
                        ? nil : sqlite3_column_int64($0, 7),
                    maximumAmountMinor: sqlite3_column_type($0, 8) == SQLITE_NULL
                        ? nil : sqlite3_column_int64($0, 8),
                    categoryID: categoryID
                )
            )
        }
        return values
    }

    func scheduledTransactions() throws -> [ScheduledTransaction] {
        var values: [ScheduledTransaction] = []
        try query(
            """
            SELECT id,name,account_id,payee,purpose,category_id,amount_minor,currency,
                   next_due_date,end_date,frequency,action,reminder_days,is_active
            FROM scheduled_transactions ORDER BY is_active DESC,next_due_date,name COLLATE NOCASE,id
            """
        ) {
            guard
                let id = UUID(uuidString: Self.text($0, 0)),
                let accountID = UUID(uuidString: Self.text($0, 2)),
                let nextDueDate = Self.date(Self.text($0, 8)),
                let frequency = RecurrenceFrequency(rawValue: Self.text($0, 10)),
                let action = ScheduledAction(rawValue: Self.text($0, 11))
            else { return }
            values.append(
                ScheduledTransaction(
                    id: id,
                    name: Self.text($0, 1),
                    accountID: accountID,
                    payee: Self.text($0, 3),
                    purpose: Self.text($0, 4),
                    categoryID: Self.optionalText($0, 5).flatMap(UUID.init(uuidString:)),
                    amountMinor: sqlite3_column_int64($0, 6),
                    currency: Self.text($0, 7),
                    nextDueDate: nextDueDate,
                    endDate: Self.optionalText($0, 9).flatMap(Self.date),
                    frequency: frequency,
                    action: action,
                    reminderDays: Int(sqlite3_column_int($0, 12)),
                    isActive: sqlite3_column_int($0, 13) != 0
                )
            )
        }
        return values
    }

    func saveScheduledTransaction(_ value: ScheduledTransaction) throws {
        guard !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FinanceError.database("Der Name des regelmäßigen Vorgangs fehlt.")
        }
        if let endDate = value.endDate, endDate < value.nextDueDate {
            throw FinanceError.database("Das Enddatum liegt vor der nächsten Fälligkeit.")
        }
        let info = try financeFileInfo()
        let now = Self.timestamp(Date())
        try transaction {
            try run(
                """
                INSERT INTO scheduled_transactions(
                    id,finance_file_id,name,account_id,payee,purpose,category_id,amount_minor,
                    currency,next_due_date,end_date,frequency,action,reminder_days,is_active,
                    created_at,updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET name=excluded.name,account_id=excluded.account_id,
                    payee=excluded.payee,purpose=excluded.purpose,category_id=excluded.category_id,
                    amount_minor=excluded.amount_minor,currency=excluded.currency,
                    next_due_date=excluded.next_due_date,end_date=excluded.end_date,
                    frequency=excluded.frequency,action=excluded.action,
                    reminder_days=excluded.reminder_days,is_active=excluded.is_active,
                    updated_at=excluded.updated_at,version=version+1
                """,
                [
                    .text(value.id.uuidString), .text(info.id.uuidString), .text(value.name),
                    .text(value.accountID.uuidString), .text(value.payee), .text(value.purpose),
                    value.categoryID.map { .text($0.uuidString) } ?? .null,
                    .integer(value.amountMinor), .text(value.currency),
                    .text(Self.day(value.nextDueDate)),
                    value.endDate.map { .text(Self.day($0)) } ?? .null,
                    .text(value.frequency.rawValue), .text(value.action.rawValue),
                    .integer(Int64(value.reminderDays)), .integer(value.isActive ? 1 : 0),
                    .text(now), .text(now)
                ]
            )
            try audit(entity: "scheduled_transaction", id: value.id, action: "save", details: value.name)
        }
    }

    func budgets() throws -> [FinanceBudget] {
        var values: [FinanceBudget] = []
        try query(
            """
            SELECT id,name,start_year,start_month,currency,is_active
            FROM budgets ORDER BY is_active DESC,start_year DESC,name COLLATE NOCASE,id
            """
        ) {
            guard let id = UUID(uuidString: Self.text($0, 0)) else { return }
            values.append(
                FinanceBudget(
                    id: id, name: Self.text($0, 1),
                    startYear: Int(sqlite3_column_int($0, 2)),
                    startMonth: Int(sqlite3_column_int($0, 3)),
                    currency: Self.text($0, 4),
                    isActive: sqlite3_column_int($0, 5) != 0
                )
            )
        }
        return values
    }

    func saveBudget(_ value: FinanceBudget) throws {
        guard !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FinanceError.database("Der Budgetname fehlt.")
        }
        guard (1...12).contains(value.startMonth) else {
            throw FinanceError.database("Der Startmonat ist ungültig.")
        }
        let info = try financeFileInfo()
        let now = Self.timestamp(Date())
        try transaction {
            try run(
                """
                INSERT INTO budgets(
                    id,finance_file_id,name,start_year,start_month,currency,is_active,created_at,updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET name=excluded.name,start_year=excluded.start_year,
                    start_month=excluded.start_month,currency=excluded.currency,
                    is_active=excluded.is_active,updated_at=excluded.updated_at,version=version+1
                """,
                [
                    .text(value.id.uuidString), .text(info.id.uuidString), .text(value.name),
                    .integer(Int64(value.startYear)), .integer(Int64(value.startMonth)),
                    .text(value.currency), .integer(value.isActive ? 1 : 0), .text(now), .text(now)
                ]
            )
            try audit(entity: "budget", id: value.id, action: "save", details: value.name)
        }
    }

    func budgetLines(budgetID: UUID, year: Int, month: Int) throws -> [BudgetLine] {
        var values: [BudgetLine] = []
        try query(
            """
            SELECT id,category_id,planned_minor,rollover_positive,rollover_negative
            FROM budget_lines WHERE budget_id=? AND year=? AND month=?
            ORDER BY category_id
            """,
            [.text(budgetID.uuidString), .integer(Int64(year)), .integer(Int64(month))]
        ) {
            guard
                let id = UUID(uuidString: Self.text($0, 0)),
                let categoryID = UUID(uuidString: Self.text($0, 1))
            else { return }
            values.append(
                BudgetLine(
                    id: id, budgetID: budgetID, categoryID: categoryID,
                    year: year, month: month, plannedMinor: sqlite3_column_int64($0, 2),
                    rolloverPositive: sqlite3_column_int($0, 3) != 0,
                    rolloverNegative: sqlite3_column_int($0, 4) != 0
                )
            )
        }
        return values
    }

    func saveBudgetLine(_ value: BudgetLine) throws {
        guard (1...12).contains(value.month) else {
            throw FinanceError.database("Der Budgetmonat ist ungültig.")
        }
        let now = Self.timestamp(Date())
        try transaction {
            try run(
                """
                INSERT INTO budget_lines(
                    id,budget_id,category_id,year,month,planned_minor,
                    rollover_positive,rollover_negative,created_at,updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(budget_id,category_id,year,month) DO UPDATE SET
                    planned_minor=excluded.planned_minor,
                    rollover_positive=excluded.rollover_positive,
                    rollover_negative=excluded.rollover_negative,
                    updated_at=excluded.updated_at,version=version+1
                """,
                [
                    .text(value.id.uuidString), .text(value.budgetID.uuidString),
                    .text(value.categoryID.uuidString), .integer(Int64(value.year)),
                    .integer(Int64(value.month)), .integer(value.plannedMinor),
                    .integer(value.rolloverPositive ? 1 : 0),
                    .integer(value.rolloverNegative ? 1 : 0), .text(now), .text(now)
                ]
            )
            try audit(entity: "budget_line", id: value.id, action: "save", details: "\(value.year)-\(value.month)")
        }
    }

    func paymentOrders() throws -> [PaymentOrder] {
        var values: [PaymentOrder] = []
        try query(
            """
            SELECT id,account_id,type,recipient_name,iban,bic,amount_minor,currency,
                   execution_date,purpose,end_to_end_id,status,idempotency_key,
                   bank_reference,created_at,updated_at
            FROM payment_orders ORDER BY created_at DESC,id DESC
            """
        ) {
            guard
                let id = UUID(uuidString: Self.text($0, 0)),
                let accountID = UUID(uuidString: Self.text($0, 1)),
                let type = PaymentType(rawValue: Self.text($0, 2)),
                let executionDate = Self.date(Self.text($0, 8)),
                let status = PaymentStatus(rawValue: Self.text($0, 11)),
                let createdAt = Self.timestampDate(Self.text($0, 14)),
                let updatedAt = Self.timestampDate(Self.text($0, 15))
            else { return }
            values.append(
                PaymentOrder(
                    id: id, accountID: accountID, type: type,
                    recipientName: Self.text($0, 3), iban: Self.text($0, 4),
                    bic: Self.text($0, 5), amountMinor: sqlite3_column_int64($0, 6),
                    currency: Self.text($0, 7), executionDate: executionDate,
                    purpose: Self.text($0, 9), endToEndID: Self.text($0, 10),
                    status: status, idempotencyKey: Self.text($0, 12),
                    bankReference: Self.text($0, 13),
                    createdAt: createdAt, updatedAt: updatedAt
                )
            )
        }
        return values
    }

    func tags() throws -> [FinanceTag] {
        var values: [FinanceTag] = []
        try query(
            """
            SELECT id,parent_id,name,color,description,is_active
            FROM tags ORDER BY name COLLATE NOCASE,id
            """
        ) {
            guard let id = UUID(uuidString: Self.text($0, 0)) else { return }
            values.append(
                FinanceTag(
                    id: id,
                    parentID: Self.optionalText($0, 1).flatMap(UUID.init(uuidString:)),
                    name: Self.text($0, 2), color: Self.text($0, 3),
                    description: Self.text($0, 4),
                    isActive: sqlite3_column_int($0, 5) != 0
                )
            )
        }
        return values
    }

    func saveTag(_ value: FinanceTag) throws {
        let name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FinanceError.database("Der Tagname fehlt.") }
        let info = try financeFileInfo()
        let now = Self.timestamp(Date())
        try transaction {
            try run(
                """
                INSERT INTO tags(
                    id,finance_file_id,parent_id,name,color,description,is_active,created_at,updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET parent_id=excluded.parent_id,name=excluded.name,
                    color=excluded.color,description=excluded.description,
                    is_active=excluded.is_active,updated_at=excluded.updated_at,version=version+1
                """,
                [
                    .text(value.id.uuidString), .text(info.id.uuidString),
                    value.parentID.map { .text($0.uuidString) } ?? .null,
                    .text(name), .text(value.color), .text(value.description),
                    .integer(value.isActive ? 1 : 0), .text(now), .text(now)
                ]
            )
            try audit(entity: "tag", id: value.id, action: "save", details: name)
        }
    }

    func payees() throws -> [FinancePayee] {
        var values: [FinancePayee] = []
        try query(
            """
            SELECT id,canonical_name,address,email,phone,iban,bic,
                   default_category_id,preferred_account_id,note,is_active
            FROM payees ORDER BY canonical_name COLLATE NOCASE,id
            """
        ) {
            guard let id = UUID(uuidString: Self.text($0, 0)) else { return }
            var aliases: [String] = []
            try? query(
                "SELECT alias FROM payee_aliases WHERE payee_id=? ORDER BY alias COLLATE NOCASE",
                [.text(id.uuidString)]
            ) { aliases.append(Self.text($0, 0)) }
            values.append(
                FinancePayee(
                    id: id, canonicalName: Self.text($0, 1), aliases: aliases,
                    address: Self.text($0, 2), email: Self.text($0, 3),
                    phone: Self.text($0, 4), iban: Self.text($0, 5),
                    bic: Self.text($0, 6),
                    defaultCategoryID: Self.optionalText($0, 7).flatMap(UUID.init(uuidString:)),
                    preferredAccountID: Self.optionalText($0, 8).flatMap(UUID.init(uuidString:)),
                    note: Self.text($0, 9), isActive: sqlite3_column_int($0, 10) != 0
                )
            )
        }
        return values
    }

    func savePayee(_ value: FinancePayee) throws {
        let name = value.canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FinanceError.database("Der Empfängername fehlt.") }
        if !value.iban.isEmpty, !IBANValidator.isValid(value.iban) {
            throw FinanceError.invalidIBAN
        }
        let info = try financeFileInfo()
        let now = Self.timestamp(Date())
        try transaction {
            try run(
                """
                INSERT INTO payees(
                    id,finance_file_id,canonical_name,address,email,phone,iban,bic,
                    default_category_id,preferred_account_id,note,is_active,created_at,updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET canonical_name=excluded.canonical_name,
                    address=excluded.address,email=excluded.email,phone=excluded.phone,
                    iban=excluded.iban,bic=excluded.bic,
                    default_category_id=excluded.default_category_id,
                    preferred_account_id=excluded.preferred_account_id,note=excluded.note,
                    is_active=excluded.is_active,updated_at=excluded.updated_at,version=version+1
                """,
                [
                    .text(value.id.uuidString), .text(info.id.uuidString), .text(name),
                    .text(value.address), .text(value.email), .text(value.phone),
                    .text(IBANValidator.normalized(value.iban)), .text(value.bic.uppercased()),
                    value.defaultCategoryID.map { .text($0.uuidString) } ?? .null,
                    value.preferredAccountID.map { .text($0.uuidString) } ?? .null,
                    .text(value.note), .integer(value.isActive ? 1 : 0),
                    .text(now), .text(now)
                ]
            )
            try run("DELETE FROM payee_aliases WHERE payee_id=?", [.text(value.id.uuidString)])
            for alias in Set(value.aliases.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }) {
                try run(
                    "INSERT INTO payee_aliases(payee_id,alias) VALUES(?,?)",
                    [.text(value.id.uuidString), .text(alias)]
                )
            }
            try audit(entity: "payee", id: value.id, action: "save", details: name)
        }
    }

    func securities() throws -> [Security] {
        var values: [Security] = []
        try query(
            """
            SELECT id,name,short_name,isin,wkn,ticker,type,currency,exchange,
                   price_decimals,allows_short,is_active,note
            FROM securities ORDER BY name COLLATE NOCASE,id
            """
        ) {
            guard
                let id = UUID(uuidString: Self.text($0, 0)),
                let type = SecurityType(rawValue: Self.text($0, 6))
            else { return }
            values.append(
                Security(
                    id: id, name: Self.text($0, 1), shortName: Self.text($0, 2),
                    isin: Self.text($0, 3), wkn: Self.text($0, 4),
                    ticker: Self.text($0, 5), type: type,
                    currency: Self.text($0, 7), exchange: Self.text($0, 8),
                    priceDecimals: Int(sqlite3_column_int($0, 9)),
                    allowsShort: sqlite3_column_int($0, 10) != 0,
                    isActive: sqlite3_column_int($0, 11) != 0,
                    note: Self.text($0, 12)
                )
            )
        }
        return values
    }

    func saveSecurity(_ value: Security) throws {
        let name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FinanceError.database("Der Wertpapiername fehlt.") }
        let info = try financeFileInfo()
        let now = Self.timestamp(Date())
        try transaction {
            try run(
                """
                INSERT INTO securities(
                    id,finance_file_id,name,short_name,isin,wkn,ticker,type,currency,
                    exchange,price_decimals,allows_short,is_active,note,created_at,updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET name=excluded.name,short_name=excluded.short_name,
                    isin=excluded.isin,wkn=excluded.wkn,ticker=excluded.ticker,type=excluded.type,
                    currency=excluded.currency,exchange=excluded.exchange,
                    price_decimals=excluded.price_decimals,allows_short=excluded.allows_short,
                    is_active=excluded.is_active,note=excluded.note,
                    updated_at=excluded.updated_at,version=version+1
                """,
                [
                    .text(value.id.uuidString), .text(info.id.uuidString), .text(name),
                    .text(value.shortName), .text(value.isin.uppercased()),
                    .text(value.wkn.uppercased()), .text(value.ticker.uppercased()),
                    .text(value.type.rawValue), .text(value.currency.uppercased()),
                    .text(value.exchange), .integer(Int64(value.priceDecimals)),
                    .integer(value.allowsShort ? 1 : 0), .integer(value.isActive ? 1 : 0),
                    .text(value.note), .text(now), .text(now)
                ]
            )
            try audit(entity: "security", id: value.id, action: "save", details: name)
        }
    }

    func assetClasses() throws -> [AssetClass] {
        var values: [AssetClass] = []
        try query(
            "SELECT id,name,color,is_active FROM asset_classes ORDER BY name COLLATE NOCASE,id"
        ) {
            guard let id = UUID(uuidString: Self.text($0, 0)) else { return }
            values.append(
                AssetClass(
                    id: id, name: Self.text($0, 1), color: Self.text($0, 2),
                    isActive: sqlite3_column_int($0, 3) != 0
                )
            )
        }
        return values
    }

    func allocations(securityID: UUID) throws -> [SecurityAllocation] {
        var values: [SecurityAllocation] = []
        try query(
            """
            SELECT id,asset_class_id,basis_points FROM security_allocations
            WHERE security_id=? ORDER BY asset_class_id
            """,
            [.text(securityID.uuidString)]
        ) {
            guard
                let id = UUID(uuidString: Self.text($0, 0)),
                let classID = UUID(uuidString: Self.text($0, 1))
            else { return }
            values.append(
                SecurityAllocation(
                    id: id, securityID: securityID,
                    assetClassID: classID,
                    basisPoints: Int(sqlite3_column_int($0, 2))
                )
            )
        }
        return values
    }

    func replaceAllocations(
        securityID: UUID,
        values: [(assetClassID: UUID, basisPoints: Int)]
    ) throws {
        let sum = values.reduce(0) { $0 + $1.basisPoints }
        guard sum == 10_000 else { throw FinanceError.allocationMismatch(sum) }
        guard values.allSatisfy({ (0...10_000).contains($0.basisPoints) }) else {
            throw FinanceError.allocationMismatch(sum)
        }
        try transaction {
            try run(
                "DELETE FROM security_allocations WHERE security_id=?",
                [.text(securityID.uuidString)]
            )
            for value in values where value.basisPoints > 0 {
                try run(
                    """
                    INSERT INTO security_allocations(id,security_id,asset_class_id,basis_points)
                    VALUES(?,?,?,?)
                    """,
                    [
                        .text(UUID().uuidString), .text(securityID.uuidString),
                        .text(value.assetClassID.uuidString),
                        .integer(Int64(value.basisPoints))
                    ]
                )
            }
            try audit(
                entity: "security", id: securityID, action: "allocation",
                details: values.map { "\($0.assetClassID.uuidString):\($0.basisPoints)" }.joined(separator: ",")
            )
        }
    }

    func recordPurchase(
        accountID: UUID,
        securityID: UUID,
        date: Date,
        quantityMicro: Int64,
        priceMinor: Int64,
        feesMinor: Int64,
        taxesMinor: Int64 = 0,
        note: String = ""
    ) throws {
        guard quantityMicro > 0, priceMinor >= 0, feesMinor >= 0, taxesMinor >= 0 else {
            throw FinanceError.database("Kaufwerte müssen positiv sein.")
        }
        let security = try securities().first { $0.id == securityID }
        guard let security else { throw FinanceError.database("Wertpapier fehlt.") }
        let gross = Self.scaledProduct(quantityMicro, priceMinor)
        let totalCost = gross + feesMinor + taxesMinor
        let tradeID = UUID()
        let lotID = UUID()
        let now = Self.timestamp(Date())
        try transaction {
            try run(
                """
                INSERT INTO security_trades(
                    id,account_id,security_id,type,trade_date,quantity_micro,price_minor,
                    fees_minor,taxes_minor,gross_minor,realized_gain_minor,currency,note,created_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
                [
                    .text(tradeID.uuidString), .text(accountID.uuidString),
                    .text(securityID.uuidString), .text(SecurityTradeType.buy.rawValue),
                    .text(Self.day(date)), .integer(quantityMicro), .integer(priceMinor),
                    .integer(feesMinor), .integer(taxesMinor), .integer(gross),
                    .integer(0), .text(security.currency), .text(note), .text(now)
                ]
            )
            try run(
                """
                INSERT INTO portfolio_lots(
                    id,account_id,security_id,acquisition_trade_id,acquisition_date,
                    quantity_micro,remaining_quantity_micro,total_cost_minor,
                    remaining_cost_minor,currency
                ) VALUES(?,?,?,?,?,?,?,?,?,?)
                """,
                [
                    .text(lotID.uuidString), .text(accountID.uuidString),
                    .text(securityID.uuidString), .text(tradeID.uuidString),
                    .text(Self.day(date)), .integer(quantityMicro), .integer(quantityMicro),
                    .integer(totalCost), .integer(totalCost), .text(security.currency)
                ]
            )
            try audit(entity: "security_trade", id: tradeID, action: "buy", details: "\(quantityMicro)")
        }
    }

    func recordSale(
        accountID: UUID,
        securityID: UUID,
        date: Date,
        quantityMicro: Int64,
        priceMinor: Int64,
        feesMinor: Int64,
        taxesMinor: Int64 = 0,
        note: String = ""
    ) throws {
        guard quantityMicro > 0, priceMinor >= 0, feesMinor >= 0, taxesMinor >= 0 else {
            throw FinanceError.database("Verkaufswerte müssen positiv sein.")
        }
        let security = try securities().first { $0.id == securityID }
        guard let security else { throw FinanceError.database("Wertpapier fehlt.") }
        let lots = try portfolioLots(accountID: accountID, securityID: securityID)
            .filter { $0.remainingQuantityMicro > 0 }
        let available = lots.reduce(Int64.zero) { $0 + $1.remainingQuantityMicro }
        guard available >= quantityMicro else { throw FinanceError.insufficientQuantity }
        let gross = Self.scaledProduct(quantityMicro, priceMinor)
        let net = gross - feesMinor - taxesMinor
        var remainingToSell = quantityMicro
        var disposals: [(PortfolioLot, Int64, Int64)] = []
        var totalAllocatedCost: Int64 = 0
        for lot in lots where remainingToSell > 0 {
            let consumed = min(remainingToSell, lot.remainingQuantityMicro)
            let allocatedCost = consumed == lot.remainingQuantityMicro
                ? lot.remainingCostMinor
                : Self.scaledRatio(
                    lot.remainingCostMinor, numerator: consumed,
                    denominator: lot.remainingQuantityMicro
                )
            disposals.append((lot, consumed, allocatedCost))
            totalAllocatedCost += allocatedCost
            remainingToSell -= consumed
        }
        let tradeID = UUID()
        let now = Self.timestamp(Date())
        try transaction {
            try run(
                """
                INSERT INTO security_trades(
                    id,account_id,security_id,type,trade_date,quantity_micro,price_minor,
                    fees_minor,taxes_minor,gross_minor,realized_gain_minor,currency,note,created_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
                [
                    .text(tradeID.uuidString), .text(accountID.uuidString),
                    .text(securityID.uuidString), .text(SecurityTradeType.sell.rawValue),
                    .text(Self.day(date)), .integer(-quantityMicro), .integer(priceMinor),
                    .integer(feesMinor), .integer(taxesMinor), .integer(gross),
                    .integer(net - totalAllocatedCost), .text(security.currency),
                    .text(note), .text(now)
                ]
            )
            for disposal in disposals {
                try run(
                    """
                    UPDATE portfolio_lots SET remaining_quantity_micro=?,
                        remaining_cost_minor=? WHERE id=?
                    """,
                    [
                        .integer(disposal.0.remainingQuantityMicro - disposal.1),
                        .integer(disposal.0.remainingCostMinor - disposal.2),
                        .text(disposal.0.id.uuidString)
                    ]
                )
                try run(
                    """
                    INSERT INTO lot_disposals(
                        sale_trade_id,lot_id,quantity_micro,allocated_cost_minor
                    ) VALUES(?,?,?,?)
                    """,
                    [
                        .text(tradeID.uuidString), .text(disposal.0.id.uuidString),
                        .integer(disposal.1), .integer(disposal.2)
                    ]
                )
            }
            try audit(entity: "security_trade", id: tradeID, action: "sell_fifo", details: "\(quantityMicro)")
        }
    }

    func saveSecurityPrice(
        securityID: UUID,
        date: Date,
        priceMinor: Int64,
        currency: String,
        source: String
    ) throws {
        guard priceMinor >= 0 else { throw FinanceError.database("Der Kurs darf nicht negativ sein.") }
        try transaction {
            try run(
                """
                INSERT INTO security_prices(security_id,price_date,price_minor,currency,source)
                VALUES(?,?,?,?,?)
                ON CONFLICT(security_id,price_date,source) DO UPDATE SET
                    price_minor=excluded.price_minor,currency=excluded.currency
                """,
                [
                    .text(securityID.uuidString), .text(Self.day(date)),
                    .integer(priceMinor), .text(currency), .text(source)
                ]
            )
            try audit(entity: "security", id: securityID, action: "price", details: "\(priceMinor)")
        }
    }

    func portfolioLots(accountID: UUID? = nil, securityID: UUID? = nil) throws -> [PortfolioLot] {
        var clauses: [String] = []
        var bindings: [SQLiteValue] = []
        if let accountID {
            clauses.append("account_id=?")
            bindings.append(.text(accountID.uuidString))
        }
        if let securityID {
            clauses.append("security_id=?")
            bindings.append(.text(securityID.uuidString))
        }
        var values: [PortfolioLot] = []
        try query(
            """
            SELECT id,account_id,security_id,acquisition_trade_id,acquisition_date,
                   quantity_micro,remaining_quantity_micro,total_cost_minor,
                   remaining_cost_minor,currency
            FROM portfolio_lots
            \(clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND "))
            ORDER BY acquisition_date,id
            """,
            bindings
        ) {
            guard
                let id = UUID(uuidString: Self.text($0, 0)),
                let accountID = UUID(uuidString: Self.text($0, 1)),
                let securityID = UUID(uuidString: Self.text($0, 2)),
                let tradeID = UUID(uuidString: Self.text($0, 3)),
                let date = Self.date(Self.text($0, 4))
            else { return }
            values.append(
                PortfolioLot(
                    id: id, accountID: accountID, securityID: securityID,
                    acquisitionTradeID: tradeID, acquisitionDate: date,
                    quantityMicro: sqlite3_column_int64($0, 5),
                    remainingQuantityMicro: sqlite3_column_int64($0, 6),
                    totalCostMinor: sqlite3_column_int64($0, 7),
                    remainingCostMinor: sqlite3_column_int64($0, 8),
                    currency: Self.text($0, 9)
                )
            )
        }
        return values
    }

    func securityTrades() throws -> [SecurityTrade] {
        var values: [SecurityTrade] = []
        try query(
            """
            SELECT id,account_id,security_id,type,trade_date,quantity_micro,price_minor,
                   fees_minor,taxes_minor,gross_minor,realized_gain_minor,currency,note
            FROM security_trades ORDER BY trade_date DESC,id DESC
            """
        ) {
            guard
                let id = UUID(uuidString: Self.text($0, 0)),
                let accountID = UUID(uuidString: Self.text($0, 1)),
                let securityID = UUID(uuidString: Self.text($0, 2)),
                let type = SecurityTradeType(rawValue: Self.text($0, 3)),
                let date = Self.date(Self.text($0, 4))
            else { return }
            values.append(
                SecurityTrade(
                    id: id, accountID: accountID, securityID: securityID,
                    type: type, tradeDate: date,
                    quantityMicro: sqlite3_column_int64($0, 5),
                    priceMinor: sqlite3_column_int64($0, 6),
                    feesMinor: sqlite3_column_int64($0, 7),
                    taxesMinor: sqlite3_column_int64($0, 8),
                    grossMinor: sqlite3_column_int64($0, 9),
                    realizedGainMinor: sqlite3_column_int64($0, 10),
                    currency: Self.text($0, 11), note: Self.text($0, 12)
                )
            )
        }
        return values
    }

    func portfolioPositions() throws -> [PortfolioPosition] {
        let securitiesByID = Dictionary(uniqueKeysWithValues: try securities().map { ($0.id, $0) })
        var values: [PortfolioPosition] = []
        try query(
            """
            SELECT account_id,security_id,SUM(remaining_quantity_micro),
                   SUM(remaining_cost_minor)
            FROM portfolio_lots GROUP BY account_id,security_id
            HAVING SUM(remaining_quantity_micro) != 0
            ORDER BY account_id,security_id
            """
        ) {
            guard
                let accountID = UUID(uuidString: Self.text($0, 0)),
                let securityID = UUID(uuidString: Self.text($0, 1)),
                let security = securitiesByID[securityID]
            else { return }
            var latestPrice: Int64?
            try? query(
                """
                SELECT price_minor FROM security_prices WHERE security_id=?
                ORDER BY price_date DESC,source LIMIT 1
                """,
                [.text(securityID.uuidString)]
            ) { latestPrice = sqlite3_column_int64($0, 0) }
            values.append(
                PortfolioPosition(
                    security: security, accountID: accountID,
                    quantityMicro: sqlite3_column_int64($0, 2),
                    costBasisMinor: sqlite3_column_int64($0, 3),
                    latestPriceMinor: latestPrice
                )
            )
        }
        return values
    }

    func loans() throws -> [FinanceLoan] {
        var values: [FinanceLoan] = []
        try query(
            """
            SELECT id,name,lender,principal_minor,disbursement_date,first_payment_date,
                   fixed_rate_until,term_months,installment_minor,regular_fee_minor,
                   due_day,linked_account_id,currency,note,is_active
            FROM loans ORDER BY is_active DESC,name COLLATE NOCASE,id
            """
        ) {
            guard
                let id = UUID(uuidString: Self.text($0, 0)),
                let disbursementDate = Self.date(Self.text($0, 4)),
                let firstPaymentDate = Self.date(Self.text($0, 5))
            else { return }
            values.append(
                FinanceLoan(
                    id: id, name: Self.text($0, 1), lender: Self.text($0, 2),
                    principalMinor: sqlite3_column_int64($0, 3),
                    disbursementDate: disbursementDate,
                    firstPaymentDate: firstPaymentDate,
                    fixedRateUntil: Self.optionalText($0, 6).flatMap(Self.date),
                    termMonths: Int(sqlite3_column_int($0, 7)),
                    installmentMinor: sqlite3_column_int64($0, 8),
                    regularFeeMinor: sqlite3_column_int64($0, 9),
                    dueDay: Int(sqlite3_column_int($0, 10)),
                    linkedAccountID: Self.optionalText($0, 11).flatMap(UUID.init(uuidString:)),
                    currency: Self.text($0, 12), note: Self.text($0, 13),
                    isActive: sqlite3_column_int($0, 14) != 0
                )
            )
        }
        return values
    }

    func saveLoan(_ value: FinanceLoan) throws {
        try value.validate()
        let info = try financeFileInfo()
        let now = Self.timestamp(Date())
        try transaction {
            try run(
                """
                INSERT INTO loans(
                    id,finance_file_id,name,lender,principal_minor,disbursement_date,
                    first_payment_date,fixed_rate_until,term_months,installment_minor,
                    regular_fee_minor,due_day,linked_account_id,currency,note,is_active,
                    created_at,updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET name=excluded.name,lender=excluded.lender,
                    principal_minor=excluded.principal_minor,
                    disbursement_date=excluded.disbursement_date,
                    first_payment_date=excluded.first_payment_date,
                    fixed_rate_until=excluded.fixed_rate_until,
                    term_months=excluded.term_months,
                    installment_minor=excluded.installment_minor,
                    regular_fee_minor=excluded.regular_fee_minor,
                    due_day=excluded.due_day,
                    linked_account_id=excluded.linked_account_id,
                    currency=excluded.currency,note=excluded.note,
                    is_active=excluded.is_active,updated_at=excluded.updated_at,
                    version=version+1
                """,
                [
                    .text(value.id.uuidString), .text(info.id.uuidString),
                    .text(value.name.trimmingCharacters(in: .whitespacesAndNewlines)),
                    .text(value.lender), .integer(value.principalMinor),
                    .text(Self.day(value.disbursementDate)),
                    .text(Self.day(value.firstPaymentDate)),
                    value.fixedRateUntil.map { .text(Self.day($0)) } ?? .null,
                    .integer(Int64(value.termMonths)), .integer(value.installmentMinor),
                    .integer(value.regularFeeMinor), .integer(Int64(value.dueDay)),
                    value.linkedAccountID.map { .text($0.uuidString) } ?? .null,
                    .text(value.currency.uppercased()), .text(value.note),
                    .integer(value.isActive ? 1 : 0), .text(now), .text(now)
                ]
            )
            try audit(entity: "loan", id: value.id, action: "save", details: value.name)
        }
    }

    func loanInterestRates(loanID: UUID) throws -> [LoanInterestRate] {
        var values: [LoanInterestRate] = []
        try query(
            """
            SELECT id,annual_basis_points,effective_from,note
            FROM loan_interest_rates WHERE loan_id=?
            ORDER BY effective_from,id
            """,
            [.text(loanID.uuidString)]
        ) {
            guard
                let id = UUID(uuidString: Self.text($0, 0)),
                let effectiveFrom = Self.date(Self.text($0, 2))
            else { return }
            values.append(
                LoanInterestRate(
                    id: id, loanID: loanID,
                    annualBasisPoints: Int(sqlite3_column_int($0, 1)),
                    effectiveFrom: effectiveFrom, note: Self.text($0, 3)
                )
            )
        }
        return values
    }

    func saveLoanInterestRate(_ value: LoanInterestRate) throws {
        guard (0...100_000).contains(value.annualBasisPoints) else {
            throw FinanceError.invalidLoanTerms("Der Zinssatz liegt außerhalb des zulässigen Bereichs.")
        }
        try transaction {
            try run(
                """
                INSERT INTO loan_interest_rates(
                    id,loan_id,annual_basis_points,effective_from,note
                ) VALUES(?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET annual_basis_points=excluded.annual_basis_points,
                    effective_from=excluded.effective_from,note=excluded.note
                """,
                [
                    .text(value.id.uuidString), .text(value.loanID.uuidString),
                    .integer(Int64(value.annualBasisPoints)),
                    .text(Self.day(value.effectiveFrom)), .text(value.note)
                ]
            )
            try audit(
                entity: "loan_rate", id: value.id, action: "save",
                details: "\(value.annualBasisPoints)"
            )
        }
    }

    func loanExtraPayments(loanID: UUID) throws -> [LoanExtraPayment] {
        var values: [LoanExtraPayment] = []
        try query(
            """
            SELECT id,payment_date,amount_minor,note
            FROM loan_extra_payments WHERE loan_id=?
            ORDER BY payment_date,id
            """,
            [.text(loanID.uuidString)]
        ) {
            guard
                let id = UUID(uuidString: Self.text($0, 0)),
                let date = Self.date(Self.text($0, 1))
            else { return }
            values.append(
                LoanExtraPayment(
                    id: id, loanID: loanID, paymentDate: date,
                    amountMinor: sqlite3_column_int64($0, 2), note: Self.text($0, 3)
                )
            )
        }
        return values
    }

    func saveLoanExtraPayment(_ value: LoanExtraPayment) throws {
        guard value.amountMinor > 0 else {
            throw FinanceError.invalidLoanTerms("Eine Sondertilgung muss positiv sein.")
        }
        try transaction {
            try run(
                """
                INSERT INTO loan_extra_payments(id,loan_id,payment_date,amount_minor,note)
                VALUES(?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET payment_date=excluded.payment_date,
                    amount_minor=excluded.amount_minor,note=excluded.note
                """,
                [
                    .text(value.id.uuidString), .text(value.loanID.uuidString),
                    .text(Self.day(value.paymentDate)), .integer(value.amountMinor),
                    .text(value.note)
                ]
            )
            try audit(
                entity: "loan_extra_payment", id: value.id, action: "save",
                details: "\(value.amountMinor)"
            )
        }
    }

    func loanSchedule(loanID: UUID) throws -> [LoanScheduleEntry] {
        guard let loan = try loans().first(where: { $0.id == loanID }) else {
            throw FinanceError.database("Darlehen nicht gefunden.")
        }
        return try LoanAmortizationEngine.schedule(
            loan: loan,
            rates: loanInterestRates(loanID: loanID),
            extraPayments: loanExtraPayments(loanID: loanID)
        )
    }

    func loanBalanceMinor(loanID: UUID, asOf date: Date = Date()) throws -> Int64 {
        guard let loan = try loans().first(where: { $0.id == loanID }) else {
            throw FinanceError.database("Darlehen nicht gefunden.")
        }
        let entries = try loanSchedule(loanID: loanID).filter { $0.dueDate <= date }
        return entries.last?.closingBalanceMinor ?? loan.principalMinor
    }

    func propertyAssets() throws -> [PropertyAsset] {
        var values: [PropertyAsset] = []
        try query(
            """
            SELECT id,name,type,purchase_date,purchase_value_minor,linked_loan_id,
                   location,note,is_active
            FROM property_assets ORDER BY is_active DESC,name COLLATE NOCASE,id
            """
        ) {
            guard
                let id = UUID(uuidString: Self.text($0, 0)),
                let type = PropertyAssetType(rawValue: Self.text($0, 2)),
                let purchaseDate = Self.date(Self.text($0, 3))
            else { return }
            values.append(
                PropertyAsset(
                    id: id, name: Self.text($0, 1), type: type,
                    purchaseDate: purchaseDate,
                    purchaseValueMinor: sqlite3_column_int64($0, 4),
                    linkedLoanID: Self.optionalText($0, 5).flatMap(UUID.init(uuidString:)),
                    location: Self.text($0, 6), note: Self.text($0, 7),
                    isActive: sqlite3_column_int($0, 8) != 0
                )
            )
        }
        return values
    }

    func savePropertyAsset(_ value: PropertyAsset) throws {
        let name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, value.purchaseValueMinor >= 0 else {
            throw FinanceError.database("Name und gültiger Kaufwert sind erforderlich.")
        }
        let info = try financeFileInfo()
        let now = Self.timestamp(Date())
        try transaction {
            try run(
                """
                INSERT INTO property_assets(
                    id,finance_file_id,name,type,purchase_date,purchase_value_minor,
                    linked_loan_id,location,note,is_active,created_at,updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET name=excluded.name,type=excluded.type,
                    purchase_date=excluded.purchase_date,
                    purchase_value_minor=excluded.purchase_value_minor,
                    linked_loan_id=excluded.linked_loan_id,location=excluded.location,
                    note=excluded.note,is_active=excluded.is_active,
                    updated_at=excluded.updated_at,version=version+1
                """,
                [
                    .text(value.id.uuidString), .text(info.id.uuidString), .text(name),
                    .text(value.type.rawValue), .text(Self.day(value.purchaseDate)),
                    .integer(value.purchaseValueMinor),
                    value.linkedLoanID.map { .text($0.uuidString) } ?? .null,
                    .text(value.location), .text(value.note),
                    .integer(value.isActive ? 1 : 0), .text(now), .text(now)
                ]
            )
            try audit(entity: "property_asset", id: value.id, action: "save", details: name)
        }
    }

    func assetValuations(assetID: UUID) throws -> [AssetValuation] {
        var values: [AssetValuation] = []
        try query(
            """
            SELECT id,valuation_date,value_minor,source,note
            FROM asset_valuations WHERE asset_id=?
            ORDER BY valuation_date,id
            """,
            [.text(assetID.uuidString)]
        ) {
            guard
                let id = UUID(uuidString: Self.text($0, 0)),
                let date = Self.date(Self.text($0, 1))
            else { return }
            values.append(
                AssetValuation(
                    id: id, assetID: assetID, valuationDate: date,
                    valueMinor: sqlite3_column_int64($0, 2),
                    source: Self.text($0, 3), note: Self.text($0, 4)
                )
            )
        }
        return values
    }

    func saveAssetValuation(_ value: AssetValuation) throws {
        guard value.valueMinor >= 0 else {
            throw FinanceError.database("Der Vermögenswert darf nicht negativ sein.")
        }
        try transaction {
            try run(
                """
                INSERT INTO asset_valuations(
                    id,asset_id,valuation_date,value_minor,source,note
                ) VALUES(?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET valuation_date=excluded.valuation_date,
                    value_minor=excluded.value_minor,source=excluded.source,note=excluded.note
                """,
                [
                    .text(value.id.uuidString), .text(value.assetID.uuidString),
                    .text(Self.day(value.valuationDate)), .integer(value.valueMinor),
                    .text(value.source), .text(value.note)
                ]
            )
            try audit(
                entity: "asset_valuation", id: value.id, action: "save",
                details: "\(value.valueMinor)"
            )
        }
    }

    func propertyAssetPositions(asOf date: Date = Date()) throws -> [PropertyAssetPosition] {
        let allAssets = try propertyAssets()
        var values: [PropertyAssetPosition] = []
        for asset in allAssets {
            let latest = try assetValuations(assetID: asset.id)
                .filter { $0.valuationDate <= date }
                .last
            let loanBalance = try asset.linkedLoanID.map {
                try loanBalanceMinor(loanID: $0, asOf: date)
            } ?? 0
            values.append(
                PropertyAssetPosition(
                    asset: asset, latestValuation: latest,
                    linkedLoanBalanceMinor: loanBalance
                )
            )
        }
        return values
    }

    func contracts() throws -> [FinanceContract] {
        var values: [FinanceContract] = []
        try query(
            """
            SELECT id,provider,contract_number,name,type,start_date,
                   initial_term_months,renewal_months,cancellation_notice_days,
                   amount_minor,frequency,account_id,category_id,reminder_days,
                   note,is_active
            FROM contracts ORDER BY is_active DESC,name COLLATE NOCASE,id
            """
        ) {
            guard
                let id = UUID(uuidString: Self.text($0, 0)),
                let type = ContractType(rawValue: Self.text($0, 4)),
                let startDate = Self.date(Self.text($0, 5)),
                let frequency = ContractPaymentFrequency(rawValue: Self.text($0, 10))
            else { return }
            values.append(
                FinanceContract(
                    id: id, provider: Self.text($0, 1),
                    contractNumber: Self.text($0, 2), name: Self.text($0, 3),
                    type: type, startDate: startDate,
                    initialTermMonths: Int(sqlite3_column_int($0, 6)),
                    renewalMonths: Int(sqlite3_column_int($0, 7)),
                    cancellationNoticeDays: Int(sqlite3_column_int($0, 8)),
                    amountMinor: sqlite3_column_int64($0, 9),
                    frequency: frequency,
                    accountID: Self.optionalText($0, 11).flatMap(UUID.init(uuidString:)),
                    categoryID: Self.optionalText($0, 12).flatMap(UUID.init(uuidString:)),
                    reminderDays: Int(sqlite3_column_int($0, 13)),
                    note: Self.text($0, 14), isActive: sqlite3_column_int($0, 15) != 0
                )
            )
        }
        return values
    }

    func saveContract(_ value: FinanceContract) throws {
        let name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !value.provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.initialTermMonths > 0, value.renewalMonths >= 0,
              value.cancellationNoticeDays >= 0, value.amountMinor >= 0,
              value.reminderDays >= 0
        else { throw FinanceError.database("Die Vertragsangaben sind unvollständig.") }
        let info = try financeFileInfo()
        let now = Self.timestamp(Date())
        try transaction {
            try run(
                """
                INSERT INTO contracts(
                    id,finance_file_id,provider,contract_number,name,type,start_date,
                    initial_term_months,renewal_months,cancellation_notice_days,
                    amount_minor,frequency,account_id,category_id,reminder_days,
                    note,is_active,created_at,updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET provider=excluded.provider,
                    contract_number=excluded.contract_number,name=excluded.name,
                    type=excluded.type,start_date=excluded.start_date,
                    initial_term_months=excluded.initial_term_months,
                    renewal_months=excluded.renewal_months,
                    cancellation_notice_days=excluded.cancellation_notice_days,
                    amount_minor=excluded.amount_minor,frequency=excluded.frequency,
                    account_id=excluded.account_id,category_id=excluded.category_id,
                    reminder_days=excluded.reminder_days,note=excluded.note,
                    is_active=excluded.is_active,updated_at=excluded.updated_at,
                    version=version+1
                """,
                [
                    .text(value.id.uuidString), .text(info.id.uuidString),
                    .text(value.provider.trimmingCharacters(in: .whitespacesAndNewlines)),
                    .text(value.contractNumber), .text(name), .text(value.type.rawValue),
                    .text(Self.day(value.startDate)),
                    .integer(Int64(value.initialTermMonths)),
                    .integer(Int64(value.renewalMonths)),
                    .integer(Int64(value.cancellationNoticeDays)),
                    .integer(value.amountMinor), .text(value.frequency.rawValue),
                    value.accountID.map { .text($0.uuidString) } ?? .null,
                    value.categoryID.map { .text($0.uuidString) } ?? .null,
                    .integer(Int64(value.reminderDays)), .text(value.note),
                    .integer(value.isActive ? 1 : 0), .text(now), .text(now)
                ]
            )
            try audit(entity: "contract", id: value.id, action: "save", details: name)
        }
    }

    func inventoryItems() throws -> [InventoryItem] {
        var values: [InventoryItem] = []
        try query(
            """
            SELECT id,name,category,room,purchase_date,purchase_price_minor,
                   current_value_minor,insurance_value_minor,retailer,serial_number,
                   warranty_end,note,is_active
            FROM inventory_items ORDER BY is_active DESC,room COLLATE NOCASE,
                 name COLLATE NOCASE,id
            """
        ) {
            guard
                let id = UUID(uuidString: Self.text($0, 0)),
                let category = InventoryCategory(rawValue: Self.text($0, 2))
            else { return }
            values.append(
                InventoryItem(
                    id: id, name: Self.text($0, 1), category: category,
                    room: Self.text($0, 3),
                    purchaseDate: Self.optionalText($0, 4).flatMap(Self.date),
                    purchasePriceMinor: sqlite3_column_int64($0, 5),
                    currentValueMinor: sqlite3_column_int64($0, 6),
                    insuranceValueMinor: sqlite3_column_int64($0, 7),
                    retailer: Self.text($0, 8), serialNumber: Self.text($0, 9),
                    warrantyEnd: Self.optionalText($0, 10).flatMap(Self.date),
                    note: Self.text($0, 11),
                    isActive: sqlite3_column_int($0, 12) != 0
                )
            )
        }
        return values
    }

    func saveInventoryItem(_ value: InventoryItem) throws {
        let name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, value.purchasePriceMinor >= 0,
              value.currentValueMinor >= 0, value.insuranceValueMinor >= 0
        else { throw FinanceError.database("Die Inventarangaben sind ungültig.") }
        let info = try financeFileInfo()
        let now = Self.timestamp(Date())
        try transaction {
            try run(
                """
                INSERT INTO inventory_items(
                    id,finance_file_id,name,category,room,purchase_date,
                    purchase_price_minor,current_value_minor,insurance_value_minor,
                    retailer,serial_number,warranty_end,note,is_active,
                    created_at,updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET name=excluded.name,
                    category=excluded.category,room=excluded.room,
                    purchase_date=excluded.purchase_date,
                    purchase_price_minor=excluded.purchase_price_minor,
                    current_value_minor=excluded.current_value_minor,
                    insurance_value_minor=excluded.insurance_value_minor,
                    retailer=excluded.retailer,serial_number=excluded.serial_number,
                    warranty_end=excluded.warranty_end,note=excluded.note,
                    is_active=excluded.is_active,updated_at=excluded.updated_at,
                    version=version+1
                """,
                [
                    .text(value.id.uuidString), .text(info.id.uuidString), .text(name),
                    .text(value.category.rawValue), .text(value.room),
                    value.purchaseDate.map { .text(Self.day($0)) } ?? .null,
                    .integer(value.purchasePriceMinor), .integer(value.currentValueMinor),
                    .integer(value.insuranceValueMinor), .text(value.retailer),
                    .text(value.serialNumber),
                    value.warrantyEnd.map { .text(Self.day($0)) } ?? .null,
                    .text(value.note), .integer(value.isActive ? 1 : 0),
                    .text(now), .text(now)
                ]
            )
            try audit(entity: "inventory_item", id: value.id, action: "save", details: name)
        }
    }

    func createPaymentOrder(_ value: PaymentOrder) throws {
        try value.validate()
        if try scalarInt(
            "SELECT COUNT(*) FROM payment_orders WHERE idempotency_key=?",
            [.text(value.idempotencyKey)]
        ) > 0 {
            throw FinanceError.duplicatePaymentOrder
        }
        let info = try financeFileInfo()
        try transaction {
            try run(
                """
                INSERT INTO payment_orders(
                    id,finance_file_id,account_id,type,recipient_name,iban,bic,amount_minor,
                    currency,execution_date,purpose,end_to_end_id,status,idempotency_key,
                    bank_reference,created_at,updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
                [
                    .text(value.id.uuidString), .text(info.id.uuidString),
                    .text(value.accountID.uuidString), .text(value.type.rawValue),
                    .text(value.recipientName), .text(IBANValidator.normalized(value.iban)),
                    .text(value.bic.uppercased()), .integer(value.amountMinor),
                    .text(value.currency), .text(Self.day(value.executionDate)),
                    .text(value.purpose), .text(value.endToEndID),
                    .text(value.status.rawValue), .text(value.idempotencyKey),
                    .text(value.bankReference), .text(Self.timestamp(value.createdAt)),
                    .text(Self.timestamp(value.updatedAt))
                ]
            )
            try audit(entity: "payment_order", id: value.id, action: "create", details: value.type.rawValue)
        }
    }

    func transitionPaymentOrder(id: UUID, to target: PaymentStatus) throws {
        var currentStatus: PaymentStatus?
        try query("SELECT status FROM payment_orders WHERE id=?", [.text(id.uuidString)]) {
            currentStatus = PaymentStatus(rawValue: Self.text($0, 0))
        }
        guard
            let currentStatus,
            let current = try paymentOrders().first(where: {
                $0.id == id && $0.status == currentStatus
            })
        else { throw FinanceError.database("Zahlungsauftrag nicht gefunden.") }
        guard current.status.canTransition(to: target) else {
            throw FinanceError.invalidPaymentTransition
        }
        let now = Self.timestamp(Date())
        try transaction {
            let bankReference = target == .accepted
                ? "SIM-\(id.uuidString.prefix(8).uppercased())" : current.bankReference
            try run(
                """
                UPDATE payment_orders SET status=?,bank_reference=?,updated_at=?,version=version+1
                WHERE id=? AND status=?
                """,
                [
                    .text(target.rawValue), .text(bankReference), .text(now),
                    .text(id.uuidString), .text(current.status.rawValue)
                ]
            )
            if target == .accepted {
                let reference = "payment:\(id.uuidString)"
                if try scalarInt(
                    "SELECT COUNT(*) FROM transactions WHERE reference=?",
                    [.text(reference)]
                ) == 0 {
                    try writeTransaction(
                        FinanceTransaction(
                            id: UUID(), accountID: current.accountID,
                            bookingDate: current.executionDate, valueDate: current.executionDate,
                            payee: current.recipientName, purpose: current.purpose,
                            categoryID: nil, amountMinor: -current.amountMinor,
                            currency: current.currency, status: .pending, memo: current.type.title,
                            reference: reference, transferID: nil,
                            importFingerprint: nil, splits: []
                        ),
                        now: now
                    )
                }
            }
            try audit(
                entity: "payment_order", id: id, action: "transition",
                details: "\(current.status.rawValue)->\(target.rawValue)"
            )
        }
    }

    func saveCategorizationRule(_ rule: CategorizationRule) throws {
        let info = try financeFileInfo()
        let now = Self.timestamp(Date())
        try transaction {
            try run(
                """
                INSERT INTO categorization_rules(
                    id,finance_file_id,name,priority,is_active,stop_after_match,
                    payee_contains,purpose_contains,minimum_amount_minor,maximum_amount_minor,
                    category_id,created_at,updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET name=excluded.name,priority=excluded.priority,
                    is_active=excluded.is_active,stop_after_match=excluded.stop_after_match,
                    payee_contains=excluded.payee_contains,purpose_contains=excluded.purpose_contains,
                    minimum_amount_minor=excluded.minimum_amount_minor,
                    maximum_amount_minor=excluded.maximum_amount_minor,
                    category_id=excluded.category_id,updated_at=excluded.updated_at,version=version+1
                """,
                [
                    .text(rule.id.uuidString), .text(info.id.uuidString), .text(rule.name),
                    .integer(Int64(rule.priority)), .integer(rule.isActive ? 1 : 0),
                    .integer(rule.stopAfterMatch ? 1 : 0), .text(rule.payeeContains),
                    .text(rule.purposeContains),
                    rule.minimumAmountMinor.map(SQLiteValue.integer) ?? .null,
                    rule.maximumAmountMinor.map(SQLiteValue.integer) ?? .null,
                    .text(rule.categoryID.uuidString), .text(now), .text(now)
                ]
            )
            try audit(entity: "categorization_rule", id: rule.id, action: "save", details: rule.name)
        }
    }

    func applyCategorizationRule(_ rule: CategorizationRule) throws -> Int {
        let candidates = try transactions().filter(rule.matches)
        guard !candidates.isEmpty else { return 0 }
        let now = Self.timestamp(Date())
        try transaction {
            for candidate in candidates {
                try run(
                    """
                    UPDATE transactions SET category_id=?,updated_at=?,version=version+1
                    WHERE id=? AND status NOT IN ('reconciled','cancelled')
                    """,
                    [
                        .text(rule.categoryID.uuidString), .text(now),
                        .text(candidate.id.uuidString)
                    ]
                )
            }
            try audit(
                entity: "categorization_rule", id: rule.id, action: "apply",
                details: "\(candidates.count) Buchungen"
            )
        }
        return candidates.count
    }

    func transactions(accountID: UUID? = nil) throws -> [FinanceTransaction] {
        var values: [FinanceTransaction] = []
        let sql = """
            SELECT id,account_id,booking_date,value_date,payee,purpose,category_id,
                   amount_minor,currency,status,memo,reference,transfer_id,import_fingerprint,payee_id
            FROM transactions
            \(accountID == nil ? "" : "WHERE account_id = ?")
            ORDER BY booking_date DESC,id DESC
            """
        try query(sql, accountID.map { [.text($0.uuidString)] } ?? []) { statement in
            guard
                let id = UUID(uuidString: Self.text(statement, 0)),
                let account = UUID(uuidString: Self.text(statement, 1)),
                let date = Self.date(Self.text(statement, 2)),
                let status = TransactionStatus(rawValue: Self.text(statement, 9))
            else { return }
            values.append(
                FinanceTransaction(
                    id: id,
                    accountID: account,
                    bookingDate: date,
                    valueDate: Self.optionalText(statement, 3).flatMap(Self.date),
                    payee: Self.text(statement, 4),
                    purpose: Self.text(statement, 5),
                    categoryID: Self.optionalText(statement, 6).flatMap(UUID.init(uuidString:)),
                    amountMinor: sqlite3_column_int64(statement, 7),
                    currency: Self.text(statement, 8),
                    status: status,
                    memo: Self.text(statement, 10),
                    reference: Self.text(statement, 11),
                    transferID: Self.optionalText(statement, 12).flatMap(UUID.init(uuidString:)),
                    importFingerprint: Self.optionalText(statement, 13),
                    splits: [],
                    payeeID: Self.optionalText(statement, 14).flatMap(UUID.init(uuidString:)),
                    tagIDs: []
                )
            )
        }
        for index in values.indices {
            values[index].splits = try splits(transactionID: values[index].id)
            values[index].tagIDs = try tagIDs(
                table: "transaction_tags", ownerColumn: "transaction_id",
                ownerID: values[index].id
            )
        }
        return values
    }

    func saveAccount(_ account: FinanceAccount) throws {
        let name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw FinanceError.database("Der Kontoname fehlt.")
        }
        guard account.creditLimitMinor >= 0 else {
            throw FinanceError.database("Das Kreditlimit darf nicht negativ sein.")
        }
        let normalizedIBAN = account.iban
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        if !normalizedIBAN.isEmpty, !IBANValidator.isValid(normalizedIBAN) {
            throw FinanceError.invalidIBAN
        }
        if let groupID = account.groupID,
           try !accountGroups().contains(where: { $0.id == groupID }) {
            throw FinanceError.database("Die Kontengruppe existiert nicht.")
        }
        let info = try financeFileInfo()
        let now = Self.timestamp(Date())
        try transaction {
            try run(
                """
                INSERT INTO accounts(
                    id,finance_file_id,name,institution,type,currency,opening_balance_minor,
                    is_hidden,is_closed,sort_order,created_at,updated_at,short_name,description,
                    group_id,iban,bic,account_number_masked,owner_name,opening_date,
                    credit_limit_minor,is_online,include_net_worth,include_budget,include_reports,
                    include_forecast,last_sync_at,last_bank_balance_minor,sync_status
                )
                VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET name=excluded.name,institution=excluded.institution,
                    type=excluded.type,currency=excluded.currency,opening_balance_minor=excluded.opening_balance_minor,
                    is_hidden=excluded.is_hidden,is_closed=excluded.is_closed,sort_order=excluded.sort_order,
                    short_name=excluded.short_name,description=excluded.description,
                    group_id=excluded.group_id,iban=excluded.iban,bic=excluded.bic,
                    account_number_masked=excluded.account_number_masked,owner_name=excluded.owner_name,
                    opening_date=excluded.opening_date,credit_limit_minor=excluded.credit_limit_minor,
                    is_online=excluded.is_online,include_net_worth=excluded.include_net_worth,
                    include_budget=excluded.include_budget,include_reports=excluded.include_reports,
                    include_forecast=excluded.include_forecast,last_sync_at=excluded.last_sync_at,
                    last_bank_balance_minor=excluded.last_bank_balance_minor,
                    sync_status=excluded.sync_status,
                    updated_at=excluded.updated_at,version=version+1
                """,
                [
                    .text(account.id.uuidString), .text(info.id.uuidString), .text(name),
                    .text(account.institution), .text(account.type.rawValue), .text(account.currency),
                    .integer(account.openingBalanceMinor), .integer(account.isHidden ? 1 : 0),
                    .integer(account.isClosed ? 1 : 0), .integer(Int64(account.sortOrder)),
                    .text(now), .text(now), .text(account.shortName), .text(account.description),
                    account.groupID.map { .text($0.uuidString) } ?? .null,
                    .text(normalizedIBAN), .text(account.bic.uppercased()),
                    .text(account.accountNumberMasked), .text(account.ownerName),
                    account.openingDate.map { .text(Self.day($0)) } ?? .null,
                    .integer(account.creditLimitMinor), .integer(account.isOnline ? 1 : 0),
                    .integer(account.includeNetWorth ? 1 : 0),
                    .integer(account.includeBudget ? 1 : 0),
                    .integer(account.includeReports ? 1 : 0),
                    .integer(account.includeForecast ? 1 : 0),
                    account.lastSyncAt.map { .text(Self.timestamp($0)) } ?? .null,
                    account.lastBankBalanceMinor.map(SQLiteValue.integer) ?? .null,
                    .text(account.syncStatus.rawValue)
                ]
            )
            try audit(entity: "account", id: account.id, action: "save", details: name)
        }
    }

    func saveAccountGroup(_ group: AccountGroup) throws {
        let name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw FinanceError.database("Der Name der Kontengruppe fehlt.")
        }
        let info = try financeFileInfo()
        let now = Self.timestamp(Date())
        try transaction {
            try run(
                """
                INSERT INTO account_groups(id,finance_file_id,name,sort_order,is_active,created_at,updated_at)
                VALUES(?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET name=excluded.name,sort_order=excluded.sort_order,
                    is_active=excluded.is_active,updated_at=excluded.updated_at,version=version+1
                """,
                [
                    .text(group.id.uuidString), .text(info.id.uuidString), .text(name),
                    .integer(Int64(group.sortOrder)), .integer(group.isActive ? 1 : 0),
                    .text(now), .text(now)
                ]
            )
            try audit(entity: "account-group", id: group.id, action: "save", details: name)
        }
    }

    func saveCategory(_ category: FinanceCategory) throws {
        let name = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw FinanceError.database("Der Kategoriename fehlt.")
        }
        guard category.parentID != category.id else {
            throw FinanceError.database("Eine Kategorie kann nicht ihr eigener Oberpunkt sein.")
        }
        let existing = try categories()
        if let parentID = category.parentID {
            guard let parent = existing.first(where: { $0.id == parentID }) else {
                throw FinanceError.database("Die übergeordnete Kategorie fehlt.")
            }
            guard parent.kind == category.kind else {
                throw FinanceError.database("Ober- und Unterkategorie müssen dieselbe Art besitzen.")
            }
            var ancestorID: UUID? = parent.id
            var visited = Set<UUID>()
            while let currentID = ancestorID {
                guard visited.insert(currentID).inserted else {
                    throw FinanceError.database("Die Kategoriehierarchie enthält einen Kreis.")
                }
                guard currentID != category.id else {
                    throw FinanceError.database("Die Kategoriehierarchie würde einen Kreis erzeugen.")
                }
                ancestorID = existing.first(where: { $0.id == currentID })?.parentID
            }
        }
        let info = try financeFileInfo()
        let now = Self.timestamp(Date())
        try transaction {
            try run(
                """
                INSERT INTO categories(id,finance_file_id,parent_id,name,kind,color,is_active,created_at,updated_at)
                VALUES(?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET parent_id=excluded.parent_id,name=excluded.name,
                    kind=excluded.kind,color=excluded.color,is_active=excluded.is_active,
                    updated_at=excluded.updated_at,version=version+1
                """,
                [
                    .text(category.id.uuidString), .text(info.id.uuidString),
                    category.parentID.map { .text($0.uuidString) } ?? .null,
                    .text(name), .text(category.kind.rawValue), .text(category.color),
                    .integer(category.isActive ? 1 : 0), .text(now), .text(now)
                ]
            )
            try audit(entity: "category", id: category.id, action: "save", details: name)
        }
    }

    func saveTransaction(_ value: FinanceTransaction) throws {
        try value.validate()
        var existingStatus: String?
        try query("SELECT status FROM transactions WHERE id=?", [.text(value.id.uuidString)]) {
            existingStatus = Self.text($0, 0)
        }
        if existingStatus == TransactionStatus.reconciled.rawValue {
            throw FinanceError.protectedTransaction
        }
        let now = Self.timestamp(Date())
        try transaction {
            try writeTransaction(value, now: now)
            try audit(entity: "transaction", id: value.id, action: "save", details: value.purpose)
        }
    }

    func bulkUpdateTransactionCategory(
        ids: Set<UUID>,
        categoryID: UUID?
    ) throws -> BulkCategoryUpdateResult {
        guard !ids.isEmpty else {
            return BulkCategoryUpdateResult(updatedCount: 0, totalsByCurrency: [:])
        }
        if let categoryID {
            var categoryExists = false
            try query(
                "SELECT 1 FROM categories WHERE id=? AND is_active=1 LIMIT 1",
                [.text(categoryID.uuidString)]
            ) { _ in categoryExists = true }
            guard categoryExists else {
                throw FinanceError.database("Die gewählte Kategorie existiert nicht oder ist inaktiv.")
            }
        }

        var selected: [(id: UUID, status: String, transferID: String?, splitCount: Int, amount: Int64, currency: String)] = []
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            try query(
                """
                SELECT t.status,t.transfer_id,
                       (SELECT COUNT(*) FROM transaction_splits s WHERE s.transaction_id=t.id),
                       t.amount_minor,t.currency
                FROM transactions t WHERE t.id=?
                """,
                [.text(id.uuidString)]
            ) { statement in
                selected.append(
                    (
                        id,
                        Self.text(statement, 0),
                        Self.optionalText(statement, 1),
                        Int(sqlite3_column_int64(statement, 2)),
                        sqlite3_column_int64(statement, 3),
                        Self.text(statement, 4)
                    )
                )
            }
        }
        guard selected.count == ids.count else {
            throw FinanceError.database("Mindestens eine ausgewählte Buchung wurde nicht gefunden.")
        }
        guard selected.allSatisfy({
            $0.status != TransactionStatus.reconciled.rawValue
                && $0.transferID == nil
                && $0.splitCount == 0
        }) else {
            throw FinanceError.protectedBulkEdit
        }

        let now = Self.timestamp(Date())
        try transaction {
            for value in selected {
                try run(
                    """
                    UPDATE transactions
                    SET category_id=?,updated_at=?,version=version+1
                    WHERE id=?
                    """,
                    [
                        categoryID.map { .text($0.uuidString) } ?? .null,
                        .text(now),
                        .text(value.id.uuidString)
                    ]
                )
                try audit(
                    entity: "transaction",
                    id: value.id,
                    action: "bulk-category",
                    details: categoryID?.uuidString ?? "uncategorized"
                )
            }
        }
        let totals = Dictionary(grouping: selected, by: \.currency)
            .mapValues { values in values.reduce(Int64.zero) { $0 + $1.amount } }
        return BulkCategoryUpdateResult(updatedCount: selected.count, totalsByCurrency: totals)
    }

    func deleteTransaction(id: UUID) throws {
        try transaction {
            var transferID: String?
            try query("SELECT transfer_id FROM transactions WHERE id=?", [.text(id.uuidString)]) {
                transferID = Self.optionalText($0, 0)
            }
            if let transferID {
                try run("DELETE FROM transactions WHERE transfer_id=?", [.text(transferID)])
            } else {
                try run("DELETE FROM transactions WHERE id=?", [.text(id.uuidString)])
            }
            try audit(entity: "transaction", id: id, action: "delete", details: transferID ?? "")
        }
    }

    func createTransfer(
        from source: FinanceAccount,
        to destination: FinanceAccount,
        amountMinor: Int64,
        date: Date,
        purpose: String
    ) throws {
        let transferID = UUID()
        let sourceValue = FinanceTransaction(
            id: UUID(), accountID: source.id, bookingDate: date, valueDate: date,
            payee: destination.name, purpose: purpose, categoryID: nil,
            amountMinor: -abs(amountMinor), currency: source.currency, status: .booked,
            memo: "", reference: "", transferID: transferID, importFingerprint: nil, splits: []
        )
        let destinationValue = FinanceTransaction(
            id: UUID(), accountID: destination.id, bookingDate: date, valueDate: date,
            payee: source.name, purpose: purpose, categoryID: nil,
            amountMinor: abs(amountMinor), currency: destination.currency, status: .booked,
            memo: "", reference: "", transferID: transferID, importFingerprint: nil, splits: []
        )
        let now = Self.timestamp(Date())
        try transaction {
            try writeTransaction(sourceValue, now: now)
            try writeTransaction(destinationValue, now: now)
            try audit(entity: "transfer", id: transferID, action: "create", details: purpose)
        }
    }

    func accountBalanceMinor(account: FinanceAccount) throws -> Int64 {
        try scalarInt64(
            """
            SELECT ? + COALESCE(SUM(amount_minor),0) FROM transactions
            WHERE account_id=? AND status != 'cancelled'
            """,
            [.integer(account.openingBalanceMinor), .text(account.id.uuidString)]
        )
    }

    func categoryReport() throws -> [CategoryReportRow] {
        var rows: [CategoryReportRow] = []
        try query(
            """
            SELECT COALESCE(c.name,'Ohne Kategorie'),
                   COALESCE(SUM(CASE WHEN t.amount_minor > 0 THEN t.amount_minor ELSE 0 END),0),
                   COALESCE(SUM(CASE WHEN t.amount_minor < 0 THEN -t.amount_minor ELSE 0 END),0)
            FROM transactions t
            JOIN accounts a ON a.id=t.account_id
            LEFT JOIN categories c ON c.id=t.category_id
            WHERE t.status != 'cancelled' AND t.transfer_id IS NULL
              AND a.include_reports=1
            GROUP BY COALESCE(c.name,'Ohne Kategorie') ORDER BY 1 COLLATE NOCASE
            """
        ) {
            let name = Self.text($0, 0)
            rows.append(
                CategoryReportRow(
                    id: name,
                    name: name,
                    incomeMinor: sqlite3_column_int64($0, 1),
                    expenseMinor: sqlite3_column_int64($0, 2)
                )
            )
        }
        return rows
    }

    func reportTemplates() throws -> [SavedReportTemplate] {
        var templates: [SavedReportTemplate] = []
        let decoder = JSONDecoder()
        try query(
            """
            SELECT id,name,definition_version,query_json
            FROM report_templates
            ORDER BY name COLLATE NOCASE
            """
        ) { statement in
            guard let id = UUID(uuidString: Self.text(statement, 0)),
                  let data = Self.text(statement, 3).data(using: .utf8)
            else {
                throw FinanceError.database("Eine Berichtsvorlage ist beschädigt.")
            }
            do {
                templates.append(
                    SavedReportTemplate(
                        id: id,
                        name: Self.text(statement, 1),
                        definitionVersion: Int(sqlite3_column_int64(statement, 2)),
                        query: try decoder.decode(TransactionReportQuery.self, from: data)
                    )
                )
            } catch {
                throw FinanceError.database(
                    "Die Berichtsvorlage „\(Self.text(statement, 1))“ kann nicht gelesen werden."
                )
            }
        }
        return templates
    }

    func saveReportTemplate(_ template: SavedReportTemplate) throws {
        let name = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw FinanceError.database("Die Berichtsvorlage benötigt einen Namen.")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let json = String(data: try encoder.encode(template.query), encoding: .utf8) else {
            throw FinanceError.database("Die Berichtsvorlage konnte nicht codiert werden.")
        }
        let info = try financeFileInfo()
        let now = Self.timestamp(Date())
        try transaction {
            try run(
                """
                INSERT INTO report_templates(
                    id,finance_file_id,name,definition_version,query_json,
                    created_at,updated_at
                )
                VALUES(?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET
                    name=excluded.name,
                    definition_version=excluded.definition_version,
                    query_json=excluded.query_json,
                    updated_at=excluded.updated_at,
                    version=report_templates.version+1
                """,
                [
                    .text(template.id.uuidString),
                    .text(info.id.uuidString),
                    .text(name),
                    .integer(Int64(template.definitionVersion)),
                    .text(json),
                    .text(now),
                    .text(now)
                ]
            )
            try audit(
                entity: "report-template",
                id: template.id,
                action: "save",
                details: name
            )
        }
    }

    func deleteReportTemplate(id: UUID) throws {
        try transaction {
            try run("DELETE FROM report_templates WHERE id=?", [.text(id.uuidString)])
            try audit(
                entity: "report-template",
                id: id,
                action: "delete",
                details: ""
            )
        }
    }

    func reconcile(account: FinanceAccount, endingBalanceMinor: Int64, date: Date) throws {
        let calculated = try scalarInt64(
            """
            SELECT ? + COALESCE(SUM(amount_minor),0)
            FROM transactions
            WHERE account_id=? AND booking_date<=? AND status!='cancelled'
            """,
            [
                .integer(account.openingBalanceMinor),
                .text(account.id.uuidString),
                .text(Self.day(date))
            ]
        )
        guard calculated == endingBalanceMinor else {
            throw FinanceError.reconciliationDifference(endingBalanceMinor - calculated)
        }
        let reconciliationID = UUID()
        let now = Self.timestamp(Date())
        try transaction {
            try run(
                """
                INSERT INTO reconciliations(id,account_id,statement_date,ending_balance_minor,completed_at)
                VALUES(?,?,?,?,?)
                """,
                [
                    .text(reconciliationID.uuidString), .text(account.id.uuidString),
                    .text(Self.day(date)), .integer(endingBalanceMinor), .text(now)
                ]
            )
            try run(
                """
                UPDATE transactions SET status='reconciled',updated_at=?,version=version+1
                WHERE account_id=? AND booking_date<=? AND status IN ('booked','cleared')
                """,
                [.text(now), .text(account.id.uuidString), .text(Self.day(date))]
            )
            try audit(
                entity: "reconciliation", id: reconciliationID, action: "complete",
                details: "\(account.id.uuidString):\(endingBalanceMinor)"
            )
        }
    }

    func commitImport(_ preview: ImportPreview) throws {
        if try scalarInt(
            "SELECT COUNT(*) FROM import_packages WHERE fingerprint=?",
            [.text(preview.fingerprint)]
        ) > 0 {
            throw FinanceError.duplicateImport
        }
        let now = Self.timestamp(Date())
        try transaction {
            for value in preview.rows {
                try value.validate()
                try writeTransaction(value, now: now)
            }
            try run(
                "INSERT INTO import_packages(fingerprint,imported_at,row_count) VALUES(?,?,?)",
                [.text(preview.fingerprint), .text(now), .integer(Int64(preview.rows.count))]
            )
            try audit(
                entity: "import",
                id: UUID(),
                action: "commit",
                details: "\(preview.fingerprint):\(preview.rows.count)"
            )
        }
    }

    func commitQIFPackage(_ package: QIFPackagePreview) throws {
        let preview = package.importPreview
        if try scalarInt(
            "SELECT COUNT(*) FROM import_packages WHERE fingerprint=?",
            [.text(preview.fingerprint)]
        ) > 0 {
            throw FinanceError.duplicateImport
        }
        let info = try financeFileInfo()
        let groupIDs = Dictionary(
            uniqueKeysWithValues: try accountGroups().map { ($0.name, $0.id) }
        )
        let now = Self.timestamp(Date())
        try transaction {
            for account in package.accountsToCreate {
                try run(
                    """
                    INSERT INTO accounts(
                        id,finance_file_id,name,institution,type,currency,
                        opening_balance_minor,is_hidden,is_closed,sort_order,
                        created_at,updated_at,group_id
                    )
                    VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
                    """,
                    [
                        .text(account.id.uuidString), .text(info.id.uuidString),
                        .text(account.name), .text(account.institution), .text(account.type.rawValue),
                        .text(account.currency), .integer(account.openingBalanceMinor),
                        .integer(account.isHidden ? 1 : 0), .integer(account.isClosed ? 1 : 0),
                        .integer(Int64(account.sortOrder)), .text(now), .text(now),
                        groupIDs[account.type.defaultGroupName]
                            .map { .text($0.uuidString) } ?? .null
                    ]
                )
            }
            for category in package.categoriesToCreate {
                try run(
                    """
                    INSERT INTO categories(id,finance_file_id,parent_id,name,kind,color,is_active,created_at,updated_at)
                    VALUES(?,?,?,?,?,?,?,?,?)
                    """,
                    [
                        .text(category.id.uuidString), .text(info.id.uuidString),
                        category.parentID.map { .text($0.uuidString) } ?? .null,
                        .text(category.name), .text(category.kind.rawValue), .text(category.color),
                        .integer(category.isActive ? 1 : 0), .text(now), .text(now)
                    ]
                )
            }
            for value in preview.rows {
                try value.validate()
                try writeTransaction(value, now: now)
            }
            try run(
                "INSERT INTO import_packages(fingerprint,imported_at,row_count) VALUES(?,?,?)",
                [.text(preview.fingerprint), .text(now), .integer(Int64(preview.rows.count))]
            )
            try audit(
                entity: "import", id: UUID(), action: "commit-qif-package",
                details: "\(preview.fingerprint):\(package.accountsToCreate.count):\(package.categoriesToCreate.count):\(preview.rows.count)"
            )
        }
    }

    func backup(to target: URL) throws {
        var targetDatabase: OpaquePointer?
        guard sqlite3_open(target.path, &targetDatabase) == SQLITE_OK else {
            throw FinanceError.database("Sicherungsdatei konnte nicht angelegt werden.")
        }
        defer { sqlite3_close(targetDatabase) }
        guard let backup = sqlite3_backup_init(targetDatabase, "main", database, "main") else {
            throw FinanceError.database("Sicherung konnte nicht gestartet werden.")
        }
        defer { sqlite3_backup_finish(backup) }
        guard sqlite3_backup_step(backup, -1) == SQLITE_DONE else {
            throw FinanceError.database("Sicherung konnte nicht abgeschlossen werden.")
        }
        var check: OpaquePointer?
        guard sqlite3_prepare_v2(targetDatabase, "PRAGMA integrity_check", -1, &check, nil) == SQLITE_OK else {
            throw FinanceError.invalidBackup
        }
        defer { sqlite3_finalize(check) }
        guard sqlite3_step(check) == SQLITE_ROW, Self.text(check, 0) == "ok" else {
            throw FinanceError.invalidBackup
        }
    }

    func integrityCheck() throws -> Bool {
        var result = ""
        try query("PRAGMA integrity_check") { result = Self.text($0, 0) }
        return result == "ok"
    }

    private func writeTransaction(_ value: FinanceTransaction, now: String) throws {
        try run(
            """
            INSERT INTO transactions(id,account_id,booking_date,value_date,payee,purpose,category_id,amount_minor,currency,status,memo,reference,transfer_id,import_fingerprint,payee_id,created_at,updated_at)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET booking_date=excluded.booking_date,value_date=excluded.value_date,
                payee=excluded.payee,purpose=excluded.purpose,category_id=excluded.category_id,
                amount_minor=excluded.amount_minor,currency=excluded.currency,status=excluded.status,
                memo=excluded.memo,reference=excluded.reference,payee_id=excluded.payee_id,
                updated_at=excluded.updated_at,version=version+1
            """,
            [
                .text(value.id.uuidString), .text(value.accountID.uuidString),
                .text(Self.day(value.bookingDate)), value.valueDate.map { .text(Self.day($0)) } ?? .null,
                .text(value.payee), .text(value.purpose),
                value.categoryID.map { .text($0.uuidString) } ?? .null,
                .integer(value.amountMinor), .text(value.currency), .text(value.status.rawValue),
                .text(value.memo), .text(value.reference),
                value.transferID.map { .text($0.uuidString) } ?? .null,
                value.importFingerprint.map(SQLiteValue.text) ?? .null,
                value.payeeID.map { .text($0.uuidString) } ?? .null,
                .text(now), .text(now)
            ]
        )
        try run("DELETE FROM transaction_tags WHERE transaction_id=?", [.text(value.id.uuidString)])
        for tagID in Set(value.tagIDs) {
            try run(
                "INSERT INTO transaction_tags(transaction_id,tag_id) VALUES(?,?)",
                [.text(value.id.uuidString), .text(tagID.uuidString)]
            )
        }
        try run("DELETE FROM transaction_splits WHERE transaction_id=?", [.text(value.id.uuidString)])
        for split in value.splits {
            try run(
                "INSERT INTO transaction_splits(id,transaction_id,category_id,amount_minor,memo,sort_order) VALUES(?,?,?,?,?,?)",
                [
                    .text(split.id.uuidString), .text(value.id.uuidString),
                    split.categoryID.map { .text($0.uuidString) } ?? .null,
                    .integer(split.amountMinor), .text(split.memo), .integer(Int64(split.sortOrder))
                ]
            )
            for tagID in Set(split.tagIDs) {
                try run(
                    "INSERT INTO split_tags(split_id,tag_id) VALUES(?,?)",
                    [.text(split.id.uuidString), .text(tagID.uuidString)]
                )
            }
        }
    }

    private func splits(transactionID: UUID) throws -> [FinanceSplit] {
        var values: [FinanceSplit] = []
        try query(
            "SELECT id,category_id,amount_minor,memo,sort_order FROM transaction_splits WHERE transaction_id=? ORDER BY sort_order",
            [.text(transactionID.uuidString)]
        ) {
            guard let id = UUID(uuidString: Self.text($0, 0)) else { return }
            values.append(
                FinanceSplit(
                    id: id,
                    categoryID: Self.optionalText($0, 1).flatMap(UUID.init(uuidString:)),
                    amountMinor: sqlite3_column_int64($0, 2),
                    memo: Self.text($0, 3),
                    sortOrder: Int(sqlite3_column_int($0, 4)),
                    tagIDs: []
                )
            )
        }
        for index in values.indices {
            values[index].tagIDs = try tagIDs(
                table: "split_tags", ownerColumn: "split_id", ownerID: values[index].id
            )
        }
        return values
    }

    private func tagIDs(table: String, ownerColumn: String, ownerID: UUID) throws -> [UUID] {
        precondition(["transaction_tags", "split_tags"].contains(table))
        precondition(["transaction_id", "split_id"].contains(ownerColumn))
        var values: [UUID] = []
        try query(
            "SELECT tag_id FROM \(table) WHERE \(ownerColumn)=? ORDER BY tag_id",
            [.text(ownerID.uuidString)]
        ) {
            if let id = UUID(uuidString: Self.text($0, 0)) { values.append(id) }
        }
        return values
    }

    private func seedCategories(financeFileID: UUID) throws {
        let now = Self.timestamp(Date())
        let seeds: [(String, CategoryKind, String)] = [
            ("Gehalt", .income, "green"), ("Zinsen", .income, "mint"),
            ("Wohnen", .expense, "blue"), ("Lebensmittel", .expense, "orange"),
            ("Mobilität", .expense, "purple"), ("Freizeit", .expense, "pink"),
            ("Versicherungen", .expense, "indigo"), ("Steuern", .expense, "red")
        ]
        for seed in seeds {
            try run(
                "INSERT INTO categories(id,finance_file_id,name,kind,color,created_at,updated_at) VALUES(?,?,?,?,?,?,?)",
                [.text(UUID().uuidString), .text(financeFileID.uuidString), .text(seed.0), .text(seed.1.rawValue), .text(seed.2), .text(now), .text(now)]
            )
        }
    }

    private func audit(entity: String, id: UUID, action: String, details: String) throws {
        try run(
            "INSERT INTO audit_events(id,occurred_at,entity_type,entity_id,action,correlation_id,details) VALUES(?,?,?,?,?,?,?)",
            [.text(UUID().uuidString), .text(Self.timestamp(Date())), .text(entity), .text(id.uuidString), .text(action), .text(UUID().uuidString), .text(details)]
        )
    }

    private func transaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try operation()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "Unbekannter SQLite-Fehler"
            sqlite3_free(error)
            throw FinanceError.database(message)
        }
    }

    private func run(_ sql: String, _ values: [SQLiteValue] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }

    private func query(
        _ sql: String,
        _ values: [SQLiteValue] = [],
        row: (OpaquePointer?) throws -> Void
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        while sqlite3_step(statement) == SQLITE_ROW {
            try row(statement)
        }
    }

    private func scalarInt(_ sql: String, _ values: [SQLiteValue] = []) throws -> Int {
        Int(try scalarInt64(sql, values))
    }

    private func scalarInt64(_ sql: String, _ values: [SQLiteValue] = []) throws -> Int64 {
        var result: Int64 = 0
        try query(sql, values) { result = sqlite3_column_int64($0, 0) }
        return result
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer?) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let code: Int32
            switch value {
            case .integer(let number):
                code = sqlite3_bind_int64(statement, index, number)
            case .text(let text):
                code = sqlite3_bind_text(statement, index, text, -1, transient)
            case .null:
                code = sqlite3_bind_null(statement, index)
            }
            guard code == SQLITE_OK else { throw databaseError() }
        }
    }

    private func databaseError() -> FinanceError {
        FinanceError.database(database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unbekannter Fehler")
    }

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private static func optionalText(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : text(statement, column)
    }

    private static let dayFormatter: DateFormatter = {
        let value = DateFormatter()
        value.calendar = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = TimeZone(secondsFromGMT: 0)
        value.dateFormat = "yyyy-MM-dd"
        return value
    }()

    private static func day(_ date: Date) -> String { dayFormatter.string(from: date) }
    private static func date(_ text: String) -> Date? { dayFormatter.date(from: text) }
    private static func timestamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private static func timestampDate(_ text: String) -> Date? {
        ISO8601DateFormatter().date(from: text)
    }

    private static func scaledProduct(_ quantityMicro: Int64, _ priceMinor: Int64) -> Int64 {
        roundedInt64(
            Decimal(quantityMicro) * Decimal(priceMinor)
                / Decimal(SecurityQuantity.scale)
        )
    }

    private static func scaledRatio(
        _ value: Int64,
        numerator: Int64,
        denominator: Int64
    ) -> Int64 {
        roundedInt64(Decimal(value) * Decimal(numerator) / Decimal(denominator))
    }

    private static func roundedInt64(_ value: Decimal) -> Int64 {
        NSDecimalNumber(decimal: value)
            .rounding(
                accordingToBehavior: NSDecimalNumberHandler(
                    roundingMode: .bankers, scale: 0,
                    raiseOnExactness: false, raiseOnOverflow: true,
                    raiseOnUnderflow: true, raiseOnDivideByZero: true
                )
            )
            .int64Value
    }
}

private enum SQLiteValue {
    case integer(Int64)
    case text(String)
    case null
}

enum CSVFinanceImporter {
    static func preview(data: Data, account: FinanceAccount) throws -> ImportPreview {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let header = lines.first else {
            return ImportPreview(rows: [], rejectedRows: ["Die Datei ist leer."], fingerprint: fingerprint)
        }
        let separator: Character = header.filter { $0 == ";" }.count >= header.filter { $0 == "," }.count ? ";" : ","
        let headings = fields(header, separator: separator).map { $0.lowercased() }
        var rows: [FinanceTransaction] = []
        var rejected: [String] = []
        for (offset, line) in lines.dropFirst().enumerated() {
            let values = fields(line, separator: separator)
            let record = Dictionary(uniqueKeysWithValues: zip(headings, values))
            do {
                guard
                    let dateText = record["datum"] ?? record["date"],
                    let date = parseDate(dateText),
                    let amountText = record["betrag"] ?? record["amount"]
                else { throw FinanceError.invalidAmount(line) }
                let amount = try Money(parsing: amountText, currency: account.currency)
                rows.append(
                    FinanceTransaction(
                        id: UUID(), accountID: account.id, bookingDate: date, valueDate: nil,
                        payee: record["empfänger"] ?? record["empfaenger"] ?? record["payee"] ?? "",
                        purpose: record["verwendungszweck"] ?? record["purpose"] ?? "",
                        categoryID: nil, amountMinor: amount.minorUnits, currency: account.currency,
                        status: .booked, memo: record["notiz"] ?? record["memo"] ?? "",
                        reference: record["referenz"] ?? record["reference"] ?? "",
                        transferID: nil, importFingerprint: fingerprint, splits: []
                    )
                )
            } catch {
                rejected.append("Zeile \(offset + 2): \(line)")
            }
        }
        return ImportPreview(rows: rows, rejectedRows: rejected, fingerprint: fingerprint)
    }

    private static func fields(_ line: String, separator: Character) -> [String] {
        var values: [String] = []
        var current = ""
        var quoted = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if quoted, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    index = next
                } else {
                    quoted.toggle()
                }
            } else if character == separator, !quoted {
                values.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
            index = line.index(after: index)
        }
        values.append(current.trimmingCharacters(in: .whitespaces))
        return values
    }

    private static func parseDate(_ text: String) -> Date? {
        for format in ["dd.MM.yyyy", "yyyy-MM-dd", "dd.MM.yy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "de_DE")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = format
            if let date = formatter.date(from: text.trimmingCharacters(in: .whitespaces)) {
                return date
            }
        }
        return nil
    }
}

enum QIFFinanceImporter {
    static func preview(
        data: Data,
        account: FinanceAccount,
        categories: [FinanceCategory]
    ) throws -> ImportPreview {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let accountDirectiveCount = normalizedText
            .components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces) == "!Account" }
            .count
        let typeDirectives = normalizedText
            .components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("!Type:") }
        if accountDirectiveCount > 0 || Set(typeDirectives).count > 1 {
            throw FinanceError.qifPackageRequiresPackageImport
        }
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let records = normalizedText.components(separatedBy: "\n^")
        var rows: [FinanceTransaction] = []
        var rejected: [String] = []
        for (offset, rawRecord) in records.enumerated() {
            let lines = rawRecord
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("!Type:") }
            guard !lines.isEmpty else { continue }
            var date: Date?
            var amount: Money?
            var payee = ""
            var memo = ""
            var reference = ""
            var categoryName = ""
            var splitDrafts: [(category: String, memo: String, amount: Money)] = []
            var pendingSplitCategory = ""
            var pendingSplitMemo = ""
            do {
                for line in lines {
                    guard let code = line.first else { continue }
                    let value = String(line.dropFirst())
                    switch code {
                    case "D": date = parseDate(value)
                    case "T", "U": if amount == nil { amount = try Money(parsing: value, currency: account.currency) }
                    case "P": payee = value
                    case "M": memo = value
                    case "N": reference = value
                    case "L": categoryName = normalizedCategory(value)
                    case "S": pendingSplitCategory = normalizedCategory(value)
                    case "E": pendingSplitMemo = value
                    case "$":
                        splitDrafts.append(
                            (
                                pendingSplitCategory,
                                pendingSplitMemo,
                                try Money(parsing: value, currency: account.currency)
                            )
                        )
                        pendingSplitCategory = ""
                        pendingSplitMemo = ""
                    default: break
                    }
                }
                guard let date, let amount else {
                    throw FinanceError.invalidAmount(rawRecord)
                }
                let categoryID = categories.first {
                    $0.name.localizedCaseInsensitiveCompare(categoryName) == .orderedSame
                }?.id
                let splits = splitDrafts.enumerated().map { index, draft in
                    FinanceSplit(
                        id: UUID(),
                        categoryID: categories.first {
                            $0.name.localizedCaseInsensitiveCompare(draft.category) == .orderedSame
                        }?.id,
                        amountMinor: draft.amount.minorUnits,
                        memo: draft.memo,
                        sortOrder: index
                    )
                }
                let transaction = FinanceTransaction(
                    id: UUID(), accountID: account.id, bookingDate: date, valueDate: nil,
                    payee: payee, purpose: memo, categoryID: splits.isEmpty ? categoryID : nil,
                    amountMinor: amount.minorUnits, currency: account.currency, status: .booked,
                    memo: "", reference: reference, transferID: nil,
                    importFingerprint: fingerprint, splits: splits
                )
                try transaction.validate()
                rows.append(transaction)
            } catch {
                rejected.append("QIF-Datensatz \(offset + 1): \(error.localizedDescription)")
            }
        }
        return ImportPreview(rows: rows, rejectedRows: rejected, fingerprint: fingerprint)
    }

    private static func normalizedCategory(_ value: String) -> String {
        value
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .components(separatedBy: "/").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? value
    }

    private static func parseDate(_ text: String) -> Date? {
        let cleaned = text.replacingOccurrences(of: "'", with: "/")
        for format in ["M/d/yyyy", "M/d/yy", "dd.MM.yyyy", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) { return date }
        }
        return nil
    }
}

enum QIFPackageImporter {
    private struct RawRecord {
        let section: String
        let lines: [String]
    }

    private struct AccountRecord {
        let account: FinanceAccount
    }

    private struct CategoryDraft {
        let path: String
        let kind: CategoryKind
    }

    static func isPackage(data: Data) -> Bool {
        let text = decodedText(data)
        let lines = normalizedLines(text)
        return lines.contains("!Account")
            || Set(lines.filter { $0.hasPrefix("!Type:") }).count > 1
    }

    static func preview(
        data: Data,
        existingAccounts: [FinanceAccount],
        existingCategories: [FinanceCategory],
        currency: String = "EUR"
    ) throws -> QIFPackagePreview {
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let records = records(in: decodedText(data))
        var sectionCounts: [String: Int] = [:]
        for record in records {
            sectionCounts[displaySection(record.section), default: 0] += 1
        }

        var accountRecords: [AccountRecord] = []
        var accountByKey: [String: FinanceAccount] = [:]
        for record in records where normalizedSection(record.section) == "account" {
            let fields = firstValues(record.lines)
            guard let rawName = fields["N"], !rawName.trimmingCharacters(in: .whitespaces).isEmpty else {
                continue
            }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let type = accountType(fields["T"] ?? "")
            let key = accountKey(name)
            if accountByKey[key] != nil { continue }
            let existing = existingAccounts.first {
                accountKey($0.name) == key
            }
            let account = existing ?? FinanceAccount(
                id: UUID(), name: name,
                institution: (fields["D"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                type: type, currency: currency, openingBalanceMinor: 0,
                isHidden: false, isClosed: false,
                sortOrder: existingAccounts.count + accountRecords.count
            )
            accountByKey[key] = account
            accountRecords.append(AccountRecord(account: account))
        }
        guard !accountRecords.isEmpty else { throw FinanceError.invalidQIFPackage }

        let explicitCategoryDrafts = records
            .filter { normalizedSection($0.section) == "cat" }
            .compactMap(categoryDraft)
        var inferredCategoryDrafts: [CategoryDraft] = []
        var currentAccountName: String?
        for record in records {
            let section = normalizedSection(record.section)
            if section == "account" {
                currentAccountName = firstValues(record.lines)["N"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            guard isTransactionSection(section), currentAccountName != nil else { continue }
            let amount = try? transactionAmount(record.lines, currency: currency)
            let kind: CategoryKind = (amount?.minorUnits ?? 0) >= 0 ? .income : .expense
            for line in record.lines where line.first == "L" || line.first == "S" {
                if let path = categoryPath(String(line.dropFirst())) {
                    inferredCategoryDrafts.append(CategoryDraft(path: path, kind: kind))
                }
            }
        }

        let categories = categoryMapping(
            existing: existingCategories,
            drafts: explicitCategoryDrafts + inferredCategoryDrafts
        )
        let existingCategoryIDs = Set(existingCategories.map(\.id))
        let categoriesToCreate = categories.ordered.filter { !existingCategoryIDs.contains($0.id) }

        var rows: [FinanceTransaction] = []
        var rejected: [String] = []
        var unsupportedSectionCounts: [String: Int] = [:]
        var supportedRecordCount = 0
        currentAccountName = nil
        for record in records {
            let section = normalizedSection(record.section)
            if section == "account" {
                currentAccountName = firstValues(record.lines)["N"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            guard !["cat", "class", "memorized"].contains(section) else {
                if section != "cat" {
                    unsupportedSectionCounts[displaySection(record.section), default: 0] += 1
                }
                continue
            }
            guard isTransactionSection(section) else { continue }
            guard
                let currentAccountName,
                let account = accountByKey[accountKey(currentAccountName)]
            else {
                unsupportedSectionCounts[displaySection(record.section), default: 0] += 1
                continue
            }
            if account.type == .investment || section == "invst" {
                unsupportedSectionCounts[displaySection(record.section), default: 0] += 1
                continue
            }
            supportedRecordCount += 1
            do {
                rows.append(
                    try transaction(
                        record.lines,
                        account: account,
                        categoryIDs: categories.idsByPath,
                        fingerprint: fingerprint
                    )
                )
            } catch {
                rejected.append(
                    "\(displaySection(record.section))-Datensatz \(supportedRecordCount): \(error.localizedDescription)"
                )
            }
        }

        let newAccountIDs = Set(existingAccounts.map(\.id))
        let accountsToCreate = accountRecords.map(\.account).filter { !newAccountIDs.contains($0.id) }
        let unsupportedCount = unsupportedSectionCounts.values.reduce(0, +)
        var warnings: [String] = []
        if unsupportedCount > 0 {
            warnings.append(
                "\(unsupportedCount) Datensätze aus Depot-, Klassen- oder Merkpostenbereichen werden nicht übernommen."
            )
        }
        if !rejected.isEmpty {
            warnings.append("\(rejected.count) Buchungen müssen wegen unvollständiger oder widersprüchlicher Felder ausgelassen werden.")
        }
        return QIFPackagePreview(
            accountsToCreate: accountsToCreate,
            categoriesToCreate: categoriesToCreate,
            importPreview: ImportPreview(
                rows: rows, rejectedRows: rejected, fingerprint: fingerprint
            ),
            summary: QIFPackageSummary(
                accountDefinitions: accountRecords.count,
                categoryRecords: explicitCategoryDrafts.count,
                transactionRecords: supportedRecordCount + unsupportedCount,
                supportedTransactionRecords: rows.count,
                sectionCounts: sectionCounts,
                unsupportedSectionCounts: unsupportedSectionCounts
            ),
            warnings: warnings
        )
    }

    private static func decodedText(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func records(in text: String) -> [RawRecord] {
        var section = ""
        var pendingLines: [String] = []
        var values: [RawRecord] = []
        func flush() {
            guard !pendingLines.isEmpty else { return }
            values.append(RawRecord(section: section, lines: pendingLines))
            pendingLines.removeAll(keepingCapacity: true)
        }
        for line in normalizedLines(text) where !line.isEmpty {
            if line == "^" {
                flush()
            } else if line.hasPrefix("!") {
                flush()
                if line == "!Account" {
                    section = "Account"
                } else if line.hasPrefix("!Type:") {
                    section = String(line.dropFirst("!Type:".count))
                }
            } else {
                pendingLines.append(line)
            }
        }
        flush()
        return values
    }

    private static func normalizedSection(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func displaySection(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unbekannt" : trimmed
    }

    private static func firstValues(_ lines: [String]) -> [String: String] {
        var values: [String: String] = [:]
        for line in lines {
            guard let code = line.first, values[String(code)] == nil else { continue }
            values[String(code)] = String(line.dropFirst())
        }
        return values
    }

    private static func accountKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func accountType(_ value: String) -> AccountType {
        switch normalizedSection(value) {
        case "bank": .checking
        case "cash": .cash
        case "ccard": .creditCard
        case "invst": .investment
        case "oth l": .liability
        case "loan": .loan
        default: .asset
        }
    }

    private static func isTransactionSection(_ section: String) -> Bool {
        !section.isEmpty
            && !["account", "cat", "class", "memorized"].contains(section)
    }

    private static func categoryDraft(_ record: RawRecord) -> CategoryDraft? {
        let fields = firstValues(record.lines)
        guard let rawName = fields["N"], let path = categoryPath(rawName) else { return nil }
        let kind: CategoryKind = fields["I"] != nil ? .income : .expense
        return CategoryDraft(path: path, kind: kind)
    }

    private static func categoryPath(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("[") else { return nil }
        let withoutClass = trimmed.components(separatedBy: "/").first ?? trimmed
        let parts = withoutClass
            .components(separatedBy: ":")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ":")
    }

    private static func categoryKey(_ path: String) -> String {
        path.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func categoryMapping(
        existing: [FinanceCategory],
        drafts: [CategoryDraft]
    ) -> (ordered: [FinanceCategory], idsByPath: [String: UUID]) {
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        func path(for category: FinanceCategory) -> String {
            var names = [category.name]
            var parentID = category.parentID
            var visited = Set([category.id])
            while let id = parentID,
                  visited.insert(id).inserted,
                  let parent = byID[id] {
                names.insert(parent.name, at: 0)
                parentID = parent.parentID
            }
            return names.joined(separator: ":")
        }
        var idsByPath: [String: UUID] = [:]
        for category in existing {
            idsByPath[categoryKey(path(for: category))] = category.id
        }
        var ordered = existing
        let sortedDrafts = drafts.sorted {
            $0.path.components(separatedBy: ":").count
                < $1.path.components(separatedBy: ":").count
        }
        for draft in sortedDrafts {
            let parts = draft.path.components(separatedBy: ":")
            var accumulated: [String] = []
            var parentID: UUID?
            for part in parts {
                accumulated.append(part)
                let fullPath = accumulated.joined(separator: ":")
                let key = categoryKey(fullPath)
                if let existingID = idsByPath[key] {
                    parentID = existingID
                    continue
                }
                let category = FinanceCategory(
                    id: UUID(), parentID: parentID, name: part, kind: draft.kind,
                    color: draft.kind == .income ? "green" : "blue", isActive: true
                )
                byID[category.id] = category
                idsByPath[key] = category.id
                ordered.append(category)
                parentID = category.id
            }
        }
        return (ordered, idsByPath)
    }

    private static func transactionAmount(_ lines: [String], currency: String) throws -> Money {
        for line in lines where line.first == "T" || line.first == "U" {
            return try qifMoney(String(line.dropFirst()), currency: currency)
        }
        throw FinanceError.invalidAmount("")
    }

    private static func transaction(
        _ lines: [String],
        account: FinanceAccount,
        categoryIDs: [String: UUID],
        fingerprint: String
    ) throws -> FinanceTransaction {
        var date: Date?
        var amount: Money?
        var payee = ""
        var memo = ""
        var reference = ""
        var categoryID: UUID?
        var splitDrafts: [(categoryID: UUID?, memo: String, amount: Money)] = []
        var pendingSplitCategoryID: UUID?
        var pendingSplitMemo = ""
        for line in lines {
            guard let code = line.first else { continue }
            let value = String(line.dropFirst())
            switch code {
            case "D": date = parseDate(value)
            case "T", "U":
                if amount == nil { amount = try qifMoney(value, currency: account.currency) }
            case "P": payee = value
            case "M": memo = value
            case "N": reference = value
            case "L":
                categoryID = categoryPath(value).flatMap { categoryIDs[categoryKey($0)] }
            case "S":
                pendingSplitCategoryID = categoryPath(value).flatMap { categoryIDs[categoryKey($0)] }
            case "E": pendingSplitMemo = value
            case "$":
                splitDrafts.append(
                    (
                        pendingSplitCategoryID,
                        pendingSplitMemo,
                        try qifMoney(value, currency: account.currency)
                    )
                )
                pendingSplitCategoryID = nil
                pendingSplitMemo = ""
            default: break
            }
        }
        guard let date, let amount else { throw FinanceError.invalidAmount("") }
        let splits = splitDrafts.enumerated().map {
            FinanceSplit(
                id: UUID(), categoryID: $0.element.categoryID,
                amountMinor: $0.element.amount.minorUnits,
                memo: $0.element.memo, sortOrder: $0.offset
            )
        }
        let value = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: date, valueDate: nil,
            payee: payee, purpose: memo, categoryID: splits.isEmpty ? categoryID : nil,
            amountMinor: amount.minorUnits, currency: account.currency,
            status: .booked, memo: "", reference: reference,
            transferID: nil, importFingerprint: fingerprint, splits: splits
        )
        try value.validate()
        return value
    }

    private static func qifMoney(_ text: String, currency: String) throws -> Money {
        var normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00a0}", with: "")
            .replacingOccurrences(of: "€", with: "")
        let negativeParentheses = normalized.hasPrefix("(") && normalized.hasSuffix(")")
        if negativeParentheses {
            normalized.removeFirst()
            normalized.removeLast()
        }
        if let comma = normalized.lastIndex(of: ","),
           let dot = normalized.lastIndex(of: ".") {
            if comma < dot {
                normalized = normalized.replacingOccurrences(of: ",", with: "")
            } else {
                normalized = normalized.replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: ",", with: ".")
            }
        } else if let comma = normalized.lastIndex(of: ",") {
            let decimals = normalized.distance(from: comma, to: normalized.endIndex) - 1
            normalized = decimals <= 2
                ? normalized.replacingOccurrences(of: ",", with: ".")
                : normalized.replacingOccurrences(of: ",", with: "")
        }
        if negativeParentheses { normalized = "-" + normalized }
        return try Money(parsing: normalized, currency: currency)
    }

    private static func parseDate(_ text: String) -> Date? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "'", with: "/")
            .replacingOccurrences(of: ".", with: "/")
        for format in ["M/d/yyyy", "M/d/yy", "MM/dd/yyyy", "MM/dd/yy", "dd/MM/yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = format
            if let value = formatter.date(from: cleaned) { return value }
        }
        return nil
    }
}
