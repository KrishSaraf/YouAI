import SwiftUI
import SwiftData

struct FoodView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthKitManager.self) private var health
    @Environment(AccountStore.self) private var account
    @Query(sort: \Meal.date, order: .reverse) private var meals: [Meal]

    @State private var showingCapture = false
    @State private var editing: Meal?

    private let calendar = Calendar.current

    private var todaysMeals: [Meal] {
        meals.filter { calendar.isDateInToday($0.date) }
    }

    private var earlierMeals: [Meal] {
        meals.filter { !calendar.isDateInToday($0.date) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    totalsRow
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section("Today") {
                    if todaysMeals.isEmpty {
                        Text("Nothing logged yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(todaysMeals) { meal in
                            Button {
                                editing = meal
                            } label: {
                                MealRow(meal: meal)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { delete(todaysMeals, at: $0) }
                    }
                }

                if !earlierMeals.isEmpty {
                    Section("Earlier") {
                        ForEach(earlierMeals) { meal in
                            Button {
                                editing = meal
                            } label: {
                                MealRow(meal: meal, showsDate: true)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { delete(earlierMeals, at: $0) }
                    }
                }
            }
            .navigationTitle("Food")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCapture = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Log a meal")
                }
            }
            .sheet(isPresented: $showingCapture) {
                NavigationStack { MealCaptureView() }
            }
            .sheet(item: $editing) { meal in
                NavigationStack { MealEditorView(meal: meal) }
            }
        }
    }

    private var totalsRow: some View {
        HStack(spacing: 12) {
            MetricTile(
                title: "Calories today",
                value: Fmt.whole(todaysMeals.reduce(0) { $0 + $1.calories }),
                unit: "kcal",
                symbol: "flame.fill",
                tint: .orange
            )
            MetricTile(
                title: "Protein today",
                value: Fmt.whole(todaysMeals.reduce(0) { $0 + $1.proteinG }),
                unit: "g",
                symbol: "fish.fill",
                tint: .primary
            )
        }
    }

    /// Deleting a meal also removes the nutrition samples it wrote to Health, so
    /// the two never drift apart.
    private func delete(_ source: [Meal], at offsets: IndexSet) {
        let doomed = offsets.map { source[$0] }
        let sampleIDs = doomed.flatMap(\.healthKitSampleIDs)
        let cloudIDs = doomed.map(\.cloudID)

        for meal in doomed {
            context.delete(meal)
        }

        Task {
            for id in cloudIDs { await account.removeRecord(id) }
            await health.deleteSamples(ids: sampleIDs)
        }
    }
}

struct MealRow: View {
    let meal: Meal
    var showsDate = false

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 3) {
                Text(meal.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(meal.type.label)
                    Text("·")
                    Text(showsDate ? Fmt.relativeDay(meal.date) : Fmt.time(meal.date))
                    if meal.wasEstimated {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                            .accessibilityLabel("Estimated from a photo")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Fmt.whole(meal.calories)) kcal")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("P \(Fmt.whole(meal.proteinG)) · C \(Fmt.whole(meal.carbsG)) · F \(Fmt.whole(meal.fatG))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = meal.photo, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.5))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: meal.type.symbol)
                        .foregroundStyle(.secondary)
                }
        }
    }
}
