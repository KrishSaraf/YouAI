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

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "name": ["type": "string"],
            "meal_type": ["type": "string", "enum": MealType.allCases.map(\.rawValue)],
            "calories": ["type": "number"],
            "protein_g": ["type": "number"],
            "carbs_g": ["type": "number"],
            "fat_g": ["type": "number"],
            "note": ["type": "string"],
        ],
        "required": ["name", "meal_type", "calories", "protein_g", "carbs_g", "fat_g"],
        "additionalProperties": false,
    ]

    private static let prompt = """
    You are a nutrition estimator. Look at this photo of a meal and estimate its \
    contents for a single serving as shown.

    Reply with only a JSON object, no prose and no code fences, with these keys:
      "name": a short dish name, at most 5 words
      "meal_type": one of breakfast, lunch, dinner, snack
      "calories": total kilocalories, a number
      "protein_g", "carbs_g", "fat_g": grams, numbers
      "note": one short sentence on what you assumed about portion size

    If the photo does not contain food, set "name" to "No food detected" and all \
    numbers to 0.
    """

    func estimate(from image: UIImage, at date: Date = Date()) async throws -> MealEstimate {
        guard let prepared = ImagePreparer.prepare(image) else { throw NIMError.imageTooLarge }

        let text = try await client.complete(
            prompt: Self.prompt,
            image: prepared,
            jsonSchema: Self.schema
        )

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
