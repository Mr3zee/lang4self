import SwiftUI
import Lang4SelfCore

struct DictionaryView: View {
    @EnvironmentObject private var state: AppState
    @FocusState private var searchFocused: Bool

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("German, English, or Russian", text: $state.searchQuery)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .onSubmit {
                            if let first = state.searchResults.first { state.selectedEntry = first }
                        }
                    if !state.searchQuery.isEmpty {
                        Button {
                            state.search("")
                        } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(9)
                .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
                .padding(12)

                Divider()

                if state.searchQuery.isEmpty {
                    PlaceholderView(symbol: "text.magnifyingglass", title: "Search locally", detail: "Type a German, English, or Russian word or phrase. Press ⌘F from anywhere.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            searchFocused = true
        }
        .onAppear {
            if state.searchQuery.isEmpty { searchFocused = true }
        }
    }

    private var addLabel: String {
        "Add to \(state.selectedWordList?.name ?? "My words")"
    }
}

extension Notification.Name {
    static let focusDictionarySearch = Notification.Name("focusDictionarySearch")
}
