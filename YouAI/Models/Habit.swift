import Foundation
import SwiftData

@Model
final class Habit {
    var cloudID: String = ""
    var name: String = ""
    var symbol: String = "checkmark.circle"
    var isActive: Bool = true
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \HabitTick.habit)
    var ticks: [HabitTick] = []

    init(name: String, symbol: String = "checkmark.circle", isActive: Bool = true) {
        self.name = name
        self.symbol = symbol
        self.isActive = isActive
        self.createdAt = Date()
    }

    /// Ticks are stored normalised to the start of their day, so day-equality is a plain `==`.
    func isTicked(on day: Date, calendar: Calendar = .current) -> Bool {
        let target = calendar.startOfDay(for: day)
        return ticks.contains { $0.day == target }
    }

    func tick(for day: Date, calendar: Calendar = .current) -> HabitTick? {
        let target = calendar.startOfDay(for: day)
        return ticks.first { $0.day == target }
    }
}

@Model
final class HabitTick {
    var day: Date = Date()
    var habit: Habit?

    init(day: Date, habit: Habit? = nil, calendar: Calendar = .current) {
        self.day = calendar.startOfDay(for: day)
        self.habit = habit
    }
}
