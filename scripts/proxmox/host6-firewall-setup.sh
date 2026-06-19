#!/usr/bin/env bash
# host6-firewall-setup.sh — configurar Host 6 como gateway perimetral del Cyber Range
#
# Prepara Host 6 para recibir la VM OPNsense como firewall perimetral:
#   - Habilita ip_forward en el kernel (permanente)
#   - Crea vmbr_wan (172.16.0.1/30) como bridge interno WAN virtual para OPNsense
#   - Aplica reglas iptables MASQUERADE persistentes vía post-up/pre-down en
#     /etc/network/interfaces (sin requerir iptables-persistent por separado)
#
# PREREQUISITO OBLIGATORIO:
#   wlan0 DEBE tener una IP asignada (WiFi asociado y DHCP obtenido) antes de
#   ejecutar --apply. Si wlan0 no tiene IP, el script termina con exit 1 antes
#   de modificar nada.
#
# Rango de red:
#   172.16.0.0/30   vmbr_wan subnet (solo 2 hosts útiles)
#   172.16.0.1/30   Host 6 kernel (este host — gateway WAN virtual)
#   172.16.0.2/30   OPNsense VM (WAN interface vtnet0)
#
# Uso:
#   bash host6-firewall-setup.sh            # DRY-RUN (default — no modifica nada)
#   bash host6-firewall-setup.sh --apply    # Aplica cambios (requiere root)
#
# Tras aplicar:
#   ifup vmbr_wan                            # levantar el bridge (ya hecho por el script)
#   iptables -t nat -L POSTROUTING -n        # verificar MASQUERADE activo
#
# ADR-001: scripts/proxmox/../.planning/decisions/adr-firewall-opnsense.md
# Fase:    Phase 1.5 — Perimeter Firewall (Plan 01, Tarea 1)

set -euo pipefail

# ── constantes ────────────────────────────────────────────────────────────────
VMBR_WAN="vmbr_wan"
VMBR_WAN_IP="172.16.0.1"
VMBR_WAN_PREFIX="30"
VMBR_WAN_NET="172.16.0.0/30"
WIFI_IFACE="wlan0"
IFACES_FILE="/etc/network/interfaces"
SYSCTL_CONF="/etc/sysctl.d/99-ipforward.conf"

APPLY=false
for arg in "$@"; do
    if [[ "$arg" == "--apply" ]]; then
        APPLY=true
    fi
done

# ── bloque de configuración que se añadirá a /etc/network/interfaces ─────────
VMBR_WAN_BLOCK=$(cat <<'BLOCK_EOF'

# vmbr_wan — WAN virtual bridge para OPNsense (Host 6)
# Host 6 kernel hace NAT: vmbr_wan → wlan0 → Internet
# Rango: 172.16.0.0/30 — Host 6 = .1, OPNsense WAN = .2
# Reglas iptables MASQUERADE persistentes via post-up/pre-down (sin iptables-persistent)
auto vmbr_wan
iface vmbr_wan inet static
        address 172.16.0.1/30
        bridge-ports none
        bridge-stp off
        bridge-fd 0
        post-up   iptables -t nat -A POSTROUTING -s 172.16.0.0/30 -o wlan0 -j MASQUERADE
        post-up   iptables -A FORWARD -i vmbr_wan -o wlan0 -j ACCEPT
        post-up   iptables -A FORWARD -i wlan0 -o vmbr_wan -m state --state RELATED,ESTABLISHED -j ACCEPT
        pre-down  iptables -t nat -D POSTROUTING -s 172.16.0.0/30 -o wlan0 -j MASQUERADE
        pre-down  iptables -D FORWARD -i vmbr_wan -o wlan0 -j ACCEPT
        pre-down  iptables -D FORWARD -i wlan0 -o vmbr_wan -m state --state RELATED,ESTABLISHED -j ACCEPT
BLOCK_EOF
)

# ── funciones de salida ───────────────────────────────────────────────────────
info()  { echo "[INFO]  $*"; }
pass()  { echo "[PASS]  $*"; }
fail()  { echo "[FAIL]  $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# ── verificar wlan0 con IP ────────────────────────────────────────────────────
check_wlan0_ip() {
    if ! ip link show "${WIFI_IFACE}" &>/dev/null; then
        error "La interfaz ${WIFI_IFACE} no existe en este host. Verificar con: ip link show | grep -E 'wlan|wlp'"
    fi
    if ! ip addr show "${WIFI_IFACE}" | grep -q 'inet '; then
        error "${WIFI_IFACE} no tiene IP asignada — asociar al WiFi antes de continuar.
       Ejemplo con wpa_supplicant:
         wpa_passphrase \"SSID\" \"PASSWORD\" > /etc/wpa_supplicant/wpa_supplicant.conf
         wpa_supplicant -B -i ${WIFI_IFACE} -c /etc/wpa_supplicant/wpa_supplicant.conf
         dhclient ${WIFI_IFACE}"
    fi
    WLAN_IP=$(ip addr show "${WIFI_IFACE}" | grep 'inet ' | awk '{print $2}' | head -1)
    info "wlan0 activo con IP: ${WLAN_IP}"
}

# ── dry-run ───────────────────────────────────────────────────────────────────
if [[ "$APPLY" == "false" ]]; then
    echo "=== host6-firewall-setup.sh — DRY-RUN ==="
    echo ""
    echo "Este script configura Host 6 como gateway perimetral del Cyber Range."
    echo "  WiFi NIC:  ${WIFI_IFACE}"
    echo "  vmbr_wan:  ${VMBR_WAN_IP}/${VMBR_WAN_PREFIX}  (bridge interno, sin NIC físico)"
    echo "  MASQUERADE: ${VMBR_WAN_NET} → ${WIFI_IFACE} → Internet"
    echo ""
    echo ">>> DRY-RUN — no se modifica nada (pasa --apply para aplicar)"
    echo ""
    echo "Verificaciones previas que se ejecutarían:"
    echo "  1. ip addr show ${WIFI_IFACE} | grep 'inet '   (wlan0 debe tener IP)"
    echo ""
    echo "Archivo sysctl que se crearía (${SYSCTL_CONF}):"
    echo "  net.ipv4.ip_forward=1"
    echo ""
    echo "Bloque que se añadiría a ${IFACES_FILE}:"
    echo "${VMBR_WAN_BLOCK}"
    echo ""
    echo "Comandos iptables que se ejecutarían (vía ifup vmbr_wan → post-up):"
    echo "  iptables -t nat -A POSTROUTING -s ${VMBR_WAN_NET} -o ${WIFI_IFACE} -j MASQUERADE"
    echo "  iptables -A FORWARD -i ${VMBR_WAN} -o ${WIFI_IFACE} -j ACCEPT"
    echo "  iptables -A FORWARD -i ${WIFI_IFACE} -o ${VMBR_WAN} -m state --state RELATED,ESTABLISHED -j ACCEPT"
    echo ""
    echo "Para aplicar: bash $0 --apply"
    exit 0
fi

# ── modo --apply (requiere root) ─────────────────────────────────────────────
if [[ "$(id -u)" -ne 0 ]]; then
    error "Este script debe ejecutarse como root (sudo o SSH root@host6)"
fi

echo "=== host6-firewall-setup.sh — APPLY ==="
echo ""

# Paso 1: verificar wlan0 con IP
info "Paso 1: verificar ${WIFI_IFACE} con IP asignada..."
check_wlan0_ip

# Paso 2: habilitar ip_forward permanente
info "Paso 2: habilitar ip_forward permanente en ${SYSCTL_CONF}..."
echo "net.ipv4.ip_forward=1" > "${SYSCTL_CONF}"
sysctl -p "${SYSCTL_CONF}"
info "ip_forward configurado en ${SYSCTL_CONF}"

# Paso 3 + 4: añadir bloque vmbr_wan a /etc/network/interfaces
info "Paso 3: añadir bloque ${VMBR_WAN} a ${IFACES_FILE}..."

if grep -q "${VMBR_WAN}" "${IFACES_FILE}" 2>/dev/null; then
    info "SKIP: ${VMBR_WAN} ya existe en ${IFACES_FILE} — no se duplica"
else
    # Backup antes de modificar
    BACKUP="${IFACES_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp "${IFACES_FILE}" "${BACKUP}"
    info "Backup creado: ${BACKUP}"

    # Añadir el bloque al final
    printf '%s\n' "${VMBR_WAN_BLOCK}" >> "${IFACES_FILE}"
    info "Bloque ${VMBR_WAN} añadido a ${IFACES_FILE}"
fi

# Paso 5: levantar el bridge (aplica post-up rules → iptables MASQUERADE)
info "Paso 4: ifup ${VMBR_WAN} (aplica reglas iptables vía post-up)..."
ifup "${VMBR_WAN}" || {
    # Si el bridge ya está activo, ifup puede retornar error — verificar estado
    if ip link show "${VMBR_WAN}" &>/dev/null; then
        info "${VMBR_WAN} ya estaba activo — aplicando reglas iptables manualmente..."
        iptables -t nat -A POSTROUTING -s "${VMBR_WAN_NET}" -o "${WIFI_IFACE}" -j MASQUERADE 2>/dev/null || true
        iptables -A FORWARD -i "${VMBR_WAN}" -o "${WIFI_IFACE}" -j ACCEPT 2>/dev/null || true
        iptables -A FORWARD -i "${WIFI_IFACE}" -o "${VMBR_WAN}" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    else
        error "ifup ${VMBR_WAN} falló y el bridge no existe. Revisar /etc/network/interfaces."
    fi
}

echo ""
echo "=== Verificaciones ==="
echo ""

# Verificación: bridge vmbr_wan existe y está UP
if ip link show "${VMBR_WAN}" 2>/dev/null | grep -q 'state UP\|<.*UP.*>'; then
    pass "vmbr_wan bridge activo — $(ip link show ${VMBR_WAN} | head -1)"
else
    fail "vmbr_wan no está UP — verificar con: ip link show ${VMBR_WAN}"
fi

# Verificación: IP correcta en vmbr_wan
if ip addr show "${VMBR_WAN}" 2>/dev/null | grep -q "${VMBR_WAN_IP}"; then
    pass "vmbr_wan IP configurada: ${VMBR_WAN_IP}/${VMBR_WAN_PREFIX}"
else
    fail "vmbr_wan no tiene IP ${VMBR_WAN_IP} — verificar con: ip addr show ${VMBR_WAN}"
fi

# Verificación: MASQUERADE activo
if iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -q MASQUERADE; then
    pass "MASQUERADE activo en cadena POSTROUTING"
    iptables -t nat -L POSTROUTING -n | grep MASQUERADE
else
    fail "MASQUERADE NO activo — verificar con: iptables -t nat -L POSTROUTING -n"
fi

# Verificación: ip_forward habilitado
if [[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" == "1" ]]; then
    pass "ip_forward = 1 (activo)"
else
    fail "ip_forward no está habilitado — verificar con: sysctl net.ipv4.ip_forward"
fi

echo ""
echo "=== Próximos pasos ==="
echo ""
echo "  1. Verificar MASQUERADE:  iptables -t nat -L POSTROUTING -n -v | grep MASQUERADE"
echo "  2. Ejecutar configure-vmbr-lan.sh para crear el bridge LAN de OPNsense:"
echo "     bash configure-vmbr-lan.sh eth0 --mode=new-bridge [--apply]"
echo "  3. Desplegar VM OPNsense (Wave 2) con:"
echo "     WAN → vmbr_wan (172.16.0.2/30, GW 172.16.0.1)"
echo "     LAN → vmbr_lan (10.0.0.254/24)"
