import SwiftUI

struct RootView: View {
    @Environment(HealthKitManager.self) private var health

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
            WorkoutsView()
                .tabItem { Label("Workouts", systemImage: "figure.strengthtraining.traditional") }
            FoodView()
                .tabItem { Label("Food", systemImage: "fork.knife") }
            HealthView()
                .tabItem { Label("Health", systemImage: "heart") }
        }
        .task {
            await health.requestAuthorization()
            await health.refresh()
        }
    }
}
