# macOS 版本

安装：

```bash
chmod +x install.sh Codex-History-Manager.sh Codex-Chat-History-Manager-UI.command
./install.sh
```

启动：

- 桌面 UI：`Codex-Chat-History-Manager-UI.command`
- 经典命令行：`Codex-Chat-History-Manager.command`

源码结构：

```text
Codex-History-Manager.sh    macOS 后端和命令行入口
codex-history-core.mjs      共用备份/历史核心
ui/                         桌面 UI 源码
install.sh                  安装器
```

如果 UI 找不到 `node`，请先完整打开一次 Codex Desktop，或安装 Node.js 22+。

UI 会把指定 LINE Store 页面的乌萨奇贴图预览导入到本机 `ui/private-assets/`。这些官方图片不会进入 GitHub 或便携导出包；导入失败时会继续使用 `ui/assets/` 中的原创 SVG 占位图。
