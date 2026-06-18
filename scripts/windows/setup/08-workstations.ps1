# =============================================================================
# 08-workstations.ps1 — Workstation-specific configuration for ws01 and ws02
#
# LOCKED SPECS (do NOT change without updating D-08..D-11 in 02-CONTEXT.md):
#   D-08: file_generator.exe — 100 files C:\Users\Public\ + 50 files C:\Users\ (seed=EVALS)
#         BOTH ws01 and ws02; files must be in clean_state snapshot (Wizard Spider target)
#   D-09: Microsoft Office + Outlook on ws01 ONLY (OilRig + Wizard Spider Dorothy)
#   D-10: Google Chrome on ws02 ONLY (APT29 S1 chrome-passwords target)
#         Same local Administrator password on ws01 AND ws02 (APT29 Pass-the-Hash lateral movement)
#   D-11: judy gets takeown C:\Windows\* + icacls full control on ws01 (Wizard Spider scenario)
#
# USAGE:
#   # Run on ws01 (from control node):
#   $s = New-PSSession -ComputerName 10.0.0.14 -Credential $cred -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)
#   Copy-Item -Path ".\08-workstations.ps1",".\file_generator.exe" -Destination "C:\Temp\" -ToSession $s
#   Invoke-Command -Session $s -ScriptBlock { & "C:\Temp\08-workstations.ps1" -Target "ws01" }
#
#   # Run on ws02 (from control node):
#   $s = New-PSSession -ComputerName 10.0.0.15 -Credential $cred -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)
#   Copy-Item -Path ".\08-workstations.ps1",".\file_generator.exe" -Destination "C:\Temp\" -ToSession $s
#   Invoke-Command -Session $s -ScriptBlock { & "C:\Temp\08-workstations.ps1" -Target "ws02" }
#
# PREREQUISITES:
#   1. Run 07-security-baseline.ps1 on BOTH ws01 and ws02 FIRST (Defender must be off — Pitfall 8)
#   2. Copy to C:\Temp\ on ws01: file_generator.exe, setup.exe (Office installer), office-config.xml
#   3. Copy to C:\Temp\ on ws02: file_generator.exe
#   4. file_generator.exe location: github/adversary_emulation_library/wizard_spider/Resources/setup/file_generator/
#
# D-10 NOTE: ws01 and ws02 MUST have the same local Administrator password for APT29 Pass-the-Hash.
#   The passwords are set in autounattend.xml. If they differ, reset ws02 via:
#     net user Administrator <same_password_as_ws01>
#   Verify both passwords match in .planning/secrets/PASSWORDS.md before running emulation.
#
# OFFICE CONFIG NOTE: Provide a minimal office-config.xml at C:\Temp\office-config.xml
#   Example config (Microsoft 365 Apps for Enterprise, 64-bit, en-US):
#     <Configuration>
#       <Add OfficeClientEdition="64" Channel="PerpetualVL2019">
#         <Product ID="ProPlus2019Retail">
#           <Language ID="en-us"/>
#           <ExcludeApp ID="Teams"/>
#         </Product>
#       </Add>
#       <Display Level="None" AcceptEULA="TRUE"/>
#     </Configuration>
#   Adapt Product ID to match your license type. See: https://learn.microsoft.com/deployoffice/office-deployment-tool-configuration-options
# =============================================================================

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("ws01","ws02")]
    [string]$Target
)

$ErrorActionPreference = "Continue"

Write-Host "================================================================"
Write-Host " 08-workstations.ps1 — Target: $Target"
Write-Host " Host: $env:COMPUTERNAME"
Write-Host "================================================================"

# ============================================================
# SHARED PRE-FLIGHT: Verify Defender is disabled
# Pitfall 8: file_generator.exe is blocked by Windows Defender.
# This script MUST be run after 07-security-baseline.ps1.
# ============================================================

Write-Host "[i] Pre-flight: checking Defender status (must be off before file_generator runs)"

$defStatus = (Get-MpComputerStatus -ErrorAction SilentlyContinue)
if ($defStatus -and $defStatus.RealTimeProtectionEnabled -eq $true) {
    Write-Error "ABORT: Windows Defender real-time protection is still enabled on $env:COMPUTERNAME."
    Write-Error "Run 07-security-baseline.ps1 first, then reboot, then re-run this script."
    Write-Error "Pitfall 8: file_generator.exe will be blocked and silently fail with Defender on."
    exit 1
}
Write-Host "[PASS] Defender real-time protection is off — safe to run file_generator.exe"

# ============================================================
# WS01 SECTION
# ============================================================

if ($Target -eq "ws01") {

    Write-Host ""
    Write-Host "--- WS01 Configuration ---"

    # ----------------------------------------------------------
    # STEP 1: Install Microsoft Office + Outlook (D-09)
    # Required by: OilRig Exchange Admin Workstation scenario + Wizard Spider Dorothy scenario
    # PREREQUISITE: Operator must place at C:\Temp\ before running:
    #   setup.exe        — Office 365 click-to-run installer (ODT setup.exe)
    #   office-config.xml — ODT configuration file (see header for example)
    # ----------------------------------------------------------

    Write-Host "[1/4] Installing Microsoft Office + Outlook on ws01 (D-09)"

    $officeSetup  = "C:\Temp\setup.exe"
    $officeConfig = "C:\Temp\office-config.xml"

    if (-not (Test-Path $officeSetup)) {
        Write-Warning "[!] $officeSetup not found — skipping Office install."
        Write-Warning "    Download ODT (Office Deployment Tool) setup.exe from:"
        Write-Warning "    https://www.microsoft.com/en-us/download/details.aspx?id=49117"
        Write-Warning "    Copy setup.exe and office-config.xml to C:\Temp\ on ws01."
    } elseif (-not (Test-Path $officeConfig)) {
        Write-Warning "[!] $officeConfig not found — skipping Office install."
        Write-Warning "    Create an ODT configuration XML. See script header for example."
        Write-Warning "    Reference: https://learn.microsoft.com/deployoffice/office-deployment-tool-configuration-options"
    } else {
        Write-Host "[i] Running Office silent install (this may take 10-20 minutes)..."
        Start-Process -FilePath $officeSetup -Args "/configure `"$officeConfig`"" -Wait -NoNewWindow
        Write-Host "[i] Office setup.exe exited"

        # Verify Outlook installed
        $outlookPath = "C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE"
        $outlookPath2 = "C:\Program Files (x86)\Microsoft Office\root\Office16\OUTLOOK.EXE"
        if ((Test-Path $outlookPath) -or (Test-Path $outlookPath2)) {
            Write-Host "[PASS] Outlook.exe found — Office install succeeded"
        } else {
            Write-Warning "[WARN] Outlook.exe not found at expected path. Check C:\Temp\ for Office setup logs."
            Write-Warning "       Expected: $outlookPath"
        }
    }

    # ----------------------------------------------------------
    # STEP 2: Run file_generator.exe (D-08)
    # Generates dummy files for Wizard Spider ransomware encryption scenario
    # MUST run AFTER Defender is disabled (verified in pre-flight above)
    # Source: github/adversary_emulation_library/wizard_spider/Resources/setup/file_generator/
    # ----------------------------------------------------------

    Write-Host "[2/4] Generating dummy files on ws01 (D-08 — Wizard Spider ransomware targets)"

    $fileGen = "C:\Temp\file_generator.exe"

    if (-not (Test-Path $fileGen)) {
        Write-Warning "[!] $fileGen not found — skipping file generation."
        Write-Warning "    Copy file_generator.exe from:"
        Write-Warning "    github/adversary_emulation_library/wizard_spider/Resources/setup/file_generator/"
        Write-Warning "    to C:\Temp\ on ws01 and re-run this step."
    } else {
        # Set execution policy for this session
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

        Write-Host "[i] Generating 100 files in C:\Users\Public\ (seed=EVALS)..."
        & $fileGen -path "C:\Users\Public\" -count 100 -seed EVALS
        Write-Host "[i] Generating 50 files in C:\Users\ (seed=EVALS)..."
        & $fileGen -path "C:\Users\" -count 50 -seed EVALS

        # Verify
        $publicCount = (Get-ChildItem "C:\Users\Public\" -ErrorAction SilentlyContinue | Measure-Object).Count
        $usersCount  = (Get-ChildItem "C:\Users\" -ErrorAction SilentlyContinue | Measure-Object).Count

        if ($publicCount -ge 100) {
            Write-Host "[PASS] C:\Users\Public\ file count = $publicCount (>= 100)"
        } else {
            Write-Host "[FAIL] C:\Users\Public\ file count = $publicCount (expected >= 100)"
        }
        if ($usersCount -ge 50) {
            Write-Host "[PASS] C:\Users\ file count = $usersCount (>= 50)"
        } else {
            Write-Host "[FAIL] C:\Users\ file count = $usersCount (expected >= 50)"
        }
    }

    # ----------------------------------------------------------
    # STEP 3: Grant judy full control on C:\Windows (D-11)
    # Required by: Wizard Spider scenario — judy must be able to write to C:\Windows
    # judy is a domain user (LAB\judy), NOT a local admin
    # This icacls grant is intentional — it is a scenario pre-condition, not an error
    # ----------------------------------------------------------

    Write-Host "[3/4] Granting LAB\judy full control on C:\Windows (D-11 — Wizard Spider scenario)"

    Write-Host "[i] Running takeown on C:\Windows (recursive — this takes several minutes)..."
    takeown /f C:\Windows /r /d Y 2>&1 | Out-Null
    Write-Host "[i] takeown complete"

    Write-Host "[i] Running icacls to grant LAB\judy (OI)(CI)F on C:\Windows..."
    icacls "C:\Windows" /grant "LAB\judy:(OI)(CI)F" /T 2>&1 | Select-Object -Last 5
    Write-Host "[i] icacls grant complete — LAB\judy has full control on C:\Windows"

    # ----------------------------------------------------------
    # STEP 4: Verification summary for ws01
    # ----------------------------------------------------------

    Write-Host ""
    Write-Host "[4/4] ws01 verification summary"

    # Office
    $outlookFound = (Test-Path "C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE") -or
                    (Test-Path "C:\Program Files (x86)\Microsoft Office\root\Office16\OUTLOOK.EXE")
    if ($outlookFound) {
        Write-Host "[PASS] Office/Outlook: installed"
    } else {
        Write-Host "[SKIP] Office/Outlook: not found (may need manual install)"
    }

    # Dummy files
    $publicCount = (Get-ChildItem "C:\Users\Public\" -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Host "[INFO] C:\Users\Public\ file count = $publicCount"

    # judy permissions — check icacls output
    $icaclsOut = icacls "C:\Windows" 2>&1 | Select-String "judy"
    if ($icaclsOut) {
        Write-Host "[PASS] judy icacls: $icaclsOut"
    } else {
        Write-Host "[WARN] judy not found in icacls output for C:\Windows — re-run Step 3"
    }
}

# ============================================================
# WS02 SECTION
# ============================================================

if ($Target -eq "ws02") {

    Write-Host ""
    Write-Host "--- WS02 Configuration ---"

    # ----------------------------------------------------------
    # STEP 1: Install Google Chrome (D-10)
    # Required by: APT29 Scenario 1 — chrome-passwords.exe dumps Chrome saved credentials
    # Chrome install can be automated; credential CACHING requires an interactive operator step (DPAPI)
    # ----------------------------------------------------------

    Write-Host "[1/3] Installing Google Chrome on ws02 (D-10)"

    $chromeInstaller = "C:\Temp\ChromeSetup.exe"
    $chromeExe       = "C:\Program Files\Google\Chrome\Application\chrome.exe"

    if (Test-Path $chromeExe) {
        Write-Host "[PASS] Chrome already installed at $chromeExe — skipping download/install"
    } else {
        # Try to download from Google if internet is available via MGMT NIC
        $hasInternet = $false
        try {
            $null = Invoke-WebRequest -Uri "https://dl.google.com/chrome/" -Method Head -UseBasicParsing -TimeoutSec 5
            $hasInternet = $true
        } catch {
            Write-Host "[i] No internet access from this NIC — will use pre-copied installer"
        }

        if ($hasInternet -and -not (Test-Path $chromeInstaller)) {
            Write-Host "[i] Downloading Chrome installer from Google..."
            Invoke-WebRequest -Uri "https://dl.google.com/chrome/install/latest/chrome_installer.exe" `
                -OutFile $chromeInstaller -UseBasicParsing
            Write-Host "[i] Chrome installer downloaded to $chromeInstaller"
        }

        if (Test-Path $chromeInstaller) {
            Write-Host "[i] Installing Chrome silently..."
            Start-Process -FilePath $chromeInstaller -Args "/silent /install" -Wait -NoNewWindow
            Write-Host "[i] Chrome installer exited"
        } else {
            Write-Warning "[!] Chrome installer not found at $chromeInstaller and download failed."
            Write-Warning "    Pre-download Chrome standalone installer and copy to C:\Temp\ChromeSetup.exe"
            Write-Warning "    Standalone installer: https://dl.google.com/chrome/install/latest/chrome_installer.exe"
        }

        if (Test-Path $chromeExe) {
            Write-Host "[PASS] Chrome installed at $chromeExe"
        } else {
            Write-Host "[FAIL] Chrome not found at $chromeExe after install attempt"
        }
    }

    # MANUAL STEP REQUIRED — Chrome credential caching
    Write-Host ""
    Write-Host "================================================================"
    Write-Host " MANUAL STEP REQUIRED: Chrome saved credential on ws02 (D-10)"
    Write-Host "================================================================"
    Write-Host " APT29 Scenario 1 uses chrome-passwords.exe to dump saved Chrome"
    Write-Host " credentials. At least 1 saved password must exist in Chrome."
    Write-Host ""
    Write-Host " This step CANNOT be automated. Chrome encrypts saved passwords"
    Write-Host " using Windows DPAPI tied to the logged-in user session."
    Write-Host ""
    Write-Host " OPERATOR INSTRUCTIONS:"
    Write-Host "   1. RDP to ws02 (10.0.0.15) as Administrator"
    Write-Host "      OR use Proxmox SPICE console for ws02"
    Write-Host "   2. Open Chrome: C:\Program Files\Google\Chrome\Application\chrome.exe"
    Write-Host "   3. If Chrome prompts to sign in to Google — click 'Not now' / 'Skip'"
    Write-Host "   4. Navigate to chrome://password-manager/passwords"
    Write-Host "   5. Click 'Add' and enter any dummy credential:"
    Write-Host "        Site:     http://intranet.lab.local"
    Write-Host "        Username: administrator"
    Write-Host "        Password: any string (e.g., DummyPass123!)"
    Write-Host "   6. Verify: at least 1 entry appears in chrome://password-manager/passwords"
    Write-Host "   7. Close Chrome"
    Write-Host "   8. Return to control node and type 'approved' to continue."
    Write-Host ""
    Write-Host " NOTE: See 02-RESEARCH.md Open Question 1 for technical background."
    Write-Host "================================================================"

    # ----------------------------------------------------------
    # STEP 2: Run file_generator.exe (D-08)
    # Same as ws01 — generates ransomware encryption targets
    # ----------------------------------------------------------

    Write-Host "[2/3] Generating dummy files on ws02 (D-08 — Wizard Spider ransomware targets)"

    $fileGen = "C:\Temp\file_generator.exe"

    if (-not (Test-Path $fileGen)) {
        Write-Warning "[!] $fileGen not found — skipping file generation."
        Write-Warning "    Copy file_generator.exe from:"
        Write-Warning "    github/adversary_emulation_library/wizard_spider/Resources/setup/file_generator/"
        Write-Warning "    to C:\Temp\ on ws02 and re-run this step."
    } else {
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

        Write-Host "[i] Generating 100 files in C:\Users\Public\ (seed=EVALS)..."
        & $fileGen -path "C:\Users\Public\" -count 100 -seed EVALS
        Write-Host "[i] Generating 50 files in C:\Users\ (seed=EVALS)..."
        & $fileGen -path "C:\Users\" -count 50 -seed EVALS

        $publicCount = (Get-ChildItem "C:\Users\Public\" -ErrorAction SilentlyContinue | Measure-Object).Count
        $usersCount  = (Get-ChildItem "C:\Users\" -ErrorAction SilentlyContinue | Measure-Object).Count

        if ($publicCount -ge 100) {
            Write-Host "[PASS] C:\Users\Public\ file count = $publicCount (>= 100)"
        } else {
            Write-Host "[FAIL] C:\Users\Public\ file count = $publicCount (expected >= 100)"
        }
        if ($usersCount -ge 50) {
            Write-Host "[PASS] C:\Users\ file count = $usersCount (>= 50)"
        } else {
            Write-Host "[FAIL] C:\Users\ file count = $usersCount (expected >= 50)"
        }
    }

    # ----------------------------------------------------------
    # STEP 3: Verification summary for ws02
    # ----------------------------------------------------------

    Write-Host ""
    Write-Host "[3/3] ws02 verification summary"

    $chromeInstalled = Test-Path "C:\Program Files\Google\Chrome\Application\chrome.exe"
    if ($chromeInstalled) {
        Write-Host "[PASS] Chrome: installed"
    } else {
        Write-Host "[FAIL] Chrome: not found — check install log"
    }

    $publicCount = (Get-ChildItem "C:\Users\Public\" -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Host "[INFO] C:\Users\Public\ file count = $publicCount"

    Write-Host ""
    Write-Host "[!] REMINDER: Chrome credential caching requires a MANUAL OPERATOR STEP."
    Write-Host "    Open Chrome on ws02, navigate to chrome://password-manager/passwords,"
    Write-Host "    add a dummy saved credential, then run verify-phase2.ps1."
}

Write-Host ""
Write-Host "[i] 08-workstations.ps1 complete for target: $Target"
Write-Host "================================================================"
