---
phase: 02-windows-target-network
plan: "01"
subsystem: windows-provisioning
tags: [autounattend, winrm, verification, credentials, scaffolding]
dependency_graph:
  requires: []
  provides:
    - autounattend XMLs for 5 Windows VMs (dc01, exchange01, sql01, ws01, ws02)
    - verify-phase2.ps1 integration test covering INFRA-03/04/05/06
    - .planning/secrets/PASSWORDS.md operator credential fill-in template
  affects:
    - scripts/proxmox/build-unattend-isos.sh (will consume these XMLs)
    - scripts/windows/setup/*.ps1 (run post-WinRM-enabled boot)
    - All subsequent Phase 2 plans (02-02 through 02-07 depend on WinRM being enabled)
tech_stack:
  added:
    - "Windows Unattended Setup (autounattend.xml) — Microsoft Windows Setup XML schema"
    - "WinRM (Windows Remote Management) — HTTP 5985 bootstrap via FirstLogonCommands"
    - "PowerShell Remoting — New-PSSession over WinRM for all post-install automation"
  patterns:
    - "autounattend.xml dual-ISO delivery: genisoimage ISO mounted as second CD-ROM (RESEARCH.md Q1)"
    - "5-command WinRM bootstrap: quickconfig + AllowUnencrypted + Basic auth + firewall + TrustedHosts=*"
    - "OPERATOR_SETS_PASSWORD placeholder token — safe to commit; operator replaces before ISO build"
    - "Test-WinRM helper function encapsulating PSSession creation with SkipCACheck/SkipCNCheck"
key_files:
  created:
    - scripts/windows/autounattend/dc01-autounattend.xml
    - scripts/windows/autounattend/exchange01-autounattend.xml
    - scripts/windows/autounattend/sql01-autounattend.xml
    - scripts/windows/autounattend/ws01-autounattend.xml
    - scripts/windows/autounattend/ws02-autounattend.xml
    - scripts/windows/verify/verify-phase2.ps1
  modified: []
decisions:
  - "Autounattend XMLs stored in scripts/windows/autounattend/ with OPERATOR_SETS_PASSWORD placeholder — safe to track in git. Real-password copies go in .planning/secrets/ (gitignored)"
  - "Dual ISO approach chosen over floppy workaround (RESEARCH.md Q1 recommendation) — genisoimage builds second CD-ROM ISO; Proxmox mounts as --ide2 without -args hack"
  - "ws01/ws02 use Windows 10 image index=1; dc01/exchange01/sql01 use WS2019 index=2 (Desktop Experience)"
  - "Test-WinRM helper function pattern: single New-PSSession call encapsulated, called 5 times — passes acceptance criteria even though grep count shows 1 literal occurrence"
  - "Unreachable-VM error handling added to verify-phase2.ps1: dependent checks marked FAIL gracefully instead of throwing exceptions"
metrics:
  duration_minutes: 25
  tasks_completed: 2
  tasks_total: 2
  files_created: 6
  files_modified: 0
  completed_date: "2026-06-18"
---

# Phase 2 Plan 01: Autounattend XML Scaffolding + Verify Script Summary

**One-liner:** Five per-VM autounattend XMLs with 5-command WinRM bootstrap and OPERATOR_SETS_PASSWORD token, plus a 166-line verify-phase2.ps1 covering 16 integration checks across INFRA-03/04/05/06.

## What Was Built

### Task 1: Autounattend XMLs + Credential Inventory

Five Windows Setup answer files created in `scripts/windows/autounattend/`:

| File | ComputerName | OS Index | Purpose |
|------|-------------|----------|---------|
| dc01-autounattend.xml | DC01 | 2 (WS2019 Desktop Experience) | Domain Controller |
| exchange01-autounattend.xml | EXCHANGE01 | 2 (WS2019 Desktop Experience) | Exchange Server |
| sql01-autounattend.xml | SQL01 | 2 (WS2019 Desktop Experience) | SQL Server |
| ws01-autounattend.xml | WS01 | 1 (Win10 Enterprise Eval) | Workstation 1 / Dorothy |
| ws02-autounattend.xml | WS02 | 1 (Win10 Enterprise Eval) | Workstation 2 / Toto |

Each XML contains:
- **windowsPE pass:** en-US locale, SATA disk (DiskID=0, WillWipeDisk=true, single primary NTFS partition labeled "OS" with letter C, Active=true), OS image install from correct index, AcceptEula=true
- **specialize pass:** ComputerName (unique per VM), TimeZone=UTC
- **oobeSystem pass:** AutoLogon (Administrator, LogonCount=1), AdministratorPassword, FirstLogonCommands (5 WinRM bootstrap commands), full OOBE suppression block

WinRM bootstrap sequence (identical across all 5 VMs):
1. `cmd /c winrm quickconfig -quiet`
2. `cmd /c winrm set winrm/config/service @{AllowUnencrypted="true"}`
3. `cmd /c winrm set winrm/config/service/auth @{Basic="true"}`
4. `cmd /c netsh advfirewall firewall set rule group="remote administration" new enable=yes`
5. `cmd /c winrm set winrm/config/client @{TrustedHosts="*"}`

Password placeholder `OPERATOR_SETS_PASSWORD` appears 4 times per XML (AutoLogon Password value + PlainText, AdministratorPassword Value + PlainText = 4 occurrences). Total 20 across all 5 files. No real passwords committed.

`.planning/secrets/PASSWORDS.md` created locally (gitignored) with operator fill-in template covering:
- 5 VM local Administrator passwords (with D-10 note: ws01 = ws02 for Pass-the-Hash)
- DSRM password for dc01 AD promotion
- 7 domain users: tous, gosta, mariam, shiroyeh, shiroyeh_admin, vfleming, judy
- SQL SA password for sql01
- Instructions for copying XMLs, filling passwords, and building ISOs

### Task 2: verify-phase2.ps1 Integration Test

`scripts/windows/verify/verify-phase2.ps1` (166 lines) — runs from control node via `pwsh verify-phase2.ps1 -Password 'ActualPassword'`

Test groups:

| Group | Checks | Requirement |
|-------|--------|-------------|
| [1] WinRM | 5 VMs reachable on 10.0.0.11-15 | INFRA-03/04/05/06 |
| [2] AD | 7 D-03 users + SPN MSSQLSvc/sql01.lab.local:1433 + 5 computer objects | INFRA-03 |
| [3] SQL | COUNT(*) FROM sitedata.dbo.minfac > 0 + port 1433 LISTENING | INFRA-05 |
| [4] Exchange EWS | https://10.0.0.12/ews/exchange.asmx returns 200 or 401 | INFRA-04 |
| [5] Workstations | PartOfDomain=true + UseLogonCredential=1 on ws01 and ws02 | INFRA-06 |

Output: sorted `[PASS]/[FAIL]` per check, total count, "Phase 2 COMPLETE" (green) or "Phase 2 INCOMPLETE" (red).

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written, with one enhancement:

**[Enhancement] Added unreachable-VM error handling to verify-phase2.ps1**
- **Found during:** Task 2 implementation
- **Issue:** Original RESEARCH.md Q10 template did not handle the case where a VM's PSSession fails — subsequent `Invoke-Command` calls on `$null` session would throw unhandled exceptions rather than recording graceful FAIL results
- **Fix:** Added `else` branches after each session check to record "FAIL: <vm> WinRM unreachable" for all dependent checks when the upstream PSSession fails. Also added 401 exception handling in the Exchange EWS check (PowerShell throws on 401 even though it indicates Exchange is running).
- **Files modified:** scripts/windows/verify/verify-phase2.ps1
- **Commit:** c31b514

### Automated Verify Discrepancy

The plan's automated verify check `grep -c "New-PSSession" | grep -qE "^[3-9]"` expects 3+ literal `New-PSSession` occurrences. The implementation uses a `Test-WinRM` helper function with 1 literal `New-PSSession` call, invoked 5 times. The acceptance criteria (which supersedes the automated check) requires "New-PSSession calls to all 5 MGMT IPs" — satisfied via the helper function pattern from RESEARCH.md Q10.

## Threat Surface Scan

All threat model mitigations applied:

| Threat | Mitigation Applied |
|--------|--------------------|
| T-02-01: autounattend.xml plaintext passwords | OPERATOR_SETS_PASSWORD placeholder in scripts/; real passwords go only in .planning/secrets/ (gitignored) |
| T-02-02: PASSWORDS.md credential inventory | Created in .planning/secrets/ (gitignored). Not committed to repo. |
| T-02-03: PSSession -SkipCACheck/-SkipCNCheck | Documented as intentional lab config for MGMT subnet (vmbr0, LAN-internal only) |

No new threat surface introduced beyond the plan's threat model.

## Known Stubs

| Stub | File | Reason |
|------|------|--------|
| OPERATOR_SETS_PASSWORD | scripts/windows/autounattend/*.xml (all 5) | Intentional placeholder — operator fills in real password in .planning/secrets/ copies before building ISO. By design per T-02-01 mitigation. |
| Password placeholder fields in PASSWORDS.md | .planning/secrets/PASSWORDS.md | Intentional — operator fill-in template. Not a runtime stub. |

These stubs do NOT prevent the plan's goal. The XMLs are templates; operators substitute real values in local .planning/secrets/ copies that are never committed.

## Self-Check

### Files Created

- [x] scripts/windows/autounattend/dc01-autounattend.xml — FOUND
- [x] scripts/windows/autounattend/exchange01-autounattend.xml — FOUND
- [x] scripts/windows/autounattend/sql01-autounattend.xml — FOUND
- [x] scripts/windows/autounattend/ws01-autounattend.xml — FOUND
- [x] scripts/windows/autounattend/ws02-autounattend.xml — FOUND
- [x] scripts/windows/verify/verify-phase2.ps1 — FOUND
- [x] .planning/secrets/PASSWORDS.md — FOUND (gitignored, local only)

### Commits

- [x] ac171ea — feat(02-01): add 5 per-VM autounattend XMLs with WinRM bootstrap + PASSWORDS.md template
- [x] c31b514 — feat(02-01): add verify-phase2.ps1 integration test covering INFRA-03/04/05/06

## Self-Check: PASSED
