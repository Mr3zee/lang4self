import CoreFoundation
import Foundation
import SwiftUI
import Lang4SelfCore

struct SpeechAuroraMotion {
    static func phase(at date: Date, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : date.timeIntervalSinceReferenceDate
    }

    static func offset(
        at phase: TimeInterval,
        period: TimeInterval,
        xAmplitude: CGFloat,
        yAmplitude: CGFloat,
        initialAngle: Double
    ) -> CGSize {
        let angle = loopAngle(at: phase, period: period, initialAngle: initialAngle)
        return CGSize(
            width: cos(angle) * xAmplitude,
            height: sin(angle) * yAmplitude
        )
    }

    static func oscillation(
        at phase: TimeInterval,
        period: TimeInterval,
        initialAngle: Double
    ) -> Double {
        sin(loopAngle(at: phase, period: period, initialAngle: initialAngle))
    }

    private static func loopAngle(
        at phase: TimeInterval,
        period: TimeInterval,
        initialAngle: Double
    ) -> Double {
        let progress = phase.truncatingRemainder(dividingBy: period) / period
        return progress * 2 * Double.pi + initialAngle
    }
}

struct AuroraBackground: View {
    enum Style {
        case speech
        case review
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let style: Style

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { timeline in
            GeometryReader { geometry in
                let phase = SpeechAuroraMotion.phase(at: timeline.date, reduceMotion: reduceMotion)
                let size = geometry.size

                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    Color.black.opacity(colorScheme == .dark ? 0.18 : 0.035)

                    auroraBlob(
                        color: Gender.masculine.color,
                        size: CGSize(width: max(size.width * 0.40, 270), height: max(size.height * 0.90, 240)),
                        position: CGPoint(x: size.width * 0.03, y: size.height * 0.20),
                        phase: phase,
                        period: 19,
                        amplitude: amplitude(for: size, x: 0.10, y: 0.08),
                        initialAngle: 0.3,
                        rotation: -16
                    )

                    auroraBlob(
                        color: Gender.feminine.color,
                        size: CGSize(width: max(size.width * 0.38, 250), height: max(size.height * 0.82, 220)),
                        position: CGPoint(x: size.width * 0.97, y: size.height * 0.24),
                        phase: phase,
                        period: 23,
                        amplitude: amplitude(for: size, x: 0.09, y: 0.11),
                        initialAngle: 2.1,
                        rotation: 19
                    )

                    auroraBlob(
                        color: Gender.plural.color,
                        size: CGSize(width: max(size.width * 0.36, 235), height: max(size.height * 0.76, 200)),
                        position: CGPoint(x: size.width * 0.20, y: size.height * 0.94),
                        phase: phase,
                        period: 27,
                        amplitude: amplitude(for: size, x: 0.12, y: 0.07),
                        initialAngle: 3.7,
                        rotation: 11
                    )

                    auroraBlob(
                        color: Gender.neuter.color,
                        size: CGSize(width: max(size.width * 0.34, 225), height: max(size.height * 0.70, 185)),
                        position: CGPoint(x: size.width * 0.80, y: size.height * 0.96),
                        phase: phase,
                        period: 31,
                        amplitude: amplitude(for: size, x: 0.10, y: 0.09),
                        initialAngle: 5.2,
                        rotation: -12
                    )

                    RadialGradient(
                        colors: [.clear, .black.opacity(colorScheme == .dark ? 0.11 : 0.025)],
                        center: .center,
                        startRadius: min(size.width, size.height) * 0.30,
                        endRadius: max(size.width, size.height) * 0.70
                    )

                    LinearGradient(
                        colors: [.white.opacity(colorScheme == .dark ? 0.02 : 0.08), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                }
                .clipped()
            }
        }
    }

    private func amplitude(for size: CGSize, x: CGFloat, y: CGFloat) -> CGSize {
        let multiplier: CGFloat = style == .speech ? 1 : 1.15
        return CGSize(
            width: max(size.width * x * multiplier, 28),
            height: max(size.height * y * multiplier, 18)
        )
    }

    private func auroraBlob(
        color: Color,
        size: CGSize,
        position: CGPoint,
        phase: TimeInterval,
        period: TimeInterval,
        amplitude: CGSize,
        initialAngle: Double,
        rotation: Double
    ) -> some View {
        let offset = SpeechAuroraMotion.offset(
            at: phase,
            period: period,
            xAmplitude: amplitude.width,
            yAmplitude: amplitude.height,
            initialAngle: initialAngle
        )
        let wave = SpeechAuroraMotion.oscillation(
            at: phase,
            period: period * 0.72,
            initialAngle: initialAngle + 0.8
        )
        let gradientCenter = UnitPoint(
            x: 0.5 + 0.16 * cos(wave * .pi),
            y: 0.5 + 0.13 * sin(wave * .pi)
        )
        let baseIntensity = colorScheme == .dark ? 0.15 : 0.095
        let intensity = baseIntensity * (style == .speech ? 1 : 0.82)

        return ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(intensity), color.opacity(intensity * 0.30), .clear],
                        center: gradientCenter,
                        startRadius: 0,
                        endRadius: max(size.width, size.height) * 0.50
                    )
                )

            Ellipse()
                .fill(color.opacity(intensity * 0.34))
                .frame(width: size.width * 0.46, height: size.height * 0.72)
                .offset(x: size.width * 0.20 * wave, y: size.height * -0.08 * wave)
        }
        .frame(width: size.width, height: size.height)
        .compositingGroup()
        .blur(radius: 34)
        .rotationEffect(.degrees(rotation + wave * 12))
        .scaleEffect(1 + wave * 0.07)
        .position(x: position.x + offset.width, y: position.y + offset.height)
    }
}

enum GermanTextPresentation {
    static let softHyphen = "\u{00AD}"

    static func hyphenated(_ text: String) -> String {
        let plainText = text.replacingOccurrences(of: softHyphen, with: "")
        guard plainText.utf16.count > 3 else { return plainText }

        let locale = CFLocaleCreate(
            kCFAllocatorDefault,
            CFLocaleIdentifier(rawValue: "de_DE" as CFString)
        )
        guard CFStringIsHyphenationAvailableForLocale(locale) else { return plainText }

        let source = plainText as CFString
        var hyphenationLocations: [Int] = []
        plainText.enumerateSubstrings(
            in: plainText.startIndex..<plainText.endIndex,
            options: .byWords
        ) { _, wordRange, _, _ in
            let range = NSRange(wordRange, in: plainText)
            let limit = CFRange(location: range.location, length: range.length)
            var searchLocation = NSMaxRange(range)

            while searchLocation > range.location {
                let location = CFStringGetHyphenationLocationBeforeIndex(
                    source,
                    searchLocation,
                    limit,
                    0,
                    locale,
                    nil
                )
                guard location != kCFNotFound, location > range.location else { break }
                hyphenationLocations.append(location)
                searchLocation = location
            }
        }

        let result = NSMutableString(string: plainText)
        for location in hyphenationLocations.sorted(by: >) {
            result.insert(softHyphen, at: location)
        }
        return result as String
    }
}

extension Gender {
    var color: Color {
        switch self {
        case .masculine: Color(red: 0.47, green: 0.65, blue: 0.82)
        case .feminine: Color(red: 0.85, green: 0.56, blue: 0.64)
        case .neuter: Color(red: 0.82, green: 0.73, blue: 0.43)
        case .plural: Color(red: 0.49, green: 0.71, blue: 0.54)
        case .unknown: .secondary
        }
    }
}

struct GenderBadge: View {
    let gender: Gender

    var body: some View {
        if gender != .unknown {
            Text(gender.article)
                .font(.caption.weight(.bold))
                .foregroundStyle(gender.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(gender.color.opacity(0.12), in: Capsule())
                .fixedSize()
                .accessibilityLabel("Gender: \(gender.article)")
        }
    }
}

struct TranslationLanguageBadge: View {
    let language: TranslationLanguage

    var body: some View {
        Text(language.shortLabel)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .fixedSize()
            .accessibilityLabel(language.label)
    }
}

enum TranslationPresentation {
    static func items(from value: String) -> [String] {
        parts(from: value).reduce(into: []) { result, part in
            if !result.contains(part) { result.append(part) }
        }
    }

    static func expandedMeanings(_ meanings: [DictionaryMeaning]) -> [DictionaryMeaning] {
        meanings.flatMap(expandedMeaning)
    }

    static func summary(
        of meanings: [DictionaryMeaning],
        fallback: String = ""
    ) -> String {
        let translations = expandedMeanings(meanings).map(\.translation)
        let values = translations.isEmpty ? items(from: fallback) : translations
        return values.reduce(into: []) { result, value in
            if !result.contains(value) { result.append(value) }
        }
        .joined(separator: ", ")
    }

    private static func expandedMeaning(_ meaning: DictionaryMeaning) -> [DictionaryMeaning] {
        let translations = parts(from: meaning.translation)
        guard translations.count > 1 else { return [meaning] }

        let rawTranslations = parts(from: meaning.rawTranslation)
        return translations.enumerated().reduce(into: []) { result, item in
            let (index, translation) = item
            guard !result.contains(where: { $0.translation == translation }) else { return }
            result.append(DictionaryMeaning(
                english: translation,
                rawEnglish: rawTranslations.indices.contains(index) ? rawTranslations[index] : translation,
                rawGerman: meaning.rawGerman,
                language: meaning.language,
                gender: meaning.gender,
                usage: meaning.usage,
                explanation: meaning.explanation,
                grammar: meaning.grammar,
                subject: meaning.subject
            ))
        }
    }

    private static func parts(from value: String) -> [String] {
        value.split(separator: ";", omittingEmptySubsequences: true).compactMap { part in
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}

struct PartOfSpeechBadge: View {
    let kind: WordKind

    var body: some View {
        Text(kind.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .fixedSize()
            .accessibilityLabel("Part of speech: \(kind.label)")
    }
}

struct TranslationResultBadge: View {
    var body: some View {
        Label("Translation", systemImage: "translate")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.blue)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.blue.opacity(0.12), in: Capsule())
            .fixedSize()
            .accessibilityLabel("Apple on-device translation")
            .accessibilityIdentifier("entry.translation-result")
    }
}

struct GermanWordView: View {
    let entry: DictionaryEntry
    var font: Font = .headline

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if entry.gender != .unknown {
                Text(entry.gender.article.replacingOccurrences(of: " (plural)", with: ""))
                    .foregroundStyle(entry.gender.color)
                    .fontWeight(.semibold)
                    .fixedSize()
            }
            if let parts = GermanMorphology.separableParts(for: entry) {
                ((GermanMorphology.isReflexive(entry) ? Text("sich ") : Text(""))
                    + Text(GermanTextPresentation.hyphenated(parts.prefix)).fontWeight(.semibold)
                    + Text("·").foregroundStyle(.secondary)
                    + Text(GermanTextPresentation.hyphenated(parts.stem)))
            } else {
                Text(GermanTextPresentation.hyphenated(entry.german))
                    .foregroundStyle(
                        entry.kind == .noun && entry.gender != .unknown ? entry.gender.color : .primary
                    )
            }
        }
        .font(font)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.german)
    }
}

struct GermanSentenceText: View {
    @EnvironmentObject private var state: AppState
    let german: String
    let tokens: [SentenceToken]
    @State private var genders: [Int: Gender] = [:]

    var body: some View {
        styledText
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(german)
            .task(id: tokens) {
                genders = await state.sentenceGenders(for: tokens)
            }
    }

    private var styledText: Text {
        guard !tokens.isEmpty else { return Text(GermanTextPresentation.hyphenated(german)) }
        return tokens.enumerated().reduce(Text("")) { text, item in
            let (offset, token) = item
            let prefix = offset == 0 ? "" : " "
            var segment = Text(prefix + GermanTextPresentation.hyphenated(token.surface))
            if let gender = genders[token.index] {
                segment = segment.foregroundColor(gender.color)
            }
            return text + segment
        }
    }
}

struct GermanPronunciationHint: View {
    @EnvironmentObject private var speech: GermanSpeechController
    let german: String
    var ipa: String?

    var body: some View {
        HStack(spacing: 8) {
            if let ipa {
                Text("IPA")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                Text(ipa)
                    .textSelection(.enabled)
                    .accessibilityLabel("Pronunciation: \(ipa)")
                    .accessibilityIdentifier("entry.ipa")
            }

            Button {
                speech.speak(german)
            } label: {
                Label("Listen", systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(.borderless)
            .help("Play German pronunciation — press Shift twice")
            .accessibilityLabel("Play German pronunciation")
            .accessibilityIdentifier("pronunciation.play")

            KeyboardShortcutHint(.doubleShift)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("pronunciation.shortcut")
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct EntryRow: View {
    let entry: DictionaryEntry
    @State private var expandedLanguages: Set<TranslationLanguage> = []

    private func meanings(for language: TranslationLanguage) -> [DictionaryMeaning] {
        TranslationPresentation.expandedMeanings(entry.meanings).filter { $0.language == language }
    }

    private func previewLimit(for language: TranslationLanguage) -> Int {
        language == .english ? 3 : 1
    }

    private func visibleMeanings(for language: TranslationLanguage) -> [DictionaryMeaning] {
        let languageMeanings = meanings(for: language)
        guard !expandedLanguages.contains(language) else { return languageMeanings }
        return Array(languageMeanings.prefix(previewLimit(for: language)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) {
                    GermanWordView(entry: entry)
                        .fixedSize()
                    entryBadges
                }

                VStack(alignment: .leading, spacing: 4) {
                    GermanWordView(entry: entry)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    entryBadges
                }
            }

            ForEach(TranslationLanguage.allCases, id: \.self) { language in
                let languageMeanings = meanings(for: language)
                ForEach(visibleMeanings(for: language)) { meaning in
                    HStack(spacing: 6) {
                        TranslationLanguageBadge(language: language)
                        Text(meaning.translation)
                            .fixedSize(horizontal: false, vertical: true)
                        if entry.gender == .unknown, meaning.gender != .unknown {
                            GenderBadge(gender: meaning.gender)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                if languageMeanings.count > previewLimit(for: language) {
                    Button {
                        if expandedLanguages.contains(language) {
                            expandedLanguages.remove(language)
                        } else {
                            expandedLanguages.insert(language)
                        }
                    } label: {
                        let remaining = languageMeanings.count - previewLimit(for: language)
                        Text(expandedLanguages.contains(language)
                            ? "Show less \(language.label)"
                            : "+ \(remaining) more \(language.label)")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("entry.\(entry.id).meanings.\(language.rawValue).toggle")
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var entryBadges: some View {
        HStack(spacing: 7) {
            if entry.isAppleTranslation {
                TranslationResultBadge()
            }
            PartOfSpeechBadge(kind: entry.kind)
        }
    }
}

struct EntryMeaningSections {
    static let englishPreviewLimit = 3

    let englishPreview: [DictionaryMeaning]
    let additionalEnglish: [DictionaryMeaning]
    let russian: [DictionaryMeaning]

    init(meanings: [DictionaryMeaning]) {
        let expandedMeanings = TranslationPresentation.expandedMeanings(meanings)
        let english = expandedMeanings.filter { $0.language == .english }
        englishPreview = Array(english.prefix(Self.englishPreviewLimit))
        additionalEnglish = Array(english.dropFirst(Self.englishPreviewLimit))
        russian = expandedMeanings.filter { $0.language == .russian }
    }
}

struct EntryDetailInfoRows {
    static func supplemental(from rows: [WordInfo.Row]) -> [WordInfo.Row] {
        rows.filter { row in
            row.label != "German" && row.label != "Translations"
        }
    }
}

struct EntryDetailView: View {
    @State private var isShowingInternalListSelection = false
    @State private var isShowingAdditionalEnglishMeanings = false
    @State private var isShowingRussianMeanings = false
    @State private var isShowingAllForms = false
    let entry: DictionaryEntry
    var addLabel = "Add to My words"
    var addShortcut: ShortcutPresentation?
    var addShortcutModifiers: EventModifiers = [.command]
    var addAccessibilityIdentifier = "dictionary.add-selected"
    var wordLists: [WordList] = []
    var addedListID: WordList.ID?
    var isShowingListSelection: Binding<Bool>?
    var switchAddedListAction: (@MainActor (WordList.ID) async -> Bool)?
    var createAndSwitchAddedListAction: (@MainActor (String) async -> Bool)?
    var didFinishListSelection: (() -> Void)?
    var addAction: (() -> Void)?

    private var info: WordInfo { GermanMorphology.info(for: entry) }
    private var meaningSections: EntryMeaningSections {
        EntryMeaningSections(meanings: entry.meanings)
    }
    private var supplementalInfoRows: [WordInfo.Row] {
        EntryDetailInfoRows.supplemental(from: info.rows)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            GermanWordView(entry: entry, font: .largeTitle.weight(.bold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("entry.word")

                            HStack(spacing: 9) {
                                if entry.isAppleTranslation {
                                    TranslationResultBadge()
                                }
                                PartOfSpeechBadge(kind: entry.kind)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)

                        Spacer(minLength: 8)

                        if let addedListID,
                           let addedList = wordLists.first(where: { $0.id == addedListID }),
                           let switchAddedListAction {
                            Button {
                                listSelectionBinding.wrappedValue = true
                            } label: {
                                HStack(spacing: 8) {
                                    Label(addedList.name, systemImage: "checkmark.circle.fill")
                                    if isShowingListSelection != nil {
                                        KeyboardShortcutHint(.init(chords: [.init(.right)]))
                                            .accessibilityHidden(true)
                                    } else {
                                        Image(systemName: "chevron.down")
                                            .accessibilityHidden(true)
                                    }
                                }
                                .lineLimit(1)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Added to \(addedList.name)")
                            .accessibilityIdentifier("\(addAccessibilityIdentifier).list")
                            .accessibilityHint(
                                isShowingListSelection == nil
                                    ? "Choose or create another list"
                                    : "Press Right Arrow from the recorded words to choose or create another list"
                            )
                            .fixedSize()
                            .popover(isPresented: listSelectionBinding, arrowEdge: .trailing) {
                                AddedWordListSelection(
                                    wordLists: wordLists,
                                    initialListID: addedListID,
                                    confirm: { destinationListID in
                                        guard destinationListID != addedListID else { return true }
                                        return await switchAddedListAction(destinationListID)
                                    },
                                    createAndConfirm: createAndSwitchAddedListAction,
                                    finish: {
                                        listSelectionBinding.wrappedValue = false
                                        didFinishListSelection?()
                                    },
                                    cancel: {
                                        listSelectionBinding.wrappedValue = false
                                        didFinishListSelection?()
                                    }
                                )
                            }
                        } else if let addAction {
                            Button(action: addAction) {
                                HStack(spacing: 8) {
                                    Label(addLabel, systemImage: "plus.circle.fill")
                                    if let addShortcut {
                                        KeyboardShortcutHint(addShortcut)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.return, modifiers: addShortcutModifiers)
                            .accessibilityIdentifier(addAccessibilityIdentifier)
                            .fixedSize()
                        }
                    }

                    meanings
                    HStack {
                        GenderBadge(gender: entry.gender)
                        GermanPronunciationHint(german: entry.german, ipa: entry.ipa)
                    }
                }

                if entry.kind == .adjective {
                    adjectiveScale
                } else if !supplementalInfoRows.isEmpty {
                    infoTable
                }

                importedForms

                if info.separablePrefix != nil {
                    Label("The middle dot marks a prefix that separates in a main clause.", systemImage: "arrow.left.and.right")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                referenceDetails

                if info.isEstimated {
                    Label(generatedFormsDescription, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(generatedFormsDescription)
                        .accessibilityIdentifier("entry.generated-forms")
                }

                Text("Source: \(entry.source)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 700, alignment: .leading)
            .padding(28)
        }
        .accessibilityIdentifier("entry.detail")
        .onChange(of: entry) { _, _ in
            isShowingAdditionalEnglishMeanings = false
            isShowingRussianMeanings = false
            isShowingAllForms = false
        }
    }

    private var listSelectionBinding: Binding<Bool> {
        isShowingListSelection ?? $isShowingInternalListSelection
    }

    private var generatedFormsDescription: String {
        switch entry.kind {
        case .verb:
            "Conjugation generated using regular verb rules."
        case .adjective:
            "Comparative and superlative generated using regular adjective rules."
        default:
            "Forms generated using regular grammar rules."
        }
    }

    private var meanings: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !meaningSections.englishPreview.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    meaningSectionTitle("English")
                    meaningRows(
                        meaningSections.englishPreview,
                        startingAt: 1,
                        totalCount: englishMeaningCount
                    )

                    if !meaningSections.additionalEnglish.isEmpty {
                        meaningDisclosureButton(
                            title: isShowingAdditionalEnglishMeanings
                                ? "Show fewer English translations"
                                : "\(meaningSections.additionalEnglish.count) more English translations",
                            isExpanded: isShowingAdditionalEnglishMeanings,
                            accessibilityIdentifier: "entry.meanings.english.toggle"
                        ) {
                            isShowingAdditionalEnglishMeanings.toggle()
                        }

                        if isShowingAdditionalEnglishMeanings {
                            meaningRows(
                                meaningSections.additionalEnglish,
                                startingAt: EntryMeaningSections.englishPreviewLimit + 1,
                                totalCount: englishMeaningCount
                            )
                        }
                    }
                }
            }

            if !meaningSections.russian.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    meaningDisclosureButton(
                        title: isShowingRussianMeanings
                            ? "Hide Russian translations"
                            : "Russian translations (\(meaningSections.russian.count))",
                        isExpanded: isShowingRussianMeanings,
                        accessibilityIdentifier: "entry.meanings.russian.toggle"
                    ) {
                        isShowingRussianMeanings.toggle()
                    }

                    if isShowingRussianMeanings {
                        meaningRows(
                            meaningSections.russian,
                            startingAt: 1,
                            totalCount: meaningSections.russian.count
                        )
                    }
                }
            }

            if !entry.distinctExplanations.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("EXPLANATIONS")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                    ForEach(Array(entry.distinctExplanations.enumerated()), id: \.element.id) { index, explanation in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if entry.distinctExplanations.count > 1 {
                                Text("\(index + 1).")
                                    .foregroundStyle(.tertiary)
                            }
                            Text(explanation.text)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .font(.title2)
        .foregroundStyle(.secondary)
    }

    private var infoTable: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
            ForEach(supplementalInfoRows) { row in
                GridRow {
                    Text(row.label)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text(GermanTextPresentation.hyphenated(row.value))
                        .fontWeight(.medium)
                        .foregroundStyle(infoColor(for: row))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier(
                            "entry.info." + row.label
                                .lowercased()
                                .replacingOccurrences(of: " ", with: "-")
                        )
                }
            }
        }
    }

    private var englishMeaningCount: Int {
        meaningSections.englishPreview.count + meaningSections.additionalEnglish.count
    }

    private func meaningSectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(.tertiary)
    }

    private func meaningRows(
        _ meanings: [DictionaryMeaning],
        startingAt firstNumber: Int,
        totalCount: Int
    ) -> some View {
        ForEach(Array(meanings.enumerated()), id: \.element.id) { index, meaning in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if totalCount > 1 {
                    Text("\(firstNumber + index).")
                        .foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(meaning.translation)
                            .textSelection(.enabled)
                        if entry.gender == .unknown, meaning.gender != .unknown {
                            GenderBadge(gender: meaning.gender)
                        }
                        if let usage = meaning.usage {
                            Text(usage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let explanation = meaning.distinctExplanation {
                        Text(explanation)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if let metadata = meaningMetadata(meaning) {
                        Text(metadata)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("entry.meaning.metadata")
                    }
                }
            }
        }
    }

    private func meaningMetadata(_ meaning: DictionaryMeaning) -> String? {
        var parts: [String] = []
        if let grammar = meaning.grammar { parts.append("Grammar: \(grammar)") }
        if let subject = meaning.subject { parts.append("Subject: \(subject)") }
        if !meaning.germanMetadata.isEmpty {
            parts.append("German: \(meaning.germanMetadata.joined(separator: ", "))")
        }
        if !meaning.translationMetadata.isEmpty {
            parts.append("Translation: \(meaning.translationMetadata.joined(separator: ", "))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var referenceDetails: some View {
        if let etymology = entry.etymology {
            VStack(alignment: .leading, spacing: 7) {
                Text("ETYMOLOGY")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                Text(etymology)
                    .font(.body)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("entry.etymology")
            }
        }
        if !entry.relatedForms.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("RELATED FORMS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                ForEach(entry.relatedForms) { form in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(form.relation.capitalized)
                            .foregroundStyle(.secondary)
                        Text(GermanTextPresentation.hyphenated(form.word))
                            .fontWeight(.medium)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            .accessibilityIdentifier("entry.related-forms")
        }
    }

    private func meaningDisclosureButton(
        title: String,
        isExpanded: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func infoColor(for row: WordInfo.Row) -> Color {
        guard entry.kind == .noun else { return .primary }
        if row.label == "Plural" { return Gender.plural.color }
        if (row.label == "Singular" || row.label == "Article / gender"), entry.gender != .unknown {
            return entry.gender.color
        }
        return .primary
    }

    private var adjectiveScale: some View {
        HStack(spacing: 10) {
            ForEach(Array(info.rows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.label.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(GermanTextPresentation.hyphenated(row.value))
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(Double(index + 1) * 0.06), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private var importedForms: some View {
        if !entry.forms.isEmpty {
            DisclosureGroup(isExpanded: $isShowingAllForms) {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(entry.forms) { form in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(GermanTextPresentation.hyphenated(form.form))
                                .fontWeight(.medium)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                                .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                            Text(form.tags.sorted().joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("All imported forms (\(entry.forms.count))")
                    .font(.headline)
            }
            .accessibilityIdentifier("entry.imported-forms")
        }
    }
}

private struct AddedWordListSelection: View {
    private enum FocusedControl: Hashable {
        case list
        case newListName
    }

    let wordLists: [WordList]
    let confirm: @MainActor (WordList.ID) async -> Bool
    let createAndConfirm: (@MainActor (String) async -> Bool)?
    let finish: () -> Void
    let cancel: () -> Void

    @State private var selectedListID: WordList.ID
    @State private var isCreatingList = false
    @State private var newListName = ""
    @State private var confirmationTask: Task<Void, Never>?
    @FocusState private var focusedControl: FocusedControl?

    init(
        wordLists: [WordList],
        initialListID: WordList.ID,
        confirm: @escaping @MainActor (WordList.ID) async -> Bool,
        createAndConfirm: (@MainActor (String) async -> Bool)?,
        finish: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) {
        self.wordLists = wordLists
        self.confirm = confirm
        self.createAndConfirm = createAndConfirm
        self.finish = finish
        self.cancel = cancel
        _selectedListID = State(initialValue: initialListID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Choose a list")
                    .font(.headline)
                Spacer()
                if confirmationTask != nil {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            if isCreatingList {
                TextField("List name", text: $newListName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(confirmationTask != nil)
                    .focused($focusedControl, equals: .newListName)
                    .onSubmit(beginCreation)
                    .onExitCommand(perform: cancelCreation)
                    .accessibilityIdentifier("entry.list-selection.name")

                HStack {
                    Button("Cancel", action: cancelCreation)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Create and Move", action: beginCreation)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(trimmedNewListName.isEmpty || confirmationTask != nil)
                        .accessibilityIdentifier("entry.list-selection.create")
                }
            } else {
                List(wordLists, selection: $selectedListID) { list in
                    Text(list.name)
                        .tag(list.id)
                }
                .disabled(confirmationTask != nil)
                .focused($focusedControl, equals: .list)
                .onMoveCommand(perform: moveSelection)
                .onKeyPress(.return) {
                    beginConfirmation()
                    return .handled
                }
                .onExitCommand {
                    guard confirmationTask == nil else { return }
                    cancel()
                }

                if createAndConfirm != nil {
                    Button(action: beginCreatingList) {
                        Label("New list", systemImage: "plus")
                    }
                    .disabled(confirmationTask != nil)
                    .accessibilityIdentifier("entry.list-selection.new-list")
                }
            }
        }
        .padding(12)
        .frame(
            width: 260,
            height: isCreatingList ? 130 : min(CGFloat(wordLists.count) * 28 + 108, 300)
        )
        .onAppear {
            DispatchQueue.main.async { focusedControl = .list }
        }
        .onDisappear {
            confirmationTask?.cancel()
            confirmationTask = nil
        }
    }

    private var trimmedNewListName: String {
        newListName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func beginCreatingList() {
        guard confirmationTask == nil, createAndConfirm != nil else { return }
        isCreatingList = true
        DispatchQueue.main.async { focusedControl = .newListName }
    }

    private func cancelCreation() {
        guard confirmationTask == nil else { return }
        newListName = ""
        isCreatingList = false
        DispatchQueue.main.async { focusedControl = .list }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard confirmationTask == nil else { return }
        guard let index = wordLists.firstIndex(where: { $0.id == selectedListID }) else { return }
        switch direction {
        case .up:
            selectedListID = wordLists[max(index - 1, 0)].id
        case .down:
            selectedListID = wordLists[min(index + 1, wordLists.count - 1)].id
        default:
            break
        }
    }

    private func beginConfirmation() {
        guard confirmationTask == nil else { return }
        let destinationListID = selectedListID
        confirmationTask = Task { @MainActor in
            let didConfirm = await confirm(destinationListID)
            guard !Task.isCancelled else { return }
            confirmationTask = nil
            if didConfirm { finish() }
        }
    }

    private func beginCreation() {
        guard confirmationTask == nil,
              !trimmedNewListName.isEmpty,
              let createAndConfirm
        else { return }
        let name = trimmedNewListName
        confirmationTask = Task { @MainActor in
            let didConfirm = await createAndConfirm(name)
            guard !Task.isCancelled else { return }
            confirmationTask = nil
            if didConfirm { finish() }
        }
    }
}

struct PlaceholderView: View {
    let symbol: String
    let title: String
    let detail: String
    var shortcut: ShortcutPresentation?

    var body: some View {
        if let shortcut {
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                VStack(spacing: 8) {
                    Text(detail)
                    KeyboardShortcutHint(shortcut)
                }
            }
        } else {
            ContentUnavailableView(title, systemImage: symbol, description: Text(detail))
        }
    }
}

enum ShortcutKey: Hashable {
    case symbol(name: String, accessibilityName: String)
    case character(String, accessibilityName: String)
    case comma
    case space

    static let command = symbol(name: "command", accessibilityName: "Command")
    static let control = symbol(name: "control", accessibilityName: "Control")
    static let shift = symbol(name: "shift", accessibilityName: "Shift")
    static let tab = symbol(name: "arrow.right.to.line", accessibilityName: "Tab")
    static let returnKey = symbol(name: "return", accessibilityName: "Return")
    static let escape = symbol(name: "escape", accessibilityName: "Escape")
    static let delete = symbol(name: "delete.left", accessibilityName: "Delete")
    static let up = symbol(name: "arrow.up", accessibilityName: "Up Arrow")
    static let down = symbol(name: "arrow.down", accessibilityName: "Down Arrow")
    static let left = symbol(name: "arrow.left", accessibilityName: "Left Arrow")
    static let right = symbol(name: "arrow.right", accessibilityName: "Right Arrow")
    static let slash = symbol(name: "line.diagonal", accessibilityName: "Slash")
    static let questionMark = symbol(name: "questionmark.square", accessibilityName: "Question Mark")
    static let leftBracket = character("[", accessibilityName: "Left Bracket")
    static let rightBracket = character("]", accessibilityName: "Right Bracket")

    static func letter(_ value: Character) -> ShortcutKey {
        let letter = value.uppercased()
        return character(letter, accessibilityName: letter)
    }

    static func digit(_ value: Int) -> ShortcutKey {
        let digit = value.formatted()
        return character(digit, accessibilityName: digit)
    }

    var accessibilityName: String {
        switch self {
        case .symbol(_, let accessibilityName): accessibilityName
        case .character(_, let accessibilityName): accessibilityName
        case .comma: "Comma"
        case .space: "Space"
        }
    }
}

enum KeyboardShortcutLabel {
    static func pressSpace(to action: String) -> String {
        "Press Space to \(action)"
    }
}

struct ShortcutChord: Hashable {
    let keys: [ShortcutKey]

    init(_ keys: ShortcutKey...) {
        self.keys = keys
    }

    var accessibilityName: String {
        keys.map(\.accessibilityName).joined(separator: "-")
    }
}

struct ShortcutPresentation: Hashable {
    enum Separator: Hashable {
        case alternatives
        case range
        case slash
    }

    let chords: [ShortcutChord]
    var separator: Separator = .slash
    var hold = false

    static let returnKey = ShortcutPresentation(chords: [.init(.returnKey)])
    static let commandF = ShortcutPresentation(chords: [.init(.command, .letter("F"))])
    static let doubleShift = ShortcutPresentation(chords: [.init(.shift), .init(.shift)])

    var accessibilityName: String {
        let separatorName = switch separator {
        case .alternatives: " or "
        case .range: " through "
        case .slash: ", "
        }
        let shortcut = chords.map(\.accessibilityName).joined(separator: separatorName)
        return hold ? "Hold \(shortcut)" : shortcut
    }
}

struct KeyboardShortcutHint: View {
    let shortcut: ShortcutPresentation

    init(_ shortcut: ShortcutPresentation) {
        self.shortcut = shortcut
    }

    var body: some View {
        HStack(spacing: 5) {
            if shortcut.hold {
                Text("Hold")
            }
            ForEach(Array(shortcut.chords.enumerated()), id: \.offset) { index, chord in
                if index > 0 {
                    separator(shortcut.separator)
                }
                HStack(spacing: 2) {
                    ForEach(Array(chord.keys.enumerated()), id: \.offset) { _, key in
                        keyView(key)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut.accessibilityName)
    }

    @ViewBuilder
    private func keyView(_ key: ShortcutKey) -> some View {
        switch key {
        case .symbol(let name, _):
            Image(systemName: name)
        case .character(let value, _):
            Text(value)
        case .comma:
            CommaShortcutIcon()
                .fill(.primary)
                .frame(width: 7, height: 12)
        case .space:
            Text("Space")
        }
    }

    @ViewBuilder
    private func separator(_ separator: ShortcutPresentation.Separator) -> some View {
        switch separator {
        case .alternatives:
            Text("or")
                .fontWeight(.regular)
                .foregroundStyle(.secondary)
        case .range:
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
        case .slash:
            Image(systemName: "line.diagonal")
                .foregroundStyle(.secondary)
        }
    }
}

private struct CommaShortcutIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scaleX = rect.width / 7
        let scaleY = rect.height / 12
        path.addEllipse(in: CGRect(x: 2 * scaleX, y: 3 * scaleY, width: 3 * scaleX, height: 3 * scaleY))
        path.move(to: CGPoint(x: 4.8 * scaleX, y: 5 * scaleY))
        path.addLine(to: CGPoint(x: 4 * scaleX, y: 8.5 * scaleY))
        path.addLine(to: CGPoint(x: 2 * scaleX, y: 10 * scaleY))
        path.addLine(to: CGPoint(x: 3.1 * scaleX, y: 5.5 * scaleY))
        path.closeSubpath()
        return path
    }
}

struct AppShortcut: Identifiable {
    enum Group: String, CaseIterable {
        case global = "Global"
        case dictionary = "Dictionary"
        case review = "Review"
        case lists = "Lists and sentences"
        case dialogs = "Dialogs and controls"
        case macOS = "Standard macOS"
    }

    let id: String
    let group: Group
    let shortcut: ShortcutPresentation
    let action: String

    static let all: [AppShortcut] = [
        .init(id: "global.routes", group: .global, shortcut: .init(chords: [.init(.command, .digit(1)), .init(.command, .digit(5))], separator: .range), action: "Select and focus Dictionary, Review, My Words, Sentences, or Settings in the sidebar"),
        .init(id: "global.settings", group: .global, shortcut: .init(chords: [.init(.command, .comma)]), action: "Open Settings"),
        .init(id: "global.find", group: .global, shortcut: .commandF, action: "Focus search in Dictionary or My Words; open Dictionary elsewhere"),
        .init(id: "global.help", group: .global, shortcut: .init(chords: [.init(.command, .slash), .init(.command, .questionMark)], separator: .alternatives), action: "Show this keyboard shortcut reference"),
        .init(id: "global.pronunciation", group: .global, shortcut: .doubleShift, action: "Play the displayed German word or sentence"),
        .init(id: "global.focus", group: .global, shortcut: .init(chords: [.init(.tab), .init(.shift, .tab)]), action: "Move focus forward or backward"),
        .init(id: "dictionary.navigate", group: .dictionary, shortcut: .init(chords: [.init(.up), .init(.down)]), action: "Move through search results"),
        .init(id: "dictionary.results", group: .dictionary, shortcut: .returnKey, action: "Move from search into its results; press again to add"),
        .init(id: "dictionary.add", group: .dictionary, shortcut: .init(chords: [.init(.command, .returnKey)]), action: "Add the selected dictionary entry"),
        .init(id: "dictionary.clear", group: .dictionary, shortcut: .init(chords: [.init(.escape)]), action: "Clear the focused search field"),
        .init(id: "dictionary.voice-search", group: .dictionary, shortcut: .init(chords: [.init(.space)], hold: true), action: "Search spoken German when focus is outside the text field"),
        .init(id: "dictionary.voice-alternatives", group: .dictionary, shortcut: .init(chords: [.init(.command, .leftBracket), .init(.command, .rightBracket)]), action: "Cycle through voice recognition results"),
        .init(id: "review.reveal", group: .review, shortcut: .init(chords: [.init(.space)]), action: "Reveal the current answer or restart after completion"),
        .init(id: "review.mode", group: .review, shortcut: .init(chords: [.init(.command, .leftBracket), .init(.command, .rightBracket)]), action: "Switch review mode"),
        .init(id: "review.translation", group: .review, shortcut: .init(chords: [.init(.left), .init(.right)]), action: "Move between translations in the current language"),
        .init(id: "review.language", group: .review, shortcut: .init(chords: [.init(.up), .init(.down)]), action: "Move between translation languages"),
        .init(id: "review.speaking", group: .review, shortcut: .init(chords: [.init(.space)]), action: "Start or stop speaking in the speaking test"),
        .init(id: "review.gender", group: .review, shortcut: .init(chords: [.init(.digit(1)), .init(.digit(3))], separator: .range), action: "Choose der, die, or das in the gender test"),
        .init(id: "review.rate", group: .review, shortcut: .init(chords: [.init(.digit(1)), .init(.digit(4))], separator: .range), action: "Rate Again, Hard, Good, or Easy after revealing"),
        .init(id: "lists.navigate", group: .lists, shortcut: .init(chords: [.init(.up), .init(.down)]), action: "Move through results, cards, and sentences"),
        .init(id: "lists.words", group: .lists, shortcut: .init(chords: [.init(.left), .init(.right)]), action: "Move between the sentence list and its words, or through words"),
        .init(id: "lists.toggle-sentence", group: .lists, shortcut: .init(chords: [.init(.letter("X"))]), action: "Toggle the selected generated sentence"),
        .init(id: "lists.open", group: .lists, shortcut: .returnKey, action: "Edit a selected card or save selected generated sentences"),
        .init(id: "lists.new", group: .lists, shortcut: .init(chords: [.init(.command, .letter("N"))]), action: "Create a new list while My Words is open"),
        .init(id: "lists.delete", group: .lists, shortcut: .init(chords: [.init(.delete)]), action: "Remove the selected card or saved sentence"),
        .init(id: "dialogs.accept", group: .dialogs, shortcut: .returnKey, action: "Activate the default button or save an editor"),
        .init(id: "dialogs.cancel", group: .dialogs, shortcut: .init(chords: [.init(.escape)]), action: "Cancel or close a dialog"),
        .init(id: "dialogs.activate", group: .dialogs, shortcut: .init(chords: [.init(.space)]), action: "Activate the focused button, checkbox, or control"),
        .init(id: "macos.close", group: .macOS, shortcut: .init(chords: [.init(.command, .letter("W"))]), action: "Close the current window"),
        .init(id: "macos.quit", group: .macOS, shortcut: .init(chords: [.init(.command, .letter("Q"))]), action: "Quit Lang4Self"),
        .init(id: "macos.clipboard", group: .macOS, shortcut: .init(chords: [.init(.command, .letter("X")), .init(.command, .letter("C")), .init(.command, .letter("V"))]), action: "Cut, copy, or paste in an editable field"),
        .init(id: "macos.select-all", group: .macOS, shortcut: .init(chords: [.init(.command, .letter("A"))]), action: "Select all text in the active editable field"),
        .init(id: "macos.undo", group: .macOS, shortcut: .init(chords: [.init(.command, .letter("Z")), .init(.shift, .command, .letter("Z"))]), action: "Undo or redo the last add, remove, or text edit"),
        .init(id: "macos.window", group: .macOS, shortcut: .init(chords: [.init(.command, .letter("M")), .init(.control, .command, .letter("F"))]), action: "Minimize the window or enter full screen")
    ]
}

struct KeyboardShortcutList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(AppShortcut.Group.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.rawValue)
                        .font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
                        ForEach(AppShortcut.all.filter { $0.group == group }) { shortcut in
                            GridRow {
                                KeyboardShortcutHint(shortcut.shortcut)
                                    .font(.body.weight(.semibold))
                                    .frame(minWidth: 110, alignment: .leading)
                                    .accessibilityIdentifier("shortcut.\(shortcut.id)")
                                Text(shortcut.action)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var closeFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Keyboard Shortcuts", systemImage: "keyboard")
                    .font(.title2.weight(.bold))
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .focusable()
                    .focused($closeFocused)
                    .accessibilityIdentifier("shortcuts.close")
            }
            .padding(20)

            Divider()

            ScrollView {
                KeyboardShortcutList()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
        .frame(width: 620, height: 620)
        .defaultFocus($closeFocused, true)
        .onKeyPress(.space) {
            dismiss()
            return .handled
        }
        .onAppear {
            DispatchQueue.main.async { closeFocused = true }
        }
    }
}
