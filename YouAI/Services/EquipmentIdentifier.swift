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

    func identify(from image: UIImage) async throws -> EquipmentIdentification {
        guard let prepared = ImagePreparer.prepare(image) else { throw NIMError.imageTooLarge }

        let text = try await client.complete(task: "equipment", image: prepared)

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
