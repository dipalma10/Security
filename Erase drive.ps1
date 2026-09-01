
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Please run PowerShell as Administrator!"
    Exit

$usbDrives = Get-Volume | Where-Type -FilterScript { $_.DriveType -eq 'Removable' -and $_.DriveLetter }

if ($usbDrives.Count -eq 0) {
    Write-Warning "No USB drives found with assigned drive 

if ($usbDrives.Count -eq 1) {
    $selectedDrive = $usbDrives[0]
    Write-Host "Found 1 USB drive: Drive $($selectedDrive.DriveLetter): ($($selectedDrive.FileSystemLabel))" -ForegroundColor Cyan
} else {
    Write-Host "Multiple USB drives detected:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $usbDrives.Count; $i++) {
        $drive = $usbDrives[$i]
        Write-Host " [$i] Drive $($drive.DriveLetter): - $($drive.FileSystemLabel) ($([math]::Round($drive.SizeRemaining/1GB, 2)) GB free)"
    }
    
    $selection = Read-Host "Select the drive number to target (0-$($usbDrives.Count - 1))"
    
    if ($selection -notmatch '^\d+$' -or [int]$selection -ge $usbDrives.Count) {
        Write-Error "Invalid selection. Script cancelled."
        Exit
    }
    $selectedDrive = $usbDrives[[int]$

$targetPath = "$($selectedDrive.DriveLetter):\"
$totalPasses = 7

Write-Host "`nTarget drive selected: $targetPath" -ForegroundColor Green
Write-Host "Starting 7 passes of cipher /w (3 wipes per pass = 21 total overwrites)...`n" -ForegroundColor Yellow

for ($i = 1; $i -le $totalPasses; $i++) {
    Write-Host "--- Starting Pass $i of $totalPasses on $targetPath ---" -ForegroundColor Cyan
    
    cipher /w:$targetPath
    
    Write-Host "Pass $i finished.`n" -ForegroundColor Green
}

Write-Host "All $totalPasses passes completed successfully on $targetPath!" -ForegroundColor Green
