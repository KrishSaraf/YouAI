import Foundation

enum APIConfig {
    private static let unconfiguredHost = "YOUR-SITE"

    /// Site origin from `APIBaseURL` in Info.plist, once the placeholder is replaced.
    static var baseURL: URL? {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String,
            !raw.contains(unconfiguredHost),
            let url = URL(string: raw)
        else { return nil }

        if url.scheme == "https" { return url }
        #if DEBUG
        if url.host == "localhost" || url.host == "127.0.0.1" { return url }
        #endif
        return nil
    }

    static func endpoint(_ path: String) -> URL? {
        baseURL?.appending(path: path)
    }
}

enum ServerError: LocalizedError {
    case notConfigured
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Photo estimates aren't available right now."
        case .message(let text):
            text
        }
    }

    static func parse(data: Data, fallback: String) -> ServerError {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? String,
           !error.isEmpty {
            return .message(error)
        }
        return .message(fallback)
    }
}
