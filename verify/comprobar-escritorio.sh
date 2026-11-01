#!/usr/bin/env bash
# Comprueba que el fondo de titan-desktop ya no dibuja la tarjeta central ni
# la barra superior con Salir. No necesita compositor.
set -u
export QT_QPA_PLATFORMTHEME=generic

DISTRO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESKTOP="${TITAN_DESKTOP:-${DISTRO}/apps/titan-desktop/build/titan-desktop}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

fallos=0
ok() { printf 'ok: %s\n' "$1"; }
mal() { printf 'FALLO: %s\n' "$1" >&2; fallos=$((fallos + 1)); }

if [[ ! -x "${DESKTOP}" ]]; then
  echo "FALLO: no existe ${DESKTOP} (compila titan-desktop)" >&2
  exit 1
fi

COMPROBAR="$("${DESKTOP}" --comprobar 2>"${TMP}/err")"
[[ $? -eq 0 ]] && ok "titan-desktop --comprobar arranca sin grafico" \
  || mal "fallo --comprobar: $(cat "${TMP}/err")"

for clave in 'barra_superior=no' 'tarjeta_central=no' 'salir=no'; do
  grep -qx "${clave}" <<<"${COMPROBAR}" \
    && ok "--comprobar incluye ${clave}" \
    || mal "falta ${clave} en --comprobar: ${COMPROBAR}"
done

QT_QPA_PLATFORM=offscreen "${DESKTOP}" --captura "${TMP}/fondo.png" \
  >/dev/null 2>&1
[[ -s "${TMP}/fondo.png" ]] && file "${TMP}/fondo.png" \
  | grep -q '1280 x 800' \
  && ok "el fondo se pinta a 1280x800" \
  || mal "no se pudo pintar el fondo"

if [[ ${fallos} -ne 0 ]]; then
  echo "titan-desktop: ${fallos} fallo(s)" >&2
  exit 1
fi
echo "titan-desktop: todo correcto"
