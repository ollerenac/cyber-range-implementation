#!/usr/bin/env bash
# =============================================================================
# create-kali-vm.sh — Provision kali VM on Host 6 (Proxmox)
#
# LOCKED SPECS (do NOT change without updating D-01 and D-NEW-09 in 03-CONTEXT.md):
#   VMID: 601         — Host 6 (alongside caldera-vm VMID ~600)
#   RAM:  4096 MiB   (4 GB — D-NEW-09; Host 6: caldera-vm 6 GB + kali 4 GB = 10 GB)
#   Disk: 80 GB       (D-NEW-09 — Kali tooling + BloodHound CE Docker + Metasploit data)
#   Cores: 2
#   net0: vmbr1       (TARGET NIC — 10.10.10.200/24, no gateway; configured inside VM)
#   net1: vmbr0       (MGMT NIC  — 10.0.0.16/24, gw 10.0.0.1; configured inside VM)
#
# HOST LAYOUT (D-NEW-09):
#   Host 6: caldera-vm (600, 6 GB) + kali (601, 4 GB) = 10 GB total
#   Within 16 GB physical ceiling.
#
# NETWORK CONFIG NOTE:
#   Kali pre-built qcow2 images are FULL DESKTOP installations (XFCE).
#   They do NOT use cloud-init — configure IPs inside the VM after first boot.
#   Use the Proxmox console for initial network setup (Pitfall 3, 03-RESEARCH.md).
#   IPs configured manually via Proxmox console after first boot.
#   See Task 2 checkpoint for step-by-step console instructions.
#
# DOWNLOAD URL for Kali qcow2:
#   https://www.kali.org/get-kali/#kali-virtual-machines → QEMU (64-bit)
#   File: kali-linux-YYYY.X-qemu-amd64.qcow2
#   Recommended: copy to root@host6:/var/lib/vz/template/iso/ before running
#
# DEFAULT CREDENTIALS:
#   kali / kali
#   MUST be changed before taking the clean_state snapshot (RESET-01 requirement).
#   See Task 2 checkpoint, Step 5 — change via: passwd kali
#
# POST-IMPORT TOOLS (D-02):
#   BloodHound CE and Mimikatz staging run INSIDE Kali after boot,
#   NOT via this script. See Task 2 checkpoint for installation steps.
#   Metasploit, Nmap, and Impacket are pre-installed in the Kali QEMU image.
#
# ROLE: Attacker platform — Kali is the red team operator's machine.
#   Included in clean_state snapshot (D-03) and in reset_range.sh RESET_VMS.
#   elastic-vm SSHes to kali for management and enrollment (MGMT NIC).
#
# USAGE:
#   bash create-kali-vm.sh <VMID> <LAN_GW> <STORAGE> <KALI_IMAGE> <SSH_KEYFILE>
#
# ARGUMENTS:
#   VMID         VMID for the Kali VM (must be 601 per D-01 — passed for safety)
#   LAN_GW       LAN gateway for MGMT network (e.g. 10.0.0.1)
#   STORAGE      Proxmox LVM-thin storage name (typically: local-lvm)
#   KALI_IMAGE   Path to Kali qcow2 image on Host 6
#                (e.g. /var/lib/vz/template/iso/kali-linux-2025.x-qemu-amd64.qcow2)
#   SSH_KEYFILE  Path to operator SSH public key file (for reference/documentation only;
#                Kali does NOT use cloud-init — SSH key must be added manually inside Kali)
#
# EXAMPLE:
#   bash create-kali-vm.sh 601 10.0.0.1 local-lvm \
#       /var/lib/vz/template/iso/kali-linux-2025.2-qemu-amd64.qcow2 \
#       /root/.ssh/id_rsa.pub
#
# PREREQUISITES:
#   - Host 6 has vmbr0 and vmbr1 configured (Phase 1 complete)
#   - LVM-thin pool present on local-lvm (verify-storage.sh gate passed)
#   - Kali qcow2 image downloaded from kali.org and available at KALI_IMAGE path
#     https://www.kali.org/get-kali/#kali-virtual-machines → QEMU
# =============================================================================

set -euo pipefail

# --- Argument validation -----------------------------------------------------
if [[ $# -lt 5 ]]; then
  echo "ERROR: Missing required arguments." >&2
  echo "Usage: $0 <VMID> <LAN_GW> <STORAGE> <KALI_IMAGE> <SSH_KEYFILE>" >&2
  echo "" >&2
  echo "  VMID        Kali VM ID (must be 601 per D-01)" >&2
  echo "  LAN_GW      LAN gateway for MGMT (e.g. 10.0.0.1)" >&2
  echo "  STORAGE     LVM-thin storage name (e.g. local-lvm)" >&2
  echo "  KALI_IMAGE  Path to Kali qcow2 on Host 6" >&2
  echo "  SSH_KEYFILE Path to operator SSH public key file (documentation only)" >&2
  exit 1
fi

VMID="$1"
LAN_GW="$2"
STORAGE="$3"
KALI_IMAGE="$4"
SSH_KEYFILE="$5"

# --- Locked configuration (D-01, D-NEW-09 in 03-CONTEXT.md) -----------------
VM_NAME="kali"
VM_MEMORY=4096       # 4 GB RAM (D-NEW-09 — Host 6: caldera-vm 6 GB + kali 4 GB = 10 GB)
VM_CORES=2
VM_DISK_SIZE="80G"   # D-NEW-09 — sized for Kali tooling + BloodHound CE Docker + Metasploit

# Network: dual-NIC (same convention as all target VMs in provision-windows.sh)
#   net0 = vmbr1 (TARGET 10.10.10.200/24)  — emulation traffic
#   net1 = vmbr0 (MGMT  10.0.0.16/24  )  — management, SSH from elastic-vm
VM_NET0="virtio,bridge=vmbr1"
VM_NET1="virtio,bridge=vmbr0"

# IPs configured manually inside Kali after first boot (NOT via cloud-init)
KALI_MGMT_IP="10.0.0.16"
KALI_TARGET_IP="10.10.10.200"

# --- Validate inputs ---------------------------------------------------------
if [[ -z "$VMID" ]] || ! [[ "$VMID" =~ ^[0-9]+$ ]]; then
  echo "ERROR: VMID must be a positive integer, got: '$VMID'" >&2
  exit 1
fi

if [[ "$VMID" -ne 601 ]]; then
  echo "WARNING: VMID $VMID != 601 (locked spec D-01). Ensure this is intentional." >&2
  read -r -p "Continue with VMID $VMID? [y/N] " vmid_confirm
  if [[ "$vmid_confirm" != "y" && "$vmid_confirm" != "Y" ]]; then
    echo "Aborted."
    exit 0
  fi
fi

if [[ -z "$LAN_GW" ]]; then
  echo "ERROR: LAN_GW cannot be empty (e.g. 10.0.0.1)" >&2
  exit 1
fi

if [[ ! -f "$KALI_IMAGE" ]]; then
  echo "ERROR: Kali image not found at '$KALI_IMAGE'" >&2
  echo "  Download from: https://www.kali.org/get-kali/#kali-virtual-machines" >&2
  echo "  Select: QEMU (64-bit) → download kali-linux-YYYY.X-qemu-amd64.qcow2" >&2
  echo "  Copy to Host 6: scp kali-linux-*.qcow2 root@host6:/var/lib/vz/template/iso/" >&2
  exit 1
fi

if [[ ! -f "$SSH_KEYFILE" ]]; then
  echo "ERROR: SSH public key file not found at '$SSH_KEYFILE'" >&2
  exit 1
fi

# --- Confirm before proceeding -----------------------------------------------
echo "============================================================"
echo " Creating kali VM on Host 6"
echo "============================================================"
echo "  VMID        : $VMID"
echo "  Name        : $VM_NAME"
echo "  Memory      : ${VM_MEMORY} MiB (4 GB)"
echo "  Cores       : $VM_CORES"
echo "  Disk        : $VM_DISK_SIZE on $STORAGE (LVM-thin)"
echo "  net0 (TARGET): vmbr1 — ${KALI_TARGET_IP}/24 (configured inside VM)"
echo "  net1 (MGMT) : vmbr0 — ${KALI_MGMT_IP}/24, gw ${LAN_GW} (configured inside VM)"
echo "  Agent       : enabled (QEMU guest agent)"
echo "  Kali image  : $KALI_IMAGE"
echo "  SSH key ref : $SSH_KEYFILE (NOT applied — Kali has no cloud-init)"
echo "  Host 6 co-tenant: caldera-vm (600, 6 GB); combined = 10 GB"
echo ""
echo "IMPORTANT: No cloud-init. After VM starts, use Proxmox console"
echo "  to configure static IPs and change default credentials (kali/kali)."
echo "------------------------------------------------------------"
read -r -p "Proceed? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

# --- Create VM shell (no disk yet) -------------------------------------------
# NOTE: No cloud-init flags here. Kali pre-built qcow2 is a full desktop image
# (XFCE) that does NOT use cloud-init. Do NOT add:
#   --ide2 cloudinit
#   --ciuser / --sshkeys / --ipconfig0 / --nameserver / --cicustom
# Network configuration is done manually from the Proxmox console after first boot.
# Reference: 03-RESEARCH.md Pitfall 3 and Pattern 2.
echo "[1/4] Creating VM $VMID ($VM_NAME) — no cloud-init (Kali full desktop image)..."
qm create "$VMID" \
  --name "$VM_NAME" \
  --memory "$VM_MEMORY" \
  --cores "$VM_CORES" \
  --cpu cputype=host \
  --net0 "$VM_NET0" \
  --net1 "$VM_NET1" \
  --ostype l26 \
  --agent 1 \
  --onboot 1 \
  --scsihw virtio-scsi-pci

# --- Import Kali qcow2 image as disk -----------------------------------------
echo "[2/4] Importing Kali qcow2 image as VM disk (this may take several minutes)..."
qm importdisk "$VMID" "$KALI_IMAGE" "$STORAGE"

# --- Attach imported disk as scsi0 (boot disk) -------------------------------
echo "[3/4] Attaching disk as scsi0 (boot disk)..."
DISK_VOLID="${STORAGE}:vm-${VMID}-disk-0"
qm set "$VMID" \
  --scsi0 "${DISK_VOLID},discard=on,ssd=1" \
  --boot "order=scsi0" \
  --bootdisk scsi0

# --- Resize disk to 80 GB ----------------------------------------------------
echo "[4/4] Resizing disk to $VM_DISK_SIZE..."
qm resize "$VMID" scsi0 "$VM_DISK_SIZE"

# --- Set VM description (no cloud-init section) ------------------------------
qm set "$VMID" \
  --description "kali: Attacker platform (Kali Linux full desktop image).
MGMT NIC (vmbr0/net1): ${KALI_MGMT_IP}/24 — SSH from elastic-vm, Elastic Agent management.
TARGET NIC (vmbr1/net0): ${KALI_TARGET_IP}/24 — emulation traffic to TARGET subnet.
IPs configured manually inside VM via Proxmox console (no cloud-init in Kali qcow2).
Host: Host 6 (alongside caldera-vm 600, 6 GB — total 10 GB per D-NEW-09).
Included in clean_state snapshot (D-03) and reset_range.sh RESET_VMS.
Tools: Metasploit/Nmap/Impacket pre-installed. BloodHound CE + Mimikatz added post-import (D-02).
Default creds: kali/kali — MUST be changed before clean_state snapshot (RESET-01)."

# --- Summary -----------------------------------------------------------------
echo ""
echo "============================================================"
echo " kali VM $VMID created successfully"
echo "============================================================"
echo "  VMID            : $VMID"
echo "  Name            : $VM_NAME"
echo "  RAM             : ${VM_MEMORY} MiB (4 GB)"
echo "  Disk            : ${VM_DISK_SIZE} on ${STORAGE}"
echo "  net0 (TARGET)   : vmbr1 (${KALI_TARGET_IP}/24 — configure inside VM)"
echo "  net1 (MGMT)     : vmbr0 (${KALI_MGMT_IP}/24 — configure inside VM)"
echo ""
echo "NEXT STEPS (console configuration required — no cloud-init):"
echo ""
echo "  1. Start the VM on Host 6:"
echo "     qm start $VMID"
echo ""
echo "  2. Open the Proxmox console for VM $VMID:"
echo "     Proxmox web UI → Host 6 → VM $VMID → Console"
echo "     Log in as: kali / kali"
echo ""
echo "  3. Configure static IP addresses inside Kali:"
echo "     (Adapt interface names if needed — run 'ip link' to list interfaces)"
echo ""
echo "     Using nmcli (NetworkManager):"
echo "       sudo nmcli connection add type ethernet ifname eth0 con-name TARGET \\"
echo "         ip4 ${KALI_TARGET_IP}/24"
echo "       sudo nmcli connection add type ethernet ifname eth1 con-name MGMT \\"
echo "         ip4 ${KALI_MGMT_IP}/24 gw4 ${LAN_GW}"
echo "       sudo nmcli connection up TARGET"
echo "       sudo nmcli connection up MGMT"
echo ""
echo "     OR using /etc/network/interfaces (ifupdown):"
echo "       Edit /etc/network/interfaces, add:"
echo "         auto eth0"
echo "         iface eth0 inet static"
echo "           address ${KALI_TARGET_IP}"
echo "           netmask 255.255.255.0"
echo "         auto eth1"
echo "         iface eth1 inet static"
echo "           address ${KALI_MGMT_IP}"
echo "           netmask 255.255.255.0"
echo "           gateway ${LAN_GW}"
echo "       Then: sudo systemctl restart networking"
echo ""
echo "  4. Verify MGMT IP reachable from elastic-vm:"
echo "     From elastic-vm (10.0.0.10): ping -c 3 ${KALI_MGMT_IP}"
echo "     Expected: 3 packets received, 0% packet loss"
echo ""
echo "SECURITY REMINDER:"
echo "  - Change default credentials BEFORE taking clean_state snapshot (RESET-01):"
echo "      passwd kali"
echo "  - Enable and start SSH:"
echo "      sudo systemctl enable ssh && sudo systemctl start ssh"
echo "  - Set up SSH key from elastic-vm:"
echo "      From elastic-vm: ssh-copy-id kali@${KALI_MGMT_IP}"
echo "      Verify: ssh kali@${KALI_MGMT_IP} 'hostname && ip addr show'"
echo ""
echo "POST-IMPORT TOOLS (D-02 — done via Task 2 checkpoint, NOT this script):"
echo "  - BloodHound CE: docker-compose stack on Kali (http://${KALI_MGMT_IP}:8080)"
echo "  - Mimikatz PE staged at /opt/mimikatz/x64/mimikatz.exe"
echo "  - Metasploit/Nmap/Impacket: pre-installed in Kali image (verify with:"
echo "      msfconsole -v; nmap --version; impacket-smbclient --version)"
echo ""
echo "SSH KEY SETUP (elastic-vm → Proxmox hosts, required for reset_range.sh):"
echo "  From elastic-vm:"
echo "    ssh-keygen -t ed25519 -C 'elastic-vm-reset-fanout' -f ~/.ssh/id_ed25519_proxmox"
echo "    ssh-copy-id -i ~/.ssh/id_ed25519_proxmox.pub root@host2"
echo "    ssh-copy-id -i ~/.ssh/id_ed25519_proxmox.pub root@host3"
echo "    ssh-copy-id -i ~/.ssh/id_ed25519_proxmox.pub root@host4"
echo "    ssh-copy-id -i ~/.ssh/id_ed25519_proxmox.pub root@host6"
echo "  Verify: for h in host2 host3 host4 host6; do"
echo "    echo -n \"\$h: \"; ssh root@\$h 'qm list | head -3'; done"
