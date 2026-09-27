import Foundation
import HealthKit

/// The exact set of Health types the app touches. Kept in one place so the
/// authorization request and the individual queries can never drift apart.
enum HealthTypes {

    static let bodyMass = HKQuantityType(.bodyMass)
    static let stepCount = HKQuantityType(.stepCount)
    static let activeEnergyBurned = HKQuantityType(.activeEnergyBurned)
    static let appleExerciseTime = HKQuantityType(.appleExerciseTime)
    static let appleStandTime = HKQuantityType(.appleStandTime)
    static let heartRate = HKQuantityType(.heartRate)
    static let restingHeartRate = HKQuantityType(.restingHeartRate)
    static let dietaryEnergy = HKQuantityType(.dietaryEnergyConsumed)
    static let dietaryProtein = HKQuantityType(.dietaryProtein)
    static let dietaryCarbs = HKQuantityType(.dietaryCarbohydrates)
    static let dietaryFat = HKQuantityType(.dietaryFatTotal)
    static let dietaryWater = HKQuantityType(.dietaryWater)
    static let bloodPressureSystolic = HKQuantityType(.bloodPressureSystolic)
    static let bloodPressureDiastolic = HKQuantityType(.bloodPressureDiastolic)
    static let bodyTemperature = HKQuantityType(.bodyTemperature)
    static let oxygenSaturation = HKQuantityType(.oxygenSaturation)
    static let sleepAnalysis = HKCategoryType(.sleepAnalysis)

    /// HealthKit has no ready-made bpm unit; it has to be composed.
    static let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

    static var read: Set<HKObjectType> {
        [
            bodyMass, stepCount, activeEnergyBurned, appleExerciseTime, appleStandTime,
            heartRate, restingHeartRate,
            dietaryEnergy, dietaryProtein, dietaryCarbs, dietaryFat, dietaryWater,
            bloodPressureSystolic, bloodPressureDiastolic, bodyTemperature, oxygenSaturation,
            sleepAnalysis,
            HKObjectType.workoutType(),
            HKObjectType.activitySummaryType(),
        ]
    }

    static var write: Set<HKSampleType> {
        [
            bodyMass,
            dietaryEnergy, dietaryProtein, dietaryCarbs, dietaryFat, dietaryWater,
            bloodPressureSystolic, bloodPressureDiastolic, bodyTemperature, oxygenSaturation,
            sleepAnalysis,
            HKObjectType.workoutType(),
        ]
    }

    /// Sleep category values that count as actually asleep (as opposed to in bed or awake).
    static let asleepValues: Set<Int> = [
        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
    ]
}

enum WeightUnit: String, CaseIterable, Identifiable {
    case kilograms, pounds

    var id: String { rawValue }
    var label: String { self == .kilograms ? "kg" : "lb" }
    var hkUnit: HKUnit { self == .kilograms ? .gramUnit(with: .kilo) : .pound() }
}

/// A day's activity rings, straight from `HKActivitySummary` so the goals are
/// the user's real goals rather than numbers the app invented.
struct ActivityRings: Equatable {
    var moveKcal: Double = 0
    var moveGoalKcal: Double = 0
    var exerciseMinutes: Double = 0
    var exerciseGoalMinutes: Double = 0
    var standHours: Double = 0
    var standGoalHours: Double = 0

    private static func fraction(_ value: Double, _ goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return min(value / goal, 1)
    }

    var moveFraction: Double { Self.fraction(moveKcal, moveGoalKcal) }
    var exerciseFraction: Double { Self.fraction(exerciseMinutes, exerciseGoalMinutes) }
    var standFraction: Double { Self.fraction(standHours, standGoalHours) }

    var isEmpty: Bool { moveKcal == 0 && exerciseMinutes == 0 && standHours == 0 }
}

struct WeightPoint: Identifiable, Equatable {
    let date: Date
    let kilograms: Double
    var id: Date { date }
}

struct WorkoutSummary: Identifiable, Equatable {
    let id: UUID
    let activityName: String
    let symbol: String
    let start: Date
    let duration: TimeInterval
    let energyKcal: Double?
    let sourceName: String
}
