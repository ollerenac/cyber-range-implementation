# =============================================================================
# 02-dc01-users.ps1 — Create D-03 domain users, groups, SPN, ADFind, Firefox on dc01
#
# LOCKED SPECS (do NOT change without updating CONTEXT.md):
#   Domain:        lab.local  / NetBIOS: LAB              (D-03)
#   SPN target:    MSSQLSvc/sql01.lab.local:1433 on LAB\tous (D-04)
#   ADFind dest:   C:\Windows\System32\adfind.exe           (D-13)
#   Users:         tous, gosta, mariam, shiroyeh,
#                  shiroyeh_admin, vfleming, judy            (D-03)
#   Groups:        EWS Admins, SQL Admins                   (D-03)
#   Domain Admins: shiroyeh_admin, vfleming                 (D-03)
#
# USAGE (run on dc01 as LAB\Administrator, or via WinRM from control node):
#   .\02-dc01-users.ps1 `
#       -DomainAdminPassword "Admin@Lab2025!" `
#       -TousPassword        "OilRigUser@2025!" `
#       -GostaPassword       "OilRigUser@2025!" `
#       -MariamPassword      "OilRigUser@2025!" `
#       -ShiroyehPassword    "OilRigUser@2025!" `
#       -ShiroyehAdminPassword "OilRigAdmin@2025!" `
#       -VflemingPassword    "Pass@Lab2025!" `
#       -JudyPassword        "Passw0rd!"
#
# PREREQUISITES:
#   - dc01 has been promoted to domain controller (01-dc01-promote.ps1 complete)
#   - AdFind.exe pre-downloaded to control node (no internet from dc01)
#   - Copy AdFind.exe to dc01 BEFORE running this script:
#       $session = New-PSSession -ComputerName 10.0.0.11 -Credential $cred
#       Copy-Item -Path ".\AdFind.exe" -Destination "C:\Temp\AdFind.exe" -ToSession $session
#   - Firefox installer pre-downloaded OR MGMT NIC has internet access
# =============================================================================

param(
    [Parameter(Mandatory=$true)]  [string]$DomainAdminPassword,
    [Parameter(Mandatory=$true)]  [string]$TousPassword,
    [Parameter(Mandatory=$true)]  [string]$GostaPassword,
    [Parameter(Mandatory=$true)]  [string]$MariamPassword,
    [Parameter(Mandatory=$true)]  [string]$ShiroyehPassword,
    [Parameter(Mandatory=$true)]  [string]$ShiroyehAdminPassword,
    [Parameter(Mandatory=$true)]  [string]$VflemingPassword,
    [Parameter(Mandatory=$true)]  [string]$JudyPassword
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================"
Write-Host " 02-dc01-users.ps1 — Domain user + group + SPN setup"
Write-Host " Domain: lab.local (LAB)"
Write-Host "============================================================"

# ============================================================
# Section 1 — User creation (D-03, adapted from CTID
#             create_domain_users.ps1, Q9 adaptation log)
# ============================================================
Write-Host "[i] Section 1: Creating D-03 domain user accounts"

Write-Host "[i] Creating user: judy (Wizard Spider — Domain Users)"
net user /add /domain judy $JudyPassword
if ($LASTEXITCODE -ne 0) { throw "net user /add judy failed (exit $LASTEXITCODE)" }
net user /domain judy /EXPIRES:NEVER
if ($LASTEXITCODE -ne 0) { throw "net user judy /EXPIRES:NEVER failed (exit $LASTEXITCODE)" }

Write-Host "[i] Creating user: vfleming (Wizard Spider — Domain Admins)"
net user /add /domain vfleming $VflemingPassword
if ($LASTEXITCODE -ne 0) { throw "net user /add vfleming failed (exit $LASTEXITCODE)" }
net user /domain vfleming /EXPIRES:NEVER
if ($LASTEXITCODE -ne 0) { throw "net user vfleming /EXPIRES:NEVER failed (exit $LASTEXITCODE)" }

Write-Host "[i] Creating user: tous (OilRig — EWS Admins, SQL Admins)"
net user /add /domain tous $TousPassword
if ($LASTEXITCODE -ne 0) { throw "net user /add tous failed (exit $LASTEXITCODE)" }
net user /domain tous /EXPIRES:NEVER
if ($LASTEXITCODE -ne 0) { throw "net user tous /EXPIRES:NEVER failed (exit $LASTEXITCODE)" }

Write-Host "[i] Creating user: gosta (OilRig — EWS Admins)"
net user /add /domain gosta $GostaPassword
if ($LASTEXITCODE -ne 0) { throw "net user /add gosta failed (exit $LASTEXITCODE)" }
net user /domain gosta /EXPIRES:NEVER
if ($LASTEXITCODE -ne 0) { throw "net user gosta /EXPIRES:NEVER failed (exit $LASTEXITCODE)" }

Write-Host "[i] Creating user: mariam (OilRig — Domain Users)"
net user /add /domain mariam $MariamPassword
if ($LASTEXITCODE -ne 0) { throw "net user /add mariam failed (exit $LASTEXITCODE)" }
net user /domain mariam /EXPIRES:NEVER
if ($LASTEXITCODE -ne 0) { throw "net user mariam /EXPIRES:NEVER failed (exit $LASTEXITCODE)" }

Write-Host "[i] Creating user: shiroyeh (OilRig — Domain Users)"
net user /add /domain shiroyeh $ShiroyehPassword
if ($LASTEXITCODE -ne 0) { throw "net user /add shiroyeh failed (exit $LASTEXITCODE)" }
net user /domain shiroyeh /EXPIRES:NEVER
if ($LASTEXITCODE -ne 0) { throw "net user shiroyeh /EXPIRES:NEVER failed (exit $LASTEXITCODE)" }

Write-Host "[i] Creating user: shiroyeh_admin (OilRig — Domain Admins)"
net user /add /domain shiroyeh_admin $ShiroyehAdminPassword
if ($LASTEXITCODE -ne 0) { throw "net user /add shiroyeh_admin failed (exit $LASTEXITCODE)" }
net user /domain shiroyeh_admin /EXPIRES:NEVER
if ($LASTEXITCODE -ne 0) { throw "net user shiroyeh_admin /EXPIRES:NEVER failed (exit $LASTEXITCODE)" }

Write-Host "[i] All 7 D-03 user accounts created."

# ============================================================
# Section 2 — Group creation and membership (D-03)
# ============================================================
Write-Host ""
Write-Host "[i] Section 2: Creating groups and assigning membership (D-03)"

net group /add /domain "EWS Admins"
if ($LASTEXITCODE -ne 0) { throw "net group /add 'EWS Admins' failed (exit $LASTEXITCODE)" }
net group /add /domain "SQL Admins"
if ($LASTEXITCODE -ne 0) { throw "net group /add 'SQL Admins' failed (exit $LASTEXITCODE)" }

Write-Host "[i] Adding tous and gosta to EWS Admins"
net group "EWS Admins" /add /domain tous
if ($LASTEXITCODE -ne 0) { throw "net group 'EWS Admins' /add tous failed (exit $LASTEXITCODE)" }
net group "EWS Admins" /add /domain gosta
if ($LASTEXITCODE -ne 0) { throw "net group 'EWS Admins' /add gosta failed (exit $LASTEXITCODE)" }

Write-Host "[i] Adding tous to SQL Admins"
net group "SQL Admins" /add /domain tous
if ($LASTEXITCODE -ne 0) { throw "net group 'SQL Admins' /add tous failed (exit $LASTEXITCODE)" }

Write-Host "[i] Adding shiroyeh_admin and vfleming to Domain Admins"
net group "Domain Admins" /add /domain shiroyeh_admin
if ($LASTEXITCODE -ne 0) { throw "net group 'Domain Admins' /add shiroyeh_admin failed (exit $LASTEXITCODE)" }
net group "Domain Admins" /add /domain vfleming
if ($LASTEXITCODE -ne 0) { throw "net group 'Domain Admins' /add vfleming failed (exit $LASTEXITCODE)" }

Write-Host "[i] Group memberships configured."

# ============================================================
# Section 3 — SPN registration (D-04, adapted from setup_spn.ps1)
#   Original: setspn -s exchange/oz.local oz.local\vfleming
#   Adapted:  MSSQLSvc on tous per D-04 (Kerberoasting target)
# ============================================================
Write-Host ""
Write-Host "[i] Section 3: Registering SPN for Kerberoasting scenario (D-04)"

Write-Host "[i] Setting SPN: MSSQLSvc/sql01.lab.local:1433 on LAB\tous"
setspn -s MSSQLSvc/sql01.lab.local:1433 LAB\tous

Write-Host "[i] Verifying SPN registration..."
$spnCheck = setspn -Q MSSQLSvc/sql01.lab.local:1433
Write-Host $spnCheck
if ($spnCheck -match "tous") {
    Write-Host "[PASS] SPN MSSQLSvc/sql01.lab.local:1433 confirmed on LAB\tous"
} else {
    Write-Error "[FAIL] SPN verification failed — 'tous' not found in setspn -Q output"
}

# ============================================================
# Section 4 — ADFind install (D-13)
#   install_adfind.ps1 original uses Invoke-WebRequest (internet).
#   dc01 has no internet on vmbr1. Use pre-copied file from
#   C:\Temp\AdFind.exe (operator must copy via WinRM before running).
# ============================================================
Write-Host ""
Write-Host "[i] Section 4: Installing adfind.exe to C:\Windows\System32\ (D-13)"

$adFindSource = "C:\Temp\AdFind.exe"
$adFindDest   = "C:\Windows\System32\adfind.exe"

if (-not (Test-Path $adFindSource)) {
    Write-Error @"
[FAIL] AdFind.exe not found at $adFindSource.
Pre-copy it from the control node BEFORE running this script:
  `$session = New-PSSession -ComputerName 10.0.0.11 -Credential `$cred
  Copy-Item -Path '.\AdFind.exe' -Destination 'C:\Temp\AdFind.exe' -ToSession `$session
"@
}

if (-not (Test-Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp" | Out-Null
}

Copy-Item -Path $adFindSource -Destination $adFindDest -Force
Write-Host "[i] adfind.exe installed to $adFindDest"

# Quick version check
$adFindVer = & $adFindDest -h 2>&1 | Select-Object -First 1
Write-Host "[i] AdFind version header: $adFindVer"

if (Test-Path $adFindDest) {
    Write-Host "[PASS] adfind.exe present at $adFindDest"
} else {
    Write-Error "[FAIL] adfind.exe not found at $adFindDest after copy"
}

# ============================================================
# Section 5 — Firefox install (D-13)
#   Two strategies: (a) internet via MGMT NIC, (b) pre-copied installer.
#   Script checks for pre-copied installer first; falls back to download.
# ============================================================
Write-Host ""
Write-Host "[i] Section 5: Installing Firefox on dc01 (D-13)"

$firefoxExe  = "C:\Program Files\Mozilla Firefox\firefox.exe"
$firefoxTemp = "C:\Temp\Firefox_Setup.exe"

if (Test-Path $firefoxExe) {
    Write-Host "[i] Firefox already installed at $firefoxExe — skipping install."
} elseif (Test-Path $firefoxTemp) {
    Write-Host "[i] Using pre-copied Firefox installer at $firefoxTemp"
    Start-Process -FilePath $firefoxTemp -ArgumentList "-ms" -Wait -NoNewWindow
} else {
    Write-Host "[i] Attempting Firefox download via MGMT NIC (requires internet on 10.0.0.0/24)"
    $firefoxUrl = "https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US"
    try {
        Invoke-WebRequest -Uri $firefoxUrl -OutFile $firefoxTemp -UseBasicParsing -TimeoutSec 120
        Start-Process -FilePath $firefoxTemp -ArgumentList "-ms" -Wait -NoNewWindow
    } catch {
        Write-Warning "[WARN] Firefox download failed: $_"
        Write-Warning "[WARN] Pre-copy Firefox_Setup.exe to C:\Temp\ on dc01 and re-run Section 5."
        Write-Warning "[WARN] Continuing — Firefox is required for Wizard Spider scenario but not for domain join."
    }
}

if (Test-Path $firefoxExe) {
    Write-Host "[PASS] Firefox installed: $firefoxExe"
} else {
    Write-Warning "[WARN] Firefox not detected — install manually if needed for Wizard Spider scenario."
}

# ============================================================
# Section 6 — Verification summary
# ============================================================
Write-Host ""
Write-Host "[i] Section 6: Verification summary"
Write-Host "------------------------------------------------------------"

Import-Module ActiveDirectory -ErrorAction SilentlyContinue

$users = @("tous", "gosta", "mariam", "shiroyeh", "shiroyeh_admin", "vfleming", "judy")
foreach ($u in $users) {
    try {
        $adUser = Get-ADUser $u -ErrorAction Stop
        Write-Host "[PASS] User found in AD: $($adUser.SamAccountName)"
    } catch {
        Write-Host "[FAIL] User NOT found in AD: $u"
    }
}

$groups = @("EWS Admins", "SQL Admins")
foreach ($g in $groups) {
    try {
        $adGroup = Get-ADGroup $g -ErrorAction Stop
        Write-Host "[PASS] Group found in AD: $($adGroup.Name)"
    } catch {
        Write-Host "[FAIL] Group NOT found in AD: $g"
    }
}

Write-Host ""
Write-Host "[i] SPN check: setspn -Q MSSQLSvc/sql01.lab.local:1433"
setspn -Q MSSQLSvc/sql01.lab.local:1433

Write-Host ""
Write-Host "============================================================"
Write-Host " DC01 user setup complete."
Write-Host " Next step: run 03-domain-join.ps1 from the control node"
Write-Host " to domain-join exchange01, sql01, ws01, ws02."
Write-Host "============================================================"
