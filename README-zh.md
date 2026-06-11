# Codex 聊天与登录管理器

桌面双击：

```text
Codex-Chat-History-Manager.cmd
```

也可以直接调用：

```powershell
Codex-Chat-History-Manager.cmd -Action status
Codex-Chat-History-Manager.cmd -Action backup
Codex-Chat-History-Manager.cmd -Action help
Codex-Chat-History-Manager.cmd -Action export-tool
```

说明已经内置在菜单 `H` 和 `-Action help` 中，不需要记住本文档位置。

## 推荐流程

1. 平时使用菜单 `2` 创建完整备份。
2. 切换 ChatGPT 账号或 API Key 后，再创建一次完整备份。
3. ChatGPT 登录和 API Key 登录都保持 `model_provider = "openai"`。
4. 自定义 API 地址使用菜单 `7`，不要创建另一个 Provider。
5. 主菜单 `P` 可以保存并切换 ChatGPT 与自定义 API 两个登录档案。
6. 自定义 API 出现反复 reconnect 时，使用主菜单 `N` 切换网络模式。

## 一键切换登录

进入主菜单 `P`：

- `1` 保存或更新当前 ChatGPT 登录档案。
- `2` 首次配置自定义 API 地址与 API Key，并保存 API 档案。
- `3` 一键切换到 ChatGPT 登录。
- `4` 一键切换到自定义 API 登录。
- `5` 查看两个档案及当前正在使用的档案。
- `6` 打开 ChatGPT 凭证导入文件夹。
- `7` 从导入文件夹导入 ChatGPT 凭证并保存为加密档案。

切换前必须完全退出 Codex Desktop。切换操作只恢复加密登录配置，
不会替换或删除本地聊天记录。

配置 API Key 时可以选择：

- 从 Windows 剪贴板读取，适合直接复制服务商提供的 Key。
- 从 `.txt`、`.key`、`.env` 或 `.json` 文件读取。
- 使用隐藏输入手动填写。

`.env` 文件支持 `OPENAI_API_KEY=...`，JSON 文件支持顶层 `apiKey`、
`api_key`、`OPENAI_API_KEY` 或 `key` 字段。读取后只显示 Key 的长度和
末尾 4 位用于核对，不显示完整内容。源文件不会自动删除，其中的 Key
仍是明文，需要自行妥善保管。

## 从凭证文件登录 ChatGPT

固定导入目录：

```text
%USERPROFILE%\.codex\credential-import
```

选择 `[P] -> [6]` 打开目录，把同一个账号的以下文件放进去：

```text
auth.json
.cockpit_codex_auth.json
```

完全退出 Codex Desktop 后选择 `[P] -> [7]`。工具会先校验文件，再备份
当前聊天、登录和配置，导入凭证，清除自定义 API 地址，并将新状态保存成
DPAPI 加密的 ChatGPT 档案。最后可以选择删除导入目录里的明文文件。

这不是账号密码登录，也不会绕过 OpenAI 登录。导入文件必须来自已经合法
登录的 Codex 环境。已过期、已注销或被服务器撤销的令牌无法通过复制恢复。

## 完整备份

完整备份包括：

- 本地聊天与归档会话
- 会话索引和附件
- 本地状态数据库
- `auth.json`
- `.cockpit_codex_auth.json`
- `config.toml`
- `.env`

登录和配置文件使用 Windows DPAPI 加密，备份目录中不保存明文凭证。
该加密包通常只能由当前 Windows 用户在当前电脑上解密。

备份目录：

```text
%USERPROFILE%\.codex\chat-history-backups
```

每份备份都有 SHA-256 文件清单，并在创建后自动执行完整性和解密测试。

## 自定义 API 地址

菜单 `7` 会生成官方推荐的形式：

```toml
model_provider = "openai"
openai_base_url = "https://你的地址/v1"

[desktop]
model_provider = "openai"
```

菜单 `8` 可以从剪贴板、文件或隐藏输入安全读取 API Key。Key 通过标准输入传给：

```text
codex login --with-api-key
```

Key 不会出现在命令行参数和日志中。

## 自定义 API 网络模式

主菜单 `N` 用于处理 API 登录后反复 reconnect、响应慢或断流：

- `1` 自动测速直连和本机代理，并按结果优化。
- `2` 强制直连当前自定义 API 域名，把域名加入 `.env` 的 `NO_PROXY`。
- `3` 强制当前自定义 API 域名走本机代理，从 `NO_PROXY` 移除该域名。
- `4` 查看当前 `.env` 代理配置。

ChatGPT 账号访问官方服务通常需要 `.env` 里的本机代理。自定义 API 则取决于
服务商线路：有时直连快，有时走本机代理更稳。修改后必须完全退出并重新打开
Codex，新的 `.env` 才会被桌面进程读取。

## 恢复

恢复前必须完全退出 Codex Desktop。工具不会强行结束 Codex。

恢复时可以：

- 只恢复聊天记录
- 同时恢复登录状态、API 地址和配置

恢复前会自动创建新的完整安全备份。

ChatGPT 令牌如果已经被服务器撤销，或者 API Key 已被平台删除，旧备份只能恢复文件，不能让失效凭证重新有效。

## 给其他电脑使用

主菜单 `E` 或命令：

```powershell
Codex-Chat-History-Manager.cmd -Action export-tool
```

会导出一个便携安装包到：

```text
%USERPROFILE%\.codex\tool-exports
```

安装包只包含工具脚本和说明，不包含你的聊天记录、登录凭证、API Key、备份或个人配置。
别人解压后双击 `install.cmd`，工具会安装到他自己的
`%USERPROFILE%\.codex\tools\history-manager`，并在他的桌面生成入口。

工具默认服务当前 Windows 用户的 `%USERPROFILE%\.codex`。如果别人使用了自定义
Codex Home，可先设置 `CODEX_HOME` 环境变量再启动工具。
