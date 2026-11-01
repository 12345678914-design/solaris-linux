#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Titan Linux -- lo que se comprueba de la pantalla GRAFICA, dentro del live
#
# Este script lo ejecuta el driver DENTRO del live (titan-instala.py, fase 2),
# y todo lo que mira son cosas que no se pueden mirar desde fuera: si el perfil
# ha instalado la pila de GTK, si el permiso de ejecucion del frontal ha
# llegado a la ISO, y si el frontal pinta de verdad con los PAQUETES DE LA ISO
# (que no son los del equipo donde se escriben las comprobaciones).
#
# Cada comprobacion imprime una linea
#
#     GRAFICO/<nombre>=<OK|MAL> <detalle>
#
# y son once: el frontal, los cinco paquetes, la pila de python, la pantalla
# rota, la pantalla pintada, '--grafico' y sus tres decisiones, el reparto de
# 'ventana()', lo que ha quedado sin limpiar dentro de '/root/instalador',
# y las dos del asiento, que son las que miran la pantalla de verdad.
#
# y el driver las lee por el prefijo. Las que son informacion y no fallo (de
# momento, lo que hay en /dev/dri) salen igual pero con su propio nombre, que el
# driver no cuenta. Al final se imprime
# 'GRAFICO/RESUMEN=<ok|mal> <n>/<n>'. Nunca se sale con codigo distinto de
# cero: que esto falle es informacion del informe, no motivo para que la
# instalacion entera se pare.
#
# Todo lo que escribe va a un directorio de trabajo propio y todo lo que puede
# quedarse colgado lleva un 'timeout', porque esto corre dentro de una prueba
# que no esta mirando.
# ---------------------------------------------------------------------------

set -uo pipefail

BASE="/var/tmp/comprobar-gui-en-vivo"
INSTALADOR="/root/instalador"
FRONTAL="${INSTALADOR}/ventana-gui.py"
INSTALL="/root/install.sh"
COMUN="${INSTALADOR}/lib-comun.sh"

ok=0
total=0

# Una linea, sin saltos, y como mucho de largo. Los detalles se cortan porque
# van al log del driver, que es de la consola serie, y ahi una linea larga se
# envuelve y parte el log hecho un lio.
detalle() { printf '%s' "$1" | tr '\n' ' ' | cut -c1-"$2"; }

# Igual, pero por el FINAL. Lo que escribe cage (y GTK) va con el tiempo al
# principio de su log, asi que el motivo de que algo falle casi siempre son las
# ultimas lineas, y con 'detalle' de las primeras solo se leia el encabezado.
detalle_final() { printf '%s' "$1" | tail -2 | tr '\n' ' ' | cut -c1-"$2"; }

anota() { # anota NOMBRE RESULTADO [DETALLE...]
  total=$((total + 1))
  [[ "$2" == OK ]] && ok=$((ok + 1))
  printf 'GRAFICO/%s=%s' "$1" "$2"
  shift 2
  (( $# )) && printf ' %s' "$*"
  printf '\n'
  return 0
}

# Lo mismo, pero esto no es una comprobacion: es un hecho del equipo, que se
# escribe para que el resto del informe se pueda leer (si no hay /dev/dri, el
# camino que se ha probado es el de caida a texto, y eso hay que poder leer).
dato() { # dato NOMBRE VALOR
  printf 'GRAFICO/%s=%s\n' "$1" "$2"
}

rm -rf "${BASE}"
mkdir -p "${BASE}"
chmod 700 "${BASE}"

# Todo lo que el guion escriba en la salida de error (que es donde se quejan el
# shell y los programas) se guarda aparte, para poder mirarlo al final. El
# 'exec 2>' no cambia el descriptor de los programas que ya estan corriendo, y
# lo que se necesita es justo eso: que lo que dicen las comprobaciones salga
# por la salida normal y lo que dice el shell acabe en un fichero.
exec 3>&2 2>"${BASE}/errores.txt"

# --- 1. el frontal esta y se puede ejecutar ----------------------------------
# El permiso lo declara profiledef.sh. Si no viaja, el fichero llega como 0644
# y 'ventana()' lo salta con su '-x': el instalador grafico no existiria, en
# silencio, y en un equipo con tarjeta el usuario veria un instalador de texto
# sin ninguna pista de por que. Por eso se mira el '-x' y no solo que el
# fichero este (medido: con el permiso a 0644, preguntar solo por el fichero
# daba bien y la ISO iba a caer a texto sin avisar).
if [[ -f "${FRONTAL}" && -x "${FRONTAL}" ]]; then
  anota frontal OK "$(stat -c '%a %U' "${FRONTAL}")"
elif [[ -f "${FRONTAL}" ]]; then
  anota frontal MAL "esta pero no se puede ejecutar" \
    "($(stat -c '%a' "${FRONTAL}"))"
else
  anota frontal MAL "no esta en el live"
fi

# --- 2. la pila entera esta en la ISO ---------------------------------------
# Los cinco van en el perfil, pero un paquete que se cae de una lista se cae en
# silencio, y entonces el frontal no abre y no dice nada.
faltan=""
for paquete in gtk4 libadwaita adwaita-icon-theme python-gobject cage; do
  pacman -Qq "${paquete}" >/dev/null 2>&1 || faltan="${faltan} ${paquete}"
done
if [[ -z "${faltan}" ]]; then
  anota paquetes OK "los cinco"
else
  anota paquetes MAL "faltan:${faltan}"
fi

# --- 3. python puede con GTK4 y con libadwaita ------------------------------
# Esto es lo que mas se puede estropear sin que se note: una version que no
# coincide con la que quiere el frontal da un ImportError al arrancar, y el
# frontal no cae al texto (que es lo que haria 'ventana()' con el codigo 2)
# sino que no llega a existir.
# La salida se pide entera porque GTK escribe avisos por su cuenta (si no
# encuentra pantalla, avisa, y sigue). Lo que se mira son las DOS lineas con
# nombre propio, y el resto se tira: si se aceptara lo que salta de fondo, un
# 'import gi' que falla con un aviso de autorizacion pasaria por bueno.
sal="$(timeout 60 python3 -c '
import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw
print("PILA-GTK", Gtk.get_major_version(), Gtk.get_minor_version())
print("PILA-ADW", Adw.get_major_version(), Adw.get_minor_version())
' 2>&1)"
codigo=$?
versiones="$(printf '%s' "${sal}" | grep -c '^PILA-')"
versiones="${versiones:-0}"
if [[ ${codigo} -eq 0 && "${versiones}" == 2 ]]; then
  anota pila OK "$(printf '%s' "${sal}" | grep '^PILA-' | tr '\n' ' ')"
else
  anota pila MAL "rc=${codigo}, ${versiones} de 2, $(detalle_final "${sal}" 60)"
fi

# --- 4. con la pantalla rota, contesta 2 y calla ----------------------------
# El 2 es lo unico que 'ventana()' traduce en caida al modo de texto. Y la
# salida de error es la ranura por la que el motor lee lo que el usuario ha
# elegido: un aviso de GTK ahi se pegaria delante de la respuesta y el motor
# instalaria el aviso en vez de lo que el usuario eligio.
timeout 60 env -u DISPLAY -u WAYLAND_DISPLAY \
  python3 "${FRONTAL}" --title Prueba --msgbox Linea 24 76 \
  >"${BASE}/pantalla.txt" 2>"${BASE}/error.txt" </dev/null
codigo=$?
bytes="$(tr -d ' ' <"${BASE}/error.txt" | wc -c)"
if [[ ${codigo} -eq 2 && "${bytes}" == 0 ]] &&
   grep -q 'ventana-gui:' "${BASE}/pantalla.txt"; then
  anota pantalla-rota OK "rc=2, ${bytes} bytes de error, diagnostico a la vista"
else
  visto="$(detalle "$(cat "${BASE}/pantalla.txt")" 50)"
  anota pantalla-rota MAL \
    "rc=${codigo}, ${bytes} bytes de error, pantalla: ${visto}"
fi

# --- 5. y con pantalla de verdad, pinta y contesta la etiqueta ---------------
# cage con 'WLR_BACKENDS=headless' levanta una pantalla sin monitor y sin
# tarjeta (va por pixman), que es lo unico que se puede hacer en una maquina sin
# video. La respuesta tiene que ser la ETIQUETA de la fila marcada (la del
# '--default-item'), no lo que se lee en la fila.
#
# cage escribe su log por la salida de error de SU PROPIO proceso, y el frontal
# contesta por la salida de error del suyo: los dos son el mismo descriptor. Si
# se captura todo de una vez, el log se cuela delante de la respuesta (medido:
# eran veinte lineas de EGL y luego el 'gnome' al final, y la comprobacion
# fallaba con la respuesta llena de log). En el instalador de verdad no se
# mezclan, porque cage escribe al arrancar y 'ventana()' captura despues, pero
# aqui estan los dos en la misma captura, asi que la captura la hace un
# envoltorio DENTRO de cage y deja el resultado en un fichero.
mkdir -p "${BASE}/xdg"
chmod 700 "${BASE}/xdg"
cat >"${BASE}/pinta.sh" <<'FINO'
#!/bin/bash
# Unico parametro: el frontal. Segundo: donde dejar el resultado.
resp="$("$1" --title Prueba --menu "Elige una" 18 74 2 gnome GNOME sway Sway \
  3>&1 1>/dev/null 2>/dev/null 2>&3)"
rc=$?
printf 'rc=%s resp=[%s]\n' "${rc}" "${resp}" >"$2"
FINO
chmod 755 "${BASE}/pinta.sh"
timeout 180 env XDG_RUNTIME_DIR="${BASE}/xdg" \
  WLR_BACKENDS=headless GDK_BACKEND=wayland TITAN_GUI_PRUEBA=aceptar \
  cage -- "${BASE}/pinta.sh" "${FRONTAL}" "${BASE}/respuesta.txt" \
  >"${BASE}/pantalla-cage.txt" 2>"${BASE}/error-cage.txt" </dev/null
codigo=$?
leido="$(cat "${BASE}/respuesta.txt" 2>/dev/null || true)"
rc_ventana="$(printf '%s' "${leido}" | sed -n 's/^rc=\([0-9]*\).*/\1/p')"
resp_ventana="$(printf '%s' "${leido}" | sed -n 's/.*resp=\[\(.*\)\]$/\1/p')"
rc_ventana="${rc_ventana:-vacio}"
resp_ventana="${resp_ventana:-vacia}"
if [[ ${codigo} -eq 0 && "${rc_ventana}" == 0 ]] &&
   [[ "${resp_ventana}" == gnome ]]; then
  anota pantalla-pintada OK "cage rc=0, la ventana respondio '${resp_ventana}'"
else
  anota pantalla-pintada MAL \
    "cage rc=${codigo}, ventana rc=${rc_ventana}, respuesta='${resp_ventana}'" \
    "error: $(detalle_final "$(cat "${BASE}/error-cage.txt")" 60)"
fi

# --- 6. '--grafico' esta y decide antes de levantar nada --------------------
# Ademas de la ayuda, lo que importa es que la funcion este DENTRO del live: se
# saca del propio fichero que se acaba de instalar, no del repositorio, porque
# lo que se comprueba es lo que viaja.
if timeout 30 "${INSTALL}" --help 2>/dev/null | grep -q -- '--grafico'; then
  anota ayuda OK "install.sh --help ofrece --grafico"
else
  anota ayuda MAL "install.sh --help no ofrece --grafico"
fi

# A 'arranca_grafico' se le quita 'cage' del PATH para poder mirar el camino de
# texto sin que la prueba levante un compositor de verdad: por el camino de
# pantalla, la funcion se queda con la shell ('exec cage') y no hay quien
# conteste nada.
mkdir -p "${BASE}/poco"
for herramienta in bash id mkdir chmod; do
  donde="$(command -v "${herramienta}" 2>/dev/null)" &&
    ln -sf "${donde}" "${BASE}/poco/${herramienta}"
done
# El 2>/dev/null es para que un 'sed' que no encuentre el fichero no escriba su
# error en la consola serie, que es por donde vuelve el informe.
# Las DOS funciones, y en orden: 'arranca_grafico' llama a 'asegura_asiento',
# y sacar solo la primera daria un fichero que no puede funcionar.
sed -n '/^asegura_asiento() {/,/^}/p' "${INSTALL}" \
  >"${BASE}/arranca.sh" 2>/dev/null
sed -n '/^arranca_grafico() {/,/^}/p' "${INSTALL}" \
  >>"${BASE}/arranca.sh" 2>/dev/null
sal="$(timeout 60 env -u DISPLAY -u WAYLAND_DISPLAY \
  -u TITAN_DENTRO_GRAFICO -u TITAN_GUI PATH="${BASE}/poco" \
  bash -c 'source "$1"; arranca_grafico; echo "GUI=${TITAN_GUI:-0}"' \
  _ "${BASE}/arranca.sh" 2>&1)"
codigo=$?
if [[ ${codigo} -eq 0 && "${sal}" == *"GUI=0"* ]] &&
   { [[ "${sal}" == *"No hay dispositivo de grafica"* ]] ||
     [[ "${sal}" == *"No esta 'cage'"* ]]; }; then
  anota arranca-grafico OK "$(detalle "$(printf '%s' "${sal}" | head -1)" 60)"
else
  anota arranca-grafico MAL "rc=${codigo} $(detalle_final "${sal}" 80)"
fi

# --- 7. 'ventana()' es la unica que abre ventanas ---------------------------
# Sin esto, un 'dialog' nuevo escrito en cualquier sitio pasaria todo lo de
# arriba y dejaria el instalador a medias: una ventana grafica y todas las
# demas de texto.
#
# No vale contar las menciones a 'dialog' del fichero entero: en el de verdad
# hay veintiseis, y veinticinco son comentarios y el 'command -v' que mira si
# esta el programa. Lo que se mira es la cuenta dentro del CUERPO de
# 'ventana()' (que tiene que ser una, la de reserva) y la de fuera (que tiene
# que ser ninguna). El '2>/dev/null' y el '${x:-0}' son por lo mismo de antes:
# 'grep -c' sobre un fichero que no esta no imprime un 0, no imprime nada.
cuerpo="$(awk '/^ventana\(\) \{/{d=1} d{print} d&&/^\}/{exit}' "${COMUN}")"
reservas="$(printf '%s\n' "${cuerpo}" |
  grep -cE '(^|[^_[:alnum:]-])dialog +"\$@"')"
reservas="${reservas:-0}"
fuera="$(awk '/^ventana\(\) \{/{d=1; next} d&&/^\}/{d=0; next} !d{print}' \
  "${COMUN}" 2>/dev/null |
  grep -nE '(^|[^_[:alnum:]-])dialog' 2>/dev/null |
  grep -vE 'command -v dialog' | grep -vE '^[0-9]+: *#')"
if [[ -z "${cuerpo}" ]]; then
  anota ventana MAL "no se ha encontrado ventana() en lib-comun.sh"
elif [[ "${reservas}" == 1 && -z "${fuera}" ]]; then
  anota ventana OK "una llamada a dialog dentro, ninguna fuera"
else
  anota ventana MAL "dentro ${reservas}, fuera: ${fuera:-ninguna}"
fi

# --- 8. la carpeta del instalador no lleva restos de las pruebas --------------
# Esta comprueba la COPIA de la ISO, que es lo unico que puede decir si el arbol
# de trabajo ha metido algo dentro de la imagen. Se sabe que se cuela: al
# importar el frontal para probarlo, Python deja el '.pyc' al lado del '.py', y
# el '.py' que se importa es el del ARBOL DE LA ISO, asi que el '__pycache__' se
# queda dentro del squashfs (medido: un '__pycache__' de root con un '.pyc'
# dentro de '/root/instalador', y el recorrido contando ficheros decia que
# habia once librerias en vez de nueve).
esperados="lib-apps.sh lib-comun.sh lib-escritorios.sh menus.sh paso-base.sh"
esperados="${esperados} paso-cerrar.sh paso-chroot.sh paso-disco.sh"
esperados="${esperados} paso-red.sh ventana-gui.py"
sobras="$(ls -A "${INSTALADOR}" 2>/dev/null | sort |
  grep -vxF "${esperados// /$'\n'}" || true)"
restos="$(find "${INSTALADOR}" \( -name '__pycache__' -o -name '*.pyc' \) \
  2>/dev/null | head -3 | tr '\n' ' ')"
if [[ ! -d "${INSTALADOR}" ]]; then
  # Sin la carpeta, el 'ls -A' no falla (con '|| true' todavia menos) y sale
  # vacio, que es justo lo que un 'ls' de un sitio que no existe parece: que no
  # hay nada. Medido: sin esta rama, con el arbol de pruebas en '/var/tmp' en
  # vez de en '/root', el check daba bien sin haber mirado una sola vez.
  anota sin-restos MAL "no esta ${INSTALADOR} en la imagen"
elif [[ -n "${restos}" ]]; then
  anota sin-restos MAL "la imagen lleva: $(detalle "${restos}" 80)"
elif [[ -n "${sobras}" ]]; then
  anota sin-restos MAL "sobra: $(detalle "${sobras}" 80)"
else
  anota sin-restos OK "las nueve librerias, el frontal y nada mas"
fi

# --- 9. cage de verdad, con la tarjeta de verdad -----------------------------
# Esta seccion es la que caza el fallo 44, y antes no existia. Lo que se
# comprobaba era 'pantalla-pintada', y esa va con 'WLR_BACKENDS=headless':
# headless no pide asiento a nadie, de modo que el camino de verdad (el que usa
# 'install.sh --grafico' en el live, con la tarjeta de la maquina) no se miraba
# en absoluto. Con solo lo de antes, un live donde 'cage' no puede abrir un
# asiento daba en verde entero, y el usuario se encontraba con un 'cage' que
# se moria con 'No backend was able to open a seat' y ademas se llevaba por
# delante al instalador entero, porque 'arranca_grafico' lo lanzaba con 'exec'.
#
# Las dos comprobaciones van en orden, y la segunda se apoya en la primera: la
# segunda necesita el asiento que la primera abre. Por eso antes se mata
# cualquier 'seatd' que hubiera y se borra su socket. Si no, la primera se
# encontraria el asiento ya puesto del intento anterior y daria bien SIN abrir
# nada, que es justo como se comprueba de verdad que lo abre.
pkill -x seatd 2>/dev/null || true
rm -f /run/seatd.sock 2>/dev/null || true

sed -n '/^asegura_asiento() {/,/^}/p' "${INSTALL}" \
  >"${BASE}/asegura.sh" 2>/dev/null
if [[ ! -s "${BASE}/asegura.sh" ]]; then
  # Sin la funcion no hay nada que mirar, y esto NO es cosa del equipo: es que
  # el instalador de la ISO no la trae. Se dice en rojo y con el motivo. La
  # comprobacion de 'cage' de mas abajo se hace IGUAL, porque es la que de
  # verdad enseña lo que se encuentra el usuario cuando '--grafico' no levanta
  # ninguna pantalla.
  anota asiento-abierto MAL "install.sh no trae asegura_asiento()" \
    "asi que '--grafico' no abre ningun asiento y cage no dibuja"
elif [[ ! -d /dev/dri ]]; then
  anota asiento-abierto MAL "este equipo no tiene /dev/dri, y sin tarjeta" \
    "cage no dibuja: el camino de pantalla no se puede probar aqui"
else
  salida_asiento="$(timeout 60 env -u SEATD_SOCK bash -c \
    'source "$1"; asegura_asiento; echo "ASIENTO=$?"' \
    _ "${BASE}/asegura.sh" 2>&1)"
  if grep -q 'ASIENTO=0' <<<"${salida_asiento}" &&
     [[ -S /run/seatd.sock ]]; then
    anota asiento-abierto OK "asegura_asiento() rc=0 y /run/seatd.sock existe" \
      "$(detalle "$(printf '%s' "${salida_asiento}" | head -1)" 60)"
  else
    anota asiento-abierto MAL "asegura_asiento() no ha abierto el asiento" \
      "$(detalle_final "${salida_asiento}" 80)"
  fi
fi

# Y ahora lo que de verdad importa, y que NO depende de que haya asiento ni de
# que 'asegura_asiento' este en el fichero: 'cage' con la tarjeta de verdad, que
# es justo lo que '--grafico' intenta levantar en el live. Asi, con el producto
# roto, esta comprobacion sigue siendo la de verdad y enseña el error que se
# encuentra el usuario, en vez de quedarse sin hacer nada.
#
# El 'WLR_BACKENDS=drm' es OBLIGATORIO y va a proposito: sin el, cage puede
# caerse al headless, que no pide asiento a nadie, y darian bien los dos casos,
# el bueno y el malo. Con el, o hay asiento o cage se cae.
if [[ ! -d /dev/dri ]]; then
  anota cage-dibuja MAL "este equipo no tiene /dev/dri"
else
  mkdir -p "${BASE}/xdg-drm"
  chmod 700 "${BASE}/xdg-drm"
  timeout 90 env -u DISPLAY -u WAYLAND_DISPLAY \
    XDG_RUNTIME_DIR="${BASE}/xdg-drm" WLR_BACKENDS=drm GDK_BACKEND=wayland \
    cage -- /bin/true >"${BASE}/cage-drm.out" 2>"${BASE}/cage-drm.err" \
    </dev/null
  codigo=$?
  if [[ ${codigo} -eq 0 ]]; then
    anota cage-dibuja OK "cage rc=0 con la tarjeta de verdad y el" \
      "asiento abierto"
  else
    # El motivo se busca por la palabra 'seat' y no por el final del log, que
    # es donde esta el error de verdad: 'wayland' y 'wlroots' solo dicen que
    # no pudieron arrancar, y lo unico que explica POR QUE es la linea del
    # asiento, que es justo lo que se leia en la pantalla del usuario.
    motivo="$(grep -i 'seat' "${BASE}/cage-drm.err" | tail -1)"
    [[ -n "${motivo}" ]] || \
      motivo="$(tail -2 "${BASE}/cage-drm.err" | tr '\n' ' ')"
    anota cage-dibuja MAL "cage rc=${codigo} con WLR_BACKENDS=drm" \
      "error: $(detalle "${motivo}" 90)"
  fi
fi

# Un hecho, no una comprobacion: que version de 'seatd' es la que abre el
# asiento, y si venia ya en la ISO o hay que instalarla.
dato seatd-info "en el live: $(seatd -v 2>&1 | head -1) | socket: $({
  [[ -S /run/seatd.sock ]] && echo abierto || echo cerrado
})"

# Lo que hay en ESTA maquina, que no es lo mismo que en una con tarjeta. Sin
# /dev/dri, el camino de '--grafico' que se prueba es el de caida a texto, y eso
# hay que poder leer sin adivinarlo.
if [[ -d /dev/dri ]]; then
  dato dri-info "hay: $(ls /dev/dri | tr '\n' ' ')"
else
  dato dri-info "no hay /dev/dri: el instalador grafico cae a texto"
fi

# --- resumen ----------------------------------------------------------------
# Si el shell ha dicho algo (un 'bad substitution', un 'no such file or
# directory'), se anade al resumen: este guion no sale nunca con codigo distinto
# de cero, asi que un error suyo se come una linea y se pierde en silencio, que
# es como se ha colado el 'bad substitution' de la comprobacion 'sin-restos'.
avisos="$(grep -icE 'bad substitution|syntax error|command not found' \
  "${BASE}/errores.txt" 2>/dev/null || true)"
if [[ "${avisos:-0}" != 0 ]]; then
  printf 'GRAFICO/errores-del-guion=MAL %s avisos del shell\n' "${avisos}"
else
  printf 'GRAFICO/errores-del-guion=OK ni uno\n'
fi

if [[ ${ok} -eq ${total} ]]; then
  printf 'GRAFICO/RESUMEN=ok %s/%s\n' "${ok}" "${total}"
else
  printf 'GRAFICO/RESUMEN=mal %s/%s\n' "${ok}" "${total}"
fi
rm -rf "${BASE}"
exit 0
