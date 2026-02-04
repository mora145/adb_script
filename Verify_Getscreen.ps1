# --- CONFIGURATION ---
$executableName = "getscreen.exe" 
$executablePath = "C:\Program Files\Getscreen.me\Getscreen.exe" 
$remotePortTarget = 443
$checkIntervalSeconds = 60
$taskName = "Monitor_Getscreen_Watchdog"

$offlineThresholdMinutes = 30
$offlineStartTime = $null
# ---------------------

# 1. AUTO-ELEVATION LOGIC
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# 2. WATCHDOG TASK REGISTRATION (Every 1 minute)
$taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if (-not $taskExists) {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Normal -File `"$PSCommandPath`""
    $triggerStartup = New-ScheduledTaskTrigger -AtStartup
    $triggerRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 1)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($triggerStartup, $triggerRepeat) -Settings $settings -RunLevel Highest -Force
}

# 3. MAIN MONITORING LOOP
$processName = [System.IO.Path]::GetFileNameWithoutExtension($executableName)
Write-Host "--- Monitoring Started (Multi-PID Fixed) ---" -ForegroundColor Cyan

while ($true) {
    $timestamp = Get-Date -Format "HH:mm:ss"

    # A. INTERNET WATCHDOG
    $isConnected = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet -ErrorAction SilentlyContinue
    if ($isConnected) { $offlineStartTime = $null } else {
        if ($null -eq $offlineStartTime) { $offlineStartTime = Get-Date }
        if (((Get-Date) - $offlineStartTime).TotalMinutes -ge $offlineThresholdMinutes) {
            $response = (New-Object -ComObject "WScript.Shell").Popup("Internet offline. Rebooting in 2 mins.", 120, "Network Watchdog", 1 + 48)
            if ($response -eq 2) { $offlineStartTime = Get-Date } else { Restart-Computer -Force }
        }
    }

    # B. PROCESS & PORT MONITORING
    $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
    
    if ($processes) {
        $foundConnection = $false
        $allPids = $processes.Id 

        # Renamed variable to $procID to avoid "VariableNotWritable" error
        foreach ($procID in $allPids) {
            $connections = Get-NetTCPConnection -OwningProcess $procID -State Established -ErrorAction SilentlyContinue
            if ($connections | Where-Object { $_.RemotePort -eq $remotePortTarget }) {
                $foundConnection = $true
                $winningPid = $procID
                break
            }
        }

        if ($foundConnection) {
            Write-Host "[$timestamp] OK: $executableName connected (Found on PID $winningPid)." -ForegroundColor Green
        } else {
            Write-Host "[$timestamp] WARNING: No server connection on port $remotePortTarget." -ForegroundColor Yellow
            Write-Host "Checked PIDs: $($allPids -join ', ')" -ForegroundColor Gray
        }
    } else {
        Write-Host "[$timestamp] ALERT: $executableName not found." -ForegroundColor Red
        if (Test-Path $executablePath) { Start-Process -FilePath $executablePath -WorkingDirectory (Split-Path $executablePath -Parent) }
    }

    Start-Sleep -Seconds $checkIntervalSeconds
}