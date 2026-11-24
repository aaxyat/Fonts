# Install.ps1 - Modern Encrypted Font Installer Utility for Windows
# Usage: 
#   Normal Install: irm https://raw.githubusercontent.com/aaxyat/fonts/main/install.ps1 | iex
#   Dry Run Test:   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/aaxyat/fonts/main/install.ps1))) -DryRun

[CmdletBinding()]
param (
    [string]$Password,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# Set Console Output Encoding to UTF8 for clean Unicode characters
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function Draw-Header {
    try { Clear-Host } catch {}
    $modeText = if ($DryRun) { "               DRY RUN TEST MODE - NO PERMANENT SYSTEM CHANGES             " } else { "                Secure Archive Extraction & Utility               " }
    $modeColor = if ($DryRun) { "Yellow" } else { "Gray" }
    
    Write-Host "┌──────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "│                   AAXYAT PRIVATE FONT INSTALLER                  │" -ForegroundColor Cyan
    Write-Host "│$modeText│" -ForegroundColor $modeColor
    Write-Host "└──────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
    Write-Host ""
}

function Show-ProgressBar {
    param(
        [long]$Current,
        [long]$Total,
        [string]$Status,
        [int]$Width = 26
    )
    if ($Total -le 0) { $Total = 1 }
    $percent = [math]::Min(100, [math]::Max(0, [int](($Current / $Total) * 100)))
    $numFilled = [math]::Round(($percent / 100) * $Width)
    $numEmpty = $Width - $numFilled

    $filledBar = "█" * $numFilled
    $emptyBar = "░" * $numEmpty

    $paddedPercent = "{0,3}" -f $percent

    if ($Status.Length -gt 42) {
        $Status = $Status.Substring(0, 39) + "..."
    }

    $barStr = "`r  [$filledBar$emptyBar] $paddedPercent% | $Status"
    Write-Host $barStr -NoNewline -ForegroundColor Green
}

# 1. Startup Cleanup: Purge leftover temporary files from prior crashed/interrupted runs
try {
    Get-ChildItem -Path $env:TEMP -Filter "FontsInstall_*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
} catch {}

# Show Header & Authentication
Draw-Header

# Password Hash Verification (SHA-256 only; the password is never stored in this repository)
$ExpectedHash = "243284468d2d197ebb9cad8b191b7e6dc9cf2e790ad5af3ee7bd6fd0001d584d"

if (-not $Password) {
    Write-Host " [?] Authentication Required" -ForegroundColor Yellow
    $sec = Read-Host -Prompt "     Enter Password" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
}

$bytes = [System.Text.Encoding]::UTF8.GetBytes($Password)
$hasher = [System.Security.Cryptography.HashAlgorithm]::Create("SHA256")
$hashBytes = $hasher.ComputeHash($bytes)
$actualHash = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()

if ($actualHash -ne $ExpectedHash) {
    Write-Host "`n [!] AUTHENTICATION ERROR: Invalid password provided!" -ForegroundColor Red
    Write-Host "     Installation aborted.`n" -ForegroundColor Red
    exit 1
}

Write-Host "`n [✓] Authentication Successful!`n" -ForegroundColor Green

# 2. Setup Temporary Directories
$tempDir = Join-Path $env:TEMP "FontsInstall_$(Get-Random)"
$tempExtract = Join-Path $tempDir "Extracted"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null

try {
    # Check 7z executable locally, fallback to repo's shipped portable binary
    $7zExe = (Get-Command "7z" -ErrorAction SilentlyContinue).Source
    if (-not $7zExe) { $7zExe = (Get-Command "7zr" -ErrorAction SilentlyContinue).Source }
    if (-not $7zExe) { $7zExe = (Get-Command "NanaZipC" -ErrorAction SilentlyContinue).Source }

    if (-not $7zExe) {
        Write-Host " [i] Fetching bundled portable 7-Zip engine..." -ForegroundColor Yellow
        $repo7zUrl = "https://raw.githubusercontent.com/aaxyat/fonts/main/bin/7za.exe"
        $7zExe = Join-Path $tempDir "7za.exe"
        Invoke-WebRequest -Uri $repo7zUrl -OutFile $7zExe -UseBasicParsing -UserAgent "Mozilla/5.0"
        Write-Host " [✓] Portable 7-Zip engine ready." -ForegroundColor Green
    }

    # Check aria2c executable locally, fallback to repo's shipped portable binary
    $aria2Exe = (Get-Command "aria2c" -ErrorAction SilentlyContinue).Source
    if (-not $aria2Exe) {
        Write-Host " [i] Fetching bundled portable aria2 downloader..." -ForegroundColor Yellow
        $repoAriaUrl = "https://raw.githubusercontent.com/aaxyat/fonts/main/bin/aria2c.exe"
        $aria2Exe = Join-Path $tempDir "aria2c.exe"
        Invoke-WebRequest -Uri $repoAriaUrl -OutFile $aria2Exe -UseBasicParsing -UserAgent "Mozilla/5.0"
        Write-Host " [✓] Portable aria2 engine ready!" -ForegroundColor Green
    }

    # 3. Download Archive Volumes
    $repoRaw = "https://raw.githubusercontent.com/aaxyat/fonts/main/Fonts"
    $volumeCount = 6
    $estimatedTotalBytes = 192 * 1024 * 1024

    Write-Host " [↓] Concurrent Download of Encrypted Archives ($volumeCount volumes)..." -ForegroundColor Cyan

    $downloadUrls = @()
    for ($i = 1; $i -le $volumeCount; $i++) {
        $volName = "Fonts.7z.{0:D3}" -f $i
        $downloadUrls += "$repoRaw/$volName"
    }

    $useFallbackDownload = $false

    if ($aria2Exe -and (Test-Path $aria2Exe)) {
        $inputListPath = Join-Path $tempDir "urls.txt"
        $downloadUrls | Out-File -FilePath $inputListPath -Encoding utf8

        $ariaArgs = @(
            "-i", "`"$inputListPath`"",
            "-d", "`"$tempDir`"",
            "-j", "$volumeCount",
            "-x", "16",
            "-s", "16",
            "-k", "1M",
            "-q",
            "--console-log-level=error",
            "--download-result=hide",
            "--summary-interval=0"
        )
        
        $pInfo = New-Object System.Diagnostics.ProcessStartInfo
        $pInfo.FileName = $aria2Exe
        $pInfo.Arguments = ($ariaArgs -join " ")
        $pInfo.UseShellExecute = $false
        $pInfo.CreateNoWindow = $true
        $procAria = [System.Diagnostics.Process]::Start($pInfo)

        while (-not $procAria.HasExited) {
            $allVols = Get-ChildItem -Path $tempDir -Filter "Fonts.7z.*" -ErrorAction SilentlyContinue
            $downloadedBytes = 0
            $completedCount = 0

            if ($allVols) {
                $downloadedBytes = ($allVols | Measure-Object -Property Length -Sum).Sum
                
                foreach ($volFile in $allVols) {
                    if ($volFile.Extension -ne ".aria2") {
                        $ctrlFile = "$($volFile.FullName).aria2"
                        if (-not (Test-Path $ctrlFile)) {
                            $completedCount++
                        }
                    }
                }
            }
            
            $dlMB = [math]::Round($downloadedBytes / (1024 * 1024), 1)
            $totalMB = [math]::Round($estimatedTotalBytes / (1024 * 1024), 0)
            
            Show-ProgressBar -Current $downloadedBytes -Total $estimatedTotalBytes -Status "${dlMB}/${totalMB} MB | Vols: ${completedCount}/${volumeCount} Done"
            Start-Sleep -Milliseconds 150
        }

        if ($procAria.ExitCode -ne 0) {
            Write-Host "`n [!] Aria2 background task failed, switching to standard download..." -ForegroundColor Yellow
            $useFallbackDownload = $true
        } else {
            $finalFiles = Get-ChildItem -Path $tempDir -Filter "Fonts.7z.*" | Where-Object { $_.Extension -ne ".aria2" }
            $finalBytes = ($finalFiles | Measure-Object -Property Length -Sum).Sum
            $finalMB = [math]::Round($finalBytes / (1024 * 1024), 1)
            Show-ProgressBar -Current $finalBytes -Total $finalBytes -Status "${finalMB} MB | All ${volumeCount} Volumes Downloaded"
        }
    } else {
        $useFallbackDownload = $true
    }

    if ($useFallbackDownload) {
        for ($i = 1; $i -le $volumeCount; $i++) {
            $volName = "Fonts.7z.{0:D3}" -f $i
            $volUrl = "$repoRaw/$volName"
            $volPath = Join-Path $tempDir $volName
            Show-ProgressBar -Current $i -Total $volumeCount -Status "Vol ${i}/${volumeCount}: $volName"
            Invoke-WebRequest -Uri $volUrl -OutFile $volPath -UseBasicParsing
        }
    }

    Write-Host "`n [✓] Archives downloaded successfully!`n" -ForegroundColor Green

    # 4. Extracting Archives
    Write-Host " [⚙] Unpacking Font Package..." -ForegroundColor Cyan
    $firstVol = Join-Path $tempDir "Fonts.7z.001"
    
    $proc = Start-Process -FilePath $7zExe -ArgumentList "x `"$firstVol`" -p`"$Password`" -o`"$tempExtract`" -y" -Wait -NoNewWindow -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "Extraction failed. Invalid archive payload or password corruption."
    }
    Write-Host " [✓] Package unpacked successfully!`n" -ForegroundColor Green

    $fontFiles = Get-ChildItem -Path $tempExtract -Include "*.ttf", "*.otf" -Recurse
    $totalFonts = $fontFiles.Count

    if ($DryRun) {
        Write-Host " ┌──────────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
        Write-Host " │  [✓] DRY RUN SUCCESSFUL: Payload & $totalFonts fonts verified!           │" -ForegroundColor Yellow
        Write-Host " │      No system fonts were modified during this test run.        │" -ForegroundColor Yellow
        Write-Host " └──────────────────────────────────────────────────────────────────┘`n" -ForegroundColor Yellow
        return
    }

    # 5. Thread-Safe Parallel Font Copying & Registration
    Write-Host " [⚡] Installing $totalFonts Fonts (Parallel File Copy + Safe Registration)..." -ForegroundColor Cyan

    $userFontsDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
    if (-not (Test-Path $userFontsDir)) {
        New-Item -ItemType Directory -Path $userFontsDir -Force | Out-Null
    }

    $regPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"

    # GDI32 API Definition
    $gdi32 = Add-Type -MemberDefinition @"
[DllImport("gdi32.dll", CharSet=CharSet.Auto)]
public static extern int AddFontResource(string lpFileName);
[DllImport("gdi32.dll", CharSet=CharSet.Auto)]
public static extern bool RemoveFontResource(string lpFileName);
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern int SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
"@ -Name "SafeFontInstaller" -Namespace "WinAPI" -PassThru

    # Step A: High-Speed Thread-Safe File Copying (16 Threads)
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $fontFiles | ForEach-Object -Parallel {
            $dest = Join-Path $using:userFontsDir $_.Name
            try {
                [System.IO.File]::Copy($_.FullName, $dest, $true)
            } catch {}
        } -ThrottleLimit 16
    } else {
        foreach ($font in $fontFiles) {
            $dest = Join-Path $userFontsDir $font.Name
            try { Copy-Item -Path $font.FullName -Destination $dest -Force -ErrorAction SilentlyContinue } catch {}
        }
    }

    # Step B: Fast Single-Threaded Registry & GDI Registration
    $installedCount = 0
    foreach ($font in $fontFiles) {
        $installedCount++
        $destPath = Join-Path $userFontsDir $font.Name
        $fontName = $font.BaseName
        $ext = $font.Extension.ToUpper().TrimStart('.')
        $regName = "$fontName ($ext)"

        try {
            Set-ItemProperty -Path $regPath -Name $regName -Value $destPath -Force -ErrorAction SilentlyContinue
            [WinAPI.SafeFontInstaller]::AddFontResource($destPath) | Out-Null
        } catch {}

        Show-ProgressBar -Current $installedCount -Total $totalFonts -Status "$($font.Name)"
    }

    # 6. Windows Font Cache Reset & System Refresh
    Write-Host "`n`n [🔄] Resetting Windows Font Cache & Refreshing System..." -ForegroundColor Cyan

    try {
        Stop-Service -Name "FontCache" -Force -ErrorAction SilentlyContinue
        Stop-Service -Name "FontCache3.0.0.0" -Force -ErrorAction SilentlyContinue

        $cacheDirs = @(
            "$env:LOCALAPPDATA\FontCache",
            "$env:LOCALAPPDATA\Microsoft\FontCache"
        )
        foreach ($cd in $cacheDirs) {
            if (Test-Path $cd) {
                Get-ChildItem -Path $cd -Filter "*.dat" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }

        Start-Service -Name "FontCache" -ErrorAction SilentlyContinue
        Write-Host " [✓] Font cache purged & reinitialized!" -ForegroundColor Green
    } catch {
        Write-Host " [i] Font cache reset completed with partial service permissions." -ForegroundColor Gray
    }

    # Broadcast Font Change to Windows System
    $HWND_BROADCAST = [IntPtr]0xffff
    $WM_FONTCHANGE = 0x001D
    [WinAPI.SafeFontInstaller]::SendMessage($HWND_BROADCAST, $WM_FONTCHANGE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null

    Write-Host "`n ┌──────────────────────────────────────────────────────────────────┐" -ForegroundColor Green
    Write-Host " │  [✓] COMPLETE: $totalFonts fonts installed & font cache reset!            │" -ForegroundColor Green
    Write-Host " └──────────────────────────────────────────────────────────────────┘`n" -ForegroundColor Green

} finally {
    # Guaranteed Cleanup of temp binaries, downloaded volumes, and extracted files
    if ($tempDir -and (Test-Path $tempDir)) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
