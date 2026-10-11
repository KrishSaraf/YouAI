import SwiftData
import SwiftUI

/// Speak a meal, workout, weight, water, sleep, or habit. Nothing is saved until confirmed.
struct VoiceLogView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitManager.self) private var health
    @Environment(AppSettings.self) private var settings
    @Environment(AccountStore.self) private var account

    @Query(filter: #Predicate<Habit> { $0.isActive }, sort: \Habit.createdAt)
    private var habits: [Habit]

    @State private var speech = SpeechCapture()
    @State private var proposal: SpokenLog?
    @State private var isReading = false
    @State private var isSaving = false
    @State private var statusMessage: String?
    @State private var pendingAI: (() -> Void)?

    private var hasTranscript: Bool {
        !speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if proposal != nil || (hasTranscript && !speech.isListening) {
                    Form {
                        transcriptSection
                        if hasTranscript, proposal == nil {
                            Section {
                                Button {
                                    if settings.allowsAISharing {
                                        Task { await interpret() }
                                    } else {
                                        pendingAI = { Task { await interpret() } }
                                    }
                                } label: {
                                    HStack {
                                        Text("Log this")
                                        if isReading {
                                            Spacer()
                                            ProgressView()
                                        }
                                    }
                                }
                                .disabled(isReading)
                            }
                        }
                        if let proposal {
                            review(proposal)
                        }
                    }
                } else {
                    centeredSpeak
                }
            }
            .aiConsentGate($pendingAI)
            .navigationTitle("Speak a log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        speech.stop()
                        dismiss()
                    }
                }
            }
        }
    }

    private var centeredSpeak: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)

            Button {
                proposal = nil
                statusMessage = nil
                speech.toggle()
            } label: {
                VStack(spacing: 14) {
                    Image(systemName: speech.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .frame(width: 96, height: 96)
                        .background(Color.primary, in: Circle())
                        .foregroundStyle(Color(.systemBackground))
                    Text(speech.isListening ? "Listening…" : "Speak")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)

            Text("Say a meal, a workout, your weight, water, sleep, or a habit.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if speech.isListening, hasTranscript {
                Text(speech.transcript)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            if let message = speech.errorMessage ?? statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var transcriptSection: some View {
        Section {
            Button {
                proposal = nil
                statusMessage = nil
                speech.toggle()
            } label: {
                Label(speech.isListening ? "Stop" : "Speak again", systemImage: speech.isListening ? "stop.fill" : "mic.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)

            TextField("What you said", text: $speech.transcript, axis: .vertical)
                .lineLimit(2...6)

            if let message = speech.errorMessage ?? statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("You'll confirm it before it saves.")
        }
    }

    @ViewBuilder
    private func review(_ log: SpokenLog) -> some View {
        switch log {
        case .meal(let estimate):
            Section("Meal") {
                LabeledContent("Name", value: estimate.name)
                LabeledContent("Calories", value: "\(Fmt.whole(estimate.calories)) kcal")
                LabeledContent("Protein", value: "\(Fmt.whole(estimate.proteinG)) g")
                if let note = estimate.note, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            saveButton("Save meal") { await saveMeal(estimate) }
        case .workout(let name, let minutes, let exercises):
            Section(name) {
                Text(Fmt.hoursMinutes(minutes / 60))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(exercises) { exercise in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                        Text(exercise.sets.map { "\(Fmt.weight($0.weightKg)) kg × \($0.reps)" }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            saveButton("Save workout") { await saveWorkout(name: name, minutes: minutes, exercises: exercises) }
        case .weight(let kilograms):
            Section("Weight") {
                Text("\(Fmt.weight(Fmt.kilograms(kilograms, in: settings.weightUnit))) \(settings.weightUnit.label)")
                    .font(.title3.weight(.semibold))
            }
            saveButton("Save weight") { await saveWeight(kilograms) }
        case .water(let millilitres):
            Section("Water") {
                Text("\(Fmt.whole(millilitres)) ml")
                    .font(.title3.weight(.semibold))
            }
            saveButton("Save water") { await saveWater(millilitres) }
        case .sleep(let asleep, let awake):
            Section("Sleep") {
                LabeledContent("Asleep", value: asleep.formatted(date: .omitted, time: .shortened))
                LabeledContent("Awake", value: awake.formatted(date: .omitted, time: .shortened))
            }
            saveButton("Save sleep") { await saveSleep(asleep: asleep, awake: awake) }
        case .habit(let name):
            Section("Habit") {
                Text(name)
                    .font(.title3.weight(.semibold))
            }
            saveButton("Tick habit") { await saveHabit(name) }
        case .unclear(let message):
            Section {
                Text(message)
            }
        }
    }

    private func saveButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Section {
            if account.isSignedIn {
                Button {
                    Task { await action() }
                } label: {
                    HStack {
                        Text(title)
                        if isSaving {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isSaving)
            } else {
                AccountSignInSection()
            }
        }
    }

    private func interpret() async {
        speech.stop()
        let spoken = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return }
        isReading = true
        statusMessage = nil
        defer { isReading = false }
        do {
            let token = try await account.accessTokenForRequest()
            proposal = try await VoiceLogClient(sessionToken: token).interpret(spoken)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func saveMeal(_ estimate: MealEstimate) async {
        isSaving = true
        defer { isSaving = false }
        let meal = Meal(
            name: estimate.name,
            type: estimate.mealType,
            calories: estimate.calories,
            proteinG: estimate.proteinG,
            carbsG: estimate.carbsG,
            fatG: estimate.fatG,
            wasEstimated: true
        )
        context.insert(meal)
        meal.healthKitSampleIDs = await health.saveMeal(
            calories: meal.calories,
            proteinG: meal.proteinG,
            carbsG: meal.carbsG,
            fatG: meal.fatG,
            date: meal.date
        )
        try? context.save()
        await account.storeMeal(meal)
        try? context.save()
        await health.refresh()
        dismiss()
    }

    private func saveWorkout(name: String, minutes: Double, exercises: [SpokenExercise]) async {
        isSaving = true
        defer { isSaving = false }
        let session = WorkoutSession(name: name, date: Date(), notes: "")
        session.durationMinutes = minutes
        context.insert(session)
        for (index, exercise) in exercises.enumerated() {
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
        try? context.save()
        await account.storeWorkout(session)
        session.healthKitWorkoutID = await health.saveStrengthWorkout(
            name: name,
            start: session.date,
            duration: minutes * 60
        )
        try? context.save()
        await health.refresh()
        dismiss()
    }

    private func saveWeight(_ kilograms: Double) async {
        isSaving = true
        defer { isSaving = false }
        guard await health.saveWeight(kilograms: kilograms) else {
            statusMessage = "Couldn't save that weight. Try again."
            return
        }
        await account.storeWeight(kilograms: kilograms, date: Date())
        await health.refresh()
        dismiss()
    }

    private func saveWater(_ millilitres: Double) async {
        isSaving = true
        defer { isSaving = false }
        guard await health.saveWater(litres: millilitres / 1000) else {
            statusMessage = "Couldn't save that water. Try again."
            return
        }
        await account.storeWater(millilitres: millilitres, date: Date())
        await health.refresh()
        dismiss()
    }

    private func saveSleep(asleep: Date, awake: Date) async {
        isSaving = true
        defer { isSaving = false }
        guard await health.saveSleep(start: asleep, end: awake) else {
            statusMessage = "Couldn't save that sleep. Try again."
            return
        }
        await account.storeSleep(start: asleep, end: awake)
        await health.refresh()
        dismiss()
    }

    private func saveHabit(_ name: String) async {
        isSaving = true
        defer { isSaving = false }
        let needle = name.lowercased()
        guard let habit = habits.first(where: {
            $0.name.lowercased() == needle || $0.name.lowercased().contains(needle) || needle.contains($0.name.lowercased())
        }) else {
            statusMessage = "No habit matches \(name)."
            return
        }
        if !habit.isTicked(on: Date()) {
            let tick = HabitTick(day: Date(), habit: habit)
            context.insert(tick)
            habit.ticks.append(tick)
        }
        try? context.save()
        await account.storeHabit(habit)
        dismiss()
    }
}
