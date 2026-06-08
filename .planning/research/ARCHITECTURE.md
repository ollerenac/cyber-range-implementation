# Architecture Research: Cyber Range — APT Emulation & Intrusion Detection

**Researched:** 2026-06-07
**Confidence:** MEDIUM-HIGH (training knowledge, well-established patterns; no live doc verification due to tool restrictions)

---

## Component Map

### VMs and their roles

| VM | OS | Role | Network membership |
|----|-----|------|--------------------|
| mgmt-host | Proxmox host (bare metal) or Ubuntu | Hypervisor + operator console; runs Elasticsearch, Kibana, Fleet Server, CALDERA | MGMT only (host-level) |
| dc01 | Windows Server 2019/2022 | Active Directory Domain Controller | TARGET |
| exchange01 | Windows Server 2019 + Exchange 2019 | Mail server (lateral movement target) | TARGET |
| sql01 | Windows Server 2019 + SQL Server 2019 | Database server (data exfiltration target) | TARGET |
| kali | Kali Linux (rolling) | Attacker workstation; CALDERA agent (red) optionally co-located | ATTACKER; routable to TARGET for attack traffic |
| elastic-vm | Ubuntu 22.04 LTS | Elasticsearch + Kibana + Fleet Server (dedicated VM) | MGMT; receives agent data from TARGET and ATTACKER |

**Key placement decision:** Elastic Stack lives on a dedicated VM (or the Proxmox management host), NOT on the attacker machine. Rationale: Elastic data must survive the post-exercise reset; if Elastic lives on Kali and Kali is snapshotted/restored, you lose all telemetry. Attacker machine getting isolated or compromised during an exercise also must not take the SIEM down.

**Key placement decision:** CALDERA server lives on the management host or elastic-vm (NOT on Kali). The CALDERA server is the C2 orchestrator that Kali-side agents phone home to. Placing it on a stable, non-snapshotted VM means: (a) CALDERA state persists across VM resets, (b) the operator can issue commands to agents even if Kali is being restored, (c) CALDERA's REST API is reachable by the operator from outside the attack subnet. CALDERA agents (the red-team implants dropped on target VMs or run from Kali) connect outbound to the server.

---

## Network Segmentation

### Three-network model (standard for cyber ranges)

```
┌─────────────────────────────────────────────────────────────┐
│  MGMT NETWORK  10.0.0.0/24                                  │
│  (host-only or dedicated vNIC on Proxmox bridge vmbrMGMT)   │
│                                                             │
│  elastic-vm     10.0.0.10   (Elasticsearch :9200,           │
│                              Kibana :5601,                  │
│                              Fleet Server :8220)            │
│  mgmt-host      10.0.0.1    (Proxmox API, operator SSH)     │
│  CALDERA srv    10.0.0.10   (co-located on elastic-vm       │
│                              :8888 REST, :8853 agent C2)    │
└──────────────────────────┬──────────────────────────────────┘
                           │ Elastic Agents ship telemetry
                           │ over MGMT to Fleet Server
                           │ (agents bound to MGMT interface)
┌──────────────────────────┼──────────────────────────────────┐
│  TARGET NETWORK 10.0.1.0/24 (vmbr1 / internal switch)      │
│                           │                                 │
│  dc01           10.0.1.10  ◄── Elastic Agent + Sysmon       │
│  exchange01     10.0.1.20  ◄── Elastic Agent + Sysmon       │
│  sql01          10.0.1.30  ◄── Elastic Agent + Sysmon       │
│                                                             │
│  Each VM has TWO vNICs:                                     │
│    eth0 → TARGET (attack traffic, AD replication)           │
│    eth1 → MGMT  (Elastic Agent → Fleet Server only)         │
└──────────────────────────┬──────────────────────────────────┘
                           │ attack traffic
┌──────────────────────────┼──────────────────────────────────┐
│  ATTACKER NETWORK 10.0.2.0/24 (vmbr2 / host-only)          │
│                           │                                 │
│  kali           10.0.2.5  ── attack traffic → 10.0.1.x     │
│                              CALDERA agent → 10.0.0.10:8853 │
│                              Elastic Agent → 10.0.0.10:8220 │
│                                                             │
│  Kali has THREE vNICs:                                      │
│    eth0 → ATTACKER (source of attack traffic)               │
│    eth1 → TARGET   (reach victims; routed not bridged)      │
│    eth2 → MGMT     (reach CALDERA srv + Fleet Server)       │
└─────────────────────────────────────────────────────────────┘
```

### Why this segmentation matters

**Problem being solved:** Elastic Agents on target VMs must phone home to Fleet Server, but Fleet Server cannot sit on the TARGET network because (a) the attacker can see it and tamper with telemetry, (b) after a snapshot restore the target VMs must reconnect to the same persistent Fleet Server address without re-enrollment.

**Solution:** Each target VM carries a second vNIC bound to MGMT. The Elastic Agent enrollment URL and Fleet Server address use the MGMT IP (10.0.0.10:8220). This NIC is NOT snapshotted (the Elastic Agent enrollment token and configuration are baked in before snapshotting, so after restore the agent reconnects automatically).

**Proxmox implementation:** Create two Linux bridges on the Proxmox host — `vmbr0` (MGMT, host is on this), `vmbr1` (TARGET, internal, no uplink), `vmbr2` (ATTACKER, internal, no uplink). Assign multiple network interfaces to each VM in the Proxmox VM hardware config. vmbr1 and vmbr2 have no physical uplink, so they are air-gapped from the internet.

**Routing between ATTACKER and TARGET:** On Kali, add a static route: `ip route add 10.0.1.0/24 via 10.0.2.1` (or configure Proxmox to route between vmbr1 and vmbr2 using iptables/nftables on the Proxmox host itself). The management network is NOT routed to the internet.

**Confidence:** HIGH — dual-NIC target VM pattern for isolated telemetry collection is the canonical approach in published cyber range designs (SANS, NIST SP 800-190 lab guides, academic cyber range literature).

---

## Data Flow

### Full telemetry pipeline

```
[Attack execution]
  CALDERA server (10.0.0.10:8888)
    └─ sends task to CALDERA agent on Kali (via :8853 reverse C2)
         └─ Kali executes TTPs against TARGET VMs (10.0.1.x)

[Host telemetry — Windows targets]
  Windows Event Log ──► Sysmon (kernel driver) writes to Security/Sysmon channel
  Elastic Agent (Elastic Defend) reads Windows Event Log
    └─ ships via MGMT NIC (eth1) → Fleet Server 10.0.0.10:8220
         └─ Fleet Server proxies to Elasticsearch 10.0.0.10:9200
              └─ Indices: logs-endpoint.events.*, logs-system.*,
                          metrics-system.*, .sysmon-*
                   └─ Kibana reads indices
                        └─ Elastic ML anomaly jobs run on index patterns
                             └─ Alerting → Kibana dashboards

[Network telemetry — all VMs]
  Packetbeat (runs on each VM, listens on local NIC)
    └─ captures protocol flows: DNS, HTTP, SMB, Kerberos, RDP, etc.
    └─ ships via MGMT NIC → Fleet Server :8220
         └─ Indices: packetbeat-*

[CALDERA telemetry — attack metadata]
  CALDERA server logs: operation ID, technique ID, timestamp, agent ID
    └─ manually correlated with Elastic timelines during analysis
    └─ (No native CALDERA → Elastic integration in open-source CALDERA)
       Workaround: export CALDERA operation JSON, ingest via Filebeat/API
```

### Port summary

| Service | Port | Protocol | Direction |
|---------|------|----------|-----------|
| Elasticsearch | 9200 | HTTPS | Fleet Server → ES; Kibana → ES |
| Kibana | 5601 | HTTPS | Operator browser → Kibana |
| Fleet Server | 8220 | HTTPS | Elastic Agents → Fleet Server |
| CALDERA C2 (HTTP) | 8888 | HTTP | Operator browser → CALDERA |
| CALDERA agent (TCP) | 8853 | TCP | CALDERA agents → server |
| CALDERA agent (UDP) | 8853 | UDP | CALDERA agents → server |
| Sysmon | — | — | Local; writes to Windows Event Log only |
| Packetbeat | — | — | Local; reads from NIC; ships via Agent |

**Note on Elastic Agent vs. standalone Packetbeat:** The modern pattern (Elastic 8.x) is to run Packetbeat as an Elastic Agent integration rather than standalone. This means one `elastic-agent` process on each VM manages both Elastic Defend (EDR) and Packetbeat capture, reporting through Fleet. Standalone Packetbeat (direct to Elasticsearch) also works but loses Fleet management benefits. For this project, the Fleet-managed approach is recommended.

**Confidence:** HIGH for Elastic data flow (well-documented Elastic architecture). MEDIUM for CALDERA→Elastic integration (no native connector; workaround required).

---

## VM Resource Requirements

Resource estimates for a single-host Proxmox deployment. These are minimum viable figures; real performance depends on exercise load.

| VM | vCPU | RAM | Disk | Notes |
|----|------|-----|------|-------|
| elastic-vm (ES + Kibana + Fleet + CALDERA) | 4 | 8–12 GB | 100 GB SSD | Elasticsearch JVM heap = 4 GB min; Kibana ~1 GB; CALDERA ~256 MB. SSD critical — ES is I/O bound. 100 GB fills up with 3-APT telemetry corpus. |
| dc01 (Windows Server + AD DS) | 2 | 4 GB | 60 GB | AD DS baseline. Exchange prereqs require AD schema extension done before Exchange install. |
| exchange01 (Windows Server + Exchange 2019) | 4 | 8 GB | 100 GB | Exchange 2019 minimum: 8 GB RAM, 4 cores. Disk for mail spool + Exchange binaries. |
| sql01 (Windows Server + SQL Server 2019) | 2 | 4–6 GB | 80 GB | SQL Server Developer edition free. 4 GB RAM workable for lab load. |
| kali (attacker) | 2 | 4 GB | 60 GB | Kali rolling + Metasploit + CALDERA agent + tool suite. |
| **Total** | **14–16 vCPU** | **28–34 GB RAM** | **~500 GB** | Proxmox host needs 32–48 GB physical RAM; 8+ physical cores; NVMe preferred |

**Proxmox host recommendation:** 32 GB RAM minimum (tight), 64 GB comfortable. If running on 32 GB, reduce exchange01 to 6 GB and elastic-vm to 8 GB, and accept degraded Elasticsearch performance during heavy indexing.

**Snapshot storage overhead:** Each VM snapshot is a QCOW2 delta. Expect 10–20 GB per snapshot per VM for a full pre-exercise clean state. With 5 VMs = 50–100 GB additional storage for snapshots. Total disk budget: ~600 GB.

**Confidence:** MEDIUM — estimates from Elastic documentation minimums and Exchange 2019 system requirements (well-published). Actual exercise load may require tuning.

---

## Build Order (Dependency Chain)

The dependency chain is strict. Each layer depends on the layer below being stable and snapshotted.

```
Layer 0: Proxmox networking
  └─ Create vmbr0 (MGMT), vmbr1 (TARGET), vmbr2 (ATTACKER)
  └─ Validate inter-bridge routing rules

Layer 1: elastic-vm (must exist before ANY agents enroll)
  ├─ Install Elasticsearch
  ├─ Install Kibana
  ├─ Install Fleet Server (generates enrollment tokens)
  └─ CALDERA server (independent, but co-located for simplicity)
  SNAPSHOT: elastic-vm-clean

Layer 2: dc01 (must exist before Exchange and SQL can join domain)
  ├─ Install Windows Server
  ├─ Promote to Domain Controller (AD DS)
  ├─ Configure DNS (AD-integrated)
  ├─ Extend AD schema for Exchange (if Exchange is next)
  ├─ Install Sysmon (config: SwiftOnSecurity or custom)
  ├─ Install Elastic Agent → enroll to Fleet Server (MGMT NIC)
  └─ Validate telemetry arriving in Kibana
  SNAPSHOT: dc01-clean

Layer 3: exchange01 (requires dc01 domain + schema extension)
  ├─ Join domain (dc01 must be reachable)
  ├─ Install Exchange 2019 prerequisites (.NET, Visual C++ redist)
  ├─ Install Exchange 2019
  ├─ Install Sysmon
  ├─ Install Elastic Agent → enroll to Fleet
  └─ Validate telemetry
  SNAPSHOT: exchange01-clean

Layer 4: sql01 (requires dc01 domain; independent of Exchange)
  ├─ Join domain
  ├─ Install SQL Server 2019 (Developer edition)
  ├─ Configure sample databases (AdventureWorks or custom)
  ├─ Install Sysmon
  ├─ Install Elastic Agent → enroll to Fleet
  └─ Validate telemetry
  SNAPSHOT: sql01-clean

Layer 5: kali (attacker; requires TARGET network to be reachable)
  ├─ Install Kali (all tools)
  ├─ Configure routing to TARGET (10.0.1.0/24)
  ├─ Install CALDERA agent (connects to elastic-vm:8853)
  ├─ Install Elastic Agent (optional — for attacker-side telemetry)
  ├─ Validate CALDERA: server sees kali agent
  └─ Validate routing: kali can reach dc01, exchange01, sql01
  SNAPSHOT: kali-clean

Layer 6: Elastic Stack configuration (requires all agents enrolled)
  ├─ Enable Elastic Defend policy on all Windows agents
  ├─ Enable Packetbeat integration on all agents
  ├─ Configure Sysmon ingest pipeline / integration
  ├─ Create index lifecycle policies (ILM) for telemetry indices
  ├─ Import Kibana dashboards (Windows, Network, Security)
  └─ Configure ML anomaly detection jobs
  SNAPSHOT: elastic-vm-configured

Layer 7: APT emulation content (requires Layers 0–6 complete)
  ├─ Adapt APT29 emulation plan → CALDERA adversary YAML
  ├─ Adapt OilRig emulation plan → CALDERA adversary YAML
  ├─ Adapt Wizard Spider emulation plan → CALDERA adversary YAML
  └─ Test each plan end-to-end
```

**Critical dependency explanation:**

- **Fleet Server before agents:** An Elastic Agent cannot enroll without a reachable Fleet Server and a valid enrollment token. Fleet Server requires Elasticsearch to be running (it stores agent state in ES). Therefore: Elasticsearch → Fleet Server → agents, in strict sequence.
- **DC before Exchange:** Exchange 2019 requires AD Domain Services to exist and the schema extension (`setup.exe /PrepareAD`) to be run from an account with Schema Admin rights. Exchange cannot be installed on a standalone machine.
- **DC before SQL:** SQL Server can be installed standalone, but joining the domain (for Kerberos auth and AD-integrated logins, which APT techniques exploit) requires a working DC.
- **All target VMs enrolled before Elastic configuration:** ML jobs, detection rules, and dashboards reference index patterns that only exist once agents have sent data. Configure detection after at least one telemetry heartbeat per VM.

**Confidence:** HIGH — these dependency constraints are architectural facts (Exchange prereqs, ES→Fleet→Agent enrollment sequence) documented by Microsoft and Elastic respectively.

---

## Reset Architecture

### What state needs to be restored

| Component | State that degrades | Reset mechanism | What persists (intentionally) |
|-----------|--------------------|-----------------|-----------------------------|
| dc01 | Attack artifacts: new user accounts, modified GPOs, registry changes, dropped tools, scheduled tasks, service installs | `virsh snapshot-revert dc01 dc01-clean` | Nothing — full revert |
| exchange01 | Malicious email rules, webshells in IIS/Exchange dirs, modified configs | `virsh snapshot-revert exchange01 exchange01-clean` | Nothing — full revert |
| sql01 | Dropped stored procedures, new SQL logins, exfiltrated data markers | `virsh snapshot-revert sql01 sql01-clean` | Nothing — full revert |
| kali | CALDERA agent state, downloaded loot files, modified tool configs | `virsh snapshot-revert kali kali-clean` | Nothing — full revert |
| elastic-vm | **NOT reverted** — telemetry data is the research output | No revert | All Elasticsearch indices, CALDERA operation logs |
| CALDERA server | Operation state from previous exercise | Partial reset: archive or delete operation via CALDERA API, or restart CALDERA process | Agent registrations can persist |

### What the reset script does

```bash
#!/bin/bash
# cyber-range-reset.sh
# Revert all target VMs to clean snapshot, leave elastic-vm running

set -e

TARGETS=("dc01" "exchange01" "sql01" "kali")
SNAPSHOT="clean"  # snapshot name suffix e.g. dc01-clean

echo "[*] Shutting down target VMs..."
for vm in "${TARGETS[@]}"; do
  virsh shutdown "$vm" --mode acpi 2>/dev/null || true
done

echo "[*] Waiting for VMs to stop..."
sleep 30  # or poll virsh domstate

echo "[*] Reverting snapshots..."
for vm in "${TARGETS[@]}"; do
  virsh snapshot-revert "$vm" "${vm}-${SNAPSHOT}"
  echo "    [+] ${vm} reverted"
done

echo "[*] Starting VMs in dependency order..."
virsh start dc01
sleep 60  # wait for AD DS to come up before domain members start
virsh start exchange01
virsh start sql01
virsh start kali

echo "[*] Reset complete. elastic-vm untouched."
echo "[*] Wait ~3 min for Elastic Agents to reconnect to Fleet Server."
```

### Elastic index management during reset

Because elastic-vm is not reverted, Elasticsearch retains all historical indices. This is desirable (the telemetry corpus is the research deliverable), but for a clean-slate exercise the operator may want to:

1. **Archive previous exercise indices** — use ILM to roll over to a new index generation, or prefix indices with exercise ID (`apt29-run1-*`, `apt29-run2-*`).
2. **Reset CALDERA operation state** — delete the completed operation via CALDERA UI or `DELETE /api/v2/operations/{id}` before starting the next run.
3. **NOT clear Elasticsearch** — retaining all data is correct for building the FullAPT-2025 dataset corpus.

### Elastic Agent reconnection after VM restore

When a target VM is snapshot-reverted, the Elastic Agent process is in the state it was when the snapshot was taken (enrolled, running). On boot after restore:
- The agent reads its enrollment config from disk (persisted before snapshot)
- It re-establishes the Fleet Server connection on the MGMT NIC
- The Fleet Server (which was never reverted) recognizes the agent by its agent ID
- Telemetry resumes within 1–2 minutes of VM boot

**Important:** If the snapshot was taken AFTER agent enrollment and initial check-in, re-enrollment is NOT required after each reset. This is the correct snapshot point — take the clean snapshot only after confirming the agent is enrolled and showing as "Healthy" in Fleet.

**Confidence:** HIGH for virsh snapshot-revert mechanics (standard Proxmox/libvirt). HIGH for Elastic Agent reconnection behavior (it stores enrollment state on disk, reconnects by agent ID). MEDIUM for exact boot wait times (hardware dependent).

---

## Placement Decisions — Summary

### Where does Elastic Stack live?

**Dedicated VM (`elastic-vm`), never snapshotted.**

Rationale: Elasticsearch is the data sink. It must be running continuously and must not lose data. Placing it on the Proxmox host directly (without a VM) is also valid and saves one VM's RAM overhead, but complicates portability. A dedicated VM on MGMT network is cleaner — it can be backed up independently, upgraded independently, and its resource limits set via Proxmox without touching the host.

### Where does CALDERA live?

**Co-located on `elastic-vm` (or management host), NOT on Kali.**

Rationale: CALDERA server is the mission control. It must outlive VM resets. Kali is a target of the reset cycle. If CALDERA lives on Kali and Kali is reverted, all running operations, agent registrations, and operation history are lost. CALDERA on a persistent management VM means: operators can monitor ongoing operations in the Kibana + CALDERA UI simultaneously from the same host, operations survive the VM reset cycle, and the CALDERA REST API is accessible from the management network without exposing it to the attack subnet.

CALDERA agents (the implants) run wherever they are dropped — on Kali (acting as initial access point) and optionally planted on target VMs as lateral movement progresses.

### How do Elastic Agents communicate with Fleet Server when networks are isolated?

**Via the MGMT NIC (second vNIC) on each target VM.**

The target VMs have two NICs:
- `eth0` on TARGET network (10.0.1.x) — used for attack traffic, AD/domain comms
- `eth1` on MGMT network (10.0.0.x) — used exclusively for Elastic Agent → Fleet Server (port 8220)

The Elastic Agent configuration (`fleet.yml`) binds the Fleet Server URL to `https://10.0.0.10:8220`. This address is reachable from the MGMT NIC regardless of what happens to the TARGET NIC during an attack simulation. Even if the attacker disables the primary NIC or manipulates DNS on eth0, telemetry continues to flow on eth1.

This dual-NIC approach is the standard pattern for out-of-band management in network security labs and is directly analogous to how production SOC environments use dedicated management VLANs for security tooling.

**Confidence:** HIGH — dual-NIC out-of-band management is a well-established networking pattern. The specific Elastic Agent behavior (binding to a specific Fleet Server URL in config) is consistent with Elastic Fleet documentation.

---

## Architecture Diagram (ASCII)

```
PROXMOX HOST (bare metal)
│
├── vmbr0: MGMT 10.0.0.0/24 ─────────────────────────────────────────┐
│   │                                                                  │
│   ├── elastic-vm (10.0.0.10)                                         │
│   │   ├── Elasticsearch :9200                                        │
│   │   ├── Kibana :5601                                               │
│   │   ├── Fleet Server :8220 ◄── agents enroll/checkin here         │
│   │   └── CALDERA server :8888/:8853                                 │
│   │                                                                  │
│   └── [MGMT NICs of all other VMs connect here for telemetry]       │
│                                                                      │
├── vmbr1: TARGET 10.0.1.0/24 (no internet uplink) ────────────────┐  │
│   ├── dc01       10.0.1.10  [eth0=TARGET, eth1=MGMT]             │  │
│   ├── exchange01 10.0.1.20  [eth0=TARGET, eth1=MGMT]             │  │
│   └── sql01      10.0.1.30  [eth0=TARGET, eth1=MGMT]             │  │
│                                                                   │  │
└── vmbr2: ATTACKER 10.0.2.0/24 (no internet uplink) ─────────┐   │  │
    └── kali       10.0.2.5   [eth0=ATTACKER, eth1=TARGET,     │   │  │
                                eth2=MGMT]                     │   │  │
                                                               │   │  │
                  attack traffic: eth1 ──────────────────────► └───┘  │
                  CALDERA agent: eth2 ─────────────────────────────►  │
                  Elastic Agent: eth2 ─────────────────────────────►  │
                                                               TARGET  │
                  Windows Elastic Agents: MGMT NIC ────────────────►  └─MGMT
```

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Elastic Stack on the attacker VM
Putting Elasticsearch on Kali means snapshot-reverting Kali destroys all collected telemetry. The attacker machine is in the reset cycle; the SIEM must not be.

### Anti-Pattern 2: Single-NIC target VMs
If target VMs have only one NIC (on the TARGET network), and CALDERA or Elastic Fleet Server also lives on TARGET, then the attacker's lateral movement (e.g., disabling NIC, ARP poisoning, DNS manipulation) can disrupt telemetry collection. Separate management NIC is not optional for a research-grade lab.

### Anti-Pattern 3: Snapshotting elastic-vm
Reverting the SIEM VM destroys the telemetry corpus. Snapshots of elastic-vm are only appropriate for disaster recovery, not for the exercise reset cycle. The reset script explicitly excludes it.

### Anti-Pattern 4: Taking the clean snapshot before Elastic Agent is enrolled
If the snapshot is taken before the agent enrolls with Fleet, every post-revert boot requires re-enrollment. This is manual, slow, and breaks the one-command reset goal. Take the clean snapshot only after the agent shows "Healthy" in Kibana Fleet UI.

### Anti-Pattern 5: CALDERA server on an exercise-participant VM
CALDERA server needs to outlive the VMs it controls. If it is on dc01 and dc01 gets reverted mid-operation, the C2 session is lost. Co-locate CALDERA with the persistent management infrastructure.

---

## Phase Implications for Roadmap

| Build phase | What gets built | Dependency unlocked |
|-------------|-----------------|---------------------|
| Phase 1 | Proxmox networking (bridges, routing) | All VMs can be created |
| Phase 2 | elastic-vm: ES + Kibana + Fleet Server | Agents can enroll |
| Phase 3 | dc01: AD DS + Sysmon + Agent enrolled | Exchange and SQL can join domain |
| Phase 4 | exchange01: Exchange + Sysmon + Agent | Mail-based attack TTPs available |
| Phase 5 | sql01: SQL Server + Sysmon + Agent | Data exfil TTPs available |
| Phase 6 | kali: tools + CALDERA agent + routing | Attack execution possible |
| Phase 7 | CALDERA server config + APT adversaries | Scripted APT runs possible |
| Phase 8 | Elastic detection: Defend policy, ML jobs, dashboards | Detection against attack telemetry |
| Phase 9 | Reset script + snapshot management | Repeatable exercises |
| Phase 10 | APT29 run → APT34 run → Wizard Spider run | FullAPT-2025 corpus collection |

**Confidence:** HIGH for the dependency ordering. Phase sequencing follows hard technical constraints, not arbitrary choices.
