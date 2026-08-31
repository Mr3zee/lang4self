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
        "rufen": .init(present: "ich rufe · du rufst · er/sie ruft · wir rufen · ihr ruft · sie rufen", past: "rief", participle: "gerufen", auxiliary: "haben"),
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
        "stehen": .init(present: "ich stehe · du stehst · er/sie steht · wir stehen · ihr steht · sie stehen", past: "stand", participle: "gestanden", auxiliary: "haben"),
        "fallen": .init(present: "ich falle · du fällst · er/sie fällt · wir fallen · ihr fallt · sie fallen", past: "fiel", participle: "gefallen", auxiliary: "sein"),
        "laufen": .init(present: "ich laufe · du läufst · er/sie läuft · wir laufen · ihr lauft · sie laufen", past: "lief", participle: "gelaufen", auxiliary: "sein"),
        "tragen": .init(present: "ich trage · du trägst · er/sie trägt · wir tragen · ihr tragt · sie tragen", past: "trug", participle: "getragen", auxiliary: "haben")
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

    /// Closed-class verb particles, conventional directional compounds, and
    /// lexicalized particles commonly written as the first part of a German
    /// separable verb. German also productively makes separable verbs from
    /// nouns and adjectives, so lookup must not use this finite catalog as a
    /// gate; `lookupTerms(for:)` also tries the dictionary-backed joined form.
    static let separablePrefixCatalog: Set<String> = [
        "ab", "an", "anheim", "auf", "aus", "auseinander",
        "bei", "beieinander", "beisammen", "beiseite",
        "da", "dabei", "dafür", "dagegen", "daher", "dahin", "daneben", "dar", "daran", "darauf",
        "daraus", "darein", "davon", "dazu", "dazwischen", "dran", "drauf", "drauflos",
        "durch", "durcheinander",
        "ein", "einher", "empor", "entgegen", "entlang", "entzwei",
        "fehl", "fern", "fest", "fort", "frei",
        "gegen", "gegenüber", "gleich",
        "heim", "her", "herab", "heran", "herauf", "heraus", "herbei", "herein", "herüber",
        "herum", "herunter", "hervor", "herzu",
        "hin", "hinab", "hinan", "hinauf", "hinaus", "hindurch", "hinein", "hintan",
        "hinter", "hinterher", "hinüber", "hinunter", "hinweg", "hinzu", "hoch",
        "inne", "kennen", "los", "mit", "nach", "nebenher", "nieder", "preis", "quer",
        "ran", "raus", "rein", "rüber", "rum", "runter", "statt", "teil",
        "über", "überein", "um", "umher", "unter",
        "vor", "voran", "voraus", "vorbei", "vorher", "vorüber", "vorweg",
        "weg", "weiter", "wider", "wieder",
        "zu", "zurecht", "zurück", "zusammen", "zuvor", "zwischen"
    ]

    // Inferring separability from an unmarked spelling is inherently narrower:
    // particles such as "da", "durch", "um", and "über" are ambiguous and
    // would otherwise misclassify ordinary verbs such as "danken". Explicit
    // dict.cc `|` markers are handled before this fallback.
    private static let inferredSeparablePrefixCatalog: Set<String> = [
        "auseinander", "zusammen", "zurück", "weiter", "wieder", "vorbei", "herunter", "hinunter",
        "herauf", "hinauf", "kennen", "statt", "teil", "preis", "fest", "frei", "heim", "hoch",
        "ab", "an", "auf", "aus", "bei", "dar", "ein", "empor", "entgegen", "fort", "her", "hin",
        "los", "mit", "nach", "nieder", "vor", "weg", "zu"
    ]

    private static let separablePrefixes = inferredSeparablePrefixCatalog.sorted {
        $0.count == $1.count ? $0 < $1 : $0.count > $1.count
    }
    private static let normalizedSeparablePrefixes = Set(
        separablePrefixCatalog.map(DictCCParser.normalized)
    )
    private static let normalizedInferredSeparablePrefixesByLength: [String] = {
        let prefixes = inferredSeparablePrefixCatalog.map { DictCCParser.normalized($0) }
        return prefixes.sorted {
            $0.count == $1.count ? $0 < $1 : $0.count > $1.count
        }
    }()

    public static func info(for entry: DictionaryEntry) -> WordInfo {
        let term = canonicalGerman(entry.german)
        switch entry.kind {
        case .noun:
            var rows: [WordInfo.Row] = []
            let plurals = pluralForms(for: entry)
            if entry.gender != .unknown { rows.append(.init("Article / gender", entry.gender.article)) }
            if entry.gender == .plural {
                rows.append(.init("Plural", term))
            } else {
                rows.append(.init("Singular", term))
                if !plurals.isEmpty { rows.append(.init("Plural", plurals.joined(separator: " · "))) }
            }
            if let usage = entry.usage, !plurals.contains(usage) {
                rows.append(.init("Usage", usage))
            }
            return .init(headline: term, kind: .noun, gender: entry.gender, separablePrefix: nil, stem: term, rows: rows, isEstimated: false)

        case .verb:
            return verbInfo(for: term, raw: entry.rawGerman, gender: entry.gender, importedForms: entry.forms)

        case .adjective:
            let base = term.lowercased()
            let known = adjectiveForms[base]
            let importedComparative = preferredDegreeForm("comparative", in: entry.forms)
            let importedSuperlative = preferredDegreeForm("superlative", in: entry.forms)
            let comparative = importedComparative ?? known?.0 ?? base + "er"
            let superlative = importedSuperlative.map { "am " + $0 }
                ?? known?.1
                ?? "am " + base + (needsExtraE(base) ? "esten" : "sten")
            return .init(
                headline: term,
                kind: .adjective,
                gender: .unknown,
                separablePrefix: nil,
                stem: term,
                rows: [.init("Positive", base), .init("Comparative", comparative), .init("Superlative", superlative)],
                isEstimated: (importedComparative == nil || importedSuperlative == nil) && known == nil
            )

        default:
            let translations = entry.meanings.map(\.translation).joined(separator: " · ")
            var rows = [WordInfo.Row("German", term), .init("Translations", translations)]
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
        guard let prefix = separablePrefix(in: term) else { return nil }
        return (prefix, String(term.dropFirst(prefix.count)))
    }

    public static func separablePrefix(in infinitive: String) -> String? {
        let term = canonicalGerman(infinitive).lowercased().replacingOccurrences(of: "|", with: "")
        return separablePrefixes.first {
            term.hasPrefix($0) && term.dropFirst($0.count).count >= 3
        }
    }

    /// Terms worth trying when a German lookup contains an article or an inflected word.
    /// The literal term stays first; callers can use entry metadata to prefer a base form.
    public static func lookupTerms(for value: String) -> [String] {
        let normalized = DictCCParser.normalized(value)
        guard !normalized.isEmpty else { return [] }

        var result = [normalized]
        let words = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let lexicalWords = Array(words.drop(while: { leadingDeterminers.contains($0) }))
        let lexicalTerm = lexicalWords.joined(separator: " ")
        if !lexicalTerm.isEmpty { appendUnique(lexicalTerm, to: &result) }

        // Speech recognition often inserts spaces inside a word ("zu machen"
        // for "zumachen"). Trying the collapsed spelling is safe because the
        // dictionary still decides whether that spelling exists. It also covers
        // productive noun/adjective particles that no finite prefix list can.
        if (2...4).contains(lexicalWords.count) {
            appendUnique(lexicalWords.joined(), to: &result)
        }

        if lexicalWords.count == 1, let word = lexicalWords.first {
            for candidate in baseFormCandidates(for: word) {
                appendUnique(candidate, to: &result)
            }
        } else if lexicalWords.count == 2,
                  let inflected = lexicalWords.first,
                  let prefix = lexicalWords.last,
                  normalizedSeparablePrefixes.contains(prefix) {
            for infinitive in verbBaseCandidates(for: inflected) {
                appendUnique(prefix + infinitive, to: &result)
            }
        }
        return result
    }

    public static func isDeterminer(_ value: String) -> Bool {
        leadingDeterminers.contains(DictCCParser.normalized(value))
    }

    /// Plural forms supplied by dict.cc in square brackets, excluding usage notes.
    public static func pluralForms(for entry: DictionaryEntry) -> [String] {
        guard entry.kind == .noun, entry.gender != .plural else { return [] }
        let singular = canonicalGerman(entry.german)
        let singularKey = DictCCParser.normalized(singular)
        guard !singularKey.isEmpty else { return [] }

        return (entry.pluralForms + squareAnnotations(in: entry.rawGerman)
            .flatMap(splitPluralAlternatives)
            .filter { isPluralForm($0, of: singular) })
            .reduce(into: [String]()) { forms, form in
                if !forms.contains(form) { forms.append(form) }
            }
    }

    public static func isPluralForm(_ candidate: String, of singular: String) -> Bool {
        let candidateKey = DictCCParser.normalized(candidate)
        let singularKey = DictCCParser.normalized(singular)
        guard !candidateKey.isEmpty, !singularKey.isEmpty,
              comparableSpelling(candidate) != comparableSpelling(singular) else { return false }
        return candidateKey == singularKey || nounBaseCandidates(for: candidateKey).contains(singularKey)
    }

    private static func verbInfo(
        for termValue: String,
        raw: String,
        gender: Gender,
        importedForms: [DictionaryForm]
    ) -> WordInfo {
        let infinitive = termValue.lowercased().replacingOccurrences(of: "|", with: "")
        let synthetic = DictionaryEntry(german: termValue, english: "", rawGerman: raw, kind: .verb, gender: gender)
        let parts = separableParts(for: synthetic)
        let root = parts.map { String(infinitive.dropFirst($0.prefix.count)) } ?? infinitive
        let known = irregularVerbs[infinitive] ?? irregularVerbs[root]
        let generated = regularForms(infinitive: infinitive, parts: parts)
        let fallback = known ?? generated
        let fallbackPresent = known.flatMap {
            parts == nil ? $0.present : compoundPresent(prefix: parts!.prefix, rootForms: $0.present)
        } ?? fallback.present
        let fallbackPast = known.map {
            parts == nil ? $0.past : $0.past + " " + parts!.prefix
        } ?? fallback.past
        let fallbackParticiple = known.map {
            parts == nil ? $0.participle : parts!.prefix + $0.participle
        } ?? fallback.participle

        let importedPresent = importedPresentParadigm(
            in: importedForms,
            infinitive: infinitive,
            separablePrefix: parts?.prefix
        )
        let importedPast = importedSimplePast(in: importedForms).map {
            separatedFiniteForm($0, prefix: parts?.prefix)
        }
        let importedParticiple = matchingForm(
            in: importedForms,
            requiring: ["participle", "past"]
        )
        let importedAuxiliaries = importedForms
            .filter { $0.tags.contains("auxiliary") }
            .map(\.form)
            .uniqued()
            .sorted()

        let present = importedPresent ?? fallbackPresent
        let past = importedPast ?? fallbackPast
        let participle = importedParticiple ?? fallbackParticiple
        let auxiliary = importedAuxiliaries.isEmpty
            ? fallback.auxiliary
            : importedAuxiliaries.joined(separator: "/")
        let usedGeneratedFallback = known == nil && (
            importedPresent == nil
                || importedPast == nil
                || importedParticiple == nil
                || importedAuxiliaries.isEmpty
        )

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
            isEstimated: usedGeneratedFallback
        )
    }

    private static func importedPresentParadigm(
        in forms: [DictionaryForm],
        infinitive: String,
        separablePrefix: String?
    ) -> String? {
        let ich = matchingForm(in: forms, requiring: ["present", "first-person", "singular"])
        let du = matchingForm(in: forms, requiring: ["present", "second-person", "singular"])
        let third = matchingForm(in: forms, requiring: ["present", "third-person", "singular"])
        guard let ich, let du, let third else { return nil }

        let firstPlural = matchingForm(in: forms, requiring: ["present", "first-person", "plural"])
        let secondPlural = matchingForm(in: forms, requiring: ["present", "second-person", "plural"])
        let thirdPlural = matchingForm(in: forms, requiring: ["present", "third-person", "plural"])
        let values = [
            ("ich", ich),
            ("du", du),
            ("er/sie", third),
            ("wir", firstPlural ?? infinitive),
            ("ihr", secondPlural ?? third),
            ("sie", thirdPlural ?? firstPlural ?? infinitive)
        ]
        return values.map { pronoun, form in
            "\(pronoun) \(separatedFiniteForm(form, prefix: separablePrefix))"
        }.joined(separator: " · ")
    }

    private static func importedSimplePast(in forms: [DictionaryForm]) -> String? {
        matchingForm(in: forms, requiring: ["past"], exact: true)
            ?? matchingForm(in: forms, requiring: ["preterite", "first-person", "singular"])
    }

    private static func matchingForm(
        in forms: [DictionaryForm],
        requiring tags: Set<String>,
        exact: Bool = false
    ) -> String? {
        forms.first {
            exact ? $0.tags == tags : $0.tags.isSuperset(of: tags)
        }?.form
    }

    private static func separatedFiniteForm(_ form: String, prefix: String?) -> String {
        guard let prefix, form.lowercased().hasPrefix(prefix.lowercased()), form.count > prefix.count else {
            return form
        }
        return String(form.dropFirst(prefix.count)) + " " + prefix
    }

    private static func preferredDegreeForm(_ tag: String, in forms: [DictionaryForm]) -> String? {
        let candidates = forms.filter { $0.tags.contains(tag) }.map(\.form).uniqued()
        if tag == "superlative",
           let declined = candidates.first(where: { $0.lowercased().hasSuffix("sten") }) {
            return declined
        }
        return candidates.first
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

    static func inflectionLemma(for value: String) -> String {
        canonicalGerman(value).replacingOccurrences(of: "|", with: "")
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

    private static let leadingDeterminers: Set<String> = [
        "der", "die", "das", "den", "dem", "des",
        "ein", "eine", "einen", "einem", "einer", "eines"
    ]

    private static func baseFormCandidates(for word: String) -> [String] {
        nounBaseCandidates(for: word) + verbBaseCandidates(for: word)
    }

    private static func nounBaseCandidates(for word: String) -> [String] {
        var result: [String] = []
        let suffixes = ["ern", "en", "er", "es", "e", "n", "s"]
        for suffix in suffixes where word.hasSuffix(suffix) && word.count > suffix.count + 2 {
            appendUnique(String(word.dropLast(suffix.count)), to: &result)
        }
        if word.hasSuffix("n"), word.count > 4 {
            appendUnique(String(word.dropLast()), to: &result)
        }
        return result
    }

    private static func verbBaseCandidates(for word: String, includeSeparableForms: Bool = true) -> [String] {
        var result: [String] = []
        if let irregular = irregularInfinitives[word] {
            for infinitive in irregular { appendUnique(infinitive, to: &result) }
        }

        for suffix in ["test", "tet", "ten", "te", "est", "st", "et", "t", "e"]
        where word.hasSuffix(suffix) && word.count > suffix.count + 2 {
            let stem = String(word.dropLast(suffix.count))
            appendUnique(infinitive(from: stem), to: &result)
        }

        if word.hasPrefix("ge"), word.hasSuffix("t"), word.count > 5 {
            let stem = String(word.dropFirst(2).dropLast())
            appendUnique(infinitive(from: stem), to: &result)
        }
        if includeSeparableForms {
            for prefix in normalizedInferredSeparablePrefixesByLength where word.hasPrefix(prefix) {
                let separatedForm = String(word.dropFirst(prefix.count))
                guard separatedForm.count > 3 else { continue }
                for base in verbBaseCandidates(for: separatedForm, includeSeparableForms: false) {
                    appendUnique(prefix + base, to: &result)
                }
            }
        }
        return result
    }

    private static func infinitive(from stem: String) -> String {
        stem.hasSuffix("e") ? stem + "n" : stem + "en"
    }

    private static let irregularInfinitives: [String: [String]] = {
        var result: [String: [String]] = [:]
        for (infinitive, forms) in irregularVerbs {
            let values = forms.present
                .split(separator: "·")
                .compactMap { $0.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) }
                + [forms.past, forms.participle]
            for value in values {
                let key = DictCCParser.normalized(value)
                if !result[key, default: []].contains(infinitive) {
                    result[key, default: []].append(infinitive)
                }
            }
        }
        return result
    }()

    private static func squareAnnotations(in value: String) -> [String] {
        let expression = try! NSRegularExpression(pattern: #"\[([^]]+)\]"#)
        let range = NSRange(value.startIndex..., in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let matchRange = Range(match.range(at: 1), in: value) else { return nil }
            return String(value[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func splitPluralAlternatives(_ value: String) -> [String] {
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for marker in ["Plural:", "Pl.:", "Pl:"] where value.lowercased().hasPrefix(marker.lowercased()) {
            value = String(value.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        guard !value.contains(":"), !value.isEmpty else { return [] }
        return value
            .split(whereSeparator: { $0 == "/" || $0 == ";" || $0 == "," })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func comparableSpelling(_ value: String) -> String {
        DictCCParser.cleanedTerm(value)
            .precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "de_DE"))
    }

    private static func appendUnique(_ value: String, to values: inout [String]) {
        if !value.isEmpty, !values.contains(value) { values.append(value) }
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
