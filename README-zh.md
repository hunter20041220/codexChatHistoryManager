# Codex 聊天与登录管理器

[English](README.md) | 中文说明

这是一个给 Codex Desktop 使用的本地 Windows/macOS 桌面管理器，用来管理聊天记录、备份恢复、账号登录状态和自定义 API 配置。

> 仓库只包含工具脚本、UI 素材和说明文档，不包含你的聊天记录、登录凭证、API Key、备份或个人 Codex 配置。

## 安装

Windows：

```powershell
.\windows\install.cmd
```

安装后桌面只会生成一个带乌萨奇图标的入口：`Codex-Chat-History-Manager`。

macOS：

```bash
cd mac
chmod +x install.sh Codex-History-Manager.sh Codex-Chat-History-Manager.command
./install.sh
```

安装后打开桌面的 `Codex-Chat-History-Manager.command`。

## 主要功能

- 完整备份、仅聊天备份、备份校验和恢复。
- 保存并切换 ChatGPT 账号登录档案。
- API Key 登录，支持完全新用户的首次登录流程。
- 从 API Key 切回 ChatGPT 账号登录时清理 API 残留。
- 设置自定义 API 地址并检查 `/v1/responses` 网络兼容性。
- 修复统一历史记录模式，让 ChatGPT/API Key 会话一起显示。
- 本地桌面 UI，内置乌萨奇贴图预览素材。

## 目录结构

```text
windows/     Windows 源码、安装器、内部启动器、桌面 UI
mac/         macOS 源码、安装器、内部启动器、桌面 UI
install.cmd  兼容入口，会转发到 windows/install.cmd
```

Windows 会把内部启动器安装到 `%USERPROFILE%\.codex\tools\history-manager\Codex-Chat-History-Manager.cmd`，不会把 `.cmd` 放到桌面。桌面只保留一个 `Codex-Chat-History-Manager` 快捷方式。

## 乌萨奇素材

内置乌萨奇图片来自指定 LINE Store 页面公开展示的贴图预览：

https://store.line.me/stickershop/product/21802595/ja

项目只保留乌萨奇为主体的预览图，素材位于各平台 `ui/assets/line-usagi/`，仅用于本地个人学习和非商业 UI 原型展示。说明见 [ASSET-NOTICE-zh.md](ASSET-NOTICE-zh.md)。

## 作者

- [hunter20041220](https://github.com/hunter20041220)
- [Binpei-Hua](https://github.com/Binpei-Hua)

## 许可证

当前仓库尚未指定开源许可证。
