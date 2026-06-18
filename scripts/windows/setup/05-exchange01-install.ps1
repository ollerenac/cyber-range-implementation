# 05-exchange01-install.ps1
# AD schema prep (PrepareAD on dc01) + Exchange 2019 unattended install on exchange01
# + EWS ApplicationImpersonation + sql_connection.bat scheduled task (D-06).
#
# USAGE:
#   pwsh 05-exchange01-install.ps1 -DomainAdminPassword 'P@ss' -TousPassword 'P@ss'
#
# PREREQUISITES:
#   - 04-exchange01-prereqs.ps1 Steps 1-5 must be complete on exchange01
#   - Exchange ISO mounted as E: on BOTH dc01 (for PrepareAD) and exchange01 (for Setup)
#   - exchange01 is domain-joined and DNS resolves dc01.lab.local
#   - 02-dc01-users.ps1 must have run (EWS Admins group exists)
#
# WARNING: Exchange install takes 60-90 minutes. Do not interrupt.
# Recovery point: phase2-domain-joined snapshot (qm rollback 301 phase2-domain-joined)

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DomainAdminPassword,
    [Parameter(Mandatory)][string]$TousPassword
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DcMgmtIP       = "10.0.0.11"
$ExchangeMgmtIP = "10.0.0.12"
$SessionOpts    = New-PSSessionOption -SkipCACheck -SkipCNCheck
$DomainCred     = New-Object PSCredential("LAB\Administrator",
    (ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force))

# ─── Step 1: PrepareAD — run on dc01 ─────────────────────────────────────────
Write-Host "`n=== Step 1: PrepareAD (runs on dc01) ===" -ForegroundColor Cyan
Write-Host "[i] This extends AD schema for Exchange org 'LabOrg'. Takes ~5-10 min."

$DcSession = New-PSSession -ComputerName $DcMgmtIP -Credential $DomainCred -SessionOption $SessionOpts

Invoke-Command -Session $DcSession -ScriptBlock {
    $PrepareLog = "C:\Temp\PrepareAD.log"
    if (-not (Test-Path "E:\Setup.exe")) {
        Write-Error "Exchange ISO must be mounted as E: on dc01. Mount ISO first."
    }
    Write-Host "[i] Running PrepareAD..."
    $proc = Start-Process -FilePath "E:\Setup.exe" -ArgumentList `
        "/IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF /PrepareAD /OrganizationName:LabOrg" `
        -Wait -PassThru -RedirectStandardOutput $PrepareLog
    if ($proc.ExitCode -ne 0) {
        Write-Error "PrepareAD failed (exit $($proc.ExitCode)). Check $PrepareLog"
    }
    Write-Host "[PASS] PrepareAD complete (ExitCode: $($proc.ExitCode))"
}

Remove-PSSession $DcSession -EA SilentlyContinue

# Replicate AD changes to all DCs (only one DC here, but good practice)
Write-Host "[i] Waiting 60s for AD schema replication..."
Start-Sleep -Seconds 60

# ─── Step 2: Exchange unattended install on exchange01 ────────────────────────
Write-Host "`n=== Step 2: Exchange 2019 Install (runs on exchange01) ===" -ForegroundColor Cyan
Write-Host "[i] Installing Exchange Mailbox role. Expected duration: 60-90 minutes."
Write-Host "[i] Do NOT close this session or reboot exchange01 during install."

$ExchSession = New-PSSession -ComputerName $ExchangeMgmtIP -Credential $DomainCred -SessionOption $SessionOpts

Invoke-Command -Session $ExchSession -ScriptBlock {
    if (-not (Test-Path "E:\Setup.exe")) {
        Write-Error "Exchange ISO must be mounted as E: on exchange01."
    }
    $InstallLog = "C:\Temp\ExchangeSetup.log"
    Write-Host "[i] Starting Exchange Setup.exe..."
    $proc = Start-Process -FilePath "E:\Setup.exe" -ArgumentList @(
        "/IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF",
        "/Mode:Install",
        "/Roles:Mailbox",
        "/InstallWindowsComponents",
        "/DomainController:dc01.lab.local",
        "/DoNotEnableEP_FEEWS"    # MANDATORY: CU14+ Extended Protection blocks EWS in lab
    ) -Wait -PassThru -RedirectStandardOutput $InstallLog

    if ($proc.ExitCode -ne 0) {
        Write-Error "Exchange Setup failed (exit $($proc.ExitCode)). Check $InstallLog"
    }
    Write-Host "[PASS] Exchange install complete (ExitCode: $($proc.ExitCode))"
}

# ─── Step 3: Reboot exchange01 post-install ───────────────────────────────────
Write-Host "`n=== Step 3: Reboot exchange01 ===" -ForegroundColor Cyan
Invoke-Command -Session $ExchSession -ScriptBlock { Restart-Computer -Force }
Remove-PSSession $ExchSession -EA SilentlyContinue

# Poll until exchange01 accepts a new WinRM session (up to 10 minutes).
# A fixed sleep is not reliable: Exchange post-install reboots on a 10 GiB RAM VM
# routinely exceed 3 minutes depending on service initialization time.
Write-Host "[i] Polling for exchange01 to come back online (up to 10 min)..."
$deadline    = (Get-Date).AddMinutes(10)
$ExchSession2 = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 15
    try {
        $ExchSession2 = New-PSSession -ComputerName $ExchangeMgmtIP `
            -Credential $DomainCred -SessionOption $SessionOpts -EA Stop
        Write-Host "[PASS] exchange01 is back online"
        break
    } catch { }
}
if (-not $ExchSession2) {
    Write-Error "exchange01 did not come back within 10 minutes. Check Proxmox console for VM state."
}

# ─── Step 4: EWS ApplicationImpersonation for EWS Admins ─────────────────────
Write-Host "`n=== Step 4: EWS ApplicationImpersonation ===" -ForegroundColor Cyan

Invoke-Command -Session $ExchSession2 -ScriptBlock {
    Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn -ErrorAction SilentlyContinue
    $existing = Get-ManagementRoleAssignment -Name "EWSAdmins-Impersonation" -EA SilentlyContinue
    if (-not $existing) {
        New-ManagementRoleAssignment -Name "EWSAdmins-Impersonation" `
            -Role ApplicationImpersonation -SecurityGroup "EWS Admins"
        Write-Host "[PASS] ApplicationImpersonation granted to EWS Admins"
    } else {
        Write-Host "[PASS] ApplicationImpersonation already configured"
    }

    # Verify EWS endpoint responds
    try {
        $resp = Invoke-WebRequest -Uri "https://localhost/EWS/Exchange.asmx" `
            -SkipCertificateCheck -EA Stop
        Write-Host "[PASS] EWS endpoint: HTTP $($resp.StatusCode)"
    } catch {
        if ($_.Exception.Response.StatusCode.Value__ -eq 401) {
            Write-Host "[PASS] EWS endpoint: HTTP 401 (auth required — Exchange running)"
        } else {
            Write-Warning "[WARN] EWS check: $_"
        }
    }
}

# ─── Step 5: Create sql_connection.bat + scheduled task (D-06) ───────────────
Write-Host "`n=== Step 5: sql_connection.bat scheduled task (D-06) ===" -ForegroundColor Cyan

Invoke-Command -Session $ExchSession2 -ScriptBlock {
    param($TousPassword)

    # Create the bat file (adapted from CTID OilRig Resources/Infrastructure/)
    $BatPath = "C:\Scripts\sql_connection.bat"
    New-Item -ItemType Directory -Path "C:\Scripts" -Force | Out-Null
    @"
@echo off
REM sql_connection.bat — CTID OilRig persistence: periodic SQL query simulating data access
REM Adapted from adversary_emulation_library/oilrig/Resources/Infrastructure/
REM Domain: lab.local (original: boombox.boom.box)
sqlcmd -S sql01.lab.local -Q "SELECT TOP 1 * FROM sitedata.dbo.minfac"
"@ | Out-File -FilePath $BatPath -Encoding ASCII

    # Register scheduled task to run as LAB\tous at system startup
    $existing = schtasks /query /tn "SQL Connection" 2>&1
    if ($LASTEXITCODE -eq 0) {
        schtasks /delete /tn "SQL Connection" /f | Out-Null
    }
    schtasks /create /tn "SQL Connection" /tr "`"$BatPath`"" `
        /sc onstart /RU "LAB\tous" /RP "$TousPassword" /F | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[PASS] sql_connection.bat created at $BatPath"
        Write-Host "[PASS] Scheduled task 'SQL Connection' registered (runs as LAB\tous at startup)"
    } else {
        Write-Warning "Scheduled task creation returned exit $LASTEXITCODE — verify manually"
    }
} -ArgumentList $TousPassword

Remove-PSSession $ExchSession2 -EA SilentlyContinue

Write-Host "`n[PASS] Plan 05 complete." -ForegroundColor Green
Write-Host "[i] Verify EWS from control node:"
Write-Host "    Invoke-WebRequest https://10.0.0.12/EWS/Exchange.asmx -SkipCertificateCheck"
Write-Host "[i] Verify from TARGET NIC (emulation path):"
Write-Host "    Invoke-WebRequest https://10.10.10.20/EWS/Exchange.asmx -SkipCertificateCheck"
