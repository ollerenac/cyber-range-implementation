# Phase 3: Full Telemetry Pipeline + Reset Mechanism - Context

**Gathered:** 2026-06-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 3 delivers: Kali Linux VM provisioned on Host 6, Elastic Agents enrolled and Healthy in Fleet on all 5 Windows VMs and Kali, Sysmon deployed on all Windows VMs with per-role configs, Packetbeat flowing on all VMs (Windows via Elastic Agent, Kali via Elastic Agent), a `clean_state` snapshot taken across all 6 target VMs simultaneously after agents show Healthy, and `reset_range.sh` validated end-to-end (SSH fan-out from elastic-vm → qm rollback all 6 VMs → Fleet health poll confirms recovery in < 5 minutes). The phase exits with dual telemetry flowing into Elasticsearch and a tested one-command reset.

**elastic-vm and caldera-vm are NEVER touched by Phase 3 reset operations — this is a hard constraint inherited from Phase 1 D-10 and already encoded in reset_range.sh by construction.**

**Success gate (from ROADMAP.md):**
1. Fleet UI shows dc01, exchange01, sql01, ws01 all "Healthy" — Elastic Defend DETECT mode verifiable in Fleet policy view
2. `cmd.exe` on dc01 → Kibana Discover `process.name: "cmd.exe"` → at least one Sysmon EID 1 event with ECS `process.name` populated
3. `packetbeat-*` index shows DNS traffic from TARGET subnet — Packetbeat flowing on all Windows VMs
4. `./reset_range.sh` → within 5 minutes all VMs back online, Fleet shows Healthy, AD auth succeeds
5. Kali reaches TARGET subnet and CALDERA agent binary phones home to caldera-vm:8853 on a test run

</domain>

<decisions>
## Implementation Decisions

### Kali VM Provisioning (INFRA-07)

- **D-01:** Kali provisioned from official **pre-built qcow2 VM image** (kali.org download), imported via `qm importdisk` on **Host 6** (alongside caldera-vm). VMID: **601**. Mirrors the `create-caldera-vm.sh` and `create-elastic-vm.sh` patterns already in `scripts/proxmox/`. MGMT NIC: 10.0.0.16 (vmbr0/net1); TARGET NIC: 10.10.10.200 (vmbr1/net0) — same dual-NIC convention as all target VMs.

- **D-02:** Post-import tool additions on Kali: **BloodHound CE** (Docker Compose install) + **Mimikatz** (Windows PE binary staged on Kali at `/opt/mimikatz/` for deployment to Windows targets). Metasploit, Nmap, and Impacket are pre-installed in the Kali image — no explicit install needed.

- **D-03:** Kali is included in the `clean_state` snapshot and in `reset_range.sh` (already present in scaffold RESET_VMS). Kali VMID 601 populates the placeholder in the script.

### Elastic Agent Enrollment (TELEM-01, TELEM-02)

- **D-04:** **Kali gets Elastic Agent** enrolled in Fleet with the `kali-linux` policy. Rationale: attacker-originated traffic (DNS, HTTP, SMB from Kali) is intentionally captured for Phase 6 correlation between what Kali sent and what Windows VMs received. This is a deliberate design choice — Kali telemetry enables cross-perspective analysis.

- **D-05:** Kali host-event telemetry via **Elastic Defend Linux** (eBPF/kprobes) in `kali-linux` policy — not auditd. Provides ECS-mapped process trees, network connections, and file events in the same format as Windows Elastic Defend, enabling unified Kibana dashboards.

- **D-06:** Elastic Agent installer **served via HTTP from elastic-vm** (10.0.0.10). A simple HTTP file server on elastic-vm serves both the `elastic-agent-*.zip/.deb` installer and `npcap-*.exe` to all target VMs via the MGMT NIC (10.0.0.0/24). No SMB shares or manual file copies needed.

- **D-07:** **Single control-node bash script** (`scripts/elastic/enroll-agents.sh`) runs from elastic-vm and loops all 5 Windows VMs via WinRM `Invoke-Command`. Sequence per VM: (1) copy Fleet CA cert via WinRM, (2) download Npcap from elastic-vm HTTP, (3) silent install Npcap, (4) download elastic-agent installer, (5) install + enroll with Fleet token. Consistent with Phase 2's WinRM-based remote script delivery pattern.

- **D-08:** Fleet CA cert distribution: the control script SCPs the CA cert from `elastic-vm:/etc/elasticsearch/certs/ca.crt` to each Windows VM before running `elastic-agent install` — per Phase 1 D-13. CA cert must already exist on elastic-vm (generated in Phase 1 via `generate-certs.sh`).

### Sysmon Configuration (TELEM-03)

- **D-09:** **Servers** (dc01, exchange01, sql01): olafhartong/sysmon-modular config merging EventID modules **1, 3, 7, 10, 11, 13, 17, 22**:
  - EID 1: ProcessCreate — process telemetry
  - EID 3: NetworkConnect — outbound connections
  - EID 7: ImageLoad — DLL sideloading detection
  - EID 10: ProcessAccess — credential theft (LSASS access)
  - EID 11: FileCreate — file drop/write
  - EID 13: RegistryValueSet — persistence mechanisms
  - EID 17: PipeEvent — named pipe activity (lateral movement)
  - EID 22: DNSQuery — C2 beaconing via DNS
  Merged output: `sysmon-server.xml`

- **D-10:** **Workstations** (ws01, ws02): same as D-09 PLUS additional EventIDs **15, 23, 25, 26**:
  - EID 15: FileCreateStreamHash — MOTW-bypassing downloads (initial access)
  - EID 23: FileDelete — Wizard Spider ransomware file deletion tracking
  - EID 25: ProcessTampering — process hollowing/injection detection
  - EID 26: FileDeleteDetected — confirms ransomware encryption (Ryuk)
  Merged output: `sysmon-workstation.xml`
  Rationale: workstations are primary initial-access targets — wider coverage is justified.

- **D-11:** Two separate sysmon-modular merge configs stored in `scripts/windows/sysmon/`: `sysmon-server.xml` (servers) and `sysmon-workstation.xml` (workstations). Deployed via Sysmon.exe on each VM as part of the agent enrollment script or a separate sysmon-deploy step.

### Fleet Policy Design

- **D-12:** **Two Fleet policies:**
  - `windows-target` — applied to dc01, exchange01, sql01, ws01, ws02. Integrations: Elastic Defend (DETECT) + Windows Event Log (Sysmon/Operational + Security + System channels) + Packetbeat + System.
  - `kali-linux` — applied to Kali. Integrations: Elastic Defend Linux (DETECT) + Packetbeat.

- **D-13:** Elastic Defend set to **DETECT mode in the Fleet policy BEFORE the first agent enrolls**. Agents enroll already in DETECT mode — no post-enrollment mode switch needed. This satisfies ROADMAP Phase 3 success criterion #1 ("DETECT not PREVENT, verifiable in Fleet policy view").

### Npcap and Packetbeat (TELEM-04)

- **D-14:** **Npcap** silently installed on each Windows VM before Elastic Agent installation:
  ```
  npcap-*.exe /S /winpcap_mode=yes /dot11_support=no /admin_only=no
  ```
  Served from elastic-vm HTTP alongside the agent installer. Must be installed BEFORE `elastic-agent install` runs, as Packetbeat requires Npcap to be present at agent startup.

- **D-15:** **Packetbeat protocol set** in `windows-target` Fleet policy (APT-focused, not all-protocols):
  - DNS — C2 beaconing (T1071.004), exfiltration via DNS
  - HTTP — C2 over HTTP (T1071.001), OilRig TwoFace webshell traffic
  - SMB — lateral movement (T1021.002), Pass-the-Hash
  - TLS metadata / JA3 fingerprinting — encrypted C2 identification
  - Kerberos — Kerberoasting (T1558.003 — OilRig, Wizard Spider)
  - MSSQL — OilRig SQL exfiltration via sql01 (T1041)

- **D-16:** Packetbeat configured via **Fleet integration panel** (not standalone `packetbeat.yml`). Configuration is managed centrally in Kibana Fleet UI → Policy → Add integration. No per-VM config files to maintain.

### Reset Strategy (RESET-01, RESET-02, RESET-03)

- **D-17:** Proxmox hosts are **standalone** (no cluster). `reset_range.sh` uses **SSH fan-out from elastic-vm** to each host where target VMs live:
  - `ssh root@host2` → `qm stop/rollback/start` for dc01 (VMID 201) and sql01 (VMID 202)
  - `ssh root@host3` → `qm stop/rollback/start` for exchange01 (VMID 301)
  - `ssh root@host4` → `qm stop/rollback/start` for ws01 (VMID 401) and ws02 (VMID 402)
  - `ssh root@host6` → `qm stop/rollback/start` for kali (VMID 601)
  All SSH fan-out branches run in parallel (`&`) — total wall-clock ≈ slowest single-VM reset.

- **D-18:** `reset_range.sh` runs **from elastic-vm** (10.0.0.10). elastic-vm is always online (excluded from reset by D-10), holds SSH keys to all Proxmox hosts, and is the natural control plane. Operator SSHes into elastic-vm and runs the script.

- **D-19:** Post-reset **verification polls the Fleet API** until all expected agents report online:
  ```bash
  curl -s -k -u elastic:$ELASTIC_PW \
    'https://10.0.0.10:9200/.fleet-agents/_search?q=status:online&_source=local_metadata.host.name' \
    | jq '.hits.total.value'
  ```
  Polls every 10 seconds with a 5-minute timeout. Satisfies RESET-03 ("< 5 min, no manual intervention") measurably. Pass condition: all 6 enrolled agents (dc01, exchange01, sql01, ws01, ws02, kali) show `status:online`.

- **D-20:** `clean_state` snapshot taken **simultaneously across all 6 target VMs** via the same SSH fan-out pattern, AFTER all agents show Healthy in Fleet (RESET-01). Snapshot name locked: `clean_state` (per Phase 1 D-05). The take-snapshot script is a separate one-shot script, not part of `reset_range.sh`.

### Claude's Discretion

- Kali qcow2 image version (Kali 2024.x or 2025.x — use latest available at setup time; tools are rolling-release)
- HTTP file server on elastic-vm (Python `http.server`, nginx, or any simple static server — simplest option wins)
- Exact Packetbeat JA3 configuration syntax in Fleet integration panel (follow Elastic 8.x docs for the `tls` protocol settings)
- SSH key format and distribution method for elastic-vm → Proxmox hosts (ed25519 recommended; standard `ssh-copy-id` during initial lab setup)
- Sysmon.exe deployment method: download from Sysinternals or stage on elastic-vm HTTP server alongside other installers

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase context (locked decisions that carry forward)

- `.planning/phases/01-proxmox-foundation-siem-node/01-CONTEXT.md` — IP plan (D-NEW-07/08), host layout (D-NEW-09), snapshot tool `qm` not `virsh` (D-05), TLS cert SAN `IP:10.0.0.10` (D-12), elastic-vm NEVER snapshotted (D-10), CA cert path on elastic-vm (D-13)
- `.planning/phases/02-windows-target-network/02-CONTEXT.md` — WinRM enabled on all Windows VMs (D-12), VMID assignments (provision-windows.sh header: dc01=201, sql01=202, exchange01=301, ws01=401, ws02=402), `phase2-domain-joined` snapshot as starting point

### Project requirements

- `.planning/ROADMAP.md §Phase 3` — Phase goal, 5 success criteria, requirements: INFRA-07, TELEM-01-04, RESET-01-03
- `.planning/REQUIREMENTS.md` — INFRA-07 (Kali), TELEM-01 (Fleet enrollment via MGMT), TELEM-02 (Elastic Defend DETECT), TELEM-03 (Sysmon + sysmon-modular), TELEM-04 (Packetbeat), RESET-01/02/03 (snapshot + script + timing)
- `.planning/STATE.md` — Critical constraints: elastic-vm NEVER in reset_range.sh, simultaneous snapshots, all Elastic versions pinned to same 8.x patch

### Existing scripts (Phase 3 must extend/complete these)

- `scripts/proxmox/reset_range.sh` — scaffold with SSH fan-out TODO, D-10 exclusion guard; Phase 3 populates real VMIDs and implements SSH fan-out to Host 2/3/4/6
- `scripts/proxmox/provision-windows.sh` — VMID convention (Host 2: 201/202, Host 3: 301, Host 4: 401/402); Kali VMID 601 follows Host 6 convention
- `scripts/proxmox/create-caldera-vm.sh` — template for Kali VM creation script (same `qm create` pattern, same Host 6)
- `scripts/elastic/bootstrap-fleet.sh` — Fleet enrollment token generation; CA cert path on elastic-vm
- `scripts/elastic/generate-certs.sh` — CA cert location produced by Phase 1

### Telemetry reference

- `github/adversary_emulation_library/` — APT emulation plans that define which TTPs must produce telemetry; Phase 3 telemetry coverage directly enables Phase 5/6 detection

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`scripts/proxmox/reset_range.sh`** — Phase 3's primary deliverable is completing this scaffold. SSH fan-out structure, D-10 guard, and parallel `qm rollback` loop are already designed. Task: populate VMIDs, implement SSH fan-out, add Fleet API health poll.
- **`scripts/proxmox/create-caldera-vm.sh`** — Direct template for Kali VM creation script. Uses `qm create` + `qm importdisk` pattern. Copy and adapt for Kali (qcow2 source instead of Ubuntu cloud image).
- **`scripts/proxmox/provision-windows.sh`** — VMID convention and dual-NIC (net0=vmbr1 TARGET, net1=vmbr0 MGMT) pattern to follow for Kali.
- **`scripts/windows/setup/07-security-baseline.ps1`** — WinRM `Invoke-Command` delivery pattern to follow for the enrollment script.

### Established Patterns

- `qm` (not `virsh`) for all snapshot operations — Phase 1 locked decision, already in reset_range.sh
- MGMT NIC (vmbr0, 10.0.0.0/24) for enrollment; TARGET NIC (vmbr1, 10.10.10.0/24) for emulation traffic
- All Phase 2 Windows scripts delivered via WinRM from the control node — same pattern for Phase 3 enrollment

### Integration Points

- **Phase 1 → Phase 3:** Fleet CA cert at `/etc/elasticsearch/certs/ca.crt` on elastic-vm must be distributed to each Windows VM before `elastic-agent install`
- **Phase 2 → Phase 3:** `phase2-domain-joined` snapshot is the starting point — all VMs in that clean domain-joined state before enrollment
- **Phase 3 → Phase 4:** `clean_state` snapshot captured here is the baseline for CALDERA ML baselining (Phases 4-6); elastic-vm must already be running the ML jobs when CALDERA starts
- **Phase 3 → Phase 6:** `reset_range.sh` validated here is the between-run reset mechanism used in every Phase 6 APT scenario run

</code_context>

<specifics>
## Specific Ideas

- **VMID assignments for reset_range.sh:** dc01=201, sql01=202, exchange01=301, ws01=401, ws02=402, kali=601. These populate the TODO placeholders in the existing scaffold.
- **SSH fan-out host addresses:** Host 2 = 10.0.0.X (operator knows actual IPs), Host 3, Host 4, Host 6. Phase 3 plan should include a step to add Proxmox host IPs to elastic-vm's `/etc/hosts` or `~/.ssh/config`.
- **Fleet API health poll endpoint:** `/_cat/agents` or `/.fleet-agents/_search` — verify exact Elasticsearch Fleet API path against Elastic 8.x docs before implementing (API path changed between 8.x minor versions).
- **Npcap download source:** Stage `npcap-*.exe` on elastic-vm HTTP server (same path as elastic-agent installer) — do NOT rely on internet download from target VMs (TARGET network has no internet; enrollment uses MGMT NIC but HTTP path to Nmap.org from lab may be restricted).
- **Kali CALDERA test:** ROADMAP success criterion #5 requires the CALDERA agent binary to phone home to `caldera-vm:8853`. This is a Phase 3 validation test — deploy CALDERA's sandcat agent from caldera-vm to kali and confirm beacon. Phase 3 does NOT need to run a full operation (that's Phase 4).

</specifics>

<deferred>
## Deferred Ideas

- **Host 5 IDS sensor (Suricata/Zeek):** Noted in Phase 1 CONTEXT.md (D-NEW-06) as reserved for future phases. Not in Phase 3 scope.
- **Per-role Fleet policies (servers vs workstations):** User confirmed two policies (windows-target + kali-linux) is sufficient for Phase 3. Can split windows-target into servers/workstations in Phase 4 if Elastic Defend tuning per role becomes needed.
- **Packetbeat on Kali with separate index routing:** Kali's Packetbeat data (attacker perspective) will land in the same `packetbeat-*` indices as Windows VM data. Index routing separation (to distinguish red from blue telemetry) is a Phase 6 data architecture concern, not Phase 3.
- **auditd as supplementary logging on Kali:** Elastic Defend Linux covers the critical events; auditd as a complement for syscall-level logging is a Phase 4+ enhancement.

</deferred>

---

*Phase: 3-Full Telemetry Pipeline + Reset Mechanism*
*Context gathered: 2026-06-18*
