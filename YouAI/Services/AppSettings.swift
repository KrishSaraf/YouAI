import Foundation
import Observation

/// User-tweakable settings. Everything here is a preference rather than data, so
/// it lives in `UserDefaults` — except the API key, which lives in the Keychain.
@MainActor
@Observable
final class AppSettings {

    private enum Key {
        static let visionModel = "visionModel"
        static let imageEncoding = "imageEncoding"
        static let weightUnit = "weightUnit"
        static let baseURL = "nimBaseURL"
    }

    /// Starting point only — the Settings screen loads the live catalog from
    /// `/v1/models` so the user can pick a model that actually exists today.
    static let fallbackVisionModel = "meta/llama-3.2-90b-vision-instruct"

    private let defaults: UserDefaults

    var visionModel: String {
        didSet { defaults.set(visionModel, forKey: Key.visionModel) }
    }

    var imageEncoding: NIMImageEncoding {
        didSet { defaults.set(imageEncoding.rawValue, forKey: Key.imageEncoding) }
    }

    var weightUnit: WeightUnit {
        didSet { defaults.set(weightUnit.rawValue, forKey: Key.weightUnit) }
    }

    var baseURL: String {
        didSet { defaults.set(baseURL, forKey: Key.baseURL) }
    }

    /// Mirrors the Keychain so views can react to the key being set or cleared.
    var apiKey: String {
        didSet { KeychainStore.set(apiKey, for: NIMClient.keychainAccount) }
    }

    var hasAPIKey: Bool { !apiKey.isEmpty }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.visionModel = defaults.string(forKey: Key.visionModel) ?? Self.fallbackVisionModel
        self.imageEncoding = NIMImageEncoding(rawValue: defaults.string(forKey: Key.imageEncoding) ?? "") ?? .openAIImageURL
        self.weightUnit = WeightUnit(rawValue: defaults.string(forKey: Key.weightUnit) ?? "") ?? .kilograms
        self.baseURL = defaults.string(forKey: Key.baseURL) ?? NIMClient.defaultBaseURL
        self.apiKey = KeychainStore.get(NIMClient.keychainAccount) ?? ""
    }

    var client: NIMClient {
        NIMClient(baseURL: baseURL, model: visionModel, encoding: imageEncoding, apiKey: apiKey)
    }
}
