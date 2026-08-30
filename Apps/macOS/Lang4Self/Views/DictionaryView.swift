import SwiftUI
import Lang4SelfCore

struct DictionaryView: View {
    @EnvironmentObject private var state: AppState
    @FocusState private var focusedArea: FocusArea?
    let automaticallyFocusContent: Bool

    private enum FocusArea: Hashable { case search, results }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("German, English, or Russian", text: $state.searchQuery)
                        .textFieldStyle(.plain)
                        .focused($focusedArea, equals: .search)
                        .accessibilityIdentifier("dictionary.search")
                        .onSubmit(focusFirstResult)
                        .onKeyPress(.downArrow) {
                            focusFirstResult()
                            return state.searchResults.isEmpty ? .ignored : .handled
                        }
                        .onExitCommand(perform: clearSearch)
                    if !state.searchQuery.isEmpty {
                        Button {
                            clearSearch()
                        } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Clear search")
                            .accessibilityLabel("Clear search")
                            .accessibilityIdentifier("dictionary.clear-search")
                    }
                }
                .padding(9)
                .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
                .padding(12)

                Divider()

                if state.searchQuery.isEmpty {
                    PlaceholderView(symbol: "text.magnifyingglass", title: "Search locally", detail: "Type a German, English, or Russian word or phrase. Press ⌘F from anywhere.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if state.isSearchingDictionary {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Searching…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("dictionary.searching")
                } else if state.searchResults.isEmpty {
                    PlaceholderView(symbol: "questionmark.folder", title: "No match", detail: "Try another spelling or import the complete dict.cc file in Settings.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(state.searchResults, selection: $state.selectedEntry) { entry in
                        EntryRow(entry: entry)
                            .tag(entry)
                            .contextMenu {
                                Button(addLabel) { state.addToPersonalDictionary(entry) }
                            }
                    }
                    .listStyle(.inset)
                    .focused($focusedArea, equals: .results)
                    .accessibilityIdentifier("dictionary.results")
                }
            }
            .frame(minWidth: 285, idealWidth: 340)

            if let entry = state.selectedEntry {
                EntryDetailView(entry: entry, addLabel: addLabel) {
                    state.addToPersonalDictionary(entry)
                }
            } else {
                PlaceholderView(symbol: "character.book.closed", title: "Lang4Self", detail: "Your offline German dictionary")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Dictionary")
        .onChange(of: state.searchQuery) { _, query in state.search(query) }
        .onReceive(NotificationCenter.default.publisher(for: .focusDictionarySearch)) { _ in
            state.route = .dictionary
            focusedArea = .search
        }
        .onAppear {
            guard automaticallyFocusContent else { return }
            DispatchQueue.main.async { focusedArea = .search }
        }
    }

    private var addLabel: String {
        "Add to \(state.selectedWordList?.name ?? "My words")"
    }

    private func focusFirstResult() {
        guard let first = state.searchResults.first else { return }
        state.selectedEntry = first
        focusedArea = .results
    }

    private func clearSearch() {
        state.search("")
        focusedArea = .search
    }
}

extension Notification.Name {
    static let focusDictionarySearch = Notification.Name("focusDictionarySearch")
}
