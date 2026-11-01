#!/bin/bash
# Comprobador del banner de la consola.
#
# El fallo real: /etc/profile carga 10-titan.sh y despues ~/.bashrc lo vuelve
# a cargar en la MISMA shell. El guard TITAN_SHELL_VISIBLE no lo evita porque
# las dos cargas son la misma shell visible, asi que la bienvenida sale dos
# veces seguidas. Este test simula las dos cargas y cuenta banners.
#
# Uso:  ./verify/comprobar-banner.sh [ruta-a-10-titan.sh]
#
# El test FALLA con el codigo de antes del arreglo (2 banners en ttyS0) y
# pasa con el arreglo (1). No comprueba que el fichero exista: comprueba el
# comportamiento.

set -u

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
perfil="${1:-${raiz}/iso/titan/airootfs/etc/profile.d/10-titan.sh}"

if [[ ! -r "${perfil}" ]]; then
  echo "FALLO: no se puede leer ${perfil}" >&2
  exit 2
fi

fallos=0

comprobar() {
  local nombre="$1" tty="$2" con_tmux="$3" esperado="$4"
  local salida veces

  salida="$(TITAN_TTY="${tty}" TITAN_TMUX="${con_tmux}" \
            TITAN_PERFIL="${perfil}" \
    bash --norc -i -c '
      tty() { printf "%s\n" "$TITAN_TTY"; }
      if [ "$TITAN_TMUX" = "si" ]; then
        TMUX="prueba"
      else
        unset TMUX
      fi
      . "$TITAN_PERFIL"
      . "$TITAN_PERFIL"
    ' 2>/dev/null)"

  veces="$(printf '%s\n' "${salida}" | grep -c 'L I N U X')"

  if [ "${veces}" -eq "${esperado}" ]; then
    printf 'OK    %-40s %s banner(es)\n' "${nombre}" "${veces}"
  else
    printf 'FALLO %-40s %s banner(es), esperado %s\n' \
           "${nombre}" "${veces}" "${esperado}"
    fallos=$((fallos + 1))
  fi
}

# La consola de serie: el perfil se carga dos veces (profile + .bashrc) en la
# misma shell. Tiene que quedar una sola bienvenida.
comprobar 'ttyS0, perfil y .bashrc (2 cargas)' '/dev/ttyS0' 'no' 1

# tty1 con tmux: la shell de fuera se sustituye y no imprime; la de dentro si.
comprobar 'tty1 fuera de tmux (no imprime)'    '/dev/tty1' 'no' 0
comprobar 'tty1 dentro de tmux (imprime 1)'    '/dev/tty1' 'si' 1

# Y una shell normal de tty2: una sola bienvenida aunque se recargue.
comprobar 'tty2, perfil y .bashrc (2 cargas)'  '/dev/tty2' 'no' 1

echo "---"
if [ "${fallos}" -eq 0 ]; then
  echo 'comprobar-banner: 4 comprobaciones, 0 FALLO'
  exit 0
fi
echo "comprobar-banner: ${fallos} FALLO"
exit 1
