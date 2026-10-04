import Foundation

enum SpokenLog {
    case meal(MealEstimate)
    case workout(name: String, durationMinutes: Double, exercises: [SpokenExercise])
    case weight(kilograms: Double)
    case water(millilitres: Double)
    case sleep(asleep: Date, awake: Date)
    case habit(name: String)
    case unclear(String)
}

struct SpokenExercise: Identifiable {
    let id = UUID()
    var name: String
    var sets: [SpokenSet]
}

struct SpokenSet: Identifiable {
    let id = UUID()
    var weightKg: Double
    var reps: Int
}

enum VoiceLogError: LocalizedError {
    case notConfigured
    case signedOut
    case http(String)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Voice logs aren't available right now."
        case .signedOut: "Sign in to log by voice."
        case .http(let message): message
        case .unreadable: "Couldn't understand that. Try saying it again."
        }
    }
}

struct VoiceLogClient {
    var sessionToken: String?

    func interpret(_ text: String) async throws -> SpokenLog {
        guard let url = APIConfig.endpoint("api/dictate") else { throw VoiceLogError.notConfigured }
        guard let sessionToken, !sessionToken.isEmpty else { throw VoiceLogError.signedOut }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 55
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw VoiceLogError.http(serverMessage(data) ?? "Couldn't log that. Try again.")
        }
        return try SpokenLog.parse(from: data)
    }

    private func serverMessage(_ data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? String,
            !error.isEmpty
        else { return nil }
        return error
    }
}

extension SpokenLog {
    static func parse(from data: Data) throws -> SpokenLog {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let text = message["content"] as? String,
            let json = JSONExtractor.object(from: text)
        else { throw VoiceLogError.unreadable }

        let summary = (json["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch (json["kind"] as? String)?.lowercased() {
        case "meal":
            let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let type = (json["meal_type"] as? String).flatMap { MealType(rawValue: $0.lowercased()) }
            return .meal(MealEstimate(
                name: name?.isEmpty == false ? name! : "Meal",
                mealType: type ?? .suggested(),
                calories: JSONExtractor.double(json["calories"]),
                proteinG: JSONExtractor.double(json["protein_g"]),
                carbsG: JSONExtractor.double(json["carbs_g"]),
                fatG: JSONExtractor.double(json["fat_g"]),
                note: json["note"] as? String ?? (summary.isEmpty ? nil : summary)
            ))
        case "workout":
            let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let exercises = (json["exercises"] as? [[String: Any]] ?? []).compactMap { item -> SpokenExercise? in
                let exerciseName = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !exerciseName.isEmpty else { return nil }
                let sets = (item["sets"] as? [[String: Any]] ?? []).map { set in
                    SpokenSet(
                        weightKg: JSONExtractor.double(set["weight_kg"]),
                        reps: Int(JSONExtractor.double(set["reps"]).rounded())
                    )
                }
                return SpokenExercise(name: exerciseName, sets: sets.isEmpty ? [SpokenSet(weightKg: 0, reps: 0)] : sets)
            }
            guard !exercises.isEmpty else { throw VoiceLogError.unreadable }
            let minutes = JSONExtractor.double(json["duration_minutes"])
            return .workout(
                name: name?.isEmpty == false ? name! : "Workout",
                durationMinutes: minutes > 0 ? minutes : 45,
                exercises: exercises
            )
        case "weight":
            let kilograms = JSONExtractor.double(json["kilograms"])
            guard kilograms > 0 else { throw VoiceLogError.unreadable }
            return .weight(kilograms: kilograms)
        case "water":
            let millilitres = JSONExtractor.double(json["millilitres"])
            guard millilitres > 0 else { throw VoiceLogError.unreadable }
            return .water(millilitres: millilitres)
        case "sleep":
            guard var asleep = clockDate(json, hour: "asleep_hour", minute: "asleep_minute"),
                  let awake = clockDate(json, hour: "awake_hour", minute: "awake_minute")
            else { throw VoiceLogError.unreadable }
            if awake <= asleep {
                asleep = Calendar.current.date(byAdding: .day, value: -1, to: asleep) ?? asleep
            }
            return .sleep(asleep: asleep, awake: awake)
        case "habit":
            let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { throw VoiceLogError.unreadable }
            return .habit(name: name)
        default:
            return .unclear(summary.isEmpty ? "Say that again, a bit more specifically." : summary)
        }
    }

    private static func clockDate(_ json: [String: Any], hour: String, minute: String) -> Date? {
        guard json[hour] != nil else { return nil }
        let hourValue = Int(JSONExtractor.double(json[hour]).rounded())
        let minuteValue = Int(JSONExtractor.double(json[minute]).rounded())
        guard (0..<24).contains(hourValue), (0..<60).contains(minuteValue) else { return nil }
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        parts.hour = hourValue
        parts.minute = minuteValue
        return Calendar.current.date(from: parts)
    }
}
