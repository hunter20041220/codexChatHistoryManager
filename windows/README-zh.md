# Windows 版本

安装：

```powershell
.\install.cmd
```

启动：

- 桌面 UI：带乌萨奇风格图标的 `Codex-Chat-History-Manager-UI.lnk`
- 备用 UI 命令：`Codex-Chat-History-Manager-UI.cmd`
- 经典命令行：`Codex-Chat-History-Manager.cmd`

安装器会尽量把 Codex Desktop 自带的 `node.exe` 复制到 `%USERPROFILE%\.codex\tools\history-manager\runtime\node.exe`，通常不需要用户手动安装 Node。

源码结构：

```text
Codex-History-Manager.ps1   Windows 后端和命令行入口
codex-history-core.mjs      共用备份/历史核心
ui/                         桌面 UI 源码
install.ps1                 安装器
```

日常使用推荐打开桌面 UI；命令行入口保留给排查和高级操作。

UI 会把指定 LINE Store 页面的乌萨奇贴图预览导入到本机 `ui/private-assets/`。这些官方图片不会进入 GitHub 或便携导出包；导入失败时会继续使用 `ui/assets/` 中的原创 SVG 占位图。Windows 桌面快捷方式仍使用 `ui/assets/app-icon.ico`。
