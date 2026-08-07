import Foundation

enum TaxAssessmentType: String, Codable, CaseIterable, Identifiable, Sendable {
    case individual
    case joint

    var id: Self { self }

    var title: String {
        switch self {
        case .individual: "Einzelauftrag"
        case .joint: "Gemeinsamer Auftrag"
        }
    }
}

struct TaxPerson: Identifiable, Hashable, Sendable {
    let id: UUID
    var displayName: String
    var taxIDLastFour: String
    var taxIDConfirmed: Bool
    var isActive: Bool
}

struct TaxAllowanceRule: Identifiable, Hashable, Sendable {
    let id: UUID
    var effectiveFromYear: Int
    var effectiveThroughYear: Int?
    var assessmentType: TaxAssessmentType
    var allowanceMinor: Int64
    var sourceName: String
    var sourceURL: String

    func applies(to year: Int, assessmentType: TaxAssessmentType) -> Bool {
        self.assessmentType == assessmentType
            && year >= effectiveFromYear
            && (effectiveThroughYear == nil || year <= effectiveThroughYear!)
    }
}

struct TaxAllowanceOrder: Identifiable, Hashable, Sendable {
    let id: UUID
    var institution: String
    var assessmentType: TaxAssessmentType
    var primaryPersonID: UUID
    var partnerPersonID: UUID?
    var allowanceMinor: Int64
    var validFromYear: Int
    var validThroughYear: Int?
    var accountIDs: Set<UUID>
    var note: String
    var isActive: Bool

    func applies(to year: Int) -> Bool {
        isActive && covers(year)
    }

    func covers(_ year: Int) -> Bool {
        year >= validFromYear
            && (validThroughYear == nil || year <= validThroughYear!)
    }

    var subjectKey: String {
        if assessmentType == .joint, let partnerPersonID {
            return [primaryPersonID.uuidString, partnerPersonID.uuidString]
                .sorted().joined(separator: ":")
        }
        return primaryPersonID.uuidString
    }
}

struct TaxAllowanceUsage: Identifiable, Hashable, Sendable {
    let id: UUID
    var orderID: UUID
    var taxYear: Int
    var usedMinor: Int64
}

struct TaxAllowanceReportQuery: Codable, Equatable, Sendable {
    var taxYear: Int
    var personIDs = Set<UUID>()
    var institutionText = ""
    var includeInactive = false
}

struct TaxAllowanceReportRow: Identifiable, Equatable, Sendable {
    let id: UUID
    let institution: String
    let holderNames: String
    let assessmentType: TaxAssessmentType
    let allowanceMinor: Int64
    let usedMinor: Int64
    let remainingMinor: Int64
    let legalLimitMinor: Int64
    let accountNames: String
    let validity: String
    let taxIDComplete: Bool
    let subjectKey: String
}

struct TaxAllowanceReportSubjectTotal: Identifiable, Equatable, Sendable {
    var id: String { subjectKey }
    let subjectKey: String
    let holderNames: String
    let legalLimitMinor: Int64
    let allocatedMinor: Int64
    let usedMinor: Int64

    var remainingAllocationMinor: Int64 { legalLimitMinor - allocatedMinor }
    var unusedOrderMinor: Int64 { allocatedMinor - usedMinor }
}

struct TaxAllowanceReportSnapshot: Equatable, Sendable {
    let taxYear: Int
    let rows: [TaxAllowanceReportRow]
    let subjectTotals: [TaxAllowanceReportSubjectTotal]

    var allocatedMinor: Int64 { rows.reduce(0) { $0 + $1.allowanceMinor } }
    var usedMinor: Int64 { rows.reduce(0) { $0 + $1.usedMinor } }
    var unusedOrderMinor: Int64 { allocatedMinor - usedMinor }
}

enum TaxAllowanceRuleEngine {
    static func rule(
        for year: Int,
        assessmentType: TaxAssessmentType,
        rules: [TaxAllowanceRule]
    ) -> TaxAllowanceRule? {
        rules.filter { $0.applies(to: year, assessmentType: assessmentType) }
            .max { $0.effectiveFromYear < $1.effectiveFromYear }
    }

    static func validate(
        order: TaxAllowanceOrder,
        replacingExisting: TaxAllowanceOrder? = nil,
        orders: [TaxAllowanceOrder],
        usages: [TaxAllowanceUsage],
        people: [TaxPerson],
        accounts: [FinanceAccount],
        rules: [TaxAllowanceRule],
        currentYear: Int = Calendar.current.component(.year, from: Date())
    ) throws {
        let institution = order.institution.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !institution.isEmpty, order.allowanceMinor >= 0,
              (1900...2200).contains(order.validFromYear),
              order.validThroughYear == nil || order.validThroughYear! >= order.validFromYear,
              people.contains(where: { $0.id == order.primaryPersonID && $0.isActive })
        else { throw FinanceError.database("Die Angaben zum Freistellungsauftrag sind unvollständig.") }
        if order.assessmentType == .joint {
            guard let partnerID = order.partnerPersonID,
                  partnerID != order.primaryPersonID,
                  people.contains(where: { $0.id == partnerID && $0.isActive })
            else { throw FinanceError.database("Ein gemeinsamer Auftrag benötigt zwei verschiedene aktive Personen.") }
        } else if order.partnerPersonID != nil {
            throw FinanceError.database("Ein Einzelauftrag darf keine zweite Person enthalten.")
        }
        let coveredAccounts = accounts.filter { order.accountIDs.contains($0.id) }
        guard coveredAccounts.count == order.accountIDs.count else {
            throw FinanceError.database("Mindestens ein zugeordnetes Konto existiert nicht mehr.")
        }
        let normalizedInstitution = normalized(institution)
        guard coveredAccounts.allSatisfy({ normalized($0.institution) == normalizedInstitution }) else {
            throw FinanceError.database("Zugeordnete Konten müssen zum selben Institut wie der Freistellungsauftrag gehören.")
        }
        let existingUsage = usages.filter { $0.orderID == order.id }.map(\.usedMinor).max() ?? 0
        guard order.allowanceMinor >= existingUsage else {
            throw FinanceError.database("Der Betrag darf nicht unter die bereits genutzte Freistellung gesenkt werden.")
        }
        let through = order.validThroughYear ?? max(currentYear, rules.compactMap(\.effectiveThroughYear).max() ?? currentYear)
        let years = Set(
            rules.filter { rule in
                rule.assessmentType == order.assessmentType
                    && rule.effectiveFromYear <= through
                    && (rule.effectiveThroughYear ?? through) >= order.validFromYear
            }.flatMap { rule -> [Int] in
                let start = max(order.validFromYear, rule.effectiveFromYear)
                let end = min(through, rule.effectiveThroughYear ?? through)
                return start <= end ? Array(start...end) : []
            }
        )
        guard !years.isEmpty else {
            throw FinanceError.database("Für den Gültigkeitszeitraum ist kein gesetzliches Regelpaket hinterlegt.")
        }
        let candidates = orders.filter {
            $0.id != replacingExisting?.id && $0.id != order.id
        } + [order]
        for year in years.sorted() {
            let active = candidates.filter { $0.applies(to: year) }
            let joint = active.filter { $0.assessmentType == .joint }
            let jointPairsByPerson = Dictionary(grouping: joint.flatMap { value in
                participantIDs(value).map { ($0, value.subjectKey) }
            }, by: \.0)
            guard jointPairsByPerson.values.allSatisfy({ Set($0.map(\.1)).count <= 1 }) else {
                throw FinanceError.database(
                    "Eine Person kann im Steuerjahr \(year) nicht mehreren gemeinsamen Freistellungsrahmen zugeordnet sein."
                )
            }
            for context in Dictionary(grouping: joint, by: \.subjectKey).values {
                guard let representative = context.first else { continue }
                let participants = participantIDs(representative)
                let allocated = active.filter {
                    !participantIDs($0).isDisjoint(with: participants)
                }.reduce(Int64.zero) { $0 + $1.allowanceMinor }
                guard let limit = rule(
                    for: year, assessmentType: .joint, rules: rules
                )?.allowanceMinor, allocated <= limit else {
                    let maximum = rule(
                        for: year, assessmentType: .joint, rules: rules
                    )?.allowanceMinor ?? 0
                    throw FinanceError.database(
                        "Einzelne und gemeinsame Aufträge überschreiten im Steuerjahr \(year) den gemeinsamen Höchstbetrag von \(Money(minorUnits: maximum).formatted)."
                    )
                }
            }
            let peopleInJointContexts = Set(joint.flatMap { participantIDs($0) })
            let uncoveredIndividuals = active.filter {
                $0.assessmentType == .individual
                    && !peopleInJointContexts.contains($0.primaryPersonID)
            }
            for values in Dictionary(grouping: uncoveredIndividuals, by: \.primaryPersonID).values {
                let allocated = values.reduce(Int64.zero) { $0 + $1.allowanceMinor }
                guard let limit = rule(
                    for: year, assessmentType: .individual, rules: rules
                )?.allowanceMinor, allocated <= limit else {
                    let maximum = rule(
                        for: year, assessmentType: .individual, rules: rules
                    )?.allowanceMinor ?? 0
                    throw FinanceError.database(
                        "Die Einzelaufträge überschreiten im Steuerjahr \(year) den Höchstbetrag von \(Money(minorUnits: maximum).formatted)."
                    )
                }
            }
        }
    }

    static func validateUsage(
        _ usage: TaxAllowanceUsage,
        order: TaxAllowanceOrder?
    ) throws {
        guard let order, order.applies(to: usage.taxYear), usage.usedMinor >= 0,
              usage.usedMinor <= order.allowanceMinor
        else {
            throw FinanceError.database("Die Nutzung muss im Gültigkeitsjahr liegen und darf den Auftragsbetrag nicht überschreiten.")
        }
    }

    static func snapshot(
        query: TaxAllowanceReportQuery,
        orders: [TaxAllowanceOrder],
        usages: [TaxAllowanceUsage],
        people: [TaxPerson],
        accounts: [FinanceAccount],
        rules: [TaxAllowanceRule]
    ) -> TaxAllowanceReportSnapshot {
        let peopleByID = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let usageByOrder = Dictionary(
            uniqueKeysWithValues: usages.filter { $0.taxYear == query.taxYear }.map { ($0.orderID, $0) }
        )
        let needle = query.institutionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = orders.filter { order in
            (query.includeInactive || order.isActive) && order.covers(query.taxYear)
                && (query.personIDs.isEmpty
                    || query.personIDs.contains(order.primaryPersonID)
                    || order.partnerPersonID.map(query.personIDs.contains) == true)
                && (needle.isEmpty || order.institution.localizedStandardContains(needle))
        }
        let jointContextByPerson = Dictionary(
            selected.filter { $0.assessmentType == .joint && $0.applies(to: query.taxYear) }
                .flatMap { order in participantIDs(order).map { ($0, order.subjectKey) } },
            uniquingKeysWith: { first, _ in first }
        )
        let rows = selected.map { order -> TaxAllowanceReportRow in
            let holderPeople = [peopleByID[order.primaryPersonID], order.partnerPersonID.flatMap { peopleByID[$0] }]
                .compactMap { $0 }
            let holderNames = holderPeople.map(\.displayName).joined(separator: " & ")
            let used = usageByOrder[order.id]?.usedMinor ?? 0
            let accountNames = order.accountIDs.compactMap { accountsByID[$0]?.name }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .joined(separator: ", ")
            let validity = order.validThroughYear.map { "\(order.validFromYear)–\($0)" }
                ?? "ab \(order.validFromYear)"
            return TaxAllowanceReportRow(
                id: order.id, institution: order.institution,
                holderNames: holderNames, assessmentType: order.assessmentType,
                allowanceMinor: order.allowanceMinor, usedMinor: used,
                remainingMinor: order.allowanceMinor - used,
                legalLimitMinor: rule(
                    for: query.taxYear, assessmentType: order.assessmentType, rules: rules
                )?.allowanceMinor ?? 0,
                accountNames: accountNames.isEmpty ? "Alle Konten des Instituts" : accountNames,
                validity: validity,
                taxIDComplete: !holderPeople.isEmpty && holderPeople.allSatisfy(\.taxIDConfirmed),
                subjectKey: order.assessmentType == .joint
                    ? order.subjectKey
                    : jointContextByPerson[order.primaryPersonID] ?? order.subjectKey
            )
        }.sorted {
            let holderOrder = $0.holderNames.localizedCaseInsensitiveCompare($1.holderNames)
            if holderOrder != .orderedSame { return holderOrder == .orderedAscending }
            let institutionOrder = $0.institution.localizedCaseInsensitiveCompare($1.institution)
            return institutionOrder == .orderedSame ? $0.id.uuidString < $1.id.uuidString
                : institutionOrder == .orderedAscending
        }
        let groupedRows: [String: [TaxAllowanceReportRow]] = Dictionary(
            grouping: rows, by: \.subjectKey
        )
        var totals: [TaxAllowanceReportSubjectTotal] = groupedRows.map { key, values in
            let holderNames = key.split(separator: ":").compactMap {
                UUID(uuidString: String($0)).flatMap { peopleByID[$0]?.displayName }
            }.joined(separator: " & ")
            return TaxAllowanceReportSubjectTotal(
                subjectKey: key,
                holderNames: holderNames.isEmpty ? values.first?.holderNames ?? "" : holderNames,
                legalLimitMinor: values.map(\.legalLimitMinor).max() ?? 0,
                allocatedMinor: values.reduce(0) { $0 + $1.allowanceMinor },
                usedMinor: values.reduce(0) { $0 + $1.usedMinor }
            )
        }
        totals.sort {
            $0.holderNames.localizedCaseInsensitiveCompare($1.holderNames) == .orderedAscending
        }
        return TaxAllowanceReportSnapshot(taxYear: query.taxYear, rows: rows, subjectTotals: totals)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func participantIDs(_ order: TaxAllowanceOrder) -> Set<UUID> {
        Set([order.primaryPersonID] + (order.partnerPersonID.map { [$0] } ?? []))
    }
}

enum TaxAllowanceReportCSVExporter {
    static func data(snapshot: TaxAllowanceReportSnapshot, generatedAt: Date) -> Data {
        var lines = [
            csv(["Bericht", "Freistellungsaufträge"]),
            csv(["Steuerjahr", String(snapshot.taxYear)]),
            csv(["Erstellt", ISO8601DateFormatter().string(from: generatedAt)]),
            "",
            csv(["Institut", "Person/en", "Art", "Auftrag", "Genutzt", "Rest",
                 "Gesetzliches Maximum", "Gültigkeit", "Steuer-ID bestätigt", "Kontenabdeckung"])
        ]
        lines += snapshot.rows.map { row in
            csv([row.institution, row.holderNames, row.assessmentType.title,
                 decimal(row.allowanceMinor), decimal(row.usedMinor), decimal(row.remainingMinor),
                 decimal(row.legalLimitMinor), row.validity, row.taxIDComplete ? "Ja" : "Nein",
                 row.accountNames])
        }
        lines += ["", csv(["Person/en", "Gesetzliches Maximum", "Verteilt", "Genutzt",
                             "Noch verteilbar", "Im Auftrag ungenutzt"])]
        lines += snapshot.subjectTotals.map { total in
            csv([total.holderNames, decimal(total.legalLimitMinor), decimal(total.allocatedMinor),
                 decimal(total.usedMinor), decimal(total.remainingAllocationMinor),
                 decimal(total.unusedOrderMinor)])
        }
        return Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    private static func csv(_ values: [String]) -> String {
        values.map { value in
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return escaped.contains(";") || escaped.contains("\"")
                || escaped.contains("\n") || escaped.contains("\r")
                ? "\"\(escaped)\"" : escaped
        }.joined(separator: ";")
    }

    private static func decimal(_ minor: Int64) -> String {
        let sign = minor < 0 ? "-" : ""
        let magnitude = minor.magnitude
        return "\(sign)\(magnitude / 100),\(String(format: "%02llu", magnitude % 100))"
    }
}
