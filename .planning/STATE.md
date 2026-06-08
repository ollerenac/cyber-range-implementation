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

**Current phase:** Phase 1 — Proxmox Foundation + SIEM Node
**Current plan:** TBD (not yet planned)
**Status:** Not started

**Progress:**
```
Phase 1  [          ] Not started
Phase 2  [          ] Not started
Phase 3  [          ] Not started
Phase 4  [          ] Not started
Phase 5  [          ] Not started
Phase 6  [          ] Not started
Phase 7  [          ] Not started
```

**Overall:** 0 / 7 phases complete

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

**To resume:** Read ROADMAP.md for phase structure, REQUIREMENTS.md for requirement status, this file for decisions and open questions.

**Next action:** Run `/gsd:plan-phase 1` to decompose Phase 1 into executable plans.

**Phase 1 entry conditions met:**
- [x] ROADMAP.md written
- [x] STATE.md written
- [x] REQUIREMENTS.md traceability confirmed
- [ ] Hardware available for Proxmox installation

---
*State initialized: 2026-06-08*
