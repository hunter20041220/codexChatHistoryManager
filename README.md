# Codex Chat History Manager

English | [中文说明](README-zh.md)

A local Windows/macOS desktop manager for Codex Desktop chat history, backups, account login state, and custom API profiles.

> This repository contains only tool scripts, UI assets, and documentation. It does not contain chats, credentials, API keys, backups, or personal Codex config.

## Install

Windows:

```powershell
.\windows\install.cmd
```

Then open the desktop shortcut `Codex-Chat-History-Manager` with the Usagi icon.

macOS:

```bash
cd mac
chmod +x install.sh Codex-History-Manager.sh Codex-Chat-History-Manager.command
./install.sh
```

Then open `Codex-Chat-History-Manager.command` on the Desktop.

## Features

- Full backup, chat-only backup, verification, and restore.
- ChatGPT account profile saving and switching.
- API Key login, including first-login flow for new users.
- Clean API leftovers when switching back to ChatGPT account login.
- Custom API base URL setup and `/v1/responses` network checks.
- Unified history repair so ChatGPT/API Key sessions stay visible together.
- Local desktop UI with bundled Usagi sticker-preview assets.

## Repository Layout

```text
windows/     Windows source, installer, runtime launcher, desktop UI
mac/         macOS source, installer, runtime launcher, desktop UI
install.cmd  Compatibility shortcut forwarding to windows/install.cmd
```

Windows installs an internal launcher at `%USERPROFILE%\.codex\tools\history-manager\Codex-Chat-History-Manager.cmd`; it is not placed on the Desktop. The Desktop only gets one shortcut: `Codex-Chat-History-Manager`.

## Usagi Assets

The bundled Usagi images are selected public sticker previews from the approved LINE Store page:

https://store.line.me/stickershop/product/21802595/ja

Only previews where Usagi is the main subject are included. They are stored under each platform's `ui/assets/line-usagi/` folder for local, non-commercial learning/UI prototype use. See [ASSET-NOTICE.md](ASSET-NOTICE.md).

## Authors

- [hunter20041220](https://github.com/hunter20041220)
- [Binpei-Hua](https://github.com/Binpei-Hua)

## License

No open-source license has been specified yet.
