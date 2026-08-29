import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                settingsSection("Offline dictionary", symbol: "character.book.closed") {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(state.hasCompleteDictionary ? "dict.cc dictionary installed" : "Starter dictionary only")
                                .font(.headline)
                            Text("\(state.dictionaryCount.formatted()) entries available locally")
                                .foregroundStyle(.secondary)
                            if !state.hasCompleteDictionary {
                                Text("dict.cc requires every user to accept its terms and request their own copy. Its data is free for personal use, but is not open-source data and cannot be bundled with this app.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            Link(destination: URL(string: "https://www1.dict.cc/translation_file_request.php?l=e")!) {
                                Label("Request DE → EN file", systemImage: "safari")
                            }
                            Button {
                                showingImporter = true
                            } label: {
                                Label("Import downloaded file…", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(state.isImporting)
                        }
                    }

                    if state.isImporting, let progress = state.importProgress {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: progress.fraction)
                            Text("Imported \(progress.imported.formatted()) entries…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                settingsSection("Speech", symbol: "waveform") {
                    Text("Speech recognition is forced to German on-device mode. Install German under System Settings → Keyboard → Dictation Languages if macOS reports that the model is unavailable.")
                        .foregroundStyle(.secondary)
                    Label("Audio and recognized text never leave this Mac", systemImage: "lock.shield")
                        .foregroundStyle(.green)
                }

                settingsSection("Keyboard", symbol: "keyboard") {
                    Grid(alignment: .leading, horizontalSpacing: 36, verticalSpacing: 9) {
                        shortcut("⌘1 … ⌘5", "Open each section")
                        shortcut("⌘F", "Search dictionary")
                        shortcut("Space", "Record / reveal")
                        shortcut("Return", "Confirm spoken word")
                        shortcut("1 … 4", "Rate a review")
                        shortcut("↑ / ↓", "Move through lists")
                    }
                }

                settingsSection("Local data", symbol: "internaldrive") {
                    Text(state.store.databaseURL.path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                    Text("Cards, reviews, and the imported dictionary survive restarts in this SQLite database. No account or server is used.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 800, alignment: .leading)
            .padding(28)
        }
        .navigationTitle("Settings")
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.plainText, .zip, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { state.importDictionary(from: url) }
            case .failure(let error):
                state.banner = error.localizedDescription
            }
        }
    }

    private func settingsSection<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.title3.weight(.bold))
            VStack(alignment: .leading, spacing: 12, content: content)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func shortcut(_ keys: String, _ action: String) -> some View {
        GridRow {
            Text(keys).font(.body.monospaced().weight(.semibold))
            Text(action).foregroundStyle(.secondary)
        }
    }
}
