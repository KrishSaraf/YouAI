import Foundation

enum NIMError: LocalizedError {
    case notConfigured
    case signedOut
    case imageTooLarge
    case http(status: Int, body: String)
    case emptyResponse
    case badJSON(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Photo estimates aren't available right now."
        case .signedOut:
            "Sign in to estimate from a photo."
        case .imageTooLarge:
            "That photo couldn't be compressed small enough to send."
        case .http(_, let body):
            userMessage(from: body)
        case .emptyResponse:
            "Couldn't read that photo. Try again."
        case .badJSON:
            "Couldn't read that photo. Try again."
        }
    }
}

/// Talks to this app's server, which holds the NVIDIA key and calls the model.
struct NIMClient {
    var sessionToken: String?

    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 55
        return URLSession(configuration: config)
    }

    /// Asks the server to run one of the built-in photo tasks and returns the
    /// assistant's text. The server owns the prompt, the model, and the key.
    func complete(task: String, image: ImagePreparer.Prepared) async throws -> String {
        guard let url = APIConfig.endpoint("api/vision") else { throw NIMError.notConfigured }
        guard let sessionToken, !sessionToken.isEmpty else { throw NIMError.signedOut }

        let body: [String: Any] = [
            "task": task,
            "image_data_url": image.dataURL,
        ]

        let data = try await send(url: url, body: body, sessionToken: sessionToken)
        return try firstMessageContent(from: data)
    }

    private func send(url: URL, body: [String: Any], sessionToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try check(response, data)
        return data
    }

    private func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw NIMError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
    }

    private func firstMessageContent(from data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NIMError.badJSON("response wasn't JSON")
        }

        guard
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any]
        else { throw NIMError.badJSON("no choices in response") }

        if let text = message["content"] as? String {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NIMError.emptyResponse
            }
            return text
        }

        if let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined()
            guard !text.isEmpty else { throw NIMError.emptyResponse }
            return text
        }

        throw NIMError.emptyResponse
    }
}

private func userMessage(from body: String) -> String {
    guard
        let data = body.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let error = json["error"] as? String,
        !error.isEmpty
    else { return "Couldn't read that photo. Try again." }
    return error
}
