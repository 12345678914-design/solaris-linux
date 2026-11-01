#!/bin/bash
# ---------------------------------------------------------------------------
# Titan Linux -- instalador del live
#
# Se arranca desde la ISO en vivo, en modo de TEXTO (la consola de tty1, el
# puerto serie, o cualquier terminal):
#
#     sudo install.sh
#
# O en modo GRAFICO, con ventana de GTK4 y libadwaita. La levanta cage, que
# viene en el live; si el equipo no tiene dispositivo de grafica, avisa y sigue
# en modo de texto, que instala igual de bien:
#
#     sudo install.sh --grafico
#
# Y se puede pasar un fichero de respuestas para no teclear nada (es lo que
# usan las comprobaciones automaticas, y de paso deja claro que el instalador
# no depende de que haya alguien delante):
#
#     sudo install.sh --autopiloto --respuestas /tmp/respuestas.txt
#
# Que hace, en orden:
#
#   1. comprueba que hay internet, y la pide si no la hay
#   2. pregunta para que va a usar el equipo: de ahi sale la lista de apps
#   3. pregunta el escritorio (GNOME por defecto)
#   4. deja ajustar esa lista de aplicaciones
#   5. pregunta el disco y lo particiona
#   6. pregunta las cuentas
#   7. descarga e instala el sistema, el kernel del proyecto y GRUB
#   8. configura el sistema, la consola con historial y el terminal kitty
#   9. instala las apps de la tienda y desmonta
#
# Las dos pantallas son el MISMO motor: no hay dos instaladores, hay una sola
# logica de instalacion y dos maneras de preguntarle al usuario ('dialog' y
# 'ventana-gui.py', que se reparten en 'ventana()'). La consola de texto sigue
# disponible en todo momento (tty1, tty2 y el puerto serie): el modo grafico
# levanta su propia pantalla encima y no se come la consola.
# ---------------------------------------------------------------------------

set -euo pipefail

AUTO="${TITAN_AUTOPILOTO:-0}"
RESPUESTAS=""
GRAFICO=0
# Los argumentos tal cual han llegado, para poder volver a arrancar este mismo
# programa dentro de cage (que es lo que hace '--grafico') sin perderlos.
ARGUMENTOS=("$@")

while (( $# )); do
  case "$1" in
    --autopiloto) AUTO=1 ;;
    --grafico)    GRAFICO=1 ;;
    --respuestas) RESPUESTAS="${2:-}"; shift ;;
    -h|--help)    sed -n '3,/^# ---/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            echo "Opcion desconocida: $1" >&2; exit 2 ;;
  esac
  shift
done

export AUTO
export TITAN_SILENCIO="${TITAN_SILENCIO:-0}"

# --- la pantalla -------------------------------------------------------------
#
# asegura_asiento
#
# cage necesita un 'asiento' (seat) para poder dibujar en la tarjeta, y en el
# live no hay ninguno. El de logind es el de la sesion de tty1, que es del
# usuario normal, y el instalador va como root, que no tiene sesion propia: con
# las dos cosas a la vez, cage muere con 'No backend was able to open a seat'
# ANTES de dibujar nada, y sin decir por que (fallo 44).
#
# 'seatd' es justo para eso: un gestor de asientos minimo que ya viene en el
# live (es dependencia de cage) y da un asiento a quien lo pida, root incluido.
# Su socket es /run/seatd.sock, o el que diga $SEATD_SOCK, que es la variable
# que mira libseat: el mismo codigo que usa cage, no uno inventado aqui.
#
# Devuelve 0 si hay asiento (ya estaba, o se acaba de abrir) y 1 si no se ha
# podido, que es lo que hace que 'arranca_grafico' siga en modo de texto.
#
# Los diez intentos por 0,2 s son dos segundos: lo que se espera es a que seatd
# llegue a enlazar su socket, no a que arranque el sistema entero.
asegura_asiento() {
  # El mismo socket que mira libseat. Con $SEATD_SOCK puesto se puede ensayar
  # el camino de 'no hay asiento' sin tocar el del equipo.
  local sock="${SEATD_SOCK:-/run/seatd.sock}"
  if [[ -S "${sock}" ]]; then
    return 0
  fi
  if ! command -v seatd >/dev/null 2>&1; then
    echo "No esta 'seatd' en el sistema: cage no puede abrir un asiento," >&2
    echo "y sin asiento no hay pantalla grafica. Se instala en modo" >&2
    echo "de texto, que instala igual de bien." >&2
    return 1
  fi
  if (( EUID != 0 )); then
    echo "Abrir el asiento de la pantalla grafica pide root: arranca el" >&2
    echo "instalador con 'sudo install.sh --grafico'. Se sigue en texto." >&2
    return 1
  fi
  echo "Abriendo un asiento de pantalla para 'cage' (seatd)." >&2
  # Con 'setsid' si lo hay, porque el asiento tiene que sobrevivir al
  # instalador, que es quien lo abre. Sin el, cerrarse la consola se lleva por
  # delante al asiento y cage se queda sin el a mitad de la instalacion.
  if command -v setsid >/dev/null 2>&1; then
    setsid seatd >/dev/null 2>&1 &
  else
    seatd >/dev/null 2>&1 &
  fi
  local intento
  for intento in 1 2 3 4 5 6 7 8 9 10; do
    if [[ -S "${sock}" ]]; then
      return 0
    fi
    sleep 0.2
  done
  echo "El servicio del asiento (seatd) no ha abierto '${sock}'." >&2
  return 1
}

# arranca_grafico
#
# Pone TITAN_GUI=1 si hay una pantalla, y si no la levanta con cage (un
# compositor minimo, que esta en el live precisamente para esto) y vuelve a
# arrancar este mismo programa dentro. Cuatro casos, y el tercero es el que
# importa:
#
#   1. Ya hay sesion grafica (el live con escritorio, o una que haya abierto el
#      usuario): se usa tal cual, sin tocar nada.
#   2. No hay sesion pero hay dispositivo de grafica (/dev/dri) y se puede
#      abrir un asiento: cage levanta una pantalla y el instalador corre
#      dentro de ella.
#   3. No hay sesion y no hay grafica (una VM sin video, un equipo al que le
#      han quitado la tarjeta), o no esta 'cage', o no se puede abrir el
#      asiento: NO se inventa nada. Se avisa en un par de lineas y se sigue en
#      modo de texto, que instala exactamente igual de bien.
#   4. Hay grafica, hay 'cage' y hay asiento, pero cage NO ARRANCA. Antes esto
#      no podia pasar, y era la otra mitad del fallo 44: cage se quedaba con
#      la shell ('exec cage'), de modo que si muria el instalador se iba con el
#      y el usuario se quedaba sin instalador, sin ventana y sin un motivo.
#      Ahora cage es un hijo: si muere, aqui se sigue en modo de texto y se
#      dice por que.
#
# El caso 3 se decide ANTES de lanzar cage, y no por lo que conteste cage: cage
# sin /dev/dri no arranca. Tambien se mira TITAN_DENTRO_GRAFICO, que es lo que
# hace que el hijo no meta otro cage dentro del primero.
arranca_grafico() {
  if [[ "${TITAN_DENTRO_GRAFICO:-0}" == "1" ]]; then
    export TITAN_GUI=1
    return 0
  fi
  if [[ -n "${WAYLAND_DISPLAY:-}" ]] || [[ -n "${DISPLAY:-}" ]]; then
    export TITAN_GUI=1
    return 0
  fi
  shopt -s nullglob
  local dispositivos=(/dev/dri/renderD* /dev/dri/card*)
  shopt -u nullglob
  if (( ! ${#dispositivos[@]} )); then
    echo "No hay dispositivo de grafica en /dev/dri: se instala en modo de" >&2
    echo "texto, que instala igual de bien. Para la pantalla grafica hace" >&2
    echo "falta un equipo con tarjeta (o una VM con video)." >&2
    return 0
  fi
  if ! command -v cage >/dev/null 2>&1; then
    echo "No esta 'cage' en el sistema: se instala en modo de texto." >&2
    return 0
  fi
  if ! asegura_asiento; then
    return 0
  fi
  # cage deja su socket de Wayland en XDG_RUNTIME_DIR. Sin esa variable puesta
  # se cae en un sitio que puede no existir.
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/titan-xdg-$(id -u)}"
  mkdir -p "${XDG_RUNTIME_DIR}"
  chmod 700 "${XDG_RUNTIME_DIR}"
  # Los bloqueos de Wayland de una vuelta anterior estorban: 'wayland' no
  # puede abrir ninguno de los treinta y dos que prueba y cage se cae con
  # 'Unable to open Wayland socket: Invalid argument'. Este directorio es de
  # este mismo euid, asi que lo que se puede es borrar lo que haya en el.
  rm -f "${XDG_RUNTIME_DIR}"/wayland-*.lock 2>/dev/null || true
  echo "Levantando la pantalla con cage, que sale encima de la consola." >&2
  echo "El puerto serie sigue con el instalador en modo de texto." >&2
  # cage NO se queda con la shell (antes si, con 'exec'): si se le lanza y no
  # puede, el instalador tiene que seguir aqui y decirlo, no desaparecer. Las
  # dos variables van como prefijo y no como 'export' para que las examine el
  # hijo de dentro y esta shell se quede limpia si cage muere.
  local codigo=0
  TITAN_DENTRO_GRAFICO=1 TITAN_GUI=1 \
    cage -- "${BASH_SOURCE[0]}" "${ARGUMENTOS[@]}" || codigo=$?
  if (( codigo == 0 )); then
    # El instalador de dentro ha terminado: ya ha instalado. Si aqui se
    # siguiera, se instalaria una segunda vez por el camino de texto.
    exit 0
  fi
  if (( codigo == 3 )); then
    # El 3 NO es de cage: es el codigo de 'cancelado' de 'instalar', y sale de
    # la shell de dentro cuando se pulsa Esc en una pantalla SIN valor por
    # defecto (la contrasena: 'cancelar()' en lib-comun.sh, que ya ha enseado
    # el motivo). cage ha hecho su trabajo y el instalador de dentro ha
    # decidido salirse.
    #
    # Y aqui lo que NO se puede hacer es lo de antes, que era 'return 0':
    # volver al modo de texto con un codigo de 'sigue instalando' significa que
    # el usuario cancela en la pantalla grafica y ve COMENZAR OTRA VEZ una
    # instalacion sin haber pedido nada (fallo 46). Se propaga el 3 y se sale.
    echo "" >&2
    echo "Instalacion cancelada en la pantalla grafica. No se ha tocado" >&2
    echo "el disco." >&2
    exit 3
  fi
  echo "" >&2
  echo "La pantalla grafica no ha podido levantarse: 'cage' ha salido con" >&2
  echo "codigo ${codigo}. Se sigue en modo de texto, que instala igual de" >&2
  echo "bien; el motivo esta en las lineas de arriba." >&2
  return 0
}

[[ "${GRAFICO}" == "1" ]] && arranca_grafico

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# El log arranca antes de cargar los modulos: si uno de ellos tiene un error,
# tambien queda escrito.
LOG="${TITAN_LOG:-/var/log/titan-install.log}"
mkdir -p "$(dirname "${LOG}")" 2>/dev/null || true
: >"${LOG}" 2>/dev/null || LOG="/tmp/titan-install.log"

source "${DIR}/instalador/lib-comun.sh"
source "${DIR}/instalador/lib-escritorios.sh"
source "${DIR}/instalador/lib-apps.sh"
source "${DIR}/instalador/menus.sh"
source "${DIR}/instalador/paso-red.sh"
source "${DIR}/instalador/paso-disco.sh"
source "${DIR}/instalador/paso-base.sh"
source "${DIR}/instalador/paso-chroot.sh"
source "${DIR}/instalador/paso-cerrar.sh"

banner() {
  cat <<EOF

${C_TITULO}  Titan Linux  -  instalador${C_RESET}

  ${C_GRIS}El live va en memoria: no se toca el disco hasta que lo confirmes,
  y se puede salir en cualquier momento con Esc.${C_RESET}
  ${C_GRIS}Log: ${LOG}${C_RESET}

EOF
}

# El recorrido completo. Cada 'paso' dice cuanto ha tardado y lo que falle se
# apunta para el resumen.
instalar() {
  paso_red                || return 1
  menu_tipo_uso
  menu_escritorio
  menu_apps
  paso_disco              || return 1
  menu_cuentas
  menu_arranque
  # Propaga el codigo tal cual: menu_resumen devuelve 3 si el usuario ha
  # cancelado, y con un '|| return 1' el cancelado y un fallo serian lo mismo.
  menu_resumen            || return $?

  paso "descargando e instalando el sistema" paso_base      || return 1
  paso "instalando el kernel"                paso_kernel    || return 1
  paso "reconstruyendo el initramfs"         paso_mkinitcpio || return 1
  paso "instalando GRUB"                     paso_grub      || return 1
  paso "configurando cuentas y sistema"      paso_sistema   || return 1
  paso "activando servicios"                 paso_servicios || return 1
  paso "identidad Titan y terminal"          paso_titan     || return 1
  paso "instalando las apps de la tienda"    paso_flatpak   || return 1
  guardar_estado
  return 0
}

resumen_pasos() {
  local p
  printf '\n%sResultado de los pasos:%s\n' "${C_TITULO}" "${C_RESET}"
  for p in ${PASOS_OK[@]+"${PASOS_OK[@]}"}; do
    printf '  %sOK    %s%s\n' "${C_OK}" "${p}" "${C_RESET}"
  done
  for p in ${PASOS_KO[@]+"${PASOS_KO[@]}"}; do
    printf '  %sFALLO %s%s\n' "${C_MAL}" "${p}" "${C_RESET}"
  done
  printf '\n'
}

main() {
  comprueba_entorno
  banner
  [[ -n "${RESPUESTAS}" ]] && leer_respuestas "${RESPUESTAS}"

  # OJO: con 'if ! instalar' el estado se invierte y $? aqui dentro siempre es
  # 0. Para saber si fue un fallo o un 'cancelado' (3) hay que guardarlo con
  # '||', que ademas evita que el 'set -e' se dispare antes de tiempo.
  local codigo=0
  instalar || codigo=$?
  if (( codigo != 0 )); then
    # 3 no es un fallo: es el boton de cancelar del resumen, o el Esc. El disco
    # esta intacto y no hay nada que arreglar, asi que no se enseña la pantalla
    # de "ha fallado", que seria mentira.
    if [[ "${codigo}" -eq 3 ]]; then
      info "instalacion cancelada. No se ha tocado el disco."
      resumen_pasos
      if [[ "${AUTO}" != "1" ]]; then
        ventana --title "Cancelado" --backtitle "Titan Linux  -  Instalador" --msgbox "
  Se ha salido antes de instalar nada.

  El disco ${E[disco]:-} sigue como estaba. Puedes apagar el equipo.

  ${C_GRIS}Si quieres intentarlo otra vez, arranca el live y repite la
  instalacion.${C_RESET}" 12 66
      fi
      exit 0
    fi
    error "la instalacion se ha parado. Log: ${LOG}"
    resumen_pasos
    # Tambien aqui, y no solo cuando todo va bien. Si la instalacion se para a
    # mitad, el sistema de ficheros de destino se queda montado, y eso no es un
    # detalle: lo que viene despues (otra instalacion desde esta misma sesion, o
    # un 'ls /mnt' para ver lo que ha quedado) se encuentra con un /mnt que no
    # es un directorio vacio sino otro sistema montado encima, y todo lo que se
    # mire ahi es de mas. Pasaba de verdad: al medir lo que habia quedado
    # instalado, los ficheros que se buscaban aparecian como inexistentes
    # porque se estaban buscando DENTRO del sistema ya montado, un nivel mas
    # abajo.
    if ! desmontar; then
      aviso "ha quedado algo montado; se ve con: findmnt -R ${DESTINO}"
    fi
    if [[ "${AUTO}" == "1" ]]; then exit 1; fi
    menu_error "No se ha podido terminar" \
"La instalacion se ha parado antes de acabarse. El log dice por que:

  ${LOG}

El disco puede haber quedado a medias. Vuelve a arrancar el live y repite la
instalacion desde el principio: el disco estara ya vacio." || true
    exit 1
  fi

  resumen_pasos
  # El desmontado va fuera de 'instalar' para poder mirar que se ha quedado
  # montado sin perder el resumen.
  if ! desmontar; then
    aviso "ha quedado algo montado; se ve con: findmnt -R ${DESTINO}"
  fi
  pantalla_final
  preguntar_reiniciar
  info "instalador terminado correctamente"
  exit 0
}

main "$@"
