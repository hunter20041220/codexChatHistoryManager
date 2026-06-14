# macOS 版本

安装：

```bash
chmod +x install.sh Codex-History-Manager.sh Codex-Chat-History-Manager.command
./install.sh
```

安装后打开桌面的：

```text
Codex-Chat-History-Manager.command
```

内部启动器会安装到：

```text
~/.codex/tools/history-manager-mac/Codex-Chat-History-Manager.command
```

源码结构：

```text
Codex-History-Manager.sh           macOS 后端和命令行操作
codex-history-core.mjs             共用备份/历史核心
Codex-Chat-History-Manager.command 内部桌面 UI 启动器
ui/                                桌面 UI 源码和内置乌萨奇素材
install.sh                         安装器
```

如果 UI 找不到 `node`，请先完整打开一次 Codex Desktop，或者安装 Node.js 22+。
