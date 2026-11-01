#!/bin/bash
# ---------------------------------------------------------------------------
# Titan Linux -- paso 2: disco, particionado y montaje
#
# Es el unico paso que DESTRUYE datos, asi que va con tres medidas grandes de
# seguridad: no se ofrece formatear sin confirmar, la confirmacion pide
# escribir el nombre del disco a mano, y antes de formatear se ensena lo que
# hay ahi dentro.
#
# El automatico (lo de por defecto) usa sgdisk y monta siempre en este orden,
# decidido de antemano para no tener que redimensionar nada despues:
#
#   1. arranque   (UEFI: 1 GiB de particion EFI;  BIOS: 1 MiB de bios_grub)
#   2. swap       (solo si se ha pedido particion de swap)
#   3. raiz       (todo lo que queda)
#
# ---------------------------------------------------------------------------

DESTINO="/mnt"
ESP_MNT="/mnt/boot/efi"

# --- elegir disco -----------------------------------------------------------

discos_candidatos() {
  local d
  while read -r d; do
    [[ "${d}" =~ ^(loop|sr|ram|zram)[0-9]*$ ]] && continue
    # El live corre desde un DVD, que ademas no se puede formatear.
    [[ "$(cat "/sys/class/block/${d}/removable" 2>/dev/null)" == "1" ]] && continue
    printf '%s|%s|%s\n' "/dev/${d}" \
      "$(tamano_legible "$(( $(cat "/sys/class/block/${d}/size") * 512 ))")" \
      "$(sed 's/ *$//' "/sys/class/block/${d}/device/model" 2>/dev/null)"
  done < <(ls /sys/class/block | grep -E '^(sd[a-z]+|nvme[0-9]+n[0-9]+|vd[a-z]+|mmcblk[0-9]+)$')
}

# Las columnas que se piden son NAME,TYPE,SIZE,MOUNTPOINT, o sea $1 $2 $3 $4.
# Las de sgdisk son otras (NUMERO CODIGO INICIO FIN tamano) y ahi el codigo va
# en $5: mezclar los dos formatos hacia que en la ventana se enseñara el
# numero de particion donde iba el nombre, y el punto de montaje donde el
# tamaño.
particiones_de() {
  local disco="$1"
  lsblk -nr -o NAME,TYPE,SIZE,MOUNTPOINT "${disco}" 2>/dev/null |
    awk '$2=="part" {printf "  /dev/%s  %s", $1, $3; if ($4!="") printf " (montada en %s)", $4; print ""}'
}

menu_disco() {
  local lista opciones tam tamano
  lista="$(discos_candidatos)"
  if [[ -z "${lista}" ]]; then
    menu_error "No hay discos donde instalar" \
"No se ha encontrado ningun disco donde instalar Titan Linux.

Si estas en una maquina virtual, anade un disco duro virtual y vuelve a
arrancar. Si estas en un equipo real, comprueba que el disco aparece en la
BIOS."
    return 1
  fi
  opciones=""
  while IFS='|' read -r tam tamano modelo; do
    opciones+="${tam}:${tamano}  ${modelo}|"
  done <<<"${lista}"
  opciones="${opciones%|}"

  preguntar_lista "disco" "Disco de instalacion" \
"¿Donde quieres instalar Titan Linux?

  SE BORRA TODO LO QUE HAYA EN EL DISCO ELEGIDO.
  El live va en memoria, asi que esto no se puede deshacer." \
    "${opciones}" 20 ""
  [[ -n "${E[disco]}" ]] || return 1
  E[aviso_disco]="$(particiones_de "${E[disco]}")"
  return 0
}

confirmar_borrado() {
  local disco="$1"
  if [[ "${AUTO}" == "1" ]]; then
    # En autopilot no hay nadie que confirme: se exige que el fichero de
    # respuestas lo diga de forma explicita, para que una comprobacion
    # automatica no pueda formatear el disco de alguien por un descuido.
    if [[ "${E[confirmar_borrado]:-}" != "si" ]]; then
      error "autopiloto: falta confirmar_borrado=si en el fichero de respuestas"
      return 1
    fi
    E[confirmado]="si"
    return 0
  fi

  if [[ -n "${E[aviso_disco]}" ]]; then
    menu_informacion "Antes de continuar" \
"El disco ${disco} tiene esto dentro ahora mismo:

${E[aviso_disco]}

Se va a borrar entero. Si hay algo que quieras conservar, sal de aqui ahora."
  fi

  # El '--yesno' NO es opcional ni decorativo: es el tipo de ventana. Sin el,
  # dialog imprime su ayuda y sale con codigo 0, el '||' de despues no se
  # cumple nunca, y el disco se borra sin que nadie haya dicho que si. Por eso
  # el comprobador verifica que toda llamada a ventana lleve su tipo.
  ventana --title "Borrar el disco" --backtitle "Titan Linux  -  Instalador" \
    --defaultno --yes-label "Si, borrar" --no-label "No, salir" \
    --yesno "Se va a BORRAR TODO el contenido de ${disco}.

Esto no tiene vuelta atras y la instalacion no empieza hasta que lo
confirmes.

¿Seguro?" 14 70 || {
      menu_error "Instalacion cancelada" \
"No se ha tocado nada. El live sigue aqui y puedes salir cuando quieras."; return 1; }

  # La segunda confirmacion: escribir el nombre del disco a mano. Es la que
  # salva del error de formatear el disco equivocado por ir con prisa.
  local escrito
  escrito="$(ventana --title "Borrar el disco" --backtitle "Titan Linux  -  Instalador" \
    --inputbox "Ultima comprobacion. Escribe el nombre del disco para confirmar:

    ${disco}

O sea ${disco##*/} , sin /dev/ y en minusculas" 12 62 3>&1 1>&2 2>&3)" || {
      menu_error "Instalacion cancelada" "No se ha tocado nada."; return 1; }
  if [[ "${escrito}" != "${disco##*/}" ]]; then
    menu_error "No coincide" \
"Se esperaba:  ${disco##*/}
Has escrito:  ${escrito:-(nada)}

No se ha borrado nada."
    return 1
  fi
  E[confirmado]="si"
  return 0
}

# --- tamano del swap y comprobacion de espacio ------------------------------

tamano_swap_gib() {
  local ram_gib
  ram_gib="$(( $(awk '/^MemTotal:/{print $2}' /proc/meminfo) / 1024 / 1024 ))"
  if   (( ram_gib >= 16 )); then printf '4'
  elif (( ram_gib >= 8  )); then printf '4'
  elif (( ram_gib >= 4  )); then printf '8'
  else printf '16'; fi
}

comprobar_espacio() {
  local disco="$1" necesario="$2" disponibles=$3
  (( disponibles >= necesario )) && return 0
  menu_error "El disco es pequeno" \
"El escritorio que has elegido necesita unos ${necesario} GB y en
${disco} solo hay ${disponibles} GB.

Puedes continuar (y la instalacion se quedara sin sitio), o volver atras y
elegir un escritorio mas ligero, como niri, Sway o 'solo terminal'."
  if [[ "${AUTO}" == "1" ]]; then
    error "autopiloto: falta espacio (${disponibles} GB de ${necesario} GB)"
    return 1
  fi
  preguntar_si "seguir_sin_espacio" "El disco es pequeno" \
"¿Continuar de todos modos?" "no"
  [[ "${E[seguir_sin_espacio]}" == "si" ]]
}

# --- sistema de ficheros, swap y cifrado -----------------------------------

menu_sistema_ficheros() {
  preguntar_lista "fs" "Como guardar los archivos" \
"¿De que forma quieres guardar los archivos?

  ext4    Lo de siempre: simple y muy probado.
  btrfs    Ademas puede hacer copias instantaneas del sistema entero.
           Si no sabes lo que es, elige ext4." \
    "ext4:ext4, el habitual|btrfs:btrfs, con copias instantaneas" 16 "ext4"

  preguntar_lista "swap" "Memoria de intercambio" \
"¿Que hago con la memoria de intercambio?

  zram      Un trozo de la RAM comprimida. Recomendado con 8 GB o mas.
  particion Un trozo del disco. Solo con poca RAM.
  ninguno   Nada. Si el equipo se queda sin memoria, se queda colgado." \
    "zram:zram, dentro de la memoria (recomendado)|particion:una particion del disco|ninguno:sin swap" 18 "zram"

  preguntar_si "luks" "Cifrado del disco" \
"¿Quieres cifrar lo que se guarda en el disco con una clave?

Con cifrado, nadie mas que tu puede leer lo guardado, ni aunque te roben el
equipo. Tendras que escribir la clave en cada arranque, y si se te olvida no
hay forma de recuperarlo.

Si no lo haces, el sistema es mas facil de recuperar." 17 "no"
}

# --- particionado automatico ------------------------------------------------

particionar_auto() {
  local disco="$1" swap="$2" swap_gib="$3"
  local efi=0
  [[ -d /sys/firmware/efi ]] && efi=1
  E[modo_arranque]="${efi}"

  sgdisk --zap-all "${disco}" >/dev/null 2>&1 || return 1
  wipefs -a "${disco}" >/dev/null 2>&1 || true

  local -a args=()
  if (( efi )); then
    args+=(-n1:0:+1024M -t1:EF00 -c1:"Titan boot")
  else
    # Sin esta particion de 1 MiB, GRUB no se puede instalar sobre GPT en BIOS.
    args+=(-n1:0:+1M -t1:EF02 -c1:"Titan bios-boot")
  fi
  local n=2
  if [[ "${swap}" == "particion" ]]; then
    args+=(-n${n}:0:+${swap_gib}G -t${n}:8200 -c${n}:"Titan swap")
    n=$(( n + 1 ))
  fi
  args+=(-n${n}:0:0 -t${n}:8300 -c${n}:"Titan root")
  sgdisk "${args[@]}" "${disco}" >/dev/null 2>&1 || return 1

  partprobe "${disco}" >/dev/null 2>&1 || partx -u "${disco}" >/dev/null 2>&1 || true
  udevadm settle --timeout=15 2>/dev/null || sleep 3

  local raiz esp swap_p
  raiz="$(particion_por_codigo "${disco}" 8300)" || return 1
  E[part_raiz]="${raiz}"
  E[part_esp]=""; E[part_swap]=""
  if (( efi )); then
    esp="$(particion_por_codigo "${disco}" EF00)" || return 1
    E[part_esp]="${esp}"
  fi
  [[ "${swap}" == "particion" ]] && { swap_p="$(particion_por_codigo "${disco}" 8200)" || true; E[part_swap]="${swap_p:-}"; }
  info "particiones: raiz=${E[part_raiz]} esp=${E[part_esp]:-ninguna} swap=${E[part_swap]:-ninguno}"
  return 0
}

# El numero de particion de la tabla segun su codigo, y su ruta real (que no
# es la misma en sda, nvme ni mmc).
particion_por_codigo() {
  local disco="$1" codigo="$2" num
  num="$(sgdisk -p "${disco}" 2>/dev/null | numero_de_particion "${codigo}")"
  [[ -n "${num}" ]] || return 1
  local ruta
  ruta="$(ruta_particion "${disco}" "${num}")"
  [[ -b "${ruta}" ]] || { error "la particion ${ruta} no aparece todavia"; return 1; }
  printf '%s' "${ruta}"
}

# De la salida de 'sgdisk -p' (por la entrada estandar), el numero de la
# primera particion con el codigo pedido: 8300 la de linux, EF00 la de arranque,
# 8200 la de swap, EF02 la de bios_grub. Se separa del comando a proposito, para
# poder probarlo con una salida de ejemplo sin un disco delante.
#
# OJO con las columnas de 'sgdisk -p'. No son fijas, porque el TAMAÑO son dos
# palabras separadas por un espacio:
#
#   Number  Start (sector)  End (sector)  Size        Code  Name
#      2         2099200        41943006   19.0 GiB    8300  Titan root
#   ^1           ^2              ^3      ^4  ^5     ^6  ^7 ...
#
# o sea que el codigo es el campo de DESPUES de la unidad, no el quinto. Contar
# columnas a pelo aqui hacia que no se encontrase nunca ninguna particion y que
# el paso de disco fallase siempre, con el disco ya borrado. Se busca por eso el
# campo que parece un codigo de cuatro digitos hexadecimales a partir del
# quinto, y solo en las lineas de la tabla (no en los parrafos que sgdisk
# escribe encima de ella).
numero_de_particion() {
  local codigo="$1"
  awk -v c="${codigo}" '
    /^Number/ { cab = 1; next }
    cab {
      for (i = 5; i <= NF; i++) {
        if ($i ~ /^[0-9A-Fa-f]{4}$/ && toupper($i) == toupper(c)) { print $1; exit }
      }
    }'
}

# Como se llama la particion NUM de DISCO. El separador depende de COMO se
# llame el disco, no de si es IDE o NVMe: si el nombre ya acaba en digito hace
# falta la 'p', para que 'nvme0n1' no se convierta en 'nvme0n11'.
#
#   sda1     vda1     hda1            (sin 'p': no acaba en digito)
#   nvme0n1p1 mmcblk0p1 loop0p1 md0p1 (con 'p': si acaba en digito)
#
# Preguntar solo por 'nvme' o 'mmcblk' parece suficiente y no lo es: en un
# equipo normal con disco NVMe, '/dev/nvme0n1' + 'p' daba '/dev/nvme0n12', que
# no existe, y el paso de disco fallaba al buscar la particion raiz (con el
# disco ya borrado). La regla general ('acaba en digito') cubre los dos casos.
ruta_particion() {
  local base="${1##*/}" num="$2"
  if [[ "${base}" =~ [0-9]$ ]]; then
    printf '/dev/%sp%s' "${base}" "${num}"
  else
    printf '/dev/%s%s' "${base}" "${num}"
  fi
}

# --- formato y montaje ------------------------------------------------------

formatear() {
  local fs="$1" raiz="$2" esp="${3:-}" swap="${4:-}"
  if [[ "${fs}" == "btrfs" ]]; then
    mkfs.btrfs -f -L titan "${raiz}" >/dev/null 2>&1 || return 1
  else
    mkfs.ext4 -F -L titan "${raiz}" >/dev/null 2>&1 || return 1
  fi
  if [[ -n "${esp}" ]]; then
    mkfs.fat -F32 -n TITAN "${esp}" >/dev/null 2>&1 || return 1
  fi
  if [[ -n "${swap}" && -b "${swap}" ]]; then
    mkswap -L swap "${swap}" >/dev/null 2>&1 || return 1
  fi
  return 0
}

montar() {
  local fs="$1" raiz="$2" esp="${3:-}" swap="${4:-}"
  umount -R "${DESTINO}" 2>/dev/null || true
  mkdir -p "${DESTINO}"

  if [[ "${fs}" == "btrfs" ]]; then
    # El sistema en si, la carpeta personal y /var, en subvolumenes aparte:
    # asi una copia del sistema entero no se lleva los datos ni las impresoras.
    #
    # OJO: 'mkfs.btrfs' NO crea ningun subvolumen, solo deja el arbol principal.
    # Montar con 'subvol=@' sin haberlo creado antes falla con un error que no
    # dice nada util ('fsconfig() failed: No such file or directory'), asi que
    # primero se monta el arbol principal, se crean los tres subvolumenes, y
    # solo despues se monta cada uno con su '-o subvol='.
    mount -t btrfs "${raiz}" "${DESTINO}" || return 1
    local sv
    for sv in @ @home @var; do
      btrfs subvolume create "${DESTINO}/${sv}" >/dev/null 2>&1 || {
        error "no se ha podido crear el subvolumen ${sv} en ${raiz}"
        umount "${DESTINO}" 2>/dev/null || true
        return 1
      }
    done
    umount "${DESTINO}" || return 1
    mount -t btrfs -o subvol=@,compress=zstd "${raiz}" "${DESTINO}" || return 1
    mkdir -p "${DESTINO}/home" "${DESTINO}/var"
    mount -t btrfs -o subvol=@home,compress=zstd "${raiz}" "${DESTINO}/home" || return 1
    mount -t btrfs -o subvol=@var,compress=zstd  "${raiz}" "${DESTINO}/var"  || return 1
  else
    mount "${raiz}" "${DESTINO}" || return 1
  fi

  if [[ -n "${esp}" ]]; then
    mkdir -p "${ESP_MNT}"
    mount "${esp}" "${ESP_MNT}" || return 1
  fi
  if [[ -n "${swap}" && -b "${swap}" ]]; then
    swapon "${swap}" >/dev/null 2>&1 || aviso "el live no ha podido activar el swap"
  fi
  # Comprobacion de verdad: si /mnt no esta montado, el nombre de la particion
  # estaba mal y lo que se instalase ahi se perderia.
  findmnt -n "${DESTINO}" >/dev/null 2>&1 || return 1
  return 0
}

# --- cifrado ----------------------------------------------------------------

cifrar_raiz() {
  local particion="$1" clave="${E[clave_cifrado]}"
  if [[ -z "${clave}" ]]; then
    preguntar_password "clave_cifrado" "Cifrado del disco" \
"Clave para cifrar el disco.

Se escribe ahora y habra que escribirla en cada arranque. Si se te olvida,
no hay forma de recuperarlo. Minimo 8 caracteres."
    clave="${E[clave_cifrado]}"
  fi
  if [[ ${#clave} -lt 8 ]]; then
    menu_error "Clave corta" "La clave del cifrado necesita al menos 8 caracteres."; return 1
  fi
  printf '%s' "${clave}" | cryptsetup luksFormat --type luks2 --batch-mode --key-file=- "${particion}" || return 1
  printf '%s' "${clave}" | cryptsetup open --type luks2 --key-file=- "${particion}" titan-raiz || return 1
  return 0
}

# --- el paso entero ---------------------------------------------------------

paso_disco() {
  menu_disco || return 1
  menu_sistema_ficheros
  [[ "${E[luks]}" == "si" ]] && exige cryptsetup "cifrado del disco"

  # Espacio: se avisa antes de destruir nada, que luego ya no tiene sentido.
  local disponibles
  disponibles="$(( $(cat "/sys/class/block/${E[disco]##*/}/size") * 512 / 1024 / 1024 / 1024 ))"
  comprobar_espacio "${E[disco]}" "$(datos_escritorio "${E[escritorio]}" | cut -d'|' -f5)" "${disponibles}" || return 1

  confirmar_borrado "${E[disco]}" || return 1

  local swap_gib=""
  [[ "${E[swap]}" == "particion" ]] && swap_gib="$(tamano_swap_gib)"
  particionar_auto "${E[disco]}" "${E[swap]}" "${swap_gib}" || {
    menu_error "No se pudo particionar" \
"El particionado automatico ha fallado en ${E[disco]}.

Suele deberse a que el disco esta protegido por el hardware (cifrado de
fabricante, RAID, o BitLocker) o a un disco con sectores danados al
principio.

Comprueba tambien que el equipo tiene 8 GB de RAM o mas, que es lo que
recomienda el particionado automatico."; return 1; }

  if [[ "${E[luks]}" == "si" ]]; then
    E[cifrado]="si"
    E[part_cifrada]="${E[part_raiz]}"
    cifrar_raiz "${E[part_raiz]}" || {
      menu_error "No se pudo cifrar" "cryptsetup ha fallado al cifrar ${E[part_raiz]}."; return 1; }
    E[part_raiz]="/dev/mapper/titan-raiz"
  else
    E[cifrado]="no"
  fi

  formatear "${E[fs]}" "${E[part_raiz]}" "${E[part_esp]}" "${E[part_swap]}" || {
    menu_error "No se pudo dar formato" "Fallo mkfs sobre ${E[part_raiz]}."; return 1; }

  montar "${E[fs]}" "${E[part_raiz]}" "${E[part_esp]}" "${E[part_swap]}" || {
    menu_error "No se pudo montar" "No se ha podido montar ${E[part_raiz]} en ${DESTINO}."; return 1; }

  info "destino montado: $(findmnt -n -o SOURCE,FSTYPE "${DESTINO}")"
  return 0
}
