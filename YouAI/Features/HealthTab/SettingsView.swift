import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HealthKitManager.self) private var health

    @State private var keyDraft = ""
    @State private var catalog: [String] = []
    @State private var isLoadingCatalog = false
    @State private var statusMessage: String?
    @State private var isProbing = false

    /// Models whose id hints at vision capability, surfaced first so the user
    /// isn't scrolling a list of hundreds of text-only models.
    private var likelyVisionModels: [String] {
        let hints = ["vision", "vl", "vila", "nemotron-nano-vl", "phi-3.5-vision", "llava"]
        return catalog.filter { id in
            let lower = id.lowercased()
            return hints.contains { lower.contains($0) }
        }
    }

    var body: some View {
        Form {
            Section {
                SecureField("nvapi-...", text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))

                HStack {
                    Button("Save key") {
                        settings.apiKey = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        statusMessage = settings.hasAPIKey ? "Key saved to the Keychain." : "Key cleared."
                    }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines) == settings.apiKey)

                    Spacer()

                    if settings.hasAPIKey {
                        Button("Clear", role: .destructive) {
                            keyDraft = ""
                            settings.apiKey = ""
                            catalog = []
                            statusMessage = "Key cleared."
                        }
                    }
                }
            } header: {
                Text("NVIDIA API key")
            } footer: {
                Text("Stored in the iOS Keychain on this device only. Get a key from build.nvidia.com.")
            }

            Section {
                if catalog.isEmpty {
                    LabeledContent("Model", value: settings.visionModel)
                        .font(.footnote)
                } else {
                    Picker("Model", selection: Binding(
                        get: { settings.visionModel },
                        set: { settings.visionModel = $0 }
                    )) {
                        if !likelyVisionModels.isEmpty {
                            Section("Vision models") {
                                ForEach(likelyVisionModels, id: \.self) { Text($0).tag($0) }
                            }
                        }
                        Section("All models") {
                            ForEach(catalog, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Button {
                    loadCatalog()
                } label: {
                    HStack {
                        Label(catalog.isEmpty ? "Load available models" : "Reload models", systemImage: "arrow.clockwise")
                        if isLoadingCatalog {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!settings.hasAPIKey || isLoadingCatalog)
            } header: {
                Text("Vision model")
            } footer: {
                Text("Loaded live from your account, so the list only ever shows models that actually exist.")
            }

            Section {
                Picker("Image format", selection: Binding(
                    get: { settings.imageEncoding },
                    set: { settings.imageEncoding = $0 }
                )) {
                    ForEach(NIMImageEncoding.allCases) { encoding in
                        Text(encoding.label).tag(encoding)
                    }
                }

                Button {
                    probe()
                } label: {
                    HStack {
                        Label("Detect automatically", systemImage: "wand.and.stars")
                        if isProbing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!settings.hasAPIKey || isProbing)
            } header: {
                Text("How images are sent")
            } footer: {
                Text("NVIDIA's hosted models disagree on this: some want the OpenAI image_url field, others need the image inlined as an <img> tag. Detect sends a tiny test image both ways and keeps whichever the model accepts.")
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
                LabeledContent("Endpoint", value: settings.baseURL)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .onAppear { keyDraft = settings.apiKey }
        .alert("Settings", isPresented: .constant(statusMessage != nil)) {
            Button("OK") { statusMessage = nil }
        } message: {
            Text(statusMessage ?? "")
        }
    }

    private func loadCatalog() {
        isLoadingCatalog = true
        Task {
            do {
                catalog = try await settings.client.availableModels()
                statusMessage = "Found \(catalog.count) models, \(likelyVisionModels.count) of them vision-capable."
            } catch {
                statusMessage = error.localizedDescription
            }
            isLoadingCatalog = false
        }
    }

    private func probe() {
        isProbing = true
        Task {
            // A 1-pixel image is enough to find out whether the endpoint accepts
            // the payload shape at all, and costs almost nothing.
            guard let probeImage = Self.onePixelImage(), let prepared = ImagePreparer.prepare(probeImage) else {
                statusMessage = "Couldn't build a test image."
                isProbing = false
                return
            }

            if let working = await settings.client.probeEncoding(using: prepared) {
                settings.imageEncoding = working
                statusMessage = "\(settings.visionModel) accepts \(working.label)."
            } else {
                statusMessage = "Neither image format worked with \(settings.visionModel). It may not be a vision model — try another one."
            }
            isProbing = false
        }
    }

    private static func onePixelImage() -> UIImage? {
        let size = CGSize(width: 8, height: 8)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
