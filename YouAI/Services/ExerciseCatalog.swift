import Foundation
import ImageIO
import UIKit

/// Built-in exercise catalog bundled with the app. The text and illustrations
/// are the public-domain free-exercise-db set.
enum ExerciseCatalog {

    static let exercises: [CatalogExercise] = load()

    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ relativePath: String, maxPixel: CGFloat) -> UIImage? {
        let key = "\(relativePath)#\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard
            let root = Bundle.main.url(forResource: "images", withExtension: nil),
            let source = CGImageSourceCreateWithURL(root.appending(path: relativePath) as CFURL, nil)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key)
        return image
    }

    static func entries(matching search: String, group: MuscleGroup, custom: [Exercise]) -> [LibraryEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let customEntries = custom
            .map(LibraryEntry.init(custom:))
            .filter { $0.matches(query: query, group: group) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let catalogEntries = exercises
            .map(LibraryEntry.init(catalog:))
            .filter { $0.matches(query: query, group: group) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return customEntries + catalogEntries
    }

    static func contains(name: String) -> Bool {
        match(name: name) != nil
    }

    /// The catalog exercise a spoken or custom name is referring to, when one is close enough.
    static func match(name: String) -> CatalogExercise? {
        let query = NameKey(name)
        guard !query.words.isEmpty else { return nil }

        if let exact = exercises.first(where: { NameKey($0.name).squashed == query.squashed }) {
            return exact
        }

        let hits = exercises.filter { exercise in
            let candidate = NameKey(exercise.name)
            return query.words.allSatisfy { word in
                candidate.words.contains(word) || candidate.squashed.contains(word)
            }
        }
        return hits.min { lhs, rhs in
            let leftExtra = NameKey(lhs.name).words.count - query.words.count
            let rightExtra = NameKey(rhs.name).words.count - query.words.count
            if leftExtra != rightExtra { return leftExtra < rightExtra }
            return lhs.name.count < rhs.name.count
        }
    }

    private static func load() -> [CatalogExercise] {
        guard
            let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([CatalogExercise].self, from: data)
        else { return [] }
        return decoded
    }
}

enum MuscleGroup: String, CaseIterable, Identifiable {
    case all = "All"
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case arms = "Arms"
    case core = "Core"
    case legs = "Legs"

    var id: String { rawValue }

    static var pickerGroups: [MuscleGroup] {
        allCases.filter { $0 != .all }
    }

    static func group(forPrimary muscle: String) -> MuscleGroup {
        switch muscle.lowercased() {
        case "chest": .chest
        case "lats", "middle back", "lower back", "traps", "neck": .back
        case "shoulders": .shoulders
        case "biceps", "triceps", "forearms": .arms
        case "abdominals": .core
        default: .legs
        }
    }

    static func matching(_ title: String) -> MuscleGroup? {
        pickerGroups.first { $0.rawValue.caseInsensitiveCompare(title) == .orderedSame }
    }
}

struct CatalogExercise: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let level: String
    let equipment: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let instructions: [String]
    let category: String
    let images: [String]
}

struct LibraryEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let group: MuscleGroup?
    let muscle: String
    let subtitle: String
    let equipment: String?
    let level: String?
    let kind: String?
    let secondary: String?
    let instructions: [String]
    let images: [String]
    let isCustom: Bool

    var imagePath: String? { images.first }

    func matches(query: String, group selected: MuscleGroup) -> Bool {
        if selected != .all, group != selected { return false }
        guard !query.isEmpty else { return true }
        let folded = NameKey(query).squashed
        return NameKey(name).squashed.contains(folded)
            || NameKey(muscle).squashed.contains(folded)
            || NameKey(equipment ?? "").squashed.contains(folded)
    }

    init(catalog exercise: CatalogExercise) {
        let primary = exercise.primaryMuscles.first ?? ""
        id = exercise.id
        name = exercise.name
        group = MuscleGroup.group(forPrimary: primary)
        muscle = MuscleNames.label(primary)
        equipment = EquipmentNames.label(exercise.equipment)
        level = exercise.level.localizedCapitalized
        kind = CategoryNames.label(exercise.category)
        let also = exercise.secondaryMuscles.map(MuscleNames.label).filter { !$0.isEmpty }
        secondary = also.isEmpty ? nil : also.joined(separator: ", ")
        instructions = exercise.instructions
        images = exercise.images
        isCustom = false
        subtitle = [equipment, muscle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    init(custom exercise: Exercise) {
        id = "custom:\(exercise.name)"
        name = exercise.name
        group = MuscleGroup.matching(exercise.muscleGroup)
        muscle = exercise.muscleGroup
        equipment = nil
        level = nil
        kind = nil
        secondary = nil
        instructions = []
        images = []
        isCustom = true
        subtitle = exercise.muscleGroup
    }
}

private struct NameKey {
    let words: [String]
    let squashed: String

    init(_ raw: String) {
        let dropped: Set<String> = ["a", "an", "the", "with", "machine"]
        let cleaned = raw.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        words = String(cleaned)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 && !dropped.contains($0) }
        squashed = words.joined()
    }
}

private enum MuscleNames {
    static func label(_ muscle: String) -> String {
        switch muscle.lowercased() {
        case "abdominals": "Abs"
        case "abductors": "Abductors"
        case "adductors": "Adductors"
        case "biceps": "Biceps"
        case "calves": "Calves"
        case "chest": "Chest"
        case "forearms": "Forearms"
        case "glutes": "Glutes"
        case "hamstrings": "Hamstrings"
        case "lats": "Lats"
        case "lower back": "Lower Back"
        case "middle back": "Mid Back"
        case "neck": "Neck"
        case "quadriceps": "Quads"
        case "shoulders": "Shoulders"
        case "traps": "Traps"
        case "triceps": "Triceps"
        default: muscle.localizedCapitalized
        }
    }
}

private enum EquipmentNames {
    static func label(_ equipment: String?) -> String? {
        switch equipment?.lowercased() {
        case nil, "", "other": nil
        case "body only": "Bodyweight"
        case "e-z curl bar": "EZ-Bar"
        case "kettlebells": "Kettlebell"
        case "bands": "Band"
        case "medicine ball": "Medicine Ball"
        case "exercise ball": "Exercise Ball"
        case "foam roll": "Foam Roll"
        default: equipment?.localizedCapitalized
        }
    }
}

private enum CategoryNames {
    static func label(_ category: String) -> String? {
        switch category.lowercased() {
        case "strength": nil
        case "stretching": "Stretch"
        case "plyometrics": "Plyometrics"
        case "cardio": "Cardio"
        case "powerlifting": "Powerlifting"
        case "olympic weightlifting": "Olympic lifting"
        case "strongman": "Strongman"
        default: nil
        }
    }
}
