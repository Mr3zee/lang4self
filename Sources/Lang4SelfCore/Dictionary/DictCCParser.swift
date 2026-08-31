import Foundation

public enum DictCCParser {
    private static let curlyExpression = try! NSRegularExpression(pattern: #"\s*\{[^}]+\}"#)
    private static let squareExpression = try! NSRegularExpression(pattern: #"\s*\[[^]]+\]"#)
    private static let angleExpression = try! NSRegularExpression(pattern: #"\s*<[^>]+>"#)

    public static func parse(
        line: String,
        germanFirst: Bool = true,
        translationLanguage: TranslationLanguage = .english
    ) -> DictionaryEntry? {
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard columns.count >= 2 else { return nil }

        let germanColumn = germanFirst ? 0 : 1
        let englishColumn = germanFirst ? 1 : 0
        let rawGerman = String(columns[germanColumn]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rawEnglish = String(columns[englishColumn]).trimmingCharacters(in: .whitespacesAndNewlines)
        let declaredKind = columns.count > 2
            ? String(columns[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let subject = columns.count > 3
            ? String(columns[3]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        guard !rawGerman.isEmpty, !rawEnglish.isEmpty else { return nil }

        let gender = detectGender(in: rawGerman)
        let kind = detectKind(in: rawGerman, english: rawEnglish, declaredKind: declaredKind, gender: gender)
        let german = cleanedTerm(rawGerman)
        let english = cleanedTerm(rawEnglish)
        guard !german.isEmpty, !english.isEmpty else { return nil }

        return DictionaryEntry(
            german: german,
            english: english,
            rawGerman: rawGerman,
            rawEnglish: rawEnglish,
            kind: kind,
            gender: gender,
            usage: extractUsage(from: rawGerman),
            source: "dict.cc",
            meanings: [DictionaryMeaning(
                english: english,
                rawEnglish: rawEnglish,
                rawGerman: rawGerman,
                language: translationLanguage,
                gender: gender,
                usage: extractUsage(from: rawGerman),
                grammar: declaredKind.isEmpty ? nil : declaredKind,
                subject: subject.isEmpty ? nil : subject
            )]
        )
    }

    public static func normalized(_ value: String) -> String {
        cleanedTerm(value)
            .replacingOccurrences(of: "|", with: "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func cleanedTerm(_ value: String) -> String {
        var result = replacingMatches(curlyExpression, in: value, with: "")
        result = replacingMatches(squareExpression, in: result, with: "")
        result = replacingMatches(angleExpression, in: result, with: "")
        return result
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func detectGender(in value: String) -> Gender {
        let lower = value.lowercased()
        if lower.contains("{m}") { return .masculine }
        if lower.contains("{f}") { return .feminine }
        if lower.contains("{n}") { return .neuter }
        if lower.contains("{pl}") { return .plural }
        return .unknown
    }

    private static func detectKind(in value: String, english: String, declaredKind: String, gender: Gender) -> WordKind {
        if gender != .unknown { return .noun }
        if let declared = wordKind(for: declaredKind) { return declared }
        let lower = value.lowercased()
        let lowerEnglish = english.lowercased()
        if lowerEnglish.contains("[determiner]")
            || lowerEnglish.contains("[possessive]")
            || lowerEnglish.contains("[article]")
            || lower.contains("{indefinite article}") {
            return .determiner
        }
        if lowerEnglish.contains("[pronoun]")
            || lowerEnglish.contains("[relative pronoun]")
            || lower.contains("[pronomen]")
            || lower.contains("{pronomen}") {
            return .pronoun
        }
        if ["{vi}", "{vt}", "{vr}", "{verb}", "{v.i.}", "{v.t.}"].contains(where: lower.contains)
            || value.contains("|")
            || looksLikeEnglishInfinitive(lowerEnglish) { return .verb }
        if lower.contains("{adj}") || lower.contains("{adj.}") { return .adjective }
        if lower.contains("{adv}") || lower.contains("{adv.}") { return .adverb }
        if cleanedTerm(value).contains(" ") { return .phrase }
        return .other
    }

    static func looksLikeEnglishInfinitive(_ value: String) -> Bool {
        let lower = cleanedTerm(value).lowercased()
        guard lower.hasPrefix("to ") else { return false }
        let nonVerbPrefixes = [
            "to a ", "to an ", "to the ", "to one's ", "to one’s ",
            "to sb.", "to sth.", "to somebody", "to someone", "to something"
        ]
        return !nonVerbPrefixes.contains(where: lower.hasPrefix)
    }

    static func hasGermanVerbMarker(_ value: String) -> Bool {
        let lower = value.lowercased()
        return ["{vi}", "{vt}", "{vr}", "{verb}", "{v.i.}", "{v.t.}"].contains(where: lower.contains)
            || value.contains("|")
    }

    private static func wordKind(for declaration: String) -> WordKind? {
        for rawToken in declaration.lowercased().split(whereSeparator: { $0.isWhitespace }) {
            let qualifierFree = rawToken.split(separator: ":").last.map(String.init) ?? String(rawToken)
            let token = qualifierFree.trimmingCharacters(in: .punctuationCharacters)
            switch token {
            case "noun": return .noun
            case "verb": return .verb
            case "adj", "adjj": return .adjective
            case "adv": return .adverb
            case "pron", "rel-pron": return .pronoun
            case "prep": return .preposition
            case "conj": return .conjunction
            case "pres-p": return .presentParticiple
            case "past-p": return .pastParticiple
            case "prefix": return .prefix
            case "suffix": return .suffix
            default:
                if token.hasPrefix("adj") { return .adjective }
                if token.hasPrefix("pres-p") { return .presentParticiple }
                if token.hasPrefix("past-p") { return .pastParticiple }
            }
        }
        return nil
    }

    private static func extractUsage(from value: String) -> String? {
        let range = NSRange(value.startIndex..., in: value)
        guard let match = squareExpression.firstMatch(in: value, range: range),
              let swiftRange = Range(match.range, in: value) else { return nil }
        let text = value[swiftRange]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return text.isEmpty ? nil : text
    }

    private static func replacingMatches(_ expression: NSRegularExpression, in text: String, with replacement: String) -> String {
        expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }
}
