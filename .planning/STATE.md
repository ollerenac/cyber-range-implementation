---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: 02
current_plan: 7
status: complete
stopped_at: "02-07 COMPLETE — operator approved verify-phase2.ps1 all [PASS]; Phase 2 COMPLETE"
last_updated: "2026-06-18T21:55:00.000Z"
progress:
  total_phases: 7
  completed_phases: 1
  total_plans: 11
  completed_plans: 8
  percent: 14
---

# State: Cyber Range — APT Emulation & Intrusion Detection

**Project:** Cyber Range / APT Emulation Thesis (TSP — FIEE-UNI)
**Last updated:** 2026-06-08

---

## Project Reference

**Core Value:** Un operador ejecuta un escenario APT, observa telemetría real, detecta la intrusión — y resetea todo en un comando para repetirlo.

**Repository:** /home/researcher/Research/titulacion
**Planning dir:** .planning/
**Key artifacts:** ROADMAP.md, REQUIREMENTS.md, PROJECT.md, research/SUMMARY.md

---

## Current Position

Phase: 02 (windows-target-network) — EXECUTING
Plan: 1 of 7
**Current phase:** 02
**Current plan:** 1
**Status:** Executing Phase 02

**Progress:**

```
Phase 1  [▓         ] Planned (4/4 plans written; 0/4 executed)
Phase 2  [▓▓▓▓▓▓▓▓▓▓] Complete (7/7 plans executed: 02-01 through 02-07; all [PASS] on verify-phase2.ps1)
Phase 3  [          ] Not started
Phase 4  [          ] Not started
Phase 5  [          ] Not started
Phase 6  [          ] Not started
Phase 7  [          ] Not started
```

**Overall:** 1 / 7 phases complete — Phase 2 COMPLETE (7/7 plans executed, verify-phase2.ps1 all [PASS])

---

## Performance Metrics

| Metric | Value |
|--------|-------|
| Phases defined | 7 |
| Requirements mapped | 27 / 27 |
| Plans written | 0 |
| Plans complete | 0 |
| Phases complete | 0 |

---

## Accumulated Context

### Decisions Made

| Decision | Rationale | Status |
|----------|-----------|--------|
| Proxmox VE 8.x as hypervisor | Type-1, `qm snapshot`/`qm rollback` scriptable, better performance | Pending validation |
| Elastic ML unsupervised anomaly detection | Free tier, no labeled training data required, legitimately ML | Pending validation |
| Windows Server 2019 (not 2022) for all target VMs | WS2022 SMB signing + LSA protection defaults interfere with credential-theft TTPs uncontrollably | Pending validation |
| Scripted reset (`reset_range.sh`) over manual snapshots | One command, parallel `qm rollback` — enables repeatable exercises | Pending validation |
| Elastic Defend in DETECT mode only | PREVENT kills implants before technique artifacts are generated; invalidates detection-recall study | Pending validation |
| `qm` (not `virsh`) for snapshot operations | `virsh` behaves inconsistently with Proxmox-managed QEMU VMs in 8.x | Pending validation |
| elastic-vm never snapshotted / never reset | SIEM is the data sink — rollback would destroy FullAPT-2025 corpus | Pending validation |
| Per-run index naming (apt29-run1-*, etc.) | Prevents telemetry bleed between runs; no VM snapshot needed on elastic-vm | Pending validation |
| GitHub Pages for setup guide + runbooks only | Thesis is formal UNI submission; GH Pages is the technical reference layer | Pending validation |
| DNS validation gate in 01-dc01-promote.ps1 | RESEARCH.md Q3 failure point #1 — exits with clear message if TARGET NIC DNS != 127.0.0.1 before Install-ADDSForest | Confirmed pattern |
| WinThreshold for both DomainMode and ForestMode | Exchange 2019 requires Windows Server 2016 forest functional level minimum; WS2019 DC supports WinThreshold | Confirmed pattern |
| DSRM password as mandatory -DSRMPassword parameter | No hardcoded credentials; sourced from .planning/secrets/PASSWORDS.md at operator runtime | Confirmed pattern |
| -ErrorAction Continue on all CTID Defender cmdlets | Re-runs on partially-configured VMs must not abort; Defender may already be partially disabled | Confirmed pattern |
| Defender pre-flight exit in 08-workstations.ps1 | file_generator.exe silently fails if Defender is on (Pitfall 8); abort-on-still-enabled guard prevents silent corruption | Confirmed pattern |
| Chrome credential caching is operator-only manual step | Chrome DPAPI ties saved passwords to the logged-in interactive session; cannot be scripted from WinRM | Confirmed pattern |

### Critical Constraints (Non-Negotiable)

- elastic-vm NEVER in reset_range.sh — it is the persistent data sink
- Elastic Defend MUST be DETECT mode before every emulation run — verify in Fleet UI, item 1 on pre-emulation checklist
- Snapshots taken simultaneously across all VMs (not sequentially) — prevents AD USN rollback
- Snapshots taken AFTER all Elastic Agents show "Healthy" in Fleet — not before
- CALDERA agent binary NOT present at snapshot time — deploy per-run only
- Elastic ML needs >= 48h baseline data before first emulation run
- Results table (Technique ID | Emulated | Detected | Detection Method) designed at Phase 6 start — not assembled retroactively
- All Elastic components pinned to same 8.x patch version (Elasticsearch = Kibana = Fleet Server = Elastic Agent = Packetbeat)

### Open Questions (Carry Forward to Phase Plans)

| Question | Phase | Risk |
|----------|-------|------|
| Does `qm snapshot --quiesce` work reliably on WS2019 under Proxmox 8.x? | 1 / 3 | Snapshot chain corruption |
| Elastic ML free-tier: are `rare_process` and `network_traffic_anomaly` job types available in 8.17.x? | 4 | ML detection layer unavailable |
| CALDERA 5.x ability YAML schema — has it changed from CTID caldera-integration README? | 5 | Abilities fail to load |
| Exchange 2019 CU14+ install sequence on WS2019 (exact prerequisite order)? | 2 | Exchange install fails |
| How long does Elastic Agent take to reconnect to Fleet after VM restore? | 3 | Wrong wait times in health check |
| CALDERA fact store flush via `DELETE /api/v2/facts` — still valid in 5.x? | 4 / 5 | Stale facts contaminate cross-scenario runs |
| olafhartong/sysmon-modular merge profile covering EventIDs 1,3,7,8,10,11,12,13,22 without WS2019 server noise? | 3 | Missing critical EventIDs or storage collapse |

### Todos

- [ ] Verify all Elastic version numbers live at first setup session (all marked [VERIFY] in SUMMARY.md)
- [ ] Test `qm snapshot --quiesce` on a throwaway VM before using in production
- [ ] Design pre-emulation checklist (Elastic Defend = DETECT, CALDERA fact flush, reset health check) before Phase 6
- [ ] Design three-column results table schema before Phase 6 begins

### Blockers

None.

---

## Session Continuity

**To resume:** Read `.planning/phases/01-proxmox-foundation-siem-node/.continue-here.md` — full handoff with anti-patterns, remaining work, and decisions. Structured machine state in `.planning/HANDOFF.json`.

**Last session:** 2026-06-18T21:55:00.000Z
**Stopped at:** Phase 2 COMPLETE — all 7 plans executed; verify-phase2.ps1 all [PASS]; operator approved 02-07 checkpoint
**Resume file:** None

**Next action:** Begin Phase 3 — Elastic Agent enrollment + clean_state snapshot. Run `/gsd:execute-phase 03` when ready.

**Phase 1 planning completed:**

- [x] ROADMAP.md written
- [x] STATE.md written
- [x] REQUIREMENTS.md traceability confirmed
- [x] Phase 1 CONTEXT.md — 22 locked decisions (D-01..D-NEW-09)
- [x] Phase 1 RESEARCH.md — Elasticsearch 8.19.16 pin, vmbr1 eno1.10, CALDERA port
- [x] 01-01-PLAN.md — Proxmox networking (vmbr0+vmbr1, VLAN 10, LVM-thin)
- [x] 01-02-PLAN.md — elastic-vm + caldera-vm provisioning
- [x] 01-03-PLAN.md — Elasticsearch 8.19.16 + Kibana + Fleet Server + TLS
- [x] 01-04-PLAN.md — CALDERA 5.3.0 + snapshot/reset + 4 success gates
- [x] plan-checker passed (13/13 decisions covered)
- [ ] Hardware available and operator present for execution

---
*State initialized: 2026-06-08*
