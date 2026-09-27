import HealthKit

extension HKWorkoutActivityType {
    /// Covers the activity types likely to come off an Apple Watch; anything else
    /// falls through to a generic label rather than showing a raw number.
    var displayName: String {
        switch self {
        case .running: "Run"
        case .walking: "Walk"
        case .cycling: "Cycle"
        case .hiking: "Hike"
        case .swimming: "Swim"
        case .traditionalStrengthTraining: "Strength Training"
        case .functionalStrengthTraining: "Functional Strength"
        case .highIntensityIntervalTraining: "HIIT"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .coreTraining: "Core Training"
        case .rowing: "Rowing"
        case .elliptical: "Elliptical"
        case .stairClimbing, .stairs: "Stair Climbing"
        case .dance, .cardioDance: "Dance"
        case .boxing, .kickboxing: "Boxing"
        case .soccer: "Soccer"
        case .basketball: "Basketball"
        case .tennis: "Tennis"
        case .golf: "Golf"
        case .cooldown: "Cooldown"
        case .flexibility: "Stretching"
        case .mixedCardio: "Mixed Cardio"
        default: "Workout"
        }
    }

    var symbolName: String {
        switch self {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .cycling: "figure.outdoor.cycle"
        case .hiking: "figure.hiking"
        case .swimming: "figure.pool.swim"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "figure.strengthtraining.traditional"
        case .highIntensityIntervalTraining: "figure.highintensity.intervaltraining"
        case .yoga: "figure.yoga"
        case .pilates: "figure.pilates"
        case .coreTraining: "figure.core.training"
        case .rowing: "figure.rower"
        case .elliptical: "figure.elliptical"
        case .stairClimbing, .stairs: "figure.stair.stepper"
        case .dance, .cardioDance: "figure.dance"
        case .boxing, .kickboxing: "figure.boxing"
        case .soccer: "figure.soccer"
        case .basketball: "figure.basketball"
        case .tennis: "figure.tennis"
        case .golf: "figure.golf"
        case .flexibility, .cooldown: "figure.flexibility"
        default: "figure.mixed.cardio"
        }
    }
}
