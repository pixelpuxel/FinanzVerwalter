import Foundation

enum BankingCalendarProfile: String, Codable, CaseIterable, Identifiable, Sendable {
    case targetEuroV1 = "target-euro-v1"
    case weekdaysV1 = "weekdays-v1"

    var id: Self { self }

    var title: String {
        switch self {
        case .targetEuroV1: "TARGET-Euro-Kalender v1"
        case .weekdaysV1: "Nur Montag bis Freitag v1"
        }
    }

    var shortTitle: String {
        switch self {
        case .targetEuroV1: "TARGET-Euro v1"
        case .weekdaysV1: "Wochentage v1"
        }
    }

    var version: Int { 1 }

    var sourceDescription: String {
        switch self {
        case .targetEuroV1:
            "TARGET-Schließtage: 1. Januar, Karfreitag, Ostermontag, 1. Mai, 25. und 26. Dezember"
        case .weekdaysV1:
            "Nur Samstag und Sonntag sind geschlossen"
        }
    }

    func closureName(on date: Date, calendar suppliedCalendar: Calendar = .current) -> String? {
        var calendar = suppliedCalendar
        calendar.locale = Locale(identifier: "en_US_POSIX")
        guard !calendar.isDateInWeekend(date) else { return "Wochenende" }
        guard self == .targetEuroV1 else { return nil }

        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else { return "Ungültiges Datum" }
        switch (month, day) {
        case (1, 1): return "Neujahr"
        case (5, 1): return "Tag der Arbeit"
        case (12, 25): return "1. Weihnachtstag"
        case (12, 26): return "2. Weihnachtstag"
        default: break
        }

        guard let easterSunday = Self.easterSunday(year: year, calendar: calendar),
              let goodFriday = calendar.date(byAdding: .day, value: -2, to: easterSunday),
              let easterMonday = calendar.date(byAdding: .day, value: 1, to: easterSunday)
        else { return "Ungültiges Datum" }
        if calendar.isDate(date, inSameDayAs: goodFriday) { return "Karfreitag" }
        if calendar.isDate(date, inSameDayAs: easterMonday) { return "Ostermontag" }
        return nil
    }

    func isBusinessDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        closureName(on: date, calendar: calendar) == nil
    }

    func adjusted(
        _ date: Date,
        direction: BusinessDayAdjustment,
        calendar: Calendar = .current
    ) -> Date {
        guard direction != .none else { return date }
        var result = date
        let step = direction == .nextWeekday ? 1 : -1
        for _ in 0..<14 {
            if isBusinessDay(result, calendar: calendar) { return result }
            guard let next = calendar.date(byAdding: .day, value: step, to: result) else {
                return result
            }
            result = next
        }
        return result
    }

    private static func easterSunday(year: Int, calendar: Calendar) -> Date? {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
