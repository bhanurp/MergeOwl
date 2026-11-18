#!/usr/bin/env bash
set -euo pipefail

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "error: this installer supports macOS only" >&2
  exit 1
fi

resolve_repo() {
  local input="${1:-}"
  if [[ -n "$input" ]]; then
    echo "$input"
    return 0
  fi

  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    echo "$GITHUB_REPOSITORY"
    return 0
  fi

  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local remote
    remote="$(git config --get remote.origin.url || true)"
    if [[ "$remote" =~ ^https://github\.com/([^/]+/[^/.]+)(\.git)?$ ]]; then
      echo "${BASH_REMATCH[1]}"
      return 0
    fi
    if [[ "$remote" =~ ^git@github\.com:([^/]+/[^/.]+)(\.git)?$ ]]; then
      echo "${BASH_REMATCH[1]}"
      return 0
    fi
  fi

  return 1
}

REPO="$(resolve_repo "${1:-}" || true)"
if [[ -z "$REPO" ]]; then
  echo "usage: $0 <owner/repo>" >&2
  echo "example: $0 octocat/MergeOwl" >&2
  exit 1
fi

API_URL="https://api.github.com/repos/${REPO}/releases/latest"
RELEASE_JSON="$(curl -fsSL -H "Accept: application/vnd.github+json" "$API_URL")"

ASSET_URL="$(printf '%s' "$RELEASE_JSON" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
assets = data.get("assets", [])
preferred_exts = [".dmg", ".zip", ".tar.gz"]

for ext in preferred_exts:
    for asset in assets:
        name = asset.get("name", "")
        if name.endswith(ext):
            print(asset.get("browser_download_url", ""))
            raise SystemExit(0)

raise SystemExit(1)
')" || true

if [[ -z "$ASSET_URL" ]]; then
  echo "error: no installable .dmg/.zip/.tar.gz asset found in latest release for ${REPO}" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ASSET_NAME="$(basename "${ASSET_URL%%\?*}")"
ASSET_PATH="${TMP_DIR}/${ASSET_NAME}"
echo "Downloading ${ASSET_NAME}..."
curl -fL "$ASSET_URL" -o "$ASSET_PATH"

INSTALL_ROOT="/Applications"
if [[ ! -w "$INSTALL_ROOT" ]]; then
  INSTALL_ROOT="$HOME/Applications"
  mkdir -p "$INSTALL_ROOT"
fi

install_app() {
  local source_app="$1"
  local app_name
  app_name="$(basename "$source_app")"
  local dest="${INSTALL_ROOT}/${app_name}"
  echo "Installing ${app_name} to ${INSTALL_ROOT}..."
  rm -rf "$dest"
  /usr/bin/ditto "$source_app" "$dest"
  echo "If macOS blocks the first launch, remove quarantine only from this trusted release copy:"
  echo "  xattr -dr com.apple.quarantine \"${dest}\""
  echo "Opening ${app_name}..."
  open "$dest"
}

if [[ "$ASSET_NAME" == *.dmg ]]; then
  ATTACH_OUTPUT="$(hdiutil attach "$ASSET_PATH" -nobrowse)"
  MOUNT_POINT="$(printf '%s\n' "$ATTACH_OUTPUT" | awk -F '\t' 'END{print $NF}')"
  APP_IN_DMG="$(find "$MOUNT_POINT" -maxdepth 1 -name "*.app" -print -quit)"

  if [[ -z "$APP_IN_DMG" ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet || true
    echo "error: no .app found inside ${ASSET_NAME}" >&2
    exit 1
  fi

  install_app "$APP_IN_DMG"
  hdiutil detach "$MOUNT_POINT" -quiet || true
  exit 0
fi

EXTRACT_DIR="${TMP_DIR}/extract"
mkdir -p "$EXTRACT_DIR"

if [[ "$ASSET_NAME" == *.zip ]]; then
  /usr/bin/ditto -x -k "$ASSET_PATH" "$EXTRACT_DIR"
elif [[ "$ASSET_NAME" == *.tar.gz ]]; then
  tar -xzf "$ASSET_PATH" -C "$EXTRACT_DIR"
else
  echo "error: unsupported asset type: ${ASSET_NAME}" >&2
  exit 1
fi

APP_PATH="$(find "$EXTRACT_DIR" -name "*.app" -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  echo "error: no .app found after extracting ${ASSET_NAME}" >&2
  exit 1
fi

install_app "$APP_PATH"
