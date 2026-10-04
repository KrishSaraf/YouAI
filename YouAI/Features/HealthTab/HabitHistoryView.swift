import SwiftUI
import SwiftData

/// Past ticks for every habit, newest days first.
struct HabitHistorySection: View {
    @Query(sort: \Habit.createdAt) private var habits: [Habit]

    private let calendar = Calendar.current

    private var days: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (0..<30).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private var rows: [(day: Date, done: [Habit])] {
        days.compactMap { day in
            let done = habits.filter { $0.isTicked(on: day) }
            guard !done.isEmpty else { return nil }
            return (day, done)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Habit history")
                .font(.headline)

            if habits.isEmpty {
                Text("No habits yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if rows.isEmpty {
                Text("Nothing ticked in the last 30 days.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows, id: \.day) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Fmt.relativeDay(row.day))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        FlowHabits(habits: row.done)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

private struct FlowHabits: View {
    let habits: [Habit]

    var body: some View {
        FlexibleHabitChips(habits: habits)
    }
}

/// Simple wrapping chips without a third-party layout package.
private struct FlexibleHabitChips: View {
    let habits: [Habit]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { habit in
                        Label(habit.name, systemImage: habit.symbol)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.secondarySystemFill), in: Capsule())
                    }
                }
            }
        }
    }

    /// Chunk into rows of up to 2 so the list stays readable without a flow layout.
    private var rows: [[Habit]] {
        stride(from: 0, to: habits.count, by: 2).map { start in
            Array(habits[start..<min(start + 2, habits.count)])
        }
    }
}
