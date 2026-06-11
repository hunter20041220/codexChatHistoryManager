# Codex 聊天与登录管理器

[English](README.md) | 中文说明

这是一个跨平台的 Codex Desktop 辅助工具，用于备份、恢复和切换 Codex 本地聊天记录、ChatGPT 登录状态、API Key 登录状态以及自定义 OpenAI 兼容 API 配置。

当前项目提供两个平台版本：

- `windows/`：Windows 版本，使用 PowerShell 和 Windows DPAPI。
- `mac/`：macOS 版本，使用 Bash、macOS Keychain 和 OpenSSL。

为了不破坏已有用户的文件引用和安装路径，根目录下原有的 Windows 文件仍然保留：`install.cmd`、`install.ps1`、`Codex-History-Manager.ps1` 和 `codex-history-core.mjs` 都可以继续使用。

> 本仓库只包含管理器脚本和说明，不包含你的聊天记录、登录凭证、API Key、备份或个人配置。

## 主要功能

- 备份 Codex Desktop 本地聊天记录和归档会话。
- 备份本地状态数据库、附件和会话索引。
- 完整备份时加密保存登录和配置文件。
- 从已有备份恢复聊天记录。
- 可选择同时恢复登录状态和 API 配置。
- 保存并切换 ChatGPT 账号登录档案和自定义 API 登录档案。
- 让 ChatGPT 与 API Key 登录都使用 `model_provider = "openai"`。
- 设置或清除自定义 OpenAI 兼容 `openai_base_url`。
- 从剪贴板、文件或隐藏输入安全读取 API Key。
- 导出便携安装包给其他电脑使用。

## 平台差异

| 平台 | 主脚本 | 安装器 | 凭证保护方式 | 安装位置 |
| --- | --- | --- | --- | --- |
| Windows | `windows/Codex-History-Manager.ps1` | `windows/install.cmd` | Windows DPAPI CurrentUser | `%USERPROFILE%\.codex\tools\history-manager` |
| macOS | `mac/Codex-History-Manager.sh` | `mac/install.sh` | macOS Keychain + OpenSSL AES-256-CBC | `~/.codex/tools/history-manager-mac` |

Windows 完整备份使用：

```text
credentials.dpapi.json
```

macOS 完整备份使用：

```text
credentials.keychain.json
```

加密凭证包通常只能由创建它的同一系统用户解密。Windows DPAPI 凭证包不能在 macOS 上解密，macOS Keychain 凭证包也不能在 Windows 上解密。聊天记录文件本身在 Codex Desktop 数据结构兼容时可以单独恢复。

## 项目目录

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
├─ Codex-History-Manager.ps1      # 兼容旧 Windows 入口
├─ codex-history-core.mjs         # 共享核心，兼容旧引用
├─ install.cmd                    # 兼容旧 Windows 安装器
├─ install.ps1                    # 兼容旧 Windows 安装器
├─ README.md
└─ README-zh.md
```

## 运行要求

### Windows

- Windows
- 已安装 Codex Desktop
- PowerShell
- Codex Desktop 自带的 `node.exe` 和 `codex.exe` 可用

Windows 版默认管理：

```text
%USERPROFILE%\.codex
```

如果你的 Codex Home 不在默认位置，请先设置 `CODEX_HOME`。

### macOS

- macOS
- 已安装 Codex Desktop
- Bash
- 系统自带的 `security`、`openssl`、`curl` 和 `open`
- 可用的 `node` 和 `codex` 命令，或者能在 Codex 应用/运行时目录中找到它们

macOS 版默认管理：

```text
~/.codex
```

如果你的 Codex Home 不在默认位置，请先设置 `CODEX_HOME`。如果脚本找不到运行时，可以设置 `CODEX_NODE` 或 `CODEX_CLI`。

## Windows 安装

推荐方式：

1. 下载或克隆本仓库。
2. 打开 `windows/` 文件夹。
3. 双击 `install.cmd`。
4. 使用桌面入口：

   ```text
   Codex-Chat-History-Manager.cmd
   ```

从仓库根目录运行旧安装器也仍然可用：

```text
install.cmd
```

## macOS 安装

1. 下载或克隆本仓库。
2. 在仓库根目录打开 Terminal。
3. 运行：

   ```bash
   cd mac
   chmod +x install.sh Codex-History-Manager.sh
   ./install.sh
   ```

4. 使用桌面入口：

   ```text
   Codex-Chat-History-Manager.command
   ```

也可以直接运行安装后的脚本：

```bash
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh
```

## 快速开始

### 打开菜单

Windows：

```powershell
Codex-Chat-History-Manager.cmd
```

macOS：

```bash
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh
```

### 创建完整备份

Windows：

```powershell
Codex-Chat-History-Manager.cmd -Action backup
```

macOS：

```bash
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action backup
```

备份位置：

Windows：

```text
%USERPROFILE%\.codex\chat-history-backups
```

macOS：

```text
~/.codex/chat-history-backups
```

### 查看当前状态

Windows：

```powershell
Codex-Chat-History-Manager.cmd -Action status
```

macOS：

```bash
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action status
```

## 主菜单说明

```text
[1] 查看聊天、登录和 API 配置状态
[2] 创建完整备份
[3] 仅备份聊天记录
[4] 查看并校验已有备份
[5] 恢复备份

[6] 修复统一历史模式
[7] 设置或清除自定义 API 地址
[8] 安全输入 API Key 并登录
[9] 查看 Codex 登录状态
[N] 自定义 API 网络模式
[P] ChatGPT / 自定义 API 一键切换

[A] 用 CLI 打开全部本地历史
[E] 导出便携安装包
[L] 打开备份目录
[H] 查看内置使用说明
[Q] 退出
```

## 推荐使用流程

1. 平时使用菜单 `[2]` 创建完整备份。
2. 切换 ChatGPT 账号或 API Key 后，再创建一次完整备份。
3. ChatGPT 登录和 API Key 登录都保持 `model_provider = "openai"`。
4. 自定义 API 地址使用菜单 `[7]`，不要创建另一个 Provider。
5. 使用主菜单 `[P]` 保存并切换 ChatGPT 与自定义 API 两个登录档案。
6. 自定义 API 出现反复 reconnect、响应慢或断流时，使用主菜单 `[N]` 切换网络模式。

## 自定义 API 配置

工具会写入推荐配置：

```toml
model_provider = "openai"
openai_base_url = "https://你的地址/v1"

[desktop]
model_provider = "openai"
```

API Key 支持三种输入方式：

- 从剪贴板读取；
- 从 `.txt`、`.key`、`.env` 或 `.json` 文件读取；
- 使用隐藏输入手动填写。

`.env` 文件支持：

```env
OPENAI_API_KEY=你的_key
```

JSON 文件支持：

```json
{
  "apiKey": "你的_key"
}
```

也支持顶层字段 `api_key`、`OPENAI_API_KEY` 或 `key`。

读取后工具只显示 Key 的长度和末尾 4 位用于核对，不显示完整内容。源文件不会自动删除，其中的 Key 仍是明文，需要自行妥善保管或删除。

## 从凭证文件导入 ChatGPT 登录

导入目录：

Windows：

```text
%USERPROFILE%\.codex\credential-import
```

macOS：

```text
~/.codex/credential-import
```

选择 `[P] -> [6]` 打开目录，把同一个已登录 Codex 环境中的以下两个文件放进去：

```text
auth.json
.cockpit_codex_auth.json
```

完全退出 Codex Desktop 后选择：

```text
[P] -> [7]
```

工具会先校验文件结构，再创建完整安全备份，导入凭证，清除自定义 API 地址，并把新状态保存为加密的 ChatGPT 档案。

这不是账号密码登录工具，也不会绕过 OpenAI 登录。导入文件必须来自已经合法登录的 Codex 环境。已过期、已注销或被服务器撤销的令牌无法通过复制文件恢复有效。

## 备份内容说明

完整备份可能包含：

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

每份备份都会生成 SHA-256 文件清单。备份创建后，工具会自动执行文件完整性校验；如果当前平台能解密凭证包，还会执行解密测试。

## 恢复备份

恢复前请先：

1. 完全退出 Codex Desktop。
2. 打开管理器。
3. 选择主菜单 `[5]`。
4. 选择要恢复的备份。
5. 选择只恢复聊天记录，或同时恢复登录状态和 API 配置。

恢复前工具会自动创建新的完整安全备份。

跨平台凭证包不能互相解密。如果 ChatGPT 令牌已经被服务器撤销，或者 API Key 已被平台删除，旧备份只能恢复文件，不能让失效凭证重新有效。

## 导出便携安装包

选择主菜单：

```text
[E] 导出便携安装包
```

或运行：

Windows：

```powershell
Codex-Chat-History-Manager.cmd -Action export-tool
```

macOS：

```bash
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action export-tool
```

导出的 ZIP 包会保存到：

Windows：

```text
%USERPROFILE%\.codex\tool-exports
```

macOS：

```text
~/.codex/tool-exports
```

安装包只包含工具脚本、说明文档和安装脚本，不会包含你的聊天记录、登录凭证、API Key、备份或个人配置。

## 命令行用法

Windows：

```powershell
Codex-Chat-History-Manager.cmd
Codex-Chat-History-Manager.cmd -Action status
Codex-Chat-History-Manager.cmd -Action backup
Codex-Chat-History-Manager.cmd -Action help
Codex-Chat-History-Manager.cmd -Action profiles
Codex-Chat-History-Manager.cmd -Action save-chatgpt
Codex-Chat-History-Manager.cmd -Action export-tool
```

macOS：

```bash
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action status
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action backup
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action help
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action profiles
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action save-chatgpt
~/.codex/tools/history-manager-mac/Codex-History-Manager.sh -Action export-tool
```

## 安全说明

- 仓库只包含工具代码和文档。
- Windows 完整备份中的登录和配置文件使用 Windows DPAPI CurrentUser 范围加密。
- macOS 完整备份中的登录和配置文件使用 Keychain 中保存的密钥与 OpenSSL AES-256-CBC 加密。
- 凭证包通常绑定创建它的系统用户。
- 从文件读取 API Key 后，原始文件仍然可能保存明文 Key，需要你自行处理。
- 工具不会强制关闭 Codex Desktop。恢复、切换档案或修改配置前必须手动完全退出 Codex。
- 备份可以恢复文件，但不能让被服务端撤销的 ChatGPT 令牌或已删除的 API Key 重新有效。

## 常见问题

### 提示 Codex 仍在运行怎么办？

请完全退出 Codex Desktop，然后重试。恢复和配置修改要求 Codex 完全关闭。

### 切换登录方式后历史记录不见了？

使用菜单 `[6]` 修复统一历史模式。工具会让 ChatGPT 和 API Key 历史都使用 `openai` Provider，避免历史列表因为 Provider 名称不同而被过滤。

### 自定义 API 一直 reconnect 或响应很慢？

使用菜单 `[N]` 自动测速并切换直连或本机代理模式。修改 `.env` 后，需要完全退出并重新打开 Codex Desktop 才会生效。

### macOS 找不到 node 或 codex 怎么办？

先设置运行时路径：

```bash
export CODEX_NODE="/path/to/node"
export CODEX_CLI="/path/to/codex"
```

然后重新运行脚本。

### 恢复登录后仍然不能用？

对应的 ChatGPT 令牌可能已经过期、注销或被服务器撤销，API Key 也可能已经被服务商删除。恢复文件不能让无效凭证重新有效。

## 作者

- [hunter20041220](https://github.com/hunter20041220)
- [Binpei-Hua](https://github.com/Binpei-Hua)

## 许可证

当前仓库还没有指定开源许可证。如果你希望别人使用、分发或贡献代码，建议补充一个 LICENSE 文件。
