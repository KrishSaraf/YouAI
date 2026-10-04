import SwiftUI
import SwiftData

struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Exercise> { $0.isCustom }, sort: \Exercise.name) private var custom: [Exercise]

    @State private var search = ""
    @State private var group: MuscleGroup = .all
    @State private var showingAdd = false

    private var entries: [LibraryEntry] {
        ExerciseCatalog.entries(matching: search, group: group, custom: custom)
    }

    private var customEntries: [LibraryEntry] { entries.filter(\.isCustom) }
    private var catalogEntries: [LibraryEntry] { entries.filter { !$0.isCustom } }

    var body: some View {
        VStack(spacing: 0) {
            MuscleGroupBar(selection: $group)
            List {
                if !customEntries.isEmpty {
                    Section("Yours") {
                        ForEach(customEntries) { entry in
                            ExerciseRow(entry: entry)
                        }
                        .onDelete(perform: deleteCustom)
                    }
                }

                Section {
                    ForEach(catalogEntries) { entry in
                        NavigationLink {
                            ExerciseDetailView(entry: entry)
                        } label: {
                            ExerciseRow(entry: entry)
                        }
                    }
                }
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView.search(text: search)
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
    }

    private func deleteCustom(at offsets: IndexSet) {
        let names = Set(offsets.map { customEntries[$0].name.lowercased() })
        for exercise in custom where names.contains(exercise.name.lowercased()) {
            context.delete(exercise)
        }
    }
}

struct ExerciseDetailView: View {
    let entry: LibraryEntry

    var body: some View {
        List {
            if !entry.images.isEmpty {
                Section {
                    TabView {
                        ForEach(entry.images, id: \.self) { path in
                            BundledExerciseImage(path: path, maxPixel: 800)
                                .scaledToFit()
                                .padding(8)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .tabViewStyle(.page)
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            Section {
                if let equipment = entry.equipment {
                    LabeledContent("Equipment", value: equipment)
                }
                LabeledContent("Muscle", value: entry.muscle)
                if let secondary = entry.secondary {
                    LabeledContent("Also works", value: secondary)
                }
                if let level = entry.level {
                    LabeledContent("Level", value: level)
                }
                if let kind = entry.kind {
                    LabeledContent("Type", value: kind)
                }
            }

            if !entry.instructions.isEmpty {
                Section("How to do it") {
                    ForEach(Array(entry.instructions.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 20, alignment: .trailing)
                            Text(step)
                        }
                    }
                }
            }
        }
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ExerciseRow: View {
    let entry: LibraryEntry

    var body: some View {
        HStack(spacing: 12) {
            BundledExerciseImage(path: entry.imagePath, maxPixel: 160)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .foregroundStyle(.primary)
                Text(entry.isCustom ? "\(entry.subtitle) · Added by you" : entry.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

struct BundledExerciseImage: View {
    let path: String?
    var maxPixel: CGFloat = 160

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemFill))
            }
        }
        .task(id: path) {
            guard let path else { return }
            let pixels = maxPixel
            let loaded = await Task.detached(priority: .userInitiated) {
                ExerciseCatalog.image(path, maxPixel: pixels)
            }.value
            image = loaded
        }
    }
}

struct MuscleGroupBar: View {
    @Binding var selection: MuscleGroup

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MuscleGroup.allCases) { group in
                    let selected = selection == group
                    Button(group.rawValue) { selection = group }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(selected ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                        .foregroundStyle(selected ? Color.white : Color.primary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }
}

struct AddExerciseSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existing: [Exercise]

    @State private var name = ""
    @State private var muscleGroup: MuscleGroup = .chest

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    private var isDuplicate: Bool {
        let target = trimmed.lowercased()
        if ExerciseCatalog.contains(name: trimmed) { return true }
        return existing.contains { $0.name.lowercased() == target }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise name", text: $name)
                    Picker("Muscle group", selection: $muscleGroup) {
                        ForEach(MuscleGroup.pickerGroups) { group in
                            Text(group.rawValue).tag(group)
                        }
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
                        context.insert(Exercise(name: trimmed, muscleGroup: muscleGroup.rawValue, isCustom: true))
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty || isDuplicate)
                }
            }
        }
    }
}
