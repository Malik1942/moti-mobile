import Foundation

/// Minimal Google Gemini REST client.
///
/// Two transport modes:
///   - **direct**: talks to `generativelanguage.googleapis.com` with the API
///     key as a query parameter. Used only when no proxy is configured.
///   - **proxy**: talks to your own MotiProxy Cloudflare Worker with a shared
///     secret in `Authorization: Bearer`. The real Gemini key never leaves
///     the Worker. This is the distribution-safe path.
///
/// In both modes the request body is identical (Gemini's `generateContent`
/// schema), so the upstream parsing logic is shared.
///
/// Scope is intentionally narrow: one method, structured-JSON output via the
/// `responseSchema` field in `generationConfig`. No streaming, no tool use, no
/// chat history — Smart Capture is one-shot and stateless.
struct GeminiAPIClient {

    enum Transport {
        /// Talk to Gemini directly. The API key is sent as a `?key=` query param.
        case direct(apiKey: String)
        /// Talk to a MotiProxy Cloudflare Worker. The shared secret is sent in
        /// `Authorization: Bearer`. The Worker injects the real Gemini key.
        case proxy(baseURL: URL, sharedSecret: String)
    }

    let transport: Transport
    let model: String
    let session: URLSession

    init(transport: Transport, model: String = "gemini-2.5-flash", session: URLSession = .shared) {
        self.transport = transport
        self.model = model
        self.session = session
    }

    /// Convenience initializer for legacy direct-mode call sites.
    init(apiKey: String, model: String = "gemini-2.5-flash", session: URLSession = .shared) {
        self.init(transport: .direct(apiKey: apiKey), model: model, session: session)
    }

    /// Sends a structured-JSON request and returns the raw JSON bytes of the
    /// model's response (the payload inside `candidates[0].content.parts[0].text`).
    ///
    /// - Parameters:
    ///   - systemInstruction: The system prompt. Sent in Gemini's `systemInstruction` field.
    ///   - userPrompt: The user-turn content.
    ///   - responseSchema: A Gemini-flavor JSON Schema describing the expected output.
    ///   - temperature: Sampling temperature (0…2). Smart Capture defaults low (0.4) for stability.
    /// - Returns: UTF-8 JSON bytes of the structured output; ready for `JSONDecoder`.
    func generateStructuredJSON(
        systemInstruction: String,
        userPrompt: String,
        responseSchema: [String: Any],
        temperature: Double = 0.4
    ) async throws -> Data {

        // Build the same body for both transports — the MotiProxy Worker forwards
        // it verbatim to Gemini after adding the real API key.
        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": systemInstruction]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": userPrompt]]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": responseSchema,
                "temperature": temperature
            ]
        ]

        // Choose endpoint + auth based on transport mode.
        let url: URL
        var authHeader: (name: String, value: String)? = nil
        switch transport {
        case .direct(let apiKey):
            guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GeminiError.missingAPIKey
            }
            guard let directURL = URL(
                string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
            ) else {
                throw GeminiError.invalidEndpoint
            }
            url = directURL
        case .proxy(let baseURL, let sharedSecret):
            // Path mirrors Gemini's so the Worker can pattern-match cleanly:
            //   {base}/v1/models/{model}:generateContent
            guard let proxyURL = URL(
                string: "v1/models/\(model):generateContent",
                relativeTo: baseURL
            )?.absoluteURL else {
                throw GeminiError.invalidEndpoint
            }
            url = proxyURL
            authHeader = ("Authorization", "Bearer \(sharedSecret)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let header = authHeader {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? "<binary>"
            #if DEBUG
            print("[Gemini] HTTP \(http.statusCode): \(snippet.prefix(400))")
            #endif
            throw GeminiError.httpError(status: http.statusCode, body: snippet)
        }

        // Extract the structured payload: candidates[0].content.parts[0].text → UTF-8 bytes.
        guard
            let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = payload["candidates"] as? [[String: Any]],
            let first = candidates.first,
            let content = first["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let firstPart = parts.first,
            let text = firstPart["text"] as? String,
            let jsonBytes = text.data(using: .utf8)
        else {
            // Surface safety-block / prompt-blocked cases distinctly when possible.
            if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let promptFeedback = payload["promptFeedback"] as? [String: Any],
               let reason = promptFeedback["blockReason"] as? String {
                throw GeminiError.promptBlocked(reason: reason)
            }
            throw GeminiError.malformedResponse
        }
        return jsonBytes
    }
}

// MARK: - Errors

enum GeminiError: LocalizedError {
    case missingAPIKey
    case invalidEndpoint
    case invalidResponse
    case httpError(status: Int, body: String)
    case malformedResponse
    case promptBlocked(reason: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No Gemini API key configured."
        case .invalidEndpoint:
            return "Gemini: could not construct request URL."
        case .invalidResponse:
            return "Gemini: invalid HTTP response."
        case .httpError(let status, let body):
            return "Gemini HTTP \(status): \(body.prefix(200))"
        case .malformedResponse:
            return "Gemini: response did not contain structured output."
        case .promptBlocked(let reason):
            return "Gemini blocked the prompt: \(reason)"
        }
    }
}
