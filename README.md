# Codex Chat History Manager

English | [中文说明](README-zh.md)

A small Windows/macOS utility for Codex Desktop. It backs up local chats, restores history, and switches between ChatGPT account login and custom API Key login without losing the local history list.

> This repository contains only tool scripts and documentation. It does not contain your chats, credentials, API keys, backups, or personal Codex config.

## Versions

| Platform | Folder | Installer | Credential protection |
| --- | --- | --- | --- |
| Windows | `windows/` | `install.cmd` | Windows DPAPI CurrentUser |
| macOS | `mac/` | `install.sh` | macOS Keychain + OpenSSL |

Root-level Windows files are kept for old links and existing users.

## Install

Windows:

1. Install and open Codex Desktop once.
2. Open `windows/`.
3. Double-click `install.cmd`.
4. Use the desktop shortcut `Codex-Chat-History-Manager.cmd`.

macOS:

```bash
cd mac
chmod +x install.sh Codex-History-Manager.sh
./install.sh
```

Then open `Codex-Chat-History-Manager.command` on the Desktop.

## Main Uses

- `[2]` create a full backup.
- `[5]` restore a backup.
- `[6]` fix unified history mode when history disappears after switching login methods.
- `[7]` set or clear a custom API base URL.
- `[8]` log in with an API Key.
- `[N] -> [5]` test custom API `/v1/responses` compatibility.
- `[P] -> [3]` switch back to a saved ChatGPT account profile.
- `[P] -> [6]` clean API leftovers and start ChatGPT account login.

Useful commands:

```powershell
Codex-Chat-History-Manager.cmd -Action status
Codex-Chat-History-Manager.cmd -Action backup
Codex-Chat-History-Manager.cmd -Action chatgpt-login
```

```bash
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action status
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action backup
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action chatgpt-login
```

## Switching Back From API To ChatGPT

Fully quit Codex Desktop first.

- If a ChatGPT profile was saved before, use `[P] -> [3]`.
- If no ChatGPT profile was saved, use `[P] -> [6]`.

The enhanced cleanup removes custom API leftovers such as `openai_base_url`, OpenAI API variables in `.env`, custom API hosts in `NO_PROXY`, and API Key auth files.

## Troubleshooting

- `node.exe` or `codex.exe` not found: open Codex Desktop once, then reinstall this tool. The installer copies Codex's bundled Node runtime when available. If it still fails, set `CODEX_NODE` or `CODEX_CLI`.
- Custom API returns `503` on `/v1/responses`: the provider or upstream model is usually unavailable. Use `[N] -> [5]`.
- Restore says Codex is running: fully quit Codex Desktop from the tray/menu.
- Restored login still fails: the token or API key may be expired, signed out, revoked, or deleted by the provider.

## Authors

- [hunter20041220](https://github.com/hunter20041220)
- [Binpei-Hua](https://github.com/Binpei-Hua)

## License

No license has been specified yet.
