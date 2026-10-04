import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<Habit> { $0.isActive }, sort: \Habit.createdAt)
    private var habits: [Habit]

    @Query(sort: \Meal.date, order: .reverse) private var allMeals: [Meal]

    @State private var showingWeightSheet = false
    @State private var showingWorkoutEditor = false
    @State private var showingMealLogger = false
    @State private var showingNewHabit = false
    @State private var showingVoice = false

    private var todaysMeals: [Meal] {
        allMeals.filter { Calendar.current.isDateInToday($0.date) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ringsCard
                    weightCard
                    voiceButton
                    quickLogButtons
                    habitsSection
                    mealsSection
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await health.refresh() }
            .sheet(isPresented: $showingWeightSheet) {
                WeightLogSheet()
            }
            .sheet(isPresented: $showingWorkoutEditor) {
                NavigationStack { SessionEditorView(session: nil) }
            }
            .sheet(isPresented: $showingMealLogger) {
                NavigationStack { MealCaptureView() }
            }
            .sheet(isPresented: $showingNewHabit) {
                HabitEditorSheet()
            }
            .sheet(isPresented: $showingVoice) {
                VoiceLogView()
            }
        }
    }

    // MARK: - Rings

    private var ringsCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 20) {
                RingsView(rings: health.rings, lineWidth: 11, size: 116)
                RingLegend(rings: health.rings)
            }

            if !health.appearsConnected {
                HealthAccessBanner()
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Weight

    private var weightCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Weight")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let kg = health.latestWeightKg {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Fmt.weight(Fmt.kilograms(kg, in: settings.weightUnit)))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                        Text(settings.weightUnit.label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let date = health.latestWeightDate, !Calendar.current.isDateInToday(date) {
                        Text("Last logged \(Fmt.relativeDay(date))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Not logged yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                showingWeightSheet = true
            } label: {
                Label("Log", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Log today's weight")
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }

    private var voiceButton: some View {
        Button {
            showingVoice = true
        } label: {
            Label("Speak a log", systemImage: "mic.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(.primary)
    }

    // MARK: - Quick log

    private var quickLogButtons: some View {
        HStack(spacing: 12) {
            Button {
                showingWorkoutEditor = true
            } label: {
                Label("Log workout", systemImage: "figure.strengthtraining.traditional")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.primary)

            Button {
                showingMealLogger = true
            } label: {
                Label("Log meal", systemImage: "fork.knife")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.primary)
        }
    }

    // MARK: - Habits

    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Habits")
                    .font(.headline)
                Spacer()
                Button {
                    showingNewHabit = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel("Add a habit")
            }

            if habits.isEmpty {
                ContentUnavailableView(
                    "No active habits",
                    systemImage: "checkmark.circle",
                    description: Text("Add one to start tracking a streak.")
                )
                .frame(height: 160)
            } else {
                ForEach(habits) { habit in
                    HabitCardView(habit: habit)
                }
            }
        }
    }

    // MARK: - Meals

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today's meals")
                    .font(.headline)
                Spacer()
                if !todaysMeals.isEmpty {
                    Text("\(Fmt.whole(todaysMeals.reduce(0) { $0 + $1.calories })) kcal")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            if todaysMeals.isEmpty {
                Text("Nothing logged yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(todaysMeals) { meal in
                    MealRow(meal: meal)
                }
            }
        }
    }
}

/// Shown when no Health data is coming through. HealthKit deliberately won't tell
/// us whether read access was granted, so this offers a route to Settings rather
/// than claiming to know the permission state.
struct HealthAccessBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.text.square")
                .foregroundStyle(.pink)
            VStack(alignment: .leading, spacing: 2) {
                Text("No Health data yet")
                    .font(.subheadline.weight(.semibold))
                Text("Allow Lean Lah! to read your data in Health → Sharing → Apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let url = URL(string: "x-apple-health://") {
                Link("Open", destination: url)
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(12)
        .background(.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
