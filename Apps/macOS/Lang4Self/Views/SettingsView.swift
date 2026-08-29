import SwiftUI
import UniformTypeIdentifiers
import Lang4SelfCore

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingImporter = false
    @State private var showingExplanationImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                settingsSection("Offline dictionary", symbol: "character.book.closed") {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(dictionaryStatus)
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
                            Link(destination: URL(string: "https://www1.dict.cc/translation_file_request.php?l=e")!) {
                                Label("Request DE → RU file", systemImage: "safari")
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

                    Divider()

                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Wiktionary explanations")
                                .font(.headline)
                            Text("\(state.explanationCount.formatted()) English explanations available locally")
                                .foregroundStyle(.secondary)
                            Text("Derived from Wiktionary through kaikki.org and Lector; licensed CC BY-SA 4.0.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            Link("Source and license", destination: URL(string: "https://lector.dev/free/german-dictionary/")!)
                            Button {
                                showingExplanationImporter = true
                            } label: {
                                Label("Import explanation database…", systemImage: "text.book.closed")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(state.isImportingExplanations)
                        }
                    }

                    if state.isImportingExplanations, let progress = state.explanationImportProgress {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: progress.fraction)
                            Text("Imported \(progress.imported.formatted()) of \(progress.total.formatted()) explanations…")
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

                settingsSection("Sentence model", symbol: "cpu") {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                        GridRow {
                            Text("Model").foregroundStyle(.secondary)
                            HStack {
                                Picker("Model", selection: lmSetting(\.modelKey)) {
                                    Text("Automatic (best installed)").tag("")
                                    if !state.lmStudioSettings.modelKey.isEmpty,
                                       state.configuredLMStudioModel == nil {
                                        Text("Missing — \(state.lmStudioSettings.modelKey)")
                                            .tag(state.lmStudioSettings.modelKey)
                                    }
                                    ForEach(state.installedLMStudioModels) { model in
                                        Text("\(model.displayName) — \(model.details)")
                                            .tag(model.modelKey)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                if state.isRefreshingLMStudioModels {
                                    ProgressView().controlSize(.small)
                                }
                                Button {
                                    state.refreshLMStudioModels()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .disabled(state.isRefreshingLMStudioModels)
                                .help("Refresh installed LM Studio models")
                            }
                        }

                        GridRow {
                            Text("Context window").foregroundStyle(.secondary)
                            Picker("Context window", selection: lmSetting(\.contextLength)) {
                                ForEach([8_192, 16_384, 32_768, 65_536, 131_072], id: \.self) { value in
                                    Text("\(value.formatted()) tokens").tag(value)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        GridRow {
                            Text("GPU offload").foregroundStyle(.secondary)
                            Picker("GPU offload", selection: lmSetting(\.gpuOffload)) {
                                ForEach(LMStudioGPUOffload.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        GridRow {
                            Text("Temperature").foregroundStyle(.secondary)
                            HStack {
                                Slider(value: lmSetting(\.temperature), in: 0...1.5, step: 0.05)
                                Text(state.lmStudioSettings.temperature, format: .number.precision(.fractionLength(2)))
                                    .monospacedDigit()
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }

                        GridRow {
                            Text("Top-p").foregroundStyle(.secondary)
                            HStack {
                                Slider(value: lmSetting(\.topP), in: 0.1...1, step: 0.05)
                                Text(state.lmStudioSettings.topP, format: .number.precision(.fractionLength(2)))
                                    .monospacedDigit()
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }

                        GridRow {
                            Text("Max output").foregroundStyle(.secondary)
                            Picker("Maximum output tokens", selection: lmSetting(\.maxOutputTokens)) {
                                ForEach([1_024, 2_048, 4_096, 8_192], id: \.self) { value in
                                    Text("\(value.formatted()) tokens").tag(value)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }

                    if let model = state.configuredLMStudioModel {
                        Text("Using \(model.displayName) (\(model.modelKey))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else if !state.isRefreshingLMStudioModels {
                        Text("No installed text-generation model found.")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }

                    HStack {
                        Label("Requests stay on 127.0.0.1", systemImage: "lock.shield")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Reset Defaults") {
                            state.updateLMStudioSettings(.defaults)
                        }
                    }
                    Text("Model, context, and GPU changes reload the dedicated model on the next generation. Temperature and top-p apply without reloading.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                settingsSection("Keyboard", symbol: "keyboard") {
                    Grid(alignment: .leading, horizontalSpacing: 36, verticalSpacing: 9) {
                        shortcut("⌘1 … ⌘6", "Open each section")
                        shortcut("⌘F", "Search dictionary")
                        shortcut("Hold Space", "Record speech; release to stop")
                        shortcut("Return", "Confirm spoken entry")
                        shortcut("1 … 4", "Rate a review")
                        shortcut("↑ / ↓", "Move through lists")
                        shortcut("Delete", "Remove the selected card from its list")
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
        .task {
            if state.installedLMStudioModels.isEmpty {
                state.refreshLMStudioModels()
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.plainText, .zip, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { state.importDictionary(from: url) }
            case .failure(let error):
                state.showBanner(error.localizedDescription)
            }
        }
        .fileImporter(
            isPresented: $showingExplanationImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { state.importExplanations(from: url) }
            case .failure(let error):
                state.showBanner(error.localizedDescription)
            }
        }
    }

    private var dictionaryStatus: String {
        let languages = TranslationLanguage.allCases
            .filter(state.installedTranslationLanguages.contains)
            .map(\.label)
        return languages.isEmpty
            ? "Starter dictionary only"
            : "dict.cc \(languages.joined(separator: " + ")) installed"
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

    private func lmSetting<Value>(_ keyPath: WritableKeyPath<LMStudioSettings, Value>) -> Binding<Value> {
        Binding(
            get: { state.lmStudioSettings[keyPath: keyPath] },
            set: { value in
                var settings = state.lmStudioSettings
                settings[keyPath: keyPath] = value
                state.updateLMStudioSettings(settings)
            }
        )
    }
}
