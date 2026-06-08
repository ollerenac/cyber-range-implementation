<!-- GSD:project-start source:PROJECT.md -->
## Project

**Cyber Range — APT Emulation & Intrusion Detection**

A fully virtualized Cyber Range that emulates three real-world APT groups (APT29, OilRig, Wizard Spider) using CTID adversary emulation plans packaged for CALDERA, and detects those attacks via Elastic Stack (SIEM + Elastic Defend EDR + Elastic ML anomaly detection). Dual telemetry is collected via Sysmon (host) and Packetbeat (network). The project also produces a thesis document (Trabajo de Suficiencia Profesional — FIEE-UNI) and publishes a setup guide plus APT runbooks on GitHub Pages.

**Core Value:** A working lab where an operator can run a scripted APT scenario, observe real attack telemetry, and detect the intrusion — then reset everything to a clean state in one command and do it again.

### Constraints

- **Platform**: Local hardware only — no cloud budget; Proxmox or VirtualBox
- **Elastic**: Free/basic tier only — no paid X-Pack features; Elastic Defend and ML basic jobs available
- **CALDERA**: Open-source CALDERA (MITRE) — no Prelude/paid CALDERA features
- **Tools**: Red Team tools limited to open-source/freely licensed: Metasploit, Nmap, Nessus (community), Burp Suite (community), Mimikatz, Cobalt Strike excluded
- **Thesis scope**: APT29 + OilRig + Wizard Spider only; 10 thesis sections per PROJECT.md structure
- **Dataset**: FullAPT-2025 framed as "en proceso de publicación" — dataset complete, paper not yet submitted
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Recommended Stack
### Red Team Layer
| Tool | Version | Role | Why |
|------|---------|------|-----|
| MITRE CALDERA | 5.x (latest stable) [VERIFY] | C2 framework / adversary automation engine | Open-source, MITRE-maintained, native ATT&CK mapping, stockpile plugin supports CTID micro-emulation plan payloads directly. The CTID adversary_emulation_library caldera-integration README already documents the exact payload→ability→adversary→operation pipeline needed here. |
| Metasploit Framework | 6.x (ships with Kali) | Exploitation, lateral movement, post-exploitation modules | Free/open-source (Rapid7). Fills the gap between CALDERA ability execution and realistic exploit chains. APT29 Scenario 1 (smash-and-grab) and Wizard Spider (Emotet→TrickBot→Ryuk chain) both require realistic initial-access vectors that CALDERA alone does not provide. Use `msfconsole` or REST API; wire findings back to CALDERA via manual step annotation. |
| Mimikatz | Latest release (GitHub: gentilkiwi/mimikatz) | Credential harvesting | Used directly by the CTID OilRig emulation plan (VALUEVAULT is a Golang reimplementation; original Mimikatz is listed as a payload in the OilRig Resources). Mandatory for T1003 (OS Credential Dumping) coverage. |
| Impacket | Latest PyPI release | SMB/DCOM/WMI lateral movement, Pass-the-Hash, DCSync | Pure-Python; ships with Kali. Covers ATT&CK T1550.002 (Pass-the-Hash), T1021.002 (SMB/Windows Admin Shares), T1047 (WMI). Bridges the gap between credential theft and lateral movement in all three APT scenarios. |
| PsExec (Sysinternals) | Latest | Remote execution on Windows | Listed explicitly as a payload in CTID OilRig emulation plan. Free, no license required for lab use. |
| Plink (PuTTY) | Latest | SSH tunneling / port forwarding | Listed explicitly as a payload in CTID OilRig emulation plan. Covers T1572 (Protocol Tunneling). |
| Nmap | 7.9x (ships with Kali) | Network discovery / port scanning | Table-stakes for initial recon phase. T1046 (Network Service Discovery). Free, open-source. |
| Nessus Essentials | Free tier (up to 16 IPs) | Vulnerability scanning | Free for lab use. Adds realism to the pre-exploitation recon phase. If Nessus license friction is a problem, use OpenVAS (Greenbone Community Edition) instead. |
| BloodHound CE | 6.x (Community Edition) | AD attack path visualization | Free, open-source (BloodHound Community Edition). Dramatically improves AD enumeration realism for APT29 Scenario 2 (domain compromise) and Wizard Spider post-Emotet lateral movement. Replaces SharpHound collector; use AzureHound or SharpHound for data collection. |
| Tool | Why Not |
|------|---------|
| Cobalt Strike | Commercial license (~$5,000/seat/year). Explicitly excluded in PROJECT.md constraints. Use CALDERA + Metasploit to cover the same TTPs. |
| Brute Ratel C4 | Commercial, actively flagged by AV/EDR — detection noise would corrupt telemetry. |
| Empire (BC-Security) | Largely superseded by CALDERA for structured emulation. Adds complexity without coverage gain for this scope. Not wrong, just unnecessary given CALDERA handles the C2 orchestration role. |
| Sliver C2 | Good alternative to Cobalt Strike but redundant with CALDERA already chosen. Would split the C2 story without benefit. |
### Blue Team Layer (SIEM / EDR)
| Component | Version | Role | Why |
|-----------|---------|------|-----|
| Elasticsearch | 8.17.x [VERIFY — latest 8.x patch] | Search/analytics engine, event store | Core of the SIEM. Free/basic tier covers all needed features. 8.x introduced native TSDB support and improved ML anomaly detection APIs. Do NOT use 7.x — EOL and missing Fleet Server architecture. |
| Kibana | 8.17.x (match Elasticsearch) | Visualization, Detection Rules UI, ML jobs, Fleet UI | Must be exact same version as Elasticsearch. Fleet UI, Security Solution, and ML anomaly detection jobs all run here. |
| Fleet Server | 8.17.x (match Elasticsearch) | Central agent policy management | Manages Elastic Agent deployments and policy pushes across all VMs. Eliminates per-VM Logstash configuration. Run Fleet Server as a standalone process on the SIEM VM or on a dedicated lightweight VM. |
| Elastic Agent | 8.17.x (match Elasticsearch) | Unified telemetry collector on each target VM | Replaces Beats on managed hosts. Wraps Elastic Defend (EDR), System integration, and Windows Event Log integration in one binary. Deploy via Fleet Server for centralized policy management. |
| Elastic Defend | Bundled with Elastic Agent 8.17.x | EDR — process telemetry, file events, network events, memory protection | Free/basic tier. Provides ECS-mapped process trees, file write events, and network connection events on Windows. Enable in "Detect" mode (not "Prevent") during emulation runs to avoid killing your own red team tooling. Switch to "Prevent" for detection validation tests. |
| Elastic ML | Bundled with Elasticsearch 8.17.x (basic tier) | Unsupervised anomaly detection | Basic license includes `single_metric`, `multi_metric`, and `population` anomaly detection job types. Suitable for behavioral baselining (unusual process trees, rare parent-child relationships, data volume anomalies). Does NOT require labeled training data — fits the thesis constraint perfectly. |
- **Index lifecycle management (ILM):** Configure hot→warm→delete with a 30-day retention on `logs-*` and `metrics-*` indices. Lab disk is finite.
- **Detection Rules:** Import Elastic prebuilt rules from the Security Solution. The MITRE ATT&CK coverage matrix in Kibana shows which techniques have prebuilt rules — use this to identify gaps for the thesis.
- **Fleet Server placement:** Run on the same host as Elasticsearch for this lab scale. Separate VM only if performance degrades.
- **Elastic Defend policy:** Set to "Detect" mode during red team runs. "Prevent" mode will terminate implants before telemetry is generated — defeating the purpose.
### Infrastructure Layer
| Component | Version | Role | Why |
|-----------|---------|------|-----|
| Proxmox VE | 8.x (latest stable — 8.3.x as of mid-2025) [VERIFY] | Type-1 hypervisor | Runs directly on bare metal (KVM+QEMU). Native `virsh snapshot-create/restore` supports the one-command reset requirement. Web UI for initial setup; CLI for automation. Superior performance vs VirtualBox for running 4-6 concurrent VMs. |
| Windows Server 2019 | Standard or Datacenter evaluation (180-day free from Microsoft) | AD DC + Exchange | Prefer 2019 over 2022 for this lab. Exchange Server 2019 CU14+ is the last supported on Windows Server 2019. The CTID OilRig plan targets EWS (Exchange Web Services) — Exchange 2019 is the correct target. Windows Server 2022 adds stricter SMB signing defaults and Credential Guard hardening that would interfere with credential-theft TTPs (Mimikatz, Pass-the-Hash) — intentional friction you do not want in an emulation lab. |
| Windows Server 2019 | Second instance | SQL Server host | SQL Server 2019 Developer Edition (free) runs on WS2019. Matches the CTID OilRig scenario (SQL server storing "critical infrastructure data"). |
| Windows 10/11 | Enterprise Evaluation (90-day free) | Workstation — initial access target | OilRig Scenario: initial access onto "an administrator's workstation." APT29 Scenario 1: rapid espionage. Need a domain-joined workstation VM, not a server. Windows 10 LTSC 2019 evaluation is stable and freely available. |
| Kali Linux | 2024.4 or latest rolling [VERIFY] | Attacker platform | Official Debian-based, ships Metasploit, Nmap, Impacket, BloodHound, and hundreds of other tools pre-installed. Use the VM image from kali.org — do not build from scratch. |
| Ubuntu Server | 22.04 LTS | SIEM host (Elasticsearch + Kibana + Fleet Server) | 22.04 LTS supported through 2027. Elasticsearch 8.x officially supports it. Use the minimal server image — no desktop environment needed. Allocate at minimum 16 GB RAM, 4 vCPU, 500 GB disk to the SIEM VM. |
# Take baseline snapshot of all VMs after initial setup
# Reset all VMs to baseline (one-command reset)
### Telemetry Layer
| Component | Version | Role | Why |
|-----------|---------|------|-----|
| Sysmon | 15.x (Sysinternals — latest stable) [VERIFY] | Host-level process/network/registry/file telemetry | De facto standard for Windows endpoint telemetry in security labs. Generates Event ID 1 (process create), 3 (network connect), 7 (image load), 10 (process access), 11 (file create), 13 (registry set), 22 (DNS query). Feed into Elastic Agent via Windows Event Log integration. |
| Sysmon Config | SwiftOnSecurity/sysmon-config OR olafhartong/sysmon-modular | Sysmon XML configuration | Do not use default Sysmon config — it is too noisy or too permissive. Use `olafhartong/sysmon-modular` for this lab: it is modular (enable only relevant modules per VM role), actively maintained, and designed for detection engineering use cases. Apply full config on workstation VM; reduced config on servers to control noise. |
| Packetbeat | 8.17.x (match Elastic Stack) | Network flow telemetry | Elastic's lightweight network protocol analyzer. Captures DNS, HTTP, SMB, LDAP, TLS flows. Critical for detecting C2 beaconing (T1071), lateral movement over SMB (T1021.002), and DNS exfiltration (T1071.004). Run on each Windows VM as a standalone Beat or via Elastic Agent custom integration. |
| Windows Event Forwarding | Built-in Windows | Security event log aggregation | Configure WEF on domain-joined VMs to forward Security, System, and Application logs to Elastic Agent's Windows Event Log integration. Captures logon events (4624/4625), privilege escalation (4672), scheduled task creation (4698), service installs (7045). No additional software needed. |
## What NOT to Use
| Tool / Approach | Category | Why Not |
|-----------------|----------|---------|
| Cobalt Strike | C2 framework | Commercial license, excluded by PROJECT.md. More importantly: would create scope creep — CALDERA already covers C2 orchestration needs for structured ATT&CK emulation. |
| Splunk (SIEM) | SIEM alternative | Free tier (500 MB/day ingest) is completely insufficient for a lab generating dual-telemetry across 4-5 VMs under active attack. Elastic Stack free tier has no ingest cap. |
| Wazuh | EDR/SIEM alternative | Good open-source option but the project has already made the correct choice with Elastic Stack. Running both creates data duplication, agent conflicts, and doubles the maintenance surface. Not additive for this scope. |
| Security Onion | SIEM/NSM platform | Excellent for network security monitoring but bundles Zeek + Suricata + its own Elasticsearch instance. Installing Elastic Stack separately alongside Security Onion creates conflicting Elasticsearch instances and port conflicts. Choose one or the other — this project chose Elastic Stack directly. |
| VirtualBox (as primary) | Hypervisor | Falls back here only if Proxmox is infeasible on available hardware. VirtualBox lacks native snapshot scripting comparable to `qm rollback`. VBoxManage has snapshot commands (`VBoxManage snapshot <VM> restore <name>`) but is slower, less stable under load, and Type-2 (runs inside host OS), meaning 5-6 concurrent VMs will saturate resources faster. |
| Docker / Kubernetes for Windows targets | Containerization | Windows containers cannot simulate a real AD environment (domain join, Kerberos, SMB, LSASS). Must use full Windows VMs. Docker is fine for the SIEM components (Elasticsearch, Kibana) in a development/test context but Elastic's own recommendation for production-style labs is bare-metal or VM installation for stable memory-mapped file performance. |
| Atomic Red Team alone | Emulation framework | Atomic Red Team (Red Canary) tests individual techniques in isolation. Valuable for unit-testing detections but does NOT chain techniques into realistic APT kill chains. CALDERA + CTID plans handle chained emulation. Use Atomics as a supplement to validate specific detection rules, not as a primary emulation engine. |
| OSSEC / Suricata as primary EDR | EDR alternative | Neither provides the behavioral EDR visibility (process tree, memory telemetry) needed to support ML anomaly jobs. Suricata is a network IDS and is additive (could complement Packetbeat) but adds integration complexity for marginal gain over what Packetbeat + Elastic Defend already provides. Skip for this scope. |
| Windows Server 2022 as primary target | OS version | WS2022 defaults: SMB signing required, Credential Guard enabled by default in some configurations, LSA protection stricter. These are real-world hardening improvements but they will block or alert on Mimikatz/Pass-the-Hash before telemetry can be generated, defeating the emulation lab purpose. WS2019 has these features available but not mandatory-on — gives you control over what hardening to enable during specific test phases. |
| Logstash (for lab-scale ingest) | Ingest pipeline | Logstash adds memory overhead (JVM, ~1 GB baseline) and pipeline configuration complexity. Elastic Agent with Fleet Server is the modern replacement and handles all ingest, parsing, and routing without Logstash. Only add Logstash if you have a specific enrichment or routing requirement not met by Fleet ingest pipelines. |
## Confidence Notes
| Area | Confidence | Basis | Action Required |
|------|------------|-------|-----------------|
| Elastic Stack — tool choice (Elasticsearch + Kibana + Fleet + Elastic Agent + Elastic Defend + ML basic tier) | HIGH | Official Elastic free tier documentation, stable since 8.0 (2022). Elastic Defend and ML anomaly detection confirmed available on basic/free license through mid-2025. | Verify free tier limits have not changed at elastic.co/subscriptions before deployment. |
| Elastic Stack — version (8.17.x) | MEDIUM | 8.x series is current; 8.17 is consistent with mid-2025 release cadence. Exact patch version unknown without live check. | Run `apt list --upgradeable` or check elastic.co/downloads for latest 8.x before installing. Pin all components to the same version (Elasticsearch = Kibana = Fleet Server = Elastic Agent). |
| CALDERA — version (5.x) | MEDIUM | CALDERA 5.x was the current major series through training cutoff (August 2025). The stockpile plugin and CTID caldera-integration pattern (payload→ability→adversary→operation) documented in the local repo is stable API. | Check github.com/mitre/caldera/releases for latest tag before cloning. |
| Proxmox VE — version (8.x) | HIGH | Proxmox 8.x is current stable release series (8.0 released 2023, 8.3 mid-2024). Long-term stable for this lab. | Verify 8.x current patch at proxmox.com/en/downloads. |
| `qm` vs `virsh` for snapshot/reset | MEDIUM | `qm` is Proxmox-native and recommended in Proxmox documentation. `virsh` works via libvirt but can have edge cases with Proxmox-managed QEMU VMs. | Test `qm snapshot` and `qm rollback` on a single test VM before scripting all VMs. |
| Windows Server 2019 over 2022 | HIGH | WS2022 hardening defaults (mandatory SMB signing, stricter LSA protection) conflict with credential-theft TTPs. This is well-documented in attacker tradecraft literature. WS2019 evaluation ISOs are freely downloadable from Microsoft. | Download evaluation ISO from Microsoft Evaluation Center. 180-day free evaluation is sufficient for thesis timeline. |
| Sysmon 15.x | MEDIUM | Sysmon 15.x was current through training cutoff. Sysinternals releases are frequent and backward-compatible. | Check learn.microsoft.com/sysinternals/downloads/sysmon for current version before deployment. |
| `olafhartong/sysmon-modular` as Sysmon config | HIGH | Actively maintained, widely adopted in the detection engineering community, explicitly designed for modular per-role configuration. Correct choice over SwiftOnSecurity's config for a multi-VM lab where noise control per role matters. | Pull latest release from github.com/olafhartong/sysmon-modular. |
| Mimikatz + Impacket + BloodHound CE as companion Red Team tools | HIGH | All three are explicitly referenced in CTID emulation plan resources (Mimikatz in OilRig plan directly). These are the canonical open-source tools for the TTPs covered. Free, open-source, no license friction. | Confirm BloodHound CE is the current name (replaced legacy BloodHound + Neo4j stack ~2023). |
| Network architecture (internal bridge vmbr1, 10.10.10.0/24) | HIGH | Standard isolation pattern for cyber range labs. Internal bridge with no physical NIC attached is the correct Proxmox configuration for air-gapped emulation. | Configure in Proxmox web UI under Network tab during initial setup. |
| Exchange Server 2019 as OilRig target | HIGH | CTID OilRig emulation plan explicitly targets EWS (Exchange Web Services). Exchange 2019 is the current on-premises version supported on WS2019. OilRig scenario requires exploiting Exchange (TwoFace webshell on EWS). | Download Exchange Server 2019 CU14+ evaluation/trial from Microsoft. Note: Exchange setup requires .NET 4.8 and Visual C++ Redistributables — plan install order. |
| Packetbeat for network telemetry | HIGH | Packetbeat 8.x is the Elastic-native network protocol analyzer. Matches the existing Elastic Stack choice. ECS-compatible output. Actively maintained by Elastic. | Same version as Elasticsearch. Requires Npcap on Windows. |
| Atomic Red Team as supplement (not primary) | MEDIUM | Atomic Red Team provides per-technique test scripts that can validate specific Elastic detection rules. Use after CALDERA scenario runs to fill technique coverage gaps. | Install via `Install-Module -Name invoke-atomicredteam` on Windows PowerShell. Not required for MVP. |
## Installation Order (Recommended)
## Sources
- Project context: `/home/researcher/Research/titulacion/.planning/PROJECT.md`
- CTID Adversary Emulation Library: `/home/researcher/Research/titulacion/github/adversary_emulation_library/`
- Training data knowledge (cutoff August 2025): Elastic 8.x architecture, CALDERA 5.x, Proxmox 8.x, Sysmon 15.x, Windows Server version hardening differences, network isolation patterns for cyber ranges
- All version numbers marked [VERIFY] require live confirmation at setup time
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
