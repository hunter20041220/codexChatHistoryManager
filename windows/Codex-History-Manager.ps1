param(
    [string]$Action = "menu",
    [string]$Argument = "",
    [switch]$RestoreLogin
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
try {
    $Host.UI.RawUI.WindowTitle = "Codex 聊天与登录管理器"
    $Host.UI.RawUI.ForegroundColor = "Gray"
    $Host.UI.RawUI.BackgroundColor = "Black"
}
catch {
    # Some non-interactive hosts do not expose window properties.
}

$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }
$toolDirectory = Join-Path $codexHome "tools\history-manager"
$coreScript = Join-Path $toolDirectory "codex-history-core.mjs"
$backupDirectory = Join-Path $codexHome "chat-history-backups"
$profileDirectory = Join-Path $codexHome "login-profiles"
$credentialImportDirectory = Join-Path $codexHome "credential-import"
$credentialPackageName = "credentials.dpapi.json"
$credentialFiles = @("auth.json", ".cockpit_codex_auth.json", "config.toml", ".env")
$dpapiEntropy = [Text.Encoding]::UTF8.GetBytes("Codex-History-Manager-v1")

Add-Type -AssemblyName System.Security

function Write-PortableInstallFiles {
    param([string]$PackageDirectory)

    $installScript = @'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
pause
'@
    [IO.File]::WriteAllText((Join-Path $PackageDirectory "install.cmd"), $installScript, [Text.ASCIIEncoding]::new())

    $powerShellInstallScript = @'
$ErrorActionPreference = "Stop"
$source = $PSScriptRoot
$target = Join-Path $env:USERPROFILE ".codex\tools\history-manager"
New-Item -ItemType Directory -Force -Path $target | Out-Null

Copy-Item -LiteralPath (Join-Path $source "Codex-History-Manager.ps1") -Destination $target -Force
Copy-Item -LiteralPath (Join-Path $source "codex-history-core.mjs") -Destination $target -Force
Copy-Item -LiteralPath (Join-Path $source "README-zh.md") -Destination (Join-Path $target "使用说明.md") -Force
if (Test-Path -LiteralPath (Join-Path $source "ui")) {
    Copy-Item -LiteralPath (Join-Path $source "ui") -Destination $target -Recurse -Force
    Remove-Item -LiteralPath (Join-Path $target "ui\private-assets") -Recurse -Force -ErrorAction SilentlyContinue
}

function Test-NodeRuntime {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    try {
        & $Path --disable-warning=ExperimentalWarning -e "import('node:sqlite').then(()=>process.exit(0)).catch(()=>process.exit(1))" 2>$null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Install-NodeRuntime {
    $runtimeDirectory = Join-Path $target "runtime"
    $targetNode = Join-Path $runtimeDirectory "node.exe"
    $candidates = [Collections.Generic.List[string]]::new()
    $searchRoots = [Collections.Generic.List[string]]::new()

    function Add-Candidate {
        param([string]$Path)
        if (-not [string]::IsNullOrWhiteSpace($Path) -and -not $candidates.Contains($Path)) {
            $candidates.Add($Path)
        }
    }

    function Add-SearchRoot {
        param([string]$Path)
        if (-not [string]::IsNullOrWhiteSpace($Path) -and
            (Test-Path -LiteralPath $Path -PathType Container) -and
            -not $searchRoots.Contains($Path)) {
            $searchRoots.Add($Path)
        }
    }

    Add-Candidate -Path $targetNode
    Add-Candidate -Path $env:CODEX_NODE
    Add-Candidate -Path (Join-Path $source "runtime\node.exe")

    $codexCommand = Get-Command "codex.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($codexCommand -and $codexCommand.Source) {
        $codexDirectory = Split-Path -Parent $codexCommand.Source
        Add-SearchRoot -Path $codexDirectory
        Add-SearchRoot -Path (Join-Path $codexDirectory "cua_node")
        Add-SearchRoot -Path (Join-Path $codexDirectory "cua_node\bin")
    }

    foreach ($root in @(
            (Join-Path $env:LOCALAPPDATA "OpenAI\Codex"),
            (Join-Path $env:LOCALAPPDATA "OpenAI"),
            (Join-Path $env:LOCALAPPDATA "Programs\OpenAI Codex"),
            (Join-Path $env:LOCALAPPDATA "Programs\Codex"),
            (Join-Path $env:LOCALAPPDATA "Programs\OpenAI\Codex"),
            (Join-Path $env:APPDATA "OpenAI\Codex"),
            (Join-Path $env:ProgramFiles "OpenAI\Codex"),
            (Join-Path ${env:ProgramFiles(x86)} "OpenAI\Codex")
        )) {
        Add-SearchRoot -Path $root
    }

    $windowsApps = Join-Path $env:ProgramFiles "WindowsApps"
    if (Test-Path -LiteralPath $windowsApps -PathType Container) {
        Get-ChildItem -LiteralPath $windowsApps -Directory -Filter "OpenAI.Codex_*" -ErrorAction SilentlyContinue |
            ForEach-Object {
                Add-SearchRoot -Path $_.FullName
                Add-SearchRoot -Path (Join-Path $_.FullName "app\resources")
                Add-SearchRoot -Path (Join-Path $_.FullName "app\resources\cua_node")
                Add-SearchRoot -Path (Join-Path $_.FullName "app\resources\cua_node\bin")
            }
    }

    foreach ($root in $searchRoots) {
        Add-Candidate -Path (Join-Path $root "node.exe")
        Add-Candidate -Path (Join-Path $root "bin\node.exe")
        Add-Candidate -Path (Join-Path $root "resources\node.exe")
        Add-Candidate -Path (Join-Path $root "resources\cua_node\bin\node.exe")
        Add-Candidate -Path (Join-Path $root "app\resources\node.exe")
        Add-Candidate -Path (Join-Path $root "app\resources\cua_node\bin\node.exe")
    }

    foreach ($root in $searchRoots) {
        if (Test-Path -LiteralPath $root) {
            Get-ChildItem -LiteralPath $root -Filter "node.exe" -File -Recurse -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                ForEach-Object { Add-Candidate -Path $_.FullName }
        }
    }

    $nodeCommand = Get-Command "node.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($nodeCommand -and $nodeCommand.Source) {
        Add-Candidate -Path $nodeCommand.Source
    }

    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            continue
        }
        try {
            $resolvedCandidate = (Resolve-Path -LiteralPath $candidate).Path
            if ((Test-Path -LiteralPath $targetNode -PathType Leaf) -and
                ((Resolve-Path -LiteralPath $targetNode).Path -eq $resolvedCandidate) -and
                (Test-NodeRuntime -Path $targetNode)) {
                Write-Host "Node runtime: $targetNode" -ForegroundColor DarkGray
                return
            }
            New-Item -ItemType Directory -Force -Path $runtimeDirectory | Out-Null
            Copy-Item -LiteralPath $resolvedCandidate -Destination $targetNode -Force -ErrorAction Stop
            if (Test-NodeRuntime -Path $targetNode) {
                Write-Host "Node runtime: $targetNode" -ForegroundColor DarkGray
                return
            }
            Remove-Item -LiteralPath $targetNode -Force -ErrorAction SilentlyContinue
        }
        catch {
            continue
        }
    }

    Write-Host "Warning: no usable Node runtime was copied. The launcher will try Codex Desktop or system Node at startup." -ForegroundColor Yellow
}

Install-NodeRuntime

$importScript = Join-Path $target "ui\import-line-usagi.mjs"
$installedNode = Join-Path $target "runtime\node.exe"
if ((Test-Path -LiteralPath $importScript -PathType Leaf) -and (Test-Path -LiteralPath $installedNode -PathType Leaf)) {
    try {
        Write-Host "Importing local Usagi sticker previews from approved LINE page..." -ForegroundColor DarkGray
        $env:USAGI_IMPORT_TIMEOUT_MS = "15000"
        & $installedNode $importScript 2>$null | Out-Null
        Remove-Item Env:\USAGI_IMPORT_TIMEOUT_MS -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Usagi stickers imported to local private assets." -ForegroundColor Green
        }
        else {
            Write-Host "Warning: Usagi sticker import failed. You can retry from the desktop UI." -ForegroundColor Yellow
        }
    }
    catch {
        Remove-Item Env:\USAGI_IMPORT_TIMEOUT_MS -ErrorAction SilentlyContinue
        Write-Host "Warning: Usagi sticker import failed. You can retry from the desktop UI." -ForegroundColor Yellow
    }
}

$desktopDirectory = [Environment]::GetFolderPath("Desktop")
if ([string]::IsNullOrWhiteSpace($desktopDirectory)) {
    $desktopDirectory = Join-Path $env:USERPROFILE "Desktop"
}
New-Item -ItemType Directory -Force -Path $desktopDirectory | Out-Null
$desktopEntry = Join-Path $desktopDirectory "Codex-Chat-History-Manager.cmd"
$desktopScript = @"
@echo off
cd /d "%USERPROFILE%\.codex\tools\history-manager"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.codex\tools\history-manager\Codex-History-Manager.ps1" %*
if errorlevel 1 pause
"@
[IO.File]::WriteAllText($desktopEntry, $desktopScript, [Text.ASCIIEncoding]::new())

$desktopUiEntry = Join-Path $desktopDirectory "Codex-Chat-History-Manager-UI.cmd"
$desktopUiScript = @"
@echo off
cd /d "%USERPROFILE%\.codex\tools\history-manager"
set "NODE_EXE=%USERPROFILE%\.codex\tools\history-manager\runtime\node.exe"
if exist "%NODE_EXE%" (
  "%NODE_EXE%" "%USERPROFILE%\.codex\tools\history-manager\ui\server.mjs"
) else (
  node "%USERPROFILE%\.codex\tools\history-manager\ui\server.mjs"
)
if errorlevel 1 pause
"@
[IO.File]::WriteAllText($desktopUiEntry, $desktopUiScript, [Text.ASCIIEncoding]::new())

$iconPath = Join-Path $target "ui\assets\app-icon.ico"
if (Test-Path -LiteralPath $iconPath) {
    $shortcutPath = Join-Path $desktopDirectory "Codex-Chat-History-Manager-UI.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $desktopUiEntry
    $shortcut.WorkingDirectory = $target
    $shortcut.IconLocation = $iconPath
    $shortcut.Description = "Codex Chat History Manager Desktop UI"
    $shortcut.Save()
}

Write-Host ""
Write-Host "Installed to: $target" -ForegroundColor Green
Write-Host "Desktop shortcut: $desktopEntry" -ForegroundColor Green
Write-Host "Desktop UI shortcut: $desktopUiEntry" -ForegroundColor Green
if (Test-Path -LiteralPath (Join-Path $desktopDirectory "Codex-Chat-History-Manager-UI.lnk")) {
    Write-Host "Desktop UI icon shortcut: $(Join-Path $desktopDirectory "Codex-Chat-History-Manager-UI.lnk")" -ForegroundColor Green
}
Write-Host ""
'@
    [IO.File]::WriteAllText((Join-Path $PackageDirectory "install.ps1"), $powerShellInstallScript, [Text.UTF8Encoding]::new($true))

    $readme = @"
# Codex 聊天与登录管理器便携包

安装：

1. 确认本机已经安装 Codex Desktop。
2. 解压本压缩包。
3. 双击 `install.cmd`。
4. 双击桌面的 `Codex-Chat-History-Manager-UI.lnk` 使用桌面 UI；也可用 `Codex-Chat-History-Manager.cmd` 打开命令行版本。

本包只包含管理器脚本和说明，不包含导出者的聊天记录、登录凭证、API Key、备份或个人配置。

工具默认服务当前 Windows 用户的 `%USERPROFILE%\.codex`。如果需要指定其他 Codex Home，可先设置环境变量 `CODEX_HOME`。
"@
    [IO.File]::WriteAllText((Join-Path $PackageDirectory "README.md"), $readme, [Text.UTF8Encoding]::new($true))
}

function Export-PortableToolPackage {
    $exportRoot = Join-Path $codexHome "tool-exports"
    New-Item -ItemType Directory -Force -Path $exportRoot | Out-Null
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $packageDirectory = Join-Path $exportRoot "Codex-Chat-History-Manager-$stamp"
    New-Item -ItemType Directory -Force -Path $packageDirectory | Out-Null

    Copy-Item -LiteralPath (Join-Path $toolDirectory "Codex-History-Manager.ps1") -Destination (Join-Path $packageDirectory "Codex-History-Manager.ps1") -Force
    Copy-Item -LiteralPath (Join-Path $toolDirectory "codex-history-core.mjs") -Destination (Join-Path $packageDirectory "codex-history-core.mjs") -Force
    Copy-Item -LiteralPath (Join-Path $toolDirectory "使用说明.md") -Destination (Join-Path $packageDirectory "README-zh.md") -Force
    if (Test-Path -LiteralPath (Join-Path $toolDirectory "ui")) {
        Copy-Item -LiteralPath (Join-Path $toolDirectory "ui") -Destination $packageDirectory -Recurse -Force
        Remove-Item -LiteralPath (Join-Path $packageDirectory "ui\private-assets") -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-PortableInstallFiles -PackageDirectory $packageDirectory

    $zipPath = "$packageDirectory.zip"
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    $packageFiles = @(
        "Codex-History-Manager.ps1",
        "codex-history-core.mjs",
        "README-zh.md",
        "install.cmd",
        "install.ps1",
        "README.md"
    ) | ForEach-Object { Join-Path $packageDirectory $_ }
    if (Test-Path -LiteralPath (Join-Path $packageDirectory "ui")) {
        $packageFiles += Join-Path $packageDirectory "ui"
    }
    Compress-Archive -LiteralPath $packageFiles -DestinationPath $zipPath -Force
    if (-not (Test-Path -LiteralPath $zipPath)) {
        throw "便携安装包压缩失败：$zipPath"
    }
    Write-Host ""
    Write-Host "  [完成] 已导出便携安装包。" -ForegroundColor Green
    Write-Host ("  ZIP：{0}" -f $zipPath)
    Write-Host "  该包不包含你的聊天记录、登录凭证、API Key 或备份。" -ForegroundColor DarkGray
    Start-Process explorer.exe -ArgumentList $exportRoot
}

function Test-NodeRuntime {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    try {
        & $Path --disable-warning=ExperimentalWarning -e "import('node:sqlite').then(()=>process.exit(0)).catch(()=>process.exit(1))" 2>$null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Copy-NodeRuntime {
    param([string]$SourcePath)

    if ([string]::IsNullOrWhiteSpace($SourcePath) -or -not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        return $null
    }

    $runtimeDirectory = Join-Path $toolDirectory "runtime"
    $targetNode = Join-Path $runtimeDirectory "node.exe"
    try {
        $resolvedSource = (Resolve-Path -LiteralPath $SourcePath).Path
        if ((Test-Path -LiteralPath $targetNode -PathType Leaf) -and
            ((Resolve-Path -LiteralPath $targetNode).Path -eq $resolvedSource) -and
            (Test-NodeRuntime -Path $targetNode)) {
            return (Resolve-Path -LiteralPath $targetNode).Path
        }
        New-Item -ItemType Directory -Force -Path $runtimeDirectory | Out-Null
        Copy-Item -LiteralPath $resolvedSource -Destination $targetNode -Force -ErrorAction Stop
        if (Test-NodeRuntime -Path $targetNode) {
            return (Resolve-Path -LiteralPath $targetNode).Path
        }
        Remove-Item -LiteralPath $targetNode -Force -ErrorAction SilentlyContinue
    }
    catch {
        return $null
    }
    return $null
}

function Find-CodexRuntime {
    param([string]$FileName)

    $override = if ($FileName -eq "node.exe") { $env:CODEX_NODE } else { $env:CODEX_CLI }
    $candidates = [Collections.Generic.List[string]]::new()
    $searchRoots = [Collections.Generic.List[string]]::new()

    function Add-Candidate {
        param([string]$Path)
        if (-not [string]::IsNullOrWhiteSpace($Path) -and -not $candidates.Contains($Path)) {
            $candidates.Add($Path)
        }
    }

    function Add-SearchRoot {
        param([string]$Path)
        if (-not [string]::IsNullOrWhiteSpace($Path) -and
            (Test-Path -LiteralPath $Path -PathType Container) -and
            -not $searchRoots.Contains($Path)) {
            $searchRoots.Add($Path)
        }
    }

    if ($override) {
        Add-Candidate -Path $override
    }

    if ($FileName -eq "node.exe") {
        Add-Candidate -Path (Join-Path $toolDirectory "runtime\node.exe")
        Add-Candidate -Path (Join-Path $PSScriptRoot "runtime\node.exe")
    }

    $codexCommand = Get-Command "codex.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($codexCommand -and $codexCommand.Source) {
        $codexDirectory = Split-Path -Parent $codexCommand.Source
        if ($FileName -eq "codex.exe") {
            Add-Candidate -Path $codexCommand.Source
        }
        Add-SearchRoot -Path $codexDirectory
        Add-SearchRoot -Path (Join-Path $codexDirectory "cua_node")
        Add-SearchRoot -Path (Join-Path $codexDirectory "cua_node\bin")
    }

    foreach ($root in @(
            $toolDirectory,
            $PSScriptRoot,
            (Join-Path $env:LOCALAPPDATA "OpenAI\Codex"),
            (Join-Path $env:LOCALAPPDATA "OpenAI"),
            (Join-Path $env:LOCALAPPDATA "Programs\OpenAI Codex"),
            (Join-Path $env:LOCALAPPDATA "Programs\Codex"),
            (Join-Path $env:LOCALAPPDATA "Programs\OpenAI\Codex"),
            (Join-Path $env:APPDATA "OpenAI\Codex"),
            (Join-Path $env:ProgramFiles "OpenAI\Codex"),
            (Join-Path ${env:ProgramFiles(x86)} "OpenAI\Codex")
        )) {
        Add-SearchRoot -Path $root
    }

    $windowsApps = Join-Path $env:ProgramFiles "WindowsApps"
    if (Test-Path -LiteralPath $windowsApps -PathType Container) {
        Get-ChildItem -LiteralPath $windowsApps -Directory -Filter "OpenAI.Codex_*" -ErrorAction SilentlyContinue |
            ForEach-Object {
                Add-SearchRoot -Path $_.FullName
                Add-SearchRoot -Path (Join-Path $_.FullName "app\resources")
                Add-SearchRoot -Path (Join-Path $_.FullName "app\resources\cua_node")
                Add-SearchRoot -Path (Join-Path $_.FullName "app\resources\cua_node\bin")
            }
    }

    foreach ($root in $searchRoots) {
        Add-Candidate -Path (Join-Path $root $FileName)
        Add-Candidate -Path (Join-Path $root "bin\$FileName")
        Add-Candidate -Path (Join-Path $root "resources\$FileName")
        Add-Candidate -Path (Join-Path $root "resources\cua_node\bin\$FileName")
        Add-Candidate -Path (Join-Path $root "app\resources\$FileName")
        Add-Candidate -Path (Join-Path $root "app\resources\cua_node\bin\$FileName")
    }

    foreach ($root in $searchRoots) {
        if (Test-Path -LiteralPath $root) {
            Get-ChildItem -LiteralPath $root -Filter $FileName -File -Recurse -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                ForEach-Object { Add-Candidate -Path $_.FullName }
        }
    }

    if ($FileName -eq "node.exe") {
        $nodeCommand = Get-Command "node.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($nodeCommand -and $nodeCommand.Source) {
            Add-Candidate -Path $nodeCommand.Source
        }
    }

    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            continue
        }
        if ($FileName -eq "node.exe") {
            if (Test-NodeRuntime -Path $candidate) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
            $copiedNode = Copy-NodeRuntime -SourcePath $candidate
            if ($copiedNode) {
                return $copiedNode
            }
            continue
        }
        return (Resolve-Path -LiteralPath $candidate).Path
    }

    $hint = if ($FileName -eq "node.exe") {
        "请先完整打开一次 Codex Desktop，然后重新运行 install.cmd；仍失败时请安装 Node.js 22+ 或 24+，或设置 CODEX_NODE 指向 node.exe。"
    } else {
        "请先完整打开一次 Codex Desktop；如果仍失败，请设置环境变量 CODEX_CLI 指向 Codex 的 codex.exe。"
    }
    throw "未找到可用的 $FileName。$hint"
}

$nodeExe = Find-CodexRuntime -FileName "node.exe"
$codexExe = Find-CodexRuntime -FileName "codex.exe"

function Invoke-Core {
    param(
        [string]$CoreAction,
        [string]$Argument = ""
    )

    $arguments = @("--disable-warning=ExperimentalWarning", $coreScript, $CoreAction)
    if ($Argument) {
        $arguments += $Argument
    }
    $json = & $nodeExe @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "核心操作失败：$CoreAction"
    }
    $parsed = ($json -join "`n") | ConvertFrom-Json
    if ($parsed -is [Array]) {
        foreach ($item in $parsed) {
            Write-Output $item
        }
        return
    }
    return $parsed
}

function Write-UiJson {
    param($Value)

    $Value | ConvertTo-Json -Depth 20
}

function Read-UiSecretFromStdIn {
    $inputText = [Console]::In.ReadToEnd()
    if ($null -eq $inputText) {
        return ""
    }
    return $inputText.Trim()
}

function Get-Sha256 {
    param([byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Test-CodexRunning {
    return @(
        Get-Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ProcessName -eq "Codex" -or
                ($_.ProcessName -eq "codex" -and $_.Path -like "*OpenAI\Codex*")
            }
    ).Count -gt 0
}

function Assert-CodexClosed {
    if (Test-CodexRunning) {
        throw "Codex 当前仍在运行。请先从托盘完全退出 Codex，再执行恢复或配置修改；本工具不会强行结束 Codex。"
    }
}

function Get-AuthMode {
    $authPath = Join-Path $codexHome "auth.json"
    if (-not (Test-Path -LiteralPath $authPath)) {
        return "未找到登录凭证"
    }
    try {
        $auth = Get-Content -LiteralPath $authPath -Raw -Encoding UTF8 | ConvertFrom-Json
        switch ("$($auth.auth_mode)") {
            "chatgpt" { return "ChatGPT 账号登录" }
            "apikey" { return "OpenAI API Key" }
            "api_key" { return "OpenAI API Key" }
            default { return $(if ($auth.auth_mode) { "$($auth.auth_mode)" } else { "已存在凭证" }) }
        }
    }
    catch {
        return "凭证存在，但无法读取登录类型"
    }
}

function Get-CurrentOpenAiBaseUrl {
    $configPath = Join-Path $codexHome "config.toml"
    if (-not (Test-Path -LiteralPath $configPath)) {
        return $null
    }
    $match = Select-String -LiteralPath $configPath -Pattern '^\s*openai_base_url\s*=\s*"(.+?)"\s*$' | Select-Object -First 1
    if (-not $match) {
        return $null
    }
    return $match.Matches[0].Groups[1].Value.Trim()
}

function Get-CurrentModelName {
    $configPath = Join-Path $codexHome "config.toml"
    if (-not (Test-Path -LiteralPath $configPath)) {
        return $null
    }
    $section = ""
    foreach ($line in Get-Content -LiteralPath $configPath -Encoding UTF8) {
        if ($line -match '^\s*\[([^\]]+)\]\s*$') {
            $section = $Matches[1]
            continue
        }
        if (-not $section -and $line -match '^\s*model\s*=\s*"(.+?)"\s*$') {
            return $Matches[1].Trim()
        }
    }
    return $null
}

function Get-EnvFileMap {
    $envPath = Join-Path $codexHome ".env"
    $map = [ordered]@{}
    if (Test-Path -LiteralPath $envPath) {
        foreach ($line in Get-Content -LiteralPath $envPath -Encoding UTF8) {
            if ($line -match '^\s*([^#=\s]+)\s*=\s*(.*?)\s*$') {
                $value = $Matches[2].Trim()
                if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                    $value = $value.Substring(1, $value.Length - 2)
                }
                $map[$Matches[1]] = $value
            }
        }
    }
    return $map
}

function Save-EnvFileMap {
    param($Map)

    $envPath = Join-Path $codexHome ".env"
    $lines = foreach ($key in $Map.Keys) {
        $value = "$($Map[$key])".Replace("\", "\\").Replace('"', '\"')
        "$key=`"$value`""
    }
    [IO.File]::WriteAllText($envPath, (($lines -join "`r`n") + "`r`n"), [Text.UTF8Encoding]::new($false))
}

function Add-NoProxyHost {
    param([string]$HostName)

    if ([string]::IsNullOrWhiteSpace($HostName)) {
        return
    }
    $map = Get-EnvFileMap
    $existing = @()
    foreach ($name in @("NO_PROXY", "no_proxy")) {
        if ($map.Contains($name) -and $map[$name]) {
            $existing += $map[$name] -split ','
        }
    }
    $items = [Collections.Generic.List[string]]::new()
    foreach ($item in @($existing + @("localhost", "127.0.0.1", "::1", $HostName))) {
        $trimmed = "$item".Trim()
        if ($trimmed -and -not $items.Contains($trimmed)) {
            [void]$items.Add($trimmed)
        }
    }
    $value = $items -join ","
    $changed = ($map["NO_PROXY"] -ne $value) -or ($map["no_proxy"] -ne $value)
    $map["NO_PROXY"] = $value
    $map["no_proxy"] = $value
    Save-EnvFileMap -Map $map
    return $changed
}

function Remove-NoProxyHost {
    param([string]$HostName)

    if ([string]::IsNullOrWhiteSpace($HostName)) {
        return $false
    }
    $map = Get-EnvFileMap
    $changed = $false
    foreach ($name in @("NO_PROXY", "no_proxy")) {
        if (-not $map.Contains($name)) {
            continue
        }
        $items = @(
            "$($map[$name])" -split ',' |
                ForEach-Object { "$_".Trim() } |
                Where-Object { $_ -and $_ -ne $HostName }
        )
        $newValue = $items -join ","
        if ($map[$name] -ne $newValue) {
            $map[$name] = $newValue
            $changed = $true
        }
    }
    if ($changed) {
        Save-EnvFileMap -Map $map
    }
    return $changed
}

function Save-CustomApiProfileIfActive {
    if ((Get-AuthMode) -like "OpenAI API Key*") {
        [void](Save-LoginProfile -Slot "custom-api" -Label "自定义 API")
        Write-Host "  [完成] 已同步更新自定义 API 加密档案。" -ForegroundColor Green
    }
}

function Test-ApiEndpointLatency {
    param(
        [string]$BaseUrl,
        [string]$ApiKey,
        [string]$Mode
    )

    $uri = "$($BaseUrl.TrimEnd('/'))/models"
    $headers = @{ Authorization = "Bearer $ApiKey" }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        if ($Mode -eq "proxy") {
            $response = Invoke-WebRequest -Uri $uri -Headers $headers -Proxy "http://127.0.0.1:10808" -TimeoutSec 15 -UseBasicParsing
        }
        else {
            $response = Invoke-WebRequest -Uri $uri -Headers $headers -TimeoutSec 15 -UseBasicParsing
        }
        $sw.Stop()
        return [pscustomobject]@{ Mode = $Mode; Ok = $true; Status = $response.StatusCode; Ms = $sw.ElapsedMilliseconds; Error = "" }
    }
    catch {
        $sw.Stop()
        return [pscustomobject]@{ Mode = $Mode; Ok = $false; Status = ""; Ms = $sw.ElapsedMilliseconds; Error = $_.Exception.Message }
    }
}

function Read-HttpResponseBody {
    param($Response)

    try {
        if (-not $Response) {
            return ""
        }
        $stream = $Response.GetResponseStream()
        if (-not $stream) {
            return ""
        }
        $reader = [IO.StreamReader]::new($stream)
        try {
            return $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }
    catch {
        return ""
    }
}

function Test-ApiResponsesEndpoint {
    param(
        [string]$BaseUrl,
        [string]$ApiKey,
        [string]$Model,
        [string]$Mode
    )

    $uri = "$($BaseUrl.TrimEnd('/'))/responses"
    $headers = @{ Authorization = "Bearer $ApiKey" }
    $body = @{
        model = $Model
        input = "ping"
        max_output_tokens = 1
        stream = $false
    } | ConvertTo-Json -Compress

    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        if ($Mode -eq "proxy") {
            $response = Invoke-WebRequest -Method Post -Uri $uri -Headers $headers -ContentType "application/json" -Body $body -Proxy "http://127.0.0.1:10808" -TimeoutSec 30 -UseBasicParsing
        }
        else {
            $response = Invoke-WebRequest -Method Post -Uri $uri -Headers $headers -ContentType "application/json" -Body $body -TimeoutSec 30 -UseBasicParsing
        }
        $sw.Stop()
        return [pscustomobject]@{ Mode = $Mode; Ok = $true; Status = $response.StatusCode; Ms = $sw.ElapsedMilliseconds; Error = ""; Body = "" }
    }
    catch {
        $sw.Stop()
        $response = $_.Exception.Response
        $status = ""
        if ($response -and $response.StatusCode) {
            $status = [int]$response.StatusCode
        }
        $responseBody = Read-HttpResponseBody -Response $response
        if ($responseBody.Length -gt 300) {
            $responseBody = $responseBody.Substring(0, 300)
        }
        return [pscustomobject]@{ Mode = $Mode; Ok = $false; Status = $status; Ms = $sw.ElapsedMilliseconds; Error = $_.Exception.Message; Body = $responseBody }
    }
}

function Show-CustomApiCompatibility {
    $baseUrl = Get-CurrentOpenAiBaseUrl
    if (-not $baseUrl) {
        Write-Host "  [提示] 当前没有配置自定义 API 地址。" -ForegroundColor Yellow
        return
    }

    $authPath = Join-Path $codexHome "auth.json"
    if (-not (Test-Path -LiteralPath $authPath)) {
        Write-Host "  [提示] 未找到 auth.json，无法检查 API 兼容性。" -ForegroundColor Yellow
        return
    }
    $auth = Get-Content -LiteralPath $authPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ("$($auth.auth_mode)" -notin @("apikey", "api_key")) {
        Write-Host "  [提示] 当前不是 API Key 登录，跳过 API 兼容性检查。" -ForegroundColor DarkGray
        return
    }
    $apiKey = "$($auth.OPENAI_API_KEY)"
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        Write-Host "  [提示] auth.json 中没有 API Key，无法检查 API 兼容性。" -ForegroundColor Yellow
        return
    }

    $model = Get-CurrentModelName
    if ([string]::IsNullOrWhiteSpace($model)) {
        $model = (Read-Host "  未在 config.toml 中找到 model，请输入要测试的模型名（例如 gpt-5.5）").Trim()
    }
    if ([string]::IsNullOrWhiteSpace($model)) {
        throw "没有模型名，已取消兼容性检查。"
    }

    Write-Host ""
    Write-Host "  自定义 API /v1/responses 兼容性检查" -ForegroundColor Cyan
    Write-Host ("  地址：{0}" -f $baseUrl)
    Write-Host ("  模型：{0}" -f $model)
    $direct = Test-ApiResponsesEndpoint -BaseUrl $baseUrl -ApiKey $apiKey -Model $model -Mode "direct"
    $proxy = Test-ApiResponsesEndpoint -BaseUrl $baseUrl -ApiKey $apiKey -Model $model -Mode "proxy"
    @($direct, $proxy) | Select-Object Mode, Ok, Status, Ms | Format-Table -AutoSize | Out-Host

    foreach ($result in @($direct, $proxy)) {
        if ($result.Ok) {
            Write-Host ("  [正常] {0} 路径可以调用 /v1/responses。" -f $result.Mode) -ForegroundColor Green
            continue
        }
        if ($result.Status -eq 503) {
            Write-Host ("  [服务不可用] {0} 路径返回 503：服务商上游暂不可用或该模型暂不可用。" -f $result.Mode) -ForegroundColor Yellow
        }
        elseif ($result.Status -in @(404, 405)) {
            Write-Host ("  [不兼容] {0} 路径返回 {1}：该服务可能不支持 Codex Desktop 需要的 /v1/responses。" -f $result.Mode, $result.Status) -ForegroundColor Yellow
        }
        elseif ($result.Status -in @(401, 403)) {
            Write-Host ("  [认证失败] {0} 路径返回 {1}：请检查 API Key 或服务商权限。" -f $result.Mode, $result.Status) -ForegroundColor Yellow
        }
        elseif ($result.Status -eq 400) {
            Write-Host ("  [请求被拒绝] {0} 路径返回 400：请检查模型名是否正确，或服务商是否兼容 Responses API 请求格式。" -f $result.Mode) -ForegroundColor Yellow
        }
        else {
            Write-Host ("  [失败] {0} 路径调用失败：{1}" -f $result.Mode, $result.Error) -ForegroundColor Yellow
        }
        if ($result.Body) {
            Write-Host ("    响应：{0}" -f $result.Body) -ForegroundColor DarkGray
        }
    }
}

function Invoke-CustomApiCompatibility {
    param([string]$Model = "")

    $baseUrl = Get-CurrentOpenAiBaseUrl
    if (-not $baseUrl) {
        throw "当前没有配置自定义 API 地址。"
    }

    $authPath = Join-Path $codexHome "auth.json"
    if (-not (Test-Path -LiteralPath $authPath)) {
        throw "未找到 auth.json，无法检查 API 兼容性。"
    }
    $auth = Get-Content -LiteralPath $authPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ("$($auth.auth_mode)" -notin @("apikey", "api_key")) {
        throw "当前不是 API Key 登录，无法检查 API 兼容性。"
    }
    $apiKey = "$($auth.OPENAI_API_KEY)"
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw "auth.json 中没有 API Key，无法检查 API 兼容性。"
    }

    $modelName = if ([string]::IsNullOrWhiteSpace($Model)) { Get-CurrentModelName } else { $Model.Trim() }
    if ([string]::IsNullOrWhiteSpace($modelName)) {
        throw "未找到模型名，请先在 config.toml 中设置 model，或从 UI 输入模型名。"
    }

    return [pscustomobject]@{
        baseUrl = $baseUrl
        model = $modelName
        direct = Test-ApiResponsesEndpoint -BaseUrl $baseUrl -ApiKey $apiKey -Model $modelName -Mode "direct"
        proxy = Test-ApiResponsesEndpoint -BaseUrl $baseUrl -ApiKey $apiKey -Model $modelName -Mode "proxy"
    }
}

function Optimize-CustomApiNetwork {
    param([bool]$Interactive = $true)

    $baseUrl = Get-CurrentOpenAiBaseUrl
    if (-not $baseUrl) {
        if ($Interactive) { Write-Host "  [提示] 当前没有配置自定义 API 地址。" -ForegroundColor Yellow }
        return
    }

    $authPath = Join-Path $codexHome "auth.json"
    if (-not (Test-Path -LiteralPath $authPath)) {
        if ($Interactive) { Write-Host "  [提示] 未找到 auth.json，无法测速 API。" -ForegroundColor Yellow }
        return
    }
    $auth = Get-Content -LiteralPath $authPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ("$($auth.auth_mode)" -notin @("apikey", "api_key")) {
        if ($Interactive) { Write-Host "  [提示] 当前不是 API Key 登录，跳过 API 网络优化。" -ForegroundColor DarkGray }
        return
    }
    $apiKey = "$($auth.OPENAI_API_KEY)"
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        if ($Interactive) { Write-Host "  [提示] auth.json 中没有 API Key，无法测速。" -ForegroundColor Yellow }
        return
    }

    $hostName = ([Uri]$baseUrl).Host
    Write-Host ""
    Write-Host "  API 网络测速" -ForegroundColor Cyan
    Write-Host ("  地址：{0}" -f $baseUrl)
    $direct = Test-ApiEndpointLatency -BaseUrl $baseUrl -ApiKey $apiKey -Mode "direct"
    $proxy = Test-ApiEndpointLatency -BaseUrl $baseUrl -ApiKey $apiKey -Mode "proxy"
    @($direct, $proxy) | Select-Object Mode, Ok, Status, Ms | Format-Table -AutoSize | Out-Host

    if ($direct.Ok -and (-not $proxy.Ok -or $direct.Ms -lt [Math]::Max(500, [int]($proxy.Ms * 0.75)))) {
        $changed = Add-NoProxyHost -HostName $hostName
        Write-Host ("  [完成] 已将 {0} 加入 .env 的 NO_PROXY，API 请求会优先直连。" -f $hostName) -ForegroundColor Green
        if ($changed -and ("$($auth.auth_mode)" -in @("apikey", "api_key"))) {
            Save-CustomApiProfileIfActive
        }
        Write-Host "  请完全退出并重新打开 Codex，让 .env 生效。" -ForegroundColor Yellow
    }
    elseif ($proxy.Ok -and (-not $direct.Ok -or $proxy.Ms -le $direct.Ms)) {
        Write-Host "  [结果] 代理路径不慢于直连，保持当前代理配置。" -ForegroundColor Green
    }
    else {
        Write-Host "  [警告] 直连和代理测速都失败，请检查自定义 API 服务或 Key。" -ForegroundColor Yellow
    }
}

function Set-CustomApiNetworkMode {
    param([ValidateSet("direct", "proxy")] [string]$Mode)

    Assert-CodexClosed
    $baseUrl = Get-CurrentOpenAiBaseUrl
    if (-not $baseUrl) {
        throw "当前没有配置自定义 API 地址。"
    }
    $hostName = ([Uri]$baseUrl).Host
    $changed = if ($Mode -eq "direct") {
        Add-NoProxyHost -HostName $hostName
    } else {
        Remove-NoProxyHost -HostName $hostName
    }
    Save-CustomApiProfileIfActive
    return [pscustomobject]@{
        mode = $Mode
        host = $hostName
        changed = [bool]$changed
        message = if ($Mode -eq "direct") { "已强制直连自定义 API 域名。" } else { "已强制该域名走本机代理。" }
    }
}

function Show-ApiNetworkMenu {
    while ($true) {
        $baseUrl = Get-CurrentOpenAiBaseUrl
        $hostName = if ($baseUrl) { ([Uri]$baseUrl).Host } else { "" }
        $map = Get-EnvFileMap
        $noProxy = if ($map.Contains("NO_PROXY")) { "$($map["NO_PROXY"])" } else { "" }
        $noProxyItems = @($noProxy -split ',' | ForEach-Object { "$_".Trim() })
        $mode = if ($hostName -and $noProxyItems -contains $hostName) { "强制直连该 API 域名" } else { "默认走代理" }

        Clear-Host
        Write-Host ("=" * 74) -ForegroundColor DarkGray
        Write-Host "                         自定义 API 网络模式" -ForegroundColor Cyan
        Write-Host ("=" * 74) -ForegroundColor DarkGray
        Write-Host ""
        Write-Host ("  API 地址     : {0}" -f $(if ($baseUrl) { $baseUrl } else { "未配置" }))
        Write-Host ("  API 域名     : {0}" -f $(if ($hostName) { $hostName } else { "无" }))
        Write-Host ("  当前模式     : {0}" -f $mode)
        Write-Host ""
        Write-Host "    [1] 自动测速并按结果优化"
        Write-Host "    [2] 强制直连自定义 API 域名（加入 NO_PROXY）"
        Write-Host "    [3] 强制走本机代理（从 NO_PROXY 移除该域名）"
        Write-Host "    [4] 查看当前 .env 代理配置"
        Write-Host "    [5] 检查 /v1/responses 兼容性"
        Write-Host "    [B] 返回"
        Write-Host ""
        $rawChoice = Read-Host "  请选择"
        if ($null -eq $rawChoice) { return }
        $choice = $rawChoice.Trim().ToUpperInvariant()
        try {
            switch ($choice) {
                "1" { Optimize-CustomApiNetwork -Interactive $true }
                "2" {
                    if (-not $hostName) { throw "当前没有配置自定义 API 地址。" }
                    [void](Add-NoProxyHost -HostName $hostName)
                    Save-CustomApiProfileIfActive
                    Write-Host ("  [完成] 已强制直连：{0}" -f $hostName) -ForegroundColor Green
                    Write-Host "  请完全退出并重新打开 Codex，让 .env 生效。" -ForegroundColor Yellow
                }
                "3" {
                    if (-not $hostName) { throw "当前没有配置自定义 API 地址。" }
                    [void](Remove-NoProxyHost -HostName $hostName)
                    Save-CustomApiProfileIfActive
                    Write-Host ("  [完成] 已强制该域名走代理：{0}" -f $hostName) -ForegroundColor Green
                    Write-Host "  请完全退出并重新打开 Codex，让 .env 生效。" -ForegroundColor Yellow
                }
                "4" {
                    Write-Host ""
                    foreach ($name in @("http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "no_proxy")) {
                        $value = if ($map.Contains($name)) { $map[$name] } else { "" }
                        Write-Host ("  {0,-12} {1}" -f $name, $value)
                    }
                }
                "5" { Show-CustomApiCompatibility }
                "B" { return }
                default { Write-Host "  [提示] 输入无效。" -ForegroundColor Yellow }
            }
        }
        catch {
            Write-Host ("  [错误] {0}" -f $_.Exception.Message) -ForegroundColor Red
        }
        if ($choice -ne "B") {
            Write-Host ""
            [void](Read-Host "  按 Enter 继续")
        }
    }
}

function Protect-LoginState {
    param([string]$BackupPath)

    $entries = @()
    foreach ($name in $credentialFiles) {
        $source = Join-Path $codexHome $name
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            continue
        }
        $plainBytes = [IO.File]::ReadAllBytes($source)
        $cipherBytes = [Security.Cryptography.ProtectedData]::Protect(
            $plainBytes,
            $dpapiEntropy,
            [Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        $entries += [pscustomobject][ordered]@{
            name = $name
            bytes = $plainBytes.Length
            sha256 = Get-Sha256 -Bytes $plainBytes
            encrypted = [Convert]::ToBase64String($cipherBytes)
        }
    }
    if ($entries.Count -eq 0) {
        return 0
    }

    $package = [pscustomobject][ordered]@{
        version = 1
        protection = "Windows DPAPI / CurrentUser"
        computer = $env:COMPUTERNAME
        user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        createdAt = (Get-Date).ToUniversalTime().ToString("o")
        files = $entries
    }
    $packagePath = Join-Path $BackupPath $credentialPackageName
    $json = $package | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($packagePath, $json, [Text.UTF8Encoding]::new($false))
    return $entries.Count
}

function Test-LoginStatePackage {
    param([string]$PackagePath)

    if (-not (Test-Path -LiteralPath $PackagePath)) {
        return [pscustomobject]@{ Present = $false; Checked = 0; Failures = @() }
    }
    $package = Get-Content -LiteralPath $PackagePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $failures = @()
    $checked = 0
    foreach ($entry in @($package.files)) {
        try {
            $cipherBytes = [Convert]::FromBase64String($entry.encrypted)
            $plainBytes = [Security.Cryptography.ProtectedData]::Unprotect(
                $cipherBytes,
                $dpapiEntropy,
                [Security.Cryptography.DataProtectionScope]::CurrentUser
            )
            if ((Get-Sha256 -Bytes $plainBytes) -ne $entry.sha256) {
                $failures += "$($entry.name)：解密后哈希不一致"
            }
            $checked++
        }
        catch {
            $failures += "$($entry.name)：$($_.Exception.Message)"
        }
    }
    return [pscustomobject]@{ Present = $true; Checked = $checked; Failures = $failures }
}

function Restore-LoginState {
    param([string]$PackagePath)

    $test = Test-LoginStatePackage -PackagePath $PackagePath
    if (-not $test.Present) {
        throw "该备份不包含登录状态。"
    }
    if (@($test.Failures).Count -gt 0) {
        throw "登录状态加密包校验失败：$($test.Failures -join '；')"
    }

    $package = Get-Content -LiteralPath $PackagePath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in @($package.files)) {
        $cipherBytes = [Convert]::FromBase64String($entry.encrypted)
        $plainBytes = [Security.Cryptography.ProtectedData]::Unprotect(
            $cipherBytes,
            $dpapiEntropy,
            [Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        $target = Join-Path $codexHome $entry.name
        $temporary = "$target.history-manager.tmp"
        [IO.File]::WriteAllBytes($temporary, $plainBytes)
        Move-Item -LiteralPath $temporary -Destination $target -Force
    }
}

function Set-BackupPermissions {
    param([string]$BackupPath)

    $currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $currentUserGrant = "*{0}:(OI)(CI)F" -f $currentUserSid
    $systemGrant = "*S-1-5-18:(OI)(CI)F"
    $administratorsGrant = "*S-1-5-32-544:(OI)(CI)F"

    & icacls.exe $BackupPath /inheritance:r /grant:r `
        $currentUserGrant `
        $systemGrant `
        $administratorsGrant | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "设置备份目录权限失败：$BackupPath"
    }
}

function Get-ProfilePath {
    param(
        [ValidateSet("chatgpt", "custom-api")]
        [string]$Slot
    )

    return Join-Path $profileDirectory $Slot
}

function Save-LoginProfile {
    param(
        [ValidateSet("chatgpt", "custom-api")]
        [string]$Slot,
        [string]$Label
    )

    $profilePath = Get-ProfilePath -Slot $Slot
    $profileRoot = [IO.Path]::GetFullPath($profileDirectory) + [IO.Path]::DirectorySeparatorChar
    $resolvedProfile = [IO.Path]::GetFullPath($profilePath)
    if (-not $resolvedProfile.StartsWith($profileRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "登录档案路径无效。"
    }
    if (Test-Path -LiteralPath $profilePath) {
        Remove-Item -LiteralPath $profilePath -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $profilePath | Out-Null
    $count = Protect-LoginState -BackupPath $profilePath
    if ($count -eq 0) {
        Remove-Item -LiteralPath $profilePath -Recurse -Force
        throw "没有可保存的登录或配置文件。"
    }

    $status = Invoke-Core -CoreAction "status"
    $metadata = [pscustomobject][ordered]@{
        version = 1
        slot = $Slot
        label = $Label
        savedAt = (Get-Date).ToUniversalTime().ToString("o")
        authMode = Get-AuthMode
        provider = $status.desktopProvider
        openaiBaseUrl = $status.openaiBaseUrl
        encryptedFiles = $count
    }
    [IO.File]::WriteAllText(
        (Join-Path $profilePath "profile.json"),
        ($metadata | ConvertTo-Json -Depth 4),
        [Text.UTF8Encoding]::new($false)
    )
    Set-BackupPermissions -BackupPath $profilePath

    $test = Test-LoginStatePackage -PackagePath (Join-Path $profilePath $credentialPackageName)
    if (@($test.Failures).Count -gt 0) {
        throw "登录档案保存后校验失败。"
    }
    return $metadata
}

function Get-LoginProfiles {
    $profiles = @()
    foreach ($slot in @("chatgpt", "custom-api")) {
        $profilePath = Get-ProfilePath -Slot $slot
        $metadataPath = Join-Path $profilePath "profile.json"
        $packagePath = Join-Path $profilePath $credentialPackageName
        if (Test-Path -LiteralPath $metadataPath -PathType Leaf) {
            try {
                $metadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $test = Test-LoginStatePackage -PackagePath $packagePath
                $profiles += [pscustomobject]@{
                    Slot = $slot
                    Label = $metadata.label
                    AuthMode = $metadata.authMode
                    BaseUrl = $metadata.openaiBaseUrl
                    SavedAt = $metadata.savedAt
                    Valid = (@($test.Failures).Count -eq 0)
                    Path = $profilePath
                }
            }
            catch {
                $profiles += [pscustomobject]@{
                    Slot = $slot
                    Label = $slot
                    AuthMode = "读取失败"
                    BaseUrl = ""
                    SavedAt = ""
                    Valid = $false
                    Path = $profilePath
                }
            }
        }
    }
    return @($profiles)
}

function Test-CurrentProfileMatch {
    param([string]$ProfilePath)

    $packagePath = Join-Path $ProfilePath $credentialPackageName
    if (-not (Test-Path -LiteralPath $packagePath)) {
        return $false
    }
    try {
        $package = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($entry in @($package.files)) {
            $currentPath = Join-Path $codexHome $entry.name
            if (-not (Test-Path -LiteralPath $currentPath -PathType Leaf)) {
                return $false
            }
            $currentBytes = [IO.File]::ReadAllBytes($currentPath)
            if ((Get-Sha256 -Bytes $currentBytes) -ne $entry.sha256) {
                return $false
            }
        }
        return @($package.files).Count -gt 0
    }
    catch {
        return $false
    }
}

function Get-ActiveProfileLabel {
    foreach ($slot in @("chatgpt", "custom-api")) {
        $profilePath = Get-ProfilePath -Slot $slot
        if (Test-CurrentProfileMatch -ProfilePath $profilePath) {
            return $(if ($slot -eq "chatgpt") { "ChatGPT 账号档案" } else { "自定义 API 档案" })
        }
    }
    return "当前状态尚未保存为登录档案"
}

function Show-ChatGptPreparationResult {
    param($Result)

    if ($Result.previousBaseUrl) {
        Write-Host ("  原自定义 API 地址：{0}" -f $Result.previousBaseUrl) -ForegroundColor DarkGray
    }
    if ($Result.removedBaseUrl) {
        Write-Host "  [完成] 已清除 config.toml 顶层 openai_base_url。" -ForegroundColor Green
    }
    if ($Result.providerChanged) {
        Write-Host "  [完成] 已确认桌面 Provider 使用 openai。" -ForegroundColor Green
    }
    if (@($Result.removedEnvKeys).Count -gt 0) {
        Write-Host ("  [完成] 已从 .env 移除 API 覆盖项：{0}" -f (@($Result.removedEnvKeys) -join ", ")) -ForegroundColor Green
    }
    if (@($Result.removedNoProxyHosts).Count -gt 0) {
        Write-Host ("  [完成] 已从 NO_PROXY/no_proxy 移除自定义 API 域名：{0}" -f (@($Result.removedNoProxyHosts) -join ", ")) -ForegroundColor Green
    }
    if (@($Result.removedAuthFiles).Count -gt 0) {
        Write-Host ("  [完成] 已移除 API Key 登录凭证文件：{0}" -f (@($Result.removedAuthFiles) -join ", ")) -ForegroundColor Green
    }
    if (-not $Result.removedBaseUrl -and
        -not $Result.providerChanged -and
        @($Result.removedEnvKeys).Count -eq 0 -and
        @($Result.removedNoProxyHosts).Count -eq 0 -and
        @($Result.removedAuthFiles).Count -eq 0) {
        Write-Host "  [正常] 未发现需要清理的自定义 API 残留。" -ForegroundColor DarkGray
    }
    foreach ($path in @($Result.configBackupPath, $Result.providerBackupPath, $Result.envBackupPath)) {
        if ($path) {
            Write-Host ("  配置备份：{0}" -f $path) -ForegroundColor DarkGray
        }
    }
}

function Prepare-ChatGptAccountMode {
    param([switch]$RemoveApiAuth)

    $mode = if ($RemoveApiAuth) { "remove-api-auth" } else { "keep-auth" }
    $result = Invoke-Core -CoreAction "prepare-chatgpt" -Argument $mode
    Show-ChatGptPreparationResult -Result $result
    return $result
}

function Show-LoginProfiles {
    $profiles = @(Get-LoginProfiles)
    Write-Host ""
    Write-Host "  登录档案状态" -ForegroundColor Cyan
    Write-Host ("  " + ("-" * 76)) -ForegroundColor DarkGray
    foreach ($slot in @("chatgpt", "custom-api")) {
        $profile = $profiles | Where-Object Slot -eq $slot | Select-Object -First 1
        $slotLabel = if ($slot -eq "chatgpt") { "ChatGPT 账号" } else { "自定义 API" }
        if (-not $profile) {
            Write-Host ("  {0,-16} 未保存" -f $slotLabel) -ForegroundColor DarkGray
            continue
        }
        $validLabel = if ($profile.Valid) { "正常" } else { "损坏或无法解密" }
        $activeLabel = if (Test-CurrentProfileMatch -ProfilePath $profile.Path) { " [当前使用]" } else { "" }
        Write-Host ("  {0,-16} {1,-18} {2}{3}" -f $slotLabel, $profile.AuthMode, $validLabel, $activeLabel)
        if ($profile.BaseUrl) {
            Write-Host ("  {0,-16} {1}" -f "", $profile.BaseUrl)
        }
    }
    Write-Host ("  " + ("-" * 76)) -ForegroundColor DarkGray
}

function Switch-LoginProfile {
    param(
        [ValidateSet("chatgpt", "custom-api")]
        [string]$Slot
    )

    Assert-CodexClosed
    $profilePath = Get-ProfilePath -Slot $Slot
    $packagePath = Join-Path $profilePath $credentialPackageName
    if (-not (Test-Path -LiteralPath $packagePath)) {
        throw "该登录档案尚未保存。"
    }
    $test = Test-LoginStatePackage -PackagePath $packagePath
    if (@($test.Failures).Count -gt 0) {
        throw "登录档案校验失败：$($test.Failures -join '；')"
    }

    New-Backup -IncludeLoginState $true
    Restore-LoginState -PackagePath $packagePath
    $label = if ($Slot -eq "chatgpt") { "ChatGPT 账号" } else { "自定义 API" }
    if ($Slot -eq "chatgpt") {
        [void](Prepare-ChatGptAccountMode)
        if ((Get-AuthMode) -like "ChatGPT*") {
            [void](Save-LoginProfile -Slot "chatgpt" -Label "当前 ChatGPT 账号")
        }
    }
    Write-Host ("  [完成] 已切换到：{0}" -f $label) -ForegroundColor Green
    if ($Slot -eq "custom-api") {
        Optimize-CustomApiNetwork -Interactive $true
    }
    Write-Host "  请重新打开 Codex；聊天记录不会被替换或删除。"
    & $codexExe login status
}

function Get-ApiKeyFromText {
    param(
        [string]$Text,
        [string]$SourceLabel
    )

    $content = "$Text".Trim().TrimStart([char]0xFEFF)
    if ([string]::IsNullOrWhiteSpace($content)) {
        throw "$SourceLabel 中没有 API Key。"
    }

    if ($content.StartsWith("{")) {
        try {
            $json = $content | ConvertFrom-Json
            foreach ($name in @("apiKey", "api_key", "OPENAI_API_KEY", "key")) {
                $property = $json.PSObject.Properties[$name]
                if ($property -and -not [string]::IsNullOrWhiteSpace("$($property.Value)")) {
                    $content = "$($property.Value)".Trim()
                    break
                }
            }
        }
        catch {
            throw "$SourceLabel 看起来是 JSON，但格式无法解析。"
        }
    }
    else {
        $matchingLine = @(
            $content -split "`r?`n" |
                Where-Object { $_ -match '^\s*(?:OPENAI_API_KEY|API_KEY)\s*=' }
        ) | Select-Object -First 1
        if ($matchingLine -match '^\s*(?:OPENAI_API_KEY|API_KEY)\s*=\s*(.+?)\s*$') {
            $content = $Matches[1].Trim().Trim('"').Trim("'")
        }
        else {
            $lines = @($content -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($lines.Count -ne 1) {
                throw "$SourceLabel 包含多行内容，且未找到 OPENAI_API_KEY=...。"
            }
            $content = $lines[0].Trim()
        }
    }

    if ([string]::IsNullOrWhiteSpace($content)) {
        throw "$SourceLabel 中的 API Key 为空。"
    }
    if ($content -match '\s') {
        throw "API Key 中包含空格或换行，请检查来源内容。"
    }
    return $content
}

function Get-ApiKeyFromFile {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = [Windows.Forms.OpenFileDialog]::new()
    try {
        $dialog.Title = "选择包含 API Key 的文件"
        $dialog.Filter = "密钥或文本文件 (*.txt;*.key;*.env;*.json)|*.txt;*.key;*.env;*.json|所有文件 (*.*)|*.*"
        $dialog.CheckFileExists = $true
        $dialog.Multiselect = $false
        if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) {
            return $null
        }
        $text = [IO.File]::ReadAllText($dialog.FileName, [Text.Encoding]::UTF8)
        $key = Get-ApiKeyFromText -Text $text -SourceLabel "所选文件"
        Write-Host ("  已读取文件：{0}" -f $dialog.FileName) -ForegroundColor DarkGray
        Write-Host "  注意：原文件仍是明文，请自行妥善保管或删除。" -ForegroundColor Yellow
        return $key
    }
    finally {
        $dialog.Dispose()
    }
}

function Read-ApiKey {
    Write-Host ""
    Write-Host "  选择 API Key 输入方式" -ForegroundColor Cyan
    Write-Host "    [1] 从 Windows 剪贴板读取（推荐）"
    Write-Host "    [2] 从 TXT / KEY / ENV / JSON 文件读取"
    Write-Host "    [3] 隐藏手动输入"
    Write-Host "    [B] 取消"
    $choice = (Read-Host "  请选择").Trim().ToUpperInvariant()

    $plainKey = $null
    switch ($choice) {
        "1" {
            try {
                $clipboardText = Get-Clipboard -Raw -ErrorAction Stop
                $plainKey = Get-ApiKeyFromText -Text $clipboardText -SourceLabel "剪贴板"
            }
            catch {
                throw "无法从剪贴板读取 API Key：$($_.Exception.Message)"
            }
        }
        "2" {
            $plainKey = Get-ApiKeyFromFile
            if (-not $plainKey) {
                throw "已取消选择 API Key 文件。"
            }
        }
        "3" {
            $secureKey = Read-Host "  请输入 API Key" -AsSecureString
            $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
            try {
                $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
            }
            finally {
                if ($pointer -ne [IntPtr]::Zero) {
                    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
                }
                $secureKey = $null
            }
            $plainKey = Get-ApiKeyFromText -Text $plainKey -SourceLabel "手动输入"
        }
        "B" { return $null }
        default { throw "输入无效，请选择 1、2、3 或 B。" }
    }

    $suffixLength = [Math]::Min(4, $plainKey.Length)
    $suffix = $plainKey.Substring($plainKey.Length - $suffixLength)
    Write-Host ("  [已读取] 长度 {0}，末尾 {1} 位：{2}" -f $plainKey.Length, $suffixLength, $suffix) -ForegroundColor Green
    if ((Read-Host "  确认使用这个 Key？[Y/N]").Trim().ToUpperInvariant() -ne "Y") {
        $plainKey = $null
        throw "已取消使用该 API Key。"
    }
    return $plainKey
}

function Configure-CustomApiProfile {
    Assert-CodexClosed

    $chatProfile = Get-LoginProfiles | Where-Object Slot -eq "chatgpt" | Select-Object -First 1
    if (-not $chatProfile -and (Get-AuthMode) -like "ChatGPT*") {
        Write-Host "  正在先保存当前 ChatGPT 登录档案..." -ForegroundColor DarkGray
        [void](Save-LoginProfile -Slot "chatgpt" -Label "当前 ChatGPT 账号")
    }

    Set-CustomApiAddress
    Write-Host ""
    Write-Host "  读取自定义 API 对应的 Key。" -ForegroundColor Cyan
    $plainKey = Read-ApiKey
    if (-not $plainKey) {
        throw "已取消配置自定义 API 档案。"
    }
    try {
        $plainKey | & $codexExe login --with-api-key
        if ($LASTEXITCODE -ne 0) {
            throw "API Key 登录失败。"
        }
    }
    finally {
        $plainKey = $null
    }

    $metadata = Save-LoginProfile -Slot "custom-api" -Label "自定义 API"
    Write-Host "  [完成] 自定义 API 登录档案已保存，以后可一键切换。" -ForegroundColor Green
    Write-Host ("  API 地址：{0}" -f $metadata.openaiBaseUrl)
    Optimize-CustomApiNetwork -Interactive $true
}

function Save-CurrentChatGptProfile {
    $authMode = Get-AuthMode
    if ($authMode -notlike "ChatGPT*") {
        throw "当前不是 ChatGPT 账号登录，不能覆盖 ChatGPT 登录档案。"
    }
    $metadata = Save-LoginProfile -Slot "chatgpt" -Label "当前 ChatGPT 账号"
    Write-Host "  [完成] 当前 ChatGPT 登录已加密保存。" -ForegroundColor Green
    Write-Host ("  保存时间：{0}" -f $metadata.savedAt)
}

function Login-WithChatGptAccount {
    Assert-CodexClosed
    Write-Host ""
    Write-Host "  切回 ChatGPT 账号登录（增强清理）" -ForegroundColor Cyan
    Write-Host "  会先创建完整备份，然后清理自定义 API 地址、API Key 环境变量和 API 登录凭证。" -ForegroundColor DarkGray
    Write-Host "  清理后将调用 Codex 官方账号登录流程。"
    if ((Read-Host "  确认继续？[Y/N]").Trim().ToUpperInvariant() -ne "Y") {
        throw "已取消切回账号登录。"
    }

    New-Backup -IncludeLoginState $true
    [void](Prepare-ChatGptAccountMode -RemoveApiAuth)

    Write-Host ""
    Write-Host "  正在启动 Codex 账号登录..." -ForegroundColor Cyan
    & $codexExe login --device-auth
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [提示] device-auth 未完成，尝试打开默认账号登录流程。" -ForegroundColor Yellow
        & $codexExe login
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Codex 账号登录未完成。你可以重新打开 Codex Desktop 后手动登录，API 残留已清理。"
    }

    [void](Prepare-ChatGptAccountMode)
    if ((Get-AuthMode) -notlike "ChatGPT*") {
        throw "登录命令已结束，但本地 auth.json 还不是 ChatGPT 账号模式。请重新打开 Codex Desktop 检查登录状态。"
    }

    $metadata = Save-LoginProfile -Slot "chatgpt" -Label "当前 ChatGPT 账号"
    Write-Host "  [完成] 已切回 ChatGPT 账号登录，并保存为账号档案。" -ForegroundColor Green
    Write-Host ("  档案保存时间：{0}" -f $metadata.savedAt)
    New-Backup -IncludeLoginState $true
}

function Open-CredentialImportDirectory {
    New-Item -ItemType Directory -Force -Path $credentialImportDirectory | Out-Null
    $readmePath = Join-Path $credentialImportDirectory "请放入凭证文件.txt"
    if (-not (Test-Path -LiteralPath $readmePath)) {
        $instructions = @"
请把同一个 ChatGPT 账号的以下两个文件放在本目录：

1. auth.json
2. .cockpit_codex_auth.json

然后完全退出 Codex Desktop，在管理器中选择：
[P] -> [8] 从导入文件夹登录 ChatGPT 账号

不要放账号密码。这里只接受已经登录后导出的 Codex 凭证文件。
导入前工具会校验 JSON，不会在屏幕或日志中显示令牌。
"@
        [IO.File]::WriteAllText($readmePath, $instructions, [Text.UTF8Encoding]::new($true))
    }
    Start-Process explorer.exe -ArgumentList $credentialImportDirectory
    Write-Host ("  [完成] 已打开：{0}" -f $credentialImportDirectory) -ForegroundColor Green
}

function Test-ImportedChatGptCredentials {
    $authPath = Join-Path $credentialImportDirectory "auth.json"
    $cockpitPath = Join-Path $credentialImportDirectory ".cockpit_codex_auth.json"
    $missing = @()
    if (-not (Test-Path -LiteralPath $authPath -PathType Leaf)) { $missing += "auth.json" }
    if (-not (Test-Path -LiteralPath $cockpitPath -PathType Leaf)) { $missing += ".cockpit_codex_auth.json" }
    if ($missing.Count -gt 0) {
        throw "导入文件夹缺少：$($missing -join '、')。请确保两个文件来自同一个账号。"
    }

    try {
        $auth = Get-Content -LiteralPath $authPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "auth.json 不是有效 JSON：$($_.Exception.Message)"
    }
    if ("$($auth.auth_mode)" -ne "chatgpt") {
        throw "auth.json 不是 ChatGPT 账号凭证，auth_mode 必须是 chatgpt。"
    }
    foreach ($name in @("access_token", "refresh_token", "account_id")) {
        $property = $auth.tokens.PSObject.Properties[$name]
        if (-not $property -or [string]::IsNullOrWhiteSpace("$($property.Value)")) {
            throw "auth.json 缺少必要字段 tokens.$name。"
        }
    }

    try {
        [void](Get-Content -LiteralPath $cockpitPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        throw ".cockpit_codex_auth.json 不是有效 JSON：$($_.Exception.Message)"
    }

    return [pscustomobject]@{
        AuthPath = $authPath
        CockpitPath = $cockpitPath
        AccountHint = "$($auth.tokens.account_id)"
    }
}

function Import-ChatGptCredentials {
    Assert-CodexClosed
    New-Item -ItemType Directory -Force -Path $credentialImportDirectory | Out-Null
    $validated = Test-ImportedChatGptCredentials

    $accountHint = $validated.AccountHint
    if ($accountHint.Length -gt 8) {
        $accountHint = $accountHint.Substring(0, 4) + "..." + $accountHint.Substring($accountHint.Length - 4)
    }
    Write-Host ""
    Write-Host "  已找到一组结构有效的 ChatGPT 凭证。" -ForegroundColor Cyan
    Write-Host ("  账号标识：{0}" -f $accountHint)
    Write-Host "  工具无法仅靠文件结构确认令牌是否仍被服务器接受。" -ForegroundColor Yellow
    if ((Read-Host "  确认备份当前状态并导入？[Y/N]").Trim().ToUpperInvariant() -ne "Y") {
        throw "已取消导入。"
    }

    New-Backup -IncludeLoginState $true
    $targets = @(
        [pscustomobject]@{ Source = $validated.AuthPath; Destination = (Join-Path $codexHome "auth.json") },
        [pscustomobject]@{ Source = $validated.CockpitPath; Destination = (Join-Path $codexHome ".cockpit_codex_auth.json") }
    )
    foreach ($item in $targets) {
        $temporary = "$($item.Destination).history-manager.import"
        Copy-Item -LiteralPath $item.Source -Destination $temporary -Force
        Move-Item -LiteralPath $temporary -Destination $item.Destination -Force
    }

    [void](Prepare-ChatGptAccountMode)
    if ((Get-AuthMode) -notlike "ChatGPT*") {
        throw "凭证文件已复制，但登录类型校验失败。请使用刚才创建的完整备份恢复。"
    }

    $metadata = Save-LoginProfile -Slot "chatgpt" -Label "导入的 ChatGPT 账号"
    Write-Host "  [完成] ChatGPT 凭证已导入，并已保存为 DPAPI 加密档案。" -ForegroundColor Green
    Write-Host ("  档案保存时间：{0}" -f $metadata.savedAt)
    Write-Host ""
    & $codexExe login status
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [警告] 本地文件已导入，但 Codex 登录状态检查未通过；令牌可能已过期或被撤销。" -ForegroundColor Yellow
    }

    if ((Read-Host "  是否删除导入文件夹中的两个明文凭证文件？[Y/N]").Trim().ToUpperInvariant() -eq "Y") {
        Remove-Item -LiteralPath $validated.AuthPath, $validated.CockpitPath -Force
        Write-Host "  [完成] 已删除导入文件夹中的明文凭证文件。" -ForegroundColor Green
    }
    else {
        Write-Host ("  [提醒] 明文凭证仍保留在：{0}" -f $credentialImportDirectory) -ForegroundColor Yellow
    }
}

function Show-ProfileMenu {
    while ($true) {
        Clear-Host
        Write-Host ("=" * 74) -ForegroundColor DarkGray
        Write-Host "                       登录档案快速切换" -ForegroundColor Cyan
        Write-Host ("=" * 74) -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "    [1] 保存或更新当前 ChatGPT 登录档案"
        Write-Host "    [2] 首次配置或更新自定义 API 档案"
        Write-Host "    [3] 一键切换到 ChatGPT 账号"
        Write-Host "    [4] 一键切换到自定义 API"
        Write-Host "    [5] 查看两个登录档案状态"
        Write-Host "    [6] 增强切回 ChatGPT 账号登录（清理 API 残留）"
        Write-Host "    [7] 打开 ChatGPT 凭证导入文件夹"
        Write-Host "    [8] 从导入文件夹登录 ChatGPT 账号"
        Write-Host ""
        Write-Host "    [B] 返回主菜单"
        Write-Host ""
        Write-Host ("-" * 74) -ForegroundColor DarkGray

        $choice = (Read-Host "  请选择功能").Trim().ToUpperInvariant()
        try {
            switch ($choice) {
                "1" { Save-CurrentChatGptProfile }
                "2" { Configure-CustomApiProfile }
                "3" { Switch-LoginProfile -Slot "chatgpt" }
                "4" { Switch-LoginProfile -Slot "custom-api" }
                "5" { Show-LoginProfiles }
                "6" { Login-WithChatGptAccount }
                "7" { Open-CredentialImportDirectory }
                "8" { Import-ChatGptCredentials }
                "B" { return }
                default { Write-Host "  [提示] 输入无效。" -ForegroundColor Yellow }
            }
        }
        catch {
            Write-Host ("  [错误] {0}" -f $_.Exception.Message) -ForegroundColor Red
        }
        if ($choice -ne "B") {
            Write-Host ""
            [void](Read-Host "  按 Enter 继续")
        }
    }
}

function Show-Status {
    $status = Invoke-Core -CoreAction "status"
    $backups = @(Invoke-Core -CoreAction "list")
    Write-Host ""
    Write-Host "  本地状态总览" -ForegroundColor Cyan
    Write-Host ("  " + ("-" * 70)) -ForegroundColor DarkGray
    Write-Host ("  登录方式          {0}" -f (Get-AuthMode))
    Write-Host ("  当前登录档案      {0}" -f (Get-ActiveProfileLabel))
    Write-Host ("  桌面 Provider     {0}" -f $status.desktopProvider)
    Write-Host ("  自定义 API 地址   {0}" -f $(if ($status.openaiBaseUrl) { $status.openaiBaseUrl } else { "未配置（使用 OpenAI 默认地址）" }))
    Write-Host ("  会话文件          {0} 个（有效 {1}，异常 {2}）" -f
        $status.totalSessionFiles, $status.validSessionFiles, $status.invalidSessionFiles)
    Write-Host ("  会话索引          {0} 条" -f $status.indexLines)
    Write-Host ("  可用备份          {0} 份" -f $backups.Count)
    Write-Host ("  Codex 运行状态    {0}" -f $(if (Test-CodexRunning) { "运行中" } else { "已退出" }))

    Write-Host ""
    Write-Host "  会话 Provider 分布" -ForegroundColor Yellow
    foreach ($property in $status.providers.PSObject.Properties) {
        Write-Host ("    {0,-24} {1,6}" -f $property.Name, $property.Value)
    }
    if ($status.desktopProvider -and
        $status.providers.PSObject.Properties.Name -notcontains $status.desktopProvider) {
        Write-Host ""
        Write-Host "  [警告] 桌面 Provider 与历史会话不一致，历史列表可能被过滤。" -ForegroundColor Yellow
    }
    Write-Host ("  " + ("-" * 70)) -ForegroundColor DarkGray
}

function New-Backup {
    param([bool]$IncludeLoginState)

    $kind = if ($IncludeLoginState) { "完整备份" } else { "聊天记录备份" }
    Write-Host ""
    Write-Host ("  正在创建{0}..." -f $kind) -ForegroundColor Cyan
    $result = Invoke-Core -CoreAction "backup" -Argument $(if ($IncludeLoginState) { "full" } else { "history" })
    $credentialCount = 0
    if ($IncludeLoginState) {
        $credentialCount = Protect-LoginState -BackupPath $result.destination
        if ($credentialCount -gt 0) {
            $backupName = Split-Path -Leaf $result.destination
            $result = Invoke-Core -CoreAction "refresh-manifest" -Argument $backupName
        }
    }
    Set-BackupPermissions -BackupPath $(if ($result.destination) { $result.destination } else { Join-Path $backupDirectory $result.backupName })

    $backupPath = if ($result.destination) { $result.destination } else { Join-Path $backupDirectory $result.backupName }
    $verification = Invoke-Core -CoreAction "verify" -Argument (Split-Path -Leaf $backupPath)
    $credentialTest = Test-LoginStatePackage -PackagePath (Join-Path $backupPath $credentialPackageName)
    if (@($verification.failures).Count -gt 0 -or @($credentialTest.Failures).Count -gt 0) {
        throw "备份完成，但自动校验未通过。"
    }

    Write-Host ("  [完成] 文件校验通过：{0} 个" -f $verification.checked) -ForegroundColor Green
    if ($IncludeLoginState) {
        if ($credentialCount -gt 0) {
            Write-Host ("  [完成] 已加密登录与配置文件：{0} 个" -f $credentialCount) -ForegroundColor Green
            Write-Host "  加密方式：Windows DPAPI，仅当前 Windows 用户可解密。"
        }
        else {
            Write-Host "  [提示] 当前没有可加密的登录或配置文件，本次仅保存聊天与本地状态。" -ForegroundColor Yellow
        }
    }
    Write-Host ("  保存位置：{0}" -f $backupPath)
}

function New-BackupForUi {
    param([bool]$IncludeLoginState)

    $result = Invoke-Core -CoreAction "backup" -Argument $(if ($IncludeLoginState) { "full" } else { "history" })
    $credentialCount = 0
    if ($IncludeLoginState) {
        $credentialCount = Protect-LoginState -BackupPath $result.destination
        if ($credentialCount -gt 0) {
            $backupName = Split-Path -Leaf $result.destination
            $result = Invoke-Core -CoreAction "refresh-manifest" -Argument $backupName
        }
    }

    $backupPath = if ($result.destination) { $result.destination } else { Join-Path $backupDirectory $result.backupName }
    Set-BackupPermissions -BackupPath $backupPath
    $verification = Invoke-Core -CoreAction "verify" -Argument (Split-Path -Leaf $backupPath)
    $credentialTest = Test-LoginStatePackage -PackagePath (Join-Path $backupPath $credentialPackageName)
    if (@($verification.failures).Count -gt 0 -or @($credentialTest.Failures).Count -gt 0) {
        throw "备份完成，但自动校验未通过。"
    }

    return [pscustomobject]@{
        backupName = Split-Path -Leaf $backupPath
        path = $backupPath
        includeLoginState = $IncludeLoginState
        encryptedCredentialCount = $credentialCount
        checked = $verification.checked
        credentialChecked = $credentialTest.Checked
    }
}

function Get-Backups {
    return @(Invoke-Core -CoreAction "list")
}

function Select-Backup {
    $backups = @(Get-Backups)
    if ($backups.Count -eq 0) {
        throw "目前没有可用备份。"
    }
    Write-Host ""
    Write-Host "  可用备份" -ForegroundColor Cyan
    Write-Host ("  " + ("-" * 86)) -ForegroundColor DarkGray
    for ($index = 0; $index -lt $backups.Count; $index++) {
        $credentialLabel = if ($backups[$index].credentialProtection -eq "windows-dpapi-current-user") {
            "聊天 + 加密登录状态"
        } else {
            "仅聊天记录"
        }
        Write-Host ("  [{0,2}] {1,-42} {2,-20} {3,4} 文件" -f
            ($index + 1), $backups[$index].name, $credentialLabel, $backups[$index].files)
    }
    $selection = Read-Host "  请输入备份编号"
    $number = 0
    if (-not [int]::TryParse($selection, [ref]$number) -or
        $number -lt 1 -or $number -gt $backups.Count) {
        throw "备份编号无效。"
    }
    return $backups[$number - 1]
}

function Verify-Backup {
    $backup = Select-Backup
    $result = Invoke-Core -CoreAction "verify" -Argument $backup.name
    $credentialTest = Test-LoginStatePackage -PackagePath (Join-Path $backup.path $credentialPackageName)
    $failures = @($result.failures) + @($credentialTest.Failures)
    if ($failures.Count -gt 0) {
        $failures | ForEach-Object { Write-Host ("  [失败] {0}" -f $_) -ForegroundColor Red }
        throw "备份校验失败。"
    }
    Write-Host ("  [正常] 文件完整性校验通过：{0} 个文件。" -f $result.checked) -ForegroundColor Green
    if ($credentialTest.Present) {
        Write-Host ("  [正常] 登录状态解密测试通过：{0} 个文件。" -f $credentialTest.Checked) -ForegroundColor Green
    }
}

function Restore-Backup {
    Assert-CodexClosed
    $backup = Select-Backup
    Verify-BackupByObject -Backup $backup

    Write-Host ""
    Write-Host "  恢复会覆盖当前聊天记录；操作前会自动创建完整安全备份。" -ForegroundColor Yellow
    if ((Read-Host "  输入 RESTORE 确认").Trim() -cne "RESTORE") {
        Write-Host "  [取消] 未做修改。"
        return
    }

    New-Backup -IncludeLoginState $true
    $result = Invoke-Core -CoreAction "restore" -Argument $backup.name
    $packagePath = Join-Path $backup.path $credentialPackageName
    if (Test-Path -LiteralPath $packagePath) {
        $restoreLogin = (Read-Host "  是否同时恢复登录状态和 API 配置？[Y/N]").Trim().ToUpperInvariant()
        if ($restoreLogin -eq "Y") {
            Restore-LoginState -PackagePath $packagePath
            Write-Host "  [完成] 登录状态和 API 配置已恢复。" -ForegroundColor Green
        }
    }
    Write-Host "  [完成] 聊天记录已恢复，请重新启动 Codex。" -ForegroundColor Green
    Write-Host ("  恢复来源：{0}" -f $result.restoredFrom)
}

function Verify-BackupByObject {
    param($Backup)

    $result = Invoke-Core -CoreAction "verify" -Argument $Backup.name
    $credentialTest = Test-LoginStatePackage -PackagePath (Join-Path $Backup.path $credentialPackageName)
    if (@($result.failures).Count -gt 0 -or @($credentialTest.Failures).Count -gt 0) {
        throw "所选备份校验失败，已停止恢复。"
    }
}

function Get-BackupByName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "缺少备份名称。"
    }
    $backup = @(Get-Backups | Where-Object { $_.name -eq $Name }) | Select-Object -First 1
    if (-not $backup) {
        throw "未找到备份：$Name"
    }
    return $backup
}

function Test-BackupForUi {
    param([string]$Name)

    $backup = Get-BackupByName -Name $Name
    $result = Invoke-Core -CoreAction "verify" -Argument $backup.name
    $credentialTest = Test-LoginStatePackage -PackagePath (Join-Path $backup.path $credentialPackageName)
    $failures = @($result.failures) + @($credentialTest.Failures)
    if ($failures.Count -gt 0) {
        throw "备份校验失败：$($failures -join '; ')"
    }
    return [pscustomobject]@{
        name = $backup.name
        path = $backup.path
        checked = $result.checked
        credentialChecked = $credentialTest.Checked
        credentialPackagePresent = $credentialTest.Present
    }
}

function Restore-BackupForUi {
    param(
        [string]$Name,
        [bool]$IncludeLoginState
    )

    Assert-CodexClosed
    $backup = Get-BackupByName -Name $Name
    Verify-BackupByObject -Backup $backup
    $safetyBackup = New-BackupForUi -IncludeLoginState $true
    $result = Invoke-Core -CoreAction "restore" -Argument $backup.name
    $loginRestored = $false
    $packagePath = Join-Path $backup.path $credentialPackageName
    if ($IncludeLoginState -and (Test-Path -LiteralPath $packagePath)) {
        Restore-LoginState -PackagePath $packagePath
        $loginRestored = $true
    }
    return [pscustomobject]@{
        restoredFrom = $result.restoredFrom
        loginRestored = $loginRestored
        safetyBackup = $safetyBackup
    }
}

function Enable-UnifiedHistory {
    Assert-CodexClosed
    $configResult = Invoke-Core -CoreAction "unify-config"
    $historyResult = Invoke-Core -CoreAction "normalize-provider" -Argument "openai"
    Write-Host ("  [完成] 桌面 Provider：openai；更新历史会话：{0} 个。" -f $historyResult.changed) -ForegroundColor Green
    if ($configResult.backupPath) {
        Write-Host ("  配置备份：{0}" -f $configResult.backupPath)
    }
}

function Set-CustomApiAddress {
    Assert-CodexClosed
    $current = (Invoke-Core -CoreAction "status").openaiBaseUrl
    Write-Host ""
    Write-Host "  配置自定义 OpenAI API 地址" -ForegroundColor Cyan
    Write-Host ("  当前地址：{0}" -f $(if ($current) { $current } else { "OpenAI 默认地址" }))
    Write-Host "  示例：https://example.com/v1"
    Write-Host "  直接按 Enter 可清除自定义地址并恢复默认。"
    $url = (Read-Host "  新地址").Trim()
    if ($url -and $url -notmatch '^https?://') {
        throw "地址必须以 http:// 或 https:// 开头。"
    }
    if ($url -and $url -notmatch '/v1/?$') {
        Write-Host "  [提示] 地址未以 /v1 结尾，请确认你的服务商要求。" -ForegroundColor Yellow
    }
    $result = Invoke-Core -CoreAction "set-base-url" -Argument $url
    Write-Host ("  [完成] 自定义 API 地址：{0}" -f $(if ($result.baseUrl) { $result.baseUrl } else { "已清除，使用 OpenAI 默认地址" })) -ForegroundColor Green
    Write-Host "  Provider 已保持为 openai，历史记录不会因登录方式切换而分组消失。"
    Write-Host ("  配置备份：{0}" -f $result.backupPath)
}

function Set-CustomApiAddressForUi {
    param([string]$Url)

    Assert-CodexClosed
    $trimmedUrl = "$Url".Trim()
    if ($trimmedUrl -and $trimmedUrl -notmatch '^https?://') {
        throw "地址必须以 http:// 或 https:// 开头。"
    }
    $result = Invoke-Core -CoreAction "set-base-url" -Argument $trimmedUrl
    return [pscustomobject]@{
        baseUrl = $result.baseUrl
        backupPath = $result.backupPath
        provider = "openai"
        warning = if ($trimmedUrl -and $trimmedUrl -notmatch '/v1/?$') { "地址未以 /v1 结尾，请确认你的服务商要求。" } else { "" }
    }
}

function Invoke-ApiKeyLoginForUi {
    param(
        [string]$PlainKey,
        [bool]$FirstLogin
    )

    Assert-CodexClosed
    $apiKey = Get-ApiKeyFromText -Text $PlainKey -SourceLabel "UI 输入"
    $beforeBackup = $null
    if (-not $FirstLogin) {
        $beforeBackup = New-BackupForUi -IncludeLoginState $true
    }
    elseif ((Get-AuthMode) -notlike "未找到登录凭证") {
        throw "当前已经存在登录凭证。请使用普通 API Key 登录，或先确认要覆盖当前状态。"
    }

    try {
        $apiKey | & $codexExe login --with-api-key
        if ($LASTEXITCODE -ne 0) {
            throw "API Key 登录失败。"
        }
    }
    finally {
        $apiKey = $null
    }

    Optimize-CustomApiNetwork -Interactive $false
    $afterBackup = New-BackupForUi -IncludeLoginState $true
    return [pscustomobject]@{
        mode = "api-key"
        firstLogin = $FirstLogin
        beforeBackup = $beforeBackup
        afterBackup = $afterBackup
    }
}

function Login-WithApiKey {
    Assert-CodexClosed
    Write-Host ""
    Write-Host "  OpenAI API Key 登录" -ForegroundColor Cyan
    Write-Host "  API Key 不会显示，也不会写入命令行参数或日志。" -ForegroundColor DarkGray
    Write-Host "  登录前先创建当前状态的完整安全备份。"
    New-Backup -IncludeLoginState $true

    $plainKey = Read-ApiKey
    if (-not $plainKey) {
        throw "已取消 API Key 登录。"
    }
    try {
        $plainKey | & $codexExe login --with-api-key
        if ($LASTEXITCODE -ne 0) {
            throw "API Key 登录失败。"
        }
    }
    finally {
        $plainKey = $null
    }

    Write-Host "  [完成] API Key 登录成功。" -ForegroundColor Green
    Optimize-CustomApiNetwork -Interactive $true
    New-Backup -IncludeLoginState $true
}

function FirstLogin-WithApiKey {
    Assert-CodexClosed
    Write-Host ""
    Write-Host "  新用户首次 API Key 登录" -ForegroundColor Cyan
    Write-Host "  适用于当前 Codex Home 还没有登录状态的新用户。" -ForegroundColor DarkGray
    Write-Host "  这一步不会先创建登录前备份；登录成功后会自动创建完整备份。"

    if ((Get-AuthMode) -notlike "未找到登录凭证") {
        Write-Host "  [提示] 当前已经存在登录凭证。若要保留现有状态，请优先使用菜单 [8]。" -ForegroundColor Yellow
        if ((Read-Host "  仍然继续首次登录流程？[Y/N]").Trim().ToUpperInvariant() -ne "Y") {
            throw "已取消首次登录。"
        }
    }

    $plainKey = Read-ApiKey
    if (-not $plainKey) {
        throw "已取消 API Key 登录。"
    }
    try {
        $plainKey | & $codexExe login --with-api-key
        if ($LASTEXITCODE -ne 0) {
            throw "API Key 登录失败。"
        }
    }
    finally {
        $plainKey = $null
    }

    Write-Host "  [完成] API Key 登录成功。" -ForegroundColor Green
    Write-Host "  如需调整自定义 API 的直连/代理模式，可稍后使用主菜单 [N]。"
    New-Backup -IncludeLoginState $true
}

function Show-LoginStatus {
    Write-Host ""
    Write-Host "  Codex 登录状态" -ForegroundColor Cyan
    & $codexExe login status
    if ($LASTEXITCODE -ne 0) {
        throw "Codex 登录状态检查失败。"
    }
}

function Open-ResumePicker {
    Start-Process powershell.exe -ArgumentList @(
        "-NoExit",
        "-Command",
        "& '$codexExe' resume --all"
    )
}

function Show-Help {
    Clear-Host
    Write-Host ("=" * 74) -ForegroundColor DarkGray
    Write-Host "                         使用说明" -ForegroundColor Cyan
    Write-Host ("=" * 74) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  推荐操作" -ForegroundColor Yellow
    Write-Host "    1. 平时选择 [2] 创建完整备份。"
    Write-Host "    2. ChatGPT 与 API Key 切换后，历史仍应统一使用 openai Provider。"
    Write-Host "    3. 使用自定义 API 地址时选择 [7]，不要再创建 openai_http Provider。"
    Write-Host "    4. 使用主菜单 [P] 保存两个登录档案并一键切换。"
    Write-Host "    5. 从 API 切回账号优先用 [P] -> [3]；没有账号档案时用 [P] -> [6]。"
    Write-Host "    6. 已有合法 ChatGPT 凭证可放入 credential-import，再用 [P] -> [8] 导入。"
    Write-Host ""
    Write-Host "  凭证安全" -ForegroundColor Yellow
    Write-Host "    完整备份包含 auth.json、桌面认证文件、config.toml 和 .env。"
    Write-Host "    这些文件使用 Windows DPAPI 加密，不会在备份目录中明文保存。"
    Write-Host "    DPAPI 备份通常只能由当前 Windows 用户在当前电脑上解密。"
    Write-Host "    ChatGPT 令牌被服务器撤销或 API Key 被删除后，旧备份不能恢复其有效性。"
    Write-Host "    导入账号要求 auth.json 与 .cockpit_codex_auth.json 来自同一个账号。"
    Write-Host ""
    Write-Host "  自定义 API 地址" -ForegroundColor Yellow
    Write-Host '    配置结果使用：model_provider = "openai"'
    Write-Host '    并在顶层写入：openai_base_url = "https://地址/v1"'
    Write-Host "    登录仍通过 Codex 的 API Key 登录完成。"
    Write-Host "    新用户第一次登录可用菜单 [0]，登录成功后再自动备份。"
    Write-Host "    菜单 [8] 会安全读取 API Key，并通过标准输入交给 Codex。"
    Write-Host "    更推荐使用 [P] -> [2] 一次配置 API 档案，以后直接一键切换。"
    Write-Host ""
    Write-Host "  恢复要求" -ForegroundColor Yellow
    Write-Host "    恢复或修改配置前必须完全退出 Codex。工具不会强行结束 Codex。"
    Write-Host "    恢复前会自动创建新的完整安全备份。"
    Write-Host ""
    Write-Host "  命令行调用" -ForegroundColor Yellow
    Write-Host '    Codex-Chat-History-Manager.cmd'
    Write-Host '    Codex-Chat-History-Manager.cmd -Action status'
    Write-Host '    Codex-Chat-History-Manager.cmd -Action backup'
    Write-Host '    Codex-Chat-History-Manager.cmd -Action help'
    Write-Host '    Codex-Chat-History-Manager.cmd -Action profiles'
    Write-Host '    Codex-Chat-History-Manager.cmd -Action first-login'
    Write-Host '    Codex-Chat-History-Manager.cmd -Action chatgpt-login'
    Write-Host '    Codex-Chat-History-Manager.cmd -Action export-tool'
    Write-Host '    powershell -File "%USERPROFILE%\.codex\tools\history-manager\Codex-History-Manager.ps1" -Action status'
    Write-Host '    powershell -File "%USERPROFILE%\.codex\tools\history-manager\Codex-History-Manager.ps1" -Action backup'
    Write-Host '    powershell -File "%USERPROFILE%\.codex\tools\history-manager\Codex-History-Manager.ps1" -Action help'
    Write-Host ""
    Write-Host ("-" * 74) -ForegroundColor DarkGray
}

function Show-Menu {
    Clear-Host
    Write-Host ("=" * 74) -ForegroundColor DarkGray
    Write-Host "                    Codex 聊天与登录管理器" -ForegroundColor Cyan
    Write-Host ("=" * 74) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  状态与备份" -ForegroundColor Yellow
    Write-Host "    [1] 查看聊天、登录和 API 配置状态"
    Write-Host "    [2] 创建完整备份（聊天 + DPAPI 加密登录状态）"
    Write-Host "    [3] 仅备份聊天记录"
    Write-Host "    [4] 查看并校验已有备份"
    Write-Host "    [5] 恢复备份"
    Write-Host ""
    Write-Host "  登录与 API" -ForegroundColor Yellow
    Write-Host "    [0] 新用户首次 API Key 登录（无登录状态时使用）"
    Write-Host "    [6] 修复统一历史模式（ChatGPT / API Key 共用）"
    Write-Host "    [7] 设置或清除自定义 API 地址"
    Write-Host "    [8] 安全输入 API Key 并登录"
    Write-Host "    [9] 查看 Codex 登录状态"
    Write-Host "    [N] 自定义 API 网络模式（自动 / 直连 / 代理）"
    Write-Host "    [P] ChatGPT / 自定义 API 一键切换"
    Write-Host ""
    Write-Host "  历史工具" -ForegroundColor Yellow
    Write-Host "    [A] 用 CLI 打开全部本地历史"
    Write-Host "    [E] 导出便携安装包（给其他电脑使用）"
    Write-Host "    [L] 打开备份目录"
    Write-Host "    [H] 查看内置使用说明"
    Write-Host ""
    Write-Host "    [Q] 退出"
    Write-Host ""
    Write-Host ("-" * 74) -ForegroundColor DarkGray
}

function Get-UiStatus {
    $status = Invoke-Core -CoreAction "status"
    $backups = @(Invoke-Core -CoreAction "list")
    return [pscustomobject]@{
        authMode = Get-AuthMode
        activeProfile = Get-ActiveProfileLabel
        codexRunning = Test-CodexRunning
        desktopProvider = $status.desktopProvider
        openaiBaseUrl = $status.openaiBaseUrl
        totalSessionFiles = $status.totalSessionFiles
        validSessionFiles = $status.validSessionFiles
        invalidSessionFiles = $status.invalidSessionFiles
        indexLines = $status.indexLines
        providers = $status.providers
        backups = $backups
        profiles = @(Get-LoginProfiles)
        codexHome = $codexHome
        backupDirectory = $backupDirectory
        credentialImportDirectory = $credentialImportDirectory
    }
}

function Invoke-UiAction {
    param(
        [string]$Name,
        [string]$Value,
        [bool]$IncludeLoginState
    )

    $result = switch ($Name) {
        "ui-status" { Get-UiStatus }
        "ui-list-backups" { @(Get-Backups) }
        "ui-backup-full" { New-BackupForUi -IncludeLoginState $true }
        "ui-backup-history" { New-BackupForUi -IncludeLoginState $false }
        "ui-verify-backup" { Test-BackupForUi -Name $Value }
        "ui-restore-backup" { Restore-BackupForUi -Name $Value -IncludeLoginState $IncludeLoginState }
        "ui-set-base-url" { Set-CustomApiAddressForUi -Url $Value }
        "ui-login-api-key" { Invoke-ApiKeyLoginForUi -PlainKey (Read-UiSecretFromStdIn) -FirstLogin $false }
        "ui-first-login-api-key" { Invoke-ApiKeyLoginForUi -PlainKey (Read-UiSecretFromStdIn) -FirstLogin $true }
        "ui-save-chatgpt" { Save-CurrentChatGptProfile; [pscustomobject]@{ saved = $true } }
        "ui-switch-chatgpt" { Switch-LoginProfile -Slot "chatgpt"; [pscustomobject]@{ switchedTo = "chatgpt" } }
        "ui-switch-api" { Switch-LoginProfile -Slot "custom-api"; [pscustomobject]@{ switchedTo = "custom-api" } }
        "ui-clean-chatgpt" { Login-WithChatGptAccount; [pscustomobject]@{ started = "chatgpt-login" } }
        "ui-unify-history" { Enable-UnifiedHistory; [pscustomobject]@{ unified = $true } }
        "ui-login-status" { & $codexExe login status; if ($LASTEXITCODE -ne 0) { throw "Codex 登录状态检查失败。" }; [pscustomobject]@{ checked = $true } }
        "ui-api-network-auto" { Optimize-CustomApiNetwork -Interactive $false; [pscustomobject]@{ mode = "auto" } }
        "ui-api-network-direct" { Set-CustomApiNetworkMode -Mode "direct" }
        "ui-api-network-proxy" { Set-CustomApiNetworkMode -Mode "proxy" }
        "ui-api-compatibility" { Invoke-CustomApiCompatibility -Model $Value }
        "ui-open-backups" { New-Item -ItemType Directory -Force -Path $backupDirectory | Out-Null; Start-Process explorer.exe -ArgumentList $backupDirectory; [pscustomobject]@{ opened = $backupDirectory } }
        "ui-open-import" { Open-CredentialImportDirectory; [pscustomobject]@{ opened = $credentialImportDirectory } }
        "ui-open-history" { Open-ResumePicker; [pscustomobject]@{ opened = "codex resume --all" } }
        "ui-export-tool" { Export-PortableToolPackage; [pscustomobject]@{ exported = $true } }
        default { throw "Unknown UI action: $Name" }
    }

    Write-UiJson -Value ([pscustomobject]@{
        ok = $true
        action = $Name
        result = $result
    })
}

if ($Action -like "ui-*") {
    try {
        Invoke-UiAction -Name $Action -Value $Argument -IncludeLoginState ([bool]$RestoreLogin)
        exit 0
    }
    catch {
        Write-UiJson -Value ([pscustomobject]@{
            ok = $false
            action = $Action
            error = $_.Exception.Message
        })
        exit 1
    }
}

switch ($Action) {
    "status" { Show-Status; exit }
    "backup" { New-Backup -IncludeLoginState $true; exit }
    "help" { Show-Help; exit }
    "profiles" { Show-LoginProfiles; exit }
    "save-chatgpt" { Save-CurrentChatGptProfile; exit }
    "first-login" { FirstLogin-WithApiKey; exit }
    "chatgpt-login" { Login-WithChatGptAccount; exit }
    "export-tool" { Export-PortableToolPackage; exit }
}

while ($true) {
    Show-Menu
    $selection = ""
    try {
        $rawSelection = Read-Host "  请选择功能"
        if ($null -eq $rawSelection) { break }
        $selection = $rawSelection.Trim().ToUpperInvariant()
        switch ($selection) {
            "0" { FirstLogin-WithApiKey }
            "1" { Show-Status }
            "2" { New-Backup -IncludeLoginState $true }
            "3" { New-Backup -IncludeLoginState $false }
            "4" { Verify-Backup }
            "5" { Restore-Backup }
            "6" { Enable-UnifiedHistory }
            "7" { Set-CustomApiAddress }
            "8" { Login-WithApiKey }
            "9" { Show-LoginStatus }
            "N" { Show-ApiNetworkMenu }
            "P" { Show-ProfileMenu }
            "A" { Open-ResumePicker }
            "E" { Export-PortableToolPackage }
            "L" {
                New-Item -ItemType Directory -Force -Path $backupDirectory | Out-Null
                Start-Process explorer.exe -ArgumentList $backupDirectory
            }
            "H" { Show-Help }
            "Q" { break }
            default { Write-Host "  [提示] 请输入菜单中的编号或字母。" -ForegroundColor Yellow }
        }
    }
    catch {
        Write-Host ("  [错误] {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
    if ($selection -ne "Q") {
        Write-Host ""
        [void](Read-Host "  按 Enter 返回主菜单")
    }
}
