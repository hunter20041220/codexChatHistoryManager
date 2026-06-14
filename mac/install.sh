#!/usr/bin/env bash

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.codex/tools/history-manager-mac"
mkdir -p "$TARGET"

cp "$SOURCE_DIR/Codex-History-Manager.sh" "$TARGET/"
cp "$SOURCE_DIR/codex-history-core.mjs" "$TARGET/"
if [ -d "$SOURCE_DIR/ui" ]; then
  rm -rf "$TARGET/ui"
  cp -R "$SOURCE_DIR/ui" "$TARGET/"
  rm -rf "$TARGET/ui/private-assets"
fi
if [ -f "$SOURCE_DIR/README-zh.md" ]; then
  cp "$SOURCE_DIR/README-zh.md" "$TARGET/使用说明.md"
elif [ -f "$SOURCE_DIR/../README-zh.md" ]; then
  cp "$SOURCE_DIR/../README-zh.md" "$TARGET/使用说明.md"
fi

chmod +x "$TARGET/Codex-History-Manager.sh"
if [ -f "$SOURCE_DIR/Codex-Chat-History-Manager-UI.command" ]; then
  cp "$SOURCE_DIR/Codex-Chat-History-Manager-UI.command" "$TARGET/"
  chmod +x "$TARGET/Codex-Chat-History-Manager-UI.command"
fi

IMPORT_SCRIPT="$TARGET/ui/import-line-usagi.mjs"
NODE_FOR_IMPORT="${CODEX_NODE:-}"
if [ -z "$NODE_FOR_IMPORT" ] || [ ! -x "$NODE_FOR_IMPORT" ]; then
  if command -v node >/dev/null 2>&1; then
    NODE_FOR_IMPORT="$(command -v node)"
  fi
fi
if [ -n "$NODE_FOR_IMPORT" ] && [ -x "$NODE_FOR_IMPORT" ] && [ -f "$IMPORT_SCRIPT" ]; then
  echo "Importing local Usagi sticker previews from approved LINE page..."
  if USAGI_IMPORT_TIMEOUT_MS=15000 "$NODE_FOR_IMPORT" "$IMPORT_SCRIPT" >/dev/null 2>&1; then
    echo "Usagi stickers imported to local private assets."
  else
    echo "Warning: Usagi sticker import failed. You can retry from the desktop UI."
  fi
fi

DESKTOP="$HOME/Desktop"
mkdir -p "$DESKTOP"
LAUNCHER="$DESKTOP/Codex-Chat-History-Manager.command"
cat > "$LAUNCHER" <<LAUNCHER_EOF
#!/usr/bin/env bash
"$TARGET/Codex-History-Manager.sh" "\$@"
printf "\\n"
read -r -p "Press Enter to close..."
LAUNCHER_EOF
chmod +x "$LAUNCHER"

UI_LAUNCHER="$DESKTOP/Codex-Chat-History-Manager-UI.command"
cat > "$UI_LAUNCHER" <<LAUNCHER_EOF
#!/usr/bin/env bash
"$TARGET/Codex-Chat-History-Manager-UI.command"
LAUNCHER_EOF
chmod +x "$UI_LAUNCHER"

echo ""
echo "Installed to: $TARGET"
echo "Desktop launcher: $LAUNCHER"
echo "Desktop UI launcher: $UI_LAUNCHER"
echo ""
