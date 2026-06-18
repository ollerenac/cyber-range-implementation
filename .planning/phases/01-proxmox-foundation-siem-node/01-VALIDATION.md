---
phase: 1
slug: proxmox-foundation-siem-node
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-17
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash — infrastructure verification scripts (no unit test framework applicable) |
| **Config file** | none — verification is CLI/SSH-based |
| **Quick run command** | `bash .planning/phases/01-proxmox-foundation-siem-node/verify-quick.sh` |
| **Full suite command** | `bash .planning/phases/01-proxmox-foundation-siem-node/verify-full.sh` |
| **Estimated runtime** | ~30 seconds (quick) / ~90 seconds (full) |

---

## Sampling Rate

- **After every task commit:** Run quick check on the specific subsystem completed
- **After every plan wave:** Run full verification suite
- **Before `/gsd:verify-work`:** All 4 success criteria from CONTEXT.md must pass
- **Max feedback latency:** 90 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| bridge-vmbr0 | 01 | 1 | INFRA-01 | — | vmbr0 has physical NIC uplink; no routing to TARGET VLAN | manual | `ssh root@pve1 'ip link show vmbr0'` | ❌ W0 | ⬜ pending |
| bridge-vmbr1 | 01 | 1 | INFRA-01 | T-1-01 | vmbr1 has NO physical uplink; TARGET VMs cannot reach LAN | manual | `ssh root@pve1 'ip link show vmbr1 && brctl show vmbr1'` | ❌ W0 | ⬜ pending |
| vlan10-isolation | 01 | 1 | INFRA-01 | T-1-01 | Test VM on vmbr1 cannot ping 8.8.8.8 | manual | `ping -c 3 -W 2 8.8.8.8` (from test VM, must FAIL) | ❌ W0 | ⬜ pending |
| elastic-vm-create | 02 | 1 | INFRA-02 | — | elastic-vm created on Host 1 with 14 GB RAM, 200 GB disk | manual | `ssh root@pve1 'qm config <VMID>'` | ❌ W0 | ⬜ pending |
| elasticsearch-install | 02 | 2 | INFRA-02 | T-1-02 | Elasticsearch running, cluster health green, no unauthenticated access | manual | `curl -u elastic:<pw> https://10.0.0.10:9200/_cluster/health` | ❌ W0 | ⬜ pending |
| kibana-install | 02 | 2 | INFRA-02 | — | Kibana reachable at https://10.0.0.10:5601 | manual | browser / `curl -k https://10.0.0.10:5601/api/status` | ❌ W0 | ⬜ pending |
| fleet-server-bootstrap | 02 | 3 | INFRA-02 | T-1-02 | Fleet Server shows HEALTHY; enrollment token generated | manual | Fleet UI → Agents → Enrollment tokens | ❌ W0 | ⬜ pending |
| tls-cert-san | 02 | 2 | INFRA-02 | T-1-02 | Fleet cert SAN contains IP:10.0.0.10; no CN mismatch | manual | `openssl x509 -in fleet-server.crt -text \| grep -A1 'Subject Alternative'` | ❌ W0 | ⬜ pending |
| caldera-install | 03 | 2 | — | — | CALDERA UI accessible at http://10.0.0.20:8888 | manual | `curl http://10.0.0.20:8888` | ❌ W0 | ⬜ pending |
| snapshot-clean-state | 02 | 3 | INFRA-01 | — | `qm rollback` succeeds; VM returns to clean state in <60s | manual | `time qm rollback <VMID> clean_state` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

This is a greenfield infrastructure phase. No automated test framework is applicable — all verification is CLI/SSH/browser-based against live hardware.

*Existing infrastructure covers all phase requirements via manual verification steps.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| vmbr0 and vmbr1 bridges exist on ALL 6 Proxmox hosts | INFRA-01 | Requires SSH to each physical host | `for H in pve1 pve2 pve3 pve4 pve5 pve6; do ssh root@$H 'hostname && brctl show'; done` |
| vmbr1 has no physical uplink on any host | INFRA-01 | Live bridge state inspection | `brctl show vmbr1` on each host — "interfaces" column must be empty |
| VLAN 10 switch port carrying TARGET traffic is isolated from LAN | INFRA-01 | Requires managed switch CLI access | Switch CLI: verify VLAN 10 is not in the same L3 SVI as LAN VLAN; inter-VLAN routing disabled |
| Test VM on vmbr1 cannot reach 8.8.8.8 or 10.0.0.0/24 | INFRA-01 | Requires live test VM on vmbr1 | Boot minimal VM on vmbr1; `ping 8.8.8.8` must time out; `ping 10.0.0.10` must time out |
| Elasticsearch cluster health is green | INFRA-02 | Requires live elastic-vm | `curl -u elastic:<pw> --cacert http_ca.crt https://10.0.0.10:9200/_cluster/health?pretty` |
| Kibana loads without TLS errors in browser | INFRA-02 | Browser UI state | Open https://10.0.0.10:5601; accept CA cert; Kibana login screen appears |
| Fleet Server active with enrollment token | INFRA-02 | Fleet UI state | Kibana → Fleet → Agents → Enrollment tokens; at least one active token shown |
| Fleet Server cert SAN matches IP:10.0.0.10 | INFRA-02 | TLS cert inspection | `openssl s_client -connect 10.0.0.10:8220 2>/dev/null \| openssl x509 -noout -text \| grep IP` |
| CALDERA server starts; ports 8888 and correct TCP contact port are open | — | Live process state | `ss -tlnp \| grep -E '8888\|8853\|7010'` on caldera-vm after startup |
| `qm snapshot` and `qm rollback` succeed on a test VM | INFRA-01 | Requires live Proxmox + VM | `qm snapshot <VMID> test_snap && qm rollback <VMID> test_snap && qm delsnapshot <VMID> test_snap` |

---

## Validation Sign-Off

- [ ] All tasks have manual verification steps defined above
- [ ] Sampling continuity: each wave has a defined verification command
- [ ] Wave 0 not applicable — greenfield infra phase
- [ ] No watch-mode flags (not applicable)
- [ ] Feedback latency < 90s for each subsystem check
- [ ] `nyquist_compliant: true` set in frontmatter after sign-off

**Approval:** pending
