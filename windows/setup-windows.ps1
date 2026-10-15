# setup-windows.ps1 - Windows-host side of the WSL setup. Idempotent.
#
#   - npiperelay.exe -> C:\Tools         (WSL ssh-agent bridge, YubiKey)
#   - Windows ssh-agent service           (Automatic + running; asks for UAC once)
#   - Meslo Nerd Font (per-user)          (Tide prompt glyphs)
#   - %USERPROFILE%\.wslconfig            (mirrored networking, no idle stop)
#   - Windows Terminal: Nerd Font on the WSL Ubuntu profile(s)
#
# Run as your NORMAL user (not elevated - everything here is per-user except
# the ssh-agent service, which elevates just that step). Keep this file ASCII:
# Windows PowerShell 5.1 reads BOM-less scripts as ANSI.
#   powershell -ExecutionPolicy Bypass -File \\wsl.localhost\<distro>\home\<user>\.local\share\chezmoi\windows\setup-windows.ps1

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # PS 5.1 progress bars make big downloads crawl
$here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$fontFace = 'MesloLGLDZ Nerd Font'
$isAdmin  = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

# --- npiperelay ---------------------------------------------------------------
Step 'npiperelay'
$relay = 'C:\Tools\npiperelay.exe'
if (Test-Path $relay) {
    Write-Host "    already at $relay"
} else {
    try {
        New-Item -ItemType Directory -Force -Path 'C:\Tools' | Out-Null
    } catch {
        # hardened images may not let normal users create folders under C:\
        try { Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile', '-Command', "New-Item -ItemType Directory -Force -Path 'C:\Tools'; icacls 'C:\Tools' /grant '$($env:USERNAME):(OI)(CI)M'" } catch {}
    }
    $zip = Join-Path $env:TEMP 'npiperelay.zip'
    Invoke-WebRequest -UseBasicParsing -OutFile $zip `
        'https://github.com/jstarks/npiperelay/releases/latest/download/npiperelay_windows_amd64.zip'
    $tmp = Join-Path $env:TEMP 'npiperelay'
    Expand-Archive -Force $zip $tmp
    Copy-Item (Join-Path $tmp 'npiperelay.exe') $relay
    Remove-Item -Recurse -Force $zip, $tmp
    Write-Host "    installed $relay"
}

# --- ssh-agent service --------------------------------------------------------
Step 'ssh-agent service'
$svc = Get-Service ssh-agent -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Warning 'OpenSSH client not installed (Settings -> Optional features -> OpenSSH Client)'
} elseif ($svc.StartType -ne 'Automatic' -or $svc.Status -ne 'Running') {
    $cmd = 'Set-Service ssh-agent -StartupType Automatic; Start-Service ssh-agent'
    if ($isAdmin) {
        Invoke-Expression $cmd
    } else {
        try {
            Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile', '-Command', $cmd
        } catch {
            Write-Warning "elevation declined/failed: $($_.Exception.Message)"
        }
    }
    $svc = Get-Service ssh-agent
    if ($svc.Status -eq 'Running' -and $svc.StartType -eq 'Automatic') { Write-Host '    enabled + started' }
    else { Write-Warning "ssh-agent still $($svc.Status) - run as admin: $cmd" }
} else {
    Write-Host '    already Automatic + Running'
}

# --- Meslo Nerd Font (per-user install, no admin needed) ----------------------
Step "font: $fontFace"
$userFonts = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
if (Get-ChildItem $userFonts, "$env:WINDIR\Fonts" -Filter 'MesloLGLDZNerdFont-*.ttf' -ErrorAction SilentlyContinue) {
    Write-Host '    already installed'
} else {
    $zip = Join-Path $env:TEMP 'Meslo.zip'
    Invoke-WebRequest -UseBasicParsing -OutFile $zip `
        'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip'
    $tmp = Join-Path $env:TEMP 'Meslo'
    Expand-Archive -Force $zip $tmp
    New-Item -ItemType Directory -Force -Path $userFonts | Out-Null
    $reg = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    Get-ChildItem $tmp -Filter 'MesloLGLDZNerdFont-*.ttf' | ForEach-Object {
        $dst = Join-Path $userFonts $_.Name
        Copy-Item $_.FullName $dst -Force
        New-ItemProperty -Path $reg -Name "$($_.BaseName) (TrueType)" -Value $dst -PropertyType String -Force | Out-Null
    }
    Remove-Item -Recurse -Force $zip, $tmp
    Write-Host '    installed (restart Windows Terminal to pick it up)'
}

# --- .wslconfig ---------------------------------------------------------------
Step '.wslconfig'
$src = Join-Path $here '.wslconfig'
$dst = Join-Path $env:USERPROFILE '.wslconfig'
$want = (Get-Content -Raw -Encoding UTF8 $src) -replace "`r?`n", "`r`n"
if ((Test-Path $dst) -and ((Get-Content -Raw -Encoding UTF8 $dst) -replace "`r?`n", "`r`n") -eq $want) {
    Write-Host '    up to date'
} else {
    # never overwrite an existing backup - first one is .bak, later ones timestamped
    if (Test-Path $dst) {
        $bak = if (Test-Path "$dst.bak") { "$dst.bak-$(Get-Date -Format yyyyMMddHHmmss)" } else { "$dst.bak" }
        Copy-Item $dst $bak; Write-Host "    backed up to $bak"
    }
    [IO.File]::WriteAllText($dst, $want)
    Write-Host '    written - run `wsl --shutdown` to apply'
}

# --- Windows Terminal: Nerd Font on the WSL Ubuntu profile(s) -----------------
# Set on per-profile entries (matched by the WSL fragment's guid) rather than
# profiles.defaults, so only the Ubuntu tabs get the Nerd Font.
Step 'Windows Terminal font'
$wtSettings = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
$wslGuids = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\Microsoft.WSL" -Filter '*.json' -ErrorAction SilentlyContinue |
    ForEach-Object { (Get-Content -Raw $_.FullName | ConvertFrom-Json).profiles } |
    Where-Object { $_.guid -and $_.'wsl.distribution-type' -eq 'ubuntu' } |
    ForEach-Object { $_.guid }

$snippet = @"
    In settings.json -> "profiles" -> "list", add/extend the Ubuntu entry:
        { "guid": "<Ubuntu profile guid>", "font": { "face": "$fontFace" } }
"@
if (-not $wtSettings) {
    Write-Warning "Windows Terminal settings.json not found - open Windows Terminal once, then re-run.`n$snippet"
} elseif (-not $wslGuids) {
    Write-Warning "No WSL Ubuntu profile fragment found.`n$snippet"
} else {
    try {
        $json = Get-Content -Raw -Encoding UTF8 $wtSettings | ConvertFrom-Json   # PS 5.1 fails on JSONC comments; PS 7 drops them (backup kept)
    } catch {
        $json = $null
        Write-Warning "Could not parse $wtSettings (comments? use PowerShell 7).`n$snippet"
    }
    if (-not $json) {
        Write-Warning "settings.json parsed to nothing.`n$snippet"
    } elseif (-not ($json.profiles -and $json.profiles.PSObject.Properties['list'])) {
        Write-Warning "Unexpected settings.json shape (no profiles.list).`n$snippet"
        $json = $null
    }
    if ($json) {
        $changed = $false
        foreach ($g in $wslGuids) {
            $p = @($json.profiles.list | Where-Object { $_.guid -eq $g })[0]
            if (-not $p) {
                $p = [pscustomobject]@{ guid = $g }
                $json.profiles.list = @($json.profiles.list) + $p
            }
            if ($p.font.face -ne $fontFace) {
                # change only the face - keep size/weight if already set
                if (-not $p.font) {
                    $p | Add-Member -Force -NotePropertyName font -NotePropertyValue ([pscustomobject]@{ face = $fontFace })
                } elseif ($p.font.PSObject.Properties['face']) {
                    $p.font.face = $fontFace
                } else {
                    $p.font | Add-Member -NotePropertyName face -NotePropertyValue $fontFace
                }
                $changed = $true
            }
        }
        if ($changed) {
            Copy-Item $wtSettings "$wtSettings.bak" -Force
            $json | ConvertTo-Json -Depth 32 | Set-Content -Encoding UTF8 $wtSettings
            Write-Host "    set font on $($wslGuids.Count) Ubuntu profile(s) (backup: settings.json.bak)"
        } else {
            Write-Host '    already set'
        }
    }
}

Write-Host "`nDone. Next: run 'wsl --shutdown' if .wslconfig changed, then continue in WSL." -ForegroundColor Green
