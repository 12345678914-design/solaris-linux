#!/bin/bash
#
# Titan Linux 0.1 - personalizacion de la ISO en vivo.
#
# Lo ejecuta archiso DENTRO del chroot de airootfs, despues de pacstrap.
# Por eso se puede escribir /usr/lib/os-release y /etc/passwd: aqui ya no hay
# ningun paquete que lo pise despues.
#
# Que hace, en orden:
#   1. identidad de la distribucion (os-release, titan-release, hostname, motd)
#   2. usuario 'titan' con autologin y su configuracion de shell
#   3. initramfs de archiso para el kernel propio del proyecto
#   4. anillo de claves de pacman, para que el live pueda instalar paquetes
#   5. red por DHCP con systemd-networkd
#   6. comprobacion: si falta un comando basico, el build falla aqui y no
#      en mitad de una prueba en QEMU

set -euo pipefail

log() { printf '==>%s\n' " $*"; }

# Los valores los deja scripts/build-iso.sh en /etc/titan-build.env.
# Si no estan (perfil usado a mano) se usan los de abajo.
if [[ -r /etc/titan-build.env ]]; then
  # shellcheck disable=SC1091
  . /etc/titan-build.env
fi
TITAN_VERSION="${TITAN_VERSION:-0.1.0}"
TITAN_CODENAME="${TITAN_CODENAME:-TITÁN}"
TITAN_VARIANT="${TITAN_VARIANT:-live}"
TITAN_BUILD_DATE="${TITAN_BUILD_DATE:-$(date -u +%Y-%m-%d)}"
TITAN_KERNEL_PKG="${TITAN_KERNEL_PKG:-linux-titanlinux}"

# ---------------------------------------------------------------- 1. identidad

log "identidad: Titan Linux ${TITAN_VERSION} (${TITAN_CODENAME})"

cat >/usr/lib/os-release <<EOF
NAME="Titan Linux"
PRETTY_NAME="Titan Linux ${TITAN_VERSION} (${TITAN_CODENAME})"
VERSION_ID="${TITAN_VERSION}"
VERSION="${TITAN_VERSION} (${TITAN_CODENAME})"
# ID=arch es deliberado: Titan Linux es una derivada de Arch y pacman, los
# hooks y las herramientas de /etc dependen de ese identificador.
ID=arch
ID_LIKE=arch
ANSI_COLOR="38;2;56;214;255"
HOME_URL="https://github.com/titan-linux"
SUPPORT_URL="https://github.com/titan-linux/issues"
BUG_REPORT_URL="https://github.com/titan-linux/issues"
LOGO=titanlinux-logo
EOF
ln -sf ../usr/lib/os-release /etc/os-release

cat >/etc/titan-release <<EOF
NAME="Titan Linux"
PRETTY_NAME="Titan Linux ${TITAN_VERSION} (${TITAN_CODENAME})"
VERSION="${TITAN_VERSION}"
VERSION_ID="${TITAN_VERSION}"
CODENAME="${TITAN_CODENAME}"
BUILD_DATE="${TITAN_BUILD_DATE}"
VARIANT="${TITAN_VARIANT}"
ID=titan
ID_LIKE=arch
EOF

printf 'titan\n' >/etc/hostname

# Zona horaria. Sin esto, systemd-firstboot abre el asistente interactivo
# "Please enter the new timezone name or number" en la consola, y como el
# airootfs es de solo lectura no hay forma de saltarselo en caliente: la ISO se
# queda ahi preguntando y nunca llega a la shell. En una imagen en vivo UTC es
# la unica respuesta razonable, y ademas es la que quiere QEMU.
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
printf 'UTC\n' >/etc/timezone

# Teclado y fuente de consola. KEYMAP=us porque el teclado de QEMU es US.
cat >/etc/vconsole.conf <<'EOF'
KEYMAP=us
FONT=Lat2-Terminus16
EOF

# Locale: espanol si se puede generar, C.UTF-8 si no.
if localedef -i es_ES -f UTF-8 es_ES.UTF-8 2>/dev/null; then
  printf 'LANG=es_ES.UTF-8\n' >/etc/locale.conf
else
  printf 'LANG=C.UTF-8\n' >/etc/locale.conf
fi
rm -f /etc/locale.gen

# ------------------------------------------------------------------ 2. usuario

log "usuario: titan"

if ! getent passwd titan >/dev/null; then
  useradd --create-home --home-dir /home/titan --shell /bin/bash \
          --comment "Titan Linux" --groups wheel titan
fi
# Sin contrasena: es una ISO en vivo, y asi `su titan` no pide nada.
passwd -d titan >/dev/null 2>&1 || true

# sudo sin contrasena, para que 'sudo pacman -S ...' funcione de verdad.
# Hace falta porque en el sudoers de Arch la regla de wheel esta COMENTADA
# (# %wheel ALL=(ALL:ALL) ALL): sin esto, sudo responde "titan is not in the
# sudoers file", y aunque estuviera, pediria una contrasena que este usuario no
# tiene.
log "sudo: sin contrasena para el usuario titan"
install -d -m 0750 /etc/sudoers.d
cat >/etc/sudoers.d/10-titan <<'EOF'
# Titan Linux (live): el usuario titan no tiene contrasena, asi que sudo
# tiene que funcionar sin prompt. Es lo mismo que hace la ISO oficial de Arch
# con su usuario archlive.
titan ALL=(ALL:ALL) NOPASSWD: ALL
EOF
chmod 0440 /etc/sudoers.d/10-titan
chown root:root /etc/sudoers.d/10-titan
# El prompt y los alias de /etc/profile.d/10-titan.sh tambien para shells
# que no son de login.
if [[ ! -f /home/titan/.bashrc ]]; then
  cp /etc/skel/.bashrc /home/titan/.bashrc
fi
printf '\n# Titan Linux\n[[ $- == *i* ]] && . /etc/profile.d/10-titan.sh\n' \
  >>/home/titan/.bashrc
chown -R titan:titan /home/titan

# fastfetch: que 'fastfetch' a secas ya salga con el logo y las claves en
# espanol de Titan Linux. fastfetch no busca en /usr/share/fastfetch/presets/
# para la configuracion por defecto, sino en ~/.config/fastfetch/config.jsonc
# (la lista de rutas sale de 'fastfetch --list-config-paths'), asi que el
# preset del sistema se enlaza ahi. Enlazar y no copiar: asi el preset sigue
# siendo una unica fuente de verdad, y 'fastfetch --config titan' (que si
# busca en /usr/share) da exactamente lo mismo.
log "fastfetch: config por defecto con el logo de Titan"
install -d -m 0755 -o titan -g titan /home/titan/.config/fastfetch
ln -sfn /usr/share/fastfetch/presets/titan.jsonc \
        /home/titan/.config/fastfetch/config.jsonc


# ------------------------------------------- 2b. escritorio grafico ---------
#
# Labwc inicia titan-desktop y titan-shell desde su autostart.
# El perfil 15-titan-grafico.sh inicia la sesion grafica en tty1.
log "escritorio: Labwc y titan-shell"

for fichero in \
    /usr/local/bin/titan-shell \
    /usr/local/bin/titan-terminal \
    /usr/local/bin/titan-finder \
    /usr/local/bin/titan-desktop \
    /usr/local/bin/titan-panel \
    /usr/local/bin/titan-acerca \
    /usr/share/applications/titan-acerca.desktop \
    /etc/titan/base.conf \
    /etc/profile.d/15-titan-grafico.sh \
    /etc/skel/.config/labwc/autostart \
    /etc/skel/.config/labwc/rc.xml \
    /etc/skel/.config/labwc/themerc; do
  [[ -e "${fichero}" ]] || {
    echo "ERROR: falta ${fichero}" >&2
    echo "       Revisa scripts/build-iso.sh y el perfil de la ISO." >&2
    exit 1
  }
done

install -d -m 0755 -o titan -g titan /home/titan/.config/labwc

install -m 0755 \
    /etc/skel/.config/labwc/autostart \
    /home/titan/.config/labwc/autostart
chown titan:titan /home/titan/.config/labwc/autostart

install -m 0644 \
    /etc/skel/.config/labwc/rc.xml \
    /home/titan/.config/labwc/rc.xml

install -m 0644 \
    /etc/skel/.config/labwc/themerc \
    /home/titan/.config/labwc/themerc

if [[ -f /etc/skel/.config/labwc/environment ]]; then
  install -m 0644 \
      /etc/skel/.config/labwc/environment \
      /home/titan/.config/labwc/environment
fi

for xbm in /etc/skel/.config/labwc/*.xbm; do
  if [[ -f "$xbm" ]]; then
    install -m 0644 "$xbm" "/home/titan/.config/labwc/$(basename "$xbm")"
  fi
done

chown -R titan:titan /home/titan/.config/labwc

# El MOTD de Arch (paquete 'filesystem') no viene en el perfil: se sustituye.
rm -f /etc/motd

# ------------------------------------------------- 3. initramfs del kernel propio

# El kernelrelease con sufijo -titanlinux, tal y como lo produce el PKGBUILD
# (localversion.10-pkgrel + localversion.20-pkgname).
kver="$(find /usr/lib/modules -maxdepth 1 -mindepth 1 -type d -name '*-titanlinux' \
        -printf '%f\n' 2>/dev/null | sort -V | tail -n 1 || true)"

if [[ -n "$kver" ]]; then
  # El hook de alpm de mkinitcpio ya ha podido construir este initramfs al
  # instalar el paquete del kernel. Si lo hizo bien (lleva el hook 'archiso'),
  # no hay que rehacerlo: son varios minutos de zstd para nada.
  img="/boot/initramfs-linux-titanlinux.img"
  if [[ -s "$img" ]] && lsinitcpio "$img" 2>/dev/null | grep -q 'hooks/archiso'; then
    log "initramfs del kernel propio ya trae el hook archiso; se reutiliza"
  else
    log "initramfs de archiso para el kernel propio ${kver}"
    mkinitcpio -k "$kver" -p linux-titanlinux
  fi
else
  log "AVISO: no hay kernel propio instalado; la ISO solo lleva el de Arch"
fi

# --------------------------------------------------- 4. pacman utilizable (live)

log "anillo de claves de pacman (para poder instalar paquetes en el live)"
pacman-key --init >/dev/null 2>&1 || true
pacman-key --populate archlinux >/dev/null 2>&1 || true

# El mirrorlist que trae el paquete pacman viene con TODOS los espejos
# comentados, porque en una instalacion normal los activa el instalador. En una
# ISO en vivo no hay instalador, asi que 'sudo pacman -S ...' fallaba con
# "no servers configured for repository". Se activa el espejo geografico de
# Arch (el que enruta por pais, sin lista de paises que mantener) mas un
# respaldo. Con commented queda la lista original del paquete, por si alguien
# quiere activar mas espejos a mano.
log "pacman: espejos activados en /etc/pacman.d/mirrorlist"
if [[ -f /etc/pacman.d/mirrorlist ]]; then
  cp -f /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.commented
fi
cat >/etc/pacman.d/mirrorlist <<'EOF'
## Titan Linux (live): la lista de candidatos, en el orden en que se prefieren.
##
## De estos diez, al medirlos uno a uno (ver 'medir_espjos' en
## /root/instalador/paso-base.sh) solo unos pocos contestan con la ultima
## version de los paquetes. Con rolling eso es normal: un paquete acaba de
## publicarse y los espejos van sincronizandolo a distinta velocidad, asi que
## un 404 aqui no es un problema del espejo, es que va con retraso. Por eso el
## instalador mide antes de descargar en vez de confiar en el primero de la
## lista.
##
## Para hacer 'sudo pacman -S ...' a mano sin instalar, vale esta misma lista:
## pacman va probando uno por uno para cada fichero.
##
## La lista completa de espejos de Arch (toda comentada, tal como la instala el
## paquete pacman) esta en /etc/pacman.d/mirrorlist.commented.
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://fastly.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
Server = https://mirror.dogado.de/archlinux/$repo/os/$arch
Server = https://mirror.clarkson.edu/archlinux/$repo/os/$arch
Server = https://mirrors.dotsrc.org/archlinux/$repo/os/$arch
Server = https://mirror.leaseweb.com/archlinux/$repo/os/$arch
EOF
# La misma lista, aparte, en el formato que entiende 'espejos_candidatos': URLs
# peladas, una por linea, y SIN los comodines de pacman al final. Los comodines
# ('$repo/os/$arch') los sustituye pacman al instalar, pero no al medir: para
# medir hay que anadir una ruta de verdad delante, y con '$repo' en medio la URL
# que se pide no existe en ninguna parte. Por eso es un fichero aparte, y no se
# deduce leyendo el mirrorlist de arriba.
sed -n 's/^Server[[:space:]]*=[[:space:]]*//p' /etc/pacman.d/mirrorlist \
  | sed 's#/\$repo/os/\$arch$##' >/etc/pacman.d/mirrorlist.candidatos
chmod 0644 /etc/pacman.d/mirrorlist
chmod 0644 /etc/pacman.d/mirrorlist.commented 2>/dev/null || true
chmod 0644 /etc/pacman.d/mirrorlist.candidatos

# ------------------------------------------------------------- 5. red en el live

log "red: systemd-networkd + systemd-resolved"
install -d -m 0755 /etc/systemd/network
cat >/etc/systemd/network/20-ethernet.network <<'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes
DNS=1.1.1.1 8.8.8.8
EOF
cat >/etc/systemd/network/20-wlan.network <<'EOF'
[Match]
Name=wlan* wl*

[Network]
DHCP=yes
DNS=1.1.1.1 8.8.8.8
EOF

for unit in systemd-networkd systemd-resolved; do
  if [[ -e "/usr/lib/systemd/system/${unit}.service" ]]; then
    # install -d: el directorio no tiene por que existir todavia y ln -sf con
    # set -e abortaria el build entero.
    install -d -m 0755 "/etc/systemd/system/multi-user.target.wants"
    ln -sf "/usr/lib/systemd/system/${unit}.service" \
           "/etc/systemd/system/multi-user.target.wants/${unit}.service"
  fi
done

# ---------------------------------------------------------- 6. comprobaciones

log "comprobacion: comando basico de Linux + titan + fastfetch"

# El mismo conjunto que documenta `titan commands`.
required="ls cat pwd mkdir rmdir rm cp mv ln touch stat file tree realpath
basename dirname readlink less head tail wc grep cut tr sort uniq tee diff column
fold nl rev paste join sed awk gawk expr seq xargs fmt pr find rg fd fzf bat which
jq ps top htop free vmstat uptime uname hostname id whoami date cal env lscpu lspci
lsusb lsblk dmesg sysctl lsof strace df du mount umount fdisk mkfs.ext4 fsck blkid
dd ip ss ping curl wget dig host ethtool tar gzip gunzip bzip2 xz zstd unzip pacman
makepkg base64 nano vim man git bc titan fastfetch sudo"

missing=""
for cmd in $required; do
  command -v "$cmd" >/dev/null 2>&1 || missing="${missing} ${cmd}"
done

if [[ -n "$missing" ]]; then
  printf 'ERROR: la ISO no tiene estos comandos:%s\n' "$missing" >&2
  printf 'Revisa iso/titan/packages.x86_64 y reconstruye.\n' >&2
  exit 1
fi

# 'command -v' localiza un fichero aunque NO sea ejecutable (bash solo resuelve
# el nombre contra el PATH), asi que el bucle de arriba no dice nada de que los
# binarios funcionen. Esto los ejecuta de verdad, que es la unica comprobacion
# que detecta un 0644 en un binario.
run_check() {
  local cmd="$1" hint="$2"
  # Con 'bash -c' porque el argumento es una linea de shell con sus opciones
  # ("fastfetch --config titan"), no un unico ejecutable.
  if ! bash -c "$cmd" >/dev/null 2>&1; then
    printf 'ERROR: %s\n' "$cmd falla dentro de la imagen" >&2
    printf '       %s\n' "$hint" >&2
    exit 1
  fi
}
run_check 'titan version' \
  'Comprueba file_permissions en iso/titan/profiledef.sh: archiso copia el perfil con --no-preserve=mode y solo restaura los modos de ahi.'
run_check 'titan doctor' 'El CLI titan deberia pasar todas sus comprobaciones.'
run_check 'fastfetch --config titan' 'Revisa /usr/share/fastfetch/presets/titan.jsonc y /usr/share/titan/titan.logo.'
# El escritorio de tty1. Se comprueba aqui, y no en el paso 2b, porque alli
# todavia no existe la funcion run_check (es un fallo real del primer build).
run_check 'bash -n /etc/profile.d/15-titan-grafico.sh' \
  'El arranque grafico tiene un error de sintaxis.'
run_check 'command -v labwc' \
  'Falta labwc; revisa iso/titan/packages.x86_64.'
run_check 'test -x /home/titan/.config/labwc/autostart' \
  'Falta el autostart de labwc que crea el paso 2b.'
run_check 'command -v titan-shell' \
  'Falta titan-shell; revisa el bloque de compilacion Qt.'
run_check 'command -v titan-terminal' \
  'Falta titan-terminal; revisa el bloque de compilacion Qt.'
run_check 'command -v titan-finder' \
  'Falta titan-finder; revisa el bloque de compilacion Qt.'
run_check '/usr/local/bin/titan-shell --comprobar | grep -q "^titan-shell=ok"' \
  'titan-shell no pasa su autocomprobacion.'
run_check '/usr/local/bin/titan-desktop --comprobar | grep -q "^so=."' \
  'titan-desktop no lee /etc/titan/base.conf (nombre del sistema).'
run_check '/usr/local/bin/titan-desktop --comprobar | grep -q "^usuario=."' \
  'titan-desktop no lee el usuario de /etc/titan/base.conf.'
run_check '/usr/local/bin/titan-panel --comprobar | grep -q "^barra_alto=."' \
  'titan-panel no lee /etc/titan/base.conf o no arranca sin grafico.'
run_check '/usr/local/bin/titan-acerca --comprobar | grep -q "^ram=."' \
  'titan-acerca no lee los datos del equipo.'
run_check 'test -e /usr/share/applications/titan-acerca.desktop' \
  'Falta la entrada de Acerca en el catalogo de aplicaciones.'
run_check 'test -e /usr/lib/libLayerShellQtInterface.so' \
  'Falta layer-shell-qt: la barra no tendria capa ni zona exclusiva.'
run_check 'test -e /usr/lib/qt6/plugins/wayland-shell-integration/liblayer-shell.so' \
  'Falta el plugin de layer-shell de Qt; revisa layer-shell-qt.'
for programa in dbus-run-session labwc kitty pcmanfm-qt; do
  run_check "command -v ${programa}" \
    "Falta ${programa}: revisa iso/titan/packages.x86_64."
done

# sudo tiene que servir PARA ALGO: poder instalar paquetes en el live. Ojo a que
# 'command -v sudo' no dira nada (ver la nota de mas abajo): hay que ejecutarlo
# como el usuario titan y sin contrasena.
if [[ "$(su titan -c 'sudo -n id -u' 2>/dev/null)" != 0 ]]; then
  echo "ERROR: 'sudo -n' no da root para el usuario titan." >&2
  echo "       Revisa /etc/sudoers.d/10-titan y el modo 0440 de ese fichero." >&2
  exit 1
fi
run_check 'sudo -n pacman --version' \
  'pacman deberia estar en la ISO para poder instalar paquetes en el live.'

# Que pacman tenga espejos es justo lo que rompia el live, y no lo detecta
# 'pacman --version'. Ademas se comprueba que las bases de datos de los repos
# se pueden sincronizar de verdad, para que un espejo roto falle aqui y no en
# la ISO ya quemada.
if ! grep -qE '^[[:space:]]*Server[[:space:]]*=' /etc/pacman.d/mirrorlist; then
  echo "ERROR: /etc/pacman.d/mirrorlist no tiene ningun Server activo." >&2
  echo "       Sin espejos, 'sudo pacman -S' no puede descargar nada." >&2
  exit 1
fi
# Que los repos sincronizen de verdad, no solo que el mirrorlist tenga lineas
# Server. Aqui el DNS ya funciona: mkarchiso lanza este script con arch-chroot,
# que monta el /etc/resolv.conf del host dentro del chroot. Ojo: por eso
# /etc/resolv.conf es un punto de montaje y 'rm' sobre el da EBUSY, no se toca.
# (Ejecutar este script a mano con 'chroot' plano, en cambio, no da DNS: por eso
# el fallo por nombres baja a aviso en vez de tumbar el build.)
sync_log=/tmp/titan-pacman-sync.log
sync_ok=0
pacman -Sy --noconfirm >"${sync_log}" 2>&1 && sync_ok=1
if (( sync_ok )); then
  log "pacman: repos sincronizados desde la imagen"
elif grep -qE 'Could not resolve host|Temporary failure in name resolution' "${sync_log}"; then
  echo "AVISO: no se pudieron sincronizar los repos en el chroot (sin DNS aqui)." >&2
  echo "       Lo verificara el check 9 de verify-qemu.sh dentro del live." >&2
else
  echo "ERROR: los repos de la imagen no sincronizan con este mirrorlist:" >&2
  tail -3 "${sync_log}" >&2
  echo "       Revisa los Server de /etc/pacman.d/mirrorlist." >&2
  exit 1
fi
rm -f "${sync_log}"

# Y el preset tiene que estar enlazado como configuracion por defecto del
# usuario, que es lo que hace que un 'fastfetch' a secas salga con el logo.
for f in /usr/share/fastfetch/presets/titan.jsonc \
         /usr/share/titan/titan.logo \
         /home/titan/.config/fastfetch/config.jsonc; do
  [[ -r "$f" ]] || { echo "ERROR: falta $f" >&2; exit 1; }
done

# El historial de la salida en la consola (ver /etc/tmux.conf para el porque):
# si tmux falta o el envoltorio no esta, el live vuelve a ser una consola sin
# scroll y no hay nada que avisar al usuario en el arranque. Mejor que falle
# aqui el build, que quemando la ISO.
log "historial de consola: tmux + envoltorio de tty1"
run_check 'tmux -V' \
  'Anade tmux a iso/titan/packages.x86_64: la consola del kernel no tiene scroll.'
for f in /etc/tmux.conf /etc/profile.d/20-titan-scrollback.sh; do
  [[ -r "$f" ]] || {
    echo "ERROR: falta $f (historial de la salida en la consola)." >&2
    echo "       Revisa que el fichero siga en iso/titan/airootfs/etc/." >&2
    exit 1
  }
done
# 'bash -n' es la unica forma de pillar un error de sintaxis aqui: dentro del
# chroot no hay tty, asi que tmux no llega a arrancar un servidor de prueba.
# Y ademas tmux no avisa de un config invalido ni con 'start-server' ni con
# 'new-session -d' (comprobado con tmux 3.7: codigo de salida 0 y ni un aviso),
# asi que desde aqui solo se puede mirar lo que se puede mirar.
run_check 'bash -n /etc/profile.d/20-titan-scrollback.sh' \
  'El envoltorio de tty1 tiene un error de sintaxis.'
# Lo que tmux IGNORA EN SILENCIO: los nombres de las teclas de pagina. tmux
# llama a RePag 'PPage' y a AvPag 'NPage'. Escribir 'PageUp' o 'S-PageUp' no da
# error: no se registra ningun binding y la tecla se queda muerta (y dentro
# del historial se le soltaria el codigo de tecla entero a la shell). Por eso
# se comprueba con grep, la unica forma de verlo sin terminal.
if grep -qE '^[[:space:]]*bind[^#]*(S-)?Page(Up|Down)' /etc/tmux.conf; then
  echo "ERROR: /etc/tmux.conf usa nombres de tecla de pagina que tmux ignora." >&2
  echo "       Usa PPage y NPage (ver 'tmux list-keys -T copy-mode')." >&2
  grep -nE '^[[:space:]]*bind[^#]*(S-)?Page(Up|Down)' /etc/tmux.conf >&2
  exit 1
fi
# Y que no se le prometa al usuario una tecla que no existe. El unico sitio
# donde se le dice que tecla pulsar es la pista del banner (el heredoc HINT),
# asi que ahi no puede aparecer Shift+RePag, que el keymap del kernel se come
# antes de que llegue a la tty (ver la cabecera de /etc/tmux.conf). En el config
# lo equivalente ya esta comprobado arriba: que ningun 'bind' la use. Los
# COMENTARIOS si la pueden mencionar, que para eso estan: es donde se explica
# por que la tecla es esa y no otra, asi que buscarla ahi seria absurdo.
pista="$(sed -n "/<<'HINT'/,/^HINT\$/p" /etc/profile.d/10-titan.sh)"
if printf '%s\n' "$pista" | grep -qE 'Shift\+RePag'; then
  echo "ERROR: la pista del banner ofrece Shift+RePag, que el kernel no deja" >&2
  echo "       pasar a la tty. Ofrece RePag a secas (ver /etc/tmux.conf)." >&2
  printf '%s\n' "$pista" | grep -nE 'Shift\+RePag' >&2
  exit 1
fi
# Y que la pista mencione la tecla que si funciona, que si no el usuario se
# queda sin saber como volver atras.
if ! printf '%s\n' "$pista" | grep -q 'RePag'; then
  echo "ERROR: la pista del banner no dice como se vuelve atras." >&2
  exit 1
fi
# La comprobacion de verdad de los enlaces de /etc/tmux.conf (arrancar un tmux
# de prueba y LEER su tabla de teclas con 'list-keys') NO se puede hacer aqui, y
# no por el config: porque dentro del chroot no hay terminal.
#
# tmux arranca un servidor que necesita una terminal de verdad, y una terminal
# de verdad es /dev/pts/ptmx. En el airootfs, /dev esta vacio: mkarchiso lo
# monta mientras instala los paquetes y lo desmonta despues, y este script viene
# mas tarde. Asi que tmux responde 'server exited unexpectedly' y no hay tabla de
# teclas que leer. De ahi el error que ha parado dos builds seguidos:
#
#   ERROR: /etc/tmux.conf no engancha el historial: sin servidor
#
# que decia falsehood: el problema no era el config, era que no habia donde
# arrancar. Antes se sortaba por casualidad, cuando otro build habia dejado /dev
# montado ahi; a partir de ahi, o nunca, y no se puede fiar de eso.
#
# Montar /dev aqui tampoco vale: no se puede (dentro de este chroot mount() da
# EPERM con las mismas capacidades que fuera), y aunque se pudiera, un '--rbind'
# de /dev entra en el grupo de propagacion compartido del /dev del host, con lo
# que un 'umount -R' posterior se lleva el /dev de la maquina que construye. Ya
# se ha probado de verdad. No se repite.
#
# La comprobacion vive entonces en scripts/build-iso.sh, en el HOST y antes de
# lanzar mkarchiso: ahi si hay terminal, y ademas falla en dos segundos en vez
# de diez minutos de descargas despues. Ver 'verificar_tmux' en ese script. Y el
# check 9 de verify-qemu.sh, dentro del live ya arrancado, la repite contra el
# config que de verdad acaba instalado.
#
# Lo que si se comprueba aqui es que el fichero este, que tmux este instalado y
# que el envoltorio de tty1 este.
# Y que el envoltorio solo separe tty1: la consola por serie (ttyS0), que usan
# las pruebas automaticas y el instalador, tiene que seguir siendo una shell
# normal, sin tmux en medio que se coma la entrada.
run_check 'grep -q "/dev/tty1" /etc/profile.d/20-titan-scrollback.sh' \
  'El envoltorio de tmux deberia actuar solo sobre tty1.'
# Y que el banner solo se imprima una vez: /etc/profile y ~/.bashrc cargan el
# mismo fichero en la misma shell, y ademas tty1 pasa por tmux. La marca es lo
# que corta la segunda impresion. El test de comportamiento (que si puede
# fallar) esta en verify/comprobar-banner.sh.
run_check 'grep -q TITAN_BANNER_IMPRESO /etc/profile.d/10-titan.sh' \
  'El banner se imprimiria dos veces (profile y .bashrc en la misma shell).'

# El kernel propio tiene que existir si el paquete se instalo. Ojo: el paquete
# se llama linux-titanlinux, y por eso los ficheros de /boot se llaman
# vmlinuz-linux-titanlinux, no vmlinuz-<kernelrelease>.
if [[ -n "$kver" ]]; then
  [[ -s "/boot/vmlinuz-${TITAN_KERNEL_PKG}" ]] || {
    echo "ERROR: falta /boot/vmlinuz-${TITAN_KERNEL_PKG}" >&2; exit 1; }
  [[ -s "/boot/initramfs-${TITAN_KERNEL_PKG}.img" ]] || {
    echo "ERROR: falta /boot/initramfs-${TITAN_KERNEL_PKG}.img" >&2; exit 1; }
fi

# ------------------------------------------- 9. instalador: root y sus ficheros
#
# En el LIVE no hay root. Decision del proyecto: el live existe para instalar el
# sistema y para trabajar, no para administrar. root esta bloqueado (no se
# puede entrar con 'login root', ni con su, ni con su - desde la consola), pero
# sudo sigue funcionando sin contrasena para el usuario 'titan', que es lo que
# hace falta para instalar. En el sistema INSTALADO, en cambio, root si existe y
# tiene contrasena: eso lo pone el instalador.
#
# El bloqueo se hace con 'passwd -l' (no con un '*' escrito a mano) para que
# /etc/shadow quede con el formato que espera shadow.
log "root: bloqueado en el live (sudo sin contrasena sigue funcionando)"
if ! passwd -l root 2>/dev/null; then
  echo "ERROR: no se ha podido bloquear la cuenta de root en el live." >&2
  exit 1
fi
# Comprobacion de verdad sobre /etc/shadow: que la cuenta de root no tenga una
# huella utilizable. Un '!' inicial o un '*' significa que no se puede
# autenticar; cualquier otra cosa si.
root_shadow="$(awk -F: '$1=="root" {print $2}' /etc/shadow)"
case "$root_shadow" in
  '!'*|'*'*)
    log "root bloqueado (huella: ${root_shadow:0:3}...)" ;;
  '')
    echo "ERROR: root no tiene linea en /etc/shadow." >&2
    exit 1 ;;
  *)
    echo "ERROR: root NO esta bloqueado en el live (huella: ${root_shadow:0:3}...)" >&2
    echo "       En el live no debe existir root con clave usable." >&2
    exit 1 ;;
esac

# El instalador y sus modulos tienen que estar todos, ser ejecutables donde toca
# y no tener errores de sintaxis. Un 'install.sh' con un error de sintaxis
# rompe la ISO en el momento de instalar, que es el peor sitio y el mas tarde.
log "instalador: comprobando ficheros y sintaxis"
[[ -f /root/install.sh ]] || {
  echo "ERROR: falta /root/install.sh" >&2; exit 1; }
[[ -x /root/install.sh ]] || {
  echo "ERROR: /root/install.sh no es ejecutable" >&2; exit 1; }

modulos=(lib-comun.sh lib-escritorios.sh lib-apps.sh menus.sh
         paso-red.sh paso-disco.sh paso-base.sh paso-chroot.sh paso-cerrar.sh)
faltan=0
for m in "${modulos[@]}"; do
  if [[ ! -f "/root/instalador/$m" ]]; then
    echo "ERROR: falta el modulo del instalador /root/instalador/$m" >&2
    faltan=1
  fi
done
(( faltan )) && exit 1

# Sintaxis: si un modulo tiene un error, el instalador no arranca y el usuario
# ve un fallo sin explicacion. Aqui se puede ver cual es.
for f in /root/install.sh /root/instalador/*.sh; do
  if ! bash -n "$f" 2>/tmp/titan-bash-n.txt; then
    echo "ERROR: error de sintaxis en $f" >&2
    cat /tmp/titan-bash-n.txt >&2
    exit 1
  fi
done
rm -f /tmp/titan-bash-n.txt
log "instalador: ${#modulos[@]} modulos, sintaxis correcta"

# Y que el instalador tenga las herramientas que usa de verdad. Faltaria una y
# se descubre a mitad de una instalacion, con el disco ya particionado.
log "instalador: comprobando herramientas"
# 'dialog' y no 'whiptail': whiptail era un script que dialog hacia de envoltorio
# y dialog 1.3-20260721 quito ese script del paquete. En Arch ya no existe, asi
# que el instalador habla dialog. Este fallo lo ha cazado el propio build: sin
# esta comprobacion, la ISO se construiria sin ventanas y el instalador se
# quedaria en negro al arrancar.
herramientas=(dialog sgdisk mkfs.ext4 mkfs.btrfs mkfs.fat cryptsetup
              pacstrap arch-chroot genfstab grub-install wpa_supplicant iw)
faltan=0
for h in "${herramientas[@]}"; do
  if ! command -v "$h" >/dev/null 2>&1; then
    echo "ERROR: el instalador necesita '$h' y no esta en el live." >&2
    faltan=1
  fi
done
(( faltan )) && exit 1
log "instalador: ${#herramientas[@]} herramientas presentes"

# El paquete del kernel viaja en la ISO para que el instalador lo pueda poner
# en el disco. No es un error que no este (se puede construir la ISO sin
# kernel propio), pero se avisa: sin el, lo instalado arranca con el de Arch.
if compgen -G '/titan-repo/linux-titanlinux-*.pkg.tar.zst' >/dev/null; then
  log "titan-repo: el live lleva el paquete del kernel del proyecto"
else
  log "titan-repo: sin paquete del kernel; lo instalado usara el de Arch"
fi

log "OK: ${TITAN_VERSION} lista"
