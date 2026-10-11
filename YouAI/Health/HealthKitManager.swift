import Foundation
import HealthKit
import Observation

/// Single facade over HealthKit. Everything the UI needs is published here as
/// plain values, so no view ever touches `HKHealthStore` directly.
@MainActor
@Observable
final class HealthKitManager {

    // MARK: - Published state

    var isHealthDataAvailable = HKHealthStore.isHealthDataAvailable()
    var hasRequestedAuthorization = false
    var lastError: String?

    var rings = ActivityRings()
    var steps: Double = 0
    var sleepHours: Double = 0
    var restingHeartRate: Double?
    var averageHeartRate: Double?
    var latestWeightKg: Double?
    var latestWeightDate: Date?
    var weightHistory: [WeightPoint] = []
    var recentWorkouts: [WorkoutSummary] = []
    var waterLitresToday: Double = 0

    /// HealthKit deliberately never reveals whether *read* access was granted, so
    /// "connected" can only ever be inferred. We treat "we asked, and at least one
    /// read returned something" as connected, and surface a banner otherwise.
    var appearsConnected: Bool {
        !rings.isEmpty || steps > 0 || latestWeightKg != nil || !recentWorkouts.isEmpty || sleepHours > 0
    }

    private let store = HKHealthStore()
    private let calendar = Calendar.current

    // MARK: - Authorization

    func requestAuthorization() async {
        guard isHealthDataAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: HealthTypes.write, read: HealthTypes.read)
            hasRequestedAuthorization = true
        } catch {
            lastError = "Health access request failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Refresh

    /// Reloads everything the Today and Health tabs display. Runs the independent
    /// queries concurrently, since each is its own round trip to the Health store.
    func refresh(for day: Date = Date()) async {
        guard isHealthDataAvailable else { return }

        async let rings = activityRings(for: day)
        async let steps = sum(HealthTypes.stepCount, unit: .count(), on: day)
        async let sleep = asleepHours(endingOn: day)
        async let resting = average(HealthTypes.restingHeartRate, unit: HealthTypes.beatsPerMinute, on: day)
        async let heart = average(HealthTypes.heartRate, unit: HealthTypes.beatsPerMinute, on: day)
        async let weight = latestWeight()
        async let history = weightSeries(days: 90, endingOn: day)
        async let workouts = workouts(limit: 20)
        async let water = sum(HealthTypes.dietaryWater, unit: .liter(), on: day)

        self.rings = await rings
        self.steps = await steps
        self.sleepHours = await sleep
        self.restingHeartRate = await resting
        self.averageHeartRate = await heart
        if let weight = await weight {
            self.latestWeightKg = weight.kilograms
            self.latestWeightDate = weight.date
        }
        self.weightHistory = await history
        self.recentWorkouts = await workouts
        self.waterLitresToday = await water
    }

    // MARK: - Rings

    func activityRings(for day: Date) async -> ActivityRings {
        var components = calendar.dateComponents([.era, .year, .month, .day], from: day)
        components.calendar = calendar
        let predicate = HKQuery.predicateForActivitySummary(with: components)

        let summaries: [HKActivitySummary] = await withCheckedContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                continuation.resume(returning: summaries ?? [])
            }
            store.execute(query)
        }

        guard let summary = summaries.first else { return ActivityRings() }

        // Fall back to Apple's own defaults when a goal isn't set, so a ring with
        // real progress and no goal still renders instead of showing as empty.
        let exerciseGoal = summary.exerciseTimeGoal?.doubleValue(for: .minute()) ?? 30
        let standGoal = summary.standHoursGoal?.doubleValue(for: .count()) ?? 12

        return ActivityRings(
            moveKcal: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
            moveGoalKcal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
            exerciseMinutes: summary.appleExerciseTime.doubleValue(for: .minute()),
            exerciseGoalMinutes: exerciseGoal,
            standHours: summary.appleStandHours.doubleValue(for: .count()),
            standGoalHours: standGoal
        )
    }

    // MARK: - Statistics helpers

    func sum(_ type: HKQuantityType, unit: HKUnit, on day: Date) async -> Double {
        let interval = dayInterval(for: day)
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
        return await statistic(type, unit: unit, predicate: predicate, options: .cumulativeSum) { $0.sumQuantity() } ?? 0
    }

    func average(_ type: HKQuantityType, unit: HKUnit, on day: Date) async -> Double? {
        let interval = dayInterval(for: day)
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
        return await statistic(type, unit: unit, predicate: predicate, options: .discreteAverage) { $0.averageQuantity() }
    }

    private func statistic(
        _ type: HKQuantityType,
        unit: HKUnit,
        predicate: NSPredicate,
        options: HKStatisticsOptions,
        extract: @escaping (HKStatistics) -> HKQuantity?
    ) async -> Double? {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: options) { _, statistics, _ in
                guard let statistics, let quantity = extract(statistics) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    // MARK: - Sleep

    /// Hours actually asleep for the night that ends on `day` — i.e. samples from
    /// 18:00 the previous evening through 18:00 on `day`, which is how the Health
    /// app attributes a night's sleep to a morning.
    func asleepHours(endingOn day: Date) async -> Double {
        let end = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day
        let start = calendar.date(byAdding: .hour, value: -24, to: end) ?? day
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HealthTypes.sleepAnalysis, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        let asleep = samples.filter { HealthTypes.asleepValues.contains($0.value) }
        let seconds = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        return seconds / 3600
    }

    // MARK: - Weight

    func latestWeight() async -> WeightPoint? {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HealthTypes.bodyMass, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
        guard let sample = samples.first else { return nil }
        return WeightPoint(date: sample.endDate, kilograms: sample.quantity.doubleValue(for: .gramUnit(with: .kilo)))
    }

    /// One point per day that has a reading, using the daily average so several
    /// weigh-ins on one day collapse to a single sensible value.
    func weightSeries(days: Int, endingOn day: Date) async -> [WeightPoint] {
        let end = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: day) ?? day)
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let collection: HKStatisticsCollection? = await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: HealthTypes.bodyMass,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: start,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                continuation.resume(returning: collection)
            }
            store.execute(query)
        }

        guard let collection else { return [] }
        var points: [WeightPoint] = []
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            if let quantity = statistics.averageQuantity() {
                points.append(WeightPoint(date: statistics.startDate, kilograms: quantity.doubleValue(for: .gramUnit(with: .kilo))))
            }
        }
        return points
    }

    func saveWeight(kilograms: Double, date: Date = Date()) async -> Bool {
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms)
        let sample = HKQuantitySample(type: HealthTypes.bodyMass, quantity: quantity, start: date, end: date)
        return await save([sample])
    }

    // MARK: - Workouts

    func workouts(limit: Int) async -> [WorkoutSummary] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let samples: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: nil, limit: limit, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }

        return samples.map { workout in
            let energy = workout.statistics(for: HealthTypes.activeEnergyBurned)?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie())
            return WorkoutSummary(
                id: workout.uuid,
                activityName: workout.workoutActivityType.displayName,
                symbol: workout.workoutActivityType.symbolName,
                start: workout.startDate,
                duration: workout.duration,
                energyKcal: energy,
                sourceName: workout.sourceRevision.source.name
            )
        }
    }

    /// Mirrors a locally logged strength session into Health so it shows up
    /// alongside Watch workouts. Returns the new workout's UUID string.
    func saveStrengthWorkout(name: String, start: Date, duration: TimeInterval) async -> String? {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        let end = start.addingTimeInterval(duration)

        do {
            try await builder.beginCollection(at: start)
            try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: name])
            try await builder.endCollection(at: end)
            let workout = try await builder.finishWorkout()
            return workout?.uuid.uuidString
        } catch {
            lastError = "Couldn't save the workout to Health: \(error.localizedDescription)"
            return nil
        }
    }

    /// Removes a workout this app wrote, so deleting a session doesn't leave it in Health.
    func deleteWorkout(id: String) async {
        guard let uuid = UUID(uuidString: id) else { return }
        let predicate = HKQuery.predicateForObjects(with: [uuid])
        _ = try? await store.deleteObjects(of: HKObjectType.workoutType(), predicate: predicate)
    }

    // MARK: - Nutrition

    /// Writes a meal's macros as four correlated samples. Returns their UUIDs so
    /// the meal can revise or remove exactly these samples later.
    func saveMeal(
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        date: Date
    ) async -> [String] {
        var samples: [HKQuantitySample] = []

        func add(_ type: HKQuantityType, _ value: Double, _ unit: HKUnit) {
            guard value > 0 else { return }
            let quantity = HKQuantity(unit: unit, doubleValue: value)
            samples.append(HKQuantitySample(type: type, quantity: quantity, start: date, end: date))
        }

        add(HealthTypes.dietaryEnergy, calories, .kilocalorie())
        add(HealthTypes.dietaryProtein, proteinG, .gram())
        add(HealthTypes.dietaryCarbs, carbsG, .gram())
        add(HealthTypes.dietaryFat, fatG, .gram())

        guard !samples.isEmpty, await save(samples) else { return [] }
        return samples.map(\.uuid.uuidString)
    }

    func deleteSamples(ids: [String]) async {
        let uuids = ids.compactMap(UUID.init(uuidString:))
        guard !uuids.isEmpty else { return }
        let predicate = HKQuery.predicateForObjects(with: Set(uuids))

        for type in [HealthTypes.dietaryEnergy, HealthTypes.dietaryProtein, HealthTypes.dietaryCarbs, HealthTypes.dietaryFat] {
            _ = try? await store.deleteObjects(of: type, predicate: predicate)
        }
    }

    func saveWater(litres: Double, date: Date = Date()) async -> Bool {
        let quantity = HKQuantity(unit: .liter(), doubleValue: litres)
        let sample = HKQuantitySample(type: HealthTypes.dietaryWater, quantity: quantity, start: date, end: date)
        return await save([sample])
    }

    // MARK: - Sleep & vitals writing

    func saveSleep(start: Date, end: Date) async -> Bool {
        let sample = HKCategorySample(
            type: HealthTypes.sleepAnalysis,
            value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            start: start,
            end: end
        )
        return await save([sample])
    }

    func saveVitals(
        systolic: Double?,
        diastolic: Double?,
        temperatureC: Double?,
        oxygenPercent: Double?,
        date: Date = Date()
    ) async -> Bool {
        var samples: [HKQuantitySample] = []

        func add(_ type: HKQuantityType, _ value: Double?, _ unit: HKUnit) {
            guard let value, value > 0 else { return }
            let quantity = HKQuantity(unit: unit, doubleValue: value)
            samples.append(HKQuantitySample(type: type, quantity: quantity, start: date, end: date))
        }

        add(HealthTypes.bloodPressureSystolic, systolic, .millimeterOfMercury())
        add(HealthTypes.bloodPressureDiastolic, diastolic, .millimeterOfMercury())
        add(HealthTypes.bodyTemperature, temperatureC, .degreeCelsius())
        // HealthKit stores oxygen saturation as a fraction, not a percentage.
        add(HealthTypes.oxygenSaturation, oxygenPercent.map { $0 / 100 }, .percent())

        guard !samples.isEmpty else { return false }
        return await save(samples)
    }

    // MARK: - Plumbing

    private func save(_ objects: [HKObject]) async -> Bool {
        do {
            try await store.save(objects)
            return true
        } catch {
            lastError = "Couldn't save to Health: \(error.localizedDescription)"
            return false
        }
    }

    private func dayInterval(for day: Date) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }
}
