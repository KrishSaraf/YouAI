import Foundation
import Observation

/// User-tweakable settings. Preferences live in `UserDefaults`. The vision API
/// key does not live here — the server holds it.
@MainActor
@Observable
final class AppSettings {

    private enum Key {
        static let weightUnit = "weightUnit"
    }

    private let defaults: UserDefaults

    var weightUnit: WeightUnit {
        didSet { defaults.set(weightUnit.rawValue, forKey: Key.weightUnit) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.weightUnit = WeightUnit(rawValue: defaults.string(forKey: Key.weightUnit) ?? "") ?? .kilograms
    }
}
