import Foundation

enum Fmt {

    /// Whole numbers with thousands separators — steps, calories, kcal goals.
    static func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    /// One decimal place, for weights and litres.
    static func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    /// Drops a trailing ".0" so 80 kg reads "80" but 80.5 reads "80.5".
    static func weight(_ value: Double) -> String {
        value.rounded() == value ? whole(value) : oneDecimal(value)
    }

    static func grams(_ value: Double) -> String {
        "\(whole(value))g"
    }

    /// "7h 32m" — used for sleep and workout durations.
    static func hoursMinutes(_ hours: Double) -> String {
        let totalMinutes = Int((hours * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        hoursMinutes(seconds / 3600)
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Today" / "Yesterday" / a date, for grouping history lists.
    static func relativeDay(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return day(date)
    }

    static func kilograms(_ kg: Double, in unit: WeightUnit) -> Double {
        unit == .kilograms ? kg : kg * 2.2046226218
    }

    static func toKilograms(_ value: Double, from unit: WeightUnit) -> Double {
        unit == .kilograms ? value : value / 2.2046226218
    }
}

extension Date {
    /// The seven days ending today, oldest first — the habit-card week strip.
    static func trailingWeek(endingOn day: Date = Date(), calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: day)
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }
}
