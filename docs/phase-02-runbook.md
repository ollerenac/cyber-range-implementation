<!-- generated-by: gsd-doc-writer -->
# Phase 02 — Windows Target Network

> **Status:** ✅ Complete · All scripts authored and hardware checkpoint approved

This runbook covers provisioning the five Windows target VMs (dc01, exchange01, sql01, ws01, ws02), promoting the domain controller, installing Exchange Server 2019 and SQL Server 2019, applying the security baseline, and configuring workstations.

---

## VM Topology

| VM | VMID | Host | RAM | Disk | MGMT IP | TARGET IP | Role |
|----|------|------|-----|------|---------|-----------|------|
| dc01 | 201 | Host 2 | 4 GB | 60 GB | 10.0.0.11 | 10.10.10.10 | Domain Controller (lab.local) |
| exchange01 | 301 | Host 3 | 10 GB | 120 GB | 10.0.0.12 | 10.10.10.20 | Exchange Server 2019 / EWS |
| sql01 | 202 | Host 2 | 5 GB | 80 GB | 10.0.0.13 | 10.10.10.30 | SQL Server 2019 / sitedata DB |
| ws01 | 401 | Host 4 | 4 GB | 60 GB | 10.0.0.14 | 10.10.10.40 | Workstation — Dorothy (initial access target) |
| ws02 | 402 | Host 4 | 4 GB | 60 GB | 10.0.0.15 | 10.10.10.50 | Workstation — Toto (lateral movement target) |

Each VM has two NICs:
- **net0 → vmbr1** (TARGET 10.10.10.0/24) — emulation traffic, air-gapped
- **net1 → vmbr0** (MGMT 10.0.0.0/24) — WinRM, Elastic Agent, SSH from control node

!!! note
    The MGMT subnet (vmbr0) has internet access for ISO downloads and package installs.
    The TARGET subnet (vmbr1) is air-gapped — no internet, no inter-VLAN routing.

---

## Step 1 — Prepare ISO Files and Credential Templates

### Prerequisites
- Phase 1 complete — vmbr0/vmbr1 bridges on all Proxmox hosts, elastic-vm and caldera-vm running
- Access to the Proxmox web UI and SSH root access to Hosts 2, 3, 4
- Windows Server 2019 Evaluation ISO and Windows 10 Enterprise Evaluation ISO downloaded from Microsoft Evaluation Center
- VirtIO drivers ISO downloaded from [Fedora People](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/)

### Download and place ISOs

Place the following files in `/var/lib/vz/template/iso/` on each relevant host:

| File | Required on |
|------|------------|
| `WS2019-eval.iso` | Hosts 2 and 3 (dc01, sql01, exchange01) |
| `Win10-eval.iso` | Host 4 (ws01, ws02) |
| `virtio-win.iso` | Hosts 2, 3, and 4 |

!!! warning
    The scripts expect **exactly** these filenames: `WS2019-eval.iso`, `Win10-eval.iso`, and `virtio-win.iso`.
    Rename your downloaded files before running `provision-windows.sh`.

### Fill in credential templates

The autounattend XMLs committed to the repo use the placeholder `OPERATOR_SETS_PASSWORD`. You must create local copies with real passwords before building ISOs.

1. Copy the XML templates to the secrets directory:

    ```bash
    cp scripts/windows/autounattend/dc01-autounattend.xml .planning/secrets/dc01-autounattend.xml
    cp scripts/windows/autounattend/exchange01-autounattend.xml .planning/secrets/exchange01-autounattend.xml
    cp scripts/windows/autounattend/sql01-autounattend.xml .planning/secrets/sql01-autounattend.xml
    cp scripts/windows/autounattend/ws01-autounattend.xml .planning/secrets/ws01-autounattend.xml
    cp scripts/windows/autounattend/ws02-autounattend.xml .planning/secrets/ws02-autounattend.xml
    ```

2. In each `.planning/secrets/*.xml` copy, replace every occurrence of `OPERATOR_SETS_PASSWORD` with the actual Administrator password for that VM. Record passwords in `.planning/secrets/PASSWORDS.md` (gitignored).

!!! warning
    ws01 and ws02 **must share the same local Administrator password**. This is required for APT29 Pass-the-Hash lateral movement in later scenarios.

!!! note
    `.planning/secrets/` is gitignored. Never commit real passwords or the filled-in XML copies to the repository.

### Build unattend ISOs

Run once on the Proxmox host that has access to `.planning/secrets/` (or copy secrets to the host first):

```bash
bash scripts/proxmox/build-unattend-isos.sh
```

This produces five ISOs in `/var/lib/vz/template/iso/`:

```text
/var/lib/vz/template/iso/unattend-dc01.iso
/var/lib/vz/template/iso/unattend-exchange01.iso
/var/lib/vz/template/iso/unattend-sql01.iso
/var/lib/vz/template/iso/unattend-ws01.iso
/var/lib/vz/template/iso/unattend-ws02.iso
```

If `genisoimage` is missing, the script will print the install command:

```bash
apt-get install -y genisoimage
```

---

## Step 2 — Provision Windows VMs on Proxmox

Run `provision-windows.sh` once per Proxmox host, passing the host number as argument:

```bash
# On Proxmox Host 2 (dc01 and sql01)
bash scripts/proxmox/provision-windows.sh 2

# On Proxmox Host 3 (exchange01)
bash scripts/proxmox/provision-windows.sh 3

# On Proxmox Host 4 (ws01 and ws02)
bash scripts/proxmox/provision-windows.sh 4
```

Each run shows a VM table and prompts for confirmation before creating any VMs. Review the table carefully before typing `y`.

### Start the VMs and wait for unattended install

```bash
# On Host 2
qm start 201   # dc01
qm start 202   # sql01

# On Host 3
qm start 301   # exchange01

# On Host 4
qm start 401   # ws01
qm start 402   # ws02
```

Windows Setup runs fully unattended. Each VM takes approximately 15–20 minutes to complete setup and reboot to the desktop. Monitor progress in the Proxmox web UI console.

### Detach install media after OS setup completes

Once each VM has rebooted to the Windows desktop, detach the installation ISOs:

```bash
# Replace VMID with each VM's ID (201, 202, 301, 401, 402)
qm set VMID --delete ide2 --delete ide3 --delete cdrom
```

!!! warning
    Remove the unattend ISOs after setup is complete. The ISOs contain the Administrator password in a mounted virtual drive that is visible if the VM is later restored from a pre-detach snapshot.

### Verify WinRM is responding on all five VMs

Run from your control node (the machine running these scripts, with network access to 10.0.0.0/24):

```powershell
$sessionOpt = New-PSSessionOption -SkipCACheck -SkipCNCheck
$vms = @{dc01="10.0.0.11"; exchange01="10.0.0.12"; sql01="10.0.0.13"; ws01="10.0.0.14"; ws02="10.0.0.15"}
foreach ($vm in $vms.GetEnumerator()) {
    $cred = Get-Credential -UserName "Administrator" -Message "Password for $($vm.Key)"
    $s = New-PSSession -ComputerName $vm.Value -Credential $cred -SessionOption $sessionOpt
    $name = Invoke-Command -Session $s -ScriptBlock { hostname }
    Write-Host "$($vm.Key) ($($vm.Value)): $name — WinRM OK"
    Remove-PSSession $s
}
```

Expected: each VM returns its hostname with no errors.

---

## Step 3 — Promote dc01 to Domain Controller

### Prerequisites
- dc01 WinRM responding at 10.0.0.11
- DSRM password ready from `.planning/secrets/PASSWORDS.md`

### Run from the control node

```powershell
$cred = Get-Credential -UserName "Administrator" -Message "dc01 local admin password"
$sessionOpt = New-PSSessionOption -SkipCACheck -SkipCNCheck
$session = New-PSSession -ComputerName 10.0.0.11 -Credential $cred -SessionOption $sessionOpt

Copy-Item -Path "scripts/windows/setup/01-dc01-promote.ps1" `
          -Destination "C:\Temp\01-dc01-promote.ps1" -ToSession $session

Invoke-Command -Session $session -ScriptBlock {
    & "C:\Temp\01-dc01-promote.ps1" -DSRMPassword "DSRM_FROM_PASSWORDS_MD"
}
```

The script performs these steps in order:

1. Validates the hostname is `DC01` — exits with an error if not
2. Sets static IPs: TARGET NIC → `10.10.10.10/24` (DNS=127.0.0.1), MGMT NIC → `10.0.0.11/24`
3. Validates DNS on the TARGET NIC is `127.0.0.1` before continuing
4. Installs the AD DS Windows role
5. Runs `Install-ADDSForest` for `lab.local` (NetBIOS: `LAB`, forest/domain mode: WinThreshold)
6. Triggers an automatic reboot

!!! warning
    The WinRM session **will disconnect** when promotion triggers the reboot — this is expected.
    Wait approximately 2–3 minutes, then reconnect using domain credentials `LAB\Administrator`.

### Verify AD is healthy after reboot

```powershell
$domCred = Get-Credential -UserName "LAB\Administrator" -Message "Domain admin password"
$sessionOpt = New-PSSessionOption -SkipCACheck -SkipCNCheck
Invoke-Command -ComputerName 10.0.0.11 -Credential $domCred -SessionOption $sessionOpt -ScriptBlock {
    (Get-ADDomain).Name
    (Get-ADForest).ForestMode
}
# Expected: "lab" and "Windows2016Forest"
```

---

## Step 4 — Create AD Users, Groups, and SPN

### Prerequisites
- dc01 rebooted and AD DS stable (Step 3 complete)
- Domain admin credentials (`LAB\Administrator`)

### Run from the control node

```powershell
$domCred = Get-Credential -UserName "LAB\Administrator" -Message "Domain admin password"
$sessionOpt = New-PSSessionOption -SkipCACheck -SkipCNCheck
$session = New-PSSession -ComputerName 10.0.0.11 -Credential $domCred -SessionOption $sessionOpt

Copy-Item -Path "scripts/windows/setup/02-dc01-users.ps1" `
          -Destination "C:\Temp\02-dc01-users.ps1" -ToSession $session

# Copy AdFind.exe to C:\Temp\ on dc01 first (no internet on TARGET NIC)
Copy-Item -Path "PATH_TO\AdFind.exe" -Destination "C:\Temp\AdFind.exe" -ToSession $session

Invoke-Command -Session $session -ScriptBlock { & "C:\Temp\02-dc01-users.ps1" }
Remove-PSSession $session
```

The script creates:

| Account | Groups | Notes |
|---------|--------|-------|
| `LAB\tous` | EWS Admins, SQL Admins | SPN: `MSSQLSvc/sql01.lab.local:1433` — OilRig service account |
| `LAB\gosta` | Domain Users | Standard user |
| `LAB\mariam` | Domain Users | Standard user |
| `LAB\shiroyeh` | Domain Users | Standard user |
| `LAB\shiroyeh_admin` | Domain Admins | Privileged admin account |
| `LAB\vfleming` | Domain Admins | Privileged admin account |
| `LAB\judy` | Domain Users | ws01 file-access account (Wizard Spider scenario) |

All accounts are created with `EXPIRES:NEVER`. ADFind.exe is installed to `C:\Windows\System32\adfind.exe`. Firefox is also installed as part of this script.

---

## Step 5 — Domain-Join Remaining VMs

### Prerequisites
- Steps 3 and 4 complete — `lab.local` domain controller running, AD users created
- exchange01, sql01, ws01, and ws02 WinRM responding on their MGMT IPs

### Run from the control node

```powershell
$localCred = Get-Credential -UserName "Administrator" -Message "Local admin password (same on all 4 VMs)"
$domCred = Get-Credential -UserName "LAB\Administrator" -Message "Domain admin password"
$sessionOpt = New-PSSessionOption -SkipCACheck -SkipCNCheck

Copy-Item -Path "scripts/windows/setup/03-domain-join.ps1" `
          -Destination "C:\Temp\03-domain-join.ps1" -ToSession `
          (New-PSSession -ComputerName 10.0.0.12 -Credential $localCred -SessionOption $sessionOpt)

Invoke-Command -ComputerName 10.0.0.11 -Credential $domCred -SessionOption $sessionOpt -FilePath `
    "scripts/windows/setup/03-domain-join.ps1"
```

The script runs in three parts:

- **Part A:** For each of exchange01, sql01, ws01, ws02 — connects via WinRM, sets the TARGET NIC DNS to `10.10.10.10` (dc01), validates `Resolve-DnsName lab.local` succeeds, then runs `Add-Computer -DomainName lab.local -Restart -Force`
- **Part B:** Verifies all five AD computer objects appear on dc01
- **Part C:** Prints the exact `qm snapshot` commands to run on Hosts 2, 3, and 4 for the post-domain-join baseline snapshot

### Take the post-domain-join snapshot

After the script completes and all VMs have rebooted into the domain, run the snapshot commands printed by the script on each Proxmox host. Example:

```bash
# On Host 2
qm snapshot 201 phase2-domain-joined --description "dc01 after domain join"
qm snapshot 202 phase2-domain-joined --description "sql01 after domain join"

# On Host 3
qm snapshot 301 phase2-domain-joined --description "exchange01 after domain join"

# On Host 4
qm snapshot 401 phase2-domain-joined --description "ws01 after domain join"
qm snapshot 402 phase2-domain-joined --description "ws02 after domain join"
```

!!! note
    The snapshot commands exclude elastic-vm (VM 200) and caldera-vm (VM 201 range) — those are control-plane VMs and are never included in target snapshots.

---

## Step 6 — Install Exchange Server 2019

Exchange setup requires multiple reboots. The prerequisites script uses a `-Step N` parameter so each step is run separately, with a reboot between steps.

### Prerequisites
- exchange01 is domain-joined (Step 5 complete)
- Exchange Server 2019 CU14+ evaluation ISO mounted as drive E: on exchange01
- `.NET Framework 4.8` installer available at `C:\Temp\ndp48-x86-x64-allos-enu.exe`
- Visual C++ 2012 and 2013 x64 redistributables available at `C:\Temp\`
- IIS URL Rewrite Module installer at `C:\Temp\rewrite_amd64_en-US.msi`

### Copy prerequisites to exchange01

```powershell
$domCred = Get-Credential -UserName "LAB\Administrator" -Message "Domain admin password"
$sessionOpt = New-PSSessionOption -SkipCACheck -SkipCNCheck
$s = New-PSSession -ComputerName 10.0.0.12 -Credential $domCred -SessionOption $sessionOpt

Copy-Item "scripts/windows/setup/04-exchange01-prereqs.ps1" -Destination "C:\Temp\" -ToSession $s
Copy-Item "scripts/windows/setup/05-exchange01-install.ps1" -Destination "C:\Temp\" -ToSession $s
Copy-Item "PATH_TO\ndp48-x86-x64-allos-enu.exe" -Destination "C:\Temp\" -ToSession $s
Copy-Item "PATH_TO\vcredist2012_x64.exe","PATH_TO\vcredist2013_x64.exe" -Destination "C:\Temp\" -ToSession $s
Copy-Item "PATH_TO\rewrite_amd64_en-US.msi" -Destination "C:\Temp\" -ToSession $s
Remove-PSSession $s
```

### Run prerequisites in five steps (with reboots between)

Run each step via WinRM. After steps that install software requiring a reboot, wait for exchange01 to come back up before running the next step.

```powershell
$domCred = Get-Credential -UserName "LAB\Administrator" -Message "Domain admin password"
$sessionOpt = New-PSSessionOption -SkipCACheck -SkipCNCheck

# Step 1 — Windows features (Web-Server, RSAT-ADDS, etc.) — triggers reboot
Invoke-Command -ComputerName 10.0.0.12 -Credential $domCred -SessionOption $sessionOpt `
    -ScriptBlock { & "C:\Temp\04-exchange01-prereqs.ps1" -Step 1 }
# Wait for reboot (~2 min), then continue

# Step 2 — .NET Framework 4.8 — triggers reboot
Invoke-Command -ComputerName 10.0.0.12 -Credential $domCred -SessionOption $sessionOpt `
    -ScriptBlock { & "C:\Temp\04-exchange01-prereqs.ps1" -Step 2 }
# Wait for reboot (~3 min), then continue

# Step 3 — UCMA 4.0 (from Exchange ISO E:\UCMARedist\)
Invoke-Command -ComputerName 10.0.0.12 -Credential $domCred -SessionOption $sessionOpt `
    -ScriptBlock { & "C:\Temp\04-exchange01-prereqs.ps1" -Step 3 }

# Step 4 — Visual C++ 2012 + 2013 redistributables
Invoke-Command -ComputerName 10.0.0.12 -Credential $domCred -SessionOption $sessionOpt `
    -ScriptBlock { & "C:\Temp\04-exchange01-prereqs.ps1" -Step 4 }

# Step 5 — IIS URL Rewrite Module
Invoke-Command -ComputerName 10.0.0.12 -Credential $domCred -SessionOption $sessionOpt `
    -ScriptBlock { & "C:\Temp\04-exchange01-prereqs.ps1" -Step 5 }
```

!!! warning
    **Run prerequisites in strict order (1 → 5) with reboots after steps 1 and 2.**
    Exchange setup will fail silently or produce cryptic errors if prerequisites are missing or incomplete.
    Do not skip steps or run them out of order.

### Run Exchange unattended install

Exchange installation takes approximately 45–60 minutes. Run this from the control node:

```powershell
$domCred = Get-Credential -UserName "LAB\Administrator" -Message "Domain admin password"
$sessionOpt = New-PSSessionOption -SkipCACheck -SkipCNCheck
Invoke-Command -ComputerName 10.0.0.12 -Credential $domCred -SessionOption $sessionOpt `
    -ScriptBlock { & "C:\Temp\05-exchange01-install.ps1" }
```

The script:
- Runs `PrepareAD` and `PrepareAllDomains` on dc01 before starting Setup
- Installs Exchange with Mailbox role only (`/DoNotEnableEP_FEEWS`)
- Grants `LAB\tous` the EWS `ApplicationImpersonation` management role
- Creates the `sql_connection.bat` scheduled task (OilRig persistence pre-condition)

### Verify EWS endpoint

```powershell
Invoke-WebRequest -Uri "https://10.0.0.12/EWS/Exchange.asmx" -SkipCertificateCheck
# Expected: StatusCode 200 or 401 (401 means Exchange is running but authentication is required — correct)
```

---

## Step 7 — Install SQL Server 2019

### Prerequisites
- sql01 is domain-joined (Step 5 complete)
- SQL Server 2019 Developer Edition ISO mounted as drive D: on sql01
- `minfac.csv` available in the repo at `data/minfac.csv` (critical infrastructure seed data)

### Copy scripts and data to sql01

```powershell
$domCred = Get-Credential -UserName "LAB\Administrator" -Message "Domain admin password"
$sessionOpt = New-PSSessionOption -SkipCACheck -SkipCNCheck
$s = New-PSSession -ComputerName 10.0.0.13 -Credential $domCred -SessionOption $sessionOpt

Copy-Item "scripts/windows/setup/06-sql01-install.ps1" -Destination "C:\Temp\" -ToSession $s
Copy-Item "data/minfac.csv" -Destination "C:\Temp\minfac.csv" -ToSession $s
Remove-PSSession $s
```

### Run SQL installation

```powershell
$domCred = Get-Credential -UserName "LAB\Administrator" -Message "Domain admin password"
$sessionOpt = New-PSSessionOption -SkipCACheck -SkipCNCheck

# Provide the SQL SA password and LAB\tous password as parameters
Invoke-Command -ComputerName 10.0.0.13 -Credential $domCred -SessionOption $sessionOpt `
    -ScriptBlock {
        & "C:\Temp\06-sql01-install.ps1" `
            -SaPassword "SA_PASSWORD_FROM_PASSWORDS_MD" `
            -TousPassword "TOUS_PASSWORD_FROM_PASSWORDS_MD"
    }
```

The script:
- Installs SQL Server 2019 Developer Edition in silent/mixed-auth mode from `D:\`
- Creates the `sitedata` database with the `minfac` table schema
- Imports `minfac.csv` using `SqlBulkCopy` (not `BULK INSERT` — quoted CSV fields require this)
- Takes a full backup to `C:\Backups\sitedata.bak`
- Grants `LAB\tous` the `db_owner` role and creates a SQL login for `tous`
- Opens TCP 1433 in Windows Firewall

### Verify SQL is responding

```powershell
Invoke-Command -ComputerName 10.0.0.13 -Credential $domCred -SessionOption $sessionOpt `
    -ScriptBlock {
        sqlcmd -S localhost -Q "SELECT COUNT(*) FROM sitedata.dbo.minfac"
    }
# Expected: a positive row count
```

---

## Step 8 — Apply Security Baseline to All VMs

This step applies the emulation lab security settings to all five VMs. These settings intentionally weaken Windows security to allow credential theft techniques to function.

!!! warning
    This step **disables Windows Defender**, enables WDigest authentication (cleartext credentials in LSASS), and sets UAC to "Never Notify". These settings are intentional for the emulation lab. All VMs are isolated on the air-gapped TARGET subnet.

### Copy prerequisites to each VM

Copy the VC++ redistributables and QEMU Guest Agent MSI to `C:\Temp\` on each VM before running the baseline script:

```powershell
$pass = ConvertTo-SecureString "ADMIN_PASSWORD" -AsPlainText -Force
$cred = New-Object PSCredential("LAB\Administrator", $pass)
$sessionOpt = New-PSSessionOption -SkipCACheck -SkipCNCheck

$vms = @{dc01="10.0.0.11"; exchange01="10.0.0.12"; sql01="10.0.0.13"; ws01="10.0.0.14"; ws02="10.0.0.15"}
foreach ($vm in $vms.GetEnumerator()) {
    $s = New-PSSession -ComputerName $vm.Value -Credential $cred -SessionOption $sessionOpt
    Copy-Item "PATH_TO\vcredist_x86.exe","PATH_TO\vcredist_x64.exe","PATH_TO\qemu-ga-x86_64.msi" `
        -Destination "C:\Temp\" -ToSession $s
    Remove-PSSession $s
}
```

### Apply baseline to all five VMs

```powershell
$vms = @{dc01="10.0.0.11"; exchange01="10.0.0.12"; sql01="10.0.0.13"; ws01="10.0.0.14"; ws02="10.0.0.15"}
foreach ($vm in $vms.GetEnumerator()) {
    Write-Host "Applying baseline to $($vm.Key) ($($vm.Value))..."
    $s = New-PSSession -ComputerName $vm.Value -Credential $cred -SessionOption $sessionOpt
    Invoke-Command -Session $s -FilePath "scripts\windows\setup\07-security-baseline.ps1"
    Remove-PSSession $s
}
```

Each VM receives these settings:

| Setting | Value | Purpose |
|---------|-------|---------|
| Windows Defender | Disabled | Allows red team tools to execute without quarantine |
| Automatic updates | Disabled | Prevents state changes during emulation runs |
| WinRM | Re-enforced (TrustedHosts=*) | Ensures remote management stays available |
| UAC | Never Notify (`EnableLUA=0`) | Allows privilege escalation without prompts |
| WDigest | `UseLogonCredential=1` | Enables cleartext credential harvesting from LSASS |
| Visual C++ runtimes | x86 + x64 installed | Required by several red team tools |
| QEMU Guest Agent | Installed and running | Required for Proxmox snapshot consistency |

### Reboot all five VMs

UAC and WDigest changes require a reboot to take effect:

```powershell
foreach ($ip in $vms.Values) {
    Invoke-Command -ComputerName $ip -Credential $cred -SessionOption $sessionOpt `
        -ScriptBlock { Restart-Computer -Force }
}
# Wait approximately 2 minutes for reboots to complete
```

---

## Step 9 — Configure Workstations

### ws01 (Dorothy — initial access target)

```powershell
$s1 = New-PSSession -ComputerName "10.0.0.14" -Credential $cred -SessionOption $sessionOpt
Copy-Item "scripts\windows\setup\08-workstations.ps1" -Destination "C:\Temp\" -ToSession $s1
Copy-Item "PATH_TO\file_generator.exe" -Destination "C:\Temp\" -ToSession $s1
# If installing Office, also copy:
# Copy-Item "PATH_TO\setup.exe","PATH_TO\office-config.xml" -Destination "C:\Temp\" -ToSession $s1

Invoke-Command -Session $s1 -ScriptBlock { & "C:\Temp\08-workstations.ps1" -Target "ws01" }
Remove-PSSession $s1
```

ws01 configuration:
- Installs Microsoft Office via ODT (if `setup.exe` and `office-config.xml` are present in `C:\Temp\`)
- Generates 150 decoy files using `file_generator.exe -seed EVALS` across `C:\Users\Public\` and `C:\Users\`
- Grants `LAB\judy` full-control ACL on `C:\Windows` (Wizard Spider pre-condition, T1222)

### ws02 (Toto — lateral movement target)

```powershell
$s2 = New-PSSession -ComputerName "10.0.0.15" -Credential $cred -SessionOption $sessionOpt
Copy-Item "scripts\windows\setup\08-workstations.ps1" -Destination "C:\Temp\" -ToSession $s2
Copy-Item "PATH_TO\file_generator.exe" -Destination "C:\Temp\" -ToSession $s2
Invoke-Command -Session $s2 -ScriptBlock { & "C:\Temp\08-workstations.ps1" -Target "ws02" }
Remove-PSSession $s2
```

ws02 configuration:
- Installs Google Chrome (downloads from `dl.google.com` if internet is available on MGMT NIC, otherwise expects `C:\Temp\ChromeSetup.exe`)
- Generates 150 decoy files using `file_generator.exe -seed EVALS`

!!! warning
    After Chrome installs on ws02, you must **manually log in to Chrome and save at least one credential** via the Proxmox console. This Chrome saved-password is the APT29 Scenario 1 initial-access target. The script prints detailed instructions for this manual step — follow them before taking the final snapshot.

---

## Step 10 — Run Integration Tests

Run the full Phase 2 integration test from the control node:

```powershell
pwsh scripts/windows/verify/verify-phase2.ps1 -Password 'ActualPassword'
```

The script runs 16 checks across five groups:

| Group | What is tested |
|-------|---------------|
| WinRM | All 5 VMs reachable on 10.0.0.11–15 |
| AD | 7 domain users + SPN `MSSQLSvc/sql01.lab.local:1433` + 5 computer objects |
| SQL | `COUNT(*) FROM sitedata.dbo.minfac > 0` + port 1433 accessible |
| Exchange EWS | `https://10.0.0.12/EWS/Exchange.asmx` returns 200 or 401 |
| Workstations | `PartOfDomain=True` + `UseLogonCredential=1` on ws01 and ws02 |

Expected output ends with `Phase 2 COMPLETE` in green. Any `[FAIL]` result indicates a misconfiguration — refer to the relevant step above.

---

## UAT Gates (Phase 2)

| Gate | Requirement |
|------|------------|
| INFRA-03 | lab.local AD domain running on dc01; 7 users created; SPN registered |
| INFRA-04 | Exchange EWS endpoint returns 200/401 at https://10.0.0.12/EWS/Exchange.asmx |
| INFRA-05 | SQL Server on sql01; minfac table populated; port 1433 accessible |
| INFRA-06 | ws01 and ws02 domain-joined; WDigest=1; Defender disabled; decoy files present |

---

## Key Scripts Reference

| Script | Run on | Purpose |
|--------|--------|---------|
| `scripts/proxmox/build-unattend-isos.sh` | Proxmox host with secrets access | Package filled-in XMLs into 5 bootable unattend ISOs |
| `scripts/proxmox/provision-windows.sh 2` | Proxmox Host 2 | Create dc01 (VMID 201) and sql01 (VMID 202) |
| `scripts/proxmox/provision-windows.sh 3` | Proxmox Host 3 | Create exchange01 (VMID 301) |
| `scripts/proxmox/provision-windows.sh 4` | Proxmox Host 4 | Create ws01 (VMID 401) and ws02 (VMID 402) |
| `scripts/windows/setup/01-dc01-promote.ps1` | control node → dc01 WinRM | Promote DC, create lab.local forest |
| `scripts/windows/setup/02-dc01-users.ps1` | control node → dc01 WinRM | Create 7 AD users, groups, SPN, ADFind |
| `scripts/windows/setup/03-domain-join.ps1` | control node | Domain-join 4 VMs + print snapshot commands |
| `scripts/windows/setup/04-exchange01-prereqs.ps1` | control node → exchange01 WinRM | 5-step Exchange prerequisite chain |
| `scripts/windows/setup/05-exchange01-install.ps1` | control node → exchange01 WinRM | Exchange unattended install + EWS config |
| `scripts/windows/setup/06-sql01-install.ps1` | control node → sql01 WinRM | SQL Server install + sitedata DB + minfac import |
| `scripts/windows/setup/07-security-baseline.ps1` | control node → each VM WinRM | Defender off, WDigest on, UAC off, QEMU agent |
| `scripts/windows/setup/08-workstations.ps1` | control node → ws01/ws02 WinRM | Office, Chrome, decoy files, judy ACLs |
| `scripts/windows/verify/verify-phase2.ps1` | control node | 16-check integration test; must show Phase 2 COMPLETE |

---

[← Back to index](.)
