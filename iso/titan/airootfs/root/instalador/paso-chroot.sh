#!/bin/bash
# ---------------------------------------------------------------------------
# Titan Linux -- paso 4: configurar el sistema instalado (dentro del chroot)
#
# Todo lo de aqui se ejecuta con 'arch-chroot /mnt', o sea DENTRO del sistema
# que se esta instalando, no en el live. Por eso los caminos no llevan /mnt.
#
# Reparto:
#   paso_sistema    cuentas, nombre, idioma, teclado, zona horaria
#   paso_servicios  arranque, cortafuegos, red, y lo que se habilita
#   paso_titan      la identidad del proyecto: titan, fastfetch, scrollback
# ---------------------------------------------------------------------------

raiz() { printf '%s' "${DESTINO}"; }

# --- grupos del sistema ------------------------------------------------------
#
# 'useradd --groups' NO crea los grupos: si uno no existe dice "useradd: group
# 'seat' does not exist", sale con codigo 1, y el instalador se para ahi, con
# veinte minutos de descarga hechos y el sistema entero a medias en el disco.
#
# El que falta es 'seat', y no por descuido de la lista: 'wheel', 'audio',
# 'video', 'storage', 'power', 'network' e 'input' los crea el paquete
# 'filesystem' con reglas de sysusers, pero 'seat' lo crea 'seatd' con SU
# PROPIA regla (/usr/lib/sysusers.d/seatd.conf). Y las reglas de sysusers se
# aplican al ARRANCAR el sistema: uno recien salido de pacstrap no ha arrancado
# nunca, asi que ahi no hay quien las haya aplicado todavia.
#
# Por eso la lista no se da por hecha: se comprueba uno a uno y se crea lo que
# falte, en vez de confiar en lo que traia el paquete de la base.
asegurar_grupos() { # RAIZ LISTA
  local r="$1" lista="$2" g
  local -a faltan=()
  for g in ${lista//,/ }; do
    [[ -n "${g}" ]] || continue
    if ! arch-chroot "${r}" getent group "${g}" >/dev/null 2>&1; then
      faltan+=("${g}")
    fi
  done
  if (( ${#faltan[@]} == 0 )); then
    return 0
  fi
  info "grupos del sistema que no existian y se crean: ${faltan[*]}"
  for g in "${faltan[@]}"; do
    # Con '--system': son grupos del sistema, y sin eso 'groupadd' les asigna
    # un GID del rango de usuarios, que se lo come el primer usuario que se
    # cree despues.
    arch-chroot "${r}" groupadd --system "${g}" \
      || { error "no se ha podido crear el grupo ${g}"; return 1; }
  done
  return 0
}

# --- identidad ---------------------------------------------------------------
#
# Fallo 35: el sistema instalado se presenta como si fuera Arch Linux.
#
# 'pacstrap' deja el /usr/lib/os-release que trae el paquete 'pacman', que dice
# textualmente
#
#     NAME="Arch Linux"
#     PRETTY_NAME="Arch Linux"
#
# y el equipo recien instalado contesta 'Arch Linux' a todo el que lo pregunta:
# el 'fastfetch' de la primera consola, 'lsb_release', 'uname -o', el menu de
# GRUB, las paginas de error de GNOME. Solo el live decia la verdad, porque su
# /usr/lib/os-release lo escribe el build (root/customize_airootfs.sh), y el
# instalador no tocaba el del destino. Lo cazo el driver, con la comprobacion
# de 'fastfetch': pedia 'OS: Titan Linux' y el instalado contestaba 'OS: Arch
# Linux'.
#
# Los valores se COPIAN del os-release del live en vez de escribirse aqui: la
# version vive en un solo sitio (el build) y el instalado no puede quedarse
# atras. Si el live no trae el fichero, se avisa y se deja lo que hubiera: mejor
# un nombre equivocado que un /etc/os-release vacio, que rompe mas cosas (sudo,
# pacman y systemd leen ID= e ID_LIKE= de ahi).
#
# El ORIGEN es un parametro, y no un '/usr/lib/os-release' escrito aqui, por dos
# motivos que son el mismo: la version vive en el build (que es quien escribe el
# os-release del live) y esta funcion tiene que poder comprobarse sin montar
# una ISO, con un os-release de ejemplo delante. Lo segundo no es un adorno: sin
# el parametro, la comprobacion tendria que usar el os-release de ESTE host, que
# es el de Arch, y dariia verde con un os-release que dice 'Arch Linux'.
escribir_identidad() { # RAIZ [ORIGEN]
  # OJO con partirlo en dos lineas, que no es manía. En una sola,
  #     local r="$1" destino="${r}/usr/lib/os-release"
  # el '${r}' se expande ANTES de que 'local' haga su trabajo (los argumentos
  # de una orden simple se expanden todos antes de ejecutarla), asi que con
  # 'set -u' --que es como corre el instalador-- la funcion muere con
  # 'r: unbound variable'. Dentro de la instalacion no se notaba, porque quien
  # la llama tiene su propio 'r' local y el ambito dinamico de bash lo hacia
  # aparecer; pero en cuanto se la llama sin ese 'r' de alrededor (que es lo que
  # hace la comprobacion) se ve al instante. Menos mal.
  local r="$1"
  local origen="${2:-/usr/lib/os-release}" destino="${r}/usr/lib/os-release"
  local nombre bonito version version_id color

  if [[ ! -r "${origen}" ]]; then
    aviso "el live no trae ${origen}; el sistema instalado no va a poder dizer que es Titan"
    return 0
  fi

  nombre="$(sed -n 's/^NAME=//p' "${origen}" | head -n1)"
  bonito="$(sed -n 's/^PRETTY_NAME=//p' "${origen}" | head -n1)"
  version="$(sed -n 's/^VERSION=//p' "${origen}" | head -n1)"
  version_id="$(sed -n 's/^VERSION_ID=//p' "${origen}" | head -n1)"
  color="$(sed -n 's/^ANSI_COLOR=//p' "${origen}" | head -n1)"

  if [[ -z "${nombre}" || -z "${version_id}" ]]; then
    aviso "el os-release del live no trae NAME o VERSION_ID; no se cambia la identidad"
    return 0
  fi

  # Los dos directorios, no solo el de /usr/lib: se escribe tambien el enlace de
  # /etc y el /etc/titan-release, y si el destino no los tiene todavia (una raiz
  # de pruebas, un sistema minimo) el 'ln' y el 'cat' se quedan sin hacer nada y
  # la funcion sale con codigo 0 como si hubiesen salido.
  mkdir -p "${r}/usr/lib" "${r}/etc"
  {
    printf 'NAME=%s\n' "${nombre}"
    printf 'PRETTY_NAME=%s\n' "${bonito}"
    printf 'VERSION_ID=%s\n' "${version_id}"
    printf 'VERSION=%s\n' "${version}"
    # ID=arch e ID_LIKE=arch se copian tal cual del live, y a proposito: Titan
    # Linux es una derivada de Arch, y los hooks de pacman, los scripts de
    # /etc y el propio systemd toman decisiones leyendo estas dos lineas.
    sed -n '/^ID=/p;/^ID_LIKE=/p' "${origen}"
    printf 'ANSI_COLOR=%s\n' "${color:-38;2;56;214;255}"
    printf 'HOME_URL=%s\n' "$(sed -n 's/^HOME_URL=//p' "${origen}" | head -n1)"
    printf 'SUPPORT_URL=%s\n' "$(sed -n 's/^SUPPORT_URL=//p' "${origen}" | head -n1)"
    printf 'BUG_REPORT_URL=%s\n' "$(sed -n 's/^BUG_REPORT_URL=//p' "${origen}" | head -n1)"
    printf 'LOGO=%s\n' "$(sed -n 's/^LOGO=//p' "${origen}" | head -n1)"
  } >"${destino}"

  # /etc/os-release es un enlace simbolico a ese fichero, en Arch y en el live.
  # Si el destino no lo tiene (o tiene el suyo propio), se deja como este
  # enlace: es como lo tiene el live y como lo espera el resto.
  ln -sf ../usr/lib/os-release "${r}/etc/os-release"

  # /etc/titan-release es lo propio del proyecto (el live lo tiene) y lo que
  # leen los scripts de 'titan version' y 'titan-mira'. Sin VARIANT=live, que
  # es la del live.
  cat >"${r}/etc/titan-release" <<EOF
NAME=${nombre}
PRETTY_NAME=${bonito}
VERSION=${version}
VERSION_ID=${version_id}
CODENAME=TITAN
VARIANT=installed
ID=titan
ID_LIKE=arch
EOF
  info "identidad del sistema instalado: ${bonito}"
  return 0
}

# --- cuentas ----------------------------------------------------------------

paso_sistema() {
  local r; r="$(raiz)"
  local usuario="${E[usuario]}" clave="${E[clave]}" grupos_usuario=""

  # root SI existe en el sistema instalado (a diferencia del live, donde esta
  # bloqueado): es decision del proyecto y lo normal en un sistema de verdad.
  #
  # OJO con el 'arch-chroot': la clave de root va a lo DENTRO del sistema
  # instalado. Sin el, el 'chpasswd' modifica el /etc/shadow del LIVE, que es
  # justo donde no debe tocar: el root del live queda desbloqueado (con la
  # clave que el usuario acaba de escribir) y el del sistema instalado se
  # queda bloqueado, sin la contrasena que el instalador acaba de prometer para
  # arreglar las cosas desde una consola de rescate.
  if [[ -n "${E[clave_root]}" ]]; then
    printf 'root:%s\n' "${E[clave_root]}" | arch-chroot "${r}" chpasswd \
      || { error "no se ha podido fijar la clave de root"; return 1; }
    info "clave de root puesta en el sistema instalado"
  else
    info "root se deja sin clave (asi se ha pedido)"
  fi

  # La lista de grupos se pasa primero por 'asegurar_grupos'. Sin eso,
  # 'useradd' falla en cuanto uno no existe, y con el sistema entero ya copiado
  # al disco: veinte minutos de trabajo para quedarse sin usuario.
  grupos_usuario="wheel,audio,video,storage,power,network,input,seat"
  asegurar_grupos "${r}" "${grupos_usuario}" \
    || { error "no se han podido preparar los grupos del usuario"; return 1; }
  arch-chroot "${r}" useradd --create-home --shell /bin/bash \
    --groups "${grupos_usuario}" "${usuario}" \
    || { error "no se ha podido crear el usuario ${usuario}"; return 1; }
  printf '%s:%s\n' "${usuario}" "${clave}" | arch-chroot "${r}" chpasswd \
    || { error "no se ha podido fijar la clave de ${usuario}"; return 1; }
  info "usuario ${usuario} creado"

  # sudo: un drop-in, como en el live. Un usuario en 'wheel' ya puede usar
  # sudo, pero la regla de Arch viene comentada de serie, asi que sin esto
  # 'sudo' responde 'no esta en el fichero sudoers'.
  cat >"${r}/etc/sudoers.d/10-titan" <<EOF
# Escrito por el instalador de Titan Linux.
# ${usuario} puede usar sudo sin escribir la clave, igual que en el live.
# Para que la pida, cambia 'NOPASSWD' por 'PASSWD' y ejecuta 'visudo -f' sobre
# este fichero antes de reiniciar.
${usuario} ALL=(ALL:ALL) NOPASSWD: ALL
EOF
  chmod 0440 "${r}/etc/sudoers.d/10-titan"
  # Que el fichero sea valido ANTES de reiniciar: un sudoers roto deja al
  # usuario sin sudo y solo se arregla desde una live.
  if ! arch-chroot "${r}" visudo -c -f /etc/sudoers.d/10-titan; then
    error "el fichero sudoers no es valido; se quitan los permisos"
    rm -f "${r}/etc/sudoers.d/10-titan"
    return 1
  fi

  # Nombre, localizacion, teclado, zona horaria
  printf '%s\n' "${E[hostname]}" >"${r}/etc/hostname"
  cat >"${r}/etc/hosts" <<EOF
127.0.0.1	localhost
127.0.1.1	${E[hostname]}
::1	localhost
EOF
  escribir_identidad "${r}"
  ln -sf "/usr/share/zoneinfo/${E[zona]}" "${r}/etc/localtime"
  printf '%s\n' "${E[locale]}" >"${r}/etc/locale.conf"
  # El teclado de la consola y el de las sesiones graficas son dos cosas.
  printf 'KEYMAP=%s\n' "${E[keymap]}" >"${r}/etc/vconsole.conf"
  if [[ -n "${E[teclado_grafico]}" ]]; then
    mkdir -p "${r}/etc/X11/xorg.conf.d"
    printf 'Section "InputClass"\n\tIdentifier "teclado Titan"\n\tMatchIsKeyboard "on"\n\tOption "XkbLayout" "%s"\nEndSection\n' \
      "${E[teclado_grafico]}" >"${r}/etc/X11/xorg.conf.d/00-teclado.conf"
  fi

  # El idioma se genera dentro del sistema nuevo, que es donde hace falta.
  #
  # OJO con la forma de la linea (fallo 32), que es lo mas caro que se ha
  # encontrado en una tarde entera. El 'locale-gen' de glibc 2.41 lee cada linea
  # de '/etc/locale.gen' como DOS campos: el locale y el juego de caracteres. La
  # linea que se escribia aqui era solo el locale ('es_ES.UTF-8'), y el script
  # contesta, textual, en el sistema destino:
  #
  #     Generating locales...
  #     error: Bad entry 'es_ES.UTF-8 '
  #     Generation complete.
  #
  # O sea: no genera NADA, avisa de que la linea esta mal... y sale con codigo
  # 0. Por eso el '|| aviso' de este paso no se enteraba nunca, y el sistema
  # instalado se quedaba sin idioma (locale -a solo knew C, C.utf8 y POSIX)
  # con el usuario creyendo que habia pedido espanol. Un comando que sale bien
  # sin hacer su trabajo: por eso, despues de generarlo, se COMPRUEBA que el
  # idioma existe, que es lo unico que sabe decir la verdad.
  #
  # 'locale -a' normaliza el nombre ('es_ES.UTF-8' sale como 'es_ES.utf8'), asi
  # que la busqueda va sin distinguir mayusculas.
  local juego="${E[locale]##*.}"
  local gen="${r}/etc/locale.gen"
  if [[ "${juego}" == "${E[locale]}" ]]; then
    aviso "el idioma '${E[locale]}' no dice el juego de caracteres; no se genera"
  elif ! grep -q "^${E[locale]}[[:space:]]\+${juego}[[:space:]]*$" "${gen}" 2>/dev/null; then
    printf '%s %s\n' "${E[locale]}" "${juego}" >>"${gen}"
  fi
  arch-chroot "${r}" locale-gen >/dev/null 2>&1 || aviso "locale-gen ha salido con error"
  # Fallo 37: la comprobacion comparaba 'locale -a' con '${E[locale]}' tal cual, y
  # eso NUNCA casa, porque al generar el idioma glibc normaliza el juego de
  # caracteres: escribe 'es_ES.utf8' (sin guion, en minusculas) y no 'es_ES.UTF-8'.
  # Con el idioma GENERADO de verdad, el aviso salia igual:
  #
  #     [AVISO] el idioma es_ES.UTF-8 NO se ha generado: el menu y los mensajes
  #             saldran en ingles
  #
  # y tres minutos despues el sistema arrancaba y 'locale -a' en el disco
  # instalado tenia 'es_ES.utf8' ahi, con el idioma generado y todo. O sea, el
  # aviso era un embuste: decia que el idioma no estaba puesto cuando si que
  # estaba. Y lo que es peor: como el aviso nunca se calla, el aviso de verdad
  # (el que si que importa, el de 'locale-gen' que no genera nada) no se
  # distingue de este.
  #
  # La comparacion se hace con el nombre NORMALIZADO, que es como glibc lo deja,
  # y la normalizacion es la misma que hace la biblioteca: el territorio se queda
  # como esta y el juego de caracteres va en minusculas y solo con letras y
  # digitos ('UTF-8' -> 'utf8', 'ISO-8859-1' -> 'iso88591'). No se busca con un
  # 'grep -i' a pelo porque el guion no es un problema de mayusculas: 'UTF-8' y
  # 'utf8' no son la misma palabra ni ignorando mayusculas.
  #
  # OJO con como se quita lo que no sea alfanumerico. La primera version de este
  # arreglo decia 'tr -d "-_"', y 'tr' ve ahi un RANGO de la tabla ASCII: del '-'
  # (0x2d) al '_' (0x5f). Eso se come los puntos, las barras, los digitos y las
  # MAYUSCULAS enteras, y el nombre esperado se quedaba en 'es_ES.'. Se
  # escribio con la expansion de bash, que no tiene rangos:
  #
  #     juego="${juego,,}"                 # minusculas
  #     juego="${juego//[^a-z0-9]/}"        # fuera lo que no sea alfanumerico
  #
  # (Y con 'LC_ALL=C' no hace falta porque el juego de caracteres son solo letras
  # y digitos, que en la configuracion regional del live estan en el rango
  # latino y salen igual. Aun asi, las dos lineas de arriba no dependen de la
  # configuracion regional, que es justo lo que se busca con esto.)
  local esperado="${E[locale]}"
  if [[ "${esperado}" == *.* ]]; then
    local juego_norm="${esperado##*.}"
    juego_norm="${juego_norm,,}"
    juego_norm="${juego_norm//[^a-z0-9]/}"
    esperado="${esperado%%.*}.${juego_norm}"
  fi
  if arch-chroot "${r}" locale -a 2>/dev/null | tr -d '\r' \
      | grep -qxF "${esperado}"; then
    info "idioma generado: ${esperado}"
  else
    aviso "el idioma ${E[locale]} NO se ha generado: el menu y los mensajes saldran en ingles"
  fi

  # Contrasenas de las cuentas de sistema: sin ellas, cualquier programa puede
  # entrar como 'daemon' o 'nobody'.
  for cuenta in bin daemon ftp games http nobody sys sync usr msg; do
    arch-chroot "${r}" usermod --lock "${cuenta}" 2>/dev/null || true
  done

  return 0
}

# --- servicios --------------------------------------------------------------

paso_servicios() {
  local r; r="$(raiz)"
  local gestor; gestor="$(datos_escritorio "${E[escritorio]}" | cut -d'|' -f2)"

  # Red: en el live manda systemd-networkd, en el sistema instalado manda
  # NetworkManager (que es lo que entiende el usuario y lo que sabe usar el
  # wifi sin herramientas extra). Se apaga el otro para que no se peleen por
  # la misma interfaz.
  arch-chroot "${r}" systemctl enable NetworkManager.service >/dev/null 2>&1
  arch-chroot "${r}" systemctl enable iwd.service >/dev/null 2>&1 || true
  arch-chroot "${r}" systemctl mask systemd-networkd.service >/dev/null 2>&1 || true
  arch-chroot "${r}" systemctl mask systemd-resolved.service >/dev/null 2>&1 || true

  if [[ "${gestor}" != "ninguno" ]]; then
    arch-chroot "${r}" systemctl enable "${gestor}.service" >/dev/null 2>&1 \
      || { error "no se ha podido activar el gestor de sesion ${gestor}"; return 1; }
  else
    # Sin escritorio: consola con login normal, y el scrollback de titan.
    arch-chroot "${r}" systemctl enable getty@tty1.service >/dev/null 2>&1 || true
  fi

  # Bluetooth, si el usuario lo quiere.
  [[ "${E[bluetooth]}" == "si" ]] && arch-chroot "${r}" systemctl enable bluetooth.service >/dev/null 2>&1

  # zram: memoria de intercambio comprimida en RAM.
  #
  # Y el fichero de configuracion, que es la mitad del fallo 33: instalar el
  # paquete NO basta. 'zram-generator' 1.2.1, si no encuentra ningun
  # configuracion, no crea ningun dispositivo y sale sin quejarse (en el
  # registro del sistema solo decia esto, y con un codigo de salida de 0):
  #
  #     zram_generator::config[196]: No configuration found.
  #
  # Es decir: el usuario pide swap en la memoria, el instalador dice que si, y
  # el sistema instalado arranca SIN swap ('swapon --show' no enseña nada). Con
  # el fichero escrito, el mismo arranque da:
  #
  #     kernel: zram: Added device: zram0
  #     systemd[1]: Starting Create swap on /dev/zram0...
  #     NAME       TYPE      SIZE USED PRIO
  #     /dev/zram0 partition 1.9G   0B  100
  #
  # Las tres claves son las documentadas por 'man 5 zram-generator.conf' de esa
  # misma version: 'zram-size' como funcion de 'ram' (la mitad de la memoria,
  # con un tope de 4 GiB, que es el propio valor por defecto), 'zstd' para
  # comprimir (que es lo que lleva el host y lo que aguanta mejor la memoria) y
  # la prioridad 100, que tambien es la de por defecto y va puesta para que se
  # vea a proposito.
  if [[ "${E[swap]}" == "zram" ]]; then
    if arch-chroot "${r}" pacman -S --noconfirm --needed zram-generator >/dev/null 2>&1; then
      mkdir -p "${r}/etc/systemd"
      cat >"${r}/etc/systemd/zram-generator.conf" <<'ZRAM'
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
swap-priority = 100
ZRAM
      info "swap en memoria configurado (zram, la mitad de la memoria, con zstd)"
    else
      aviso "no se ha podido instalar zram-generator (el swap en RAM)"
    fi
  fi

  # Cortafuegos: se instala y se deja PREPARADO, pero no se activa. Encenderlo
  # sin que el usuario lo decida puede dejarle sin red, y eso no tiene arreglo
  # salvo entrando en modo seguro. El paso final le dice el comando.
  if [[ " ${E[apps]}" == *" ufw "* ]]; then
    arch-chroot "${r}" ufw --force reset >/dev/null 2>&1 || true
    arch-chroot "${r}" ufw default deny incoming >/dev/null 2>&1 || true
    arch-chroot "${r}" ufw default allow outgoing >/dev/null 2>&1 || true
    E[ufw]="instalado-sin-activar"
  fi
  return 0
}

# --- identidad Titan --------------------------------------------------------

# El kernel del proyecto se llama linux-titanlinux, y si se instala con LUKS o
# btrfs necesita los hooks de mkinitcpio correspondientes: sin ellos, el
# initramfs no sabe descifrar ni montar y el equipo no arranca.
paso_mkinitcpio() {
  local r; r="$(raiz)"
  local conf="${r}/etc/mkinitcpio.conf"
  if [[ "${E[cifrado]}" == "si" ]]; then
    grep -q '^HOOKS=.*sd-encrypt' "${conf}" || \
      sed -i 's/^HOOKS=(\(.*\))/HOOKS=(sd-encrypt \1)/' "${conf}"
  fi
  if [[ "${E[fs]}" == "btrfs" ]]; then
    grep -q '^HOOKS=.*btrfs' "${conf}" || \
      sed -i 's/^HOOKS=(\(.*\))/HOOKS=(btrfs \1)/' "${conf}"
  fi
  # El filesystem de la particion de arranque tiene que estar en el initramfs.
  local esp_tipo=""
  [[ "${E[modo_arranque]:-0}" == "1" ]] && esp_tipo="fat"
  local base="$(grep '^HOOKS=' "${conf}")"
  if [[ -n "${esp_tipo}" && "${base}" != *filesystems* ]]; then
    sed -i "s/^HOOKS=(\(.*\))/HOOKS=(\1 filesystems)/" "${conf}"
  fi
  # La salida de mkinitcpio va a un log aparte, NO a /dev/null. Cuando esto
  # fallaba (hook 'btrfs' que no encontraba, porque btrfs-progs no estaba
  # instalado) lo unico que decia el instalador era "mkinitcpio ha fallado" y
  # ni una linea de mas: media hora de instalacion perdida por no tener a mano
  # el motivo, que mkinitcpio ya habia escrito entero en su salida.
  if ! arch-chroot "${r}" mkinitcpio -P >"${LOG}.mkinitcpio" 2>&1; then
    error "mkinitcpio ha fallado; el equipo podria no arrancar. Sus ultimas lineas:"
    while IFS= read -r linea; do error "  ${linea}"; done \
      < <(tail -n 15 "${LOG}.mkinitcpio" 2>/dev/null)
    return 1
  fi
  return 0
}

paso_titan() {
  local r; r="$(raiz)"
  local usuario="${E[usuario]}"

  # El CLI del proyecto, compilado en la ISO.
  if [[ -f /usr/local/bin/titan ]]; then
    install -m 0755 /usr/local/bin/titan "${r}/usr/local/bin/titan"
  else
    aviso "el live no lleva el binario 'titan'"
  fi

  # fastfetch, que el live trae de serie y el sistema instalado se queda sin el
  # (fallo 34). No es un adorno del live: es la herramienta con la que se ve el
  # equipo, y sin ella el sistema instalado no tiene forma de enseñarse. Es un
  # paquete de los repos, asi que se pide con pacman y no se copia del live.
  arch-chroot "${r}" pacman -S --noconfirm --needed fastfetch >/dev/null 2>&1 \
    || aviso "no se ha podido instalar fastfetch"
  # El logo de fastfetch, si esta en el live.
  local origen
  for origen in /usr/share/titan/titan-logo.png /usr/share/titan/logo.png \
                /etc/skel/.config/fastfetch/titan.png; do
    if [[ -f "${origen}" ]]; then
      mkdir -p "${r}/usr/share/titan"
      install -m 0644 "${origen}" "${r}/usr/share/titan/titan-logo.png"
      break
    fi
  done
  # La configuracion de fastfetch con el logo (lo que hace 'titan' al arrancar).
  if [[ -d /etc/titan ]]; then
    cp -a /etc/titan "${r}/etc/" 2>/dev/null || true
  fi

  # El historial de la consola: los tres ficheros del live, con la condicion
  # adaptada. En un equipo con escritorio grafico el gestor de sesion ocupa
  # tty1, asi que el wrapper tiene que aplicarse a las demas tty y no a la del
  # gestor (ver /root/instalador/instalador-tmux.txt).
  # Con el '[[ -f ]]' porque el script va con 'set -e': un 'install' de un
  # fichero que no exista no avisa de nada util y para el instalador entero, aqui
  # ya con el sistema instalado. El prompt y el historial son adornos; si no
  # estan, se avisa y se sigue.
  if [[ -f /etc/profile.d/10-titan.sh ]]; then
    install -m 0644 /etc/profile.d/10-titan.sh "${r}/etc/profile.d/10-titan.sh"
  else
    aviso "el live no lleva el prompt de Titan (/etc/profile.d/10-titan.sh)"
  fi
  if [[ -f /etc/tmux.conf ]]; then
    install -m 0644 /etc/tmux.conf "${r}/etc/tmux.conf"
  else
    aviso "el live no lleva la configuracion de tmux"
  fi
  cat >"${r}/etc/profile.d/20-titan-scrollback.sh" <<'EOF'
# Titan Linux -- historial de la consola de texto.
#
# La consola de texto del kernel no puede hacer scroll (fbcon no implementa
# con_scrolldelta), asi que el historial lo da un tmux por encima. Solo
# envuelve las consolas de texto, nunca el puerto serie, que es la via de
# rescate y la que usan las comprobaciones automaticas.
#
# En un equipo con escritorio grafico el gestor de sesion ocupa tty1, asi que
# aqui se aplica a cualquier tty virtual que no sea la suya.

[[ -z "${TMUX:-}" ]] || return 0
[[ -t 1 ]] || return 0
command -v tmux >/dev/null 2>&1 || return 0

tty_actual="$(tty 2>/dev/null || true)"
[[ "${tty_actual}" == /dev/tty[0-9]* ]] || return 0

# Si hay un gestor de sesion grafico, saber en que tty esta.
tty_grafica=""
if systemctl is-active --quiet display-manager 2>/dev/null; then
  for proceso in gdm sddm lightdm cage; do
    tty_grafica="$(ps -o tty= -C "${proceso}" 2>/dev/null | head -n1 | tr -d ' ')"
    [[ -n "${tty_grafica}" ]] && break
  done
fi
[[ -n "${tty_grafica}" && "${tty_actual}" == "/dev/${tty_grafica}" ]] && return 0

exec tmux new-session -A -s titan
EOF
  chmod 0644 "${r}/etc/profile.d/20-titan-scrollback.sh"

  # El terminal grafico. Decision del proyecto: kitty.
  if [[ -n "$(terminal_escritorio "${E[escritorio]}")" ]]; then
    if ! arch-chroot "${r}" pacman -S --noconfirm --needed kitty >/dev/null 2>&1; then
      aviso "no se ha podido instalar kitty"
    else
      # Que 'kitty' sea el terminal de verdad: tanto el que usan KDE y los
      # editores como el que aparece en el menu de archivos.
      arch-chroot "${r}" update-alternatives --install /usr/bin/x-terminal-emulator \
        x-terminal-emulator /usr/bin/kitty 50 >/dev/null 2>&1 || true
      arch-chroot "${r}" update-alternatives --install /usr/bin/xterm xterm /usr/bin/kitty 50 >/dev/null 2>&1 || true
      # GNOME lo guarda en su propia base de ajustes, asi que hay que
      # escribirlo con gsettings como el usuario, no como root.
      if [[ "${E[escritorio]}" == "gnome" ]]; then
        arch-chroot "${r}" su - "${usuario}" -c \
          "dbus-run-session -- gsettings set org.gnome.desktop.default-applications.terminal exec kitty" \
          >/dev/null 2>&1 || aviso "el terminal por defecto de GNOME no se ha podido cambiar; se cambia en Ajustes"
      fi
    fi
  fi

  # Aviso de bienvenida, como el del live.
  if [[ -f /etc/motd ]]; then
    cp -a /etc/motd "${r}/etc/motd"
  fi

  return 0
}
