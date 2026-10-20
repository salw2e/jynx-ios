import Foundation

enum Tone: String, CaseIterable {
    case keep, friendly, calm, firm, final

    var label: String {
        switch self {
        case .keep: "Just fix"
        case .friendly: "Friendly"
        case .calm: "Calm"
        case .firm: "Firm"
        case .final: "Final warning"
        }
    }
}

struct CustomTone: Codable, Hashable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var how: String
}

struct FixResult: Decodable {
    let fixed: String
    let changes: [String]
    let heads_up: String?
}

struct ApiError: Error {
    let message: String
}

enum Api {
    private static let base = "https://justsal.xyz/api/modvoice/"

    static func fix(_ text: String, tone: Tone, custom: CustomTone?) async throws -> FixResult {
        var body = ["text": text, "tone": custom == nil ? tone.rawValue : "custom"]
        if let custom { body["custom"] = custom.how }
        return try await call("fix", method: "POST", body: try JSONEncoder().encode(body), timeout: 45)
    }

    static func tones() async throws -> [CustomTone] {
        try await call("tones", method: "GET", body: nil, timeout: 15)
    }

    static func save(_ tones: [CustomTone]) async throws {
        let _: [CustomTone] = try await call("tones", method: "PUT", body: try JSONEncoder().encode(tones), timeout: 15)
    }

    private static func call<T: Decodable>(_ path: String, method: String, body: Data?, timeout: TimeInterval) async throws -> T {
        var req = URLRequest(url: URL(string: base + path)!, timeoutInterval: timeout)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(Bundle.main.object(forInfoDictionaryKey: "ModVoiceKey") as? String ?? "", forHTTPHeaderField: "x-modvoice-key")
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw ApiError(message: "Couldn't reach the fixer. Check your connection.")
        }
        if (resp as? HTTPURLResponse)?.statusCode == 200, let r = try? JSONDecoder().decode(T.self, from: data) {
            return r
        }
        let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
        throw ApiError(message: msg ?? "The fixer had a problem. Try again.")
    }
}
