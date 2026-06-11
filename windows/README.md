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
```

Windows credential backups use `credentials.dpapi.json`, protected by Windows DPAPI CurrentUser.
