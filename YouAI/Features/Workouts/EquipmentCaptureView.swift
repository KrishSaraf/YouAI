import SwiftUI
import SwiftData
import PhotosUI

/// Photograph a machine, get back what it is and what you can do on it, then
/// carry the chosen exercises straight into a new session.
struct EquipmentCaptureView: View {
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
            } footer: {
                if !settings.hasAPIKey {
                    Text("Add an NVIDIA API key in Settings to identify equipment.")
                }
            }

            if image != nil && result == nil {
                Section {
                    Button {
                        identify()
                    } label: {
                        HStack {
                            Label("Identify equipment", systemImage: "sparkles")
                            if isIdentifying {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isIdentifying || !settings.hasAPIKey)
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
                        Text("Pick the ones you did — they'll be added to a new session.")
                    }

                    Section {
                        Button {
                            addSelectedToLibrary()
                            showingSession = true
                        } label: {
                            Label("Start a session with \(selected.count) exercise\(selected.count == 1 ? "" : "s")", systemImage: "arrow.right.circle")
                        }
                        .disabled(selected.isEmpty)
                    }
                }
            }
        }
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
                    prefilledExercises: result?.suggestedExercises.filter { selected.contains($0) } ?? []
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
                let identification = try await EquipmentIdentifier(client: settings.client).identify(from: image)
                result = identification
                // Preselect the most likely exercise so one tap gets you moving.
                selected = Set(identification.suggestedExercises.prefix(1))
            } catch {
                errorMessage = error.localizedDescription
            }
            isIdentifying = false
        }
    }

    /// Anything the model suggested that isn't in the library gets added, so it's
    /// searchable next time without another photo.
    private func addSelectedToLibrary() {
        let group = result?.equipmentName ?? "Other"
        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let names = Set(existing.map { $0.name.lowercased() })

        for exercise in selected where !names.contains(exercise.lowercased()) {
            context.insert(Exercise(name: exercise, muscleGroup: group, isCustom: true))
        }
        try? context.save()
    }
}
