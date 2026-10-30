import AppKit
import SwiftUI

struct PullRequestRowView: View {
    var presentation: PullRequestPresentation
    var actionHandler: (DashboardViewModel.QuickAction) -> Void
    var showAuthor: Bool = false
    var ciRefreshInterval: TimeInterval = 300
    var ciRefreshing = false
    var ciMuted = false
    var toggleCIMute: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 14)).foregroundStyle(.secondary)
                .frame(width: 18).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 4) {
                    Button {
                        NSWorkspace.shared.open(presentation.pullRequest.url)
                    } label: {
                        Text(presentation.pullRequest.title)
                            .font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.leading).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .help("Open on GitHub")
                    .accessibilityIdentifier("prpulse.open.\(presentation.id)")
                    rowActions
                }
                Text(metadataText).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    .help(metadataText)
                HStack(spacing: 8) {
                    CIStatusView(
                        pullRequest: presentation.pullRequest, refreshInterval: ciRefreshInterval,
                        isRefreshing: ciRefreshing, condensed: true)
                    if presentation.status.changesRequested > 0 {
                        Label(
                            "\(presentation.status.changesRequested) changes requested",
                            systemImage: "exclamationmark.bubble"
                        )
                        .foregroundStyle(.orange)
                    } else if presentation.status.approvals > 0 {
                        Label(
                            "\(presentation.status.approvals) \(presentation.status.approvals == 1 ? "approval" : "approvals")",
                            systemImage: "person.2"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 11)).lineLimit(1)
                if ciMuted {
                    Label("CI alerts muted", systemImage: "bell.slash").font(.system(size: 11)).foregroundStyle(
                        .secondary)
                }
                if !presentation.pullRequest.detail.linkedReferences.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(presentation.pullRequest.detail.linkedReferences.prefix(3))) { ref in
                            if let url = linkedReferenceURL(ref) {
                                Link(linkedReferenceLabel(ref), destination: url).font(.caption2)
                            }
                        }
                        if presentation.pullRequest.detail.linkedReferences.count > 3 {
                            Text("+\(presentation.pullRequest.detail.linkedReferences.count - 3) more")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack(spacing: 6) {
                    readinessBadge
                    if !presentation.actionableBadgeText.isEmpty {
                        Label(
                            presentation.actionableBadgeText,
                            systemImage: presentation.status.badge == .reviewed ? "checkmark.circle" : "arrow.clockwise"
                        )
                        .font(.caption).foregroundStyle(presentation.status.badge == .reviewed ? .green : .orange)
                    }
                    if presentation.pullRequest.override.state == .todo {
                        Text("To do").foregroundStyle(Color.accentColor)
                    }
                    if presentation.pullRequest.override.state == .notApplicable {
                        Text("Not relevant").foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 11))
                if let date = presentation.pullRequest.override.snoozedUntil,
                    presentation.pullRequest.override.isSnoozed
                {
                    Text("Snoozed until \(date, formatter: dateFormatter)").font(.system(size: 11)).foregroundStyle(
                        .secondary)
                }
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 2)
        .contextMenu {
            Button("Mark to do") { actionHandler(.markTodo) }
            Button("Mark not relevant") { actionHandler(.markNotApplicable) }
            Button("Clear override") { actionHandler(.clearOverride) }
            Divider()
            Button("Snooze 1 hour") { actionHandler(.snooze(Date().addingTimeInterval(3600))) }
            Button("Snooze tomorrow") { actionHandler(.snoozeTomorrow) }
        }
    }

    private var rowActions: some View {
        HStack(spacing: 2) {
            Menu {
                Button("Tomorrow morning") { actionHandler(.snoozeTomorrow) }
                Button("1 hour") { actionHandler(.snooze(Date().addingTimeInterval(3600))) }
                Button("Clear") { actionHandler(.clearOverride) }
            } label: {
                Image(systemName: "clock").frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .accessibilityLabel("Snooze").help("Snooze this PR")
            .accessibilityIdentifier("prpulse.snooze.\(presentation.id)")
            Menu {
                Button("Mark to do") { actionHandler(.markTodo) }
                Button("Mark not relevant") { actionHandler(.markNotApplicable) }
                Button("Clear override") { actionHandler(.clearOverride) }
                if let toggleCIMute {
                    Divider()
                    Button(ciMuted ? "Unmute CI failure alerts" : "Mute CI failure alerts", action: toggleCIMute)
                }
            } label: {
                Image(systemName: "ellipsis").frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .accessibilityLabel("More PR actions").help("More PR actions")
            .accessibilityIdentifier("prpulse.pr-more.\(presentation.id)")
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().controlSize(.small)
    }

    private var metadataText: String {
        guard showAuthor else {
            return presentation.subtitle
        }
        return "\(presentation.subtitle) · @\(presentation.pullRequest.author.login)"
    }

    private var readinessBadge: some View {
        switch presentation.status.readiness {
        case .ready:
            return Text("No known blockers")
                .font(.caption)
                .foregroundStyle(.green)
        case .pending:
            return Text("Pending")
                .font(.caption)
                .foregroundStyle(.orange)
        case .blocked(let reason):
            return Text("Blocked: \(reason)")
                .font(.caption)
                .foregroundStyle(.red)
        case .checking:
            return Text("Checking…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func linkedReferenceLabel(_ ref: PullRequestDetail.LinkedReference) -> String {
        let kind = ref.type == .issue ? "Issue" : "PR"
        return "\(kind) #\(ref.number)"
    }

    private func linkedReferenceURL(_ ref: PullRequestDetail.LinkedReference) -> URL? {
        if let url = ref.url {
            return url
        }

        let pathPart = ref.type == .issue ? "issues" : "pull"
        return URL(string: "https://github.com/\(ref.repositoryNameWithOwner)/\(pathPart)/\(ref.number)")
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
}()
