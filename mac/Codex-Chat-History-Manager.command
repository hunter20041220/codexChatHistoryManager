#!/usr/bin/env bash
set -euo pipefail

TARGET="$HOME/.codex/tools/history-manager-mac"
NODE_EXE="${CODEX_NODE:-}"
if [ -z "$NODE_EXE" ] || [ ! -x "$NODE_EXE" ]; then
  if command -v node >/dev/null 2>&1; then
    NODE_EXE="$(command -v node)"
  else
    echo "未找到 node。请先完整打开一次 Codex Desktop，或安装 Node.js 22+。"
    read -r -p "Press Enter to close..."
    exit 1
  fi
fi

"$NODE_EXE" "$TARGET/ui/server.mjs"
