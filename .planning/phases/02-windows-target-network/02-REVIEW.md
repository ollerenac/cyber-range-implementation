---
phase: 02
status: findings
critical_count: 4
warning_count: 6
info_count: 4
---

# Phase 02 Code Review

## Summary

Reviewed 16 source files: 2 bash provisioning scripts, 5 autounattend XMLs, 8 PowerShell setup
scripts, and 1 PowerShell verification script. The overall structure is solid — the scripts follow
a clear execution order, parameters are validated, and intentional lab-security weaknesses
(Defender off, WDigest=1, UAC=0) are correctly annotated and excluded from findings. Four
critical bugs were found that would cause silent failures or incorrect state: `sqlcmd -Q` does not
honour `GO` batch separators (sitedata DB creation will fail), `$AUSettings.Save` is never called
due to missing `()` (auto-updates stay on), string concatenation inside `Write-Error` produces a
broken error message and unintended pipeline output, and `genisoimage` stderr is silently
suppressed preventing diagnosis of ISO build failures. Six warnings cover logic ordering issues,
a missing success-check after the AD DS role install, an idempotency gap in the SQL ini, a
WinRM credential mismatch in verify-phase2.ps1, a fixed 90-second reboot wait in domain-join,
and the use of the legacy `pc` machine type in `qm create`.

---

## Findings

### Critical

#### CR-01: `sqlcmd -Q` does not process `GO` batch terminators — sitedata DB will not be created

- **File:** `scripts/windows/setup/06-sql01-install.ps1`
- **Line:** ~103–137 (Part C)
- **Issue:** The `$createDB` here-string contains `GO` statements (`GO` after `CREATE DATABASE
  sitedata;`, `GO` after `USE sitedata;`, `GO` at the end). When passed to `sqlcmd` via the `-Q`
  flag, `GO` is NOT recognised as a batch terminator — it is treated as a literal T-SQL token and
  causes a syntax error. Only `sqlcmd` reading from a file (`-i`) or stdin processes `GO`. As a
  result, `CREATE DATABASE sitedata` will succeed but `USE sitedata` and `CREATE TABLE dbo.minfac`
  will either fail or run in the wrong database context. The subsequent SqlBulkCopy import (Part D)
  will then fail because the target table does not exist. The script will exit with a
  `Write-Error` (terminating) at the SqlBulkCopy step, leaving sql01 in a broken partial state.
- **Fix:** Split into separate `sqlcmd` calls without `GO`, or write the SQL to a `.sql` file and
  use `sqlcmd -i`:

  ```powershell
  # Option A: separate sqlcmd calls (no GO needed)
  sqlcmd -S localhost -b -Q "IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'sitedata') CREATE DATABASE sitedata;"
  sqlcmd -S localhost -d sitedata -b -Q @"
  IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'minfac')
  BEGIN
      CREATE TABLE dbo.minfac (
          position INT, rec_id NVARCHAR(50), year INT, country NVARCHAR(100),
          commodity NVARCHAR(100), location NVARCHAR(200), fac_name NVARCHAR(300),
          fac_type NVARCHAR(100), dmslat NVARCHAR(50), dmslong NVARCHAR(50),
          latitude FLOAT, longitude FLOAT, precision_ NVARCHAR(50), mm NVARCHAR(50),
          op_comp NVARCHAR(200), maininvest NVARCHAR(300), othinvest NVARCHAR(300),
          status NVARCHAR(100), capacity NVARCHAR(100), units NVARCHAR(50),
          notes NVARCHAR(MAX), cite NVARCHAR(MAX)
      );
  END
  "@

  # Option B: write to file then use -i
  $createDB | Out-File "C:\Temp\create_sitedata.sql" -Encoding ASCII
  sqlcmd -S localhost -i "C:\Temp\create_sitedata.sql" -b
  ```

---

#### CR-02: `$AUSettings.Save` missing parentheses — Windows Update is never actually disabled

- **File:** `scripts/windows/setup/07-security-baseline.ps1`
- **Line:** ~98
- **Issue:** Line 98 reads `$AUSettings.Save` — this is a property/method reference, not a method
  call. PowerShell evaluates the expression and discards the result without invoking the method.
  The `NotificationLevel = 1` assignment on line 97 is also discarded because `.Save()` is never
  called to commit the change. The Windows Update AutoUpdate COM object requires `.Save()` to
  persist settings. As a result, Windows Update remains enabled at the COM API level even though
  the service is stopped via `sc.exe`. After a reboot the service may restart and resume updates,
  interfering with emulation runs.
- **Fix:**

  ```powershell
  $AUSettings = (New-Object -com "Microsoft.Update.AutoUpdate").Settings
  $AUSettings.NotificationLevel = 1
  $AUSettings.Save()   # parentheses required — this is a method call
  ```

---

#### CR-03: `Write-Error` with `+` string concatenation inside a remote scriptblock emits an
unintended pipeline object and does not produce the intended error message

- **File:** `scripts/windows/setup/03-domain-join.ps1`
- **Line:** ~79–83
- **Issue:** The `Write-Error` call reads:

  ```powershell
  Write-Error "DNS resolution FAILED for '$DomainName' via $DcTargetIP. " +
      "Verify dc01 is running and TARGET NIC on this VM reaches 10.10.10.0/24. " +
      "Aborting domain join."
  ```

  In PowerShell, `Write-Error <string>` does not support the `+` string-concatenation operator
  across line continuations this way. The first string is passed as the `-Message` argument.
  The second line (`+ "Verify dc01..."`) is a separate pipeline expression: PowerShell parses it
  as a binary `+` applied to the return value of `Write-Error` (which is `$null`) and a string,
  producing an error `Cannot convert 'System.String' to type 'System.Int32'` — or in some PS
  versions simply echoes the string to stdout. The `return` on line 83 still executes so the
  abort logic is intact, but the error message shown to the operator is truncated (only the first
  string is displayed) and a spurious type-conversion error or extra output is emitted, obscuring
  diagnostics.
- **Fix:** Use a here-string or explicit concatenation before `Write-Error`:

  ```powershell
  Write-Error ("DNS resolution FAILED for '$DomainName' via $DcTargetIP. " +
      "Verify dc01 is running and TARGET NIC on this VM reaches 10.10.10.0/24. " +
      "Aborting domain join.")
  return
  ```

---

#### CR-04: `genisoimage` stderr silently suppressed — ISO build failures produce no diagnostic

- **File:** `scripts/proxmox/build-unattend-isos.sh`
- **Line:** ~133–138
- **Issue:** The `genisoimage` invocation redirects stderr to `/dev/null`:

  ```bash
  genisoimage \
    -o "${OUT_ISO}" \
    -J -r \
    "${STAGING_DIR}/" \
    2>/dev/null
  ```

  `genisoimage` writes all progress and error messages to stderr. With `set -euo pipefail`, a
  non-zero exit code will still abort the script, but the operator sees only the script's own
  `die` message with no indication of what `genisoimage` actually failed on (disk full, bad
  source directory, permission denied on ISO_DIR, etc.). On a Proxmox host where `/var/lib/vz/`
  may be on a separate ZFS pool, a disk-full condition is plausible and the suppression would
  hide the root cause entirely.
- **Fix:** Remove the stderr suppression, or redirect to a log file:

  ```bash
  genisoimage \
    -o "${OUT_ISO}" \
    -J -r \
    "${STAGING_DIR}/" \
    2>&1 | tee "/tmp/genisoimage-${VM_NAME}.log"
  ```

  If the intentional behaviour is to suppress the normal "progress" noise but keep errors, use
  `genisoimage ... 2>&1 | grep -v '^%'` or keep stderr but hide stdout.

---

### Warning

#### WR-01: No exit check after `Install-WindowsFeature AD-Domain-Services` — promotion proceeds even if role install fails

- **File:** `scripts/windows/setup/01-dc01-promote.ps1`
- **Line:** ~148
- **Issue:** `Install-WindowsFeature AD-Domain-Services -IncludeManagementTools -Verbose` is
  called without checking the return value. The cmdlet returns a
  `Microsoft.Windows.ServerManager.Commands.FeatureOperationResult` object with a `Success`
  property. If the feature install fails (e.g. installation source not found, WIM file
  unavailable) the cmdlet does not throw by default — it returns `Success = False`. With
  `$ErrorActionPreference = "Stop"`, non-terminating errors from this cmdlet may still not
  terminate. The script then immediately proceeds to `Import-Module ADDSDeployment` and
  `Install-ADDSForest`, which will fail with a module-not-found error, but the failure message
  will be misleading (it will blame the forest promotion rather than the role install).
- **Fix:**

  ```powershell
  $roleResult = Install-WindowsFeature AD-Domain-Services -IncludeManagementTools -Verbose
  if (-not $roleResult.Success) {
      Write-Warning "AD-Domain-Services feature install failed: $($roleResult.ExitCode)"
      exit 1
  }
  ```

---

#### WR-02: Hardcoded default password in `verify-phase2.ps1` parameter

- **File:** `scripts/windows/verify/verify-phase2.ps1`
- **Line:** ~25
- **Issue:** `[string]$Password = "Admin@Lab2025!"` — the default value is a specific password
  string. This means running `pwsh verify-phase2.ps1` without `-Password` silently uses this
  credential against all 5 VMs. If the operator set a different password (which the autounattend
  XMLs require via `OPERATOR_SETS_PASSWORD`), the verification script fails all 5 WinRM checks
  with authentication errors and reports the entire lab as broken — with no indication that the
  password parameter is wrong. The operator may waste time diagnosing WinRM or network issues.
  Additionally, the credential used is `Administrator` (local), but after domain join the
  domain-aware checks (AD users, computers) require `LAB\Administrator` — the same password but
  a different account name. The script uses the local `Administrator` credential for the DC
  session, which post-domain-join becomes `LAB\Administrator` implicitly on that host, so this
  likely works — but it is fragile.
- **Fix:** Make the parameter mandatory, or at minimum add a `[ValidateNotNullOrEmpty()]`
  attribute and emit a prominent warning when the default is being used:

  ```powershell
  param(
    [Parameter(Mandatory=$true)]
    [string]$Password
  )
  ```

---

#### WR-03: `qm create` uses `--machine pc` (i440fx) instead of `q35` for all Windows VMs

- **File:** `scripts/proxmox/provision-windows.sh`
- **Line:** ~129
- **Issue:** All 5 VMs are created with `--machine pc` (the legacy i440fx chipset). Proxmox
  recommends `q35` for Windows Server 2019 and Windows 10 as it better emulates modern hardware,
  provides PCIe bus for VirtIO devices, and is required for TPM 2.0 / Secure Boot if needed
  later. More concretely: the `virtio` NIC driver (`--net0 "virtio,bridge=vmbr1"`) works on
  i440fx but Proxmox documentation notes that VirtIO-SCSI-single with `pc` machine type can have
  interrupt routing quirks. If the VMs fail to detect the VirtIO NIC during Windows setup (before
  VirtIO drivers are installed from ide3), the autounattend DNS and WinRM bootstrap steps will
  silently be applied to a network adapter that has no working driver, resulting in WinRM being
  unreachable post-install. The autounattend XMLs use SATA for the OS disk (no VirtIO needed)
  but both NICs are `virtio`. On `pc` machine type, VirtIO NICs require the `NetKVM` driver from
  the VirtIO ISO — this is present on `ide3`, but Windows Setup's autounattend `FirstLogonCommands`
  run after OOBE, by which time the VirtIO driver may or may not have been auto-detected.
- **Fix:**

  ```bash
  qm create "${VMID}" \
    ...
    --machine q35 \    # was: --machine pc
    ...
  ```

---

#### WR-04: Fixed 90-second reboot wait in domain-join loop is insufficient for Exchange01

- **File:** `scripts/windows/setup/03-domain-join.ps1`
- **Line:** ~104
- **Issue:** After triggering a domain-join reboot with `Add-Computer ... -Restart -Force`, the
  script sleeps a fixed 90 seconds and then attempts to reconnect via WinRM as the domain admin.
  For dc01, sql01, ws01, ws02 this is marginal but plausible. For exchange01 (10240 MiB RAM,
  Exchange installed, 120 GB disk), a post-domain-join reboot takes considerably longer — Exchange
  services restart during boot. A 90-second wait will cause the verification step at line 109
  (`New-PSSession -ComputerName $MgmtIP -Credential $DomainCred`) to fail with a WinRM connection
  refused error, mark exchange01 as `[FAIL] PartOfDomain=False`, and the operator will need to
  manually verify. This is not destructive but is a reliable false-negative.
- **Fix:** Replace the fixed sleep with a retry loop:

  ```powershell
  $timeout = 180  # seconds
  $interval = 10
  $elapsed  = 0
  while ($elapsed -lt $timeout) {
      Start-Sleep -Seconds $interval
      $elapsed += $interval
      try {
          $PostSession = New-PSSession -ComputerName $MgmtIP -Credential $DomainCred `
              -SessionOption $SessionOpts -ErrorAction Stop
          break
      } catch { }
  }
  ```

---

#### WR-05: `C:\Temp` directory creation occurs after the file-exists check in `02-dc01-users.ps1` — ordering inversion; directory may not exist when needed

- **File:** `scripts/windows/setup/02-dc01-users.ps1`
- **Line:** ~142–153
- **Issue:** The script checks `Test-Path $adFindSource` (line 142) where `$adFindSource =
  "C:\Temp\AdFind.exe"`. If the file is missing, `Write-Error` fires (terminating under `Stop`).
  If the file IS present, the script proceeds to line 151: `if (-not (Test-Path "C:\Temp")) {
  New-Item -ItemType Directory -Path "C:\Temp" | Out-Null }`. This mkdir is pointless — if
  `C:\Temp\AdFind.exe` exists, `C:\Temp` obviously exists. Worse, the `adfind.exe` version-check
  at line 159 runs `& $adFindDest -h 2>&1` immediately after copying, but AdFind's `-h` flag
  prints help to stderr and exits non-zero. With `$ErrorActionPreference = "Stop"`, the
  non-zero exit code from `& $adFindDest` will not terminate the script (external process exit
  codes don't trigger Stop mode), but `2>&1` merges stderr into the string, which is fine. The
  real issue is the mkdir ordering: if `C:\Temp` does not exist (unusual but possible on a fresh
  install where the operator never created it), the initial `Test-Path "C:\Temp\AdFind.exe"` on
  line 142 returns `$false` and the script terminates before creating the directory — the operator
  error message says "AdFind.exe not found" but the real problem is a missing directory. The
  pre-copy instruction assumes the operator created `C:\Temp`, but no script creates it.
- **Fix:** Create `C:\Temp` unconditionally before the file check:

  ```powershell
  if (-not (Test-Path "C:\Temp")) { New-Item -ItemType Directory -Path "C:\Temp" | Out-Null }

  if (-not (Test-Path $adFindSource)) {
      Write-Error "[FAIL] AdFind.exe not found at $adFindSource. ..."
  }
  ```

---

#### WR-06: SQL Server ConfigurationFile.ini `SQLSYSADMINACCOUNTS` with multiple space-separated values will cause setup to fail

- **File:** `scripts/windows/setup/06-sql01-install.ps1`
- **Line:** ~52
- **Issue:** The ini entry is:

  ```
  SQLSYSADMINACCOUNTS="LAB\SQL Admins" "LAB\Domain Admins"
  ```

  SQL Server setup's ConfigurationFile.ini requires multiple accounts to be listed as separate
  space-separated quoted tokens on the same line. However, because this value is embedded in a
  PowerShell here-string and written via `Out-File`, the backslash characters will be written
  literally (correct). The SQL setup parser reads this correctly when the line is:
  `SQLSYSADMINACCOUNTS="LAB\SQL Admins" "LAB\Domain Admins"` — this IS the documented multi-value
  syntax. This is not actually a bug.

  HOWEVER: the here-string uses `"$SaPassword"` (line 52 of the here-string context, passed as
  the `$SaPassword` parameter). If the SA password contains characters meaningful to the SQL
  Setup INI parser (equals sign `=`, double-quote `"`, or semicolons), the ini file will be
  malformed and setup will either use a wrong password or fail. There is no sanitisation or
  validation of `$SaPassword` format before it is interpolated into the ini.
- **Fix:** Add a validation guard on `$SaPassword` before generating the ini:

  ```powershell
  if ($SaPassword -match '[=";]') {
      Write-Error "SaPassword contains characters not safe for SQL ConfigurationFile.ini (=, `", ;). Choose a different password."
  }
  ```

---

### Info

#### IN-01: `02-dc01-users.ps1` uses `net user /add /domain` (legacy) rather than `New-ADUser` — no error checking per user

- **File:** `scripts/windows/setup/02-dc01-users.ps1`
- **Line:** ~59–84
- **Issue:** All user and group operations use legacy `net user` and `net group` commands. These
  commands write success/failure to stdout/stderr but do not throw PowerShell terminating errors
  on failure (even with `$ErrorActionPreference = "Stop"`). If a user creation silently fails
  (e.g. password complexity rejection, duplicate account), the script continues. The verification
  section at line 212 will catch it, but the operator must scroll back to find the problem.
- **Fix:** Use `New-ADUser -ErrorAction Stop` for each account, which integrates with
  `$ErrorActionPreference` and provides structured error objects. At minimum, check
  `$LASTEXITCODE` after each `net user` call.

---

#### IN-02: `provision-windows.sh` — `require_iso` function uses `return 1` with `set -euo pipefail` — may cause unexpected script abort

- **File:** `scripts/proxmox/provision-windows.sh`
- **Line:** ~98–107
- **Issue:** `require_iso` returns exit code 1 when an ISO is missing. The caller uses
  `|| MISSING_ISOS=$((MISSING_ISOS + 1))` to catch it. This works correctly. However, if
  `require_iso` is ever called without the `|| ...` guard (e.g. in a future edit), `set -e`
  will abort the script immediately without printing the summary of all missing ISOs. The
  existing pattern is safe but fragile. Also, the function does not print the missing ISO name
  with a consistent prefix — it writes to stderr with two separate `echo` calls, so if several
  ISOs are missing the output interleaves with the caller's progress messages.
- **Fix:** Low priority. Consider making the function accumulate into a global array rather than
  using return codes, for resilience.

---

#### IN-03: `04-exchange01-prereqs.ps1` Step 2 — `.NET 4.8` installer runs `Restart-Computer -Force` unconditionally without giving the operator a chance to abort

- **File:** `scripts/windows/setup/04-exchange01-prereqs.ps1`
- **Line:** ~70
- **Issue:** After the `.NET 4.8` silent install, the script immediately calls
  `Restart-Computer -Force`. This is run via `Invoke-Command` over WinRM, which means the reboot
  happens on exchange01 without any confirmation prompt or countdown. While the comment says
  "triggers reboot", an operator who runs Step 2 from a terminal that they expected would remain
  connected will lose the WinRM session mid-command with no output. The step does log
  `"Step 2 complete — .NET 4.8 installed"` just before the reboot, so this is more of a UX
  issue than a bug.
- **Fix:** Add a `Start-Sleep -Seconds 5` before the reboot and a prominent message:

  ```powershell
  Write-OK "Step 2 complete — .NET 4.8 installed. Rebooting in 5 seconds..."
  Start-Sleep -Seconds 5
  Restart-Computer -Force
  ```

---

#### IN-04: `verify-phase2.ps1` — `$cred` uses `Administrator` (local) for all VMs including dc01, but post-domain-join the dc01 local Administrator IS the domain Administrator — ambiguity risk on non-English Windows installs

- **File:** `scripts/windows/verify/verify-phase2.ps1`
- **Line:** ~30–31
- **Issue:** A single credential object `New-Object PSCredential("Administrator", $pass)` is
  used for all 5 VMs. On domain controllers, the local `Administrator` account effectively
  becomes `LAB\Administrator`. On non-English Windows installations, the built-in Administrator
  account may have a localised name (e.g. `Administrador` in Spanish locales), which would cause
  WinRM authentication to fail. The evaluation ISOs are en-US so this is unlikely, but the
  autounattend XMLs use `en-US` locale for all VMs, making this a non-issue for the specific
  lab described. Noted for completeness.
- **Fix:** Document the assumption that all VMs use en-US locale and the built-in account name
  is `Administrator`. No code change required for this lab configuration.

---

## Verdict

findings — 4 critical, 6 warning, 4 info

**Must fix before running the lab:**
- CR-01: `GO` in `sqlcmd -Q` — sitedata table will not be created, minfac import will fail
- CR-02: `$AUSettings.Save` → `$AUSettings.Save()` — auto-updates not actually disabled
- CR-03: `Write-Error` string concatenation syntax — error message is broken
- CR-04: `genisoimage` stderr suppressed — ISO build failures are undiagnosable
