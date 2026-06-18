---
phase: 02-windows-target-network
reviewed: 2026-06-18T21:22:00Z
depth: standard
files_reviewed: 16
files_reviewed_list:
  - scripts/windows/autounattend/dc01-autounattend.xml
  - scripts/windows/autounattend/exchange01-autounattend.xml
  - scripts/windows/autounattend/sql01-autounattend.xml
  - scripts/windows/autounattend/ws01-autounattend.xml
  - scripts/windows/autounattend/ws02-autounattend.xml
  - scripts/windows/setup/01-dc01-promote.ps1
  - scripts/windows/setup/02-dc01-users.ps1
  - scripts/windows/setup/03-domain-join.ps1
  - scripts/windows/setup/04-exchange01-prereqs.ps1
  - scripts/windows/setup/05-exchange01-install.ps1
  - scripts/windows/setup/06-sql01-install.ps1
  - scripts/windows/setup/07-security-baseline.ps1
  - scripts/windows/setup/08-workstations.ps1
  - scripts/windows/verify/verify-phase2.ps1
  - scripts/proxmox/build-unattend-isos.sh
  - scripts/proxmox/provision-windows.sh
findings:
  critical: 5
  warning: 7
  info: 3
  total: 15
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-06-18T21:22:00Z
**Depth:** standard
**Files Reviewed:** 16
**Status:** issues_found

## Summary

Phase 2 provisions a five-VM Windows target network (DC01, EXCHANGE01, SQL01, WS01, WS02)
through unattended installation XMLs and a sequential PowerShell setup pipeline. The overall
architecture is sound: password placeholders are used in committed XMLs, the Proxmox shell
scripts use `set -euo pipefail` with input validation and a VMID safety guard, and intentional
security weaknesses (Defender off, WDigest=1, UAC=0) are correctly annotated and are out of
scope per review instructions.

Five blockers were found that would cause silent failures or hard stops during an operator
run. Three are logic bugs that produce wrong behavior invisibly: `$AUSettings.Save` is never
invoked (missing parentheses), multi-line SQL with `GO` terminators fails when passed via
`sqlcmd -Q`, and `net.exe` exit codes are invisible to `$ErrorActionPreference = "Stop"`
meaning failed user creations silently continue. One is a broken error-message string (the
concatenation in `Write-Error` is not evaluated). One is a credential hygiene break: a
real-looking default password is hardcoded in the verification script while every other file
in the phase correctly uses the `OPERATOR_SETS_PASSWORD` placeholder pattern.

Seven warnings cover: suppressed `genisoimage` stderr, a missing success-check on
`Install-WindowsFeature`, a session-not-closed-before-reboot race in the Exchange script,
unchecked `sqlcmd` exit codes, a password injection risk in `schtasks /RP`, an irreversible
`takeown` with no hostname guard, and a fixed 90-second reboot wait insufficient for
EXCHANGE01.

---

## Critical Issues

### CR-01: `$AUSettings.Save` missing parentheses — Windows Update is never actually disabled

**File:** `scripts/windows/setup/07-security-baseline.ps1:98`

**Issue:** Line 98 reads `$AUSettings.Save`. In PowerShell this is a property-access
expression, not a method call. The expression is evaluated and its result discarded without
ever invoking the method. The `NotificationLevel = 1` assignment on line 97 is also never
committed because `.Save()` is never called to persist the COM object's state. The `sc.exe`
commands above correctly stop and disable the `wuauserv` service, but the Windows Update COM
API channel remains unconstrained. After a reboot, Windows Update scheduled tasks can
re-trigger the service, causing patches to install during emulation runs and potentially
disrupting CALDERA agents or Mimikatz payloads. The script prints confirmation that the
setting was applied, giving the operator no indication the change was silently lost.

**Fix:**
```powershell
$AUSettings = (New-Object -com "Microsoft.Update.AutoUpdate").Settings
$AUSettings.NotificationLevel = 1
$AUSettings.Save()   # parentheses are required — this is a method call, not a property
```

---

### CR-02: `net.exe` exit codes invisible to `$ErrorActionPreference = "Stop"` — failed user/group creations silently continue

**File:** `scripts/windows/setup/02-dc01-users.ps1:59-108`

**Issue:** `$ErrorActionPreference = "Stop"` halts execution only when a PowerShell *cmdlet*
raises a terminating error. It has no effect on external native executables. All seven
`net user /add /domain` calls (lines 59–85) and the `net group` calls (lines 94–107) will
proceed to the next statement even if `net.exe` returns a non-zero exit code. Failure
scenarios include: DC not yet fully ready after the promotion reboot, password complexity
rejection, duplicate account name on script re-run, or insufficient AD replication time. The
script will reach Section 6 and emit `[PASS] User found in AD` or `[FAIL] User NOT found in
AD` without any indication which step actually failed. The SPN registered in Section 3 targets
`LAB\tous` — if `tous` was never created, `setspn` will silently register the SPN on a
non-existent account and the Kerberoasting scenario (D-04) will be silently broken.

**Fix:** Check `$LASTEXITCODE` after every `net.exe` invocation, or replace with PowerShell
AD cmdlets that integrate with `$ErrorActionPreference`:
```powershell
# Preferred: use New-ADUser which throws on failure
New-ADUser -Name "judy" -SamAccountName "judy" `
    -AccountPassword (ConvertTo-SecureString $JudyPassword -AsPlainText -Force) `
    -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop

# Minimum fix if keeping net.exe: check exit code after each call
net user /add /domain judy $JudyPassword
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create user 'judy' (net.exe exit code: $LASTEXITCODE)"
}
```
The same pattern applies to all `net group`, `setspn`, and `schtasks` calls across scripts
02, 05, and 06.

---

### CR-03: Multi-line SQL with `GO` batch terminators passed via `sqlcmd -Q` — `GO` is not processed; table creation fails

**File:** `scripts/windows/setup/06-sql01-install.ps1:103-137`

**Issue:** The `$createDB` here-string (lines 103–136) contains `GO` batch separators between
statements (`GO` after `CREATE DATABASE sitedata;`, `GO` after `USE sitedata;`, etc.).
`sqlcmd -Q <string>` executes a single inline query batch — in this mode `GO` is **not**
recognized as a batch terminator. It is treated as a bare T-SQL token, causing a syntax error
on the `GO` line itself. `CREATE DATABASE sitedata` may succeed, but `USE sitedata` and
`CREATE TABLE dbo.minfac` will not run. The `-b` flag causes `sqlcmd` to exit non-zero on any
error, but the exit code is not checked (see WR-05), so execution continues. Part D's
`SqlBulkCopy` then fails with `Invalid object name 'dbo.minfac'` — a terminating exception —
leaving sql01 in a broken partial state where the database exists but the schema does not.

**Fix:** Use `sqlcmd -i` (file input mode, where `GO` is processed as a batch separator), or
split into separate `-Q` invocations removing the `GO` separators:
```powershell
# Option A: write to temp file, use -i
$createDB | Out-File "C:\Temp\create_sitedata.sql" -Encoding ASCII
sqlcmd -S localhost -i "C:\Temp\create_sitedata.sql" -b
if ($LASTEXITCODE -ne 0) {
    Write-Error "sitedata schema creation failed (sqlcmd exit $LASTEXITCODE). Aborting."
}

# Option B: split into two separate -Q calls (no GO needed)
sqlcmd -S localhost -b -Q `
    "IF NOT EXISTS (SELECT name FROM sys.databases WHERE name='sitedata') CREATE DATABASE sitedata;"
if ($LASTEXITCODE -ne 0) { Write-Error "CREATE DATABASE failed" }

sqlcmd -S localhost -d sitedata -b -Q @"
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'minfac')
    CREATE TABLE dbo.minfac (position INT, rec_id NVARCHAR(50), ...);
"@
if ($LASTEXITCODE -ne 0) { Write-Error "CREATE TABLE minfac failed" }
```

---

### CR-04: `Write-Error` with `+` across line continuations produces a truncated message and a spurious pipeline output

**File:** `scripts/windows/setup/03-domain-join.ps1:79-82`

**Issue:** The error call inside the remote scriptblock reads:
```powershell
Write-Error "DNS resolution FAILED for '$DomainName' via $DcTargetIP. " +
    "Verify dc01 is running and TARGET NIC on this VM reaches 10.10.10.0/24. " +
    "Aborting domain join."
```
In PowerShell, `Write-Error` is a cmdlet, not a function receiving an expression. The first
string is bound as the `-Message` argument and the call completes there. The remainder of the
line (`+ "Verify dc01..."`) is parsed as a separate pipeline expression: the `+` operator is
applied to the return value of `Write-Error` (which is `$null`) and a string literal. In
PowerShell 5/7 this produces a type-conversion error (`Cannot convert 'System.String' to
'System.Int32'`) or echoes the strings to the output stream — output which contaminates the
`Invoke-Command` return value in the caller. The `return` on line 83 still fires so the abort
is intact, but the operator sees only the first truncated sentence of the error message, losing
the actionable guidance about verifying dc01 and the TARGET NIC.

**Fix:** Wrap the concatenated string in parentheses so it is evaluated before being passed
to `Write-Error`:
```powershell
Write-Error ("DNS resolution FAILED for '$DomainName' via $DcTargetIP. " +
    "Verify dc01 is running and TARGET NIC on this VM reaches 10.10.10.0/24. " +
    "Aborting domain join.")
return
```

---

### CR-05: Hardcoded default password in `verify-phase2.ps1` contradicts the `OPERATOR_SETS_PASSWORD` pattern established by every other file in this phase

**File:** `scripts/windows/verify/verify-phase2.ps1:25`

**Issue:** `[string]$Password = "Admin@Lab2025!"` — a specific credential string is
committed as the default parameter value. Every other file in Phase 2 (all five autounattend
XMLs) uses `OPERATOR_SETS_PASSWORD` as a placeholder and documents that secrets must be
substituted in `.planning/secrets/` before use. The verify script breaks this pattern. An
operator who runs `pwsh verify-phase2.ps1` without `-Password` silently authenticates with
this default against all five VMs. If the actual lab password differs, all five WinRM checks
fail with authentication errors, and the operator may spend time diagnosing WinRM or network
configuration before realizing the password parameter was wrong. The string `Admin@Lab2025!`
also appears in git history for any clone.

**Fix:** Remove the default value and make the parameter mandatory, matching the pattern
established in all other scripts:
```powershell
param(
  [Parameter(Mandatory=$true)]
  [string]$Password
)
```

---

## Warnings

### WR-01: `genisoimage` stderr suppressed — build failures produce no diagnostic output

**File:** `scripts/proxmox/build-unattend-isos.sh:138`

**Issue:** `genisoimage ... 2>/dev/null` discards all stderr. `genisoimage` writes both its
normal progress output and its error messages to stderr. With `set -euo pipefail`, a non-zero
exit code will abort the script, but the operator sees only the script's own `die()` message
with no indication of why genisoimage failed. On a Proxmox host where `/var/lib/vz/` is on a
separate ZFS pool, disk-full and permission-denied errors are plausible and would be completely
hidden.

**Fix:** Remove the suppression. If the progress chatter is unwanted, suppress only the
progress lines while keeping errors visible:
```bash
genisoimage \
  -o "${OUT_ISO}" \
  -J \
  -r \
  "${STAGING_DIR}/"
# Removed 2>/dev/null — errors must reach the operator
```
Or log to a file: `genisoimage ... 2>"/tmp/genisoimage-${VM_NAME}.log"` and print the log
path on failure.

---

### WR-02: `Install-WindowsFeature` result not checked — promotion proceeds even if AD DS role install failed silently

**File:** `scripts/windows/setup/01-dc01-promote.ps1:148`

**Issue:** `Install-WindowsFeature AD-Domain-Services -IncludeManagementTools -Verbose`
returns a `FeatureOperationResult` object with a `Success` property. The cmdlet does not
always throw on failure — it can return `Success = False` while executing normally (e.g.,
installation source missing, WinSxS corruption). With `$ErrorActionPreference = "Stop"`,
non-terminating internal errors from this cmdlet may still not raise a terminating exception.
If the role install fails silently, execution falls through to `Import-Module ADDSDeployment`
which will throw module-not-found, producing a misleading error that points at the forest
promotion step rather than the role install.

**Fix:**
```powershell
$roleResult = Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
if (-not $roleResult.Success) {
    Write-Warning "AD-Domain-Services feature install failed: $($roleResult.ExitCode)"
    exit 1
}
Write-Host "[i] AD DS role installed. RestartNeeded: $($roleResult.RestartNeeded)"
```

---

### WR-03: Exchange session not closed before reboot; fixed 180-second wait insufficient

**File:** `scripts/windows/setup/05-exchange01-install.ps1:89-97`

**Issue:** Line 89 fires `Restart-Computer -Force` inside `$ExchSession` without closing the
session first. Line 90 then calls `Remove-PSSession $ExchSession` on a session whose transport
was torn down by the reboot — this throws a non-terminating error (suppressed by `-EA
SilentlyContinue`), which is acceptable. The larger problem is the fixed `Start-Sleep -Seconds
180` on line 92. Exchange Server post-install reboots involve service initialization on a
10 GiB RAM VM and frequently exceed 3 minutes. If `$ExchSession2` on line 97 is opened before
EXCHANGE01 is ready, all of Steps 4 and 5 (ApplicationImpersonation grant + sql_connection.bat
scheduled task — both required for the OilRig scenario) will fail with no retry and no
fallback, leaving the Exchange configuration silently incomplete.

**Fix:** Replace the fixed sleep with a poll-until-available loop:
```powershell
Invoke-Command -Session $ExchSession -ScriptBlock { Restart-Computer -Force }
Remove-PSSession $ExchSession -EA SilentlyContinue

Write-Host "[i] Polling for exchange01 to come back (up to 10 min)..."
$deadline   = (Get-Date).AddMinutes(10)
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
    Write-Error "exchange01 did not come back within 10 minutes. Check Proxmox console."
}
```

---

### WR-04: `schtasks /RP` receives `$TousPassword` via command-line interpolation — password with shell-special characters will break task registration

**File:** `scripts/windows/setup/05-exchange01-install.ps1:146-147`

**Issue:** The scheduled task is created with:
```powershell
schtasks /create /tn "SQL Connection" /tr "`"$BatPath`"" `
    /sc onstart /RU "LAB\tous" /RP "$TousPassword" /F | Out-Null
```
`$TousPassword` is interpolated directly into the command-line string passed to `schtasks.exe`.
If the password contains `"`, `%`, `^`, `!`, or `&`, the resulting command line will be
malformed. The task may be created with an empty or truncated password, causing it to fail at
runtime without any indication during setup. The OilRig persistence step (D-06) would appear
to succeed (`$LASTEXITCODE -eq 0`) but the task would never run as `LAB\tous`.

**Fix:** Use `Register-ScheduledTask` (PowerShell 3+), which accepts credentials as a
structured parameter and avoids shell-quoting entirely:
```powershell
$taskAction  = New-ScheduledTaskAction -Execute "`"$BatPath`""
$taskTrigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName "SQL Connection" `
    -Action $taskAction -Trigger $taskTrigger `
    -User "LAB\tous" -Password $TousPassword -RunLevel Highest -Force
if (-not (Get-ScheduledTask -TaskName "SQL Connection" -EA SilentlyContinue)) {
    Write-Error "Scheduled task 'SQL Connection' not found after registration"
}
```

---

### WR-05: `sqlcmd` exit codes not checked after `-b` flag — downstream steps proceed on broken database state

**File:** `scripts/windows/setup/06-sql01-install.ps1:137, 193, 199, 204`

**Issue:** Four `sqlcmd` invocations use `-b` (abort batch on error) but their `$LASTEXITCODE`
is never checked. When CR-03 triggers a failure (the `GO`-separator issue), `sqlcmd` exits
non-zero, but execution continues into Part D's `SqlBulkCopy` (which throws an exception),
then into Part E (backup of a malformed database), then Part F (login/role grant against a
non-existent schema). Part E in particular creates a backup at:
`C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\Backup\sitedata.bak`
If an operator later rolls back to this backup as a "known good" state, they would restore a
broken database and have no indication.

**Fix:** After every standalone `sqlcmd` call, check `$LASTEXITCODE`:
```powershell
sqlcmd -S localhost -i "C:\Temp\create_sitedata.sql" -b
if ($LASTEXITCODE -ne 0) {
    Write-Error "sitedata schema creation failed (exit $LASTEXITCODE). Aborting before import."
}
```
Apply this pattern to all four `sqlcmd` calls at lines 137, 193, 199, and 204.

---

### WR-06: `takeown /f C:\Windows /r` runs with no hostname guard — if session is accidentally connected to the wrong VM, it executes on that host

**File:** `scripts/windows/setup/08-workstations.ps1:176`

**Issue:** The `takeown /f C:\Windows /r /d Y` command is recursive, takes ownership of the
entire `C:\Windows` tree, and is effectively irreversible without a snapshot rollback. The
`-Target "ws01"` validation at line 82 guards the ws01 block, but the script executes inside
an `Invoke-Command` remote session. If the operator accidentally passes the wrong IP to
`New-PSSession` (e.g., dc01's 10.0.0.11 instead of ws01's 10.0.0.14), the takeown and
`icacls ... /grant "LAB\judy:(OI)(CI)F" /T` will execute on the domain controller.
`$env:COMPUTERNAME` is available inside the remote session and should be verified.

**Fix:** Add a hostname guard before the destructive operations:
```powershell
$actualHost = $env:COMPUTERNAME.ToUpper()
if ($actualHost -ne "WS01") {
    Write-Error "ABORT: D-11 takeown/icacls must only run on WS01. This host is '$actualHost'. Check your PSSession target IP."
    exit 1
}
takeown /f C:\Windows /r /d Y 2>&1 | Out-Null
```

---

### WR-07: Fixed 90-second reboot wait in domain-join loop is a reliable false-negative for EXCHANGE01

**File:** `scripts/windows/setup/03-domain-join.ps1:104`

**Issue:** After triggering a domain-join reboot via `Add-Computer ... -Restart -Force`, the
script sleeps a fixed 90 seconds and then attempts a WinRM reconnect. For EXCHANGE01 (10 GiB
RAM, Exchange services starting), 90 seconds is routinely insufficient. The
post-reboot `New-PSSession` on line 109 will fail, marking EXCHANGE01 as
`[FAIL] PartOfDomain=False` even when the join succeeded. This is a reliable false-negative
that will confuse operators on every run.

**Fix:** Replace `Start-Sleep -Seconds 90` with a retry loop (similar to WR-03 fix):
```powershell
Write-Host "[i] Polling for $VMName to come back (up to 3 min)..."
$deadline = (Get-Date).AddMinutes(3)
$PostSession = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 10
    try {
        $PostSession = New-PSSession -ComputerName $MgmtIP -Credential $DomainCred `
            -SessionOption $SessionOpts -EA Stop
        break
    } catch { }
}
if (-not $PostSession) {
    Write-Warning "[WARN] $VMName did not respond within 3 min — verify domain join manually"
}
```

---

## Info

### IN-01: `ostype win10` for all VMs including Windows Server 2019 — correct but undocumented

**File:** `scripts/proxmox/provision-windows.sh:130`

**Issue:** `--ostype win10` is used for all five VMs, including the three Windows Server 2019
instances. In Proxmox, `win10` is the correct ostype for both Windows 10 and Windows Server
2019 (they share the same QEMU machine type profile). There is no separate `win2019` ostype.
This is not a bug, but future operators may assume it is wrong and "correct" it, or waste time
looking for a `win2019` value.

**Fix:** Add an inline comment:
```bash
--ostype win10 \    # Proxmox uses win10 for both Win10 and WS2019; no win2019 type exists
```

---

### IN-02: `Get-WmiObject Win32_ComputerSystem` is deprecated in PowerShell 7+

**File:** `scripts/windows/setup/03-domain-join.ps1:112`, `scripts/windows/verify/verify-phase2.ps1:140`

**Issue:** `Get-WmiObject` is deprecated in PowerShell 7 (replaced by `Get-CimInstance`).
The control node uses `pwsh` (PowerShell 7+) per the script headers. While `Get-WmiObject`
still functions via WinRM remoting to Windows targets, it emits deprecation warnings in
PowerShell 7 that pollute the operator's terminal output and may be removed in a future release.

**Fix:**
```powershell
# Replace:
(Get-WmiObject Win32_ComputerSystem).PartOfDomain
# With:
(Get-CimInstance -ClassName Win32_ComputerSystem).PartOfDomain
```

---

### IN-03: `setspn -Q` verification uses `-match "tous"` — loose substring match

**File:** `scripts/windows/setup/02-dc01-users.ps1:124`

**Issue:** `if ($spnCheck -match "tous")` matches any output line containing the substring
"tous" — including error messages or coincidental matches. A more precise check would verify
the SPN is bound to the specific account path.

**Fix:**
```powershell
if ($spnCheck -match "LAB\\tous") {
    Write-Host "[PASS] SPN MSSQLSvc/sql01.lab.local:1433 confirmed on LAB\tous"
} else {
    Write-Error "[FAIL] SPN verification failed — LAB\tous not found in setspn -Q output"
}
```

---

_Reviewed: 2026-06-18T21:22:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
