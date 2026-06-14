$ErrorActionPreference = "Stop"
$source = $PSScriptRoot
$target = Join-Path $env:USERPROFILE ".codex\tools\history-manager"
New-Item -ItemType Directory -Force -Path $target | Out-Null

Copy-Item -LiteralPath (Join-Path $source "Codex-History-Manager.ps1") -Destination $target -Force
Copy-Item -LiteralPath (Join-Path $source "codex-history-core.mjs") -Destination $target -Force
if (Test-Path -LiteralPath (Join-Path $source "ui")) {
    Copy-Item -LiteralPath (Join-Path $source "ui") -Destination $target -Recurse -Force
    Remove-Item -LiteralPath (Join-Path $target "ui\private-assets") -Recurse -Force -ErrorAction SilentlyContinue
}
if (Test-Path -LiteralPath (Join-Path $source "README-zh.md")) {
    Copy-Item -LiteralPath (Join-Path $source "README-zh.md") -Destination (Join-Path $target "使用说明.md") -Force
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

$iconPath = Join-Path $target "ui\assets\line-usagi\app-icon.ico"
if (-not (Test-Path -LiteralPath $iconPath)) {
    $iconPath = Join-Path $target "ui\private-assets\line-usagi\app-icon.ico"
}
if (-not (Test-Path -LiteralPath $iconPath)) {
    $iconPath = Join-Path $target "ui\assets\app-icon.ico"
}
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
