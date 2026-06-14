# Codex Chat History Manager

English | [中文说明](README-zh.md)

A Windows/macOS desktop utility for Codex Desktop. It provides a local desktop UI for chat backups, backup restore, ChatGPT account profile switching, custom API Key login, custom API network checks, and unified history repair.

> This repository contains only tool scripts and documentation. It does not contain chats, credentials, API keys, backups, or personal Codex config.

## Desktop UI

The recommended launcher is the desktop UI:

- Windows: `windows/install.cmd`, then open the Usagi-icon desktop shortcut `Codex-Chat-History-Manager-UI.lnk`.
- macOS: `mac/install.sh`, then open `Codex-Chat-History-Manager-UI.command` on the Desktop.

The classic command-line launcher is still installed for fallback and advanced troubleshooting.

The UI can locally import Usagi sticker previews from the approved LINE Store page `ちいかわ(うさぎ多)`:

https://store.line.me/stickershop/product/21802595/ja

Only previews where Usagi is the main subject are used. The selected images are bundled under each platform's `ui/assets/line-usagi/` folder for this local, non-commercial learning/UI prototype project. See [ASSET-NOTICE.md](ASSET-NOTICE.md).

The UI can also refresh the same selections into `ui/private-assets/` by clicking "重新导入 LINE 乌萨奇贴图".

## Repository Layout

```text
windows/   Windows source, installer, CLI launcher, desktop UI source
mac/       macOS source, installer, CLI launcher, desktop UI source
install.cmd  Compatibility shortcut that forwards to windows/install.cmd
```

## Main Features

- Create full backups or chat-only backups.
- Verify and restore backups, with optional encrypted login-state restore.
- Switch between saved ChatGPT account and custom API profiles.
- Log in with an API Key, including first-login flow for new users.
- Clean API leftovers when switching back to ChatGPT account login.
- Set or clear custom API base URL.
- Check `/v1/responses` compatibility and custom API network mode.
- Repair unified history mode so ChatGPT/API Key sessions remain visible together.

## UI Research

I checked available Codex skills and desktop UI projects:

| Option | Stars | Fit |
| --- | ---: | --- |
| Electron | 121,622 | Best cross-platform desktop UI ecosystem |
| Tauri | 107,852 | Strong cross-platform option |
| NW.js | 41,184 | Mature but less active for this use case |
| Neutralino | 8,541 | Lightweight but smaller ecosystem |
| OpenAI `winui-app` skill | openai/skills: 22,118 | Installed locally; Windows-only guidance |

The UI uses a dependency-free local desktop web shell launched with Node, while keeping all sensitive operations in the existing Windows/macOS scripts. This avoids requiring users to install npm packages.

## Authors

- [hunter20041220](https://github.com/hunter20041220)
- [Binpei-Hua](https://github.com/Binpei-Hua)

## License

No license has been specified yet.
