import XCTest
import Lang4SelfCore
@testable import Lang4Self

@MainActor
final class DictionaryTranslationServiceTests: XCTestCase {
    func testKeepsIndexedResultsWithoutCallingAppleTranslation() async throws {
        let indexedEntry = DictionaryEntry(german: "Haus", english: "house")
        let translator = StubDictionaryTranslator(result: "unused")
        let service = DictionarySearchService(
            index: StubDictionaryIndex(results: [indexedEntry]),
            translator: translator
        )

        let results = try await service.search("Haus", limit: 80)

        XCTAssertEqual(results, [indexedEntry])
        XCTAssertTrue(translator.requests.isEmpty)
    }

    func testFallsBackToAVisiblyMarkedTranslationForAnEmptyIndexResult() async throws {
        let translator = StubDictionaryTranslator(result: "This sentence is translated locally.")
        let service = DictionarySearchService(
            index: StubDictionaryIndex(results: []),
            translator: translator
        )
        var phases: [DictionaryTranslationPhase] = []
        service.translationPhaseDidChange = { phases.append($0) }

        let results = try await service.search("  Dieser Satz wird lokal übersetzt.  ", limit: 80)
        let result = try XCTUnwrap(results.first)

        XCTAssertEqual(translator.requests, ["Dieser Satz wird lokal übersetzt."])
        XCTAssertEqual(result.german, "Dieser Satz wird lokal übersetzt.")
        XCTAssertEqual(result.english, "This sentence is translated locally.")
        XCTAssertEqual(result.kind, .phrase)
        XCTAssertTrue(result.isAppleTranslation)
        XCTAssertEqual(result.id, 0)
        XCTAssertEqual(phases, [.downloadingLanguages, .translating, .idle])
    }
}

private actor StubDictionaryIndex: DictionaryIndexSearching {
    let results: [DictionaryEntry]

    init(results: [DictionaryEntry]) {
        self.results = results
    }

    func searchDictionary(_ query: String, limit: Int) async throws -> [DictionaryEntry] {
        results
    }
}

@MainActor
private final class StubDictionaryTranslator: DictionaryTranslating {
    var phaseDidChange: ((DictionaryTranslationPhase) -> Void)?
    let result: String?
    private(set) var requests: [String] = []

    init(result: String?) {
        self.result = result
    }

    func translateGermanToEnglish(_ text: String) async throws -> String? {
        requests.append(text)
        phaseDidChange?(.downloadingLanguages)
        phaseDidChange?(.translating)
        defer { phaseDidChange?(.idle) }
        return result
    }
}
