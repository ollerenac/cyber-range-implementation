#!/usr/bin/env bash
# configure-vmbr-lan.sh — crear bridge vmbr_lan en Host 6 como interfaz LAN de OPNsense
#
# Crea (o reutiliza vmbr0) como bridge LAN de OPNsense con IP 10.0.0.254/24.
# Esta IP es el default gateway de todos los hosts del lab vía OPNsense.
#
# NOTA ARQUITECTURAL — conflicto potencial con vmbr0:
#   En Host 6, vmbr0 puede haber sido creado en Phase 1 con bridge-ports eth0.
#   vmbr_lan también necesita bridge-ports eth0. Un NIC puede pertenecer a múltiples
#   bridges en Linux, pero con IPs distintas y en la misma subred crea ambigüedad de
#   routing (el kernel no sabe qué bridge usar para 10.0.0.0/24).
#
#   SOLUCIÓN: Si vmbr0 ya existe con bridge-ports eth0 en Host 6, usa --mode=reuse-vmbr0
#   para reasignar la IP 10.0.0.254/24 a vmbr0 en lugar de crear un nuevo bridge.
#   Si vmbr0 NO tiene bridge-ports eth0 (o no existe), usa --mode=new-bridge (default).
#
#   El operador decide el modo en el Checkpoint Wave 1 tras revisar Host 6.
#
# Uso:
#   bash configure-vmbr-lan.sh [NIC] [--mode=new-bridge|reuse-vmbr0] [--apply]
#
#   NIC                 NIC físico para el bridge LAN (default: eth0)
#   --mode=new-bridge   Crea un nuevo bridge vmbr_lan sobre NIC (default)
#   --mode=reuse-vmbr0  Muestra instrucciones para reasignar IP a vmbr0 existente
#   --apply             Escribe cambios (default: DRY-RUN)
#
# Ejemplos:
#   bash configure-vmbr-lan.sh                          # dry-run, eth0, new-bridge
#   bash configure-vmbr-lan.sh eth0 --mode=new-bridge --apply
#   bash configure-vmbr-lan.sh eth0 --mode=reuse-vmbr0  # siempre dry-run (seguro)
#
# ADR-001: .planning/decisions/adr-firewall-opnsense.md
# Fase:    Phase 1.5 — Perimeter Firewall (Plan 01, Tarea 2)

set -euo pipefail

# ── constantes ────────────────────────────────────────────────────────────────
VMBR_LAN="vmbr_lan"
VMBR_LAN_IP="10.0.0.254"
VMBR_LAN_PREFIX="24"
IFACES_FILE="/etc/network/interfaces"

# ── parseo de argumentos ──────────────────────────────────────────────────────
NIC="eth0"
MODE="new-bridge"
APPLY=false

for arg in "$@"; do
    case "$arg" in
        --apply)         APPLY=true ;;
        --mode=new-bridge)   MODE="new-bridge" ;;
        --mode=reuse-vmbr0)  MODE="reuse-vmbr0" ;;
        --*)             echo "Opción desconocida: $arg" >&2; exit 1 ;;
        *)               NIC="$arg" ;;
    esac
done

# ── funciones de salida ───────────────────────────────────────────────────────
info()  { echo "[INFO]  $*"; }
pass()  { echo "[PASS]  $*"; }
fail()  { echo "[FAIL]  $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# ── bloque de configuración (modo new-bridge) ─────────────────────────────────
vmbr_lan_block() {
    cat <<BLOCK_EOF

# vmbr_lan — LAN bridge de OPNsense (Host 6)
# OPNsense vtnet1 se conecta aquí; ${NIC} lleva el tráfico al switch y al resto de hosts
# IP 10.0.0.254/24 = default gateway de toda la red MGMT del Cyber Range
auto vmbr_lan
iface vmbr_lan inet static
        address ${VMBR_LAN_IP}/${VMBR_LAN_PREFIX}
        bridge-ports ${NIC}
        bridge-stp off
        bridge-fd 0
BLOCK_EOF
}

# ── dry-run ───────────────────────────────────────────────────────────────────
if [[ "$APPLY" == "false" ]]; then
    echo "=== configure-vmbr-lan.sh — DRY-RUN ==="
    echo ""
    echo "  NIC:     ${NIC}"
    echo "  Modo:    ${MODE}"
    echo "  IP LAN:  ${VMBR_LAN_IP}/${VMBR_LAN_PREFIX}  (default gateway del lab)"
    echo ""

    if [[ "$MODE" == "new-bridge" ]]; then
        echo ">>> DRY-RUN — no se modifica nada (pasa --apply para aplicar)"
        echo ""
        echo "Bloque que se añadiría a ${IFACES_FILE}:"
        vmbr_lan_block
        echo ""
        echo "Para aplicar: bash $0 ${NIC} --mode=new-bridge --apply"
    else
        echo ">>> MODO reuse-vmbr0 — siempre dry-run (edición manual requerida)"
        echo ""
        echo "INSTRUCCIONES para reasignar IP a vmbr0 existente:"
        echo ""
        echo "  1. Abrir ${IFACES_FILE} en el editor:"
        echo "       nano ${IFACES_FILE}"
        echo ""
        echo "  2. Localizar el bloque 'iface vmbr0 inet static' y cambiar su"
        echo "     dirección IP a ${VMBR_LAN_IP}/${VMBR_LAN_PREFIX}:"
        echo ""
        echo "       iface vmbr0 inet static"
        echo "               address ${VMBR_LAN_IP}/${VMBR_LAN_PREFIX}    # <-- cambiar aquí"
        echo "               bridge-ports ${NIC}"
        echo "               bridge-stp off"
        echo "               bridge-fd 0"
        echo ""
        echo "  3. Guardar el archivo y recargar (en una sesión screen/tmux para"
        echo "     no perder la conexión SSH):"
        echo "       screen -dmS reload bash -c 'sleep 2; ifreload -a'"
        echo ""
        echo "  ADVERTENCIA: cambiar la IP de vmbr0 corta brevemente la conectividad"
        echo "  de gestión del host. Ejecutar SOLO si tienes acceso físico o una"
        echo "  segunda ruta de administración."
    fi
    echo ""
    exit 0
fi

# ── modo --apply (requiere root) ─────────────────────────────────────────────
if [[ "$(id -u)" -ne 0 ]]; then
    error "Este script debe ejecutarse como root (sudo o SSH root@host6)"
fi

echo "=== configure-vmbr-lan.sh — APPLY (modo: ${MODE}) ==="
echo ""

# Paso 1: verificar que el NIC existe
info "Paso 1: verificar que ${NIC} existe..."
if ! ip link show "${NIC}" &>/dev/null; then
    error "La interfaz '${NIC}' no existe. Verificar con: ip link show"
fi
info "${NIC} existe"

# Paso 2: advertir si vmbr0 ya tiene bridge-ports en el mismo NIC
if grep -q "auto vmbr0" "${IFACES_FILE}" 2>/dev/null; then
    EXISTING_VMBR0_PORTS=$(grep -A8 'auto vmbr0' "${IFACES_FILE}" | grep 'bridge-ports' | grep -v '^#' | awk '{print $2}' || true)
    if [[ "${EXISTING_VMBR0_PORTS}" == "${NIC}" ]]; then
        echo ""
        echo "[ADVERTENCIA] vmbr0 ya tiene bridge-ports ${NIC} en ${IFACES_FILE}."
        echo "              Crear vmbr_lan también sobre ${NIC} causará ambigüedad de routing."
        echo "              OPCIÓN RECOMENDADA: usar --mode=reuse-vmbr0 en lugar de new-bridge."
        echo "              Continúa bajo tu responsabilidad..."
        echo ""
    fi
fi

if [[ "$MODE" == "reuse-vmbr0" ]]; then
    info "Modo reuse-vmbr0 seleccionado — no se aplican cambios automáticos."
    echo ""
    echo "El modo reuse-vmbr0 requiere edición manual de ${IFACES_FILE}."
    echo "Ver instrucciones con: bash $0 ${NIC} --mode=reuse-vmbr0  (sin --apply)"
    exit 0
fi

# Modo new-bridge: añadir bloque vmbr_lan
info "Paso 2: añadir bloque ${VMBR_LAN} a ${IFACES_FILE}..."

if grep -q "${VMBR_LAN}" "${IFACES_FILE}" 2>/dev/null; then
    info "SKIP: ${VMBR_LAN} ya existe en ${IFACES_FILE} — no se duplica"
else
    # Backup antes de modificar
    BACKUP="${IFACES_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp "${IFACES_FILE}" "${BACKUP}"
    info "Backup creado: ${BACKUP}"

    # Añadir el bloque al final
    vmbr_lan_block >> "${IFACES_FILE}"
    info "Bloque ${VMBR_LAN} añadido a ${IFACES_FILE}"
fi

# Paso 3: levantar el bridge
info "Paso 3: ifup ${VMBR_LAN}..."
ifup "${VMBR_LAN}" || {
    if ip link show "${VMBR_LAN}" &>/dev/null; then
        info "${VMBR_LAN} ya estaba activo"
    else
        error "ifup ${VMBR_LAN} falló. Revisar /etc/network/interfaces."
    fi
}

echo ""
echo "=== Verificaciones ==="
echo ""

# Verificación: bridge vmbr_lan existe
if ip link show "${VMBR_LAN}" 2>/dev/null | grep -q 'state UP\|<.*UP.*>'; then
    pass "vmbr_lan bridge activo — $(ip link show ${VMBR_LAN} | head -1)"
else
    fail "vmbr_lan no está UP — verificar con: ip link show ${VMBR_LAN}"
fi

# Verificación: IP 10.0.0.254 en vmbr_lan
if ip addr show "${VMBR_LAN}" 2>/dev/null | grep -q "${VMBR_LAN_IP}"; then
    pass "vmbr_lan IP configurada: ${VMBR_LAN_IP}/${VMBR_LAN_PREFIX}"
else
    fail "vmbr_lan no tiene IP ${VMBR_LAN_IP} — verificar con: ip addr show ${VMBR_LAN}"
fi

# Verificación: bridge show
if command -v bridge &>/dev/null; then
    info "bridge show ${VMBR_LAN}:"
    bridge show "${VMBR_LAN}" 2>/dev/null || true
fi

echo ""
echo "=== Próximos pasos ==="
echo ""
echo "  1. Verificar gateway LAN: ip addr show ${VMBR_LAN} | grep 10.0.0.254"
echo "  2. Verificar conectividad MGMT: ping -c 3 10.0.0.10  (elastic-vm)"
echo "  3. Desplegar VM OPNsense (Wave 2) con:"
echo "     LAN → vmbr_lan (${VMBR_LAN_IP}/${VMBR_LAN_PREFIX})"
echo "     WAN → vmbr_wan (172.16.0.2/30, GW 172.16.0.1)"
