# macOS Version

Install:

```bash
chmod +x install.sh Codex-History-Manager.sh Codex-Chat-History-Manager-UI.command
./install.sh
```

Launch:

- Desktop UI: `Codex-Chat-History-Manager-UI.command`
- Classic CLI: `Codex-Chat-History-Manager.command`

Source layout:

```text
Codex-History-Manager.sh    macOS backend and CLI
codex-history-core.mjs      Shared backup/history core
ui/                         Desktop UI source
install.sh                  Installer
```

If the UI cannot find `node`, open Codex Desktop once or install Node.js 22+.
