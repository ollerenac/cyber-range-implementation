# Feature Research: Cyber Range — APT Emulation & Intrusion Detection

**Domain:** Virtualized Cyber Range / APT Emulation Lab
**Project:** Thesis — FIEE-UNI (Trabajo de Suficiencia Profesional)
**Researched:** 2026-06-07
**Overall confidence:** HIGH — domain well-established; CTID/MITRE emulation plans, Elastic Stack detection, and cyber range design patterns are mature fields with extensive public documentation and community practice.

---

## Table Stakes

Features that must be present or the lab is not credible to a thesis evaluator or a practitioner who clones it. Missing any of these makes the project look incomplete, not like a deliberate scope decision.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Network isolation | Without it, emulated attacks could reach real infrastructure; also required for repeatable, non-interfering runs | Low | Proxmox internal bridge / VirtualBox host-only + NAT; no route to host LAN |
| Realistic Windows target topology | APT29/OilRig/Wizard Spider all target AD environments; a flat Linux network does not demonstrate the right threat model | Medium | AD DC + at least one workstation; Exchange and SQL add realism but are optional for credibility floor |
| Attacker-side command and control | Must have a legitimate C2 framework, not ad-hoc scripts, for technique fidelity | Medium | CALDERA open-source satisfies this; Metasploit as secondary for non-CALDERA steps |
| MITRE ATT&CK technique traceability | Each emulated action must map to a specific ATT&CK technique ID | Low (design) | Critical for thesis — evaluator will check this; CTID plans already provide mapping |
| Host telemetry collection | Sysmon event logs are the minimum accepted standard for host visibility in red/blue exercises | Low | Sysmon with SwiftOnSecurity or olafhartong config; must be present on all targets |
| Network telemetry collection | Host-only visibility misses lateral movement, C2 beaconing, DNS exfiltration | Low | Packetbeat or equivalent; already in requirements |
| Centralized log aggregation | Scattered logs on individual VMs are not analyzable; a SIEM is expected for any detection claim | Medium | Elastic Stack already chosen; Elasticsearch + Kibana minimum |
| At least one detection rule that fires | The range must demonstrate detection, not just collection; at least one Elastic rule or ML job must produce an alert per APT scenario | Medium | Without this, the lab is a data collection exercise, not a cyber range |
| Scripted/repeatable scenario execution | Manual click-through exercises cannot be independently reproduced; reproducibility is a thesis credibility requirement | Medium | CALDERA adversary profiles + operation execution; this is the core of the project |
| Snapshot-based environment reset | Without reset, each run contaminates the next; demonstrates methodology rigor | Low–Medium | `virsh snapshot-restore` (Proxmox) or `VBoxManage snapshot restore`; one command means one script calling restore on all VMs |
| APT attribution and threat intelligence context | Each emulation must be grounded in real-world threat intelligence, not invented TTPs | Low (documentation) | CTID Intelligence_Summary for each APT group provides this; must be cited in thesis |
| Documentation sufficient to reproduce | A practitioner who reads the guide must be able to rebuild the lab from scratch | High (effort) | GitHub Pages setup guide; this is a stated deliverable |

---

## Differentiators

Features that elevate this lab above a basic "I ran Metasploit against a Windows VM" setup. These are what make the thesis contribution meaningful and what make the GitHub repo worth starring.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Three distinct APT groups with full emulation plans | Most academic labs emulate one group or use generic TTPs; three groups with distinct tooling, objectives, and tradecraft demonstrates depth | High | APT29 (covert, living-off-the-land), OilRig (persistent, custom tooling), Wizard Spider (financially motivated, ransomware chain) cover very different MITRE technique clusters |
| Dual telemetry (host + network) with explicit coverage analysis | Many labs use either host or network; dual coverage with explicit gap analysis (what Sysmon sees vs what Packetbeat sees) is a genuine contribution | Medium | Per-technique telemetry mapping — "technique T1055 produces ProcCreate event in Sysmon channel, no network artifact" |
| Elastic ML anomaly detection (behavioral, not signature) | Most academic ranges use only signature detection rules; behavioral anomaly detection represents the current SOTA defensive layer | Medium | Elastic ML basic jobs (network traffic anomaly, rare process, user behavior) are free-tier and demonstrate ML-based detection without custom model training |
| FullAPT-2025 dataset (117 ATT&CK techniques) | A publishable labeled dataset derived from the range is a research output beyond the thesis itself; cited as "en proceso de publicación" it elevates the work from class project to research contribution | High | Already partially constructed; the range is the generation mechanism |
| MITRE ATT&CK Navigator heatmap per APT | Visual technique coverage per adversary; makes the thesis figures compelling and shows evaluators exactly what was emulated vs what was detected | Low | Export from ATT&CK Navigator as SVG/PNG; annotate detected vs emulated |
| Detection metrics table (recall per technique) | Explicitly stating "we detected 34 of 39 emulated techniques = 87% recall" makes the thesis quantitatively rigorous | Medium | Requires mapping each CALDERA operation step to the alert(s) it should produce, then checking which fired |
| CALDERA adversary profiles as first-class artifacts | Checked-in `.yml` CALDERA adversary + operation files mean the emulation is reproducible by anyone with a CALDERA instance, not just people who follow manual steps | Low–Medium | CTID already provides CALDERA integration stubs; requires adaptation for Elastic telemetry |
| Per-APT MITRE technique extension (beyond CTID base plan) | CTID plans are good starting points but intentionally conservative; extending each plan with 5–10 additional techniques relevant to the APT's known operations demonstrates independent judgment | High | This is where professional background matters — know which techniques to add |
| One-command reset with state verification | Most labs document "restore snapshot" but don't verify clean state; a reset script that checks services are up, agents are enrolled, and baseline telemetry is flowing before marking ready is a meaningful quality bar | Medium | Post-reset health check: `elastic-agent status`, `sysmon` running, test event visible in Kibana |
| Runbooks structured as operator procedures (not just documentation) | An operator-oriented runbook (pre-flight checklist, step-by-step execution, expected output per step, what-to-do-if-wrong) is far more useful than narrative documentation | Medium | See Documentation section below |

---

## Anti-Features

Features to explicitly NOT build. These are either scope traps that consume time without advancing the thesis contribution, or they conflict with the stated constraints.

| Anti-Feature | Why Exclude | What to Do Instead |
|--------------|-------------|-------------------|
| Custom trained ML / supervised IDS model | Requires a labeled training/test split methodology, model evaluation, hyperparameter tuning — a separate thesis topic; also excluded by PROJECT.md | Use Elastic ML free-tier unsupervised anomaly detection; frame as "behavioral detection layer" |
| Cloud deployment (AWS/Azure/GCP) | No cloud budget; adds networking complexity (VPC, security groups, egress costs); cloud lab ≠ enterprise on-prem threat model for these APT groups | Document hardware requirements clearly; Proxmox runs on a single physical host |
| Cobalt Strike or paid red team tools | Licensed commercial tool; cannot be open-source referenced or redistributed; thesis reproducibility requires free tools | CALDERA + Metasploit + open-source TTPs cover the technique space |
| Blue team scoring / CTF gamification | Scoring engines (iCTF, ISTS, RangeForce-style) add platform complexity that's orthogonal to the thesis question (detection coverage) | Focus on detection metrics (recall, technique coverage), not competitive scoring |
| Student/multi-user access control | Multi-tenant ranges (Cyber Skyline, EDURange) need auth, isolation per student, account management — not needed for a single-operator thesis lab | Single operator; document who the intended user is (thesis evaluator + future practitioners) |
| Network traffic generation / background noise | Some ranges add legitimate user simulation (GHOSTS, realistic background traffic) to reduce false positive analysis; this is a legitimate differentiator but very high effort | Acknowledge as a limitation in the thesis; it's a known gap in controlled-lab research |
| Vulnerability scanning as a range feature | Nessus/OpenVAS scans are a red team recon step, not a range infrastructure feature; building a "vuln management" layer is scope creep | Include Nmap/Nessus recon steps inside APT emulation plans where the APT actually does recon |
| IDS/IPS inline blocking | An IPS that blocks attacks during emulation defeats the purpose of running the emulation to completion | Keep Elastic in detection-only mode; alerts, not blocks |
| Custom SIEM / log management platform | Building a log pipeline from scratch when Elastic Stack is already chosen wastes time | Use Elastic Stack as-is; beat configurations are the only custom layer |
| APT groups beyond the three defined | OceanLotus, Lazarus, FIN7, etc. are in the CTID library but expanding dilutes depth | Three APTs with complete emulation plans > six with partial plans |
| Automated remediation / SOAR | SOAR playbooks are a production SOC feature; out of scope for a detection-research lab | Document remediation steps in runbooks as operator procedures, not automated responses |
| Physical hardware targets | Some ranges use physical switches/routers; all-VM is the right choice for reproducibility and thesis defense | Full virtualization; document VM specs |

---

## Detection Coverage — What It Means in This Context

This section defines the measurement model so the thesis and metrics table are internally consistent.

### Recall (Detection Recall per Technique)

The primary metric. For each emulated ATT&CK technique:

- **True Positive (TP):** An alert or anomaly fired that is attributable to the technique execution
- **False Negative (FN):** The technique executed, telemetry was collected, but no alert fired
- **False Positive (FP):** Alert fired when technique was NOT executing (relevant for noise analysis, not for recall)

**Recall = TP / (TP + FN)** computed per technique, then aggregated.

A thesis result of "87 of 117 techniques produced at least one alert = 74% recall" is a complete, honest, defensible finding. Do not claim higher recall by counting "telemetry present" as detection — an alert must fire.

### MITRE Technique Coverage

Two distinct measurements that are often conflated:

| Metric | Definition | How to Compute |
|--------|------------|----------------|
| Emulation coverage | What fraction of the ATT&CK matrix was exercised | Emulated techniques / total ATT&CK v14 techniques (this will be small — that's expected) |
| Detection recall | Of what was emulated, what fraction was detected | Detected techniques / emulated techniques (this should be the thesis's main claim) |

Report both. Conflating them (claiming "covered 117 techniques" when you mean "emulated 117, detected 87") is a methodological error evaluators will catch.

### Detection Rule Taxonomy for This Lab

| Layer | Technology | What It Catches |
|-------|------------|-----------------|
| Signature / EQL rules | Elastic detection rules (free tier) | Known bad patterns: specific process names, command-line strings, registry keys, network IOCs |
| Threshold / frequency rules | Elastic threshold queries | Brute force, port scanning, excessive failed logins |
| Behavioral / ML anomaly | Elastic ML jobs | Rare processes, unusual network connections, abnormal user behavior baselines |

A technique is "detected" if any layer fires. Report which layer detected it — this lets the thesis compare signature vs behavioral detection rates, which is a substantive finding.

### Precision (secondary metric)

Precision = TP / (TP + FP). Important but secondary for a controlled lab with no background traffic. In a zero-background-noise lab, nearly all alerts will be TPs (attacker activity is all that's happening). Acknowledge this as a lab limitation: real-world precision will be lower due to legitimate activity generating false positives. This is the appropriate honest framing.

---

## APT Emulation Runbook Standard

What a complete, high-quality runbook contains. Based on CTID adversary emulation plan structure, MITRE ATT&CK evaluation methodology, and practitioner conventions from open-source purple team resources.

### Runbook Sections

**1. Threat Intelligence Summary (1–2 pages)**
- APT group overview: nation-state attribution, primary targets, active since
- Objectives: espionage / financial / destructive
- Known tooling: custom malware families, LOTL techniques, preferred protocols
- Key public references: Mandiant/CrowdStrike/Recorded Future reports that ground the emulation
- MITRE ATT&CK group page citation (e.g., `attack.mitre.org/groups/G0016` for APT29)

**2. Emulation Scope**
- Techniques emulated: table of ATT&CK IDs + technique names + sub-technique IDs
- Techniques explicitly excluded from base plan and why (e.g., "T1566.001 Spearphishing not emulated — requires email infrastructure not in scope")
- Extensions added beyond CTID base plan: which techniques, why they represent this APT

**3. Environment Prerequisites**
- Required VMs and their roles
- Required agents running (Elastic Agent, Sysmon version, Packetbeat)
- Required CALDERA configuration (server URL, API key, agent beacon interval)
- Pre-flight checklist (numbered, checkable): confirm AD is up, confirm agents enrolled, confirm CALDERA has required abilities, confirm snapshot taken

**4. Scenario Narrative**
- High-level story of the attack (what would this look like in a real intrusion?)
- Phases: initial access → execution → persistence → privilege escalation → lateral movement → collection → exfiltration
- Each phase maps to the step table in section 5

**5. Step-by-Step Execution Table**

The core of the runbook. Per step:

| Field | Content |
|-------|---------|
| Step number | Sequential; references scenario narrative phase |
| ATT&CK technique | T-ID + name + sub-technique |
| Description | What this step does in plain English |
| Execution method | CALDERA ability name + operation, OR manual command |
| Target VM | Which machine executes and which is targeted |
| Expected output | What success looks like (process created, file written, network connection) |
| Expected telemetry | Sysmon event ID(s) and/or Packetbeat fields that should appear |
| Expected detection | Which Elastic rule or ML job should fire; rule name or job ID |
| Failure handling | What to check if step does not produce expected output |

**6. Expected Telemetry Reference**

A separate mapping table (not the step table — this is the raw data layer):

- Per technique: list of Sysmon event IDs, Windows Event Log IDs, Packetbeat fields, Elastic field names that are populated
- This is what differentiates this runbook from a generic one — it tells the operator what to look for in Kibana, not just what tool to run

**7. Detection Validation**

After running the scenario:
- Checklist of alerts that should have fired (one row per detection rule expected to trigger)
- For each: alert name, rule type (EQL / threshold / ML), Kibana query to verify, TP / FN result
- Running total: X of Y expected alerts fired = Z% recall for this APT scenario

**8. Reset Procedure**
- Pre-reset checklist (export any logs you need first)
- Reset command(s) with expected output
- Post-reset verification: services up, agents enrolled, baseline telemetry flowing
- Estimated reset time

**9. Known Limitations**
- What this emulation does NOT cover from the real APT's playbook
- Where simulation fidelity diverges from real malware (e.g., "CALDERA uses PowerShell stubs, not compiled malware — process artifacts differ")
- Lab conditions that artificially inflate detection rate (no background noise)

### Runbook Quality Indicators

A high-quality runbook passes these checks:

- A practitioner who has never seen the lab can complete the scenario from section 3 onward without asking questions
- Every step has an expected output — there is no step that says "run this and move on"
- Every expected detection is verifiable with a specific Kibana query or dashboard
- The reset procedure is tested and timed (not "approximately 10 minutes")
- Limitations are honest, not defensive

---

## GitHub Pages / Documentation Features

What makes a cyber range setup guide actually useful vs a wall of markdown.

### Must-Have Structure

**Landing page (index)**
- What this lab is and what it demonstrates (3 sentences max)
- Prerequisites (hardware, OS, time estimate)
- Quick-start path (link to Part 1 immediately)
- Link to thesis document (PDF) for academic context

**Part 1: Infrastructure Setup**
- Proxmox/VirtualBox installation with exact version numbers
- VM provisioning: OS, RAM, CPU, disk per VM (table format)
- Network configuration: internal bridge name, IP allocation table, no internet for target VMs
- Each step has a verification command — the reader never has to guess if it worked

**Part 2: Elastic Stack Deployment**
- Fleet Server setup
- Elastic Agent enrollment on each target VM
- Sysmon deployment (which config file, how to verify events in Kibana)
- Packetbeat deployment and index template
- Smoke test: "run this query and you should see X"

**Part 3: CALDERA Setup**
- Install CALDERA (specific version pinned)
- Load APT adversary profiles
- Verify agents connected
- Run a test ability (something benign) to confirm C2 connectivity

**Part 4–6: APT Runbooks** (one page per APT)
- Link to the full PDF runbook or inline the operator procedure
- Screenshots of expected Kibana dashboards after scenario run

**Appendix: Reset & Maintenance**
- Reset script with annotated inline comments (not just the script — explain each line)
- Troubleshooting: 10–15 common failure modes with exact error messages and fixes
- Version matrix (tested on: Proxmox X.Y, Elastic Z.A, CALDERA B.C)

### Differentiating Documentation Features

| Feature | Why It Matters |
|---------|---------------|
| Exact version numbers pinned throughout | "Install Elastic" fails in 6 months; pinned versions with upgrade notes do not |
| Screenshots of Kibana dashboards | Practitioners need to know what "success" looks like visually |
| Copy-pasteable commands (no line wrapping) | Line-wrapped bash in PDF is the most common reason setup guides fail |
| Time estimates per section | Helps practitioners plan a session; a realistic "Part 2 takes 90 minutes" is more useful than no estimate |
| Troubleshooting section with real error messages | Captures issues found during lab construction; invaluable for reproducibility |
| Network diagram (simple ASCII or draw.io export) | One diagram explaining VM topology is worth 500 words |
| "What you'll see in Kibana" screenshots per APT | Confirms the detection layer is working as described |
| GitHub Releases for VM base images or snapshots | Optional but high value: downloadable OVA/OVF skips Part 1 entirely for quick evaluation |

### Anti-patterns in Cyber Range Documentation

- "Configure X appropriately" — never appropriate; always specify the exact value
- Version-free installation instructions — always pin versions
- Prerequisites listed at the bottom — move them to the top
- Skipping the verification step — every config section needs a "run this to confirm it worked"
- Single giant README — break into navigation-friendly sections; GitHub Pages lets you use a sidebar
- No troubleshooting section — the lab will fail in unexpected ways; document the ones found during construction

---

## Feature Dependencies

The following hard dependencies exist in build order:

```
Network isolation → all other VMs (cannot install anything without a working network topology)
AD DC → Exchange, SQL Server, workstation join
Sysmon on targets → host telemetry → Elastic Agent enrollment (Sysmon feeds Elastic)
Fleet Server → Elastic Agent enrollment → Elastic Defend → EDR telemetry
Elastic Agent enrollment → Packetbeat → network telemetry
CALDERA server → CALDERA agents on targets → APT emulation execution
Emulation execution → telemetry corpus → detection rule validation
Detection rule validation → recall metrics → thesis quantitative findings
Thesis findings → GitHub Pages runbooks (runbooks cite real results)
```

Any phase that skips a node in this chain produces a partial lab that cannot be fully demonstrated.

---

## MVP Feature Floor

The minimum set that produces a credible, defensible thesis. Everything below this is a scope cut that requires explicit justification.

1. Isolated network with AD DC + one workstation VM
2. Sysmon + Elastic Agent on all targets (host telemetry)
3. Elastic Stack (Elasticsearch + Kibana + Fleet Server) receiving events
4. CALDERA with at least one APT adversary profile loaded
5. At least one complete emulation scenario run to completion
6. At least one Elastic detection rule or ML job firing on that scenario
7. Snapshot reset script (even if slow or manual)
8. Setup guide sufficient for an evaluator to re-run the scenario

Everything above the MVP floor is a differentiator. The project as scoped in PROJECT.md significantly exceeds this floor, which is the right choice for a thesis that also contributes the FullAPT-2025 dataset.

---

## Sources

**Confidence note:** All findings are HIGH confidence based on:
- CTID/MITRE adversary emulation library (github.com/center-for-threat-informed-defense/adversary_emulation_library) — structure of emulation plans is publicly documented and well-established
- MITRE ATT&CK Evaluations methodology (attackevals.mitre-engenuity.org) — defines TP/FN/detection categories used by the field
- Elastic detection documentation (elastic.co/guide/en/security) — EQL rules, ML jobs, Fleet/Elastic Agent architecture
- Community standards from open-source purple teaming (Atomic Red Team, VECTR, Caldera docs, DetectionLab) which define the accepted runbook and lab structure conventions
- Academic cyber range literature (NIST SP 800-100 series, ENISA cyber range guidance) for table stakes/differentiator framing

External tool access was denied during research. All findings are from training knowledge (cutoff August 2025). No LOW-confidence claims are presented — the domain is sufficiently stable that training data is reliable here. Areas that would benefit from live verification: exact Elastic ML job names available at free tier, current CALDERA version and ability format, CTID plan update status for the three target APT groups.
