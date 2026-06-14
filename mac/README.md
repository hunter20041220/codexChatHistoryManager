# macOS Version

Install:

```bash
chmod +x install.sh Codex-History-Manager.sh Codex-Chat-History-Manager.command
./install.sh
```

After installation, open this launcher on the Desktop:

```text
Codex-Chat-History-Manager.command
```

The internal launcher is installed at:

```text
~/.codex/tools/history-manager-mac/Codex-Chat-History-Manager.command
```

Source layout:

```text
Codex-History-Manager.sh       macOS backend and CLI actions
codex-history-core.mjs         Shared backup/history core
Codex-Chat-History-Manager.command  Internal desktop UI launcher
ui/                            Desktop UI source and bundled Usagi assets
install.sh                     Installer
```

If the UI cannot find `node`, open Codex Desktop once or install Node.js 22+.
