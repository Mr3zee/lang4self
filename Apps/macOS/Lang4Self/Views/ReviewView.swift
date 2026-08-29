import SwiftUI
import Lang4SelfCore

struct ReviewView: View {
    @EnvironmentObject private var state: AppState
    @State private var revealed = false

    private var current: PersonalCard? { state.dueCards.first }

    var body: some View {
        VStack(spacing: 0) {
            statsBar
            Divider()

            if let card = current {
                VStack(spacing: 24) {
                    Spacer()
                    Text("ENGLISH → GERMAN")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
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
                    }
                    Spacer()

                    if revealed { ratingBar(card) }
                }
                .padding(32)
            } else {
                PlaceholderView(
                    symbol: "checkmark.circle",
                    title: "All caught up",
                    detail: state.stats.totalCards == 0 ? "Add a word from Dictionary or Speak to start learning." : "No cards are due right now."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Review")
        .onAppear {
            Task { await state.refreshStudyData() }
        }
        .onChange(of: current?.id) { _, _ in revealed = false }
    }

    private var statsBar: some View {
        HStack(spacing: 28) {
            stat(state.stats.dueCards, "Due")
            stat(state.stats.reviewsToday, "Today")
            stat(state.stats.streakDays, "Day streak")
            Spacer()
            Text("Space reveal · 1–4 rate")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
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
}
