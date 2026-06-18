---
status: partial
phase: 01-proxmox-foundation-siem-node
source: [01-01-SUMMARY.md, 01-02-SUMMARY.md, 01-03-SUMMARY.md, 01-04-SUMMARY.md]
started: 2026-06-18T07:26:00Z
updated: 2026-06-18T07:36:00Z
---

## Current Test

[testing paused — 12 items outstanding (all blocked: physical hardware not yet configured)]

## Tests

### 1. Network bridges present on all 6 hosts (ROADMAP gate 1)
expected: |
  SSH into any Proxmox host and run:
    brctl show | grep -E 'vmbr0|vmbr1'
  or: ip link show type bridge
  Expected output: both vmbr0 and vmbr1 appear. Then confirm vmbr1
  has no bare NIC (only eno1.10 VLAN sub-interface):
    bridge link show dev vmbr1
  Expected: output shows eno1.10, NOT eno1.
  Do this on at least Host 1 and Host 6 (where elastic-vm and caldera-vm live).
result: blocked
blocked_by: physical-device
reason: Physical Proxmox hosts not yet configured

### 2. verify-isolation.sh passes on at least one host
expected: |
  On any Proxmox host, run:
    bash scripts/proxmox/verify-isolation.sh
  Expected: script exits 0 with "[OK] vmbr1: no bare physical NIC in bridge-ports"
  (Mode A check). No "FAIL" lines in output.
result: blocked\nblocked_by: physical-device\nreason: Physical Proxmox hosts not yet configured

### 3. Network isolation gate — vmbr1 VMs cannot reach internet or LAN (ROADMAP gate 4)
expected: |
  From a test VM attached to vmbr1 (or via the isolation test in verify-isolation.sh --from-target-vm):
    ping -c2 8.8.8.8        → should TIME OUT (no reply)
    ping -c2 <LAN gateway>  → should TIME OUT (no reply)
  Isolation is confirmed when BOTH pings fail.
  If verify-isolation.sh --from-target-vm is not accessible, run a manual ping test
  from any vmbr1-attached VM shell.
result: blocked\nblocked_by: physical-device\nreason: Physical Proxmox hosts not yet configured

### 4. elastic-vm SSH-reachable with correct OS prereqs
expected: |
  SSH to elastic-vm:
    ssh ubuntu@10.0.0.10
  Then verify Elasticsearch OS prerequisites were applied by cloud-init:
    sysctl vm.max_map_count
  Expected output: vm.max_map_count = 262144
  Also confirm RAM:
    free -h | grep Mem
  Expected: ~13.6 GiB (14336 MiB provisioned).
result: blocked\nblocked_by: physical-device\nreason: Physical Proxmox hosts not yet configured

### 5. Kibana loads at https://10.0.0.10:5601 and Elasticsearch is green (ROADMAP gate 2)
expected: |
  In a browser on the management network, open:
    https://10.0.0.10:5601
  Expected:
  - Kibana login page loads (browser may warn about self-signed cert — accept and proceed)
  - Log in as "elastic" with the password captured during install-stack.sh
  - Kibana home dashboard loads without errors
  - In Stack Monitoring or via health-check.sh: cluster health is GREEN
    bash scripts/elastic/health-check.sh → exits 0, "cluster health: green"
result: blocked\nblocked_by: physical-device\nreason: Physical Proxmox hosts not yet configured

### 6. Fleet Server Healthy with enrollment token (ROADMAP gate 3)
expected: |
  In Kibana (https://10.0.0.10:5601):
  - Navigate to Stack Management → Fleet → Settings
  - Fleet Server should show status "Healthy" or "Online"
  - Navigate to Fleet → Enrollment Tokens
  - At least one enrollment token exists and is copyable
  This confirms bootstrap-fleet.sh ran successfully and Fleet Server
  is ready to enroll Phase 3 Elastic Agents.
result: blocked\nblocked_by: physical-device\nreason: Physical Proxmox hosts not yet configured

### 7. TLS cert SAN verified for Fleet Server
expected: |
  From any machine that can reach elastic-vm, run:
    openssl s_client -connect 10.0.0.10:8220 </dev/null 2>/dev/null | \
      openssl x509 -noout -text | grep -A2 "Subject Alternative"
  Expected output must contain:
    IP Address:10.0.0.10
  If this IP is absent, the Fleet Server cert does not have the required SAN
  and Elastic Agents will reject it during enrollment.
result: blocked\nblocked_by: physical-device\nreason: Physical Proxmox hosts not yet configured

### 8. caldera-vm SSH-reachable with correct specs
expected: |
  SSH to caldera-vm:
    ssh ubuntu@10.0.0.20
  Confirm RAM (6 GB provisioned):
    free -h | grep Mem
  Expected: ~5.8 GiB
  Confirm it has no internet access (D-10 control-plane node):
    ping -c2 8.8.8.8
  Expected: no reply (caldera-vm is on vmbr0 MGMT only, no vmbr1 NIC).
result: blocked\nblocked_by: physical-device\nreason: Physical Proxmox hosts not yet configured

### 9. CALDERA web UI accessible at http://10.0.0.20:8888
expected: |
  In a browser or with curl from the management network:
    curl -s -o /dev/null -w "%{http_code}" http://10.0.0.20:8888
  Expected: HTTP 200 (or 302 redirect to /login)
  In browser: CALDERA login page appears.
  NOTE: This test requires install-caldera.sh to have been run on caldera-vm
  with rotated API keys (CHANGE_ME placeholders replaced).
result: blocked\nblocked_by: physical-device\nreason: Physical Proxmox hosts not yet configured

### 10. CALDERA TCP contact port 8853 listening (Research A1 resolution)
expected: |
  SSH to caldera-vm, then:
    ss -tlnp | grep -E '8888|8853|7010'
  Expected: 8888 present (HTTP UI/beacon). 8853 present if the local.yml
  override took effect. 7010 should NOT appear (that would mean local.yml
  was not loaded and the CALDERA default was used instead).
  Record which ports actually appear — this resolves the CONTEXT open question A1.
result: blocked\nblocked_by: physical-device\nreason: Physical Proxmox hosts not yet configured

### 11. Snapshot mechanism validated (D-05 gate)
expected: |
  On the Proxmox host that has your throwaway test VM (not elastic-vm or caldera-vm!),
  run snapshot-test.sh:
    bash scripts/proxmox/snapshot-test.sh <THROWAWAY_VMID>
  Expected: script completes all 3 stages (snapshot → rollback → delsnapshot),
  reports rollback duration in seconds, exits 0.
  This confirms qm snapshot/rollback works reliably on this hardware (D-05).
  If you don't have a throwaway VM, mark as blocked with "need throwaway VM".
result: blocked\nblocked_by: physical-device\nreason: Physical Proxmox hosts not yet configured

### 12. ILM policy applied (30-day log retention)
expected: |
  In Kibana:
  - Navigate to Stack Management → Index Lifecycle Policies
  - Policy "lab-logs-30d" should be listed
  OR verify via curl on elastic-vm:
    curl -s -u elastic:$ES_PASSWORD -k https://10.0.0.10:9200/_ilm/policy/lab-logs-30d \
      | python3 -m json.tool | grep max_age
  Expected: "max_age": "1d" (rollover trigger) and policy exists with delete phase.
result: blocked\nblocked_by: physical-device\nreason: Physical Proxmox hosts not yet configured

## Summary

total: 12
passed: 0
issues: 0
pending: 0
skipped: 0
blocked: 12

## Gaps

[none yet]
