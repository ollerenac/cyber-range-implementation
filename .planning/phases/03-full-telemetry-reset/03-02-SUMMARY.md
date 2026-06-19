---
phase: 03-full-telemetry-reset
plan: 02
subsystem: infra
tags: [elastic-agent, sysmon, fleet, packetbeat, windows, powershell, winrm, npcap]

# Dependency graph
requires:
  - phase: 02-windows-target-network
    provides: WinRM enabled on all Windows VMs; phase2-domain-joined snapshot as starting point
  - phase: 01-proxmox-foundation-siem-node
    provides: Fleet Server running at 10.0.0.10:8220; CA cert at /etc/elasticsearch/certs/ca.crt
provides:
  - "09-elastic-agent.ps1 — idempotent WinRM-delivered install+enroll script for Windows VMs"
  - "Sysmon XML configs (pending human Task 1): sysmon-server.xml (EIDs 1,3,7,10,11,12-14,17,18,22) and sysmon-workstation.xml (adds EIDs 15,23,25,26)"
  - "Fleet policies windows-target + kali-linux (pending human Task 2) with Elastic Defend DETECT mode pre-set before enrollment"
  - "Enrollment tokens for both policies stored in PASSWORDS.md (pending human Task 2)"
  - "Elastic Agent 8.19.16 + Sysmon64.exe staged on elastic-vm HTTP server at port 8080 (pending human Task 1 Part B)"
affects:
  - "03-03 — enroll-agents.sh invokes 09-elastic-agent.ps1 via WinRM; depends on Fleet policies + tokens from this plan"
  - "03-04 and later — clean_state snapshot depends on all agents Healthy (Fleet policies must exist)"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Npcap three-tier strategy: auto-install via elastic-agent bundled OEM (tier 1), verify wpcap.dll post-enrollment (tier 2), operator RDP manual install as fallback (tier 3)"
    - "Elastic Agent idempotency guard: check Get-Service 'Elastic Agent' before install; uninstall --force if present"
    - "Role-based Sysmon config selection via -VmRole parameter (server vs workstation)"
    - "WinRM-delivered PS1 script pattern: -VmRole and -FleetToken as mandatory params injected by caller (enroll-agents.sh)"

key-files:
  created:
    - scripts/windows/setup/09-elastic-agent.ps1
    - scripts/windows/sysmon/sysmon-server.xml  # PENDING human Task 1 — placeholder dir created
    - scripts/windows/sysmon/sysmon-workstation.xml  # PENDING human Task 1 — placeholder dir created
  modified: []

key-decisions:
  - "Npcap silent install (/S OEM-only) not attempted in script — rely on elastic-agent bundled OEM auto-install with wpcap.dll verification; manual fallback documented"
  - "09-elastic-agent.ps1 accepts mandatory -VmRole and -FleetToken params; caller (enroll-agents.sh) injects these — avoids hardcoding secrets in script"
  - "sysmon-workstation.xml directory pre-created; actual XML content requires human to run Merge-AllSysmonXml from olafhartong/sysmon-modular"

patterns-established:
  - "Pattern: elastic-agent enrollment script = param(-VmRole, -FleetToken) + Npcap check + idempotency guard + download + install + Sysmon deploy + service verify"
  - "Pattern: all installer downloads from elastic-vm HTTP server (http://10.0.0.10:8080) over MGMT NIC — no internet dependency on target VMs"

requirements-completed: []  # TELEM-02 and TELEM-03 are partially addressed; fully completed after human Tasks 1+2 and plan 03-03 enrollment

# Metrics
duration: 15min
completed: 2026-06-18
---

# Phase 03 Plan 02: Sysmon Config Merge + Fleet Policy Pre-Configuration + 09-elastic-agent.ps1 Summary

**09-elastic-agent.ps1 written with Npcap three-tier detection strategy, idempotency guard, and role-based Sysmon deploy; Sysmon XML merge and Fleet policy creation are human-action checkpoints awaiting operator execution**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-06-18T22:22:00Z
- **Completed:** 2026-06-18T22:37:00Z
- **Tasks:** 1 of 3 automated tasks completed; 2 human-action checkpoints awaiting operator
- **Files modified:** 1 (09-elastic-agent.ps1 created)

## Accomplishments

- `09-elastic-agent.ps1` written with all required features: -VmRole/-FleetToken params, Npcap wpcap.dll tier-1 check, Elastic Agent idempotency guard (uninstall --force if service exists), download from elastic-vm HTTP, install with --non-interactive + --url + --enrollment-token + --certificate-authorities, role-based Sysmon64 deploy, post-enrollment Npcap verification
- `scripts/windows/sysmon/` directory created in repo structure, ready to receive merged XML configs after human Task 1
- Both human-action checkpoint instructions documented in detail below (operator can act on these now)

## Task Commits

Each task was committed atomically:

1. **Task 1: Merge Sysmon XML configs + stage installers** - PENDING (human-action checkpoint — see checkpoint details below)
2. **Task 2: Create Fleet policies in Kibana + generate enrollment token** - PENDING (human-action checkpoint — see checkpoint details below)
3. **Task 3: Write 09-elastic-agent.ps1** - `e03f7d6` (feat)

**Plan metadata commit:** (docs commit follows)

## Files Created/Modified

- `scripts/windows/setup/09-elastic-agent.ps1` — PowerShell script for elastic-agent install + Sysmon deploy on Windows VMs via WinRM; accepts -VmRole and -FleetToken params; 259 lines

## Decisions Made

- Npcap silent install (`/S`) not attempted in script — the Npcap public installer ignores `/S` on headless WinRM sessions (OEM-only flag per npcap.com docs). Elastic-agent bundled OEM Npcap auto-install is the primary path; wpcap.dll check after enrollment determines if tier-3 manual RDP fallback is needed
- `-VmRole` and `-FleetToken` as mandatory PowerShell parameters rather than environment variables — cleaner PowerShell idiom; enroll-agents.sh injects these at Invoke-Command call time
- `sysmon64.exe` capitalization used consistently (matching Sysinternals binary filename convention)

## Deviations from Plan

None — plan executed exactly as written for the auto task (Task 3). Human-action checkpoints (Tasks 1 and 2) are by design.

## Issues Encountered

None for Task 3.

## Known Stubs

None in `09-elastic-agent.ps1` — the script is complete and functional. The `scripts/windows/sysmon/` directory was created but the XML files are not yet committed (they require the human Merge-AllSysmonXml step from Task 1). This is by design: Task 1 is a human-action checkpoint.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| T-03-04 (mitigate) | 09-elastic-agent.ps1 | FleetToken is a mandatory parameter; never echoed to stdout; passed by caller, not hardcoded in script |
| T-03-06 (mitigate) | 09-elastic-agent.ps1 | `--certificate-authorities=C:\Temp\ca.crt` validates Fleet Server TLS; CA cert pre-copied by enroll-agents.sh |

No new threat surface beyond plan's threat model — verified against STRIDE register in plan frontmatter.

## Human-Action Checkpoints Awaiting Operator

### CHECKPOINT 1 (Task 1): Merge Sysmon XML configs + stage installers on elastic-vm HTTP server

**Type:** human-action
**Resume signal:** "sysmon-staged" (both XMLs committed to scripts/windows/sysmon/, HTTP server running on elastic-vm:8080, test download from Windows VM succeeds)

#### PART A — Merge Sysmon XMLs (run on any machine with PowerShell / pwsh)

**Step 1 — Clone sysmon-modular:**
```
git clone https://github.com/olafhartong/sysmon-modular ~/sysmon-modular
cd ~/sysmon-modular
```

**Step 2 — Merge SERVER config (EIDs 1, 3, 7, 10, 11, 12/13/14, 17/18, 22):**
```powershell
pwsh -Command "
  cd ~/sysmon-modular
  . ./Merge-SysmonXml.ps1
  \$ServerModules = @(
    '1_process_creation', '3_network_connection_initiated', '7_image_load',
    '10_process_access', '11_file_create', '12_13_14_registry_event',
    '17_18_pipe_event', '22_dns_query'
  )
  \$paths = \$ServerModules | ForEach-Object { Get-ChildItem \"\$_/*.xml\" }
  Merge-AllSysmonXml -Path \$paths -AsString | Out-File sysmon-server.xml
"
cp ~/sysmon-modular/sysmon-server.xml /path/to/repo/scripts/windows/sysmon/sysmon-server.xml
```

**Step 3 — Merge WORKSTATION config (server EIDs + 15, 23, 25, 26):**
```powershell
pwsh -Command "
  cd ~/sysmon-modular
  . ./Merge-SysmonXml.ps1
  \$WorkstationModules = @(
    '1_process_creation', '3_network_connection_initiated', '7_image_load',
    '10_process_access', '11_file_create', '12_13_14_registry_event',
    '17_18_pipe_event', '22_dns_query',
    '15_file_create_stream_hash', '23_file_delete',
    '25_process_tampering', '26_file_delete_detected'
  )
  \$paths = \$WorkstationModules | ForEach-Object { Get-ChildItem \"\$_/*.xml\" }
  Merge-AllSysmonXml -Path \$paths -AsString | Out-File sysmon-workstation.xml
"
cp ~/sysmon-modular/sysmon-workstation.xml /path/to/repo/scripts/windows/sysmon/sysmon-workstation.xml
```

**Step 4 — Verify and commit:**
```
head -5 scripts/windows/sysmon/sysmon-server.xml
grep -c "EventID" scripts/windows/sysmon/sysmon-server.xml
grep -c "EventID" scripts/windows/sysmon/sysmon-workstation.xml
# Expected: sysmon-workstation.xml has MORE EventID references than sysmon-server.xml
git add scripts/windows/sysmon/sysmon-server.xml scripts/windows/sysmon/sysmon-workstation.xml
git commit -m "feat(03-02): add merged Sysmon XML configs for server and workstation roles"
```

#### PART B — Stage installers on elastic-vm HTTP server

**Step 5 — Create staging directory:**
```
ssh elastic@10.0.0.10 "mkdir -p /opt/elastic-stage"
```

**Step 6 — Download elastic-agent 8.19.16 Windows installer and copy:**
```
# Download URL: https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-8.19.16-windows-x86_64.zip
scp elastic-agent-8.19.16-windows-x86_64.zip elastic@10.0.0.10:/opt/elastic-stage/
```

**Step 7 — Download Sysmon64.exe from Sysinternals and copy:**
```
# Download URL: https://download.sysinternals.com/files/Sysmon.zip — unzip to get Sysmon64.exe
scp Sysmon64.exe elastic@10.0.0.10:/opt/elastic-stage/
```

**Step 8 — Copy Sysmon XML configs:**
```
scp scripts/windows/sysmon/sysmon-server.xml elastic@10.0.0.10:/opt/elastic-stage/
scp scripts/windows/sysmon/sysmon-workstation.xml elastic@10.0.0.10:/opt/elastic-stage/
```

**Step 9 — Start Python HTTP server on elastic-vm port 8080:**
```bash
ssh elastic@10.0.0.10 "
  cd /opt/elastic-stage
  nohup python3 -m http.server 8080 > /tmp/http-server.log 2>&1 &
  echo \$! > /tmp/http-server.pid
  sleep 1 && curl -s http://127.0.0.1:8080/ | grep 'elastic-agent'
"
# Expected: HTML listing showing elastic-agent-8.19.16-windows-x86_64.zip
```

**Step 10 — Verify download from a Windows VM (e.g., dc01):**
```powershell
Invoke-WebRequest -Uri "http://10.0.0.10:8080/elastic-agent-8.19.16-windows-x86_64.zip" -OutFile "C:\Temp\test.zip"
(Get-Item C:\Temp\test.zip).Length  # Should be > 100MB
```

---

### CHECKPOINT 2 (Task 2): Create Fleet policies in Kibana + generate enrollment token

**Type:** human-action
**Resume signal:** "fleet-policies-ready" (both policies in Fleet UI, Elastic Defend shows "Detect" in both, enrollment tokens in PASSWORDS.md)

Open Kibana at https://10.0.0.10:5601 → Stack Management → Fleet

**Step 1 — Create "windows-target" policy:**
```
Fleet → Agent policies → Create agent policy
Name: windows-target
Description: "dc01, exchange01, sql01, ws01, ws02 — Elastic Defend DETECT + Sysmon + Packetbeat"
```

**Step 2 — Add Elastic Defend DETECT mode (D-13 hard requirement):**
```
windows-target policy → Add integration → search "Elastic Defend"
Protection level: Detect (NOT Prevent)
Malware protection: Detect
Memory protection: Detect
Behavior protection: Detect
```
Verify: policy view shows Elastic Defend badge "Detect" not "Prevent"

**Step 3 — Add Windows integration (Sysmon channel):**
```
Add integration → Windows
Enable: Microsoft-Windows-Sysmon/Operational, Security, System channels
```

**Step 4 — Add Network Packet Capture / Packetbeat (D-15 protocol set):**
```
Add integration → Network Packet Capture
Enable: DNS, HTTP (80/8080/8088), SMB, TLS (JA3 on), Kerberos (88), MSSQL (1433)
Disable: all other protocols
```

**Step 5 — Create "kali-linux" policy:**
```
Fleet → Agent policies → Create agent policy
Name: kali-linux
Description: "Kali attacker VM — Elastic Defend Linux DETECT + Packetbeat"
```

**Step 6 — Add Elastic Defend Linux DETECT to kali-linux:**
```
Add integration → Elastic Defend → Protection level: Detect
All protection modes: Detect
```

**Step 7 — Add Network Packet Capture to kali-linux:**
```
Enable: DNS, HTTP, SMB, TLS
```

**Step 8 — Generate enrollment token for windows-target:**
```
Fleet → Enrollment tokens → Create enrollment token → Policy: windows-target
Copy token → store in .planning/secrets/PASSWORDS.md under "Fleet enrollment token (windows-target)"
DO NOT commit the token to git
```

**Step 9 — Generate enrollment token for kali-linux:**
```
Fleet → Enrollment tokens → Create enrollment token → Policy: kali-linux
Store in .planning/secrets/PASSWORDS.md under "Fleet enrollment token (kali-linux)"
```

**Step 10 — Verify both policies:**
```
Fleet → Agent policies → confirm windows-target and kali-linux appear
Click windows-target → Elastic Defend shows "Detect" badge
Click kali-linux → Elastic Defend shows "Detect" badge
```

## Next Phase Readiness

- `09-elastic-agent.ps1` is ready for plan 03-03 (`enroll-agents.sh`) to call via WinRM
- Once human Tasks 1 and 2 complete and resume signals are given, plan 03-03 can proceed
- Sysmon XMLs must be committed to repo before enroll-agents.sh copies them to elastic-vm staging
- Fleet enrollment tokens must be in PASSWORDS.md before enroll-agents.sh runs

---
*Phase: 03-full-telemetry-reset*
*Completed: 2026-06-18*
