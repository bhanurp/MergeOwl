import AppKit
import SwiftUI

@MainActor
enum GitHubPullRequestIconRenderer {
    // Decode the official vector once, rather than once per row/body evaluation.
    static let image: NSImage? = {
        #if E2E_TESTING
        let resourceBundle: Bundle? = .main
        #else
        let installedURL = Bundle.main.resourceURL?.appendingPathComponent("MergeOwl_PRPulseApp.bundle")
        let resourceBundle: Bundle?
        if let installed = installedURL.flatMap(Bundle.init(url:)) {
            resourceBundle = installed
        } else if Bundle.main.bundleURL.pathExtension == "app" {
            resourceBundle = nil
        } else {
            resourceBundle = .module
        }
        #endif
        let image = resourceBundle?.url(forResource: "git-pull-request-16", withExtension: "svg")
            .flatMap(NSImage.init(contentsOf:))
        image?.isTemplate = true
        return image
    }()
}

struct GitHubPullRequestIcon: View {
    var body: some View {
        Group {
            if let image = GitHubPullRequestIconRenderer.image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Text("PR").font(.system(size: 10, weight: .semibold))
            }
        }
        .frame(width: 16, height: 16)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pull request")
    }
}
