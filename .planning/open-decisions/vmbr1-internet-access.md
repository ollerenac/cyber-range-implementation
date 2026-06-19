---
status: open
topic: Internet access for TARGET network (vmbr1)
created: 2026-06-19
---

# Decisión abierta: ¿Dar internet a vmbr1 (TARGET)?

## Contexto

La red TARGET (vmbr1, 10.10.10.0/24) actualmente es air-gapped por diseño.
El operador quiere darle acceso a internet para simular una red enterprise real.

**Confirmado por el operador:** ningún TTP de APT29, OilRig, ni Wizard Spider
realiza conexiones a redes externas ni tiene impacto fuera del lab.

## Hardware de cada host Proxmox

- 1 puerto Ethernet (eth0/eno1) → vmbr0 (MGMT, 10.0.0.0/24)
- 1 tarjeta Wireless → no usada en producción
- Router físico (Opción C ya decidida): WiFi hotspot → router → switch → eth0

## Opciones evaluadas

### Opción 1 — NAT en el host Proxmox
```bash
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -o vmbr0 -j MASQUERADE
```
- VMs TARGET usan la IP del host en vmbr1 (ej. 10.10.10.1) como gateway
- Pros: sin hardware extra, 5 min de config
- Contra: hay que replicar en 6 hosts; frágil si cae iptables

### Opción 2 — VM pfSense/OPNsense como router perimetral ⭐ recomendada
```
Internet → router → switch → vmbr0 → [pfSense VM] → vmbr1 → VMs TARGET
```
- Una VM con dos NICs (vmbr0=WAN, vmbr1=LAN)
- VMs TARGET gateway = IP pfSense en vmbr1 (ej. 10.10.10.254)
- Pros: enterprise-realista, firewall granular, bloquea C2 accidental,
  mejor narrativa de tesis, CALDERA puede enrutar explícitamente
- Contra: una VM más (~1 GB RAM)

### Opción 3 — Inter-VLAN routing en el switch (L3)
- Requiere switch gestionado con capacidad L3
- No requiere VMs ni iptables
- Contra: más complejo, menos control granular

## Preguntas técnicas pendientes del operador

(añadir aquí antes de continuar la conversación)

## Estado

**Sin decidir** — operador tiene más preguntas técnicas antes de elegir.

## Cómo retomar después de /clear

Después de hacer `/clear`, escribe:
> "lee .planning/open-decisions/vmbr1-internet-access.md y sigamos
> la conversación sobre dar internet a la red TARGET"
