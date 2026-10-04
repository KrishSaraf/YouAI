import Foundation
import SwiftData
import Supabase

/// Saves the logs that belong to a signed-in account. Apple Health readings the
/// app only displays stay in Apple Health.
extension AccountStore {
    func sync(context: ModelContext, health: HealthKitManager, settings: AppSettings) async {
        guard isSignedIn else { return }
        await dedupeMeals(context: context, health: health)
        await pull(context: context, health: health, settings: settings)
        await dedupeMeals(context: context, health: health)
        await pushAll(context: context, settings: settings)
        await flushPendingHealth()
    }

    func storeMeal(_ meal: Meal) async {
        let id = CloudID.ensure(&meal.cloudID)
        let saved = await upsert(id: id, kind: "meal", payload: RecordPayload(
            name: meal.name,
            mealType: meal.typeRaw,
            loggedAt: CloudDate.string(meal.date),
            calories: meal.calories,
            proteinG: meal.proteinG,
            carbsG: meal.carbsG,
            fatG: meal.fatG,
            wasEstimated: meal.wasEstimated,
            photoBase64: meal.photo?.base64EncodedString()
        ))
        if !saved { meal.cloudID = "" }
    }

    func storeWorkout(_ session: WorkoutSession) async {
        let id = CloudID.ensure(&session.cloudID)
        let exercises = session.orderedExercises.map { exercise in
            CloudExercise(
                name: exercise.name,
                sets: exercise.orderedSets.map { CloudSet(weightKg: $0.weightKg, reps: $0.reps) }
            )
        }
        await upsert(id: id, kind: "workout", payload: RecordPayload(
            name: session.name,
            loggedAt: CloudDate.string(session.date),
            notes: session.notes,
            durationMinutes: session.durationMinutes,
            exercises: exercises
        ))
    }

    func storeHabit(_ habit: Habit) async {
        let id = CloudID.ensure(&habit.cloudID)
        let ticks = habit.ticks.map { CloudDate.string($0.day) }
        await upsert(id: id, kind: "habit", payload: RecordPayload(
            name: habit.name,
            symbol: habit.symbol,
            isActive: habit.isActive,
            createdAt: CloudDate.string(habit.createdAt),
            ticks: ticks
        ))
    }

    func storeExercise(_ exercise: Exercise) async {
        guard exercise.isCustom else { return }
        let id = CloudID.ensure(&exercise.cloudID)
        await upsert(id: id, kind: "exercise", payload: RecordPayload(
            name: exercise.name,
            muscleGroup: exercise.muscleGroup
        ))
    }

    func storeSettings(_ unit: WeightUnit) async {
        guard let userID = currentUserID else { return }
        await upsert(id: userID.uuidString, kind: "settings", payload: RecordPayload(weightUnit: unit.rawValue))
    }

    func storeWeight(kilograms: Double, date: Date) async {
        await storeHealth(kind: "weight", payload: RecordPayload(
            loggedAt: CloudDate.string(date),
            kilograms: kilograms
        ))
    }

    func storeWater(millilitres: Double, date: Date) async {
        await storeHealth(kind: "water", payload: RecordPayload(
            loggedAt: CloudDate.string(date),
            millilitres: millilitres
        ))
    }

    func storeSleep(start: Date, end: Date) async {
        await storeHealth(kind: "sleep", payload: RecordPayload(
            sleepStart: CloudDate.string(start),
            sleepEnd: CloudDate.string(end)
        ))
    }

    func storeVitals(
        systolic: Double?,
        diastolic: Double?,
        temperatureC: Double?,
        oxygenPercent: Double?,
        date: Date
    ) async {
        await storeHealth(kind: "vitals", payload: RecordPayload(
            loggedAt: CloudDate.string(date),
            systolic: systolic,
            diastolic: diastolic,
            temperatureC: temperatureC,
            oxygenPercent: oxygenPercent
        ))
    }

    func removeRecord(_ id: String) async {
        guard !id.isEmpty, let client else { return }
        _ = try? await client.from("user_records").delete().eq("id", value: id).execute()
    }

    private var currentUserID: UUID? {
        client?.auth.currentSession?.user.id
    }

    private func pushAll(context: ModelContext, settings: AppSettings) async {
        let meals = (try? context.fetch(FetchDescriptor<Meal>())) ?? []
        for meal in meals { await storeMeal(meal) }

        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        for session in sessions { await storeWorkout(session) }

        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        for habit in habits { await storeHabit(habit) }

        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        for exercise in exercises where exercise.isCustom { await storeExercise(exercise) }

        try? context.save()
        await storeSettings(settings.weightUnit)
    }

    private func pull(context: ModelContext, health: HealthKitManager, settings: AppSettings) async {
        guard let client else { return }
        let response = try? await client.from("user_records").select("id,kind,payload").execute()
        guard let data = response?.data,
              let rows = try? JSONDecoder().decode([StoredRecord].self, from: data) else { return }

        var meals = (try? context.fetch(FetchDescriptor<Meal>())) ?? []
        var mealIDs = Set(meals.map(\.cloudID).filter { !$0.isEmpty })
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let sessionIDs = Set(sessions.map(\.cloudID))
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        let habitIDs = Set(habits.map(\.cloudID))
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let exerciseNames = Set(exercises.map { $0.name.lowercased() })

        for row in rows {
            switch row.kind {
            case "meal":
                if mealIDs.contains(row.id) { continue }
                if let local = meals.first(where: { mealMatches($0, row: row) }) {
                    if local.cloudID.isEmpty {
                        local.cloudID = row.id
                        mealIDs.insert(row.id)
                    }
                    continue
                }
                let meal = await insertMeal(row, context: context, health: health)
                meals.append(meal)
                mealIDs.insert(row.id)
            case "workout":
                guard !sessionIDs.contains(row.id) else { continue }
                await insertWorkout(row, context: context, health: health)
            case "habit":
                let remoteName = (row.payload.name ?? "").lowercased()
                if SeedData.retiredHabitNames.contains(remoteName) {
                    await removeRecord(row.id)
                    continue
                }
                guard !habitIDs.contains(row.id) else { continue }
                if let local = habits.first(where: { $0.name.lowercased() == remoteName }) {
                    if local.cloudID.isEmpty { local.cloudID = row.id }
                    continue
                }
                insertHabit(row, context: context)
            case "exercise":
                guard let name = row.payload.name else { continue }
                if let local = exercises.first(where: { $0.name.lowercased() == name.lowercased() }) {
                    if local.cloudID.isEmpty { local.cloudID = row.id }
                    continue
                }
                guard !exerciseNames.contains(name.lowercased()) else { continue }
                let exercise = Exercise(name: name, muscleGroup: row.payload.muscleGroup ?? "Other", isCustom: true)
                exercise.cloudID = row.id
                context.insert(exercise)
            case "settings":
                if !UserDefaults.standard.bool(forKey: CloudKeys.didApplySettings),
                   let raw = row.payload.weightUnit,
                   let unit = WeightUnit(rawValue: raw) {
                    settings.weightUnit = unit
                }
            case "weight", "water", "sleep", "vitals":
                await applyHealth(row, health: health)
            default:
                break
            }
        }

        UserDefaults.standard.set(true, forKey: CloudKeys.didApplySettings)
        try? context.save()
    }

    @discardableResult
    private func insertMeal(_ row: StoredRecord, context: ModelContext, health: HealthKitManager) async -> Meal {
        let payload = row.payload
        let meal = Meal(
            name: payload.name ?? "Meal",
            type: MealType(rawValue: payload.mealType ?? "") ?? .snack,
            date: CloudDate.date(payload.loggedAt) ?? Date(),
            calories: payload.calories ?? 0,
            proteinG: payload.proteinG ?? 0,
            carbsG: payload.carbsG ?? 0,
            fatG: payload.fatG ?? 0,
            photo: payload.photoBase64.flatMap { Data(base64Encoded: $0) },
            wasEstimated: payload.wasEstimated ?? false
        )
        meal.cloudID = row.id
        context.insert(meal)
        meal.healthKitSampleIDs = await health.saveMeal(
            calories: meal.calories,
            proteinG: meal.proteinG,
            carbsG: meal.carbsG,
            fatG: meal.fatG,
            date: meal.date
        )
        return meal
    }

    private func mealMatches(_ meal: Meal, row: StoredRecord) -> Bool {
        if meal.cloudID == row.id { return true }
        return meal.fingerprint == fingerprint(for: row)
    }

    private func fingerprint(for row: StoredRecord) -> String {
        let payload = row.payload
        return Meal(
            name: payload.name ?? "",
            type: MealType(rawValue: payload.mealType ?? "") ?? .snack,
            date: CloudDate.date(payload.loggedAt) ?? .distantPast,
            calories: payload.calories ?? 0,
            proteinG: payload.proteinG ?? 0
        ).fingerprint
    }

    /// Keeps one copy of each meal and drops the extras from the phone and the account.
    private func dedupeMeals(context: ModelContext, health: HealthKitManager) async {
        let meals = (try? context.fetch(FetchDescriptor<Meal>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        var kept = [String: Meal]()
        var doomed: [Meal] = []

        for meal in meals {
            let key = meal.fingerprint
            if let existing = kept[key] {
                // Prefer the copy that already has an account id / Health samples.
                let preferNew =
                    (existing.cloudID.isEmpty && !meal.cloudID.isEmpty)
                    || (existing.healthKitSampleIDs.isEmpty && !meal.healthKitSampleIDs.isEmpty)
                if preferNew {
                    doomed.append(existing)
                    kept[key] = meal
                } else {
                    doomed.append(meal)
                }
            } else {
                kept[key] = meal
            }
        }

        if !doomed.isEmpty {
            let sampleIDs = doomed.flatMap(\.healthKitSampleIDs)
            let cloudIDs = doomed.map(\.cloudID).filter { !$0.isEmpty }
            for meal in doomed {
                context.delete(meal)
            }
            try? context.save()
            for id in cloudIDs { await removeRecord(id) }
            await health.deleteSamples(ids: sampleIDs)
        }

        // Collapse duplicate account rows so the next pull cannot reimport them.
        await dedupeCloudMeals(keeping: Array(kept.values))
        try? context.save()
    }

    private func dedupeCloudMeals(keeping meals: [Meal]) async {
        guard let client else { return }
        let response = try? await client
            .from("user_records")
            .select("id,kind,payload")
            .eq("kind", value: "meal")
            .execute()
        guard let data = response?.data,
              let rows = try? JSONDecoder().decode([StoredRecord].self, from: data)
        else { return }

        var keepIDByFingerprint = Dictionary(
            uniqueKeysWithValues: meals.compactMap { meal -> (String, String)? in
                guard !meal.cloudID.isEmpty else { return nil }
                return (meal.fingerprint, meal.cloudID)
            }
        )
        var seen = Set<String>()

        for row in rows {
            let print = fingerprint(for: row)
            if let keepID = keepIDByFingerprint[print] {
                if row.id != keepID { await removeRecord(row.id) }
                continue
            }
            if seen.contains(print) {
                await removeRecord(row.id)
                continue
            }
            seen.insert(print)
            keepIDByFingerprint[print] = row.id
            if let meal = meals.first(where: { $0.fingerprint == print }), meal.cloudID.isEmpty {
                meal.cloudID = row.id
            }
        }
    }

    private func insertWorkout(_ row: StoredRecord, context: ModelContext, health: HealthKitManager) async {
        let payload = row.payload
        let session = WorkoutSession(
            name: payload.name ?? "Workout",
            date: CloudDate.date(payload.loggedAt) ?? Date(),
            notes: payload.notes ?? ""
        )
        session.cloudID = row.id
        session.durationMinutes = payload.durationMinutes ?? 60
        context.insert(session)

        for (index, exercise) in (payload.exercises ?? []).enumerated() {
            let item = SessionExercise(name: exercise.name, order: index)
            item.session = session
            context.insert(item)
            for (setIndex, set) in exercise.sets.enumerated() {
                let logged = ExerciseSet(weightKg: set.weightKg, reps: set.reps, order: setIndex)
                logged.exercise = item
                context.insert(logged)
                item.sets.append(logged)
            }
            session.exercises.append(item)
        }

        if session.durationMinutes > 0 {
            session.healthKitWorkoutID = await health.saveStrengthWorkout(
                name: session.name,
                start: session.date,
                duration: session.durationMinutes * 60
            )
        }
    }

    private func insertHabit(_ row: StoredRecord, context: ModelContext) {
        let payload = row.payload
        let habit = Habit(
            name: payload.name ?? "Habit",
            symbol: payload.symbol ?? "checkmark.circle",
            isActive: payload.isActive ?? true
        )
        habit.cloudID = row.id
        if let created = payload.createdAt, let date = CloudDate.date(created) {
            habit.createdAt = date
        }
        context.insert(habit)
        for tick in payload.ticks ?? [] {
            guard let day = CloudDate.date(tick) else { continue }
            let mark = HabitTick(day: day, habit: habit)
            context.insert(mark)
            habit.ticks.append(mark)
        }
    }

    private func applyHealth(_ row: StoredRecord, health: HealthKitManager) async {
        guard !AppliedHealthLogs.contains(row.id) else { return }
        let payload = row.payload
        let when = CloudDate.date(payload.loggedAt) ?? Date()
        let saved: Bool
        switch row.kind {
        case "weight":
            guard let kilograms = payload.kilograms else { return }
            saved = await health.saveWeight(kilograms: kilograms, date: when)
        case "water":
            guard let millilitres = payload.millilitres else { return }
            saved = await health.saveWater(litres: millilitres / 1000, date: when)
        case "sleep":
            guard let start = CloudDate.date(payload.sleepStart), let end = CloudDate.date(payload.sleepEnd) else { return }
            saved = await health.saveSleep(start: start, end: end)
        case "vitals":
            saved = await health.saveVitals(
                systolic: payload.systolic,
                diastolic: payload.diastolic,
                temperatureC: payload.temperatureC,
                oxygenPercent: payload.oxygenPercent,
                date: when
            )
        default:
            return
        }
        if saved { AppliedHealthLogs.add(row.id) }
    }

    private func storeHealth(kind: String, payload: RecordPayload) async {
        let id = UUID().uuidString
        AppliedHealthLogs.add(id)
        let pending = PendingHealth(id: id, kind: kind, payload: payload)
        var queue = PendingHealth.load()
        queue.append(pending)
        PendingHealth.save(queue)
        await flushPendingHealth()
    }

    private func flushPendingHealth() async {
        var remaining: [PendingHealth] = []
        for item in PendingHealth.load() {
            let saved = await upsert(id: item.id, kind: item.kind, payload: item.payload)
            if !saved { remaining.append(item) }
        }
        PendingHealth.save(remaining)
    }

    @discardableResult
    private func upsert(id: String, kind: String, payload: RecordPayload) async -> Bool {
        guard let client, let userID = currentUserID else { return false }
        let row = CloudRow(id: id, user_id: userID.uuidString, kind: kind, payload: payload)
        do {
            try await client.from("user_records").upsert(row, returning: .minimal).execute()
            return true
        } catch {
            return false
        }
    }
}

private enum CloudKeys {
    static let didApplySettings = "leanlah.didApplyRemoteSettings"
    static let appliedHealth = "leanlah.appliedHealthLogIDs"
    static let pendingHealth = "leanlah.pendingHealthLogs"
}

private enum CloudID {
    static func ensure(_ value: inout String) -> String {
        if value.isEmpty { value = UUID().uuidString }
        return value
    }
}

private enum CloudDate {
    static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func string(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        return formatter.date(from: value)
    }
}

private enum AppliedHealthLogs {
    static func contains(_ id: String) -> Bool {
        Set(UserDefaults.standard.stringArray(forKey: CloudKeys.appliedHealth) ?? []).contains(id)
    }

    static func add(_ id: String) {
        var ids = Set(UserDefaults.standard.stringArray(forKey: CloudKeys.appliedHealth) ?? [])
        ids.insert(id)
        UserDefaults.standard.set(Array(ids), forKey: CloudKeys.appliedHealth)
    }
}

private struct PendingHealth: Codable {
    var id: String
    var kind: String
    var payload: RecordPayload

    static func load() -> [PendingHealth] {
        guard let data = UserDefaults.standard.data(forKey: CloudKeys.pendingHealth) else { return [] }
        return (try? JSONDecoder().decode([PendingHealth].self, from: data)) ?? []
    }

    static func save(_ items: [PendingHealth]) {
        let data = try? JSONEncoder().encode(items)
        UserDefaults.standard.set(data, forKey: CloudKeys.pendingHealth)
    }
}

private struct CloudRow: Encodable {
    var id: String
    var user_id: String
    var kind: String
    var payload: RecordPayload
}

private struct StoredRecord: Decodable {
    var id: String
    var kind: String
    var payload: RecordPayload
}

private struct RecordPayload: Codable {
    var name: String?
    var mealType: String?
    var loggedAt: String?
    var calories: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var wasEstimated: Bool?
    var photoBase64: String?
    var notes: String?
    var durationMinutes: Double?
    var exercises: [CloudExercise]?
    var symbol: String?
    var isActive: Bool?
    var createdAt: String?
    var ticks: [String]?
    var muscleGroup: String?
    var kilograms: Double?
    var millilitres: Double?
    var sleepStart: String?
    var sleepEnd: String?
    var systolic: Double?
    var diastolic: Double?
    var temperatureC: Double?
    var oxygenPercent: Double?
    var weightUnit: String?
}

private struct CloudExercise: Codable {
    var name: String
    var sets: [CloudSet]
}

private struct CloudSet: Codable {
    var weightKg: Double
    var reps: Int
}
