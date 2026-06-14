# Windows Version

Install:

```powershell
.\install.cmd
```

After installation, the Desktop only contains one Usagi-icon shortcut:

```text
Codex-Chat-History-Manager
```

The internal launcher is installed at:

```text
%USERPROFILE%\.codex\tools\history-manager\Codex-Chat-History-Manager.cmd
```

It is kept inside the installed tool folder and is not copied to the Desktop.

Source layout:

```text
Codex-History-Manager.ps1   Windows backend and CLI actions
codex-history-core.mjs      Shared backup/history core
Codex-Chat-History-Manager.cmd  Internal desktop UI launcher
ui/                         Desktop UI source and bundled Usagi assets
install.ps1                 Installer
```
