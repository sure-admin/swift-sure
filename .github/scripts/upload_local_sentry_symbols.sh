#!/bin/sh
set -eu

# The scheme's post-build action runs after Xcode finishes both dSYM images.
# TestFlight archives upload their archive dSYMs in CI.
if [ "${PLATFORM_NAME:-}" != "iphoneos" ] || [ "${CONFIGURATION:-}" != "Debug" ]; then
  exit 0
fi

if [ -z "${SURE_SENTRY_DSN:-}" ]; then
  exit 0
fi

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v sentry-cli >/dev/null 2>&1; then
  echo "warning: Install sentry-cli to upload local iOS Debug symbols to Sentry."
  exit 0
fi

if [ -z "${SENTRY_AUTH_TOKEN:-}" ] && [ ! -f "${PROJECT_DIR}/.sentryclirc" ]; then
  echo "warning: Set SENTRY_AUTH_TOKEN or add an ignored .sentryclirc to upload local iOS Debug symbols."
  exit 0
fi

symbols_path="${DWARF_DSYM_FOLDER_PATH:-}/${DWARF_DSYM_FILE_NAME:-}"
if [ ! -d "$symbols_path" ]; then
  echo "warning: No dSYM found for the local iOS Debug build at $symbols_path."
  exit 0
fi

# Xcode puts the stub executor and Debug Dylib DWARF images in the same
# Sure.app.dSYM bundle. The dylib image must be complete before upload.
if [ "${ENABLE_DEBUG_DYLIB:-NO}" = "YES" ]; then
  debug_image="$symbols_path/Contents/Resources/DWARF/${PRODUCT_NAME:-Sure}.debug.dylib"
  if [ ! -f "$debug_image" ]; then
    echo "warning: The local iOS Debug build has no matching dylib image at $debug_image."
    exit 0
  fi
fi

export SENTRY_URL="${SENTRY_URL:-https://de.sentry.io}"
export SENTRY_ORG="${SENTRY_ORG:-chancen}"
export SENTRY_PROJECT="${SENTRY_PROJECT:-swift-sure}"
cd "$PROJECT_DIR"
if ! sentry-cli debug-files upload --wait "$symbols_path"; then
  echo "warning: Sentry symbol upload failed; the local app build can still run."
fi
