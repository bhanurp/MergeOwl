#!/usr/bin/env bash
set -euo pipefail
if [[ $# != 2 ]]; then
  echo "usage: package_sparkle.sh <app-bundle> <Sparkle.framework>" >&2
  exit 1
fi
PRPULSE_APP="$1"
PRPULSE_FRAMEWORK="$2"
if [[ ! -d "$PRPULSE_FRAMEWORK" || ! -x "$PRPULSE_FRAMEWORK/Sparkle" ]]; then
  echo "error: Sparkle framework is missing or invalid" >&2
  exit 1
fi
if [[ "$PRPULSE_APP" != *.app ]]; then
  echo "error: destination must be an app bundle" >&2
  exit 1
fi
mkdir -p "$PRPULSE_APP/Contents/Frameworks"
/usr/bin/ditto "$PRPULSE_FRAMEWORK" "$PRPULSE_APP/Contents/Frameworks/Sparkle.framework"
