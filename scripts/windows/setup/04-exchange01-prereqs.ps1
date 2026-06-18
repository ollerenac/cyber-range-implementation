# 04-exchange01-prereqs.ps1
# Installs Exchange Server 2019 prerequisites on exchange01 in 5 numbered steps.
# Run via WinRM from control node: Invoke-Command -ComputerName 10.0.0.12 -FilePath .\04-exchange01-prereqs.ps1 -ArgumentList 1
#
# USAGE (run each step, reboot between 1→2→3, no reboot needed between 3→4→5):
#   pwsh 04-exchange01-prereqs.ps1 -Step 1   # Windows features (triggers reboot)
#   pwsh 04-exchange01-prereqs.ps1 -Step 2   # .NET Framework 4.8 (triggers reboot)
#   pwsh 04-exchange01-prereqs.ps1 -Step 3   # UCMA 4.0 from Exchange ISO (no reboot)
#   pwsh 04-exchange01-prereqs.ps1 -Step 4   # Visual C++ 2012 + 2013 (no reboot)
#   pwsh 04-exchange01-prereqs.ps1 -Step 5   # IIS URL Rewrite (no reboot)
#
# PREREQUISITES before running:
#   - Exchange ISO mounted as E: (needed for Step 3)
#   - Files pre-copied to C:\Temp\ via WinRM:
#       ndp48-x86-x64-allos-enu.exe    (.NET 4.8 offline installer)
#       vcredist_x64_2012.exe          (Visual C++ 2012 x64)
#       vcredist_x64_2013.exe          (Visual C++ 2013 x64)
#       rewrite_amd64_en-US.msi        (IIS URL Rewrite)

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(1,5)][int]$Step
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step([string]$msg) { Write-Host "[i] $msg" -ForegroundColor Cyan }
function Write-OK([string]$msg)   { Write-Host "[PASS] $msg" -ForegroundColor Green }
function Write-Fail([string]$msg) { Write-Error "[FAIL] $msg" }

switch ($Step) {

    1 {
        Write-Step "Step 1: Installing Windows features required by Exchange 2019..."

        $Features = @(
            "NET-Framework-45-Features","NET-Framework-45-Core","NET-Framework-45-ASPNET",
            "NET-WCF-HTTP-Activation45","NET-WCF-Pipe-Activation45","NET-WCF-TCP-Activation45",
            "NET-WCF-TCP-PortSharing45","RPC-over-HTTP-proxy","RSAT-Clustering",
            "RSAT-Clustering-CmdInterface","RSAT-Clustering-Mgmt","RSAT-Clustering-PowerShell",
            "Web-Mgmt-Console","WAS-Process-Model","Web-Asp-Net45","Web-Basic-Auth",
            "Web-Client-Auth","Web-Digest-Auth","Web-Dir-Browsing","Web-Dyn-Compression",
            "Web-Http-Errors","Web-Http-Logging","Web-Http-Redirect","Web-Http-Tracing",
            "Web-ISAPI-Ext","Web-ISAPI-Filter","Web-Lgcy-Mgmt-Console","Web-Metabase",
            "Web-Mgmt-Service","Web-Net-Ext45","Web-Request-Monitor","Web-Server",
            "Web-Stat-Compression","Web-Static-Content","Web-Windows-Auth","Web-WMI",
            "Windows-Identity-Foundation","RSAT-ADDS"
        )

        $result = Install-WindowsFeature -Name $Features -IncludeManagementTools -Restart
        if ($result.RestartNeeded -eq "Yes") {
            Write-OK "Step 1 complete — Windows features installed. System will reboot now."
            Write-Step "After reboot: run Step 2."
        } else {
            Write-OK "Step 1 complete — Windows features installed (no reboot needed)."
            Write-Step "Run Step 2 next."
        }
    }

    2 {
        Write-Step "Step 2: Installing .NET Framework 4.8..."
        $Installer = "C:\Temp\ndp48-x86-x64-allos-enu.exe"
        if (-not (Test-Path $Installer)) {
            Write-Fail "Missing: $Installer. Copy ndp48-x86-x64-allos-enu.exe to C:\Temp\ via WinRM first."
        }
        Start-Process -FilePath $Installer -ArgumentList "/quiet /norestart /log C:\Temp\dotnet48.log" -Wait
        Write-OK "Step 2 complete — .NET 4.8 installed."
        Write-Step "Reboot now, then run Step 3."
        Restart-Computer -Force
    }

    3 {
        Write-Step "Step 3: Installing UCMA 4.0 from Exchange ISO..."
        $UCMAPath = "E:\UCMARedist\UCMARunTimeSetup.exe"
        if (-not (Test-Path $UCMAPath)) {
            Write-Fail "Exchange ISO must be mounted as E:. UCMARedist\ not found at E:\. Mount ISO first."
        }
        Start-Process -FilePath $UCMAPath -ArgumentList "/quiet" -Wait
        Write-OK "Step 3 complete — UCMA 4.0 installed."
        Write-Step "Continue to Step 4 (no reboot needed)."
    }

    4 {
        Write-Step "Step 4: Installing Visual C++ 2012 and 2013 Redistributables..."
        foreach ($vc in @("C:\Temp\vcredist_x64_2012.exe","C:\Temp\vcredist_x64_2013.exe")) {
            if (-not (Test-Path $vc)) {
                Write-Fail "Missing: $vc. Pre-copy to C:\Temp\ via WinRM."
            }
            Start-Process -FilePath $vc -ArgumentList "/quiet /norestart" -Wait
            Write-OK "Installed: $(Split-Path $vc -Leaf)"
        }
        Write-Step "Continue to Step 5 (no reboot needed)."
    }

    5 {
        Write-Step "Step 5: Installing IIS URL Rewrite Module..."
        $Msi = "C:\Temp\rewrite_amd64_en-US.msi"
        if (-not (Test-Path $Msi)) {
            Write-Fail "Missing: $Msi. Pre-copy to C:\Temp\ via WinRM."
        }
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$Msi`" /quiet /norestart" -Wait
        Write-OK "Step 5 complete — IIS URL Rewrite installed."
        Write-OK "ALL Exchange prerequisites installed. Proceed with 05-exchange01-install.ps1."
    }
}
