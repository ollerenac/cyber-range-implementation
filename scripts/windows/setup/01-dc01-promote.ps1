<#
.SYNOPSIS
    Promotes dc01 to Domain Controller for lab.local forest.

.DESCRIPTION
    This script performs the following steps in order:
      1. Verifies the hostname is DC01 (mandatory before promotion).
      2. Sets static IPs on both NICs (TARGET=10.10.10.10, MGMT=10.0.0.11).
      3. Sets DNS on TARGET NIC to 127.0.0.1 BEFORE promotion (critical — see notes).
      4. Installs the AD DS Windows role.
      5. Runs Install-ADDSForest to create the lab.local forest.

    After promotion, dc01 reboots automatically. WinRM session will disconnect.
    Reconnect to 10.0.0.11 after ~2-3 minutes using domain credentials LAB\Administrator.

.USAGE
    Run via WinRM from the control node:
      $cred = Get-Credential -UserName "Administrator" -Message "dc01 local admin"
      $session = New-PSSession -ComputerName 10.0.0.11 -Credential $cred `
                   -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)
      Copy-Item -Path "scripts/windows/setup/01-dc01-promote.ps1" `
                -Destination "C:\Temp\01-dc01-promote.ps1" -ToSession $session
      Invoke-Command -Session $session -ScriptBlock { & "C:\Temp\01-dc01-promote.ps1" -DSRMPassword "DSRM_FROM_PASSWORDS_MD" }

.PARAMETER DSRMPassword
    Directory Services Restore Mode (DSRM) password for the new domain controller.
    Must meet Windows complexity requirements: >= 8 chars, upper+lower+digit+symbol.
    Source: .planning/secrets/PASSWORDS.md (gitignored). Never hardcode here.

.PREREQUISITES
    - WinRM must be enabled on dc01 (autounattend.xml FirstLogonCommands handles this).
    - Hostname must be DC01 (autounattend.xml specialize pass sets this; verify before running).
    - This script triggers an automatic reboot at the end of Step 5.

.WARNING
    This script triggers a reboot. The WinRM session WILL disconnect when promotion
    completes. Reconnect to 10.0.0.11 after ~2-3 minutes.

.NOTES
    NIC alias convention (Proxmox net0/net1 → Windows):
      "Ethernet"   = net0 = vmbr1 = TARGET subnet (10.10.10.0/24) — emulation traffic
      "Ethernet 2" = net1 = vmbr0 = MGMT subnet   (10.0.0.0/24)  — WinRM + Elastic Agent

    If Windows assigns different alias names (hardware-dependent), run:
      Get-NetAdapter | Select Name, InterfaceDescription, MacAddress
    and update the -InterfaceAlias values in Section 2 accordingly before running.

    Forest functional level WinThreshold = Windows Server 2016 — minimum required by
    Exchange Server 2019. See: https://learn.microsoft.com/en-us/exchange/plan-and-deploy/system-requirements

    DNS MUST be set to 127.0.0.1 on the TARGET NIC BEFORE Install-ADDSForest.
    If DNS points to DHCP/external at promotion time, Install-ADDSForest fails with
    "The specified domain already exists" or DNS registration errors. This is failure
    point #1 per RESEARCH.md Q3.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$DSRMPassword
)

$ErrorActionPreference = "Stop"

# ============================================================
# Section 1 — Hostname verification
# ============================================================
Write-Host "[i] Section 1: Verifying hostname..."

$currentHostname = (hostname).ToUpper()
if ($currentHostname -ne "DC01") {
    Write-Warning "Hostname is '$currentHostname' — expected 'DC01'."
    Write-Warning "Rename the computer first (set via autounattend.xml specialize pass)."
    Write-Warning "Run: Rename-Computer -NewName 'DC01' -Force; then restart and re-run this script."
    exit 1
}

Write-Host "[i] Hostname verified: DC01"

# ============================================================
# Section 2 — Static IP configuration
# ============================================================
Write-Host "[i] Section 2: Configuring static IPs..."

# TARGET NIC (net0 = vmbr1 = "Ethernet") — 10.10.10.10/24
# DNS set to 127.0.0.1 BEFORE promotion (critical — failure point #1 per RESEARCH.md Q3)
Write-Host "[i] Configuring TARGET NIC ('Ethernet') — 10.10.10.10/24, DNS=127.0.0.1"
try {
    # Remove any existing DHCP-assigned addresses first
    $targetAdapter = Get-NetAdapter -Name "Ethernet" -ErrorAction Stop
    $existingIPs = Get-NetIPAddress -InterfaceIndex $targetAdapter.InterfaceIndex `
                                    -AddressFamily IPv4 -ErrorAction SilentlyContinue
    foreach ($ip in $existingIPs) {
        Remove-NetIPAddress -InterfaceIndex $targetAdapter.InterfaceIndex `
                            -IPAddress $ip.IPAddress -Confirm:$false -ErrorAction SilentlyContinue
    }
    # Remove any existing default route on this adapter
    Remove-NetRoute -InterfaceIndex $targetAdapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue

    New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 10.10.10.10 -PrefixLength 24 -ErrorAction Stop
    # DNS MUST be 127.0.0.1 before Install-ADDSForest — do not skip this step
    Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 127.0.0.1 -ErrorAction Stop
    Write-Host "[i] TARGET NIC set: 10.10.10.10/24, DNS=127.0.0.1"
} catch {
    Write-Warning "Failed to configure TARGET NIC 'Ethernet': $_"
    Write-Warning "Check NIC alias with: Get-NetAdapter | Select Name, InterfaceDescription"
    Write-Warning "Update -InterfaceAlias in this script if Windows assigned a different name."
    exit 1
}

# MGMT NIC (net1 = vmbr0 = "Ethernet 2") — 10.0.0.11/24
# No default gateway on MGMT NIC — dc01 is not the default gateway
Write-Host "[i] Configuring MGMT NIC ('Ethernet 2') — 10.0.0.11/24, no gateway"
try {
    $mgmtAdapter = Get-NetAdapter -Name "Ethernet 2" -ErrorAction Stop
    $existingMgmtIPs = Get-NetIPAddress -InterfaceIndex $mgmtAdapter.InterfaceIndex `
                                         -AddressFamily IPv4 -ErrorAction SilentlyContinue
    foreach ($ip in $existingMgmtIPs) {
        Remove-NetIPAddress -InterfaceIndex $mgmtAdapter.InterfaceIndex `
                            -IPAddress $ip.IPAddress -Confirm:$false -ErrorAction SilentlyContinue
    }
    Remove-NetRoute -InterfaceIndex $mgmtAdapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue

    New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress 10.0.0.11 -PrefixLength 24 -ErrorAction Stop
    # No gateway — dc01 is not a router; MGMT subnet handles WinRM + Elastic Agent enrollment only
    Write-Host "[i] MGMT NIC set: 10.0.0.11/24 (no gateway)"
} catch {
    Write-Warning "Failed to configure MGMT NIC 'Ethernet 2': $_"
    Write-Warning "Check NIC alias with: Get-NetAdapter | Select Name, InterfaceDescription"
    exit 1
}

Write-Host "[i] Static IPs set: TARGET=10.10.10.10, MGMT=10.0.0.11"

# Verify DNS is 127.0.0.1 on TARGET NIC before continuing — this is the #1 promotion failure cause
$dnsCheck = (Get-DnsClientServerAddress -InterfaceAlias "Ethernet" -AddressFamily IPv4).ServerAddresses
if ($dnsCheck -notcontains "127.0.0.1") {
    Write-Warning "DNS on TARGET NIC is NOT 127.0.0.1 — current value: $dnsCheck"
    Write-Warning "Install-ADDSForest requires DNS=127.0.0.1 on the TARGET NIC before promotion."
    exit 1
}
Write-Host "[i] DNS pre-promotion check passed: TARGET NIC DNS = 127.0.0.1"

# ============================================================
# Section 3 — Install AD DS role
# ============================================================
Write-Host "[i] Section 3: Installing AD DS Windows role (this may take several minutes)..."

Install-WindowsFeature AD-Domain-Services -IncludeManagementTools -Verbose

Write-Host "[i] AD DS role installed. Proceeding to forest creation..."

# ============================================================
# Section 4 — Forest promotion (triggers automatic reboot)
# ============================================================
Write-Host "[i] Section 4: Promoting dc01 to Domain Controller for lab.local..."
Write-Host "[!] WARNING: VM will reboot after promotion. WinRM session will disconnect."
Write-Host "[!] Reconnect to 10.0.0.11 after ~2-3 minutes using domain credentials LAB\Administrator."

Import-Module ADDSDeployment

# Convert DSRM password to SecureString
# DSRM password complexity requirement: >= 8 chars, upper+lower+digit+symbol
# Example compliant password format: DSRM@Lab2025!  (do not hardcode — pass via -DSRMPassword parameter)
$secureDSRMPassword = ConvertTo-SecureString $DSRMPassword -AsPlainText -Force

Install-ADDSForest `
    -DomainName "lab.local" `
    -DomainNetbiosName "LAB" `
    -DomainMode "WinThreshold" `
    -ForestMode "WinThreshold" `
    -InstallDns:$true `
    -DatabasePath "C:\Windows\NTDS" `
    -LogPath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -SafeModeAdministratorPassword $secureDSRMPassword `
    -NoRebootOnCompletion:$false `
    -CreateDnsDelegation:$false `
    -Force:$true

# ============================================================
# Section 5 — Post-promotion instructions (printed before reboot)
# ============================================================
# Note: Install-ADDSForest with -NoRebootOnCompletion:$false triggers reboot
# immediately after forest creation completes. The Write-Host calls below may
# not be visible if the reboot fires before they execute. This is expected.
Write-Host "[!] dc01 is rebooting. Wait 2-3 minutes then verify:"
Write-Host "    1. Reconnect: New-PSSession -ComputerName 10.0.0.11 -Credential (Get-Credential 'LAB\Administrator')"
Write-Host "    2. Resolve-DnsName lab.local -Server 10.10.10.10"
Write-Host "       Expected: returns dc01.lab.local A record (10.10.10.10)"
Write-Host "    3. Invoke-Command { (Get-ADDomain).Name }      -> 'lab'"
Write-Host "    4. Invoke-Command { (Get-ADDomain).DomainMode } -> 'Windows2016Domain'"
Write-Host "    5. Invoke-Command { (Get-ADForest).ForestMode } -> 'Windows2016Forest'"
Write-Host "    6. Invoke-Command { Get-Service ADWS }          -> Status = Running"
Write-Host ""
Write-Host "    After verification, run: scripts/windows/setup/02-dc01-users.ps1"
Write-Host ""
Write-Host "    Post-promotion DNS note for other VMs:"
Write-Host "    All other VMs (exchange01, sql01, ws01, ws02) must use dc01 as DNS:"
Write-Host "      Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses 10.10.10.10"
Write-Host "    This is configured in scripts/windows/setup/06-workstations.ps1 before domain join."
