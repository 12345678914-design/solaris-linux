#!/usr/bin/env bash
#
# build-iso.sh - construye la ISO en vivo de Titan Linux 0.1 con archiso.
#
# Que hace, en orden:
#   1. comprueba que el host tiene lo necesario (Arch, archiso, xorriso, disco)
#   2. compila el CLI 'titan' (apps/titan-cli) y lo mete en el perfil
#   3. deposita linux-titanlinux en el repositorio local 'titan' del perfil
#   4. genera los ficheros de build (variables del hook, pacman.conf resuelto)
#   5. lanza mkarchiso y comprueba el resultado
#
# Uso:
#   ./scripts/build-iso.sh                 # build normal
#   ./scripts/build-iso.sh --no-kernel     # fuerza una ISO solo con kernel de Arch
#
# OJO: el directorio de trabajo se borra SIEMPRE, no hace falta pedir nada.
# mkarchiso marca cada paso con un fichero testigo ("base._make_packages",
# "iso._build_iso_image"...) dentro de work/ y se salta los que ya estan
# marcados. Si work/ sobrevive de un build anterior, el segundo build no
# rehace NADA, sale con codigo 0 en veinte segundos y te vuelve a cantar el
# sha256 de la ISO de antes como si fuera nueva. Medido, y es justo el modo de
# fallo que mas dano hace: uno cree que ha probado un cambio y no ha probado
# nada. Asi que work/ se limpia siempre y la ISO de salida se borra antes de
# empezar, para que un build que no arrive a hacer nada falle en vez de
# colarse.
#
# Variables de entorno:
#   TITAN_VERSION   version de la ISO            (0.1.0)
#   TITAN_CODENAME  apodo de la release          (TITÁN)
#   TITAN_OUT       directorio de salida         (<distro>/out)
#   TITAN_WORK      directorio de trabajo        (<proyecto>/build/archiso)
#   TITAN_SKIP_APP  1 = no recompilar el CLI titan

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISTRO="$(cd "${HERE}/.." && pwd)"
PROJECT="$(cd "${DISTRO}/.." && pwd)"
PROFILE="${DISTRO}/iso/titan"
APP="${DISTRO}/apps/titan-cli"

TITAN_VERSION="${TITAN_VERSION:-0.1.0}"
TITAN_CODENAME="${TITAN_CODENAME:-TITÁN}"
TITAN_BUILD_DATE="${TITAN_BUILD_DATE:-$(date -u +%Y-%m-%d)}"
OUT_DIR="${TITAN_OUT:-${DISTRO}/out}"
WORK_DIR="${TITAN_WORK:-${PROJECT}/build/archiso}"
REPO_DIR="${DISTRO}/repo"

use_kernel=1
verbose=""

red()  { printf '\033[1;31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[1;32m%s\033[0m\n' "$*"; }
yel()  { printf '\033[1;33m%s\033[0m\n' "$*"; }
info() { printf '\033[0;36m==>\033[0m %s\n' "$*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-kernel) use_kernel=0; shift ;;
    -v|--verbose) verbose="--verbose"; shift ;;
    -h|--help)  sed -n '3,25p' "$0"; exit 0 ;;
    *) red "Opcion desconocida: $1"; exit 1 ;;
  esac
done

# --------------------------------------------------------------- 1. preflight --

[[ -r /etc/os-release ]] || { red "Falta /etc/os-release"; exit 1; }
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "arch" || "${ID:-}" == "cachyos" || "${ID_LIKE:-}" == *"arch"* ]] || { red "Se necesita Arch Linux o una derivada como CachyOS (ID=${ID:-?})"; exit 1; }

for cmd in mkarchiso xorriso pacstrap; do
  command -v "$cmd" >/dev/null || { red "Falta '$cmd'. Instala: pacman -S archiso devtools"; exit 1; }
done
[[ -f "${PROFILE}/profiledef.sh" ]] || { red "Perfil no encontrado: ${PROFILE}"; exit 1; }

avail_mb="$(df --output=avail -B1M / | tail -n1 | tr -dc '0-9')"
[[ -n "$avail_mb" ]] || { red "No se pudo leer el espacio libre de /"; exit 1; }
avail_gb=$((avail_mb / 1024))
if (( avail_gb < 8 )); then
  red "Solo ${avail_gb} GB libres en /. El build necesita 8 GB o mas."
  yel "Libera espacio o borra el arbol de compilacion del kernel:"
  yel "  rm -rf ${PROJECT}/build/kernel-titanlinux"
  exit 1
fi
info "host listo: ${PRETTY_NAME}, ${avail_gb} GB libres en /"

# ------------------------------------------------- 1b. el historial de la consola
# El config de tmux se comprueba AQUI, en el host, y no dentro del airootfs, y
# el motivo es que dentro del airootfs no hay donde arrancar un tmux de prueba:
# su /dev esta vacio (mkarchiso lo monta mientras instala paquetes y lo suelta
# despues), y un servidor de tmux sin /dev/pts no arranca. Cuando se intentaba
# desde ahi, el build se paraba con
#
#   ERROR: /etc/tmux.conf no engancha el historial: sin servidor
#
# que era mentira: el config estaba bien y lo que no habia era terminal. Y
# montar /dev dentro del chroot no es opcion: mount() da EPERM ahi con las
# mismas capacidades, y un '--rbind' de /dev entra en el grupo de propagacion
# del /dev del HOST, con lo que el 'umount -R' de limpieza se lleva el /dev de
# la maquina que construye. Comprobado de verdad, no es hipotesis.
#
# En el host si hay terminal, y el build se para en dos segundos en vez de
# después de diez minutos de descargas.
verificar_tmux() {
  local conf="${PROFILE}/airootfs/etc/tmux.conf"
  local problema="" socket="titancheck-$$"
  [[ -r "${conf}" ]] || { red "No se encuentra ${conf}"; return 1; }
  # tmux hace falta en el HOST para esto. Si no esta, no se puede comprobar la
  # tabla de teclas, y avisar es mejor que fingir que se ha comprobado. (En una
  # maquina de build sin tmux lo dira el customize_airootfs.sh con 'tmux -V'.)
  if ! command -v tmux >/dev/null; then
    yel "AVISO: el host no tiene tmux, asi que los enlaces del config no se comprueban."
    return 0
  fi
  # 1) Los nombres de tecla que tmux ignora en silencio. 'PageUp' y
  #    'S-PageUp' no dan error: no se registra el enlace y la tecla queda muerta.
  #    tmux llama a RePag 'PPage' y a AvPag 'NPage' (ver 'tmux list-keys').
  if grep -qE '^[[:space:]]*bind[^#]*(S-)?Page(Up|Down)' "${conf}"; then
    problema="usa nombres de tecla de pagina que tmux ignora en silencio"
    grep -nE '^[[:space:]]*bind[^#]*(S-)?Page(Up|Down)' "${conf}" >&2
  fi
  # 2) La tabla de teclas DE VERDAD: se arranca un servidor y se lee con
  #    'list-keys'. Importa hacerlo asi y no con grep sobre el fichero, porque un
  #    config invalido no lo dice: 'start-server' y 'new-session -d' devuelven 0
  #    y ni un aviso (medido con tmux 3.7). Lo que se mira no es que arranque, es
  #    que los enlaces ESTEN.
  #
  #    'start-server ; list-keys' y no 'new-session -d' a proposito: crear una
  #    sesion abre un panel, y el panel necesita una terminal (/dev/ptmx). Sin
  #    ella, tmux responde 'create window failed: fork failed: Permission
  #    denied' y parece que el problema es el config, cuando el config esta
  #    bien. 'start-server' no abre nada: carga el config y responde, y con eso
  #    la tabla de teclas se lee igual.
  if [[ -z "${problema}" ]]; then
    tabla() { tmux -f "${conf}" -L "${socket}" start-server ';' \
                list-keys -T "$1" 2>/dev/null; }
    if ! tabla root >/dev/null; then
      problema="no se ha podido arrancar el tmux de prueba"
    else
      # RePag tiene que entrar en el historial desde el modo normal. Este enlace
      # NO es de serie (con un config vacio, la tabla root no tiene ninguno para
      # PPage), asi que su ausencia si que se ve.
      tabla root | grep -qE 'bind-key +(-n )?-T root PPage +copy-mode -u' \
        || problema="falta 'bind -n PPage copy-mode -u' (RePag no entra al historial)"
      # Y dentro del historial tiene que subir UNA PANTALLA, no una linea: por
      # eso 'page-up' y no 'scroll-up', que mueve una linea, y menos todavia con
      # un numero detras, que tmux se ignora en silencio.
      #
      # Ojo: 'PPage -> page-up' en copy-mode es ademas el enlace POR DEFECTO de
      # tmux (medido con 'tmux -f /dev/null'), asi que este grep solo no
      # distingue "lo puso el config" de "lo puso tmux". Da igual para el
      # usuario (la tecla funciona igual), pero por eso la comprobacion 1, la
      # del texto, no es redundante: es la que pilla un 'PageUp' mal escrito,
      # que tmux ignora en silencio y deja el enlace por defecto en su sitio.
      tabla copy-mode | grep -qE 'bind-key +-T copy-mode PPage +send-keys -X page-up' \
        || problema="falta 'bind -T copy-mode PPage send-keys -X page-up' (RePag no sube pantalla)"
      # Este si que es nuestro de verdad: el defecto de tmux para NPage es
      # 'page-down', y lo que se quiere es volver de golpe a la cola de la
      # salida, que es lo unico que mantiene la ultima linea a la vista.
      tabla copy-mode | grep -qE 'bind-key +-T copy-mode NPage +send-keys -X history-bottom' \
        || problema="falta 'bind -T copy-mode NPage send-keys -X history-bottom' (AvPag no vuelve a la cola)"
    fi
    tmux -L "${socket}" kill-server 2>/dev/null || true
  fi
  if [[ -n "${problema}" ]]; then
    red "ERROR: /etc/tmux.conf no engancha el historial: ${problema}"
    yel "       Medido en el live: Shift+RePag no llega a la tty, asi que el"
    yel "       historial tiene que ir con RePag a secas (tecla 'PPage')."
    return 1
  fi
  grn "    /etc/tmux.conf engancha el historial (tabla de teclas leida de verdad)"
  return 0
}
verificar_tmux || exit 1

# El work dir se borra siempre: ver la nota de la cabecera sobre los testigos de
# mkarchiso. Antes hay que desmontar lo que el build anterior dejo dentro del
# airootfs: mkarchiso monta /proc, /sys, /run, /dev, /tmp y /srv ahi cuando no
# puede hacer unshare (y avisa con "not a mountpoint"). Con esos montajes puestos,
# 'rm -rf' del arbol falla con "Permission denied" aunque el directorio este
# vacio, y el build entero se queda sin herramienta.
info "limpiando ${WORK_DIR}"
for stale in "${WORK_DIR}"/*/airootfs "${WORK_DIR}/archiso"/*/airootfs; do
  [[ -d "${stale}" ]] || continue
  umount -R "${stale}" 2>/dev/null || true
done

# Y antes de borrar NADA, se comprueba que no queda ningun montaje dentro. Por
# dos motivos, y el segundo es el que duele:
#
#   1. Un 'umount -R' puede fallar a medias (un submontaje de /sys que es del
#      host, por ejemplo) y dejar montajes colgando. Entonces 'rm -rf' falla con
#      "Permission denied" y el build se para: molesto pero inofensivo.
#
#   2. Si lo que queda montado dentro del airootfs es un ENLACE de /dev (y lo
#      es: mkarchiso monta /dev ahi con '--rbind'), 'rm -rf' del arbol no borra
#      el arbol: borra el CONTENIDO de /dev a traves del enlace. O sea, borra el
#      /dev de la maquina que esta construyendo. Sin mas, sin aviso y sin
#      codigo de error.
#
#      Esto no es una hipotesis de manual: al pasar, la maquina se quedo con
#      un /dev con dos ficheros, y sin /dev/null no arrancaba ni un build ni un
#      QEMU ni un 'sudo'. Recuperarlo son 249 mknod.
#
# Por eso: si queda ALGO montado dentro del work dir, no se borra nada y se
# dice cual es, para que lo desmonte quien puede (root).
quedan=""
# Primero los montajes MAS PROFUNDOS: si se supiera que queda algo dentro, hay
# que soltarlo de dentro hacia fuera, porque 'umount' de un padre con un hijo
# montado encima falla y deja al hijo colgado.
montajes_dentro() {
  findmnt -rn -o TARGET 2>/dev/null | grep "^${WORK_DIR}/" || true
}
ordenados() {
  awk '{ print length, $0 }' | sort -rn | awk '{ print $2 }'
}
while read -r m; do
  [[ -n "${m}" ]] || continue
  quedan+="  ${m}"$'\n'
done < <(montajes_dentro)
if [[ -n "${quedan}" ]]; then
  red "Quedan montajes dentro de ${WORK_DIR}; no se borra nada:"
  printf '%s' "${quedan}"
  yel "Se desmontan a mano, como root, de dentro hacia fuera:"
  while read -r m; do
    [[ -n "${m}" ]] && yel "  sudo umount -R ${m}"
  done < <(montajes_dentro | ordenados)
  exit 1
fi

if ! rm -rf -- "${WORK_DIR}"; then
  # Caso real y corriente: mkarchiso deja la raiz del airootfs en modo 555
  # (dr-xr-xr-x), y con eso no se puede ni quitar lo que hay dentro, aunque el
  # directorio sea tuyo. Se le devuelve el permiso de escritura y se reintenta
  # una vez, que es lo que arregla el caso de siempre.
  chmod -R u+w -- "${WORK_DIR}" 2>/dev/null || true
fi
if ! rm -rf -- "${WORK_DIR}"; then
  # aqui ya se sabe que NO hay montajes dentro (lo ha mirado el guard de antes),
  # asi que lo que queda son permisos. Y el culpable casi siempre es el mismo:
  # el customize_airootfs.sh corre como root DENTRO del airootfs, asi que deja
  # ficheros de root ahi (por ejemplo /tmp/tmux-0, con el bit pegajoso del /tmp
  # de la imagen encima, que impide quitarlo aunque el directorio padre sea
  # tuyo). Quitar eso sin ser root no se puede, y no tiene por que: el arreglo
  # es de un segundo, se dice cual es.
  red "No se pudo limpiar ${WORK_DIR} y no es por montajes: son permisos."
  yel "Es lo normal si el build anterior se paro en customize_airootfs.sh, que"
  yel "corre como root dentro del airootfs y deja cosas de root. Se quita en un"
  yel "segundo:"
  yel "  sudo rm -rf ${WORK_DIR}"
  exit 1
fi
# Y la ISO de antes tambien se borra: si el build no llega a terminar, el
# 'find' de abajo no debe poder dar con una ISO vieja y llamarla nueva.
rm -f -- "${OUT_DIR}"/*.iso "${OUT_DIR}"/*.iso.sha256
mkdir -p -- "${OUT_DIR}" "${WORK_DIR}" "${REPO_DIR}"

# ------------------------------------------------------------- 2. app 'titan' --

install -d -m 0755 "${PROFILE}/airootfs/usr/local/bin"
if [[ "${TITAN_SKIP_APP:-0}" == "1" ]]; then
  yel "TITAN_SKIP_APP=1: no se recompila el CLI titan"
else
  info "compilando el CLI titan (apps/titan-cli)"
  ( cd "${APP}" && cargo build --release --quiet )
fi
if [[ -x "${APP}/target/release/titan" ]]; then
  install -m 0755 "${APP}/target/release/titan" "${PROFILE}/airootfs/usr/local/bin/titan"
  info "titan $("${PROFILE}/airootfs/usr/local/bin/titan" --version | head -n1) en el perfil"
else
  red "No existe ${APP}/target/release/titan"
  exit 1
fi

# ---------------------------------------- 2b. escritorio Qt 'titan-desktop' --

DESKTOP="${DISTRO}/apps/titan-desktop"
if [[ "${TITAN_SKIP_DESKTOP:-0}" == "1" ]]; then
  yel "TITAN_SKIP_DESKTOP=1: no se recompila el escritorio"
else
  command -v qmake6 >/dev/null 2>&1 || {
    red "Falta qmake6 para compilar el escritorio (paquete qt6-base)."
    exit 1
  }
  info "compilando el escritorio titan-desktop (Qt 6)"
  if ! ( cd "${DESKTOP}" && mkdir -p build && cd build \
         && qmake6 .. && make -j"$(nproc)" ) \
       >"${WORK_DIR}/titan-desktop-build.log" 2>&1; then
    red "Fallo al compilar titan-desktop; ultimas lineas del log:"
    tail -n 30 "${WORK_DIR}/titan-desktop-build.log" >&2
    exit 1
  fi
fi
if [[ ! -x "${DESKTOP}/build/titan-desktop" ]]; then
  red "No existe ${DESKTOP}/build/titan-desktop"
  exit 1
fi
install -m 0755 "${DESKTOP}/build/titan-desktop" \
        "${PROFILE}/airootfs/usr/local/bin/titan-desktop"
install -d -m 0755 "${PROFILE}/airootfs/etc/titan"
install -m 0644 "${DISTRO}/config/titan-base.conf" \
        "${PROFILE}/airootfs/etc/titan/base.conf"
info "escritorio titan-desktop y variables de /etc/titan/base.conf en el perfil"

if [[ -x "${DISTRO}/verify/comprobar-escritorio.sh" ]]; then
  info "comprobando fondo del escritorio (sin tarjeta central)"
  if ! TITAN_DESKTOP="${DESKTOP}/build/titan-desktop" \
       "${DISTRO}/verify/comprobar-escritorio.sh" \
       >"${WORK_DIR}/titan-desktop-test.log" 2>&1; then
    red "Fallo la prueba de titan-desktop; ultimas lineas del log:"
    tail -n 30 "${WORK_DIR}/titan-desktop-test.log" >&2
    exit 1
  fi
fi

# ------------------------------------------- 2c. barra 'titan-panel' ---------

PANEL="${DISTRO}/apps/titan-panel"
if [[ "${TITAN_SKIP_PANEL:-0}" == "1" ]]; then
  yel "TITAN_SKIP_PANEL=1: no se recompila la barra de tareas"
else
  command -v qmake6 >/dev/null 2>&1 || {
    red "Falta qmake6 para compilar la barra (paquete qt6-base)."
    exit 1
  }
  if [[ ! -f /usr/include/LayerShellQt/window.h ]]; then
    red "Falta LayerShellQt: instala 'layer-shell-qt' en el host de build."
    exit 1
  fi
  if ! ldconfig -p 2>/dev/null | grep -q 'libLayerShellQtInterface'; then
    red "Falta libLayerShellQtInterface: instala 'layer-shell-qt'."
    exit 1
  fi
  info "compilando la barra titan-panel (Qt 6 + layer-shell)"
  if ! ( cd "${PANEL}" && mkdir -p build && cd build \
         && qmake6 .. && make -j"$(nproc)" ) \
       >"${WORK_DIR}/titan-panel-build.log" 2>&1; then
    red "Fallo al compilar titan-panel; ultimas lineas del log:"
    tail -n 30 "${WORK_DIR}/titan-panel-build.log" >&2
    exit 1
  fi
fi
if [[ ! -x "${PANEL}/build/titan-panel" ]]; then
  red "No existe ${PANEL}/build/titan-panel"
  exit 1
fi
install -m 0755 "${PANEL}/build/titan-panel" \
        "${PROFILE}/airootfs/usr/local/bin/titan-panel"
info "barra titan-panel y centro de aplicaciones en el perfil"

# El catalogo, la configuracion y el pintado offscreen se prueban antes de
# meter la barra en la ISO. Asi un cambio en un .desktop, en Name[es] o en
# las variables de /etc/titan/base.conf no llega a la imagen sin avisar.
if [[ -x "${DISTRO}/verify/comprobar-panel.sh" ]]; then
  info "comprobando catalogo y barra de titan-panel (offscreen)"
  if ! TITAN_PANEL="${PANEL}/build/titan-panel" \
       "${DISTRO}/verify/comprobar-panel.sh" \
       >"${WORK_DIR}/titan-panel-test.log" 2>&1; then
    red "Fallo la prueba de titan-panel; ultimas lineas del log:"
    tail -n 30 "${WORK_DIR}/titan-panel-test.log" >&2
    exit 1
  fi
fi

if [[ -x "${DISTRO}/verify/comprobar-resolucion.sh" ]]; then
  info "comprobando la deteccion de resolucion de QEMU"
  if ! "${DISTRO}/verify/comprobar-resolucion.sh" \
       >"${WORK_DIR}/titan-resolucion-test.log" 2>&1; then
    red "Fallo la prueba de resolucion; ultimas lineas del log:"
    tail -n 30 "${WORK_DIR}/titan-resolucion-test.log" >&2
    exit 1
  fi
fi

# ------------------------------------- 2e. TITAN Shell y aplicaciones -------

build_qt_app() {
  local name="$1"
  local app_dir="${DISTRO}/apps/${name}"
  local build_dir="${app_dir}/build"
  local log="${WORK_DIR}/${name}-build.log"

  if [[ ! -f "${app_dir}/${name}.pro" ]]; then
    red "Falta ${app_dir}/${name}.pro"
    return 1
  fi

  info "compilando ${name} (Qt 6)"
  if ! (
    mkdir -p "${build_dir}"
    cd "${build_dir}"
    qmake6 ..
    make -j"$(nproc)"
  ) >"${log}" 2>&1; then
    red "Fallo al compilar ${name}; ultimas lineas del log:"
    tail -n 30 "${log}" >&2
    return 1
  fi

  if [[ ! -x "${build_dir}/${name}" ]]; then
    red "No existe el ejecutable ${build_dir}/${name}"
    return 1
  fi

  install -m 0755 "${build_dir}/${name}" \
    "${PROFILE}/airootfs/usr/local/bin/${name}"

  info "${name} instalado en el perfil de la ISO"
}

command -v qmake6 >/dev/null 2>&1 || {
  red "Falta qmake6 para compilar las aplicaciones Qt 6."
  exit 1
}

build_qt_app titan-shell || exit 1
build_qt_app titan-terminal || exit 1
build_qt_app titan-finder || exit 1
build_qt_app titan-fotos || exit 1
build_qt_app titan-musica || exit 1
build_qt_app titan-settings || exit 1

# ------------------------------------------- 2d. app 'titan-acerca' ----------

ACERCA="${DISTRO}/apps/titan-acerca"
if [[ "${TITAN_SKIP_ACERCA:-0}" == "1" ]]; then
  yel "TITAN_SKIP_ACERCA=1: no se recompila la app Acerca"
else
  command -v qmake6 >/dev/null 2>&1 || {
    red "Falta qmake6 para compilar Acerca (paquete qt6-base)."
    exit 1
  }
  info "compilando la app Acerca (Qt 6)"
  if ! ( cd "${ACERCA}" && mkdir -p build && cd build \
         && qmake6 .. && make -j"$(nproc)" ) \
       >"${WORK_DIR}/titan-acerca-build.log" 2>&1; then
    red "Fallo al compilar titan-acerca; ultimas lineas del log:"
    tail -n 30 "${WORK_DIR}/titan-acerca-build.log" >&2
    exit 1
  fi
fi
if [[ ! -x "${ACERCA}/build/titan-acerca" ]]; then
  red "No existe ${ACERCA}/build/titan-acerca"
  exit 1
fi
install -m 0755 "${ACERCA}/build/titan-acerca" \
        "${PROFILE}/airootfs/usr/local/bin/titan-acerca"
desktop_acerca="${PROFILE}/airootfs/usr/share/applications/titan-acerca.desktop"
if [[ ! -f "${desktop_acerca}" ]]; then
  red "Falta ${desktop_acerca}"
  exit 1
fi
info "app Acerca y su entrada del catalogo en el perfil"

if [[ -x "${DISTRO}/verify/comprobar-acerca.sh" ]]; then
  info "comprobando app Acerca y su entrada en el catalogo"
  if ! TITAN_ACERCA="${ACERCA}/build/titan-acerca" \
       TITAN_PANEL="${PANEL}/build/titan-panel" \
       "${DISTRO}/verify/comprobar-acerca.sh" \
       >"${WORK_DIR}/titan-acerca-test.log" 2>&1; then
    red "Fallo la prueba de titan-acerca; ultimas lineas del log:"
    tail -n 30 "${WORK_DIR}/titan-acerca-test.log" >&2
    exit 1
  fi
fi

# ------------------------------------------- 3. repositorio local del kernel --

kernel_pkg=""
extra_packages=()

# La base de datos del repositorio local se regenera en cada build: si no, un
# build antiguo seguiria Serviendo un kernel que ya no esta en el arbol.
rm -f -- "${REPO_DIR}"/titan.db "${REPO_DIR}"/titan.files \
         "${REPO_DIR}"/titan.db.tar.* "${REPO_DIR}"/titan.files.tar.*

if (( use_kernel )); then
  shopt -s nullglob
  # Solo el paquete del kernel en si: el split tambien produce -docs y
  # -headers, y 'ls -t' se llevaria el ultimo que se construyo (los docs).
  candidates=()
  for p in "${DISTRO}"/kernel/linux-titanlinux/linux-titanlinux-*.pkg.tar.zst; do
    [[ $p == *-docs-* || $p == *-headers-* ]] && continue
    candidates+=("$p")
  done
  shopt -u nullglob
  if (( ${#candidates[@]} )); then
    kernel_pkg="$(ls -t "${candidates[@]}" | head -n1)"
    # El repositorio local se reconstruye desde cero en cada build: si no, un
    # paquete viejo seguiria siendo instalable.
    rm -f -- "${REPO_DIR}"/linux-titanlinux-*.pkg.tar.zst
    install -m 0644 "${kernel_pkg}" "${REPO_DIR}/$(basename "${kernel_pkg}")"
    # Un repositorio file:// necesita su base de datos (titan.db); sin ella
    # pacman aborta con "failed retrieving file 'titan.db' from disk".
    command -v repo-add >/dev/null || { red "Falta 'repo-add' (viene con pacman)"; exit 1; }
    repo-add --quiet "${REPO_DIR}/titan.db.tar.gz" \
      "${REPO_DIR}"/linux-titanlinux-*.pkg.tar.zst
    # Sin el '-p' aqui: lo antepone la linea que llama a mkarchiso.
    extra_packages+=(linux-titanlinux)
    info "kernel propio: $(basename "${kernel_pkg}") (repo local 'titan' actualizado)"

    # El paquete tambien viaja DENTRO de la ISO, en /titan-repo. Motivo: el
    # instalador (root/install.sh) tiene que poder poner el kernel del proyecto
    # en el disco que instala, y no hay repositorio publico de donde sacarlo.
    # La cache de pacman del live va vacia (mkarchiso borra lo que instala), asi
    # que sin esta copia el sistema instalado se quedaria con el kernel de
    # Arch. El instalador busca primero en /titan-repo y luego en la cache.
    if [[ "${TITAN_ISO_KERNEL_PKG:-1}" == "1" ]]; then
      rm -rf -- "${PROFILE}/airootfs/titan-repo"
      install -d -m 0755 "${PROFILE}/airootfs/titan-repo"
      install -m 0644 "${kernel_pkg}" \
        "${PROFILE}/airootfs/titan-repo/$(basename "${kernel_pkg}")"
      # El .PKGINFO basta para que el instalador sepa de que version se trata
      # sin tener que abrir el paquete entero.
      printf '%s\n' "$(basename "${kernel_pkg}")" >"${PROFILE}/airootfs/titan-repo/LEEME"
      info "paquete del kernel copiado al perfil (/titan-repo en el live)"
    else
      rm -rf -- "${PROFILE}/airootfs/titan-repo"
      yel "TITAN_ISO_KERNEL_PKG=0: el live NO lleva el paquete del kernel;"
      yel "el sistema instalado usara el kernel de Arch."
    fi
  else
    rm -rf -- "${PROFILE}/airootfs/titan-repo"
    yel "No hay kernel propio construido; la ISO llevara solo el kernel de Arch."
    yel "Para incluirlo: makepkg en kernel/linux-titanlinux"
  fi
else
  rm -rf -- "${PROFILE}/airootfs/titan-repo"
  yel "--no-kernel: la ISO se construye sin el kernel propio"
fi

# ------------------------------------------------- 4. ficheros generados ------

# Variables que lee /root/customize_airootfs.sh dentro del chroot.
# arch-chroot no propaga el entorno del host, de ahi el fichero.
install -m 0644 /dev/null "${PROFILE}/airootfs/etc/titan-build.env"
cat >"${PROFILE}/airootfs/etc/titan-build.env" <<EOF
# Generado por scripts/build-iso.sh. Lo lee airootfs/root/customize_airootfs.sh
TITAN_VERSION="${TITAN_VERSION}"
TITAN_CODENAME="${TITAN_CODENAME}"
TITAN_BUILD_DATE="${TITAN_BUILD_DATE}"
TITAN_VARIANT="live"
TITAN_KERNEL_PKG="linux-titanlinux"
EOF

# pacman.conf con la ruta real del repositorio local.
generated_conf="${WORK_DIR}/pacman.conf"
sed "s|%TITAN_REPO%|${REPO_DIR}|g" "${PROFILE}/pacman.conf" >"${generated_conf}"

# Lista de espejos robusta para el build de la ISO:
# Sitúa en primer lugar los CDNs globales oficiales de Arch (geo y fastly)
# y filtra espejos con fallos de multiplexación HTTP/2 o caídos (como cachyos.org o zyner.org).
generated_mirrorlist="${WORK_DIR}/mirrorlist"
cat >"${generated_mirrorlist}" <<'EOF'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://fastly.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://mirror.leaseweb.com/archlinux/$repo/os/$arch
EOF
if [[ -r /etc/pacman.d/mirrorlist ]]; then
  grep -E '^[[:space:]]*Server[[:space:]]*=' /etc/pacman.d/mirrorlist \
    | grep -vE 'cachyos\.org|zyner\.org' >>"${generated_mirrorlist}" || true
fi
chmod 0644 "${generated_mirrorlist}"
sed -i "s|/etc/pacman.d/mirrorlist|${generated_mirrorlist}|g" "${generated_conf}"
info "espejos para el build -> ${generated_mirrorlist} (CDNs oficiales al frente)"

# Y la cache de paquetes, que por defecto NO va al sitio que dice pacman.
#
# En un airootfs recien hecho /var/cache/pacman/pkg no existe todavia, asi que
# pacman avisa "couldn't find or create package cache, using /tmp/ instead" y se
# descarga alli lo que necesita. En un host normal /tmp es un disco; aqui /tmp
# es un tmpfs de 5,7 GB, y la ISO se queda sin sitio a mitad de la descarga:
#
#   error: failed retrieving file 'linux-titanlinux-...pkg.tar.zst' from disk:
#          Failure writing output to destination, passed 16383 returned 3014
#
# Que es un error de lo mas tonto del mundo (no queda espacio) expresado de la
# forma mas dificil de entender, y solo cuando ya se ha descargado un gigabyte.
# Aqui se le dice donde puede dejar los paquetes, en el disco de verdad, que
# tiene 20 GB libres. Y luego se borran, porque 1,5 GB de .pkg.tar.zst en un
# directorio de trabajo no se pueden quedar dando vueltas.
cache_dir="${WORK_DIR}/x86_64/cache"
mkdir -p "${cache_dir}"
sed -i "s|^#\?CacheDir.*|CacheDir = ${cache_dir}|" "${generated_conf}"
if ! grep -q "^CacheDir = ${cache_dir}$" "${generated_conf}"; then
  { red "el pacman.conf generado no ha quedado con CacheDir: revisa la plantilla"; exit 1; }
fi
info "pacman.conf generado -> ${generated_conf} (cache en ${cache_dir})"

# Las lineas de arranque viven en el perfil (grub.cfg y syslinux-linux.cfg), no
# en el airootfs, asi que el check de customize_airootfs.sh no las ve. La ISO
# no debe fijar una resolucion: usa la nativa del firmware o la que
# scripts/run-qemu.sh pone en virtio-vga despues de detectar el monitor. Un
# video= estatico deja franjas negras o una ventana que no cabe.
info "comprobando que el arranque no fija una resolucion estatica"
entradas_total=0
entradas_con_video=0
for cfg in "${PROFILE}/grub/grub.cfg" \
           "${PROFILE}/syslinux/syslinux-linux.cfg"; do
  if [[ ! -r "$cfg" ]]; then
    red "Falta ${cfg}"
    exit 1
  fi
  while IFS= read -r linea; do
    entradas_total=$((entradas_total + 1))
    if [[ "$linea" == *"video="* ]]; then
      entradas_con_video=$((entradas_con_video + 1))
      red "  entrada con video= fijo: ${linea}"
    fi
  done < <(grep -E '^[[:space:]]*linux /|^APPEND ' "$cfg")
done
if (( entradas_con_video )); then
  red "${entradas_con_video} de ${entradas_total} entradas fijan la pantalla"
  red "La resolucion debe detectarse en run-qemu.sh, no escribirse aqui."
  exit 1
fi
if [[ ! -x "${DISTRO}/scripts/detectar-resolucion.sh" ]]; then
  red "Falta o no es ejecutable scripts/detectar-resolucion.sh"
  exit 1
fi
info "${entradas_total} entradas de arranque sin resolucion fija"

# ----------------------------------------------------------------- 5. mkarchiso --

info "lanzando mkarchiso (esto tarda: descarga paquetes y monta airootfs.erofs)"
# Ojo con el orden: getopts se detiene en el primer argumento que no sea una
# opcion, y el perfil es posicional. Todo lo que lleve '-p' tiene que ir ANTES
# del perfil; puesto despues, mkarchiso lo ignora en silencio y la ISO sale sin
# el kernel propio.
args=(-C "${generated_conf}"
      -o "${OUT_DIR}"
      -w "${WORK_DIR}"
      -L "TITAN_$(date +%Y%m)"
      -P "Titan Linux Project"
      -A "Titan Linux ${TITAN_VERSION} (${TITAN_CODENAME})")
(( ${#extra_packages[@]} )) && args+=(-p "${extra_packages[@]}")
args+=("${PROFILE}")
[[ -n "$verbose" ]] && args+=(-v)

SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(date +%s)}" export SOURCE_DATE_EPOCH
TITAN_VERSION="${TITAN_VERSION}" export TITAN_VERSION
TITAN_CODENAME="${TITAN_CODENAME}" export TITAN_CODENAME

# mkarchiso no suelta ni una linea hasta el final (en archiso 90 todos sus
# mensajes de progreso van detras del '-v', que se pide con -v aqui), asi que
# el build parece colgarse durante cinco minutos. Este latido solo dice "sigo
# aqui", y se para en cuanto mkarchiso acaba.
latido=0
if [[ -z "$verbose" ]]; then
  (
    t0=$(date +%s)
    while sleep 30; do
      printf '    (sigue, %s s)\n' "$(( $(date +%s) - t0 ))"
    done
  ) &
  latido=$!
  # Con 'trap', no con un kill aqui: si el build falla a mitad (por ejemplo en
  # un check de customize_airootfs.sh) el script se va por 'set -e' y sin esto
  # el latido se queda escribiendo en el log del build siguiente.
  trap '[[ "${latido:-0}" != 0 ]] && kill "${latido}" 2>/dev/null; true' EXIT
fi
mkarchiso "${args[@]}"
if (( latido )); then
  kill "${latido}" 2>/dev/null || true
  wait "${latido}" 2>/dev/null || true
  latido=0
fi

# ------------------------------------------------------------------ 6. resultado

# La ISO anterior se borro antes de empezar, asi que lo que hay aqui es
# necesariamente de este build. Aun asi se comprueba que no sea del futuro: si
# mkarchiso se comiese un error y no escribiese nada, el 'find' no daria nada y
# esto falla, que es lo que tiene que pasar.
iso="$(find "${OUT_DIR}" -maxdepth 1 -name '*.iso' -printf '%T@ %p\n' | sort -rn | head -n1 | cut -d' ' -f2-)"
[[ -n "$iso" ]] || { red "No se encontro ninguna ISO en ${OUT_DIR}"; exit 1; }

grn "ISO construida: ${iso}"
ls -lh -- "${iso}" | awk '{print "   tamano: " $5}'
( cd "$(dirname "$iso")" && sha256sum "$(basename "$iso")" >"$(basename "$iso").sha256" )
info "sha256: $(cut -d' ' -f1 <"${iso}.sha256")"
echo
info "siguiente paso:  ${DISTRO}/scripts/verify-qemu.sh"
info "o, para arrancarla con ventana:  ${DISTRO}/scripts/run-qemu.sh"
