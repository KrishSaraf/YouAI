import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HealthKitManager.self) private var health
    @Environment(AccountStore.self) private var account

    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                if account.isSignedIn {
                    LabeledContent("Account", value: account.email ?? "Signed in")
                    Button("Sign out") {
                        Task { await account.signOut() }
                    }
                    .disabled(isDeleting)
                    Button("Delete account", role: .destructive) {
                        confirmingDelete = true
                    }
                    .disabled(isDeleting)
                } else {
                    AccountSignInSection()
                }
            } footer: {
                Text(account.isSignedIn
                    ? "Deleting your account removes it and everything saved to it. Meals and workouts on this iPhone stay here."
                    : "Sign in to estimate meals and identify equipment from a photo.")
            }

            Section {
                Toggle("AI estimates", isOn: Binding(
                    get: { settings.allowsAISharing },
                    set: { settings.allowsAISharing = $0 }
                ))
            } footer: {
                Text("Sends the photos you estimate, and the text of spoken logs, to OpenRouter and Google's Gemini model. Off means nothing is sent, and you'll be asked again next time.")
            }

            Section("Units") {
                Picker("Weight", selection: Binding(
                    get: { settings.weightUnit },
                    set: { settings.weightUnit = $0 }
                )) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Apple Health") {
                LabeledContent("Data showing", value: health.appearsConnected ? "Yes" : "No")
                Button("Re-request access") {
                    Task {
                        await health.requestAuthorization()
                        await health.refresh()
                    }
                }
                if let url = URL(string: "x-apple-health://") {
                    Link("Open the Health app", destination: url)
                }
            }

            Section {
                if let url = APIConfig.endpoint("privacy") {
                    Link("Privacy policy", destination: url)
                }
                if let url = APIConfig.endpoint("support") {
                    Link("Help and support", destination: url)
                }
            } footer: {
                Text("Lean Lah! is for general fitness tracking. It isn't a medical device and doesn't give medical advice.")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Delete account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your account and the logs saved to it. Meals and workouts on this iPhone stay here.")
        }
        .alert("Couldn't delete the account", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await account.deleteAccount()
        } catch is CancellationError {
            // Backed out of the Apple prompt. Nothing was deleted.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
