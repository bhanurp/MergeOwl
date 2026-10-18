import SwiftUI

struct DefaultPRTabs: View {
    @ObservedObject var viewModel: DashboardViewModel
    var body: some View {
        HStack(spacing: 4) {
            ForEach(PullRequestTab.allCases) { tab in
                let selected = viewModel.selectedSavedViewID == nil && viewModel.selectedTab == tab
                Button { viewModel.selectDefaultTab(tab) } label: {
                    HStack(spacing: 5) {
                        Text(tab == .reviewRequested ? "Reviews" : tab.rawValue).lineLimit(1).minimumScaleFactor(0.8)
                        Text("\(viewModel.actionableCount(for: tab))").font(.caption).monospacedDigit()
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6).frame(maxWidth: .infinity)
                    .background(selected ? Color.accentColor.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityValue("\(viewModel.actionableCount(for: tab)) actionable loaded PRs")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(3).background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .help("Actionable counts cover loaded PRs only.")
    }
}

struct PRViewTabStrip: View {
    @ObservedObject var viewModel: DashboardViewModel
    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 6) {
                    ForEach(viewModel.savedViews.filter(\.enabled)) { view in
                        Button { viewModel.selectSavedView(id: view.id) } label: {
                            HStack(spacing: 6) {
                                Text(view.name).lineLimit(1)
                                Text("\(viewModel.actionableCount(for: view))").monospacedDigit()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(viewModel.selectedSavedViewID == view.id ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain).help(view.name)
                        .accessibilityIdentifier("prpulse.saved-view.\(view.name)")
                        .accessibilityLabel("\(view.name), \(viewModel.actionableCount(for: view)) actionable loaded PRs")
                        .accessibilityAddTraits(viewModel.selectedSavedViewID == view.id ? [.isSelected] : [])
                    }
                }.padding(.bottom, 3)
            }
            Menu {
                ForEach(viewModel.savedViews.filter(\.enabled)) { view in
                    Button("\(view.name) (\(viewModel.actionableCount(for: view)))") { viewModel.selectSavedView(id: view.id) }
                }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("All saved views")
        }
        .onMoveCommand { direction in
            if direction == .left || direction == .right { viewModel.moveViewSelection(forward: direction == .right) }
        }
        .help("Counts cover loaded PRs only. Refresh or load more to include additional pages.")
    }
}
