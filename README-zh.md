# Codex 聊天与登录管理器

[English](README.md) | 中文说明

这是一个 Windows 上的 Codex Desktop 辅助工具，用于备份、恢复和切换 Codex 的本地聊天记录、ChatGPT 登录状态、API Key 登录状态以及自定义 OpenAI 兼容 API 配置。

它适合这些场景：

- 备份 Codex Desktop 本地聊天记录；
- 用 Windows DPAPI 加密备份登录凭证和配置文件；
- 在 ChatGPT 账号登录和自定义 API Key 登录之间一键切换；
- 让 ChatGPT 与 API Key 登录都使用同一个 `openai` Provider，避免历史记录因为 Provider 不一致而看起来“消失”；
- 设置或清除自定义 OpenAI 兼容 API 地址；
- 导出一个便携安装包，给其他 Windows 电脑使用。

> 本项目只包含管理器脚本和说明，不包含你的聊天记录、登录凭证、API Key、备份或个人配置。

## 功能特性

- **完整备份**
  备份聊天记录、归档会话、附件、会话索引、本地状态数据库、`auth.json`、`.cockpit_codex_auth.json`、`config.toml` 和 `.env`。

- **凭证加密**
  登录和配置文件会打包为 `credentials.dpapi.json`，并使用 Windows DPAPI CurrentUser 范围加密。

- **安全恢复**
  可以从已有备份恢复聊天记录，也可以选择同时恢复登录状态和 API 配置。恢复前会自动创建新的完整安全备份。

- **登录档案切换**
  可以保存两个加密登录档案：ChatGPT 账号档案和自定义 API 档案，并在菜单中一键切换。

- **自定义 API 地址**
  工具会写入推荐配置：

  ```toml
  model_provider = "openai"
  openai_base_url = "https://你的地址/v1"

  [desktop]
  model_provider = "openai"
  ```

- **安全输入 API Key**
  支持从剪贴板、`.txt`、`.key`、`.env`、`.json` 文件读取，或隐藏输入手动填写。API Key 会通过标准输入传给 `codex login --with-api-key`。

- **自定义 API 网络模式**
  自定义 API 出现反复 reconnect、响应慢或断流时，可以自动测速直连和本机代理，并调整 `.env` 里的代理设置。

- **便携安装包导出**
  可以导出只包含工具脚本和说明的 ZIP 包，不会包含你的私人数据。

## 运行要求

- Windows
- 已安装 Codex Desktop
- Codex Desktop 自带的 `node.exe` 和 `codex.exe` 可用
- PowerShell

工具默认管理当前 Windows 用户的 Codex Home：

```text
%USERPROFILE%\.codex
```

如果你的 Codex 数据目录不在默认位置，请先设置 `CODEX_HOME` 环境变量。

## 安装

1. 下载或克隆本仓库。
2. 打开项目文件夹。
3. 双击 `install.cmd`。
4. 安装完成后，双击桌面入口使用：

   ```text
   Codex-Chat-History-Manager.cmd
   ```

安装脚本会把工具复制到：

```text
%USERPROFILE%\.codex\tools\history-manager
```

并在桌面创建启动入口。

## 快速开始

### 打开交互菜单

双击桌面上的：

```text
Codex-Chat-History-Manager.cmd
```

或者在命令行运行：

```powershell
Codex-Chat-History-Manager.cmd
```

### 创建完整备份

在主菜单选择：

```text
[2] 创建完整备份
```

也可以运行：

```powershell
Codex-Chat-History-Manager.cmd -Action backup
```

备份会保存到：

```text
%USERPROFILE%\.codex\chat-history-backups
```

### 查看当前状态

```powershell
Codex-Chat-History-Manager.cmd -Action status
```

状态信息包括当前登录方式、正在使用的登录档案、自定义 API 地址、会话数量、备份数量以及 Codex 是否正在运行。

### 查看帮助

```powershell
Codex-Chat-History-Manager.cmd -Action help
```

## 主菜单说明

```text
[1] 查看聊天、登录和 API 配置状态
[2] 创建完整备份（聊天 + DPAPI 加密登录状态）
[3] 仅备份聊天记录
[4] 查看并校验已有备份
[5] 恢复备份

[6] 修复统一历史模式（ChatGPT / API Key 共用）
[7] 设置或清除自定义 API 地址
[8] 安全输入 API Key 并登录
[9] 查看 Codex 登录状态
[N] 自定义 API 网络模式（自动 / 直连 / 代理）
[P] ChatGPT / 自定义 API 一键切换

[A] 用 CLI 打开全部本地历史
[E] 导出便携安装包（给其他电脑使用）
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

## 登录档案一键切换

进入主菜单：

```text
[P] ChatGPT / 自定义 API 一键切换
```

子菜单功能：

```text
[1] 保存或更新当前 ChatGPT 登录档案
[2] 首次配置或更新自定义 API 档案
[3] 一键切换到 ChatGPT 账号
[4] 一键切换到自定义 API
[5] 查看两个登录档案状态
[6] 打开 ChatGPT 凭证导入文件夹
[7] 从导入文件夹登录 ChatGPT 账号
```

注意事项：

- 切换前必须完全退出 Codex Desktop。
- 切换操作只恢复加密登录和配置文件。
- 切换不会替换或删除本地聊天记录。

## 配置自定义 API

推荐使用：

```text
[P] -> [2]
```

工具会依次完成：

1. 读取 API Key；
2. 通过 `codex login --with-api-key` 登录；
3. 设置自定义 API 地址；
4. 保持 Provider 为 `openai`；
5. 保存为 DPAPI 加密的自定义 API 档案。

API Key 支持三种输入方式：

- 从 Windows 剪贴板读取；
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

读取后工具只显示 Key 的长度和末尾 4 位用于核对，不显示完整内容。源文件不会自动删除，其中的 Key 仍是明文，需要你自行妥善保管或删除。

## 从凭证文件导入 ChatGPT 登录

固定导入目录：

```text
%USERPROFILE%\.codex\credential-import
```

选择：

```text
[P] -> [6]
```

打开目录，然后把同一个已登录 Codex 环境中的以下两个文件放进去：

```text
auth.json
.cockpit_codex_auth.json
```

完全退出 Codex Desktop 后选择：

```text
[P] -> [7]
```

工具会先校验文件结构，再创建完整安全备份，导入凭证，清除自定义 API 地址，并把新状态保存为 DPAPI 加密的 ChatGPT 档案。最后可以选择删除导入目录里的明文凭证文件。

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

每份备份都会生成 SHA-256 文件清单。备份创建后，工具会自动执行文件完整性校验；如果包含登录和配置文件，还会执行 DPAPI 解密测试。

DPAPI 加密包通常只能由当前 Windows 用户在当前电脑上解密。

## 恢复备份

恢复前请先：

1. 完全退出 Codex Desktop。
2. 打开管理器。
3. 选择主菜单 `[5]`。
4. 选择要恢复的备份。
5. 选择只恢复聊天记录，或同时恢复登录状态和 API 配置。

恢复前工具会自动创建新的完整安全备份。

如果 ChatGPT 令牌已经被服务器撤销，或者 API Key 已被平台删除，旧备份只能恢复文件，不能让失效凭证重新有效。

## 导出便携安装包

选择主菜单：

```text
[E] 导出便携安装包
```

或运行：

```powershell
Codex-Chat-History-Manager.cmd -Action export-tool
```

导出的 ZIP 包会保存到：

```text
%USERPROFILE%\.codex\tool-exports
```

安装包只包含：

- `Codex-History-Manager.ps1`
- `codex-history-core.mjs`
- 说明文档
- 安装脚本

不会包含你的聊天记录、登录凭证、API Key、备份或个人配置。

别人解压后双击 `install.cmd`，工具会安装到他自己的：

```text
%USERPROFILE%\.codex\tools\history-manager
```

并在他的桌面生成入口。

## 命令行用法

```powershell
Codex-Chat-History-Manager.cmd
Codex-Chat-History-Manager.cmd -Action status
Codex-Chat-History-Manager.cmd -Action backup
Codex-Chat-History-Manager.cmd -Action help
Codex-Chat-History-Manager.cmd -Action profiles
Codex-Chat-History-Manager.cmd -Action save-chatgpt
Codex-Chat-History-Manager.cmd -Action export-tool
```

也可以直接调用 PowerShell 脚本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.codex\tools\history-manager\Codex-History-Manager.ps1" -Action status
```

## 安全说明

- 仓库只包含工具代码和文档。
- 完整备份中的登录和配置文件使用 Windows DPAPI CurrentUser 范围加密。
- DPAPI 保护通常绑定当前 Windows 用户和当前电脑。
- 从文件读取 API Key 后，原始文件仍然可能保存明文 Key，需要你自行处理。
- 工具不会强制关闭 Codex Desktop。恢复、切换档案或修改配置前必须手动完全退出 Codex。
- 备份可以恢复文件，但不能让被服务端撤销的 ChatGPT 令牌或已删除的 API Key 重新有效。

## 常见问题

### 提示 Codex 仍在运行怎么办？

请从托盘或任务栏完全退出 Codex Desktop，然后重试。恢复和配置修改要求 Codex 完全关闭。

### 切换登录方式后历史记录不见了？

使用菜单 `[6]` 修复统一历史模式。工具会让 ChatGPT 和 API Key 历史都使用 `openai` Provider，避免历史列表因为 Provider 名称不同而被过滤。

### 自定义 API 一直 reconnect 或响应很慢？

使用菜单 `[N]` 自动测速并切换直连或本机代理模式。修改 `.env` 后，需要完全退出并重新打开 Codex Desktop 才会生效。

### 恢复登录后仍然不能用？

对应的 ChatGPT 令牌可能已经过期、注销或被服务器撤销，API Key 也可能已经被服务商删除。恢复文件不能让无效凭证重新有效。

## 许可证

当前仓库还没有指定开源许可证。如果你希望别人使用、分发或贡献代码，建议补充一个 LICENSE 文件。
