# Codex Chat History Manager

English | [中文说明](README-zh.md)

A Windows utility for backing up, restoring, and switching Codex Desktop chat history, ChatGPT login state, API Key login state, and custom OpenAI-compatible API configuration.

This project is designed for people who use Codex Desktop on Windows and want a safer way to:

- back up local Codex conversations;
- back up login and configuration files with Windows DPAPI encryption;
- switch between ChatGPT account login and custom API Key login;
- keep ChatGPT and API Key history under the same `openai` provider;
- configure a custom OpenAI-compatible `base_url`;
- export a portable installer for another Windows computer.

> This tool does not include, upload, or publish your chat records, login credentials, API keys, backups, or personal Codex configuration.

## Features

- **Full backup**
  Backs up chat history, archived sessions, attachments, session indexes, local state databases, `auth.json`, `.cockpit_codex_auth.json`, `config.toml`, and `.env`.

- **Credential encryption**
  Login and configuration files are stored in a `credentials.dpapi.json` package encrypted with Windows DPAPI for the current Windows user.

- **Restore workflow**
  Restores chat history from a selected backup and optionally restores login state and API configuration. A new safety backup is created automatically before restore.

- **Login profile switcher**
  Saves two encrypted login profiles: one for ChatGPT account login and one for custom API login. You can switch between them from the menu.

- **Custom API support**
  Writes the recommended Codex configuration:

  ```toml
  model_provider = "openai"
  openai_base_url = "https://your-api.example.com/v1"

  [desktop]
  model_provider = "openai"
  ```

- **Secure API Key input**
  Reads API keys from the clipboard, a `.txt`, `.key`, `.env`, or `.json` file, or hidden manual input. The key is passed to `codex login --with-api-key` through standard input.

- **Network mode helper**
  Helps custom API users choose direct connection or local proxy mode by editing `.env` proxy settings.

- **Portable installer export**
  Creates a ZIP package containing only the tool scripts and documentation, not your private data.

## Requirements

- Windows
- Codex Desktop installed
- A valid Codex Desktop runtime, including the bundled `node.exe` and `codex.exe`
- PowerShell

The tool uses the current user's Codex home directory:

```text
%USERPROFILE%\.codex
```

If your Codex data is stored somewhere else, set `CODEX_HOME` before running the tool.

## Installation

1. Download or clone this repository.
2. Open the project folder.
3. Double-click `install.cmd`.
4. After installation, use the desktop shortcut:

   ```text
   Codex-Chat-History-Manager.cmd
   ```

The installer copies the tool to:

```text
%USERPROFILE%\.codex\tools\history-manager
```

and creates a desktop launcher.

## Quick Start

### Open the interactive menu

Double-click:

```text
Codex-Chat-History-Manager.cmd
```

or run:

```powershell
Codex-Chat-History-Manager.cmd
```

### Create a full backup

In the main menu, choose:

```text
[2] Create full backup
```

or run:

```powershell
Codex-Chat-History-Manager.cmd -Action backup
```

Backups are saved to:

```text
%USERPROFILE%\.codex\chat-history-backups
```

### Check current status

```powershell
Codex-Chat-History-Manager.cmd -Action status
```

This shows the current login type, active login profile, configured API base URL, session count, backup count, and whether Codex is currently running.

### View help

```powershell
Codex-Chat-History-Manager.cmd -Action help
```

## Main Menu Guide

```text
[1] View chat, login, and API configuration status
[2] Create full backup: chat + DPAPI-encrypted login state
[3] Back up chat history only
[4] View and verify existing backups
[5] Restore backup

[6] Fix unified history mode
[7] Set or clear custom API base URL
[8] Safely enter API Key and log in
[9] View Codex login status
[N] Custom API network mode
[P] Switch between ChatGPT and custom API login profiles

[A] Open all local history with Codex CLI
[E] Export portable installer package
[L] Open backup folder
[H] Show built-in help
[Q] Quit
```

## Recommended Workflow

1. Create a full backup before changing login or API settings.
2. Create another full backup after switching ChatGPT accounts or API keys.
3. Keep both ChatGPT login and API Key login under `model_provider = "openai"`.
4. Use menu `[7]` for custom API addresses instead of creating a new provider.
5. Use menu `[P]` to save and switch between ChatGPT and custom API profiles.
6. If a custom API repeatedly reconnects or streams slowly, use menu `[N]` to test direct/proxy mode.

## Login Profile Switching

Open the profile menu:

```text
[P] ChatGPT / Custom API quick switch
```

Available actions:

```text
[1] Save or update current ChatGPT login profile
[2] Configure or update custom API profile
[3] Switch to ChatGPT account login
[4] Switch to custom API login
[5] View profile status
[6] Open ChatGPT credential import folder
[7] Import ChatGPT credentials from import folder
```

Important:

- Completely exit Codex Desktop before switching profiles.
- Switching profiles restores encrypted login and configuration files.
- Switching profiles does not replace or delete local chat history.

## Custom API Setup

Use menu `[P] -> [2]` for the easiest setup. The tool will:

1. read your API Key;
2. log in through Codex using `codex login --with-api-key`;
3. set the custom API base URL;
4. keep the provider as `openai`;
5. save the state as the encrypted custom API profile.

API Key input options:

- Windows clipboard;
- `.txt`, `.key`, `.env`, or `.json` file;
- hidden manual input.

Supported `.env` format:

```env
OPENAI_API_KEY=your_key_here
```

Supported JSON fields:

```json
{
  "apiKey": "your_key_here"
}
```

The tool displays only the key length and last 4 characters for confirmation. Source files are not deleted automatically and may still contain plaintext keys.

## ChatGPT Credential Import

The import folder is:

```text
%USERPROFILE%\.codex\credential-import
```

Use menu `[P] -> [6]` to open it.

Place both files from the same already logged-in Codex environment into that folder:

```text
auth.json
.cockpit_codex_auth.json
```

Then completely exit Codex Desktop and choose:

```text
[P] -> [7]
```

The tool will validate the files, create a full safety backup, import the credentials, clear the custom API base URL, and save the result as the encrypted ChatGPT profile.

This is not a password login tool and does not bypass OpenAI authentication. Expired, signed-out, or server-revoked tokens cannot be made valid again by copying files.

## Backup Details

A full backup can include:

- `sessions`
- `archived_sessions`
- `attachments`
- `session_index.jsonl`
- `.codex-global-state.json`
- `state_5.sqlite`
- `goals_1.sqlite`
- `auth.json`
- `.cockpit_codex_auth.json`
- `config.toml`
- `.env`

Each backup contains a SHA-256 manifest. After creating a backup, the tool verifies file integrity and tests DPAPI decryption when credentials are included.

DPAPI-encrypted credential packages are usually only decryptable by the same Windows user on the same computer.

## Restore

Before restoring:

1. Completely exit Codex Desktop.
2. Open the manager.
3. Choose menu `[5]`.
4. Select a backup.
5. Choose whether to restore only chat history or also login state and API configuration.

The tool automatically creates a new full safety backup before restoring.

Restoring old files does not make expired ChatGPT tokens or deleted API keys valid again.

## Portable Export

Use menu `[E]` or run:

```powershell
Codex-Chat-History-Manager.cmd -Action export-tool
```

The ZIP package is created under:

```text
%USERPROFILE%\.codex\tool-exports
```

The exported package contains only:

- `Codex-History-Manager.ps1`
- `codex-history-core.mjs`
- documentation
- installer scripts

It does not contain your chat history, login credentials, API keys, backups, or personal configuration.

## Command Line

```powershell
Codex-Chat-History-Manager.cmd
Codex-Chat-History-Manager.cmd -Action status
Codex-Chat-History-Manager.cmd -Action backup
Codex-Chat-History-Manager.cmd -Action help
Codex-Chat-History-Manager.cmd -Action profiles
Codex-Chat-History-Manager.cmd -Action save-chatgpt
Codex-Chat-History-Manager.cmd -Action export-tool
```

Direct PowerShell usage:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.codex\tools\history-manager\Codex-History-Manager.ps1" -Action status
```

## Security Notes

- The repository contains only tool code and documentation.
- Full backups encrypt login and configuration files using Windows DPAPI CurrentUser scope.
- DPAPI protection is tied to the current Windows user and usually the current computer.
- API keys loaded from files remain plaintext in their original files unless you delete or protect those files yourself.
- The tool does not force-close Codex Desktop. You must exit Codex manually before restore or login/profile changes.
- A backup can restore files, but it cannot reactivate credentials that have been revoked by the service provider.

## Troubleshooting

### The tool says Codex is still running

Exit Codex Desktop from the tray or taskbar, then retry. Restore and configuration changes require Codex to be fully closed.

### History disappears after switching login methods

Use menu `[6]` to fix unified history mode. The tool keeps both ChatGPT and API Key history under the `openai` provider so the history list is not filtered by a different provider name.

### Custom API keeps reconnecting

Use menu `[N]` to test and switch between direct connection and local proxy mode. After changing `.env`, fully exit and reopen Codex Desktop.

### A restored login does not work

The credential files may have been expired, signed out, revoked, or the API key may have been deleted by the provider. Restoring files cannot make invalid credentials valid again.

## License

No license has been specified yet. Add a license before accepting external contributions or redistribution.
