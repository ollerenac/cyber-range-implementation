#!/usr/bin/env bash
# =============================================================================
# create-caldera-vm.sh — Provision caldera-vm on Host 6 (Proxmox)
#
# LOCKED SPECS (do NOT change without updating D-NEW-02, D-06, D-NEW-09):
#   IP:  10.0.0.20  — caldera-vm MGMT IP (D-NEW-08)
#                   CALDERA agents phone home to 10.0.0.20:8888 (Plan 04).
#                   This IP must remain stable — changing it after Plan 04
#                   requires rebuilding all CALDERA sandcat agent binaries.
#   RAM: 6144 MiB   (6 GB — D-NEW-09; Host 6 layout: caldera-vm 6 GB + kali 4 GB)
#   Disk: 40 GB     (D-06 — sufficient for CALDERA 5.3.0 + adversary library)
#   Cores: 2
#   Bridge: vmbr0   (MGMT only — no vmbr1 NIC; caldera-vm is NOT a target VM)
#
# HOST LAYOUT (D-NEW-09):
#   Host 6: caldera-vm (this VM, 6 GB) + kali (4 GB, deployed in Phase 3)
#   Combined: 10 GB RAM, within 16 GB physical ceiling.
#   Red-team operator benefit: CALDERA C2 and Kali attacker platform colocated
#   on one physical host — clean mental model for operator.
#
# ROLE: Persistent CALDERA C2 platform — caldera-vm is NEVER snapshotted and
#       NEVER included in reset_range.sh (D-10). CALDERA 5.3.0 is installed
#       here in Plan 04. Per-run CALDERA fact flushing (not VM resets) handles
#       scenario state resets.
#
# PHASE 4 NOTE: CALDERA agents (sandcat binaries) built in Plan 04 will beacon
#   to http://10.0.0.20:8888 (agent contact URL) and https://10.0.0.20:8853
#   (agent beacon). These URLs are baked into the compiled agent binary.
#   10.0.0.20 MUST remain stable from this point forward.
#
# USAGE:
#   bash create-caldera-vm.sh <VMID> <LAN_GW> <STORAGE> <CLOUD_IMAGE> <SSH_KEYFILE>
#
# ARGUMENTS:
#   VMID          Free VMID on Host 6 (operator-chosen; check `qm list`)
#   LAN_GW        LAN gateway for MGMT network (e.g. 10.0.0.1)
#   STORAGE       Proxmox LVM-thin storage name (typically: local-lvm)
#   CLOUD_IMAGE   Path to Ubuntu 22.04 cloud image on Host 6
#                 Download: https://cloud-images.ubuntu.com/jammy/current/
#                 File: jammy-server-cloudimg-amd64.img
#   SSH_KEYFILE   Path to operator SSH public key file (e.g. ~/.ssh/id_rsa.pub)
#
# EXAMPLE:
#   bash create-caldera-vm.sh 600 10.0.0.1 local-lvm \
#       /root/jammy-server-cloudimg-amd64.img /root/.ssh/id_rsa.pub
#
# PREREQUISITES:
#   - Host 6 has vmbr0 configured (Plan 01 complete)
#   - LVM-thin pool present on local-lvm (verify-storage.sh gate passed)
#   - Ubuntu 22.04 cloud image available at CLOUD_IMAGE path
#   - cloud-init-user-data.yaml uploaded to Proxmox snippets storage on Host 6
#     (typically: /var/lib/vz/snippets/cloud-init-user-data.yaml)
#     Copy with: scp scripts/proxmox/cloud-init-user-data.yaml \
#                    root@host6:/var/lib/vz/snippets/
# =============================================================================

set -euo pipefail

# --- Argument validation -----------------------------------------------------
if [[ $# -lt 5 ]]; then
  echo "ERROR: Missing required arguments." >&2
  echo "Usage: $0 <VMID> <LAN_GW> <STORAGE> <CLOUD_IMAGE> <SSH_KEYFILE>" >&2
  echo "" >&2
  echo "  VMID        Free VMID on Host 6 (e.g. 600)" >&2
  echo "  LAN_GW      LAN gateway for MGMT (e.g. 10.0.0.1)" >&2
  echo "  STORAGE     LVM-thin storage name (e.g. local-lvm)" >&2
  echo "  CLOUD_IMAGE Path to Ubuntu 22.04 jammy cloud image" >&2
  echo "  SSH_KEYFILE Path to operator SSH public key file" >&2
  exit 1
fi

VMID="$1"
LAN_GW="$2"
STORAGE="$3"
CLOUD_IMAGE="$4"
SSH_KEYFILE="$5"

# --- Locked configuration (D-NEW-02, D-06, D-NEW-08, D-NEW-09) --------------
VM_NAME="caldera-vm"
VM_MEMORY=6144           # 6 GB RAM (D-NEW-09 — Host 6: caldera-vm 6 GB + kali 4 GB = 10 GB)
VM_CORES=2
VM_DISK_SIZE="40G"       # D-06 — sized for CALDERA 5.3.0 + adversary emulation library
VM_MGMT_IP="10.0.0.20"  # D-NEW-08 — stable MGMT IP; CALDERA agent URLs baked in Plan 04
VM_CIDR="24"
VM_BRIDGE="vmbr0"        # MGMT bridge only — no vmbr1 NIC (D-02 / T-1-04pre)
SNIPPETS_DIR="/var/lib/vz/snippets"
CLOUD_INIT_FILE="cloud-init-user-data.yaml"
CI_USER="operator"

# --- Validate inputs ---------------------------------------------------------
if [[ -z "$VMID" ]] || ! [[ "$VMID" =~ ^[0-9]+$ ]]; then
  echo "ERROR: VMID must be a positive integer, got: '$VMID'" >&2
  exit 1
fi

if [[ -z "$LAN_GW" ]]; then
  echo "ERROR: LAN_GW cannot be empty (e.g. 10.0.0.1)" >&2
  exit 1
fi

if [[ ! -f "$CLOUD_IMAGE" ]]; then
  echo "ERROR: Cloud image not found at '$CLOUD_IMAGE'" >&2
  echo "  Download from: https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img" >&2
  exit 1
fi

if [[ ! -f "$SSH_KEYFILE" ]]; then
  echo "ERROR: SSH public key file not found at '$SSH_KEYFILE'" >&2
  exit 1
fi

if [[ ! -f "${SNIPPETS_DIR}/${CLOUD_INIT_FILE}" ]]; then
  echo "ERROR: cloud-init user-data not found at '${SNIPPETS_DIR}/${CLOUD_INIT_FILE}'" >&2
  echo "  Upload with: scp scripts/proxmox/cloud-init-user-data.yaml root@<host6>:${SNIPPETS_DIR}/" >&2
  exit 1
fi

# --- Confirm before proceeding -----------------------------------------------
echo "============================================================"
echo " Creating caldera-vm on Host 6"
echo "============================================================"
echo "  VMID       : $VMID"
echo "  Name       : $VM_NAME"
echo "  Memory     : ${VM_MEMORY} MiB (6 GB)"
echo "  Cores      : $VM_CORES"
echo "  Disk       : $VM_DISK_SIZE on $STORAGE (LVM-thin)"
echo "  MGMT IP    : ${VM_MGMT_IP}/${VM_CIDR} gw ${LAN_GW}"
echo "  Bridge     : $VM_BRIDGE (MGMT only)"
echo "  Agent      : enabled (QEMU guest agent)"
echo "  Cloud image: $CLOUD_IMAGE"
echo "  SSH key    : $SSH_KEYFILE"
echo "  Host 6 co-tenant: kali (4 GB, deployed in Phase 3)"
echo "------------------------------------------------------------"
read -r -p "Proceed? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

# --- Create VM ---------------------------------------------------------------
echo "[1/7] Creating VM $VMID ($VM_NAME)..."
qm create "$VMID" \
  --name "$VM_NAME" \
  --memory "$VM_MEMORY" \
  --cores "$VM_CORES" \
  --cpu cputype=host \
  --net0 "virtio,bridge=${VM_BRIDGE}" \
  --ostype l26 \
  --agent 1 \
  --onboot 1 \
  --scsihw virtio-scsi-pci

# --- Import cloud image as boot disk -----------------------------------------
echo "[2/7] Importing cloud image as VM disk..."
qm importdisk "$VMID" "$CLOUD_IMAGE" "$STORAGE"

# --- Attach imported disk as scsi0 (boot disk) -------------------------------
echo "[3/7] Attaching disk as scsi0 (boot disk)..."
DISK_VOLID="${STORAGE}:vm-${VMID}-disk-0"
qm set "$VMID" \
  --scsi0 "${DISK_VOLID},discard=on,ssd=1" \
  --boot "order=scsi0" \
  --bootdisk scsi0

# --- Resize disk to 40 GB ----------------------------------------------------
echo "[4/7] Resizing disk to $VM_DISK_SIZE..."
qm resize "$VMID" scsi0 "$VM_DISK_SIZE"

# --- Add cloud-init drive ----------------------------------------------------
echo "[5/7] Adding cloud-init drive..."
qm set "$VMID" \
  --ide2 "${STORAGE}:cloudinit"

# --- Configure cloud-init (user, key, networking, custom user-data) ----------
echo "[6/7] Configuring cloud-init..."
qm set "$VMID" \
  --ciuser "$CI_USER" \
  --sshkeys "$SSH_KEYFILE" \
  --ipconfig0 "ip=${VM_MGMT_IP}/${VM_CIDR},gw=${LAN_GW}" \
  --nameserver "8.8.8.8" \
  --cicustom "user=local:snippets/${CLOUD_INIT_FILE}"

# --- Final VM settings -------------------------------------------------------
echo "[7/7] Applying final settings..."
qm set "$VMID" \
  --description "caldera-vm: CALDERA 5.3.0 C2 platform + adversary emulation library.
MGMT IP: ${VM_MGMT_IP} — CALDERA agent beacons to http://${VM_MGMT_IP}:8888 (Plan 04).
Host: Host 6 (alongside kali, 4 GB, deployed Phase 3 per D-NEW-09).
NEVER snapshotted / NEVER in reset_range.sh (D-10).
RAM: ${VM_MEMORY} MiB (6 GB). Disk: ${VM_DISK_SIZE} on ${STORAGE}.
Plans: provisioned in 01-02, CALDERA installed in 01-04."

# --- Summary -----------------------------------------------------------------
echo ""
echo "============================================================"
echo " caldera-vm created successfully"
echo "============================================================"
echo "  VMID          : $VMID"
echo "  MGMT IP       : ${VM_MGMT_IP}/24"
echo "  RAM           : ${VM_MEMORY} MiB (6 GB)"
echo "  Disk          : ${VM_DISK_SIZE} on ${STORAGE}"
echo "  Bridge        : ${VM_BRIDGE} (MGMT only)"
echo ""
echo "Next steps:"
echo "  1. Start VM:       qm start $VMID"
echo "  2. Monitor boot:   qm monitor $VMID  (or Proxmox console)"
echo "  3. Wait ~60s for cloud-init, then SSH:"
echo "     ssh ${CI_USER}@${VM_MGMT_IP}"
echo "  4. Check config:   qm config $VMID"
echo "     Expect: memory: ${VM_MEMORY}, net0: bridge=${VM_BRIDGE}, agent: 1"
echo ""
echo "REMINDER: Do NOT change ${VM_MGMT_IP} after Plan 04."
echo "  CALDERA sandcat agent binaries built in Plan 04 beacon to"
echo "  http://${VM_MGMT_IP}:8888 — changing the IP requires rebuilding"
echo "  all agent binaries."
echo ""
echo "NOTE: kali VM (4 GB) will be added to Host 6 in Phase 3."
echo "  Host 6 total after kali: 10 GB RAM — within 16 GB physical ceiling."
