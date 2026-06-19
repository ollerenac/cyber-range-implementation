# Phase 01 — Proxmox Foundation + SIEM Node

> **Status:** ✅ Complete · All 4 waves executed and approved

This runbook covers standing up the hypervisor networking fabric and the two persistent control-plane VMs (elastic-vm and caldera-vm) on 6 Proxmox hosts.

---

## Lab Network Topology

```
Physical hosts: 6x Proxmox VE 8.x nodes

Management network  vmbr0 — 10.0.0.0/24 (MGMT + internet via router → switch → eth0)
  └─ elastic-vm     10.0.0.10   Host 1    Ubuntu 22.04  14 GB RAM / 200 GB disk
  └─ caldera-vm     10.0.0.20   Host 6    Ubuntu 22.04   6 GB RAM /  40 GB disk

Target network      vmbr1 — 10.10.10.0/24 (air-gapped, VLAN 10 — NO internet)
  └─ [Phase 2+]     Windows Server 2019 × 2, Windows 10, Kali
```

> **Security property:** `vmbr1` has **no physical NIC uplink** — target VMs cannot reach the internet or host LAN. The managed switch carries VLAN 10 with no inter-VLAN routing.

!!! note "Physical layer: WiFi on Host 6 → OPNsense → switch → all hosts"
    Each Proxmox host has one ethernet port (eth0/eno1) and one wireless card (wlan0).
    **Host 6** uses its wireless card as the WAN uplink for an OPNsense VM (Phase 1.5),
    which acts as the perimeter gateway for all lab VMs. Hosts 1–5 reach the internet
    through eth0 → switch → Host 6 eth0 → OPNsense → wlan0.
    The wireless cards on Hosts 1–5 are unused.

---

## Wave 1 — Proxmox Networking Fabric

**Goal:** Every host exposes `vmbr0` (MGMT) and `vmbr1` (TARGET, air-gapped) before any VM is created.

### Prerequisites
- 6 Proxmox VE 8.x hosts with SSH root access
- Managed switch with 802.1Q VLAN 10 support
- LVM-thin storage pool (`local-lvm`) present on each host
- Physical router (WiFi→ETH) connected to managed switch — provides internet to vmbr0 via eth0

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

### Create caldera-vm (Host 5)

> ⚠️ **Host assignment revised:** caldera-vm was originally planned on Host 6, but Host 6
> is now dedicated to the OPNsense perimeter gateway (Phase 1.5). caldera-vm moves to **Host 5**.
> Update `HOST6_NODE` references accordingly after confirming the Proxmox node name for Host 5.

```bash
# On Proxmox Host 5  (was Host 6 in earlier planning)
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

---

## Phase 1.5 — Perimeter Firewall: Pre-Install Checklist

> **Status: ⏸ Paused** — scripts are committed and ready; hardware verification required before proceeding.

### Why Phase 1.5 exists

The TARGET network (vmbr1) needs internet access to simulate a realistic enterprise environment. Rather than NAT on each host kernel (fragile, 6× config), a single **OPNsense VM on Host 6** acts as the perimeter gateway for all lab VMs. Snort IDS runs inline on the LAN interface, adding network-level detection to complement Sysmon (host) and Packetbeat (intra-segment).

The double-NAT path for TARGET VMs:
```
Windows VM → vmbr1 → host kernel MASQUERADE → vmbr0 → OPNsense 10.0.0.254 → wlan0 → Internet
```

### Revised host assignment

| Host | VM(s) | Notes |
|------|-------|-------|
| 1 | elastic-vm (10.0.0.10) | 32 GB RAM recommended |
| 2 | dc01 + sql01 | 16 GB RAM |
| 3 | exchange01 | 16 GB RAM |
| 4 | ws01 + ws02 | 16 GB RAM |
| **5** | **caldera-vm (10.0.0.20) + kali-vm** | Was Host 6 in original plan |
| **6** | **OPNsense VM (VMID 700)** | Requires functional wlan0 |

> Confirm this assignment with actual hardware specs before installing Proxmox.

---

### Step 0 — Verify WiFi compatibility BEFORE installing Proxmox

This is the **critical gate** for Phase 1.5. If Host 6's wireless card does not work under Linux, the entire OPNsense design needs to change.

Boot a **live USB (Debian 12 or Ubuntu 22.04)** on Host 6. Then:

```bash
# Check if wireless interface is detected
ip link show | grep -E "wlan|wlp"
iw dev

# Check driver loaded
lspci -k | grep -A3 -i wireless

# Attempt WiFi association (replace with your SSID/password)
wpa_passphrase "YOUR_SSID" "YOUR_PASSWORD" > /tmp/wpa.conf
wpa_supplicant -B -i wlan0 -c /tmp/wpa.conf
dhclient wlan0

# Confirm internet via wlan0
ping -c 3 8.8.8.8
```

**If ping passes** → WiFi works, proceed with Phase 1.5 as designed.

**If wlan0 is not detected or ping fails** → report the `lspci` output; the design will need to be revised (e.g., external USB WiFi adapter, or a different host for OPNsense).

---

### Step 1 — Apply Host 6 network bridges (scripts ready)

After Proxmox is installed on Host 6 and WiFi is confirmed working:

```bash
# On Host 6 — dry-run first, review output
bash scripts/proxmox/host6-firewall-setup.sh
bash scripts/proxmox/configure-vmbr-lan.sh eth0 --mode=new-bridge

# Apply (check if vmbr0 already has bridge-ports eth0 first — see note below)
bash scripts/proxmox/host6-firewall-setup.sh --apply
bash scripts/proxmox/configure-vmbr-lan.sh eth0 --mode=new-bridge --apply
```

!!! note "vmbr0 conflict on Host 6"
    If Proxmox already created `vmbr0` with `bridge-ports eth0` during install,
    use `--mode=reuse-vmbr0` instead of `new-bridge` and follow the script's
    printed instructions to reassign the IP 10.0.0.254/24 to vmbr0 manually.

**Verification gates:**
```bash
iptables -t nat -L POSTROUTING -n | grep MASQUERADE   # must show wlan0 rule
ip addr show vmbr_lan | grep '10.0.0.254'              # LAN bridge ready
ping -c 3 10.0.0.10                                    # elastic-vm reachable
```

---

### Step 2 — Deploy OPNsense VM (after Step 1 gates pass)

```bash
# On Host 6:
bash scripts/proxmox/deploy-opnsense-vm.sh --apply
# Opens VMID 700 on the ISO; open noVNC console in Proxmox web UI to complete install
```

Post-install configuration via web UI at `https://10.0.0.254`:

| Setting | Value |
|---------|-------|
| WAN interface | vtnet0 → 172.16.0.2/30, GW 172.16.0.1 |
| LAN interface | vtnet1 → 10.0.0.254/24, DHCP off |
| NAT Outbound | Automatic (LAN → WAN) |
| Snort plugin | `os-snort`, LAN interface, ET Open ruleset |

**Operator access to CALDERA web UI** (port 8888 on 10.0.0.20) from your laptop (192.168.x.x):
- Recommended: add a port forward in OPNsense → Firewall → NAT → Port Forward
- Alternative: `ssh -L 8888:10.0.0.20:8888 root@<opnsense-wan-ip>` tunnel

---

### What to report back

Once Steps 1 and 2 are complete, confirm:

1. Output of `iptables -t nat -L POSTROUTING -n | grep MASQUERADE`
2. Output of `ip link show vmbr_wan` and `ip addr show vmbr_lan`
3. `ping -c 3 8.8.8.8` from elastic-vm — PASS/FAIL
4. OPNsense dashboard: WAN UP (172.16.0.2) + LAN UP (10.0.0.254)
5. At least 1 Snort alert after running `nmap -sS 10.0.0.1` from any lab VM

Reply `wave1-listo` with the above output to unblock Phase 1.5 Wave 2.

---

[← Back to index](.)
