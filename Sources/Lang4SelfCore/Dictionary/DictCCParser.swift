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
            translationLanguage: translationLanguage
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
        let declaration = declaredKind.lowercased()
        if declaration.contains("noun") { return .noun }
        if declaration.contains("verb") { return .verb }
        if declaration.contains("adj") || declaration.contains("past-p") || declaration.contains("pres-p") { return .adjective }
        if declaration.contains("adv") { return .adverb }
        let lower = value.lowercased()
        let lowerEnglish = english.lowercased()
        if ["{vi}", "{vt}", "{vr}", "{verb}", "{v.i.}", "{v.t.}"].contains(where: lower.contains)
            || value.contains("|")
            || lowerEnglish.hasPrefix("to ") { return .verb }
        if lower.contains("{adj}") || lower.contains("{adj.}") { return .adjective }
        if lower.contains("{adv}") || lower.contains("{adv.}") { return .adverb }
        if cleanedTerm(value).contains(" ") { return .phrase }
        return .other
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
