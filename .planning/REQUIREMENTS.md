# Requirements: Cyber Range — APT Emulation & Intrusion Detection

**Defined:** 2026-06-08
**Core Value:** Un operador ejecuta un escenario APT, observa telemetría real, detecta la intrusión — y resetea todo en un comando para repetirlo.

## v1 Requirements

### Infrastructure (INFRA)

- [ ] **INFRA-01**: Proxmox VE 8.x instalado de forma independiente en cada una de las 5-6 máquinas físicas (8 vCPU, 16 GB RAM c/u); cada máquina expone bridges aislados — vmbr0 MGMT (10.0.0.0/24), vmbr1 TARGET (10.10.10.0/24) sin uplink físico
- [ ] **INFRA-02**: elastic-vm (Ubuntu 22.04, 8-16 GB RAM) con Elasticsearch 8.17.x + Kibana + Fleet Server desplegado en máquina dedicada, accesible en MGMT network
- [ ] **INFRA-03**: dc01 (Windows Server 2019, máquina dedicada) con Active Directory DS configurado como Domain Controller del dominio lab.local
- [ ] **INFRA-04**: exchange01 (Windows Server 2019, máquina dedicada) con Exchange Server 2019 instalado y unido al dominio
- [ ] **INFRA-05**: sql01 (Windows Server 2019, máquina dedicada) con SQL Server 2019 instalado y unido al dominio
- [x] **INFRA-06**: ws01 (Windows 10/11, máquina compartida con kali o dedicada) como workstation del dominio — target realista para lateral movement
- [ ] **INFRA-07**: kali (Kali Linux) con Metasploit, Impacket, BloodHound CE y Mimikatz instalados y funcionales
- [ ] **INFRA-08**: OPNsense VM en Host 6 (rol firewall) como gateway perimetral del lab — WAN=wlan0 (via NAT kernel host), LAN=eth0→switch→hosts 1-5; todas las VMs MGMT y TARGET usan OPNsense como default gateway hacia internet
- [ ] **INFRA-09**: Snort IDS inline en OPNsense LAN interface — reglas ET Open activas; alerta en tráfico C2 anómalo, escaneo de red y movimiento lateral cross-segment

### Reset Mechanism (RESET)

- [ ] **RESET-01**: Snapshot "clean_state" tomado en dc01, exchange01, sql01 y kali de forma simultánea, DESPUÉS de que todos los Elastic Agents estén Healthy en Fleet
- [ ] **RESET-02**: Script `reset_range.sh` que vía SSH paralelo detiene, revierte (qm rollback) e inicia todos los VMs del reset cycle en las máquinas físicas correspondientes — un solo comando desde el nodo de control
- [ ] **RESET-03**: El reset completo (stop → rollback → start de 4 VMs) tarda menos de 5 minutos y deja el dominio AD funcional sin intervención manual

### Telemetry Pipeline (TELEM)

- [ ] **TELEM-01**: Elastic Agents enrollados en dc01, exchange01 y sql01 vía Fleet Server usando exclusivamente la MGMT NIC (eth1)
- [ ] **TELEM-02**: Elastic Defend desplegado en todos los Windows VMs en modo DETECT (no PREVENT) — verificable en Fleet policy antes de cada ejercicio
- [ ] **TELEM-03**: Sysmon (olafhartong/sysmon-modular) instalado en todos los Windows VMs con EventIDs 1, 3, 8, 10, 11 y 13 activos
- [ ] **TELEM-04**: Packetbeat instalado en todas las VMs para telemetría de red (documentado: no descifra TLS C2)

### Red Team / APT Emulation (RED)

- [ ] **RED-01**: CALDERA 5.x servidor en elastic-vm con agentes implantables en targets; operación de prueba ejecutada exitosamente
- [ ] **RED-02**: Plan APT29 adaptado para telemetría Elastic + extendido con técnicas ATT&CK adicionales + empaquetado como adversario CALDERA con abilities YAML
- [ ] **RED-03**: Plan OilRig (APT34) adaptado + extendido + empaquetado como adversario CALDERA
- [ ] **RED-04**: Plan Wizard Spider adaptado + extendido + empaquetado como adversario CALDERA

### Detection Engineering (DETECT)

- [ ] **DETECT-01**: Elastic ML anomaly detection jobs configurados con mínimo 48h de datos baseline antes de la primera emulación
- [ ] **DETECT-02**: Detection rules en Kibana cubriendo las técnicas primarias de cada escenario APT (mínimo 5 reglas por grupo)
- [ ] **DETECT-03**: Tabla de resultados (Technique ID | Emulated | Detected | Detection Method) generada para cada uno de los 3 escenarios APT

### Dataset (DATA)

- [ ] **DATA-01**: Corpus de telemetría FullAPT-2025 recolectado cubriendo ≥117 técnicas MITRE ATT&CK v14 a través de los 3 escenarios
- [ ] **DATA-02**: Dataset estructurado y documentado con metadatos suficientes para reproducibilidad

### Thesis Document (THESIS)

- [ ] **THESIS-01**: Los 10 capítulos de la tesis redactados: Introducción, Marco Teórico, Arquitectura, Módulo Red Team, Módulo Blue Team, Telemetría Dual, Detección ML, Evaluación y Métricas, Conclusiones, Bibliografía
- [ ] **THESIS-02**: Cada escenario APT documentado con metodología, evidencia de telemetría (exportación Elasticsearch) y tabla de resultados de detección

### Documentation / GitHub Pages (DOCS)

- [ ] **DOCS-01**: Guía de setup del cyber range publicada en GitHub Pages (Proxmox → Elastic Stack → CALDERA → VMs target, con comandos copiables)
- [ ] **DOCS-02**: Runbooks de emulación APT publicados — uno por grupo (APT29, OilRig, Wizard Spider): pasos del procedimiento + telemetría esperada + mapeo de detección

## v2 Requirements

### Extended Coverage

- **EXT-01**: Escenarios adicionales del CTID library (Sandworm, Turla, FIN7, Carbanak)
- **EXT-02**: Workstation Windows 10/11 como VM target adicional
- **EXT-03**: Detección de beaconing TLS vía análisis de metadata de flujo (frecuencia, tamaño de paquetes)

### Advanced Detection

- **ADV-01**: Custom supervised ML model entrenado sobre FullAPT-2025 dataset
- **ADV-02**: SOAR/automated remediation via Elastic SIEM Cases API
- **ADV-03**: Dashboard ejecutivo de cobertura ATT&CK (heat map de técnicas)

### Platform

- **PLT-01**: Multi-user access control para ejercicios en equipo
- **PLT-02**: Opción de despliegue cloud (AWS/GCP) con terraform

## Out of Scope

| Feature | Razón |
|---------|-------|
| Custom trained supervised ML IDS | Requiere tiempo de entrenamiento y datos etiquetados — Elastic ML unsupervised cubre el objetivo de la tesis |
| Cobalt Strike | Licencia comercial; Metasploit + CALDERA cubren los mismos TTPs |
| Entornos productivos reales | Lab únicamente — la tesis documenta el lab, no un despliegue empresarial |
| APT groups más allá de APT29, OilRig, Wizard Spider | Profundidad > amplitud para la tesis |
| Cloud deployment | Sin presupuesto cloud; local only |
| FullAPT-2025 paper en esta tesis | El paper es trabajo futuro; el dataset sí es entregable |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | Phase 1 | Pending |
| INFRA-02 | Phase 1 | Pending |
| INFRA-03 | Phase 2 | Pending |
| INFRA-04 | Phase 2 | Pending |
| INFRA-05 | Phase 2 | Pending |
| INFRA-06 | Phase 2 | Complete |
| INFRA-07 | Phase 3 | Pending |
| RESET-01 | Phase 3 | Pending |
| RESET-02 | Phase 3 | Pending |
| RESET-03 | Phase 3 | Pending |
| TELEM-01 | Phase 3 | Pending |
| TELEM-02 | Phase 3 | Pending |
| TELEM-03 | Phase 3 | Pending |
| TELEM-04 | Phase 3 | Pending |
| RED-01 | Phase 4 | Pending |
| RED-02 | Phase 5 | Pending |
| RED-03 | Phase 5 | Pending |
| RED-04 | Phase 5 | Pending |
| DETECT-01 | Phase 4 | Pending |
| DETECT-02 | Phase 6 | Pending |
| DETECT-03 | Phase 6 | Pending |
| DATA-01 | Phase 6 | Pending |
| DATA-02 | Phase 6 | Pending |
| THESIS-01 | Phase 7 | Pending |
| THESIS-02 | Phase 7 | Pending |
| DOCS-01 | Phase 7 | Pending |
| DOCS-02 | Phase 7 | Pending |

**Coverage:**
- v1 requirements: 27 total
- Mapped to phases: 26
- Unmapped: 0 ✓

---
*Requirements defined: 2026-06-08*
*Last updated: 2026-06-08 after initial definition*
