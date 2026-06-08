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

*Phase: 1-Proxmox Foundation + SIEM Node*
*Context gathered: 2026-06-08*
