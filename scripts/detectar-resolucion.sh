#!/usr/bin/env bash
#
# detectar-resolucion.sh - resolucion nativa de la pantalla del host.
#
# run-qemu.sh la usa para darle a la tarjeta virtual de QEMU el mismo tamano
# que el monitor. Asi el escritorio no queda con franjas negras y no hay que
# fijar 1920x1080 a mano: en un monitor de 1366x768 se usa 1366x768, y en uno
# de 1920x1080 se usa 1920x1080.
#
# Salida: un unico valor ANCHOxALTO. Si no se puede detectar, 1280x720.
# TITAN_QEMU_RESOLUCION permite forzarla (util para pruebas y para el usuario).
set -u

validar() {
  local valor="$1"
  local ancho alto
  if [[ ! "${valor}" =~ ^([0-9]{3,5})x([0-9]{3,5})$ ]]; then
    return 1
  fi
  ancho="${BASH_REMATCH[1]}"
  alto="${BASH_REMATCH[2]}"
  if (( ancho < 320 || alto < 200 || ancho > 7680 || alto > 4320 )); then
    return 1
  fi
  printf '%sx%s\n' "${ancho}" "${alto}"
}

# Lee el JSON de niri o de wlr-randr. Es tolerante a las dos formas: un
# objeto indexado por nombre de salida (niri) o una lista de salidas.
leer_json() {
  python3 -c '
import json
import sys

try:
    datos = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if isinstance(datos, dict):
    salidas = list(datos.values())
elif isinstance(datos, list):
    salidas = datos
else:
    sys.exit(0)

mejor = None
for salida in salidas:
    if not isinstance(salida, dict):
        continue
    if salida.get("enabled") is False:
        continue
    ancho = 0
    alto = 0
    logico = salida.get("logical")
    if isinstance(logico, dict):
        ancho = int(logico.get("width") or 0)
        alto = int(logico.get("height") or 0)
    if not ancho or not alto:
        modo = salida.get("current_mode")
        if isinstance(modo, dict):
            ancho = int(modo.get("width") or 0)
            alto = int(modo.get("height") or 0)
        elif isinstance(modo, int):
            modos = salida.get("modes") or []
            if 0 <= modo < len(modos) and isinstance(modos[modo], dict):
                ancho = int(modos[modo].get("width") or 0)
                alto = int(modos[modo].get("height") or 0)
    if ancho and alto:
        area = ancho * alto
        if mejor is None or area > mejor[0]:
            mejor = (area, ancho, alto)

if mejor:
    print("%dx%d" % (mejor[1], mejor[2]))
'
}

if [[ -n "${TITAN_QEMU_RESOLUCION:-}" ]]; then
  if validar "${TITAN_QEMU_RESOLUCION}"; then
    exit 0
  fi
  echo "resolucion invalida: ${TITAN_QEMU_RESOLUCION}" >&2
  exit 1
fi

if [[ -n "${NIRI_SOCKET:-}" ]] && command -v niri >/dev/null 2>&1; then
  json="$(niri msg -j outputs 2>/dev/null || true)"
  if [[ -n "${json}" ]]; then
    valor="$(printf '%s' "${json}" | leer_json)"
    if [[ -n "${valor}" ]] && validar "${valor}"; then
      exit 0
    fi
  fi
fi

if command -v wlr-randr >/dev/null 2>&1; then
  json="$(wlr-randr --json 2>/dev/null || true)"
  if [[ -n "${json}" ]]; then
    valor="$(printf '%s' "${json}" | leer_json)"
    if [[ -n "${valor}" ]] && validar "${valor}"; then
      exit 0
    fi
  fi
fi

if command -v xrandr >/dev/null 2>&1; then
  linea="$(xrandr --current 2>/dev/null | head -n 1 || true)"
  if [[ "${linea}" =~ current\ ([0-9]+)\ x\ ([0-9]+) ]]; then
    valor="${BASH_REMATCH[1]}x${BASH_REMATCH[2]}"
    if validar "${valor}"; then
      exit 0
    fi
  fi
fi

# Ultimo recurso: el modo preferido de una salida conectada en DRM. En un
# host sin servidor grafico (o con una sesion que no expone sus salidas) sigue
# sirviendo para no inventar un tamano.
drm="${TITAN_DRM_DIR:-/sys/class/drm}"
mejor_area=0
mejor=""
for tarjeta in "${drm}"/card*-*; do
  [[ -r "${tarjeta}/status" && -r "${tarjeta}/modes" ]] || continue
  [[ "$(cat "${tarjeta}/status" 2>/dev/null)" == "connected" ]] || continue
  modo="$(head -n 1 "${tarjeta}/modes" 2>/dev/null || true)"
  [[ "${modo}" =~ ^([0-9]+)x([0-9]+)$ ]] || continue
  area=$(( BASH_REMATCH[1] * BASH_REMATCH[2] ))
  if (( area > mejor_area )); then
    mejor_area=${area}
    mejor="${modo}"
  fi
done
if [[ -n "${mejor}" ]] && validar "${mejor}"; then
  exit 0
fi

printf '1280x720\n'
