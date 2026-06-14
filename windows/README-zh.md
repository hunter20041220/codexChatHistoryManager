# Windows 版本

安装：

```powershell
.\install.cmd
```

安装后桌面只会有一个带乌萨奇图标的快捷方式：

```text
Codex-Chat-History-Manager
```

内部启动器会安装到：

```text
%USERPROFILE%\.codex\tools\history-manager\Codex-Chat-History-Manager.cmd
```

它只保留在工具安装目录里，不会放到桌面。

源码结构：

```text
Codex-History-Manager.ps1      Windows 后端和命令行操作
codex-history-core.mjs         共用备份/历史核心
Codex-Chat-History-Manager.cmd 内部桌面 UI 启动器
ui/                            桌面 UI 源码和内置乌萨奇素材
install.ps1                    安装器
```
