# Windows Version

Install:

```powershell
.\install.cmd
```

Launch:

- Desktop UI: `Codex-Chat-History-Manager-UI.cmd`
- Classic CLI: `Codex-Chat-History-Manager.cmd`

The installer copies Codex Desktop's bundled `node.exe` into `%USERPROFILE%\.codex\tools\history-manager\runtime\node.exe` when available, so users usually do not need to install Node manually.

Source layout:

```text
Codex-History-Manager.ps1   Windows backend and CLI
codex-history-core.mjs      Shared backup/history core
ui/                         Desktop UI source
install.ps1                 Installer
```

Use the UI for normal operation. Use the CLI only for troubleshooting or when a terminal workflow is preferred.
