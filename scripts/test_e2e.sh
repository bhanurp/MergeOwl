#!/usr/bin/env bash
set -euo pipefail
PRPULSE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PRPULSE_ROOT"
command -v xcodegen >/dev/null || { echo "Install XcodeGen: brew install xcodegen" >&2; exit 1; }
mkdir -p .build/e2e
python3 Tests/E2E/github_fixture_server.py --port 8765 > .build/e2e/fixture-server.log 2>&1 &
PRPULSE_FIXTURE_PID=$!
trap 'kill "$PRPULSE_FIXTURE_PID" 2>/dev/null || true' EXIT
for attempt in {1..30}; do
  kill -0 "$PRPULSE_FIXTURE_PID" 2>/dev/null || { echo "Fixture server failed to start" >&2; exit 1; }
  if curl --fail --silent http://127.0.0.1:8765/health >/dev/null; then break; fi
  sleep 1
done
curl --fail --silent http://127.0.0.1:8765/health >/dev/null
xcodegen generate --spec Tests/E2E/project.yml
PRPULSE_RESULTS="${PRPULSE_E2E_RESULT_BUNDLE:-.build/e2e/results-$(date +%s).xcresult}"
xcodebuild test \
  -project Tests/E2E/PRPulseE2E.xcodeproj -scheme PRPulseE2E \
  -destination 'platform=macOS' -derivedDataPath .build/e2e/DerivedData \
  -resultBundlePath "$PRPULSE_RESULTS" \
  -parallel-testing-enabled NO "$@"
