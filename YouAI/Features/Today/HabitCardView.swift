import SwiftUI
import SwiftData

struct HabitCardView: View {
    @Bindable var habit: Habit
    @Environment(\.modelContext) private var context

    private let week = Date.trailingWeek()
    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: habit.symbol)
                    .foregroundStyle(.tint)
                    .frame(width: 22)
                Text(habit.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if streak > 0 {
                    Label("\(streak)", systemImage: "flame.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .labelStyle(.titleAndIcon)
                        .accessibilityLabel("\(streak) day streak")
                }
            }

            HStack(spacing: 0) {
                ForEach(week, id: \.self) { day in
                    tickButton(for: day)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        .contextMenu {
            Button("Archive habit", systemImage: "archivebox") {
                habit.isActive = false
            }
            Button("Delete habit", systemImage: "trash", role: .destructive) {
                context.delete(habit)
            }
        }
    }

    private func tickButton(for day: Date) -> some View {
        let isTicked = habit.isTicked(on: day)
        let isToday = calendar.isDateInToday(day)

        return VStack(spacing: 6) {
            Text(day.formatted(.dateTime.weekday(.narrow)))
                .font(.caption2)
                .foregroundStyle(isToday ? .primary : .secondary)

            Button {
                toggle(day)
            } label: {
                ZStack {
                    Circle()
                        .fill(isTicked ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        .frame(width: 30, height: 30)
                    if isTicked {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay {
                    if isToday {
                        Circle()
                            .strokeBorder(.tint, lineWidth: 2)
                            .frame(width: 36, height: 36)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(habit.name) on \(Fmt.day(day))")
            .accessibilityValue(isTicked ? "Done" : "Not done")
            .accessibilityAddTraits(isTicked ? [.isSelected, .isButton] : .isButton)
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
    }

    /// Consecutive ticked days ending today (or yesterday, so a streak isn't
    /// reported as broken before the day is over).
    private var streak: Int {
        let ticked = Set(habit.ticks.map(\.day))
        guard !ticked.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: Date())
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

struct NewHabitSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var symbol = "checkmark.circle"

    private let symbols = [
        "checkmark.circle", "figure.strengthtraining.traditional", "figure.walk",
        "fork.knife", "bed.double", "drop", "book", "brain.head.profile",
        "pills", "sun.max", "leaf", "heart",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Stretch for 10 minutes", text: $name)
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
                                        symbol == candidate ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.clear),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("New habit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        context.insert(Habit(name: name.trimmingCharacters(in: .whitespaces), symbol: symbol))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
