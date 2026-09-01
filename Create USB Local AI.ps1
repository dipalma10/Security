Clear-Host
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "    llamafile Model Downloader Tool       " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$targetDrive = Get-Volume | Where-ObjectType FileSystemLabel -eq 'LLAMAFILE'

if (-not $targetDrive) {
    Write-Host "No drive labeled 'LLAMAFILE' found. Searching for available removable drives..." -ForegroundColor Yellow
    $usbDrives = Get-Volume | Where-ObjectType DriveType -eq 'Removable'
    
    if (-not $usbDrives) {
        Write-Host "Error: No removable USB drives detected. Please insert your USB drive and try again." -ForegroundColor Red
        exit
    }
    
    if ($usbDrives.Count -eq 1) {
        $targetDrive = $usbDrives[0]
    } else {
        Write-Host "Select a USB drive to save the llamafile to:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $usbDrives.Count; $i++) {
            $d = $usbDrives[$i]
            Write-Host " [$i] Drive $($d.DriveLetter): ($($d.FileSystemLabel)) - $([math]::Round($d.SizeRemaining / 1GB, 2)) GB free" -ForegroundColor White
        }
        $selection = Read-Host "Select drive index (0 to $($usbDrives.Count - 1))"
        if ($selection -match '^\d+$' -and [int]$selection -lt $usbDrives.Count -and [int]$selection -ge 0) {
            $targetDrive = $usbDrives[[int]$selection]
        } else {
            Write-Host "Invalid selection. Aborting." -ForegroundColor Red
            exit
        }
    }
}

$drivePath = "$($targetDrive.DriveLetter):\"
Write-Host "Target Drive set to: $drivePath ($($targetDrive.FileSystemLabel))" -ForegroundColor Green
Write-Host ""

$models = @(
    @{
        Name        = "Llama 3 8B Instruct (Q4_K_M)"
        FileName    = "Meta-Llama-3-8B-Instruct.Q4_K_M.llamafile"
        Url         = "https://huggingface.co/Mozilla/Meta-Llama-3-8B-Instruct-llamafile/resolve/main/Meta-Llama-3-8B-Instruct.Q4_K_M.llamafile"
        ApproxSize  = "4.9 GB"
    },
    @{
        Name        = "Mistral 7B Instruct v0.2 (Q4_K_M)"
        FileName    = "mistral-7b-instruct-v0.2.Q4_K_M.llamafile"
        Url         = "https://huggingface.co/Mozilla/Mistral-7B-Instruct-v0.2-llamafile/resolve/main/mistral-7b-instruct-v0.2.Q4_K_M.llamafile"
        ApproxSize  = "4.3 GB"
    },
    @{
        Name        = "Phi-3 Mini 4K Instruct (Q4_K_M)"
        FileName    = "Phi-3-mini-4k-instruct.Q4_K_M.llamafile"
        Url         = "https://huggingface.co/Mozilla/Phi-3-mini-4k-instruct-llamafile/resolve/main/Phi-3-mini-4k-instruct.Q4_K_M.llamafile"
        ApproxSize  = "2.4 GB"
    }
)

Write-Host "Select a llamafile model to download:" -ForegroundColor Yellow
for ($i = 0; $i -lt $models.Count; $i++) {
    Write-Host " [$i] $($models[$i].Name) (~$($models[$i].ApproxSize))" -ForegroundColor White
}

Write-Host ""
$choice = Read-Host "Enter the number of your choice (0 to $($models.Count - 1))"

if ($choice -notmatch '^\d+$' -or [int]$choice -ge $models.Count -or [int]$choice -lt 0) {
    Write-Host "Invalid model selection. Aborting." -ForegroundColor Red
    exit
}

$selectedModel = $models[[int]$choice]
$destinationPath = Join-Path -Path $drivePath -ChildPath $selectedModel.FileName

Write-Host ""
Write-Host "Downloading: $($selectedModel.Name)" -ForegroundColor Cyan
Write-Host "Destination: $destinationPath" -ForegroundColor Cyan
Write-Host "Please wait, this may take a while depending on your internet connection..." -ForegroundColor Yellow
Write-Host ""

try {
    Import-Module BitsTransfer
    Start-BitsTransfer -Source $selectedModel.Url -Destination $destinationPath -DisplayName "Downloading $($selectedModel.FileName)"
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host " Download Complete!" -ForegroundColor Green
    Write-Host " File saved to: $destinationPath" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "To run your local LLM on Windows:" -ForegroundColor White
    Write-Host " 1. Open Command Prompt (cmd) or PowerShell." -ForegroundColor White
    Write-Host " 2. Navigate to your USB drive: $drivePath" -ForegroundColor White
    Write-Host " 3. Run: .\$($selectedModel.FileName)" -ForegroundColor White
    Write-Host " 4. Open your browser to http://localhost:8080" -ForegroundColor White
}
catch {
    Write-Host ""
    Write-Host "BITS transfer failed. Falling back to Invoke-WebRequest..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $selectedModel.Url -OutFile $destinationPath
    Write-Host "Download complete!" -ForegroundColor Green
}
