# Roadmap: Cyber Range — APT Emulation & Intrusion Detection

**Project:** Cyber Range / APT Emulation Thesis (TSP — FIEE-UNI)
**Granularity:** Standard (7 phases)
**Coverage:** 27/27 v1 requirements mapped
**Mode:** mvp — each phase delivers an end-to-end demonstrable capability

---

## Phases

- [ ] **Phase 1: Proxmox Foundation + SIEM Node** — Hypervisor networking live and elastic-vm fully operational (Elasticsearch, Kibana, Fleet Server)
- [ ] **Phase 2: Windows Target Network** — DC, Exchange, SQL, and workstation VMs deployed, domain joined, and reachable
- [ ] **Phase 3: Full Telemetry Pipeline + Reset Mechanism** — Kali deployed, all agents Healthy in Fleet, dual telemetry flowing, one-command reset validated
- [ ] **Phase 4: Red Team Platform + ML Baseline** — CALDERA operational with a test operation, Elastic ML jobs accumulating 48h of baseline data
- [ ] **Phase 5: APT Emulation Content** — Three CALDERA adversary packages (APT29, OilRig, Wizard Spider) authored, tested, and ready to run
- [ ] **Phase 6: Emulation Runs + Detection Results** — All three APT scenarios executed, detection rules tuned, results table populated, dataset finalized
- [ ] **Phase 7: Thesis + GitHub Pages** — Thesis document complete, GitHub Pages site live with setup guide and APT runbooks

---

## Phase Details

### Phase 1: Proxmox Foundation + SIEM Node
**Goal:** The hypervisor networking fabric and the persistent SIEM node are live — Fleet Server is issuing enrollment tokens, Kibana is reachable, and the network isolation gates pass.
**Mode:** mvp
**Depends on:** Nothing (first phase)
**Requirements:** INFRA-01, INFRA-02
**Success Criteria** (what must be TRUE):
  1. Operator can SSH into each Proxmox host and confirm vmbr0 (MGMT 10.0.0.0/24) and vmbr1 (TARGET 10.10.10.0/24) bridges exist with no physical uplink on vmbr1
  2. Operator opens https://10.0.0.10:5601 and logs into Kibana — Elasticsearch cluster health is green
  3. Operator opens Fleet UI and sees an active Fleet Server with a valid enrollment token ready to copy
  4. A test VM on vmbr1 cannot ping 8.8.8.8 or any host LAN address — network isolation confirmed
**Plans:** 4 plans (4 waves)
Plans:
- [ ] 01-01-PLAN.md — Proxmox networking foundation: vmbr0/vmbr1 bridges on all 6 hosts, VLAN 10 switch config, LVM-thin + isolation gates
- [ ] 01-02-PLAN.md — Create elastic-vm (Host 1) + caldera-vm (Host 6) with locked specs and Ubuntu 22.04 base
- [ ] 01-03-PLAN.md — SIEM stack on elastic-vm: Elasticsearch/Kibana/Fleet 8.19.16, lab CA + Fleet cert (SAN IP:10.0.0.10), 30-day ILM
- [ ] 01-04-PLAN.md — CALDERA 5.3.0 on caldera-vm, snapshot workflow + reset_range.sh scaffold, all 4 Phase 1 gates

---

### Phase 2: Windows Target Network
**Goal:** All four Windows target VMs (dc01, exchange01, sql01, ws01) are provisioned, joined to lab.local, and mutually reachable — the domain topology the three APT scenarios require exists.
**Mode:** mvp
**Depends on:** Phase 1
**Requirements:** INFRA-03, INFRA-04, INFRA-05, INFRA-06
**Success Criteria** (what must be TRUE):
  1. Operator RDPs to dc01 and confirms Active Directory Users and Computers shows the lab.local domain with exchange01, sql01, and ws01 as joined computer objects
  2. Operator logs into exchange01 with a domain account and confirms Exchange Admin Center opens — mail flow test succeeds
  3. Operator connects to sql01 via SSMS and runs a query against a sample database — SQL Server responds under domain authentication
  4. Operator logs into ws01 as a domain user and confirms network browsing reaches all three servers
**Plans:** TBD

---

### Phase 3: Full Telemetry Pipeline + Reset Mechanism
**Goal:** Every target VM (including Kali) has dual telemetry flowing to Elasticsearch, Elastic Agents are Healthy in Fleet, clean-state snapshots are captured, and a single command resets the entire lab to that clean state.
**Mode:** mvp
**Depends on:** Phase 2
**Requirements:** INFRA-07, TELEM-01, TELEM-02, TELEM-03, TELEM-04, RESET-01, RESET-02, RESET-03
**Success Criteria** (what must be TRUE):
  1. Operator opens Fleet UI and sees dc01, exchange01, sql01, and ws01 all showing status "Healthy" — Elastic Defend policy applied in DETECT (not PREVENT) mode, verifiable in Fleet policy view
  2. Operator runs `cmd.exe` on dc01, waits 10 seconds, queries Kibana Discover for `process.name: "cmd.exe"` — at least one Sysmon EventID 1 event appears with ECS field `process.name` populated (not `winlog.event_data.*`)
  3. Operator queries `packetbeat-*` index for DNS traffic from the target subnet — records appear confirming Packetbeat network telemetry is flowing on all Windows VMs
  4. Operator runs `./reset_range.sh` from the control node — within 5 minutes all four VMs are back online, Fleet shows them Healthy, and AD domain authentication succeeds without manual intervention
  5. Kali can reach the TARGET subnet and confirm CALDERA agent binary deploys and phones home to elastic-vm:8853 on a test run
**Plans:** TBD
**UI hint**: yes

---

### Phase 4: Red Team Platform + ML Baseline
**Goal:** CALDERA is operational and a test adversary operation has run end-to-end; Elastic ML anomaly jobs are started and accumulating the minimum 48-hour baseline needed before any APT emulation run.
**Mode:** mvp
**Depends on:** Phase 3
**Requirements:** RED-01, DETECT-01
**Success Criteria** (what must be TRUE):
  1. Operator opens CALDERA UI at elastic-vm:8888, creates a test operation using a built-in ability (e.g., whoami), and sees the operation complete with at least one result logged — CALDERA agent on a target VM executed the command
  2. Operator opens Kibana ML Jobs UI and confirms at least two anomaly detection jobs (e.g., `rare_process_by_host`, `network_traffic_rare_destination`) are in "started" state and have ingested data
  3. Operator confirms in Kibana that ML job datafeed has been running for at least 48 hours with no gaps — anomaly explorer shows a populated timeline before the first emulation run is permitted
**Plans:** TBD

---

### Phase 5: APT Emulation Content
**Goal:** Three complete CALDERA adversary packages exist in the repository — one per APT group — each derived from the CTID emulation plan, extended with additional ATT&CK techniques, and validated to execute correctly against the lab environment.
**Mode:** mvp
**Depends on:** Phase 4
**Requirements:** RED-02, RED-03, RED-04
**Success Criteria** (what must be TRUE):
  1. Operator loads the APT29 adversary in CALDERA and runs a dry-run operation against dc01 — all abilities execute without silent failure; CALDERA operation log shows technique IDs mapped to each completed step
  2. Operator loads the OilRig adversary and confirms abilities covering SideTwist C2, TwoFace webshell (Exchange), VALUEVAULT credential harvesting, and RDAT exfiltration are present and execute on the appropriate targets
  3. Operator loads the Wizard Spider adversary and confirms the Emotet-to-TrickBot-to-Ryuk kill chain abilities are present; a dry-run reaches the lateral movement stage without error
  4. Each adversary YAML file is committed to the repository — any operator with a CALDERA instance can import and run the package without additional configuration
**Plans:** TBD

---

### Phase 6: Emulation Runs + Detection Results
**Goal:** All three APT scenarios have been executed (minimum 3 runs each), detection rules are tuned and active, the three-column results table is populated for each scenario, and the FullAPT-2025 dataset is finalized and documented.
**Mode:** mvp
**Depends on:** Phase 5
**Requirements:** DETECT-02, DETECT-03, DATA-01, DATA-02
**Success Criteria** (what must be TRUE):
  1. Operator runs APT29 scenario and opens Kibana Detection Rules — at least 5 rules specific to APT29 primary techniques fire within the operation window; each alert links to the correct MITRE ATT&CK technique ID
  2. Operator opens the results table for any of the three APT scenarios and sees a populated three-column layout (Technique ID | Emulated | Detected | Detection Method) with detection gaps explicitly marked as false negatives — not omitted
  3. Operator queries `apt29-run1-*` (or equivalent per-run index) in Elasticsearch and retrieves raw telemetry events — index exists, contains records, and metadata fields (run ID, APT group, timestamp) are populated
  4. FullAPT-2025 dataset covers >= 117 MITRE ATT&CK v14 techniques across the three scenarios, with a README documenting schema, collection method, and how to reproduce
  5. Operator runs `./reset_range.sh` between scenario runs and confirms no telemetry bleed between run indices
**Plans:** TBD

---

### Phase 7: Thesis + GitHub Pages
**Goal:** The thesis document is complete and ready for FIEE-UNI submission, and the GitHub Pages site is live with a setup guide and three APT runbooks that allow independent reproduction of the cyber range.
**Mode:** mvp
**Depends on:** Phase 6
**Requirements:** THESIS-01, THESIS-02, DOCS-01, DOCS-02
**Success Criteria** (what must be TRUE):
  1. Operator opens the thesis PDF and confirms all 10 sections are present (Introducción through Bibliografía), each APT scenario has a methodology subsection with Elasticsearch telemetry evidence and its detection results table
  2. Operator navigates to the GitHub Pages URL and follows the setup guide from scratch — every command in the guide is copy-pasteable and the sequence matches the actual build order (Proxmox through CALDERA)
  3. Operator opens any of the three APT runbooks and can identify: the pre-emulation checklist (Elastic Defend = DETECT verified), step-by-step CALDERA operation procedure, expected telemetry artifacts, and the ATT&CK technique mapping
  4. Thesis Key Decisions table is populated with final outcomes for all decisions (Proxmox choice, Elastic ML tier, WS2019 OS choice, scripted reset) — all marked resolved, not pending
**Plans:** TBD

---

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Proxmox Foundation + SIEM Node | 0/4 | Planned | - |
| 2. Windows Target Network | 0/? | Not started | - |
| 3. Full Telemetry Pipeline + Reset Mechanism | 0/? | Not started | - |
| 4. Red Team Platform + ML Baseline | 0/? | Not started | - |
| 5. APT Emulation Content | 0/? | Not started | - |
| 6. Emulation Runs + Detection Results | 0/? | Not started | - |
| 7. Thesis + GitHub Pages | 0/? | Not started | - |

---

## Coverage

| Requirement | Phase | Notes |
|-------------|-------|-------|
| INFRA-01 | 1 | Proxmox + bridges |
| INFRA-02 | 1 | elastic-vm (Elasticsearch + Kibana + Fleet) |
| INFRA-03 | 2 | dc01 (AD DC) |
| INFRA-04 | 2 | exchange01 |
| INFRA-05 | 2 | sql01 |
| INFRA-06 | 2 | ws01 workstation |
| INFRA-07 | 3 | kali attacker platform |
| TELEM-01 | 3 | Elastic Agent enrollment via MGMT NIC |
| TELEM-02 | 3 | Elastic Defend DETECT mode verified |
| TELEM-03 | 3 | Sysmon + sysmon-modular on all Windows VMs |
| TELEM-04 | 3 | Packetbeat network telemetry |
| RESET-01 | 3 | clean_state snapshot after all agents Healthy |
| RESET-02 | 3 | reset_range.sh parallel qm rollback script |
| RESET-03 | 3 | < 5 minute reset, no manual intervention |
| RED-01 | 4 | CALDERA 5.x + test operation |
| DETECT-01 | 4 | Elastic ML jobs + 48h baseline |
| RED-02 | 5 | APT29 CALDERA adversary package |
| RED-03 | 5 | OilRig CALDERA adversary package |
| RED-04 | 5 | Wizard Spider CALDERA adversary package |
| DETECT-02 | 6 | Detection rules >= 5 per APT group |
| DETECT-03 | 6 | Three-column results table per scenario |
| DATA-01 | 6 | FullAPT-2025 corpus >= 117 techniques |
| DATA-02 | 6 | Dataset structured + reproducibility metadata |
| THESIS-01 | 7 | 10 thesis chapters |
| THESIS-02 | 7 | Per-scenario APT documentation + evidence |
| DOCS-01 | 7 | GitHub Pages setup guide |
| DOCS-02 | 7 | APT runbooks (APT29, OilRig, Wizard Spider) |

**v1 requirements: 27 total — 27 mapped — 0 orphaned**

---

## Hard Dependency Chain (Non-Negotiable Order)

```
Proxmox bridges (Phase 1)
  └─ elastic-vm + Fleet Server (Phase 1)
       └─ dc01 joined to lab.local (Phase 2)
            └─ exchange01 + sql01 + ws01 domain join (Phase 2)
                 └─ Elastic Agents enrolled + Healthy (Phase 3)
                      └─ clean_state snapshot taken (Phase 3)
                           └─ reset_range.sh validated (Phase 3)
                                └─ CALDERA test op + ML jobs started (Phase 4)
                                     └─ 48h ML baseline elapsed (Phase 4)
                                          └─ APT content authored + tested (Phase 5)
                                               └─ Emulation runs + detection results (Phase 6)
                                                    └─ Thesis + GitHub Pages (Phase 7)
```

**Critical constraints:**
- elastic-vm is NEVER snapshotted and NEVER included in reset_range.sh
- Elastic Defend MUST be in DETECT mode before every emulation run — verified in Fleet UI
- Snapshots taken simultaneously across all VMs after all agents show Healthy
- Three-column results table (Technique ID | Emulated | Detected | Detection Method) designed before Phase 6 begins, not assembled retroactively

---
*Roadmap created: 2026-06-08*
