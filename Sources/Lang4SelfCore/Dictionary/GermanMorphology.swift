import Foundation

public enum GermanMorphology {
    private struct VerbForms {
        let present: String
        let past: String
        let participle: String
        let auxiliary: String
    }

    private static let irregularVerbs: [String: VerbForms] = [
        "sein": .init(present: "ich bin · du bist · er/sie ist · wir sind · ihr seid · sie sind", past: "war", participle: "gewesen", auxiliary: "sein"),
        "haben": .init(present: "ich habe · du hast · er/sie hat · wir haben · ihr habt · sie haben", past: "hatte", participle: "gehabt", auxiliary: "haben"),
        "werden": .init(present: "ich werde · du wirst · er/sie wird · wir werden · ihr werdet · sie werden", past: "wurde", participle: "geworden", auxiliary: "sein"),
        "gehen": .init(present: "ich gehe · du gehst · er/sie geht · wir gehen · ihr geht · sie gehen", past: "ging", participle: "gegangen", auxiliary: "sein"),
        "kommen": .init(present: "ich komme · du kommst · er/sie kommt · wir kommen · ihr kommt · sie kommen", past: "kam", participle: "gekommen", auxiliary: "sein"),
        "fahren": .init(present: "ich fahre · du fährst · er/sie fährt · wir fahren · ihr fahrt · sie fahren", past: "fuhr", participle: "gefahren", auxiliary: "sein/haben"),
        "nehmen": .init(present: "ich nehme · du nimmst · er/sie nimmt · wir nehmen · ihr nehmt · sie nehmen", past: "nahm", participle: "genommen", auxiliary: "haben"),
        "geben": .init(present: "ich gebe · du gibst · er/sie gibt · wir geben · ihr gebt · sie geben", past: "gab", participle: "gegeben", auxiliary: "haben"),
        "sprechen": .init(present: "ich spreche · du sprichst · er/sie spricht · wir sprechen · ihr sprecht · sie sprechen", past: "sprach", participle: "gesprochen", auxiliary: "haben"),
        "sehen": .init(present: "ich sehe · du siehst · er/sie sieht · wir sehen · ihr seht · sie sehen", past: "sah", participle: "gesehen", auxiliary: "haben"),
        "lesen": .init(present: "ich lese · du liest · er/sie liest · wir lesen · ihr lest · sie lesen", past: "las", participle: "gelesen", auxiliary: "haben"),
        "essen": .init(present: "ich esse · du isst · er/sie isst · wir essen · ihr esst · sie essen", past: "aß", participle: "gegessen", auxiliary: "haben"),
        "schlafen": .init(present: "ich schlafe · du schläfst · er/sie schläft · wir schlafen · ihr schlaft · sie schlafen", past: "schlief", participle: "geschlafen", auxiliary: "haben"),
        "schreiben": .init(present: "ich schreibe · du schreibst · er/sie schreibt · wir schreiben · ihr schreibt · sie schreiben", past: "schrieb", participle: "geschrieben", auxiliary: "haben"),
        "finden": .init(present: "ich finde · du findest · er/sie findet · wir finden · ihr findet · sie finden", past: "fand", participle: "gefunden", auxiliary: "haben"),
        "bringen": .init(present: "ich bringe · du bringst · er/sie bringt · wir bringen · ihr bringt · sie bringen", past: "brachte", participle: "gebracht", auxiliary: "haben"),
        "denken": .init(present: "ich denke · du denkst · er/sie denkt · wir denken · ihr denkt · sie denken", past: "dachte", participle: "gedacht", auxiliary: "haben"),
        "wissen": .init(present: "ich weiß · du weißt · er/sie weiß · wir wissen · ihr wisst · sie wissen", past: "wusste", participle: "gewusst", auxiliary: "haben"),
        "tun": .init(present: "ich tue · du tust · er/sie tut · wir tun · ihr tut · sie tun", past: "tat", participle: "getan", auxiliary: "haben"),
        "stehen": .init(present: "ich stehe · du stehst · er/sie steht · wir stehen · ihr steht · sie stehen", past: "stand", participle: "gestanden", auxiliary: "haben")
    ]

    private static let adjectiveForms: [String: (String, String)] = [
        "gut": ("besser", "am besten"),
        "viel": ("mehr", "am meisten"),
        "gern": ("lieber", "am liebsten"),
        "hoch": ("höher", "am höchsten"),
        "nah": ("näher", "am nächsten"),
        "groß": ("größer", "am größten"),
        "alt": ("älter", "am ältesten"),
        "jung": ("jünger", "am jüngsten")
    ]

    private static let separablePrefixes = [
        "auseinander", "zusammen", "zurück", "weiter", "wieder", "vorbei", "herunter", "hinunter",
        "herauf", "hinauf", "kennen", "statt", "teil", "preis", "fest", "frei", "heim", "hoch",
        "ab", "an", "auf", "aus", "bei", "dar", "ein", "empor", "entgegen", "fort", "her", "hin",
        "los", "mit", "nach", "nieder", "vor", "weg", "zu"
    ]

    public static func info(for entry: DictionaryEntry) -> WordInfo {
        let term = canonicalGerman(entry.german)
        switch entry.kind {
        case .noun:
            var rows: [WordInfo.Row] = []
            if entry.gender != .unknown { rows.append(.init("Article / gender", entry.gender.article)) }
            rows.append(.init("Singular", term))
            if entry.gender == .plural { rows.append(.init("Number", "plural form")) }
            if let usage = entry.usage { rows.append(.init("Usage", usage)) }
            return .init(headline: term, kind: .noun, gender: entry.gender, separablePrefix: nil, stem: term, rows: rows, isEstimated: false)

        case .verb:
            return verbInfo(for: term, raw: entry.rawGerman, gender: entry.gender)

        case .adjective:
            let base = term.lowercased()
            let known = adjectiveForms[base]
            let comparative = known?.0 ?? base + "er"
            let superlative = known?.1 ?? "am " + base + (needsExtraE(base) ? "esten" : "sten")
            return .init(
                headline: term,
                kind: .adjective,
                gender: .unknown,
                separablePrefix: nil,
                stem: term,
                rows: [.init("Positive", base), .init("Comparative", comparative), .init("Superlative", superlative)],
                isEstimated: known == nil
            )

        default:
            var rows = [WordInfo.Row("German", term), .init("Translations", entry.translations)]
            if let usage = entry.usage { rows.append(.init("Usage", usage)) }
            return .init(headline: term, kind: entry.kind, gender: entry.gender, separablePrefix: nil, stem: term, rows: rows, isEstimated: false)
        }
    }

    public static func separableParts(for entry: DictionaryEntry) -> (prefix: String, stem: String)? {
        guard entry.kind == .verb else { return nil }
        let rawTerm = canonicalGerman(entry.rawGerman)
        if let divider = rawTerm.firstIndex(of: "|") {
            let prefix = String(rawTerm[..<divider])
            let stem = String(rawTerm[rawTerm.index(after: divider)...])
            if !prefix.isEmpty, !stem.isEmpty { return (prefix, stem) }
        }
        let term = canonicalGerman(entry.german).lowercased().replacingOccurrences(of: "|", with: "")
        for prefix in separablePrefixes where term.hasPrefix(prefix) && term.dropFirst(prefix.count).count >= 3 {
            return (prefix, String(term.dropFirst(prefix.count)))
        }
        return nil
    }

    private static func verbInfo(for termValue: String, raw: String, gender: Gender) -> WordInfo {
        let infinitive = termValue.lowercased().replacingOccurrences(of: "|", with: "")
        let synthetic = DictionaryEntry(german: termValue, english: "", rawGerman: raw, kind: .verb, gender: gender)
        let parts = separableParts(for: synthetic)
        let root = parts.map { String(infinitive.dropFirst($0.prefix.count)) } ?? infinitive
        let known = irregularVerbs[infinitive] ?? irregularVerbs[root]
        let forms = known ?? regularForms(infinitive: infinitive, parts: parts)
        let present = known.flatMap { parts == nil ? $0.present : compoundPresent(prefix: parts!.prefix, rootForms: $0.present) } ?? forms.present
        let past = known.map { parts == nil ? $0.past : $0.past + " " + parts!.prefix } ?? forms.past
        let participle = known.map { parts == nil ? $0.participle : parts!.prefix + $0.participle } ?? forms.participle
        let auxiliary = known?.auxiliary ?? forms.auxiliary

        return .init(
            headline: infinitive,
            kind: .verb,
            gender: .unknown,
            separablePrefix: parts?.prefix,
            stem: parts?.stem ?? infinitive,
            rows: [
                .init("Infinitive", infinitive),
                .init("Present", present),
                .init("Simple past", past),
                .init("Perfect", auxiliary + " " + participle),
                .init("Future I", "werden + " + infinitive)
            ],
            isEstimated: known == nil
        )
    }

    private static func regularForms(infinitive: String, parts: (prefix: String, stem: String)?) -> VerbForms {
        let root = parts?.stem ?? infinitive
        let stem: String
        if root.hasSuffix("en") { stem = String(root.dropLast(2)) }
        else if root.hasSuffix("n") { stem = String(root.dropLast()) }
        else { stem = root }
        let connectingE = stem.hasSuffix("d") || stem.hasSuffix("t")
        let du = stem + (connectingE ? "est" : "st")
        let third = stem + (connectingE ? "et" : "t")
        let presentCore = "ich \(stem)e · du \(du) · er/sie \(third) · wir \(root) · ihr \(third) · sie \(root)"
        let present = parts.map { compoundPresent(prefix: $0.prefix, rootForms: presentCore) } ?? presentCore
        let pastCore = stem + (connectingE ? "ete" : "te")
        let past = parts.map { pastCore + " " + $0.prefix } ?? pastCore
        let inseparable = ["be", "emp", "ent", "er", "ge", "miss", "ver", "zer"].contains(where: infinitive.hasPrefix)
        let participle: String
        if let parts {
            participle = parts.prefix + "ge" + stem + (connectingE ? "et" : "t")
        } else if infinitive.hasSuffix("ieren") || inseparable {
            participle = stem + (connectingE ? "et" : "t")
        } else {
            participle = "ge" + stem + (connectingE ? "et" : "t")
        }
        return .init(present: present, past: past, participle: participle, auxiliary: "haben")
    }

    private static func compoundPresent(prefix: String, rootForms: String) -> String {
        rootForms
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespaces) + " " + prefix }
            .joined(separator: " · ")
    }

    private static func canonicalGerman(_ value: String) -> String {
        var term = DictCCParser.cleanedTerm(value)
        for marker in ["jdn. ", "jdm. ", "etw. ", "sich "] where term.lowercased().hasPrefix(marker) {
            term = String(term.dropFirst(marker.count))
        }
        return term.trimmingCharacters(in: .whitespaces)
    }

    private static func needsExtraE(_ adjective: String) -> Bool {
        ["s", "ß", "x", "z", "tz", "t", "d"].contains(where: adjective.hasSuffix)
    }
}
