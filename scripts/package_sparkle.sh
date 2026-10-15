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
PRPULSE_STAGE="$(mktemp -d "$PRPULSE_APP/Contents/Frameworks/.sparkle-stage.XXXXXX")"
PRPULSE_REPLACED=false
cleanup() {
  if [[ "$PRPULSE_REPLACED" == false && ( -e "$PRPULSE_STAGE/previous.framework" || -L "$PRPULSE_STAGE/previous.framework" ) ]]; then
    echo "error: previous framework retained at $PRPULSE_STAGE/previous.framework" >&2
  else
    rm -rf -- "$PRPULSE_STAGE"
  fi
}
trap cleanup EXIT
/usr/bin/ditto "$PRPULSE_FRAMEWORK" "$PRPULSE_STAGE/Sparkle.framework"
PRPULSE_DESTINATION="$PRPULSE_APP/Contents/Frameworks/Sparkle.framework"
if [[ -e "$PRPULSE_DESTINATION" || -L "$PRPULSE_DESTINATION" ]]; then
  mv "$PRPULSE_DESTINATION" "$PRPULSE_STAGE/previous.framework"
fi
if ! mv "$PRPULSE_STAGE/Sparkle.framework" "$PRPULSE_DESTINATION"; then
  if [[ -e "$PRPULSE_STAGE/previous.framework" || -L "$PRPULSE_STAGE/previous.framework" ]]; then
    mv "$PRPULSE_STAGE/previous.framework" "$PRPULSE_DESTINATION"
  fi
  exit 1
fi
PRPULSE_REPLACED=true
