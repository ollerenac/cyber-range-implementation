# =============================================================================
# 09-elastic-agent.ps1 — Install and enroll Elastic Agent on Windows VMs
#
# DELIVERY METHOD:
#   Run via Invoke-Command from elastic-vm by enroll-agents.sh (plan 03-03)
#   Do NOT run interactively — designed for WinRM scriptblock delivery
#
# EXPECTED ENV VARS (injected by enroll-agents.sh before Invoke-Command):
#   $env:FLEET_TOKEN — Fleet enrollment token for the windows-target policy
#   $env:VM_ROLE     — "server" or "workstation" (controls Sysmon config selection)
#
# SEQUENCE (per D-07 in 03-CONTEXT.md):
#   1. Npcap tier-1 verify (wpcap.dll check — do NOT attempt silent install)
#   2. Elastic Agent idempotency guard (uninstall if already present)
#   3. Download elastic-agent installer from elastic-vm HTTP server
#   4. Install and enroll with Fleet Server (with CA cert validation)
#   5. Deploy Sysmon with role-appropriate XML config
#   6. Verify Elastic Agent service running
#
# PREREQUISITES (must be satisfied by enroll-agents.sh BEFORE this script runs):
#   - C:\Temp\ca.crt must exist — Fleet CA cert copied from elastic-vm via WinRM
#   - HTTP file server running on elastic-vm: http://10.0.0.10:8080
#   - Fleet policy "windows-target" must already exist in Kibana (plan 03-02 Task 2)
#   - Elastic Defend must be in DETECT mode in the policy (D-13 hard requirement)
#
# CA CERT PATH:
#   C:\Temp\ca.crt — copied from elastic-vm:/etc/elasticsearch/certs/ca.crt (D-08)
#
# VM IPs (MGMT NIC): dc01=10.0.0.11, exchange01=10.0.0.12, sql01=10.0.0.13,
#                     ws01=10.0.0.14, ws02=10.0.0.15
# Fleet Server URL: https://10.0.0.10:8220
# Elastic Stack version: 8.19.16 (pinned — all components match)
# =============================================================================

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("server", "workstation")]
    [string]$VmRole,

    [Parameter(Mandatory = $true)]
    [string]$FleetToken
)

$ErrorActionPreference = "Continue"

Write-Host "================================================================"
Write-Host "09-elastic-agent.ps1 — Elastic Agent + Sysmon enrollment"
Write-Host "Host: $env:COMPUTERNAME | Role: $VmRole"
Write-Host "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "================================================================"

# Ensure C:\Temp exists
if (-not (Test-Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp" | Out-Null
    Write-Host "[INFO] Created C:\Temp"
}

# ---------------------------------------------------------------------------
# STEP 1: Npcap tier-1 check (D-14 three-tier strategy from RESEARCH.md Pitfall 1)
#
# Tier 1: Detect via wpcap.dll presence — do NOT attempt silent /S install
#         (Npcap /S is OEM-only; the free public installer ignores /S on headless sessions)
# Tier 2: Elastic Agent auto-installs bundled OEM Npcap — detected after enrollment
# Tier 3: Operator manual RDP session for Npcap GUI install (one-time; persists in snapshot)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- STEP 1: Npcap tier-1 check ---"
$NpcapDll = "C:\Windows\System32\Npcap\wpcap.dll"
if (Test-Path $NpcapDll) {
    Write-Host "[OK] Npcap already installed ($NpcapDll exists)"
} else {
    Write-Host "[WARN] Npcap not found at $NpcapDll"
    Write-Host "[WARN] Will attempt elastic-agent auto-install; verify Packetbeat status after enrollment"
    Write-Host "[WARN] If Packetbeat shows Degraded, run manual Npcap installer (RESEARCH.md Pitfall 1 Tier 3)"
}

# ---------------------------------------------------------------------------
# STEP 2: Elastic Agent idempotency guard (RESEARCH.md Pitfall 6)
#
# If Elastic Agent service exists, uninstall first to avoid --non-interactive
# install error "Elastic Agent is already installed"
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- STEP 2: Elastic Agent idempotency guard ---"
$svc = Get-Service "Elastic Agent" -ErrorAction SilentlyContinue
if ($null -ne $svc) {
    Write-Host "[INFO] Elastic Agent service found (Status: $($svc.Status)) — uninstalling existing installation"
    $agentExe = "C:\Program Files\Elastic\Agent\elastic-agent.exe"
    if (Test-Path $agentExe) {
        & "$agentExe" uninstall --non-interactive --force
        Write-Host "[INFO] elastic-agent uninstall completed (exit code: $LASTEXITCODE)"
    } else {
        Write-Host "[WARN] Service found but elastic-agent.exe not at expected path — proceeding anyway"
    }
    Start-Sleep -Seconds 5
} else {
    Write-Host "[OK] No existing Elastic Agent service found — clean install"
}

# ---------------------------------------------------------------------------
# STEP 3: Download elastic-agent installer from elastic-vm HTTP server
#
# HTTP server runs on elastic-vm (10.0.0.10:8080) — served via Python http.server
# Download over MGMT NIC (10.0.0.0/24) — no internet access required
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- STEP 3: Download elastic-agent 8.19.16 installer ---"
$AgentZip = "C:\Temp\elastic-agent-8.19.16-windows-x86_64.zip"
$AgentExtract = "C:\Temp\elastic-agent"
$AgentUrl = "http://10.0.0.10:8080/elastic-agent-8.19.16-windows-x86_64.zip"

Write-Host "[INFO] Downloading: $AgentUrl"
try {
    Invoke-WebRequest -Uri $AgentUrl -OutFile $AgentZip -UseBasicParsing
    Write-Host "[OK] Downloaded to $AgentZip ($(((Get-Item $AgentZip).Length / 1MB).ToString('F1')) MB)"
} catch {
    Write-Host "[ERROR] Download failed: $_"
    Write-Host "[ERROR] Verify HTTP server is running: ssh elastic@10.0.0.10 'curl -s http://127.0.0.1:8080/'"
    exit 1
}

Write-Host "[INFO] Expanding archive to $AgentExtract"
if (Test-Path $AgentExtract) {
    Remove-Item -Recurse -Force $AgentExtract
}
Expand-Archive -Path $AgentZip -DestinationPath $AgentExtract -Force
Write-Host "[OK] Archive expanded"

# ---------------------------------------------------------------------------
# STEP 4: Install and enroll Elastic Agent with Fleet Server
#
# Flags per RESEARCH.md Pattern 1:
#   --non-interactive            — no GUI dialogs on headless WinRM session
#   --url                        — Fleet Server address (MGMT IP, port 8220)
#   --enrollment-token           — token from windows-target policy (plan 03-02 Task 2)
#   --certificate-authorities    — Fleet CA cert (copied by enroll-agents.sh before this script)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- STEP 4: Install and enroll Elastic Agent ---"
$AgentDir = "$AgentExtract\elastic-agent-8.19.16-windows-x86_64"
if (-not (Test-Path "$AgentDir\elastic-agent.exe")) {
    Write-Host "[ERROR] elastic-agent.exe not found at expected path: $AgentDir"
    Write-Host "[ERROR] Archive contents:"
    Get-ChildItem $AgentExtract -Recurse -Depth 2 | Select-Object FullName
    exit 1
}

Write-Host "[INFO] Installing elastic-agent from $AgentDir"
Set-Location $AgentDir

# elastic-agent.exe install flags documented in RESEARCH.md Pattern 1
$installArgs = @(
    "install",
    "--non-interactive",
    "--url=https://10.0.0.10:8220",
    "--enrollment-token=$FleetToken",
    "--certificate-authorities=C:\Temp\ca.crt"
)
Write-Host "[INFO] Running: elastic-agent.exe install --non-interactive --url=https://10.0.0.10:8220 ..."
& ".\elastic-agent.exe" @installArgs

$installExitCode = $LASTEXITCODE
if ($installExitCode -ne 0) {
    Write-Host "[ERROR] elastic-agent install exited with code $installExitCode"
    Write-Host "[ERROR] Check Fleet Server connectivity: curl -sk https://10.0.0.10:8220"
    Write-Host "[ERROR] Verify CA cert at C:\Temp\ca.crt exists"
} else {
    Write-Host "[OK] elastic-agent install completed (exit code: $installExitCode)"
}

# ---------------------------------------------------------------------------
# STEP 5: Deploy Sysmon with role-appropriate XML config
#
# Server config   (dc01, exchange01, sql01): sysmon-server.xml
#   EventIDs: 1, 3, 7, 10, 11, 12/13/14, 17/18, 22 (D-09)
# Workstation config (ws01, ws02): sysmon-workstation.xml
#   EventIDs: server EIDs + 15, 23, 25, 26 (D-10)
#
# Sysmon64.exe and XML served from elastic-vm HTTP (staged in plan 03-02 Task 1)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- STEP 5: Deploy Sysmon ($VmRole config) ---"
$SysmonXml = if ($VmRole -eq "workstation") { "sysmon-workstation.xml" } else { "sysmon-server.xml" }
$SysmonExe = "C:\Temp\Sysmon64.exe"
$SysmonConfig = "C:\Temp\sysmon.xml"

Write-Host "[INFO] Sysmon config: $SysmonXml (role: $VmRole)"
Write-Host "[INFO] Downloading Sysmon64.exe from elastic-vm HTTP"
try {
    Invoke-WebRequest -Uri "http://10.0.0.10:8080/Sysmon64.exe" -OutFile $SysmonExe -UseBasicParsing
    Write-Host "[OK] Sysmon64.exe downloaded"
} catch {
    Write-Host "[ERROR] Failed to download Sysmon64.exe: $_"
    exit 1
}

Write-Host "[INFO] Downloading Sysmon config: $SysmonXml"
try {
    Invoke-WebRequest -Uri "http://10.0.0.10:8080/$SysmonXml" -OutFile $SysmonConfig -UseBasicParsing
    Write-Host "[OK] Sysmon config downloaded to $SysmonConfig"
} catch {
    Write-Host "[ERROR] Failed to download Sysmon config: $_"
    exit 1
}

$existingSvc = Get-Service "Sysmon64" -ErrorAction SilentlyContinue
if ($null -ne $existingSvc) {
    Write-Host "[INFO] Sysmon64 service already exists — updating config only"
    & $SysmonExe -c $SysmonConfig
    Write-Host "[INFO] Sysmon config update exit code: $LASTEXITCODE"
} else {
    Write-Host "[INFO] Installing Sysmon64 (first time)"
    & $SysmonExe -accepteula -i $SysmonConfig
    Write-Host "[INFO] Sysmon install exit code: $LASTEXITCODE"
}

Write-Host "[INFO] Sysmon64 service status:"
Get-Service "Sysmon64" -ErrorAction SilentlyContinue | Select-Object Status, StartType

# ---------------------------------------------------------------------------
# STEP 6: Verify Elastic Agent service running
#
# Allow 10 seconds for service to stabilize after install+enroll
# Fleet connection may take additional time (30-60s for first check-in)
# If Packetbeat shows Degraded, Npcap auto-install may have failed (Pitfall 1)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- STEP 6: Verify Elastic Agent service ---"
Start-Sleep -Seconds 10
$agentSvc = Get-Service "Elastic Agent" -ErrorAction SilentlyContinue
if ($null -ne $agentSvc) {
    Write-Host "Elastic Agent service: $($agentSvc.Status)"
    if ($agentSvc.Status -ne "Running") {
        Write-Host "[WARN] Elastic Agent service is not Running — check 'elastic-agent status' on this VM"
    }
} else {
    Write-Host "[ERROR] Elastic Agent service not found after install — check install logs"
}

# Post-enrollment Npcap verification (tier-2 check after elastic-agent auto-install)
Write-Host ""
Write-Host "--- Npcap post-enrollment check ---"
if (Test-Path $NpcapDll) {
    Write-Host "[OK] Npcap installed ($NpcapDll present) — Packetbeat should start correctly"
} else {
    Write-Host "[WARN] Npcap wpcap.dll still not found after elastic-agent install"
    Write-Host "[WARN] Elastic Agent auto-install of OEM Npcap may have failed (RESEARCH.md Pitfall 1 issue #6108)"
    Write-Host "[WARN] If Packetbeat shows 'Degraded' in Fleet, perform Tier 3 manual install:"
    Write-Host "[WARN]   1. RDP to $env:COMPUTERNAME"
    Write-Host "[WARN]   2. Download Npcap installer from http://10.0.0.10:8080/npcap-installer.exe"
    Write-Host "[WARN]   3. Run installer GUI — accept defaults, enable WinPcap compatibility"
    Write-Host "[WARN]   4. Restart Elastic Agent service: Restart-Service 'Elastic Agent'"
}

Write-Host ""
Write-Host "================================================================"
Write-Host "[DONE] 09-elastic-agent.ps1 complete on $env:COMPUTERNAME"
Write-Host "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "================================================================"
