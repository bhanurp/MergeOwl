import AppKit
import SwiftUI

struct CIStatusView: View {
    let pullRequest: PullRequest
    let refreshInterval: TimeInterval
    var isRefreshing = false
    @State private var showingChecks = false
    private var ci: CIStatus { pullRequest.detail.ci ?? .unavailable }

    var body: some View {
        Button { showingChecks.toggle() } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(isRefreshing ? "Checking CI…" : ci.label, systemImage: isRefreshing ? "arrow.triangle.2.circlepath" : symbol)
                    .font(.caption).foregroundStyle(isRefreshing ? Color.secondary : color)
                if !ci.headSHA.isEmpty {
                    Text("Checked \(ci.checkedAt, style: .relative) ago")
                        .font(.caption2).foregroundStyle(.secondary)
                        .accessibilityIdentifier("prpulse.ci-checked.\(pullRequest.id)")
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("prpulse.ci.\(pullRequest.id)")
        .help("Show CI checks")
        .popover(isPresented: $showingChecks) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("CI checks").font(.headline)
                    Spacer()
                    Button("Close") { showingChecks = false }.keyboardShortcut(.cancelAction)
                }
                Text(ci.label).foregroundStyle(color)
                if let warning = ci.warning { Text(warning).font(.caption).foregroundStyle(.orange) }
                if !ci.headSHA.isEmpty {
                    Text("Revision \(ci.revision.prefix(8))\(ci.revision != ci.headSHA ? " · test merge" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        VStack(alignment: .leading) {
                            Text("Checked \(ci.checkedAt, style: .relative) ago").font(.caption)
                            if ci.isStale || context.date.timeIntervalSince(ci.checkedAt) > max(120, refreshInterval * 2) {
                                Text("Results may be stale. Refresh to check the latest state.").font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(ci.checks) { check in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(check.name).font(.body)
                                    Text(check.state.label).font(.caption).foregroundStyle(.secondary)
                                    if check.state == .running, let start = check.startedAt {
                                        Text(start, style: .timer).font(.caption).monospacedDigit()
                                    }
                                }
                                Spacer()
                                if let url = check.url {
                                    VStack(alignment: .trailing) {
                                        Link("Open check", destination: url)
                                        Button("Copy link") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(url.absoluteString, forType: .string)
                                        }.buttonStyle(.link)
                                    }.font(.caption)
                                }
                            }
                            Divider()
                        }
                    }
                }.frame(maxHeight: 280)
                Link("Open checks on GitHub", destination: pullRequest.url.appendingPathComponent("checks"))
                Text("CI results alone do not verify every merge requirement.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16).frame(width: 360)
        }
    }
    private var symbol: String {
        switch ci.state {
        case .failed: "xmark.circle.fill"
        case .passed: "checkmark.circle.fill"
        case .queued, .running: "clock"
        case .actionRequired: "exclamationmark.triangle.fill"
        default: "questionmark.circle"
        }
    }
    private var color: Color {
        switch ci.state {
        case .failed: .red
        case .passed: .green
        case .queued, .running, .actionRequired: .orange
        default: .secondary
        }
    }
}
