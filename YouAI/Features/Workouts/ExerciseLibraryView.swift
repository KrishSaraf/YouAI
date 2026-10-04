import SwiftUI
import SwiftData

struct ExerciseLibraryView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Exercise> { $0.isCustom }, sort: \Exercise.name) private var custom: [Exercise]

    @State private var search = ""
    @State private var group: MuscleGroup = .all
    @State private var showingAdd = false

    /// Names already in the library stay in that list. Only a genuinely new exercise is added.
    private var entries: [LibraryEntry] {
        let novel = custom.filter { ExerciseCatalog.match(name: $0.name) == nil }
        return ExerciseCatalog.entries(matching: search, group: group, custom: novel)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            MuscleGroupBar(selection: $group)
            List {
                Section {
                    ForEach(entries) { entry in
                        NavigationLink {
                            ExerciseDetailView(entry: entry)
                        } label: {
                            ExerciseRow(entry: entry)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if entry.isCustom {
                                Button("Delete", role: .destructive) {
                                    deleteCustom(named: entry.name)
                                }
                            }
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
        .task { await retireMatchedCustoms() }
    }

    /// A photo used to save a second copy of an exercise the library already has.
    private func retireMatchedCustoms() async {
        let matched = custom.filter { ExerciseCatalog.match(name: $0.name) != nil }
        guard !matched.isEmpty else { return }
        let cloudIDs = matched.map(\.cloudID)
        for exercise in matched {
            context.delete(exercise)
        }
        try? context.save()
        for id in cloudIDs {
            await account.removeRecord(id)
        }
    }

    private func deleteCustom(named name: String) {
        let doomed = custom.filter { $0.name.lowercased() == name.lowercased() }
        let cloudIDs = doomed.map(\.cloudID)
        for exercise in doomed {
            context.delete(exercise)
        }
        try? context.save()
        Task {
            for id in cloudIDs { await account.removeRecord(id) }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search exercises", text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
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
                Text(entry.subtitle)
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
                        .background(selected ? Color.primary : Color(.tertiarySystemFill), in: Capsule())
                        .foregroundStyle(selected ? Color(.systemBackground) : Color.primary)
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
    @Environment(AccountStore.self) private var account
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
                        let exercise = Exercise(name: trimmed, muscleGroup: muscleGroup.rawValue, isCustom: true)
                        context.insert(exercise)
                        Task { await account.storeExercise(exercise) }
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty || isDuplicate)
                }
            }
        }
    }
}
