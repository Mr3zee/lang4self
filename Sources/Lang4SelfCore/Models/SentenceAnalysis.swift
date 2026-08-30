import Foundation

public struct SentenceAnalysis: Codable, Hashable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let engine: String
    public let model: String
    public let tokens: [SentenceAnalysisToken]
    public let rawCoNLLU: String

    public init(
        formatVersion: Int = SentenceAnalysis.currentFormatVersion,
        engine: String,
        model: String,
        tokens: [SentenceAnalysisToken],
        rawCoNLLU: String
    ) {
        self.formatVersion = formatVersion
        self.engine = engine
        self.model = model
        self.tokens = tokens
        self.rawCoNLLU = rawCoNLLU
    }
}

public struct SentenceAnalysisToken: Codable, Hashable, Sendable {
    public let id: Int
    public let surface: String
    public let lemma: String
    public let universalPartOfSpeech: String
    public let languageSpecificPartOfSpeech: String
    public let morphologicalFeatures: [String: String]
    public let headID: Int?
    public let dependencyRelation: String
    public let startUTF16: Int
    public let lengthUTF16: Int

    public init(
        id: Int,
        surface: String,
        lemma: String,
        universalPartOfSpeech: String,
        languageSpecificPartOfSpeech: String,
        morphologicalFeatures: [String: String],
        headID: Int?,
        dependencyRelation: String,
        startUTF16: Int,
        lengthUTF16: Int
    ) {
        self.id = id
        self.surface = surface
        self.lemma = lemma
        self.universalPartOfSpeech = universalPartOfSpeech
        self.languageSpecificPartOfSpeech = languageSpecificPartOfSpeech
        self.morphologicalFeatures = morphologicalFeatures
        self.headID = headID
        self.dependencyRelation = dependencyRelation
        self.startUTF16 = startUTF16
        self.lengthUTF16 = lengthUTF16
    }
}

public protocol SentenceAnalyzing: Sendable {
    func analyze(sentences: [String]) async throws -> [SentenceAnalysis]
}

public enum CoNLLUParsingError: Error, Equatable, LocalizedError {
    case sentenceCount(expected: Int, actual: Int)
    case malformedTokenLine(String)
    case tokenNotFound(token: String, sentence: String)

    public var errorDescription: String? {
        switch self {
        case .sentenceCount(let expected, let actual):
            "UDPipe returned \(actual) sentence analyses instead of \(expected)."
        case .malformedTokenLine:
            "UDPipe returned malformed sentence analysis data."
        case .tokenNotFound:
            "UDPipe tokenization could not be aligned with the generated sentence."
        }
    }
}

public enum CoNLLUParser {
    public static func parse(
        _ conllu: String,
        sourceSentences: [String],
        engine: String,
        model: String
    ) throws -> [SentenceAnalysis] {
        let blocks = sentenceBlocks(in: conllu)
        guard blocks.count == sourceSentences.count else {
            throw CoNLLUParsingError.sentenceCount(
                expected: sourceSentences.count,
                actual: blocks.count
            )
        }

        return try zip(blocks, sourceSentences).map { block, sentence in
            let tokens = try parseTokens(in: block, sourceSentence: sentence)
            return SentenceAnalysis(
                engine: engine,
                model: model,
                tokens: tokens,
                rawCoNLLU: block.joined(separator: "\n") + "\n"
            )
        }
    }

    private static func sentenceBlocks(in conllu: String) -> [[String]] {
        let lines = conllu.components(separatedBy: .newlines)
        var blocks: [[String]] = []
        var current: [String] = []
        var containsSyntacticToken = false

        func finishBlock() {
            if containsSyntacticToken { blocks.append(current) }
            current = []
            containsSyntacticToken = false
        }

        for line in lines {
            if line.isEmpty {
                finishBlock()
                continue
            }
            current.append(line)
            guard !line.hasPrefix("#"), let field = line.split(separator: "\t", maxSplits: 1).first else {
                continue
            }
            if Int(field) != nil { containsSyntacticToken = true }
        }
        finishBlock()
        return blocks
    }

    private static func parseTokens(
        in block: [String],
        sourceSentence: String
    ) throws -> [SentenceAnalysisToken] {
        let source = sourceSentence as NSString
        var searchLocation = 0
        var tokens: [SentenceAnalysisToken] = []

        for line in block where !line.hasPrefix("#") {
            let fields = line.components(separatedBy: "\t")
            guard let idField = fields.first else { continue }
            // CoNLL-U range IDs and empty nodes are metadata, not syntactic words.
            guard let id = Int(idField) else { continue }
            guard fields.count >= 8,
                  let rawHead = Int(fields[6]) else {
                throw CoNLLUParsingError.malformedTokenLine(line)
            }

            let surface = fields[1]
            let remainingLength = source.length - searchLocation
            guard remainingLength >= 0 else {
                throw CoNLLUParsingError.tokenNotFound(token: surface, sentence: sourceSentence)
            }
            let range = source.range(
                of: surface,
                options: [],
                range: NSRange(location: searchLocation, length: remainingLength)
            )
            guard range.location != NSNotFound else {
                throw CoNLLUParsingError.tokenNotFound(token: surface, sentence: sourceSentence)
            }
            searchLocation = range.location + range.length

            tokens.append(.init(
                id: id,
                surface: surface,
                lemma: fields[2] == "_" ? surface : fields[2],
                universalPartOfSpeech: fields[3] == "_" ? "" : fields[3],
                languageSpecificPartOfSpeech: fields[4] == "_" ? "" : fields[4],
                morphologicalFeatures: parseFeatures(fields[5]),
                headID: rawHead == 0 ? nil : rawHead,
                dependencyRelation: fields[7] == "_" ? "" : fields[7],
                startUTF16: range.location,
                lengthUTF16: range.length
            ))
        }
        return tokens
    }

    private static func parseFeatures(_ value: String) -> [String: String] {
        guard value != "_" else { return [:] }
        return value.split(separator: "|").reduce(into: [:]) { result, feature in
            let parts = feature.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            result[parts[0]] = parts[1]
        }
    }
}

public enum SentenceRelations {
    public static func contextualLookupToken(
        for token: SentenceToken,
        sentence: String,
        tokens: [SentenceToken],
        analysis: SentenceAnalysis?,
        nounTokenIndices: Set<Int> = []
    ) -> SentenceToken {
        guard let analysis,
              let analyzed = analyzedToken(for: token, sentence: sentence, sentenceTokens: tokens, analysis: analysis)
        else {
            return SentenceTokenizer.contextualLookupToken(
                for: token,
                in: tokens,
                nounTokenIndices: nounTokenIndices
            )
        }

        if let antecedent = relativeAntecedent(for: analyzed, in: analysis),
           let noun = sentenceToken(for: antecedent, sentence: sentence, sentenceTokens: tokens) {
            return lookupToken(using: noun, surfaceOf: token)
        }

        if analyzed.dependencyRelation == "compound:prt",
           let head = analysis.token(id: analyzed.headID),
           let verb = sentenceToken(for: head, sentence: sentence, sentenceTokens: tokens) {
            return particleLookupToken(selected: token, particle: analyzed, verb: verb, analyzedVerb: head)
        }

        if let particle = analysis.tokens.first(where: {
            $0.headID == analyzed.id && $0.dependencyRelation == "compound:prt"
        }) {
            return particleLookupToken(selected: token, particle: particle, verb: token, analyzedVerb: analyzed)
        }

        if analyzed.dependencyRelation == "det",
           let head = analysis.token(id: analyzed.headID),
           let noun = sentenceToken(for: head, sentence: sentence, sentenceTokens: tokens) {
            return lookupToken(using: noun, surfaceOf: token)
        }

        return SentenceTokenizer.contextualLookupToken(
            for: token,
            in: tokens,
            nounTokenIndices: nounTokenIndices
        )
    }

    public static func relatedTokenIndices(
        for token: SentenceToken,
        sentence: String,
        tokens: [SentenceToken],
        analysis: SentenceAnalysis?,
        nounTokenIndices: Set<Int> = []
    ) -> Set<Int> {
        guard let analysis,
              let analyzed = analyzedToken(for: token, sentence: sentence, sentenceTokens: tokens, analysis: analysis)
        else {
            return SentenceTokenizer.relatedTokenIndices(
                for: token,
                in: tokens,
                nounTokenIndices: nounTokenIndices
            )
        }

        var relatedIDs: Set<Int> = [analyzed.id]

        if analyzed.dependencyRelation == "compound:prt", let headID = analyzed.headID {
            relatedIDs.insert(headID)
        }
        relatedIDs.formUnion(analysis.tokens.filter {
            $0.headID == analyzed.id && $0.dependencyRelation == "compound:prt"
        }.map(\.id))

        if analyzed.dependencyRelation == "det", let headID = analyzed.headID {
            relatedIDs.insert(headID)
        }
        relatedIDs.formUnion(analysis.tokens.filter {
            $0.headID == analyzed.id && $0.dependencyRelation == "det"
        }.map(\.id))

        if let antecedent = relativeAntecedent(for: analyzed, in: analysis) {
            relatedIDs.insert(antecedent.id)
        }
        for candidate in analysis.tokens {
            if relativeAntecedent(for: candidate, in: analysis)?.id == analyzed.id {
                relatedIDs.insert(candidate.id)
            }
        }

        let mapped = Set(relatedIDs.compactMap { id in
            analysis.token(id: id).flatMap {
                sentenceToken(for: $0, sentence: sentence, sentenceTokens: tokens)?.index
            }
        })
        return mapped.isEmpty ? [token.index] : mapped
    }

    private static func lookupToken(using source: SentenceToken, surfaceOf selected: SentenceToken) -> SentenceToken {
        SentenceToken(
            index: selected.index,
            surface: selected.surface,
            lookupTerm: source.lookupTerm,
            cardID: source.cardID
        )
    }

    private static func particleLookupToken(
        selected: SentenceToken,
        particle: SentenceAnalysisToken,
        verb: SentenceToken,
        analyzedVerb: SentenceAnalysisToken
    ) -> SentenceToken {
        let hasMappedLemma = verb.cardID != nil ||
            SentenceTokenizer.normalized(verb.lookupTerm) != SentenceTokenizer.normalized(verb.surface)
        let particleTerm = SentenceTokenizer.lookupTerm(from: particle.surface).lowercased()
        let verbLemma = analyzedVerb.lemma.lowercased()
        let inferredLookup = SentenceTokenizer.normalized(verbLemma)
            .hasPrefix(SentenceTokenizer.normalized(particleTerm))
            ? verbLemma
            : particleTerm + verbLemma
        let lookup = hasMappedLemma
            ? verb.lookupTerm
            : inferredLookup
        return SentenceToken(
            index: selected.index,
            surface: selected.surface,
            lookupTerm: lookup,
            cardID: verb.cardID
        )
    }

    private static func relativeAntecedent(
        for token: SentenceAnalysisToken,
        in analysis: SentenceAnalysis
    ) -> SentenceAnalysisToken? {
        guard token.languageSpecificPartOfSpeech == "PRELS" ||
                token.morphologicalFeatures["PronType"]?.split(separator: ",").contains("Rel") == true
        else { return nil }

        var visited: Set<Int> = []
        var current = token
        while let head = analysis.token(id: current.headID), visited.insert(head.id).inserted {
            if head.dependencyRelation.hasPrefix("acl"),
               let antecedent = analysis.token(id: head.headID) {
                return antecedent
            }
            current = head
        }
        return nil
    }

    private static func analyzedToken(
        for token: SentenceToken,
        sentence: String,
        sentenceTokens: [SentenceToken],
        analysis: SentenceAnalysis
    ) -> SentenceAnalysisToken? {
        guard let range = sentenceTokenRanges(sentence: sentence, tokens: sentenceTokens)[token.index] else {
            return nil
        }
        return analysis.tokens
            .filter { $0.universalPartOfSpeech != "PUNCT" && overlap(range, $0.range) > 0 }
            .max { overlap(range, $0.range) < overlap(range, $1.range) }
    }

    private static func sentenceToken(
        for analyzed: SentenceAnalysisToken,
        sentence: String,
        sentenceTokens: [SentenceToken]
    ) -> SentenceToken? {
        let ranges = sentenceTokenRanges(sentence: sentence, tokens: sentenceTokens)
        return sentenceTokens
            .filter { overlap(ranges[$0.index], analyzed.range) > 0 }
            .max { overlap(ranges[$0.index], analyzed.range) < overlap(ranges[$1.index], analyzed.range) }
    }

    private static func sentenceTokenRanges(
        sentence: String,
        tokens: [SentenceToken]
    ) -> [Int: NSRange] {
        let source = sentence as NSString
        var location = 0
        var result: [Int: NSRange] = [:]
        for token in tokens {
            let remaining = source.length - location
            guard remaining >= 0 else { break }
            let range = source.range(
                of: token.surface,
                options: [],
                range: NSRange(location: location, length: remaining)
            )
            guard range.location != NSNotFound else { break }
            result[token.index] = range
            location = range.location + range.length
        }
        return result
    }

    private static func overlap(_ lhs: NSRange?, _ rhs: NSRange) -> Int {
        guard let lhs else { return 0 }
        return NSIntersectionRange(lhs, rhs).length
    }
}

private extension SentenceAnalysis {
    func token(id: Int?) -> SentenceAnalysisToken? {
        guard let id else { return nil }
        return tokens.first { $0.id == id }
    }
}

private extension SentenceAnalysisToken {
    var range: NSRange {
        NSRange(location: startUTF16, length: lengthUTF16)
    }
}
