import Foundation
import SwiftData

@Model
final class WorkoutSession {
    var cloudID: String = ""
    var name: String = ""
    var date: Date = Date()
    var notes: String = ""
    var durationMinutes: Double = 60
    /// Set when this session has been mirrored into HealthKit as an HKWorkout, so edits can revise it.
    var healthKitWorkoutID: String?

    @Relationship(deleteRule: .cascade, inverse: \SessionExercise.session)
    var exercises: [SessionExercise] = []

    init(name: String, date: Date = Date(), notes: String = "") {
        self.name = name
        self.date = date
        self.notes = notes
    }

    var orderedExercises: [SessionExercise] {
        exercises.sorted { $0.order < $1.order }
    }

    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    /// Sum of kg x reps across every set — a rough stand-in for session volume.
    var totalVolumeKg: Double {
        exercises.flatMap(\.sets).reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    }
}

@Model
final class SessionExercise {
    /// Denormalised on purpose: renaming or deleting a library `Exercise` must not rewrite history.
    var name: String = ""
    var order: Int = 0
    var session: WorkoutSession?

    @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.exercise)
    var sets: [ExerciseSet] = []

    init(name: String, order: Int = 0) {
        self.name = name
        self.order = order
    }

    var orderedSets: [ExerciseSet] {
        sets.sorted { $0.order < $1.order }
    }
}

@Model
final class ExerciseSet {
    var weightKg: Double = 0
    var reps: Int = 0
    var order: Int = 0
    var exercise: SessionExercise?

    init(weightKg: Double, reps: Int, order: Int = 0) {
        self.weightKg = weightKg
        self.reps = reps
        self.order = order
    }
}

/// Library of exercise names, seeded on first launch and extendable by the user.
@Model
final class Exercise {
    var cloudID: String = ""
    @Attribute(.unique) var name: String = ""
    var muscleGroup: String = ""
    var isCustom: Bool = false

    init(name: String, muscleGroup: String, isCustom: Bool = false) {
        self.name = name
        self.muscleGroup = muscleGroup
        self.isCustom = isCustom
    }
}
