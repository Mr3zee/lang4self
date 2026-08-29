import SwiftUI
import Lang4SelfCore

struct LibraryView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedID: PersonalCard.ID?
    @State private var editingCard: PersonalCard?

    private var selected: PersonalCard? { state.cards.first { $0.id == selectedID } }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search My words", text: $state.libraryQuery)
                        .textFieldStyle(.plain)
                }
                .padding(9)
                .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
                .padding(12)

                Divider()

                if state.cards.isEmpty {
                    PlaceholderView(symbol: "books.vertical", title: "No saved words", detail: "Add words from Dictionary or confirm them after speaking.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(state.cards, selection: $selectedID) { card in
                        HStack {
                            if card.isStarred { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                            VStack(alignment: .leading, spacing: 3) {
                                GermanWordView(entry: entry(for: card))
                                Text(card.english).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if card.isSuspended { Image(systemName: "pause.circle").foregroundStyle(.secondary) }
                        }
                        .padding(.vertical, 3)
                        .tag(card.id)
                        .contextMenu { cardMenu(card) }
                    }
                }
            }
            .frame(minWidth: 300, idealWidth: 365)

            if let card = selected {
                cardDetail(card)
            } else {
                PlaceholderView(symbol: "rectangle.on.rectangle", title: "Select a word", detail: "Saved words and study status appear here.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("My words")
        .onChange(of: state.libraryQuery) { _, value in state.loadLibrary(search: value) }
        .onAppear { state.loadLibrary() }
        .sheet(item: $editingCard) { card in
            CardEditor(card: card) { updated in
                state.updateCard(updated)
                editingCard = nil
            }
        }
    }

    private func cardDetail(_ card: PersonalCard) -> some View {
        VStack(spacing: 0) {
            EntryDetailView(entry: entry(for: card))
            Divider()
            HStack {
                Label(card.isSuspended ? "Suspended" : "Due \(card.dueAt.formatted(date: .abbreviated, time: .shortened))", systemImage: card.isSuspended ? "pause.circle" : "calendar")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Edit") { editingCard = card }
                Button {
                    var changed = card
                    changed.isStarred.toggle()
                    state.updateCard(changed)
                } label: {
                    Label(card.isStarred ? "Unstar" : "Star", systemImage: card.isStarred ? "star.slash" : "star")
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private func cardMenu(_ card: PersonalCard) -> some View {
        Button("Edit…") { editingCard = card }
        Button(card.isStarred ? "Unstar" : "Star") {
            var changed = card; changed.isStarred.toggle(); state.updateCard(changed)
        }
        Button(card.isSuspended ? "Resume reviews" : "Suspend reviews") {
            var changed = card; changed.isSuspended.toggle(); state.updateCard(changed)
        }
        Divider()
        Button("Delete", role: .destructive) { state.deleteCard(card) }
    }

    private func entry(for card: PersonalCard) -> DictionaryEntry {
        .init(id: card.dictionaryEntryID ?? 0, german: card.german, english: card.english, rawGerman: card.rawGerman, kind: card.kind, gender: card.gender, source: "My words")
    }
}

private struct CardEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var card: PersonalCard
    let save: (PersonalCard) -> Void

    init(card: PersonalCard, save: @escaping (PersonalCard) -> Void) {
        _card = State(initialValue: card)
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit word").font(.title2.weight(.bold))
            Form {
                TextField("German", text: $card.german)
                TextField("English", text: $card.english)
                TextField("Tags", text: $card.tags, prompt: Text("travel, A2"))
                TextField("Notes", text: $card.notes, axis: .vertical)
                    .lineLimit(3...8)
                Picker("Word type", selection: $card.kind) {
                    ForEach(WordKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Gender", selection: $card.gender) {
                    ForEach(Gender.allCases, id: \.self) { Text($0 == .unknown ? "Unknown" : $0.article).tag($0) }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save(card) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(card.german.isEmpty || card.english.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
