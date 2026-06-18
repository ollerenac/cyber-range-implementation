# =============================================================================
# 07-security-baseline.ps1 — D-12 security baseline for all 5 Windows VMs
#
# LOCKED SPECS (do NOT change without updating D-12 in 02-CONTEXT.md):
#   Defender disabled     — required for CALDERA agent, file_generator, Mimikatz to run
#   UAC = Never Notify    — required for privilege escalation TTPs
#   WDigest = 1           — required for APT29 Scenario 2 LSASS credential dump
#   Auto-updates disabled — prevents patch disruption during emulation runs
#   Visual C++ (x86+x64) — required by Exchange prereqs and CALDERA payloads
#   QEMU Guest Agent      — required for qm snapshot --quiesce (Phase 3 clean_state)
#   WinRM reinforced      — required for Phase 3 Elastic Agent enrollment over WinRM
#
# USAGE (run from control node for each VM):
#   Invoke-Command -ComputerName <IP> -Credential $cred -FilePath .\07-security-baseline.ps1
#
# PREREQUISITES (copy to C:\Temp\ on each VM before running):
#   C:\Temp\vcredist_x86.exe   — Visual C++ Redistributable x86 (2015-2022 bundle)
#   C:\Temp\vcredist_x64.exe   — Visual C++ Redistributable x64 (2015-2022 bundle)
#   C:\Temp\qemu-ga-x86_64.msi — from virtio-win ISO guest-agent\ directory
#
# EXECUTION ORDER:
#   Run 07-security-baseline.ps1 on ALL 5 VMs BEFORE running 08-workstations.ps1
#   Reason: Defender must be off before file_generator.exe runs (Pitfall 8)
#
# VM IPs: dc01=10.0.0.11, exchange01=10.0.0.12, sql01=10.0.0.13, ws01=10.0.0.14, ws02=10.0.0.15
# =============================================================================

$ErrorActionPreference = "Continue"

Write-Host "================================================================"
Write-Host " 07-security-baseline.ps1 — D-12 settings"
Write-Host " Host: $env:COMPUTERNAME"
Write-Host "================================================================"

# ============================================================
# SECTION 1: Disable Windows Defender
# Source: github/adversary_emulation_library/oilrig/Resources/setup/modify-defender.ps1
# Copied verbatim — all -ErrorAction Continue flags preserved
# Required: Defender must be off BEFORE file_generator.exe runs (Pitfall 8)
# ============================================================

Write-Host "[1/8] Disabling Windows Defender (D-12)"

# Add RegKey Path as it does not exist on the DC
Write-Host "[i] Disabling Windows Defender"
New-Item -Path "HKLM:\SOFTWARE\Wow6432Node\Policies\Microsoft\" -Name "Windows Defender" -ErrorAction Continue
Set-ItemProperty "HKLM:\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows Defender" "DisableAntiSpyware" 1
New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft' -Name "Windows Defender" -Force -ErrorAction Continue
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Value 1 -PropertyType DWORD -Force -ErrorAction Continue
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableRoutinelyTakingAction" -Value 1 -PropertyType DWORD -Force -ErrorAction Continue
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Name "SpyNetReporting" -Value 0 -PropertyType DWORD -Force -ErrorAction Continue
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Name "SubmitSamplesConsent" -Value 0 -PropertyType DWORD -Force -ErrorAction Continue
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\MRT" -Name "DontReportInfectionInformation" -Value 1 -PropertyType DWORD -Force -ErrorAction Continue

# set preferences for Windows Defender scans and updates - may error out if Defender is already disabled
Set-MpPreference -DisableRealtimeMonitoring $true -DisableBehaviorMonitoring $true `
-DisableIntrusionPreventionSystem $true -DisableIOAVProtection $true -DisableScriptScanning $true `
-DisableArchiveScanning $true -DisableCatchupFullScan $true -DisableCatchupQuickScan $true `
-DisableEmailScanning $true -DisableRemovableDriveScanning $true -DisableScanningMappedNetworkDrivesForFullScan $true `
-DisableScanningNetworkFiles $true -SignatureDisableUpdateOnStartupWithoutEngine $true -DisableBlockAtFirstSeen $true `
-SevereThreatDefaultAction 6 -MAPSReporting 0 -HighThreatDefaultAction 6 -ModerateThreatDefaultAction 6 -LowThreatDefaultAction 6 `
-SubmitSamplesConsent 2 -ErrorAction Continue

# exclude C drive from A/V scans - may error out if Defender is already disabled
Add-MpPreference -ExclusionPath "C:\" -ErrorAction Continue

# modify defender to disable real-time protection
New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -Name "Real-Time Protection" -Force -ErrorAction Continue
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableRealtimeMonitoring" -Value 1 -PropertyType DWORD -Force -ErrorAction Continue

Write-Host "[i] Defender registry keys and preferences set"

# ============================================================
# SECTION 2: Disable Automatic Updates
# Source: github/adversary_emulation_library/oilrig/Resources/setup/disable-automatic-updates.ps1
# Copied verbatim
# ============================================================

Write-Host "[2/8] Disabling automatic Windows updates (D-12)"

# set the Windows Update service to "disabled"
sc.exe config wuauserv start=disabled

# display the status of the service
sc.exe query wuauserv

# stop the service, in case it is running
sc.exe stop wuauserv

sc.exe query wuauserv

# double check it's REALLY disabled - Start value should be 0x4
REG.exe QUERY HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\wuauserv /v Start

# Set AutoUpdate to not check for updates
$AUSettings = (New-Object -com "Microsoft.Update.AutoUpdate").Settings
$AUSettings.NotificationLevel = 1
$AUSettings.Save

Write-Host "[i] Windows Update service disabled and NotificationLevel=1 (no auto-check)"

# ============================================================
# SECTION 3: Enable / Reinforce WinRM
# Source: github/adversary_emulation_library/wizard_spider/Resources/setup/enable-winrm.ps1
# Copied verbatim — WinRM was enabled in autounattend.xml; this reinforces it
# Required for Phase 3 Elastic Agent enrollment via WinRM
# ============================================================

Write-Host "[3/8] Reinforcing WinRM (D-12)"

# Enable PSRemoting and trust all hosts
Write-Host "[i] Enabling WinRM"
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force

# permit WMI through firewall
netsh advfirewall firewall add rule dir=in name="DCOM" action=allow protocol=TCP localport=135
netsh advfirewall firewall add rule dir=in name="WMI" program=%systemroot%\system32\svchost.exe service=winmgmt action=allow protocol=TCP localport=any

Write-Host "[i] WinRM enabled, TrustedHosts=*, DCOM/WMI firewall rules added"

# ============================================================
# SECTION 4: Set UAC to Never Notify
# Source: 02-RESEARCH.md Example 3
# Required: privilege escalation TTPs (T1548.002)
# ============================================================

Write-Host "[4/8] Setting UAC to Never Notify (D-12)"

# Set UAC to "Never notify"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
  -Name "EnableLUA" -Value 0 -Type DWORD
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
  -Name "ConsentPromptBehaviorAdmin" -Value 0 -Type DWORD

Write-Host "[i] UAC: EnableLUA=0, ConsentPromptBehaviorAdmin=0"

# ============================================================
# SECTION 5: Enable WDigest UseLogonCredential
# Source: 02-RESEARCH.md Example 2
# Required: APT29 Scenario 2 — LSASS credential dump (T1003.001)
#           WDigest=1 causes Windows to cache cleartext credentials in LSASS
# ============================================================

Write-Host "[5/8] Enabling WDigest UseLogonCredential (D-12 — APT29 S2 requirement)"

Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest" `
  -Name "UseLogonCredential" -Value 1 -Type DWORD

Write-Host "[i] WDigest UseLogonCredential=1 — cleartext creds cached in LSASS after next logon"

# ============================================================
# SECTION 6: Install Visual C++ Redistributable x86 + x64
# Required: Exchange prereqs, CALDERA payloads, Mimikatz dependencies
# PREREQUISITE: Operator must copy installers to C:\Temp\ before running this script
#   vcredist_x86.exe — Microsoft Visual C++ 2015-2022 Redistributable (x86)
#   vcredist_x64.exe — Microsoft Visual C++ 2015-2022 Redistributable (x64)
#   Download: https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist
# ============================================================

Write-Host "[6/8] Installing Visual C++ Redistributables (D-12)"

$vcx86 = "C:\Temp\vcredist_x86.exe"
$vcx64 = "C:\Temp\vcredist_x64.exe"

if (Test-Path $vcx86) {
    Write-Host "[i] Installing VC++ Redistributable x86..."
    Start-Process -FilePath $vcx86 -Args "/quiet /norestart" -Wait -NoNewWindow
    Write-Host "[i] VC++ x86 install complete"
} else {
    Write-Warning "[!] $vcx86 not found — skipping x86 VC++ install. Copy installer to C:\Temp\ and re-run."
}

if (Test-Path $vcx64) {
    Write-Host "[i] Installing VC++ Redistributable x64..."
    Start-Process -FilePath $vcx64 -Args "/quiet /norestart" -Wait -NoNewWindow
    Write-Host "[i] VC++ x64 install complete"
} else {
    Write-Warning "[!] $vcx64 not found — skipping x64 VC++ install. Copy installer to C:\Temp\ and re-run."
}

# ============================================================
# SECTION 7: Install QEMU Guest Agent
# Required: qm snapshot --quiesce (Phase 3 clean_state snapshot)
# Source: 02-RESEARCH.md Q2 — qemu-ga-x86_64.msi from virtio-win ISO guest-agent\ directory
# PREREQUISITE: Operator must copy qemu-ga-x86_64.msi to C:\Temp\ before running
#   Source path on Proxmox host: /mnt/pve/local/template/iso/virtio-win.iso (mount and extract)
#   Or pre-download: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/
# NOTE: qm set <VMID> --agent 1 was already done in provision-windows.sh
#       This step installs the agent software INSIDE Windows
# ============================================================

Write-Host "[7/8] Installing QEMU Guest Agent (D-12 — required for qm snapshot --quiesce)"

$qemuMsi = "C:\Temp\qemu-ga-x86_64.msi"

if (Test-Path $qemuMsi) {
    Write-Host "[i] Installing QEMU Guest Agent from $qemuMsi..."
    Start-Process -FilePath "msiexec.exe" -Args "/i `"$qemuMsi`" /quiet /norestart" -Wait -NoNewWindow
    Write-Host "[i] QEMU Guest Agent install complete"
    # Verify service started
    $svc = Get-Service "QEMU-GA" -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -ne "Running") {
            Start-Service "QEMU-GA" -ErrorAction SilentlyContinue
        }
        Write-Host "[i] QEMU-GA service status: $( (Get-Service 'QEMU-GA').Status )"
    } else {
        Write-Warning "[!] QEMU-GA service not found after install — may require reboot"
    }
} else {
    Write-Warning "[!] $qemuMsi not found — skipping QEMU Guest Agent install."
    Write-Warning "    Extract qemu-ga-x86_64.msi from virtio-win ISO guest-agent\ directory."
    Write-Warning "    Mount virtio-win.iso on Proxmox host, copy guest-agent\qemu-ga-x86_64.msi to C:\Temp\"
}

# ============================================================
# SECTION 8: Verification Summary
# Expected results after successful baseline application:
#   Defender    — RealTimeProtectionEnabled = False
#   UAC         — EnableLUA = 0
#   WDigest     — UseLogonCredential = 1
#   QEMU-GA     — QEMU-GA service = Running
# ============================================================

Write-Host ""
Write-Host "================================================================"
Write-Host " [8/8] Verification Summary — $env:COMPUTERNAME"
Write-Host "================================================================"

# Defender
$defStatus = (Get-MpComputerStatus -ErrorAction SilentlyContinue)
if ($defStatus) {
    $rtpEnabled = $defStatus.RealTimeProtectionEnabled
    if ($rtpEnabled -eq $false) {
        Write-Host "[PASS] Defender: RealTimeProtectionEnabled = False"
    } else {
        Write-Host "[FAIL] Defender: RealTimeProtectionEnabled = $rtpEnabled (expected False)"
    }
} else {
    Write-Host "[PASS] Defender: Get-MpComputerStatus unavailable (Defender fully disabled/removed)"
}

# UAC
$uacVal = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -ErrorAction SilentlyContinue).EnableLUA
if ($uacVal -eq 0) {
    Write-Host "[PASS] UAC: EnableLUA = 0 (Never Notify)"
} else {
    Write-Host "[FAIL] UAC: EnableLUA = $uacVal (expected 0)"
}

# WDigest
$wdigest = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest" -ErrorAction SilentlyContinue).UseLogonCredential
if ($wdigest -eq 1) {
    Write-Host "[PASS] WDigest: UseLogonCredential = 1"
} else {
    Write-Host "[FAIL] WDigest: UseLogonCredential = $wdigest (expected 1)"
}

# QEMU-GA
$qemuSvc = Get-Service "QEMU-GA" -ErrorAction SilentlyContinue
if ($qemuSvc) {
    if ($qemuSvc.Status -eq "Running") {
        Write-Host "[PASS] QEMU-GA: Status = Running"
    } else {
        Write-Host "[FAIL] QEMU-GA: Status = $($qemuSvc.Status) (expected Running)"
    }
} else {
    Write-Host "[WARN] QEMU-GA: service not found — may require reboot after MSI install"
}

Write-Host ""
Write-Host "[i] Baseline complete on $env:COMPUTERNAME."
Write-Host "[i] NOTE: A reboot is required for some settings to fully take effect (UAC, WDigest)."
Write-Host "[i] After reboot, re-logon required for WDigest cached creds to appear in LSASS."
Write-Host "================================================================"
