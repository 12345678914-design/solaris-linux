#!/bin/bash
# ---------------------------------------------------------------------------
# Titan Linux -- paso 5: cerrar la instalacion
#
# Lo que se hace aqui, en este orden y por estos motivos:
#
#  1. flatpak dentro del chroot, con su remoto. Se hace con el sistema ya
#     desmontado porque necesita escribir en el disco destino, y con red
#     porque baja el indice de las tiendas.
#  2. sync y desmontar. Un 'umount' sin 'sync' puede dejar el arbol de
#     ficheros a medias, y entonces el equipo no arranca y no se sabe por que.
#  3. La pantalla final: que se ha instalado y que falta hacer (el
#     cortafuegos, que por seguridad no se activa solo).
# ---------------------------------------------------------------------------

paso_flatpak() {
  [[ -n "${E[flatpaks]:-}" ]] || { info "no hay nada de flatpak que instalar"; return 0; }
  local r="${DESTINO}"
  # El remoto se anade con '--if-not-exists' y ya esta: antes se comprobaba
  # antes con 'flatpak remotes --if-exists flathub', pero ese codigo de salida
  # no es de fiar (no dice si lo encontro o no), asi que con un remoto ya
  # puesto se podia dar por bueno un remoto que no estaba y luego fallar al
  # instalar. Con '--if-not-exists' la orden es idempotente de verdad.
  if ! arch-chroot "${r}" flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo; then
    aviso "no se ha podido anadir el remoto de Flathub"
    return 1
  fi
  # Y se comprueba que ha quedado ahi, que es lo que se va a ver luego.
  #
  # OJO con el '--columns=name', que es el arreglo del fallo 28. Sin el, la
  # comprobacion era
  #
  #     flatpak remotes | grep -qx flathub
  #
  # y 'flatpak remotes' NO imprime un nombre por linea: imprime una TABLA, y en
  # esta maquina sale
  #
  #     flathub<TAB>system
  #
  # (una tabulacion y la columna de donde esta puesto). Con '-x', que exige que
  # la linea SEA 'flathub' y nada mas, eso no casa nunca: la comprobacion daba
  # falso, el paso se paraba ahi, y las apps no se instalaban nunca. No hacia
  # falta que el remoto faltara de verdad para que pasara, que es lo grave: la
  # instalacion se rompia con el remoto puesto y en su sitio.
  #
  # Y si aun asi no se ve, no se para la instalacion: se avisa y se sigue. El
  # remoto lo acaba de anadir 'remote-add --if-not-exists', que si falla de
  # verdad avisa y para, y el bucle de abajo avisa app por app de lo que no se
  # pueda bajar. Perder la instalacion entera porque una comprobacion no
  # encuentra una cadena es la misma clase de fallo que el 24.
  if ! arch-chroot "${r}" flatpak remotes --columns=name 2>/dev/null \
        | grep -qx "flathub"; then
    aviso "el remoto de Flathub no aparece en la lista; a lo mejor no se podran instalar las apps"
  fi
  local app
  for app in ${E[flatpaks]}; do
    info "flatpak: instalando ${app} (puede tardar)"
    if ! arch-chroot "${r}" flatpak install -y --noninteractive flathub "${app}" \
         >/dev/null 2>&1; then
      aviso "no se ha podido instalar la app ${app} de Flathub"
      E[flatpak_fallos]+="${app} "
    fi
  done
  return 0
}

# Quien tiene cogido un montaje, sin 'fuser' ni 'lsof', que el live no lleva.
# Se mira /proc, que siempre esta: el directorio de trabajo ('cwd') y la raiz
# ('root') de cada proceso. Son los dos que de verdad impiden soltar un montaje
# ('el destino esta ocupado'). Un fichero abierto dentro tambien lo impide, asi
# que si no aparece ninguno de estos dos, el aviso dice donde mirar.
#
# Esto se imprime solo cuando el umount ha fallado, y es lo unico que ha dicho
# nunca por que se queda montado. Sin esto, el aviso decia 'quedan montajes
# dentro de /mnt' y a partir de ahi no habia ni una pista de por que.
# La tabla de lo que sigue montado DENTRO de un directorio, puesta en el log.
#
# Por que una funcion y no un 'findmnt' a pelo: lo que se necesita es que la
# tabla quede escrita en el log, no solo en la pantalla de aquel momento. Con
# 'findmnt -R /mnt' a secas la tabla se va a la consola, que cuando el
# instalador acaba y el equipo se apaga se pierde; el aviso que la acompaña si
# queda, pero solo decia COMO verla ('se ve con findmnt -R /mnt'), que es
# justamente lo que no hace falta: hace falta verla.
#
# '-R' y no el camino suelto porque 'findmnt /mnt' NO es recursivo: lista solo
# ese montaje, y el culpable de un EBUSY casi nunca es el montaje de /mnt sino
# uno de dentro (el /proc o el /dev que dejo 'arch-chroot', un /run, un /sys).
# Con '-R' salen los dos, que es lo que hace falta.
#
# Con '|| true' porque un 'findmnt' que no encuentra el camino sale con codigo
# 1, y con 'set -e' eso tumbaba el propio paso de desmontaje, que es lo
# contrario de lo que se quiere: aqui se esta ya rindiendo y avisando.
# Los montajes que hay debajo de RUTA, DEL MAS HONDO AL MAS ALTO. Es el unico
# orden en el que se pueden soltar: un padre no se suelta con un hijo montado.
# Y la longitud de la ruta hace de profundidad, que es lo que se ordena.
#
# En modo RAW ('-rn') y pidiendo solo la columna TARGET: sale un objetivo por
# linea, sin cabecera y sin las flechas del arbol, y asi el bucle que las suelta
# no tiene que parsear una tabla. Con la tabla con cabecera (que es lo que hacia
# el codigo de antes) el mismo 'findmnt' mezcla DOS cosas distintas --el montaje
# de RUTA y los que hay DENTRO de el-- y el aviso no las puede separar. Eso es el
# fallo 38, y fue en la pasada real de UEFI del 29 de septiembre: la tabla de una
# sola linea, con RUTA y nada mas, y el aviso rematando 'lo que lo tiene es un
# montaje de dentro de /mnt'.
rutas_de_montajes() { # RUTA
  findmnt -rn -o TARGET -R "$1" 2>/dev/null \
    | awk '{ print length($0) " " $0 }' \
    | sort -rn \
    | cut -d' ' -f2-
}

# Hay ALGO montado dentro de RUTA (sin contar el propio RUTA). Lo que decide lo
# que dice el aviso, y por eso tiene su propia funcion: si lo dijeran dos sitios
# distintos, un dia los dos dirian cosas distintas, que es justo lo que paso.
hay_montajes_dentro() { # RUTA
  local r="$1" m
  while IFS= read -r m; do
    [[ "${m}" == "${r}"/* ]] && return 0
  done < <(rutas_de_montajes "${r}")
  return 1
}

# La tabla de lo que sigue montado, en el log, separando las DOS cosas que antes
# iban juntas: el propio RUTA y lo que hay DENTRO de el.
tabla_montajes() { # RUTA
  local r="$1" tabla
  tabla="$(findmnt -rn -o TARGET,SOURCE,FSTYPE -R "$1" 2>/dev/null || true)"
  if [[ -z "${tabla}" ]]; then
    aviso "no queda ningun montaje en ${r} ni debajo, y el 'umount' no ha podido soltarlo"
  elif hay_montajes_dentro "${r}"; then
    aviso "esto es lo que sigue montado dentro de ${r} (la primera linea es el propio ${r}):"
    aviso "${tabla}"
  else
    aviso "${r} sigue montado y no hay NINGUN montaje dentro de el:"
    aviso "${tabla}"
  fi
  return 0
}

quien_lo_tiene() {
  local r="${1}"
  local proc enlace destino pid com fd
  local encontrado=0
  for proc in /proc/[0-9]*; do
    pid="${proc#/proc/}"
    com="$(cat "${proc}/comm" 2>/dev/null || echo '?')"
    # El directorio de trabajo y la raiz: son los dos que mas veces dejan un
    # '/mnt' con 'el destino esta ocupado'.
    for enlace in cwd root; do
      destino="$(readlink "${proc}/${enlace}" 2>/dev/null || true)"
      destino="${destino% (deleted)}"
      case "${destino}" in
        "${r}"|"${r}"/*) ;;
        *) continue ;;
      esac
      aviso "lo tiene cogido el proceso ${pid} (${com}): su '${enlace}' esta en ${destino}"
      encontrado=1
    done
    # Y un fichero abierto dentro, que es el tercer motivo y el que menos se ve
    # (no sale en 'ps', y no hay 'lsof' en el live). Con '-maxdepth 1' y sin el
    # '*', un proceso sin descriptores no da error.
    for fd in "${proc}"/fd/*; do
      [[ -e "${fd}" ]] || continue
      destino="$(readlink "${fd}" 2>/dev/null || true)"
      destino="${destino% (deleted)}"
      case "${destino}" in
        "${r}"|"${r}"/*) ;;
        *) continue ;;
      esac
      aviso "lo tiene cogido el proceso ${pid} (${com}): tiene abierto ${destino}"
      encontrado=1
    done
  done
  if (( ! encontrado )); then
    aviso "no hay ningun proceso con el directorio de trabajo, la raiz ni ficheros abiertos dentro de ${r}"
    # Y aqui la conclusion que SI se puede poner, que es la que se ponia antes
    # sin mirar: solo se puede decir 'es un montaje de dentro' si hay un montaje
    # de dentro. En la pasada real de UEFI del 29 de septiembre lo decia sin que
    # lo hubiera, con delante la tabla de una sola linea (el propio RUTA) que
    # decia lo contrario: el aviso y su propia prueba, discrepando en el log.
    # Un diagnostico que se contradice no hace falta corregirlo entero: basta
    # con no decir lo que no se sabe.
    if hay_montajes_dentro "${r}"; then
      aviso "asi que lo que lo tiene es un montaje de dentro de ${r}, y la tabla de arriba lo dice"
    else
      aviso "pero no hay ningun montaje dentro de ${r} tampoco: lo que no se suelta es el montaje de ${r} MISMO"
      montajes_de_otros_espacios "${r}"
    fi
  fi
}

# Lo que hay montado dentro de RUTA en el espacio de montajes de OTRO proceso.
#
# OJO con lo que esto es y lo que no es: es EVIDENCIA, no la causa. Medido en un
# laboratorio propio (un btrfs de verdad con los tres subvolumenes y un vfat en el
# /boot/efi, todo dentro de un 'unshare -m'), un montaje hecho en un espacio de
# montajes HIJO NO impide soltar el nuestro: 'umount -R' va bien igual, porque la
# comprobacion de 'el destino esta ocupado' es del espacio de montajes de quien
# desmonta. Lo que si aparece es un resto del instalador (un 'arch-chroot' que se
# quedo vivo y tiene el destino montado en su namespace), que es una pista de por
# donde seguir. Se pone en el log con ese nombre y no como la solucion.
# El punto de montaje de una linea de 'mountinfo', que es el QUINTO campo (id,
# padre, mayor:menor, raiz, punto de montaje, ... y despues los opcionales). Con
# 'awk' y no con 'read -a' porque los campos de en medio no se saben de antemano.
punto_de_montaje() { # LINEA_DE_MOUNTINFO
  awk '{ print $5 }' <<<"$1"
}

# Las lineas de un 'mountinfo' AJENO que son interesante: lo que ese espacio de
# montajes tiene dentro de RUTA y aqui NO se ve. Nada mas. Imprime esas lineas,
# una por linea, y no avisa de nada: quien decide si esto se dice o no es su
# llamante, que es el que tiene el contexto (el PID, y si ya se ha dicho).
#
# Los dos arrays entran por NOMBRE ('local -n'), no por valor, porque un
# 'mountinfo' de verdad son cientos de lineas y porque separarlos por un
# separador de adivinanzas seria justo el tipo de cosa que se rompe el dia que
# una ruta lleva un espacio (el kernel escribe los espacios de 'mountinfo' como
# '\040', pero 'findmnt' los enseña sin escapar, y los dos entran aqui).
#
# Y es una funcion sin bash, para poder darle un 'mountinfo' de verdad como dato
# --una linea real de un proceso real-- en vez de tener que montar nada para
# probarla.
lineas_ajenas_interesantes() { # RUTA NOMBRE_MIOS NOMBRE_LINEAS
  local r="$1" nombre_mios="$2" nombre_lineas="$3"
  # Los nombres de dentro NO pueden ser los que le pasa el llamante: con
  # 'local -n crudas="crudas"' (que es justo como lo llamaba) bash se queja de
  # 'circular name reference', deja el array vacio y la funcion no mira nada.
  # No hacia falta ningun aviso: la funcion no fallaba, devolvia 0 con la lista
  # vacia, que es la forma mas silenciosa de no comprobar nada.
  local -n arr_mios="${nombre_mios}"
  local -n arr_lineas="${nombre_lineas}"
  local linea objetivo
  for linea in "${arr_lineas[@]-}"; do
    objetivo="$(punto_de_montaje "${linea}")"
    case "${objetivo}" in
      "${r}"|"${r}"/*) ;;
      *) continue ;;
    esac
    # Lo que ya tenemos montado nosotros no es 'ajeno': el espacio de montajes de
    # un proceso hijo es una COPIA del nuestro, asi que sin esta lista cada
    # entrada repetiria el arbol entero que ya hemos mostrado y el aviso que
    # vale se perderia en medio.
    [[ " ${arr_mios[*]-} " == *" ${objetivo} "* ]] && continue
    printf '%s\n' "${linea}"
  done
  return 0
}

montajes_de_otros_espacios() { # RUTA
  local r="$1" info pid mio vista linea objetivo
  local visto=0
  local -a ya_vistos=() los_mios=() crudas=() interesantes=()
  mio="$(readlink /proc/self/ns/mnt 2>/dev/null || echo '?')"
  while IFS= read -r linea; do
    [[ -n "${linea}" ]] && los_mios+=("${linea}")
  done < <(rutas_de_montajes "${r}")
  for info in /proc/[0-9]*/mountinfo; do
    [[ -r "${info}" ]] || continue
    pid="${info#/proc/}"
    pid="${pid%/mountinfo}"
    vista="$(readlink "/proc/${pid}/ns/mnt" 2>/dev/null || echo '?')"
    [[ "${vista}" == "${mio}" ]] && continue
    # El bucle con su '2>/dev/null' ANTES del '< "${info}"': hay procesos cuyo
    # 'mountinfo' no se puede ni abrir ni leer (el kernel contesta EINVAL), y
    # como el shell avisa del fallo de la redireccion al 'stderr' de ENTONCES,
    # el '/dev/null' tiene que ir primero. Sin eso el aviso sale en mitad del
    # recorrido, que es justo donde no se lee. Y sin 'exec' a proposito: un
    # 'exec 3< FICHERO 2>/dev/null' deja el 'stderr' del guion entero
    # descartado para siempre (un 'exec' sin orden aplica sus redirecciones a la
    # shell), y a partir de ahi no se ve ningun error de nada.
    crudas=()
    while IFS= read -r linea; do
      crudas+=("${linea}")
    done 2>/dev/null < "${info}" || true
    # Un 'mountinfo' que no se ha podido leer no tiene nada que decir, asi que
    # el proceso se salta entero.
    (( ${#crudas[@]} > 0 )) || continue
    interesantes=()
    mapfile -t interesantes < <(lineas_ajenas_interesantes "${r}" \
                                los_mios crudas) || interesantes=()
    for linea in "${interesantes[@]-}"; do
      [[ -n "${linea}" ]] || continue
      objetivo="$(punto_de_montaje "${linea}")"
      # Uno por proceso y montaje, que si no esto sale una vez por cada proceso
      # que comparta ese espacio de montajes (que son todos los hijos de quien
      # lo creo) y en el log no se lee nada.
      [[ " ${ya_vistos[*]-} " == *" ${pid}:${objetivo} "* ]] && continue
      ya_vistos+=("${pid}:${objetivo}")
      aviso "en el espacio de montajes del proceso ${pid} hay algo montado en ${objetivo} que aqui no se ve: ${linea}"
      visto=1
    done
  done
  if (( ! visto )); then
    aviso "y en ningun otro espacio de montajes hay nada montado dentro de ${r} que aqui no se vea"
  fi
}

# Soltar los montajes de uno en uno, del mas hondo al mas alto, y APUNTAR el que
# no se deja. Un 'umount -R' se para en el primero que falla y no dice cual es,
# que es justo lo que faltaba: el aviso decia que no se habia podido soltar
# /mnt del todo, y lo unico que hacia falta era el nombre del montaje que se
# resiste. Con esta pasada, cada 'umount' que falla deja su ruta en el log.
soltar_uno_a_uno() { # RUTA
  local r="$1" m atascado=0
  while IFS= read -r m; do
    [[ -n "${m}" ]] || continue
    if ! umount "${m}" 2>/dev/null; then
      aviso "este montaje no se ha podido soltar y es el que se resiste: ${m}"
      atascado=1
    fi
  done < <(rutas_de_montajes "${r}")
  # 0 si no se ha atascado nada, 1 si hay algun montaje que se resiste: al
  # reves, el que no encuentra ni un solo 'umount' que falle acababa
  # contestando 'atascado', que es justo cuando no hay nada atascado.
  return "${atascado}"
}

desmontar() {
  local r="${DESTINO}"
  sync
  # Los subvolumenes de btrfs y los montajes de la particion EFI se sueltan
  # con -R; si algo queda montado, el equipo no arranca bien y el usuario no
  # entiende por que.
  #
  # El caso de verdad (fallo 30): hay algo con el directorio de trabajo dentro
  # de /mnt y 'umount -R' responde 'el destino esta ocupado', las dos veces. Con
  # el codigo de antes se acababa en un aviso y el /mnt se quedaba montado, que
  # es justo lo que no puede ser: al arrancar desde el disco el equipo puede no
  # arrancar, y una segunda instalacion desde la misma sesion se encuentra con
  # un /mnt que es otro sistema montado encima.
  #
  # Por eso, antes de rendirse, se dice QUIEN lo tiene (que es lo que hace
  # falta para arreglarlo) y se prueba 'umount -l', que suelta el montaje
  # aunque algo lo tenga cogido. Con el sistema recien instalado ya no se
  # escribe nada dentro, y un montaje suelto a la fuerza es mucho mejor que un
  # montaje que se queda.
  if ! umount -R "${r}" 2>/dev/null; then
    # Antes de reintentar, soltar de uno en uno (que el codigo anterior no
    # hacia nunca): el 'umount -R' se para en el primero que falla y no dice
    # cual, y ademas deja la mitad sin soltar, que es lo que hacia que
    # despues la tabla ya no decia nada del culpable. Asi el log dice QUE
    # montaje se resiste.
    soltar_uno_a_uno "${r}" || :
    sleep 2
    if ! umount -R "${r}" 2>/dev/null; then
      aviso "no se ha podido soltar ${r} del todo"
      # Primero la tabla de montajes, y antes que los procesos (fallo 35). Un
      # montaje colgando dentro de /mnt --un /proc, un /dev, un /sys que dejo
      # 'arch-chroot', que los monta y los desmonta al salir-- no sale en 'ps',
      # ni en '/proc/*/cwd', ni en los descriptores abiertos: para el
      # 'umount' son EBUSY igual que un proceso, pero ninguno de los tres
      # montones los ve. En la pasada real de esto, el aviso decia que no
      # habia ningun proceso y ahi se acababa la pista; con la tabla por
      # delante, el culpable sale solo. El aviso de mas abajo solo decia COMO
      # verlo, y lo que hace falta es verlo.
      #
      # Y va por 'aviso', que escribe en el log, y no con un 'findmnt' a pelo
      # (que solo se veria en la pantalla de aquel momento): el log es lo que
      # se lee despues, cuando el instalador ya ha acabado y el equipo esta
      # apagado, y es donde se busca por que se quedo montado.
      tabla_montajes "${r}"
      quien_lo_tiene "${r}"
      if umount -l -R "${r}" 2>/dev/null; then
        aviso "se ha soltado a la fuerza (umount -l): el montaje ya no estorba, pero algo lo tenia cogido"
        return 0
      fi
      aviso "y con 'umount -l' tampoco: quedan montajes dentro de ${r}:"
      tabla_montajes "${r}"
      return 1
    fi
  fi
  return 0
}

pantalla_final() {
  local texto="Titan Linux instalado
===================================================================

  Se ha instalado en ${E[disco]} con el escritorio $(nombre_escritorio "${E[escritorio]}").
  Usuario: ${E[usuario]}     Arrancador: ${E[arranque]}

  Arranca el equipo con el disco${E[disco]} conectado. Para volver a entrar
  en el live, usa el menu de arranque del equipo.

  ${C_GRIS}Todo lo que este paso ha hecho esta en el log:
  ${LOG}${C_RESET}"
  # El ':-' no es cosmetico: si la instalacion se para antes de llegar a
  # configurar el cortafuegos, E[ufw] no existe, y sin esto el 'set -u' del
  # instalador para aqui echando la exception mientras se enseña la pantalla
  # final, que es justo lo que no puede pasar. Lo mismo con E[kernel].
  if [[ "${E[ufw]:-}" == "instalado-sin-activar" ]]; then
    texto+="

  ${C_TITULO}Un paso que queda a tu eleccion:${C_RESET}

  El cortafuegos (ufw) esta instalado pero NO se ha activado. Se ha hecho
  asi a proposito: si se enciende sin que lo decidas y algo queda cerrado
  por error, no hay forma de arreglarlo sin entrar en modo seguro.

  Cuando quieras activarlo:

      ${C_TITULO}sudo ufw enable${C_RESET}"
  fi
  if [[ -n "${E[flatpak_fallos]:-}" ]]; then
    texto+="

  ${C_TITULO}Apps que no se han podido instalar:${C_RESET}
  ${E[flatpak_fallos]}
  Se pueden instalar desde la tienda cuando haya conexion."
  fi
  if [[ "${E[kernel]:-}" == "linux" ]]; then
    texto+="

  ${C_AVISO}Atencion:${C_RESET} se ha instalado el kernel de Arch, no el del
  proyecto. La ISO no llevaba el paquete linux-titanlinux."
  fi
  texto+="

  ${C_GRIS}El live sigue en memoria: si reinicias sin guardar nada, se
  reinicia desde cero.${C_RESET}"

  if [[ "${AUTO}" == "1" ]]; then
    info "[autopiloto] pantalla final saltada"
    return 0
  fi
  # Con el '|| codigo' y el 'return 0' de despues: el codigo de la ventana no
  # decide nada aqui (es un aviso), pero sin ellos el 'set -e' del instalador
  # se dispara si el usuario pulsa Esc, y se queda SIN preguntar lo de
  # reiniciar, que es justo lo que viene despues.
  local codigo=0
  ventana --title "Instalacion terminada" --backtitle "Titan Linux" --msgbox "${texto}" 24 72 \
    || codigo=$?
  return 0
}

preguntar_reiniciar() {
  [[ "${AUTO}" == "1" ]] && { info "[autopiloto] no se reinicia"; return 0; }
  # El codigo se guarda antes de mirarlo, por lo del 'set -e' (ver 'ventana').
  # Decir 'No' devuelve 1, y sin el '|| codigo=$?' el instalador moria aqui
  # sin llegar a explicar que se puede apagar a mano.
  local codigo=0
  ventana --title "¿Reiniciar?" --backtitle "Titan Linux" --yesno \
 "¿Reiniciar el equipo ahora?

Si todavia tienes cosas del live que quieras guardar, se perderan: el live
va en memoria. En un equipo real, apaga con 'sudo poweroff' y enciende." 12 66 \
    || codigo=$?
  if (( codigo == 0 )); then
    sync
    systemctl reboot
  else
    titulo "Instalacion terminada"
    echo "El equipo NO se reinicia. Puedes apagarlo con:  sudo poweroff"
  fi
  return 0
}
