# Codex Chat History Manager

English | [中文说明](README-zh.md)

A cross-platform utility for backing up, restoring, and switching Codex Desktop chat history, ChatGPT login state, API Key login state, and custom OpenAI-compatible API configuration.

The project now provides two platform builds:

- `windows/`: Windows version, implemented with PowerShell and Windows DPAPI.
- `mac/`: macOS version, implemented with Bash, macOS Keychain, and OpenSSL.

The original root-level Windows files are still kept for compatibility, so existing links and install instructions that use `install.cmd`, `install.ps1`, `Codex-History-Manager.ps1`, or `codex-history-core.mjs` will continue to work.

> This repository contains only manager scripts and documentation. It does not contain your chat records, login credentials, API keys, backups, or personal Codex configuration.

## What It Does

- Back up Codex Desktop local chat history and archived sessions.
- Back up local state databases, attachments, and session indexes.
- Encrypt login and configuration files in full backups.
- Restore chat history from a selected backup.
- Optionally restore login state and API configuration.
- Save and switch between ChatGPT account login and custom API Key login profiles.
- Keep both ChatGPT and API Key history under `model_provider = "openai"`.
- Configure or clear a custom OpenAI-compatible `openai_base_url`.
- Safely read API keys from clipboard, file, or hidden input.
- Export a portable package for another machine.

## Platform Differences

| Platform | Main script | Installer | Credential protection | Installed path |
| --- | --- | --- | --- | --- |
| Windows | `windows/Codex-History-Manager.ps1` | `windows/install.cmd` | Windows DPAPI CurrentUser | `%USERPROFILE%\.codex\tools\history-manager` |
| macOS | `mac/Codex-History-Manager.sh` | `mac/install.sh` | macOS Keychain + OpenSSL AES-256-CBC | `~/.codex/tools/history-manager-mac` |

Windows full backups use:

```text
credentials.dpapi.json
```

macOS full backups use:

```text
credentials.keychain.json
```

Each encrypted package is intended for the same OS user that created it. A Windows DPAPI credential package cannot be decrypted on macOS, and a macOS Keychain credential package cannot be decrypted on Windows. Chat history files can still be restored independently when compatible with the Codex Desktop data layout.

## Repository Layout

```text
.
├─ windows/
│  ├─ Codex-History-Manager.ps1
│  ├─ codex-history-core.mjs
│  ├─ install.cmd
│  ├─ install.ps1
│  └─ README-zh.md
├─ mac/
│  ├─ Codex-History-Manager.sh
│  ├─ codex-history-core.mjs
│  ├─ install.sh
│  └─ README-zh.md
├─ Codex-History-Manager.ps1      # compatibility Windows entry
├─ codex-history-core.mjs         # shared core, compatibility copy
├─ install.cmd                    # compatibility Windows installer
├─ install.ps1                    # compatibility Windows installer
├─ README.md
└─ README-zh.md
```

## Requirements

### Windows

- Windows
- Codex Desktop installed
- PowerShell
- Codex Desktop bundled `node.exe` and `codex.exe`

The Windows version manages:

```text
%USERPROFILE%\.codex
```

Set `CODEX_HOME` first if your Codex Home is somewhere else.

### macOS

- macOS
- Codex Desktop installed
- Bash
- `security`, `openssl`, `curl`, and `open`, which are available on standard macOS installs
- A usable `node` and `codex` command, either on `PATH` or discoverable inside the Codex app/runtime

The macOS version manages:

```text
~/.codex
```

Set `CODEX_HOME` first if your Codex Home is somewhere else. If the script cannot find runtime binaries, set `CODEX_NODE` and/or `CODEX_CLI`.

## Install on Windows

Recommended:

1. Download or clone this repository.
2. Open the `windows/` folder.
3. Double-click `install.cmd`.
4. Use the desktop shortcut:

   ```text
   Codex-Chat-History-Manager.cmd
   ```

Compatibility install from the repository root still works:

```text
install.cmd
```

## Install on macOS

1. Download or clone this repository.
2. Open Terminal in the repository root.
3. Run:

   ```bash
   cd mac
   chmod +x install.sh Codex-History-Manager.sh
   ./install.sh
   ```

4. Use the desktop launcher:

   ```text
   Codex-Chat-History-Manager.command
   ```

You can also run the installed script directly:

```bash
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh
```

## Quick Start

### Open the menu

Windows:

```powershell
Codex-Chat-History-Manager.cmd
```

macOS:

```bash
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh
```

### Create a full backup

Windows:

```powershell
Codex-Chat-History-Manager.cmd -Action backup
```

macOS:

```bash
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action backup
```

Backups are saved to:

Windows:

```text
%USERPROFILE%\.codex\chat-history-backups
```

macOS:

```text
~/.codex/chat-history-backups
```

### Check current status

Windows:

```powershell
Codex-Chat-History-Manager.cmd -Action status
```

macOS:

```bash
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action status
```

## Main Menu

```text
[1] View chat, login, and API configuration status
[2] Create full backup
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
4. Use menu `[7]` for custom API addresses instead of creating another provider.
5. Use menu `[P]` to save and switch between ChatGPT and custom API profiles.
6. If a custom API repeatedly reconnects or streams slowly, use menu `[N]` to test direct/proxy mode.

## Custom API Configuration

The manager writes the recommended Codex configuration:

```toml
model_provider = "openai"
openai_base_url = "https://your-api.example.com/v1"

[desktop]
model_provider = "openai"
```

API Key input supports:

- clipboard;
- `.txt`, `.key`, `.env`, or `.json` files;
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

The tool only displays the key length and last 4 characters for confirmation. Source files are not deleted automatically.

## ChatGPT Credential Import

The import folder is:

Windows:

```text
%USERPROFILE%\.codex\credential-import
```

macOS:

```text
~/.codex/credential-import
```

Use menu `[P] -> [6]` to open the folder, then place both files from the same already logged-in Codex environment:

```text
auth.json
.cockpit_codex_auth.json
```

Fully quit Codex Desktop, then choose:

```text
[P] -> [7]
```

This is not a password login tool and does not bypass OpenAI authentication. Expired, signed-out, or server-revoked tokens cannot be made valid again by copying files.

## Backup Contents

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

Each backup includes a SHA-256 manifest. After creating a backup, the tool verifies file integrity and tests credential decryption when the current platform can decrypt the package.

## Restore Notes

- Fully quit Codex Desktop before restoring.
- Restore creates a new full safety backup first.
- You can restore chat history only, or restore login state and API configuration too.
- Cross-platform credential packages are not interchangeable.
- Restoring old files cannot reactivate expired ChatGPT tokens or deleted API keys.

## Command Line

Windows:

```powershell
Codex-Chat-History-Manager.cmd
Codex-Chat-History-Manager.cmd -Action status
Codex-Chat-History-Manager.cmd -Action backup
Codex-Chat-History-Manager.cmd -Action help
Codex-Chat-History-Manager.cmd -Action profiles
Codex-Chat-History-Manager.cmd -Action save-chatgpt
Codex-Chat-History-Manager.cmd -Action export-tool
```

macOS:

```bash
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action status
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action backup
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action help
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action profiles
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action save-chatgpt
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action export-tool
```

## Security Notes

- The repository contains only tool code and documentation.
- Windows credentials are protected by Windows DPAPI CurrentUser.
- macOS credentials are protected by a Keychain-stored secret and OpenSSL AES-256-CBC.
- Credential packages are intended for the same OS user that created them.
- API keys loaded from files remain plaintext in their original files unless you delete or protect those files yourself.
- The tool does not force-close Codex Desktop. You must exit Codex manually before restore or login/profile changes.
- A backup can restore files, but it cannot reactivate credentials revoked by the service provider.

## Troubleshooting

### The tool says Codex is still running

Exit Codex Desktop completely, then retry. Restore and configuration changes require Codex to be fully closed.

### History disappears after switching login methods

Use menu `[6]` to fix unified history mode. The tool keeps both ChatGPT and API Key history under the `openai` provider.

### Custom API keeps reconnecting

Use menu `[N]` to test and switch between direct connection and local proxy mode. After changing `.env`, fully exit and reopen Codex Desktop.

### macOS cannot find node or codex

Set one or both environment variables before running the script:

```bash
export CODEX_NODE="/path/to/node"
export CODEX_CLI="/path/to/codex"
```

### A restored login does not work

The credential files may have expired, been signed out, been revoked, or the API key may have been deleted by the provider. Restoring files cannot make invalid credentials valid again.

## Authors

- [hunter20041220](https://github.com/hunter20041220)
- [Binpei-Hua](https://github.com/Binpei-Hua)

## License

No license has been specified yet. Add a license before accepting external contributions or redistribution.
