# Phase 1: Proxmox Foundation + SIEM Node - Context

**Gathered:** 2026-06-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 1 delivers: the hypervisor networking fabric on each physical host (vmbr0 MGMT 10.0.0.0/24, vmbr1 TARGET 10.10.10.0/24, VLAN 10 on managed switch for cross-host TARGET connectivity) and the persistent SIEM + control node pair (elastic-vm running Elasticsearch + Kibana + Fleet Server; caldera-vm running CALDERA 5.x) — both ready for Elastic Agent enrollment and a Fleet enrollment token to be issued.

**Success gate (from ROADMAP.md):**
1. SSH into any Proxmox host → vmbr0 and vmbr1 bridges exist, vmbr1 has no physical uplink
2. `https://10.0.0.10:5601` → Kibana loads, Elasticsearch cluster health is green
3. Fleet UI → active Fleet Server with a valid enrollment token
4. A test VM on vmbr1 cannot ping 8.8.8.8 or any LAN host (network isolation confirmed)

</domain>

<decisions>
## Implementation Decisions

### Networking (cross-host TARGET connectivity)
- **D-01:** VLAN 802.1Q on the managed switch already available — VLAN 10 carries the TARGET network (10.10.10.0/24). Each Proxmox host connects its vmbr1 bridge to a VLAN 10 access or trunk port on the switch.
- **D-02:** vmbr1 has NO physical uplink on any host — TARGET VMs cannot reach the internet or the host LAN. VLAN 10 on the switch is isolated from the LAN at the switch level (access VLAN only, no inter-VLAN routing to LAN).
- **D-03:** vmbr0 (MGMT, 10.0.0.0/24) connects normally to the LAN — Elastic Agents enroll via MGMT NIC, not via TARGET NIC.

### Storage (Proxmox VM disks)
- **D-04:** LVM-thin as the storage backend on every Proxmox host. No ZFS (avoids 1-2 GB RAM overhead per host on 16 GB machines).
- **D-05:** One snapshot per VM: `clean_state`. No multi-snapshot chains. `qm rollback <vmid> clean_state` is the single reset command. Thin-pool stays predictable without snapshot accumulation.
- **D-06:** ~500 GB SSD/HDD available per physical machine. elastic-vm disk: 200 GB. caldera-vm disk: 40 GB. Remaining disk allocated to Windows target VMs on their respective hosts.

### elastic-vm / caldera-vm RAM and placement
- **D-07:** One physical machine (Proxmox) hosts two VMs that are NEVER in the reset cycle:
  - `elastic-vm` (Ubuntu 22.04): Elasticsearch 8.17.x + Kibana + Fleet Server — 12 GB RAM, 200 GB disk
  - `caldera-vm` (Ubuntu 22.04): CALDERA 5.x — 4 GB RAM, 40 GB disk
- **D-08:** Elasticsearch heap: `Xms8g` / `Xmx8g` (8 GB, equal values — no GC expansion latency). OS retains ~4 GB for page cache + Kibana (~1 GB) + Fleet Server (~512 MB).
- **D-09:** The other 4-5 physical machines run Proxmox and host the Windows target VMs (dc01, exchange01, sql01, ws01) and Kali — all in the reset cycle.
- **D-10:** elastic-vm and caldera-vm are NEVER snapshotted and NEVER included in `reset_range.sh`. This is a hard constraint carried from STATE.md.

### TLS — Fleet Server certificate
- **D-11:** Lab-own CA generated with `elasticsearch-certutil ca` (or openssl). Fleet Server certificate signed by this CA.
- **D-12:** Fleet Server cert SAN includes `IP:10.0.0.10` (no DNS dependency — Elastic Agents connect by IP). CN: `fleet-server` or `elastic-vm`.
- **D-13:** CA cert distribution: the VM provisioning script for each target host copies the CA cert from elastic-vm via SCP/HTTPS before running `elastic-agent enroll`. This step is part of the Phase 3 onboarding sequence, but the CA cert must be generated and placed on elastic-vm during Phase 1.

### Claude's Discretion
- Exact Proxmox network bridge configuration syntax (nmcli vs `/etc/network/interfaces` vs Proxmox WebUI) — use whatever the Proxmox 8.x documentation recommends for each approach.
- Managed switch VLAN configuration steps — depends on switch vendor/model (not specified); planner should note this as an operator-specific step with a generic 802.1Q trunk example.
- ILM (Index Lifecycle Management) policy for `logs-*` indices — planner can propose 30-day hot→delete with reasonable defaults.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project context
- `.planning/PROJECT.md` — What this project is, Core Value, constraints (local hardware only, free Elastic tier, open-source tools only)
- `.planning/REQUIREMENTS.md` — INFRA-01 (Proxmox bridges) and INFRA-02 (elastic-vm) are the two requirements this phase delivers
- `.planning/ROADMAP.md` §Phase 1 — Phase goal, success criteria (4 items), and hard dependency chain
- `.planning/STATE.md` — Critical constraints (especially: elastic-vm NEVER in reset, Elastic Defend DETECT mode, simultaneous snapshots, all Elastic versions pinned to same 8.x patch)

### Architecture and stack decisions
- `.planning/research/ARCHITECTURE.md` — 3-network model, build order, VM resource requirements, elastic-vm as the persistent data sink
- `.planning/research/STACK.md` — Proxmox 8.x rationale, `qm` vs `virsh`, Elastic Defend DETECT mode requirement, sysmon-modular
- `.planning/research/PITFALLS.md` — Anti-patterns to avoid: isolation failure, PREVENT mode, TLS SAN mismatch (directly relevant to D-12/D-13), AD USN rollback

### Lab infrastructure
- `.planning/research/SUMMARY.md` — Consolidated synthesis of all 4 research dimensions

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `github/adversary_emulation_library/` — CTID library (APT29, OilRig, Wizard Spider emulation plans). Not used in Phase 1 but informs why the lab network must be isolated and why elastic-vm must persist across resets.

### Established Patterns
- **No existing codebase** — Phase 1 is greenfield infrastructure. All configuration is manual or scripted from scratch.
- **CTID caldera-integration pattern** (`github/adversary_emulation_library/micro_emulation_plans/caldera-integration/`) — establishes why CALDERA needs its own VM and persistent state across scenarios.

### Integration Points
- Fleet Server (Phase 1) → Elastic Agents on Windows VMs (Phase 3): enrollment token generated here must still be valid in Phase 3.
- CA cert (Phase 1) → VM provisioning script (Phase 3): CA cert path on elastic-vm must be documented for the Phase 3 enrollment script.
- caldera-vm IP (Phase 1) → CALDERA agent beacon URL (Phase 4): agents will phone home to caldera-vm IP, not elastic-vm.

</code_context>

<specifics>
## Specific Ideas

- The managed switch for VLAN 10 is **already available** (confirmed by user) — Phase 1 plan must include the switch configuration step but not procure new hardware.
- elastic-vm and caldera-vm are **VMs on Proxmox** (not bare-metal Ubuntu installs) — they benefit from Proxmox's resource controls but are never snapshotted.
- `qm` (not `virsh`) for all snapshot operations — this is a locked decision from STATE.md.
- Kibana access URL: `https://10.0.0.10:5601` — used in Phase 1 success criteria.
- Fleet Server port: 8220 (Elastic default) on elastic-vm.
- CALDERA port: 8888 (UI) and 8853 (agent beacon) on caldera-vm.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within Phase 1 scope.

</deferred>

---

## Session 2026-06-17 Decisions

These decisions were reached conversationally on 2026-06-17 after the initial discuss-phase. They update or extend D-01..D-13 above and MUST be in scope for any plan generated for this phase.

### VM Resource Revisions

- **D-NEW-01:** `elastic-vm` RAM upgraded to **14 GB** (was 12 GB in D-07). Host 1 is dedicated solely to elastic-vm — no co-tenants. 14 GB gives Elasticsearch heap 8 GB (D-08 unchanged), OS page cache ~4 GB, Kibana ~1 GB, Fleet Server ~512 MB, with ~512 MB headroom for Proxmox QEMU overhead. 2 GB slack under the 16 GB physical ceiling is the acceptable minimum for this configuration.

- **D-NEW-02:** `caldera-vm` relocated from Host 1 to **Host 6** (alongside kali). Host 1 is now exclusively elastic-vm. Operator benefit: red-team operator accesses caldera-vm and kali from one physical host — clean mental model.

- **D-NEW-03:** **ws02 added** — second Windows 10 workstation VM (4 GB RAM, 60 GB disk, Host 4). Required because APT29 Scenario 1, APT29 Scenario 2, and Wizard Spider Scenario 1 all specify ≥2 victim workstations. Original plan only included ws01; ws02 closes this gap. Host 4 carries ws01 (4 GB) + ws02 (4 GB) = 8 GB total, within 16 GB physical.

- **D-NEW-04:** `exchange01` RAM upgraded to **10 GB** (was 8 GB). Exchange Server 2019 benefits from extra heap for EWS request processing. Host 3 is dedicated to exchange01 — 10 GB leaves 6 GB headroom on a 16 GB host, well within limits.

### Host Layout (Final — Option B)

- **D-NEW-05:** **Option B selected** — `dc01` (4 GB RAM, 60 GB disk) and `sql01` (5 GB RAM, 80 GB disk) co-located on **Host 2**. Combined = 9 GB RAM, within 16 GB physical. Trade-off accepted: in a controlled lab, AD + SQL on same host is acceptable because emulation runs are sequential (not concurrent high-load), and this frees Host 5 for a future IDS sensor.

- **D-NEW-06:** **Host 5 = SPARE / future IDS sensor** (Suricata or Zeek). Not provisioned in Phase 1 or Phase 2. Reserved for Phase 5+ when network-based detection is added alongside Elastic Defend. An IDS sensor on the TARGET VLAN would complement Packetbeat and enable rule-based network detections independent of endpoint telemetry.

### IP Address Plan (Locked)

- **D-NEW-07:** **TARGET network IPs (10.10.10.0/24):**

  | VM | IP |
  |----|-----|
  | dc01 | 10.10.10.10 |
  | exchange01 | 10.10.10.20 |
  | sql01 | 10.10.10.30 |
  | ws01 | 10.10.10.40 |
  | ws02 | 10.10.10.50 |
  | kali | 10.10.10.200 |

  Rationale: dc01 gets the lowest address (.10) because domain join requires DC reachable before Exchange and SQL join the domain. kali at .200 is visually separated from victim VMs in any SIEM dashboard.

- **D-NEW-08:** **MGMT network IPs (10.0.0.0/24):**

  | VM | IP | Note |
  |----|-----|------|
  | elastic-vm | 10.0.0.10 | LOCKED — Fleet Server SAN includes IP:10.0.0.10 (D-12) |
  | caldera-vm | 10.0.0.20 | |
  | dc01 | 10.0.0.11 | |
  | exchange01 | 10.0.0.12 | |
  | sql01 | 10.0.0.13 | |
  | ws01 | 10.0.0.14 | |
  | ws02 | 10.0.0.15 | |
  | kali | 10.0.0.16 | |

  elastic-vm .10 is locked by D-12 (Fleet Server cert SAN `IP:10.0.0.10`). Changing this IP would require regenerating the CA and re-enrolling all agents.

### Physical Host Layout (Final)

- **D-NEW-09:** **Physical host assignments:**

  | Host | VMs | Total RAM | Disk |
  |------|-----|-----------|------|
  | Host 1 | elastic-vm (Ubuntu 22.04) | 14 GB | 170 GB thin |
  | Host 2 | dc01 (WS2019) + sql01 (WS2019 + SQL 2019) | 9 GB | 60 + 80 GB thin |
  | Host 3 | exchange01 (WS2019 + Exchange 2019) | 10 GB | 120 GB thin |
  | Host 4 | ws01 (Win10) + ws02 (Win10) | 8 GB | 60 + 60 GB thin |
  | Host 5 | SPARE — future IDS (Suricata/Zeek) | — | — |
  | Host 6 | caldera-vm (Ubuntu 22.04) + kali (Kali 2024.x) | 6 + 4 GB | 40 + 80 GB thin |

  All disk values are thin-provisioned on LVM-thin (D-04). Physical disk per host is 220 GB; all thin allocations have comfortable headroom.

---

*Phase: 1-Proxmox Foundation + SIEM Node*
*Context gathered: 2026-06-08*
*Updated: 2026-06-17 (D-NEW-01..D-NEW-09 added)*
