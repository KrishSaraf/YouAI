import SwiftUI
import SwiftData

struct HabitCardView: View {
    @Bindable var habit: Habit
    @Environment(\.modelContext) private var context
    @Environment(AccountStore.self) private var account

    @State private var showingEditor = false
    @State private var confirmingDelete = false

    private let calendar = Calendar.current

    private var today: Date { calendar.startOfDay(for: Date()) }
    private var isTickedToday: Bool { habit.isTicked(on: today) }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                toggle(today)
            } label: {
                ZStack {
                    Circle()
                        .fill(isTickedToday ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                        .frame(width: 36, height: 36)
                    if isTickedToday {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color(.systemBackground))
                    } else {
                        Image(systemName: habit.symbol)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(habit.name)
            .accessibilityValue(isTickedToday ? "Done today" : "Not done today")

            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.subheadline.weight(.semibold))
                if streak > 0 {
                    Label("\(streak) day streak", systemImage: "flame.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(isTickedToday ? "Done today" : "Not yet today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            Button {
                showingEditor = true
            } label: {
                Image(systemName: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(habit.name)")

            Button {
                confirmingDelete = true
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(habit.name)")
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showingEditor) {
            HabitEditorSheet(habit: habit)
        }
        .confirmationDialog("Delete \(habit.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the habit and its history from this iPhone.")
        }
    }

    private func toggle(_ day: Date) {
        if let existing = habit.tick(for: day) {
            context.delete(existing)
            habit.ticks.removeAll { $0.persistentModelID == existing.persistentModelID }
        } else {
            let tick = HabitTick(day: day, habit: habit)
            context.insert(tick)
            habit.ticks.append(tick)
        }
        Task { await account.storeHabit(habit) }
    }

    private func delete() {
        let cloudID = habit.cloudID
        context.delete(habit)
        try? context.save()
        Task { await account.removeRecord(cloudID) }
    }

    /// Consecutive ticked days ending today (or yesterday, so a streak isn't
    /// reported as broken before the day is over).
    private var streak: Int {
        let ticked = Set(habit.ticks.map(\.day))
        guard !ticked.isEmpty else { return 0 }

        var cursor = ticked.contains(today)
            ? today
            : calendar.date(byAdding: .day, value: -1, to: today) ?? today

        var count = 0
        while ticked.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}

struct HabitEditorSheet: View {
    var habit: Habit?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountStore.self) private var account

    @State private var name = ""
    @State private var symbol = "checkmark.circle"
    @State private var hasLoaded = false

    private let symbols = [
        "checkmark.circle", "figure.strengthtraining.traditional", "figure.walk",
        "fish.fill", "bed.double", "drop", "book", "brain.head.profile",
        "pills", "sun.max", "leaf", "heart",
    ]

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var isEditing: Bool { habit != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Protein", text: $name)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(), count: 6), spacing: 14) {
                        ForEach(symbols, id: \.self) { candidate in
                            Button {
                                symbol = candidate
                            } label: {
                                Image(systemName: candidate)
                                    .font(.title3)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        symbol == candidate ? AnyShapeStyle(.primary.opacity(0.15)) : AnyShapeStyle(.clear),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(isEditing ? "Edit habit" : "New habit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .disabled(trimmed.isEmpty)
                }
            }
            .onAppear {
                guard !hasLoaded else { return }
                hasLoaded = true
                if let habit {
                    name = habit.name
                    symbol = habit.symbol
                }
            }
        }
    }

    private func save() {
        if let habit {
            habit.name = trimmed
            habit.symbol = symbol
            Task { await account.storeHabit(habit) }
        } else {
            let created = Habit(name: trimmed, symbol: symbol)
            context.insert(created)
            Task { await account.storeHabit(created) }
        }
        try? context.save()
        dismiss()
    }
}
