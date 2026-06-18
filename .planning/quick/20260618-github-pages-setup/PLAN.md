---
task: github-pages-setup
slug: github-pages-setup
status: in-progress
created: 2026-06-18
---

# Quick Task: GitHub Pages — Granate Red Theme + Content

## Goal
Publish the Cyber Range thesis docs to GitHub Pages with a granate red (dark garnet) color theme so the operator can review the site online at https://ollerenac.github.io/titulacion/.

## Tasks
1. Create `docs/index.md` — project landing page with overview, links to phase runbooks
2. Create `docs/assets/css/style.scss` — override Cayman theme with granate red palette
3. Create `docs/phase-01-runbook.md` — Phase 1 operator runbook (Proxmox + SIEM setup)
4. Push to GitHub → instruct operator to enable GitHub Pages (Settings → Pages → /docs)

## Acceptance
- Site renders at https://ollerenac.github.io/titulacion/
- Header and headings use granate red (#7B1F26 palette)
- Phase 01 runbook is reachable from the index

## Notes
- Does NOT touch .planning/ phases or scripts — fully isolated
- Granate red: #7B1F26 (dark), #A0282F (mid), #C1363E (light accent)
