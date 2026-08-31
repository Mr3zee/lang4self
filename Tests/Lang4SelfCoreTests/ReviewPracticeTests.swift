import XCTest
@testable import Lang4SelfCore

final class ReviewPracticeTests: XCTestCase {
    func testSavedDictCCCardRetainsItsAnnotatedPlural() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let dictionary = directory.appendingPathComponent("dictionary.txt")
        try "Haus {n} [Häuser]\thouse\n"
            .write(to: dictionary, atomically: true, encoding: .utf8)
        let store = try LocalStore(url: directory.appendingPathComponent("store.sqlite3"))
        try await store.seedStarterDictionaryIfNeeded()
        _ = try await store.importDictionary(from: dictionary)
        let entries = try await store.searchDictionary("Haus")
        _ = try await store.addCard(from: try XCTUnwrap(entries.first))
        let cards = try await store.dueCards()

        let challenge = try XCTUnwrap(
            ReviewChallenge(card: try XCTUnwrap(cards.first), mode: .plural)
        )
        XCTAssertTrue(challenge.accepts("Häuser"))
    }

    func testModesCycleAndWrapInBothDirections() {
        XCTAssertEqual(ReviewTestMode.flashcard.advanced(by: -1), .listeningWords)
        XCTAssertEqual(ReviewTestMode.flashcard.advanced(by: 1), .writing)
        XCTAssertEqual(ReviewTestMode.plural.advanced(by: 1), .listeningWords)
        XCTAssertEqual(ReviewTestMode.listeningWords.advanced(by: 1), .flashcard)
    }

    func testListeningWordsChecksOnlyTheHeardGermanSpelling() throws {
        let challenge = try XCTUnwrap(ReviewChallenge(
            card: PersonalCard(german: "Straße", english: ""),
            mode: .listeningWords
        ))

        XCTAssertTrue(challenge.accepts("straße"))
        XCTAssertFalse(challenge.accepts("street"))
        XCTAssertTrue(ReviewTestMode.listeningWords.requiresWrittenAnswer)
        XCTAssertFalse(ReviewTestMode.listeningWords.usesTranslationCarousel)
    }

    func testWritingRequiresTheGermanSpellingButIgnoresCaseAndOuterPunctuation() throws {
        let card = PersonalCard(german: "Mütter", english: "mothers")
        let challenge = try XCTUnwrap(ReviewChallenge(card: card, mode: .writing))

        XCTAssertTrue(challenge.accepts("  mütter! "))
        XCTAssertFalse(challenge.accepts("Mutter"))

        let street = try XCTUnwrap(ReviewChallenge(
            card: PersonalCard(german: "Straße", english: "street"),
            mode: .writing
        ))
        XCTAssertTrue(street.accepts("STRAẞE"))
        XCTAssertFalse(street.accepts("Strasse"))
    }

    func testSpeakingAcceptsANounWithOrWithoutItsArticle() throws {
        let card = PersonalCard(
            german: "Hund",
            english: "dog",
            kind: .noun,
            gender: .masculine
        )
        let challenge = try XCTUnwrap(ReviewChallenge(card: card, mode: .speaking))

        XCTAssertTrue(challenge.accepts("Hund"))
        XCTAssertTrue(challenge.accepts("der Hund"))
        XCTAssertFalse(challenge.accepts("die Hunde"))
    }

    func testGenderOnlyIncludesSingularNounsWithAKnownGender() throws {
        let noun = PersonalCard(
            german: "Haus",
            english: "house",
            kind: .noun,
            gender: .neuter
        )
        let challenge = try XCTUnwrap(ReviewChallenge(card: noun, mode: .gender))

        XCTAssertTrue(challenge.accepts("das"))
        XCTAssertFalse(challenge.accepts("der"))
        XCTAssertNil(ReviewChallenge(
            card: PersonalCard(german: "Leute", english: "people", kind: .noun, gender: .plural),
            mode: .gender
        ))
        XCTAssertNil(ReviewChallenge(
            card: PersonalCard(german: "Haus", english: "house", kind: .noun),
            mode: .gender
        ))
    }

    func testGermanToEnglishWritingAcceptsEveryEnglishMeaningButNotOtherLanguages() throws {
        let card = PersonalCard(
            german: "Mädchen",
            english: "girl; chick; девочка",
            kind: .noun,
            meanings: [
                DictionaryMeaning(english: "girl", language: .english),
                DictionaryMeaning(english: "chick", language: .english),
                DictionaryMeaning(english: "девочка", language: .russian)
            ]
        )
        let challenge = try XCTUnwrap(
            ReviewChallenge(card: card, mode: .germanToEnglishWriting)
        )

        XCTAssertTrue(challenge.accepts("girl"))
        XCTAssertTrue(challenge.accepts("Chick"))
        XCTAssertFalse(challenge.accepts("девочка"))
    }

    func testConjugationUsesTheGivenPronounAndImportedPresentForm() throws {
        let forms = [
            DictionaryForm(
                form: "aufstehe",
                tags: ["first-person", "present", "singular"]
            ),
            DictionaryForm(
                form: "aufstehst",
                tags: ["second-person", "present", "singular"]
            ),
            DictionaryForm(
                form: "aufsteht",
                tags: ["third-person", "present", "singular"]
            )
        ]
        let card = PersonalCard(
            german: "aufstehen",
            english: "to get up",
            kind: .verb,
            rawGerman: "auf|stehen",
            forms: forms
        )
        let challenge = try XCTUnwrap(
            ReviewChallenge(card: card, mode: .conjugation, conjugationIndex: 1)
        )

        XCTAssertEqual(challenge.conjugationPronoun, "du")
        XCTAssertEqual(challenge.acceptedAnswers.first, "stehst auf")
        XCTAssertTrue(challenge.accepts("stehst auf"))
        XCTAssertTrue(challenge.accepts("du stehst auf"))
        XCTAssertFalse(challenge.accepts("steht auf"))
    }

    func testConjugationIncludesTheMatchingReflexivePronoun() throws {
        let challenge = try XCTUnwrap(ReviewChallenge(
            card: PersonalCard(
                german: "sich freuen",
                english: "to be happy",
                kind: .verb
            ),
            mode: .conjugation,
            conjugationIndex: 1
        ))

        XCTAssertEqual(challenge.conjugationPronoun, "du")
        XCTAssertEqual(challenge.acceptedAnswers.first, "freust dich")
        XCTAssertTrue(challenge.accepts("du freust dich"))
        XCTAssertFalse(challenge.accepts("du freust dir"))
    }

    func testConjugationSupportsDativeReflexivePronouns() throws {
        let challenge = try XCTUnwrap(ReviewChallenge(
            card: PersonalCard(
                german: "sich merken",
                english: "to remember",
                kind: .verb,
                rawGerman: "sich [Dat.] merken {vr}"
            ),
            mode: .conjugation,
            conjugationIndex: 1
        ))

        XCTAssertEqual(challenge.acceptedAnswers.first, "merkst dir")
        XCTAssertTrue(challenge.accepts("du merkst dir"))
        XCTAssertFalse(challenge.accepts("du merkst dich"))
    }

    func testConjugationAcceptsExplicitAccusativeAndDativeAlternatives() throws {
        let forms = [
            DictionaryForm(form: "wasche", tags: ["first-person", "present", "singular"]),
            DictionaryForm(form: "wäschst", tags: ["second-person", "present", "singular"]),
            DictionaryForm(form: "wäscht", tags: ["third-person", "present", "singular"])
        ]
        let challenge = try XCTUnwrap(ReviewChallenge(
            card: PersonalCard(
                german: "sich waschen",
                english: "to wash oneself",
                kind: .verb,
                rawGerman: "sich [Akk.]/[Dat.] waschen {vr}",
                forms: forms
            ),
            mode: .conjugation,
            conjugationIndex: 1
        ))

        XCTAssertTrue(challenge.accepts("wäschst dich"))
        XCTAssertTrue(challenge.accepts("du wäschst dir"))
    }

    func testConjugationAcceptsEveryThirdPersonGenderAndFormalSie() throws {
        let card = PersonalCard(
            german: "sich freuen",
            english: "to be happy",
            kind: .verb
        )
        let thirdPerson = try XCTUnwrap(ReviewChallenge(
            card: card,
            mode: .conjugation,
            conjugationIndex: 2
        ))
        let pluralAndFormal = try XCTUnwrap(ReviewChallenge(
            card: card,
            mode: .conjugation,
            conjugationIndex: 5
        ))

        XCTAssertEqual(thirdPerson.conjugationPronoun, "er/sie/es")
        XCTAssertTrue(thirdPerson.accepts("er freut sich"))
        XCTAssertTrue(thirdPerson.accepts("sie freut sich"))
        XCTAssertTrue(thirdPerson.accepts("es freut sich"))
        XCTAssertEqual(pluralAndFormal.conjugationPronoun, "sie/Sie")
        XCTAssertTrue(pluralAndFormal.accepts("Sie freuen sich"))
    }

    func testSeparableReflexivePronounPrecedesTheDetachedPrefix() throws {
        let forms = [
            DictionaryForm(form: "anziehe", tags: ["first-person", "present", "singular"]),
            DictionaryForm(form: "anziehst", tags: ["second-person", "present", "singular"]),
            DictionaryForm(form: "anzieht", tags: ["third-person", "present", "singular"])
        ]
        let card = PersonalCard(
            german: "sich anziehen",
            english: "to get dressed",
            kind: .verb,
            rawGerman: "sich an|ziehen {vr}",
            forms: forms
        )
        let challenge = try XCTUnwrap(ReviewChallenge(
            card: card,
            mode: .conjugation,
            conjugationIndex: 1
        ))
        let info = GermanMorphology.info(for: DictionaryEntry(
            german: card.german,
            english: card.english,
            rawGerman: card.rawGerman,
            kind: card.kind,
            forms: forms
        ))

        XCTAssertEqual(challenge.acceptedAnswers.first, "ziehst dich an")
        XCTAssertTrue(challenge.accepts("du ziehst dich an"))
        XCTAssertEqual(info.headline, "sich anziehen")
        XCTAssertEqual(info.rows.first { $0.label == "Infinitive" }?.value, "sich anziehen")
        XCTAssertTrue(info.rows.first { $0.label == "Present" }?.value.contains("er/sie/es zieht sich an") == true)
        XCTAssertFalse(info.rows.contains { $0.value.contains("zieht an sich") })
    }

    func testPluralOnlyIncludesNounsWithAtLeastOneKnownForm() throws {
        let card = PersonalCard(
            german: "Thema",
            english: "topic",
            kind: .noun,
            gender: .neuter,
            pluralForms: ["Themen", "Themata"]
        )
        let challenge = try XCTUnwrap(ReviewChallenge(card: card, mode: .plural))

        XCTAssertTrue(challenge.accepts("Themen"))
        XCTAssertTrue(challenge.accepts("themata"))
        XCTAssertNil(ReviewChallenge(
            card: PersonalCard(german: "Wasser", english: "water", kind: .noun),
            mode: .plural
        ))
        XCTAssertNil(ReviewChallenge(
            card: PersonalCard(german: "lernen", english: "to learn", kind: .verb),
            mode: .plural
        ))

        let unchangedPlural = PersonalCard(
            german: "Lehrer",
            english: "teacher",
            kind: .noun,
            gender: .masculine,
            forms: [
                DictionaryForm(form: "Lehrer", tags: ["nominative", "plural"]),
                DictionaryForm(form: "Lehrern", tags: ["dative", "plural"])
            ]
        )
        let unchangedChallenge = try XCTUnwrap(
            ReviewChallenge(card: unchangedPlural, mode: .plural)
        )
        XCTAssertEqual(unchangedChallenge.acceptedAnswers, ["Lehrer"])
    }
}
