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
                    LabeledContent("Account", value: "Signed in")
                    Button("Delete account", role: .destructive) {
                        confirmingDelete = true
                    }
                    .disabled(isDeleting)
                } else {
                    SignInWithAppleButtonRow()
                }
            } footer: {
                Text(account.isSignedIn
                    ? "Deleting your account removes the sign-in. Meals and workouts on this iPhone stay here."
                    : "Sign in to estimate meals and identify equipment from a photo.")
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
        }
        .navigationTitle("Settings")
        .confirmationDialog("Delete account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your sign-in. You can also disconnect You AI in your Apple ID settings.")
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
