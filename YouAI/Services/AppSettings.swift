import Foundation
import Observation

/// User-tweakable settings. Preferences live in `UserDefaults`. The AI service's
/// key does not live here — the server holds it.
@MainActor
@Observable
final class AppSettings {

    private enum Key {
        static let weightUnit = "weightUnit"
        static let allowsAISharing = "allowsAISharing"
    }

    private let defaults: UserDefaults

    var weightUnit: WeightUnit {
        didSet { defaults.set(weightUnit.rawValue, forKey: Key.weightUnit) }
    }

    /// Whether the person agreed to send photos and spoken text to the AI service.
    /// Nothing goes to it until this is true.
    var allowsAISharing: Bool {
        didSet { defaults.set(allowsAISharing, forKey: Key.allowsAISharing) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.weightUnit = WeightUnit(rawValue: defaults.string(forKey: Key.weightUnit) ?? "") ?? .kilograms
        self.allowsAISharing = defaults.bool(forKey: Key.allowsAISharing)
    }
}
