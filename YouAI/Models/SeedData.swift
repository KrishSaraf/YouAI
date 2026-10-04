import Foundation
import SwiftData

/// First-launch habits. Exercises come from the bundled catalog, not a short seed list.
enum SeedData {

    static let habits: [(String, String)] = [
        ("Train", "figure.strengthtraining.traditional"),
        ("10k steps", "figure.walk"),
        ("Protein target", "fork.knife"),
        ("Sleep 7h+", "bed.double"),
        ("Drink 2L water", "drop"),
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
}
