# Phase 1: Proxmox Foundation + SIEM Node — Research

**Researched:** 2026-06-17
**Domain:** Hypervisor networking (Proxmox VE 8.x), Elasticsearch/Kibana/Fleet Server 8.19.x, CALDERA 5.x, LVM-thin, TLS certificate provisioning
**Confidence:** HIGH (verified against live official sources; critical version numbers confirmed from apt repo)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Networking**
- D-01: VLAN 802.1Q on managed switch — VLAN 10 carries the TARGET network (10.10.10.0/24). Each Proxmox host connects vmbr1 bridge to a VLAN 10 access or trunk port on the switch.
- D-02: vmbr1 has NO physical uplink on any host — TARGET VMs cannot reach internet or host LAN. VLAN 10 on the switch is isolated from the LAN at the switch level.
- D-03: vmbr0 (MGMT, 10.0.0.0/24) connects normally to the LAN — Elastic Agents enroll via MGMT NIC, not TARGET NIC.

**Storage**
- D-04: LVM-thin storage backend on every Proxmox host. No ZFS.
- D-05: One snapshot per VM: `clean_state`. No multi-snapshot chains. `qm rollback <vmid> clean_state` is the single reset command.
- D-06: ~500 GB SSD/HDD per physical machine. elastic-vm disk: 200 GB. caldera-vm disk: 40 GB.

**VM placement and RAM**
- D-07 (superseded by D-NEW-01/02): elastic-vm and caldera-vm are NEVER in the reset cycle.
- D-08: Elasticsearch heap: Xms8g / Xmx8g. Equal values.
- D-09: Other hosts run Windows target VMs (Phase 2+ scope).
- D-10: elastic-vm and caldera-vm NEVER snapshotted, NEVER in reset_range.sh. Hard constraint.

**TLS**
- D-11: Lab-own CA generated with `elasticsearch-certutil ca`. Fleet Server cert signed by this CA.
- D-12: Fleet Server cert SAN includes `IP:10.0.0.10`. CN: `fleet-server` or `elastic-vm`.
- D-13: CA cert distribution handled in Phase 3 provisioning scripts, but CA cert generated and placed on elastic-vm in Phase 1.

**VM Resource Revisions (D-NEW-01..D-NEW-09)**
- D-NEW-01: elastic-vm RAM = 14 GB (not 12 GB). Host 1 dedicated solely to elastic-vm.
- D-NEW-02: caldera-vm relocated to Host 6 (alongside kali). Host 1 is exclusive elastic-vm.
- D-NEW-03: ws02 added (Phase 2+ scope).
- D-NEW-04: exchange01 RAM = 10 GB (Phase 2+ scope).
- D-NEW-05: dc01 + sql01 co-located on Host 2 (Phase 2+ scope).
- D-NEW-06: Host 5 = SPARE / future IDS sensor. Not provisioned in Phase 1.
- D-NEW-07: TARGET network IPs locked (Phase 2+ scope).
- D-NEW-08: MGMT network IPs locked — elastic-vm = 10.0.0.10 (LOCKED by D-12), caldera-vm = 10.0.0.20.
- D-NEW-09: Final host layout confirmed.

**Final host layout (Phase 1 scope: Host 1 + Host 6)**
| Host | VMs | RAM | Disk |
|------|-----|-----|------|
| Host 1 | elastic-vm (Ubuntu 22.04) | 14 GB | 170 GB thin |
| Host 6 | caldera-vm (Ubuntu 22.04) + kali (Phase 3) | 6 GB | 40 GB thin |

**Ports**
- Fleet Server: 8220
- Kibana: 5601
- Elasticsearch: 9200
- CALDERA UI: 8888
- CALDERA agent beacon: 8853 (TCP contact)

### Claude's Discretion

- Exact Proxmox network bridge configuration syntax (nmcli vs /etc/network/interfaces vs Proxmox WebUI)
- Managed switch VLAN configuration steps (vendor/model not specified — provide generic 802.1Q trunk example)
- ILM policy for logs-* indices (30-day hot → delete)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within Phase 1 scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INFRA-01 | Proxmox VE 8.x installed on each physical machine; each exposes vmbr0 MGMT (10.0.0.0/24) and vmbr1 TARGET (10.10.10.0/24) with no physical uplink on vmbr1 | Covered by: Proxmox bridge syntax, VLAN 10 switch config, isolation verification |
| INFRA-02 | elastic-vm (Ubuntu 22.04, 14 GB RAM) with Elasticsearch 8.19.x + Kibana + Fleet Server deployed on Host 1, accessible on MGMT network at 10.0.0.10 | Covered by: Elasticsearch/Kibana apt install, Fleet Server bootstrap, TLS cert chain, ILM policy |
</phase_requirements>

---

## Summary

Phase 1 delivers two independent tracks that can partly run in parallel: (1) Proxmox networking on all 6 physical hosts, and (2) elastic-vm + caldera-vm provisioning on Hosts 1 and 6. The networking track creates vmbr0 (MGMT, 10.0.0.0/24 with physical uplink) and vmbr1 (TARGET, 10.10.10.0/24 with no physical uplink) on every host, then coordinates VLAN 10 on the managed switch so vmbr1 bridges on different hosts share the same isolated Layer 2 segment. The SIEM track installs Elasticsearch + Kibana + Fleet Server on elastic-vm (Host 1) at 10.0.0.10, generates a lab CA, signs a Fleet Server certificate with SAN IP:10.0.0.10, and verifies that an enrollment token can be issued. CALDERA 5.x is installed on caldera-vm (Host 6) and configured to listen on all interfaces.

**Critical version update:** The CONTEXT.md and prior research reference Elasticsearch 8.17.x, but 8.17.x reached EOL on August 5, 2025. The current supported 8.x series is **8.19.x** (latest: 8.19.16, supported until July 2027). All Elastic components (elasticsearch, kibana, elastic-agent) pin to the same 8.19.16. This affects the locked decision in STATE.md which reads "All Elastic components pinned to same 8.x patch version" — the patch version to pin is now **8.19.16**, not 8.17.x.

The two most common Phase 1 failure modes are: (a) Fleet Server TLS certificate SAN mismatch (cert generated without IP:10.0.0.10 → no agents enroll in Phase 3), and (b) vmbr1 isolation failure (physical uplink accidentally attached or switch port misconfigured → lab network bleeds into LAN).

**Primary recommendation:** Build elastic-vm first, generate the CA and Fleet Server cert before enrolling anything else, verify Kibana access at https://10.0.0.10:5601 with green cluster health, then perform the network isolation gate test on each host before declaring Phase 1 complete.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Layer 2 isolation (TARGET network) | Hypervisor (Proxmox bridge) | Managed switch (VLAN 10 access ports) | vmbr1 with no uplink enforces air-gap at hypervisor; switch enforces cross-host isolation |
| MGMT network routing | Proxmox host OS (vmbr0) | — | Physical NIC on vmbr0 connects hosts to LAN/each other for management |
| Event storage and search | elastic-vm (Elasticsearch 9200) | — | Persistent data sink — never reset |
| Agent policy management | elastic-vm (Fleet Server 8220) | — | All future Elastic Agents enroll here |
| SIEM dashboard | elastic-vm (Kibana 5601) | — | UI for Fleet, Detection Rules, ML Jobs |
| C2 orchestration | caldera-vm (CALDERA 8888/8853) | — | Red team platform; persistent across exercises |
| VM disk provisioning | LVM-thin per-host | Proxmox storage config (local-lvm) | LVM-thin is local; each host has its own pool |
| TLS chain of trust | elastic-vm (CA + Fleet cert) | Phase 3 (CA distribution to target VMs) | CA generated Phase 1; distributed Phase 3 |

---

## Standard Stack

### Core (Phase 1 scope)

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Proxmox VE | 8.x (8.3+ current stable) | Type-1 hypervisor, bridge networking, LVM-thin, qm snapshot | Native `qm rollback` for scripted reset; KVM performance for 6 concurrent VMs |
| Ubuntu Server | 22.04 LTS | Base OS for elastic-vm and caldera-vm | LTS supported until 2027; Elasticsearch 8.x officially supports it; minimal server image |
| Elasticsearch | 8.19.16 | Search/analytics engine, event store | Latest supported 8.x; free/basic tier; Fleet Server requires ES as backend |
| Kibana | 8.19.16 | Fleet UI, Detection Rules UI, dashboards | Must match ES version exactly — same 8.19.16 |
| Fleet Server | 8.19.16 (via elastic-agent) | Central agent policy management | Fleet Server runs inside elastic-agent; pin to same 8.19.16 |
| CALDERA | 5.3.0 (latest v5) | C2 framework / adversary automation | MITRE-maintained; CTID caldera-integration pattern; Python 3.8+ |

### Supporting

| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| elasticsearch-certutil | Bundled with ES 8.19.16 | Lab CA and cert generation | Phase 1 TLS setup; generates .p12 or PEM |
| QEMU Guest Agent | Latest virtio-win | Filesystem freeze for consistent snapshots | Required on all Windows VMs in Phase 2+ |
| python3 / pip3 | 3.10+ (Ubuntu 22.04 ships 3.10) | CALDERA runtime | CALDERA requires Python 3.8+ |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Elasticsearch 8.19.x | Elasticsearch 9.4.2 | 9.x is current but schema changes may break CTID/compatibility assumptions in training data — stay on supported 8.x for thesis timeline |
| Elasticsearch 8.17.x (prior locked decision) | Elasticsearch 8.19.16 | 8.17.x is EOL (August 2025); 8.19.16 is the correct current pin |
| elasticsearch-certutil | openssl req | Both valid; certutil integrates with ES keystore; openssl gives PEM files directly (needed for Fleet Server --fleet-server-cert flag) |
| vmbr1 (no uplink) + managed switch VLAN | pfSense/OPNsense firewall VM | Firewall VM adds complexity; bridge-level isolation is simpler and harder to misconfigure |

**Installation (elastic-vm — Ubuntu 22.04):**
```bash
# Import GPG key
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | \
  sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg

# Add 8.x apt repo
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] \
  https://artifacts.elastic.co/packages/8.x/apt stable main" | \
  sudo tee /etc/apt/sources.list.d/elastic-8.x.list

# Install pinned version
sudo apt-get update
sudo apt-get install elasticsearch=8.19.16 kibana=8.19.16 elastic-agent=8.19.16
```

**Version verification (confirmed from live apt repo, 2026-06-17):**
```bash
apt-cache madison elasticsearch | grep "8.19.16"
# Output: elasticsearch | 8.19.16 | https://artifacts.elastic.co/packages/8.x/apt stable/main amd64
```

---

## Package Legitimacy Audit

> This phase installs system packages via the official Elastic apt repository (artifacts.elastic.co), not from npm/PyPI public registries. CALDERA is installed via git clone from github.com/mitre/caldera (MITRE-maintained). No third-party registry packages are installed in Phase 1.

| Package | Source | Age | Authority | slopcheck | Disposition |
|---------|--------|-----|-----------|-----------|-------------|
| elasticsearch 8.19.16 | elastic.co apt repo (8.x) | ~3 yrs (8.x series) | Official Elastic vendor repo | N/A (vendor apt) | Approved — vendor-controlled repo |
| kibana 8.19.16 | elastic.co apt repo (8.x) | ~3 yrs | Official Elastic vendor repo | N/A (vendor apt) | Approved |
| elastic-agent 8.19.16 | elastic.co apt repo (8.x) | ~3 yrs | Official Elastic vendor repo | N/A (vendor apt) | Approved |
| caldera | github.com/mitre/caldera | ~8 yrs | MITRE — US federal research org | N/A (git clone) | Approved — MITRE-maintained |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

*slopcheck not applicable to vendor apt repos or git-clone installs from known authoritative sources. All sources confirmed directly from official websites.*

---

## Architecture Patterns

### System Architecture Diagram

```
PHYSICAL HOSTS (6x bare metal, 16 GB RAM each)
│
├── Host 1 ─────────────────────────────────────────────────────────
│   │   vmbr0 (MGMT, 10.0.0.0/24) ─── physical NIC ─── LAN switch
│   │   vmbr1 (TARGET, 10.10.10.0/24) ─── NO physical uplink
│   │                                         │ (VLAN 10 on managed switch
│   │   ┌─────────────────────────────────────┤  connects vmbr1 across hosts)
│   │   │ elastic-vm  10.0.0.10               │
│   │   │   Elasticsearch :9200  ◄── Fleet Server :8220
│   │   │   Kibana :5601                      │
│   │   │   Fleet Server :8220  ← enrollment tokens issued here
│   │   │   [ILM policy: logs-* 30-day hot→delete]
│   │   └─────────────────────────────────────┘
│
├── Host 6 ─────────────────────────────────────────────────────────
│   │   vmbr0 (MGMT, 10.0.0.0/24) ─── physical NIC ─── LAN switch
│   │   vmbr1 (TARGET, 10.10.10.0/24) ─── NO physical uplink
│   │
│   │   ┌────────────────────────────────┐
│   │   │ caldera-vm  10.0.0.20          │
│   │   │   CALDERA :8888 (UI)           │
│   │   │   CALDERA :8853 (TCP beacon)   │
│   │   └────────────────────────────────┘
│   │   kali-vm  10.0.0.16 / 10.10.10.200  (Phase 3 scope)
│
├── Hosts 2, 3, 4 ──────────────────────────────────────────────────
│   │   vmbr0 (MGMT) + vmbr1 (TARGET, no uplink)
│   │   Windows target VMs (Phase 2 scope)
│   │   Each target VM: eth0=TARGET, eth1=MGMT
│
└── Host 5 ──────── SPARE (future IDS sensor) ──────────────────────
│       vmbr0 (MGMT) + vmbr1 (TARGET)
│       Not provisioned in Phase 1

MANAGED SWITCH
├── Port → Host 1 physical NIC: trunk port, VLAN 10 tagged + native VLAN untagged
├── Port → Host 2 physical NIC: trunk port, VLAN 10 tagged
├── Port → Host 3 physical NIC: trunk port, VLAN 10 tagged
├── Port → Host 4 physical NIC: trunk port, VLAN 10 tagged
├── Port → Host 5 physical NIC: trunk port, VLAN 10 tagged
└── Port → Host 6 physical NIC: trunk port, VLAN 10 tagged
    VLAN 10 has NO inter-VLAN routing to LAN — switch-level isolation
```

### Recommended Project Structure

```
titulacion/
├── scripts/
│   ├── proxmox/
│   │   ├── network-setup.sh        # vmbr0/vmbr1 configuration helper
│   │   └── verify-isolation.sh     # ping test from vmbr1 VM
│   ├── elastic/
│   │   ├── elasticsearch.yml       # drop-in config for elastic-vm
│   │   ├── kibana.yml              # drop-in config for elastic-vm
│   │   ├── jvm-heap.options        # 8g/8g heap file for /etc/elasticsearch/jvm.options.d/
│   │   ├── generate-certs.sh       # CA + Fleet Server cert generation
│   │   └── ilm-policy.json         # 30-day hot→delete policy
│   └── caldera/
│       ├── local.yml               # CALDERA conf override
│       └── caldera.service         # systemd unit file
└── .planning/phases/01-proxmox-foundation-siem-node/
    └── (this research + plan artifacts)
```

### Pattern 1: Proxmox Bridge Without Physical Uplink (vmbr1)

**What:** A Linux bridge with `bridge-ports none` creates an internal-only virtual switch. VMs attached to it can communicate with each other but cannot reach the physical network. Cross-host connectivity on the same isolated segment is achieved via VLAN on the managed switch.

**When to use:** TARGET network (vmbr1) — all victim VMs that must be air-gapped from internet and host LAN.

**Example:**
```
# /etc/network/interfaces on each Proxmox host
# Source: https://pve.proxmox.com/wiki/Network_Configuration [VERIFIED]

auto vmbr0
iface vmbr0 inet static
        address 10.0.0.1/24
        gateway <LAN_gateway>
        bridge-ports eno1
        bridge-stp off
        bridge-fd 0

auto vmbr1
iface vmbr1 inet static
        address 10.10.10.1/24
        bridge-ports none
        bridge-stp off
        bridge-fd 0
```

**For cross-host VLAN 10 connectivity** (vmbr1 segments on different hosts share one L2 domain):
```
# Option A: Traditional VLAN sub-interface (simpler, one VLAN)
# Source: https://pve.proxmox.com/wiki/Network_Configuration [VERIFIED]
iface eno1.10 inet manual

auto vmbr1
iface vmbr1 inet static
        address 10.10.10.1/24
        bridge-ports eno1.10
        bridge-stp off
        bridge-fd 0
        # bridge-ports eno1.10 means VLAN 10 tagged traffic from trunk port
        # feeds into this bridge — VMs on vmbr1 are on VLAN 10 untagged

# Option B: VLAN-aware bridge (scales to multiple VLANs if needed later)
auto vmbr1
iface vmbr1 inet manual
        bridge-ports eno1
        bridge-stp off
        bridge-fd 0
        bridge-vlan-aware yes
        bridge-vids 10
```

**Note on Option A vs Option B for this lab:** Option A (traditional sub-interface) is simpler for a single-VLAN lab. The managed switch port facing each Proxmox host must be a **trunk port** with VLAN 10 tagged. VMs assigned to vmbr1 receive VLAN 10 traffic untagged (from the bridge perspective, the host handles the VLAN tag).

### Pattern 2: Elasticsearch Single-Node Bootstrap on Ubuntu 22.04

**What:** Elasticsearch 8.x auto-configures TLS, generates a superuser password, and creates a Kibana enrollment token on first start. Capture this output — it is only shown once.

**When to use:** elastic-vm initial setup.

**Example:**
```yaml
# /etc/elasticsearch/elasticsearch.yml
# Source: https://www.elastic.co/guide/en/elasticsearch/reference/8.19/important-settings.html [VERIFIED]

cluster.name: cyber-range
node.name: elastic-vm
network.host: 10.0.0.10
http.port: 9200
discovery.type: single-node
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
```

```
# /etc/elasticsearch/jvm.options.d/heap.options
# Source: https://www.elastic.co/guide/en/elasticsearch/reference/8.19/important-settings.html [VERIFIED]
-Xms8g
-Xmx8g
```

```bash
# First-start sequence — capture the output
sudo systemctl daemon-reload
sudo systemctl enable elasticsearch
sudo systemctl start elasticsearch
# Watch journalctl for: elastic password, Kibana enrollment token (valid 30 min)
sudo journalctl -u elasticsearch -f
```

### Pattern 3: TLS Certificate Chain for Fleet Server

**What:** Generate a lab CA with elasticsearch-certutil, then sign a Fleet Server certificate that includes IP:10.0.0.10 as a SAN. Fleet Server uses PEM-format certs (not .p12) for the --fleet-server-cert flag.

**When to use:** Before Fleet Server bootstrap. CA cert must be placed at a known path for Phase 3 distribution.

**Example:**
```bash
# Source: https://www.elastic.co/guide/en/elasticsearch/reference/8.17/certutil.html [VERIFIED]

# Step 1: Generate lab CA (produces elastic-stack-ca.p12)
/usr/share/elasticsearch/bin/elasticsearch-certutil ca \
  --out /etc/elasticsearch/certs/elastic-stack-ca.p12 \
  --pass ""

# Step 2: Export CA certificate as PEM (for Fleet Server and agent distribution)
openssl pkcs12 -in /etc/elasticsearch/certs/elastic-stack-ca.p12 \
  -out /etc/elasticsearch/certs/ca.crt \
  -nokeys -passin pass:""

# Step 3: Generate Fleet Server cert with IP SAN (produces fleet-server.p12)
/usr/share/elasticsearch/bin/elasticsearch-certutil cert \
  --ca /etc/elasticsearch/certs/elastic-stack-ca.p12 \
  --ca-pass "" \
  --dns fleet-server \
  --ip 10.0.0.10 \
  --out /etc/elasticsearch/certs/fleet-server.p12 \
  --pass ""

# Step 4: Export Fleet Server cert and key as PEM for elastic-agent flags
openssl pkcs12 -in /etc/elasticsearch/certs/fleet-server.p12 \
  -out /etc/elasticsearch/certs/fleet-server.crt \
  -clcerts -nokeys -passin pass:""

openssl pkcs12 -in /etc/elasticsearch/certs/fleet-server.p12 \
  -out /etc/elasticsearch/certs/fleet-server.key \
  -nocerts -nodes -passin pass:""
```

### Pattern 4: Fleet Server Bootstrap

**What:** Install elastic-agent as Fleet Server on elastic-vm. Requires a service token from Elasticsearch.

**Example:**
```bash
# Source: https://www.elastic.co/guide/en/fleet/8.17/secure-connections.html [VERIFIED]

# Step 1: Create service token (run as elastic user or with ES superuser creds)
/usr/share/elasticsearch/bin/elasticsearch-service-tokens create elastic/fleet-server fleet-token

# Step 2: Install elastic-agent as Fleet Server
sudo elastic-agent install \
  --url=https://10.0.0.10:8220 \
  --fleet-server-es=https://10.0.0.10:9200 \
  --fleet-server-service-token=<token-from-step-1> \
  --fleet-server-policy=fleet-server-policy \
  --fleet-server-es-ca=/etc/elasticsearch/certs/ca.crt \
  --certificate-authorities=/etc/elasticsearch/certs/ca.crt \
  --fleet-server-cert=/etc/elasticsearch/certs/fleet-server.crt \
  --fleet-server-cert-key=/etc/elasticsearch/certs/fleet-server.key \
  --fleet-server-port=8220

# Step 3: Verify
sudo elastic-agent status
# Expected: Fleet Server running, connected to ES
```

### Pattern 5: Kibana Configuration and Enrollment

**What:** Kibana connects to Elasticsearch via enrollment token (auto-discovered) or manual kibana.yml config.

**Example:**
```yaml
# /etc/kibana/kibana.yml
# Source: https://www.elastic.co/guide/en/kibana/8.17/deb.html [VERIFIED]

server.port: 5601
server.host: "10.0.0.10"
server.name: "cyber-range-kibana"
elasticsearch.hosts: ["https://10.0.0.10:9200"]
# TLS for browser access (use ES http_ca.crt or a separate cert)
server.ssl.enabled: true
server.ssl.certificate: /etc/kibana/certs/kibana.crt
server.ssl.key: /etc/kibana/certs/kibana.key
# Trust the lab CA for ES connection
elasticsearch.ssl.certificateAuthorities: ["/etc/elasticsearch/certs/ca.crt"]
elasticsearch.ssl.verificationMode: "full"
```

**Alternative — enrollment token flow:**
```bash
# After ES first start, a Kibana enrollment token is printed (valid 30 min)
# Pass it to kibana-setup:
sudo /usr/share/kibana/bin/kibana-setup --enrollment-token <token>
# This auto-populates elasticsearch.hosts, certs, and service account token
```

### Pattern 6: ILM Policy for logs-* (30-day retention)

**What:** Apply a 30-day hot→delete policy to prevent disk exhaustion on the 200 GB elastic-vm disk.

**Example:**
```json
// Source: https://www.elastic.co/guide/en/elasticsearch/reference/8.17/ilm-put-lifecycle.html [VERIFIED]
// PUT _ilm/policy/lab-logs-30d
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_age": "1d",
            "max_size": "10gb"
          }
        }
      },
      "delete": {
        "min_age": "30d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

### Pattern 7: CALDERA 5.x Installation and Configuration

**What:** CALDERA 5.3.0 installed on caldera-vm via git clone. conf/local.yml configures it to listen on all interfaces and expose agent beacon on port 8853.

**Example:**
```bash
# Source: https://caldera.readthedocs.io/en/latest/Installing-Caldera.html [VERIFIED]
git clone https://github.com/mitre/caldera.git --recursive --branch 5.3.0
cd caldera
pip3 install -r requirements.txt
python3 server.py --insecure --build
```

```yaml
# conf/local.yml — override defaults
# Source: https://caldera.readthedocs.io/en/latest/Server-Configuration.html [VERIFIED]
host: 0.0.0.0
port: 8888

app.contact.http: http://10.0.0.20:8888
app.contact.tcp: 0.0.0.0:7010
app.contact.udp: 0.0.0.0:7011
app.contact.websocket: 0.0.0.0:7012
# Note: default TCP contact is 7010, NOT 8853
# CALDERA agents use app.contact.http for HTTP beaconing back to 10.0.0.20:8888

api_key_blue: BLUEADMIN123
api_key_red: ADMIN123
users:
  blue:
    blue: admin
  red:
    admin: admin
```

**CALDERA port clarification:** The CONTEXT.md references port 8853 as the "agent beacon" port. CALDERA 5.x documentation shows `app.contact.tcp: 0.0.0.0:7010` as the TCP contact channel by default. The HTTP contact channel (port 8888) is used by the sandcat agent for HTTP-based beaconing. **The 8853 reference in CONTEXT.md should be treated as an assumed/aspirational value** — the operator must verify the actual contact channel port in conf/local.yml and ensure it matches the agent's compiled-in server URL. [ASSUMED — verify against live CALDERA 5.3.0 conf/default.yml]

```ini
# /etc/systemd/system/caldera.service
# Community pattern — CALDERA does not ship a systemd unit file
[Unit]
Description=MITRE CALDERA C2 Framework
After=network.target

[Service]
Type=simple
User=caldera
WorkingDirectory=/opt/caldera
ExecStart=/usr/bin/python3 server.py --insecure
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
```

### Pattern 8: LVM-Thin Verification

**What:** Confirm existing thin pool on each Proxmox host before creating VMs.

**Example:**
```bash
# Source: https://pve.proxmox.com/wiki/Storage:_LVM_Thin [VERIFIED]

# List thin pools on the 'pve' volume group
pvesm scan lvmthin pve

# Verify with native LVM tools
lvs --type thin-pool

# Confirm Proxmox storage config
cat /etc/pve/storage.cfg | grep -A5 "lvmthin:"
# Expected: lvmthin: local-lvm / thinpool data / vgname pve / content rootdir,images
```

### Pattern 9: qm Snapshot Commands

**What:** Proxmox-native QEMU VM snapshot and rollback. Used for clean_state snapshots (Phase 3 scope) but the syntax must be established in Phase 1 documentation.

**Example:**
```bash
# Source: https://pve.proxmox.com/pve-docs/qm.1.html [VERIFIED]

# List VMs and their VMIDs
qm list

# Take snapshot (no --quiesce flag in qm — use QEMU Guest Agent for consistency)
qm snapshot <VMID> clean_state --description "Post-setup baseline with agent enrolled"

# For QEMU Guest Agent filesystem freeze (Windows VMs — Phase 3):
# Enable guest agent in VM options first: qm set <VMID> --agent 1
# qm snapshot automatically uses guest agent freeze if enabled
qm agent <VMID> fsfreeze-freeze   # manual pre-snapshot freeze if needed
qm snapshot <VMID> clean_state
qm agent <VMID> fsfreeze-thaw

# Rollback
qm rollback <VMID> clean_state

# Start/stop
qm stop <VMID>
qm start <VMID>
```

**Important finding:** `qm snapshot` does **not** have a `--quiesce` flag (confirmed from live Proxmox docs). Filesystem quiescing for Windows VMs requires the QEMU Guest Agent to be installed and enabled in VM options. When the agent is enabled, Proxmox automatically calls guest-fsfreeze-freeze/thaw before/after creating a snapshot. This applies to Phase 3 Windows VM snapshots; elastic-vm and caldera-vm are never snapshotted.

### Anti-Patterns to Avoid

- **Attaching a physical NIC to vmbr1:** Any physical uplink on vmbr1 bypasses isolation. Always use `bridge-ports none` (no uplink) for vmbr1. Verify with `brctl show vmbr1` — the "interfaces" column must be empty.
- **Generating Fleet Server cert without IP SAN:** `elasticsearch-certutil cert` default output does not include an IP SAN unless `--ip` is specified explicitly. A cert signed for `fleet-server` (DNS only) will reject connections from elastic-agents that connect by IP (10.0.0.10). This is the single most common Fleet enrollment failure.
- **Running Kibana on port 5601 with HTTP (not HTTPS):** Modern browsers block mixed content. Elastic Agents cannot verify Fleet Server identity without TLS. Always enable server.ssl in kibana.yml.
- **Setting Elasticsearch `network.host: 0.0.0.0` without `discovery.type: single-node`:** Elasticsearch enters production mode bootstrap checks which require virtual memory settings (vm.max_map_count), file descriptor limits, and cluster formation quorum. Always pair `network.host: <specific_IP>` with `discovery.type: single-node` for a lab single-node cluster.
- **Starting CALDERA without `--insecure` flag in HTTP mode:** CALDERA 5.x requires `--insecure` when not using HTTPS. Without it, agent connections may fail. The `--build` flag is required on first run to compile the VueJS UI.
- **Installing elastic-agent before Fleet Server is bootstrapped:** The `elastic-agent install --enrollment-token` command for regular agents (Phase 3) requires an active Fleet Server at the enrollment URL. Fleet Server must be healthy before any agent enrollment.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CA and cert generation with IP SANs | Custom openssl.conf with SAN extension | `elasticsearch-certutil ca` + `elasticsearch-certutil cert --ip` | certutil handles PKCS12 format that ES keystore expects; also outputs PEM with correct SAN when --ip flag used |
| Fleet Server enrollment token | Manual API calls to ES | `elasticsearch-service-tokens create elastic/fleet-server` | elasticsearch-service-tokens is the correct tool; manual token creation via Kibana API is error-prone in scripted setup |
| ILM rollover policy | Custom cron jobs to delete old indices | `PUT _ilm/policy/` API | ILM integrates with data streams; cron deletion misses hot index that hasn't rolled |
| Sysmon ECS field normalization | Logstash pipeline or custom ingest pipeline | Elastic Agent Windows integration (built-in ingest pipeline) | Windows integration ships with pre-built ECS normalization; hand-rolled pipelines break on field name changes |
| VLAN isolation | iptables rules on Proxmox host | `bridge-ports none` + managed switch VLAN | Hypervisor-level bridge isolation is enforced in hardware; iptables rules can be flushed accidentally |

**Key insight:** The Elastic agent/Fleet/certutil toolchain is opinionated — use the bundled tools rather than generic alternatives. The tools are designed to work together and handle key format conversions that generic tools (openssl alone) require extra steps for.

---

## Common Pitfalls

### Pitfall 1: Fleet Server TLS Certificate SAN Mismatch

**What goes wrong:** Elastic Agents receive `x509: certificate is valid for fleet-server, not 10.0.0.10` during enrollment. Fleet UI shows zero enrolled agents.

**Why it happens:** `elasticsearch-certutil cert` generates a cert with the CN as the only identifier unless `--ip` and `--dns` flags are explicitly passed. The default output cert has no SAN extensions at all, which causes rejection by modern TLS clients.

**How to avoid:** Always pass `--ip 10.0.0.10 --dns fleet-server` to certutil. After generating, verify the SAN with: `openssl x509 -in fleet-server.crt -noout -text | grep -A3 "Subject Alternative"` — must show `IP Address:10.0.0.10`.

**Warning signs:** `elastic-agent enroll` exits non-zero with TLS error; Fleet UI Agents tab is empty after 5 minutes.

### Pitfall 2: vmbr1 Isolation Failure (Physical Uplink Present)

**What goes wrong:** VMs on vmbr1 can ping 8.8.8.8 or reach host LAN addresses. Attack tools beacon to real internet infrastructure. Packetbeat floods with irrelevant traffic.

**Why it happens:** Proxmox UI default when creating a bridge is to attach the first available physical NIC as bridge-ports. If the operator creates vmbr1 via the UI without explicitly selecting "no uplink," it may inherit a NIC.

**How to avoid:** Always create vmbr1 via `/etc/network/interfaces` with `bridge-ports none`. After applying: test with `brctl show vmbr1` (interfaces column empty) AND deploy a minimal test VM on vmbr1 and run `ping -c 3 8.8.8.8` — must time out. Run this test before provisioning any target VMs.

**Warning signs:** `ping 8.8.8.8` succeeds from a vmbr1 VM; Packetbeat shows DNS queries to 8.8.8.8 from 10.10.10.x addresses.

### Pitfall 3: Elasticsearch `network.host` Bootstrap Check Failure

**What goes wrong:** After setting `network.host: 10.0.0.10`, Elasticsearch refuses to start with errors about `vm.max_map_count` or `max_file_descriptors`. This is production bootstrap mode enforcement.

**Why it happens:** Elasticsearch enters "production mode" when `network.host` is set to a non-loopback address. Production mode enforces OS-level settings that are not set by default on a fresh Ubuntu 22.04 install.

**How to avoid:**
```bash
# Set before starting Elasticsearch
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
# Increase file descriptor limits for the elasticsearch user
echo "elasticsearch soft nofile 65535" | sudo tee -a /etc/security/limits.conf
echo "elasticsearch hard nofile 65535" | sudo tee -a /etc/security/limits.conf
```

**Warning signs:** `journalctl -u elasticsearch` shows `bootstrap checks failed` with `max virtual memory areas vm.max_map_count [65530] is too low`.

### Pitfall 4: Kibana Enrollment Token Expiry (30-Minute Window)

**What goes wrong:** Operator starts Elasticsearch, gets the Kibana enrollment token from first-start output, then takes a break. Returns 45 minutes later. Token is expired. Kibana setup fails. Operator doesn't know how to get a new one.

**How to avoid:** Generate a new token at any time with:
```bash
/usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana
```
Keep this command in the runbook. It can be run at any point after Elasticsearch is healthy.

**Warning signs:** Kibana setup page shows "Enrollment token expired or invalid."

### Pitfall 5: CALDERA Agent Contact URL Points to localhost

**What goes wrong:** CALDERA is started without modifying conf/local.yml. The `app.contact.http` setting defaults to `http://0.0.0.0:8888` which agents compiled with that URL cannot actually reach from another VM (0.0.0.0 is a bind address, not a routable address).

**How to avoid:** Set `app.contact.http: http://10.0.0.20:8888` in conf/local.yml BEFORE first start, or before building any agents. Changing this after agent compilation requires rebuilding the agent binary.

**Warning signs:** CALDERA operation shows agents as "inactive" immediately after deploying the sandcat binary on a target VM.

### Pitfall 6: Elasticsearch Heap Greater Than 31 GB Disables Compressed OOPs

**What goes wrong:** Operator sets heap to 32 GB (seemingly reasonable for a 14 GB VM — actually this is above the physical RAM). Even at lower values above 31 GB, the JVM disables compressed ordinary object pointers (OOPs), increasing memory overhead by up to 20%.

**How to avoid:** Keep heap at exactly `Xms8g` / `Xmx8g` as specified in D-08. This is correct for the 14 GB elastic-vm. Never set heap above half of physical RAM.

---

## Code Examples

### Network Isolation Verification

```bash
# On any Proxmox host, after configuring vmbr1:
brctl show vmbr1
# Expected output: vmbr1  <bridge-id>  no  none
# The "interfaces" column must show "none"

# Deploy a minimal test VM on vmbr1 (Ubuntu minimal, 1 GB RAM, DHCP or static 10.10.10.254)
# From inside the test VM:
ping -c 3 8.8.8.8             # Must FAIL (timeout or unreachable)
ping -c 3 10.0.0.1            # Must FAIL (MGMT network unreachable from TARGET)
ping -c 3 10.10.10.1          # Must SUCCEED (Proxmox host vmbr1 address)

# Tcpdump confirmation on the Proxmox host:
sudo tcpdump -i vmbr1 -n icmp
# Send ping from test VM; confirm packets appear in tcpdump but never leave the bridge
```

### Elasticsearch Health Check

```bash
# After Elasticsearch starts and network.host is set:
curl -k -u elastic:<password> https://10.0.0.10:9200/_cluster/health?pretty
# Expected: "status": "green", "number_of_nodes": 1

# Check indices
curl -k -u elastic:<password> https://10.0.0.10:9200/_cat/indices?v
```

### Fleet Server Health Check

```bash
# After elastic-agent install (Fleet Server mode):
sudo elastic-agent status
# Expected: elastic-agent  Active  Fleet Server running  Connected to ES

# Verify Fleet Server port
ss -tlnp | grep 8220
# Expected: LISTEN  0  128  10.0.0.10:8220
```

### Kibana Access Verification

```bash
# From operator workstation browser:
# https://10.0.0.10:5601
# Accept self-signed cert warning (lab CA not in browser trust store)
# Login as elastic / <password>
# Navigate to: Stack Management → Fleet → Agents
# Expected: Fleet Server agent shown as "Healthy"
# Navigate to: Stack Management → Fleet → Enrollment Tokens
# Click "Create enrollment token" → copy token for Phase 3 use
```

### CALDERA Start and Verify

```bash
# On caldera-vm (10.0.0.20):
cd /opt/caldera
python3 server.py --insecure &

# Verify UI reachable from operator workstation:
curl -s http://10.0.0.20:8888/api/v2/health | python3 -m json.tool
# Expected: {"framework": "caldera", "version": "5.3.0", ...}

# Verify TCP contact port:
ss -tlnp | grep 7010
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Elasticsearch 8.17.x (project's prior locked version) | Elasticsearch 8.19.16 (latest supported 8.x) | 8.17 EOL: August 2025; 8.19 released July 2025 | All Elastic component pins must be updated from 8.17.x to 8.19.x |
| Manual Logstash ingest pipelines | Elastic Agent with Fleet (built-in ingest pipelines) | Elastic 8.0 (2022) | No Logstash needed; Fleet manages all parsing and routing |
| Standalone Packetbeat / Winlogbeat | Elastic Agent wrapping all integrations | Elastic 8.0+ | One agent process per VM; Fleet policy controls all integrations |
| `virsh snapshot-create` for Proxmox VMs | `qm snapshot` | Proxmox 7.x+ | `qm` is native; `virsh` has edge cases with Proxmox LVM-thin disks |
| BloodHound (legacy, Neo4j-based) | BloodHound CE (Community Edition) | 2023 | BloodHound CE replaced the legacy stack; different install method |

**Deprecated / outdated:**
- Elasticsearch 8.17.x: EOL August 5, 2025 — do not install. Use 8.19.16.
- Elasticsearch 8.18.x: EOL October 21, 2025 — do not install. Use 8.19.16.
- `virsh snapshot-create` for Proxmox QEMU VMs: works but inconsistent with LVM-thin; replaced by `qm snapshot`.
- `--quiesce` flag on `qm snapshot`: does not exist. Guest agent quiescing is automatic when guest agent is enabled on the VM.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | CALDERA agent beacon uses port 8853 (TCP) as stated in CONTEXT.md | Standard Stack / Pattern 7 | Agent compiled with wrong contact URL; agents won't beacon back; must recompile |
| A2 | CALDERA 5.3.0 `conf/local.yml` `app.contact.http` controls the HTTP beacon URL that agents use | Pattern 7 | Misconfigured beacon URL; operator must manually verify conf/default.yml |
| A3 | `python3 server.py --insecure --build` with conf/local.yml host:0.0.0.0 makes CALDERA listen on all interfaces | Pattern 7 | CALDERA only reachable from localhost; remote operator cannot access UI |
| A4 | Proxmox 8.x (current stable patch) is available for installation on the 6 physical hosts | Standard Stack | Must verify proxmox.com/downloads at setup time |
| A5 | The 6 physical hosts' LAN switch supports 802.1Q VLAN trunking (vendor-neutral assumption) | Architecture | If switch does not support 802.1Q, cross-host TARGET connectivity requires different approach (each host isolated, no lateral movement across hosts) |
| A6 | LVM-thin pool named `local-lvm` exists on each host post-Proxmox install (default Proxmox layout) | Pattern 8 | `pvesm scan lvmthin pve` shows no pool; operator must create it manually before VM provisioning |

**If this table is empty:** Not applicable — 6 assumed claims identified above.

---

## Open Questions (RESOLVED)

1. **CALDERA agent beacon port: 8853 vs 7010**
   - What we know: CONTEXT.md says "Fleet Server port: 8220 ... CALDERA agent beacon: 8853 (TCP contact)". CALDERA 5.x docs show `app.contact.tcp: 0.0.0.0:7010` as the TCP contact. The HTTP contact (port 8888) is the default beaconing method for sandcat.
   - What's unclear: Whether the operator previously verified a custom conf/local.yml that sets TCP contact to 8853, or if 8853 is a mistaken assumption.
   - Recommendation: Include a verification step in the plan — after starting CALDERA, run `ss -tlnp | grep -E "(8853|7010|8888)"` and document which ports are actually open. If 8853 is desired, add `app.contact.tcp: 0.0.0.0:8853` to conf/local.yml explicitly.

2. **Elasticsearch version: 8.17.x (locked in CONTEXT.md) vs 8.19.16 (current)**
   - What we know: CONTEXT.md and STATE.md reference Elasticsearch 8.17.x. 8.17.x is EOL as of August 5, 2025. The current supported 8.x release is 8.19.16 (EOL July 2027). The apt 8.x repo delivers 8.19.16 as the latest 8.x.
   - What's unclear: Whether the user wants to explicitly acknowledge the version change.
   - Recommendation: The planner should generate tasks using 8.19.16 and include a note flagging the version update from the locked decision. The spirit of STATE.md ("all Elastic components pinned to same 8.x patch version") is preserved — the specific patch just changes to 8.19.16.

3. **QEMU Guest Agent on elastic-vm and caldera-vm**
   - What we know: elastic-vm and caldera-vm are never snapshotted. QEMU Guest Agent is only needed for VMs that will be snapshotted (Windows target VMs in Phase 3).
   - What's unclear: Whether the Proxmox host benefits from guest agent on elastic-vm for graceful shutdown purposes.
   - Recommendation: Install QEMU Guest Agent on elastic-vm and caldera-vm anyway (it enables graceful shutdown via Proxmox UI) but document that it is not required for snapshot consistency since these VMs are never snapshotted.

4. **Kibana self-signed cert for browser access**
   - What we know: Kibana needs TLS for the browser to accept HTTPS at 10.0.0.10:5601. The lab CA can sign a Kibana cert using certutil. Alternatively, the auto-configured ES http_ca.crt can be reused.
   - What's unclear: Whether a separate Kibana cert (kibana.crt/kibana.key) is generated alongside the Fleet Server cert, or whether the ES HTTP cert is reused for Kibana.
   - Recommendation: Generate a separate Kibana cert in the same certutil run as the Fleet Server cert, using `--dns elastic-vm --ip 10.0.0.10`. This keeps cert scope clean and allows independent replacement.

---

## Environment Availability

> Step 2.6 assessment: This phase runs on bare-metal Proxmox hosts that do not yet exist as provisioned systems. The research machine (titulacion dev environment) is not the target execution environment. Environment availability is assessed for the target physical hosts.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Proxmox VE 8.x | INFRA-01 | Unknown (hardware not yet provisioned) | 8.3+ target | No fallback — must be installed |
| Ubuntu 22.04 LTS ISO | elastic-vm, caldera-vm | Download from ubuntu.com | 22.04.4 LTS | No fallback for the OS choice |
| Internet access from Proxmox hosts | apt package install | Required during setup | — | Offline install via local mirror (complex) |
| elastic.co apt repo (8.x) | Elasticsearch, Kibana, elastic-agent | Confirmed reachable from dev machine | 8.19.16 available | Download .deb directly from elastic.co |
| github.com/mitre/caldera | CALDERA install | Requires internet on caldera-vm | 5.3.0 | Clone to offline mirror, SCP to caldera-vm |
| Managed switch with 802.1Q | vmbr1 cross-host TARGET connectivity | Assumed available (D-01 confirmed by user) | Unknown vendor | Single-host lab (no cross-host TARGET) |
| Python 3.8+ | CALDERA | Available on Ubuntu 22.04 | Python 3.10.12 | None needed |

**Missing dependencies with no fallback:**
- Physical hardware (6 Proxmox hosts) — not blocking for planning; blocking for execution
- Internet access during initial setup — required to pull packages; operator must ensure Proxmox hosts have LAN/internet during bootstrap

**Missing dependencies with fallback:**
- elastic.co apt repo: fallback is direct .deb download from elastic.co/downloads if repo is blocked
- github.com/mitre/caldera: fallback is local mirror on dev machine, SCP to caldera-vm

---

## Validation Architecture

> `nyquist_validation: true` in config.json — section required.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Manual verification (infrastructure phase — no automated unit tests) |
| Config file | none |
| Quick run command | `bash scripts/proxmox/verify-isolation.sh` (to be created in Wave 0) |
| Full suite command | All 4 Phase 1 success criteria verified manually per ROADMAP.md |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INFRA-01 | vmbr0 and vmbr1 exist on each host; vmbr1 has no physical uplink | smoke | `brctl show vmbr0 vmbr1` | ❌ Wave 0 |
| INFRA-01 | VM on vmbr1 cannot ping 8.8.8.8 | integration | `ping -c3 -W2 8.8.8.8; echo "exit:$?"` (from vmbr1 test VM) | ❌ Wave 0 |
| INFRA-02 | Elasticsearch cluster health is green | smoke | `curl -sk -u elastic:<pass> https://10.0.0.10:9200/_cluster/health \| python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d['status']=='green' else 1)"` | ❌ Wave 0 |
| INFRA-02 | Kibana reachable at https://10.0.0.10:5601 | smoke | `curl -sk -o /dev/null -w "%{http_code}" https://10.0.0.10:5601 \| grep -q "200\|302"` | ❌ Wave 0 |
| INFRA-02 | Fleet Server active with enrollment token | manual | Fleet UI → Agents tab shows Fleet Server "Healthy"; enrollment token copyable | manual-only |

### Sampling Rate

- **Per task commit:** Run applicable smoke check for the task (e.g., after bridge config: `brctl show`)
- **Per wave merge:** Run full verification script against all completed infrastructure
- **Phase gate:** All 4 ROADMAP.md success criteria TRUE before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `scripts/proxmox/verify-isolation.sh` — covers INFRA-01 isolation gate
- [ ] `scripts/elastic/health-check.sh` — covers INFRA-02 ES green + Kibana + Fleet checks

*(No existing test infrastructure — all scripts are new in Wave 0)*

---

## Security Domain

> `security_enforcement` not set to false in config.json — section required.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | Yes | Elasticsearch built-in security (elastic superuser); Kibana SSO via ES |
| V3 Session Management | Partial | Kibana session tokens (auto-managed); not custom |
| V4 Access Control | Yes | Fleet Server service token (scoped to fleet-server role); enrollment tokens scoped per policy |
| V5 Input Validation | No | No user-facing web application in Phase 1 |
| V6 Cryptography | Yes | Lab CA (elasticsearch-certutil); TLS 1.2/1.3 enforced by Elasticsearch 8.x defaults; never use HTTP for ES or Fleet |

### Known Threat Patterns for this Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Enrollment token leakage (token in shell history or logs) | Information Disclosure | Store tokens in /root/.elastic-tokens (chmod 600); never echo to stdout in scripts |
| Fleet Server cert signed without IP SAN → MITM possible with rogue cert | Tampering | Always verify SAN with openssl x509 -text; use the lab CA for all Elastic TLS |
| vmbr1 uplink accidental attachment → network bleed | Elevation of Privilege | Verify bridge-ports after every /etc/network/interfaces edit; gate test mandatory |
| CALDERA API key default (`ADMIN123`) exposed on MGMT network | Information Disclosure | Change api_key_red and api_key_blue in conf/local.yml before first start; MGMT network is management-only but shared by all 6 hosts |
| elastic superuser password in shell history | Information Disclosure | Use password manager; set ES_PASSWORD env var in scripts; never hardcode in .sh files committed to git |

---

## Sources

### Primary (HIGH confidence — verified via live fetch 2026-06-17)

- [Proxmox VE Network Configuration](https://pve.proxmox.com/wiki/Network_Configuration) — bridge syntax, VLAN-aware bridges, vmbr1 no-uplink configuration
- [Elasticsearch 8.x Debian Install](https://www.elastic.co/guide/en/elasticsearch/reference/8.17/deb.html) — apt repo setup, GPG key, package install commands
- [Elasticsearch Important Settings](https://www.elastic.co/guide/en/elasticsearch/reference/8.17/important-settings.html) — cluster.name, node.name, network.host, discovery.type: single-node, JVM heap via jvm.options.d/
- [Elasticsearch Security Auto-Config](https://www.elastic.co/guide/en/elasticsearch/reference/8.17/configuring-stack-security.html) — first-start password, Kibana enrollment token, http_ca.crt location
- [elasticsearch-certutil](https://www.elastic.co/guide/en/elasticsearch/reference/8.17/certutil.html) — CA generation, cert with --ip and --dns SAN flags
- [Fleet Server Secure Connections](https://www.elastic.co/guide/en/fleet/8.17/secure-connections.html) — elastic-agent install command with --fleet-server-cert, --fleet-server-cert-key, --certificate-authorities
- [Kibana Debian Install](https://www.elastic.co/guide/en/kibana/8.17/deb.html) — apt install, systemd service, enrollment token flow
- [ILM Put Lifecycle API](https://www.elastic.co/guide/en/elasticsearch/reference/8.17/ilm-put-lifecycle.html) — PUT _ilm/policy JSON structure, hot rollover + delete phases
- [Proxmox qm man page](https://pve.proxmox.com/pve-docs/qm.1.html) — qm snapshot, qm rollback, qm start, qm stop syntax; confirmed no --quiesce flag
- [Proxmox QEMU Guest Agent](https://pve.proxmox.com/wiki/Qemu-guest-agent) — guest agent enable, Windows virtio-win install, automatic fsfreeze during snapshots
- [Proxmox LVM Thin Storage](https://pve.proxmox.com/wiki/Storage:_LVM_Thin) — pvesm scan lvmthin, storage.cfg format, local-lvm default
- [CALDERA Installation Docs](https://caldera.readthedocs.io/en/latest/Installing-Caldera.html) — git clone, pip3 install, python3 server.py --build
- [CALDERA Server Configuration](https://caldera.readthedocs.io/en/latest/Server-Configuration.html) — conf/local.yml host, port, app.contact.* settings, user credentials
- [Elasticsearch End of Life Dates](https://endoflife.date/elasticsearch) — 8.17 EOL August 2025, 8.19 EOL July 2027
- [Elastic apt repo 8.x package list](https://artifacts.elastic.co/packages/8.x/apt/) — confirmed elasticsearch=8.19.16, kibana=8.19.16, elastic-agent=8.19.16 (live apt query 2026-06-17)

### Secondary (MEDIUM confidence — WebSearch verified)

- [Elasticsearch 8.x release history](https://endoflife.date/elasticsearch) — version timeline confirming 8.19 as latest 8.x
- [Proxmox VLAN forum discussion](https://forum.proxmox.com/threads/proxmox-vlan-on-trunk-switch-interface.140175/) — community confirmation of trunk port + VLAN sub-interface pattern
- [CALDERA GitHub](https://github.com/mitre/caldera) — v5.3.0 confirmed as latest release (April 2025); Python 3.10+ confirmed
- [CALDERA systemd service example](https://gist.github.com/keyboardcrunch/408e49c517e3875374089d5f6d75ed5b) — community systemd unit file pattern

### Tertiary (LOW confidence — training data / ASSUMED)

- CALDERA port 8853 for agent beacon (from CONTEXT.md) — not confirmed in live CALDERA 5.x documentation; actual default TCP contact is 7010
- Proxmox 8.x current patch version — research confirms 8.x series; specific patch version requires live check at proxmox.com/downloads at install time

---

## Metadata

**Confidence breakdown:**
- Standard stack (Elasticsearch/Kibana/Fleet version): HIGH — verified from live apt repo; 8.19.16 confirmed
- Proxmox bridge syntax: HIGH — verified from live Proxmox wiki
- TLS cert generation (certutil): HIGH — verified from live Elastic docs with exact flags
- Fleet Server bootstrap command: HIGH — verified from live Elastic secure-connections doc
- CALDERA configuration: MEDIUM — core install verified; contact port 8853 unconfirmed (A1)
- LVM-thin / qm snapshot: HIGH — verified from live Proxmox docs
- ILM policy syntax: HIGH — verified from live Elastic docs

**Research date:** 2026-06-17
**Valid until:** 2026-07-17 for Elastic version pins (Elastic releases patches monthly; re-verify before install if >30 days elapsed)
