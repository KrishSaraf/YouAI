import Foundation
import UIKit

/// What the model proposes for a photographed plate. Always shown in a review
/// sheet for confirmation — never saved straight to the log.
struct MealEstimate: Equatable {
    var name: String
    var mealType: MealType
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var note: String?
}

/// Pulls a JSON object out of model output that may be wrapped in prose or a
/// ```json fence. Guided decoding isn't supported on every NIM model, so the
/// happy path can't be assumed.
enum JSONExtractor {
    static func object(from text: String) -> [String: Any]? {
        if let direct = parse(text) { return direct }

        // Find the outermost {...} span and try that.
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            return nil
        }
        return parse(String(text[start...end]))
    }

    private static func parse(_ string: String) -> [String: Any]? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Models are inconsistent about numbers vs numeric strings.
    static func double(_ value: Any?) -> Double {
        switch value {
        case let number as Double: number
        case let number as Int: Double(number)
        case let string as String: Double(string.filter { $0.isNumber || $0 == "." }) ?? 0
        default: 0
        }
    }
}

struct MealEstimator {

    let client: NIMClient

    func estimate(from image: UIImage, at date: Date = Date()) async throws -> MealEstimate {
        guard let prepared = ImagePreparer.prepare(image) else { throw NIMError.imageTooLarge }

        let text = try await client.complete(task: "meal", image: prepared)

        guard let json = JSONExtractor.object(from: text) else {
            throw NIMError.badJSON("the model didn't return JSON. It said: \(text.prefix(200))")
        }

        let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = (json["meal_type"] as? String).flatMap { MealType(rawValue: $0.lowercased()) }

        return MealEstimate(
            name: name?.isEmpty == false ? name! : "Meal",
            mealType: type ?? MealType.suggested(for: date),
            calories: JSONExtractor.double(json["calories"]),
            proteinG: JSONExtractor.double(json["protein_g"]),
            carbsG: JSONExtractor.double(json["carbs_g"]),
            fatG: JSONExtractor.double(json["fat_g"]),
            note: json["note"] as? String
        )
    }
}
