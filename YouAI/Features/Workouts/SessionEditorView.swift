import SwiftUI
import SwiftData

/// Creates or edits a strength session. `session == nil` means "new".
struct SessionEditorView: View {
    let session: WorkoutSession?
    /// Exercise names to start with, used when arriving from an equipment photo.
    var prefilledExercises: [String] = []

    @Environment(\.modelContext) private var context
    @Environment(HealthKitManager.self) private var health
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var date = Date()
    @State private var notes = ""
    @State private var durationMinutes = 60.0
    @State private var draftExercises: [DraftExercise] = []
    @State private var showingPicker = false
    @State private var mirrorToHealth = true
    @State private var hasLoaded = false

    private var isEditing: Bool { session != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section("Session") {
                TextField("Name, e.g. Push day", text: $name)
                DatePicker("When", selection: $date, in: ...Date())
            }

            ForEach($draftExercises) { $exercise in
                Section {
                    ForEach(Array($exercise.sets.enumerated()), id: \.element.id) { index, $set in
                        SetRow(index: index + 1, set: $set)
                    }
                    .onDelete { offsets in
                        exercise.sets.remove(atOffsets: offsets)
                    }

                    Button {
                        exercise.addSet()
                    } label: {
                        Label("Add set", systemImage: "plus")
                            .font(.subheadline)
                    }
                } header: {
                    HStack {
                        Text(exercise.name)
                        Spacer()
                        Button(role: .destructive) {
                            draftExercises.removeAll { $0.id == exercise.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Remove \(exercise.name)")
                    }
                } footer: {
                    if exercise.volumeKg > 0 {
                        Text("\(Fmt.whole(exercise.volumeKg)) kg total volume")
                    }
                }
            }

            Section {
                Button {
                    showingPicker = true
                } label: {
                    Label("Add exercise", systemImage: "plus.circle")
                }
            }

            Section("Notes") {
                TextField("How it went", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            if !isEditing {
                Section {
                    Toggle("Also save to Apple Health", isOn: $mirrorToHealth)
                    if mirrorToHealth {
                        VStack(alignment: .leading) {
                            Text("Duration: \(Fmt.hoursMinutes(durationMinutes / 60))")
                                .font(.subheadline)
                            Slider(value: $durationMinutes, in: 10...180, step: 5)
                        }
                    }
                } footer: {
                    Text("Saves a strength training workout so it appears alongside your Watch workouts.")
                }
            }
        }
        .navigationTitle(isEditing ? "Edit session" : "Log session")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerSheet { chosen in
                draftExercises.append(DraftExercise(name: chosen))
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true

        if let session {
            name = session.name
            date = session.date
            notes = session.notes
            if session.durationMinutes > 0 { durationMinutes = session.durationMinutes }
            draftExercises = session.orderedExercises.map { exercise in
                DraftExercise(
                    name: exercise.name,
                    sets: exercise.orderedSets.map { DraftSet(weightKg: $0.weightKg, reps: $0.reps) }
                )
            }
        } else {
            draftExercises = prefilledExercises.map { DraftExercise(name: $0) }
        }
    }

    private func save() {
        let target = session ?? WorkoutSession(name: "", date: date)
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.date = date
        target.notes = notes
        target.durationMinutes = durationMinutes

        // Rebuild the exercise tree rather than diffing it — the editor owns a
        // plain-value draft, and a session is small enough that this is cheap.
        for existing in target.exercises {
            context.delete(existing)
        }
        target.exercises = []

        for (index, draft) in draftExercises.enumerated() {
            let exercise = SessionExercise(name: draft.name, order: index)
            exercise.session = target
            context.insert(exercise)

            for (setIndex, draftSet) in draft.sets.enumerated() {
                let set = ExerciseSet(weightKg: draftSet.weightKg, reps: draftSet.reps, order: setIndex)
                set.exercise = exercise
                context.insert(set)
                exercise.sets.append(set)
            }

            target.exercises.append(exercise)
        }

        if session == nil {
            context.insert(target)
        }

        try? context.save()
        let saved = target
        Task {
            await account.storeWorkout(saved)
            try? context.save()
        }

        // New sessions mirror when the toggle is on. Edited ones revise the copy already in Health.
        let previousWorkoutID = session?.healthKitWorkoutID
        let shouldMirror = session == nil ? mirrorToHealth : previousWorkoutID != nil
        guard shouldMirror else {
            dismiss()
            return
        }

        Task {
            // HealthKit workouts can't be edited, so a revision replaces the old one.
            if let previousWorkoutID { await health.deleteWorkout(id: previousWorkoutID) }
            target.healthKitWorkoutID = await health.saveStrengthWorkout(
                name: target.name,
                start: date,
                duration: durationMinutes * 60
            )
            try? context.save()
            await health.refresh()
            dismiss()
        }
    }
}

// MARK: - Drafts

/// Plain-value stand-ins for the SwiftData models, so half-finished edits never
/// land in the store and Cancel genuinely cancels.
struct DraftExercise: Identifiable {
    let id = UUID()
    var name: String
    var sets: [DraftSet] = [DraftSet()]

    var volumeKg: Double {
        sets.reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    }

    mutating func addSet() {
        // Repeat the last set — sets within an exercise usually match.
        sets.append(sets.last.map { DraftSet(weightKg: $0.weightKg, reps: $0.reps) } ?? DraftSet())
    }
}

struct DraftSet: Identifiable {
    let id = UUID()
    var weightKg: Double = 0
    var reps: Int = 0
}

struct SetRow: View {
    let index: Int
    @Binding var set: DraftSet

    @State private var weightText = ""
    @State private var repsText = ""
    @State private var hasLoaded = false

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            TextField("0", text: $weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 60)
                .onChange(of: weightText) { _, new in
                    set.weightKg = Double(new.replacingOccurrences(of: ",", with: ".")) ?? 0
                }
            Text("kg")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("×")
                .foregroundStyle(.secondary)

            TextField("0", text: $repsText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 44)
                .onChange(of: repsText) { _, new in
                    set.reps = Int(new.filter(\.isNumber)) ?? 0
                }
            Text("reps")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            weightText = set.weightKg > 0 ? Fmt.weight(set.weightKg) : ""
            repsText = set.reps > 0 ? "\(set.reps)" : ""
        }
    }
}

// MARK: - Picker

struct ExercisePickerSheet: View {
    var onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Exercise> { $0.isCustom }, sort: \Exercise.name) private var custom: [Exercise]

    @State private var search = ""
    @State private var group: MuscleGroup = .all

    private var entries: [LibraryEntry] {
        let novel = custom.filter { ExerciseCatalog.match(name: $0.name) == nil }
        return ExerciseCatalog.entries(matching: search, group: group, custom: novel)
    }

    private var trimmedSearch: String {
        search.trimmingCharacters(in: .whitespaces)
    }

    private var canUseTypedName: Bool {
        guard !trimmedSearch.isEmpty else { return false }
        if ExerciseCatalog.match(name: trimmedSearch) != nil { return false }
        let target = trimmedSearch.lowercased()
        return !custom.contains { $0.name.lowercased() == target }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MuscleGroupBar(selection: $group)
                List {
                    if canUseTypedName {
                        Section {
                            Button {
                                onPick(trimmedSearch)
                                dismiss()
                            } label: {
                                Label("Use \"\(trimmedSearch)\"", systemImage: "plus")
                            }
                        }
                    }

                    Section {
                        ForEach(entries) { entry in
                            Button {
                                onPick(entry.name)
                                dismiss()
                            } label: {
                                ExerciseRow(entry: entry)
                            }
                        }
                    }
                }
                .overlay {
                    if entries.isEmpty && !canUseTypedName {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
            .searchable(text: $search, prompt: "Search exercises")
            .navigationTitle("Add exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
