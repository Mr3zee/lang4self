import SwiftUI
import Lang4SelfCore

extension Gender {
    var color: Color {
        switch self {
        case .masculine: .blue
        case .feminine: .pink
        case .neuter: .green
        case .plural: .orange
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
                .accessibilityLabel("Gender: \(gender.article)")
        }
    }
}

struct TranslationLanguageBadge: View {
    let language: TranslationLanguage

    var body: some View {
        Text(language.shortLabel)
            .font(.caption2.weight(.bold))
            .foregroundStyle(language == .english ? Color.blue : Color.purple)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                (language == .english ? Color.blue : Color.purple).opacity(0.12),
                in: Capsule()
            )
            .accessibilityLabel(language.label)
    }
}

struct GermanWordView: View {
    let entry: DictionaryEntry
    var font: Font = .headline

    var body: some View {
        HStack(spacing: 5) {
            if entry.gender != .unknown {
                Text(entry.gender.article.replacingOccurrences(of: " (plural)", with: ""))
                    .foregroundStyle(entry.gender.color)
                    .fontWeight(.semibold)
            }
            if let parts = GermanMorphology.separableParts(for: entry) {
                (Text(parts.prefix).foregroundStyle(.tint).underline() + Text(parts.stem))
            } else {
                Text(entry.german)
            }
        }
        .font(font)
        .textSelection(.enabled)
    }
}

struct EntryRow: View {
    let entry: DictionaryEntry

    private var previewMeanings: [DictionaryMeaning] {
        var seenLanguages = Set<TranslationLanguage>()
        let firstInEachLanguage = entry.meanings.filter {
            seenLanguages.insert($0.language).inserted
        }
        let remaining = entry.meanings.filter { !firstInEachLanguage.contains($0) }
        return Array((firstInEachLanguage + remaining).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GermanWordView(entry: entry)
            ForEach(previewMeanings) { meaning in
                HStack(spacing: 6) {
                    TranslationLanguageBadge(language: meaning.language)
                    Text(meaning.translation)
                        .lineLimit(1)
                    if entry.gender == .unknown, meaning.gender != .unknown {
                        GenderBadge(gender: meaning.gender)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            if entry.meanings.count > 3 {
                Text("+ \(entry.meanings.count - 3) more")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct EntryDetailView: View {
    let entry: DictionaryEntry
    var addLabel = "Add to My words"
    var addAction: (() -> Void)?

    private var info: WordInfo { GermanMorphology.info(for: entry) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    GermanWordView(entry: entry, font: .largeTitle.weight(.bold))
                    meanings
                    HStack {
                        Text(entry.kind.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        GenderBadge(gender: entry.gender)
                    }
                }

                if entry.kind == .adjective {
                    adjectiveScale
                } else {
                    infoTable
                }

                if info.separablePrefix != nil {
                    Label("The blue underlined prefix separates in a main clause.", systemImage: "link.badge.plus")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if info.isEstimated {
                    Label("Regular forms are estimated locally. Check irregular forms before memorising.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                if let addAction {
                    Button(action: addAction) {
                        Label(addLabel, systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command])
                }

                Text("Source: \(entry.source)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 700, alignment: .leading)
            .padding(28)
        }
    }

    private var meanings: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(TranslationLanguage.allCases, id: \.self) { language in
                let languageMeanings = entry.meanings.filter { $0.language == language }
                if !languageMeanings.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(language.label.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                        ForEach(Array(languageMeanings.enumerated()), id: \.element.id) { index, meaning in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                if languageMeanings.count > 1 {
                                    Text("\(index + 1).")
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
                                }
                            }
                        }
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
            ForEach(info.rows) { row in
                GridRow {
                    Text(row.label)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text(row.value)
                        .fontWeight(.medium)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var adjectiveScale: some View {
        HStack(spacing: 10) {
            ForEach(Array(info.rows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.label.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(row.value)
                        .font(.title3.weight(.semibold))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(Double(index + 1) * 0.06), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

struct PlaceholderView: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(detail))
    }
}
