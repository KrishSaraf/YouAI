import SwiftUI
import SwiftData

struct WorkoutsView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthKitManager.self) private var health
    @Environment(AccountStore.self) private var account

    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    @State private var showingEditor = false
    @State private var showingEquipment = false
    @State private var editing: WorkoutSession?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingEquipment = true
                    } label: {
                        Label("Photograph gym equipment", systemImage: "camera.viewfinder")
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Log a session", systemImage: "plus.circle")
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        ExerciseLibraryView()
                    } label: {
                        Label("Exercise library", systemImage: "list.bullet.rectangle")
                    }
                }

                Section("My sessions") {
                    if sessions.isEmpty {
                        Text("No sessions logged yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sessions) { session in
                            Button {
                                editing = session
                            } label: {
                                SessionRow(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: deleteSessions)
                    }
                }

                Section {
                    if health.recentWorkouts.isEmpty {
                        Text("No workouts found in Apple Health.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(health.recentWorkouts) { workout in
                            WatchWorkoutRow(workout: workout)
                        }
                    }
                } header: {
                    Text("From Apple Health")
                } footer: {
                    Text("Read-only — workouts recorded by your Watch and other apps.")
                }
            }
            .navigationTitle("Workouts")
            .refreshable { await health.refresh() }
            .sheet(isPresented: $showingEditor) {
                NavigationStack { SessionEditorView(session: nil) }
            }
            .sheet(item: $editing) { session in
                NavigationStack { SessionEditorView(session: session) }
            }
            .sheet(isPresented: $showingEquipment) {
                NavigationStack { EquipmentCaptureView() }
            }
        }
    }

    private func deleteSessions(at offsets: IndexSet) {
        let cloudIDs = offsets.map { sessions[$0].cloudID }
        for index in offsets {
            context.delete(sessions[index])
        }
        Task {
            for id in cloudIDs { await account.removeRecord(id) }
        }
    }
}

struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(Fmt.relativeDay(session.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text("\(session.exercises.count) exercises")
                Text("·")
                Text("\(session.totalSets) sets")
                if session.totalVolumeKg > 0 {
                    Text("·")
                    Text("\(Fmt.whole(session.totalVolumeKg)) kg volume")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !session.notes.isEmpty {
                Text(session.notes)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

struct WatchWorkoutRow: View {
    let workout: WorkoutSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.symbol)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(workout.activityName)
                    .font(.subheadline.weight(.medium))
                Text("\(Fmt.relativeDay(workout.start)) at \(Fmt.time(workout.start)) · \(workout.sourceName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.duration(workout.duration))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let energy = workout.energyKcal {
                    Text("\(Fmt.whole(energy)) kcal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 2)
    }
}
