#!/usr/bin/env bash
# Comprueba la app Acerca: datos del equipo, boton Aceptar y captura.
set -u
export QT_QPA_PLATFORMTHEME=generic

DISTRO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACERCA="${TITAN_ACERCA:-${DISTRO}/apps/titan-acerca/build/titan-acerca}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

fallos=0
ok() { printf 'ok: %s\n' "$1"; }
mal() { printf 'FALLO: %s\n' "$1" >&2; fallos=$((fallos + 1)); }

if [[ ! -x "${ACERCA}" ]]; then
  echo "FALLO: no existe ${ACERCA} (compila titan-acerca)" >&2
  exit 1
fi

COMPROBAR="$("${ACERCA}" --comprobar 2>"${TMP}/err")"
[[ $? -eq 0 ]] && ok "titan-acerca --comprobar arranca sin grafico" \
  || mal "fallo --comprobar: $(cat "${TMP}/err")"

for clave in equipo ram procesador disco arquitectura; do
  grep -q "^${clave}=." <<<"${COMPROBAR}" \
    && ok "--comprobar incluye ${clave}" \
    || mal "falta ${clave} en --comprobar: ${COMPROBAR}"
done
for clave in 'boton=Aceptar' 'icono=computadora'; do
  grep -qx "${clave}" <<<"${COMPROBAR}" \
    && ok "--comprobar incluye ${clave}" \
    || mal "falta ${clave} en --comprobar: ${COMPROBAR}"
done

QT_QPA_PLATFORM=offscreen "${ACERCA}" --captura "${TMP}/acerca.png" \
  >/dev/null 2>&1
[[ -s "${TMP}/acerca.png" ]] && file "${TMP}/acerca.png" \
  | grep -q '560 x 520' \
  && ok "la ventana Acerca se pinta a 560x520" \
  || mal "no se pudo pintar la ventana Acerca"

PANEL="${TITAN_PANEL:-${DISTRO}/apps/titan-panel/build/titan-panel}"
APPS="${DISTRO}/iso/titan/airootfs/usr/share/applications"
if [[ -x "${PANEL}" ]]; then
  CATALOGO="$("${PANEL}" --listar-apps "${APPS}" 2>"${TMP}/apps.err")"
  grep -q '|Acerca|computer|titan-acerca|0|titan-acerca$' \
    <<<"${CATALOGO}" \
    && ok "Acerca aparece en el catalogo del boton Inicio" \
    || mal "Acerca no aparece en el catalogo: ${CATALOGO}"
else
  mal "no existe ${PANEL} para comprobar el catalogo"
fi

if [[ ${fallos} -ne 0 ]]; then
  echo "titan-acerca: ${fallos} fallo(s)" >&2
  exit 1
fi
echo "titan-acerca: todo correcto"
