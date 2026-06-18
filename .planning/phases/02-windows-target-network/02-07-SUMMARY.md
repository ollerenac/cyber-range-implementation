---
phase: 02-windows-target-network
plan: "07"
subsystem: windows-setup
tags: [security-baseline, defender-disable, wdigest, uac, qemu-guest-agent, file-generator, chrome, office, workstations]
dependency_graph:
  requires: [02-05, 02-06]
  provides: [07-security-baseline.ps1, 08-workstations.ps1]
  affects: [Phase 3 clean_state snapshot, APT29-S1, APT29-S2, OilRig, Wizard-Spider]
tech_stack:
  added: []
  patterns:
    - CTID modify-defender.ps1 verbatim inclusion with -ErrorAction Continue on all Defender cmdlets
    - CTID disable-automatic-updates.ps1 verbatim inclusion
    - CTID enable-winrm.ps1 verbatim inclusion
    - file_generator.exe invocation pattern (D-08 seed=EVALS)
    - Defender pre-flight exit pattern (Pitfall 8 prevention)
key_files:
  created:
    - scripts/windows/setup/07-security-baseline.ps1
    - scripts/windows/setup/08-workstations.ps1
  modified: []
decisions:
  - "Defender abort-on-still-enabled guard in 08-workstations.ps1 (Pitfall 8 — file_generator silently fails with Defender on)"
  - "Chrome credential caching documented as manual operator step in script output (DPAPI cannot be automated)"
  - "QEMU Guest Agent install with service-start verification and reboot warning (msiexec /quiet may defer service start)"
  - "07-security-baseline.ps1 uses $ErrorActionPreference=Continue globally; CTID Defender cmdlets additionally carry -ErrorAction Continue for re-run safety"
metrics:
  duration_minutes: 25
  tasks_completed: 3
  tasks_total: 3
  files_created: 2
  completed_date: "2026-06-18"
---

# Phase 2 Plan 7: Security Baseline + Workstation Config Summary

**One-liner:** D-12 security baseline (Defender/UAC/WDigest/updates/VC++/QEMU agent) on all 5 VMs, plus ws01 Office+judy-perms+dummy-files and ws02 Chrome+dummy-files via two PowerShell scripts.

---

## What Was Built

### Task 1 — 07-security-baseline.ps1 (276 lines)

Applies eight D-12 settings to a single Windows VM per invocation. Run on all 5 VMs (dc01, exchange01, sql01, ws01, ws02) from the control node via `Invoke-Command -FilePath`.

| Section | Operation | Source |
|---------|-----------|--------|
| 1 | Disable Windows Defender (registry + Set-MpPreference + exclusion + Real-Time Protection key) | CTID oilrig/Resources/setup/modify-defender.ps1 (verbatim) |
| 2 | Disable automatic updates (sc.exe + COM AUSettings.NotificationLevel=1) | CTID oilrig/Resources/setup/disable-automatic-updates.ps1 (verbatim) |
| 3 | Reinforce WinRM (Enable-PSRemoting + TrustedHosts=* + DCOM/WMI firewall rules) | CTID wizard_spider/Resources/setup/enable-winrm.ps1 (verbatim) |
| 4 | UAC = Never Notify (EnableLUA=0, ConsentPromptBehaviorAdmin=0) | RESEARCH.md Example 3 |
| 5 | WDigest UseLogonCredential=1 (APT29 S2 LSASS dump) | RESEARCH.md Example 2 |
| 6 | Visual C++ x86+x64 silent install with prereq check | D-12 requirement |
| 7 | QEMU Guest Agent MSI install + service start verification | RESEARCH.md Q2 |
| 8 | PASS/FAIL verification summary for all 4 settings | Plan acceptance criteria |

Key safety property: every `New-Item`, `New-ItemProperty`, and `Set-MpPreference` call carries `-ErrorAction Continue` — re-runs on partially-configured VMs do not abort the script.

### Task 2 — 08-workstations.ps1 (358 lines)

Accepts `-Target "ws01"` or `-Target "ws02"`. Opens with a shared Defender pre-flight that calls `exit 1` if `RealTimeProtectionEnabled -eq $true`.

**ws01 steps:**
1. Microsoft Office silent install via ODT `setup.exe /configure office-config.xml` (D-09). Verifies OUTLOOK.EXE at expected path after install. Graceful skip with clear instructions if installer absent.
2. `file_generator.exe -path C:\Users\Public\ -count 100 -seed EVALS` and `-path C:\Users\ -count 50 -seed EVALS` (D-08). Verifies file counts after generation.
3. `takeown /f C:\Windows /r /d Y` + `icacls C:\Windows /grant "LAB\judy:(OI)(CI)F" /T` (D-11). Verifies with `icacls | Select-String "judy"`.

**ws02 steps:**
1. Chrome silent install with internet-availability probe — downloads from `dl.google.com/chrome/install/latest/chrome_installer.exe` if reachable, otherwise expects pre-copied `C:\Temp\ChromeSetup.exe` (D-10). Prints 10-line operator instruction block for the manual credential-caching step.
2. Same `file_generator.exe` invocation as ws01 (D-08).

**D-10 password note** is documented in script header: ws01 and ws02 local Administrator passwords must match for APT29 Pass-the-Hash lateral movement.

---

## Checkpoint: APPROVED

**Task 3 — `checkpoint:human-verify` — APPROVED by operator.**

Operator confirmed:
1. Chrome credential saved on ws02 (chrome://password-manager/passwords — at least 1 entry)
2. `verify-phase2.ps1` ran from control node — all checks [PASS]
3. "Phase 2 COMPLETE" message shown

**Operator response:** "approved — verify-phase2.ps1 shows all [PASS], Phase 2 COMPLETE"

---

## Deviations from Plan

None — plan executed exactly as written.

The CTID `modify-defender.ps1` file was found at `oilrig/Resources/setup/` not `oilrig/Resources/preflight/` as the plan interface note indicated. The actual file content was read verbatim from the correct path. This is a doc path discrepancy in the plan, not a functional deviation.

---

## Execution Sequence (control node, run after this plan)

```powershell
# Prerequisites: copy vcredist_x86.exe, vcredist_x64.exe, qemu-ga-x86_64.msi to C:\Temp\ on each VM

$pass = ConvertTo-SecureString "ADMIN_PASSWORD" -AsPlainText -Force
$cred = New-Object PSCredential("Administrator", $pass)
$sessionOpt = New-PSSessionOption -SkipCACheck -SkipCNCheck

# Step 1: Apply security baseline to all 5 VMs
$vms = @{dc01="10.0.0.11"; exchange01="10.0.0.12"; sql01="10.0.0.13"; ws01="10.0.0.14"; ws02="10.0.0.15"}
foreach ($vm in $vms.GetEnumerator()) {
    Write-Host "Applying baseline to $($vm.Key) ($($vm.Value))..."
    $s = New-PSSession -ComputerName $vm.Value -Credential $cred -SessionOption $sessionOpt
    Copy-Item "C:\Temp\vcredist_x86.exe","C:\Temp\vcredist_x64.exe","C:\Temp\qemu-ga-x86_64.msi" `
        -Destination "C:\Temp\" -ToSession $s
    Invoke-Command -Session $s -FilePath "scripts\windows\setup\07-security-baseline.ps1"
    Remove-PSSession $s
}

# Step 2: Reboot all 5 VMs (UAC + WDigest require reboot to take effect)
foreach ($ip in $vms.Values) {
    Invoke-Command -ComputerName $ip -Credential $cred -SessionOption $sessionOpt `
        -ScriptBlock { Restart-Computer -Force }
}
# Wait ~2 minutes for reboots

# Step 3: Run ws01 workstation config
$s1 = New-PSSession -ComputerName "10.0.0.14" -Credential $cred -SessionOption $sessionOpt
Copy-Item "scripts\windows\setup\08-workstations.ps1" -Destination "C:\Temp\" -ToSession $s1
Copy-Item "PATH_TO\file_generator.exe" -Destination "C:\Temp\" -ToSession $s1
# Also copy Office installer: Copy-Item "PATH_TO\setup.exe","PATH_TO\office-config.xml" -Destination "C:\Temp\" -ToSession $s1
Invoke-Command -Session $s1 -ScriptBlock { & "C:\Temp\08-workstations.ps1" -Target "ws01" }
Remove-PSSession $s1

# Step 4: Run ws02 workstation config
$s2 = New-PSSession -ComputerName "10.0.0.15" -Credential $cred -SessionOption $sessionOpt
Copy-Item "scripts\windows\setup\08-workstations.ps1" -Destination "C:\Temp\" -ToSession $s2
Copy-Item "PATH_TO\file_generator.exe" -Destination "C:\Temp\" -ToSession $s2
Invoke-Command -Session $s2 -ScriptBlock { & "C:\Temp\08-workstations.ps1" -Target "ws02" }
Remove-PSSession $s2

# Step 5: MANUAL — Chrome credential caching on ws02 (see checkpoint instructions)
# Step 6: Run verify-phase2.ps1
```

---

## Known Stubs

None. Both scripts are fully functional. File paths and parameter requirements are clearly documented for the operator. Graceful skip with actionable instructions covers the case where optional prerequisites (Office installer, QEMU MSI) are not yet present.

---

## Threat Flags

All threats accepted per plan threat model. No new surface introduced beyond what is in `<threat_model>`:

| Flag | File | Description |
|------|------|-------------|
| threat_flag: accept | 07-security-baseline.ps1 | Defender disabled, WDigest=1 — intentional, isolated lab, documented (T-02-21, T-02-22) |
| threat_flag: accept | 08-workstations.ps1 | judy F perms on C:\Windows — intentional Wizard Spider scenario pre-condition (T-02-23) |
| threat_flag: accept | 08-workstations.ps1 | Chrome dummy credentials — intentional APT29 S1 target (T-02-24) |

---

## Self-Check: PASSED

Files exist:
- [x] scripts/windows/setup/07-security-baseline.ps1 (276 lines, >= 70)
- [x] scripts/windows/setup/08-workstations.ps1 (358 lines, >= 80)

Commits exist:
- [x] 2f2c860 — feat(02-07): create 07-security-baseline.ps1
- [x] 111cceb — feat(02-07): create 08-workstations.ps1

Plan acceptance criteria:
- [x] 07-security-baseline.ps1: UseLogonCredential, DisableAntiSpyware, EnableLUA, QEMU, wuauserv, vcredist, -ErrorAction Continue all present
- [x] 08-workstations.ps1: file_generator, seed EVALS, icacls, Chrome, MANUAL STEP, RealTimeProtectionEnabled all present
- [x] Runtime verification — operator confirmed via verify-phase2.ps1 all [PASS]: Defender=False, WDigest=1, QEMU-GA=Running on all VMs, Chrome installed on ws02 with saved credential
