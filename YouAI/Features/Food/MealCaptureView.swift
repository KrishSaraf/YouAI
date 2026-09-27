import SwiftUI
import SwiftData
import PhotosUI

/// Entry point for logging a meal: photograph a plate, pick a photo, or skip the
/// photo entirely and type it in.
struct MealCaptureView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var showingCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var estimate: MealEstimate?
    @State private var isEstimating = false
    @State private var errorMessage: String?
    @State private var showingManualEntry = false

    var body: some View {
        Form {
            if let image {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                }
            }

            Section {
                if CameraPicker.isAvailable {
                    Button {
                        showingCamera = true
                    } label: {
                        Label(image == nil ? "Photograph a plate" : "Retake photo", systemImage: "camera")
                    }
                }

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose a photo", systemImage: "photo.on.rectangle")
                }
            } footer: {
                if !settings.hasAPIKey {
                    Text("Add an NVIDIA API key in Settings to estimate meals from a photo.")
                }
            }

            if image != nil {
                Section {
                    Button {
                        estimateMeal()
                    } label: {
                        HStack {
                            Label("Estimate from photo", systemImage: "sparkles")
                            if isEstimating {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isEstimating || !settings.hasAPIKey)
                }
            }

            Section {
                Button {
                    showingManualEntry = true
                } label: {
                    Label("Log without a photo", systemImage: "square.and.pencil")
                }
            }
        }
        .navigationTitle("Log meal")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { captured in
                image = captured
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let loaded = UIImage(data: data) {
                    image = loaded
                }
            }
        }
        .sheet(item: $estimate) { proposal in
            NavigationStack {
                EstimateReviewView(estimate: proposal, photo: image) {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showingManualEntry) {
            NavigationStack {
                EstimateReviewView(
                    estimate: MealEstimate(
                        name: "",
                        mealType: .suggested(),
                        calories: 0,
                        proteinG: 0,
                        carbsG: 0,
                        fatG: 0,
                        note: nil
                    ),
                    photo: image,
                    title: "New meal"
                ) {
                    dismiss()
                }
            }
        }
        .alert("Couldn't estimate", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func estimateMeal() {
        guard let image else { return }
        isEstimating = true

        Task {
            do {
                estimate = try await MealEstimator(client: settings.client).estimate(from: image)
            } catch {
                errorMessage = error.localizedDescription
            }
            isEstimating = false
        }
    }
}

/// `MealEstimate` only needs identity so it can drive a `sheet(item:)`.
extension MealEstimate: Identifiable {
    var id: String { "\(name)-\(calories)-\(proteinG)-\(carbsG)-\(fatG)" }
}
