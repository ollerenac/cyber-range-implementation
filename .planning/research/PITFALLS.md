# Domain Pitfalls: Cyber Range / APT Emulation Lab

**Domain:** Virtualized Cyber Range with APT Emulation and Elastic SIEM
**Researched:** 2026-06-07
**Confidence:** MEDIUM-HIGH (training knowledge through Aug 2025; no live docs available in this session)

---

## Layer 1: Infrastructure Pitfalls

### CRITICAL — Lab Network Bleeds Into Host Network

**What goes wrong:** Victim VMs reach the internet (or the host's LAN) because the Proxmox bridge or VirtualBox adapter is set to "bridged" or because `pfSense`/firewall rules are never applied. Red team tools call back to real infrastructure, or — worse — malware escapes containment.

**Why it happens:** Convenience during initial setup. "I'll fix isolation later" never gets fixed. Default VirtualBox NAT still routes outbound. Proxmox Linux bridges (`vmbr0`) are bridged to the physical NIC by default.

**Consequences:** Lab network artifacts contaminate telemetry with real internet traffic; Packetbeat floods with irrelevant flows; a credential-harvesting tool phones home; thesis reviewers cannot trust the dataset.

**Warning signs:**
- `ping 8.8.8.8` succeeds from a victim VM
- Packetbeat captures DNS queries to public resolvers from within the range
- Elastic agent enrollment uses a public IP instead of a lab-internal one

**Prevention:**
- Create a dedicated isolated Proxmox bridge (`vmbr1`, no uplink NIC attached) for the victim network
- Assign all victim VMs to `vmbr1` only; the attacker VM gets both `vmbr1` (internal) and optionally `vmbr0` (mgmt), never bridged
- Add a default-deny iptables rule on the Proxmox host: `iptables -I FORWARD -i vmbr1 -o vmbr0 -j DROP`
- Verify isolation as a first-pass acceptance test before installing anything else

**Phase:** Infrastructure setup (Phase 1) — must be gate-checked before proceeding.

---

### CRITICAL — Resource Exhaustion Stalls or Corrupts Emulation Runs

**What goes wrong:** The host runs out of RAM or CPU during a full emulation run. VMs balloon swap, Elasticsearch OOMs and crashes mid-ingest, or Proxmox suspends a VM. The resulting telemetry is incomplete and timestamps become unreliable.

**Why it happens:** The stack is deceptively heavy. A minimal useful configuration — AD DC + Exchange + SQL Server + attacker + Elastic node — is 5 VMs. Elastic alone needs 8 GB heap to avoid GC pauses. Exchange 2016/2019 requires 8 GB RAM minimum. Total addressable RAM easily exceeds 40 GB.

**Consequences:** Emulation runs produce partial telemetry; Elastic drops events under backpressure; timestamps get out of sync, making attack chain reconstruction unreliable.

**Warning signs:**
- `free -h` on the Proxmox host shows <2 GB free during an emulation run
- Elasticsearch logs show `[o.e.m.j.JvmGcMonitorService] [node-1] [gc][young] overhead` warnings
- Elastic Agent on a VM logs `output error: ... connection refused` — Elasticsearch crashed

**Prevention:**
- Budget RAM before building: DC (4 GB) + Exchange (8–12 GB) + SQL (4 GB) + attacker (2 GB) + Elastic node (16 GB, 8 GB heap) = 34–38 GB minimum; add 4 GB for Proxmox host OS
- Use Elasticsearch `Xms`/`Xmx` set to half physical RAM available to the Elastic VM, never exceeding 31 GB (compressed OOPs limit)
- If hardware is constrained, drop Exchange from scope — use a simple IIS/Windows Server web VM instead; Exchange is not required by any of the three CTID plans
- Enable Proxmox memory ballooning only on non-Elastic VMs

**Phase:** Infrastructure sizing (Phase 1) — decide before provisioning VMs.

---

### MODERATE — Snapshot Chain Corruption After Hot Snapshots

**What goes wrong:** Taking a snapshot of a running Windows VM (especially the DC with AD, or the Elastic node with open Lucene files) produces a snapshot that restores to an inconsistent state: NTDS.dit is mid-write, or Elasticsearch's translog is torn.

**Why it happens:** `virsh snapshot-create` without `--quiesce` (QEMU guest agent required) or VirtualBox `VBoxManage snapshot take` on a running VM skips the VSS freeze step. Windows AD and Elasticsearch both have write-active database files.

**Consequences:** Restore scripts appear to succeed but VMs boot into `chkdsk` loops or Elasticsearch refuses to start with a corrupted translog error (`failed to load node metadata`).

**Warning signs:**
- After restore, Windows DC shows Event ID 1000 (application crash) in the first boot
- Elasticsearch logs: `failed to load node metadata ... TranslogCorruptedException`
- `virsh snapshot-info` shows `state: running` for a snapshot taken without guest quiesce

**Prevention:**
- Always quiesce before snapshot: install `qemu-guest-agent` on every VM, then use `virsh snapshot-create-as --quiesce`
- For Elasticsearch: shut down the service (`systemctl stop elasticsearch`) before taking the baseline snapshot, OR use Elasticsearch's snapshot-to-S3/filesystem feature for the data layer and let the VM snapshot cover only OS state
- Test the restore pipeline explicitly: create snapshot → restore → boot → verify `elastic-agent status` and `dcdiag /test:services` both pass. Gate this before writing emulation scripts.
- Script the restore as: `virsh shutdown <vm>` → wait for clean shutdown → `virsh snapshot-revert` → `virsh start <vm>`

**Phase:** Infrastructure (Phase 1) for snapshot design; tested again at Reset Mechanism phase.

---

### MINOR — Proxmox VM Clock Drift After Restore

**What goes wrong:** Restored VMs wake up with the system clock at snapshot-creation time (hours or days in the past). Elastic Agent's TLS certificate validation fails because the VM's clock is behind. Sysmon timestamps in logs are wrong, making attack chain timelines misleading.

**Prevention:**
- Force NTP sync in the post-restore boot script: `w32tm /resync /force` (Windows) or `chronyc makestep` (Linux)
- Or: configure VMs to sync time from the Proxmox host (KVM clock) — set `<clock offset="utc">` in the VM XML and ensure `qemu-guest-agent` is running

**Phase:** Reset Mechanism phase — add to restore runbook.

---

## Layer 2: APT Emulation Pitfalls

### CRITICAL — CTID Plans Assume Tool Versions That No Longer Exist or Behave Differently

**What goes wrong:** The CTID adversary emulation plans (especially APT29 and Wizard Spider) reference specific tool versions, invocation flags, or file paths that have changed in upstream projects. For example, Mimikatz command syntax, Empire module names, and Atomic Red Team test IDs all drift over time.

**Why it happens:** The CTID plans were written at a point in time. The `Resources/` directory of each plan ships binaries or scripts frozen at that version, but CALDERA integration stubs may reference newer tool behavior. APT29 plan specifically uses `Empire`, which has changed ownership and API multiple times.

**Consequences:** A CALDERA ability fails silently (exit code 0 but no output); the technique is logged as "run" but did not actually execute; telemetry shows nothing; thesis claims a technique was emulated when it was not.

**Warning signs:**
- CALDERA operation log shows `status: success` but the expected IOC (file, registry key, network connection) is absent from Elastic
- Mimikatz returns `ERROR kuhl_m_sekurlsa_acquireLSA ; Handle on memory` — wrong invocation flag for the Windows version in the lab
- Empire or Covenant agent does not beacon back — C2 framework configuration changed

**Prevention:**
- Pin tool versions: use the binaries from each plan's `Resources/` directory, not the latest upstream build
- Validate each ability independently before packaging into a CALDERA adversary: run it manually on the target, confirm the expected artifact appears in Elastic, then add it to CALDERA
- For each MITRE technique, record the manual verification evidence (screenshot of Elastic hit, technique ID, tool invoked) before relying on CALDERA automation — this also serves as thesis evidence
- Add a "technique dry-run" phase before the full emulation: run every ability once manually, note failures, fix or substitute

**Phase:** APT Plan Adaptation phase — per-APT validation before CALDERA packaging.

---

### CRITICAL — Windows Defender / AV Blocks Emulation Tools Before They Execute

**What goes wrong:** Windows Defender (or Elastic Defend's prevention mode) detects and quarantines Mimikatz, PowerShell-based lateral movement scripts, or CALDERA agent payloads before they run. The emulation silently fails. Worse: if Elastic Defend is in prevention mode, it blocks the attack AND generates a detection — but the detection is of the tool download, not the technique execution, making the thesis detection claim misleading.

**Why it happens:** Modern AV/EDR signature databases cover every tool in the CTID plans. Defender's real-time protection is enabled by default in Windows. CALDERA's default agent (54ndc47) is a known signature.

**Consequences:**
- Zero emulation coverage because every tool is killed on landing
- Or: Elastic Defend in "prevention" mode produces detections that aren't technique-level detections — they're file-hash detections of known tools

**Warning signs:**
- CALDERA agent shows `agent lost` immediately after deploying on a victim
- Windows Event Log shows Defender events (Event ID 1116, 1117) at the exact time a CALDERA ability runs
- Elastic Defend alerts fire on "Malicious File" or "Ransomware" rules before the emulation step runs in the plan

**Prevention:**
- Set Elastic Defend to **detect mode, not prevention mode** on all victim VMs during emulation runs. This preserves telemetry while allowing execution.
- Disable Windows Defender real-time protection on victim VMs via Group Policy (`Computer Configuration > Windows Settings > Security Settings > Windows Defender`) — document this as an intentional lab configuration
- Alternatively, add exclusions for the lab tools directory (e.g., `C:\Tools\`) rather than disabling Defender entirely — this is more realistic and preserves some AV telemetry
- Test AV posture as part of the pre-emulation checklist: deploy a Mimikatz binary to the target, wait 30 seconds, verify it still exists

**Phase:** APT Plan Adaptation phase — establish AV policy before first emulation run.

---

### MODERATE — CALDERA Agent Cannot Reach the CALDERA Server

**What goes wrong:** The CALDERA agent (54ndc47 or sandcat) on a victim VM cannot connect to the CALDERA server's REST/WebSocket endpoint. Operations start but no abilities execute because no agent checks in.

**Why it happens:** CALDERA server runs on the attacker VM or a separate management host. The agent needs HTTP/HTTPS access to the CALDERA server port (default 8888 for HTTP, 4433 for HTTPS). Firewall rules or incorrect `server` parameter in the agent deployment command block the connection.

**Consequences:** CALDERA operation shows all abilities as `queued` indefinitely; no red team activity occurs; researcher doesn't notice until reviewing results.

**Warning signs:**
- CALDERA operation dashboard shows agent as "inactive" or "missing" shortly after deployment
- On the victim VM, `netstat -an | findstr 8888` shows no ESTABLISHED connection
- CALDERA server logs show no `GET /beacon` requests from the expected victim IP

**Prevention:**
- Before any emulation: verify agent connectivity with a simple test ability ("whoami" or "hostname")
- Use a static IP for the CALDERA server; include it in the `/etc/hosts` or DNS of all victim VMs
- Ensure the Proxmox internal bridge allows traffic between the attacker/CALDERA VM and victim VMs
- If using HTTPS C2 (recommended for realism), pre-install the CALDERA TLS certificate on victim VMs so SSL verification doesn't fail

**Phase:** Infrastructure phase (network routing); CALDERA Setup phase (agent deployment).

---

### MODERATE — OS Version Mismatches Break Specific Techniques

**What goes wrong:** CTID APT29 and Wizard Spider plans reference techniques (e.g., `PsExec` lateral movement, DCOM execution, named pipe impersonation) that behave differently across Windows versions. A technique validated on Windows Server 2016 may fail on Server 2019 due to patch level or behavioral changes.

**Why it happens:** The plans don't always specify the exact Windows build. SMB signing defaults changed in newer Windows versions, affecting lateral movement. PowerShell constrained language mode on hardened builds breaks Empire payloads. AMSI improvements block more reflective loading.

**Prevention:**
- Document the exact Windows build in the lab inventory (e.g., `Windows Server 2019 Datacenter, Build 17763.5329`)
- When a technique fails, first check if it's a version/patch issue before assuming a tooling bug
- Use the CTID plan's "Prerequisites" section and verify each one before running
- Keep victim VMs intentionally unpatched (disable Windows Update on lab VMs) to match realistic targets

**Phase:** APT Plan Adaptation phase.

---

### MINOR — CALDERA Fact Store Collisions Between Operations

**What goes wrong:** A CALDERA operation populates the fact store with discovered values (hostnames, credentials, file paths). If you run a second operation without clearing the fact store, stale facts from the first run are reused, producing incorrect or mixed-APT telemetry.

**Prevention:**
- Clear the CALDERA fact store between operations via the API: `DELETE /api/v2/facts`
- Or: use separate CALDERA sources per APT, with no cross-contamination
- The scripted reset should call the CALDERA API to flush facts as part of cleanup

**Phase:** Reset Mechanism phase.

---

## Layer 3: Elastic Stack Pitfalls

### CRITICAL — Fleet Server TLS Certificate Mismatch Blocks All Agent Enrollment

**What goes wrong:** Elastic Agents on victim VMs refuse to enroll with Fleet Server because the Fleet Server's TLS certificate doesn't include the correct SANs (Subject Alternative Names). The Fleet Server may be reachable by IP but the cert was generated for a hostname, or vice versa.

**Why it happens:** When deploying Elastic Stack in a lab, Fleet Server TLS is often configured with a self-signed cert generated during initial setup. If the FLEET_SERVER_HOST variable uses an IP but the cert's SAN only lists a hostname, enrollment fails with a TLS error. This is the single most common Fleet Server deployment failure in on-prem labs.

**Consequences:** No agents enroll; no telemetry is collected; the entire detection layer is silent.

**Warning signs:**
- `elastic-agent enroll` returns `x509: certificate is valid for elasticsearch, not 192.168.x.x`
- Fleet UI shows zero enrolled agents
- `elastic-agent` log on victim VM shows `Error: enroll command failed: fail to enroll: ... certificate signed by unknown authority`

**Prevention:**
- Generate the Fleet Server cert with both IP SAN and hostname SAN:
  `openssl req -x509 -newkey rsa:4096 -keyout fleet.key -out fleet.crt -sha256 -days 365 -nodes -addext "subjectAltName=IP:192.168.10.5,DNS:fleet.lab"`
- Distribute the CA certificate to all victim VMs via Group Policy (for Windows) or OS cert store (for Linux) before attempting enrollment
- Use a consistent internal DNS name for Fleet Server rather than IP — set it in the Proxmox internal DNS or `/etc/hosts` on all VMs
- Test enrollment on a single VM before provisioning the rest

**Phase:** Elastic Stack Setup phase.

---

### CRITICAL — Sysmon Schema Mismatch With Elastic Common Schema (ECS)

**What goes wrong:** Sysmon telemetry arrives in Elasticsearch but fields don't map to ECS field names. Detection rules that query `process.name`, `network.destination.ip`, or `file.path` return no results because the raw Sysmon data sits under `winlog.event_data.Image`, `winlog.event_data.DestinationIp`, etc.

**Why it happens:** There are two distinct deployment modes. If using Winlogbeat (standalone) to ship Sysmon logs, you must enable the Winlogbeat Sysmon module AND set `script.painless.regex.enabled: true` for the ECS normalization to run. If using Elastic Agent with the Windows integration, the ingest pipeline handles ECS mapping — but only for certain Sysmon event IDs.

**Consequences:** Detection rules built against ECS field names (which is every rule in Elastic's detection rule pack) produce zero matches. You see events in Kibana Discover but detections never fire.

**Warning signs:**
- Kibana Discover shows Sysmon events (EventID 1, 3, 7, etc.) but `process.name` field is missing
- An Elastic prebuilt detection rule for a known technique shows zero matches immediately after you confirmed the technique ran
- `GET /sysmon-*/_mapping` in Dev Tools shows `winlog.event_data.*` fields but no `process.*` fields

**Prevention:**
- Use Elastic Agent with the Windows integration (not standalone Winlogbeat) — this gives you the ingest pipeline that normalizes to ECS automatically
- After deploying, send a test Sysmon event (run `ping 8.8.8.8` to trigger a network event) and verify `network.destination.ip` appears in Elasticsearch — do this before any emulation
- Validate the Sysmon config covers the event IDs needed: at minimum EventID 1 (process create), 3 (network), 7 (image load), 8 (create remote thread), 10 (process access), 11 (file create), 12/13 (registry), 22 (DNS query)
- Use SwiftOnSecurity's Sysmon config as a baseline — it is well-maintained, community-validated, and covers the relevant event IDs without being so verbose it floods storage

**Phase:** Elastic Stack Setup phase — validate ECS mapping before first emulation run.

---

### CRITICAL — Elastic ML Jobs Need a Warm-Up Period; Running Immediately Gives Useless Results

**What goes wrong:** Elastic ML anomaly detection jobs are started and immediately queried for anomalies during the first emulation run. The jobs return either zero anomalies (insufficient baseline data) or a flood of anomalies (every behavior looks anomalous with no baseline).

**Why it happens:** Elastic ML unsupervised jobs build a behavioral baseline over time. The documentation recommends at least 4–8 hours of normal activity before anomalous activity is expected to be detectable. Jobs started fresh during an emulation run have no concept of "normal."

**Consequences:** Thesis claims "Elastic ML detected APT29 lateral movement" but the ML job was running for 30 minutes — a reviewer can legitimately dismiss this as meaningless.

**Warning signs:**
- ML job `model_size_stats.total_over_field_count` is very low (< 100) immediately after starting
- All processes show anomaly scores of 0 or all show scores > 80 with no discrimination

**Prevention:**
- Run a "normal operations" period of at least 24–48 hours on victim VMs before the first emulation run — users browsing, processes starting normally, DNS queries flowing
- Optionally: use a scripted normal-behavior generator (scheduled tasks opening Word, browsing to internal SharePoint, running SQL queries) to accelerate baseline building
- Document in the thesis that ML baselines were established for X hours before emulation — include the ML job start time and baseline period in the methodology
- Treat ML results as a supplementary detection layer, not the primary one — primary detections should come from rules against ECS-mapped events

**Phase:** Elastic Stack Setup phase (start ML jobs early); run baseline generation before APT emulation runs.

---

### MODERATE — Index Lifecycle Management (ILM) Rolls Indices During Long Runs

**What goes wrong:** Elasticsearch's default ILM policy for `logs-*` indices rolls over indices when they reach a size or age threshold. During a multi-day emulation exercise, the active index may roll over, causing queries that reference the old index alias to miss recent data.

**Why it happens:** Default ILM for Fleet/agent indices uses a rollover policy. In a high-volume lab (Sysmon on multiple VMs, Packetbeat, Elastic Defend all ingesting) it can hit the size threshold unexpectedly fast.

**Prevention:**
- In a lab context, disable or extend the ILM rollover policy: set the rollover size to `50gb` and age to `30d` — enough to cover a full thesis exercise period
- Query using the data stream name (`logs-endpoint.events.process-*`) rather than time-bound index names
- After each emulation run, export the relevant index to a snapshot or export NDJSON for the FullAPT-2025 dataset before ILM rolls it

**Phase:** Elastic Stack Setup phase.

---

### MODERATE — Elastic Defend Prevention Mode Blocks Techniques Before Sysmon Captures Them

**What goes wrong:** Elastic Defend in prevention mode terminates a malicious process so quickly that Sysmon EventID 1 (process create) fires but EventID 10 (process access) or EventID 8 (create remote thread) does not — the process was killed before it could do the protected action. The result is incomplete telemetry: you see the process but not the technique.

**Prevention:**
- Set Elastic Defend to **detect (not prevent)** on all victim VMs for emulation runs
- Document this as a deliberate lab configuration choice (detect-only = full telemetry capture)
- Separately validate that Elastic Defend's prevention capability works by running one test scenario in prevention mode and recording the prevention alert — then switch back to detect

**Phase:** APT Emulation phase — included in pre-emulation checklist.

---

### MINOR — Kibana Detection Rule Conflicts With Custom Rules

**What goes wrong:** Elastic's prebuilt detection rules are imported with the same rule IDs as custom rules you've written. On the next prebuilt rule update, your customizations are overwritten.

**Prevention:**
- Never edit prebuilt rules directly; instead, duplicate them and edit the copy
- Custom rules get a unique, thesis-specific naming convention: `[TSP] Rule Name`

**Phase:** Detection Engineering phase.

---

## Layer 4: Telemetry Pitfalls

### CRITICAL — Sysmon Config Too Narrow: Critical Events Silently Missing

**What goes wrong:** A minimal or improperly tuned Sysmon configuration excludes event IDs that are essential for detecting specific APT techniques. For example, if EventID 8 (CreateRemoteThread — used by process injection) is excluded or if EventID 10 (ProcessAccess — used by credential dumping via LSASS access) is not configured, entire MITRE technique categories produce no telemetry.

**Why it happens:** Default or beginner Sysmon configs often comment out "noisy" events (EventID 7 image load, EventID 3 network per-process) without understanding that specific detection rules depend on them.

**Consequences:** Technique is emulated and executes successfully, but no Sysmon event is generated, so no detection rule can fire. The thesis cannot claim detection of that technique.

**Warning signs:**
- Mimikatz `sekurlsa::logonpasswords` runs but no EventID 10 targeting `lsass.exe` appears in Elasticsearch
- A lateral movement technique using `CreateRemoteThread` runs but no EventID 8 appears
- `GET /_cat/indices/sysmon-*?v` shows very low event counts relative to the number of techniques run

**Prevention:**
- Use the SwiftOnSecurity sysmon-config as a starting point; it includes EventIDs 1, 2, 3, 5, 7, 8, 10, 11, 12, 13, 14, 15, 17, 18, 22, 23 by default
- Audit the config against the MITRE ATT&CK techniques in all three emulation plans before the first run — for each technique, identify which EventID is the expected telemetry source, and verify that EventID is `onmatch: exclude` (i.e., included) not `onmatch: include`
- After installing Sysmon, run a known-good test: execute `cmd.exe` and verify EventID 1 appears in Elasticsearch within 10 seconds — if not, the ingest pipeline is broken before emulation begins

**Phase:** Telemetry Setup phase (Sysmon configuration).

---

### CRITICAL — Sysmon Config Too Broad: Storage and Performance Collapse

**What goes wrong:** The opposite problem: an overly verbose Sysmon config (e.g., EventID 7 image load with no exclusions, EventID 3 network for all processes) generates hundreds of thousands of events per hour. Elasticsearch falls behind on ingest, index shards grow rapidly, and the Elastic node runs out of disk. Detection latency increases to the point that alerts fire minutes after the technique ran.

**Why it happens:** Security engineers copy a "maximum visibility" Sysmon config without accounting for lab hardware constraints. EventID 7 alone on a Windows server can generate 10,000+ events/hour without proper exclusions.

**Consequences:** Disk fills in hours; Elasticsearch circuit breaker trips; ingest stops; telemetry for the most critical technique window is missing.

**Warning signs:**
- `df -h` on the Elastic VM shows disk usage growing faster than expected
- Elasticsearch bulk API shows rejected requests (`TOO_MANY_REQUESTS`)
- Kibana Discover shows a huge gap in events (ingest outage) during the most active part of the emulation

**Prevention:**
- Add exclusions for noisy but low-value sources in the Sysmon config: exclude EventID 7 for known Microsoft-signed images (`\Windows\System32\*`), exclude EventID 3 for browser processes and Windows Update
- Monitor ingest rate in Kibana Stack Monitoring before running emulation: baseline the events/second during idle and estimate emulation load
- Pre-allocate disk with headroom: 100 GB minimum for the Elastic data directory for a full three-APT exercise

**Phase:** Telemetry Setup phase.

---

### MODERATE — Packetbeat Cannot Capture TLS-Encrypted C2 Traffic

**What goes wrong:** APT29 (and to a lesser extent OilRig) use HTTPS-based C2 channels. Packetbeat sees the TLS handshake and encrypted application data but cannot decode the payload. Network-layer detection relies only on IP/port metadata, not packet content.

**Why it happens:** Packetbeat operates at the network layer without TLS key material. It cannot decrypt HTTPS traffic. This is a fundamental, documented limitation.

**Consequences:** Network-based detection for HTTPS C2 is limited to behavioral heuristics (beaconing interval, unusual destination IPs) rather than content inspection. If the thesis claims "Packetbeat detected the C2 channel," this needs careful qualification.

**Warning signs:**
- Packetbeat shows flows to C2 IP on port 443 with `type: tls` but no decoded HTTP fields
- Expected `http.request.method` field is absent for HTTPS-based C2

**Prevention:**
- Be explicit in the thesis: Packetbeat provides network metadata (flow volume, beaconing cadence, connection counts) for encrypted channels, not content inspection
- For the CALDERA C2 channel specifically, consider using the HTTP (not HTTPS) protocol in the lab — this is a legitimate simplification for a research lab and produces richer Packetbeat telemetry
- Supplement network telemetry with Sysmon EventID 3 (network connection) on the host side — this captures the process-to-IP binding that Packetbeat's flow data lacks

**Phase:** Telemetry Setup phase — documented as a known limitation.

---

### MODERATE — Log Shipping Delays Cause Misattribution of Technique Timing

**What goes wrong:** Elastic Agent batches and ships log events with a configurable flush interval (default 3–10 seconds). During high-activity periods, events from a 30-second burst of technique execution can arrive in Elasticsearch over 2–3 minutes, with timestamps that are correct but ingest times that trail actual execution. Attack chain visualizations in Kibana Timeline show events "out of order" if you sort by `@timestamp` vs. `event.ingested`.

**Why it happens:** Normal Elastic Agent behavior under load. Not a bug, but creates confusion when analyzing results.

**Prevention:**
- Always use `@timestamp` (the original event time from Sysmon/Windows) not `event.ingested` for timeline reconstruction
- Reduce Elastic Agent's flush interval for lab use: set `output.elasticsearch.flush_interval: 1s` in the agent policy to reduce buffering
- Document the expected timestamp fields in the thesis methodology section

**Phase:** Telemetry Setup phase.

---

### MINOR — Packetbeat AF_PACKET Requires Specific NIC Mode on Proxmox

**What goes wrong:** Packetbeat using `af_packet` capture on a Linux VM under Proxmox needs the VirtIO NIC to support promiscuous mode. Without this, Packetbeat only sees traffic originating from or destined to that VM, not lateral traffic between two victim VMs on the same bridge.

**Prevention:**
- For the dedicated network monitoring VM (if used), enable promiscuous mode on the Proxmox bridge: `ip link set vmbr1 promisc on`
- Or deploy Packetbeat on each individual victim VM (captures only that host's traffic, which is sufficient for per-host telemetry)

**Phase:** Telemetry Setup phase.

---

## Layer 5: Reset Mechanism Pitfalls

### CRITICAL — Elastic Agent Loses Enrollment After VM Restore

**What goes wrong:** After restoring a VM to its baseline snapshot, the Elastic Agent on the restored VM has a different agent ID (or the same ID but revoked credentials) than what Fleet Server expects. The agent appears as "inactive" in Fleet UI and stops shipping telemetry.

**Why it happens:** Elastic Agent enrollment generates a unique enrollment token and agent ID that is stored both on the agent (in `/etc/elastic-agent/state/`) and registered in Fleet Server. When you restore a VM to a pre-enrollment snapshot, either: (a) the agent ID is reset to a state Fleet Server doesn't recognize, or (b) the snapshot was taken after enrollment but the Fleet Server re-enrolled state is now stale.

**Consequences:** After every reset, telemetry collection silently stops. The researcher notices only when checking Kibana and seeing no new events.

**Prevention (two valid approaches):**
- **Approach A (recommended):** Take the baseline snapshot **after** successful Elastic Agent enrollment and after verifying the agent appears as "healthy" in Fleet. Restore restores the enrolled state. This works as long as Fleet Server is not also restored to a pre-enrollment state.
- **Approach B:** Include a re-enrollment step in the reset script: after VM restore, run `elastic-agent enroll --url https://fleet.lab --enrollment-token <token>` automatically via a startup script (Windows Task Scheduler or systemd). The enrollment token from Fleet does not expire unless explicitly revoked.
- Always verify agent health after every reset as part of the pre-emulation checklist

**Phase:** Reset Mechanism phase — design decision must be made before taking baseline snapshots.

---

### CRITICAL — Windows Domain Trust Breaks If DC Is Restored to an Older USN

**What goes wrong:** Active Directory uses Update Sequence Numbers (USNs) to track replication state. When you restore the DC VM to a snapshot that predates recent AD changes (e.g., new user accounts, GPO changes made during setup), the DC's USN rolls back. Any member servers (Exchange, SQL) that have cached a higher USN from replication will refuse to authenticate to the restored DC, producing Kerberos errors and domain join failures.

**Why it happens:** AD explicitly detects "USN rollback" as a replication error and may quarantine the restored DC. Windows member machines cache DC state and notice the inconsistency.

**Consequences:** After reset, users cannot log into domain-joined VMs; Kerberos errors flood the event log; emulation cannot proceed because domain authentication is required for lateral movement techniques.

**Warning signs:**
- After restore, Event ID 2095 appears on the DC: "Active Directory Domain Services detected that the virtual machine running this domain controller may have been restored."
- Member VMs get `NETLOGON` errors (Event ID 5722 on the DC)
- `nltest /sc_verify:<domain>` from a member server returns `ERROR_NO_LOGON_SERVERS`

**Prevention:**
- Take all VM snapshots (DC + all members) at the same moment, before any AD changes that occur during emulation
- Use a snapshot script that quiesces all VMs simultaneously then snapshots all — never snapshot VMs at different times if AD is involved
- Enable VM Generation ID support in Proxmox (enabled by default for Windows VMs with QEMU machine type q35) — this triggers AD's USN rollback recovery mechanism automatically on restore, instead of quarantining the DC
- Alternatively: keep the lab AD simple — no Exchange integration, no complex GPOs — so there's minimal AD state to drift

**Phase:** Infrastructure phase (snapshot design) and Reset Mechanism phase.

---

### MODERATE — CALDERA Agent State Is Not Cleared After VM Restore

**What goes wrong:** If the CALDERA agent was running when the VM was snapshotted, the restored VM re-launches the CALDERA agent with the old agent ID and paw (agent identifier). CALDERA server may have a stale entry for this agent from a previous operation. New operations may use the stale agent entry or duplicate entries may confuse the operation planner.

**Prevention:**
- Do not include the CALDERA agent binary in the baseline snapshot. Instead, the baseline snapshot should have clean VMs with no agent. Deploy the CALDERA agent as the first step of each emulation run (CALDERA can do this via its initial access ability or a bootstrap script).
- After restore, call the CALDERA API to remove stale agent entries: `DELETE /api/v2/agents/<paw>`
- Include CALDERA fact store flush and agent cleanup in the reset script

**Phase:** Reset Mechanism phase.

---

### MODERATE — Elasticsearch Data Persists After VM Restore If Elastic Is on a Separate Persistent Volume

**What goes wrong:** If the Elastic VM's data directory (`/var/lib/elasticsearch`) is on a separate Proxmox volume that is NOT included in the snapshot, restoring the OS snapshot does not reset the data. The previous emulation's events remain in the index, contaminating the next run's dataset.

**Prevention:**
- Store Elasticsearch data on a volume that IS included in the snapshot
- OR: implement a per-run index naming convention (`sysmon-apt29-run1`, `sysmon-apt29-run2`) and delete the previous run's index via the Elasticsearch API before each new run — this approach is more resilient and avoids the snapshot-size overhead of including large Elastic data volumes in the VM snapshot

**Phase:** Reset Mechanism phase.

---

### MINOR — Windows Activation Fails After Repeated Restores

**What goes wrong:** Windows Server VMs with KMS activation can reach their reactivation limit after many snapshot restores that change the hardware ID fingerprint. VMs enter a grace period countdown, eventually watermarking the desktop.

**Prevention:**
- Use Windows Server Evaluation editions for lab VMs (180-day evaluation, no activation required)
- OR use KMS server within the lab network (Windows Server can serve as KMS for itself in a lab)

**Phase:** Infrastructure phase.

---

## Layer 6: Documentation and Thesis Pitfalls

### CRITICAL — Detection Claims Are Unverifiable Because Evidence Is Screenshots

**What goes wrong:** The thesis states "Elastic SIEM detected credential dumping by APT29 (T1003.001)" and includes a screenshot of a Kibana alert. The thesis committee cannot verify whether this alert was actually triggered by the emulation, was a false positive, was manually crafted, or was cherry-picked from a noisy detection environment.

**Why it happens:** Screenshots are easy; structured evidence is harder. Researchers default to "it looks good in the UI."

**Consequences:** A technically competent reviewer will dismiss screenshot-only evidence. For a Trabajo de Suficiencia Profesional, the documentation must demonstrate professional rigor — the same standard that would apply to reporting findings to a client.

**Prevention:**
- Export detection results as structured data, not screenshots: use the Elasticsearch API to export matched events as NDJSON or CSV — include the raw event fields, not just the alert
- For each detection claim, provide the full detection evidence chain:
  1. The CALDERA ability that ran (by operation ID, timestamp)
  2. The resulting Sysmon/Elastic Defend event (by `event.id`, `@timestamp`, field values)
  3. The detection rule that matched (by rule name, rule ID, alert `_id` in Elasticsearch)
- The FullAPT-2025 dataset (NDJSON corpus) serves as the verifiable artifact — reference it in every detection claim
- Include the detection rule definition (YAML/JSON) in an appendix — not just the rule name

**Phase:** Detection Engineering phase (establish evidence standards); Documentation phase (apply consistently).

---

### CRITICAL — Emulation Is Not Reproducible: "It Worked Once"

**What goes wrong:** The emulation ran once, produced results, and the thesis documents those results. When the thesis committee asks "can you run it again?" or when the researcher tries to reproduce during writing, something breaks: a CALDERA ability fails, the Elastic agent is unenrolled, Windows Update changed something, the Sysmon config was tweaked. The results cannot be reproduced.

**Why it happens:** Lab environments drift. Changes accumulate between runs. Without a scripted reset to a known-clean state, the environment is a snowflake.

**Consequences:** The entire premise of the thesis — a reproducible, resettable Cyber Range — is undermined.

**Prevention:**
- The scripted reset mechanism is not a nice-to-have — it is the thesis's core proof of reproducibility. Implement it before the first documented emulation run.
- Run each APT scenario at least three times and document all three runs. Variance between runs reveals environmental instability; consistency proves reproducibility.
- Keep a run log: date, CALDERA operation ID, techniques that executed, detections fired, anomalies from expected — one row per run
- Lock the VM snapshots: after establishing the baseline, do not make changes to victim VMs outside of a documented configuration change record

**Phase:** Reset Mechanism phase (implement before emulation); Documentation phase (enforce run log discipline).

---

### CRITICAL — Thesis Conflates "Technique Emulated" With "Technique Detected"

**What goes wrong:** The results section reports "117 MITRE ATT&CK techniques covered" but does not distinguish between techniques that were emulated and techniques that were detected. A detection rate of 100% would be suspicious; no analysis of detection gaps makes the methodology look unsophisticated.

**Why it happens:** The researcher is proud of the coverage number and doesn't want to highlight what wasn't detected.

**Consequences:** A technically rigorous reviewer immediately asks: "What percentage of techniques produced a detection? What is the false negative rate?" No answer = weak thesis.

**Prevention:**
- Build a three-column results table: `Technique ID | Emulated (Y/N) | Detected (Y/N) | Detection Method (Rule/ML/None)`
- Analyze and discuss detection gaps — techniques that were emulated but not detected — this is **more impressive** than claiming 100% detection, because it shows the researcher understands the limits of the detection architecture
- Frame false negatives as research findings: "T1055.012 (Process Hollowing) was emulated but not detected because Sysmon EventID 8 was excluded by the config — this gap was corrected in the next run"

**Phase:** Documentation phase.

---

### MODERATE — No Quantitative Baseline Makes ML Claims Unverifiable

**What goes wrong:** The thesis claims Elastic ML anomaly detection identified C2 beaconing behavior. But there is no documented baseline period, no ML model statistics, and no comparison of anomaly scores between the normal period and the attack period.

**Prevention:**
- Document the ML job configuration in full: job ID, detector function, `by_field`, `over_field`, bucket span, model memory limit
- Record the model's bucket results as a time series — include anomaly score over time as a figure in the thesis, with the emulation window clearly annotated
- Report both the highest anomaly score during normal operations and during the attack — the delta is the signal

**Phase:** Detection Engineering phase (design ML evidence framework); Documentation phase (execute it).

---

### MODERATE — Dataset Completeness Is Asserted, Not Demonstrated

**What goes wrong:** The thesis states the FullAPT-2025 dataset contains "117 MITRE ATT&CK techniques" but provides no mapping between the claimed techniques and the actual events in the dataset. Reviewers cannot verify the claim.

**Prevention:**
- Generate a technique-to-event mapping table programmatically from the Elasticsearch data: for each technique ID, query `threat.technique.id:<techniqueID>` and report the event count
- Include this table as an appendix — it demonstrates rigor and makes the dataset claim verifiable without requiring the reviewer to access the raw data
- For events without `threat.technique.id` fields (Sysmon raw events), include the inference chain: "EventID 1 with `Image: C:\Windows\System32\lsass.exe` as parent → T1003.001 (LSASS Memory)"

**Phase:** Documentation phase.

---

### MINOR — Thesis Omits Infrastructure Details, Making Reproduction Impossible

**What goes wrong:** The methodology section says "an Elastic Stack SIEM was deployed" without specifying the version, configuration, or ingest pipeline. Someone attempting to replicate the lab cannot do so.

**Prevention:**
- Include an appendix with exact versions of all components: Elasticsearch 8.x.x, Kibana 8.x.x, Fleet Server 8.x.x, Elastic Agent 8.x.x, Sysmon version, Sysmon config hash, CALDERA version, Proxmox version
- The GitHub Pages setup guide covers this — reference it formally in the thesis methodology section
- Include the Sysmon XML config file (or its git hash) in the thesis appendix

**Phase:** Documentation phase.

---

## Phase-Specific Warning Matrix

| Phase | Most Likely Pitfall | Mitigation |
|-------|--------------------|-----------| 
| Infrastructure Setup | Network isolation failure; resource exhaustion | Gate test: victim VM cannot reach internet; measure RAM under full load before committing |
| Snapshot Design | DC USN rollback after restore; Elasticsearch data not in snapshot | Snapshot all VMs simultaneously; verify AD health after first restore |
| Elastic Stack Setup | Fleet Server TLS cert SAN mismatch; Sysmon-to-ECS mapping broken | Verify enrollment on one VM before fleet deployment; send test event and check ECS fields |
| Sysmon/Packetbeat Setup | Config too narrow (missing critical EventIDs); log shipping delay confusion | Audit EventIDs vs. technique requirements; test each EventID with a known action |
| CALDERA Setup | Agent cannot reach server; AV blocks agent before it runs | Test agent connectivity with a trivial ability; disable/exclude Defender on lab VMs |
| APT Plan Adaptation | Tool version mismatches; techniques silently failing | Validate every ability manually before packaging in CALDERA adversary |
| Elastic ML Baseline | No warmup period; ML results meaningless | Start ML jobs ≥48h before first emulation; run a scripted normal-behavior generator |
| Emulation Runs | Elastic Defend in prevention mode; CALDERA fact store pollution | Pre-run checklist: Defend = detect mode; clear fact store; verify agent health |
| Reset Mechanism | Agent re-enrollment failure; CALDERA stale agent state | Verify agent health after every reset; automate re-enrollment or pre-enroll in baseline |
| Detection Engineering | Rules using non-ECS field names returning zero results | Write rules in Dev Console with live data; verify field names against actual events |
| Documentation | Screenshot-only evidence; emulated ≠ detected distinction missing | Export API evidence; build three-column results table for every technique |

---

## Sources

**Confidence note:** All findings are drawn from training knowledge (cutoff August 2025). No external documentation was accessible in this session. Confidence is HIGH for well-established behaviors (Elastic Fleet TLS enrollment, Sysmon ECS mapping, AD USN rollback, CALDERA architecture) based on deep domain overlap with training data. Confidence is MEDIUM for specific version behavior (Elastic 8.x Fleet Server defaults, CALDERA 4.x fact store API endpoints) — validate against current official docs during implementation.

- Elastic Fleet troubleshooting: https://www.elastic.co/guide/en/fleet/current/fleet-troubleshooting.html
- Elastic Agent TLS: https://www.elastic.co/guide/en/fleet/current/secure-connections.html
- Sysmon ECS mapping with Elastic Agent Windows integration: https://docs.elastic.co/en/integrations/system
- CTID adversary emulation library: https://github.com/center-for-threat-informed-defense/adversary_emulation_library
- CALDERA documentation: https://caldera.readthedocs.io/
- SwiftOnSecurity Sysmon config: https://github.com/SwiftOnSecurity/sysmon-config
- AD virtualization safeguards (VM Generation ID): https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/get-started/virtual-dc/virtualized-domain-controller-architecture
- Proxmox snapshot quiesce: https://pve.proxmox.com/wiki/Backup_and_Restore
