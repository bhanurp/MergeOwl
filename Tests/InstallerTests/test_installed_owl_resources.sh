#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
APP="$TEST_DIR/ResourceProbe.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/MergeOwl_PRPulseApp.bundle"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ResourceProbe</string>
<key>CFBundleIdentifier</key><string>test.mergeowl.resource-probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
cp "$ROOT_DIR/Sources/PRPulseApp/Resources/MergeOwl.png" "$APP/Contents/Resources/MergeOwl_PRPulseApp.bundle/"
cat > "$TEST_DIR/ModuleTrap.swift" <<'SWIFT'
import Foundation
extension Bundle {
    static var module: Bundle { fatalError("Build-tree resource accessor must not run in an installed app") }
}
SWIFT
cat > "$TEST_DIR/Probe.swift" <<'SWIFT'
import AppKit
@main struct ResourceProbe {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--missing") {
            precondition(StatusItemIconRenderer.owlImage == nil)
        } else {
            precondition(StatusItemIconRenderer.owlImage != nil, "Installed owl must load")
        }
        let rendered = StatusItemIconRenderer.makeImage(actionableCount: 2)
        precondition(rendered.size == NSSize(width: 24, height: 24))
        precondition(rendered.tiffRepresentation != nil)
        print("Installed icon rendered without build-tree resources")
    }
}
SWIFT
swiftc -parse-as-library "$ROOT_DIR/Sources/PRPulseApp/App/StatusItemIconPresentation.swift" \
  "$TEST_DIR/ModuleTrap.swift" "$TEST_DIR/Probe.swift" -o "$APP/Contents/MacOS/ResourceProbe"
"$APP/Contents/MacOS/ResourceProbe"
rm -rf "$APP/Contents/Resources/MergeOwl_PRPulseApp.bundle"
"$APP/Contents/MacOS/ResourceProbe" --missing
