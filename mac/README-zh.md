# Codex 聊天与登录管理器

[English](README.md) | 中文说明

这是一个给 Codex Desktop 用的小工具，支持备份本地聊天、恢复历史记录，并在 ChatGPT 账号登录和自定义 API Key 登录之间切换，尽量避免切换后历史列表丢失或配置残留。

> 仓库只包含工具脚本和说明，不包含你的聊天记录、登录凭证、API Key、备份或个人配置。

## 版本

| 平台 | 目录 | 安装器 | 凭证保护 |
| --- | --- | --- | --- |
| Windows | `windows/` | `install.cmd` | Windows DPAPI CurrentUser |
| macOS | `mac/` | `install.sh` | macOS Keychain + OpenSSL |

根目录下的 Windows 文件继续保留，兼容旧链接和旧安装方式。

## 安装

Windows：

1. 先安装并打开一次 Codex Desktop。
2. 打开 `windows/` 文件夹。
3. 双击 `install.cmd`。
4. 使用桌面快捷方式 `Codex-Chat-History-Manager.cmd`。

macOS：

```bash
cd mac
chmod +x install.sh Codex-History-Manager.sh
./install.sh
```

然后打开桌面的 `Codex-Chat-History-Manager.command`。

## 常用功能

- `[2]` 创建完整备份。
- `[5]` 恢复备份。
- `[6]` 修复切换登录方式后历史记录不见的问题。
- `[7]` 设置或清除自定义 API 地址。
- `[8]` 使用 API Key 登录。
- `[N] -> [5]` 检查自定义 API 的 `/v1/responses` 兼容性。
- `[P] -> [3]` 切回已保存的 ChatGPT 账号档案。
- `[P] -> [6]` 清理 API 残留并启动 ChatGPT 账号登录。

常用命令：

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

## 从 API 切回 ChatGPT 账号

请先完全退出 Codex Desktop。

- 如果之前保存过 ChatGPT 账号档案，用 `[P] -> [3]`。
- 如果没有保存过 ChatGPT 账号档案，用 `[P] -> [6]`。

增强清理会移除 `openai_base_url`、`.env` 里的 OpenAI API 变量、`NO_PROXY` 里的自定义 API 域名，以及 API Key 登录凭证文件。

## 常见问题

- 提示找不到 `node.exe` 或 `codex.exe`：先完整打开一次 Codex Desktop，再重新安装本工具；仍失败时设置 `CODEX_NODE` 或 `CODEX_CLI`。
- 自定义 API 在 `/v1/responses` 返回 `503`：通常是服务商或上游模型不可用，用 `[N] -> [5]` 检查。
- 恢复时提示 Codex 正在运行：请从托盘或菜单完全退出 Codex Desktop。
- 恢复登录后仍不能用：令牌或 API Key 可能已过期、注销、被撤销或删除，恢复文件不能让失效凭证重新有效。

## 作者

- [hunter20041220](https://github.com/hunter20041220)
- [Binpei-Hua](https://github.com/Binpei-Hua)

## 许可证

当前仓库还没有指定开源许可证。
