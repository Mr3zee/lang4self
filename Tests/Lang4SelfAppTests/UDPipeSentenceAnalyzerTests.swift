import Foundation
import XCTest
@testable import Lang4Self

final class UDPipeSentenceAnalyzerTests: XCTestCase {
    override func tearDown() {
        MockUDPipeURLProtocol.setHandler(nil)
        super.tearDown()
    }

    func testSendsOneBatchRequestAndParsesAllSentences() async throws {
        var requestCount = 0
        MockUDPipeURLProtocol.setHandler { request in
            requestCount += 1
            XCTAssertEqual(request.url, UDPipeSentenceAnalyzer.endpoint)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Content-Type"),
                "application/x-www-form-urlencoded; charset=utf-8"
            )

            let fields = try Self.formFields(in: request)
            XCTAssertEqual(fields["model"], UDPipeSentenceAnalyzer.model)
            XCTAssertEqual(fields["tokenizer"], "")
            XCTAssertEqual(fields["tagger"], "")
            XCTAssertEqual(fields["parser"], "")
            XCTAssertEqual(fields["output"], "conllu")
            XCTAssertEqual(fields["data"], "Ich komme rein.\nDer Hund schläft.\n")

            let conllu = """
                # text = Ich komme rein.
                1	Ich	ich	PRON	PPER	Case=Nom	2	nsubj	_	_
                2	komme	kommen	VERB	VVFIN	Mood=Ind	0	root	_	_
                3	rein	rein	ADP	PTKVZ	_	2	compound:prt	_	_
                4	.	.	PUNCT	$.	_	2	punct	_	_

                # text = Der Hund schläft.
                1	Der	der	DET	ART	Case=Nom	2	det	_	_
                2	Hund	Hund	NOUN	NN	Case=Nom	3	nsubj	_	_
                3	schläft	schlafen	VERB	VVFIN	Mood=Ind	0	root	_	_
                4	.	.	PUNCT	$.	_	3	punct	_	_

                """
            let body = try JSONSerialization.data(withJSONObject: ["result": conllu])
            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                body
            )
        }
        let analyzer = UDPipeSentenceAnalyzer(session: makeMockSession())

        let analyses = try await analyzer.analyze(sentences: [
            "Ich komme rein.",
            "Der Hund schläft."
        ])

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(analyses.count, 2)
        XCTAssertEqual(analyses[0].engine, "UDPipe 2")
        XCTAssertEqual(analyses[0].model, UDPipeSentenceAnalyzer.model)
        XCTAssertEqual(analyses[0].tokens.map(\.lemma), ["ich", "kommen", "rein", "."])
        XCTAssertEqual(analyses[1].tokens[1].surface, "Hund")
    }

    func testReportsHTTPFailureWithoutParsingIt() async {
        MockUDPipeURLProtocol.setHandler { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data("rate limited".utf8)
            )
        }
        let analyzer = UDPipeSentenceAnalyzer(session: makeMockSession())

        do {
            _ = try await analyzer.analyze(sentences: ["Hallo."])
            XCTFail("Expected HTTP failure")
        } catch {
            XCTAssertEqual(
                error as? UDPipeError,
                .api(status: 429, detail: "rate limited")
            )
        }
    }

    private static func formFields(in request: URLRequest) throws -> [String: String] {
        let data: Data
        if let httpBody = request.httpBody {
            data = httpBody
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var result = Data()
            var buffer = [UInt8](repeating: 0, count: 1_024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0 else { throw stream.streamError ?? UDPipeError.invalidResponse }
                if count == 0 { break }
                result.append(buffer, count: count)
            }
            data = result
        } else {
            throw UDPipeError.invalidResponse
        }
        let body = try XCTUnwrap(String(data: data, encoding: .utf8))
        var components = URLComponents()
        components.percentEncodedQuery = body
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
            ($0.name, $0.value ?? "")
        })
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockUDPipeURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class MockUDPipeURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private static var handler: Handler?

    static func setHandler(_ newHandler: Handler?) {
        lock.lock()
        handler = newHandler
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: UDPipeError.invalidResponse)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
