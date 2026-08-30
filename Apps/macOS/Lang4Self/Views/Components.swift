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

struct PartOfSpeechBadge: View {
    let kind: WordKind

    private var title: String {
        kind == .other ? "Unclassified" : kind.label
    }

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel("Part of speech: \(title)")
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
    @State private var expandedLanguages: Set<TranslationLanguage> = []

    private func meanings(for language: TranslationLanguage) -> [DictionaryMeaning] {
        entry.meanings.filter { $0.language == language }
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
            HStack(spacing: 7) {
                GermanWordView(entry: entry)
                PartOfSpeechBadge(kind: entry.kind)
            }

            ForEach(TranslationLanguage.allCases, id: \.self) { language in
                let languageMeanings = meanings(for: language)
                ForEach(visibleMeanings(for: language)) { meaning in
                    HStack(spacing: 6) {
                        TranslationLanguageBadge(language: language)
                        Text(meaning.translation)
                            .lineLimit(1)
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
                    HStack(spacing: 9) {
                        GermanWordView(entry: entry, font: .largeTitle.weight(.bold))
                        PartOfSpeechBadge(kind: entry.kind)
                    }
                    meanings
                    HStack {
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
                    .accessibilityIdentifier("dictionary.add-selected")
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

struct AppShortcut: Identifiable {
    enum Group: String, CaseIterable {
        case global = "Global"
        case dictionary = "Dictionary"
        case speak = "Speak"
        case review = "Review"
        case lists = "Lists and sentences"
        case dialogs = "Dialogs and controls"
        case macOS = "Standard macOS"
    }

    let group: Group
    let keys: String
    let action: String

    var id: String { "\(group.rawValue)-\(keys)-\(action)" }

    static let all: [AppShortcut] = [
        .init(group: .global, keys: "⌘1 … ⌘6", action: "Open Dictionary, Speak, Review, My Words, Sentences, or Settings"),
        .init(group: .global, keys: "⌘,", action: "Open Settings"),
        .init(group: .global, keys: "⌘F", action: "Focus search in Dictionary or My Words; open Dictionary elsewhere"),
        .init(group: .global, keys: "⌘?", action: "Show this keyboard shortcut reference"),
        .init(group: .global, keys: "Hold Space", action: "Open Speak and record from anywhere"),
        .init(group: .global, keys: "Tab / ⇧Tab", action: "Move focus forward or backward"),
        .init(group: .dictionary, keys: "↑ / ↓", action: "Move through search results"),
        .init(group: .dictionary, keys: "Return", action: "Move from search into its results"),
        .init(group: .dictionary, keys: "⌘Return", action: "Add the selected dictionary entry"),
        .init(group: .dictionary, keys: "Esc", action: "Clear the focused search field"),
        .init(group: .speak, keys: "Hold Space", action: "Record again; release to look it up"),
        .init(group: .speak, keys: "Return", action: "Confirm the selected spoken entry"),
        .init(group: .review, keys: "Space", action: "Reveal the current answer or restart after completion"),
        .init(group: .review, keys: "1 … 4", action: "Rate Again, Hard, Good, or Easy after revealing"),
        .init(group: .lists, keys: "↑ / ↓", action: "Move through results, cards, and sentences"),
        .init(group: .lists, keys: "← / →", action: "Move through words in the sentence inspector"),
        .init(group: .lists, keys: "Return", action: "Edit a selected card or inspect a selected sentence"),
        .init(group: .lists, keys: "⌘N", action: "Create a new list while My Words is open"),
        .init(group: .lists, keys: "Delete", action: "Remove the selected card or saved sentence"),
        .init(group: .dialogs, keys: "Return", action: "Activate the default button or save an editor"),
        .init(group: .dialogs, keys: "Esc", action: "Cancel or close a dialog"),
        .init(group: .dialogs, keys: "Space", action: "Activate the focused button, checkbox, or control"),
        .init(group: .macOS, keys: "⌘W", action: "Close the current window"),
        .init(group: .macOS, keys: "⌘Q", action: "Quit Lang4Self"),
        .init(group: .macOS, keys: "⌘X / ⌘C / ⌘V", action: "Cut, copy, or paste in an editable field"),
        .init(group: .macOS, keys: "⌘A", action: "Select all text in the active editable field"),
        .init(group: .macOS, keys: "⌘Z / ⇧⌘Z", action: "Undo or redo an edit"),
        .init(group: .macOS, keys: "⌘M / ⌃⌘F", action: "Minimize the window or enter full screen")
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
                                Text(shortcut.keys)
                                    .font(.body.monospaced().weight(.semibold))
                                    .frame(minWidth: 110, alignment: .leading)
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
