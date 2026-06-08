# Research Summary: Cyber Range — APT Emulation & Intrusion Detection

**Synthesized:** 2026-06-08
**Source files:** STACK.md, FEATURES.md, ARCHITECTURE.md, PITFALLS.md, PROJECT.md
**Consumer:** gsd-roadmapper agent

---

## Recommended Stack

### Infrastructure

| Component | Version | Role |
|-----------|---------|------|
| Proxmox VE | 8.x (8.3+ preferred) [VERIFY] | Type-1 hypervisor; `qm snapshot`/`qm rollback` for scripted resets |
| Ubuntu Server | 22.04 LTS | SIEM host (elastic-vm) — never snapshotted, always persistent |
| Windows Server 2019 | Standard/Datacenter Evaluation (180-day free) | DC, Exchange host, SQL host — 2019 ONLY, not 2022 |
| Windows 10 LTSC 2019 | Enterprise Evaluation (90-day free) | Workstation VM (initial access target) |
| Kali Linux | 2024.4+ rolling [VERIFY] | Attacker platform |

### SIEM / Detection

| Component | Version | Role |
|-----------|---------|------|
| Elasticsearch | 8.17.x [VERIFY latest 8.x patch] | Search/analytics engine, event store |
| Kibana | 8.17.x (must match ES exactly) | Dashboards, Detection Rules UI, Fleet UI, ML jobs |
| Fleet Server | 8.17.x | Central agent policy management |
| Elastic Agent | 8.17.x | Unified collector on each target VM (wraps Elastic Defend + Sysmon ingest + Packetbeat) |
| Elastic Defend | Bundled with Agent 8.17.x | EDR — DETECT MODE ONLY during emulation runs |
| Elastic ML | Bundled basic tier | Unsupervised anomaly detection (no labeled training data required) |

### Red Team

| Component | Version | Role |
|-----------|---------|------|
| MITRE CALDERA | 5.x latest stable [VERIFY] | C2 orchestration, ATT&CK-mapped adversary execution |
| Metasploit Framework | 6.x (ships with Kali) | Exploitation and post-exploitation gaps CALDERA does not cover |
| Mimikatz | Latest GitHub release | Credential harvesting (T1003); explicitly required by CTID OilRig plan |
| Impacket | Latest PyPI | Pass-the-Hash, DCSync, SMB lateral movement (T1550.002, T1021.002) |
| BloodHound CE | 6.x Community Edition | AD attack path enumeration (APT29 Scenario 2, Wizard Spider) |
| PsExec (Sysinternals) | Latest | Remote execution (listed in CTID OilRig plan) |
| Plink (PuTTY) | Latest | SSH tunneling / T1572 Protocol Tunneling (listed in CTID OilRig plan) |
| Nmap | 7.9x (ships with Kali) | Network recon / T1046 |

### Telemetry

| Component | Version | Role |
|-----------|---------|------|
| Sysmon | 15.x [VERIFY] | Host telemetry (process, network, file, registry, DNS) |
| olafhartong/sysmon-modular | Latest release | Sysmon config — modular per-VM-role, noise-controlled |
| Packetbeat | 8.17.x | Network flow telemetry (DNS, HTTP, SMB, Kerberos, TLS metadata) |
| Npcap | Latest | Required for Packetbeat on Windows (WinPcap successor) |

**Version pinning rule:** Elasticsearch = Kibana = Fleet Server = Elastic Agent = Packetbeat. All must be the same 8.x patch version. Any mismatch causes enrollment failures.

---

## Table Stakes (Must Deliver)

| Feature | Why Non-Negotiable |
|---------|-------------------|
| Network isolation (no route to real LAN or internet from target VMs) | Without this, telemetry is contaminated and emulation tools can reach real infrastructure |
| AD DC + workstation (minimum target topology) | APT29/OilRig/Wizard Spider all target AD; a flat network invalidates the threat model |
| CALDERA with CTID adversary profiles loaded | Scripted, ATT&CK-mapped execution — not ad-hoc commands |
| Sysmon + Elastic Agent on all target VMs | Host telemetry is the thesis's primary data source |
| Packetbeat on all target VMs | Network telemetry; without it lateral movement and C2 beaconing are invisible |
| Fleet Server managing all agents | Centralized policy; enables one-command Defend mode switching |
| At least one detection rule or ML job firing per scenario | A range that collects but never detects is a data collection exercise |
| Snapshot-based reset script (`reset-lab.sh`) | Core proof of reproducibility; the thesis's methodological claim depends on this |
| MITRE ATT&CK technique traceability per emulated step | Evaluator will audit this; CTID plans provide the mapping |
| Detection recall metric (TP / (TP + FN) per technique) | Quantitative rigor; "attack ran" is not a detection claim |
| GitHub Pages setup guide sufficient for independent reproduction | Stated deliverable; reproducibility is a thesis requirement |

---

## Key Differentiators (Already in Scope)

| Feature | Why It Stands Out |
|---------|------------------|
| Three distinct APT groups with full kill-chain emulation plans | APT29 (covert/LOTL), OilRig (persistent/custom tools), Wizard Spider (financial/ransomware) cover non-overlapping MITRE technique clusters |
| Dual telemetry (host + network) with explicit coverage analysis | Per-technique mapping of what Sysmon sees vs. what Packetbeat sees is a genuine contribution |
| Elastic ML behavioral anomaly detection | Unsupervised free-tier detection layer; demonstrates ML-based detection without custom model training |
| FullAPT-2025 dataset (117 ATT&CK techniques) | Publishable labeled corpus generated by the range — elevates from class project to research output |
| MITRE ATT&CK Navigator heatmaps per APT | Auditable technique coverage; makes thesis figures compelling |
| Three-column results table (Technique / Emulated / Detected / Method) | Honest false-negative analysis is more rigorous than inflated coverage claims |
| CALDERA adversary YAMLs checked into the repo | Makes emulation independently reproducible by anyone with a CALDERA instance |
| One-command reset with post-reset health verification | Verifies agents are enrolled and baseline telemetry is flowing before marking ready |

---

## Critical Decisions (Must Make Early)

### Decision 1: Elastic Defend Mode = DETECT, Not PREVENT

All four research dimensions flag this. PREVENT mode terminates implants before technique artifacts are generated; Sysmon captures process creation but not the protected action (LSASS access, remote thread injection). The resulting alert fires on a tool file hash, not a technique behavior — invalid for a detection-recall study.

**Rule:** Elastic Defend = DETECT mode on all target VMs for all emulation runs. Item 1 on every pre-emulation checklist. Verify via Fleet UI that policy is applied and acknowledged before starting CALDERA operations.

### Decision 2: Windows Server 2019 (Not 2022) as Target OS

WS2022 defaults: SMB signing required (blocks Pass-the-Hash / PsExec), stricter LSA protection (blocks or alerts on Mimikatz before Sysmon captures the LSASS access event). These are real hardening improvements, but in an emulation lab they create uncontrolled interference. WS2019 has these features available but not mandatory-on, giving control over what hardening to test vs. disable.

**Rule:** All target VMs use Windows Server 2019 Standard/Datacenter Evaluation. Document this decision in the thesis methodology section.

### Decision 3: Snapshot Timing — After Agent Enrollment, Simultaneous Across All VMs

Snapshot taken before agent enrollment = re-enrollment required after every reset (breaks one-command reset). Snapshot taken with CALDERA agent running = stale agent state in CALDERA after restore. Snapshots taken at different times = AD USN rollback risk (DC USN > member cached USN → domain auth failure after restore).

**Rule:** Use `qm snapshot` with QEMU guest agent quiesce. Take all VM snapshots simultaneously. Take them after: (a) Sysmon installed and running, (b) Elastic Agent enrolled and "Healthy" in Fleet, (c) CALDERA agent binary NOT present. Test full restore cycle on a single VM before scripting all VMs.

### Decision 4: elastic-vm Is Never Snapshotted / Never Reset

The SIEM VM is the data sink — all Elasticsearch telemetry indices (FullAPT-2025 corpus) and CALDERA server state live here. If elastic-vm is reverted, the corpus is lost. The exercise reset script explicitly excludes it.

**Rule:** `reset-lab.sh` never touches elastic-vm. Index management between runs uses per-run index naming (`apt29-run1-*`, `oilrig-run1-*`) and CALDERA operation archiving via API — not VM snapshot revert.

### Decision 5: Use `qm` (Not `virsh`) for Proxmox Snapshot Operations

`virsh snapshot-create` behaves inconsistently with Proxmox-managed QEMU VMs and qcow2 disk formats in Proxmox 8.x. `qm` is the native Proxmox QEMU CLI and is more reliable.

**Rule:** All reset scripts use `qm snapshot <VMID> <name>` and `qm rollback <VMID> <name>`. Validate on a test VM before writing the production script.

---

## Architecture Overview

### Network Model

```
PROXMOX HOST (bare metal — 32–64 GB RAM, NVMe, 8+ cores)
|
+-- vmbr0: MGMT 10.0.0.0/24 (host-internal, no internet uplink)
|   +-- elastic-vm  10.0.0.10  [ES :9200, Kibana :5601, Fleet :8220, CALDERA :8888/:8853]
|                               NEVER SNAPSHOTTED — ALWAYS RUNNING
|
+-- vmbr1: TARGET 10.0.1.0/24 (air-gapped — no internet uplink)
|   +-- dc01        10.0.1.10  [WS2019 — AD DS + DNS]
|   +-- exchange01  10.0.1.20  [WS2019 — Exchange 2019]
|   +-- sql01       10.0.1.30  [WS2019 — SQL Server 2019 Developer]
|   Each target VM: eth0=TARGET (attack traffic) + eth1=MGMT (telemetry only)
|
+-- vmbr2: ATTACKER 10.0.2.0/24 (air-gapped — no internet uplink)
    +-- kali        10.0.2.5   [eth0=ATTACKER, eth1->TARGET (routed), eth2->MGMT]
```

### Telemetry Data Flow

```
Attack:      CALDERA server (elastic-vm:8853) -> CALDERA agent on Kali -> TTPs -> 10.0.1.x

Host:        Sysmon -> Windows Event Log -> Elastic Agent (Elastic Defend)
             -> MGMT NIC (eth1) -> Fleet Server :8220 -> Elasticsearch :9200
             -> indices: logs-endpoint.events.*, logs-system.*, .sysmon-*
             -> Kibana: Detection Rules + ML anomaly jobs + dashboards

Network:     Packetbeat (Fleet-managed) -> captures DNS/HTTP/SMB/Kerberos/TLS metadata
             -> MGMT NIC -> Elasticsearch -> indices: packetbeat-*

CALDERA:     Operation logs (operation ID, technique ID, timestamp, agent ID)
             -> manual correlation with Elastic timelines
             (no native CALDERA->Elastic connector; workaround: export operation JSON via API)
```

### VM Resource Budget (Single-Host Minimum)

| VM | vCPU | RAM | Disk |
|----|------|-----|------|
| elastic-vm (ES + Kibana + Fleet + CALDERA) | 4 | 8-12 GB | 100 GB SSD |
| dc01 | 2 | 4 GB | 60 GB |
| exchange01 | 4 | 8 GB | 100 GB |
| sql01 | 2 | 4-6 GB | 80 GB |
| kali | 2 | 4 GB | 60 GB |
| Total + snapshots | 14-16 vCPU | 32-48 GB host RAM | ~600 GB |

---

## Build Order

Dependency chain — maps directly to roadmap phases. Each layer must be stable before proceeding.

```
Phase 1: Proxmox Networking
  Create vmbr0 (MGMT), vmbr1 (TARGET), vmbr2 (ATTACKER)
  Configure routing: Kali eth1 -> TARGET; no internet routes from vmbr1/vmbr2
  GATE: victim VM cannot reach 8.8.8.8 or host LAN

Phase 2: elastic-vm (Persistent Management VM)
  Elasticsearch 8.17.x -> Kibana -> Fleet Server -> CALDERA server
  Verify Fleet generates enrollment tokens
  WHY FIRST: Fleet Server must exist before any agent can enroll

Phase 3: dc01 (AD Domain Controller)
  WS2019 -> AD DS + DNS -> AD schema extension
  Npcap -> Sysmon (olafhartong/sysmon-modular) -> Elastic Agent -> enroll to Fleet
  GATE: agent "Healthy" in Kibana; ECS field mapping verified (process.name present)
  SNAPSHOT dc01-clean AFTER enrollment confirmed

Phase 4: exchange01 (Exchange 2019)
  WS2019 -> join domain -> .NET 4.8 + VC++ redist -> Exchange 2019 CU14+
  Npcap -> Sysmon -> Elastic Agent -> enroll to Fleet
  SNAPSHOT exchange01-clean AFTER enrollment
  WHY: OilRig TwoFace webshell + EWS exfiltration require Exchange

Phase 5: sql01 (SQL Server 2019 Developer)
  WS2019 -> join domain -> SQL Server 2019 Developer (free) -> sample DB
  Npcap -> Sysmon -> Elastic Agent -> enroll to Fleet
  SNAPSHOT sql01-clean AFTER enrollment
  WHY: OilRig data exfiltration scenario targets SQL Server

Phase 6: kali (Attacker Platform)
  Kali 2024.4 -> routing to TARGET subnet confirmed
  CALDERA agent connectivity to elastic-vm:8853 confirmed
  SNAPSHOT kali-clean WITHOUT CALDERA agent binary (deploy per-run)

Phase 7: Detection Configuration
  Elastic Defend (DETECT mode) in Fleet policy -> all Windows agents
  Packetbeat integration in Fleet policy
  GATE: run cmd.exe, verify EventID 1 + process.name in ES within 10 seconds
  ILM: 50 GB rollover, 30-day retention
  Prebuilt detection rules imported; ATT&CK coverage matrix gaps identified
  Elastic ML anomaly jobs started
  BASELINE: 24-48 hours normal activity before first emulation run

Phase 8: Reset Mechanism
  reset-lab.sh: qm stop -> qm rollback -> qm start (dc01 first, then members)
  Post-reset health check: elastic-agent status + sysmon running + test event in Kibana
  NTP resync in post-restore boot (w32tm /resync /force)
  CALDERA fact store flush (DELETE /api/v2/facts) in reset procedure
  GATE: full reset completes without re-enrollment; AD domain trust intact after DC restore

Phase 9: APT Emulation Content
  APT29 CTID plan -> CALDERA adversary YAML (smash-and-grab + domain compromise)
  OilRig CTID plan -> CALDERA adversary YAML (SideTwist, TwoFace, VALUEVAULT, RDAT)
  Wizard Spider CTID plan -> CALDERA adversary YAML (Emotet->TrickBot->Ryuk)
  VALIDATE EACH ABILITY MANUALLY before packaging (CALDERA reports success even on silent failure)

Phase 10: Emulation Runs + Dataset Collection
  Each APT: minimum 3 runs; per-run index naming (apt29-run1-*, etc.)
  Three-column results table: Technique | Emulated | Detected | Detection Method
  Recall per technique; aggregate by APT group and detection layer
  Detection gaps documented as research findings
```

---

## Watch Out For (Top 7 Pitfalls)

### 1. CRITICAL — Elastic Defend in PREVENT Mode During Emulation
Implants die before technique artifacts are generated. Detections measure tool file hashes, not technique behavior. Thesis detection claims are methodologically invalid.

**Prevention:** DETECT mode mandatory before every emulation run. Item 1 on pre-emulation checklist. Verify via Fleet UI.

### 2. CRITICAL — Baseline Snapshot Taken Before Agent Enrollment
Every reset requires manual re-enrollment of all agents. Breaks one-command reset. Thesis reproducibility claim fails.

**Prevention:** Take snapshots only after each agent shows "Healthy" in Fleet. Validate with a test restore on one VM first.

### 3. CRITICAL — DC USN Rollback After Restore Breaks Domain Authentication
Exchange/SQL/workstation VMs cannot authenticate to a restored DC whose USN rolled back. Kerberos errors. Emulation cannot run.

**Prevention:** (a) Snapshot all VMs simultaneously, not sequentially. (b) Enable VM Generation ID in Proxmox (default on q35). (c) Test full DC restore before declaring lab ready.

### 4. CRITICAL — Fleet Server TLS Certificate SAN Mismatch Blocks All Enrollment
No agents enroll. Entire detection layer is silent. Lab is inoperable.

**Prevention:** Generate Fleet cert with both `IP:10.0.0.10` and `DNS:fleet.lab` SANs. Distribute CA cert to all VMs via Group Policy. Test enrollment on one VM before deploying fleet-wide.

### 5. CRITICAL — Sysmon ECS Field Mapping Broken
All prebuilt detection rules query ECS fields (`process.name`, `network.destination.ip`). If Sysmon lands as `winlog.event_data.*`, every rule returns zero matches. No alerts fire.

**Prevention:** Use Elastic Agent with Windows integration (not standalone Winlogbeat) — ingest pipeline handles ECS normalization. Verify `process.name` field appears in ES after a known process executes.

### 6. CRITICAL — Elastic ML Jobs Have No Baseline (Started Too Late)
Jobs started immediately before emulation return either zero anomalies or undiscriminating floods. Thesis ML detection claims are dismissed by reviewers.

**Prevention:** Start ML jobs in Phase 7, at least 24-48 hours before first emulation run. Run scripted normal-behavior generator to accelerate baseline building. Document baseline period start time in thesis methodology.

### 7. CRITICAL — Thesis Conflates "Technique Emulated" With "Technique Detected"
A technically rigorous reviewer immediately asks for the false-negative rate. No answer means weak methodology.

**Prevention:** Build three-column results table from the start. Export detection evidence as API NDJSON, not screenshots. Frame detection gaps as findings, not failures.

---

## Open Questions (For Phase-Specific Research)

| Question | Phase | Risk If Wrong |
|----------|-------|---------------|
| Does `qm snapshot --quiesce` work reliably with QEMU guest agent on WS2019 under Proxmox 8.x? | 1 / 8 | Snapshot chain corruption; inconsistent AD state on restore |
| What is the exact CALDERA 5.x ability YAML schema for CTID plan payloads — have schemas changed since the CTID caldera-integration README was written? | 9 | Abilities fail to load; emulation content cannot be packaged |
| Does Elastic ML basic tier include `rare_process` and `network_traffic_anomaly` job types in 8.17.x, or have free-tier limits changed? | 7 | ML detection layer unavailable without paid license |
| What is the exact Exchange 2019 CU14+ install sequence on WS2019 (prerequisite order for .NET 4.8, VC++ redistributables, schema prep)? | 4 | Exchange install fails; OilRig EWS scenario blocked |
| How long does Elastic Agent take to reconnect to Fleet after VM restore — reliably under 3 minutes, or hardware-dependent? | 8 | Reset health check script has wrong wait times; false "ready" signal |
| Does CALDERA 5.x fact store flush via `DELETE /api/v2/facts` still work, or has the API endpoint changed? | 8 / 9 | Stale facts from APT29 run contaminate OilRig run telemetry |
| Which olafhartong/sysmon-modular merge profile covers EventIDs 1, 3, 7, 8, 10, 11, 12, 13, 22 without excessive noise on WS2019 servers? | 3 / 4 / 5 | Either missing critical EventIDs (silent technique gaps) or storage collapse |

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack choices | HIGH | All tools open-source, well-documented, stable. Version numbers need live verification at install time. |
| Feature requirements | HIGH | CTID plans, ATT&CK methodology, Elastic detection architecture are mature, publicly documented. |
| Architecture patterns | HIGH | Dual-NIC target VM pattern, elastic-vm isolation, three-network segmentation are canonical. Dependency constraints are architectural facts. |
| Pitfall identification | HIGH | Fleet TLS enrollment failures, Sysmon ECS mapping, AD USN rollback, Elastic ML warm-up are documented production failure modes. |
| Elastic Defend mode impact | HIGH | Prevent vs. Detect behavior is explicitly documented by Elastic. Consequence for emulation is deterministic. |
| WS2019 vs WS2022 decision | HIGH | WS2022 SMB signing and LSA protection defaults are documented by Microsoft. Impact on credential-theft TTPs is established in attacker tradecraft literature. |
| `qm` snapshot behavior with QEMU guest agent on WS2019 | MEDIUM | Recommended approach, but quiesce behavior with specific Windows builds has edge cases. Must validate on target hardware. |
| Elastic ML free-tier job availability in 8.17.x | MEDIUM | Confirmed available through training cutoff (August 2025). License tier limits could have changed. Verify before relying on ML as detection layer. |
| CALDERA 5.x fact store / agent API endpoints | MEDIUM | Stable through training cutoff. CALDERA 5.x introduced changes from 4.x. Verify against current caldera.readthedocs.io. |

**Overall: HIGH** — all four research dimensions agree on the architectural approach, OS choice, tool stack, and risk profile. Open questions are operational details resolved during execution, not fundamental design uncertainties.

---

## Sources

- CTID Adversary Emulation Library: `/home/researcher/Research/titulacion/github/adversary_emulation_library/`
  - APT29, OilRig, Wizard Spider READMEs; micro_emulation_plans/caldera-integration/README.MD
- Project definition: `/home/researcher/Research/titulacion/.planning/PROJECT.md`
- Elastic Stack 8.x architecture: training data (cutoff August 2025) — Fleet Server, Elastic Defend, Elastic ML basic tier, Elastic Agent Windows integration
- CALDERA 5.x documentation and stockpile plugin architecture: training data
- Proxmox VE 8.x snapshot mechanics: training data; proxmox.com/wiki/Backup_and_Restore
- Microsoft AD DS virtualization safeguards / VM Generation ID: learn.microsoft.com/windows-server/identity/ad-ds
- Exchange Server 2019 system requirements: docs.microsoft.com
- olafhartong/sysmon-modular: github.com/olafhartong/sysmon-modular
- MITRE ATT&CK Evaluations detection methodology: attackevals.mitre-engenuity.org
- Academic cyber range design literature (NIST SP 800-series, ENISA guidance): training data

**All version numbers marked [VERIFY] require live confirmation at first setup session.**
