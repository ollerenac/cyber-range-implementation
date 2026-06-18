---
plan: 02-06
phase: 02-windows-target-network
status: complete
wave: 4
completed: "2026-06-18"
hardware_checkpoint: approved
---

# Plan 02-06 Summary — SQL Server 2019 on sql01

## What Was Built

One PowerShell automation script for SQL Server 2019 Developer Edition installation on sql01:

| File | Lines | Commit | Purpose |
|------|-------|--------|---------|
| `scripts/windows/setup/06-sql01-install.ps1` | 231 | bef2f0a | SQL 2019 unattended install + sitedata DB + minfac.csv import + ACLs |

## Task Outcomes

**Task 1 (06-sql01-install.ps1):** Full SQL Server 2019 unattended installation pipeline.
- SQL Server 2019 Developer Edition silent install from ISO (D:\) with mixed auth
- `sitedata` database created with `minfac` table schema (critical infrastructure data)
- minfac.csv import via SqlBulkCopy with typed DataTable (RESEARCH.md Pitfall 6 — BULK INSERT chokes on quoted CSV)
- Full database backup to C:\Backups\sitedata.bak
- `LAB\tous` granted db_owner on sitedata + SQL login created with same password
- Firewall rule for TCP 1433 (inbound)

**Task 2 (hardware checkpoint):** Operator confirmed SQL Server responding.
- `sqlcmd -S 10.0.0.13 -Q "SELECT COUNT(*) FROM sitedata.dbo.minfac"` → rows returned
- Port 1433 accessible from control node

## Key Files

```
scripts/windows/setup/06-sql01-install.ps1
```

## Deviations

None. SqlBulkCopy approach for CSV import (vs BULK INSERT) was deliberate per RESEARCH.md Pitfall 6 — quoted fields in minfac.csv cause BULK INSERT to fail silently.

## Self-Check: PASSED

- [x] 06-sql01-install.ps1 exists (231 lines)
- [x] Script committed (bef2f0a, contains "sitedata", "minfac", port 1433)
- [x] Hardware checkpoint approved by operator — SQL port 1433 + minfac table confirmed live
- [x] LAB\tous DBO grant and SQL login included in script
