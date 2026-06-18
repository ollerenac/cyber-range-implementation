# scripts/proxmox — Wave 1 Operator Runbook

This directory contains the networking and storage setup scripts for the 6 Proxmox VE 8.x hosts
in the Cyber Range lab. Run these scripts on each physical host via SSH before creating any VMs.

---

## Scripts

| Script | Purpose |
|--------|---------|
| `verify-storage.sh` | Wave 0 gate: assert LVM-thin pool present (D-04) |
| `network-setup.sh` | Generate + apply vmbr0/vmbr1 bridge config |
| `verify-isolation.sh` | Wave 0 gate: assert vmbr1 has no bare NIC uplink (D-02) |
| `SWITCH-VLAN10.md` | Vendor-neutral managed switch VLAN 10 configuration steps |

---

## Wave 1 Operator Order (required sequence)

Run the following steps on **each of the 6 Proxmox hosts** (Host 1 through Host 6). Complete all
steps on a host before moving to the next host. Switch configuration (Step 5) is done once.

### Step 1: Verify LVM-thin storage (must pass before creating VMs)

```bash
# On each host — run locally or from the Proxmox shell via SSH
bash scripts/proxmox/verify-storage.sh
# Expected: [PASS] S-1 pvesm scan lvmthin pve: found 1 pool(s): pve/data
#           [PASS] S-2 storage.cfg contains lvmthin: stanza
```

If this fails: create the LVM-thin pool before continuing.
```bash
# Create thin pool manually (if not already present from Proxmox install):
lvcreate -L 100G -T pve/data
# Then register in Proxmox: Datacenter → Storage → Add → LVM-Thin
#   ID: local-lvm, Volume Group: pve, Thin Pool: data, Content: Disk image
```

### Step 2: Preview the bridge config (dry-run, no changes applied)

```bash
# Replace 10.0.0.X with the host's MGMT IP and 192.168.1.1 with your LAN gateway
# Replace eno1 with your host's actual physical NIC name (check: ip link show)
bash scripts/proxmox/network-setup.sh 10.0.0.1 192.168.1.1 eno1
```

Confirm the preview output shows:
- `vmbr0`: `bridge-ports eno1`, address `10.0.0.X/24`, gateway = your LAN gateway
- `vmbr1`: `bridge-ports eno1.10` (VLAN sub-interface), address `10.10.10.1/24`
- `iface eno1.10 inet manual` declared above vmbr1

**Never proceed if the preview shows `bridge-ports eno1` on vmbr1** — that would connect TARGET
traffic directly to the untagged LAN. The correct vmbr1 line is `bridge-ports eno1.10`.

### Step 3: Apply the bridge config

```bash
# --apply writes to /etc/network/interfaces (creates a timestamped backup first)
bash scripts/proxmox/network-setup.sh 10.0.0.1 192.168.1.1 eno1 --apply
```

Then reload the network configuration:
```bash
ifreload -a
# OR (fallback if ifreload is not available):
# systemctl restart networking
```

Verify bridges came up:
```bash
brctl show vmbr0 vmbr1
ip addr show vmbr0
ip addr show vmbr1
```

### Step 4: Run the isolation verification

```bash
bash scripts/proxmox/verify-isolation.sh
# Expected:
#   [PASS] A-1 vmbr1 bridge: exists on localhost
#   [PASS] A-2 vmbr1 bridge-ports: eno1.10 (VLAN sub-interface only) — isolation intact
```

### Step 5: Configure the managed switch (done once, not per-host)

See **SWITCH-VLAN10.md** for full vendor-neutral steps. Summary:
1. Create VLAN 10 named `TARGET`.
2. Configure each of the 6 host-facing switch ports as a trunk: native VLAN = LAN/MGMT, VLAN 10 tagged.
3. Confirm VLAN 10 has **no inter-VLAN routing / no L3 SVI** to the LAN.

### Step 6: Boot a test VM on vmbr1 and run the full isolation gate

Boot a minimal Linux test VM on any host's vmbr1 bridge with a static IP (e.g. 10.10.10.254):
```bash
# From inside the test VM:
bash scripts/proxmox/verify-isolation.sh --from-target-vm
# Expected:
#   [PASS] B-1 Internet reach (8.8.8.8): ping FAILED as expected — isolated from internet
#   [PASS] B-2 LAN MGMT reach (10.0.0.10): ping FAILED as expected — isolated from MGMT network
#   [PASS] B-3 vmbr1 host reach (10.10.10.1): ping SUCCEEDED — TARGET bridge functional
```

This test gate MUST pass on at least Host 1 and Host 6 before proceeding to Plan 02 (VM provisioning).

---

## Host-to-NIC Reference (D-NEW-09)

| Host | VMs | Recommended vmbr0 IP | Physical NIC (default) |
|------|-----|---------------------|------------------------|
| Host 1 | elastic-vm (Ubuntu 22.04, 14 GB RAM) | 10.0.0.1 | eno1 |
| Host 2 | dc01 + sql01 (WS2019) | 10.0.0.2 | eno1 |
| Host 3 | exchange01 (WS2019) | 10.0.0.3 | eno1 |
| Host 4 | ws01 + ws02 (Win10) | 10.0.0.4 | eno1 |
| Host 5 | SPARE (future IDS sensor) | 10.0.0.5 | eno1 |
| Host 6 | caldera-vm + kali (Ubuntu 22.04 / Kali) | 10.0.0.6 | eno1 |

> The physical NIC name may differ on your hardware. Check with `ip link show` before running
> network-setup.sh. Common alternatives: `enp2s0`, `enp3s0`, `eth0`, `em1`.

**VM MGMT IPs (10.0.0.0/24) — for reference only, not host bridge IPs:**

| VM | MGMT IP | Note |
|----|---------|------|
| elastic-vm | 10.0.0.10 | LOCKED — Fleet Server TLS cert SAN = IP:10.0.0.10 (D-12) |
| caldera-vm | 10.0.0.20 | |
| dc01 | 10.0.0.11 | |
| exchange01 | 10.0.0.12 | |
| sql01 | 10.0.0.13 | |
| ws01 | 10.0.0.14 | |
| ws02 | 10.0.0.15 | |
| kali | 10.0.0.16 | |

---

## Network Architecture Summary

```
MANAGED SWITCH
  Port 1 → Host 1 (elastic-vm)   ─ trunk: native=LAN, tagged=VLAN10
  Port 2 → Host 2 (dc01+sql01)   ─ trunk: native=LAN, tagged=VLAN10
  Port 3 → Host 3 (exchange01)   ─ trunk: native=LAN, tagged=VLAN10
  Port 4 → Host 4 (ws01+ws02)    ─ trunk: native=LAN, tagged=VLAN10
  Port 5 → Host 5 (SPARE)        ─ trunk: native=LAN, tagged=VLAN10
  Port 6 → Host 6 (caldera+kali) ─ trunk: native=LAN, tagged=VLAN10
  VLAN 10: NO inter-VLAN routing to LAN (D-02)

EACH PROXMOX HOST:
  eno1 (physical NIC)
  ├── vmbr0: 10.0.0.X/24  (MGMT — untagged on LAN VLAN)
  └── eno1.10 → vmbr1: 10.10.10.1/24  (TARGET — VLAN 10 tagged)
```

---

## Troubleshooting Quick Reference

| Problem | Check | Fix |
|---------|-------|-----|
| ifreload fails | `journalctl -xe` | Check /etc/network/interfaces syntax with `ifup --syntax-check` |
| vmbr0 has no IP after reload | gateway missing or NIC name wrong | Re-run network-setup.sh with correct NIC name |
| vmbr1 shows bare NIC in `brctl show` | Wrong bridge-ports in config | Verify network-setup.sh used `eno1.10` not `eno1` for vmbr1 |
| Cross-host TARGET ping fails | VLAN 10 not trunked on switch | Check SWITCH-VLAN10.md Step 2 |
| verify-storage.sh fails | LVM-thin pool not created | See Step 1 remediation above |
| ifreload command not found | Proxmox ifupdown2 not installed | `apt install ifupdown2` or use `systemctl restart networking` |
