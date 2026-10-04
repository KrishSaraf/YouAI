import Foundation
import SwiftData

/// First-launch habits. Exercises come from the bundled catalog, not a short seed list.
enum SeedData {

    static let habits: [(String, String)] = [
        ("Train", "figure.strengthtraining.traditional"),
        ("Protein", "fish.fill"),
        ("Drink 2L water", "drop"),
    ]

    /// Habits that belong in Apple Health, not as manual checkboxes.
    static let retiredHabitNames: Set<String> = [
        "10k steps",
        "sleep 7h+",
    ]

    static func seedIfNeeded(in context: ModelContext) {
        seedHabits(in: context)

        if context.hasChanges {
            try? context.save()
        }
    }

    private static func seedHabits(in context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Habit>())) ?? 0
        guard existing == 0 else { return }

        for (name, symbol) in habits {
            context.insert(Habit(name: name, symbol: symbol))
        }
    }

    /// Habits Apple Health already covers, plus the old Protein label.
    static func tidyHabits(in context: ModelContext) -> (removedCloudIDs: [String], renamed: [Habit]) {
        let all = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        var removedCloudIDs: [String] = []
        var renamed: [Habit] = []

        for habit in all {
            let key = habit.name.lowercased()
            if Self.retiredHabitNames.contains(key) {
                if !habit.cloudID.isEmpty { removedCloudIDs.append(habit.cloudID) }
                context.delete(habit)
                continue
            }
            if key == "protein target" || (key == "protein" && habit.symbol == "fork.knife") {
                habit.name = "Protein"
                habit.symbol = "fish.fill"
                renamed.append(habit)
            }
        }

        if context.hasChanges { try? context.save() }
        return (removedCloudIDs, renamed)
    }
}
