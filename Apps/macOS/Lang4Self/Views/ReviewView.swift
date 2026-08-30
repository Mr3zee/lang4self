import SwiftUI
import Lang4SelfCore

struct ReviewView: View {
    @EnvironmentObject private var state: AppState
    @State private var revealed = false
    @FocusState private var focusedAction: FocusedAction?

    private enum FocusedAction: Hashable {
        case reveal
        case rating(Int)
        case restart
    }

    private var current: PersonalCard? { state.reviewCards.first }

    var body: some View {
        VStack(spacing: 0) {
            statsBar
            Divider()

            if let card = current {
                VStack(spacing: 24) {
                    Spacer()
                    Text("TRANSLATIONS → GERMAN")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    PartOfSpeechBadge(kind: card.kind)
                        .accessibilityIdentifier("review.part-of-speech")
                    Text(card.english)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)

                    if revealed {
                        Divider().frame(maxWidth: 460)
                        GermanWordView(entry: entry(for: card), font: .system(size: 32, weight: .bold))
                        compactInfo(for: card)
                    } else {
                        Button("Show answer  Space") { revealed = true }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .keyboardShortcut(.space, modifiers: [])
                            .focusable()
                            .focused($focusedAction, equals: .reveal)
                            .accessibilityIdentifier("review.reveal")
                    }
                    Spacer()

                    if revealed { ratingBar(card) }
                }
                .padding(32)
            } else {
                VStack(spacing: 0) {
                    PlaceholderView(
                        symbol: "checkmark.circle",
                        title: state.isReviewingAll ? "Review complete" : "All caught up",
                        detail: emptyReviewDetail
                    )
                    if state.stats.totalCards > 0 {
                        Button(state.isReviewingAll ? "Review All Again" : "Review All Cards") {
                            state.startReviewAll()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.bottom, 40)
                        .keyboardShortcut(.space, modifiers: [])
                        .focusable()
                        .focused($focusedAction, equals: .restart)
                        .accessibilityIdentifier("review.restart")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Review")
        .onAppear {
            Task { await state.refreshStudyData() }
            focusPrimaryAction()
        }
        .onChange(of: current?.id) { _, _ in
            revealed = false
            focusPrimaryAction()
        }
        .onChange(of: state.selectedListID) { _, _ in revealed = false }
        .onChange(of: state.isReviewingAll) { _, _ in revealed = false }
        .onChange(of: revealed) { _, isRevealed in
            DispatchQueue.main.async {
                focusedAction = isRevealed ? .rating(ReviewRating.allCases.first?.rawValue ?? 1) : .reveal
            }
        }
    }

    private var statsBar: some View {
        HStack(spacing: 20) {
            Picker("List", selection: Binding(
                get: { state.selectedListID },
                set: { state.selectWordList($0) }
            )) {
                ForEach(state.wordLists) { list in Text(list.name).tag(list.id) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 180)
            .accessibilityIdentifier("review.list-picker")

            stat(state.stats.dueCards, "Due")
            stat(state.stats.reviewsToday, "Today")
            stat(state.stats.streakDays, "Day streak")
            Spacer()
            Button(state.isReviewingAll ? "Due Only" : "Review All") {
                if state.isReviewingAll { state.showDueReviews() }
                else { state.startReviewAll() }
            }
            .disabled(state.stats.totalCards == 0)
            .accessibilityIdentifier("review.scope")
            Text("Space reveal · 1–4 rate")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private var emptyReviewDetail: String {
        if state.stats.totalCards == 0 {
            return "Add a word or phrase from Dictionary or Speak to start learning."
        }
        return state.isReviewingAll ? "You reviewed every active card in this list." : "No cards are due right now. You can still review the whole list."
    }

    private func stat(_ number: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(number.formatted()).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func ratingBar(_ card: PersonalCard) -> some View {
        HStack(spacing: 10) {
            ForEach(ReviewRating.allCases, id: \.rawValue) { rating in
                Button {
                    rate(card, rating)
                } label: {
                    VStack(spacing: 3) {
                        Text(rating.label).fontWeight(.semibold)
                        Text("\(rating.rawValue)").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 82)
                }
                .buttonStyle(.bordered)
                .tint(rating == .again ? .red : rating == .easy ? .green : .accentColor)
                .keyboardShortcut(KeyEquivalent(Character(String(rating.rawValue))), modifiers: [])
                .focusable()
                .focused($focusedAction, equals: .rating(rating.rawValue))
                .accessibilityIdentifier("review.rating.\(rating.rawValue)")
            }
        }
        .padding(.bottom, 12)
    }

    private func compactInfo(for card: PersonalCard) -> some View {
        let info = GermanMorphology.info(for: entry(for: card))
        return VStack(spacing: 5) {
            ForEach(info.rows.prefix(3)) { row in
                HStack {
                    Text(row.label).foregroundStyle(.secondary)
                    Text(row.value).fontWeight(.medium)
                }
                .font(.callout)
            }
        }
    }

    private func entry(for card: PersonalCard) -> DictionaryEntry {
        .init(
            id: card.dictionaryEntryID ?? 0,
            german: card.german,
            english: card.english,
            rawGerman: card.rawGerman,
            kind: card.kind,
            gender: card.gender,
            source: "My words"
        )
    }

    private func rate(_ card: PersonalCard, _ rating: ReviewRating) {
        revealed = false
        state.rate(card, rating)
    }

    private func focusPrimaryAction() {
        DispatchQueue.main.async {
            focusedAction = current == nil ? .restart : .reveal
        }
    }
}
