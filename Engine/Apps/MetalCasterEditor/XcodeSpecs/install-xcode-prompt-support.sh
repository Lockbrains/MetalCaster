#!/bin/bash
# MetalCaster — Install .prompt syntax highlighting into Xcode
# Requires admin privileges because Xcode.app is code-signed.
# Re-run after every Xcode update.

set -e

XCODE_APP="/Applications/Xcode.app"
SM_FRAMEWORK="$XCODE_APP/Contents/SharedFrameworks/SourceModel.framework/Versions/A/Resources"
LANG_SPECS="$SM_FRAMEWORK/LanguageSpecifications"
LANG_META="$SM_FRAMEWORK/LanguageMetadata"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_FILE="$SCRIPT_DIR/MCPrompt.xclangspec"
META_FILE="$SCRIPT_DIR/Xcode.SourceCodeLanguage.MCPrompt.plist"

if [ ! -d "$XCODE_APP" ]; then
    echo "Error: Xcode.app not found at $XCODE_APP"
    exit 1
fi

if [ ! -f "$SPEC_FILE" ] || [ ! -f "$META_FILE" ]; then
    echo "Error: Spec files not found in $SCRIPT_DIR"
    exit 1
fi

echo "Installing MetalCaster .prompt syntax support into Xcode..."

sudo cp "$SPEC_FILE" "$LANG_SPECS/MCPrompt.xclangspec"
sudo cp "$META_FILE" "$LANG_META/Xcode.SourceCodeLanguage.MCPrompt.plist"

echo "Done. Restart Xcode for changes to take effect."
