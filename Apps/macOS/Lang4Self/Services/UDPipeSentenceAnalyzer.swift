import Foundation
import Lang4SelfCore

enum UDPipeError: LocalizedError, Equatable {
    case api(status: Int, detail: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .api(let status, let detail):
            "UDPipe returned HTTP \(status). \(detail)"
        case .invalidResponse:
            "UDPipe returned an invalid sentence analysis."
        }
    }
}

actor UDPipeSentenceAnalyzer: SentenceAnalyzing {
    static let endpoint = URL(string: "https://lindat.mff.cuni.cz/services/udpipe/api/process")!
    static let model = "german-hdt-ud-2.17-251125"

    private struct Response: Decodable {
        let result: String
    }

    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func analyze(sentences: [String]) async throws -> [SentenceAnalysis] {
        guard !sentences.isEmpty else { return [] }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(
            "application/x-www-form-urlencoded; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = formBody([
            ("model", Self.model),
            ("tokenizer", ""),
            ("tagger", ""),
            ("parser", ""),
            ("output", "conllu"),
            ("data", sentences.joined(separator: "\n") + "\n")
        ])

        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw UDPipeError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8)
                .map { String($0.prefix(300)) }
                ?? "The service did not provide an error message."
            throw UDPipeError.api(status: http.statusCode, detail: detail)
        }

        let payload: Response
        do {
            payload = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw UDPipeError.invalidResponse
        }
        return try CoNLLUParser.parse(
            payload.result,
            sourceSentences: sentences,
            engine: "UDPipe 2",
            model: Self.model
        )
    }

    private func formBody(_ fields: [(String, String)]) -> Data {
        let body = fields.map { key, value in
            "\(formEncode(key))=\(formEncode(value))"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    private func formEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
