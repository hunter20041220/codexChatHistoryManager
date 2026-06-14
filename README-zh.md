# Codex 聊天与登录管理器

[English](README.md) | 中文说明

这是一个给 Codex Desktop 使用的 Windows/macOS 桌面工具。现在带有原创乌萨奇风格多表情贴纸桌面 UI，用来管理本地聊天备份、备份恢复、ChatGPT 账号档案切换、自定义 API Key 登录、自定义 API 网络检测，以及统一历史记录修复。

> 仓库只包含工具脚本和说明，不包含你的聊天记录、登录凭证、API Key、备份或个人配置。

## 桌面 UI

推荐使用桌面 UI：

- Windows：运行 `windows/install.cmd`，然后打开桌面的 `Codex-Chat-History-Manager-UI.cmd`。
- macOS：运行 `mac/install.sh`，然后打开桌面的 `Codex-Chat-History-Manager-UI.command`。

原来的命令行启动器仍会安装，方便高级排查和备用。

UI 里的角色贴纸是为本项目绘制的原创乌萨奇风格 SVG，没有直接打包搬运官方 Chiikawa/Usagi 图片。

## 目录结构

```text
windows/   Windows 源码、安装器、命令行启动器、桌面 UI 源码
mac/       macOS 源码、安装器、命令行启动器、桌面 UI 源码
install.cmd  兼容旧用法，转发到 windows/install.cmd
```

## 主要功能

- 创建完整备份或仅聊天记录备份。
- 校验和恢复备份，可选择恢复加密登录状态。
- 在已保存的 ChatGPT 账号档案和自定义 API 档案之间切换。
- 使用 API Key 登录，也支持全新用户首次登录流程。
- 从自定义 API 切回 ChatGPT 账号时清理 API 残留。
- 设置或清除自定义 API 地址。
- 检查 `/v1/responses` 兼容性和自定义 API 网络模式。
- 修复统一历史模式，让 ChatGPT/API Key 会话一起显示。

## UI 调研

我调研了可用 Codex skill 和桌面 UI 项目：

| 方案 | Stars | 适配情况 |
| --- | ---: | --- |
| Electron | 121,622 | 跨平台桌面 UI 生态最成熟 |
| Tauri | 107,852 | 很强的跨平台方案 |
| NW.js | 41,184 | 成熟，但本项目不优先 |
| Neutralino | 8,541 | 轻量，但生态较小 |
| OpenAI `winui-app` skill | openai/skills: 22,118 | 已安装到本机；偏 Windows 原生指导 |

本项目的 UI 使用无 npm 依赖的本地桌面 Web 壳，通过 Node 启动并调用现有 Windows/macOS 脚本。这样既有桌面 UI，又不要求用户额外安装 npm 包。

## 作者

- [hunter20041220](https://github.com/hunter20041220)
- [Binpei-Hua](https://github.com/Binpei-Hua)

## 许可证

当前仓库还没有指定开源许可证。
