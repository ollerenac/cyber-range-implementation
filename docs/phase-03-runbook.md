<!-- generated-by: gsd-doc-writer -->
# Phase 03 — Full Telemetry Pipeline + Reset

> **Status:** 🔄 In Progress — Wave 1 complete (scripts committed and merged); Wave 2 pending lab access

This runbook covers provisioning the Kali attacker VM, configuring the SSH infrastructure used by the reset mechanism, merging Sysmon XML configs, pre-configuring Kibana Fleet policies with Elastic Defend in DETECT mode, and enrolling Elastic Agents on all target VMs.

---

## Phase Overview

| Wave | Description | Status |
|------|-------------|--------|
| Wave 1A | Kali VM provisioning + SSH key infrastructure | Scripts complete — operator execution pending |
| Wave 1B | Sysmon XML config merge + Fleet policy pre-configuration | Script complete — human steps pending |
| Wave 2 | Elastic Agent enrollment on all Windows VMs and Kali | Pending Wave 1 completion |
| Wave 3 | Reset mechanism (clean_state snapshot + reset_range.sh) + end-to-end verification | Pending Wave 2 completion |

---

## Wave 1A — Kali VM Provisioning + SSH Infrastructure

**Goal:** Kali Linux VM running on Host 6, reachable via SSH from elastic-vm, with all red team tools available and passwordless SSH from elastic-vm to all four Proxmox hosts.

### Prerequisites

- Phase 1 and Phase 2 complete — all five Windows VMs domain-joined and healthy
- Kali Linux QEMU image downloaded from [kali.org](https://www.kali.org/get-kali/#kali-virtual-machines) → select "QEMU (64-bit)"
- Image file (`kali-linux-YYYY.X-qemu-amd64.qcow2`) copied to Host 6 at `/var/lib/vz/template/iso/`

### Step A1 — Create the Kali VM on Host 6

```bash
# SSH to Proxmox Host 6
ssh root@host6

# Run the creation script
bash /path/to/scripts/proxmox/create-kali-vm.sh \
    601 \
    10.0.0.1 \
    local-lvm \
    /var/lib/vz/template/iso/kali-linux-2025.X-qemu-amd64.qcow2 \
    /root/.ssh/id_rsa.pub
```

The script creates VMID 601 with:
- 4 GB RAM · 2 vCPU · 80 GB disk
- net0 → vmbr1 (TARGET: 10.10.10.200/24, no gateway)
- net1 → vmbr0 (MGMT: 10.0.0.16/24, gw 10.0.0.1)

A confirmation prompt displays the VM spec before creating anything. Type `y` to proceed.

!!! warning
    Kali pre-built QEMU images are full desktop installations (XFCE) and **do not use cloud-init**.
    Do not pass `--ipconfig0` or `--cicustom` flags. Static IP configuration is done manually
    via the Proxmox console after first boot — see Step A3.

### Step A2 — Start the VM

```bash
# On Host 6
qm start 601
```

### Step A3 — Configure static IPs via Proxmox console

Open the Proxmox web UI → Host 6 → VM 601 → Console. Log in with the default Kali credentials (`kali` / `kali`).

First, identify network interface names:

```bash
ip link
# Typical output shows eth0 (net0/vmbr1/TARGET) and eth1 (net1/vmbr0/MGMT)
# Your interface names may differ (ens18, ens19, etc.) — use the names shown by ip link
```

Configure static IPs using NetworkManager (nmcli):

```bash
sudo nmcli connection add type ethernet ifname eth0 con-name TARGET \
    ip4 10.10.10.200/24
sudo nmcli connection add type ethernet ifname eth1 con-name MGMT \
    ip4 10.0.0.16/24 gw4 10.0.0.1
sudo nmcli connection up TARGET
sudo nmcli connection up MGMT
```

Alternatively, if using ifupdown (`/etc/network/interfaces`):

```bash
# Edit /etc/network/interfaces and add:
auto eth0
iface eth0 inet static
    address 10.10.10.200
    netmask 255.255.255.0

auto eth1
iface eth1 inet static
    address 10.0.0.16
    netmask 255.255.255.0
    gateway 10.0.0.1

# Then restart networking:
sudo systemctl restart networking
```

### Step A4 — Verify MGMT IP reachable from elastic-vm

```bash
# From elastic-vm (10.0.0.10)
ping -c 3 10.0.0.16
# Expected: 3 packets received, 0% packet loss
```

### Step A5 — Change Kali default credentials

!!! warning
    The default `kali` / `kali` credentials **must be changed** before taking the `clean_state` snapshot.
    Leaving the default password on the attacker VM would allow any VM restored from snapshot to be accessed without authentication.

In the Kali console:

```bash
passwd kali
# Set a strong password — record it in .planning/secrets/PASSWORDS.md under "kali-vm"
```

### Step A6 — Enable SSH on Kali

```bash
sudo systemctl enable ssh
sudo systemctl start ssh
# Verify:
sudo systemctl status ssh
```

### Step A7 — Set up SSH key from elastic-vm to Kali

```bash
# From elastic-vm (10.0.0.10)
ssh-copy-id kali@10.0.0.16

# Verify passwordless access:
ssh kali@10.0.0.16 "hostname && ip addr show | grep -E '10\.0\.0\.16|10\.10\.10\.200'"
# Expected: "kali" and both IP addresses shown
```

### Step A8 — Generate ed25519 key on elastic-vm for Proxmox host fan-out

The reset mechanism (`reset_range.sh`) runs `qm rollback` on each Proxmox host via SSH. elastic-vm must have passwordless root SSH to all four target-VM hosts.

```bash
# On elastic-vm (10.0.0.10)
ssh-keygen -t ed25519 -C "elastic-vm-reset-fanout" -f ~/.ssh/id_ed25519_proxmox
# Press Enter twice for no passphrase
```

### Step A9 — Enroll elastic-vm SSH key on Proxmox hosts 2, 3, 4, and 6

```bash
# From elastic-vm
ssh-copy-id -i ~/.ssh/id_ed25519_proxmox.pub root@host2
ssh-copy-id -i ~/.ssh/id_ed25519_proxmox.pub root@host3
ssh-copy-id -i ~/.ssh/id_ed25519_proxmox.pub root@host4
ssh-copy-id -i ~/.ssh/id_ed25519_proxmox.pub root@host6
```

If `host2` / `host3` / `host4` / `host6` are not resolving, add entries to `/etc/hosts` on elastic-vm first:

```bash
# On elastic-vm — append to /etc/hosts (substitute actual host IPs)
echo "HOST2_IP  host2" | sudo tee -a /etc/hosts
echo "HOST3_IP  host3" | sudo tee -a /etc/hosts
echo "HOST4_IP  host4" | sudo tee -a /etc/hosts
echo "HOST6_IP  host6" | sudo tee -a /etc/hosts
```

### Step A10 — Verify Proxmox host SSH fan-out

```bash
# From elastic-vm — verify all four hosts accept passwordless root SSH
for h in host2 host3 host4 host6; do
    echo -n "$h: "
    ssh -i ~/.ssh/id_ed25519_proxmox root@$h "qm list | head -3"
done
# Expected: qm list output for each host (dc01/sql01 on host2, exchange01 on host3, etc.)
```

### Step A11 — Install BloodHound CE and stage Mimikatz

SSH into Kali from elastic-vm:

```bash
ssh kali@10.0.0.16
```

Install Docker if not present:

```bash
sudo apt-get update && sudo apt-get install -y docker.io docker-compose
sudo systemctl enable docker && sudo systemctl start docker
sudo usermod -aG docker kali
# Log out and back in for the group change to take effect
```

Install BloodHound Community Edition:

```bash
mkdir -p ~/bloodhound && cd ~/bloodhound
curl -L https://ghcr.io/specterops/bloodhound/docker-compose -o docker-compose.yml
sudo docker compose up -d
# BloodHound CE UI accessible at http://10.0.0.16:8080
# Configure admin credentials on first login
```

Stage Mimikatz Windows PE at `/opt/mimikatz/`:

```bash
sudo mkdir -p /opt/mimikatz
# Download mimikatz_trunk.zip from https://github.com/gentilkiwi/mimikatz/releases
# Then unzip:
sudo unzip mimikatz_trunk.zip -d /opt/mimikatz/
ls /opt/mimikatz/x64/mimikatz.exe
# Expected: binary present
```

Verify pre-installed red team tools:

```bash
msfconsole -q -x "version; exit" 2>&1 | grep "Framework"
impacket-smbclient --version 2>&1 | head -1
nmap --version | head -1
ls /opt/mimikatz/x64/mimikatz.exe
# Expected: each command returns version info, no "command not found"
```

### Wave 1A Verification Checklist

Run these from elastic-vm to confirm Wave 1A is complete:

```bash
# 1. Kali VMID 601 config on Host 6
ssh root@host6 "qm config 601 | grep -E '^name|^memory|^net'"
# Expected: name: kali, memory: 4096, net0 bridge=vmbr1, net1 bridge=vmbr0

# 2. Kali SSH reachable without password
ssh kali@10.0.0.16 "hostname"
# Expected: kali

# 3. Proxmox host fan-out
for h in host2 host3 host4 host6; do echo -n "$h: "; ssh root@$h "qm list | wc -l"; done
# Expected: positive VM count for each host

# 4. BloodHound CE running on Kali
ssh kali@10.0.0.16 "sudo docker ps | grep bloodhound"

# 5. Red team tools present
ssh kali@10.0.0.16 "which msfconsole impacket-smbclient nmap && ls /opt/mimikatz/x64/mimikatz.exe"
```

---

## Wave 1B — Sysmon Config Merge + Fleet Policy Pre-Configuration

**Goal:** Two merged Sysmon XML configs committed to the repo, installers staged on elastic-vm's HTTP server at port 8080, and Fleet policies `windows-target` and `kali-linux` created in Kibana with Elastic Defend in DETECT mode — all done before any agent enrolls.

!!! warning
    **Elastic Defend MUST be set to DETECT mode in Fleet policies BEFORE the first agent enrolls.**
    Post-enrollment mode changes require re-pushing policy to all agents. Setting DETECT mode
    after agents are already enrolled risks silently running in PREVENT mode during emulation runs,
    which terminates red team implants before telemetry is generated.

### Part B1 — Merge Sysmon XML Configs

Run on any machine that has PowerShell or `pwsh` installed (Linux, macOS, or Windows).

**Step B1.1 — Clone sysmon-modular:**

```bash
git clone https://github.com/olafhartong/sysmon-modular ~/sysmon-modular
cd ~/sysmon-modular
```

**Step B1.2 — Merge server config** (EventIDs 1, 3, 7, 10, 11, 12/13/14, 17/18, 22 — covers dc01, exchange01, sql01):

```powershell
pwsh -Command "
  cd ~/sysmon-modular
  . ./Merge-SysmonXml.ps1
  \$ServerModules = @(
    '1_process_creation', '3_network_connection_initiated', '7_image_load',
    '10_process_access', '11_file_create', '12_13_14_registry_event',
    '17_18_pipe_event', '22_dns_query'
  )
  \$paths = \$ServerModules | ForEach-Object { Get-ChildItem \"\$_/*.xml\" }
  Merge-AllSysmonXml -Path \$paths -AsString | Out-File sysmon-server.xml
"
cp ~/sysmon-modular/sysmon-server.xml /path/to/repo/scripts/windows/sysmon/sysmon-server.xml
```

**Step B1.3 — Merge workstation config** (server EventIDs + 15, 23, 25, 26 — covers ws01 and ws02):

```powershell
pwsh -Command "
  cd ~/sysmon-modular
  . ./Merge-SysmonXml.ps1
  \$WorkstationModules = @(
    '1_process_creation', '3_network_connection_initiated', '7_image_load',
    '10_process_access', '11_file_create', '12_13_14_registry_event',
    '17_18_pipe_event', '22_dns_query',
    '15_file_create_stream_hash', '23_file_delete',
    '25_process_tampering', '26_file_delete_detected'
  )
  \$paths = \$WorkstationModules | ForEach-Object { Get-ChildItem \"\$_/*.xml\" }
  Merge-AllSysmonXml -Path \$paths -AsString | Out-File sysmon-workstation.xml
"
cp ~/sysmon-modular/sysmon-workstation.xml /path/to/repo/scripts/windows/sysmon/sysmon-workstation.xml
```

**Step B1.4 — Verify and commit the XML configs:**

```bash
head -5 scripts/windows/sysmon/sysmon-server.xml
grep -c "EventID" scripts/windows/sysmon/sysmon-server.xml
grep -c "EventID" scripts/windows/sysmon/sysmon-workstation.xml
# Expected: sysmon-workstation.xml has MORE EventID references than sysmon-server.xml

git add scripts/windows/sysmon/sysmon-server.xml scripts/windows/sysmon/sysmon-workstation.xml
git commit -m "feat(03-02): add merged Sysmon XML configs for server and workstation roles"
```

### Part B2 — Stage Installers on elastic-vm HTTP Server

**Step B2.1 — Create staging directory on elastic-vm:**

```bash
ssh elastic@10.0.0.10 "mkdir -p /opt/elastic-stage"
```

**Step B2.2 — Download and copy Elastic Agent 8.19.16 Windows installer:**

```bash
# Download URL:
# https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-8.19.16-windows-x86_64.zip
scp elastic-agent-8.19.16-windows-x86_64.zip elastic@10.0.0.10:/opt/elastic-stage/
```

!!! note
    Pin the Elastic Agent version to **8.19.16** — this must match the Elasticsearch and Kibana version running on elastic-vm. Using a mismatched version causes Fleet enrollment failures.

**Step B2.3 — Download and copy Sysmon64.exe:**

```bash
# Download URL: https://download.sysinternals.com/files/Sysmon.zip
# Unzip to extract Sysmon64.exe, then:
scp Sysmon64.exe elastic@10.0.0.10:/opt/elastic-stage/
```

**Step B2.4 — Copy Sysmon XML configs to the staging directory:**

```bash
scp scripts/windows/sysmon/sysmon-server.xml elastic@10.0.0.10:/opt/elastic-stage/
scp scripts/windows/sysmon/sysmon-workstation.xml elastic@10.0.0.10:/opt/elastic-stage/
```

**Step B2.5 — Start the HTTP file server on elastic-vm port 8080:**

```bash
ssh elastic@10.0.0.10 "
  cd /opt/elastic-stage
  nohup python3 -m http.server 8080 > /tmp/http-server.log 2>&1 &
  echo \$! > /tmp/http-server.pid
  sleep 1 && curl -s http://127.0.0.1:8080/ | grep 'elastic-agent'
"
# Expected: HTML listing showing elastic-agent-8.19.16-windows-x86_64.zip
```

**Step B2.6 — Verify download works from a Windows VM** (e.g., dc01):

```powershell
Invoke-WebRequest -Uri "http://10.0.0.10:8080/elastic-agent-8.19.16-windows-x86_64.zip" `
    -OutFile "C:\Temp\test.zip"
(Get-Item C:\Temp\test.zip).Length
# Expected: file size > 100 MB
```

### Part B3 — Create Fleet Policies in Kibana

Open Kibana at `https://10.0.0.10:5601` → Stack Management → Fleet.

**Step B3.1 — Create the `windows-target` policy:**

```
Fleet → Agent policies → Create agent policy
Name: windows-target
Description: dc01, exchange01, sql01, ws01, ws02 — Elastic Defend DETECT + Sysmon + Packetbeat
Click "Create agent policy"
```

**Step B3.2 — Add Elastic Defend in DETECT mode (critical — D-13):**

```
windows-target policy → Add integration → search "Elastic Defend"
Click Elastic Defend → Add Elastic Defend
  Protection level: Detect  ← NOT Prevent
  Malware protection: Detect
  Memory protection: Detect
  Behavior protection: Detect
Click Save integration
Verify: policy view shows Elastic Defend badge labelled "Detect" (not "Prevent")
```

!!! warning
    If you accidentally set PREVENT mode, Elastic Defend will terminate implants the moment they are
    launched during an emulation run. No telemetry will be generated. Set DETECT before any agent
    connects to this policy.

**Step B3.3 — Add Windows integration (Sysmon channel):**

```
windows-target policy → Add integration → search "Windows"
Click Windows → Add Windows
  Enable "Windows Event Log" integration
  Add channel: Microsoft-Windows-Sysmon/Operational
  Also enable: Security, System channels
Click Save integration
```

**Step B3.4 — Add Network Packet Capture / Packetbeat:**

```
windows-target policy → Add integration → search "Network Packet Capture"
Click Network Packet Capture → Add Network Packet Capture
  Enable the following protocols only:
    DNS: enabled
    HTTP: enabled  (ports 80, 8080, 8088)
    SMB: enabled
    TLS: enabled  (JA3 fingerprinting: on)
    Kerberos: enabled  (port 88)
    MSSQL: enabled  (port 1433)
    All other protocols: disabled
Click Save integration
```

**Step B3.5 — Create the `kali-linux` policy:**

```
Fleet → Agent policies → Create agent policy
Name: kali-linux
Description: Kali attacker VM — Elastic Defend Linux DETECT + Packetbeat
Click "Create agent policy"
```

**Step B3.6 — Add Elastic Defend Linux in DETECT mode to `kali-linux`:**

```
kali-linux policy → Add integration → search "Elastic Defend"
Add Elastic Defend
  Protection level: Detect  ← NOT Prevent
  All protection modes: Detect
Click Save integration
Verify: policy shows Elastic Defend badge "Detect"
```

**Step B3.7 — Add Network Packet Capture to `kali-linux`:**

```
kali-linux policy → Add integration → search "Network Packet Capture"
Enable: DNS, HTTP, SMB, TLS
Click Save integration
```

**Step B3.8 — Generate enrollment tokens:**

```
Fleet → Enrollment tokens → Create enrollment token
  Policy: windows-target
  Copy the token value
  Store in .planning/secrets/PASSWORDS.md under "Fleet enrollment token (windows-target)"

Fleet → Enrollment tokens → Create enrollment token
  Policy: kali-linux
  Copy the token value
  Store in .planning/secrets/PASSWORDS.md under "Fleet enrollment token (kali-linux)"
```

!!! warning
    **Never commit enrollment tokens to git.** They grant enrollment rights to any agent that presents them.
    Store only in `.planning/secrets/PASSWORDS.md` (which is gitignored).

**Step B3.9 — Verify both policies:**

```
Fleet → Agent policies
  Confirm "windows-target" and "kali-linux" both appear
  Click windows-target → Elastic Defend shows "Detect" badge
  Click kali-linux → Elastic Defend shows "Detect" badge
```

Or verify via the Kibana API:

```bash
curl -sk -u "elastic:${ELASTIC_PW}" -H "kbn-xsrf: true" \
  "https://10.0.0.10:5601/api/fleet/agent_policies?full=true" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print([p['name'] for p in d['items']])"
# Expected output includes: windows-target, kali-linux
```

---

## Wave 2 — Elastic Agent Enrollment

> **Status:** Pending — requires Wave 1A and Wave 1B to be complete (Kali MGMT IP reachable, Fleet policies with DETECT mode created, enrollment tokens in PASSWORDS.md, HTTP staging server running on elastic-vm:8080).

The enrollment script `scripts/windows/setup/09-elastic-agent.ps1` is written and ready. It will be delivered to each Windows VM via WinRM by `enroll-agents.sh` (plan 03-03, not yet authored).

For each Windows VM, `09-elastic-agent.ps1` will:
1. Check for Npcap (`wpcap.dll`) — warns if absent, relies on elastic-agent bundled OEM auto-install
2. Run idempotency guard — uninstalls any existing Elastic Agent before re-enrolling
3. Download `elastic-agent-8.19.16-windows-x86_64.zip` from `http://10.0.0.10:8080`
4. Install and enroll with Fleet Server at `https://10.0.0.10:8220` using the windows-target enrollment token
5. Deploy Sysmon with the appropriate XML config (`sysmon-server.xml` for dc01/exchange01/sql01; `sysmon-workstation.xml` for ws01/ws02)
6. Verify the Elastic Agent service is running

!!! note
    The script accepts `-VmRole` (`server` or `workstation`) and `-FleetToken` as mandatory parameters.
    These are injected by the calling `enroll-agents.sh` script — do not run `09-elastic-agent.ps1`
    interactively without providing both parameters.

---

## Wave 3 — Reset Mechanism + End-to-End Verification

> **Status:** Pending — depends on Wave 2 completion (all agents Healthy in Fleet, telemetry flowing into Elasticsearch).

Wave 3 will cover:
- Taking the `clean_state` snapshot on all seven target VMs (dc01, exchange01, sql01, ws01, ws02, kali) after Elastic Agents are enrolled and Sysmon is running
- Verifying `reset_range.sh` rolls all VMs back to `clean_state` in under 5 minutes
- Running the end-to-end smoke test: one APT29 technique via CALDERA → verify detection alert fires in Kibana within 5 minutes
- Documenting the operator workflow: run scenario → observe telemetry → reset → repeat

---

## Key Scripts Reference

| Script | Run on | Purpose |
|--------|--------|---------|
| `scripts/proxmox/create-kali-vm.sh` | Proxmox Host 6 | Provision Kali VM (VMID 601), dual-NIC, 80 GB disk |
| `scripts/windows/setup/09-elastic-agent.ps1` | elastic-vm → Windows VMs via WinRM | Install + enroll Elastic Agent + deploy Sysmon |
| `scripts/proxmox/reset_range.sh` | elastic-vm | Roll all target VMs back to clean_state snapshot |
| `scripts/proxmox/snapshot-test.sh` | Proxmox hosts | Take + verify baseline snapshots |

---

[← Back to index](.)
