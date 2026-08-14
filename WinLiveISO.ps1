<#
.SYNOPSIS
    Automated WinPE/WinRE Live ISO Builder with GUI, Wi-Fi Auto-Connect,
    Explorer++, Nmap, and Wireshark.
.NOTES
    Run as Administrator with Windows ADK installed.

Created by Mikael Palmqvist, 2026-07-23 version 0.5

#>

# Requires -RunAsAdministrator

# =========================================================================
# CONFIGURATION & PATHS (Update these to match your environment)
# =========================================================================
$AdkPath            = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit"
$OscdimgPath        = "$AdkPath\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
$WinPE_Arch         = "amd64"

# Source Base Image (Using winre.wim for full WLAN/Wi-Fi stack support)
$WinRE_Source_Path  = "C:\Windows\System32\Recovery\winre.wim" 

# Workspace Paths
$WorkDir            = "C:\WinPE_Build"
$MountDir           = "$WorkDir\mount"
$SourceDir          = "$WorkDir\media"
$IsoOutputPath      = "C:\WinPE_Live_Network_Suite.iso"

# Wi-Fi & Custom Branding Assets
$WiFiProfileXml     = "C:\WinPE_Build\Wi-Fi-YourWiFiSSID.xml" # Update with your exported XML filename
$TargetSSID         = "YourWiFiSSID"                          # Update with your Wi-Fi SSID
$DriverSourceFolder = "C:\WinPE_Drivers"                      # Folder containing .inf Wi-Fi drivers
$CustomWallpaperPath= "C:\WinPE_Build\wallpaper.jpg"         # Optional custom desktop wallpaper

# =========================================================================
# STEP 1: CLEANUP & DIRECTORY SETUP
# =========================================================================
Write-Host "[1/8] Preparing build workspace..." -ForegroundColor Cyan

if (Test-Path $WorkDir) {
    # Attempt clean unmount if a prior build failed
    Dismount-WindowsImage -Path $MountDir -Discard -ErrorAction SilentlyContinue
    # Clear directory structure except exported xml files
    Get-ChildItem -Path $WorkDir -Exclude "*.xml", "*.jpg" | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Path $WorkDir, $MountDir, $SourceDir -Force | Out-Null

# =========================================================================
# STEP 2: COPY BASE WINRE & ADK MEDIA FILES
# =========================================================================
Write-Host "[2/8] Setting up media environment and boot.wim..." -ForegroundColor Cyan

$WinPE_Media = "$AdkPath\Windows Preinstallation Environment\$WinPE_Arch\Media"

if (-not (Test-Path $OscdimgPath)) {
    Throw "Oscdimg.exe not found. Please verify Windows ADK installation."
}

if (-not (Test-Path $WinRE_Source_Path)) {
    Throw "winre.wim not found at $WinRE_Source_Path. Please copy winre.wim to this path."
}

Copy-Item -Path "$WinPE_Media\*" -Destination $SourceDir -Recurse -Force
Copy-Item -Path $WinRE_Source_Path -Destination "$SourceDir\sources\boot.wim" -Force

# =========================================================================
# STEP 3: MOUNT BOOT.WIM
# =========================================================================
Write-Host "[3/8] Mounting boot.wim..." -ForegroundColor Cyan
Mount-WindowsImage -ImagePath "$SourceDir\sources\boot.wim" -Index 1 -Path $MountDir

# =========================================================================
# STEP 4: INJECT ADK PACKAGES & OEM WI-FI DRIVERS
# =========================================================================
Write-Host "[4/8] Injecting ADK Optional Packages and Wi-Fi Drivers..." -ForegroundColor Cyan

$OcfPath = "$AdkPath\Windows Preinstallation Environment\$WinPE_Arch\WinPE_OCs"
$Packages = @(
    "WinPE-WMI.cab",
    "WinPE-NetFX.cab",
    "WinPE-Scripting.cab",
    "WinPE-PowerShell.cab",
    "WinPE-StorageWMI.cab",
    "WinPE-RNDIS.cab",
    "WinPE-Dot3Svc.cab"
)

foreach ($Pkg in $Packages) {
    $PkgPath = Join-Path $OcfPath $Pkg
    if (Test-Path $PkgPath) {
        Add-WindowsPackage -Path $MountDir -PackagePath $PkgPath -NoRestart | Out-Null
        $LangPkg = Join-Path $OcfPath "en-us\$($Pkg.Replace('.cab', '_en-us.cab'))"
        if (Test-Path $LangPkg) {
            Add-WindowsPackage -Path $MountDir -PackagePath $LangPkg -NoRestart | Out-Null
        }
    }
}

# Inject OEM Drivers (.inf)
if ((Test-Path $DriverSourceFolder) -and (Get-ChildItem -Path $DriverSourceFolder -Filter "*.inf" -Recurse)) {
    Write-Host " Injecting Wi-Fi NIC drivers from $DriverSourceFolder..." -ForegroundColor Green
    Add-WindowsDriver -Path $MountDir -Driver $DriverSourceFolder -Recurse -ForceUnsigned | Out-Null
} else {
    Write-Warning "No .inf drivers found in $DriverSourceFolder. Skipping driver injection."
}

# =========================================================================
# STEP 5: INJECT TOOLS (Explorer++, Nmap, Wireshark)
# =========================================================================
Write-Host "[5/8] Injecting portable diagnostic tools..." -ForegroundColor Cyan

$ToolsDir     = "$MountDir\Tools"
$NmapDir      = "$ToolsDir\Nmap"
$WiresharkDir = "$ToolsDir\Wireshark"

New-Item -ItemType Directory -Path $ToolsDir, $NmapDir, $WiresharkDir -Force | Out-Null

# 1. Download Explorer++ Portable
$ExplorerZip = "$WorkDir\ExplorerPlusPlus.zip"
$ExplorerUrl = "https://explorerplusplus.com/software/downloads/explorer++_1.4.0_x64.zip"
try {
    Invoke-WebRequest -Uri $ExplorerUrl -OutFile $ExplorerZip -UseBasicParsing
    Expand-Archive -Path $ExplorerZip -DestinationPath $ToolsDir -Force
    Remove-Item $ExplorerZip -Force
    Write-Host " Explorer++ extracted successfully." -ForegroundColor Green
} catch {
    Write-Warning "Failed to auto-download Explorer++. Copy manually to $ToolsDir."
}

# 2. Download Nmap Portable
$NmapZip = "$WorkDir\nmap.zip"
$NmapUrl = "https://nmap.org/dist/nmap-7.95-win32.zip"
try {
    Invoke-WebRequest -Uri $NmapUrl -OutFile $NmapZip -UseBasicParsing
    Expand-Archive -Path $NmapZip -DestinationPath "$WorkDir\NmapTemp" -Force
    Get-ChildItem -Path "$WorkDir\NmapTemp\nmap-*" | Copy-Item -Destination $NmapDir -Recurse -Force
    Remove-Item $NmapZip, "$WorkDir\NmapTemp" -Recurse -Force
    Write-Host " Nmap integrated successfully." -ForegroundColor Green
} catch {
    Write-Warning "Failed to auto-download Nmap archive. Copy manually to $NmapDir."
}

# Copy Wi-Fi Profile XML into System32 inside RAMDisk
if (Test-Path $WiFiProfileXml) {
    Copy-Item -Path $WiFiProfileXml -Destination "$MountDir\Windows\System32\wifi-profile.xml" -Force
    Write-Host " Wi-Fi Profile copied into image." -ForegroundColor Green
} else {
    Write-Warning "Wi-Fi profile XML not found at $WiFiProfileXml. Auto-connect won't run until profile is added."
}

# Optional Custom Wallpaper
if (Test-Path $CustomWallpaperPath) {
    $WinPEWallpaperTarget = "$MountDir\Windows\System32\winpe.jpg"
    takeown /f $WinPEWallpaperTarget /a | Out-Null
    icacls $WinPEWallpaperTarget /grant "Administrators:F" | Out-Null
    Copy-Item -Path $CustomWallpaperPath -Destination $WinPEWallpaperTarget -Force
}

# =========================================================================
# STEP 6: CONFIGURE AUTO-STARTUP & WI-FI AUTO-CONNECT
# =========================================================================
Write-Host "[6/8] Configuring startup scripts and shell auto-launch..." -ForegroundColor Cyan

# 1. winpeshl.ini (launches Explorer++ and command shell)
$WinPeShlIni = "$MountDir\Windows\System32\winpeshl.ini"
@"
[LaunchApps]
"%SystemDrive%\Tools\Explorer++.exe"
"%SystemDrive%\Windows\System32\cmd.exe", "/k title Live Diagnostics Console"
"@ | Out-File -FilePath $WinPeShlIni -Encoding ascii -Force

# 2. startnet.cmd (Initializes WLAN service and auto-connects Wi-Fi)
$StartnetCmd = "$MountDir\Windows\System32\startnet.cmd"
@"
@echo off
wpeinit
netstart /w

:: Set Environment Paths for tools
set PATH=%PATH%;X:\Tools;X:\Tools\Nmap;X:\Tools\Wireshark

:: Initialize WLAN Service
echo [Auto-WiFi] Starting WLAN service...
net start wlansvc >nul 2>&1

:: Pause briefly for wireless NIC startup
timeout /t 3 /nobreak >nul

:: Import Wi-Fi XML Profile and Initiate Auto-Connection
if exist "%SystemRoot%\System32\wifi-profile.xml" (
    echo [Auto-WiFi] Adding network profile...
    netsh wlan add profile filename="%SystemRoot%\System32\wifi-profile.xml" user=all >nul
    
    echo [Auto-WiFi] Connecting to $TargetSSID...
    netsh wlan connect name="$TargetSSID"
)

cls
echo ========================================================
echo       Live Windows Network Diagnostics Environment
echo ========================================================
echo Target Wireless Network: $TargetSSID
echo CLI Utilities Ready: nmap, nping, tshark, netsh
echo.
"@ | Out-File -FilePath $StartnetCmd -Encoding ascii -Force

# =========================================================================
# STEP 7: SAVE & UNMOUNT WIM
# =========================================================================
Write-Host "[7/8] Unmounting and committing image changes..." -ForegroundColor Cyan
Dismount-WindowsImage -Path $MountDir -Commit

# =========================================================================
# STEP 8: COMPILE BOOTABLE ISO
# =========================================================================
Write-Host "[8/8] Compiling bootable ISO with Oscdimg..." -ForegroundColor Cyan

$EfiBootCode = "$SourceDir\efisys.bin"
$EfiBootFile = "$SourceDir\boot\etfsboot.com"

$OscdArguments = @(
    "-m",
    "-o",
    "-u2",
    "-udfver102",
    "-bootdata:2#p0,e,b""$EfiBootFile""#pEF,e,b""$EfiBootCode""",
    """$SourceDir""",
    """$IsoOutputPath"""
)

Start-Process -FilePath $OscdimgPath -ArgumentList ($OscdArguments -join " ") -Wait -NoNewWindow

if (Test-Path $IsoOutputPath) {
    Write-Host "`n========================================================" -ForegroundColor Green
    Write-Host " SUCCESS: Custom Live ISO compiled at:" -ForegroundColor Green
    Write-Host " $IsoOutputPath" -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Green
} else {
    Write-Error "Failed to build ISO file."
}
