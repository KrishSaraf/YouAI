import Foundation
import SwiftData

/// First-launch content, so the exercise library and habit list aren't empty
/// boxes the user has to fill before the app does anything.
enum SeedData {

    static let exercises: [(String, String)] = [
        ("Barbell Bench Press", "Chest"),
        ("Incline Dumbbell Press", "Chest"),
        ("Cable Fly", "Chest"),
        ("Push-Up", "Chest"),
        ("Pull-Up", "Back"),
        ("Barbell Row", "Back"),
        ("Lat Pulldown", "Back"),
        ("Seated Cable Row", "Back"),
        ("Deadlift", "Back"),
        ("Back Squat", "Legs"),
        ("Front Squat", "Legs"),
        ("Leg Press", "Legs"),
        ("Romanian Deadlift", "Legs"),
        ("Leg Extension", "Legs"),
        ("Leg Curl", "Legs"),
        ("Walking Lunge", "Legs"),
        ("Calf Raise", "Legs"),
        ("Overhead Press", "Shoulders"),
        ("Dumbbell Shoulder Press", "Shoulders"),
        ("Lateral Raise", "Shoulders"),
        ("Face Pull", "Shoulders"),
        ("Barbell Curl", "Arms"),
        ("Dumbbell Curl", "Arms"),
        ("Hammer Curl", "Arms"),
        ("Triceps Pushdown", "Arms"),
        ("Skull Crusher", "Arms"),
        ("Dip", "Arms"),
        ("Plank", "Core"),
        ("Hanging Leg Raise", "Core"),
        ("Cable Crunch", "Core"),
        ("Back Extension", "Core"),
    ]

    static let habits: [(String, String)] = [
        ("Train", "figure.strengthtraining.traditional"),
        ("10k steps", "figure.walk"),
        ("Protein target", "fork.knife"),
        ("Sleep 7h+", "bed.double"),
        ("Drink 2L water", "drop"),
    ]

    static func seedIfNeeded(in context: ModelContext) {
        seedExercises(in: context)
        seedHabits(in: context)

        if context.hasChanges {
            try? context.save()
        }
    }

    private static func seedExercises(in context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0
        guard existing == 0 else { return }

        for (name, group) in exercises {
            context.insert(Exercise(name: name, muscleGroup: group))
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
