# Phase 1: Proxmox Foundation + SIEM Node - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-08
**Phase:** 01-proxmox-foundation-siem-node
**Areas discussed:** Red entre máquinas, Storage de Proxmox, RAM de elastic-vm, TLS de Fleet Server

---

## Red entre máquinas

| Option | Description | Selected |
|--------|-------------|----------|
| VLAN en switch administrado (802.1Q) | vmbr1 (TARGET) de cada Proxmox conectado a VLAN 10 en el switch. Switch administrado ya disponible. | ✓ |
| Router/VM bridge entre hosts | Una VM actuaría como router entre las redes TARGET de cada host. Más complejo, introduce un punto de falla. | |

**User's choice:** VLAN en switch administrado (802.1Q)
**Notes:** El switch administrado ya está disponible — no requiere hardware adicional. La configuración del switch se incluye en el Phase 1 plan.

---

## Storage de Proxmox

**Q1 — Backend de storage:**

| Option | Description | Selected |
|--------|-------------|----------|
| LVM-thin | Default de Proxmox 8.x. Snapshots con qm rollback confiables. ~0 GB RAM overhead. | ✓ |
| ZFS | Snapshots CoW más robustos pero consume 1-2 GB RAM por host. En 16 GB con VMs pesadas es perceptible. | |

**Q2 — Cuántos snapshots por VM:**

| Option | Description | Selected |
|--------|-------------|----------|
| Solo 1: clean_state | Un único snapshot permanente. Simple, predecible, sin acumulación de thin-pool. | ✓ |
| 2: clean_state + pre_run | Permite comparar estado limpio vs comprometido. | |

**Q3 — Espacio en disco por máquina:**

| Option | Description | Selected |
|--------|-------------|----------|
| ~500 GB SSD/HDD | Suficiente para 2-3 VMs pesadas. | ✓ |
| ~1 TB o más | Espacio cómodo. | |
| ~250 GB o menos | Espacio ajustado. | |

**User's choice:** LVM-thin, 1 snapshot (clean_state), ~500 GB por host.
**Notes:** Con 500 GB y LVM-thin, elastic-vm obtiene 200 GB de disco para los índices Elasticsearch.

---

## RAM de elastic-vm

**Q1 — Heap JVM para Elasticsearch:**

| Option | Description | Selected |
|--------|-------------|----------|
| 8 GB heap ES | Xms8g/Xmx8g. Deja 8 GB para OS page cache, Kibana, Fleet Server. | ✓ |
| 6 GB heap ES | Más margen para OS pero puede ser insuficiente para FullAPT-2025. | |
| 4 GB heap ES | Demasiado conservador — riesgo de OOM con ML jobs activos. | |

**Q2 — Ubicación de CALDERA:**

| Option | Description | Selected |
|--------|-------------|----------|
| Misma máquina (elastic-vm) | CALDERA en elastic-vm junto a ES + Kibana + Fleet. Ahorra una máquina. | |
| Máquina separada (caldera-vm) | CALDERA como VM separada. Más aislamiento del plano de control rojo. | ✓ |

**Q3 — Distribución de máquinas físicas:**

| Option | Description | Selected |
|--------|-------------|----------|
| elastic-vm + caldera-vm como VMs en misma máquina física | Una máquina Proxmox corre elastic-vm (12 GB) + caldera-vm (4 GB). Las otras 4-5 máquinas corren Windows targets. | ✓ |
| Máquinas físicas dedicadas (bare metal) | elastic-vm y caldera-vm instalados directo en hardware sin Proxmox. | |

**User's choice:** 8 GB heap ES; CALDERA en caldera-vm (VM separada) en la misma máquina física que elastic-vm; el resto de máquinas hospedan VMs Windows + Kali.
**Notes:** elastic-vm: 12 GB RAM, 200 GB disco. caldera-vm: 4 GB RAM, 40 GB disco. Ambas en el mismo host Proxmox, ninguna en el reset cycle.

---

## TLS de Fleet Server

**Q1 — Gestión del certificado:**

| Option | Description | Selected |
|--------|-------------|----------|
| CA propia del lab | CA raíz generada con elasticsearch-certutil/openssl. Cert firmado por ella. | ✓ |
| Self-signed por Fleet (built-in) | Fleet genera cert automáticamente. Distribución de fingerprint a cada Agent. | |
| Let's Encrypt | Requiere dominio público y acceso a internet. No aplica en lab air-gapped. | |

**Q2 — Distribución del CA cert:**

| Option | Description | Selected |
|--------|-------------|----------|
| Script de setup | El script de provisionamiento de cada VM copia el CA cert desde elastic-vm via SCP antes del enrollment. | ✓ |
| Incluido en imagen base de VM | CA cert inyectado en el template Proxmox base. | |

**Q3 — Contenido del SAN del cert:**

| Option | Description | Selected |
|--------|-------------|----------|
| IP 10.0.0.10 en el SAN | SAN: IP:10.0.0.10. Agents conectan por IP, sin dependencia de DNS. | ✓ |
| Hostname (elastic-vm.lab.local) | Requiere DNS interno en dc01 — agrega complejidad antes de que dc01 exista. | |

**User's choice:** CA propia del lab, distribuida via script de setup, SAN con IP:10.0.0.10.
**Notes:** El CA cert debe generarse durante Phase 1 y estar disponible en elastic-vm para que el script de Phase 3 pueda copiarlo a cada VM al hacer el enrollment.

---

## Claude's Discretion

- Proxmox network bridge configuration syntax (nmcli vs `/etc/network/interfaces` vs WebUI)
- Managed switch VLAN configuration steps (vendor-specific — planner to include generic 802.1Q trunk example)
- ILM policy defaults for `logs-*` indices (30-day hot→delete proposed)

## Deferred Ideas

None — discussion stayed within Phase 1 scope.
