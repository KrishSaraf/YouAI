import SwiftUI
import SwiftData

@main
struct YouAIApp: App {
    private let modelContainer: ModelContainer
    @State private var health = HealthKitManager()
    @State private var settings = AppSettings()
    @State private var account = AccountStore()

    init() {
        do {
            modelContainer = try ModelContainer(
                for: Habit.self, WorkoutSession.self, Exercise.self, Meal.self
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        SeedData.seedIfNeeded(in: modelContainer.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(health)
                .environment(settings)
                .environment(account)
        }
        .modelContainer(modelContainer)
    }
}
