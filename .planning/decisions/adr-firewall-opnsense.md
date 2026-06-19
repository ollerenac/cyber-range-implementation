---
id: ADR-001
status: accepted          # proposed | accepted | superseded | deprecated
date: 2026-06-19
topic: Perimeter firewall — OPNsense VM en Host 6 con wlan0 como WAN
resolves: open-decisions/vmbr1-internet-access.md
---

# ADR-001: OPNsense VM como gateway perimetral del Cyber Range

## Contexto

La red TARGET (vmbr1, 10.10.10.0/24) fue diseñada air-gapped. Esto es
correcto como propiedad de seguridad por defecto, pero impide que las VMs
Windows del lab simulen una red enterprise real (sin Windows Update, sin
resolución DNS externa, sin egress para payloads de prueba controlados).

Se exploró dar NAT directo desde el kernel Proxmox de cada host, pero eso
requiere replicar configuración en los 6 hosts y convierte al hipervisor
en router implícito — frágil y difícil de auditar.

Host 6 tiene rol "firewall" asignado y está vacío. Tiene:
- 1 interfaz Ethernet (eth0) — actualmente conectada al switch del lab
- 1 tarjeta WiFi (wlan0) — sin usar en producción

## Decisión

Desplegar una VM OPNsense en Host 6 como gateway perimetral del lab:

- **WAN**: wlan0 del Host 6 → WiFi → Internet
- **LAN**: eth0 del Host 6 → switch → todos los demás hosts

Dado que Linux no puede bridgear wlan0 directamente a una VM, el Host 6
hace NAT en el kernel (MASQUERADE wlan0 → vmbr_wan) y OPNsense ve un
enlace WAN virtual. Double-NAT es aceptable en un lab.

Snort se despliega como plugin inline de OPNsense sobre la interfaz LAN,
añadiendo detección perimetral de red al stack defensivo de la tesis.

## Topología resultante

```
Internet
    │
[WiFi AP / hotspot / router ISP]
    │
wlan0 ──── Host 6 kernel: ip_forward + MASQUERADE (wlan0 → vmbr_wan)
    │
vmbr_wan (bridge interno, 172.16.0.0/30)
    │
┌───────────────────────────────────┐
│  OPNsense VM  (Host 6, VMID TBD) │
│  WAN: 172.16.0.2  GW: 172.16.0.1 │  ← host 6 hace NAT aquí
│  LAN: 10.0.0.254/24              │
│  [Snort inline en LAN]            │
└───────────────────────────────────┘
    │
eth0 (Host 6) ──── [Switch] ────┬──── eth0 Host 1
                                ├──── eth0 Host 2
                                ├──── eth0 Host 3
                                ├──── eth0 Host 4
                                └──── eth0 Host 5

Dentro de cada Host 1-5:
  eth0 → vmbr0 (10.0.0.0/24, IPs fijas por host)
           ├─ VMs MGMT (caldera-vm, siem-vm, kali-vm)   GW: 10.0.0.254
           └─ vmbr1 (10.10.10.0/24, TARGET)
                └─ VMs Windows                           GW: 10.10.10.1
                        │
                host kernel: ip_forward + MASQUERADE (vmbr1 → vmbr0)
                        │
                OPNsense LAN (10.0.0.254) → Internet
```

## Flujo de tráfico por caso de uso

| Origen | Destino | Ruta |
|--------|---------|-------|
| VM TARGET (Windows) | Internet | vmbr1 → host NAT → vmbr0 → OPNsense → wlan0 |
| VM MGMT (caldera/siem) | Internet | vmbr0 → OPNsense → wlan0 |
| Kali (atacante) | VM TARGET | vmbr0 → host → vmbr1 (L3 routing) |
| Agente CALDERA en TARGET | caldera-vm (10.0.0.20) | vmbr1 → host → vmbr0 (sin salir por OPNsense) |
| OPNsense (Snort) | Lab completo | inspección inline en LAN (eth0) |

## Configuración de OPNsense

```
WAN interface : vtnet0  →  vmbr_wan  →  172.16.0.2/30
LAN interface : vtnet1  →  vmbr_lan  →  10.0.0.254/24
DHCP          : deshabilitado (IPs fijas en cada host)
DNS forwarder : habilitado (resuelve para VMs)
NAT outbound  : automático (LAN → WAN)
Firewall LAN  : permitir todo salvo reglas explícitas de bloqueo
Firewall WAN  : bloquear entrante (stateful)
Snort         : inline en LAN, reglas ET Open
```

## Prerequisitos

1. **[PENDIENTE VERIFICAR]** wlan0 en Host 6 funciona bajo Proxmox
   ```bash
   # Correr en Host 6:
   ip link show | grep -E "wlan|wlp"
   iw dev
   # Si aparece wlan0/wlpXsY, el driver está cargado y es usable
   ```
2. Host 6 tiene capacidad de RAM para una VM adicional (~1 GB OPNsense)
3. El WiFi al que se conecta wlan0 tiene acceso a internet

## Impacto en fases existentes

### Phase 1 (Proxmox + SIEM + CALDERA)
- **network-setup.sh**: añadir configuración de vmbr_wan en Host 6 y reglas
  iptables MASQUERADE wlan0 → vmbr_wan. Los otros 5 hosts no cambian.
- **Runbook Phase 01**: actualizar sección de topología de red; añadir
  paso de despliegue OPNsense VM en Host 6 antes de configurar IPs fijas.
- **docs/index.md**: actualizar diagrama de topología.

### Phase 2 (Windows target network)
- Las VMs Windows no cambian. Solo actualizar su default gateway documentado
  para reflejar que hay un firewall perimetral entre ellas e internet.
- **Runbook Phase 02**: nota explicativa de la ruta de egress completa
  (TARGET → host NAT → vmbr0 → OPNsense → internet).

### Phase 3 (Kali + telemetría full)
- kali-vm en vmbr0 (10.0.0.x): acceso a internet directo vía OPNsense — sin cambios.
- Si Kali necesita atacar VMs TARGET: ruta via vmbr0 → host → vmbr1, sin cambios.
- **Runbook Phase 03**: añadir nota sobre Snort como telemetría de red perimetral
  complementaria a Packetbeat y Sysmon.

### Scripts existentes
| Script | Cambio requerido |
|--------|-----------------|
| scripts/proxmox/network-setup.sh | Nuevo bloque condicional para Host 6: wlan0 join + vmbr_wan + iptables |
| scripts/proxmox/create-kali-vm.sh | Sin cambio |
| scripts/windows/09-elastic-agent.ps1 | Sin cambio |

## Nuevos artefactos requeridos

| Artefacto | Descripción |
|-----------|-------------|
| scripts/proxmox/host6-firewall-setup.sh | Configura wlan0 en Host 6, crea vmbr_wan, aplica iptables MASQUERADE |
| scripts/proxmox/deploy-opnsense-vm.sh | Descarga ISO OPNsense, crea VM con dos NICs, arranca instalación |
| scripts/proxmox/configure-opnsense.sh | (opcional) Aplica config base via OPNsense API post-instalación |

## Valor para la tesis

- **Narrativa**: "red TARGET simula enterprise con firewall perimetral + IDS"
  → más realista que un lab flat
- **Cobertura de detección**: Snort en OPNsense añade detección de red
  perimetral (C2 beaconing, lateral movement cross-segment, DNS tunneling)
  complementando Sysmon (host) + Packetbeat (intra-red) + Elastic Defend (EDR)
- **Control operacional**: bloquear egress accidental de herramientas red team
  (CALDERA, Metasploit) hacia internet real

## Alternativas descartadas

| Opción | Por qué descartada |
|--------|-------------------|
| NAT en kernel de cada host (Opción 1) | Replica config en 6 hosts, sin visibilidad centralizada, frágil |
| pfSense en vez de OPNsense | OPNsense tiene mejor soporte Snort/Suricata como plugins activos; Suricata nativo |
| Switch L3 para inter-VLAN routing (Opción 3) | Depende de hardware gestionado L3 no confirmado; menos control |
| Bridge puro (quitar MGMT network) | Pierde aislamiento TARGET↔MGMT, mezcla planos en broadcast del router ISP |

## Próximos pasos

1. Operador verifica wlan0 en Host 6 (comando en Prerequisitos)
2. Si wlan0 OK → cambiar status a `accepted`
3. Crear `/gsd-plan-phase` para "Phase 1.5 — Perimeter Firewall (OPNsense)"
4. gsd-doc-writer actualiza index.md + runbooks Phase 01/02/03
5. Cerrar open-decisions/vmbr1-internet-access.md

---

## Estado de implementación — 2026-06-19

### Qué se ha ejecutado
- Phase 1.5 Wave 1 completado: `scripts/proxmox/host6-firewall-setup.sh` y
  `scripts/proxmox/configure-vmbr-lan.sh` creados y committeados.
- Checkpoint Wave 1 **en pausa** — los scripts están listos pero el operador
  aún no los ha aplicado en Host 6 (hardware no disponible al momento).
- Wave 2 (deploy OPNsense) y Wave 3 (docs update) bloqueados hasta que
  el operador confirme `wave1-listo`.

### Conflicto de asignación de hosts descubierto

La asignación original tenía **caldera-vm en Host 6**, pero este ADR mueve
**OPNsense a Host 6**. Esto nunca se resolvió explícitamente. El conflicto es:

| Host | Asignación original | Con ADR-001 | Estado |
|------|---------------------|-------------|--------|
| 1 | elastic-vm | elastic-vm | Sin cambio |
| 2 | dc01 + sql01 | dc01 + sql01 | Sin cambio |
| 3 | exchange01 | exchange01 | Sin cambio |
| 4 | ws01 + ws02 | ws01 + ws02 | Sin cambio |
| 5 | opnsense + snort | **libre** (OPNsense se movió a Host 6) | ❓ reasignar |
| 6 | caldera-vm | OPNsense VM (requiere wlan0) | ⚠️ conflicto |

**Propuesta de resolución:** mover caldera-vm + kali-vm a Host 5 (que queda
libre porque OPNsense se movió a Host 6). Host 6 queda dedicado a OPNsense
gateway con acceso exclusivo a wlan0.

| Host | Propuesta revisada | RAM mínima |
|------|-------------------|------------|
| 1 | elastic-vm (Elasticsearch + Kibana + Fleet) | 32 GB |
| 2 | dc01 (AD DC) + sql01 (SQL Server) | 16 GB |
| 3 | exchange01 (Exchange 2019) | 16 GB |
| 4 | ws01 + ws02 (workstations Windows 10) | 16 GB |
| 5 | caldera-vm + kali-vm | 16 GB |
| 6 | OPNsense VM — **requiere wlan0 funcional** | 8 GB |

**Pendiente de confirmar por el operador** antes de instalar Proxmox.

### Pregunta abierta: acceso del operador a caldera-vm

El operador mencionó que caldera-vm necesita ser accesible desde `192.168.0.0/24`
(red WiFi del operador). Con esta topología, caldera-vm estará en vmbr0
(10.0.0.0/24) detrás de OPNsense.

Opciones para acceder a la web UI de CALDERA (puerto 8888) desde el portátil
del operador:

| Opción | Implementación | Complejidad |
|--------|---------------|-------------|
| A — Port forward en OPNsense | Firewall → NAT → Port Forward: 192.168.x.x:8888 → 10.0.0.20:8888 | Baja |
| B — VPN (WireGuard) en OPNsense | Conectar portátil como cliente VPN → acceso directo a 10.0.0.0/24 | Media |
| C — SSH tunnel desde portátil | `ssh -L 8888:10.0.0.20:8888 root@<opnsense-ip>` | Baja (sin config permanente) |

**Recomendación:** Opción A (port forward) para acceso simple durante el lab.
Opción B (WireGuard) si el operador quiere acceso completo a toda la red MGMT
desde su portátil (más cómodo para operar múltiples VMs).

### Prerequisito crítico antes de cualquier instalación

**Verificar compatibilidad WiFi con Linux** en al menos un host físico antes
de instalar Proxmox. Si ningún host tiene wlan0 funcional, este ADR cae
completamente y hay que volver a Opción C (router físico externo).

```bash
# Correr en cualquier host desde live USB Debian/Ubuntu:
lspci | grep -i wireless
ip link show | grep -E "wlan|wlp"
iw dev
# Si aparece la interfaz → Proxmox lo soportará (mismo kernel)
```

Si el WiFi **no funciona** en ningún host: revisar ADR-001 y considerar
volver a la Opción C original (router físico con WiFi → eth0 del lab).
