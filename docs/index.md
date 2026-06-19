# Cyber Range — APT Emulation & Intrusion Detection

<!-- > **Trabajo de Suficiencia Profesional · FIEE-UNI**
> Emulación de amenazas APT y detección de intrusiones sobre infraestructura virtualizada. -->

A fully virtualized cyber range that emulates three real-world APT groups using MITRE CALDERA adversary emulation plans, and detects those attacks through the Elastic Stack (SIEM + EDR + ML anomaly detection). An operator can run a scripted APT scenario, observe live attack telemetry, and reset the entire environment to a clean baseline in a single command.

---

## APT Groups Emulated

| APT Group | Region | Focus TTPs |
|-----------|--------|------------|
| **APT29** (Cozy Bear) | Russia | Credential theft, lateral movement, data exfiltration |
| **OilRig** (APT34) | Iran | Exchange EWS exploitation, persistence, tunneling |
| **Wizard Spider** | Russia | Emotet → TrickBot → Ryuk ransomware chain |

All emulation plans are sourced from the **CTID Adversary Emulation Library** (MITRE Center for Threat-Informed Defense).

---

## Technology Stack

### Red Team
- **MITRE CALDERA 5.x** — C2 framework, native ATT&CK mapping, stockpile plugin
- **Metasploit Framework 6.x** — initial access, exploitation, lateral movement
- **Mimikatz** — credential harvesting (T1003)
- **Impacket** — Pass-the-Hash, DCSync, SMB/WMI lateral movement
- **BloodHound CE** — AD attack path visualization

### Blue Team (SIEM / EDR)
- **Elasticsearch 8.x + Kibana** — event store, detection rules, ML jobs
- **Fleet Server + Elastic Agent** — unified telemetry collection across all VMs
- **Elastic Defend** — EDR (process trees, file events, memory telemetry)
- **Elastic ML** — unsupervised anomaly detection (behavioral baselining)

### Telemetry
- **Sysmon 15.x** — host-level process / network / registry events
- **Packetbeat 8.x** — network flow telemetry (DNS, HTTP, SMB, LDAP, TLS)
- **Windows Event Forwarding** — security log aggregation

### Infrastructure
- **Proxmox VE 8.x** — Type-1 hypervisor, native snapshot/rollback
- **OPNsense VM** — perimeter gateway + Snort IDS (ET Open ruleset) on Host 6
- 6 physical hosts, management network 10.0.0.0/24, isolated TARGET network 10.10.10.0/24
- Internet access: WiFi (wlan0 Host 6) → OPNsense NAT → all VMs

---

## Lab Topology

> ⚠️ **Topology under revision (Phase 1.5 in progress)** — OPNsense perimeter gateway is being added. Host assignment is being finalized before hardware installation. See [Phase 01 runbook](phase-01-runbook#phase-15--perimeter-firewall-pre-install-checklist) for current status.

```
Internet
    │
wlan0 ── Host 6 kernel: ip_forward + MASQUERADE (wlan0 → vmbr_wan 172.16.0.0/30)
    │
┌─────────────────────────────────────┐
│  OPNsense VM  (Host 6, VMID 700)   │
│  WAN: 172.16.0.2   GW: 172.16.0.1  │
│  LAN: 10.0.0.254/24                │
│  [Snort IDS inline — ET Open]       │
└─────────────────────────────────────┘
    │
eth0 Host 6 ──── [Switch] ────┬──── Host 1: elastic-vm  [10.0.0.10]
                               ├──── Host 2: dc01 + sql01
                               ├──── Host 3: exchange01
                               ├──── Host 4: ws01 + ws02
                               └──── Host 5: caldera-vm + kali-vm  [10.0.0.20]

MGMT Network 10.0.0.0/24 (vmbr0) — default gateway: OPNsense 10.0.0.254
  └─ elastic-vm   Host 1   Ubuntu 22.04   Elasticsearch + Kibana + Fleet  [10.0.0.10]
  └─ caldera-vm   Host 5   Ubuntu 22.04   MITRE CALDERA 5.x C2            [10.0.0.20]
  └─ kali-vm      Host 5   Kali 2024.x    Attacker platform               [10.0.0.30]

TARGET Network 10.10.10.0/24 (vmbr1 — VLAN 10, internet via double NAT → OPNsense)
  └─ dc01        Host 2   Windows Server 2019   AD DC + Exchange 2019  [10.10.10.10]
  └─ sql01       Host 2   Windows Server 2019   SQL Server 2019        [10.10.10.30]
  └─ ws01        Host 4   Windows 10 Enterprise Workstation            [10.10.10.40]
  └─ ws02        Host 4   Windows 10 Enterprise Workstation            [10.10.10.41]

VMs TARGET reach internet via double NAT:
  vmbr1 → host kernel MASQUERADE → vmbr0 → OPNsense (10.0.0.254) → wlan0 → Internet
```

---

## Phase Status

| Phase | Name | Status |
|-------|------|--------|
| **01** | Proxmox Foundation + SIEM Node | ✅ Complete (scripts ready; hardware pending) |
| **1.5** | Perimeter Firewall — OPNsense + Snort | ⏸ Paused — hardware verification needed |
| **02** | Windows Target Network | ✅ Complete (scripts ready; hardware pending) |
| **03** | Full Telemetry Pipeline + Reset Mechanism | ⏸ Paused — blocked by Phase 1.5 |
| **04** | APT29 Emulation + Detection | Planned |
| **05** | OilRig Emulation + Detection | Planned |
| **06** | Wizard Spider Emulation + Detection | Planned |
| **07** | ML Anomaly Detection Tuning | Planned |

---

## Operator Runbooks

- [Phase 01 — Proxmox Foundation + SIEM Node Setup](phase-01-runbook)
- [Phase 02 — Windows Target Network](phase-02-runbook)
- [Phase 03 — Full Telemetry Pipeline + Reset Mechanism](phase-03-runbook)

<!-- ---

## Dataset

**FullAPT-2025** — attack telemetry dataset generated by running all three APT emulation scenarios through the cyber range. Captures Sysmon (host) and Packetbeat (network) dual-telemetry aligned to MITRE ATT&CK technique IDs. Currently *en proceso de publicación*. -->

---

*Repository: [github.com/ollerenac/cyber-range-implementation](https://github.com/ollerenac/cyber-range-implementation)*
