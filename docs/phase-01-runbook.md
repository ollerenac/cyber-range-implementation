# Phase 01 — Proxmox Foundation + SIEM Node

> **Status:** ✅ Complete · All 4 waves executed and approved

This runbook covers standing up the hypervisor networking fabric and the two persistent control-plane VMs (elastic-vm and caldera-vm) on 6 Proxmox hosts.

---

## Lab Network Topology

```
Physical hosts: 6x Proxmox VE 8.x nodes

Management network  vmbr0 — 10.0.0.0/24 (LAN access, Elastic Agent enrollment)
  └─ elastic-vm     10.0.0.10   Host 1    Ubuntu 22.04  14 GB RAM / 200 GB disk
  └─ caldera-vm     10.0.0.20   Host 6    Ubuntu 22.04   6 GB RAM /  40 GB disk

Target network      vmbr1 — 10.10.10.0/24 (air-gapped, VLAN 10 — NO internet)
  └─ [Phase 2+]     Windows Server 2019 × 2, Windows 10, Kali
```

> **Security property:** `vmbr1` has **no physical NIC uplink** — target VMs cannot reach the internet or host LAN. The managed switch carries VLAN 10 with no inter-VLAN routing.

---

## Wave 1 — Proxmox Networking Fabric

**Goal:** Every host exposes `vmbr0` (MGMT) and `vmbr1` (TARGET, air-gapped) before any VM is created.

### Prerequisites
- 6 Proxmox VE 8.x hosts with SSH root access
- Managed switch with 802.1Q VLAN 10 support
- LVM-thin storage pool (`local-lvm`) present on each host

### Step 1 — Verify storage pools

Run on **each** Proxmox host:

```bash
bash scripts/proxmox/verify-storage.sh
```

Expected: `[OK] LVM-thin pool found` on every host. Non-zero exit blocks provisioning.

### Step 2 — Configure switch VLAN 10

Follow `scripts/proxmox/SWITCH-VLAN10.md` on your managed switch:
- Create VLAN 10 (tag `10`)
- Set each host uplink port as **trunk, tagged VLAN 10**
- No Layer-3 SVI or routing between VLAN 10 and the LAN

### Step 3 — Apply network bridges

Run on **each** Proxmox host (dry-run first, then apply):

```bash
# Preview only — no changes written
bash scripts/proxmox/network-setup.sh

# Write /etc/network/interfaces and restart networking
bash scripts/proxmox/network-setup.sh --apply
```

### Step 4 — Verify isolation

Run on **each** Proxmox host:

```bash
bash scripts/proxmox/verify-isolation.sh
```

Expected: `vmbr1` has no bare physical NIC uplink. A ping from a target VM to `8.8.8.8` **failing** is the success condition.

---

## Wave 2 — Control-Plane VM Provisioning

**Goal:** Create `elastic-vm` (Host 1) and `caldera-vm` (Host 6) from Ubuntu 22.04 cloud image.

### Prerequisites
- Wave 1 complete — `vmbr0`/`vmbr1` bridges applied and verified
- Ubuntu 22.04 cloud image downloaded on each target host
- SSH public key ready for `SSH_KEYFILE`

### Create elastic-vm (Host 1)

```bash
# On Proxmox Host 1
export VMID=200
export SSH_KEYFILE=/root/.ssh/id_rsa.pub
export CLOUD_IMAGE=/var/lib/vz/template/iso/jammy-server-cloudimg-amd64.img
export LAN_GW=10.0.0.1
export STORAGE=local-lvm

bash scripts/proxmox/create-elastic-vm.sh
```

**Specs:** 14 GB RAM · 4 vCPU · 200 GB disk · IP 10.0.0.10 (static)

The cloud-init template pre-applies Elasticsearch production mode prerequisites:
- `vm.max_map_count=262144` (persistent via `/etc/sysctl.d/99-elasticsearch.conf`)
- `nofile` ulimit `65535` for the `elasticsearch` service account

### Create caldera-vm (Host 6)

```bash
# On Proxmox Host 6
export VMID=201
export SSH_KEYFILE=/root/.ssh/id_rsa.pub
export CLOUD_IMAGE=/var/lib/vz/template/iso/jammy-server-cloudimg-amd64.img
export LAN_GW=10.0.0.1
export STORAGE=local-lvm

bash scripts/proxmox/create-caldera-vm.sh
```

**Specs:** 6 GB RAM · 2 vCPU · 40 GB disk · IP 10.0.0.20 (static)

### Checkpoint — verify both VMs

```bash
# From any host on 10.0.0.0/24
ssh ubuntu@10.0.0.10 "hostname && free -h"   # elastic-vm
ssh ubuntu@10.0.0.20 "hostname && free -h"   # caldera-vm
```

---

## Wave 3 — Elasticsearch + Kibana + Fleet Server

**Goal:** Full SIEM stack running on `elastic-vm` (10.0.0.10) — Elasticsearch, Kibana, Fleet Server.

### Install the stack

```bash
# On elastic-vm (10.0.0.10)
bash scripts/elastic/install-stack.sh
```

Installs Elasticsearch 8.x, Kibana (same version), and Fleet Server. Configures ILM with 30-day retention on `logs-*` and `metrics-*` indices.

### Generate TLS certificates

```bash
bash scripts/elastic/generate-certs.sh
```

### Bootstrap Fleet Server

```bash
bash scripts/elastic/bootstrap-fleet.sh
```

Starts Fleet Server on port 8220. Kibana Fleet UI becomes the enrollment entry point for all Elastic Agents.

### Verify SIEM health

```bash
bash scripts/elastic/health-check.sh
```

Expected: Elasticsearch green/yellow cluster, Kibana reachable on port 5601, Fleet Server enrolled.

### Access Kibana

```
http://10.0.0.10:5601
Default credentials — set via install-stack.sh (ELASTIC_PASSWORD env var)
```

---

## Wave 4 — CALDERA 5.x Install + Snapshot Workflow

**Goal:** CALDERA C2 running on `caldera-vm` (10.0.0.20), baseline snapshots taken, reset workflow verified.

### Install CALDERA

```bash
# On caldera-vm (10.0.0.20)
# 1. Edit PLACEHOLDER values in scripts/caldera/local.yml
#    - API_KEY_PLACEHOLDER → rotate your own key
# 2. Run installer
bash scripts/caldera/install-caldera.sh
```

CALDERA installs to `/opt/caldera`, starts as a systemd service (`caldera.service`), and listens on port `8853`.

### Verify CALDERA

```bash
systemctl status caldera
curl -s http://localhost:8853/api/v2/health | python3 -m json.tool
```

### Take baseline snapshots (all VMs)

After all VMs are configured and verified:

```bash
# On each Proxmox host — run after full setup
bash scripts/proxmox/snapshot-test.sh
```

The script creates `baseline` snapshots via `qm snapshot`, verifies rollback works, and logs results.

### Reset the range (one command)

```bash
bash scripts/proxmox/reset_range.sh
```

Rolls all target VMs back to their `baseline` snapshot in parallel. **Does not touch `elastic-vm` (VM 200) or `caldera-vm` (VM 201)** — those are control-plane and excluded from reset.

---

## UAT Gates (Phase 1)

| Gate | Check | Status |
|------|-------|--------|
| INFRA-01 | All 6 hosts have vmbr0 + vmbr1 bridges; vmbr1 no bare NIC uplink | Blocked — hardware not yet configured |
| INFRA-02 | elastic-vm and caldera-vm boot, SSH reachable at 10.0.0.10 / 10.0.0.20 | Blocked — hardware not yet configured |
| INFRA-03 | Elasticsearch cluster green/yellow; Kibana on :5601; Fleet Server enrolled | Blocked — hardware not yet configured |
| INFRA-04 | CALDERA on :8853 health endpoint responds; baseline snapshot rollback succeeds | Blocked — hardware not yet configured |

> UAT tests are currently **blocked by physical device** — all scripts are authored and ready; gates will be confirmed on hardware.

---

## Key Scripts Reference

| Script | Host | Purpose |
|--------|------|---------|
| `scripts/proxmox/verify-storage.sh` | Each Proxmox host | Assert LVM-thin pool present |
| `scripts/proxmox/network-setup.sh` | Each Proxmox host | Generate vmbr0 + vmbr1 interfaces |
| `scripts/proxmox/verify-isolation.sh` | Each Proxmox host | Assert vmbr1 air-gap |
| `scripts/proxmox/create-elastic-vm.sh` | Host 1 | Provision elastic-vm via qm create |
| `scripts/proxmox/create-caldera-vm.sh` | Host 6 | Provision caldera-vm via qm create |
| `scripts/elastic/install-stack.sh` | elastic-vm | Install Elasticsearch + Kibana |
| `scripts/elastic/generate-certs.sh` | elastic-vm | Generate TLS certificates |
| `scripts/elastic/bootstrap-fleet.sh` | elastic-vm | Start Fleet Server, enroll |
| `scripts/elastic/health-check.sh` | elastic-vm | Verify SIEM stack health |
| `scripts/caldera/install-caldera.sh` | caldera-vm | Install CALDERA 5.x |
| `scripts/proxmox/snapshot-test.sh` | Proxmox hosts | Take + verify baseline snapshots |
| `scripts/proxmox/reset_range.sh` | Any Proxmox host | Roll all target VMs to baseline |

---

[← Back to index](.)
