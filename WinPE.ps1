<#
.SYNOPSIS
    Automated WinPE Live ISO Builder with GUI, Wi-Fi Auto-Connect,
    Explorer++, Nmap, and Wireshark.
.NOTES
    Run as Administrator with Windows ADK installed.
    Requires Windows ADK and WinPE Add-on for ADK installed.
    Must be run from an Administrator PowerShell session.

Created by Mikael Palmqvist, 2026-07-23 version 0.5

#>

Reminders Before Running
Npcap Drivers: Place your extracted Npcap files (⁠npcap.inf⁠, ⁠npcap.sys⁠, ⁠npcap.cat⁠) into ⁠C:\Npcap_Driver⁠ beforehand.
Background File: Point ⁠$WallpaperPath⁠ to a 24-bit ⁠.bmp⁠ image file.
 

# Force TLS 1.2 / 1.3 for external file downloads
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# ==============================================================================
# CONFIGURATION
# ==============================================================================
$BuildRootDir    = "C:\WinPE_MasterBuild"
$WallpaperPath   = "C:\Path\To\Your\Background.bmp" # Must be a 24-bit .BMP file
$NpcapDriverPath = "C:\Npcap_Driver"                # Folder containing npcap.inf, npcap.sys, etc.
$IsoOutputPath   = "C:\Custom_Security_WinPE.iso"

# Sub-directory Layout
$DownloadDir     = "$BuildRootDir\Downloads"
$SourceToolsDir  = "$BuildRootDir\SourceTools"
$NmapExtractPath = "$SourceToolsDir\Nmap"
$WSxtractPath    = "$SourceToolsDir\Wireshark"
$MediaDir        = "$BuildRootDir\media"
$MountDir        = "$BuildRootDir\mount"
$FwFilesDir      = "$BuildRootDir\fwfiles"

# ADK Paths (Standard x64 ADK Install)
$AdkPath     = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit"
$WinPeOcPath = "$AdkPath\Windows Preinstallation Environment\amd64\WinPE_OCs"
$OscdImg     = "$AdkPath\Deployment Tools\amd64\Oscdimg\oscdimg.exe"

# ==============================================================================
# 1. INITIAL CLEANUP & DIRECTORY PREPARATION
# ==============================================================================
Write-Host "[1/7] Preparing workspace directories..." -ForegroundColor Green
if (Test-Path $BuildRootDir) { 
    Write-Host "Cleaning up old build directory..." -ForegroundColor Yellow
    Remove-Item $BuildRootDir -Recurse -Force -ErrorAction SilentlyContinue 
}

$Directories = @($DownloadDir, $SourceToolsDir, $NmapExtractPath, $WSxtractPath, $MediaDir, $MountDir, $FwFilesDir)
foreach ($Dir in $Directories) {
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
}

# ==============================================================================
# 2. DOWNLOAD & EXTRACT PORTABLE TOOLS (NMAP & WIRESHARK)
# ==============================================================================
Write-Host "[2/7] Fetching portable Nmap and Wireshark..." -ForegroundColor Green

# --- Download Nmap ---
$NmapZipUrl = "https://nmap.org/dist/nmap-7.95-win32.zip"
$NmapZipFile = "$DownloadDir\nmap.zip"
Write-Host " Downloading Nmap..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $NmapZipUrl -OutFile $NmapZipFile -UseBasicParsing
Expand-Archive -Path $NmapZipFile -DestinationPath $DownloadDir -Force

$ExtractedNmapFolder = Get-ChildItem -Path $DownloadDir -Filter "nmap-*" -Directory | Select-Object -First 1
if ($ExtractedNmapFolder) {
    Copy-Item -Path "$($ExtractedNmapFolder.FullName)\*" -Destination $NmapExtractPath -Recurse -Force
    Remove-Item $ExtractedNmapFolder.FullName -Recurse -Force
}

# --- Download Wireshark ---
Write-Host " Fetching latest Wireshark Portable release..." -ForegroundColor Cyan
try {
    $WiresharkHtml = Invoke-WebRequest -Uri "https://www.wireshark.org/download.html" -UseBasicParsing
    $WiresharkZipUrl = ($WiresharkHtml.Links | Where-Object { $_.href -like "*WiresharkPortable64*.zip" } | Select-Object -First 1).href
} catch { $WiresharkZipUrl = $null }

if (-not $WiresharkZipUrl) {
    $WiresharkZipUrl = "https://www.wireshark.org/download/win64/WiresharkPortable64_latest.zip"
}

$WiresharkZipFile = "$DownloadDir\wireshark.zip"
Write-Host " Downloading Wireshark from $WiresharkZipUrl..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $WiresharkZipUrl -OutFile $WiresharkZipFile -UseBasicParsing
Expand-Archive -Path $WiresharkZipFile -DestinationPath $WSxtractPath -Force

# Flatten Wireshark folder if nested
$NestedWsFolder = Get-ChildItem -Path $WSxtractPath -Directory | Select-Object -First 1
if ($NestedWsFolder -and (Test-Path "$($NestedWsFolder.FullName)\wireshark.exe")) {
    Move-Item -Path "$($NestedWsFolder.FullName)\*" -Destination $WSxtractPath -Force
    Remove-Item $NestedWsFolder.FullName -Recurse -Force
}

# Clean up ZIP archives
Remove-Item -Path "$DownloadDir\*.zip" -Force -ErrorAction SilentlyContinue

# ==============================================================================
# 3. MOUNT WINPE BASE IMAGE
# ==============================================================================
Write-Host "[3/7] Staging and Mounting WinPE base image..." -ForegroundColor Green
Copy-Item "$AdkPath\Windows Preinstallation Environment\amd64\en-us\winpe.wim" "$MediaDir\sources\boot.wim" -Force
Copy-Item "$AdkPath\Deployment Tools\amd64\Oscdimg\efisys.bin" "$FwFilesDir\efisys.bin" -Force
Copy-Item "$AdkPath\Deployment Tools\amd64\Oscdimg\etfsboot.com" "$FwFilesDir\etfsboot.com" -Force

Mount-WindowsImage -ImagePath "$MediaDir\sources\boot.wim" -Index 1 -Path $MountDir

# ==============================================================================
# 4. ADD POWERSHELL & DRIVERS (NPCAP)
# ==============================================================================
Write-Host "[4/7] Injecting PowerShell optional components and Npcap driver..." -ForegroundColor Green

# Add PowerShell support to WinPE
$Packages = @(
    "WinPE-WMI.cab",
    "WinPE-NetFX.cab",
    "WinPE-Scripting.cab",
    "WinPE-PowerShell.cab",
    "WinPE-StorageWMI.cab"
)

foreach ($Pkg in $Packages) {
    Write-Host " Adding package: $Pkg" -ForegroundColor Cyan
    Add-WindowsPackage -Path $MountDir -PackagePath "$WinPeOcPath\$Pkg" -NoRestart | Out-Null
}

# Inject Npcap driver
if (Test-Path "$NpcapDriverPath\npcap.inf") {
    Write-Host " Injecting Npcap driver..." -ForegroundColor Cyan
    Add-WindowsDriver -Path $MountDir -Driver $NpcapDriverPath -Recurse -ForceUnsigned | Out-Null
} else {
    Write-Warning " Npcap driver not found at $NpcapDriverPath. Skipping driver injection."
}

# ==============================================================================
# 5. INJECT TOOLS, WALLPAPER & STARTUP SCRIPT
# ==============================================================================
Write-Host "[5/7] Copying tools, wallpaper, and setting up shell environment..." -ForegroundColor Green

# Copy portable tools into the image
$ToolsDir = "$MountDir\Tools"
New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null
Copy-Item -Path "$NmapExtractPath\*" -Destination "$ToolsDir\Nmap" -Recurse -Force
Copy-Item -Path "$WSxtractPath\*" -Destination "$ToolsDir\Wireshark" -Recurse -Force

# Replace custom background
if (Test-Path $WallpaperPath) {
    Write-Host " Replacing background image..." -ForegroundColor Cyan
    Copy-Item -Path $WallpaperPath -Destination "$MountDir\Windows\System32\winpe.bmp" -Force
} else {
    Write-Warning " Custom background image not found at $WallpaperPath. Retaining default."
}

# Configure startnet.cmd to run driver service and boot straight into PowerShell
$StartnetPath = "$MountDir\Windows\System32\startnet.cmd"
$StartnetContent = @"
@echo off
wpeinit

:: Start Npcap Service
net start npcap

:: Add tools to Environment PATH
set PATH=%PATH%;X:\Tools\Nmap;X:\Tools\Wireshark
cls

echo ==========================================
echo    Custom Security WinPE Shell Started
echo ==========================================
echo Tools available in PATH: nmap, wireshark
echo.
powershell.exe -NoExit -ExecutionPolicy Bypass
"@

Set-Content -Path $StartnetPath -Value $StartnetContent -Encoding ASCII

# ==============================================================================
# 6. UNMOUNT & COMMIT WIM
# ==============================================================================
Write-Host "[6/7] Committing changes and unmounting WinPE WIM..." -ForegroundColor Green
Dismount-WindowsImage -Path $MountDir -Save

# ==============================================================================
# 7. GENERATE BOOTABLE ISO
# ==============================================================================
Write-Host "[7/7] Compiling bootable ISO image with oscdimg..." -ForegroundColor Green
$OscdArgs = "-m -o -u2 -udfver102 -bootdata:2#p0,e,b""$FwFilesDir\etfsboot.com""#pEF,e,b""$FwFilesDir\efisys.bin"" ""$MediaDir"" ""$IsoOutputPath"""

Start-Process -FilePath $OscdImg -ArgumentList $OscdArgs -Wait -NoNewWindow

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host " Master WinPE ISO successfully generated at:" -ForegroundColor Green
Write-Host " $IsoOutputPath" -ForegroundColor Yellow
Write-Host "=======================================================" -ForegroundColor Green
