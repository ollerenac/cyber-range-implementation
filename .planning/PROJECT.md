# Cyber Range — APT Emulation & Intrusion Detection

## What This Is

A fully virtualized Cyber Range that emulates three real-world APT groups (APT29, OilRig, Wizard Spider) using CTID adversary emulation plans packaged for CALDERA, and detects those attacks via Elastic Stack (SIEM + Elastic Defend EDR + Elastic ML anomaly detection). Dual telemetry is collected via Sysmon (host) and Packetbeat (network). The project also produces a thesis document (Trabajo de Suficiencia Profesional — FIEE-UNI) and publishes a setup guide plus APT runbooks on GitHub Pages.

## Core Value

A working lab where an operator can run a scripted APT scenario, observe real attack telemetry, and detect the intrusion — then reset everything to a clean state in one command and do it again.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Virtualized target network with AD, Exchange, and SQL Server VMs
- [ ] Scripted reset to clean snapshot state (all VMs, one command)
- [ ] APT29 emulation plan adapted for Elastic telemetry + extended MITRE ATT&CK techniques + packaged as CALDERA adversary
- [ ] OilRig (APT34) emulation plan adapted + extended + CALDERA packaged
- [ ] Wizard Spider emulation plan adapted + extended + CALDERA packaged
- [ ] Elastic Stack deployed: Elasticsearch, Kibana, Fleet Server, Elastic Agents
- [ ] Elastic Defend (free EDR) deployed on all target VMs
- [ ] Sysmon + Packetbeat dual telemetry collecting on all VMs
- [ ] Elastic ML anomaly detection jobs configured for behavioral analysis
- [ ] FullAPT-2025 dataset: telemetry corpus covering 117 MITRE ATT&CK techniques
- [ ] Thesis document: all 10 sections written (Introducción → Bibliografía)
- [ ] GitHub Pages site: setup guide + APT emulation runbooks

### Out of Scope

- Custom trained / supervised ML IDS model — using Elastic ML free-tier unsupervised anomaly detection instead
- Cloud deployment — local virtualization only (Proxmox / VirtualBox)
- APT groups beyond APT29, OilRig, Wizard Spider — CTID library has others but thesis scope is these 3
- Production environments — lab only, no real corporate infrastructure
- Monetization or SaaS offering — thesis deliverable, not a product

## Context

- **Foundation library**: `github/adversary_emulation_library` (CTID/MITRE) — contains Emulation_Plan, Operations_Flow, Intelligence_Summary, Resources, and micro_emulation_plans/caldera-integration for each APT group
- **Prior work**: FullAPT-2025 dataset already being constructed at SeoulTech doctoral lab — 117 MITRE ATT&CK v14 techniques, paper in preparation (not yet submitted)
- **Professional background**: 6+ years in telecom/cybersecurity engineering (INICTEL-UNI, Deep Security consulting, DirecTV AT&T); Elastic Stack and EDR experience from Deep Security engagements
- **Thesis modality**: Trabajo de Suficiencia Profesional — FIEE-UNI (demonstrates existing professional work, not new research); carpeta forms (Formatos 1–5) already completed in `carpeta_llena.pdf`
- **Virtualization**: Proxmox VE preferred (type-1 hypervisor, native snapshot/restore via `virsh`); VirtualBox as fallback (`VBoxManage`)
- **Elastic tier**: Free/basic — Elastic Defend and Elastic ML anomaly detection are available without paid license

## Constraints

- **Platform**: Local hardware only — no cloud budget; Proxmox or VirtualBox
- **Elastic**: Free/basic tier only — no paid X-Pack features; Elastic Defend and ML basic jobs available
- **CALDERA**: Open-source CALDERA (MITRE) — no Prelude/paid CALDERA features
- **Tools**: Red Team tools limited to open-source/freely licensed: Metasploit, Nmap, Nessus (community), Burp Suite (community), Mimikatz, Cobalt Strike excluded
- **Thesis scope**: APT29 + OilRig + Wizard Spider only; 10 thesis sections per PROJECT.md structure
- **Dataset**: FullAPT-2025 framed as "en proceso de publicación" — dataset complete, paper not yet submitted

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use CTID adversary_emulation_library as APT recipe source | MITRE-backed, structured, maps directly to ATT&CK techniques, has CALDERA integration stubs | — Pending |
| Elastic ML anomaly detection instead of custom AI IDS | Free tier, legitimately ML, no training data required, already part of Elastic Stack | — Pending |
| Proxmox preferred over VirtualBox | Type-1 hypervisor, `virsh snapshot-restore` scriptable, better performance for 4+ VMs | — Pending |
| Scripted reset over manual snapshots | One command resets all VMs — enables repeatable exercises without hypervisor UI interaction | — Pending |
| GitHub Pages for setup guide + runbooks only | Thesis document is a formal UNI submission; GitHub Pages is the technical reference layer | — Pending |
| 3 APTs only (APT29, OilRig, Wizard Spider) | Thesis scope — deep coverage of 3 > shallow coverage of 11 | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-07 after initialization*
