import SwiftUI
import SwiftData
import PhotosUI

/// Photograph a machine, get back what it is and what you can do on it, then
/// carry the chosen exercises straight into a new session.
struct EquipmentCaptureView: View {
    @Environment(AccountStore.self) private var account
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showingCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var result: EquipmentIdentification?
    @State private var selected: Set<String> = []
    @State private var isIdentifying = false
    @State private var errorMessage: String?
    @State private var showingSession = false
    @State private var pendingAI: (() -> Void)?

    var body: some View {
        Form {
            if let image {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                }
            }

            Section {
                if CameraPicker.isAvailable {
                    Button {
                        showingCamera = true
                    } label: {
                        Label(image == nil ? "Photograph equipment" : "Retake photo", systemImage: "camera")
                    }
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose a photo", systemImage: "photo.on.rectangle")
                }
            }

            if image != nil && result == nil {
                if account.isSignedIn {
                    Section {
                        Button {
                            if settings.allowsAISharing { identify() } else { pendingAI = identify }
                        } label: {
                            HStack {
                                Label("Identify equipment", systemImage: "sparkles")
                                if isIdentifying {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isIdentifying)
                    } footer: {
                        Text("The photo is sent so the equipment can be named, and isn't kept.")
                    }
                } else {
                    Section {
                        AccountSignInSection()
                    } footer: {
                        Text("Sign in to identify this photo.")
                    }
                }
            }

            if let result {
                Section {
                    LabeledContent("Equipment", value: result.equipmentName)
                    if let note = result.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if result.isUnrecognised {
                    Section {
                        Text("Couldn't make out any gym equipment in that photo. Try again from a bit further back.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(result.suggestedExercises, id: \.self) { exercise in
                            Button {
                                toggle(exercise)
                            } label: {
                                HStack {
                                    Image(systemName: selected.contains(exercise) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected.contains(exercise) ? .green : .secondary)
                                    Text(exercise)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    } header: {
                        Text("Exercises")
                    } footer: {
                        Text("These use the exercise library when there's a match. Something new is only added if it isn't there yet.")
                    }

                    Section {
                        Button {
                            rememberNovelSelections()
                            showingSession = true
                        } label: {
                            Label("Start a session with \(selected.count) exercise\(selected.count == 1 ? "" : "s")", systemImage: "arrow.right.circle")
                        }
                        .disabled(selected.isEmpty)
                    }
                }
            }
        }
        .aiConsentGate($pendingAI)
        .navigationTitle("Gym equipment")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { captured in
                image = captured
                result = nil
                selected = []
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingSession) {
            NavigationStack {
                SessionEditorView(
                    session: nil,
                    prefilledExercises: selectedExercises
                )
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let loaded = UIImage(data: data) {
                    image = loaded
                    result = nil
                    selected = []
                }
            }
        }
        .alert("Couldn't identify", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var selectedExercises: [String] {
        (result?.suggestedExercises ?? []).filter { selected.contains($0) }
    }

    private func toggle(_ exercise: String) {
        if selected.contains(exercise) {
            selected.remove(exercise)
        } else {
            selected.insert(exercise)
        }
    }

    private func identify() {
        guard let image else { return }
        isIdentifying = true

        Task {
            do {
                let token = try await account.accessTokenForRequest()
                let identification = try await EquipmentIdentifier(client: NIMClient(sessionToken: token)).identify(from: image)
                result = identification.matchedToLibrary()
                // Prefer a library match when the model offered several names.
                selected = Set(result?.suggestedExercises.prefix(1) ?? [])
            } catch {
                errorMessage = error.localizedDescription
            }
            isIdentifying = false
        }
    }

    /// Keep only exercises the library does not already have.
    private func rememberNovelSelections() {
        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let names = Set(existing.map { $0.name.lowercased() })

        var added: [Exercise] = []
        for exercise in selectedExercises where ExerciseCatalog.match(name: exercise) == nil && !names.contains(exercise.lowercased()) {
            let item = Exercise(name: exercise, muscleGroup: "Other", isCustom: true)
            context.insert(item)
            added.append(item)
        }
        try? context.save()
        Task {
            for item in added { await account.storeExercise(item) }
        }
    }
}
