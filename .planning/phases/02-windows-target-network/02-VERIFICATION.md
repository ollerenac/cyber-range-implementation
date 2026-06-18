---
phase: 02-windows-target-network
verified: 2026-06-18T21:03:00Z
status: human_needed
score: 13/16 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Operator RDPs to dc01 and confirms ADUC shows lab.local domain with all 5 computer objects and all 7 D-03 users"
    expected: "ADUC shows DC01, EXCHANGE01, SQL01, WS01, WS02 as joined computer objects; tous, gosta, mariam, shiroyeh, shiroyeh_admin, vfleming, judy all present"
    why_human: "AD domain state requires a live domain controller — cannot be verified without running hardware. Script 02-dc01-users.ps1 and 03-domain-join.ps1 are complete and correct, but operator confirmed execution is pending hardware."
  - test: "EWS endpoint https://10.10.10.20/ews/exchange.asmx (TARGET NIC) returns 200 or 401"
    expected: "HTTP 200 or 401 response from TARGET NIC address — verifies EWS is accessible on the emulation subnet, not just MGMT"
    why_human: "verify-phase2.ps1 only checks MGMT NIC (10.0.0.12). ROADMAP SC2 explicitly requires the TARGET NIC address (10.10.10.20) to respond. The 05-exchange01-install.ps1 documents this as a manual verify step (line 162-163) but does not automate it."
  - test: "Operator logs into ws01 as judy (domain user) and confirms C:\\Users\\Public\\ contains >= 100 dummy files"
    expected: "File count >= 100 in C:\\Users\\Public\\ on ws01; domain logon as judy succeeds"
    why_human: "verify-phase2.ps1 does not check file count (ROADMAP SC4). File generation by file_generator.exe requires Defender to be disabled first — confirmed in 08-workstations.ps1, but requires hardware execution. This is the SC not covered by the automated gate."
---

# Phase 2: Windows Target Network — Verification Report

**Phase Goal:** Deliver all automation scripts needed to provision and configure the Windows target network (5 VMs: dc01, exchange01, sql01, ws01, ws02) from bare metal to a fully-configured Active Directory domain with Exchange EWS, SQL Server with sitedata/minfac, and an intentionally-vulnerable workstation baseline ready for Elastic Agent enrollment.
**Verified:** 2026-06-18T21:03:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Five autounattend XMLs exist with unique ComputerName and complete 5-command WinRM bootstrap | VERIFIED | 5 files in `scripts/windows/autounattend/`; all contain `winrm quickconfig`; ComputerNames DC01/EXCHANGE01/SQL01/WS01/WS02 confirmed present; 4 `OPERATOR_SETS_PASSWORD` tokens per file (no real passwords) |
| 2 | verify-phase2.ps1 covers all 4 INFRA requirements (AD users, SPN, SQL rows, EWS, domain, WDigest) | VERIFIED | 166 lines; confirms New-PSSession to 10.0.0.11-15; checks 7 AD users, SPN, 5 computer objects, minfac count, port 1433, EWS HTTP 200/401, PartOfDomain, UseLogonCredential=1; "Phase 2 COMPLETE" gate at line 165 |
| 3 | Proxmox build-unattend-isos.sh produces 5 unattend ISOs from .planning/secrets/ | VERIFIED | 167 lines; syntax OK; reads from `.planning/secrets/`; calls `genisoimage`; dies if XML missing; prerequisite check for genisoimage |
| 4 | provision-windows.sh creates all 5 VMs with correct VMIDs, RAM, disk, dual NIC, three ISO mounts | VERIFIED | 328 lines; syntax OK; VMIDs 201/202/301/401/402 present; `--ide2 local:iso/${UNATTEND_ISO},media=cdrom`; `--net0 virtio,bridge=vmbr1`; `--net1 virtio,bridge=vmbr0`; `--ide3 virtio-win.iso` |
| 5 | 01-dc01-promote.ps1 installs AD DS and promotes dc01 to lab.local DC with WinThreshold functional level | VERIFIED | 200 lines; DNS set to 127.0.0.1 before Install-ADDSForest (explicit gate at lines 70-73); WinThreshold for both DomainMode and ForestMode; hostname DC01 check; static IP 10.10.10.10/10.0.0.11 |
| 6 | All 7 D-03 user accounts created in lab.local AD with correct groups, SPN, ADFind | VERIFIED | `02-dc01-users.ps1` (241 lines); all 7 users with `/EXPIRES:NEVER`; EWS Admins and SQL Admins groups; `setspn -s MSSQLSvc/sql01.lab.local:1433 LAB\tous` at line 119; adfind.exe install present |
| 7 | exchange01, sql01, ws01, ws02 domain-joined with DNS pre-check before Add-Computer | VERIFIED | `03-domain-join.ps1` (185 lines); `$DcTargetIP = "10.10.10.10"`; `Resolve-DnsName` pre-check before Add-Computer; D-14 snapshot commands for all 5 VMIDs; elastic-vm/caldera-vm excluded from snapshot list |
| 8 | Exchange Server 2019 install script: prerequisites (5-step) + Setup.exe /DoNotEnableEP_FEEWS | VERIFIED | `04-exchange01-prereqs.ps1` (106 lines): Install-WindowsFeature, ndp48, E:\UCMARedist, vcredist_x64_2012/2013, rewrite_amd64. `05-exchange01-install.ps1` (163 lines): `/DoNotEnableEP_FEEWS` at line 78; PrepareAD step present |
| 9 | EWS ApplicationImpersonation role assignment for EWS Admins exists | VERIFIED | `05-exchange01-install.ps1` line 103-104: `New-ManagementRoleAssignment -Name "EWSAdmins-Impersonation" -Role ApplicationImpersonation -SecurityGroup "EWS Admins"` |
| 10 | sql_connection.bat scheduled task on exchange01 connects to sql01.lab.local (not hardcoded original) | VERIFIED | `05-exchange01-install.ps1` line 138: `sqlcmd -S sql01.lab.local -Q "SELECT TOP 1 * FROM sitedata.dbo.minfac"`; schtasks /create present |
| 11 | SQL Server 2019 install: sitedata DB + minfac import via SqlBulkCopy + backup + LAB\tous DBO | VERIFIED | `06-sql01-install.ps1` (231 lines): SqlBulkCopy at lines 188/190; `CREATE LOGIN [LAB\tous] FROM WINDOWS` at line 206; `sp_addrolemember 'db_owner','LAB\tous'` at line 210; sitedata.bak backup at MSSQL15.MSSQLSERVER\MSSQL\Backup\ at line 198 |
| 12 | Port 1433 open in Windows Firewall on sql01 | VERIFIED | `06-sql01-install.ps1` lines 91-95: `New-NetFirewallRule -DisplayName "SQL Server 1433" -Direction Inbound -Protocol TCP -LocalPort 1433` |
| 13 | Security baseline on all 5 VMs: Defender off, UAC never notify, WDigest=1, auto-updates off, VC++, QEMU agent | VERIFIED | `07-security-baseline.ps1` (276 lines): DisableAntiSpyware registry keys + Set-MpPreference with -ErrorAction Continue (verbatim from CTID); EnableLUA=0; UseLogonCredential=1; wuauserv disabled; vcredist_x86/x64; QEMU MSI install |
| 14 | ws01/ws02 workstation config: file_generator (100+50 files), judy icacls, Chrome on ws02 | VERIFIED | `08-workstations.ps1` (358 lines): file_generator -count 100 -seed EVALS (line 146) and -count 50 (line 148); `icacls C:\Windows /grant "LAB\judy:(OI)(CI)F"` present; Chrome download/install for ws02; Defender pre-flight at line 70 |
| 15 | AD domain state confirmed by hardware: all 5 computer objects, all 7 users, SPN registered | UNCERTAIN | 02-04-SUMMARY documents hardware as pending operator execution. 02-02-SUMMARY documents WinRM reachable. 02-07-SUMMARY and ROADMAP record operator "approved — verify-phase2.ps1 shows all [PASS]". The approval implies AD is live but cannot be verified from codebase alone. |
| 16 | EWS accessible on TARGET NIC 10.10.10.20 (ROADMAP SC2 requirement) | UNCERTAIN | verify-phase2.ps1 only checks 10.0.0.12 (MGMT). 05-exchange01-install.ps1 documents this as a manual step (lines 162-163). No automated check covers the TARGET NIC EWS address. Requires human confirmation. |

**Score:** 13/16 truths verified (2 UNCERTAIN routed to human, 1 UNCERTAIN due to hardware dependency)

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/windows/autounattend/dc01-autounattend.xml` | ComputerName=DC01, WinRM bootstrap | VERIFIED | 7546 bytes; OPERATOR_SETS_PASSWORD x4; winrm quickconfig present |
| `scripts/windows/autounattend/exchange01-autounattend.xml` | ComputerName=EXCHANGE01, WinRM bootstrap | VERIFIED | 7716 bytes |
| `scripts/windows/autounattend/sql01-autounattend.xml` | ComputerName=SQL01, WinRM bootstrap | VERIFIED | 7713 bytes |
| `scripts/windows/autounattend/ws01-autounattend.xml` | ComputerName=WS01, WinRM bootstrap | VERIFIED | 7902 bytes |
| `scripts/windows/autounattend/ws02-autounattend.xml` | ComputerName=WS02, WinRM bootstrap | VERIFIED | 8021 bytes |
| `scripts/windows/verify/verify-phase2.ps1` | >=100 lines, 16 checks covering INFRA-03/04/05/06 | VERIFIED | 166 lines; 16 result keys; Phase 2 COMPLETE gate |
| `.planning/secrets/PASSWORDS.md` | Operator fill-in template with all D-03 accounts | VERIFIED | Present on disk (6028 bytes); gitignored — not committed; contains Administrator, DSRM, all 7 domain users, SA password |
| `scripts/proxmox/build-unattend-isos.sh` | genisoimage wrapper >=40 lines | VERIFIED | 167 lines; syntax OK; reads .planning/secrets/ |
| `scripts/proxmox/provision-windows.sh` | qm create for all 5 VMs >=80 lines, vmbr1 present | VERIFIED | 328 lines; syntax OK; all 5 VMIDs; dual NIC; triple ISO |
| `scripts/windows/setup/01-dc01-promote.ps1` | Install-ADDSForest, lab.local, >=50 lines | VERIFIED | 200 lines; WinThreshold; DNS 127.0.0.1 pre-check |
| `scripts/windows/setup/02-dc01-users.ps1` | tous, EWS Admins, SPN, >=60 lines | VERIFIED | 241 lines; all 7 users; setspn present |
| `scripts/windows/setup/03-domain-join.ps1` | lab.local, 10.10.10.10 DNS, >=50 lines | VERIFIED | 185 lines; Resolve-DnsName pre-check; phase2-domain-joined snapshot commands |
| `scripts/windows/setup/04-exchange01-prereqs.ps1` | Install-WindowsFeature, UCMA, >=60 lines | VERIFIED | 106 lines; all 5 prerequisite steps |
| `scripts/windows/setup/05-exchange01-install.ps1` | DoNotEnableEP_FEEWS, PrepareAD, >=80 lines | VERIFIED | 163 lines; /DoNotEnableEP_FEEWS at line 78 |
| `scripts/windows/setup/06-sql01-install.ps1` | sitedata, SqlBulkCopy, >=90 lines | VERIFIED | 231 lines; SqlBulkCopy WriteToServer; CREATE LOGIN; sitedata.bak at D-07 path |
| `scripts/windows/setup/07-security-baseline.ps1` | UseLogonCredential, DisableAntiSpyware, >=70 lines | VERIFIED | 276 lines; all 8 sections present |
| `scripts/windows/setup/08-workstations.ps1` | file_generator, icacls, Chrome, >=80 lines | VERIFIED | 358 lines; all D-08/09/10/11 steps present |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| autounattend XML oobeSystem FirstLogonCommands | WinRM service on each VM | `winrm quickconfig` + AllowUnencrypted + TrustedHosts=* | VERIFIED | All 5 XMLs contain the 5-command WinRM bootstrap block |
| `build-unattend-isos.sh` | `.planning/secrets/*-autounattend.xml` | genisoimage reads from SECRETS_DIR | VERIFIED | Script reads from `.planning/secrets/` explicitly; dies with clear message if XML missing |
| `provision-windows.sh` | `unattend-dc01.iso` (and siblings) in Proxmox ISO storage | `--ide2 local:iso/unattend-dc01.iso,media=cdrom` | VERIFIED | Line 134: `--ide2 "local:iso/${UNATTEND_ISO},media=cdrom"` |
| `01-dc01-promote.ps1` DNS gate | lab.local DNS authoritative | DNS set to 127.0.0.1 before Install-ADDSForest | VERIFIED | Explicit validation gate; script exits 1 if DNS check fails |
| `02-dc01-users.ps1` setspn | LAB\tous SPN for Kerberoasting | `setspn -s MSSQLSvc/sql01.lab.local:1433 LAB\tous` | VERIFIED | Lines 118-125; verify via setspn -Q immediately after |
| `03-domain-join.ps1` | lab.local AD Computers container | DNS set to 10.10.10.10; Add-Computer -DomainName lab.local | VERIFIED | Resolve-DnsName pre-check; Add-Computer at line 90 |
| `05-exchange01-install.ps1` PrepareAD | dc01 AD schema (Exchange org object) | Setup.exe /PrepareAD on dc01 before exchange01 install | VERIFIED | Lines 32-50; objectVersion 16762 check present |
| `06-sql01-install.ps1` SqlBulkCopy | dbo.minfac table | Import-Csv + SqlBulkCopy WriteToServer (not BULK INSERT) | VERIFIED | Lines 140-190; quoted-field-safe import method |
| `07-security-baseline.ps1` UseLogonCredential | verify-phase2.ps1 WDigest check | Registry DWORD set; verified by verify-phase2.ps1 check group 5 | VERIFIED | Script sets value; verify-phase2.ps1 line 146 checks it |
| `05-exchange01-install.ps1` EWS TARGET | OilRig emulation path (10.10.10.20) | /DoNotEnableEP_FEEWS ensures EWS responds; manual verify step documented | PARTIAL | Script documents manual verification at lines 162-163; verify-phase2.ps1 only checks MGMT NIC 10.0.0.12 — TARGET NIC EWS is not in the automated gate |

---

## Data-Flow Trace (Level 4)

Not applicable — all phase artifacts are provisioning/configuration scripts, not components that render dynamic data from a store. Data flow is validated by the verify-phase2.ps1 runtime gate rather than static code analysis.

---

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| build-unattend-isos.sh syntax | `bash -n scripts/proxmox/build-unattend-isos.sh` | exit 0 | PASS |
| provision-windows.sh syntax | `bash -n scripts/proxmox/provision-windows.sh` | exit 0 | PASS |
| All 5 VMIDs present in provision-windows.sh | grep 201/202/301/401/402 | All found | PASS |
| autounattend XMLs: 5 files with winrm quickconfig | grep -l count | 5 | PASS |
| No real passwords in committed XMLs | grep Password (non-placeholder) | 0 matches | PASS |
| verify-phase2.ps1 line count >=100 | wc -l | 166 | PASS |
| No debt markers (TBD/FIXME/XXX/TODO) in any script | grep scan | 0 matches | PASS |
| Runtime: verify-phase2.ps1 all [PASS] gate | Operator report (02-07-SUMMARY) | "Phase 2 COMPLETE" | PASS (operator attested) |

---

## Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| INFRA-03 | 02-01, 02-02, 02-03, 02-04 | dc01 (Windows Server 2019) as AD DC for lab.local | SATISFIED — scripts complete; hardware execution confirmed via operator verify-phase2.ps1 approval | 01-dc01-promote.ps1 (200 lines), 02-dc01-users.ps1 (241 lines), verify-phase2.ps1 AD group checks |
| INFRA-04 | 02-01, 02-02, 02-04, 02-05 | exchange01 (Windows Server 2019) with Exchange 2019, domain joined | SATISFIED — scripts complete; hardware operator-confirmed (EWS 200/401 reported in 02-05-SUMMARY) | 04-exchange01-prereqs.ps1 (106 lines), 05-exchange01-install.ps1 (163 lines, DoNotEnableEP_FEEWS) |
| INFRA-05 | 02-01, 02-02, 02-04, 02-06 | sql01 (Windows Server 2019) with SQL Server 2019, domain joined | SATISFIED — scripts complete; hardware operator-confirmed (port 1433 + minfac rows in 02-06-SUMMARY) | 06-sql01-install.ps1 (231 lines, SqlBulkCopy, sitedata.bak at D-07 path) |
| INFRA-06 | 02-01, 02-02, 02-04, 02-07 | ws01 + ws02 workstations, domain joined, lateral movement target | SATISFIED — scripts complete; operator-confirmed via verify-phase2.ps1 (REQUIREMENTS.md shows INFRA-06 = Complete) | 07-security-baseline.ps1 (276 lines), 08-workstations.ps1 (358 lines) |

All 4 requirement IDs declared across Phase 2 plan frontmatter are accounted for. No orphaned requirements.

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | — | — | No debt markers, stubs, or hardcoded empty values found in any Phase 2 script |

Zero `TBD`, `FIXME`, `XXX`, `TODO`, `HACK`, or `PLACEHOLDER` markers in any file modified by this phase. No `return null` / `return []` stubs. The OPERATOR_SETS_PASSWORD token in autounattend XMLs is an intentional, documented design artifact (not a runtime stub — it is replaced by the operator in `.planning/secrets/` copies before ISO build).

---

## Human Verification Required

### 1. AD Domain State (ROADMAP SC1 — hardware-dependent)

**Test:** Operator RDPs to dc01 (10.0.0.11) and opens Active Directory Users and Computers. Alternatively, runs: `Invoke-Command -ComputerName 10.0.0.11 -Credential (Get-Credential 'LAB\Administrator') -ScriptBlock { Import-Module ActiveDirectory; (Get-ADComputer -Filter *).Name; (Get-ADUser -Filter *).SamAccountName }`

**Expected:** Computer objects: DC01, EXCHANGE01, SQL01, WS01, WS02. User accounts: tous, gosta, mariam, shiroyeh, shiroyeh_admin, vfleming, judy (plus Administrator). SPN query: `setspn -Q MSSQLSvc/sql01.lab.local:1433` returns LAB\tous.

**Why human:** AD domain state requires a live domain controller on hardware. Script 02-dc01-promote.ps1 and 02-dc01-users.ps1 are complete and substantive; the 02-07-SUMMARY records operator approval of verify-phase2.ps1 (which includes AD checks), but direct AD state cannot be confirmed from codebase alone.

---

### 2. EWS on TARGET NIC (ROADMAP SC2 — not covered by automated gate)

**Test:** From any host on the TARGET subnet (10.10.10.0/24), run: `Invoke-WebRequest -Uri "https://10.10.10.20/ews/exchange.asmx" -SkipCertificateCheck -UseBasicParsing | Select-Object StatusCode`

**Expected:** HTTP 200 or 401. This is the emulation-path address used by the OilRig TwoFace webshell scenario.

**Why human:** verify-phase2.ps1 only tests the MGMT NIC address (10.0.0.12). ROADMAP SC2 explicitly requires the TARGET NIC address (10.10.10.20) to respond. The 05-exchange01-install.ps1 documents this as a manual step (lines 162-163) with correct instructions but does not automate it. This check cannot be performed without a live exchange01 VM on the TARGET subnet.

---

### 3. ws01 Dummy Files and judy Domain Login (ROADMAP SC4 — not in automated gate)

**Test:** From control node: `Invoke-Command -ComputerName 10.0.0.14 -Credential (Get-Credential 'LAB\Administrator') -ScriptBlock { (Get-ChildItem 'C:\Users\Public\' | Measure-Object).Count }`. Also: attempt domain logon to ws01 as `LAB\judy`.

**Expected:** File count >= 100 in C:\Users\Public\ on ws01. Domain logon as judy succeeds. Network browsing from ws01 reaches dc01, exchange01, sql01.

**Why human:** verify-phase2.ps1 does not check file count (it covers domain membership and WDigest only for workstations). File generation requires hardware execution of 08-workstations.ps1. ROADMAP SC4 specifies this operator confirmation step explicitly.

---

## Gaps Summary

No gaps blocking goal achievement. All 17 required script artifacts exist, are substantive (well above minimum line counts), contain the required critical patterns (verified by grep), and pass syntax checks where applicable. The phase's primary deliverable — automation scripts for bare-metal-to-configured-domain provisioning — is complete.

The 3 human verification items above are not gaps in the scripts; they are runtime confirmation requirements that necessitate live hardware. The operator has already attested to verify-phase2.ps1 showing all [PASS] (which covers AD users, SPN, SQL minfac rows, EWS on MGMT, domain membership, and WDigest on all VMs). The outstanding human items are the TARGET NIC EWS address, a direct ADUC visual confirmation, and a ws01 file count spot-check.

---

_Verified: 2026-06-18T21:03:00Z_
_Verifier: Claude (gsd-verifier)_
