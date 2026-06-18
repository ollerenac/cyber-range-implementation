---
plan: 02-05
phase: 02-windows-target-network
status: complete
wave: 4
completed: "2026-06-18"
hardware_checkpoint: approved
---

# Plan 02-05 Summary — Exchange Server 2019 on exchange01

## What Was Built

Two PowerShell automation scripts for Exchange Server 2019 CU14+ installation on exchange01:

| File | Lines | Commit | Purpose |
|------|-------|--------|---------|
| `scripts/windows/setup/04-exchange01-prereqs.ps1` | 106 | 697003d | 5-step prerequisite chain with reboots |
| `scripts/windows/setup/05-exchange01-install.ps1` | 163 | b563c6d | PrepareAD + Exchange setup + EWS config + sql_connection.bat |

## Task Outcomes

**Task 1 (04-exchange01-prereqs.ps1):** 5-step prerequisite installer with `-Step N` parameter.
- Step 1: Install-WindowsFeature (Web-Server, RSAT-ADDS, etc.) + auto-reboot
- Step 2: .NET Framework 4.8 silent install + reboot
- Step 3: UCMA 4.0 (from Exchange ISO E:\UCMARedist\)
- Step 4: Visual C++ 2012 x64 + 2013 x64 redistributables
- Step 5: IIS URL Rewrite Module (rewrite_amd64_en-US.msi)

**Task 2 (05-exchange01-install.ps1):** Exchange unattended install with full EWS setup.
- PrepareAD / PrepareAllDomains on dc01 before install
- Setup.exe /Mode:Install /Roles:Mailbox /DoNotEnableEP_FEEWS /IAcceptExchangeServerLicenseTerms
- EWS ApplicationImpersonation management role grant for `tous` service account
- sql_connection.bat scheduled task created (OilRig persistence mechanism for Phase 5)

**Task 3 (hardware checkpoint):** Operator confirmed Exchange EWS endpoint responding.
- `Invoke-WebRequest https://10.0.0.12/EWS/Exchange.asmx -SkipCertificateCheck` → 200/401
- Exchange Management Shell accessible on exchange01

## Key Files

```
scripts/windows/setup/04-exchange01-prereqs.ps1
scripts/windows/setup/05-exchange01-install.ps1
```

## Deviations

None. Scripts follow CTID OilRig emulation plan Exchange requirements exactly.

## Self-Check: PASSED

- [x] 04-exchange01-prereqs.ps1 exists (106 lines)
- [x] 05-exchange01-install.ps1 exists (163 lines, contains DoNotEnableEP_FEEWS)
- [x] Both scripts committed (697003d, b563c6d)
- [x] Hardware checkpoint approved by operator — EWS endpoint confirmed live
- [x] sql_connection.bat scheduled task script embedded in 05-exchange01-install.ps1
