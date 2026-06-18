# Phase 3: Full Telemetry Pipeline + Reset Mechanism - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-18
**Phase:** 3-Full Telemetry Pipeline + Reset Mechanism
**Areas discussed:** Kali VM setup, Elastic Agent enrollment, Sysmon config strategy, Fleet policy design, Npcap/Packetbeat config, Reset strategy

---

## Kali VM Setup

| Option | Description | Selected |
|--------|-------------|----------|
| Pre-built qcow2 import | Download official Kali VM image from kali.org, qm importdisk into Host 6 LVM-thin. Metasploit/Nmap/Impacket pre-installed. Fastest path; consistent with create-elastic-vm.sh and create-caldera-vm.sh patterns. | ✓ |
| Fresh ISO install | Boot from kali-linux-*.iso, install manually. More control over partitioning/packages but slower and harder to automate. | |

**User's choice:** Pre-built qcow2 import

---

| Option | Description | Selected |
|--------|-------------|----------|
| BloodHound CE + Mimikatz only | Metasploit, Nmap, Impacket are pre-installed. BloodHound CE (Docker Compose) + Mimikatz Windows PE staged for deployment to targets. | ✓ |
| Full tool audit + explicit installs | Explicitly verify/install all tools. More verbose but auditable. | |

**User's choice:** BloodHound CE + Mimikatz only
**Notes:** Metasploit, Nmap, Impacket assumed pre-installed in official Kali image.

---

| Option | Description | Selected |
|--------|-------------|----------|
| No Elastic Agent on Kali | Kali is the attacker — enrolling it mixes red team traffic into baseline telemetry. | |
| Elastic Agent on Kali (Linux) | Captures attacker-side telemetry for Phase 6 correlation. | ✓ (corrected) |

**User's choice:** Elastic Agent on Kali — user initially answered "No" but corrected to "Yes" in the Packetbeat question.
**Notes:** User explicitly stated wanting to log Kali activity in Elasticsearch. Elastic Defend Linux (eBPF) chosen over auditd for unified ECS format.

---

| Option | Description | Selected |
|--------|-------------|----------|
| No Packetbeat on Kali | Avoids mixing attacker traffic into victim-side detection indices. | |
| Packetbeat on Kali | Captures attacker-originated DNS/HTTP/SMB for Phase 6 cross-perspective correlation. | ✓ |

**User's choice:** Packetbeat on Kali
**Notes:** User also wants sysmon-equivalent host events on Kali → resolved as Elastic Defend Linux (EID selection via Elastic Defend, not Sysmon XML which is Windows-only).

---

| Option | Description | Selected |
|--------|-------------|----------|
| Elastic Defend Linux (eBPF/kprobes) | ECS-mapped process trees + network + file events, same format as Windows Elastic Defend. Managed via Fleet. | ✓ |
| auditd + Elastic Agent System integration | Granular syscall logging but different format from Sysmon/Elastic Defend events. | |

**User's choice:** Elastic Defend on Kali via Fleet (Recommended)

---

## Elastic Agent Enrollment

| Option | Description | Selected |
|--------|-------------|----------|
| HTTP download from elastic-vm | Windows VMs download elastic-agent installer from elastic-vm over MGMT NIC. Simple, no SMB. | ✓ |
| Copy via WinRM + PowerShell SMB | Control node SCP to elastic-vm, then Windows VMs pull via SMB. More steps. | |
| Pre-bake into autounattend | Stage installer in VM disk during Phase 2 rebuild. Not practical — snapshots already taken. | |

**User's choice:** HTTP download from elastic-vm (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Single control-node script, loops all VMs | One bash script on elastic-vm iterating all 5 Windows VMs via WinRM. Consistent with reset philosophy. | ✓ |
| Per-VM PowerShell scripts (Phase 2 pattern) | 09-dc01-agent.ps1, etc. — run individually. More granular but 5 scripts vs 1. | |

**User's choice:** Single control-node script, loops all VMs (Recommended)

---

## Sysmon Config Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Core APT detection set: 1,3,7,10,11,13,17,22 | Covers all TELEM-03 mandatory EIDs plus DLL sideloading (7) and DNS (22). | ✓ |
| Minimal required set: 1,3,8,10,11,13 | Exactly TELEM-03 spec. Misses DNS query (22) critical for C2 detection. | |

**User's choice:** Core APT detection set (1,3,7,10,11,13,17,22) for servers

---

| Option | Description | Selected |
|--------|-------------|----------|
| Add EID 15,23,25,26 on workstations | FileCreateStreamHash(15), FileDelete(23), ProcessTampering(25), FileDeleteDetected(26) — ransomware and initial-access specific. | ✓ |
| Same set as servers | Single config for all Windows VMs. Simpler but misses workstation-specific events. | |

**User's choice:** Add EID 15,23,25,26 on workstations (ws01, ws02)

---

## Fleet Policy Design

| Option | Description | Selected |
|--------|-------------|----------|
| Two policies: Windows + Kali-Linux | windows-target (all 5 Windows VMs) + kali-linux (Kali). Simple, auditable. | ✓ |
| Three policies: servers + workstations + kali | Separate server/workstation Windows policies for per-role Elastic Defend tuning. More management overhead. | |

**User's choice:** Two policies: windows-target + kali-linux

---

| Option | Description | Selected |
|--------|-------------|----------|
| DETECT mode from enrollment | Set DETECT in Fleet policy BEFORE first enrollment. Agents enroll already in DETECT mode. | ✓ |
| PREVENT during install, switch before snapshot | Installs in PREVENT, switch to DETECT manually before snapshot. Adds risk of forgetting. | |

**User's choice:** DETECT mode from enrollment (Recommended)

---

## Npcap/Packetbeat Config

| Option | Description | Selected |
|--------|-------------|----------|
| Silent install via enrollment script | `npcap-*.exe /S /winpcap_mode=yes` delivered via WinRM before Elastic Agent installs. | ✓ |
| Pre-bake into Phase 2 VM image | Not possible — Phase 2 snapshots already taken without Npcap. | |

**User's choice:** Silent install via enrollment script (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| APT-focused set: DNS, HTTP, SMB, TLS/JA3, Kerberos, MSSQL | Covers all 3 APT scenario network techniques. No noise from unrelated protocols. | ✓ |
| Full protocol capture: all supported protocols | High noise, no APT coverage benefit. Millions of events from AMQP/MongoDB/Redis/etc. | |

**User's choice:** APT-focused set (DNS, HTTP, SMB, TLS metadata/JA3, Kerberos, MSSQL)
**Notes:** Configured via Fleet integration panel, not standalone packetbeat.yml.

---

## Reset Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Standalone hosts (no cluster) | SSH fan-out from reset control node to each Proxmox host. | ✓ |
| Proxmox cluster (joined) | Single `qm rollback` routes automatically. Requires shared storage. | |

**User's choice:** Standalone hosts — SSH fan-out required

---

| Option | Description | Selected |
|--------|-------------|----------|
| elastic-vm is the control node | elastic-vm (10.0.0.10) always online, excluded from reset, holds SSH keys to all Proxmox hosts. | ✓ |
| Any workstation on MGMT network | Operator's laptop or any 10.0.0.0/24 machine. Less defined. | |

**User's choice:** elastic-vm is the control node (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Poll Fleet API until all agents Healthy | curl to Elasticsearch Fleet agents API every 10s, 5-min timeout. True end-to-end check. Satisfies RESET-03 measurably. | ✓ |
| Fixed sleep (3 min) + ping check | Simpler but fragile — VMs pingable before AD auth recovers. | |

**User's choice:** Poll Fleet API until all agents Healthy (Recommended)

---

## Claude's Discretion

- Kali qcow2 image version (use latest available at setup time)
- HTTP file server implementation on elastic-vm (Python http.server, nginx, or similar)
- Exact Packetbeat JA3 configuration syntax in Fleet integration panel
- SSH key format and distribution (ed25519 via ssh-copy-id during initial lab setup)
- Sysmon.exe download source (Sysinternals or staged on elastic-vm)

## Deferred Ideas

- Host 5 IDS sensor (Suricata/Zeek) — Phase 1 D-NEW-06, reserved for future phases
- Per-role Fleet policies (servers vs workstations) — can split in Phase 4 if needed
- Packetbeat index routing separation (red vs blue telemetry) — Phase 6 data architecture concern
- auditd as supplementary logging on Kali — Phase 4+ enhancement if Elastic Defend Linux proves insufficient
