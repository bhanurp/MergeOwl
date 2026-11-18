import SwiftUI

struct DefaultPRTabs: View {
    @ObservedObject var viewModel: DashboardViewModel
    var body: some View {
        HStack(spacing: 4) {
            ForEach(PullRequestTab.allCases) { tab in
                let selected = viewModel.selectedSavedViewID == nil && viewModel.selectedTab == tab
                let count = viewModel.actionableCount(for: tab)
                Button {
                    viewModel.selectDefaultTab(tab)
                } label: {
                    HStack(spacing: 5) {
                        Text(tab == .reviewRequested ? "Reviews" : tab.rawValue).lineLimit(1).minimumScaleFactor(0.8)
                        Text("\(count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .padding(.horizontal, 6).padding(.vertical, 5).frame(maxWidth: .infinity)
                    .background(
                        selected ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityValue("\(count) actionable loaded PRs")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(2).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .help("Actionable counts cover loaded PRs only.")
    }
}

struct PRViewTabStrip: View {
    @ObservedObject var viewModel: DashboardViewModel
    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(viewModel.savedViews.filter(\.enabled)) { view in
                        let count = viewModel.actionableCount(for: view)
                        Button {
                            viewModel.selectSavedView(id: view.id)
                        } label: {
                            HStack(spacing: 6) {
                                Text(view.name).lineLimit(1)
                                Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(
                                viewModel.selectedSavedViewID == view.id ? Color.accentColor.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain).help(view.name)
                        .accessibilityIdentifier("prpulse.saved-view.\(view.name)")
                        .accessibilityLabel("\(view.name), \(count) actionable loaded PRs")
                        .accessibilityAddTraits(viewModel.selectedSavedViewID == view.id ? [.isSelected] : [])
                    }
                }
            }
            Menu {
                ForEach(viewModel.savedViews.filter(\.enabled)) { view in
                    Button("\(view.name) (\(viewModel.actionableCount(for: view)))") {
                        viewModel.selectSavedView(id: view.id)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("All saved views")
        }
        .onMoveCommand { direction in
            if direction == .left || direction == .right { viewModel.moveViewSelection(forward: direction == .right) }
        }
        .help("Counts cover loaded PRs only. Refresh or load more to include additional pages.")
    }
}
