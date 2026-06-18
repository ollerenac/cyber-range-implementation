# 03-domain-join.ps1
# Runs from control node. Sets TARGET NIC DNS → dc01 (10.10.10.10), domain-joins
# exchange01/sql01/ws01/ws02 to lab.local, verifies AD computer objects, then
# emits D-14 snapshot commands (operator runs on each Proxmox host via SSH).
#
# USAGE:
#   pwsh 03-domain-join.ps1 -DomainAdminPassword 'P@ssw0rd' -LocalAdminPassword 'LocalP@ss'
#
# PREREQUISITE: 01-dc01-promote.ps1 must have completed and dc01 rebooted.
#   Verify: Test-WSMan -ComputerName 10.0.0.11

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DomainAdminPassword,
    [Parameter(Mandatory)][string]$LocalAdminPassword
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DomainName   = "lab.local"
$DcMgmtIP     = "10.0.0.11"
$DcTargetIP   = "10.10.10.10"

# Target VMs: name → MGMT IP
$TargetVMs = [ordered]@{
    "exchange01" = "10.0.0.12"
    "sql01"      = "10.0.0.13"
    "ws01"       = "10.0.0.14"
    "ws02"       = "10.0.0.15"
}

$LocalCred  = New-Object PSCredential("Administrator",
    (ConvertTo-SecureString $LocalAdminPassword -AsPlainText -Force))
$DomainCred = New-Object PSCredential("LAB\Administrator",
    (ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force))

$SessionOpts = New-PSSessionOption -SkipCACheck -SkipCNCheck

# ─── PART A: DNS configuration + domain join per VM ──────────────────────────
Write-Host "`n=== PART A: Domain Join ===" -ForegroundColor Cyan

foreach ($VMName in $TargetVMs.Keys) {
    $MgmtIP = $TargetVMs[$VMName]
    Write-Host "`n[i] Processing $VMName ($MgmtIP)" -ForegroundColor Yellow

    try {
        $Session = New-PSSession -ComputerName $MgmtIP -Credential $LocalCred `
            -SessionOption $SessionOpts

        Invoke-Command -Session $Session -ScriptBlock {
            param($DcTargetIP, $DomainName, $DomainAdminPassword)

            # Step 1: Set TARGET NIC DNS to dc01 BEFORE domain join (D-05, pitfall 5)
            $TargetNIC = Get-NetAdapter | Where-Object {
                ($_ | Get-NetIPAddress -AddressFamily IPv4 -EA SilentlyContinue).IPAddress -like "10.10.10.*"
            } | Select-Object -First 1

            if (-not $TargetNIC) {
                # Fallback: use adapter named "Ethernet" (autounattend sets TARGET as first NIC)
                $TargetNIC = Get-NetAdapter -Name "Ethernet" -EA SilentlyContinue
            }

            if ($TargetNIC) {
                Set-DnsClientServerAddress -InterfaceIndex $TargetNIC.InterfaceIndex `
                    -ServerAddresses $DcTargetIP
                Write-Host "[PASS] TARGET NIC DNS set to $DcTargetIP on $($TargetNIC.Name)"
            } else {
                Write-Error "Cannot find TARGET NIC — aborting domain join for this VM"
                return
            }

            # Step 2: Verify DNS resolution BEFORE joining (exit early if DNS fails)
            Start-Sleep -Seconds 3
            try {
                $resolved = Resolve-DnsName $DomainName -Server $DcTargetIP -EA Stop
                Write-Host "[PASS] DNS resolved $DomainName via $DcTargetIP"
            } catch {
                Write-Error "DNS resolution FAILED for '$DomainName' via $DcTargetIP. " +
                    "Verify dc01 is running and TARGET NIC on this VM reaches 10.10.10.0/24. " +
                    "Aborting domain join."
                return
            }

            # Step 3: Domain join with automatic reboot
            $domainCred = New-Object PSCredential("LAB\Administrator",
                (ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force))

            Write-Host "[i] Joining $env:COMPUTERNAME to $DomainName ..."
            Add-Computer -DomainName $DomainName -Credential $domainCred `
                -OUPath "CN=Computers,DC=lab,DC=local" -Restart -Force
            Write-Host "[i] Reboot triggered — VM will come back as domain member"

        } -ArgumentList $DcTargetIP, $DomainName, $DomainAdminPassword

        Remove-PSSession $Session -EA SilentlyContinue

    } catch {
        Write-Warning "[FAIL] $VMName ($MgmtIP): $_"
        Write-Host "       Check that WinRM is responding: Test-WSMan -ComputerName $MgmtIP"
    }

    # Wait for VM to reboot and come back
    Write-Host "[i] Waiting 90s for $VMName to reboot and rejoin network..."
    Start-Sleep -Seconds 90

    # Step 4: Verify domain membership post-reboot (connect as domain admin now)
    try {
        $PostSession = New-PSSession -ComputerName $MgmtIP -Credential $DomainCred `
            -SessionOption $SessionOpts
        $IsDomainMember = Invoke-Command -Session $PostSession -ScriptBlock {
            (Get-WmiObject Win32_ComputerSystem).PartOfDomain
        }
        Remove-PSSession $PostSession -EA SilentlyContinue

        if ($IsDomainMember) {
            Write-Host "[PASS] $VMName is now a domain member of $DomainName" -ForegroundColor Green
        } else {
            Write-Warning "[FAIL] $VMName reports PartOfDomain=False — check domain join logs"
        }
    } catch {
        Write-Warning "[WARN] $VMName: could not verify domain membership post-reboot — $_"
    }
}

# ─── PART B: Verify all 5 computer objects in AD ─────────────────────────────
Write-Host "`n=== PART B: Verify AD Computer Objects ===" -ForegroundColor Cyan

try {
    $AdSession = New-PSSession -ComputerName $DcMgmtIP -Credential $DomainCred `
        -SessionOption $SessionOpts

    Invoke-Command -Session $AdSession -ScriptBlock {
        Import-Module ActiveDirectory
        $Expected = @("DC01","EXCHANGE01","SQL01","WS01","WS02")
        $Found    = (Get-ADComputer -Filter *).Name

        foreach ($Name in $Expected) {
            if ($Found -contains $Name) {
                Write-Host "[PASS] Computer object in AD: $Name" -ForegroundColor Green
            } else {
                Write-Warning "[FAIL] Computer object MISSING from AD: $Name"
            }
        }
    }
    Remove-PSSession $AdSession -EA SilentlyContinue
} catch {
    Write-Warning "Could not verify AD computer objects from dc01: $_"
}

# ─── PART C: D-14 Snapshot commands (operator runs via SSH) ──────────────────
Write-Host @"

=== PART C: D-14 SNAPSHOT COMMANDS (phase2-domain-joined) ===
Run these on each Proxmox host AFTER confirming all 4 VMs are domain-joined.
VMIDs: dc01=201, sql01=202, exchange01=301, ws01=401, ws02=402
D-10 guard: elastic-vm (VMID 200/10.0.0.10) and caldera-vm are NOT snapshotted here.

# ── HOST 2 (dc01=201, sql01=202) ───────────────────────────────
qm stop 201 && qm stop 202
qm snapshot 201 phase2-domain-joined --description "Phase 2 interim: all 5 VMs domain-joined, pre-Exchange/SQL"
qm snapshot 202 phase2-domain-joined --description "Phase 2 interim: all 5 VMs domain-joined, pre-Exchange/SQL"
qm start 201 && qm start 202

# ── HOST 3 (exchange01=301) ─────────────────────────────────────
qm stop 301
qm snapshot 301 phase2-domain-joined --description "Phase 2 interim: all 5 VMs domain-joined, pre-Exchange/SQL"
qm start 301

# ── HOST 4 (ws01=401, ws02=402) ─────────────────────────────────
qm stop 401 && qm stop 402
qm snapshot 401 phase2-domain-joined --description "Phase 2 interim: all 5 VMs domain-joined, pre-Exchange/SQL"
qm snapshot 402 phase2-domain-joined --description "Phase 2 interim: all 5 VMs domain-joined, pre-Exchange/SQL"
qm start 401 && qm start 402

# ── Verify snapshots on all VMIDs ───────────────────────────────
qm listsnapshot 201
qm listsnapshot 202
qm listsnapshot 301
qm listsnapshot 401
qm listsnapshot 402
# Expected: each shows a line containing "phase2-domain-joined"
"@

Write-Host "`n[i] After running snapshot commands, proceed to Plan 05 (Exchange) and Plan 06 (SQL) in parallel." -ForegroundColor Cyan
