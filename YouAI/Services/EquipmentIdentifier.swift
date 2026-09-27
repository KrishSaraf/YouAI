import Foundation
import UIKit

/// What the model sees in a photo of a piece of gym equipment.
struct EquipmentIdentification: Equatable {
    var equipmentName: String
    var suggestedExercises: [String]
    var note: String?

    var isUnrecognised: Bool {
        suggestedExercises.isEmpty || equipmentName.lowercased().contains("no equipment")
    }
}

struct EquipmentIdentifier {

    let client: NIMClient

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "equipment_name": ["type": "string"],
            "suggested_exercises": [
                "type": "array",
                "items": ["type": "string"],
                "maxItems": 5,
            ],
            "note": ["type": "string"],
        ],
        "required": ["equipment_name", "suggested_exercises"],
        "additionalProperties": false,
    ]

    private static let prompt = """
    You are a strength-training coach. Identify the piece of gym equipment in this \
    photo and list the exercises it is used for.

    Reply with only a JSON object, no prose and no code fences, with these keys:
      "equipment_name": what the machine or equipment is called
      "suggested_exercises": up to 5 exercise names you'd perform on it, most \
    common first, each named the way a lifter would log it
      "note": one short sentence of setup advice

    If there is no gym equipment in the photo, set "equipment_name" to \
    "No equipment detected" and "suggested_exercises" to an empty array.
    """

    func identify(from image: UIImage) async throws -> EquipmentIdentification {
        guard let prepared = ImagePreparer.prepare(image) else { throw NIMError.imageTooLarge }

        let text = try await client.complete(
            prompt: Self.prompt,
            image: prepared,
            jsonSchema: Self.schema
        )

        guard let json = JSONExtractor.object(from: text) else {
            throw NIMError.badJSON("the model didn't return JSON. It said: \(text.prefix(200))")
        }

        let name = (json["equipment_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let exercises = (json["suggested_exercises"] as? [Any] ?? [])
            .compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return EquipmentIdentification(
            equipmentName: name?.isEmpty == false ? name! : "Unknown equipment",
            suggestedExercises: exercises,
            note: json["note"] as? String
        )
    }
}
