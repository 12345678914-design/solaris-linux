#!/bin/bash
# Comprobador de la decision grafia/texto de 15-titan-grafico.sh.
#
# No arranca labwc: sustituye dbus-run-session por un stub que solo imprime
# ARRANCA_GRAFICO, y simula tty, tarjeta y linea del kernel. Asi se puede
# probar en el host la parte que decide, que es donde se cuelgan las ISO.
#
# Uso: ./verify/comprobar-arranque-grafico.sh [ruta-al-script]

set -u

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${1:-${raiz}/iso/titan/airootfs/etc/profile.d/15-titan-grafico.sh}"

if [[ ! -r "${script}" ]]; then
  echo "FALLO: no se puede leer ${script}" >&2
  exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

mkdir -p "${tmp}/bin"
for programa in labwc titan-desktop; do
  printf '#!/bin/sh\nexit 0\n' >"${tmp}/bin/${programa}"
  chmod +x "${tmp}/bin/${programa}"
done
cat >"${tmp}/bin/dbus-run-session" <<'FIN'
#!/bin/sh
# Stub del test: solo confirma que se llego al arranque grafico.
echo ARRANCA_GRAFICO
FIN
chmod +x "${tmp}/bin/dbus-run-session"

touch "${tmp}/drm"
printf 'quiet\n' >"${tmp}/cmdline"
printf 'quiet titan.texto\n' >"${tmp}/cmdline-texto"

fallos=0

probar() {
  local nombre="$1" tty="$2" drm="$3" cmdline="$4" extra="$5"
  local esperado="$6" drm_dir="${7:-}"
  local salida arranca=0

  salida="$(TITAN_TTY="${tty}" TITAN_DRM="${drm}" \
            TITAN_DRM_DIR="${drm_dir}" \
            TITAN_CMDLINE="${cmdline}" TITAN_EXTRA="${extra}" \
            TITAN_SCRIPT="${script}" PATH="${tmp}/bin:${PATH}" \
    bash --norc -i -c '
      tty() { printf "%s\n" "$TITAN_TTY"; }
      case "${TITAN_EXTRA}" in
        grafico) TITAN_GRAFICO=1 ;;
        tmux) TMUX="prueba" ;;
      esac
      . "$TITAN_SCRIPT"
    ' 2>/dev/null)"

  if printf '%s\n' "${salida}" | grep -q ARRANCA_GRAFICO; then
    arranca=1
  fi

  if [ "${arranca}" -eq "${esperado}" ]; then
    printf 'OK    %-42s %s\n' "${nombre}" "${arranca}"
  else
    printf 'FALLO %-42s %s, esperado %s\n' \
           "${nombre}" "${arranca}" "${esperado}"
    fallos=$((fallos + 1))
  fi
}

probar 'tty1 con tarjeta arranca grafia' \
       '/dev/tty1' "${tmp}/drm" "${tmp}/cmdline" 'no' 1
mkdir -p "${tmp}/dri"
touch "${tmp}/dri/card1"
probar 'detecta card1 si no hay card0' \
       '/dev/tty1' '' "${tmp}/cmdline" 'no' 1 "${tmp}/dri"
probar 'tty2 no arranca grafia' \
       '/dev/tty2' "${tmp}/drm" "${tmp}/cmdline" 'no' 0
probar 'sin tarjeta no arranca' \
       '/dev/tty1' "${tmp}/nada" "${tmp}/cmdline" 'no' 0
probar 'titan.texto fuerza consola' \
       '/dev/tty1' "${tmp}/drm" "${tmp}/cmdline-texto" 'no' 0
probar 'ya dentro de tmux no arranca' \
       '/dev/tty1' "${tmp}/drm" "${tmp}/cmdline" 'tmux' 0
probar 'TITAN_GRAFICO=1 no repite' \
       '/dev/tty1' "${tmp}/drm" "${tmp}/cmdline" 'grafico' 0

echo "---"
if [ "${fallos}" -eq 0 ]; then
  echo 'comprobar-arranque-grafico: 7 comprobaciones, 0 FALLO'
  exit 0
fi
echo "comprobar-arranque-grafico: ${fallos} FALLO"
exit 1
