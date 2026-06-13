# Windows Version

[中文说明](README-zh.md) | [Project README](../README.md)

This folder contains the Windows build of Codex Chat History Manager.

## Install

Double-click:

```text
install.cmd
```

The installer copies the tool to:

```text
%USERPROFILE%\.codex\tools\history-manager
```

and creates a desktop launcher:

```text
Codex-Chat-History-Manager.cmd
```

## Run

```powershell
Codex-Chat-History-Manager.cmd
Codex-Chat-History-Manager.cmd -Action status
Codex-Chat-History-Manager.cmd -Action backup
Codex-Chat-History-Manager.cmd -Action help
Codex-Chat-History-Manager.cmd -Action first-login
```

Windows credential backups use `credentials.dpapi.json`, protected by Windows DPAPI CurrentUser.

If the launcher says `node.exe` or `codex.exe` cannot be found, open Codex Desktop once, then run `install.cmd` again. The installer copies Codex's bundled Node runtime when available.

To switch from a custom API back to ChatGPT account login, use `[P] -> [3]` if a ChatGPT profile is saved, or `[P] -> [6]` to clean API leftovers and start account login.

For custom API `503 Service Unavailable` errors after login, open menu `[N]` and choose `[5]` to test `/v1/responses` compatibility.
