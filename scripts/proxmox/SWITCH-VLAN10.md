# Managed Switch — VLAN 10 Configuration Guide

**Purpose:** Configure the managed switch to carry VLAN 10 (TARGET network) tagged on the 6 trunk
ports that face the Proxmox hosts. VLAN 10 must have **no Layer 3 SVI / no inter-VLAN routing to
the LAN** — this is the switch-level half of the D-02 air-gap.

> This document is vendor-neutral. The exact CLI syntax differs by switch model. Concrete
> examples are given for Cisco IOS-style CLI and for a generic web-UI managed switch. Adapt
> to your specific switch (Ubiquiti, Netgear, TP-Link Omada, Cisco SG, HPE Aruba, etc.).

---

## Requirements Summary (D-01, D-02)

| Requirement | Switch Setting |
|-------------|----------------|
| VLAN 10 exists and is named TARGET | Create VLAN 10 with name "TARGET" |
| Each of the 6 host-facing ports carries VLAN 10 tagged | Configure ports as trunk; native VLAN = LAN/MGMT VLAN; VLAN 10 tagged |
| VMs on VLAN 10 can reach other hosts' VMs on VLAN 10 | VLAN 10 in the allowed VLANs list on all 6 trunk ports |
| VMs on VLAN 10 CANNOT reach the LAN or the internet | No Layer 3 SVI for VLAN 10; inter-VLAN routing from VLAN 10 to LAN disabled |
| MGMT traffic (vmbr0) continues normally | LAN/MGMT VLAN carries on the same trunk ports as native/untagged |

---

## Step 1: Create VLAN 10

Create VLAN 10 on the switch and name it "TARGET" so it is recognizable in switch dashboards.

### Cisco IOS-style CLI
```
enable
configure terminal

! Create VLAN 10 named TARGET
vlan 10
 name TARGET
exit
```

### Web-UI managed switch (generic)
1. Log in to the switch management interface.
2. Navigate to **VLAN** → **VLAN Management** (or **802.1Q VLAN**).
3. Click **Add** or **Create VLAN**.
4. Set VLAN ID = `10`, Name = `TARGET`.
5. Save.

---

## Step 2: Configure Each Host-Facing Port as a Trunk

Each of the 6 Proxmox host physical NICs connects to a dedicated switch port. Configure each of
these 6 ports as a **trunk port** that:
- Carries the **native/untagged VLAN** = your LAN/MGMT VLAN (e.g. VLAN 1 or your existing LAN VLAN)
- Carries **VLAN 10 tagged**

This allows a single cable from each host to carry both:
- Untagged MGMT traffic (Proxmox host management, elastic-agent enrollment via vmbr0)
- VLAN 10 tagged TARGET traffic (vmbr1, Proxmox strips the tag for VMs attached to vmbr1)

### Cisco IOS-style CLI

Replace `GigabitEthernet0/1` through `GigabitEthernet0/6` with the actual switch interfaces
connected to your 6 Proxmox hosts. Replace `1` with your actual LAN/MGMT VLAN if it is not VLAN 1.

```
configure terminal

! Host 1 (elastic-vm host) — trunk port
interface GigabitEthernet0/1
 description "Proxmox-Host-1"
 switchport mode trunk
 switchport trunk native vlan 1
 switchport trunk allowed vlan 1,10
exit

! Host 2
interface GigabitEthernet0/2
 description "Proxmox-Host-2"
 switchport mode trunk
 switchport trunk native vlan 1
 switchport trunk allowed vlan 1,10
exit

! Host 3
interface GigabitEthernet0/3
 description "Proxmox-Host-3"
 switchport mode trunk
 switchport trunk native vlan 1
 switchport trunk allowed vlan 1,10
exit

! Host 4
interface GigabitEthernet0/4
 description "Proxmox-Host-4"
 switchport mode trunk
 switchport trunk native vlan 1
 switchport trunk allowed vlan 1,10
exit

! Host 5 (SPARE — future IDS sensor)
interface GigabitEthernet0/5
 description "Proxmox-Host-5"
 switchport mode trunk
 switchport trunk native vlan 1
 switchport trunk allowed vlan 1,10
exit

! Host 6 (caldera-vm + kali host)
interface GigabitEthernet0/6
 description "Proxmox-Host-6"
 switchport mode trunk
 switchport trunk native vlan 1
 switchport trunk allowed vlan 1,10
exit

write memory
```

### Web-UI managed switch (generic)

1. Navigate to **VLAN** → **Port VLAN** or **802.1Q Port Configuration**.
2. For each of the 6 host-facing ports, set:
   - **Port mode**: Trunk (or "General" / "Hybrid" depending on vendor terminology)
   - **Native VLAN** (also called "PVID" or "Untagged VLAN"): your LAN/MGMT VLAN (e.g. 1)
   - **Tagged VLANs**: add VLAN 10 as tagged
3. Save and apply.

---

## Step 3: Disable Inter-VLAN Routing for VLAN 10 (CRITICAL — D-02)

This is the most important step. VLAN 10 must be a **Layer 2 segment only** — it must NOT have
a Layer 3 SVI (Switched Virtual Interface) that routes to the LAN VLAN or to the internet.

If VLAN 10 gets a SVI with a routed path to the LAN, TARGET VMs can reach the internet and
the host LAN — this completely defeats the air-gap purpose of the cyber range.

### Cisco IOS-style CLI — ensure no SVI exists

```
configure terminal

! Verify no VLAN 10 interface exists (this command should show nothing or not be present)
! show run | section interface Vlan10

! If a VLAN 10 interface exists, remove it:
no interface Vlan10

! If your switch/router has inter-VLAN routing enabled globally,
! do NOT add VLAN 10 to the routing table.

! On Layer 3 managed switches — explicitly prevent routing for VLAN 10:
! (method depends on switch OS; example for IOS-based L3 switch)
interface Vlan10
 no ip address
 shutdown
exit
```

### Web-UI managed switch (generic)

1. Navigate to **Routing** → **VLAN Interface** or **IP Interface** (Layer 3 settings).
2. Confirm that VLAN 10 does **NOT** appear in the IP interface list.
3. If it does, delete the VLAN 10 IP interface.
4. If your switch has a routing table, verify VLAN 10 is not listed as a directly connected route.

**Tip for simple managed switches (TP-Link, Netgear Smart, Ubiquiti):** These switches are
typically Layer 2 only and do not perform inter-VLAN routing by default. Confirm by checking
if your switch has a "Routing" or "IP Interface" menu — if it does not, VLAN 10 is already
L2-only. If it does, follow the steps above.

---

## Step 4: Verify the Configuration

After applying the switch configuration, verify from two angles:

### Switch-side verification

```
! Cisco IOS — show VLAN membership
show vlan id 10
! Expected: VLAN 10 active, ports 0/1 through 0/6 listed as trunk members

! Confirm no SVI
show ip interface brief | include Vlan10
! Expected: no output (or: "Vlan10   unassigned   YES unset  administratively down")
```

### Host-side verification (from inside a vmbr1 test VM)

Boot a minimal Linux VM on vmbr1 with a static IP (e.g. 10.10.10.254) and run:

```bash
# From inside the test VM on vmbr1 (10.10.10.254):

# Must FAIL — internet must be unreachable from TARGET VLAN
ping -c 3 -W 2 8.8.8.8
# Expected: 100% packet loss / Destination Host Unreachable

# Must FAIL — LAN/MGMT must be unreachable from TARGET VLAN
ping -c 3 -W 2 10.0.0.10
# Expected: 100% packet loss

# Must SUCCEED — Proxmox host vmbr1 bridge address is reachable
ping -c 3 -W 2 10.10.10.1
# Expected: 3 packets received, 0% packet loss

# Automated gate (from the lab scripts):
bash scripts/proxmox/verify-isolation.sh --from-target-vm
```

**Cross-host TARGET connectivity test** (from test VM on Host 1 to test VM on Host 6):
```bash
# Boot a second test VM on Host 6 vmbr1 at 10.10.10.253
ping -c 3 -W 2 10.10.10.253
# Expected: 3 packets received — VLAN 10 trunked correctly across both hosts
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `ping 8.8.8.8` succeeds from vmbr1 VM | VLAN 10 SVI exists with routed path to LAN | Remove VLAN 10 IP interface on switch; check default route |
| `ping 10.10.10.1` fails from vmbr1 VM | VLAN 10 not trunked to this port | Re-check trunk allowed VLANs; confirm `switchport trunk allowed vlan 1,10` |
| Cross-host ping (Host 1 → Host 6) fails | VLAN 10 not in trunk on one of the ports | Verify both host-facing ports allow VLAN 10 tagged |
| vmbr1 VM gets DHCP from LAN | Native VLAN misconfigured — VLAN 10 traffic sent untagged on LAN VLAN | Verify port is in trunk mode with correct native VLAN; vmbr1 DHCP should not exist |
| `brctl show vmbr1` shows bare NIC name | network-setup.sh generated wrong config | Re-run `bash network-setup.sh --apply` and verify `bridge-ports eno1.10` in /etc/network/interfaces |

---

*Reference: D-01 (VLAN 10 carries TARGET), D-02 (vmbr1 no physical uplink, VLAN 10 no inter-VLAN routing)*
*Source: https://pve.proxmox.com/wiki/Network_Configuration [VERIFIED]*
