# macOS Version

[中文说明](README-zh.md) | [Project README](../README.md)

This folder contains the macOS build of Codex Chat History Manager.

## Install

Open Terminal in this folder and run:

```bash
chmod +x install.sh Codex-History-Manager.sh
./install.sh
```

The installer copies the tool to:

```text
~/.codex/tools/history-manager-mac
```

and creates a desktop launcher:

```text
Codex-Chat-History-Manager.command
```

## Run

```bash
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action status
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action backup
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action help
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action first-login
```

macOS credential backups use `credentials.keychain.json`, protected by a macOS Keychain-stored secret and OpenSSL AES-256-CBC.

To switch from a custom API back to ChatGPT account login, use `[P] -> [3]` if a ChatGPT profile is saved, or `[P] -> [6]` to clean API leftovers and start account login.

For custom API `503 Service Unavailable` errors after login, open menu `[N]` and choose `[5]` to test `/v1/responses` compatibility.

If the script cannot find runtime binaries, set:

```bash
export CODEX_NODE="/path/to/node"
export CODEX_CLI="/path/to/codex"
```
