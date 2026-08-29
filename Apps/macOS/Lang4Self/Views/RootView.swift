import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
            List(AppRoute.allCases, selection: $state.route) { route in
                Label {
                    HStack {
                        Text(route.title)
                        Spacer()
                        if route == .review, state.stats.dueCards > 0 {
                            Text(state.stats.dueCards.formatted())
                                .font(.caption.monospacedDigit())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                } icon: {
                    Image(systemName: route.symbol)
                }
                .tag(route)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 205)
            .safeAreaInset(edge: .bottom) {
                if !state.hasCompleteDictionary {
                    Button {
                        state.route = .settings
                    } label: {
                        Label("Get full dictionary", systemImage: "arrow.down.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
            }
        } detail: {
            content
                .frame(minWidth: 650, minHeight: 500)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let banner = state.banner {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill")
                        Text(banner).lineLimit(1)
                        Button {
                            state.dismissBanner()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 12, y: 4)
                    .frame(maxWidth: 420)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.snappy, value: state.banner)
    }

    @ViewBuilder
    private var content: some View {
        switch state.route {
        case .dictionary: DictionaryView()
        case .speak: SpeakView()
        case .review: ReviewView()
        case .library: LibraryView()
        case .sentences: SentencesView()
        case .settings: SettingsView()
        }
    }
}
