#!/bin/bash
# ---------------------------------------------------------------------------
# Titan Linux -- libreria comun del instalador
#
# Sin estado de partida: aqui solo hay lo que todos los pasos necesitan
# (log, errores, preguntas, y el sitio donde se guardan las respuestas que
# el usuario va eligiendo).
#
# El instalador tiene DOS pantallas y UN motor. La de texto (dialog, ncurses)
# es la de siempre y funciona en cualquier equipo: sin tarjeta grafica, en una
# VM sin display, desde el puerto serie, y se puede verificar sin pantalla (que
# es como lo comprueban las comprobaciones automaticas). La grafica (GTK4 con
# libadwaita) se pide con 'install.sh --grafico' y solo se usa si hay pantalla;
# si la ventana grafica no se abre, se cae al texto sin perder nada.
#
# El motor es el mismo en los dos casos y no se escribe dos veces: las dos
# pantallas reciben los mismos argumentos y contestan con el mismo contrato.
# La frontera es 'ventana()', mas abajo, que es lo unico que llama a 'dialog' o
# a 'ventana-gui.py'.

# El frontal grafico, al lado de esta libreria. El sitio se saca de
# 'BASH_SOURCE' y no de una ruta fija porque el comprobador carga este fichero
# desde donde sea, y una ruta fija haria que la ventana grafica se buscara en un
# sitio que depende de donde se haya instalado.
GUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
GUI_VENTANA="${GUI_DIR}/ventana-gui.py"
# ---------------------------------------------------------------------------

# Idioma de los mensajes del instalador. Sin esto, dialog (ncurses) saca
# caracteres raros si el que lo lanza no tiene LANG en el entorno.
if [[ -z "${LANG:-}" ]]; then
  LANG="$(sed -n 's/^LANG=//p' /etc/locale.conf 2>/dev/null | head -n1)"
  [[ -n "${LANG}" ]] || LANG=C.UTF-8
  export LANG
fi

# --- registro ---------------------------------------------------------------
# Todo lo que dice el instalador acaba en el log y en la pantalla. El log es
# lo primero que hay que leer si algo falla, y con 'tail -f' se ve el avance
# mientras instala.
LOG="${TITAN_LOG:-/var/log/titan-install.log}"

log() {
  local nivel="$1"; shift
  local linea
  linea="$(date '+%H:%M:%S') [${nivel}] $*"
  if [[ -w "$(dirname "${LOG}")" ]]; then
    printf '%s\n' "${linea}" >>"${LOG}" 2>/dev/null || true
  fi
  if [[ -t 1 && "${TITAN_SILENCIO:-0}" != "1" ]]; then
    case "${nivel}" in
      ERROR) printf '\033[1;31m%s\033[0m\n' "${linea}" >&2 ;;
      AVISO) printf '\033[1;33m%s\033[0m\n' "${linea}" >&2 ;;
      *)     printf '%s\n' "${linea}" ;;
    esac
  fi
}

info() { log INFO "$@"; }
aviso() { log AVISO "$@"; }
error() { log ERROR "$@"; }

# sale() - termina con un codigo y una pantalla de error util.
sale() {
  local codigo="$1"; shift
  local texto="$*"
  error "${texto}"
  if [[ "${AUTO:-0}" != "1" ]] && [[ -t 1 ]] && command -v dialog >/dev/null 2>&1; then
    ventana --title "Titan Linux" --backtitle "Instalador" \
             --msgbox "\n  ${texto}\n\n  El log completo esta en ${LOG}\n" 12 66
  fi
  exit "${codigo}"
}

# cancelar() - se ha pulsado Esc en una pantalla SIN valor por defecto
#
# La mayoria de las pantallas se pueden cancelar y seguir con lo que ya estaba
# puesto (una lista, un texto, unas marcas). Otras no: una contrasena no puede
# tener un valor por defecto, porque un valor inventado es una puerta abierta.
# Ahi lo unico honesto es salir, y decirlo.
#
# El codigo es el 3, que es el de 'cancelado' (lo mira 'main' en install.sh):
# el disco esta intacto y no se ensenya la pantalla de fallo, que seria mentira.
cancelar() { # cancelar PANTALLA MOTIVO
  local pantalla="$1" motivo="$2"
  info "cancelado en la pantalla '${pantalla}': ${motivo}"
  if [[ "${AUTO:-0}" != "1" ]] && [[ -t 1 ]] \
     && command -v dialog >/dev/null 2>&1; then
    ventana --title "Titan Linux" --backtitle "Instalador" --msgbox "
  Se ha salido antes de instalar nada.

  ${motivo}

  El disco sigue como estaba." 12 66
  fi
  exit 3
}

# --- colores del instalador --------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_TITULO=$'\033[1;36m'; C_OK=$'\033[1;32m'
  C_MAL=$'\033[1;31m'; C_AVISO=$'\033[1;33m'; C_GRIS=$'\033[2m'
else
  C_RESET=""; C_TITULO=""; C_OK=""; C_MAL=""; C_AVISO=""; C_GRIS=""
fi

titulo() {
  printf '\n%s%s%s\n' "${C_TITULO}" "$*" "${C_RESET}"
  info "--- $* ---"
}

# --- estado -----------------------------------------------------------------
# E[] es donde se guardan las respuestas ya dadas. Se declara aqui para que
# todos los modulos vean el mismo, y se puede volcar a disco con
# guardar_estado / cargar_estado (util para depurar y para relanzar solo una
# parte con --solo).
declare -gA E=()

guardar_estado() {
  mkdir -p /var/lib/titan 2>/dev/null || true
  { declare -p E; } >/var/lib/titan/instalador-estado.sh 2>/dev/null || true
}

cargar_estado() {
  local f="/var/lib/titan/instalador-estado.sh"
  [[ -r "${f}" ]] || return 1
  # shellcheck disable=SC1090
  source "${f}" || return 1
  return 0
}

# --- autopilot --------------------------------------------------------------
# Con --autopiloto (o TITAN_AUTOPILOTO=1) no se abre ninguna ventana: cada
# pregunta lee su respuesta del fichero de respuestas. Es lo que usan las
# comprobaciones automaticas, y de paso deja claro que el instalador no depende
# de que haya alguien tecleando.
# AUTO lo pueden poner tres sitios: el entorno (TITAN_AUTOPILOTO=1), quien carga
# este fichero (install.sh lo exporta al ver '--autopiloto') y el primer
# argumento, por si el modulo se ejecuta en vez de cargarse con 'source'.
#
# OJO con el valor que ya venga puesto: NO se pisa, y esto es lo que hacia
# falta. install.sh se come sus argumentos con 'shift' ANTES de hacer 'source'
# de este modulo, de modo que aqui $1 ya no es '--autopiloto' sino que no hay
# nada. Con la asignacion de antes, AUTO="${TITAN_AUTOPILOTO:-0}", el autopilot
# se apagaba solo al cargar el modulo: el instalador abria las ventanas de
# dialog y se quedaba esperando a que alguien pulsara 'Aceptar', y una
# comprobacion automatica se quedaba ahi colgada para siempre sin quejarse.
AUTO="${AUTO:-${TITAN_AUTOPILOTO:-0}}"
[[ "${1:-}" == "--autopiloto" ]] && AUTO=1

leer_respuestas() {
  local fichero="$1"
  [[ -r "${fichero}" ]] || sale 2 "No se encuentra el fichero de respuestas: ${fichero}"
  local linea clave valor
  while IFS= read -r linea; do
    linea="${linea%%#*}"
    [[ -z "${linea// /}" ]] && continue
    [[ "${linea}" != *=* ]] && continue
    clave="${linea%%=*}"
    valor="${linea#*=}"
    E["${clave// /}"]="${valor# }"
  done <"${fichero}"
  info "respuestas automaticas cargadas de ${fichero} (${#E[@]} valores)"
}

# --- preguntas --------------------------------------------------------------
# Todas pasan por aqui. En autopilot leen E[clave]; si no hay respuesta usan el
# valor por defecto, y si el usuario cancela (Esc) se queda el defecto. Asi el
# codigo de cada menu se escribe una sola vez.

# ventana ...los mismos argumentos que dialog...
#
# El motor de las ventanas es 'dialog' (ncurses), no 'whiptail'. whiptail
# dejo de existir en Arch: era un script que envolvia a dialog y dialog
# 1.3-20260721 quito ese script del paquete. El codigo del instalador esta
# escrito con las opciones de dialog, y este envoltorio es el unico punto que
# toca el programa de verdad.
#
# Y hay una razon MAS para que exista. dialog NO devuelve 0 siempre: devuelve
# 1 si el usuario contesta que no, y 255 si pulsa Esc. El instalador va con
# 'set -e', asi que una llamada a dialog sin mirar su codigo de salida mataba
# el instalador entero en cuanto el usuario contestaba 'No'. En el resumen,
# pulsar 'Cancelar' acababa con codigo 1 (fallo) en vez de 3 (cancelado), y
# el usuario veia 'la instalacion se ha parado' despues de haber cancelado el
# uno.
#
# Por eso NINGUNA ventana se abre llamando a dialog directamente: se llama a
# 'ventana', que devuelve el codigo de dialog sin dejar que se dispare el
# 'set -e'. Quien quiera mirar el codigo, lo guarda con '|| codigo=$?'.
#
# La respuesta del usuario se recoge con el clasico '3>&1 1>&2 2>&3': dialog
# dibuja en la terminal y escribe lo que el usuario ha elegido en la salida de
# error, y ese juego de descriptores manda la salida de error al sitio donde se
# recoge el valor, dejando la terminal para el dibujo. Comprobado con las dos
# cajas: --inputbox devuelve el texto tecleado tal cual, sin un solo escape.
# Las dos pantallas del instalador, y como se elige una.
#
#   ventana() -> GTK4 con libadwaita (instalador/ventana-gui.py) cuando
#                TITAN_GUI=1 y hay pantalla, y 'dialog' (ncurses) si no.
#                El grafico se pide con 'install.sh --grafico'.
#   ventana() -> 'dialog' cuando TITAN_GUI no esta puesto, que es el modo de
#                texto: lo que se usa desde un terminal, desde una consola sin
#                graficos, y en las comprobaciones automaticas.
#
# Las dos reciben la MISMA lista de argumentos y contestan con el MISMO
# contrato (respuesta por la salida de error, codigo 0 aceptada, 1 cancelada,
# 2 'esta ventana no se ha podido abrir'). Un tercer codigo, el 2, es lo
# unico que esta funcion traduce: cae al modo de texto. Sin el, un frontal
# grafico que no arranca haria que el motor creyera que el usuario ha
# cancelado, y el instalador seguiria entero con todos los valores por defecto
# sin decir ni una palabra (por eso ventana-gui.py no deja que un error al
# pintar se convierta en un cancelado: lo cuenta como fallo y lo dice).
#
# Y al caer al modo de texto, el grafico no puede haber escrito nada en el
# descriptor por el que el motor lee la respuesta. Por eso el diagnostico de
# ventana-gui.py va a la salida estandar (que el motor saca por pantalla) y
# GTK no puede escribir un solo aviso en la salida de error.
ventana() {
  if [[ "${TITAN_GUI:-0}" == "1" ]] && [[ -x "${GUI_VENTANA}" ]]; then
    local rc=0
    "${GUI_VENTANA}" "$@" || rc=$?
    # Cualquier codigo menos de 2 es una respuesta de verdad del usuario (0
    # aceptada, 1 cancelada) y se propaga tal cual. Solo el 2 es un fallo de
    # este frontal, y ahi se abre la ventana de texto.
    if [[ "${rc}" -ne 2 ]]; then
      return "${rc}"
    fi
    aviso "la ventana grafica no se ha podido abrir; se sigue en modo de texto"
  fi
  dialog "$@" || return $?
}

# preguntar_texto CLAVE TITULO TEXTO [POR_DEFECTO]
preguntar_texto() {
  local clave="$1" titulo="$2" texto="$3" defecto="${4:-}"
  if [[ "${AUTO}" == "1" ]]; then
    E["${clave}"]="${E[${clave}]:-${defecto}}"
    info "[autopiloto] ${clave} = ${E[${clave}]}"
    return 0
  fi
  local valor
  valor="$(ventana --title "${titulo}" --backtitle "Titan Linux  -  Instalador" \
                   --inputbox "${texto}" 12 66 "${defecto}" 3>&1 1>&2 2>&3)" || {
    E["${clave}"]="${defecto}"; return 0; }
  E["${clave}"]="${valor}"
  return 0
}

# preguntar_password CLAVE TITULO TEXTO
preguntar_password() {
  local clave="$1" titulo="$2" texto="$3"
  if [[ "${AUTO}" == "1" ]]; then
    E["${clave}"]="${E[${clave}]:-titan}"
    info "[autopiloto] ${clave} = (oculta)"
    return 0
  fi
  local valor
  # Una contrasena NO tiene valor por defecto, asi que cancelar aqui es salir.
  # Sin esto, la clave se quedaba sin poner y el '${E[clave]}' de
  # 'menu_cuentas' mataba el instalador con 'variable sin asignar'. Y lo que
  # NO puede ser es inventar una: una contrasena que se pone sola es una
  # puerta abierta. El codigo 3, con su mensaje, es lo honesto.
  valor="$(ventana --title "${titulo}" --backtitle "Titan Linux  -  Instalador" \
                   --passwordbox "${texto}" 12 66 3>&1 1>&2 2>&3)" || {
    E["${clave}"]=""
    cancelar "${clave}" "Una contrasena no se puede dejar en blanco."
  }
  E["${clave}"]="${valor}"
  return 0
}

# parte_opciones "id:texto|id:texto"
#
# Deja los ids en el array global _opc_ids y los textos en _opc_textos: el
# mismo numero de elementos y en el mismo orden.
#
# El '|' se quita con 'IFS="|" read -r -a' y no con un 'local IFS': puestos
# como 'local', el IFS se queda puesto hasta el final de la funcion y el bucle
# de despues parte cada opcion por los ESPACIOS del texto. Con 25 apps salian
# 254 elementos sueltos y el menu era un churro.
#
# Globales y no 'local -n' (nameref) porque un nameref con el mismo nombre que
# la variable de quien llama avisa de "circular name reference" y deja el array
# como estaba: justo el fallo que se quiere evitar.
#
# OJO: por eso ningun texto de las tablas puede llevar un '|' (es el separador).
# Un texto puede llevar ':' sin problema: el id es lo que hay antes del
# PRIMER ':'.
_opc_ids=()
_opc_textos=()
parte_opciones() {
  local opciones="$1"
  local -a crudos=()
  local item
  _opc_ids=()
  _opc_textos=()
  IFS='|' read -r -a crudos <<<"${opciones}"
  for item in ${crudos[@]+"${crudos[@]}"}; do
    _opc_ids+=("${item%%:*}")
    if [[ "${item}" == *:* ]]; then
      _opc_textos+=("${item#*:}")
    else
      _opc_textos+=("")
    fi
  done
}

# preguntar_lista CLAVE TITULO TEXTO "id:texto|id:texto" [ALTO] [POR_DEFECTO]
preguntar_lista() {
  local clave="$1" titulo="$2" texto="$3" opciones="$4" alto="${5:-18}" defecto="${6:-}"
  if [[ "${AUTO}" == "1" ]]; then
    E["${clave}"]="${E[${clave}]:-${defecto}}"
    info "[autopiloto] ${clave} = ${E[${clave}]}"
    return 0
  fi
  parte_opciones "${opciones}"
  local -a ids=("${_opc_ids[@]}") textos=("${_opc_textos[@]}")
  local -a args=(--title "${titulo}" --backtitle "Titan Linux  -  Instalador")
  # El elemento de arranque va con '--default-item', que es lo que dialog
  # entiende. Antes se ponia un espacio detras de la etiqueta, costumbre de
  # whiptail que en dialog no marca absolutamente nada: la ventana abria siempre
  # en la primera opcion y el valor por defecto solo servia de sobra.
  [[ -n "${defecto}" ]] && args+=(--default-item "${defecto}")
  # OJO con el orden: dialog DEJA de leer opciones en cuanto ve el tipo de
  # ventana. Todo lo que se pone detras de '--menu' no lo lee: lo tira, dice
  # 'Expected a box option' por la salida de error (que aqui va al comando
  # sustitucion, o sea que no se ve) y abre la ventana con los valores de
  # fabrica. Por eso '--menu' va al FINAL de las opciones.
  args+=(--menu "${texto}" "${alto}" 74 "${#ids[@]}")
  local i
  for (( i = 0; i < ${#ids[@]}; i++ )); do
    args+=("${ids[i]}" "${textos[i]}")
  done
  local eleccion
  eleccion="$(ventana "${args[@]}" 3>&1 1>&2 2>&3)" || { E["${clave}"]="${defecto}"; return 0; }
  E["${clave}"]="${eleccion}"
  return 0
}

# preguntar_multiple CLAVE TITULO TEXTO "id:texto|id:texto" "marcados"
#
# dialog marca un elemento si su etiqueta empieza por "ON" y devuelve las
# etiquetas completas, asi que hay que quitar ese "ON" de la respuesta: si no,
# lo guardado seria "ON firefox" y la busqueda del paquete no la encontraria.
preguntar_multiple() {
  local clave="$1" titulo="$2" texto="$3" items="$4" marcados="${5:-}"
  if [[ "${AUTO}" == "1" ]]; then
    E["${clave}"]="${E[${clave}]:-${marcados}}"
    info "[autopiloto] ${clave} = ${E[${clave}]}"
    return 0
  fi
  parte_opciones "${items}"
  local -a ids=("${_opc_ids[@]}") textos=("${_opc_textos[@]}")
  local -a args=(--title "${titulo}" --backtitle "Titan Linux  -  Instalador"
                 --separate-output)
  args+=(--checklist "${texto}" 24 76 "${#ids[@]}")
  # Una opcion de '--checklist' son TRES campos: etiqueta, texto y estado
  # ('on' u 'off'). Antes se usaba la costumbre de whiptail de mandar la
  # etiqueta con un 'ON ' delante y sin estado: whiptail lo toleraba, dialog no.
  # Con dos campos por opcion, dialog dice 'Expected 3 arguments, found extra
  # 1' y NO ABRE LA VENTANA: la pantalla de tipo de uso y la de aplicaciones se
  # quedaban en negro, sin un solo mensaje de error en pantalla (el aviso se
  # va a la salida de error, que el codigo tira).
  local i sel elegido
  for (( i = 0; i < ${#ids[@]}; i++ )); do
    sel="off"
    for elegido in ${marcados}; do
      if [[ "${elegido}" == "${ids[i]}" ]]; then sel="on"; break; fi
    done
    args+=("${ids[i]}" "${textos[i]}" "${sel}")
  done
  local salida
  # Cancelar NO puede devolver sin poner la clave: el instalador va con
  # 'set -u' y el primer '${E[usos]}' de 'menu_tipo_uso' (o el '${E[apps]}' de
  # 'menu_apps') se moria con 'variable sin asignar'. Aqui si hay valor por
  # defecto: lo que la ventana traia marcado, que es justo lo que el usuario
  # estaba viendo. Lo que NO arregla esta linea es el caso de 'quitar todas las
  # marcas y darle a Aceptar', que llega aqui con 'salida' vacia y lo
  # resuelve la comprobacion que hay dos lineas mas abajo en cada menu.
  salida="$(ventana "${args[@]}" 3>&1 1>&2 2>&3)" || {
    E["${clave}"]="${marcados}"
    info "[cancelado] ${clave}: se queda con lo que venia marcado"
    return 0
  }
  E["${clave}"]="${salida//$'\n'/ }"
  E["${clave}"]="${E[${clave}]//ON / }"
  E["${clave}"]="${E[${clave}]//  / }"
  info "${clave} elegido: ${E[${clave}]}"
  return 0
}

# preguntar_si CLAVE TITULO TEXTO [POR_DEFECTO: si|no]
preguntar_si() {
  local clave="$1" titulo="$2" texto="$3" defecto="${4:-no}"
  if [[ "${AUTO}" == "1" ]]; then
    E["${clave}"]="${E[${clave}]:-${defecto}}"
    info "[autopiloto] ${clave} = ${E[${clave}]}"
    return 0
  fi
  # '--defaultno' ANTES de '--yesno', por lo del orden de dialog: puesto
  # detras se pierde en silencio y la ventana sale con 'Si' marcado, que es
  # justo lo contrario de lo que se queria.
  local -a args=(--title "${titulo}" --backtitle "Titan Linux  -  Instalador")
  [[ "${defecto}" == "no" ]] && args+=(--defaultno)
  args+=(--yesno "${texto}" 14 70)
  # Cancelar NO es contestar 'no': es irse sin tocar nada, asi que se queda
  # con lo que la ventana traia marcado (el cuarto argumento). Antes ponia
  # 'no' siempre, y en 'menu_cuentas' la pantalla del bluetooth sale con
  # 'Si' marcado: el usuario ve 'Si', pulsa Esc, y se queda sin bluetooth
  # sin que nadie le haya dicho nada.
  if ventana "${args[@]}"; then
    E["${clave}"]="si"
  else
    E["${clave}"]="${defecto}"
    info "[cancelado] ${clave}: se queda en ${defecto}"
  fi
  return 0
}

menu_informacion() {
  local titulo="$1" texto="$2"
  if [[ "${AUTO}" == "1" ]]; then info "[autopiloto] aviso: ${titulo}"; return 0; fi
  ventana --title "${titulo}" --backtitle "Titan Linux  -  Instalador" --msgbox "${texto}" 24 76
  return 0
}

menu_error() {
  local titulo="$1" texto="$2"
  error "${texto}"
  if [[ "${AUTO}" == "1" ]] || ! command -v dialog >/dev/null 2>&1; then return 1; fi
  ventana --title "${titulo}" --backtitle "Titan Linux  -  Instalador" --msgbox "\n${texto}\n" 18 70
  return 1
}

# --- utilidades -------------------------------------------------------------

# campo_de_linea LINEA N  -> el campo N (1..) de una linea separada por '|'.
#
# Se hace quitando partes a mano y NO con 'read -a' + IFS: un 'local IFS' se
# queda activo hasta el final de la funcion, y como todos los catalogos del
# instalador se recorren con bucles, un IFS de '|' colado hace que despues
# "${lista}" no se parta por espacios y los bucles de dentro no iteren. Asi
# que esta funcion no toca IFS, que es justo lo que se le pide.
campo_de_linea() {
  local linea="$1" n="$2" i
  for (( i = 1; i < n; i++ )); do
    case "${linea}" in
      *'|'*) linea="${linea#*|}" ;;
      *) printf ''; return 0 ;;
    esac
  done
  printf '%s' "${linea%%|*}"
}

# bytes a algo legible: 20 GiB, 512 MiB
tamano_legible() {
  numfmt --to=iec-i --suffix=B --format='%.1f' "$1" 2>/dev/null || echo "$1"
}

exige() {
  local prog="$1" para="${2:-}"
  command -v "${prog}" >/dev/null 2>&1 || \
    sale 1 "Falta '${prog}' en el live${para:+ (${para})}. No se puede seguir."
}

comprueba_entorno() {
  [[ "${EUID}" -eq 0 ]] || sale 1 "El instalador necesita ser root. Usa:  sudo install.sh"
  if [[ ! -d /run/archiso ]]; then
    sale 1 "Esto no parece el live de Titan Linux.
El instalador solo se ejecuta desde la ISO en vivo, nunca desde un sistema ya
instalado: si lo ejecutas en un sistema real, podrias borrar el sistema que
estas usando."
  fi
  info "entorno correcto: live de Titan Linux, root, kernel $(uname -r)"
}

# paso NOMBRE FUNCION... - ejecuta un paso, lo cronometra y lo apunta en el
# resumen final. El progreso se escribe en la consola (no en una ventana de
# dialog) a proposito: en modo autopilot, por serie o al final de un
# arranque sin terminal grafico, una ventana noelia nada.
PASOS_OK=()
PASOS_KO=()
paso() {
  local nombre="$1"; shift
  local t0="${SECONDS}"
  printf '%s==>%s %-46s ' "${C_TITULO}" "${C_RESET}" "${nombre}"
  info "paso: ${nombre}"
  if "$@"; then
    printf '%sOK%s (%s s)\n' "${C_OK}" "${C_RESET}" "$((SECONDS - t0))"
    PASOS_OK+=("${nombre}")
    return 0
  fi
  printf '%sFALLO%s\n' "${C_MAL}" "${C_RESET}"
  PASOS_KO+=("${nombre}")
  error "el paso '${nombre}' ha fallado"
  return 1
}
