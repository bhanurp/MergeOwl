#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEST_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

mkdir -p "$TEST_DIR/bin" "$TEST_DIR/release-bin"
printf 'stale binary\n' > "$TEST_DIR/release-bin/PRPulseApp"
chmod +x "$TEST_DIR/release-bin/PRPulseApp"

cat > "$TEST_DIR/bin/swift" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$TEST_SWIFT_LOG"

if [[ "$*" == "build -c release" ]]; then
  printf 'fresh binary\n' > "$TEST_RELEASE_BIN/PRPulseApp"
  chmod +x "$TEST_RELEASE_BIN/PRPulseApp"
  exit 0
fi

if [[ "$*" == "build -c release --show-bin-path" ]]; then
  printf '%s\n' "$TEST_RELEASE_BIN"
  exit 0
fi

echo "unexpected swift invocation: $*" >&2
exit 1
SCRIPT
chmod +x "$TEST_DIR/bin/swift"

INSTALL_ROOT="$TEST_DIR/PRPulseApp.app"
TEST_SWIFT_LOG="$TEST_DIR/swift.log" \
TEST_RELEASE_BIN="$TEST_DIR/release-bin" \
PATH="$TEST_DIR/bin:$PATH" \
bash "$PROJECT_DIR/scripts/install_prpulse.sh" "$INSTALL_ROOT"

SWIFT_CALL_1="$(sed -n '1p' "$TEST_DIR/swift.log")"
SWIFT_CALL_2="$(sed -n '2p' "$TEST_DIR/swift.log")"
SWIFT_CALL_COUNT="$(wc -l < "$TEST_DIR/swift.log" | tr -d ' ')"
if [[ "$SWIFT_CALL_COUNT" != "2" ]] \
  || [[ "$SWIFT_CALL_1" != "build -c release" ]] \
  || [[ "$SWIFT_CALL_2" != "build -c release --show-bin-path" ]]; then
  echo "expected release build before querying its binary path" >&2
  cat "$TEST_DIR/swift.log" >&2
  exit 1
fi

if [[ "$(<"$INSTALL_ROOT/Contents/MacOS/PRPulseApp")" != "fresh binary" ]]; then
  echo "expected installed app to contain the freshly built binary" >&2
  exit 1
fi
