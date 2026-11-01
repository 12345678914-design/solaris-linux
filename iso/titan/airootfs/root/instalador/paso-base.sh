#!/bin/bash
# ---------------------------------------------------------------------------
# Titan Linux -- paso 3: base del sistema, kernel y GRUB
#
# aqui es donde se descarga de verdad. El instalador ha comprobado antes que
# hay internet, asi que todo lo de pacstrap tiene que poder salir de los repos
# de Arch.
#
# Dos decisiones que no son obvias:
#
#  * El kernel del proyecto (linux-titanlinux) se instala desde un paquete que
#    la propia ISO lleva en /titan-repo. No hay repositorio publico donde
#    bajarlo, y sin el, el sistema instalado arrancaria con el kernel de Arch
#    y se perderia la razon de ser del proyecto. Si el paquete no esta, se
#    instala el de Arch y se avisa.
#
#  * Se genera el GRUB con grub-mkconfig (el de Arch), no con la configuracion
#    de la ISO. La de la ISO lleva rutas del DVD y una memdisk; en el disco
#    instalado se quiere el GRUB de verdad, que es el que arranca en mas
#    maquinas distintas. Se anaden las tres cosas que hacen falta para eso:
#    el arranque por la particion EFI estandar (/EFI/BOOT), el arranque
#    "movible" (por si se cambia de disco), y os-prober para detectar otros
#    sistemas.
# ---------------------------------------------------------------------------

# El /etc/pacman.conf del sistema que se instala.
#
# Tres repos, no dos: multilib hace falta para los juegos (Steam va ahi, y es
# multilib porque arrastra bibliotecas de 32 bits) y para el software de
# Windows. Un equipo de uso normal que no lo tenga se queda sin Steam.
#
# Lo que NO se copia es el repositorio local 'titan' de la ISO: en el disco
# instalado no existe, y dejandolo cada 'pacman -Sy' daria error.
pacman_conf_destino() {
  local destino="$1"
  cat >"${destino}" <<'EOF'
[options]
HoldPkg     = pacman glibc
Architecture = auto
ParallelDownloads = 5
SigLevel    = Required DatabaseOptional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
}

# El kernel propio que lleva la ISO, si lo lleva.
paquete_kernel_propio() {
  local cand dir
  local -a dirs=()
  # Los dos sitios donde puede estar el paquete, en orden: el '/titan-repo' que
  # monta la ISO en el live, y la cache de pacman. La lista viene de una variable
  # para que se pueda COMPROBAR el camino de la reserva (el que se usa cuando el
  # paquete no esta) sin tener el paquete delante: en la maquina donde se
  # desarrolla, el paquete SI esta en la cache, y con los caminos escritos a pelo
  # la comprobacion no llegaria nunca a ese camino.
  #
  # OJO con la lista: NO se puede escribir
  #     ${TITAN_REPO_KERNEL:-"/titan-repo /var/cache/pacman/pkg"}/linux-*.zst
  # Las comillas de dentro del valor por defecto de una expansion SI tienen
  # efecto (protegen el espacio de la particion de palabras), asi que el
  # resultado es UN solo camino con un espacio en medio y el asterisco sin
  # expandir:
  #     /titan-repo /var/cache/pacman/pkg/linux-titanlinux-*.pkg.tar.zst
  # que no existe. Ese fallo se manifesto en la pasada del 28 de septiembre: con
  # el paquete del kernel presente en el '/titan-repo' del live, la funcion decia
  # que no lo encontraba y el instalador caia a la reserva, e instalaba el kernel
  # de Arch (4 FALLO en el informe). Por eso la lista se separa ANTES, con un
  # 'read -a' que parte por espacios lo que tiene que partir, y el glob va con la
  # variable entrecomillada para que se expanda el asterisco y no el espacio.
  read -r -a dirs <<<"${TITAN_REPO_KERNEL:-/titan-repo /var/cache/pacman/pkg}"
  for dir in "${dirs[@]}"; do
    for cand in "${dir}"/linux-titanlinux-*.pkg.tar.zst; do
      [[ -f "${cand}" ]] && { printf '%s' "${cand}"; return 0; }
    done
  done
  return 1
}
# --- lista de paquetes ------------------------------------------------------

# De lo que devuelve genfstab, se queda solo lo que sirve para el disco que se
# esta instalando. Se separa del paso para poder probarla con una salida de
# ejemplo, que es como se ha encontrado que genfstab mete los swaps de todo el
# equipo (ver el comentario de paso_base).
#
#   $1  lo que ha salido de 'genfstab -U'
#   $2  UUID de la particion de swap del disco nuevo, o vacio si no la hay
filtrar_fstab() {
  local texto="$1" uuid_swap="${2:-}"
  awk -F'\t' -v u="UUID=${uuid_swap}" '
    # genfstab pone un comentario con el dispositivo delante de cada linea. Se
    # guarda aparte porque, si la linea que viene es un swap que se quita, el
    # comentario tambien: si no, el fstab acaba con un comentario hablando de
    # un swap que no esta en ninguna parte.
    /^#/ { comentario = $0; next }
    /^[[:space:]]*$/ {
      if (comentario != "") { print comentario; comentario = "" }
      print
      next
    }
    {
      if ($3 ~ /^swap/ && (u == "" || $1 != u)) { comentario = ""; next }
      if (comentario != "") { print comentario; comentario = "" }
      print
    }
    END { if (comentario != "") print comentario }
  ' <<<"${texto}"
}

paquetes_base() {
  # Lo minimo para que un Titan Linux arranque y sea usable. Todos verificados
  # contra las bases de datos de los repos: un nombre mal escrito aqui rompe la
  # instalacion a mitad, con el disco ya particionado.
  #
  # grub, efibootmgr y os-prober TIENEN que estar en esta lista, y no pueden
  # confiar en que los traiga otra cosa:
  #   * arch-install-scripts (version 31) ya NO depende de grub. Antes si, y por
  #     eso instalaba de mas. Ahora, sin 'grub' aqui, el paso de GRUB se muere
  #     con 'grub-install: no se encuentra la orden' DESPUES de haber instalado
  #     todo lo demas, que es el peor sitio posible para descubrirlo.
  #   * un solo paquete 'grub' vale para los dos arranques: en Arch el paquete
  #     'grub' trae /usr/lib/grub/i386-pc, /usr/lib/grub/x86_64-efi y
  #     /usr/lib/grub/i386-efi, y declara 'grub-bios' y 'grub-efi-x86_64' como
  #     proporciona. Los antiguos 'grub-efi-x64' y 'grub-bios' ya no existen.
  #   * efibootmgr es lo que crea la entrada de arranque en el firmware de UEFI.
  #     Sin el, el equipo instala bien pero arranca con lo que hubiera de antes.
  #   * os-prober es lo que detecta otros sistemas ya instalados.
  #   * btrfs-progs trae el hook 'btrfs' de mkinitcpio (/usr/lib/initcpio/
  #     install/50-btrfs). Sin el, el instalador escribe ese hook en el
  #     mkinitcpio.conf del sistema nuevo (que hace falta para montar la raiz) y
  #     mkinitcpio contesta "ERROR: Hook 'btrfs' cannot be found" y sale con
  #     codigo 2: el initramfs sale incompleto y el equipo no arranca. Solo
  #     pasa con el arranque por UEFI, porque en BIOS el initramfs va en el
  #     hueco del MBR y no necesita el hook, asi que es de los fallos que se
  #     ven en un equipo y no en otro.
  #
  # Y aqui NO esta 'linux' (el fallo 31). El kernel del sistema instalado es el
  # del proyecto, que se instala despues desde el paquete propio de la ISO, y el
  # de Arch se queda solo como reserva para cuando ese paquete no este (ver
  # paso_kernel). Con los dos, cada instalacion acababa con DOS kernels
  # ('/usr/lib/modules' con '7.2.7-arch1-1' y '6.18.54-1-titanlinux'), dos
  # 'vmlinuz' en /boot y dos entradas en el menu de GRUB: el usuario ve un
  # kernel que el proyecto no quiere, y el que se arranca es el segundo de la
  # lista en cuanto un hook lo reordena.
  printf '%s' "base base-devel linux-firmware sudo nano git wget curl \
reflector arch-install-scripts grub efibootmgr os-prober btrfs-progs"
}

# Los paquetes que se piden Desktop (base de datos) + extras por escritorio.
paquetes_escritorio() {
  local id="${E[escritorio]}" datos
  datos="$(datos_escritorio "${id}")" || return 1
  # Las cinco variables se nombran todas a proposito: con 'read -r a b c d e',
  # la ultima se lleva el resto de la linea con los separadores dentro, y el
  # visor se colaba en la lista de paquetes como 'evince|12' (y de ahi un
  # paquete llamado '12' que pacstrap no encuentra).
  local paquetes gestor grafico visor espacio
  IFS='|' read -r paquetes gestor grafico visor espacio <<<"${datos}"
  if [[ "${paquetes}" == "ninguno" ]]; then
    printf 'tmux'
    return 0
  fi
  local salida="${paquetes}"
  # Terminal grafico: kitty siempre (decision del proyecto). Para i3 se
  # respetan los que trae de serie, pero kitty tambien se instala.
  local term
  term="$(terminal_escritorio "${id}")"
  [[ -n "${term}" ]] && salida+=" ${term}"
  salida+=" $(complementos_escritorio "${id}")"
  # El visor de PDF que encaja con el escritorio, si no viene ya.
  if [[ -n "${visor}" && " ${paquetes} " != *" ${visor} "* ]]; then
    salida+=" ${visor}"
  fi
  # Red: en el sistema instalado manda NetworkManager, no el systemd-networkd
  # del live. iwd es el que se encarga del wifi sin pedirle nada a NetworkManager.
  salida+=" networkmanager iwd"
  printf '%s' "${salida}"
}

# Los flatpak de las apps elegidas, separados por espacios.
#
# OJO: estas dos funciones se llaman SIEMPRE dentro de $( ), o sea en una
# subshell, asi que no pueden guardar nada en E[]: una asignacion a E aqui se
# perderia al terminar la subshell, y el instalador creeria que no hay flatpak
# que instalar. Por eso la lista la guarda el que llama, con
# 'E[flatpaks]="$(flatpaks_elegidos)"' en su propio shell.
flatpaks_elegidos() {
  local app pkgs salida=""
  for app in ${E[apps]}; do
    pkgs="$(paquete_app "${app}" 2>/dev/null)" || continue
    [[ "${pkgs}" == flatpak:* ]] && salida+="${pkgs#flatpak:} "
  done
  printf '%s' "${salida% }"
}

# Los paquetes de pacman de las apps elegidas.
paquetes_apps() {
  local app pkgs salida="" flatpaks="" p
  for app in ${E[apps]}; do
    pkgs="$(paquete_app "${app}" 2>/dev/null)" || continue
    if [[ "${pkgs}" == flatpak:* ]]; then
      flatpaks+="${pkgs#flatpak:} "
      continue
    fi
    for p in ${pkgs}; do
      salida+="${p} "
    done
  done
  # Si hay flatpak que instalar, hacen falta sus paquetes y el portal, que es
  # lo que permite abrir ficheros o mostrar dialogos desde dentro de la app.
  if [[ -n "${flatpaks}" ]]; then
    salida+="flatpak xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-kde "
    salida+="xdg-desktop-portal-wlr "
  fi
  # El cortafuegos se ofrece con el sistema instalado, pero NO activado:
  # encenderlo sin que el usuario lo decida puede dejarle sin red, y eso no se
  # arregla a distancia. La pantalla final le da el comando.
  if [[ " ${E[apps]}" == *" ufw "* && " ${salida} " != *" ufw "* ]]; then
    salida+="ufw "
  fi
  printf '%s' "${salida% }"
}

# Los tres grupos de paquetes juntos, en una sola lista. Es lo que va a
# pacstrap. Antes de llamarla hay que tener E[flatpaks] puesto.
paquetes_instalar() {
  local -a todos=() todos2=() todos3=()
  local p
  read -r -a todos <<<"$(paquetes_base)"
  read -r -a todos2 <<<"$(paquetes_escritorio)"
  read -r -a todos3 <<<"$(paquetes_apps)"
  todos+=("${todos2[@]}" "${todos3[@]}" tmux)
  # Sin repetir: el mismo paquete dos veces no rompe pacman, pero ensucia el
  # log y hace mas lento el calculo de dependencias.
  local -a unicos=()
  local visto=" "
  for p in "${todos[@]}"; do
    [[ -z "${p}" || "${visto}" == *" ${p} "* ]] && continue
    visto+="${p} "
    unicos+=("${p}")
  done
  # EN UNA SOLA LINEA, separados por espacios. Con una linea por paquete,
  # 'read -a' (que solo lee la primera linea) se quedaria con el primero y
  # pacstrap instalaria unicamente 'base' sin avisar.
  printf '%s ' "${unicos[@]}"
}

# --- los espejos -------------------------------------------------------------
#
# Por que esto existe, que es una historia de dos instalaciones seguidas:
#
# El live traia TRES espejos. En la primera de las dos, uno no resolvia el
# nombre; en la segunda, el geografico de Arch contestaba con 404 a media
# descarga y los otros dos no tenian la version de los paquetes que el propio
# pacman acababa de sincronizar. O sea: la lista entera, la de los tres, dio
# error, y la instalacion se paro a los quince minutos con medio sistema
# descargado.
#
# Con Arch esto pasa todos los dias y por eso casi todos los instaladores
# ejecutan 'reflector' antes de instalar: miden los espejos de verdad y se
# quedan con los rapidos. Aqui no se puede, porque 'reflector' es un programa
# de Python y meter Python en la ISO son 40 MB que no aportan a nada mas.
# Pero la CONSULTA se puede hacer con 'curl', que si esta, y son veinte lineas.
#
# Y no es un adorno: de los diez candidatos que hay abajo, cuatro contestan con
# la version de los paquetes y los demas o no contestan o van atrasados. No se
# sabe cuales de los dos son sin preguntarles uno a uno, y preguntar es
# exactamente lo que hace esto.

# Candidatos a espejo, uno por linea y SIN los comodines de pacman ('$repo',
# '$arch'): para medirlos hay que anadir una ruta real, y con los comodines
# delante la URL que se pide no existe en ningun sitio. La lista la escribe
# customize_airootfs.sh en /etc/pacman.d/mirrorlist.candidatos.
#
# La ruta sale de 'TITAN_CANDIDATOS' para que se pueda cambiar. No es una
# comodidad: 'medir_espjos' usa 'curl' de verdad, y la unica forma de
# comprobarlo sin internet (que es como se comprueba) es darle una lista de
# candidatos de mentira en un directorio de mentira. Con la ruta escrita en el
# codigo, comprobarlo exigiria escribir en /etc del live.
ruta_candidatos() { echo "${TITAN_CANDIDATOS:-/etc/pacman.d/mirrorlist.candidatos}"; }

espejos_candidatos() {
  local archivo
  archivo="$(ruta_candidatos)"
  # En fallo no se imprime NADA por la salida normal, ni siquiera un
  # 'SIN-CANDIDATOS' de cortesia: esta lista se lee con 'mapfile' y lo que se
  # imprima se acaba tomando por un espejo mas. Pasaba: al no existir el
  # fichero, 'SIN-CANDIDATOS' entrava en la lista como si fuera una URL, curl
  # fallaba, y 'medir_espjos' aun asi decia que habia ido bien y escribia un
  # mirrorlist con 'Server = SIN-CANDIDATOS/$repo/os/$arch', que para pacman es
  # un servidor que no existe. El aviso va a la salida de error, que es donde se
  # lee a mano y no se mezcla con la lista.
  if [[ ! -r "${archivo}" ]]; then
    echo "no hay lista de espejos candidatos en ${archivo}" >&2
    return 1
  fi
  # Solo las lineas que empiezan por http, o por file: (que es como se prueban
  # sin red: curl tambien sabe leer 'file://', y asi un 'espejo' puede ser una
  # carpeta de mentira en /tmp). El fichero lleva delante una explicacion, y los
  # comentarios se cuelan en cualquier lectura linea a linea.
  grep -E '^(https?|file)://' "${archivo}" \
    || { echo "en ${archivo} no hay ninguna URL de espejo" >&2; return 1; }
}

# Cuantos se quedan. Cuatro es lo que hace falta: pacman va probando uno por
# uno para cada fichero, asi que con cuatro vivos es practicamente imposible
# que los cuatro esten atrasados a la vez. Menos de tres no cubre un fallo de
# red, y mas de ocho es descargar del doble para no ganar nada: el problema nunca
# ha sido cual es el mas rapido, es que alguno de los primeros no conteste.
espejos_a_quedarse() { echo 4; }

# Cuanto puede tardar un espejo y seguir sirviendo para instalar. OJO a lo que
# mide este numero: NO es lo que tarda en contestar, es lo que tarda en dar UN
# MEGABYTE (vease 'medir_espjos'). Ocho segundos son unos 125 KiB/s, y por
# debajo de eso los 300 MB de un escritorio tardan mas de tres horas.
#
# El limite existe porque "contestar rapido" y "sostener la descarga" son dos
# cosas distintas, y la medicion de antes solo miraba la primera. Pasaba de
# verdad: 'geo.mirror.pkgbuild.com' no es un espejo, es un redirector que
# contesta el '.db.sig' de mil bytes en 0.2 s y luego se queda sin dar un byte
# durante diez segundos cuando ya va por un paquete de cien megas. Media once
# minutos de descarga, ocho errores de pacman ("Operation too slow. Less than 1
# bytes/sec transferred the last 10 seconds") y la instalacion perdida, con el
# disco ya partido. Un espejo que tarda mas que esto no es "el penultimo", es
# uno que va a hacer perder la instalacion, asi que no se usa.
espejos_max_segundos() { echo 8; }

# Ordena lo medido: cada linea es "url segundos", y sale la lista de urls de la
# mas rapida a la mas lenta. Las lineas sin segundos (las que no han podido
# medirse) se quedan AL FINAL y en su orden, porque no se sabe nada de ellas y
# es mejor tenerlas de repuesto que perderlas. Y los que han tardado mas que
# 'espejos_max_segundos' NO salen, salvo que no quede ninguno: mejor un espejo
# lentisimo que una lista vacia, que pacman lee como "no servers configured" y
# que convierte un problema de red en un problema de instalacion.
#
# Es una funcion PURA: no mira la red, no toca ficheros, solo ordena lo que le
# dan. Por eso se puede comprobar con cuatro lineas escritas a mano, sin
# arrancar ninguna maquina virtual. La parte que si necesita la red esta en
# 'medir_espjos', y es la unica que no se puede comprobar asi.
ordenar_espjos() {
  local -a medidos=() sin_medir=()
  local linea url segundos max
  max="$(espejos_max_segundos)"
  while IFS= read -r linea; do
    [[ -z "${linea// /}" ]] && continue
    url="${linea%% *}"
    segundos="${linea#* }"
    # Un tiempo de verdad: los digitos, un punto opcional, y AL MENOS un digito
    # distinto de cero. Lo ultimo importa mas de lo que parece: curl imprime
    # '0.000000' cuando no ha podido descargar nada, y '000' cuando no ha
    # podido ni mirar la URL. Los dos son numeros, asi que una comprobacion
    # normal los aceptaria y los pondria de PRIMEROS: el espejo que no ha
    # contestado seria el que primero se usa. Para quitarlos se borran los
    # ceros y los puntos del valor, y si no queda nada es que era un cero
    # de tiempo de verdad.
    if [[ "${segundos}" =~ ^[0-9]+([.][0-9]+)?$ ]] \
       && [[ -n "${segundos//[0.]/}" ]]; then
      medidos+=("${segundos} ${url}")
    else
      sin_medir+=("${url}")
    fi
  done
  # El descarte del limite va con 'awk' y no con una '[[ ... ]]' porque los
  # tiempos son decimales ('0.35', '12.80') y bash solo compara enteros. Con
  # 'awk' el filtro es el que dice el numero de arriba, sin tener que decidir
  # cuantos decimales se redondean ni si '[[ 0.35 -le 8 ]]' es lo que parece.
  local rapidos=""
  if ((${#medidos[@]})); then
    rapidos="$(printf '%s\n' "${medidos[@]}" | awk -v max="${max}" '$1 <= max')"
  fi
  if [[ -z "${rapidos}" && "${#medidos[@]}" -gt 0 ]]; then
    rapidos="$(printf '%s\n' "${medidos[@]}" | sort -s -n -k1,1 | head -1)"
  fi
  # El numero va delante para que 'sort' ordene por el, y '-s' para que dos
  # tiempos iguales conserven el orden de entrada: sin '-s', 'sort' es libre de
  # devolver los empates en cualquier orden, y una lista de espejos que cambia
  # de un dia a otro sin motivo no se puede comparar con la de ayer.
  [[ -n "${rapidos}" ]] && printf '%s\n' "${rapidos}" | sort -s -n -k1,1 | cut -d' ' -f2-
  ((${#sin_medir[@]})) && printf '%s\n' "${sin_medir[@]}"
  return 0
}

# Rota la lista de espejos n posiciones hacia abajo: la segunda pasa a ser la
# primera, la tercera la segunda, y la ultima se va al final. La escribe en la
# SALIDA ESTANDAR y no en el fichero, que es lo que la hace pura y comprobable
# con tres lineas escritas a mano.
#
# Para que sirve: reintentar la descarga con los mismos espejos y en el mismo
# orden es reintentar exactamente lo mismo que ya ha fallado. Girando la lista,
# el segundo intento empieza por el que no se uso la primera vez.
rotar_espjos() { # LISTA N
  local lista="$1" n="$2"
  [[ -s "${lista}" ]] || return 1
  local -a lineas=()
  mapfile -t lineas <"${lista}"
  local total="${#lineas[@]}"
  ((total > 0)) || return 1
  # 'n' se reduce con '$(( ))' y no con '((n %= total))' a proposito: la forma
  # con '(( ))' devuelve 1 cuando el resultado es cero, y con 'set -e' eso es
  # salir del instalador. Pasaba: rotar una lista de cuatro espejos cuatro
  # veces (justo lo que hace el tercer reintento) mataba el instalador.
  n=$(( n % total ))
  # Ni un 'if' con 'n == 0' ni un 'return 0' aqui: girar un numero de veces
  # multiplo de la longitud TIENE que devolver la lista igual, y un retorno
  # temprano se lleva la lista consigo. Pasaba, y era el peor fallo posible: en
  # 'pacstrap_con_reintentos' lo que sale de aqui se escribe encima del
  # mirrorlist, asi que un giro de cero dejaba el mirrorlist VACIO, que es
  # exactamente lo que pacman responde con 'no servers configured for repository
  # core'. Se arregla solo letting el bucle copiar la lista en el mismo orden.
  local -a nuevas=()
  local i
  for ((i = 0; i < total; i++)); do
    nuevas+=("${lineas[$(( (i + n) % total ))]}")
  done
  printf '%s\n' "${nuevas[@]}"
  return 0
}

# Pregunta a cada candidato cuanto tarda en contestar un fichero pequeno, y
# escribe el mirrorlist bueno en el fichero que se le pase. Los que no
# contestan se quedan fuera: un 404 o un tiempo de espera no es un tiempo, y
# una linea con un tiempo que no es un numero se va al final (vease
# 'ordenar_espjos'), no a la cabeza fingiendo que tardo cero.
#
# OJO al formato de lo que se escribe. Este fichero lo lee pacman como un
# mirrorlist mas ('Include = ...' en el conf), y un mirrorlist NO es una lista de
# URLs: cada linea tiene que ser 'Server = ' con los comodines '$repo' y '$arch'
# detras. Con URLs sueltas, que es lo que devuelve 'ordenar_espjos' porque para
# ordenar no le hace falta mas, pacman no encuentra ningun servidor y responde
# "no servers configured for repository 'core'": exactamente el error que paso
# con la lista del live al principio, pero despues de haber estado midiendo diez
# espejos con todo el interes del mundo.
#
# Por eso el fichero sale con 'Server = ' delante y los comodines detras, y por
# eso el paso final no es un '>' a secas.
#
# El fichero que se mide es un MEGABYTE del principio del 'core.db', con un
# rango ('-r 0-1048575'), no entero: son 9 MB por espejo, y con diez espejos
# serian 90 MB de descargas que no instalan nada.
#
# Y el rango no es un ahorro, es el ARREGLO. Medir un '.db.sig' de mil bytes
# mide lo que tarda un espejo en CONTESTAR, y contestar rapido no es lo mismo
# que sostener una descarga: 'geo.mirror.pkgbuild.com' es un redirector que
# devuelve el kilobyte en 0.2 s y a partir de ahi se atasca, y pacman mata la
# descarga con "Operation too slow. Less than 1 bytes/sec transferred the last
# 10 seconds". Con un megabyte por delante, lo que se mide es de verdad lo que
# importa: cuantos segundos cuesta el primer cacho de algo de tamano real, que
# es la misma pregunta que se le hace al espejo tres minutos despues con un
# paquete de cien megas. Un '.db.sig' no puede contestar a esa pregunta ni en
# broma: mil bytes no dan tiempo a que nadie se atasque.
#
# El '-f' tambien esta aqui por un motivo parecido: sin el, un 404 (un espejo
# que ha quitado un repositorio, o una URL mal escrita) devuelve el error con
# codigo de salida cero y 'curl' lo mide como 'ha contestado en 0.1 s'. Con
# '-f', un 404 es un 404 y el espejo se queda fuera.
medir_espjos() {
  local destino="$1"
  local -a lineas=()
  local -a candidatos=()
  local url segundos lectura bytes
  # La lista se lee ANTES de preguntar nada. Con un '< <(espejos_candidatos)'
  # el codigo de fallo se pierde (es otra shell la que corre), asi que solo
  # se podria mirar si ha salido algo, y 'algo' incluye un mensaje de error
  # impreso por pantalla. Aqui no: si no hay lista, no hay lineas y se sale
  # con 1 sin haber escrito nada.
  mapfile -t candidatos < <(espejos_candidatos)
  ((${#candidatos[@]})) || return 1
  for url in "${candidatos[@]}"; do
    [[ -z "${url}" ]] && continue
    lectura="$(curl -s -f -o /dev/null -w '%{time_total} %{size_download}' \
      --max-time 25 --connect-timeout 6 -r 0-1048575 \
      "${url}/core/os/x86_64/core.db" 2>/dev/null)" || lectura=""
    segundos="${lectura%% *}"
    bytes="${lectura##* }"
    # curl no imprime nada si falla del todo (ni de red ni de DNS). Entonces el
    # tiempo es una cadena vacia, que no es un numero, y esta linea se queda al
    # final en vez de colocarse la primera por tratar de ser un cero.
    #
    # Y se mira tambien cuantos bytes han entrado. Un espejo que contesta con
    # un fichero vacio (o con cero bytes y codigo de salida cero) NO ha
    # servido el megabyte, y su tiempo no dice nada: lo unico que se cronometra
    # es lo que tarda en pasar por la red un fichero de cero megas, que es
    # cero segundos.
    if [[ -z "${segundos}" || "${segundos}" == "0.000000" ]] \
       || [[ ! "${bytes}" =~ ^[0-9]+$ ]] || ((bytes < 1)); then
      segundos="sin-respuesta"
    fi
    lineas+=("${url} ${segundos}")
  done
  ((${#lineas[@]})) || return 1
  ordenar_espjos <<<"$(printf '%s\n' "${lineas[@]}")" \
    | head -n "$(espejos_a_quedarse)" \
    | sed 's#^#Server = #; s#$#/$repo/os/$arch#' >"${destino}"
  [[ "$(wc -l <"${destino}")" -ge 1 ]] || return 1
  return 0
}

# Cambia el conf de pacman para que use la lista de espejos MEDIDA en vez de la
# del live. Devuelve 1 (y no toca el conf) si la lista medida no existe o esta
# vacia: sin espejos medidos, lo correcto es seguir con la del live.
#
# Esta parte es una funcion aparte, y con razon: es la que decide si lo que se
# ha medido se usa de verdad o se queda mirandose. Si estuviera dentro de
# 'paso_base', la unica forma de comprobarla seria instalar un sistema entero
# entero, o leer el texto del script y fiarse de que el texto dice lo que dice.
# Asi se puede comprobar con un conf de mentira y una lista de mentira.
#
# El 'Include' se anade si no estaba (por si el conf no lo traia), pero nunca se
# duplica: pacman lee cada 'Include' y, si el mismo mirrorlist aparece dos
# veces, descarga cada fichero dos veces.
apuntar_espjos_medidos() { # CONF LISTA_MEDIDA
  local conf="$1" medidos="$2"
  [[ -s "${medidos}" ]] || return 1
  [[ -f "${conf}" ]] || return 1
  # El ancla del final ($) no es cosmetico: sin ella, una linea
  # 'Include = /etc/pacman.d/mirrorlist.candidatos' tambien casaria con el
  # patron de 'mirrorlist' y se quedaria apuntando a la lista de candidatos en
  # vez de a la medida, que es justo lo contrario de lo que se quiere.
  sed -i "s#^Include = /etc/pacman.d/mirrorlist\$#Include = ${medidos}#" "${conf}"
  grep -qx "Include = ${medidos}" "${conf}" || \
    printf 'Include = %s\n' "${medidos}" >>"${conf}"
  return 0
}

# Cuantos intentos se hacen de la descarga antes de rendirse. Tres es lo
# justo: uno para el caso normal, y dos para cuando un espejo se ha quedado
# tonto a media descarga.
#
# Y el motivo de que hagan falta mas de uno es el del fallo de verdad: con
# la descarga entera y sin reintentos, un solo espejo atascado tira once
# minutos de descarga y la instalacion entera. El reintento es barato porque
# pacstrap deja en la cache del destino lo que ya ha bajado: el segundo intento
# solo va a por lo que faltaba.
reintentos_pacstrap() { echo 3; }

# Ejecuta la descarga dandole occasion de reintentar, y girando la lista de
# espejos entre intento e intento.
#
# Por que una funcion y no un 'for' suelto en 'paso_base': porque asi se puede
# comprobar sin internet, sin disco y sin instalar nada. Se le pasa un
# 'pacstrap' de mentira delante en el PATH que falla dos veces y acierta la
# tercera, y se mira cuantas veces ha sido llamado y en que orden han quedado
# los espejos. Un 'for' escrito directamente en 'paso_base' no se podria
# comprobar: habria que ejecutar el paso entero.
#
#   pacstrap_con_reintentos LISTA_MEDIDA LOG MAX -- ARGS_DE_PACSTRAP
#
# 'MAX' es el numero de intentos (0 o menos = no hay reintento, se llama una vez
# y ya). Con '--' de separador, que es lo que pone el que llama, para que los
# argumentos de pacstrap puedan empezar por un guion sin que se confundan con
# los de esta funcion.
pacstrap_con_reintentos() { # LISTA_MEDIDA LOG MAX -- ARGS...
  local lista="$1" log="$2" max="$3"
  shift 3
  [[ "${1:-}" == "--" ]] && shift
  ((${#} > 0)) || return 1
  local intento
  for ((intento = 1; intento <= max; intento++)); do
    if ((intento > 1)); then
      # El '-s' del medio no es una tonteria: lo que se pone encima del
      # mirrorlist tiene que existir y tener algo dentro. Un giro que devolviera
      # una lista vacia dejaria el mirrorlist vacio, y pacman responderia 'no
      # servers configured for repository core' con el disco ya partido. Mejor
      # reintentar con la lista como estaba.
      if rotar_espjos "${lista}" $((intento - 1)) >"${lista}.girado" 2>/dev/null \
         && [[ -s "${lista}.girado" ]] \
         && mv -f "${lista}.girado" "${lista}" 2>/dev/null; then
        info "intento ${intento} de ${max}: se prueban los espejos en otro orden"
      else
        info "intento ${intento} de ${max}: no hay lista de espejos que girar"
      fi
    fi
    {
      printf '\n===== intento %s de %s: %s =====\n' "${intento}" "${max}" "$(date +%H:%M:%S)"
    } >>"${log}" 2>/dev/null
    if "$@" >>"${log}" 2>&1; then
      return 0
    fi
    if ((intento < max)); then
      aviso "la descarga ha fallado (intento ${intento} de ${max}); se reintenta"
    fi
  done
  return 1
}

# --- el paso ----------------------------------------------------------------

paso_base() {
  local conf="/tmp/titan-pacman.conf"
  pacman_conf_destino "${conf}"

  # Los espejos se miden ANTES de descargar nada, y se escriben en una lista
  # propia que es la que usa pacman durante la instalacion. El mirrorlist del
  # live se queda como estaba: es la lista de candidatos, con diez, y no tiene
  # sentido cambiarla desde el instalador (y si algo va mal, sigue ahi la
  # original).
  #
  # Si la medicion falla (sin red todavia, sin curl, o una lista de candidatos
  # que no existe) se avisa y se sigue con la lista del live, que es lo de
  # siempre: medir es una mejora, no un requisito. Un instalador que se niega a
  # instalar porque no ha podido medir los espejos es peor que uno que instala
  # con lo que hay.
  local ml_medidos="/tmp/titan-mirrorlist"
  if medir_espjos "${ml_medidos}"; then
    info "espejos medidos; se instala con estos: $(tr '\n' ' ' <"${ml_medidos}")"
  else
    aviso "no se han podido medir los espejos; se usa la lista del live"
  fi
  if [[ -s "${ml_medidos}" ]]; then
    # El conf de pacman apunta a la lista medida. Al sistema nuevo se le copia
    # la del live, que es la que se ha estado probando durante toda la
    # instalacion y la que tiene mas Probabilidad de funcionar luego.
    apuntar_espjos_medidos "${conf}" "${ml_medidos}" || \
      aviso "no se ha podido apuntar el conf a la lista de espejos medidos"
  fi

  # El mirrorlist que el live ya tiene reparado (el de Arch viene con todos los
  # espejos comentados) se copia tal cual al sistema nuevo.
  local raiz="${DESTINO}"
  mkdir -p "${raiz}/etc/pacman.d"
  install -m 0644 /etc/pacman.d/mirrorlist "${raiz}/etc/pacman.d/mirrorlist"
  [[ -f /etc/pacman.d/mirrorlist.commented ]] && \
    install -m 0644 /etc/pacman.d/mirrorlist.commented "${raiz}/etc/pacman.d/mirrorlist.commented"

  # Paquetes, en un solo array: base, escritorio, apps, y lo que siempre hace
  # falta para que Titan Linux sea Titan Linux (tmux, el historial de la
  # consola).
  local -a unicos=()
  read -r -a unicos <<<"$(paquetes_instalar)"
  E[total_paquetes]="${#unicos[@]}"
  info "paquetes a instalar: ${#unicos[@]}"
  info "paquetes: ${unicos[*]}"
  guardar_estado

  # -K: keyring de pacman nuevo y con las llaves publicas de Arch (obligatorio
  # para verificar las firmas). -M: no copiar el mirrorlist del host, que ya
  # se ha puesto a mano. -C: el pacman.conf de mas arriba, sin el repo local.
  # Lo que escupe pacstrap (decenas de MB) va a un log aparte y no a la
  # pantalla: en modo autopilot, o por el puerto serie, la consola tiene que
  # poder leerse. Si algo falla, al final de ese log esta el motivo.
  if ! pacstrap_con_reintentos "${ml_medidos}" "${LOG}.pacstrap" \
       "$(reintentos_pacstrap)" -- \
       pacstrap -K -M -C "${conf}" "${raiz}" "${unicos[@]}"; then
    error "pacstrap ha fallado. Sus ultimas lineas:"
    while IFS= read -r linea; do error "  ${linea}"; done < <(tail -n 15 "${LOG}.pacstrap")
    return 1
  fi

  # fstab con los UUID de verdad, que es lo que sobrevive a un cambio de
  # orden de discos. Se genera con los montajes de ahora, que es como
  # recomienda arch-install-scripts.
  #
  # OJO: genfstab mete en el fstab TODOS los swap de la maquina, sin mirar si
  # estan debajo del destino. El bloque de los swap esta aparte, leyendo
  # /proc/swaps, y no pasa por el filtro del resto. En el live eso arrastra el
  # swap del propio live (zram, o la particion de la ISO) al sistema instalado,
  # donde ese dispositivo no existira nunca: un fallo en cada arranque.
  # Asi que aqui se dejan solo las lineas que sirven para el disco nuevo:
  # la particion de swap si se pidio, y ninguna si se eligio zram o nada.
  local fstab_swap=""
  if [[ -n "${E[part_swap]:-}" && -b "${E[part_swap]}" ]]; then
    fstab_swap="$(blkid -s UUID -o value "${E[part_swap]}" 2>/dev/null)"
  fi
  local lineas_fstab
  lineas_fstab="$(filtrar_fstab "$(genfstab -U "${raiz}" 2>/dev/null)" "${fstab_swap}")"
  {
    printf '# Generado por el instalador de Titan Linux.\n'
    printf '# Los UUID son de verdad, para que el disco pueda cambiar de orden.\n'
    printf '%s\n' "${lineas_fstab}"
  } >>"${raiz}/etc/fstab"
  info "fstab generado: $(grep -cv '^#' "${raiz}/etc/fstab") lineas"

  return 0
}

# El kernel: el del proyecto si la ISO lo trae, el de Arch si no.
paso_kernel() {
  local raiz="${DESTINO}" pkg
  if pkg="$(paquete_kernel_propio)"; then
    # OJO aqui, que es una trampa de las que no avisan. El paquete NO va a
    # "${raiz}/tmp", aunque en el papel ese es el sitio donde se meten las cosas
    # dentro de un chroot: arch-chroot (y tambien pacstrap) montan un tmpfs
    # NUEVO encima de /tmp del sistema destino. Lo que se copia ahi desde fuera
    # se queda debajo de ese tmpfs y, dentro del chroot, no existe: pacman
    # contestaba "could not find or read package" con el fichero de 163 MB
    # ahi sentado, en el disco, a la vista de todos.
    #
    # Lo mismo pasa con /run y con /dev. Por eso el paquete va a la cache de
    # pacman, que ademas es donde pacman deja los paquetes de todos modos.
    local destino_pkg="${raiz}/var/cache/pacman/pkg"
    local nombre_pkg
    nombre_pkg="$(basename "${pkg}")"
    info "instalando el kernel del proyecto desde ${pkg}"
    mkdir -p "${destino_pkg}"
    install -m 0644 "${pkg}" "${destino_pkg}/${nombre_pkg}"
    arch-chroot "${raiz}" pacman -U --noconfirm --needed \
      "/var/cache/pacman/pkg/${nombre_pkg}" \
      || { error "no se ha podido instalar linux-titanlinux"; return 1; }
    rm -f "${destino_pkg}/${nombre_pkg}"
    E[kernel]="linux-titanlinux"
    return 0
  fi
  aviso "la ISO no lleva el paquete linux-titanlinux; se instala el kernel de Arch"
  arch-chroot "${raiz}" pacman -S --noconfirm --needed linux
  E[kernel]="linux"
  return 0
}

# --- GRUB -------------------------------------------------------------------

# El /etc/default/grub del sistema instalado. Lo que NO va aqui, y por que:
#   cow_spacesize  es de la ISO (el live escribe en RAM); en el disco no.
#   video=NxM       no va ni en el live ni en el disco: manda el firmware.
#                   En QEMU, run-qemu.sh detecta el monitor y ajusta la
#                   tarjeta virtual; no se escribe una resolucion fija.
paso_grub() {
  local raiz="${DESTINO}"
  local kernel_initrd=""
  if [[ "${E[kernel]}" == "linux-titanlinux" ]]; then
    kernel_initrd="vmlinuz-linux-titanlinux initramfs-linux-titanlinux.img"
  else
    kernel_initrd="vmlinuz-linux initramfs-linux.img"
  fi
  # El initrd por defecto de Arch (el modo 'mkinitcpio' todos los kernels).
  cat >"${raiz}/etc/default/grub" <<EOF
# Escrito por el instalador de Titan Linux.
#
# NOTA: aqui NO hay video=NxM. La ISO en vivo tampoco lo lleva: en QEMU la
# resolucion se detecta en run-qemu.sh y se pasa a la tarjeta virtual; en el
# sistema instalado manda el firmware.
#
# NOTA: aqui NO hay cow_spacesize. Ese es el espacio de RAM donde la ISO en
# vivo guarda lo que se instala; en el disco no tiene sentido.
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Titan Linux"
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3"
GRUB_CMDLINE_LINUX="console=tty0 console=ttyS0,115200n8"
GRUB_DISABLE_SUBMENU=y
GRUB_TERMINAL_OUTPUT="gfxterm console"
GRUB_GFXMODE=auto
GRUB_ENABLE_CRYPTODISK=y
EOF

  # Detectar otros sistemas operativos ya instalados. Solo informativo, pero es
  # una de las cosas que hace GRUB 'mas compatible'.
  cat >"${raiz}/etc/default/os-prober" <<'EOF'
DISABLE_OS_PROBER=false
EOF
  arch-chroot "${raiz}" systemctl enable os-prober.service 2>/dev/null || true

  # El ':-0' es por si se llega aqui sin haber pasado por el paso de disco. No
  # deberia pasar, pero con 'set -u' basta un '${E[algo]}' sin valor para que
  # muera el instalador entero, y seria por no haber puesto bien el GRUB.
  if [[ "${E[modo_arranque]:-0}" == "1" ]]; then
    local disco="${E[disco]}"
    # '--no-nvram' por una razon concreta: 'grub-install' en UEFI, si no se le
    # dice lo contrario, registra EN EL FIRMWARE una entrada de arranque con el
    # nombre del '--bootloader-id'. Y aqui, despues, se crea otra a proposito
    # con 'efibootmgr' para poder poner el nombre con espacio y elegir el disco
    # a mano. Sin '--no-nvram' las dos cosas juntas dejan DOS entradas de Titan
    # en el menu de arranque del firmware, que es lo que se vio: la del
    # 'grub-install' (TitanLinux) y la del 'efibootmgr' (Titan Linux).
    arch-chroot "${raiz}" grub-install --target=x86_64-efi \
      --efi-directory=/boot/efi --bootloader-id=TitanLinux --no-nvram --recheck \
      || { error "grub-install (UEFI) ha fallado"; return 1; }
    # El arranque 'movible' (EFI/BOOT/BOOTX64.EFI) es el que encuentra la
    # BIOS de muchos portatiles, y el que se usa si la particion EFI cambia
    # de numero. Son dos instalaciones del mismo grub, no un problema.
    arch-chroot "${raiz}" grub-install --target=x86_64-efi \
      --efi-directory=/boot/efi --removable --no-nvram --recheck \
      || aviso "no se ha podido instalar el arranque movible"
    arch-chroot "${raiz}" grub-mkconfig -o /boot/grub/grub.cfg
    # Entrada en el firmware: sin esto el equipo arranca de otras veces.
    arch-chroot "${raiz}" efibootmgr --create --disk "${disco}" --part 1 \
      --label "Titan Linux" --loader '\EFI\TitanLinux\grubx64.efi' \
      || aviso "no se ha podido crear la entrada de arranque en el firmware"
  else
    local disco="${E[disco]}"
    arch-chroot "${raiz}" grub-install --target=i386-pc --recheck --modules="part_gpt part_msdos fat ext2 btrfs luks" "${disco}" \
      || { error "grub-install (BIOS) ha fallado"; return 1; }
    arch-chroot "${raiz}" grub-mkconfig -o /boot/grub/grub.cfg
  fi

  # El kernel del proyecto se llama vmlinuz-linux-titanlinux, no
  # vmlinuz-<release>, y grub-mkconfig lo detecta por el nombre. Se comprueba
  # que ha salido en el grub.cfg: si no, el equipo arranca pero con el kernel
  # equivocado, y eso no se ve hasta que se reinicia.
  if [[ "${E[kernel]}" == "linux-titanlinux" ]]; then
    if ! grep -q "linux-titanlinux" "${raiz}/boot/grub/grub.cfg"; then
      aviso "el grub.cfg no menciona el kernel del proyecto; revisa /boot"
    fi
  fi
  E[grub]="grub"
  return 0
}
