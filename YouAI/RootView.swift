import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthKitManager.self) private var health
    @Environment(AppSettings.self) private var settings
    @Environment(AccountStore.self) private var account

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
        .tint(.primary)
        .task {
            await health.requestAuthorization()
            await health.refresh()
            await account.refreshCredentialState()
            await tidyHabits()
            await account.sync(context: context, health: health, settings: settings)
            await tidyHabits()
        }
        .onChange(of: account.isSignedIn) { _, signedIn in
            guard signedIn else { return }
            Task {
                await tidyHabits()
                await account.sync(context: context, health: health, settings: settings)
                await tidyHabits()
            }
        }
        .onChange(of: settings.weightUnit) { _, unit in
            Task { await account.storeSettings(unit) }
        }
        .onOpenURL { url in
            account.handle(url)
        }
    }

    private func tidyHabits() async {
        let result = SeedData.tidyHabits(in: context)
        for id in result.removedCloudIDs {
            await account.removeRecord(id)
        }
        for habit in result.renamed {
            await account.storeHabit(habit)
        }
    }
}
