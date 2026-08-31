import XCTest
import Lang4SelfCore
@testable import Lang4Self

final class SentenceGenerationContractTests: XCTestCase {
    func testAcceptsInflectedAdjectiveAndSeparatedVerbForms() {
        let vocabulary = [
            card(
                id: 6,
                german: "einfach",
                kind: .adjective,
                forms: [DictionaryForm(form: "einfacher", tags: ["comparative"])]
            ),
            card(
                id: 8,
                german: "ankommen",
                kind: .verb,
                forms: [DictionaryForm(form: "ankommt", tags: ["present"])]
            )
        ]
        let response = SentenceGenerationEnvelope(sentences: [
            candidate(
                "Das ist eine einfache Frage.",
                id: 6,
                surfaceTokens: ["einfache"]
            ),
            candidate(
                "Der Zug kommt heute an.",
                id: 8,
                surfaceTokens: ["kommt", "an"]
            )
        ])

        let drafts = GeneratedSentenceValidator(vocabulary: vocabulary)
            .validatedDrafts(from: response, limit: 2)

        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].tokens.filter { $0.cardID == 6 }.map(\.lookupTerm), ["einfach"])
        XCTAssertEqual(drafts[1].tokens.filter { $0.cardID == 8 }.map(\.surface), ["kommt", "an."])
    }

    func testRejectsWrongLemmaInventedIDAndUnreportedSurface() {
        let vocabulary = [
            card(
                id: 9,
                german: "auskommen",
                kind: .verb,
                forms: [DictionaryForm(form: "auskommt", tags: ["present"])]
            ),
            card(id: 5, german: "Hund", kind: .noun)
        ]
        let response = SentenceGenerationEnvelope(sentences: [
            candidate("Ich mache das Licht aus.", id: 9, surfaceTokens: ["mache", "aus"]),
            candidate("Der Hundi schläft.", id: 5, surfaceTokens: ["Hundi"]),
            candidate("Der Hund schläft.", id: 999, surfaceTokens: ["Hund"]),
            candidate("Der Hund schläft.", id: 5, surfaceTokens: ["Katze"])
        ])

        let drafts = GeneratedSentenceValidator(vocabulary: vocabulary)
            .validatedDrafts(from: response, limit: 4)

        XCTAssertTrue(drafts.isEmpty)
    }

    func testRejectsDuplicateSentencesAndMalformedMultiTokenField() {
        let vocabulary = [card(id: 5, german: "Hund", kind: .noun)]
        let response = SentenceGenerationEnvelope(sentences: [
            candidate("Der Hund schläft heute ruhig.", id: 5, surfaceTokens: ["Hund"]),
            candidate("Der Hund schläft heute ruhig!", id: 5, surfaceTokens: ["Hund"]),
            candidate("Heute sieht der Hund müde aus.", id: 5, surfaceTokens: ["der Hund"])
        ])

        let drafts = GeneratedSentenceValidator(vocabulary: vocabulary)
            .validatedDrafts(from: response, limit: 3)

        XCTAssertEqual(drafts.map(\.german), ["Der Hund schläft heute ruhig."])
    }

    func testPromptAndValidatorUseSelectedGenerationOptions() throws {
        let options = SentenceGenerationOptions(
            proficiency: .c1,
            minimumWords: 7,
            maximumWords: 9,
            style: "formal newspaper report"
        )
        let vocabulary = [card(id: 5, german: "Hund", kind: .noun)]
        let contract = SentenceGenerationContract(vocabulary: vocabulary, options: options)
        let response = SentenceGenerationEnvelope(sentences: [
            candidate("Der Hund schläft heute ruhig.", id: 5, surfaceTokens: ["Hund"]),
            candidate("Der kleine Hund schläft heute sehr ruhig.", id: 5, surfaceTokens: ["Hund"])
        ])

        XCTAssertTrue(contract.systemPrompt(count: 2).contains("at C1 CEFR level"))
        XCTAssertTrue(contract.systemPrompt(count: 2).contains("7-9 words"))
        XCTAssertTrue(contract.systemPrompt(count: 2).contains("Full output JSON Schema:"))
        XCTAssertTrue(contract.systemPrompt(count: 2).contains("Example sentence item 1"))
        XCTAssertTrue(contract.systemPrompt(count: 2).contains("Example sentence item 2"))
        XCTAssertTrue(try contract.userPrompt(excluding: []).contains(#""style":"formal newspaper report""#))
        XCTAssertEqual(
            GeneratedSentenceValidator(vocabulary: vocabulary, options: options)
                .validatedDrafts(from: response, limit: 2)
                .map(\.german),
            ["Der kleine Hund schläft heute sehr ruhig."]
        )
    }

    func testGenerationOptionsClampAndOrderWordLimits() {
        let options = SentenceGenerationOptions(
            proficiency: .a2,
            minimumWords: 40,
            maximumWords: 1,
            style: "  \n"
        ).sanitized

        XCTAssertEqual(options.proficiency, .a2)
        XCTAssertEqual(options.minimumWords, 2)
        XCTAssertEqual(options.maximumWords, 30)
        XCTAssertEqual(options.style, SentenceGenerationOptions.defaultStyle)
    }

    func testSchemaRequiresExactSentenceCountAndOutputBudgetIsBounded() throws {
        let format = SentenceGenerationContract.responseFormat(count: 5)
        let data = try JSONSerialization.data(withJSONObject: format)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let jsonSchema = try XCTUnwrap(root["json_schema"] as? [String: Any])
        let schema = try XCTUnwrap(jsonSchema["schema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let sentences = try XCTUnwrap(properties["sentences"] as? [String: Any])

        XCTAssertEqual(sentences["minItems"] as? Int, 5)
        XCTAssertEqual(sentences["maxItems"] as? Int, 5)
        XCTAssertEqual(
            SentenceGenerationContract.outputTokenLimit(requestedLimit: 4_096, sentenceCount: 5),
            896
        )
    }

    func testDecoderAcceptsFencedJSONAndStringVocabularyID() throws {
        let contract = SentenceGenerationContract(vocabulary: [])
        let response = try contract.decodeEnvelope(
            """
            ```json
            {"sentences":[{"german":"Der Hund schläft.","translation":"The dog sleeps.","vocabulary_id":"5","surface_tokens":["Hund"]}]}
            ```
            """
        )

        XCTAssertEqual(response.sentences.first?.vocabularyID, 5)
    }

    private func candidate(
        _ german: String,
        id: Int64,
        surfaceTokens: [String]
    ) -> SentenceGenerationCandidate {
        SentenceGenerationCandidate(
            german: german,
            translation: "Accurate translation.",
            vocabularyID: id,
            surfaceTokens: surfaceTokens
        )
    }

    private func card(
        id: Int64,
        german: String,
        kind: WordKind,
        forms: [DictionaryForm] = []
    ) -> PersonalCard {
        PersonalCard(
            id: id,
            german: german,
            english: "translation",
            kind: kind,
            forms: forms
        )
    }
}
