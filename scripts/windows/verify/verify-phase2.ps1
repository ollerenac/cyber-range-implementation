# verify-phase2.ps1
# Run from control node: pwsh verify-phase2.ps1 -Password 'ActualPassword'
# Requires: PowerShell 7+ on control node, WinRM enabled on all target VMs
#
# Coverage:
#   [1] WinRM connectivity to all 5 MGMT IPs (10.0.0.11-15) — INFRA-03/04/05/06
#   [2] AD users (D-03 table: tous, gosta, mariam, shiroyeh, shiroyeh_admin, vfleming, judy)
#       SPN (D-04: MSSQLSvc/sql01.lab.local:1433 on LAB\tous)
#       Computer objects (DC01, EXCHANGE01, SQL01, WS01, WS02) — INFRA-03
#   [3] SQL: SELECT COUNT(*) FROM sitedata.dbo.minfac > 0; port 1433 LISTENING — INFRA-05
#   [4] Exchange EWS: https://10.0.0.12/ews/exchange.asmx returns HTTP 200 or 401 — INFRA-04
#   [5] Workstations: domain membership + WDigest UseLogonCredential=1 — INFRA-06
#
# MGMT IP assignments (D-NEW-08 from Phase 1 CONTEXT.md):
#   10.0.0.11 = dc01
#   10.0.0.12 = exchange01
#   10.0.0.13 = sql01
#   10.0.0.14 = ws01
#   10.0.0.15 = ws02
#
# Security note: -SkipCACheck -SkipCNCheck are intentional — MGMT subnet (vmbr0) is
# LAN-internal only. No internet exposure. Lab-only configuration per T-02-03 in threat model.

param(
  [string]$Password = ""
)

$ErrorActionPreference = "Stop"

# Require operator to supply the password explicitly — never use a default credential.
# Run as: pwsh verify-phase2.ps1 -Password 'ActualLabPassword'
# The actual password lives in .planning/secrets/PASSWORDS.md (gitignored).
if ([string]::IsNullOrEmpty($Password)) {
    throw "The -Password parameter is required. " +
        "Run: pwsh verify-phase2.ps1 -Password 'ActualLabPassword' " +
        "(see .planning/secrets/PASSWORDS.md for the lab Administrator password)"
}

$pass = ConvertTo-SecureString $Password -AsPlainText -Force
$cred = New-Object PSCredential("Administrator", $pass)

$results = @{}

# ---- Helper ----
function Test-WinRM {
  param($ip, $name)
  try {
    $s = New-PSSession -ComputerName $ip -Credential $cred `
      -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck) -ErrorAction Stop
    $results["$name-winrm"] = "PASS"
    return $s
  } catch {
    $results["$name-winrm"] = "FAIL: $_"
    return $null
  }
}

# ---- 1. Verify all 5 VMs are reachable over WinRM (MGMT IPs) ----
Write-Host "[1] Testing WinRM connectivity..."
$dc01_s    = Test-WinRM "10.0.0.11" "dc01"
$exch_s    = Test-WinRM "10.0.0.12" "exchange01"
$sql_s     = Test-WinRM "10.0.0.13" "sql01"
$ws01_s    = Test-WinRM "10.0.0.14" "ws01"
$ws02_s    = Test-WinRM "10.0.0.15" "ws02"

# ---- 2. LDAP: verify all D-03 accounts exist in lab.local ----
Write-Host "[2] Checking AD user accounts..."
if ($dc01_s) {
  $users = Invoke-Command -Session $dc01_s -ScriptBlock {
    Import-Module ActiveDirectory
    @("tous","gosta","mariam","shiroyeh","shiroyeh_admin","vfleming","judy") | ForEach-Object {
      try { Get-ADUser $_ | Select-Object -ExpandProperty SamAccountName } catch { "MISSING: $_" }
    }
  }
  $missing = $users | Where-Object { $_ -like "MISSING*" }
  $results["ad-users"] = if ($missing) { "FAIL: $($missing -join ', ')" } else { "PASS (7/7 accounts found)" }

  # Verify SPN on tous (D-04 — Kerberoasting target)
  $spn = Invoke-Command -Session $dc01_s -ScriptBlock {
    setspn -Q MSSQLSvc/sql01.lab.local:1433 2>&1
  }
  $results["ad-spn"] = if ($spn -match "MSSQLSvc/sql01.lab.local:1433") { "PASS" } else { "FAIL: SPN not found" }

  # Verify domain-joined computers appear in AD
  $computers = Invoke-Command -Session $dc01_s -ScriptBlock {
    Import-Module ActiveDirectory
    Get-ADComputer -Filter * | Select-Object -ExpandProperty Name
  }
  foreach ($vm in @("DC01","EXCHANGE01","SQL01","WS01","WS02")) {
    $results["ad-computer-$vm"] = if ($computers -contains $vm) { "PASS" } else { "FAIL: $vm not in AD" }
  }
} else {
  # dc01 unreachable — mark all AD checks as failed
  $results["ad-users"]               = "FAIL: dc01 WinRM unreachable"
  $results["ad-spn"]                 = "FAIL: dc01 WinRM unreachable"
  foreach ($vm in @("DC01","EXCHANGE01","SQL01","WS01","WS02")) {
    $results["ad-computer-$vm"] = "FAIL: dc01 WinRM unreachable"
  }
}

# ---- 3. SQL: sitedata database + minfac row count ----
Write-Host "[3] Checking SQL Server sitedata database..."
if ($sql_s) {
  $count = Invoke-Command -Session $sql_s -ScriptBlock {
    sqlcmd -S localhost -d sitedata -Q "SELECT COUNT(*) FROM dbo.minfac" -h -1 2>&1
  }
  $results["sql-sitedata"] = if ($count -match "^\s*\d+\s*$" -and [int]($count.Trim()) -gt 0) {
    "PASS ($($count.Trim()) rows in minfac)"
  } else {
    "FAIL: count=$count"
  }

  # Check port 1433 listening
  $port = Invoke-Command -Session $sql_s -ScriptBlock {
    netstat -ano | Select-String ":1433\s+.*LISTENING"
  }
  $results["sql-port1433"] = if ($port) { "PASS" } else { "FAIL: port 1433 not listening" }
} else {
  $results["sql-sitedata"]  = "FAIL: sql01 WinRM unreachable"
  $results["sql-port1433"]  = "FAIL: sql01 WinRM unreachable"
}

# ---- 4. Exchange: EWS endpoint HTTP response ----
Write-Host "[4] Checking Exchange EWS endpoint..."
try {
  # Test from control node directly (exchange01 MGMT IP)
  $ews = Invoke-WebRequest -Uri "https://10.0.0.12/ews/exchange.asmx" `
    -SkipCertificateCheck -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
  $results["exchange-ews"] = if ($ews.StatusCode -eq 200 -or $ews.StatusCode -eq 401) {
    "PASS (HTTP $($ews.StatusCode))"
  } else {
    "FAIL: HTTP $($ews.StatusCode)"
  }
} catch {
  # 401 Unauthorized from Exchange is expected and acceptable (service is running)
  if ($_ -match "401") {
    $results["exchange-ews"] = "PASS (HTTP 401 — Exchange EWS running, auth required)"
  } else {
    $results["exchange-ews"] = "FAIL: $_"
  }
}

# ---- 5. Workstations: domain membership + WDigest ----
Write-Host "[5] Checking workstation configuration..."
foreach ($pair in @(@("ws01","10.0.0.14"), @("ws02","10.0.0.15"))) {
  $name, $ip = $pair
  $session = if ($name -eq "ws01") { $ws01_s } else { $ws02_s }
  if ($session) {
    $domainCheck = Invoke-Command -Session $session -ScriptBlock {
      (Get-WmiObject Win32_ComputerSystem).PartOfDomain
    }
    $results["$name-domain"] = if ($domainCheck) { "PASS" } else { "FAIL: not domain joined" }

    $wdigest = Invoke-Command -Session $session -ScriptBlock {
      (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest" `
        -Name UseLogonCredential -ErrorAction SilentlyContinue).UseLogonCredential
    }
    $results["$name-wdigest"] = if ($wdigest -eq 1) { "PASS" } else { "FAIL: UseLogonCredential=$wdigest" }
  } else {
    $results["$name-domain"]  = "FAIL: $name WinRM unreachable"
    $results["$name-wdigest"] = "FAIL: $name WinRM unreachable"
  }
}

# ---- 6. Print results ----
Write-Host "`n=== Phase 2 Verification Results ==="
$pass_count = 0; $fail_count = 0
foreach ($key in $results.Keys | Sort-Object) {
  $status = $results[$key]
  $symbol = if ($status.StartsWith("PASS")) { "[PASS]" } else { "[FAIL]" }
  Write-Host "$symbol $key : $status"
  if ($status.StartsWith("PASS")) { $pass_count++ } else { $fail_count++ }
}
Write-Host "`nTotal: $pass_count PASS, $fail_count FAIL"
if ($fail_count -eq 0) { Write-Host "Phase 2 COMPLETE" -ForegroundColor Green }
else { Write-Host "Phase 2 INCOMPLETE -- fix failures above" -ForegroundColor Red }
