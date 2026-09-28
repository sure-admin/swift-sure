#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
mkdir -p "$scratch/bin" "$scratch/dSYMs/Sure.app.dSYM/Contents/Resources/DWARF"
touch "$scratch/dSYMs/Sure.app.dSYM/Contents/Resources/DWARF/Sure.debug.dylib"
cat > "$scratch/bin/sentry-cli" <<'CLI'
#!/bin/sh
printf '%s\n' "$@" > "$SENTRY_TEST_CAPTURE"
CLI
chmod +x "$scratch/bin/sentry-cli"

run_upload() {
  PROJECT_DIR="$scratch" PLATFORM_NAME=iphoneos CONFIGURATION=Debug \
    SURE_SENTRY_DSN=enabled SENTRY_AUTH_TOKEN=test \
    DWARF_DSYM_FOLDER_PATH="$scratch/dSYMs" DWARF_DSYM_FILE_NAME=Sure.app.dSYM \
    ENABLE_DEBUG_DYLIB=YES PRODUCT_NAME=Sure SENTRY_TEST_CAPTURE="$scratch/arguments" \
    PATH="$scratch/bin:$PATH" sh "$script_dir/upload_local_sentry_symbols.sh"
}

run_upload
test "$(tail -n 1 "$scratch/arguments")" = "$scratch/dSYMs/Sure.app.dSYM"

rm "$scratch/arguments"
rm "$scratch/dSYMs/Sure.app.dSYM/Contents/Resources/DWARF/Sure.debug.dylib"
run_upload > "$scratch/warning"
test ! -e "$scratch/arguments"
grep -q 'no matching dylib image' "$scratch/warning"

echo "Local Sentry symbol upload tests passed."
