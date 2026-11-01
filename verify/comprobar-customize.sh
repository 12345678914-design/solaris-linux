#!/bin/bash
# Comprueba customize_airootfs.sh antes de gastar diez minutos en mkarchiso.
#
# El primer build de la ISO 19 murio con codigo 127 porque el bloque del
# escritorio llamaba a run_check antes de definirla. 'bash -n' no lo detecta:
# la sintaxis es correcta y el fallo es de orden. Este test si lo detecta.
#
# Uso: ./verify/comprobar-customize.sh

set -u

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fichero="${1:-${raiz}/iso/titan/airootfs/root/customize_airootfs.sh}"
fallos=0

ok() {
  printf 'OK    %-44s %s\n' "$1" "$2"
}

fallo() {
  printf 'FALLO %-44s %s\n' "$1" "$2"
  fallos=$((fallos + 1))
}

if [[ ! -r "${fichero}" ]]; then
  echo "FALLO: no existe ${fichero}" >&2
  exit 2
fi

if bash -n "${fichero}" 2>/dev/null; then
  ok 'sintaxis de customize' 'bash -n'
else
  fallo 'sintaxis de customize' 'bash -n falla'
fi

definicion="$(grep -n '^run_check()' "${fichero}" | head -n1 | cut -d: -f1)"
if [[ -z "${definicion}" ]]; then
  fallo 'definicion de run_check' 'no encontrada'
else
  anterior="$(grep -nE '^[[:space:]]*run_check[[:space:]]' "${fichero}" \
    | cut -d: -f1 | awk -v d="${definicion}" '$1 < d' | head -n1)"
  if [[ -z "${anterior}" ]]; then
    ok 'run_check definida antes de usarse' "linea ${definicion}"
  else
    fallo 'run_check definida antes de usarse' \
      "se usa en la linea ${anterior}, antes de ${definicion}"
  fi
fi

if grep -q '^/usr/local/bin/titan-desktop --escritorio' "${fichero}"; then
  ok 'autostart del escritorio' 'ruta absoluta'
else
  fallo 'autostart del escritorio' 'no crea la orden esperada'
fi

if grep -q '15-titan-grafico.sh' "${fichero}"; then
  ok 'comprueba el arranque grafico' '15-titan-grafico.sh'
else
  fallo 'comprueba el arranque grafico' 'no lo menciona'
fi

echo '---'
if [[ "${fallos}" -eq 0 ]]; then
  echo 'comprobar-customize: 4 comprobaciones, 0 FALLO'
  exit 0
fi
echo "comprobar-customize: ${fallos} FALLO"
exit 1
