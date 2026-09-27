import Foundation

enum NIMError: LocalizedError {
    case missingAPIKey
    case imageTooLarge
    case http(status: Int, body: String)
    case emptyResponse
    case badJSON(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No NVIDIA API key set. Add one in Settings."
        case .imageTooLarge:
            "That photo couldn't be compressed small enough to send."
        case .http(let status, let body):
            "NVIDIA API returned \(status): \(body.prefix(300))"
        case .emptyResponse:
            "The model returned an empty response."
        case .badJSON(let detail):
            "Couldn't read the model's answer: \(detail)"
        }
    }
}

/// How the image bytes are attached to the request.
///
/// NVIDIA's hosted VLM endpoints are inconsistent here: some accept the standard
/// OpenAI `image_url` content part, while others require the image inlined into
/// the message *text* as an HTML `<img>` tag. Which one works depends on the
/// model, so it's a setting rather than a hardcoded choice, and
/// `NIMClient.probeEncoding` figures it out empirically.
enum NIMImageEncoding: String, CaseIterable, Identifiable, Codable {
    case openAIImageURL
    case inlineHTMLTag

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openAIImageURL: "OpenAI image_url"
        case .inlineHTMLTag: "Inline <img> tag"
        }
    }
}

/// Client for NVIDIA NIM's OpenAI-compatible chat completions endpoint.
struct NIMClient {

    static let defaultBaseURL = "https://integrate.api.nvidia.com/v1"
    static let keychainAccount = "nvidia-api-key"

    var baseURL: String = defaultBaseURL
    var model: String
    var encoding: NIMImageEncoding
    var apiKey: String?

    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90
        return URLSession(configuration: config)
    }

    // MARK: - Requests

    /// Sends a prompt, optionally with one image, and returns the assistant's text.
    ///
    /// `jsonSchema`, when supplied, is passed as `response_format` for guided
    /// decoding. Not every NIM model supports it, so callers must still parse
    /// defensively — see `JSONExtractor`.
    func complete(
        prompt: String,
        image: ImagePreparer.Prepared? = nil,
        jsonSchema: [String: Any]? = nil,
        maxTokens: Int = 700,
        temperature: Double = 0.2
    ) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else { throw NIMError.missingAPIKey }

        var body: [String: Any] = [
            "model": model,
            "messages": [messagePayload(prompt: prompt, image: image)],
            "max_tokens": maxTokens,
            "temperature": temperature,
            "stream": false,
        ]

        if let jsonSchema {
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": ["name": "response", "strict": true, "schema": jsonSchema],
            ]
        }

        let data = try await send(path: "chat/completions", body: body, apiKey: apiKey)
        return try firstMessageContent(from: data)
    }

    /// Lists the models this key can actually reach, so the app never hardcodes a
    /// model id that has since been retired from the catalog.
    func availableModels() async throws -> [String] {
        guard let apiKey, !apiKey.isEmpty else { throw NIMError.missingAPIKey }

        var request = URLRequest(url: try url(for: "models"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try check(response, data)

        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let list = root["data"] as? [[String: Any]]
        else { throw NIMError.badJSON("model list wasn't in the expected shape") }

        return list.compactMap { $0["id"] as? String }.sorted()
    }

    /// Tries both image encodings against the configured model with a tiny image
    /// and returns whichever one the endpoint accepts.
    func probeEncoding(using image: ImagePreparer.Prepared) async -> NIMImageEncoding? {
        for candidate in NIMImageEncoding.allCases {
            var probe = self
            probe.encoding = candidate
            if let _ = try? await probe.complete(prompt: "Reply with the single word OK.", image: image, maxTokens: 8) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Payload shaping

    private func messagePayload(prompt: String, image: ImagePreparer.Prepared?) -> [String: Any] {
        guard let image else {
            return ["role": "user", "content": prompt]
        }

        switch encoding {
        case .openAIImageURL:
            return [
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": image.dataURL]],
                ],
            ]
        case .inlineHTMLTag:
            return [
                "role": "user",
                "content": "\(prompt) <img src=\"\(image.dataURL)\" />",
            ]
        }
    }

    // MARK: - Transport

    private func url(for path: String) throws -> URL {
        guard let url = URL(string: "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/\(path)") else {
            throw NIMError.badJSON("invalid base URL")
        }
        return url
    }

    private func send(path: String, body: [String: Any], apiKey: String) async throws -> Data {
        var request = URLRequest(url: try url(for: path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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

        // Content is usually a string, but some NIM models return the OpenAI
        // content-parts array even on output.
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
