import SwiftUI
import SwiftData

struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var search = ""
    @State private var showingAdd = false

    private var grouped: [(group: String, exercises: [Exercise])] {
        let filtered = search.isEmpty
            ? exercises
            : exercises.filter { $0.name.localizedCaseInsensitiveContains(search) }

        return Dictionary(grouping: filtered, by: \.muscleGroup)
            .map { (group: $0.key, exercises: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.group < $1.group }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.group) { section in
                Section(section.group) {
                    ForEach(section.exercises) { exercise in
                        HStack {
                            Text(exercise.name)
                            if exercise.isCustom {
                                Spacer()
                                Text("Custom")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            context.delete(section.exercises[index])
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search exercises")
        .navigationTitle("Exercise library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add an exercise")
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddExerciseSheet()
        }
        .overlay {
            if grouped.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
    }
}

struct AddExerciseSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existing: [Exercise]

    @State private var name = ""
    @State private var muscleGroup = "Chest"

    private let groups = ["Chest", "Back", "Legs", "Shoulders", "Arms", "Core", "Cardio", "Other"]

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    /// `Exercise.name` is unique in the schema, so a duplicate insert would throw
    /// on save rather than fail gracefully — block it in the UI instead.
    private var isDuplicate: Bool {
        existing.contains { $0.name.lowercased() == trimmed.lowercased() }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise name", text: $name)
                    Picker("Muscle group", selection: $muscleGroup) {
                        ForEach(groups, id: \.self) { Text($0) }
                    }
                } footer: {
                    if isDuplicate {
                        Text("\"\(trimmed)\" is already in the library.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        context.insert(Exercise(name: trimmed, muscleGroup: muscleGroup, isCustom: true))
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty || isDuplicate)
                }
            }
        }
    }
}
