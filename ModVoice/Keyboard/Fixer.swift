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

struct FixResult: Decodable {
    let fixed: String
    let changes: [String]
    let heads_up: String?
}

struct FixError: Error {
    let message: String
}

enum Fixer {
    static func fix(_ text: String, tone: Tone) async throws -> FixResult {
        var req = URLRequest(url: URL(string: "https://justsal.xyz/api/modvoice/fix")!, timeoutInterval: 45)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(Bundle.main.object(forInfoDictionaryKey: "ModVoiceKey") as? String ?? "", forHTTPHeaderField: "x-modvoice-key")
        req.httpBody = try JSONEncoder().encode(["text": text, "tone": tone.rawValue])
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw FixError(message: "Couldn't reach the fixer. Check your connection.")
        }
        if (resp as? HTTPURLResponse)?.statusCode == 200, let r = try? JSONDecoder().decode(FixResult.self, from: data) {
            return r
        }
        let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
        throw FixError(message: msg ?? "The fixer had a problem. Try again.")
    }
}
