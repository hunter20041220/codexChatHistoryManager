$ErrorActionPreference = "Stop"
$source = $PSScriptRoot
$target = Join-Path $env:USERPROFILE ".codex\tools\history-manager"
New-Item -ItemType Directory -Force -Path $target | Out-Null

Copy-Item -LiteralPath (Join-Path $source "Codex-History-Manager.ps1") -Destination $target -Force
Copy-Item -LiteralPath (Join-Path $source "codex-history-core.mjs") -Destination $target -Force
Copy-Item -LiteralPath (Join-Path $source "README-zh.md") -Destination (Join-Path $target "使用说明.md") -Force

$desktopDirectory = [Environment]::GetFolderPath("Desktop")
if ([string]::IsNullOrWhiteSpace($desktopDirectory)) {
    $desktopDirectory = Join-Path $env:USERPROFILE "Desktop"
}
New-Item -ItemType Directory -Force -Path $desktopDirectory | Out-Null
$desktopEntry = Join-Path $desktopDirectory "Codex-Chat-History-Manager.cmd"
$desktopScript = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.codex\tools\history-manager\Codex-History-Manager.ps1" %*
"@
[IO.File]::WriteAllText($desktopEntry, $desktopScript, [Text.ASCIIEncoding]::new())

Write-Host ""
Write-Host "Installed to: $target" -ForegroundColor Green
Write-Host "Desktop shortcut: $desktopEntry" -ForegroundColor Green
Write-Host ""