import Foundation
import SwiftData

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon"
        case .snack: "carrot"
        }
    }

    /// Best guess from the clock, used to preselect the picker when logging.
    static func suggested(for date: Date = Date(), calendar: Calendar = .current) -> MealType {
        switch calendar.component(.hour, from: date) {
        case 4..<11: .breakfast
        case 11..<16: .lunch
        case 16..<22: .dinner
        default: .snack
        }
    }
}

@Model
final class Meal {
    var name: String = ""
    var typeRaw: String = MealType.snack.rawValue
    var date: Date = Date()
    var calories: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0

    @Attribute(.externalStorage) var photo: Data?

    /// Whether the numbers came from a photo estimate rather than being typed by hand.
    var wasEstimated: Bool = false

    /// UUIDs of the HealthKit nutrition samples written for this meal, so an edit or
    /// delete here can revise Health too instead of leaving orphans behind.
    var healthKitSampleIDs: [String] = []

    init(
        name: String,
        type: MealType,
        date: Date = Date(),
        calories: Double = 0,
        proteinG: Double = 0,
        carbsG: Double = 0,
        fatG: Double = 0,
        photo: Data? = nil,
        wasEstimated: Bool = false
    ) {
        self.name = name
        self.typeRaw = type.rawValue
        self.date = date
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.photo = photo
        self.wasEstimated = wasEstimated
    }

    var type: MealType {
        get { MealType(rawValue: typeRaw) ?? .snack }
        set { typeRaw = newValue.rawValue }
    }
}
