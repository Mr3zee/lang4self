import SwiftUI
import Lang4SelfCore

struct LibraryView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedID: PersonalCard.ID?
    @State private var editingCard: PersonalCard?
    @State private var listEditor: ListEditorRequest?
    @State private var showingDeleteListConfirmation = false
    @FocusState private var focusedArea: FocusArea?

    private enum FocusArea: Hashable { case search, cards }

    private var selected: PersonalCard? { state.cards.first { $0.id == selectedID } }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Picker("List", selection: Binding(
                        get: { state.selectedListID },
                        set: { state.selectWordList($0) }
                    )) {
                        ForEach(state.wordLists) { list in Text(list.name).tag(list.id) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    Button {
                        listEditor = .new
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("New list")

                    Menu {
                        Button("Rename List…") {
                            if let list = state.selectedWordList { listEditor = .rename(list) }
                        }
                        Button("Delete List…", role: .destructive) {
                            showingDeleteListConfirmation = true
                        }
                        .disabled(state.selectedListID == WordList.defaultID)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .help("List actions")
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search \(state.selectedWordList?.name ?? "My words")", text: $state.libraryQuery)
                        .textFieldStyle(.plain)
                        .focused($focusedArea, equals: .search)
                }
                .padding(9)
                .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
                .padding(12)

                Divider()

                if state.cards.isEmpty {
                    PlaceholderView(symbol: "books.vertical", title: "No saved entries", detail: "Add words or phrases from Dictionary or confirm them after speaking.")
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
                    .focused($focusedArea, equals: .cards)
                    .onDeleteCommand(perform: removeSelectedCard)
                }
            }
            .frame(minWidth: 300, idealWidth: 365)

            if let card = selected {
                cardDetail(card)
            } else {
                PlaceholderView(symbol: "rectangle.on.rectangle", title: "Select an entry", detail: "Saved words, phrases, and study status appear here.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("My words")
        .onChange(of: state.libraryQuery) { _, value in state.loadLibrary(search: value) }
        .onChange(of: state.selectedListID) { _, _ in
            selectedID = nil
            focusCardList()
        }
        .onChange(of: state.cards.map(\.id)) { _, ids in
            if selectedID.map({ ids.contains($0) }) != true { selectedID = ids.first }
            if focusedArea != .search { focusCardList() }
        }
        .onAppear {
            state.loadLibrary()
            focusCardList()
        }
        .sheet(item: $editingCard) { card in
            CardEditor(card: card) { updated in
                state.updateCard(updated)
                editingCard = nil
            }
        }
        .sheet(item: $listEditor) { request in
            ListNameEditor(title: request.title, initialName: request.initialName) { name in
                switch request.action {
                case .create: state.createWordList(name: name)
                case .rename: state.renameSelectedWordList(to: name)
                }
                listEditor = nil
            }
        }
        .alert("Delete \(state.selectedWordList?.name ?? "list")?", isPresented: $showingDeleteListConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete List", role: .destructive) { state.deleteSelectedWordList() }
        } message: {
            Text("Words that are not in another list will also be deleted.")
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
        Menu("Add to List") {
            ForEach(state.wordLists.filter { $0.id != state.selectedListID }) { list in
                Button(list.name) { state.addCard(card, to: list) }
            }
        }
        .disabled(state.wordLists.count < 2)
        Divider()
        Button("Remove from List", role: .destructive) { state.removeCardFromSelectedList(card) }
    }

    private func removeSelectedCard() {
        guard let selectedID, let index = state.cards.firstIndex(where: { $0.id == selectedID }) else { return }
        let card = state.cards[index]
        if state.cards.count > 1 {
            self.selectedID = state.cards[index == state.cards.count - 1 ? index - 1 : index + 1].id
        } else {
            self.selectedID = nil
        }
        state.removeCardFromSelectedList(card)
    }

    private func focusCardList() {
        if selectedID == nil { selectedID = state.cards.first?.id }
        DispatchQueue.main.async { focusedArea = .cards }
    }

    private func entry(for card: PersonalCard) -> DictionaryEntry {
        .init(id: card.dictionaryEntryID ?? 0, german: card.german, english: card.english, rawGerman: card.rawGerman, kind: card.kind, gender: card.gender, source: "My words")
    }
}

private struct ListEditorRequest: Identifiable {
    enum Action { case create, rename }

    let id = UUID()
    let title: String
    let initialName: String
    let action: Action

    static let new = ListEditorRequest(title: "New list", initialName: "", action: .create)
    static func rename(_ list: WordList) -> ListEditorRequest {
        .init(title: "Rename list", initialName: list.name, action: .rename)
    }
}

private struct ListNameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    let title: String
    let save: (String) -> Void

    init(title: String, initialName: String, save: @escaping (String) -> Void) {
        self.title = title
        _name = State(initialValue: initialName)
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.weight(.bold))
            TextField("List name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: submit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func submit() {
        guard !trimmedName.isEmpty else { return }
        save(trimmedName)
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
            Text("Edit entry").font(.title2.weight(.bold))
            Form {
                TextField("German", text: $card.german)
                TextField("English", text: $card.english)
                TextField("Tags", text: $card.tags, prompt: Text("travel, A2"))
                TextField("Notes", text: $card.notes, axis: .vertical)
                    .lineLimit(3...8)
                Picker("Entry type", selection: $card.kind) {
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
