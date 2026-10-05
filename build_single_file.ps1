# Automated Single-File Bundle Script for Most Advance Orderflow Analyzer
param(
    [switch]$SkipFlutterBuild = $false
)

$ErrorActionPreference = "Stop"
$rootDir = $PSScriptRoot
$orderflowDir = Join-Path $rootDir "orderflow"
$releaseDir = Join-Path $orderflowDir "build\windows\x64\runner\Release"
$stagingDir = Join-Path $rootDir "build_dist\staging"
$zipPath = Join-Path $rootDir "build_dist\payload.zip"
$iconPath = Join-Path $orderflowDir "windows\runner\resources\app_icon.ico"
$cscPath = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$isccPath = "C:\Users\PUTIN\AppData\Local\Programs\Inno Setup 6\ISCC.exe"

Write-Host "=== Building Single-File Windows Executable ===" -ForegroundColor Cyan

# 1. Flutter Build (optional if already built)
if (-not $SkipFlutterBuild) {
    Write-Host "`n[1/4] Building Flutter Windows application..." -ForegroundColor Yellow
    Get-Process -Name orderflow, MostAdvanceOrderflowAnalyzer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 1
    Push-Location $orderflowDir
    try {
        flutter build windows
    } finally {
        Pop-Location
    }
}

# 2. Stage files and create compressed payload
Write-Host "`n[2/4] Staging distribution files and creating compressed bundle..." -ForegroundColor Yellow
if (Test-Path $stagingDir) { Remove-Item -Recurse -Force $stagingDir }
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

Get-ChildItem -Path $releaseDir -Exclude *.lib, *.exp | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $stagingDir -Recurse -Force
}

if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)

# 3. Compile Portable Single-File Executable
Write-Host "`n[3/4] Compiling Portable Single-File Executable..." -ForegroundColor Yellow
$launcherCs = Join-Path $rootDir "build_dist\Launcher.cs"
$outPortableExe = Join-Path $rootDir "MostAdvanceOrderflowAnalyzer.exe"

& $cscPath `
    /target:winexe `
    /optimize+ `
    /platform:x64 `
    /win32icon:$iconPath `
    /resource:"$zipPath,payload.zip" `
    /reference:"C:\Windows\Microsoft.NET\Framework64\v4.0.30319\System.IO.Compression.dll" `
    /reference:"C:\Windows\Microsoft.NET\Framework64\v4.0.30319\System.IO.Compression.FileSystem.dll" `
    /reference:System.Windows.Forms.dll `
    /out:$outPortableExe `
    $launcherCs

# 4. Compile Inno Setup Single-File Installer
Write-Host "`n[4/4] Compiling Inno Setup Windows Installer..." -ForegroundColor Yellow
$issPath = Join-Path $rootDir "build_dist\installer.iss"
if (Test-Path $isccPath) {
    & $isccPath $issPath
}

# Cleanup staging files
Remove-Item -Recurse -Force $stagingDir, $zipPath -ErrorAction SilentlyContinue

# Also mirror to builds\windows directory
$buildsWinDir = Join-Path $rootDir "builds\windows"
if (-not (Test-Path $buildsWinDir)) { New-Item -ItemType Directory -Path $buildsWinDir -Force | Out-Null }
Get-Item "$rootDir\MostAdvanceOrderflowAnalyzer*.exe" | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $buildsWinDir -Force
}

Write-Host "`n=== Build Complete! ===" -ForegroundColor Green
Get-Item "$rootDir\MostAdvanceOrderflowAnalyzer*.exe" | Select-Object Name, @{Name="Size (MB)";Expression={[math]::Round($_.Length / 1MB, 2)}}, LastWriteTime | Format-Table -AutoSize

