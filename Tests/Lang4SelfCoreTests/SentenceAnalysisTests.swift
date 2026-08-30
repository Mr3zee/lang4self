import XCTest
@testable import Lang4SelfCore

final class SentenceAnalysisTests: XCTestCase {
    func testParsesBatchAndLinksRelativePronounToAntecedent() throws {
        let sentence = "Der Hund, den ich liebe."
        let analyses = try CoNLLUParser.parse(
            """
            # sent_id = 1
            # text = Der Hund, den ich liebe.
            1	Der	der	DET	ART	Case=Nom|Definite=Def	2	det	_	_
            2	Hund	Hund	NOUN	NN	Case=Nom|Gender=Masc	0	root	_	_
            3	,	,	PUNCT	$,	_	2	punct	_	_
            4	den	der	PRON	PRELS	Case=Acc|PronType=Dem,Rel	6	obj	_	_
            5	ich	ich	PRON	PPER	Case=Nom|PronType=Prs	6	nsubj	_	_
            6	liebe	lieben	VERB	VVFIN	Mood=Ind|Tense=Pres	2	acl	_	_
            7	.	.	PUNCT	$.	_	6	punct	_	_

            """,
            sourceSentences: [sentence],
            engine: "UDPipe 2",
            model: "german-hdt-test"
        )

        let analysis = try XCTUnwrap(analyses.first)
        let sentenceTokens = SentenceTokenizer.tokens(in: sentence)
        let relativePronoun = sentenceTokens[2]
        let lookup = SentenceRelations.contextualLookupToken(
            for: relativePronoun,
            sentence: sentence,
            tokens: sentenceTokens,
            analysis: analysis
        )

        XCTAssertEqual(analysis.tokens[1].morphologicalFeatures["Gender"], "Masc")
        XCTAssertEqual(lookup.lookupTerm, "Hund")
        XCTAssertEqual(
            SentenceRelations.relatedTokenIndices(
                for: relativePronoun,
                sentence: sentence,
                tokens: sentenceTokens,
                analysis: analysis
            ),
            [1, 2]
        )
    }

    func testLinksBothPartsOfSeparatedVerbToCombinedLookupTerm() throws {
        let sentence = "Ich komme rein."
        let analysis = try XCTUnwrap(CoNLLUParser.parse(
            """
            # text = Ich komme rein.
            1	Ich	ich	PRON	PPER	Case=Nom	2	nsubj	_	_
            2	komme	kommen	VERB	VVFIN	Mood=Ind|Tense=Pres	0	root	_	_
            3	rein	rein	ADP	PTKVZ	_	2	compound:prt	_	_
            4	.	.	PUNCT	$.	_	2	punct	_	_

            """,
            sourceSentences: [sentence],
            engine: "UDPipe 2",
            model: "german-hdt-test"
        ).first)
        let tokens = SentenceTokenizer.tokens(in: sentence)

        for token in tokens[1...2] {
            let lookup = SentenceRelations.contextualLookupToken(
                for: token,
                sentence: sentence,
                tokens: tokens,
                analysis: analysis
            )
            XCTAssertEqual(lookup.lookupTerm, "reinkommen")
            XCTAssertEqual(
                SentenceRelations.relatedTokenIndices(
                    for: token,
                    sentence: sentence,
                    tokens: tokens,
                    analysis: analysis
                ),
                [1, 2]
            )
        }
    }

    func testRejectsResponseWithDifferentSentenceCount() {
        XCTAssertThrowsError(try CoNLLUParser.parse(
            """
            1	Hallo	hallo	INTJ	ITJ	_	0	root	_	_

            """,
            sourceSentences: ["Hallo", "Guten Tag"],
            engine: "UDPipe 2",
            model: "german-hdt-test"
        )) { error in
            XCTAssertEqual(
                error as? CoNLLUParsingError,
                .sentenceCount(expected: 2, actual: 1)
            )
        }
    }
}
