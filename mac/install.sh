#!/usr/bin/env bash

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.codex/tools/history-manager-mac"
mkdir -p "$TARGET"

cp "$SOURCE_DIR/Codex-History-Manager.sh" "$TARGET/"
cp "$SOURCE_DIR/codex-history-core.mjs" "$TARGET/"
if [ -f "$SOURCE_DIR/README-zh.md" ]; then
  cp "$SOURCE_DIR/README-zh.md" "$TARGET/使用说明.md"
elif [ -f "$SOURCE_DIR/../README-zh.md" ]; then
  cp "$SOURCE_DIR/../README-zh.md" "$TARGET/使用说明.md"
fi

chmod +x "$TARGET/Codex-History-Manager.sh"

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

echo ""
echo "Installed to: $TARGET"
echo "Desktop launcher: $LAUNCHER"
echo ""
