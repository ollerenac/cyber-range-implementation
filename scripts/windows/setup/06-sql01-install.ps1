# 06-sql01-install.ps1
# SQL Server 2019 Developer Edition unattended install on sql01 + sitedata DB
# + minfac.csv import (SqlBulkCopy) + backup + ACLs (D-07).
#
# USAGE:
#   pwsh 06-sql01-install.ps1 -SaPassword 'SA_P@ss' -DomainAdminPassword 'Domain_P@ss'
#
# PREREQUISITES:
#   - sql01 is domain-joined (Plan 04 complete)
#   - SQL Server 2019 Developer ISO mounted as D: on sql01
#   - minfac.csv copied to sql01 at C:\Temp\minfac.csv via WinRM:
#       Copy-Item -Path .\github\adversary_emulation_library\oilrig\Resources\setup\minfac.csv `
#                 -ToSession (New-PSSession -ComputerName 10.0.0.13 ...) -Destination C:\Temp\

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SaPassword,
    [Parameter(Mandatory)][string]$DomainAdminPassword
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$SqlMgmtIP   = "10.0.0.13"
$SessionOpts = New-PSSessionOption -SkipCACheck -SkipCNCheck
$DomainCred  = New-Object PSCredential("LAB\Administrator",
    (ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force))

$SqlSession = New-PSSession -ComputerName $SqlMgmtIP -Credential $DomainCred -SessionOption $SessionOpts

Invoke-Command -Session $SqlSession -ScriptBlock {
    param($SaPassword)

    Set-StrictMode -Version Latest

    # ─── Part A: ConfigurationFile.ini + SQL Server install ──────────────────
    Write-Host "[i] Part A: SQL Server 2019 unattended install..." -ForegroundColor Cyan

    if (-not (Test-Path "D:\setup.exe")) {
        Write-Error "SQL Server 2019 ISO must be mounted as D: on sql01."
    }

    New-Item -ItemType Directory -Force -Path "C:\Temp","C:\SQLData","C:\SQLLog" | Out-Null

    $ConfigIni = @"
[OPTIONS]
ACTION="Install"
FEATURES=SQLENGINE
INSTANCENAME="MSSQLSERVER"
SECURITYMODE="SQL"
SAPWD="$SaPassword"
SQLSYSADMINACCOUNTS="LAB\SQL Admins" "LAB\Domain Admins"
SQLUSERDBDIR="C:\SQLData"
SQLUSERDBLOGDIR="C:\SQLLog"
SQLBACKUPDIR="C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\Backup"
TCPENABLED=1
NPENABLED=0
BROWSERSVCSTARTUPTYPE="Automatic"
IACCEPTSQLSERVERLICENSETERMS="True"
QUIET="True"
UPDATEENABLED="False"
AGTSVCACCOUNT="NT AUTHORITY\NETWORK SERVICE"
SQLSVCACCOUNT="NT AUTHORITY\NETWORK SERVICE"
"@
    $ConfigPath = "C:\Temp\ConfigurationFile.ini"
    $ConfigIni | Out-File -FilePath $ConfigPath -Encoding ASCII

    Write-Host "[i] Running SQL Server setup (this takes 5-15 minutes)..."
    $proc = Start-Process -FilePath "D:\setup.exe" `
        -ArgumentList "/ConfigurationFile=`"$ConfigPath`"" `
        -Wait -PassThru
    if ($proc.ExitCode -notin @(0, 3010)) {
        Write-Error "SQL Server setup failed (exit $($proc.ExitCode)). Check C:\Program Files\Microsoft SQL Server\*\Setup Bootstrap\Log\"
    }
    Write-Host "[PASS] SQL Server 2019 installed (ExitCode: $($proc.ExitCode))"

    # Restart SQL service to pick up TCP/IP enabled
    Restart-Service MSSQLSERVER -Force
    Start-Sleep -Seconds 10

    # Verify port 1433 listening
    $listening = netstat -ano | Select-String ":1433\s+.*LISTENING"
    if ($listening) {
        Write-Host "[PASS] Port 1433 is LISTENING"
    } else {
        Write-Warning "Port 1433 not yet LISTENING — SQL service may still be starting"
    }

    # ─── Part B: Open port 1433 in Windows Firewall ──────────────────────────
    Write-Host "[i] Part B: Firewall rule for port 1433..." -ForegroundColor Cyan
    $existingRule = Get-NetFirewallRule -DisplayName "SQL Server 1433" -EA SilentlyContinue
    if (-not $existingRule) {
        New-NetFirewallRule -DisplayName "SQL Server 1433" -Direction Inbound `
            -Protocol TCP -LocalPort 1433 -Action Allow | Out-Null
        Write-Host "[PASS] Firewall rule created: SQL Server 1433 inbound allow"
    } else {
        Write-Host "[PASS] Firewall rule already exists"
    }

    # ─── Part C: Create sitedata database + minfac table ─────────────────────
    Write-Host "[i] Part C: Create sitedata database and minfac table..." -ForegroundColor Cyan

    $createDB = @"
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'sitedata')
    CREATE DATABASE sitedata;
GO
USE sitedata;
GO
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'minfac')
BEGIN
    CREATE TABLE dbo.minfac (
        position     INT,
        rec_id       NVARCHAR(50),
        year         INT,
        country      NVARCHAR(100),
        commodity    NVARCHAR(100),
        location     NVARCHAR(200),
        fac_name     NVARCHAR(300),
        fac_type     NVARCHAR(100),
        dmslat       NVARCHAR(50),
        dmslong      NVARCHAR(50),
        latitude     FLOAT,
        longitude    FLOAT,
        precision_   NVARCHAR(50),
        mm           NVARCHAR(50),
        op_comp      NVARCHAR(200),
        maininvest   NVARCHAR(300),
        othinvest    NVARCHAR(300),
        status       NVARCHAR(100),
        capacity     NVARCHAR(100),
        units        NVARCHAR(50),
        notes        NVARCHAR(MAX),
        cite         NVARCHAR(MAX)
    );
END
"@
    sqlcmd -S localhost -Q $createDB -b
    Write-Host "[PASS] sitedata database and minfac table created"

    # ─── Part D: Import minfac.csv using SqlBulkCopy (quoted fields safe) ────
    Write-Host "[i] Part D: Import minfac.csv via SqlBulkCopy..." -ForegroundColor Cyan

    if (-not (Test-Path "C:\Temp\minfac.csv")) {
        Write-Error "minfac.csv not found at C:\Temp\minfac.csv. Copy via WinRM from control node:
  Copy-Item -Path .\github\adversary_emulation_library\oilrig\Resources\setup\minfac.csv ``
            -ToSession (New-PSSession -ComputerName 10.0.0.13 -Credential ...) -Destination C:\Temp\"
    }

    $csv = Import-Csv "C:\Temp\minfac.csv"
    $conn = New-Object System.Data.SqlClient.SqlConnection(
        "Server=localhost;Database=sitedata;Integrated Security=true")
    $conn.Open()

    $dt = New-Object System.Data.DataTable
    @("position","rec_id","year","country","commodity","location","fac_name","fac_type",
      "dmslat","dmslong","latitude","longitude","precision_","mm","op_comp","maininvest",
      "othinvest","status","capacity","units","notes","cite") | ForEach-Object {
        $dt.Columns.Add($_) | Out-Null
    }

    foreach ($row in $csv) {
        $dr = $dt.NewRow()
        $dr["position"]    = if ($row.position)   { [int]$row.position }   else { [DBNull]::Value }
        $dr["rec_id"]      = $row.rec_id
        $dr["year"]        = if ($row.year -match '^\d+$') { [int]$row.year } else { [DBNull]::Value }
        $dr["country"]     = $row.country
        $dr["commodity"]   = $row.commodity
        $dr["location"]    = $row.location
        $dr["fac_name"]    = $row.fac_name
        $dr["fac_type"]    = $row.fac_type
        $dr["dmslat"]      = $row.dmslat
        $dr["dmslong"]     = $row.dmslong
        $dr["latitude"]    = if ($row.latitude  -match '^-?\d+\.?\d*$') { [double]$row.latitude  } else { [DBNull]::Value }
        $dr["longitude"]   = if ($row.longitude -match '^-?\d+\.?\d*$') { [double]$row.longitude } else { [DBNull]::Value }
        $dr["precision_"]  = $row.precision
        $dr["mm"]          = $row.mm
        $dr["op_comp"]     = $row.op_comp
        $dr["maininvest"]  = $row.maininvest
        $dr["othinvest"]   = $row.othinvest
        $dr["status"]      = $row.status
        $dr["capacity"]    = $row.capacity
        $dr["units"]       = $row.units
        $dr["notes"]       = $row.notes
        $dr["cite"]        = $row.cite
        $dt.Rows.Add($dr)
    }

    $bulk = New-Object System.Data.SqlClient.SqlBulkCopy($conn)
    $bulk.DestinationTableName = "dbo.minfac"
    $bulk.WriteToServer($dt)
    $conn.Close()

    $rowCount = (sqlcmd -S localhost -Q "SELECT COUNT(*) FROM sitedata.dbo.minfac" -h -1).Trim()
    Write-Host "[PASS] minfac import complete: $rowCount rows loaded"

    # ─── Part E: Create sitedata backup (D-07) ───────────────────────────────
    Write-Host "[i] Part E: Backup sitedata database..." -ForegroundColor Cyan
    $BackupPath = "C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\Backup\sitedata.bak"
    sqlcmd -S localhost -Q "BACKUP DATABASE sitedata TO DISK='$BackupPath' WITH FORMAT, INIT, COMPRESSION;" -b
    Write-Host "[PASS] sitedata backup created at $BackupPath"

    # ─── Part F: LAB\tous SQL login + db_owner role (Pitfall 7 mitigation) ───
    Write-Host "[i] Part F: Creating LAB\tous SQL login and db_owner role..." -ForegroundColor Cyan
    sqlcmd -S localhost -b -Q @"
IF NOT EXISTS (SELECT name FROM sys.server_principals WHERE name = 'LAB\tous')
    CREATE LOGIN [LAB\tous] FROM WINDOWS;
USE sitedata;
IF NOT EXISTS (SELECT name FROM sys.database_principals WHERE name = 'LAB\tous')
    CREATE USER [LAB\tous] FOR LOGIN [LAB\tous];
EXEC sp_addrolemember 'db_owner', 'LAB\tous';
ALTER AUTHORIZATION ON DATABASE::sitedata TO [LAB\tous];
"@
    Write-Host "[PASS] LAB\tous has db_owner role in sitedata"

    # ─── Part G: SQL Admins group → Local Administrators ─────────────────────
    Write-Host "[i] Part G: Adding LAB\SQL Admins to local Administrators..." -ForegroundColor Cyan
    $existingMember = net localgroup Administrators | Select-String "SQL Admins"
    if (-not $existingMember) {
        net localgroup Administrators "LAB\SQL Admins" /add | Out-Null
        Write-Host "[PASS] LAB\SQL Admins added to local Administrators"
    } else {
        Write-Host "[PASS] LAB\SQL Admins already in local Administrators"
    }

    Write-Host "`n[PASS] Plan 06 complete." -ForegroundColor Green
    Write-Host "[i] Verify from control node:"
    Write-Host "    pwsh -c `"Invoke-Command -CN 10.0.0.13 -Cred `$cred -SB { sqlcmd -S localhost -Q 'SELECT COUNT(*) FROM sitedata.dbo.minfac' }`""

} -ArgumentList $SaPassword

Remove-PSSession $SqlSession -EA SilentlyContinue
