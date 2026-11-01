#!/bin/bash
# ---------------------------------------------------------------------------
# Comprobacion de la logica del instalador, SIN QEMU y SIN disco.
#
# El instalador decide que paquetes instalar a partir de tres tablas editables
# (escritorios, tipos de uso y catalogo de apps) y de las elecciones del
# usuario. Esa parte es texto y bucles, y se puede mirar en el host en un
# segundo. Lo que NO se puede mirar aqui es si el sistema arranca: para eso
# estan las pruebas en QEMU (verify/titan-verify.py).
#
# Que mira, en orden:
#   0. que cada fila de cada tabla tenga sus columnas. Un campo de mas o de
#      menos no da error: se cuela en la lista de paquetes y pacstrap falla mas
#      tarde, con el disco ya particionado. Por eso se cuenta.
#   1. que no haya ids repetidos y que cada app apunte a algo real.
#   2. que cada nombre de paquete exista de verdad en los repos de Arch.
#   3. que de cada tipo de uso salga la lista de apps que se espera.
#   4. que el reparto entre pacman y la tienda de apps (flatpak) sea correcto.
#   5. que la lista final de paquetes no tenga repetidos ni se le escape nada.
#
# Uso:  distro/verify/comprobar-instalador.sh
#
# Para lo de los repos: no usa la base de datos del sistema, sino una propia en
# un directorio temporal CON multilib. Sin multilib, 'steam' y 'lib32-gamemode'
# aparecen como inexistentes, y si existen.
#
# Que necesita del host, y por que (todoInstalled se comprueba contra las
# herramientas de verdad, no contra dobles: un doble que dice lo que el
# comprobador quiere oir no comprueba nada):
#   root            para 'sgdisk' y 'btrfs' sobre un disco de mentira, y para
#                   poder crear el arbol de ficheros que pacman usa en la
#                   comprobacion 2.
#   gptfdisk        'sgdisk', que es lo que usa el paso de disco del instalador.
#   btrfs-progs     'btrfs', para los subvolumenes, tambien del paso de disco.
#   pacman ( Arch ) para resolver el grafo de dependencias de los repos.
#
#   sudo bash distro/verify/comprobar-instalador.sh
# ---------------------------------------------------------------------------
set -uo pipefail

AQUI="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DISTRO="$(dirname -- "${AQUI}")"
RAIZ="${DISTRO}/iso/titan/airootfs/root"

# Contexto minimo: las librerias del instalador usan el log y el modo autopilot.
AUTO=1
TITAN_SILENCIO=1
LOG="${TMPDIR:-/tmp}/comprobar-instalador.log"
export AUTO TITAN_SILENCIO LOG

# shellcheck source=/dev/null
source "${RAIZ}/instalador/lib-comun.sh"
# shellcheck source=/dev/null
source "${RAIZ}/instalador/lib-escritorios.sh"
# shellcheck source=/dev/null
source "${RAIZ}/instalador/lib-apps.sh"
# shellcheck source=/dev/null
source "${RAIZ}/instalador/paso-base.sh"
source "${RAIZ}/instalador/paso-chroot.sh"
source "${RAIZ}/instalador/paso-cerrar.sh"
# shellcheck source=/dev/null
source "${RAIZ}/instalador/paso-disco.sh"

fallos=0

# --- bases de datos de los repos, en un directorio propio --------------------

CONF_TEST="$(mktemp -t titan-pacman.XXXXXX.conf)"
DB_TEST="$(mktemp -d -t titan-pacdb.XXXXXX)"
trap 'rm -rf -- "${CONF_TEST}" "${DB_TEST}"' EXIT

cat >"${CONF_TEST}" <<EOF
[options]
Architecture = auto
ParallelDownloads = 5
SigLevel = Required DatabaseOptional
DBPath = ${DB_TEST}
[core]
Include = /etc/pacman.d/mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist
[multilib]
Include = /etc/pacman.d/mirrorlist
EOF

echo "== preparando las bases de datos de los repos =="
if [[ ! -w "${DB_TEST}" ]] || ! pacman -Sy --config "${CONF_TEST}" \
     --noconfirm --disable-download-timeout >/dev/null 2>&1; then
  echo "AVISO: no se han podido descargar las bases de datos."
  echo "       Los nombres de paquete no se comprobaran. El resto, si."
  DB_TEST=""
fi

# existe PAQUETE -> 0 si es un paquete o un grupo de los repos de Arch
existe() {
  [[ -n "${DB_TEST}" ]] || return 0   # sin comprobacion, no fallar por eso
  pacman --config "${CONF_TEST}" --dbpath "${DB_TEST}" -Si "$1" >/dev/null 2>&1 && return 0
  pacman --config "${CONF_TEST}" --dbpath "${DB_TEST}" -Sg "$1" >/dev/null 2>&1
}

# es_grupo PAQUETE -> 0 si NO es un paquete, sino un grupo. Un grupo se instala
# igual de bien con pacstrap, pero conviene saberlo: no aparece en 'pacman -Si'.
es_grupo() {
  [[ -n "${DB_TEST}" ]] || return 1
  ! pacman --config "${CONF_TEST}" --dbpath "${DB_TEST}" -Si "$1" >/dev/null 2>&1
}

ok()   { printf '  OK    %s\n' "$1"; }
nota() { printf '  nota  %s\n' "$1"; }
falla(){ printf '  FALLO %s\n' "$1"; fallos=$((fallos + 1)); }

comprobar() { # comprobar QUE ESPERADO OBTENIDO
  if [[ "$2" == "$3" ]]; then ok "$1"; else
    falla "$1"; printf '        esperado: %s\n        obtenido: %s\n' "$2" "$3"
  fi
}

contiene() { # contiene QUE TROZO LISTA
  if [[ " $3 " == *" $2 "* ]]; then ok "$1"; else
    falla "$1 (falta '$2')"; printf '        lista: %s\n' "$3"
  fi
}

no_contiene() {
  if [[ " $3 " == *" $2 "* ]]; then
    falla "$1 (no deberia traer '$2')"; printf '        lista: %s\n' "$3"
  else ok "$1"; fi
}

# --- 0. columnas de cada fila -------------------------------------------------

echo
echo "== 0. columnas de cada fila =="
# ESCRITORIOS: id nombre frase paquetes gestor grafico visor espacio  (7 sep)
for linea in "${ESCRITORIOS[@]}"; do
  n="$(printf '%s' "${linea}" | tr -cd '|' | wc -c)"
  [[ "${n}" -eq 7 ]] || falla "escritorio con ${n} separadores: ${linea%%|*}"
done
ok "las ${#ESCRITORIOS[@]} filas de escritorio tienen 8 campos"
# CATALOGO: id nombre que_hace paquete categoria usos  (5 sep)
for linea in "${CATALOGO[@]}"; do
  n="$(printf '%s' "${linea}" | tr -cd '|' | wc -c)"
  [[ "${n}" -eq 5 ]] || falla "app con ${n} separadores: ${linea%%|*}"
done
ok "las ${#CATALOGO[@]} filas de app tienen 6 campos"
# USOS: id nombre frase apps  (3 sep)
for linea in "${USOS[@]}"; do
  n="$(printf '%s' "${linea}" | tr -cd '|' | wc -c)"
  [[ "${n}" -eq 3 ]] || falla "uso con ${n} separadores: ${linea%%|*}"
done
ok "las ${#USOS[@]} filas de uso tienen 4 campos"
# Y de verdad, que datos_escritorio devuelva las 5 columnas que se leen luego.
for e in gnome kde niri i3 ninguno; do
  d="$(datos_escritorio "${e}")"
  n="$(printf '%s' "${d}" | tr -cd '|' | wc -c)"
  [[ "${n}" -eq 4 ]] || falla "datos_escritorio ${e} devuelve $((n + 1)) campos: [${d}]"
done
ok "datos_escritorio devuelve las 5 columnas"

# --- 1. ids y paquetes de cada fila -------------------------------------------

echo
echo "== 1. ids sin repetir y paquetes que existen =="
ids=()
for linea in "${CATALOGO[@]}"; do ids+=("${linea%%|*}"); done
dups="$(printf '%s\n' "${ids[@]}" | sort | uniq -d)"
[[ -n "${dups}" ]] && falla "apps con el mismo id: ${dups}" \
                 || ok "las ${#ids[@]} apps tienen id unico"
eids=()
for linea in "${ESCRITORIOS[@]}"; do eids+=("${linea%%|*}"); done
dups="$(printf '%s\n' "${eids[@]}" | sort | uniq -d)"
[[ -n "${dups}" ]] && falla "escritorios con el mismo id: ${dups}" \
                 || ok "los ${#eids[@]} escritorios tienen id unico"
comprobar "el primer escritorio es gnome" "gnome" "${eids[0]}"
comprobar "el escritorio por defecto es gnome" "gnome" "$(escritorio_por_defecto)"

for linea in "${CATALOGO[@]}"; do
  id="${linea%%|*}"
  paq="$(paquete_app "${id}")" || { falla "${id}: app_datos no encuentra la fila"; continue; }
  [[ -n "${paq}" ]] || { falla "${id}: sin paquete"; continue; }
  [[ "${paq}" == flatpak:* ]] && continue
  for p in ${paq}; do
    if ! existe "${p}"; then
      falla "${id}: el paquete '${p}' NO existe en Arch (ni es grupo)"
    elif es_grupo "${p}"; then
      nota "${id}: '${p}' es un grupo de pacman, no un paquete"
    fi
  done
done

for linea in "${ESCRITORIOS[@]}"; do
  e="${linea%%|*}"
  paq="$(campo "${linea}" 4)" grafico="$(campo "${linea}" 6)"
  if [[ "${paq}" == "ninguno" ]]; then
    [[ "${grafico}" == "no" ]] || falla "${e}: dice 'ninguno' pero es grafico"
    continue
  fi
  [[ "$(campo "${linea}" 5)" == "ninguno" ]] && \
    falla "${e}: sin gestor de sesion para un escritorio grafico"
  for p in ${paq} $(complementos_escritorio "${e}"); do
    existe "${p}" || falla "${e}: el paquete '${p}' NO existe en Arch (ni es grupo)"
  done
done

for linea in "${USOS[@]}"; do
  u="${linea%%|*}"
  for app in $(campo_uso "${linea}" 4); do
    linea_app "${app}" >/dev/null 2>&1 || \
      falla "${u}: recomienda '${app}', que no esta en el catalogo"
  done
done
ok "cada tipo de uso solo recomienda apps del catalogo"

# --- 2. de tipo de uso a apps -------------------------------------------------

echo
echo "== 2. tipo de uso -> apps recomendadas =="
E=()
E[usos]="ordinario"
E[apps]="$(app_recomendadas "${E[usos]}")"
contiene "ordinario trae firefox" "firefox" "${E[apps]}"
contiene "ordinario trae thunderbird" "thunderbird" "${E[apps]}"
contiene "ordinario trae vlc" "vlc" "${E[apps]}"
no_contiene "ordinario NO trae libreoffice" "libreoffice" "${E[apps]}"
E[apps]="$(app_recomendadas "desarrollo")"
contiene "desarrollo trae git" "git" "${E[apps]}"
contiene "desarrollo trae gh" "gh" "${E[apps]}"
no_contiene "desarrollo NO trae firefox" "firefox" "${E[apps]}"
E[apps]="$(app_recomendadas "oficina")"
contiene "oficina trae libreoffice" "libreoffice" "${E[apps]}"
E[apps]="$(app_recomendadas "ordinario oficina")"
contiene "dos usos a la vez: firefox" "firefox" "${E[apps]}"
contiene "dos usos a la vez: libreoffice" "libreoffice" "${E[apps]}"
dups="$(printf '%s\n' ${E[apps]} | sort | uniq -d)"
[[ -n "${dups}" ]] && falla "apps repetidas al combinar usos: ${dups}" \
                 || ok "sin apps repetidas al combinar usos"

for linea in "${USOS[@]}"; do
  u="${linea%%|*}"
  a="$(app_recomendadas "${u}")"
  [[ " ${a} " == *" ufw "* ]] || falla "${u}: no recomienda el cortafuegos"
  for app in ${a}; do
    linea_app "${app}" >/dev/null 2>&1 || \
      falla "${u}: '${app}' no esta en el catalogo"
  done
  printf '        %-11s -> %s\n' "${u}" "${a}"
done
ok "los ${#USOS[@]} tipos de uso recommendan apps validas y el cortafuegos"

# --- 3. apps -> paquetes ------------------------------------------------------

echo
echo "== 3. apps -> paquetes (pacman y tienda de apps) =="
E=()
E[apps]="firefox libreoffice mpv ufw"
E[escritorio]="gnome"
E[flatpaks]="$(flatpaks_elegidos)"
salida="$(paquetes_apps)"
contiene "firefox va a la tienda de apps" "org.mozilla.firefox" "${E[flatpaks]}"
contiene "instala libreoffice-fresh" "libreoffice-fresh" "${salida}"
contiene "instala mpv" "mpv" "${salida}"
contiene "instala ufw" "ufw" "${salida}"
contiene "instala el paquete flatpak" "flatpak" "${salida}"
[[ " ${E[flatpaks]} " == *" lib"* ]] && falla "un flatpak acabo en la lista de pacman" \
                                     || ok "los flatpak no van a pacman"
E[apps]=""
E[flatpaks]="$(flatpaks_elegidos)"
[[ -z "${E[flatpaks]}" ]] || falla "hay flatpak sin elegir apps"
[[ "$(paquetes_apps)" == *" flatpak "* ]] && falla "instala flatpak sin apps de la tienda" \
                                        || ok "sin apps no hay flatpak que instalar"

# --- 4. lista final de paquetes -----------------------------------------------

echo
echo "== 4. paquetes por escritorio y lista final =="
for e in gnome niri i3 ninguno; do
  E=()
  E[escritorio]="${e}"
  E[apps]="mpv"
  p="$(paquetes_escritorio)"
  printf '        %-9s %s\n' "${e}" "${p}"
  if [[ "${e}" == "ninguno" ]]; then
    comprobar "${e}: solo el historial" "tmux" "${p}"
  else
    contiene "${e}: kitty" "kitty" "${p}"
    contiene "${e}: NetworkManager" "networkmanager" "${p}"
  fi
done

E=()
E[escritorio]="gnome"
E[apps]="mpv ufw"
E[flatpaks]=""
read -r -a fin <<<"$(paquetes_instalar)"
printf '        %s paquetes para instalar\n' "${#fin[@]}"
contiene "la lista final incluye el historial" "tmux" "${fin[*]}"
contiene "la lista final incluye kitty" "kitty" "${fin[*]}"
# El kernel de Arch NO puede estar en la lista (fallo 31). Con el, cada
# instalacion acababa con dos kernels en /usr/lib/modules, dos vmlinuz en /boot y
# dos entradas en el menu de GRUB. El kernel del sistema instalado lo pone
# paso_kernel(), con el paquete propio de la ISO, y el de Arch se queda solo como
# reserva para cuando ese paquete no este (eso si lo comprueba la seccion 6n, con
# TITAN_REPO_KERNEL).
#
# OJO con la forma de la comprobacion: 'no_contiene' separa con ESPACIOS, y no un
# 'grep linux' suelto, porque 'linux-firmware', 'linux-titanlinux' y
# 'linux-api-headers' contienen la palabra 'linux' y darian un falso positivo que
# haria pasar la comprobacion con el kernel de Arch puesto.
no_contiene "la lista final NO trae el kernel de Arch" "linux" "${fin[*]}"
dups="$(printf '%s\n' "${fin[@]}" | sort | uniq -d)"
[[ -n "${dups}" ]] && falla "paquetes repetidos: ${dups}" || ok "sin paquetes repetidos"
for p in "${fin[@]}"; do
  existe "${p}" || falla "la lista final trae '${p}', que no existe en Arch"
done
ok "los ${#fin[@]} paquetes de la lista final existen en los repos"

# --- 5. formato de las pantallas ---------------------------------------------

echo
echo "== 5. formato de las pantallas =="
# Los textos NO pueden llevar '|': es el separador de las opciones de dialog.
# Si uno lo lleva, el menu se parte mal y no se ve un error claro.
for linea in "${ESCRITORIOS[@]}" "${CATALOGO[@]}" "${USOS[@]}"; do
  id="${linea%%|*}"
  for (( i = 2; i <= 6; i++ )); do
    v="$(campo_de_linea "${linea}" "${i}")"
    [[ "${v}" == *"|"* ]] && falla "${id}: el campo ${i} lleva un '|' de dentro: [${v}]"
  done
done
ok "ningun texto de las tablas lleva un '|' de dentro"
# Y que parte_opciones devuelva tantas partes como filas hay, con textos enteros.
parte_opciones "$(opciones_app)"
declare -a _ids=("${_opc_ids[@]}") _textos=("${_opc_textos[@]}")
comprobar "opciones_app se parte en el numero de apps" "${#CATALOGO[@]}" "${#_ids[@]}"
malos=0
for t in "${_textos[@]}"; do
  [[ -n "${t}" ]] || malos=$((malos + 1))
done
comprobar "todos los textos de las apps vienen enteros" "0" "${malos}"
# Que el texto de una app con espacios llegue entero: 'que_hace' es el campo 3.
for a in firefox libreoffice gnome-disk-utility; do
  i=0
  for id in "${_ids[@]}"; do
    if [[ "${id}" == "${a}" ]]; then
      [[ "${_textos[i]}" == *" - "* ]] || \
        falla "${a}: el texto se ha partido: [${_textos[i]}]"
      break
    fi
    i=$((i + 1))
  done
done
ok "los textos con espacios y dos puntos llegan enteros al menu"

op="$(opciones_app)"
[[ "${op}" == "firefox:"* ]] && ok "opciones_app empieza por el id de la app" \
                           || falla "opciones_app no empieza por el id"
[[ "${op}" == *"||"* ]] && falla "opciones_app ha metido un separador de mas" \
                         || ok "opciones_app no mete separadores raros"
comprobar "opciones_app: una opcion por app" "${#CATALOGO[@]}" \
          "$(tr '|' '\n' <<<"${op}" | wc -l)"
op_e="$(opciones_escritorio)"
comprobar "opciones_escritorio: una opcion por escritorio" "${#ESCRITORIOS[@]}" \
          "$(tr '|' '\n' <<<"${op_e}" | wc -l)"
comprobar "cada opcion de escritorio es 'id:nombre'" "${#ESCRITORIOS[@]}" \
          "$(tr '|' '\n' <<<"${op_e}" | grep -c ':')"
op_u="$(opciones_uso)"
comprobar "opciones_uso: una opcion por uso" "${#USOS[@]}" \
          "$(tr '|' '\n' <<<"${op_u}" | wc -l)"

# --- 5b. el disco: como se leen las particiones -------------------------------

echo
echo "== 5b. como se leen las particiones =="
# El nombre de la particion cambia segun como se llame el disco. Con la regla
# antigua (preguntar solo por nvme y mmcblk) un disco NVMe de verdad daba
# '/dev/nvme0n12', que no existe.
comprobar "particion de un disco SATA"        "/dev/sda1"     "$(ruta_particion /dev/sda 1)"
comprobar "particion de un disco NVMe"         "/dev/nvme0n1p1" "$(ruta_particion /dev/nvme0n1 1)"
comprobar "particion de un disco NVMe, la 12"  "/dev/nvme0n1p12" "$(ruta_particion /dev/nvme0n1 12)"
comprobar "particion de una SD"                "/dev/mmcblk0p1" "$(ruta_particion /dev/mmcblk0 1)"
comprobar "particion de un disco virtio"       "/dev/vda3"     "$(ruta_particion /dev/vda 3)"
comprobar "particion de un disco loop"         "/dev/loop0p2"  "$(ruta_particion /dev/loop0 2)"

# Y lo mas importante: leer la tabla de particiones que imprime sgdisk. La
# salida se pega aqui tal cual la da gptfdisk, para no depender de un disco.
# El fallo que se busca aqui es contar las columnas a pelo: el TAMANO son dos
# palabras ("19.0 GiB"), asi que el codigo no es el campo quinto.
tabla_sgdisk="Disk /dev/nvme0n1: 1000215216 sectors, 512.0 GiB
Sector size (logical/physical): 512/512 bytes
Disk identifier (GUID): 5A18ED33-0AF2-44F3-8BFD-4A1AA9537F02
Partition table holds up to 128 entries
Main partition table begins at sector 2 and ends at sector 33
First usable sector is 34, last usable sector is 1000214529
Partitions will be aligned on 2048-sector boundaries
Total free space is 2014 sectors (1007.0 KiB)

Number  Start (sector)    End (sector)  Size       Code  Name
   1            2048          2099199   1024.0 MiB  EF00  Titan boot
   2         2099200         20991999      9.0 GiB  8200  Titan swap
   3         20992000       1000214529   376.9 GiB  8300  Titan root
  10      9999999999      10000000000      1.0 MiB  EF02  Titan bios-boot"
comprobar "sgdisk: lee la particion de arranque (EF00)" "1" \
          "$(printf '%s\n' "${tabla_sgdisk}" | numero_de_particion EF00)"
comprobar "sgdisk: lee la de swap (8200)"     "2" \
          "$(printf '%s\n' "${tabla_sgdisk}" | numero_de_particion 8200)"
comprobar "sgdisk: lee la de raiz (8300)"     "3" \
          "$(printf '%s\n' "${tabla_sgdisk}" | numero_de_particion 8300)"
comprobar "sgdisk: lee la de bios_grub (EF02)" "10" \
          "$(printf '%s\n' "${tabla_sgdisk}" | numero_de_particion EF02)"
comprobar "sgdisk: un codigo que no esta, no inventa nada" "" \
          "$(printf '%s\n' "${tabla_sgdisk}" | numero_de_particion 8E00)"
# Y que no se confunda con las lineas de arriba de la tabla, que tambien
# llevan numeros de cuatro digitos.
tabla_raro="Disk /dev/sda: 1000215216 sectors
Partition table holds up to 128 entries
First usable sector is 2048, last usable sector is 1000214529
8300 is mentioned here as text

Number  Start (sector)  End (sector)  Size       Code  Name
   1            2048          2099199   1024.0 MiB  EF00  Titan boot"
comprobar "sgdisk: no lee codigos de los parrafos de arriba" "1" \
          "$(printf '%s\n' "${tabla_raro}" | numero_de_particion EF00)"
comprobar "sgdisk: no lee codigos sueltos de un parrafo" "" \
          "$(printf '%s\n' "${tabla_raro}" | numero_de_particion 8300)"

# --- 6. dialog: opciones y dibujado real -------------------------------------

echo
echo "== 6. ventanas (dialog) =="
if ! command -v dialog >/dev/null 2>&1; then
  echo "  (dialog no esta instalado en este equipo: no se comprueba nada)"
else
  # Una opcion mal escrita (--yesbutton en vez de --yes-button) no da error de
  # bash: dialog dice "unknown option", no abre la ventana, y el instalador
  # sigue como si nada. Aqui se ve.
  while read -r op; do
    [[ -n "${op}" ]] || continue
    if dialog "${op}" </dev/null 2>&1 | head -1 | grep -q "unknown option"; then
      falla "dialog no conoce la opcion '${op}'"
    fi
  done < <(grep -hoE -- '--[a-z][a-z-]+' "${RAIZ}/install.sh" "${RAIZ}"/instalador/*.sh \
           | grep -vE '^--(titulo|texto|autopiloto|respuestas|solo|help|si|no|pendientes)$' \
           | sort -u)
  ok "todas las opciones de dialog del codigo existen"

  # Y que cada llamada lleve su TIPO DE VENTANA (--yesno, --msgbox, --inputbox,
  # --menu...). Sin el, dialog imprime su ayuda y sale con codigo 0: no hay
  # error visible, y en el caso de las ventanas de "se va a BORRAR el disco" eso
  # hacia que se borrase sin que nadie hubiera contestado que si.
  tipos=(--msgbox --yesno --infobox --inputbox --passwordbox --textbox
         --menu --checklist --radiolist --gauge)
  sin_tipo=0
  while IFS= read -r llamada; do
    [[ -n "${llamada}" ]] || continue
    tiene=0
    for t in "${tipos[@]}"; do
      [[ "${llamada}" == *" ${t} "* || "${llamada}" == *" ${t}="* ]] && tiene=1
    done
    if (( ! tiene )); then
      falla "llamada a ventana sin tipo de ventana: ${llamada}"
      sin_tipo=1
    fi
  done < <(tr '\n' ' ' < <(grep -h -A8 'ventana \\$' "${RAIZ}"/instalador/*.sh "${RAIZ}/install.sh" 2>/dev/null) \
           | sed 's/\\//g' | tr -s ' ' | grep -oE 'ventana .*' | sort -u)
  (( sin_tipo )) || ok "toda llamada a ventana lleva su tipo de ventana"

  # Que NINGUNA ventana se abra llamando a dialog directamente. El instalador
  # va con 'set -e' y dialog devuelve 1 cuando el usuario contesta 'No' y 255
  # con Esc: una llamada sin mirar su codigo de salida mataba el instalador
  # entero. En el resumen, pulsar 'Cancelar' acababa con codigo 1 (fallo) en vez
  # de 3 (cancelado), y el usuario veia 'la instalacion se ha parado'.
  # Para eso esta el envoltorio 'ventana'.
  #
  # Hay UNA llamada directa permitida: la de reserva, al FINAL de 'ventana()',
  # que es la que se abre cuando la grafica no esta. Antes se le hacia sitio
  # por el texto de la linea de al lado ('ventana() { dialog'), que era
  # casualidad y no regla: en cuanto la funcion se reescribio y la llamada bajo
  # a su propia linea, el filtro dejo de cubrirla y esta comprobacion se puso
  # en rojo avisando de un dialog que si que estaba en su sitio. Un filtro que
  # depende de como este escrita la linea de al lado no es un filtro, es una
  # coincidencia. Ahora se saca el CUERPO de la funcion con 'awk' y se mira que
  # no quede ninguna llamada fuera, y ademas que dentro haya exactamente una.
  cuerpo_ventana="$(awk '/^ventana\(\) \{/{d=1} d{print} d&&/^\}/{exit}' \
    "${RAIZ}/instalador/lib-comun.sh")"
  if [[ -z "${cuerpo_ventana}" ]]; then
    falla "no se ha encontrado la funcion ventana() en lib-comun.sh"
  else
    dentro="$(printf '%s\n' "${cuerpo_ventana}" |
      grep -cE '(^|[^_[:alnum:]-])dialog +"\$@"')"
    comprobar "dentro de ventana(), la llamada a dialog de reserva es una" "1" \
      "${dentro}"
  fi
  lib_sin_ventana="${TMPDIR:-/tmp}/titan-lib-sin-ventana-$$.sh"
  otros="$(mktemp -t titan-libs.XXXXXX)"
  awk '/^ventana\(\) \{/{d=1; next} d&&/^\}/{d=0; next} !d{print}' \
    "${RAIZ}/instalador/lib-comun.sh" >"${lib_sin_ventana}"
  : >"${otros}"
  for f in "${RAIZ}"/instalador/*.sh "${RAIZ}/install.sh"; do
    [[ "${f}" == "${RAIZ}/instalador/lib-comun.sh" ]] && continue
    printf '%s\n' "${f}" >>"${otros}"
  done
  # Y la copia sin 'ventana()' tambien entra en la lista, con '-H' para que el
  # aviso diga de que fichero sale cada llamada y se pueda ir a mirarla.
  printf '%s\n' "${lib_sin_ventana}" >>"${otros}"
  # Solo se quitan las lineas que SON comentarios (las que empiezan por '#') y
  # las dos menciones que no son llamadas: el 'command -v dialog' (que mira si
  # esta el programa) y 'ventana-gui' (el frontal). La lista de palabras que
  # hubo antes ('dialog que', 'dialog para', ...) se ha quitado entera: con el
  # cuerpo de 'ventana()' ya sacado no hacia falta, y mientras siga ahi, cada
  # palabra de la lista es una llamada real de la que nadie se enteraria.
  directas="$(xargs -a "${otros}" grep -nH -E '(^|[^_[:alnum:]-])dialog' \
              2>/dev/null |
              grep -vE 'command -v dialog|ventana-gui' |
              grep -vE '^[^:]+:[0-9]+: *#')"
  rm -f "${otros}" "${lib_sin_ventana}"
  if [[ -n "${directas}" ]]; then
    while IFS= read -r d; do
      # La copia sin 'ventana()' es la que mas se parece, pero el numero de
      # linea no es el del fichero de verdad (le faltan las de la funcion que se
      # ha quitado), asi que el aviso lo dice: si se busca por ahi, la llamada
      # esta unas lineas mas abajo en el original.
      d="${d//"${lib_sin_ventana}"/instalador/lib-comun.sh (linea de la copia)}"
      [[ -n "${d}" ]] && falla "llamada directa a dialog (usa ventana()): ${d}"
    done <<<"${directas}"
  else
    ok "ninguna ventana se abre con dialog directamente: todas por ventana()"
  fi

  # Y que cada ventana se abra de verdad. Sin ahi no se ve nada, asi que se
  # lanzan dentro de un terminal falso y se mira que dibujen su titulo.
  if command -v script >/dev/null 2>&1; then
    dibuja="${TMPDIR:-/tmp}/titan-menus-$$.sh"
    cat >"${dibuja}" <<'DIBUJO'
#!/bin/bash
export AUTO=0 TITAN_SILENCIO=1 LOG=/tmp/titan-dibujar.log
export TERM=xterm LANG=es_ES.UTF-8
RAIZ="${1:?}"
source "${RAIZ}/instalador/lib-comun.sh"
source "${RAIZ}/instalador/lib-escritorios.sh"
source "${RAIZ}/instalador/lib-apps.sh"
source "${RAIZ}/instalador/menus.sh"
source "${RAIZ}/instalador/paso-base.sh"
E=()
E[usos]="ordinario oficina"
E[escritorio]="gnome"
E[apps]="$(app_recomendadas "${E[usos]}")"
E[disco]="/dev/vda"; E[fs]="btrfs"; E[swap]="zram"
E[locale]="es_ES.UTF-8"; E[teclado]="es"; E[zona_horaria]="Europe/Madrid"
E[hostname]="titan"; E[usuario]="isai"
E[arranque]="UEFI"; E[modo_arranque]="efi"
E[luks]="no"; E[cifrado]="no"; E[bluetooth]="si"; E[confirmar_borrado]="si"
E[total_paquetes]="125"
"$2"
DIBUJO
    chmod 755 "${dibuja}"
    # nombre de la ventana -> una palabra que tiene que salir dibujada
    menus=("menu_tipo_uso:Para\ que" "menu_escritorio:Escritorio" \
           "menu_apps:Aplicaciones" "menu_cuentas:Nombre" \
           "menu_arranque:Arranque" "menu_resumen:Instalar")
    for entrada in "${menus[@]}"; do
      fn="${entrada%%:*}"
      esperado="${entrada#*:}"
      esperado="${esperado//\\ / }"
      salida="$(timeout 5 script -qec "bash ${dibuja} ${RAIZ} ${fn}" /dev/null 2>&1 || true)"
      # Los colores van en la salida como secuencias de escape, y dialog
      # mete una entre la 'I' y el resto de una etiqueta de boton: el texto
      # '<Instalar>' sale como 'I<esc>[...nstalar'. Buscando en crudo no se
      # encuentra nunca, aunque la ventana este bien pintada. Por eso primero
      # se quitan los escapes y luego se busca.
      limpio="$(sed -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' -e 's/\x1b[()][B0]//g' \
                   -e 's/\x1b[=>]//g' <<<"${salida}" | tr -d '\r')"
      if grep -q "unknown option\|Expected\|found extra\|not found" <<<"${limpio}"; then
        falla "${fn}: dialog se queja (mira el log del verificador)"
      elif ! grep -q "${esperado}" <<<"${limpio}"; then
        falla "${fn}: no se dibuja el titulo '${esperado}'"
      else
        ok "${fn}: se dibuja"
      fi
    done
    # 'dibuja' NO se borra aqui: la seccion 6c lo vuelve a usar con un dialog
    # de mentira para mirar los argumentos que recibe. Se borra al final de
    # 6c.
  else
    echo "  (sin 'script' no se puede dibujar: se saltar)"
  fi
fi

# --- 6c. el vector de argumentos que recibe dialog, de verdad ---------------
#
# Se ejecuta cada ventana con un dialog de mentira que solo escribe los
# argumentos que recibe, y se mira el vector. Esto caza dos formas de fallo que
# el dibujado de la seccion 6 solo cazaba por casualidad:
#
#   1. dialog DEJA de leer opciones en cuanto ve el tipo de ventana. Una opcion
#      puesta despues (--defaultno, --yes-label...) se pierde en silencio: la
#      ventana sale con los valores de fabrica y el aviso de dialog se va a la
#      salida de error, que el codigo tira. Medido:
#        dialog --yesno t 12 50 --defaultno --yes-label X   -> < Yes > < No >
#        dialog --defaultno --yes-label X --yesno t 12 50   -> <X>  y <No>
#   2. Una opcion de --checklist son TRES campos (etiqueta, texto, on/off). Con
#      dos, dialog dice 'Expected 3 arguments, found extra 1' y no abre nada.
#      Y como el error va a la salida de error, la pantalla se queda en negro
#      sin decir nada.
echo
echo "== 6c. los argumentos que recibe dialog =="
espia="${TMPDIR:-/tmp}/titan-dialog-espia-$$"
mkdir -p "${espia}"
cat >"${espia}/dialog" <<'ESPIA'
#!/bin/bash
# El dialog de mentira: no dibuja nada, solo apunta lo que le pasan.
printf '%s\0' "$@" >"${TITAN_ESPIA}"
exit 1
ESPIA
chmod 755 "${espia}/dialog"

# Ventanas que se pueden lanzar sin tener el resto del recorrido hecho.
espiar_ventana() { # espiar_ventana NOMBRE_DE_LA_FUNCION
  local fn="$1" salida
  salida="$(PATH="${espia}:${PATH}" TITAN_ESPIA="${espia}/args" AUTO=0 \
            TITAN_SILENCIO=1 LOG="${espia}/log" \
            timeout 10 bash "${dibuja}" "${RAIZ}" "${fn}" 2>&1 || true)"
  if [[ ! -s "${espia}/args" ]]; then
    return 1
  fi
  # El vector se separa por NUL y SOLO por NUL: el texto de la caja tiene
  # saltos de linea dentro, y si se partiese tambien por ellos, un solo
  # argumento contaria como varios y el recuento de campos saldria mal.
  mapfile -t -d '' vector <"${espia}/args"
  rm -f "${espia}/args"
  local -a tipo=()
  local i primero=""
  for i in "${!vector[@]}"; do
    case "${vector[i]}" in
      --msgbox|--yesno|--infobox|--inputbox|--passwordbox|--textbox|--gauge|--menu|--checklist|--radiolist)
        tipo+=("${vector[i]}")
        [[ -n "${primero}" ]] || primero="${i}"
        ;;
      --*)
        # Una opcion despues del tipo de ventana es una opcion perdida. Da igual
        # el tipo: el problema es de orden, no de ventana.
        if [[ -n "${primero}" && "${i}" -gt "${primero}" ]]; then
          falla "${fn}: la opcion '${vector[i]}' va DESPUES de '${tipo[0]}', y dialog no la lee"
          return 2
        fi
        ;;
    esac
  done
  if [[ -z "${primero}" ]]; then
    return 1
  fi
  # Cuantos campos van despues de la geometria: en un --checklist son de tres
  # en tres, y en un --menu de dos en dos.
  # Si la funcion abre varias ventanas, la que manda para contar campos es la
  # ULTIMA (la que se ha quedado abierta).
  local widget="${tipo[-1]}" campos
  if [[ "${widget}" == "--checklist" || "${widget}" == "--radiolist" ]]; then
    # ... texto, alto, ancho, alto-lista  = 4 campos
    campos=$(( ${#vector[@]} - primero - 1 - 4 ))
    if (( campos < 0 || campos % 3 != 0 )); then
      falla "${fn}: ${widget} con ${campos} campos de opcion (hace falta un numero par de tags); son de tres en tres: etiqueta, texto, on/off"
      return 2
    fi
  fi
  return 0
}

mal_orden=0
sin_ventana=0
for fn in menu_tipo_uso menu_escritorio menu_apps menu_cuentas menu_arranque \
          menu_resumen; do
  espiar_ventana "${fn}"
  case $? in
    0) ;;
    1) falla "${fn}: no se pudo espiar; la ventana no llega a abrirse con el camino de pruebas"
       sin_ventana=$(( sin_ventana + 1 )) ;;
    2) mal_orden=$(( mal_orden + 1 )) ;;
  esac
done
(( mal_orden )) || ok "ninguna opcion de dialog va detras del tipo de ventana"
(( mal_orden || sin_ventana )) || ok "las 6 ventanas llegan a abrirse con los argumentos correctos"
rm -f "${dibuja:-}"
rm -rf "${espia}"

# --- 6d. lo que se ejecuta DENTRO del sistema instalado ---------------------
#
# El instalador copia el sistema con 'pacstrap' a /mnt y luego configura ese
# sistema con 'arch-chroot /mnt ...'. Una orden que se ejecute en el live
# creyendo que esta en el destino no da ningun error visible: sale con codigo
# 0, el instalador sigue, y el efecto se pierde o se aplica donde no toca. Ya ha
# pasado de verdad: la clave de root se ponia con 'chpasswd' SIN arch-chroot, de
# modo que desbloqueaba el root del LIVE (con la clave que el usuario acababa de
# escribir) y dejaba el root del sistema instalado bloqueado, sin la contrasena
# que el propio instalador prometo para arreglar cosas desde una consola de
# rescate.
#
# Se comprueba linea a linea que toda orden de las que MODIFICAN el sistema
# vaya dentro de 'arch-chroot'. Tres cosas que hay que tener en cuenta para no
# avisar de cosas que no son fallos:
#
#   * lo que va entre comillas no es una orden. 'E[ufw]="instalado-sin-activar"'
#     y 'error "mkinitcpio ha fallado"' no ejecutan nada, asi que primero se
#     vacian las comillas y se busca en lo que queda.
#   * lo que va dentro de un heredoc es el TEXTO de un fichero que se escribe en
#     el destino, no codigo que se ejecute aqui (el envoltorio de scrollback
#     lleva dentro un 'systemctl is-active').
#   * hay ordenes que si tocan el live y estan bien ahi: reiniciar la maquina al
#     terminar. Por eso 'systemctl' solo cuenta cuando lo que se le pasa es
#     'enable', 'disable', 'mask' o 'set-default' (activar servicios), no
#     'reboot' ni 'is-active'.
echo
echo "== 6d. lo que se ejecuta dentro del sistema instalado =="
modifican=(
  chpasswd useradd usermod groupadd gpasswd visudo
  locale-gen update-desktop-database update-alternatives
  grub-install grub-mkconfig efibootmgr mkinitcpio
  flatpak ufw timedatectl
)
# Los subcomandos de 'systemctl' que cambian algo del sistema instalado.
sistema_activa='(enable|disable|mask|unmask|preset|set-default)'
# quedan_cadena LINEA ABIERTA -> estado tras leer la linea: 0 si la linea deja
# una cadena abierta, 1 si la cierra. Solo se cuentan las comillas dobles, que
# es como el instalador escribe los textos largos ('texto+=" ... "'): dentro de
# una cadena doble una comilla simple es un caracter normal, y al reves pasa lo
# mismo, asi que contar las de tipo simple daria falsos positivos.
quedan_cadena() {
  local linea="$1" abierto="$2" ch i n="${#1}"
  for (( i = 0; i < n; i++ )); do
    ch="${linea:i:1}"
    # Una barra invertida escapa el caracter siguiente, que ya no cuenta.
    if [[ "${ch}" == '\' ]]; then
      (( i++ ))
      continue
    fi
    [[ "${ch}" == '"' ]] && abierto=$(( 1 - abierto ))
  done
  printf '%d' "${abierto}"
}

fuga=""
for fichero in "${RAIZ}"/instalador/paso-chroot.sh "${RAIZ}"/instalador/paso-cerrar.sh \
               "${RAIZ}"/instalador/paso-titan.sh; do
  [[ -f "${fichero}" ]] || continue
  nombre_lib="$(basename "${fichero}")"
  # Los patrones van en variables: escritos dentro de '[[ ]]', '^[[:space:]]*#'
  # se lee como el cierre ']]' de la prueba y descoloca el analisis.
  regex_comentario='^[[:space:]]*#'
  regex_asignacion='^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*\['
  regex_activar="systemctl[[:space:]]+${sistema_activa}([[:space:]]|$)"
  terminador=""
  # Un texto puede ocupar varias lineas: 'texto+=" ... "' abre la cadena en una
  # linea y la cierra tres lineas mas abajo. Lo que va dentro es texto, no una
  # orden, asi que tambien hay que carry el control de eso.
  dentro_doble=0
  while IFS= read -r linea; do
    # Dentro de un heredoc no se ejecuta nada de lo que pone.
    if [[ -n "${terminador}" ]]; then
      [[ "${linea}" == "${terminador}" ]] && terminador=""
      continue
    fi
    if [[ "${linea}" =~ \<\<-?[\'\"]?([A-Za-z_][A-Za-z0-9_]*)[\'\"]?[[:space:]]*$ ]]; then
      terminador="${BASH_REMATCH[1]}"
      continue
    fi
    # El estado de la cadena se lleva FUERA de la cuenta aritmetica: dentro de
    # '$(( ))' las comillas no se interpretan como en una orden, y se descoloca.
    # Mira el estado ANTES de leer la linea: si la linea empieza dentro de un
    # texto de varias lineas, es texto entero, incluida la linea que lo cierra.
    dentro_antes="${dentro_doble}"
    dentro_doble="$(quedan_cadena "${linea}" "${dentro_doble}")"
    (( dentro_antes )) && continue
    [[ "${linea}" =~ ${regex_comentario} ]] && continue
    [[ "${linea}" =~ ${regex_asignacion} ]] && continue
    # 'arch-chroot /mnt ...' es justo lo que se busca.
    [[ "${linea}" == *"arch-chroot"* ]] && continue
    # Escribir un fichero del destino con la ruta completa tambien vale.
    [[ "${linea}" == *'${r}'* || "${linea}" == *'${raiz}'* || "${linea}" == *'${DESTINO}'* ]] && continue
    # Y lo que de verdad se busca: la orden, sin lo que va entre comillas.
    limpia="$(sed -e "s/'[^']*'//g" -e 's/"[^"]*"//g' <<<"${linea}")"
    for t in "${modifican[@]}"; do
      if [[ "${limpia}" =~ (^|[^_[:alnum:]-])${t}([^_[:alnum:]-]|$) ]]; then
        fuga+="${nombre_lib}: ${linea}"$'\n'
        break
      fi
    done
    [[ "${limpia}" =~ ${regex_activar} ]] && fuga+="${nombre_lib}: ${linea}"$'\n'
  done <"${fichero}"
done
if [[ -n "${fuga}" ]]; then
  while IFS= read -r mala; do
    [[ -n "${mala}" ]] && falla "se ejecuta fuera del sistema instalado: ${mala}"
  done <<<"${fuga}"
else
  ok "toda orden que modifica el sistema va dentro de arch-chroot"
fi


# --- 6b. funciones que abren una ventana: su codigo de salida -----------------
#
# Una funcion que acaba en una llamada a ventana se queda con el codigo de
# dialog: 0 al pulsar Aceptar, 1 al pulsar No, 255 con Esc. Si ademas se
# llama sin comprobar nada (que es lo normal en un aviso) y el instalador va
# con 'set -e', pulsar Esc mata el instalador: se queda a medias y sin
# explicacion. Asi que toda funcion que abra una ventana tiene que acabar
# devolviendo algo de forma explicita.
echo
echo "== 6b. funciones con ventana: el codigo de salida =="
sin_return=""
for fichero in "${RAIZ}"/instalador/*.sh "${RAIZ}/install.sh"; do
  nombre_lib="$(basename "${fichero}")"
  while IFS= read -r mala; do
    [[ -n "${mala}" ]] && sin_return+="${nombre_lib}:${mala}"$'\n'
  done < <(awk '
    /^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{/ {
      nombre = $1; sub(/\(\).*/, "", nombre)
      dentro = 1; tiene_ventana = 0; ultima = ""
      next
    }
    dentro && /^}/ {
      if (tiene_ventana && ultima !~ /^(return|exit|fi|done|\}|.*\|\|)/) print nombre
      dentro = 0
      next
    }
    dentro {
      if ($0 ~ /(^|[^_[:alnum:]-])(ventana|dialog)[ "]/) tiene_ventana = 1
      linea = $0
      sub(/^[[:space:]]+/, "", linea)
      if (linea != "" && linea !~ /^#/) ultima = linea
    }
  ' "${fichero}")
done
if [[ -n "${sin_return}" ]]; then
  while IFS= read -r mala; do
    [[ -n "${mala}" ]] && falla "abre una ventana y no termina con un return explicito: ${mala}"
  done <<<"${sin_return}"
else
  ok "toda funcion que abre una ventana termina con un return explicito"
fi

# --- 6e. el autopilot: sin ventanas y sin teclear ----------------------------
#
# El autopilot es lo que deja instalar en una maquina virtual sin nadie delante.
# Se activa con '--autopiloto', y hay una trampa en como se propaga: install.sh
# exporta AUTO=1, se come sus argumentos con 'shift', y solo entonces carga los
# modulos con 'source'. Si el modulo vuelve a poner AUTO a cero (porque al
# cargarlo $1 ya no es '--autopiloto', porque no queda ninguno), el instalador
# arranca en modo manual: abre la ventana de dialog del tipo de uso y se queda
# esperando a que alguien pulse 'Aceptar'. No da ningun error, no sale con ningun
# codigo raro, y la comprobacion automatica se queda ahi colgada hasta que se
# acaba el tiempo. Un fallo invisible: de los que no se ven si no se prueba.
#
# Se comprueba lo mismo que hace install.sh y en el mismo orden: consumir los
# argumentos, exportar AUTO, cargar el modulo, y ver que AUTO sigue siendo 1.
echo
echo "== 6e. el autopilot =="
AUTOPILOTO_LIB="${RAIZ}/instalador/lib-comun.sh"
autopiloto_al_cargar() {   # autopilot_al_cargar ARGS...
  AUTO=0 TITAN_LIB="${AUTOPILOTO_LIB}" bash -c '
    set -euo pipefail
    AUTO=0
    RESPUESTAS=""
    while (( $# )); do
      case "$1" in
        --autopiloto) AUTO=1 ;;
        --respuestas) RESPUESTAS="${2:-}"; shift ;;
      esac
      shift
    done
    export AUTO
    source "${TITAN_LIB}"
    printf "%s" "${AUTO}"
  ' _ "$@" 2>/dev/null || printf 'ERROR'
}
if [[ "$(autopiloto_al_cargar --autopiloto --respuestas /tmp/ficticio)" == "1" ]]; then
  ok "'install.sh --autopiloto' deja el autopilot encendido en los modulos"
else
  falla "'install.sh --autopiloto' apaga el autopilot: se abren ventanas y no hay quien pulse"
fi
if [[ "$(autopiloto_al_cargar)" == "0" ]]; then
  ok "sin '--autopiloto' el instalador sigue preguntando a la persona"
else
  falla "sin '--autopiloto' el instalador se creeria que hay alguien delante"
fi

# Y la consecuencia de verdad: con el autopilot encendido, ninguna de las
# preguntas llama a dialog. Se mide con un dialog de espia propio (el de la
# seccion 6c se borra al terminar ella), y se prueban LOS DOS sentidos: con
# autopilot no puede abrirse nada, y sin autopilot tiene que abrirse algo. Si
# solo se mirase el primer caso, este comprobador pasaria igual con el autopilot
# roto del todo.
espia_auto="${TMPDIR:-/tmp}/titan-dialog-espia-auto-$$"
mkdir -p "${espia_auto}"
cat >"${espia_auto}/dialog" <<'ESPIA_AUTO'
#!/bin/bash
# El dialog de mentira: no dibuja nada, solo apunta que le han llamado.
printf '%s\0' "$@" >"${TITAN_ESPIA}"
exit 1
ESPIA_AUTO
chmod 755 "${espia_auto}/dialog"

preguntas_autopiloto="${TMPDIR:-/tmp}/titan-preguntas-$$.sh"
cat >"${preguntas_autopiloto}" <<'PREGUNTAS'
#!/bin/bash
# Todas las primitivas de pregunta, seguidas. En autopilot tienen que volver sin
# tocar dialog; en modo normal tienen que abrir alguna ventana.
export TITAN_SILENCIO=1
RAIZ="${1:?}"
source "${RAIZ}/instalador/lib-comun.sh"
declare -gA E=()
preguntar_texto    "k1" "Texto"    "escribe algo" "valor"
preguntar_lista    "k2" "Lista"    "elige"        "a:uno|b:dos" 10 "a"
preguntar_multiple "k3" "Varios"   "marca"        "a:uno|b:dos" "a b"
preguntar_si       "k4" "Si o no"  "seguro"       "no"
preguntar_password "k5" "Clave"    "la clave"     "valor"
menu_informacion  "Info" "texto de informacion"
PREGUNTAS
chmod 755 "${preguntas_autopiloto}"

algo_abrio_ventana() {   # algo_abrio_ventana MODO
  local modo="$1"
  rm -f "${espia_auto}/args"
  PATH="${espia_auto}:${PATH}" TITAN_ESPIA="${espia_auto}/args" AUTO="${modo}" \
    TITAN_SILENCIO=1 LOG="${espia_auto}/log" TERM=xterm LANG=es_ES.UTF-8 \
    timeout 20 bash "${preguntas_autopiloto}" "${RAIZ}" >/dev/null 2>&1 || true
  [[ -s "${espia_auto}/args" ]]
}
if algo_abrio_ventana 1; then
  falla "con autopilot se ha abierto una ventana: el instalador se queda esperando a que alguien pulse"
else
  ok "con autopilot, ninguna pregunta abre una ventana"
fi
if algo_abrio_ventana 0; then
  ok "sin autopilot las preguntas SI abren ventana (el comprobador no es vacio)"
else
  falla "sin autopilot tampoco se abre ninguna ventana: el de arriba no probaria nada"
fi

# --- 6f. el recorrido entero de las preguntas, con las banderas de install.sh --
#
# install.sh va con 'set -euo pipefail'. Y con 'set -u', leer de un array
# asociativo una clave que no existe es un error DURO: el shell dice "unbound
# variable" y se para. Como el instalador no tiene a nadie delante, ese error no
# sale por pantalla: el proceso se acaba con codigo 1 y la ultima linea del log
# es la ultima pregunta que llego a hacer. Asi es como se cuela.
#
# Ya ha pasado: 'elegir_zona' leia '${E[zona]}' en su PRIMERA linea, y 'zona' no
# es clave del fichero de respuestas (ahi va 'zona_horaria', y 'zona' se calcula
# despues). El instalador moria ahi, a mitad de las preguntas, del todo en
# silencio. Un fallo que solo se ve instalando, y que se lleva 40 minutos por
# delante.
#
# Aqui se hace el recorrido entero de las preguntas, en autopilot, con las
# MISMAS banderas que install.sh y con el fichero de respuestas de verdad. No
# toca el disco ni descarga nada: solo son las ventanas, que es donde esta la
# mitad de estos fallos.
echo
echo "== 6f. el recorrido de las preguntas con set -euo pipefail =="
recorrido="${TMPDIR:-/tmp}/titan-recorrido-$$.sh"
cat >"${recorrido}" <<'RECORRIDO'
#!/bin/bash
# El recorrido de las preguntas, en el mismo orden que instalar() en install.sh,
# sin lo que toca el disco (eso se comprueba instalando de verdad).
set -euo pipefail                 # las mismas banderas que install.sh
export AUTO=1 TITAN_SILENCIO=1
RAIZ="${1:?}"
RESPUESTAS="${2:?}"
source "${RAIZ}/instalador/lib-comun.sh"
source "${RAIZ}/instalador/lib-escritorios.sh"
source "${RAIZ}/instalador/lib-apps.sh"
source "${RAIZ}/instalador/menus.sh"
source "${RAIZ}/instalador/paso-disco.sh"
# 'paso-base.sh' tambien, porque define dos funciones que el menu de apps llama
# ('flatpaks_elegidos' y 'paquetes_instalar') y sin ellas el menu se queda sin
# la lista de la tienda. install.sh lo carga siempre.
source "${RAIZ}/instalador/paso-base.sh"
declare -gA E=()
leer_respuestas "${RESPUESTAS}"
# Lo que deja el paso de disco al particionar. Aqui no se particiona (haria
# falta un disco de verdad), pero el resumen lee estas claves, asi que se putsen
# como las pondria. Se mira el firmware de verdad en vez de inventarse un 1, que
# es lo mismo que hace el instalador.
if [[ -d /sys/firmware/efi ]]; then E[modo_arranque]="1"; else E[modo_arranque]="0"; fi
E[cifrado]="no"
menu_tipo_uso
menu_escritorio
menu_apps
menu_cuentas
menu_arranque
menu_resumen || { printf "CODIGO=%s\n" "$?"; exit 0; }
printf "LLEGO-AL-FINAL\n"
RECORRIDO
chmod 755 "${recorrido}"

# Con un dialog de mentira delante, por si alguna ventana se colase: asi se
# nota en el log en vez de quedarse esperando a que alguien pulse.
mkdir -p "${espia_auto}"
cat >"${espia_auto}/dialog" <<'ESPIA_AUTO2'
#!/bin/bash
printf '%s\0' "$@" >"${TITAN_ESPIA}"
exit 1
ESPIA_AUTO2
chmod 755 "${espia_auto}/dialog"
# Se borra lo que dejo la seccion 6e: su ultima comprobacion deja a proposito el
# fichero de argumentos escrito (por 'la ventana SI se abre sin autopilot'), y
# si no se limpia, esta de aqui lee el rastro de la anterior y se equivoca.
rm -f "${espia_auto}/args"

recorrido_salida="$(PATH="${espia_auto}:${PATH}" TITAN_ESPIA="${espia_auto}/args" \
  LOG="${espia_auto}/log" \
  timeout 120 bash "${recorrido}" "${RAIZ}" "${DISTRO}/verify/respuestas-instalacion.txt" 2>&1 || true)"
if grep -aq "LLEGO-AL-FINAL" <<<"${recorrido_salida}"; then
  ok "las preguntas de la instalacion entera se contestan sin morir (con set -u)"
else
  # El error de 'set -u' va a la salida de error, asi que se puede ensenar tal
  # cual: es el culpable, y esconderlo seria justo el problema que hay aqui.
  falla "el recorrido de las preguntas se corta antes de tiempo:
$(sed 's/^/         | /' <<<"${recorrido_salida}" | tail -6)"
fi
if [[ -s "${espia_auto}/args" ]]; then
  falla "en autopilot se ha abierto una ventana: ${espia_auto}/args"
else
  ok "y no se ha abierto ninguna ventana por el camino"
fi

# --- 6f.2. lo que pasa si el usuario CANCELA cada pantalla -------------------
#
# Lo de arriba prueba el camino de autopilot, donde todas las pantallas se
# saltan. Falta el otro: el de una persona que le da a Esc, o el de una
# instalacion sin nadie delante y la entrada cerrada. Ese camino estaba roto, y
# de la peor manera posible: en silencio.
#
# 'preguntar_texto' y 'preguntar_lista' ponian su valor por defecto al cancelar,
# pero 'preguntar_multiple' y 'preguntar_password' devolvian SIN PONER la clave.
# El instalador va con 'set -euo pipefail', de modo que el primer '${E[usos]}'
# sin guardas de 'menu_tipo_uso' se moria con 'variable sin asignar', con codigo
# 1 y sin ninguna ventana que lo dijera. Medido en el live:
#
#     /root/instalador/menus.sh: linea 53: E[usos]: variable sin asignar
#
# Y 'menu_tipo_uso' tiene dos lineas mas abajo un 'if [[ -z "${E[usos]}" ]]' que
# existe JUSTO para el caso de 'sin tipos marcados, se usa el defecto'. Nunca
# llego a ejecutarse, porque 'set -u' se adelanta. Que es la clase de fallo
# del proyecto: un camino de codigo que existe para salvar un caso y al que
# nunca se puede llegar.
#
# Y no basta con mirar el fuente: hace falta que la ventana de verdad DEVUELVA
# MAL, que es lo que hace un 'dialog' al recibir Esc. Asi que se llama a cada
# primitiva con una 'ventana' que siempre cancela, y luego se LEE la clave SIN
# guardas ('${E[clave]}'), que es como la leen los menus de verdad: con 'set
# -u', si la primitiva no la ha puesto, el comprobador se muere aqui con el
# mismo error que el instalador.
echo
echo "== 6f.2. cancelar cada pantalla, con la ventana devolviendo mal =="
cancela="${TMPDIR:-/tmp}/titan-cancela-$$.sh"
cat >"${cancela}" <<'CANCELA'
#!/bin/bash
set -euo pipefail                  # las mismas banderas que install.sh
RAIZ="${1:?}"
source "${RAIZ}/instalador/lib-comun.sh"
# Una 'ventana' que siempre cancela: es lo que hace 'dialog' cuando le llega
# Esc, y tambien lo que pasa si no hay nadie delante (dialog lee el fin de la
# entrada y sale con codigo 1 sin pintar nada).
ventana() { return 1; }
export AUTO=0
declare -gA E=()
# Cada primitiva, y despues una lectura SIN guardas. Con 'set -u', una clave
# que la primitiva no haya puesto al cancelar mata aqui el comprobador, con el
# mismo mensaje que se leia en el live.
preguntar_texto    "t1" "Texto"  "escribe algo" "valor"
printf 't1=[%s]\n' "${E[t1]}"
preguntar_lista    "t2" "Lista"  "elige" "a:uno|b:dos" 10 "a"
printf 't2=[%s]\n' "${E[t2]}"
preguntar_multiple "t3" "Varios" "marca" "a:uno|b:dos" "a b"
printf 't3=[%s]\n' "${E[t3]}"
preguntar_si       "t4" "Si o no" "seguro" "no"
printf 't4=[%s]\n' "${E[t4]}"
preguntar_si       "t6" "Si o si" "seguro" "si"
printf 't6=[%s]\n' "${E[t6]}"
# La contrasena va aparte y es el final del script a proposito: una contrasena
# NO tiene valor por defecto (una que se inventa sola es una puerta abierta), de
# modo que cancelar ahi tiene que SALIR con el codigo 3 de 'cancelado'. Por eso
# esto no llega a 't5', y el comprobador mira el codigo de salida.
preguntar_password "t5" "Clave"  "escribe la contrasena"
printf 't5=[%s]\n' "${E[t5]}"
printf 'LLEGO-AL-FINAL\n'
CANCELA
chmod 755 "${cancela}"
# 'TITAN_LOG' y no 'LOG': 'lib-comun.sh' pisa 'LOG' con su propio valor por
# defecto al cargarse, asi que poner 'LOG' en el entorno no haria nada.
rm -f "${espia_auto}/log-cancela"
cancelado="$(TITAN_LOG="${espia_auto}/log-cancela" timeout 60 \
  bash "${cancela}" "${RAIZ}" 2>&1)"
cancelado_rc=$?

if grep -qaE 'unbound variable|sin asignar' <<<"${cancelado}"; then
  falla "cancelar una pantalla deja claves sin poner y el instalador se muere"
  printf '        %s\n' "$(grep -aE 'unbound|sin asignar' <<<"${cancelado}" \
    | head -1)"
  printf '        Claves leidas antes de morir:\n'
  grep -a '^t[0-9]=\[' <<<"${cancelado}" | sed 's/^/        /' || true
else
  ok "cancelar una pantalla no deja ninguna clave sin poner (con set -u)"
fi
# Y que este comprobador no sea de los que no pueden fallar: tiene que haber
# llegado a la ultima de las primitivas que SI tienen valor por defecto.
leidas="$(grep -ac '^t[0-9]=\[' <<<"${cancelado}" || true)"
comprobar "las cinco primitivas con valor por defecto se leen al cancelar" \
  "5" "${leidas:-0}"
comprobar "cancelar deja lo que la ventana traia marcado" "1" \
  "$(grep -c '^t3=\[a b\]$' <<<"${cancelado}" || true)"
comprobar "cancelar deja el valor por defecto de un si/no" "1" \
  "$(grep -c '^t6=\[si\]$' <<<"${cancelado}" || true)"
comprobar "cancelar en la contrasena sale con el codigo de cancelado" "3" \
  "${cancelado_rc}"
# Que no se callen y se limiten a salir: el motivo tiene que quedar escrito.
motivo="$(grep -c 'contrasena no se puede dejar en blanco' \
  "${espia_auto}/log-cancela" 2>/dev/null || true)"
comprobar "y ademas dice por que se sale" "1" "${motivo:-0}"
rm -f "${cancela}"

rm -rf "${espia_auto}"
rm -f "${recorrido}" "${preguntas_autopiloto}"

# --- 6g. lo que se escribe en el destino y luego se lee DENTRO del chroot -----
#
# arch-chroot y pacstrap montan montajes NUEVOS encima de varios sitios del
# sistema destino: /tmp (tmpfs), /run (tmpfs), /dev, /proc, /sys, y el propio
# directorio raiz encima de si mismo. Todo lo que este debajo de esos montajes
# esta a la vista desde fuera y es INVISIBLE desde dentro del chroot.
#
# No avisan de nada. El caso que ha pasado: el paquete del kernel se copiaba a
# "${raiz}/tmp" y luego se instalaba con 'arch-chroot ... pacman -U /tmp/paquete'.
# El fichero estaba en el disco, con sus 163 MB, y pacman decia "could not find
# or read package". Media hora de instalacion para un error de una palabra.
#
# Lo que se comprueba: que el instalador no deje ficheros en el /tmp, /run o
# /dev del sistema destino. Y no solo que no lo haga hoy, sino que el
# comprobador diga por que estan descartados, para que si manana alguien anade
# un caso nuevo sepa que tiene que mirarlo.
echo
echo "== 6g. lo que se escribe en el destino y se lee dentro del chroot =="
# Se busca de una vez cualquier ruta que apunte al destino (la variable que lo
# guarda) mas una de las sombras. El '\b' del final es lo que hace que valga
# tanto "${raiz}/tmp" (que acaba en comilla) como "${raiz}/tmp/paquete": pide un
# limite de palabra detras, asi que "/tmp" casa y "/tmpviejo" no.
#
# Se saca la LINEA ENTERA y no solo lo que casa, porque despues hay que poder
# distinguir un comentario de codigo, y un comentario no se puede quitar con la
# ruta ya recortada (el '#' queda antes y no se ve). Los comentarios se dejan
# fuera porque este mismo comprobador explica el motivo en un comentario, y no
# puede fallarse a si mismo.
problemas=0
while IFS= read -r linea; do
  [[ -n "${linea}" ]] || continue
  problemas=$((problemas + 1))
  falla "el instalador escribe en un sitio que arch-chroot tapa
         ${linea}"
done < <(grep -rnE '\$\{(raiz|r|DESTINO)\}/(tmp|run|dev|proc|sys)\b' \
           "${RAIZ}/instalador" "${RAIZ}/install.sh" 2>/dev/null \
         | grep -vE ':[0-9]+:[[:space:]]*#' || true)
if [[ "${problemas}" -eq 0 ]]; then
  ok "el instalador no deja nada en /tmp, /run, /dev, /proc ni /sys del destino,"
  ok "que es donde arch-chroot y pacstrap montan por encima y lo esconden"
fi

# Y la comprobacion de que esto no es un comprobador de adivinanzas: los
# montajes esos existen de verdad, se pueden listar, y son los que se supone.
# Si manana arch-chroot deja de montarlos, esta comprobacion tiene que decir
# que ya no comprueba nada, en vez de dar verde tan contenta.
montajes_reales="$(grep -oE '"\$1(/[a-z]+)"' /usr/bin/arch-chroot 2>/dev/null \
                   | tr -d '"' | sed 's|\$1||' | sort -u | tr '\n' ' ' || true)"
if [[ -n "${montajes_reales}" ]]; then
  ok "los montajes que se evitan existen de verdad en arch-chroot: ${montajes_reales}"
else
  falla "no se encuentra arch-chroot en el sistema: esta seccion no comprueba nada"
fi

# --- 6h. los hooks de mkinitcpio tienen que existir en el sistema nuevo --------
#
# El instalador anade hooks al HOOKS= de /etc/mkinitcpio.conf del sistema que
# monta (sd-encrypt si hay cifrado, btrfs si el filesystem es btrfs). Un hook
# no es una opcion: es un fichero de programa que tiene que estar en el sistema.
# Si el paquete que lo trae no esta instalado, mkinitcpio responde "ERROR: Hook
# 'btrfs' cannot be found", construye el initramfs igual (por eso el aviso de
# "the image may not be complete") y sale con codigo 2.
#
# Pasaba con btrfs: el instalador pedia btrfs y anadia el hook, pero
# btrfs-progs no estaba en la lista de paquetes base. Y solo se rompia en UEFI,
# porque en BIOS el initramfs va en el hueco del MBR y ahi no hace falta el
# hook: un fallo que aparece en un equipo y no en otro, que es la clase de
# fallo mas dificil de ver.
#
# Lo que se comprueba, en los dos sentidos:
#   1. Todo hook que escribe el instalador tiene en la tabla de abajo el paquete
#      que lo trae. Si manana se anade un hook y no se anade su paquete a la
#      lista base, esto falla aunque el paquete exista en los repos.
#   2. Ese paquete esta de verdad en lo que se instala, mirando el grafo de
#      dependencias de los repos de verdad (no una lista escrita a mano).
echo
echo "== 6h. los hooks que escribe el instalador, con su paquete =="
declare -A QUIEN_TRAE_HOOK=(
  [btrfs]=btrfs-progs          # /usr/lib/initcpio/install/50-btrfs
  [sd-encrypt]=systemd         # el hook de cifrado vive en systemd
  [filesystems]=mkinitcpio     # /usr/lib/initcpio/install/50-filesystems
)
# Los hooks se LEEN del codigo, no se escriben aqui: si se escribieran aqui, el
# comprobador solo se comprobaria a si mismo.
HOOKS_ESCRITOS="$(sed -n '/^paso_mkinitcpio()/,/^}/p' "${RAIZ}/instalador/paso-chroot.sh" \
                  | grep -oE 'HOOKS=\([a-z0-9][a-z0-9-]*' | sed 's/^HOOKS=(//' \
                  | sort -u | tr '\n' ' ')"
if [[ -z "${HOOKS_ESCRITOS}" ]]; then
  falla "no se encuentra ni un hook en paso_mkinitcpio: no se puede comprobar nada"
else
  ok "hooks que escribe el instalador: ${HOOKS_ESCRITOS}"
fi

# Alcanzable DESDE los paquetes base: no basta con que el paquete este en la
# lista, tiene que estar o ser dependencia de algo que este. Se recorre el
# grafo con 'pacman -Sii' de los repos de verdad, que es lo que se descargara.
alcanzable() { # alcanzable OBJETIVO RAIZES...
  local objetivo="$1"; shift
  local -a cola=("$@") vistos=() p d q
  while (( ${#cola[@]} )); do
    p="${cola[0]}"; cola=("${cola[@]:1}")
    [[ " ${vistos[*]} " == *" ${p} "* ]] && continue
    vistos+=("${p}")
    [[ "${p}" == "${objetivo}" ]] && return 0
    d="$(pacman -Sii "${p}" 2>/dev/null | sed -n 's/^Depends On *: *//p')"
    for q in ${d}; do
      q="${q%%=*}"          # fuera la version: 'kmod>=1.6' -> 'kmod'
      [[ -n "${q}" ]] && cola+=("${q}")
    done
  done
  return 1
}

read -r -a BASE_REAL <<<"$(paquetes_base)"
for hook in ${HOOKS_ESCRITOS}; do
  quien="${QUIEN_TRAE_HOOK[${hook}]:-}"
  if [[ -z "${quien}" ]]; then
    falla "el instalador escribe el hook '${hook}' y no se sabe que paquete lo trae"
    nota "  anadelo a QUIEN_TRAE_HOOK en ${0##*/}, o quita el hook del instalador"
    continue
  fi
  if alcanzable "${quien}" "${BASE_REAL[@]}"; then
    ok "el hook '${hook}' lo trae '${quien}', que llega a lo que se instala"
  else
    falla "el instalador escribe el hook '${hook}', pero '${quien}' no se instala"
    nota "  '${quien}' no esta en paquetes_base ni es dependencia de nada de lo"
    nota "  que se instala. Anadelo a paquetes_base: sin el, mkinitcpio dice"
    nota "  found', construye el initramfs incompleto y sale con codigo 2"
  fi
done

# Y la comprobacion hermana, que sale del mismo fallo: si mkinitcpio va a fallar,
# que no se lleve por lo mismo toda la salida por delante. Un '>/dev/null' en el
# paso que genera el initramfs es exactamente el fallo 14 otra vez.
#
# Solo se mira la linea que LANZA mkinitcpio, no cualquier linea del paso: un
# '2>/dev/null' de un 'tail' por ahi no es el mismo fallo y no puede contarse
# como si lo fuera. (Caza el suyo, no el de al lado.)
if grep -E 'arch-chroot[^|]*mkinitcpio' "${RAIZ}/instalador/paso-chroot.sh" \
     | grep -q '>/dev/null'; then
  falla "el paso de mkinitcpio tira su salida a /dev/null"
  nota "  si falla, el log no dice por que. Mandalo a un log y ensenala al final"
else
  ok "el paso de mkinitcpio guarda su salida (si falla, se ve por que)"
fi

# --- 6i. los nombres de los paquetes base existen en los repos -----------------
#
# El comentario de paquetes_base dice, con razon, que todos estan verificados
# contra las bases de datos: un nombre mal escrito ahi no falla al escribir el
# codigo, falla diez minutos despues, con el disco ya particionado y medio
# sistema descargado. Es barato comprobarlo: basta con preguntar al pacman.
echo
echo "== 6i. los paquetes base existen de verdad en los repos =="
malos=0
for p in "${BASE_REAL[@]}"; do
  if ! pacman -Si "${p}" >/dev/null 2>&1; then
    malos=$((malos + 1))
    falla "el paquete '${p}' no existe en ningun repositorio"
  fi
done
[[ "${malos}" -eq 0 ]] && ok "los ${#BASE_REAL[@]} paquetes base existen todos en los repos"

# --- 6j. la eleccion de espejos, sin red y sin maquina virtual ---------------
#
# El instalador mide los espejos antes de descargar, porque con rolling una
# lista fija se queda atrasada: de los diez candidatos, cuatro contestan con la
# ultima version de los paquetes y los demas o no contestan o van con retraso.
# Cuando los TRES espejos que traia el live fallaron a la vez, la instalacion se
# paro con medio sistema descargado.
#
# 'ordenar_espjos' es la parte con logica, y es pura: solo ordena las lineas que
# le dan. Se puede comprobar aqui entero, con ejemplos escritos a mano, sin
# arrancar nada. La parte que de verdad usa la red ('medir_espjos') no se puede
# comprobar sin internet, y en vez de darla por buena se dice aqui que no se ha
# mirado.
echo
echo "== 6j. los espejos se ordenan por lo que han tardado de verdad =="

salida="$(ordenar_espjos <<'FIN'
https://lento.example/archlinux 3.20
https://rapido.example/archlinux 0.35
https://medio.example/archlinux 1.10
FIN
)"
comprobar "de mas rapido a mas lento" \
"https://rapido.example/archlinux
https://medio.example/archlinux
https://lento.example/archlinux" "${salida}"

# El caso que hacia falta de verdad: curl imprime '0.000000' cuando no ha
# podido descargar nada, y '000' cuando ni ha podido mirar la URL. Los dos son
# NUMEROS, asi que una comprobacion normal los aceptaria como tiempos y los
# pondria de primeros: el espejo muerto seria el que primero se usaria, y la
# instalacion volveria a fallar por lo mismo que la habia hecho fallar. Asi que
# un tiempo de cero no es un tiempo: no dice nada, y lo que no dice nada se va
# al final.
salida="$(ordenar_espjos <<'FIN'
https://muerto.example/archlinux 000
https://rapido.example/archlinux 0.35
https://nada.example/archlinux 0.000000
FIN
)"
comprobar "un tiempo de cero NO cuenta como tiempo (se va al final)" \
"https://rapido.example/archlinux
https://muerto.example/archlinux
https://nada.example/archlinux" "${salida}"

# Y lo que no es un numero de tiempo tampoco: texto de error, o nada.
salida="$(ordenar_espjos <<'FIN'
https://a.example/archlinux sin-respuesta
https://b.example/archlinux vacio
https://c.example/archlinux 2.00
FIN
)"
comprobar "lo que no es un tiempo se queda al final, y en su orden" \
"https://c.example/archlinux
https://a.example/archlinux
https://b.example/archlinux" "${salida}"

# Un subsegundo de verdad tiene que contar: 0.35 es un tiempo legitimo, no un
# cero disfrazado. Si la comprobacion de arriba se escribiera quitando el cero
# de delante en vez de mirando si queda algun digito, este pasaria a ser el caso
# que falla, y por el motivo equivocado.
salida="$(ordenar_espjos <<'FIN'
https://a.example/archlinux 0.35
https://b.example/archlinux 0.04
FIN
)"
comprobar "un subsegundo si cuenta (0.35 es un tiempo de verdad)" \
"https://b.example/archlinux
https://a.example/archlinux" "${salida}"

# Los empates conservan el orden de entrada. Sin 'sort -s' el orden de los
# empates es libre, y una lista de espejos que se reordena sola cada vez que dos
# tardan lo mismo no se puede comparar con la de ayer.
salida="$(ordenar_espjos <<'FIN'
https://primero.example/archlinux 1.00
https://segundo.example/archlinux 1.00
https://tercero.example/archlinux 1.00
FIN
)"
comprobar "dos tiempos iguales mantienen el orden de entrada" \
"https://primero.example/archlinux
https://segundo.example/archlinux
https://tercero.example/archlinux" "${salida}"

# Y lineas vacias o con solo espacios, que se cuelan al pegar una lista de
# espejos en un fichero: si se ordenaran, 'url' se quedaria vacio y
# 'sed'/'cut' producirian una linea vacia que pacman leeria como un servidor.
salida="$(ordenar_espjos <<'FIN'

   
https://a.example/archlinux 1.00

FIN
)"
comprobar "las lineas vacias no salen (ni como lineas vacias ni como servidores)" \
"https://a.example/archlinux" "${salida}"

# Cuantos se quedan. Cuatro es lo razonable: pacman va probando uno por uno para
# cada fichero, asi que con cuatro vivos es practicamente imposible que los cuatro
# esten atrasados a la vez. Menos de tres no cubre un fallo de red; mas de ocho
# es descargar del doble para no ganar nada, porque el problema no es cual es el
# mas rapido, es que alguno de los primeros no conteste.
quedan="$(espejos_a_quedarse)"
if [[ "${quedan}" =~ ^[1-9][0-9]*$ ]] && (( quedan >= 3 && quedan <= 8 )); then
  ok "el instalador se queda con ${quedan} espejos (ni 1, que es lo de antes, ni 10)"
else
  falla "espejos_a_quedarse() = '${quedan}': o no es un numero, o son menos de 3 (que no cubren un fallo de red) o mas de 8 (que es descargar del doble)"
fi

# Y que de verdad se usa lo que sale de ordenar, que es lo que no se puede
# comprobar leyendo el texto. 'apuntar_espjos_medidos' es la que decide si lo
# medido se usa o se queda mirandose, asi que se le da un conf de mentira con
# la forma del de verdad y una lista medida de mentira, y se mira el conf.
conf_falso="${TMPDIR:-/tmp}/titan-conf-falso-$$.conf"
ml_falso="${TMPDIR:-/tmp}/titan-ml-falso-$$.txt"
# Las tres lineas de 'Include' del conf real, una por repositorio. Un solo
# 'Include' no serviria: el fallo de no usar la lista medida se manifesta igual
# con uno, pero un conf con los tres es el caso de verdad y el que hay.
cat >"${conf_falso}" <<'CONF'
[options]
HoldPkg = pacman glibc
[core]
Include = /etc/pacman.d/mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist
[multilib]
Include = /etc/pacman.d/mirrorlist
[testing]
Include = /etc/pacman.d/mirrorlist.candidatos
CONF
printf '%s\n' \
  'https://rapido.example/archlinux/$repo/os/$arch' \
  'https://segundo.example/archlinux/$repo/os/$arch' >"${ml_falso}"
if apuntar_espjos_medidos "${conf_falso}" "${ml_falso}"; then
  n_apunta="$(grep -cF "Include = ${ml_falso}" "${conf_falso}" || true)"
  n_viejo="$(grep -c '^Include = /etc/pacman.d/mirrorlist$' "${conf_falso}" || true)"
  if [[ "${n_apunta}" -eq 3 && "${n_viejo}" -eq 0 ]]; then
    ok "los 3 repos del conf apuntan a la lista medida, y ninguno se queda en la del live"
  else
    falla "el conf no apunta a la lista medida como debia: ${n_apunta} de 3 la apuntan y ${n_viejo} siguen en la del live (medir y no usar es medir en balde)"
  fi
  # Y que NO toca la linea que empieza igual pero es mas larga. El 'mirrorlist'
  # del live tiene al lado un 'mirrorlist.candidatos', y un 'sed' sin ancla al
  # final de linea se lo come tambien y lo deja apuntando a la lista de URLs
  # peladas, que pacman no entiende. Con un 'testing' de mentira que incluye
  # ese fichero, se ve si el ancla esta o no.
  if grep -qx 'Include = /etc/pacman.d/mirrorlist.candidatos' "${conf_falso}"; then
    ok "y no toca la linea que solo empieza igual (mirrorlist.candidatos): el ancla del final esta"
  else
    falla "el conf ya no tiene 'Include = /etc/pacman.d/mirrorlist.candidatos': el 'sed' se ha comido tambien la linea que solo empieza por mirrorlist"
  fi
  # Y que no la duplique: pacman lee cada 'Include' y descarga cada fichero una
  # vez por cada Include. Un conf con el mismo mirrorlist cuatro veces no es un
  # problema de Estetica, es descargar cuatro veces.
  apuntar_espjos_medidos "${conf_falso}" "${ml_falso}"
  if [[ "$(grep -cF "Include = ${ml_falso}" "${conf_falso}")" -eq 3 ]]; then
    ok "y no la anade otra vez si ya esta (llamarla dos veces no descarga el doble)"
  else
    falla "llamar dos veces deja $(grep -cF "Include = ${ml_falso}" "${conf_falso}") lineas: pacman descargaria cada fichero dos veces"
  fi
else
  falla "apuntar_espjos_medidos() no ha hecho su trabajo con una lista medida que existe"
fi
# Y con una lista vacia (que es lo que pasa si no se ha podido medir nada): ahi
# no se toca el conf, porque es mejor instalar con la lista del live que no
# instalar con una lista vacia.
cat >"${conf_falso}" <<'CONF'
[core]
Include = /etc/pacman.d/mirrorlist
CONF
: >"${ml_falso}"
if ! apuntar_espjos_medidos "${conf_falso}" "${ml_falso}" \
   && grep -q '^Include = /etc/pacman.d/mirrorlist$' "${conf_falso}"; then
  ok "sin lista medida, el conf se queda como estaba (mejor la del live que una vacia)"
else
  falla "con la lista medida vacia, el conf se ha tocado o la funcion dice que ha ido bien"
fi
rm -f "${conf_falso}" "${ml_falso}"
# Y que el paso de descarga llame a esa funcion, que es la forma de que la
# comprobacion de arriba mida el codigo de verdad y no una copia al lado.
if grep -q 'apuntar_espjos_medidos "${conf}" "${ml_medidos}"' \
     "${RAIZ}/instalador/paso-base.sh"; then
  ok "y el paso de descarga usa esa funcion, no otra copia de lo mismo"
else
  falla "el paso de descarga NO llama a 'apuntar_espjos_medidos': la comprobacion de arriba estaria midiendo una copia, no el codigo que se ejecuta"
fi

# La lista de candidatos del live, que es lo que se mide. Se comprueba LEYENDOLA
# del codigo del live, no desde dentro del live: arrancar una maquina virtual
# para leer diez lineas de un fichero no es una comprobacion, es una wasted.
candidatos="$(sed -n "/^cat >\/etc\/pacman.d\/mirrorlist <<'EOF'$/,/^EOF$/p" \
              "${DISTRO}/iso/titan/airootfs/root/customize_airootfs.sh" \
              | sed -n 's/^Server[[:space:]]*=[[:space:]]*//p')"
n_cand="$(grep -c . <<<"${candidatos}" || true)"
if (( n_cand >= 6 )); then
  ok "el live trae ${n_cand} espejos candidatos (traia 3, y los tres fallaron)"
else
  falla "el live solo trae ${n_cand} espejos candidatos: con menos de 6, un mal dia de red tumba la instalacion entera"
fi
if grep -qv '^https\?://' <<<"${candidatos}"; then
  falla "hay un candidato que no es una URL http(s)"
else
  ok "los ${n_cand} candidatos son URLs http(s)"
fi
repetidos="$(sort <<<"${candidatos}" | uniq -d | grep -c . || true)"
if (( repetidos == 0 )); then
  ok "no hay espejos repetidos en la lista"
else
  falla "hay ${repetidos} espejos repetidos: se miden dos veces y solo cuenta uno"
fi
# Y el detalle que hizo que esto no funcionara la primera vez: los candidatos se
# miden anadiendo una ruta real al final, asi que no pueden llevar los comodines
# de pacman. Con '$repo' en medio, la URL que se pide no existe en ningun sitio
# y TODOS los espejos miden lo mismo: fallido.
#
# El mirrorlist SI lleva los comodines (los necesita pacman, es su formato), y
# quitarlos es cosa del paso que genera la lista de candidatos. Asi que lo que
# se comprueba es el resultado de ESE paso, con su mismo comando, sobre el
# mirrorlist de verdad: comprobar el mirrorlist daria un fallo por lo que
# tiene que tener.
generador_de_candidatos="$(grep -F 's#/\$repo/os/\$arch$##' \
  "${DISTRO}/iso/titan/airootfs/root/customize_airootfs.sh" || true)"
if [[ -n "${generador_de_candidatos}" ]]; then
  ok "el live quita los comodines de pacman al generar la lista de candidatos"
else
  falla "el live NO quita los comodines al generar la lista de candidatos: al medir se pide una URL con '\$repo' en medio, que no existe en ninguna parte, y todos los espejos miden lo mismo"
fi
# Y el efecto de esa orden, para que se vea que con los candidatos limpios se
# puede medir. 'candidatos' ya viene sin el 'Server = ' (por eso se cuenta con
# 'grep -c .' y no con la forma de las lineas), asi que aqui solo queda quitar
# los comodines.
generado="$(sed 's#/\$repo/os/\$arch$##' <<<"${candidatos}")"
if grep -q '\$repo\|\$arch' <<<"${generado}"; then
  falla "la lista de candidatos sale con los comodines dentro"
elif [[ "$(grep -c . <<<"${generado}")" -ne "${n_cand}" ]]; then
  falla "al generar la lista de candidatos se pierden espejos: ${n_cand} en el mirrorlist, $(grep -c . <<<"${generado}") en la lista"
else
  ok "y salen los ${n_cand} enteros y medibles: $(head -1 <<<"${generado}")"
fi
if grep -q 'mirrorlist.candidatos' "${DISTRO}/iso/titan/airootfs/root/customize_airootfs.sh" \
   && grep -q 'mirrorlist.candidatos' "${RAIZ}/instalador/paso-base.sh"; then
  ok "el live genera la lista de candidatos y el instalador la lee"
else
  falla "el live genera la lista de candidatos pero el instalador no la lee (o al reves)"
fi
# Y que la medicion no sea un requisito: si falla, se instala con la lista del
# live. Un instalador que se niega a instalar porque no ha podido medir los
# espejos es peor que uno que instala con lo que hay.
if grep -q 'no se han podido medir los espejos; se usa la lista del live' \
     "${RAIZ}/instalador/paso-base.sh"; then
  ok "y si la medicion falla, se instala con la lista del live (medir es una mejora, no un requisito)"
else
  nota "  no se avisa de que se cae a la lista del live si la medicion falla"
fi

# --- medir de verdad, sin internet -------------------------------------------
# Todo lo de arriba ha sido ordenar lineas escritas a mano. Falta lo de verdad:
# que 'medir_espjos' consulte, tire los que no contestan y escriba un fichero
# que pacman pueda usar. Eso se puede probar SIN internet con 'file://': curl
# tambien sabe leer ficheros, asi que un 'espejo' puede ser una carpeta de
# mentira en /tmp con dentro la ruta que se mide, y uno que no contesta es una
# carpeta sin ese fichero dentro.
echo
echo "== 6j-bis. medir los espejos, con espejos de mentira =="
red_falsa="${TMPDIR:-/tmp}/titan-espjos-falso-$$"
mkdir -p "${red_falsa}"
# Cinco que contestan (con el fichero que se mide dentro, que es lo unico que
# curl mira) y uno que no: la carpeta existe pero el fichero no, asi que curl
# falla y el tiempo sale vacio, que es justo el caso que tiene que quedarse
# fuera.
for n in 1 2 3 4 5; do
  mkdir -p "${red_falsa}/vivo${n}/core/os/x86_64"
  : >"${red_falsa}/vivo${n}/core/os/x86_64/core.db.sig"
done
mkdir -p "${red_falsa}/muerto/core/os/x86_64"
{
  for n in 1 2 3 4 5; do printf 'file://%s/vivo%d\n' "${red_falsa}" "${n}"; done
  printf 'file://%s/muerto\n' "${red_falsa}"
  printf '# Esto es un comentario y no es un espejo.\n'
} >"${red_falsa}/candidatos"
ml_medido="${red_falsa}/medido"
if TITAN_CANDIDATOS="${red_falsa}/candidatos" \
   medir_espjos "${ml_medido}"; then
  n_medidos="$(grep -c . <"${ml_medido}" || true)"
  if [[ "${n_medidos}" -eq "$(espejos_a_quedarse)" ]]; then
    ok "con 5 que contestan y 1 que no, se quedan exactamente ${n_medidos} (los que se piden)"
  else
    falla "medir_espjos dejo ${n_medidos} espejos en vez de $(espejos_a_quedarse)"
  fi
  if grep -q 'muerto' "${ml_medido}"; then
    falla "el espejo que NO contestaba se ha quedado en la lista: ${ml_medido}"
    nota "  ahi lo que hay es: $(paste -sd'; ' <"${ml_medido}")"
  else
    ok "el que no contestaba se queda fuera"
  fi
  # Y el formato. Este fichero lo lee pacman como un mirrorlist, y un
  # mirrorlist son lineas 'Server = ...' con los comodines detras. Sin eso,
  # pacman no encuentra ningun servidor y dice 'no servers configured', que es
  # el mismo error de la lista del live al principio... despues de haber
  # medido seis espejos con todo el interes del mundo.
  if grep -qv '^Server = \(http\|file\)://.*/\$repo/os/\$arch$' "${ml_medido}"; then
    falla "el fichero medido no es un mirrorlist de pacman: $(head -1 "${ml_medido}")"
    nota "  cada linea tiene que ser 'Server = <url>/\$repo/os/\$arch'"
  else
    ok "y el fichero que sale es un mirrorlist de pacman, linea por linea"
  fi
else
  falla "medir_espjos ha fallado con espejos de mentira que si contestan"
  nota "  con TITAN_CANDIDATOS=${red_falsa}/candidatos"
fi
# Y con una lista de candidatos que no existe: se avisa y se sigue con la del
# live. Aqui no se puede medir nada, y eso no puede ser un fallo que pare la
# instalacion.
#
# OJO a como se pone la variable: 'VAR=x ! orden' NO vale, porque en bash el
# '!' se va al valor de la variable ('TITAN_CANDIDATOS="!"') y lo que se ejecuta
# es la orden de antes. Asi que la asignacion va delante y el 'if' mira si ha
# fallado. Pasaba, y decia que 'medir_espjos' habia ido bien en el mismo caso en
# el que la funcion acababa de arreglarse para fallar.
if TITAN_CANDIDATOS="${red_falsa}/no-existe" \
   medir_espjos "${red_falsa}/medido-vacio" 2>/dev/null; then
  falla "medir_espjos dice que ha ido bien sin lista de candidatos: instalaria con una lista de espejos que no existe"
  nota "  y escribio esto: $(paste -sd'; ' <"${red_falsa}/medido-vacio" 2>/dev/null)"
else
  ok "sin lista de candidatos, medir falla y no escribe nada (y el paso de descarga lo lleva con un aviso, no con un error)"
fi
# Y que paso_base use lo que se ha medido, de verdad. El texto es lo unico que
# se puede mirar aqui (los pasos de verdad no se pueden ejecutar sin red ni
# disco), pero es el texto que decide: si 'medir_espjos' deja de estar en un
# 'if', los espejos se miden en balde y no se nota por ningun otro lado.
if grep -q 'if medir_espjos "${ml_medidos}"; then' \
     "${RAIZ}/instalador/paso-base.sh" \
   && grep -q 'apuntar_espjos_medidos "${conf}" "${ml_medidos}"' \
     "${RAIZ}/instalador/paso-base.sh"; then
  ok "y el paso de descarga mide, y usa lo medido (si no midiera, todo lo de arriba seria en balde)"
else
  falla "el paso de descarga NO usa 'medir_espjos' como debe: mediria en balde o instalaria con la lista del live"
fi
rm -rf "${red_falsa}"

# --- 6l. un espejo que contesta no es un espejo que aguanta --------------------
#
# El fallo de verdad, con once minutos de descarga y la instalacion perdida al
# final. Todo lo de 6j estaba en verde: los espejos se median, se ordenaban y
# se escribian en el formato correcto. El problema era QUE se media.
#
# Se media un '.db.sig' de mil bytes, que mide lo que tarda un espejo en
# CONTESTAR. Y contestar rapido no es sostener una descarga: el espejo que
# ganaba la medicion era un redirector que devuelve el kilobyte en 0.2 s y se
# atasca a partir de ahi, y pacman mataba la descarga entera con "Operation too
# slow. Less than 1 bytes/sec transferred the last 10 seconds".
#
# Asi que aqui se comprueban tres cosas distintas: que la medicion pida un
# volumen de datos de verdad, que un espejo por debajo del limite quede fuera,
# y que la descarga se pueda reintentar con otros espejos en vez de rendirse al
# primer fallo.
echo
echo "== 6l. un espejo que contesta no es un espejo que aguanta =="

# --- 1. que se mida un volumen de datos, y no una firma -------------------------
#
# Se mira el texto porque medir de verdad un megabyte contra diez espejos solo
# se puede hacer con internet. Y el texto es exactamente lo que decide: si el
# rango '-r' no esta, la medicion es la de antes y todo lo demas de aqui da lo
# mismo.
if grep -q -- '-r 0-1048575' "${RAIZ}/instalador/paso-base.sh" \
   && grep -q 'core/os/x86_64/core\.db"' "${RAIZ}/instalador/paso-base.sh"; then
  ok "la medicion pide un MEGABYTE con un rango, no una firma de mil bytes"
else
  falla "la medicion sigue midiendo lo que tarda un espejo en contestar, no en sustentar la descarga"
  nota "  tiene que pedir '-r 0-1048575' sobre 'core/os/x86_64/core.db'"
fi
# Y que no se mida el '.db.sig' de antes. Si las dos cosas se midieran, la
# comprobacion de arriba pasaria con la vieja metida dentro.
if grep -q 'core\.db\.sig' "${RAIZ}/instalador/paso-base.sh"; then
  falla "la medicion sigue mirando el '.db.sig', que no puede contestar por si solo a la pregunta"
  nota "  mil bytes no dan tiempo a que nadie se atasque: por eso se mide el 'core.db'"
else
  ok "y el '.db.sig' ya no se usa para medir"
fi
# Y que un 404 no se mida como "ha contestado en 0.1 s": sin '-f', curl sale
# con codigo de salida cero y el tiempo medido es el de la pagina de error.
if grep -q 'curl -s -f -o /dev/null' "${RAIZ}/instalador/paso-base.sh"; then
  ok "un 404 se cuenta como fallo, no como 'ha contestado rapidisimo'"
else
  falla "la medicion no usa curl -f: un 404 se mediria como una respuesta rapidisima"
fi

# --- 2. el limite: un espejo lento no se usa -----------------------------------
#
# El limite es un numero, pero lo que se comprueba aqui es la decision. Un
# espejo que tarda mas de lo permitido es el que va a hacer perder la
# instalacion, asi que no sale de la lista: no es "el penultimo", es un peligro.
maximo="$(espejos_max_segundos)"
if [[ "${maximo}" =~ ^[0-9]+([.][0-9]+)?$ ]] && awk "BEGIN{exit !(${maximo} > 0)}"; then
  ok "el limite de lentitud es un numero de verdad: ${maximo} s por megabyte"
else
  falla "espejos_max_segundos() = '${maximo}': no es un numero, o es cero"
fi

salida="$(ordenar_espjos <<'FIN'
https://atascado.example/archlinux 19.20
https://lento.example/archlinux 12.80
https://rapido.example/archlinux 1.20
https://medianormal.example/archlinux 4.50
FIN
)"
comprobar "los espejos que tardan mas del limite NO salen (2 de 4)" \
"https://rapido.example/archlinux
https://medianormal.example/archlinux" "${salida}"

# El limite es un "menor o igual que", no un "menor que": un espejo justo en el
# limite se usa. Si se escribiera con '<' el limite seria otra regla de la que
# dice el comentario, y pasaria un espejo de mas.
# OJO al espejo rapido de la lista, y no es decoracion. Con SOLO los dos de la
# frontera, el limite se podria escribir con '<' y esta comprobacion pasaria
# igual: los dos se caerian, la lista quedaria vacia, y el respaldo de "si no
# queda ninguno, el mejor" devolveria el 8.00, que es justo lo que se espera.
# El fallo estaria enmascarado por el respaldo, que es exactamente el motivo por
# el que hace falta un tercer espejo que no este en la frontera. Se rompio con
# '<' a proposito para comprobar que ahora si se caza.
salida="$(ordenar_espjos <<'FIN'
https://rapido.example/archlinux 1.00
https://justo.example/archlinux 8.00
https://fuera.example/archlinux 8.01
FIN
)"
comprobar "el limite es 'menor o igual': 8.00 entra y 8.01 se queda fuera" \
"https://rapido.example/archlinux
https://justo.example/archlinux" "${salida}"

# Y el caso en el que descartar a todos dejaria la lista vacia, que es peor que
# un espejo lento: pacman lee una lista vacia como "no servers configured", y un
# problema de red se convierte en un problema de instalacion. Con todos lentos se
# queda el mejor.
salida="$(ordenar_espjos <<'FIN'
https://lento1.example/archlinux 30.00
https://lento2.example/archlinux 20.00
https://lento3.example/archlinux 40.00
FIN
)"
comprobar "si TODOS son lentos, se queda el mejor (una lista vacia no vale)" \
"https://lento2.example/archlinux" "${salida}"

# Un espejo que no ha contestado sigue yendo al final, detras del lento que no
# hay mas que usar: no se descarta (no se sabe nada de el), pero no encabeza la
# lista.
salida="$(ordenar_espjos <<'FIN'
https://muerto.example/archlinux sin-respuesta
https://lento.example/archlinux 20.00
FIN
)"
comprobar "el que no contesto se queda detras del lento que no hay mas que usar" \
"https://lento.example/archlinux
https://muerto.example/archlinux" "${salida}"

# --- 3. girar la lista ---------------------------------------------------------
#
# Reintentar con los mismos espejos y en el mismo orden es repetir exactamente
# lo que ya ha fallado. Girar la lista es lo que hace que el segundo intento
# sirva de algo.
ml_giro="${TMPDIR:-/tmp}/titan-ml-giro-$$.txt"
cat >"${ml_giro}" <<'FIN'
Server = https://a.example/$repo/os/$arch
Server = https://b.example/$repo/os/$arch
Server = https://c.example/$repo/os/$arch
FIN
salida="$(rotar_espjos "${ml_giro}" 1)"
comprobar "girar una vez: el segundo pasa a ser el primero" \
"Server = https://b.example/\$repo/os/\$arch
Server = https://c.example/\$repo/os/\$arch
Server = https://a.example/\$repo/os/\$arch" "${salida}"

salida="$(rotar_espjos "${ml_giro}" 2)"
comprobar "girar dos veces" \
"Server = https://c.example/\$repo/os/\$arch
Server = https://a.example/\$repo/os/\$arch
Server = https://b.example/\$repo/os/\$arch" "${salida}"

# Girar tres sobre una lista de tres es no girar nada. Y aqui hay una trampa: la
# forma idiomatica de bash '((n %= total))' devuelve 1 cuando el resultado es
# cero, y con 'set -e' (que el instalador lleva) eso es MORIR. Justamente el
# caso del ultimo reintento, que gira la lista un numero de veces multiplo de
# su longitud. Con el '%' escrito como '(( ))' esta comprobacion pasaria en
# silencio (no lleva 'set -e') y el instalador se caeria en el live.
salida="$(rotar_espjos "${ml_giro}" 3)"
comprobar "girar el numero de lineas es no girar nada (y no muere)" \
"Server = https://a.example/\$repo/os/\$arch
Server = https://b.example/\$repo/os/\$arch
Server = https://c.example/\$repo/os/\$arch" "${salida}"
salida="$(rotar_espjos "${ml_giro}" 7)"
comprobar "girar mas que la lista es girar el resto (7 sobre 3 = 1)" \
"Server = https://b.example/\$repo/os/\$arch
Server = https://c.example/\$repo/os/\$arch
Server = https://a.example/\$repo/os/\$arch" "${salida}"
# Y que la funcion de verdad no toque el fichero: la salida es lo que se
# escribe, y el fichero se queda como estaba hasta que quien lo llama cambia.
if [[ "$(rotar_espjos "${ml_giro}" 1 >/dev/null; head -1 <"${ml_giro}")" \
      == 'Server = https://a.example/$repo/os/$arch' ]]; then
  ok "girar no toca el fichero: escribe la lista girada en la salida"
else
  falla "rotar_espjos ha modificado el fichero de entrada: deberia limitarse a imprimir"
fi
if rotar_espjos "${TMPDIR:-/tmp}/titan-no-existe-giro-$$.txt" 1 >/dev/null 2>&1; then
  falla "rotar_espjos dice que ha ido bien con una lista que no existe"
else
  ok "girar una lista que no existe falla (y no inventa una lista vacia)"
fi
rm -f "${ml_giro}"

# --- 4. reintentar, con un pacstrap de mentira ---------------------------------
#
# Aqui ya no se mira el texto: se EJECUTA el reintento con un 'pacstrap' falso
# delante en el PATH. El falso falla dos veces y acierta la tercera, y se mira
# cuantas veces ha sido llamado. Sin esto, "que haya un for por ahi" no dice nada
# sobre lo que pasa cuando la descarga falla de verdad.
lab_pac="${TMPDIR:-/tmp}/titan-pacstrap-$$"
mkdir -p "${lab_pac}/bin"
contador="${lab_pac}/veces"
printf '0\n' >"${contador}"
cat >"${lab_pac}/bin/pacstrap" <<MENTIRA
#!/bin/sh
n=\$(cat "${contador}")
n=\$((n + 1))
printf '%s\n' "\$n" >"${contador}"
echo "pacstrap de mentira, intento \$n: error: no se pudo obtener el archivo"
[ "\$n" -ge 3 ] && exit 0
exit 1
MENTIRA
chmod +x "${lab_pac}/bin/pacstrap"
ml_reint="${lab_pac}/medidos"
cat >"${ml_reint}" <<'FIN'
Server = https://a.example/$repo/os/$arch
Server = https://b.example/$repo/os/$arch
FIN
log_reint="${lab_pac}/descarga.log"
PATH="${lab_pac}/bin:${PATH}" pacstrap_con_reintentos "${ml_reint}" \
  "${log_reint}" "$(reintentos_pacstrap)" -- pacstrap -K base
if [[ $? -eq 0 ]]; then
  ok "la descarga se reintenta: al tercer intento el pacstrap de mentira acierta"
else
  falla "pacstrap_con_reintentos ha fallado con un pacstrap que acierta al tercer intento"
fi
comprobar "y pacstrap se ha llamado las veces que se han pedido" \
  "3" "$(cat "${contador}")"
# Y que la lista se haya girado de verdad entre intento e intento, y no que solo
# se haya repetido la misma llamada tres veces.
comprobar "y la lista de espejos ha quedado girada (b primero, a segundo)" \
  "Server = https://b.example/\$repo/os/\$arch
Server = https://a.example/\$repo/os/\$arch" "$(cat "${ml_reint}")"
# Y el log tiene que decir que intento va en cada intento: un log que solo dice
# "fallo" tres veces no ayuda a nadie a diagnosicarlo.
if [[ "$(grep -c 'intento' "${log_reint}")" -ge 3 ]]; then
  ok "el log de la descarga dice que intento va en cada intento"
else
  falla "el log de la descarga no distingue los intentos: $(grep -c 'intento' "${log_reint}") menciones"
fi

# Y ahora al reves: un pacstrap que siempre falla. Con 'max' intentos se llama
# exactamente 'max' veces y se devuelve fallo, sin reintentar mas de la cuenta
# (que seria dejar al usuario mirando un progreso que no avanza).
printf '0\n' >"${contador}"
sed -i 's/-ge 3/-ge 99/' "${lab_pac}/bin/pacstrap"
if PATH="${lab_pac}/bin:${PATH}" pacstrap_con_reintentos "${ml_reint}" \
     "${log_reint}" "$(reintentos_pacstrap)" -- pacstrap -K base; then
  falla "dice que la descarga ha ido bien con un pacstrap que siempre falla"
else
  ok "si la descarga falla siempre, se acaba (no se queda reintentando para siempre)"
fi
comprobar "y no ha gastado mas intentos de los que habia" \
  "$(reintentos_pacstrap)" "$(cat "${contador}")"
# Con 'max' de 1 se llama una vez y ya: es el caso de quien quiera el
# comportamiento de antes, sin reintentos.
printf '0\n' >"${contador}"
sed -i 's/-ge 99/-ge 3/' "${lab_pac}/bin/pacstrap"
PATH="${lab_pac}/bin:${PATH}" pacstrap_con_reintentos "${ml_reint}" \
  "${log_reint}" 1 -- pacstrap -K base >/dev/null 2>&1
comprobar "con un solo intento, pacstrap se llama una vez" \
  "1" "$(cat "${contador}")"
rm -rf "${lab_pac}"

# Y que el paso de descarga use la funcion, no un pacstrap a pelo. Con un
# 'pacstrap' a pelo, todo lo de arriba seria en balde: el reintento existiria
# pero no se usaria nunca.
if grep -q 'pacstrap_con_reintentos "${ml_medidos}" "${LOG}.pacstrap"' \
     "${RAIZ}/instalador/paso-base.sh" \
   && ! grep -qE '^ *if ! pacstrap -' "${RAIZ}/instalador/paso-base.sh"; then
  ok "y el paso de descarga usa el reintento (si no, todo lo de arriba seria en balde)"
else
  falla "el paso de descarga llama a pacstrap sin reintentos: un espejo atascado vuelve a tumbar la instalacion"
fi
# Cuantos intentos, y que sean mas de uno: reintentar una vez es no reintentar.
intentos="$(reintentos_pacstrap)"
if [[ "${intentos}" =~ ^[1-9][0-9]*$ ]] && (( intentos >= 2 && intentos <= 5 )); then
  ok "se reintenta hasta ${intentos} veces (una sola vez seria no reintentar)"
else
  falla "reintentos_pacstrap() = '${intentos}': o no es un numero, o es 1, o son demasiadas"
fi

# --- 6m. el chroot de mentira: un grupo que no existe y una entrada de mas ----
#
# Los dos fallos de aqui salieron de una instalacion REAL de veinte minutos, en
# dos pasos seguidos, y los dos se pueden reproducir sin disco ni internet con
# un 'arch-chroot' de mentira delante en el PATH.
#
# El falso no es un 'exit 0' a todo: mantiene un /etc/group de verdad, con los
# grupos que trae un 'pacstrap' recien hecho, y su 'useradd' se comporta como el
# de verdad (si le pides un grupo que no existe, dice lo mismo y sale con
# codigo 1). Sin esa regla, 'useradd' de mentira aceptaria cualquier lista de
# grupos y el fallo 25 no apareceria nunca aqui.
echo
echo "== 6m. dentro del chroot: los grupos del usuario y las entradas de arranque =="

lab_ch="${TMPDIR:-/tmp}/titan-chroot-$$"
mkdir -p "${lab_ch}/bin" "${lab_ch}/raiz/etc/default" "${lab_ch}/raiz/etc/sudoers.d"
cat >"${lab_ch}/bin/arch-chroot" <<MENTIRA
#!/bin/sh
# Un 'arch-chroot' de mentira con la regla que hace que se vea el fallo: hay un
# /etc/group de verdad y 'useradd' se comporta como el de verdad, que NO crea
# los grupos que le pidan y avisa si alguno no existe.
raiz="\$1"; shift
# El valor por defecto de las dos variables de este falso (el fichero de
# llamadas y el de grupos) es a proposito: sin el, un falso con la variable sin
# poner crea en el directorio de trabajo un fichero con el NOMBRE de la variable
# dentro. OJO al escribir esto: el heredoc de arriba NO va entrecomillado, asi que
# escribir aqui el nombre de una variable entre llaves la expande al escribir el
# falso, y con 'set -u' eso no es un comentario: es un fallo que deja el falso
# vacio. Passaba, y por eso esta nota.
printf '%s\n' "\$*" >>"\${TITAN_LLAMADAS:-/dev/null}"
grupos_pedidos() {
  anterior=""; dual=""
  for a in "\$@"; do
    [ "\${anterior}" = "--groups" ] && dual="\${a}"
    anterior="\${a}"
  done
  printf '%s' "\${dual}"
}
case "\$1" in
  getent)
    [ "\$2" = "group" ] || exit 0
    grep -q "^\$3:" "\${TITAN_GRUPOS}" 2>/dev/null
    # El 'exit' explicito, y no el del final: un 'getent' que no encuentra el
    # grupo tiene que SALIR con codigo 1, que es lo que hace el de verdad, y es
    # justo lo que decide que un grupo falte. Sin esto el falso decia que
    # existian todos los grupos y el fallo de verdad no aparecia nunca.
    exit \$?
    ;;
  groupadd)
    if grep -q "^\$3:" "\${TITAN_GRUPOS}" 2>/dev/null; then
      echo "groupadd: group '\$3' already exists" >&2
      exit 9
    fi
    n="\$(wc -l <"\${TITAN_GRUPOS}")"
    printf '%s:x:%d:\n' "\$3" "\$(( 900 + n ))" >>"\${TITAN_GRUPOS}"
    ;;
  useradd)
    for g in \$(grupos_pedidos "\$@" | tr ',' ' '); do
      if ! grep -q "^\${g}:" "\${TITAN_GRUPOS}" 2>/dev/null; then
        echo "useradd: group '\${g}' does not exist" >&2
        exit 1
      fi
    done
    ;;
  flatpak)
    case "\$2" in
      remotes)
        # La salida REAL de 'flatpak remotes' en el sistema recien instalado,
        # copiada con 'cat -A' (que es como se saco; sin el, la tabulacion se
        # veria como un espacio y aqui no se distinguiria de un separador
        # normal):
        #
        #     flathub<TAB>system
        #
        # O sea: una TABLA, con el nombre del remoto en la primera columna y de
        # donde esta puesto en la segunda. 'grep -qx flathub', que exige que la
        # linea SEA eso, no casa nunca, y ese era el fallo 28: el paso se
        # paraba ahi, con el sistema entero ya instalado, y las apps no se
        # instalaban nunca. Con '--columns=name' sale solo el nombre.
        # 'TITAN_FLATPAK_SIN_REMOTO=1' hace como que el remoto no esta puesto,
        # para probar el caso de que la comprobacion falle de verdad. Se cambia
        # con una variable y no retocando este fichero con 'sed': un 'sed' con
        # tabulaciones y '\\n' de dentro no casa nunca (en una expresion regular
        # '\n' es un salto de linea, y no hay ninguno), y se queda tan contento
        # probando el caso bueno dos veces.
        # Lo primero es decidir que columnas se piden, y luego lo que hay: si
        # el remoto NO esta puesto (TITAN_FLATPAK_SIN_REMOTO=1) no imprime nada,
        # ni con '--columns=name' ni sin el. Poner el 'if' fuera de los dos
        # casos haria que con '--columns=name' saliese el remoto igual y el
        # aviso no llegaria a aparecer nunca.
        case " \$* " in
          *" --columns=name "*) columnas=name ;;
          *)                      columnas=tabla ;;
        esac
        if [ -n "\${TITAN_FLATPAK_SIN_REMOTO:-}" ]; then
          printf ''
        elif [ "\${columnas}" = "name" ]; then
          printf 'flathub\n'
        else
          printf 'flathub\tsystem\n'
        fi
        ;;
      install)
        # Las apps que llevan 'roto' en el nombre no se pueden instalar, como
        # las que no estan en el remoto o las que no bajan.
        for a in "\$@"; do
          case "\${a}" in *roto*) echo "flatpak: No se encuentra el remoto" >&2; exit 1 ;; esac
        done
        ;;
    esac
    ;;
esac
exit 0
MENTIRA
chmod +x "${lab_ch}/bin/arch-chroot"
# Los grupos que de verdad trae un pacstrap recien hecho. 'seat' NO esta, y no es
# un descuido de la lista: 'wheel', 'audio', 'video', 'storage', 'power',
# 'network' e 'input' los crea el paquete 'filesystem' con reglas de sysusers, y
# 'seat' lo crea 'seatd' con la suya (/usr/lib/sysusers.d/seatd.conf). Las
# reglas de sysusers se aplican al ARRANCAR, y un sistema recien instalado no ha
# arrancado nunca. Esto es lo que de verdad habia en el disco que fallo.
grupos_pacstrap="wheel audio video storage power network input"
{
  for g in ${grupos_pacstrap}; do printf '%s:x:%d:\n' "${g}" "$(( 900 + RANDOM % 90 ))"; done
} >"${lab_ch}/grupos"

E=([usuario]=isai [clave]="clave-de-prueba" [clave_root]="clave-root" \
    [hostname]=titan [zona]=Europe/Madrid [locale]=es_ES.UTF-8 \
    [keymap]=es [teclado_grafico]=es [kernel]=linux-titanlinux \
    [disco]=/dev/vda [modo_arranque]=1 [fs]=btrfs [cifrado]=no \
    [escritorio]=gnome [swap]=zram [bluetooth]=no [apps]=" ufw " \
    [flatpaks]="org.mozilla.firefox org.roto.Navegador")
DESTINO="${lab_ch}/raiz"
TITAN_SILENCIO=1

# --- el fallo 25: un grupo que no existe y no hay usuario --------------------
: >"${lab_ch}/llamadas"
if TITAN_GRUPOS="${lab_ch}/grupos" TITAN_LLAMADAS="${lab_ch}/llamadas" \
   PATH="${lab_ch}/bin:${PATH}" paso_sistema >/dev/null 2>&1; then
  ok "el paso de cuentas va con un chroot donde falta 'seat' (que es el caso real)"
else
  falla "el paso de cuentas falla con un chroot donde falta un grupo de la lista"
  nota "  con un pacstrap recio hecho no esta 'seat', y 'useradd' no crea lo que no existe"
fi
comprobar "y el grupo que faltaba se ha creado" \
  "1" "$(grep -c '^seat:' "${lab_ch}/grupos" || true)"
# Y no solo que acabe bien: que se haya PREGUNTADO por cada grupo antes de
# usarlo. Un arreglo que creara los grupos a lo bruto (todos, sin mirar) pasaria
# el caso de arriba solo en un sistema donde no existiera ninguno, que no es el
# caso de verdad: en el de verdad existen siete de los ocho.
pedidos="$(sed -n 's/.*--groups \([^ ]*\).*/\1/p' "${lab_ch}/llamadas" | head -1)"
sin_preguntar=""
for g in ${pedidos//,/ }; do
  grep -q "^getent group ${g}$" "${lab_ch}/llamadas" || sin_preguntar+="${g} "
done
comprobar "y se ha preguntado por cada grupo de la lista antes de usarlo" \
  "" "${sin_preguntar}"
# Y que no se creen los que ya existen: en el sistema de verdad, 'wheel' y los
# otros siete SI estan, y un 'groupadd' de un grupo que existe sale con codigo 9
# ('group already exists'), que con el '|| return 1' de la funcion pararia la
# instalacion entera. O sea: un arreglo que crease todos los grupos sin mirar
# rompe el caso real para arreglar el de mentira.
cp "${lab_ch}/grupos" "${lab_ch}/grupos-todos"
printf 'seat:x:968:\n' >>"${lab_ch}/grupos-todos"
: >"${lab_ch}/llamadas"
if TITAN_GRUPOS="${lab_ch}/grupos-todos" TITAN_LLAMADAS="${lab_ch}/llamadas" \
   PATH="${lab_ch}/bin:${PATH}" paso_sistema >/dev/null 2>&1; then
  if [[ -n "$(grep -c '^groupadd' "${lab_ch}/llamadas")" ]] 2>/dev/null; then :; fi
  comprobar "con todos los grupos ya existentes no se crea ninguno" \
    "0" "$(grep -c '^groupadd' "${lab_ch}/llamadas" || true)"
else
  falla "el paso de cuentas falla cuando los grupos YA existen todos"
  nota "  un groupadd de un grupo que ya existe sale con codigo 9 y pararia la instalacion"
fi
# Y que si la creacion falla, LO DIGA, en vez de seguir como si nada. Esto se
# mira en la propia funcion, y no en el paso entero, porque hay dos motivos por
# los que el paso puede acabar mal y solo uno es el que sirve: si
# 'asegurar_grupos' se come el fallo de 'groupadd' y devuelve 'todo bien', el
# 'useradd' de despues falla igualmente (porque el grupo sigue sin existir) y el
# paso tambien acaba en error, pero el motivo se ha perdido. Con un '|| true'
# debajo, mirado desde fuera, el fallo real y el falso se ven IGUALES. Por eso
# se llama a la funcion, que es la que tiene que saberlo.
mv "${lab_ch}/bin/arch-chroot" "${lab_ch}/bin/arch-chroot.bak"
printf '#!/bin/sh\nexit 7\n' >"${lab_ch}/bin/arch-chroot"
chmod +x "${lab_ch}/bin/arch-chroot"
cp "${lab_ch}/grupos" "${lab_ch}/grupos-sin-crear"
if TITAN_GRUPOS="${lab_ch}/grupos-sin-crear" TITAN_LLAMADAS="${lab_ch}/llamadas" \
   PATH="${lab_ch}/bin:${PATH}" asegurar_grupos "${DESTINO}" "seat" \
   >/dev/null 2>&1; then
  falla "asegurar_grupos dice que ha ido bien cuando NO puede crear el grupo"
  nota "  y el 'useradd' de despues falla por otra causa: el aviso util, de que grupos y por que, se pierde"
else
  ok "asegurar_grupos falla si no puede crear el grupo que falta"
fi
if TITAN_GRUPOS="${lab_ch}/grupos-sin-crear" TITAN_LLAMADAS="${lab_ch}/llamadas" \
   PATH="${lab_ch}/bin:${PATH}" paso_sistema >/dev/null 2>&1; then
  falla "y el paso de cuentas tambien, en vez de seguir con un usuario sin grupos"
else
  ok "y con eso, el paso de cuentas para y lo dice"
fi
mv "${lab_ch}/bin/arch-chroot.bak" "${lab_ch}/bin/arch-chroot"

# --- el fallo 28: el remoto esta puesto y la comprobacion no lo ve ------------
#
# 'flatpak remotes' imprime una TABLA ('flathub<TAB>system'), no un nombre por
# linea. Con 'grep -qx flathub', que exige que la linea SEA eso, la
# comprobacion no casa nunca, y el paso de la tienda se paraba ahi con el
# sistema entero ya instalado. Lo grave no es que el remoto faltara: es que la
# comprobacion daba falso con el remoto PUESTO y en su sitio.
# El log del instalador se manda aqui con LOG=, no con TITAN_LOG=: la
# variable LOG se fija CUANDO SE CARGA lib-comun.sh (que el comprobador
# hizo al principio de todo), asi que exportar TITAN_LOG ahora no cambia
# nada y el aviso se iria al log de verdad del sistema.
log_instalador="${lab_ch}/instalador.log"
: >"${lab_ch}/llamadas"
E[flatpak_fallos]=""
if TITAN_GRUPOS="${lab_ch}/grupos-todos" TITAN_LLAMADAS="${lab_ch}/llamadas" \
   LOG="${log_instalador}" PATH="${lab_ch}/bin:${PATH}" paso_flatpak >/dev/null 2>&1; then
  ok "el paso de la tienda sigue adelante con el remoto de Flathub puesto"
else
  falla "el paso de la tienda se para con el remoto PUESTO y en su sitio"
  nota "  'flatpak remotes' imprime una tabla, no un nombre por linea: 'grep -qx' no casa nunca"
fi
comprobar "y se han instalado las dos apps" \
  "2" "$(grep -c '^flatpak install' "${lab_ch}/llamadas" || true)"
# Y lo de verdad importante: una app que no baja no puede parar la instalacion
# entera, y tiene que quedar apuntada para el final, que es donde se le dice al
# usuario lo que falta (el fallo 24 otra vez, la misma idea).
comprobar "y la app que no se pudo instalar queda apuntada para el final" \
  "org.roto.Navegador " "${E[flatpak_fallos]}"
comprobar "y sale en el log, con el nombre de la app" \
  "1" "$(grep -c 'no se ha podido instalar la app org.roto.Navegador' "${lab_ch}/instalador.log" || true)"
# Y que una comprobacion de la lista no puede decidir que la instalacion se
# para. Aqui el remoto NO esta (el falso imprime la lista vacia) y aun asi el
# paso tiene que acabar bien: lo que se pierde son las apps, que es un aviso, no
# el sistema entero que ya esta instalado y funcionando.
export TITAN_FLATPAK_SIN_REMOTO=1
: >"${lab_ch}/llamadas"
E[flatpaks]="org.mozilla.firefox"
E[flatpak_fallos]=""
if TITAN_GRUPOS="${lab_ch}/grupos-todos" TITAN_LLAMADAS="${lab_ch}/llamadas" \
   LOG="${log_instalador}" PATH="${lab_ch}/bin:${PATH}" paso_flatpak >/dev/null 2>&1; then
  ok "y sin remoto, el paso tampoco para la instalacion (avisa y sigue)"
else
  falla "sin remoto, el paso para la instalacion: se tira el sistema entero por una comprobacion"
fi
comprobar "y avisa de que el remoto no aparece" \
  "1" "$(grep -c 'AVISO.*no aparece en la lista' "${lab_ch}/instalador.log" || true)"
unset TITAN_FLATPAK_SIN_REMOTO
E[flatpaks]="org.mozilla.firefox org.roto.Navegador"

# --- el fallo 26: dos entradas de arranque en el firmware ---------------------
#
# 'grub-install' en UEFI registra en el firmware una entrada de arranque con el
# nombre del '--bootloader-id', salvo que se le diga '--no-nvram'. Y el
# instalador, despues, crea OTRA a proposito con 'efibootmgr' para poder poner
# el nombre con espacio. Las dos juntas: dos entradas de Titan en el menu del
# firmware, que es lo que aparecio en la UEFI de la instalacion.
: >"${lab_ch}/llamadas"
TITAN_GRUPOS="${lab_ch}/grupos-todos" TITAN_LLAMADAS="${lab_ch}/llamadas" \
  PATH="${lab_ch}/bin:${PATH}" paso_grub >/dev/null 2>&1
comprobar "en UEFI se crea una sola entrada en el firmware" \
  "1" "$(grep -c 'efibootmgr --create' "${lab_ch}/llamadas" || true)"
# Y el motivo: ningun 'grub-install' puede registrar una entrada por su cuenta.
sin_nvram="$(grep '^grub-install' "${lab_ch}/llamadas" | grep -vc -- '--no-nvram' || true)"
comprobar "y ningun grub-install registra entradas por su cuenta" \
  "0" "${sin_nvram}"
# Y que la entrada se sigue creando, que es lo que hacia el 'grub-install' solo
# cuando se le quita el '--no-nvram': quitar '--no-nvram' no puede quedarse en
# 'cero entradas'.
if grep -q 'efibootmgr --create.*--label' "${lab_ch}/llamadas"; then
  ok "y la entrada del firmware se sigue creando, con su nombre y su disco"
else
  falla "no hay ninguna llamada a 'efibootmgr --create': el equipo no arranca solo"
fi
# Y en BIOS ni se toca el firmware: 'efibootmgr' no existe ahi, y la entrada la
# pone el 'grub-install' sobre el MBR.
E[modo_arranque]=0
: >"${lab_ch}/llamadas"
TITAN_GRUPOS="${lab_ch}/grupos-todos" TITAN_LLAMADAS="${lab_ch}/llamadas" \
  PATH="${lab_ch}/bin:${PATH}" paso_grub >/dev/null 2>&1
comprobar "y en BIOS no se toca el firmware (que no tiene entradas de UEFI)" \
  "0" "$(grep -c 'efibootmgr' "${lab_ch}/llamadas" || true)"
E[modo_arranque]=1
rm -rf "${lab_ch}"

# --- 6k. al fallar, el destino se queda desmontado -----------------------------
#
# 'desmontar()' solo se llamaba cuando todo iba bien. Cuando la instalacion se
# paraba a mitad, /mnt se quedaba montado, y eso no era un detalle: lo que
# venia despues (medir lo que habia quedado, o repetir la instalacion desde la
# misma sesion) se encontraba con un /mnt que era otro sistema montado encima.
# Todo lo que se buscaba ahi aparecia como inexistente, porque se estaba
# mirando un nivel mas abajo de donde estaba. Pasaba de verdad: cuatro
# comprobaciones de la fase 4 dieron 'no existe' con el sistema recien
# instalado en el disco de al lado.
#
# Aqui no se mira el texto de install.sh (que 'desmontar' aparezca dos veces no
# dice nada de si se llama antes de salir). Se ejecuta el 'main' DE VERDAD, con
# un 'umount' de mentira delante en el PATH que apunta a un fichero de registro,
# y se mira ese fichero. Lo unico que se falsea son los pasos que instalan de
# verdad, que aqui no se pueden ejecutar (uno de ellos borraria el disco).
echo
echo "== 6k. al fallar, el destino se desmonta tambien =="

install_sh="${DISTRO}/iso/titan/airootfs/root/install.sh"
lab_dir="${TMPDIR:-/tmp}/titan-desmontar-$$"
mkdir -p "${lab_dir}/bin"
# El 'umount' de mentira: no desmonta nada (que no hay nada montado), pero deja
# constancia. Sin el, 'desmontar()' no deja ninguna huella en el mundo y esta
# comprobacion no tendria nada que mirar.
cat >"${lab_dir}/bin/umount" <<'MENTIRA'
#!/bin/sh
printf 'umount %s\n' "$*" >>"${TITAN_UMOUNT_LOG}"
exit 0
MENTIRA
chmod 755 "${lab_dir}/bin/umount"

# El install.sh de verdad, pero sin la ultima linea ('main "$@"'), para poder
# llamarlo con las funciones cambiadas. Todo lo de encima de esa linea se
# ejecuta igual: los flags, el log y los siete modulos.
# Y el directorio de modulos al lado, porque install.sh los busca donde esta el
# propio install.sh ('${BASH_SOURCE[0]}/instalador'), no donde se ejecuta.
sed '$ d' "${install_sh}" >"${lab_dir}/install-sin-main.sh"
ln -s "${RAIZ}/instalador" "${lab_dir}/instalador"

probar_salida() { # probar_salida CODIGO_QUE_DEVUELVE_INSTALAR ETIQUETA
  local codigo="$1" etiqueta="$2" registro
  registro="${lab_dir}/registro-${codigo}.txt"
  : >"${registro}"
  # OJO al nombre de la variable de dentro del arnes: NO puede ser 'codigo'. En
  # bash las variables son dinamicas, y 'main' tiene un 'local codigo' suyo: si
  # el arnes se llamara 'codigo', 'instalar' devolveria el 0 de 'main' en vez
  # del codigo que se le pide, y las comprobaciones estarian probando el mismo
  # camino (el bueno) varias veces, todas en verde. Pasaba: la del 'fallar a
  # mitad' estaba en realidad probando el camino bueno, y daba verde por lo
  # mismo que daba verde la de al lado.
  #
  # Por eso la variable se llama 'que_devuelve', y por eso, debajo, se mira con
  # que codigo ha salido main: si el arnes mintiera, el 'main sale con' falla y
  # se ve en cual de las comprobaciones, no en todas.
  # OJO al flag de autopilot: es 'TITAN_AUTOPILOTO', no 'AUTO'. install.sh
  # empieza con 'AUTO=${TITAN_AUTOPILOTO:-0}', asi que poner 'AUTO=1' en el
  # entorno no hace nada: se pisa al cargar. Sin esto, el instalador se para a
  # ensenar la ventana de error de verdad, con dialog, y la salida del arnes
  # son veinte lineas de cuadritos de colores.
  #
  # Y este comentario va ANTES de la orden, no en medio de las lineas con
  # barra: una 'backslash' seguida de una linea de comentario mete la orden
  # entera dentro del comentario y no se ejecuta nada. Pasaba, y era
  # especialmente traicionero porque los ficheros de salida no se vaciaban
  # antes: el arnes leia lo de la vez anterior y daba verde sin mirar nada. Por
  # eso ahora se vacian explicitamente.
  : >"${lab_dir}/salida-${codigo}.txt"
  PATH="${lab_dir}/bin:${PATH}" \
  TITAN_UMOUNT_LOG="${registro}" \
  TITAN_LOG="${lab_dir}/install-${codigo}.log" \
  TITAN_SILENCIO=1 \
  TITAN_AUTOPILOTO=1 \
  bash -c '
    set -euo pipefail
    # Al cargar un script con '"'"'source'"'"' hereda sus argumentos, y el bucle
    # de opciones de install.sh los leeria como opciones suyas ("Opcion
    # desconocida: /tmp/.../install-sin-main.sh"). Se limpian antes.
    fichero="$1"; que_devuelve="$2"; set --
    source "${fichero}"
    # Lo que se falsea es el entorno y los pasos que de verdad tocan el disco.
    # El '"'"'main'"'"', el '"'"'paso'"'"', el '"'"'resumen_pasos'"'"' y el '"'"'desmontar'"'"' son LOS DE VERDAD.
    comprueba_entorno() { :; }
    banner() { :; }
    instalar() { return "${que_devuelve}"; }
    pantalla_final() { :; }
    preguntar_reiniciar() { :; }
    # En un subshell, porque main() acaba con '"'"'exit'"'"' y si no este script
    # se saldria antes de poder mirar nada. El codigo con el que sale main es lo
    # que dice que camino se ha tomado de verdad.
    salida_main=0
    ( main ) || salida_main=$?
    echo "main-sale-con=${salida_main}"
  ' _ "${lab_dir}/install-sin-main.sh" "${codigo}" >"${lab_dir}/salida-${codigo}.txt" 2>&1 || true
  # El 3 es el boton de cancelar: main sale con 0 (no es un fallo) y no se toca
  # el disco. Cualquier 1 es un fallo de verdad, y main sale con 1.
  local esperado_main=1
  [[ "${codigo}" -eq 0 || "${codigo}" -eq 3 ]] && esperado_main=0
  # El numero no se busca con 'grep -qx' (linea entera exacta) porque a su lado
  # queda todo lo que pinte dialog en esa misma linea. Se saca el ultimo.
  if [[ "$(grep -ao 'main-sale-con=[0-9]*' "${lab_dir}/salida-${codigo}.txt" \
          | tail -1)" == "main-sale-con=${esperado_main}" ]]; then
    ok "el arnes toma el camino que cree: main sale con ${esperado_main} si instalar devuelve ${codigo}"
  else
    falla "el arnes no ha tomado el camino que creia: main deberia salir con ${esperado_main} y sale con $(grep -ao 'main-sale-con=[0-9]*' "${lab_dir}/salida-${codigo}.txt" | paste -sd' ' -)"
    nota "  salida: $(tail -3 "${lab_dir}/salida-${codigo}.txt" | paste -sd'; ')"
  fi
  # Y ahora lo que de verdad importa en cada camino.
  if [[ "${codigo}" -eq 3 ]]; then
    if [[ ! -s "${registro}" ]]; then
      ok "al cancelar no se desmonta nada: el disco esta intacto, no hay nada que soltar"
    else
      falla "al cancelar se desmonta (y no hace falta): $(paste -sd'; ' <"${registro}")"
    fi
  elif [[ -s "${registro}" ]]; then
    ok "al ${etiqueta}, el destino se desmonta: $(paste -sd'; ' <"${registro}")"
  else
    falla "al ${etiqueta}, nada se ha desmontado y el destino se queda montado"
    nota "  salida de main: $(grep -a 'se ha parado' "${lab_dir}/salida-${codigo}.txt" | head -1)"
  fi
}
probar_salida 1 "fallar a mitad"
probar_salida 0 "terminar bien"
probar_salida 3 "cancelar"

# --- el fallo 30: 'umount' dice 'el destino esta ocupado' y ahi se acaba -----
#
# Lo que paso de verdad: el instalador dejo /mnt montado (el sistema destino) y al
# final 'umount -R /mnt' contesto las dos veces 'el destino esta ocupado'. El
# codigo de entonces se quedaba en un aviso y seguia, con el /mnt puesto. Y el
# /mnt puesto es lo que hace que todo lo que venga despues mire donde no es: la
# comprobacion de la fase 4 del driver que busca los subvolumenes dio cero, las
# veinte siguientes de dentro del sistema dijeron 'no existe', y el informe de la
# instalacion parecio un fallo del sistema instalado cuando lo unico que
# faltaba era el desmontaje.
#
# Aqui se ejecuta 'desmontar()' DE VERDAD, con un 'umount' delante que se deja
# mandar (que es lo unico que se falsea) y que falla el numero de veces que se le
# diga. Se prueban los tres caminos: que va bien a la primera, que falla una vez
# y se recupera, que no hay quien lo suelte nunca pero 'umount -l' si, y que ni
# con 'umount -l' se puede (que es el unico caso en el que se rinde de verdad).
echo
echo "== 6k2. cuando /mnt esta ocupado: que dice quien lo tiene y lo suelta =="
mkdir -p "${lab_dir}/bin2"
cat >"${lab_dir}/bin2/umount" <<MENTIRA
#!/bin/sh
printf 'umount %s\n' "\$*" >>"\${TITAN_UMOUNT_LOG}"
# El '-l' es el ultimo recurso: suelta el montaje aunque algo lo tenga cogido.
# Los intentos de verdad fallan las veces que diga el contador, que es como se
# pueden probar los dos caminos (el que se recupera y el que se rinde).
case " \$* " in
  *" -l "*)
    [ "\${TITAN_UMOUNT_L_FALLA:-0}" = "1" ] && exit 32
    exit 0
    ;;
esac
# Y un montaje CONCRETO que no se deja soltar nunca, por ruta (fallo 38). Sin
# esto no se puede probar lo unico que el arreglo anade al log: el aviso de
# 'desmontar()' decia que no se habia podido soltar /mnt del todo, y no decia
# CUAL de los montajes se resistia, que es lo unico que hace falta para
# seguir. Con un contador que falla 'n' veces, el que se resiste es SIEMPRE el
# primero, y ademas el 'umount -R' entero es el que se para: para nombrar un
# montaje concreto tiene que ser ese.
if [ -n "\${TITAN_UMOUNT_ATASCADO:-}" ]; then
  case " \$* " in
    *"\${TITAN_UMOUNT_ATASCADO} "*)
      echo "umount: \$*: el destino esta ocupado." >&2
      exit 32
      ;;
  esac
fi
n="\$(cat "\${TITAN_UMOUNT_FALLOS}" 2>/dev/null || echo 0)"
if [ "\${n}" -gt 0 ]; then
  echo "\$((n - 1))" >"\${TITAN_UMOUNT_FALLOS}"
  echo "umount: \$*: el destino esta ocupado." >&2
  exit 32
fi
exit 0
MENTIRA
chmod 755 "${lab_dir}/bin2/umount"

# Y un 'findmnt' de mentira que HONRA los argumentos, porque el codigo hace DOS
# preguntas distintas y con formatos distintos: una para la lista de rutas ('-rn
# -o TARGET', una linea por montaje) y otra para la tabla del aviso ('-rn -o
# TARGET,SOURCE,FSTYPE'). Un 'findmnt' falso que imprimiese siempre la misma
# tabla no distinguiria los dos caminos, y ademas el 'findmnt -R' con cabecera de
# antes ya no es lo que se llama.
#
# Lo que 've' sale de TITAN_MONTADOS, un fichero con una linea por montaje
# ('objetivo fuente tipo'), que es lo que cambia de caso en caso. Los tres casos
# que de verdad importan:
#   * 'dentro': hay algo DENTRO de /mnt (el /proc que arch-chroot deja al
#     salir, que ni 'ps' ni '/proc/*/cwd' ven). Es lo que la tabla tiene que
#     se ve y lo que se puede decir 'es un montaje de dentro'.
#   * 'solo': lo unico montado es el propio /mnt. ES EL CASO DE LA PASADA REAL
#     DE UEFI DEL 29 DE SEPTIEMBRE: la tabla de una sola linea, y el aviso
#     rematando 'lo que lo tiene es un montaje de dentro de /mnt' (fallo 38).
#   * 'nada': no queda ni el propio. 'findmnt' sale con codigo 1 y sin imprimir
#     nada, que es lo que hace de verdad cuando no hay nada.
cat >"${lab_dir}/bin2/findmnt" <<'MENTIRA'
#!/bin/sh
# Lo unico que este 'findmnt' imprime es lo que hay en el fichero de montajes;
# los argumentos se HONRAN (columnas y raiz), que es lo que hace que el arnes
# pueda poner el codigo del producto en un caso y en otro sin tocarlo.
col="TARGET"
raiz=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) col="$2"; shift 2 ;;
    -R) raiz="$2"; shift 2 ;;
    -r|-n) shift ;;
    *) shift ;;
  esac
done
n=0
[ -r "${TITAN_MONTADOS}" ] || exit 1
while IFS= read -r linea; do
  # El '#' va entrecomillado porque en 'sh' (dash) un '#' justo detras del 'in'
  # es principio de comentario: el falso findmnt se quedaba con un error de
  # sintaxis y no imprimia nada, que es justo el fallo del comprobador entero
  # (dar verde mirando una tabla que no salio).
  case "${linea}" in '#'*|"") continue ;; esac
  set -- ${linea}
  [ -n "${1:-}" ] || continue
  if [ -n "${raiz}" ]; then
    case "${1}" in
      "${raiz}"|"${raiz}"/*) ;;
      *) continue ;;
    esac
  fi
  n=$((n + 1))
  case "${col}" in
    TARGET) printf '%s\n' "${1}" ;;
    TARGET,SOURCE,FSTYPE) printf '%s %s %s\n' "${1}" "${2}" "${3}" ;;
    *) printf '%s\n' "${1}" ;;
  esac
done <"${TITAN_MONTADOS}"
# 'findmnt' sale con 1 si no ha encontrado nada, que es lo que hace de verdad.
[ "${n}" -gt 0 ] || exit 1
exit 0
MENTIRA
chmod 755 "${lab_dir}/bin2/findmnt"

# Los tres ficheros de montajes de mentira. El '/mnt/proc' del primero es el
# caso de verdad que se quiere ver nombrado, y es una linea que no puede salir
# por casualidad.
#
# Los montajes que 've' se escriben en cada caso, con el destino que tenga ese
# caso (ver 'desmontar_caso'), porque hay comprobaciones que necesitan un destino
# que no sea '/mnt'.

# El arnes: el 'desmontar' de verdad, con el motor de verdad delante. Solo se
# falsea 'umount' y 'findmnt'. El 'sleep 2' del reintento se deja en blanco
# porque aqui lo que se prueba es el camino que se toma, no lo que tarda.
cat >"${lab_dir}/arnes-desmontar.sh" <<'ARNES'
set -uo pipefail
RAIZ="$1"
# OJO: el log se manda con TITAN_LOG= y no con LOG=. 'LOG' lo fija lib-comun.sh
# al cargarse ('LOG="${TITAN_LOG:-/var/log/titan-install.log}"'), asi que poner
# 'LOG=' aqui no haria nada y los avisos se irian al log de verdad del sistema.
TITAN_LOG="$2"
# 'DESTINO' lo pone el instalador, no el motor: sin el, 'desmontar()' se para
# en su primera linea con 'DESTINO: unbound variable' y no se llega a mirar nada.
#
# Y por defecto es '/mnt', pero se puede cambiar (el quinto argumento) porque
# hay UNA comprobacion que necesita un destino que no sea '/mnt': la que mira los
# montajes que hay en el espacio de montajes de OTRO proceso. Con '/mnt' el
# resultado dependeria de lo que tenga montado cada proceso de la maquina, y una
# comprobacion que depende de eso no es una comprobacion.
DESTINO="${5:-/mnt}"
TITAN_SILENCIO=1
# Las del 'umount' y del 'findmnt' de mentira van exportadas: las lee el proceso
# hijo, y una variable sin exportar no llega a el (el hijo se las encontraria
# vacias y escribiria su registro en el fichero de nombre vacio, que es un fallo
# que parece que el arnes no ha hecho nada).
export TITAN_UMOUNT_LOG="$3" TITAN_UMOUNT_FALLOS="$4"
export TITAN_MONTADOS="${TITAN_MONTADOS:-}" TITAN_UMOUNT_ATASCADO="${TITAN_UMOUNT_ATASCADO:-}"
source "${RAIZ}/instalador/lib-comun.sh"
source "${RAIZ}/instalador/paso-cerrar.sh"
sleep() { :; }
salida=0
desmontar || salida=$?
echo "desmontar-sale-con=${salida}"
ARNES

desmontar_caso() { # desmontar_caso FALLOS L_FALLA CODIGO_ESPERADO ETIQUETA [MODO] [ATASCADO] [DESTINO]
  local nfallos="$1" lfalla="$2" esperado="$3" etiqueta="$4"
  local modo="${5:-dentro}" atascado="${6:-}" destino="${7:-/mnt}"
  local montados="${lab_dir}/montados-${modo}"
  local etiqueta_log="${nfallos}-${lfalla}-${modo}-${destino##*/}"
  # Lo que 've' el 'findmnt' de mentira, con las rutas del destino de este caso
  # (que no siempre es '/mnt', y por eso no pueden estar escritas de antemano).
  case "${modo}" in
    dentro)
      printf '%s /dev/vda2[/@] btrfs\n%s/proc proc proc\n' \
        "${destino}" "${destino}" >"${montados}"
      ;;
    solo) printf '%s /dev/vda2[/@] btrfs\n' "${destino}" >"${montados}" ;;
    nada) : >"${montados}" ;;
    *) echo "modo de montajes desconocido: ${modo}"; exit 2 ;;
  esac
  local registro="${lab_dir}/reg-${etiqueta_log}.txt"
  local log="${lab_dir}/log-${etiqueta_log}.txt"
  local cuenta="${lab_dir}/cuenta-${etiqueta_log}"
  echo "${nfallos}" >"${cuenta}"
  : >"${registro}"
  : >"${log}"
  local salida
  salida="$(PATH="${lab_dir}/bin2:${PATH}" TITAN_UMOUNT_L_FALLA="${lfalla}" \
    TITAN_MONTADOS="${montados}" TITAN_UMOUNT_ATASCADO="${atascado}" \
    bash "${lab_dir}/arnes-desmontar.sh" "${RAIZ}" "${log}" "${registro}" \
         "${cuenta}" "${destino}" 2>&1 || true)"
  if grep -aq "desmontar-sale-con=${esperado}" <<<"${salida}"; then
    ok "${etiqueta}: desmontar() sale con ${esperado}"
  else
    falla "${etiqueta}: desmontar() deberia salir con ${esperado}"
    nota "  sale con: $(grep -ao 'desmontar-sale-con=[0-9]*' <<<"${salida}" | paste -sd' ' -)"
  fi
  DESMONTAR_REGISTRO="${registro}"
  DESMONTAR_LOG="${log}"
}

# 1. A la primera. Un intento, y sin tocar nada mas.
desmontar_caso 0 0 0 "si /mnt no esta ocupado"
comprobar "  y basta con un 'umount -R'" \
  "umount -R /mnt" "$(paste -sd'; ' <"${DESMONTAR_REGISTRO}")"
comprobar "  y no hace falta soltarlo a la fuerza ('umount -l')" \
  "0" "$(grep -c ' -l' "${DESMONTAR_REGISTRO}" || true)"

# 2. Falla una vez (el caso de verdad: algo cogia /mnt en ese momento) y la
#    segunda vez va. Se reintenta y ya esta: nada de 'umount -l'.
desmontar_caso 1 0 0 "si /mnt esta ocupado la primera vez"
comprobar "  se reintenta una vez y con eso vale" \
  "2" "$(grep -c '^umount -R /mnt$' "${DESMONTAR_REGISTRO}" || true)"
comprobar "  y no hace falta soltarlo a la fuerza" \
  "0" "$(grep -c ' -l' "${DESMONTAR_REGISTRO}" || true)"

# 3. No hay quien lo suelte nunca, pero 'umount -l' si. Aqui lo que se exige es
#    que la instalacion pueda TERMINAR: con el sistema ya instalado, un /mnt que
#    se queda puesto es peor que uno soltado a la fuerza.
desmontar_caso 9 0 0 "si no hay quien lo suelte pero 'umount -l' si"
comprobar "  se llega a 'umount -l' al final" \
  "umount -l -R /mnt" "$(tail -1 "${DESMONTAR_REGISTRO}")"
comprobar "  y se avisa de que ha tenido que soltarlo a la fuerza" \
  "1" "$(grep -c 'se ha soltado a la fuerza' "${DESMONTAR_LOG}" || true)"

# 4. Ni con 'umount -l'. Este es el unico caso en el que se rinde, y tiene que
#    decirlo: el aviso de antes ('quedan montajes dentro de /mnt') no decia
#    NADA de por que se quedaba montado, y sin eso no habia ni una pista.
desmontar_caso 9 1 1 "si ni siquiera 'umount -l' puede"
comprobar "  y avisa de que tampoco con 'umount -l'" \
  "1" "$(grep -c 'tampoco: quedan montajes dentro de /mnt' "${DESMONTAR_LOG}" || true)"
comprobar "  y dice que no se ha podido soltar del todo" \
  "1" "$(grep -c 'no se ha podido soltar /mnt del todo' "${DESMONTAR_LOG}" || true)"
comprobar "  y mira quien lo tiene, aunque no encuentre a nadie" \
  "1" "$(grep -c 'no hay ningun proceso con el directorio de trabajo' "${DESMONTAR_LOG}" || true)"
# El fallo 35: el aviso de antes decia COMO se veia lo que quedaba montado
# ('se ve con findmnt -R /mnt') y ahi se acababa la pista, que es justo cuando
# hace falta VERLO. Ahora se imprime la tabla, y en el log, que es lo que se
# lee cuando el instalador ya ha acabado.
# Dos veces, y no una: la tabla se muestra en los DOS caminos en los que el
# instalador se rinde --antes de mirar los procesos, y otra vez cuando 'umount
# -l' tampoco ha podido--. Con la cuenta a 1, un comprobador al que le
# quitaran el segundo 'tabla_montajes' (que es el que dice que sigue montado
# DESPUES de haberlo soltado a la fuerza) seguiria dando verde.
# Anclada a la linea de la tabla ('/mnt/proc proc proc' y nada mas) y no a
# cualquier mencion de '/mnt/proc': con el arreglo del fallo 38 el log tambien
# nombra el montaje que se resiste, y contando 'mnt/proc' a secas ese nombre
# hacia que la cuenta saliera 3 y esta comprobacion dejara de mirar lo que dice.
# Un comprobador que se conforma con mas cosas de las que debe es un comprobador
# que puede dar verde por el motivo equivocado.
comprobar "  y ENSENA la tabla de lo que queda montado, en los dos caminos" \
  "2" "$(grep -c '^/mnt/proc proc proc$' "${DESMONTAR_LOG}" || true)"
# Y que NOMBRE los montajes que se resisten, que es lo que un 'umount -R' no
# dice nunca: se para en el primero que falla y no dice cual es.
comprobar "  y NOMBRA el montaje que se resiste (el hijo primero)" \
  "1" "$(grep -c 'es el que se resiste: /mnt/proc' "${DESMONTAR_LOG}" || true)"
comprobar "  y la tabla esta en el log, no solo en la pantalla" \
  "2" "$(grep -c 'esto es lo que sigue montado dentro de /mnt' "${DESMONTAR_LOG}" || true)"
comprobar "  y el aviso del proceso sin proceso remata la pista" \
  "1" "$(grep -c 'la tabla de arriba lo dice' "${DESMONTAR_LOG}" || true)"

# --- el fallo 38: el diagnostico que se contradice a si mismo ----------------
#
# Lo que paso en la pasada real de UEFI del 29 de septiembre a la 01:07. La
# tabla de montajes del log real fue de UNA sola linea:
#
#     /mnt /dev/vda2[/@] btrfs  rw,relatime,...
#
# que es el PROPIO /mnt y nada mas dentro, y el aviso de abajo remataba:
#
#     asi que lo que lo tiene es un montaje de dentro de /mnt, y la tabla de
#     arriba lo dice
#
# Es decir: el aviso afirmaba una cosa y la tabla que tenia delante, esa misma,
# decia lo contrario. Y la causa de que se pudiera escribir era que el codigo de
# la conclusion no miraba NADA: el 'if (( ! encontrado ))' (que solo dice que no
# hay procesos) remataba siempre igual.
#
# Estos casos usan un destino que NO es '/mnt' (uno del laboratorio), porque la
# ultima comprobacion de esta seccion mira lo que hay montado en el espacio de
# montajes de los OTROS procesos, y con '/mnt' el resultado dependeria de como
# este montada la maquina donde se corre el comprobador.
dest_lab="${lab_dir}/mnt"

# 5. El caso de verdad: lo unico montado es el propio /mnt. El aviso tiene que
#    decir que sigue montado SIN NINGUN montaje dentro, y sobre todo NO puede
#    decir lo contrario.
desmontar_caso 9 1 1 "si lo unico que sigue montado es el propio destino" \
  solo "" "${dest_lab}"
# DOS veces, no una: 'desmontar()' se rinde en dos caminos (antes de mirar los
# procesos, y otra vez cuando 'umount -l' tampoco ha podido) y en los dos se ve
# la tabla, que es lo que se lee cuando el instalador ya ha acabado.
comprobar "  dice que sigue montado y que NO hay nada dentro, en los dos caminos" \
  "2" "$(grep -c 'sigue montado y no hay NINGUN montaje dentro de el' "${DESMONTAR_LOG}" || true)"
comprobar "  y NO dice que lo tenga un montaje de dentro" \
  "0" "$(grep -c 'lo que lo tiene es un montaje de dentro' "${DESMONTAR_LOG}" || true)"
# Y que la tabla NO disimule: sale el propio destino y nada mas dentro. Anclada
# a la linea entera de la tabla, con su '[AVISO]' delante, porque el aviso de
# 'quien_lo_tiene' dice 'no hay NINGUN montaje dentro' y una cuenta sin ancla lo
# contaria como si fuera la tabla.
comprobar "  y la tabla no lo disimula: sale el propio destino y nada mas" \
  "2" "$(grep -c "AVISO] ${dest_lab} /dev/vda2\[/@\] btrfs\$" "${DESMONTAR_LOG}" || true)"
comprobar "  y la tabla no trae NINGUN montaje de dentro" \
  "0" "$(grep -c "AVISO] ${dest_lab}/" "${DESMONTAR_LOG}" || true)"
comprobar "  y remata que lo que no se suelta es el montaje del propio destino" \
  "1" "$(grep -c 'lo que no se suelta es el montaje de .* MISMO' "${DESMONTAR_LOG}" || true)"
# Y que mire, ademas, los montajes que hay en el espacio de montajes de OTRO
# proceso, que es donde se esconden los que 'arch-chroot' deja al salir. Con un
# destino del laboratorio y no '/mnt' el resultado no depende de como este
# montada la maquina donde corre el comprobador, que si no no seria una
# comprobacion sino una apuesta.
comprobar "  y mira tambien los espacios de montajes de los otros procesos" \
  "1" "$(grep -c "y en ningun otro espacio de montajes hay nada montado dentro de ${dest_lab}" "${DESMONTAR_LOG}" || true)"

# 6. Y lo contrario: si HAY algo dentro, el aviso sigue siendo el de antes, que
#    es el que se puede sostener con la tabla delante.
desmontar_caso 9 1 1 "si hay un montaje escondido dentro del destino" \
  dentro "" "${dest_lab}"
comprobar "  entonces si dice que lo tiene un montaje de dentro" \
  "1" "$(grep -c 'lo que lo tiene es un montaje de dentro' "${DESMONTAR_LOG}" || true)"
comprobar "  y lo de 'no hay NINGUN montaje dentro' no aparece" \
  "0" "$(grep -c 'no hay NINGUN montaje dentro' "${DESMONTAR_LOG}" || true)"
# Y lo de los montajes de los OTROS procesos, que solo tiene que mirar cuando NO
# hay montajes dentro: si se mirara siempre, el aviso "en ningun otro espacio de
# montajes hay nada" saldria tambien en el caso en el que si hay algo dentro, y el
# log diria dos cosas distintas sobre lo mismo.
comprobar "  y no dice lo de los otros espacios, que aqui no toca" \
  "0" "$(grep -c 'otros espacios de montajes' "${DESMONTAR_LOG}" || true)"

# 7. Y el caso en el que no queda ni el propio destino: 'findmnt' sale con 1 y
#    sin imprimir nada, y el aviso tiene que decir ESO y no otra cosa.
desmontar_caso 9 1 1 "si no queda ningun montaje en el destino" \
  nada "" "${dest_lab}"
comprobar "  lo dice sin inventarse una tabla, en los dos caminos" \
  "2" "$(grep -c "no queda ningun montaje en ${dest_lab} ni debajo" "${DESMONTAR_LOG}" || true)"
comprobar "  y tampoco dice que lo tenga un montaje de dentro" \
  "0" "$(grep -c 'lo que lo tiene es un montaje de dentro' "${DESMONTAR_LOG}" || true)"

# 8. Y el nombre del montaje que se resiste, que es la otra mitad del fallo 38:
#    el aviso decia 'no se ha podido soltar /mnt del todo' sin decir cual. Con un
#    montaje atascado por ruta (y no por contador), solo se puede nombrar si hay
#    una pasada que suelte de uno en uno, porque un 'umount -R' se para en el
#    primero que falla y no dice cual es.
desmontar_caso 9 1 1 "si un montaje de dentro no se deja soltar" \
  dentro "${dest_lab}/proc" "${dest_lab}"
comprobar "  NOMBRA el montaje que se resiste" \
  "1" "$(grep -c 'es el que se resiste: '"${dest_lab}"'/proc' "${DESMONTAR_LOG}" || true)"
# La secuencia ENTERA de lo que se ha intentado, en orden, que es mas de lo que
# hace falta: que se suelte de uno en uno (y no solo con el '-R'), del mas hondo
# al mas alto (un padre no se suelta con un hijo montado), que el '-R' se
# reintente UNA vez y no mas, y que lo que quede sea el '-l' de la fuerza. Tres
# cuentas sueltas (cuantas veces, en que orden) dejan sitio a que la otra parte se
# rompa sin que se note.
comprobar "  y se suelta de uno en uno, del mas hondo al mas alto" \
  "umount -R ${dest_lab}|umount ${dest_lab}/proc|umount ${dest_lab}|umount -R ${dest_lab}|umount -l -R ${dest_lab}" \
  "$(paste -sd'|' <"${DESMONTAR_REGISTRO}")"

# Y 'soltar_uno_a_uno()' por su cuenta. Su codigo de salida no lo mira nadie:
# 'desmontar()' la llama con '|| :' (que si fallara, el guion entero acabaria ahi
# sin avisar de nada), asi que un 'return' invertido --0 cuando hay un montaje que
# se resiste, 1 cuando no hay ninguno-- no lo caza NADA mirando el 'desmontar()'
# entero. Es el fallo que el laboratorio de montajes reales encontro, y aqui se
# prueba con los mismos falsos de antes: es una funcion que solo necesita un
# 'findmnt' y un 'umount' que le digan que hay, y que no se suelte.
prueba_soltar_uno_a_uno() { # FALLOS_QUE_QUEDAN -> imprime su codigo de salida
  local nfallos="$1"
  printf '%s\n' "${nfallos}" >"${lab_dir}/cuenta-soltar"
  : >"${lab_dir}/reg-soltar"
  printf '%s /dev/vda2[/@] btrfs\n%s/proc proc proc\n' \
    "${dest_lab}" "${dest_lab}" >"${lab_dir}/montados-soltar"
  TITAN_UMOUNT_LOG="${lab_dir}/reg-soltar" \
  TITAN_UMOUNT_FALLOS="${lab_dir}/cuenta-soltar" \
  TITAN_UMOUNT_ATASCADO="" \
  TITAN_MONTADOS="${lab_dir}/montados-soltar" \
  PATH="${lab_dir}/bin2:${PATH}" \
    soltar_uno_a_uno "${dest_lab}" >/dev/null 2>&1
  printf 'rc=%s\n' "$?"
}
comprobar "  soltar de uno en uno sale con 1 si hay un montaje que se resiste" \
  "rc=1" "$(prueba_soltar_uno_a_uno 99)"
comprobar "  y sale con 0 si no se resiste ninguno" \
  "rc=0" "$(prueba_soltar_uno_a_uno 0)"

# --- el filtro de las lineas ajenas, con un 'mountinfo' de verdad como DATO ----
#
# 'montajes_de_otros_espacios()' recorre '/proc/[0-9]*/mountinfo' del sistema
# entero, asi que no se puede probar sin montar cosas de verdad y mirarlas desde
# un proceso de otro espacio de montajes. Por eso el filtro esta partido en dos
# funciones: una que RECORRE (la que necesita el sistema vivo) y otra que DECIDE
# que lineas son interesantes (la que se le puede dar un 'mountinfo' de verdad
# como dato). Esto es lo segundo, y es justo lo que evita que un fallo aqui pase
# desapercibido: la funcion que recorre no avisa de nada si el filtro no le
# devuelve nada, y devolver una lista vacia y devolver la linea correcta se
# parecen MUCHISIMO al mirarlo por encima.
#
# El fallo de verdad que se caza: los arrays entran por NOMBRE ('local -n'), y si
# el nombre de dentro coincide con el que le pasa el llamante, bash contesta
# 'circular name reference', deja el array vacio y devuelve una lista vacia sin
# decir nada. No daba error, no decia nada, y el aviso de 'no hay nada en ningun
# otro espacio de montajes' salia siempre. Para eso esta prueba: llama al filtro
# con los MISMOS nombres que usa 'montajes_de_otros_espacios', no con nombres
# inventados aqui.
prueba_filtro_ajeno() { # RUTA -> imprime lo que el filtro deja pasar
  local r="$1"
  local -a ya_vistos=() los_mios=() crudas=() interesantes=()
  los_mios=("${r}" "${r}/var")
  # Lineas con el formato de verdad de 'mountinfo' de este kernel: id, padre,
  # mayor:menor, raiz, punto de montaje, opciones, "-", fuente, superopciones.
  crudas=(
    "670 669 0:77 / / rw,relatime - ext4 /dev/vda1 rw,errors=remount-ro"
    "728 727 0:82 / ${r} rw,relatime - btrfs /dev/loop0[/@] rw,subvol=/@"
    "729 727 0:83 / ${r}/var rw,relatime - btrfs /dev/loop0[/@var] rw,subvol=/@var"
    "730 727 0:84 / ${r}/home rw,relatime - tmpfs tmpfs rw,size=1024k"
    "731 727 0:85 / ${r}2/hermano rw,relatime - tmpfs tmpfs rw,size=1024k"
    '732 700 0:86 / /var/lib/una\040ruta\040con\040espacios rw - tmpfs tmpfs rw'
  )
  mapfile -t interesantes < <(lineas_ajenas_interesantes "${r}" los_mios crudas) \
    || interesantes=()
  printf '%s\n' "${interesantes[@]-}"
  return 0
}
dest_filtro="${lab_dir}/mntdest"
# Lo unico que tiene que salir es la cuarta linea: la primera esta fuera de la
# ruta, la segunda y la tercera ya las tenemos montadas nosotros, la quinta es
# un HERMANO (una ruta que empieza por los mismos caracteres pero es otra, que es
# lo que un 'case' mal escrito con un '*' suelto deja pasar) y la sexta esta
# fuera y ademas lleva espacios escapados.
comprobar "  el filtro deja pasar la linea ajena y SOLO la ajena" \
  "730 727 0:84 / ${dest_filtro}/home rw,relatime - tmpfs tmpfs rw,size=1024k" \
  "$(prueba_filtro_ajeno "${dest_filtro}")"
# Y con el nombre del array de dentro cambiado por el que le pase el llamante: si
# el filtro se declara con 'crudas' y el llamante tambien, la lista sale vacia.
# Esta comprobacion es la que dice si el fallo del 'nameref' puede volver.
comprobar "  y con los nombres que usa el llamante, el filtro tambien funciona" \
  "1" "$(prueba_filtro_ajeno "${dest_filtro}" | grep -c 'mntdest/home')"
# Anclada al principio de la linea para que no cuente el comentario que explica el
# fallo (que lo menciona, y con un 'grep' sin ancla esta comprobacion contaria su
# propia explicacion).
comprobar "  y el codigo no repite ningun nombre de los del llamante" \
  "0" "$(grep -c '^ *local -n \(mios\|crudas\)=' \
      "${RAIZ}/instalador/paso-cerrar.sh" || true)"

# Y el quinto campo: una linea de 'mountinfo' DE VERDAD, del proceso de este
# comprobador, no una inventada. El punto de montaje es el quinto, y en el de la
# raiz tiene que ser '/'; si alguien contara el cuarto (que es la raiz del
# subvolumen, o '/') las dos comprobaciones darian verde con el campo malo.
linea_raiz="$(awk '$5 == "/" { print; exit }' /proc/self/mountinfo)"
if [[ -n "${linea_raiz}" ]]; then
  comprobar "  el punto de montaje de un mountinfo de verdad es el quinto campo" \
    "/" "$(punto_de_montaje "${linea_raiz}")"
else
  nota "  no hay ningun mountinfo con la raiz en el quinto campo: no se comprueba"
fi

rm -rf "${lab_dir}"

# --- 6n. los fallos 31 a 35: lo que el sistema instalado se dejaba -----------
#
# Los cinco salieron de la PRIMERA pasada completa de la instalacion en QEMU (69
# comprobaciones, 8 en rojo) y son del mismo genero: el instalador acababa con
# codigo 0, decia que habia instalado todo, y el sistema instalado no tenia lo
# que se le habia pedido. No hacia falta QEMU para verlos; hacia falta mirar el
# disco CON lo instalado dentro, que es lo que hace la fase 4 del driver.
#
# El 'arch-chroot' de esta seccion es de mentira como el de 6m, pero con la
# regla que hace que se vea el fallo 32: un 'locale-gen' de verdad, que lee el
# /etc/locale.gen que ha escrito el instalador y SOLO genera los idiomas que
# tienen los DOS campos (el idioma y el juego de caracteres), avisando de los
# que tienen uno solo y saliendo con codigo 0 igual. Con un 'exit 0' a todo, el
# aviso de 'el idioma no se ha generado' no apareceria nunca.
echo
echo "== 6n. lo que el sistema instalado se dejaba por el camino =="

lab_n="${TMPDIR:-/tmp}/titan-in-$$"
mkdir -p "${lab_n}/bin" "${lab_n}/raiz/etc/sudoers.d" "${lab_n}/raiz/etc/default" \
         "${lab_n}/raiz/etc/profile.d"
cat >"${lab_n}/bin/arch-chroot" <<'MENTIRA'
#!/bin/sh
# Un 'arch-chroot' de mentira con la regla del fallo 32 dentro.
raiz="$1"; shift
printf '%s\n' "$*" >>"${TITAN_LLAMADAS:-/dev/null}"
case "$1" in
  locale-gen)
    # El 'locale-gen' de verdad, en lo unico que importa aqui: genera los
    # idiomas que tienen los DOS campos y AVISA, sin fallar, de los que tienen
    # uno solo. Y sale con codigo 0 siempre, que es lo que hacia que el fallo 32
    # pasara desapercibido: el paso decia que habia funcionado.
    #
    # Con 'TITAN_IDIOMA_ROTO=1' se hace lo contrario --no genera nada, que es lo
    # que pasa cuando la entrada no vale-- para comprobar que el instalador
    # AVISA en ese caso, y no solo cuando todo va bien.
    if [ -n "${TITAN_IDIOMA_ROTO:-}" ]; then
      echo "locale-gen: error: Bad entry 'x '" >&2
      exit 0
    fi
    : >"${TITAN_IDIOMAS}"
    if [ ! -r "${raiz}/etc/locale.gen" ]; then exit 0; fi
    while IFS= read -r linea; do
      case "$linea" in \#*|"") continue ;; esac
      set -- $linea
      if [ "$#" -ge 2 ]; then
        # glibc normaliza SOLO el juego de caracteres y deja el territorio como
        # estaba: 'es_ES.UTF-8' sale como 'es_ES.utf8', no como 'es_es.utf8'. Es
        # un detalle pequeno, pero si el falso normalizara distinto del real
        # la comprobacion estaria probando otra cosa.
        printf '%s.%s\n' "${1%%.*}" \
          "$(printf '%s' "${1##*.}" | tr 'A-Z' 'a-z' | sed 's/utf-8/utf8/')" \
          >>"${TITAN_IDIOMAS}"
      else
        # El aviso de verdad, con el espacio final que hace que no case:
        #     error: Bad entry 'es_ES.UTF-8 '
        echo "locale-gen: error: Bad entry '$linea '" >&2
      fi
    done <"${raiz}/etc/locale.gen"
    exit 0
    ;;
  locale)
    [ "$2" = "-a" ] || exit 0
    printf 'C\nC.utf8\nPOSIX\n'
    [ -r "${TITAN_IDIOMAS:-/dev/null}" ] && cat "${TITAN_IDIOMAS:-/dev/null}"
    exit 0
    ;;
  getent) exit 0 ;;
  pacman) exit 0 ;;
  visudo) exit 0 ;;
  systemctl) exit 0 ;;
  ufw) exit 0 ;;
esac
exit 0
MENTIRA
chmod 755 "${lab_n}/bin/arch-chroot"

# Las mismas respuestas que dejaria un autopilot, y el '/mnt' de mentira.
E=([usuario]=isai [clave]="clave-de-prueba" [clave_root]="clave-root"
   [hostname]=titan [zona]=Europe/Madrid [locale]=es_ES.UTF-8
   [keymap]=es [teclado_grafico]=es [kernel]=linux-titanlinux
   [disco]=/dev/vda [modo_arranque]=1 [fs]=btrfs [cifrado]=no
   [escritorio]=gnome [swap]=zram [bluetooth]=no [apps]=" ufw "
   [flatpaks]="org.mozilla.firefox")
DESTINO="${lab_n}/raiz"
log_n="${lab_n}/instalador.log"
: >"${lab_n}/llamadas"

# --- el fallo 31: dos kernels en el sistema instalado -------------------------
#
# 'paquetes_base' metia 'linux' (el de Arch) y luego 'paso_kernel' instalaba
# 'linux-titanlinux'. Los dos se quedan en /usr/lib/modules, el equipo llevaba
# DOS kernels ('6.18.54-1-titanlinux' y '7.2.7-arch1-1', leido del disco
# instalado), y la comprobacion "no hay mas de un kernel" salia en rojo con dos.
comprobar "la lista base NO lleva el kernel de Arch (fallo 31)" \
  "0" "$(for p in $(paquetes_base); do [[ "$p" == "linux" ]] && echo 1; done | wc -l)"
# Y que la reserva siga ahi: si la ISO no trae el paquete del proyecto, el
# instalador instala el kernel de Arch antes que dejar el sistema sin kernel.
# Se ejecuta 'paso_kernel' de verdad, y 'paquete_kernel_propio' mirando en el
# '/titan-repo' del live, que aqui no existe: o sea, el caso de la reserva.
# En un directorio vacio, y no solo en /titan-repo: en la maquina donde se
# desarrolla el paquete del kernel SI esta en la cache de pacman, y con los
# caminos escritos a pelo la comprobacion no llegaria nunca a la reserva.
mkdir -p "${lab_n}/repo-vacio"
: >"${lab_n}/llamadas"
E[kernel]=""
TITAN_REPO_KERNEL="${lab_n}/repo-vacio" \
  TITAN_LLAMADAS="${lab_n}/llamadas" PATH="${lab_n}/bin:${PATH}" \
  paso_kernel >/dev/null 2>&1
comprobar "y sin el paquete propio, cae el kernel de Arch (la reserva)" \
  "1" "$(grep -c 'pacman -S --noconfirm --needed linux$' "${lab_n}/llamadas" || true)"

# Y el caso bueno, que es el que de verdad importa y que NO estaba probado. Con
# solo el caso de la reserva, 'paquete_kernel_propio' podia no encontrar NUNCA un
# paquete y todas las comprobaciones seguian en verde: asi estuvo hasta la pasada
# del 28 de septiembre, en la que el '/titan-repo' del live tenia el paquete
# delante y la funcion decia que no lo encontraba (por el detalle de las comillas
# de la funcion), el instalador caia a la reserva y el sistema instalado arranco
# con el kernel de Arch (4 FALLO en el informe).
mkdir -p "${lab_n}/repo-vacio" "${lab_n}/repo1" "${lab_n}/repo2"
: >"${lab_n}/repo1/linux-titanlinux-6.18.54-1-x86_64.pkg.tar.zst"
: >"${lab_n}/repo2/linux-titanlinux-6.18.54-1-x86_64.pkg.tar.zst"
# Una sola ruta: el caso simple.
comprobar "con el paquete propio delante, lo encuentra" \
  "${lab_n}/repo1/linux-titanlinux-6.18.54-1-x86_64.pkg.tar.zst" \
  "$(TITAN_REPO_KERNEL="${lab_n}/repo1" paquete_kernel_propio || true)"
# Y con la lista de DOS rutas, que es la forma de verdad ('/titan-repo' y la cache
# de pacman). Con el paquete en la primera, y con el paquete en la segunda: este
# segundo caso es el que cazaba el fallo de las comillas, porque un espacio sin
# partir convierte la lista en un solo camino que no existe.
comprobar "con dos rutas y el paquete en la primera, la lista se parte bien" \
  "${lab_n}/repo1/linux-titanlinux-6.18.54-1-x86_64.pkg.tar.zst" \
  "$(TITAN_REPO_KERNEL="${lab_n}/repo1 ${lab_n}/repo2" \
     paquete_kernel_propio || true)"
comprobar "con dos rutas y el paquete en la segunda, tambien (fallo de las comillas)" \
  "${lab_n}/repo2/linux-titanlinux-6.18.54-1-x86_64.pkg.tar.zst" \
  "$(TITAN_REPO_KERNEL="${lab_n}/repo-vacio ${lab_n}/repo2" \
     paquete_kernel_propio || true)"
comprobar "con dos rutas y las dos vacias, no encuentra nada (a la reserva)" \
  "" "$(TITAN_REPO_KERNEL="${lab_n}/repo-vacio ${lab_n}/repo-vacio" \
        paquete_kernel_propio || true)"
# Y que la lista por defecto siga siendo la de verdad: el '/titan-repo' que monta
# la ISO y la cache de pacman. Sin esta comprobacion, alguien podria dejar la
# variable con un solo camino de pruebas y el instalador dejaria de encontrar el
# paquete en el live sin que ninguna otra comprobacion se enterase.
cuerpo_paquete_kernel="$(awk '/^paquete_kernel_propio\(\) \{/{d=1} d{print} d&&/^\}$/{exit}' \
  "${RAIZ}/instalador/paso-base.sh")"
# OJO con la forma otra vez, y por lo mismo de antes pero al reves: un
# 'grep -c' sobre el CUERPO contaria tambien los COMENTARIOS, y el comentario que
# explica el fallo de las comillas menciona los dos caminos (salio 5 en vez de 2).
# Lo que se mira es el VALOR por defecto de la linea que hace el trabajo, con lo
# que hay entre ':-' y '}', y se compara ENTERO con la lista de verdad: asi el
# comentario puede hablar de lo que quiera sin mover el resultado, y el orden
# tambien se comprueba (el '/titan-repo' de la ISO va primero, y por eso se mira
# el del proyecto antes que el de la cache).
linea_lista="$(grep -m1 'read -r -a dirs' <<<"${cuerpo_paquete_kernel}")"
comprobar "la lista por defecto sigue siendo /titan-repo y luego la cache de pacman" \
  "/titan-repo /var/cache/pacman/pkg" \
  "$(sed -n 's/.*TITAN_REPO_KERNEL:-\([^}]*\)}.*/\1/p' <<<"${linea_lista}")"
# Y que la lista se parta de verdad (que no se convierta en un solo camino), que es la
# comprobacion que de verdad importa y la que esta mas abajo con dos rutas.
comprobar "y se parte en una lista de caminos, no en un camino con espacios" \
  "1" "$(grep -c 'read -r -a dirs <<<' <<<"${cuerpo_paquete_kernel}" || true)"
# Y el camino bueno entero, con 'paso_kernel' de verdad: instala el paquete del
# proyecto y NO cae a la reserva.
: >"${lab_n}/llamadas"
E[kernel]=""
TITAN_REPO_KERNEL="${lab_n}/repo-vacio ${lab_n}/repo1" \
  TITAN_LLAMADAS="${lab_n}/llamadas" PATH="${lab_n}/bin:${PATH}" \
  paso_kernel >/dev/null 2>&1
comprobar "con el paquete propio, paso_kernel lo instala y no cae a la reserva" \
  "1 0" "$(grep -c 'linux-titanlinux-6.18.54-1-x86_64.pkg.tar.zst' "${lab_n}/llamadas" \
           || true) $(grep -c 'pacman -S --noconfirm --needed linux$' \
           "${lab_n}/llamadas" || true)"

# --- el fallo 32: el idioma, que se pedia y no se generaba ---------------------
#
# El instalador escribia en /etc/locale.gen la linea 'es_ES.UTF-8' y ya, sin el
# juego de caracteres. El 'locale-gen' de glibc 2.41 la rechaza con 'error: Bad
# entry' y sale con codigo 0, de modo que el paso daba por bueno un idioma
# entero sin generar. En el disco instalado solo estaba 'C.utf8' (comprobado en
# un arranque de verdad: 'ls /usr/lib/locale' -> 'C.utf8').
TITAN_LLAMADAS="${lab_n}/llamadas" TITAN_IDIOMAS="${lab_n}/idiomas" LOG="${log_n}" \
  PATH="${lab_n}/bin:${PATH}" paso_sistema >/dev/null 2>&1
comprobar "el idioma se escribe en locale.gen con su juego de caracteres" \
  "1" "$(grep -c '^es_ES\.UTF-8 UTF-8' "${DESTINO}/etc/locale.gen" 2>/dev/null || true)"
# Y que el idioma se GENERA de verdad, que es lo que no pasaba: con la entrada de
# dos campos, el 'locale-gen' de verdad genera 'es_ES.utf8'.
comprobar "y el locale-gen de verdad genera el idioma" \
  "1" "$(grep -c '^es_ES\.utf8$' "${lab_n}/idiomas" 2>/dev/null || true)"
# Y el fallo 37, que es el hermano tonto del 32 y salio de la pasada de UEFI del
# 28 de septiembre: con el idioma GENERADO de verdad, el instalador avisaba igual.
# La comparacion era 'locale -a' contra 'es_ES.UTF-8' y eso no casa nunca, porque
# al generar, glibc normaliza el juego de caracteres y escribe 'es_ES.utf8' (sin
# guion y en minusculas). O sea, el aviso era un embuste, y ademas uno que nunca
# se callaba, con lo que el aviso de verdad (el del 'locale-gen' que no genera
# nada) se escondia debajo.
#
# Esto es otra vez la letra S: hasta ahora lo que se probaba era el caso MALO (el
# idioma que no se genera, con su aviso). Del caso BUENO no habia ni una
# comprobacion, y con el aviso puesto las dos comprobaciones dabian bien igual.
# OJO con partir esto en dos lineas: lo que va dentro de las comillas dobles es
# UNA cadena, y un '\\' followed de un salto de linea mete ese salto dentro. Lo
# que se compara es '1\n           0' contra '1 0', y siempre da MAL. Se
# comprueba contando las dos cosas con 'grep -c' y juntandolas con 'tr', para que
# el valor que se compara no dependa de como se ha escrito la linea. Y el
# 'sed' del final se come el espacio que deja el ultimo 'tr', que tambien hacia
# que la comparacion no saliera nunca.
comprobar "con el idioma bien, el instalador lo da por generado" \
  "1 0" "$({ grep -c 'idioma generado: es_ES.utf8' "${log_n}" || true; grep -c 'NO se ha generado' "${log_n}" || true; } | tr '\n' ' ' | sed 's/  *$//')"
# Y que el nombre con el que se da por bueno es el NORMALIZADO, no el que pidio
# el usuario: si el mensaje dijera 'es_ES.UTF-8' seria el codigo viejo, que es el
# que no casa con nada.
comprobar "y el nombre que se dice es el normalizado por glibc" \
  "1 0" "$({ grep -c 'idioma generado: es_ES\.utf8$' "${log_n}" || true; grep -c 'idioma generado: es_ES\.UTF-8' "${log_n}" || true; } | tr '\n' ' ' | sed 's/  *$//')"
# Y que el instalador lo COMPRUEBA en vez de darlo por hecho: aqui el idioma no
# se genera, que es lo que contestaba el sistema instalado, y el paso tiene que
# seguir y avisar. (Con glibc 2.41 el idioma generado se guarda en el archivo
# '/usr/lib/locale/locale-archive' y no en un directorio, que es por lo que la
# comprobacion que lo buscaba no podia dar bien nunca.)
: >"${lab_n}/idiomas"; : >"${log_n}"
if TITAN_LLAMADAS="${lab_n}/llamadas" TITAN_IDIOMAS="${lab_n}/idiomas" \
     TITAN_IDIOMA_ROTO=1 LOG="${log_n}" PATH="${lab_n}/bin:${PATH}" \
     paso_sistema >/dev/null 2>&1; then
  ok "el paso de cuentas no se para porque el idioma no se haya generado"
else
  falla "el paso de cuentas se para si el idioma no se genera: eso es un aviso,
  no un sistema que no se instala"
fi
comprobar "y avisa de que el idioma no se ha generado" \
  "1" "$(grep -c 'NO se ha generado' "${log_n}" || true)"

# --- el fallo 33: el swap en memoria, que se instalaba y no existia -----------
#
# 'zram-generator' instalado no es swap: sin configuracion no crea ningun
# dispositivo y sale sin quejarse. En el registro del sistema instalado solo
# decia 'zram_generator::config[196]: No configuration found.' y 'swapon
# --show' no tenia nada. Con el fichero escrito, el mismo arranque da
# '/dev/zram0 partition 1.9G 0B 100'.
TITAN_LLAMADAS="${lab_n}/llamadas" LOG="${log_n}" PATH="${lab_n}/bin:${PATH}" \
  paso_servicios >/dev/null 2>&1
comprobar "se escribe el fichero de configuracion de zram (fallo 33)" \
  "1" "$([[ -s "${DESTINO}/etc/systemd/zram-generator.conf" ]] && echo 1 || echo 0)"
comprobar "y pide la mitad de la memoria, con tope" \
  "1" "$(grep -c '^zram-size = min(ram / 2, 4096)$' "${DESTINO}/etc/systemd/zram-generator.conf" 2>/dev/null || true)"
comprobar "y comprime con zstd, que es lo que aguanta la memoria" \
  "1" "$(grep -c '^compression-algorithm = zstd$' "${DESTINO}/etc/systemd/zram-generator.conf" 2>/dev/null || true)"
comprobar "y con la seccion [zram0], que es donde la lee el generador" \
  "1" "$(grep -c '^\[zram0\]$' "${DESTINO}/etc/systemd/zram-generator.conf" 2>/dev/null || true)"
# Y que el fichero NO se escriba si el usuario no ha pedido swap en memoria: el
# 'zram-size = 0' de zram-generator dejaria el paso escribiendo configuracion
# para un dispositivo que el usuario no quiere.
rm -f "${DESTINO}/etc/systemd/zram-generator.conf"
E[swap]="no"
TITAN_LLAMADAS="${lab_n}/llamadas" LOG="${log_n}" PATH="${lab_n}/bin:${PATH}" \
  paso_servicios >/dev/null 2>&1
comprobar "y sin swap en memoria no se escribe nada" \
  "0" "$([[ -e "${DESTINO}/etc/systemd/zram-generator.conf" ]] && echo 1 || echo 0)"
E[swap]="zram"

# --- el fallo 34: fastfetch, que se quedaba en el live ------------------------
#
# El live lo trae de serie y el instalado no: el driver lo compro y salio en
# rojo, y el equipo recien instalado se quedaba sin la herramienta con la que
# se ve. Se pide con pacman (que es un paquete de los repos), no se copia.
TITAN_LLAMADAS="${lab_n}/llamadas" LOG="${log_n}" PATH="${lab_n}/bin:${PATH}" \
  paso_titan >/dev/null 2>&1
comprobar "fastfetch se instala en el sistema instalado (fallo 34)" \
  "1" "$(grep -c 'pacman -S --noconfirm --needed fastfetch' "${lab_n}/llamadas" || true)"

# --- el fallo 35: el sistema instalado decia ser Arch Linux --------------------
#
# 'pacstrap' deja el /usr/lib/os-release del paquete 'pacman', que dice
# NAME="Arch Linux" (leido del disco instalado). Con eso, todo lo que pregunta
# al sistema recien instalado recibe 'Arch Linux': el fastfetch de la primera
# consola, 'lsb_release', 'uname -o', el menu de GRUB.
#
# 'escribir_identidad' copia el os-release del LIVE (que es donde el build pone
# la version) al destino. Se le pasa el origen como parametro para poder
# comprobarlo con el os-release de verdad del live delante y no con el de este
# host, que es el de Arch.
# El os-release REAL del live, que es el que escribe el build
# (root/customize_airootfs.sh). Copiado aqui casi entero, con la tilde del
# codename composingla con 'printf' porque este fichero va TODO en ASCII: la
# lleva, pero en el os-release, que es donde se ha mirado.
tildes="$(printf '\303\241')"   # 'a' con tilde, en UTF-8
os_release_live="${lab_n}/os-release-del-live"
{
  printf 'NAME="Titan Linux"\n'
  printf 'PRETTY_NAME="Titan Linux 0.1.0 (TIT%sN)"\n' "${tildes}"
  printf 'VERSION_ID="0.1.0"\n'
  printf 'VERSION="0.1.0 (TIT%sN)"\n' "${tildes}"
  # ID=arch es deliberado: Titan Linux es una derivada de Arch y pacman, los
  # hooks y las herramientas de /etc dependen de ese identificador.
  printf 'ID=arch\n'
  printf 'ID_LIKE=arch\n'
  printf 'ANSI_COLOR="38;2;56;214;255"\n'
  printf 'HOME_URL="https://github.com/titan-linux"\n'
  printf 'SUPPORT_URL="https://github.com/titan-linux/issues"\n'
  printf 'BUG_REPORT_URL="https://github.com/titan-linux/issues"\n'
  printf 'LOGO=titanlinux-logo\n'
} >"${os_release_live}"
mkdir -p "${lab_n}/identidad"
TITAN_LLAMADAS="${lab_n}/llamadas" LOG="${log_n}" \
  escribir_identidad "${lab_n}/identidad" "${os_release_live}" >/dev/null 2>&1
comprobar "el sistema instalado se identifica como Titan Linux (fallo 35)" \
  "1" "$(grep -c '^NAME="Titan Linux"$' "${lab_n}/identidad/usr/lib/os-release" 2>/dev/null || true)"
comprobar "y se queda con ID=arch, que es de donde dependen pacman y systemd" \
  "1" "$(grep -c '^ID=arch$' "${lab_n}/identidad/usr/lib/os-release" 2>/dev/null || true)"
comprobar "y /etc/os-release es el enlace al que todo el mundo mira" \
  "1" "$([[ "$(readlink "${lab_n}/identidad/etc/os-release" 2>/dev/null)" == "../usr/lib/os-release" ]] && echo 1 || echo 0)"
comprobar "y deja su propio fichero de version, con la variante instalada" \
  "1" "$(grep -c '^VARIANT=installed$' "${lab_n}/identidad/etc/titan-release" 2>/dev/null || true)"
# Y que sin un os-release de origen Util no se deje el destino sin identidad,
# que seria peor: un /etc/os-release vacio rompe mas cosas que un nombre
# equivocado (de ID= e ID_LIKE= leen sudo, pacman y systemd).
mkdir -p "${lab_n}/identidad-vacia"
printf 'ID=arch\nID_LIKE=arch\n' >"${lab_n}/os-release-sin-nombre"
: >"${log_n}"
TITAN_LLAMADAS="${lab_n}/llamadas" LOG="${log_n}" \
  escribir_identidad "${lab_n}/identidad-vacia" "${lab_n}/os-release-sin-nombre" \
  >/dev/null 2>&1
comprobar "y si el origen no trae nombre, no se pisa lo que habia" \
  "0" "$([[ -e "${lab_n}/identidad-vacia/usr/lib/os-release" ]] && echo 1 || echo 0)"
comprobar "y avisa de por que" \
  "1" "$(grep -c 'no trae NAME o VERSION_ID' "${log_n}" || true)"
# Y que el paso de cuentas la llame de verdad. Se mira el CUERPO de la funcion,
# no el fichero entero: en el fichero esta escrito, en mayusculas, el
# comentario que explica que hay que llamarla, y un comprobador que se puede
# satisfacer con un comentario no comprueba nada.
cuerpo_paso_sistema="$(awk '/^paso_sistema\(\) \{/{d=1} d{print} d&&/^\}$/{exit}' \
  "${RAIZ}/instalador/paso-chroot.sh")"
comprobar "y el paso de cuentas la llama, no solo esta escrita en el fichero" \
  "1" "$(grep -c 'escribir_identidad' <<<"${cuerpo_paso_sistema}" || true)"

rm -rf "${lab_n}"

# --- 7. el boton de cancelar, de verdad ---------------------------------------
#
# Esta se ejecuta con los MISMOS flags que install.sh ('set -euo pipefail') y
# con un dialog de mentira que devuelve 1, que es lo que hace dialog cuando
# el usuario pulsa el boton de cancelar. Lo que se comprueba es lo unico que
# importa: que el instalador NO se muere y que el resumen devuelve 3, que es el
# codigo con el que install.sh distingue 'cancelado' de 'ha fallado'.
#
# Antes de que existiera 'ventana', dialog se llamaba a pelo: devolvia 1, el
# 'set -e' mataba el script entero, install.sh leia un codigo 1, y en vez de
# 'se ha cancelado, el disco esta intacto' se enseaba 'la instalacion se ha
# parado'. O sea: el usuario cancelaba y le decian que habia fallado.
echo
echo "== 7. cancelar no es fallar =="
falso_dialog="${TMPDIR:-/tmp}/titan-dialog-falso-$$"
mkdir -p "${falso_dialog}"
cat >"${falso_dialog}/dialog" <<'FALSO'
#!/bin/sh
# Como dialog cuando el usuario contesta que no: codigo 1.
exit 1
FALSO
chmod 755 "${falso_dialog}/dialog"

probar_cancelacion() { # probar_cancelacion CODIGO_QUE_SI_ESPERABA
  local esperado="$1" salida
  salida="$(PATH="${falso_dialog}:${PATH}" AUTO=0 TITAN_SILENCIO=1 \
    LOG="${TMPDIR:-/tmp}/titan-cancel-$$.log" \
    bash -c '
      set -euo pipefail
      RAIZ="$1"
      source "${RAIZ}/instalador/lib-comun.sh"
      source "${RAIZ}/instalador/lib-escritorios.sh"
      source "${RAIZ}/instalador/lib-apps.sh"
      source "${RAIZ}/instalador/paso-base.sh"
      source "${RAIZ}/instalador/menus.sh"
      # Las mismas respuestas que dejaria un autopilot con todo por defecto.
      E=()
      E[disco]="/dev/sda";      E[escritorio]="gnome";  E[hostname]="titanpc"
      E[usuario]="titan";       E[arranque]="grub";     E[fs]="btrfs"
      E[zona]="Europe/Madrid";  E[locale]="es_ES.UTF-8"; E[teclado]="es"
      E[zona_horaria]="Europe/Madrid"; E[cifrado]="no"; E[swap]="zram"
      E[usos]="oficina";        E[clave]="titan";       E[clave_root]="titan"
      E[apps]="navegador:flatpak:navegador"; E[flatpaks]="org.gnome.Calculator"
      E[total_paquetes]=""
      # Como lo llama install.sh: guardado con || para que el set -e no se
      # dispare por un 3 que aqui es una respuesta correcta, no un fallo.
      codigo_menu=0
      menu_resumen || codigo_menu=$?
      echo "codigo=${codigo_menu}"
      # Y la pantalla final, que tambien es una ventana (y con Esc devuelve 255)
      source "${RAIZ}/instalador/paso-cerrar.sh"
      pantalla_final
      echo "final=$?"
    ' _ "${RAIZ}" 2>&1)"
  if grep -qx "codigo=${esperado}" <<<"${salida}"; then
    ok "el resumen devuelve ${esperado} al pulsar cancelar (no 1, que es 'fallo')"
  else
    falla "el resumen deberia devolver ${esperado} al cancelar; devolvio: $(grep -o 'codigo=[0-9]*' <<<"${salida}" | paste -sd' ' -)"
  fi
  if grep -qx "final=0" <<<"${salida}"; then
    ok "la pantalla final aguanta que la ventana devuelva 1"
  else
    falla "la pantalla final no aguanta el codigo de la ventana: $(grep -o 'final=[0-9]*' <<<"${salida}" | paste -sd' ' -)"
  fi
  if grep -qE '^(bash: line|: command not found|.*unbound variable)' <<<"${salida}"; then
    falla "el instalador se ha muerto con los flags de install.sh: $(head -3 <<<"${salida}" | paste -sd' ' -)"
  else
    ok "el instalador sigue vivo con 'set -euo pipefail' y el usuario cancelando"
  fi
}
probar_cancelacion 3
rm -rf "${falso_dialog}"

# --- 6p. la pantalla grafica del instalador -----------------------------------
#
# El instalador tiene DOS pantallas y UN motor: la de texto (dialog) y la
# grafica (GTK4 con libadwaita, en instalador/ventana-gui.py). Se reparten en
# 'ventana()', que es lo unico que llama a una o a otra. Lo que se comprueba
# aqui son las TRES cosas que pueden salir mal, que son las tres que importan:
#
#   1. Que el motor y la pantalla grafica hablen EL MISMO idioma. Se mide con
#      los vectores de argumentos de verdad: se espia una ventana del motor con
#      un dialog falso y ese vector, tal cual, se le pasa al frontal grafico,
#      que tiene que entenderlo. Si el motor empieza a usar una caja o una
#      opcion que el grafico no sabe, aqui sale; y al reves, se exige que
#      entre lo que usa el motor esten las SEIS cajas, que es lo que hace falta
#      para que la pantalla grafica sea el instalador entero y no un recorte.
#   2. Que la respuesta vaya por la salida de error, que es donde el motor la
#      lee, y que un fallo al abrir la ventana sea un FALLO (codigo 2) y no un
#      'el usuario ha cancelado' (codigo 1). Con la pantalla rota, el grafico
#      tiene que devolver 2 y no escribir NADA en la salida de error. Ese 2 es
#      lo unico que 'ventana()' traduce en una caida al texto; si devolviera
#      1, el motor leeria "el usuario ha pulsado Esc" e instalaria entero con
#      los valores por defecto, en silencio y con codigo de exito. Y si
#      escribiera su diagnostico por la salida de error, al caer al texto el
#      motor leeria ese texto como si fuera la eleccion del usuario.
#   3. Que la ventana de verdad funcione: las seis cajas pintadas con GTK
#      dentro de cage, contestando solas. Esto solo se puede hacer donde haya
#      'cage' y 'gtk4'; si no hay, se dice que se omite, en voz alta, porque
#      un silencio aqui seria indistinguishable de 'todo bien'.
echo
echo "== 6p. la pantalla grafica del instalador =="
gui_py="${RAIZ}/instalador/ventana-gui.py"
lab_gui="${TMPDIR:-/tmp}/titan-gui-$$"
mkdir -p "${lab_gui}"
espia_gui="${lab_gui}/espia"
mkdir -p "${espia_gui}"

# --- 6p.1. el fichero, el permiso y los paquetes ------------------------------
#
# El permiso de ejecucion va en su propia comprobacion y no de paso, porque se
# roto de verdad: 'ventana()' abre la pantalla grafica solo si el fichero tiene
# '-x', asi que un 0644 (que es lo que deja archiso si el perfil no declara el
# permiso) no da error: el instalador cae al texto sin decir nada, y en una
# maquina con tarjeta el usuario ve como el instalador grafico no existe.
if [[ -f "${gui_py}" ]]; then
  ok "el frontal grafico esta en el arbol del instalador"
else
  falla "no esta instalador/ventana-gui.py (${gui_py})"
fi
if [[ -x "${gui_py}" ]]; then
  ok "el frontal grafico se puede ejecutar en el arbol"
else
  falla "ventana-gui.py no tiene permiso de ejecucion en el arbol"
fi
comprobar "el perfil declara el permiso de ventana-gui.py" "1" \
  "$(grep -c '^\s*\["/root/instalador/ventana-gui.py"\]="0:0:755"' \
      "${DISTRO}/iso/titan/profiledef.sh")"
comprobar "el perfil declara el permiso de ventana-gui.py (una sola vez)" "1" \
  "$(grep -c '\["/root/instalador/ventana-gui.py"\]' \
      "${DISTRO}/iso/titan/profiledef.sh")"
faltan=""
for paquete in gtk4 libadwaita adwaita-icon-theme python-gobject cage; do
  grep -qx "${paquete}" "${DISTRO}/iso/titan/packages.x86_64" \
    || faltan="${faltan} ${paquete}"
done
comprobar "los cinco paquetes de la pantalla grafica estan en la ISO" "" \
  "${faltan}"
comprobar "la ayuda de install.sh ofrece el modo grafico" "1" \
  "$(bash "${RAIZ}/install.sh" --help 2>/dev/null | grep -c -- '--grafico')"
# Que install.sh ACEPTE --grafico se mira con una opcion detras que si que
# es inventada: si --grafico no estuviera en el 'case', el
# error seria sobre --grafico y no sobre la de despues. Y que una opcion que
# no existe se rechace con codigo 2, que es como el motor sabe que no es
# suya.
comprobar "install.sh acepta --grafico (el error es de la otra)" "1" \
  "$(bash "${RAIZ}/install.sh" --grafico --inventada 2>&1 \
      | grep -c '^Opcion desconocida: --inventada$')"
comprobar "una opcion que no existe se rechaza con codigo 2" "2" \
  "$(bash "${RAIZ}/install.sh" --grafico-inventada >/dev/null 2>&1; echo $?)"

# --- 6p.2. el motor y el grafico hablan el mismo idioma -----------------------
#
# El espia es el mismo de la seccion 6c (un dialog que solo escribe el vector
# que recibe) y la pregunta es la misma, pero cambiada de pregunta: en vez de
# mirar si las opciones van antes del tipo de ventana, se le pasa el vector
# ENTERO al frontal grafico, que es el que tiene que saber entenderlo.
cat >"${lab_gui}/dialog" <<'ESPIA'
#!/bin/bash
# El espia apunta CADA ventana que se abre, en un fichero por llamada. Con un
# solo fichero se perdian todas menos la ultima, y esa es justo la que de mas
# ve: 'menu_cuentas' abre un '--inputbox', un '--passwordbox' y un '--msgbox'
# uno detras de otro, y solo se veia el ultimo.
n=$(cat "${TITAN_ESPIA}/cuenta" 2>/dev/null || echo 0)
n=$((n + 1))
printf '%s' "${n}" >"${TITAN_ESPIA}/cuenta"
printf '%s\0' "$@" >"${TITAN_ESPIA}/v-${n}"
# Lo unico que se contesta de verdad es la contrasena. Sin esto el motor
# la vuelve a pedir sin fin: dos contrasenas vacias SI coinciden, pero no
# llegan a los seis caracteres, y el bucle solo se para cuando se acaba el
# 'timeout'. O sea, que la comprobacion acabaria midiendo el 'timeout' en
# vez de las ventanas, y con 7870 de ellas. Con ocho caracteres, el motor
# sale por su cuenta y la cuenta de ventanas es la de verdad.
for argumento in "$@"; do
  if [[ "${argumento}" == "--passwordbox" ]]; then
    echo 'titan123' >&2
    exit 0
  fi
done
exit 1
ESPIA
chmod 755 "${lab_gui}/dialog"
cat >"${lab_gui}/entiende.py" <<'ENTIENDE'
# Carga el frontal grafico SIN Pantalla (no importa 'gi', que entra mas abajo,
# dentro de 'mostrar()') y le pasa el vector de argumentos de verdad de una
# ventana del motor. Imprime 'ok tipo=<caja> items=<n>' o 'ERROR: <motivo>'.
import importlib.util
import sys

# Python deja el '.pyc' del modulo importado AL LADO del fichero, en un
# '__pycache__'. Ese guion importa el frontal del ARBOL DE LA ISO
# (iso/titan/airootfs/root/instalador/ventana-gui.py), asi que lo que dejaba
# aqui no se quedaba en el laboratorio de pruebas: se quedaba en el arbol que
# se esta midiendo, y de ahi lo copia archiso dentro de la ISO. Se vio en la
# primera pasada con la ISO nueva: 'ls /root/instalador' contaba 11 en vez de 9
# porque uno era un '__pycache__' con un '.pyc' de root dentro de la imagen.
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("vg", sys.argv[1])
modulo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(modulo)
with open(sys.argv[2], "rb") as fichero:
    bruto = fichero.read()
vector = [p.decode("utf-8", "replace") for p in bruto.split(b"\0")][:-1]
if not vector:
    print("ERROR: vector vacio")
    raise SystemExit(0)
try:
    desc = modulo.parse_argsv(vector)
except ValueError as error:
    print("ERROR: %s" % error)
    raise SystemExit(0)
print("ok tipo=%s items=%d" % (desc["tipo"], len(desc["items"])))
ENTIENDE

# Una linea por FUNCION y no una por ventana. 'menu_cuentas' abre mas de
# treinta ventanas seguidas (pregunta la contrasena hasta que cuadre, y con
# el espia, que contesta 'cancelado', no cuadra nunca), y treinta lineas de
# 'OK' no dicen mas que una. Lo que si se ve uno a uno son los fallos: cada
# ventana que el grafico NO entiende sale con su motivo.
cajas_vistas=""
espiar_y_preguntar() { # espiar_y_preguntar NOMBRE_DE_LA_FUNCION DEL_MOTOR
  local fn="$1" respuesta ventana caja vistas=0 entendidas=0 tipos=""
  rm -f "${espia_gui}/cuenta" "${espia_gui}"/v-* 2>/dev/null || true
  env PATH="${lab_gui}:${PATH}" AUTO=0 TITAN_SILENCIO=1 LOG="${lab_gui}/log" \
    TITAN_ESPIA="${espia_gui}" \
    timeout 20 bash "${dibuja_ventana_gui}" "${RAIZ}" "${fn}" \
    >/dev/null 2>&1 || true
  for ventana in "${espia_gui}"/v-*; do
    [[ -f "${ventana}" ]] || continue
    vistas=$((vistas + 1))
    respuesta="$(python3 "${lab_gui}/entiende.py" "${gui_py}" "${ventana}")"
    if [[ "${respuesta}" != ok\ tipo=* ]]; then
      falla "${fn}: el grafico NO entiende una ventana del motor"
      printf '        motivo: %s\n' "${respuesta}"
      continue
    fi
    entendidas=$((entendidas + 1))
    caja="${respuesta#*tipo=}"
    caja="${caja%% *}"
    case " ${tipos} " in *" ${caja} "*) ;; *) tipos="${tipos} ${caja}" ;; esac
    cajas_vistas="${cajas_vistas} ${caja}"
  done
  if (( vistas == 0 )); then
    falla "${fn}: no se ha espiado ninguna ventana del motor"
  elif (( entendidas == vistas )); then
    ok "${fn}: el grafico entiende las ${vistas} ventanas (${tipos# })"
  else
    nota "  ${fn}: ${entendidas} de ${vistas} ventanas entendidas"
  fi
}

# El mismo 'dibuja' de la seccion 6, con una diferencia: el '--grafico' NO se
# pone aqui a proposito. Se espia el motor, no la pantalla.
dibuja_ventana_gui="${lab_gui}/dibuja.sh"
cat >"${dibuja_ventana_gui}" <<DIBUJA
#!/bin/bash
export AUTO=0 TITAN_SILENCIO=1 LOG=/tmp/titan-dibujar-gui.log
export TERM=xterm LANG=es_ES.UTF-8
RAIZ="\${1:?}"
source "\${RAIZ}/instalador/lib-comun.sh"
source "\${RAIZ}/instalador/lib-escritorios.sh"
source "\${RAIZ}/instalador/lib-apps.sh"
source "\${RAIZ}/instalador/menus.sh"
source "\${RAIZ}/instalador/paso-base.sh"
E=()
E[usos]="ordinario oficina"
E[escritorio]="gnome"
E[apps]="\$(app_recomendadas "\${E[usos]}")"
E[disco]="/dev/vda"; E[fs]="btrfs"; E[swap]="zram"
E[locale]="es_ES.UTF-8"; E[teclado]="es"; E[zona]="Europe/Madrid"
E[hostname]="titan"; E[usuario]="isai"
E[arranque]="UEFI"; E[modo_arranque]="efi"
E[luks]="no"; E[cifrado]="no"; E[bluetooth]="si"; E[confirmar_borrado]="si"
E[total_paquetes]="125"
"\$2"
DIBUJA
chmod 755 "${dibuja_ventana_gui}"

# Sin sustitucion de comandos: dentro de una, lo que deja
# 'espiar_y_preguntar' en 'cajas_vistas' se pierde con la subshell, y tambien
# sus lineas de OK y de FALLO.
for fn in menu_tipo_uso menu_escritorio menu_apps menu_cuentas menu_arranque \
          menu_resumen; do
  espiar_y_preguntar "${fn}"
done
for caja in menu checklist yesno msgbox inputbox passwordbox; do
  if [[ " ${cajas_vistas} " == *" ${caja} "* ]]; then
    ok "el motor usa la caja '${caja}', que el grafico tambien sabe abrir"
  else
    falla "ninguna ventana del motor usa la caja '${caja}': la pantalla"
    falla "  grafica no seria el instalador entero (vistas: ${cajas_vistas})"
  fi
done

# --- 6p.3. las funciones puras del frontal, con datos ------------------------
#
# Arriba del todo en ventana-gui.py no hay 'import gi': las funciones puras
# (que leen la lista de argumentos y devuelven un diccionario) se pueden llamar
# sin pantalla. Eso no es una comodidad, es lo que permite comprobar el
# contrato con datos, que es donde estan los fallos de verdad: que un menu
# devuelva el TEXTO en vez de la ETIQUETA, que un checklist devuelva las
# opciones que no estan marcadas, que cancelar escriba algo, que los codigos de
# color del motor aparezcan literalmente en la etiqueta.
cat >"${lab_gui}/pregunta.py" <<'PREGUNTA'
# Carga el frontal grafico y ejecuta el trozo de python que llega por la
# entrada estandar. Si el trozo revienta, se imprime 'CLASE: mensaje', que es
# justo lo que algunas comprobaciones esperan.
import importlib.util
import sys

# Como en el otro guion de la 6p: sin esto el '__pycache__' aparece en el
# arbol de la ISO. Lo explica alli.
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("vg", sys.argv[1])
modulo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(modulo)
m = modulo
try:
    exec(sys.stdin.read())
except Exception as error:  # noqa: BLE001 - aqui se espera a veces
    print("%s: %s" % (type(error).__name__, error))
PREGUNTA

pregunta() { python3 "${lab_gui}/pregunta.py" "${gui_py}"; }
# Lo mismo pero solo con el NOMBRE de la excepcion, que es lo unico que
# importa para el contrato: que el dato se quede sin poder abrir la ventana.
vienta() { python3 "${lab_gui}/pregunta.py" "${gui_py}" | cut -d: -f1; }

MENU='["--title","T","--backtitle","B","--menu","Elige",18,74,2,'
MENU="${MENU}"'"gnome","GNOME","sway","Sway"]'
MENU_DEF='["--title","T","--default-item","sway","--menu","E",18,74,2,'
MENU_DEF="${MENU_DEF}"'"gnome","GNOME","sway","Sway"]'
LISTA='["--title","T","--separate-output","--checklist","Apps",24,76,3,'
LISTA="${LISTA}"'"firefox","Firefox","on","steam","Steam","off",'
LISTA="${LISTA}"'"gimp","Gimp","on"]'

comprobar "el modulo se carga sin 'gi' (o sea, sin pantalla)" "" \
  "$(pregunta <<'FIN'
import sys
print("gi" in sys.modules and "HAY GI" or "")
FIN
)"
comprobar "el menu devuelve la ETIQUETA de la opcion, no su texto" "sway" \
  "$(pregunta <<FIN
print(m.salida_de(m.parse_argsv(${MENU}), eleccion="sway")[1])
FIN
)"
comprobar "el menu con el TEXTO en vez de la etiqueta, no puede" "ValueError" \
  "$(vienta <<FIN
m.salida_de(m.parse_argsv(${MENU}), eleccion="Sway")
FIN
)"
comprobar "cancelar es codigo 1 y no escribe nada" "1|" \
  "$(pregunta <<FIN
print("%s|%s" % m.salida_de(m.parse_argsv(${MENU}), acepta=False))
FIN
)"
comprobar "la fila marcada es la de --default-item" "1" \
  "$(pregunta <<FIN
print(m.item_por_defecto(m.parse_argsv(${MENU_DEF})))
FIN
)"
comprobar "sin --default-item, la fila marcada es la primera" "0" \
  "$(pregunta <<FIN
print(m.item_por_defecto(m.parse_argsv(${MENU})))
FIN
)"
DOS_LINEAS=$'firefox\ngimp'
comprobar "el checklist con --separate-output sale una por linea" \
  "${DOS_LINEAS}" \
  "$(pregunta <<FIN
print(m.salida_de(m.parse_argsv(${LISTA}), marcadas=["firefox","gimp"])[1])
FIN
)"
comprobar "el checklist sin --separate-output, con espacios" "firefox gimp" \
  "$(pregunta <<FIN
v = m.parse_argsv(${LISTA})
v["separado"] = False
print(m.salida_de(v, marcadas=["firefox","gimp"])[1])
FIN
)"
comprobar "el checklist devuelve SOLO las marcadas" "gimp" \
  "$(pregunta <<FIN
print(m.salida_de(m.parse_argsv(${LISTA}), marcadas=["gimp"])[1])
FIN
)"
comprobar "el checklist con una opcion que no esta, se queda sin poder" \
  "ValueError" \
  "$(vienta <<FIN
m.salida_de(m.parse_argsv(${LISTA}), marcadas=["navegador"])
FIN
)"
comprobar "el inputbox devuelve lo tecleado" "clave" \
  "$(pregunta <<FIN
d = m.parse_argsv(["--title","T","--inputbox","Clave",12,66,"titan"])
print(m.salida_de(d, texto="clave")[1])
FIN
)"
comprobar "el inputbox lee el texto de partida" "titan" \
  "$(pregunta <<FIN
d = m.parse_argsv(["--title","T","--inputbox","Clave",12,66,"titan"])
print(d["inicial"])
FIN
)"
comprobar "el passwordbox devuelve lo tecleado" "secreto" \
  "$(pregunta <<FIN
d = m.parse_argsv(["--title","T","--passwordbox","Clave",12,70])
print(m.salida_de(d, texto="secreto")[1])
FIN
)"
comprobar "el yesno se responde con el codigo, no con texto" "0|" \
  "$(pregunta <<'FIN'
d = m.parse_argsv(["--title","T","--yesno","Borrar",14,70])
print("%s|%s" % m.salida_de(d))
FIN
)"
comprobar "el msgbox se responde con el codigo, no con texto" "0|" \
  "$(pregunta <<'FIN'
d = m.parse_argsv(["--title","T","--msgbox","Listo",24,76])
print("%s|%s" % m.salida_de(d))
FIN
)"
SPAN_TITULO='<span foreground="#26a6a1" weight="bold">Titan</span>'
SPAN_MAL='<span foreground="#e01b24" weight="bold">mal</span>'
comprobar "un color del motor sale como span, y se cierra" \
  "${SPAN_TITULO} y ${SPAN_MAL}" \
  "$(pregunta <<'FIN'
print(m.a_markup("\033[1;36mTitan\033[0m y \033[1;31mmal\033[0m"))
FIN
)"
comprobar "el gris del motor sale con su transparencia" \
  '<span alpha="60%">nota</span>' \
  "$(pregunta <<'FIN'
print(m.a_markup("\033[2mnota\033[0m"))
FIN
)"
comprobar "'<' y '&' se esconden, que si no Pango se come el texto" \
  'a &lt;b&gt; &amp; c' \
  "$(pregunta <<'FIN'
print(m.a_markup("a <b> & c"))
FIN
)"
comprobar "una cuenta que no cuadra con sus opciones no se abre" "ValueError" \
  "$(vienta <<'FIN'
m.parse_argsv(["--title","T","--menu","E",18,74,3,"gnome","GNOME"])
FIN
)"
comprobar "un tipo de ventana desconocido no se abre" "ValueError" \
  "$(vienta <<'FIN'
m.parse_argsv(["--title","T","--radiolist","E",18,74,1,"a","b","on"])
FIN
)"
comprobar "una opcion sin valor no se abre" "ValueError" \
  "$(vienta <<'FIN'
m.parse_argsv(["--title"])
FIN
)"
comprobar "un menu con un numero impar de campos no se abre" "ValueError" \
  "$(vienta <<'FIN'
m.parse_argsv(["--title","T","--menu","E",18,74,2,"gnome","GNOME","sway"])
FIN
)"
comprobar "sin tipo de ventana no hay nada que abrir" "ValueError" \
  "$(vienta <<'FIN'
m.parse_argsv(["--title","T","--backtitle","B"])
FIN
)"

# --- 6p.4. el programa entero, con la pantalla rota --------------------------
#
# Aqui no hay ningun simulacro: se lanza el programa de verdad y sin
# pantalla, que es justo lo que pasa en un equipo sin tarjeta o cuando cage
# no ha podido arrancar. Salen dos cosas, y se comprueban por separado porque
# fallan por motivos distintos:
#
#   - el CODIGO, que tiene que ser 2. El 2 es lo unico que 'ventana()' traduce
#     en "cae al modo de texto". El programa nace con el 1 en el bolsillo (que
#     es "el usuario ha pulsado Esc") y, si al pintar la ventana revienta
#     algo, PyGObject se come la excepcion del manejador de 'activate': sin
#     codigo 2, el motor
#     leeria un cancelado, se quedaria con todos los valores por defecto e
#     instalaria entero, en silencio y con codigo de exito.
#   - el SILENCIO en la salida de error, que es donde el motor lee la eleccion
#     del usuario. Si el grafico escribiera ahi su diagnostico, al caer al modo
#     de texto el motor leeria ese texto como respuesta y instalaria lo que
#     dijera su primera linea.
# Tres lineas SIEMPRE, y en este orden:
#   1. el codigo de salida
#   2. cuantos bytes han salido por la salida de error (0 es que no ha
#      salido ni uno, que es lo que se comprueba; un recuento de bytes no
#      se lia con un texto de varias lineas ni con espacios)
#   3. el diagnostico, con los saltos de linea cambiados por '~' para que
#      quepa en una linea y se pueda ver de un vistazo
roto() { # roto ARGS...
  local errf rc=0 diag
  errf="$(mktemp "${TMPDIR:-/tmp}/titan-gui-err.XXXXXX")"
  diag="$(env -u WAYLAND_DISPLAY -u GDK_BACKEND DISPLAY=:99 \
          TITAN_GUI_PRUEBA=aceptar \
          timeout 30 python3 "${gui_py}" "$@" 2>"${errf}")" || rc=$?
  printf '%s\n' "${rc}"
  printf '%s\n' "$(wc -c <"${errf}" | tr -d ' ')"
  printf '%s\n' "$(printf '%s' "${diag}" | tr '\n' '~')"
  rm -f "${errf}"
}

mapfile -t lin < <(roto --title T --menu "Elige" 18 74 1 gnome GNOME)
comprobar "sin pantalla, el grafico contesta 2 (no 1, que es 'cancelado')" \
  "2" "${lin[0]}"
comprobar "sin pantalla, no escribe NADA en la salida de error" "0" "${lin[1]}"
comprobar "sin pantalla, dice por que ha fallado (por la salida estandar)" \
  "1" "$(grep -c . <<<"${lin[2]}")"
comprobar "sin pantalla, el fallo se ve aunque este el gancho de pruebas" \
  "2" "$(roto --title T --menu "Elige" 18 74 1 gnome GNOME | head -n1)"

# Lo mismo con una caja que se puede cancelar, y con una que ni siquiera llega
# a pintarse (argumentos rotos). Las dos tienen que acabar en 2 y en silencio:
# si un '--msgbox' con la pantalla rota devolviera 0, el motor creeria que el
# usuario habia visto el mensaje.
mapfile -t lin < <(roto --title T --msgbox "Listo" 24 76)
comprobar "sin pantalla, hasta un msgbox contesta 2" "2" "${lin[0]}"
comprobar "sin pantalla, ni un msgbox escribe en la salida de error" \
  "0" "${lin[1]}"
mapfile -t lin < <(roto --title T --yesno "Borrar" 14 70)
comprobar "sin pantalla, un yesno contesta 2 y no 1" "2" "${lin[0]}"

# Y con argumentos que no valen, que es el otro camino al mismo 2.
mapfile -t lin < <(roto --title T --menu "Elige" 18 74 3 gnome GNOME)
comprobar "una cuenta que no cuadra sale con 2, no con una excepcion" \
  "2" "${lin[0]}"
comprobar "una cuenta que no cuadra tampoco escribe en la salida de error" \
  "0" "${lin[1]}"
mapfile -t lin < <(roto --title)
comprobar "una ventana a medio hacer sale con 2" "2" "${lin[0]}"
comprobar "una ventana a medio hacer no escribe nada" "0" "${lin[1]}"
# Lo que NO se puede comprobar aqui, y conviene no disimular: que el descriptor
# 2 este apartado a /dev/null antes de abrir la ventana. Ese aparto esta para
# tapar los avisos que escriben GTK y PyGObject por su cuenta, pero en este
# equipo (cage sin salida fisica, GDK por wayland) las bibliotecas callan: se ha
# probado con 'GSK_RENDERER' inventado, con 'GDK_DEBUG' y con backends raros, y
# no sale ni un byte. Sin ruido de biblioteca, quitar el aparto no se nota. Lo
# que si se nota, y por eso esta seccion lo comprueba, es el diagnostico del
# propio programa, que es el que si puede acabar en la ranura de la respuesta.
nota "el aparto del descriptor 2 no se puede comprobar aqui: las bibliotecas" \
     "callan (si se comprueba el diagnostico propio, que ese si se oye)"

# --- 6p.5. la ventana de verdad, pintada con GTK ------------------------------
#
# Las seis cajas, de verdad, dentro de cage, contestando solas con el gancho
# 'TITAN_GUI_PRUEBA'. Esto es lo que las comprobaciones con datos no pueden
# hacer: ellas miran el diccionario, no el widget. Cada linea que sale de ahi
# es 'RESULTADO <caja> rc=<codigo> resp=<respuesta con los saltos de linea
# cambiados por ~>', y de una en una se comparan con 'grep -x', que no se
# lian con prefijos ni con Ventanas que se parezcan.
#
# Y si en el equipo donde corre esto no hay 'cage', se dice en voz alta que esta
# parte queda sin comprobar: un silencio aqui seria indistinguible de "todo
# bien", que es justo lo que este comprobador no puede ser.
xdg_gui="${lab_gui}/xdg"
mkdir -p "${xdg_gui}"
chmod 700 "${xdg_gui}"
if ! command -v cage >/dev/null 2>&1; then
  echo "  AVISO: en este equipo no hay 'cage', y las seis ventanas NO se han"
  echo "  pintado. Lo de arriba (los vectores de verdad del motor, el contrato"
  echo "  y las funciones puras) si se ha comprobado entero."
else
cat >"${lab_gui}/dentro.sh" <<'DENTRO'
#!/bin/bash
# Corre DENTRO de cage, que es un compositor de Wayland: GDK tiene que hablar
# Wayland, y la pantalla se levanta en un backend sin salida fisica (headless),
# que es lo unico que se puede hacer sin monopolizar el escritorio de quien
# esta corrigiendo esto.
set -uo pipefail
export GDK_BACKEND=wayland
GUI="$1"
uno() { # uno CAJA PRUEBA ARGS...
  local caja="$1" prueba="$2"; shift 2
  local rc=0 respuesta
  respuesta="$(TITAN_GUI_PRUEBA="${prueba}" timeout 30 \
               python3 "${GUI}" "$@" 2>&1 1>/dev/null)" || rc=$?
  printf 'RESULTADO %s rc=%s resp=%s\n' "${caja}" "${rc}" \
    "$(printf '%s' "${respuesta}" | tr '\n' '~')"
}
uno menu        aceptar --title T --backtitle B --menu "Elige" 18 74 2 \
     gnome GNOME sway Sway
uno menu_def    aceptar --title T --default-item sway --menu "Elige" 18 74 2 \
     gnome GNOME sway Sway
uno menu_cancel cancelar --title T --menu "Elige" 18 74 2 gnome GNOME sway Sway
uno menu_texto  aceptar --title T --menu "Elige" 18 74 2 gnome GNOME sway Sway
uno menu_vacio  aceptar --title T --menu "Elige" 18 74 0
uno lista_sep   aceptar --title T --separate-output --checklist Apps 24 76 3 \
     firefox Firefox on steam Steam off gimp Gimp on
uno lista_junto aceptar --title T --checklist Apps 24 76 3 \
     firefox Firefox on steam Steam off gimp Gimp on
uno lista_una   aceptar --title T --separate-output --checklist Apps 24 76 3 \
     firefox Firefox on steam Steam off gimp Gimp off
uno entrada     aceptar --title T --inputbox "Nombre" 12 66 titan
uno clave       aceptar --title T --passwordbox "Clave" 12 70
uno si          aceptar --title T --yesno "Borrar" 14 70
uno no          cancelar --title T --yesno "Borrar" 14 70
uno si_no       aceptar --title T --defaultno --yesno "Borrar" 14 70
uno mensaje     aceptar --title T --msgbox "Listo" 24 76
DENTRO
  chmod 755 "${lab_gui}/dentro.sh"
  cage_log="${lab_gui}/cage.log"
  salida_cage="$(env XDG_RUNTIME_DIR="${xdg_gui}" WLR_BACKENDS=headless \
    timeout 600 cage -- "${lab_gui}/dentro.sh" "${gui_py}" \
    >"${lab_gui}/dentro.out" 2>"${cage_log}")" || true
  pintadas="$(grep -c '^RESULTADO ' "${lab_gui}/dentro.out" || true)"
  if [[ "${pintadas}" -ne 14 ]]; then
    falla "dentro de cage han salido ${pintadas} ventanas de las 14"
    sed 's/^/        /' "${lab_gui}/dentro.out"
    sed 's/^/        cage: /' "${cage_log}" | tail -n 5
  fi
  # El menu devuelve la etiqueta, no el texto: el motor busca por etiqueta.
  caja_gui() { # caja_gui LINEA_QUE_SE_BUSCA
    grep -c -x "$1" "${lab_gui}/dentro.out" || true
  }
  comprobar "pintada: el menu devuelve la ETIQUETA de la fila marcada" "1" \
    "$(caja_gui 'RESULTADO menu rc=0 resp=gnome')"
  comprobar "pintada: --default-item marca esa fila" "1" \
    "$(caja_gui 'RESULTADO menu_def rc=0 resp=sway')"
  comprobar "pintada: el menu devuelve solo la etiqueta de lo elegido" "1" \
    "$(caja_gui 'RESULTADO menu_texto rc=0 resp=gnome')"
  # Un menu SIN OPCIONES se puede construir a base de datos (la cuenta cuadra:
  # cero pares, cero), pero no se puede pintar: al elegir la fila por defecto
  # revienta un 'IndexError' DENTRO del manejador de 'activate'. Ahi PyGObject
  # se come la excepcion y sigue como si nada: la ventana se queda abierta sin
  # nadie que la cierre, el programa no llega a responder y '__main__' espera
  # hasta que lo matan. Esto NO es una comprobacion de codigo 1, que tambien
  # es lo que sale: es que la respuesta tiene que LLEGAR, y como codigo 2, que
  # es 'no se ha podido abrir'. El 1 es lo que parece cuando el usuario pulsa
  # Esc, y con el 1 el motor se quedaria con los valores por defecto en
  # silencio, que es el fallo mas caro que puede tener esta pantalla.
  comprobar "pintada: un menu sin opciones sale con 2, no colgado" "1" \
    "$(caja_gui 'RESULTADO menu_vacio rc=2 resp=')"
  comprobar "pintada: cancelar es codigo 1 y no escribe nada" "1" \
    "$(caja_gui 'RESULTADO menu_cancel rc=1 resp=')"
  comprobar "pintada: el checklist con --separate-output, uno por linea" "1" \
    "$(caja_gui 'RESULTADO lista_sep rc=0 resp=firefox~gimp')"
  comprobar "pintada: el checklist sin --separate-output, con espacios" "1" \
    "$(caja_gui 'RESULTADO lista_junto rc=0 resp=firefox gimp')"
  comprobar "pintada: el checklist devuelve solo las marcadas" "1" \
    "$(caja_gui 'RESULTADO lista_una rc=0 resp=firefox')"
  comprobar "pintada: el inputbox devuelve lo tecleado" "1" \
    "$(caja_gui 'RESULTADO entrada rc=0 resp=titan')"
  comprobar "pintada: el passwordbox se acepta con codigo 0" "1" \
    "$(caja_gui 'RESULTADO clave rc=0 resp=')"
  comprobar "pintada: el yesno se contesta con el codigo y sin texto" "1" \
    "$(caja_gui 'RESULTADO si rc=0 resp=')"
  comprobar "pintada: contestar 'No' es codigo 1" "1" \
    "$(caja_gui 'RESULTADO no rc=1 resp=')"
  comprobar "pintada: un --defaultno sigue siendo un 'Si' si se acepta" "1" \
    "$(caja_gui 'RESULTADO si_no rc=0 resp=')"
  comprobar "pintada: el msgbox se cierra con el boton y contesta 0" "1" \
    "$(caja_gui 'RESULTADO mensaje rc=0 resp=')"
  comprobar "dentro de cage no se cuela NADA de GTK en las respuestas" "0" \
    "$(grep -c -i -e 'Gtk-CRITICAL' -e 'assertion' -e 'Traceback' \
           "${lab_gui}/dentro.out" || true)"
  # Y que ninguna de las catorce lineas lleve el codigo 2, que aqui solo puede
  # significar que la ventana no se ha podido pintar. La del menu sin opciones
  # se deja fuera a proposito: esa TIENE que salir con 2, y es la comprobacion
  # de justo encima.
  comprobar "dentro de cage ninguna ventana se queda sin pintar" "0" \
    "$(grep '^RESULTADO ' "${lab_gui}/dentro.out" | grep -v 'menu_vacio' \
        | grep -c 'rc=2' || true)"
fi

# --- 6p.6. quien se abre: el reparto de 'ventana()' --------------------------
#
# Con un 'dialog' de mentira delante, que solo apunta que le han llamado y
# contesta una cosa fija por la salida de error. Se comprueban las cuatro
# decisiones de 'ventana()' sin pintar nada:
#
#   1. Sin TITAN_GUI no se mira ni el grafico: pantalla de texto.
#   2. Con TITAN_GUI=1 y la pantalla rota, cae al texto, y la respuesta tiene
#      que ser EXACTAMENTE la del dialog de mentira. Esa es la comprobacion
#      que caza al frontal grafico si escribe su diagnostico (o un aviso de
#      GTK) por la salida de error: al caer al texto, ese texto se pegaria
#      delante de la respuesta y el motor instalaria lo que dijera.
#   3. El codigo del texto se propaga tal cual: si el dialog contesta 1,
#      'ventana()' devuelve 1 (cancelado) y no 0.
#   4. Con TITAN_GUI=1 pero sin fichero ejecutable, tambien al texto. Esto no es
#      hipotetico: sin el permiso de ejecucion, 'ventana()' se salta el grafico
#      sin decir nada, y en la ISO el permiso lo declara el perfil del live.
#   5. Y que el grafico se abre CUANDO TOCA, no solo que la respuesta final
#      cuadre. Eso se mira con un frontal de mentira que solo deja rastro de
#      que le han llamado (vease 'frontal-marcador' mas abajo), porque si no
#      los dos caminos indistinguibles: un frontal que se ejecutase de mas
#      acabaria cayendo al texto igualmente y la respuesta seria la misma.
mkdir -p "${lab_gui}/texto"
cat >"${lab_gui}/texto/dialog" <<'MENTIRA'
#!/bin/bash
# El dialog de mentira: apunta que le han llamado y contesta por la salida de
# error, que es la ranura por la que el motor lee la eleccion del usuario.
printf 'PANTALLA-TEXTO\n' >>"${TITAN_ESPIA}"
echo "RESPUESTA-DEL-TEXTO" >&2
exit "${FAKE_DIALOG_RC:-0}"
MENTIRA
chmod 755 "${lab_gui}/texto/dialog"
cat >"${lab_gui}/llama.sh" <<'LLAMA'
#!/bin/bash
# Llama a 'ventana()' como el motor, con su juego de descriptores de siempre, y
# dice en una linea que codigo ha salido, que se ha leido y cuantas pantallas
# de texto se han abierto. Los argumentos que se le pasan son los de la
# ventana, con '--title T' puesto delante.
set -uo pipefail
RAIZ="$1"; LAB="$2"; GUI="$3"; shift 3
export AUTO=0 TITAN_SILENCIO=1
export TITAN_LOG="${LAB}/log" TITAN_ESPIA="${LAB}/llamadas"
export PATH="${LAB}/texto:${PATH}"
# El registro se crea vacio antes de llamar: si el grafico contesta y el
# dialog no llega a abrirse, 'grep -c' sobre un fichero que no existe no
# imprime ni un 0 (imprime un error y nada mas) y la comprobacion de
# 'no se abrio la pantalla de texto' se queda sin comparar.
: >"${LAB}/llamadas"
source "${RAIZ}/instalador/lib-comun.sh"
# La ruta del frontal la decide quien llama, para poder probar tambien el caso
# de que no exista o no sea ejecutable.
GUI_VENTANA="${GUI}"
rc=0
respuesta="$(ventana "$@" 3>&1 1>&2 2>&3)" || rc=$?
# 'marca' cuenta las llamadas al frontal de mentira, que solo deja rastro.
printf 'rc=%s|resp=[%s]|texto=%s|marca=%s\n' "${rc}" "${respuesta}" \
  "$(grep -c '^PANTALLA-TEXTO' "${LAB}/llamadas" 2>/dev/null || true)" \
  "$(grep -c '^FRONTAL-MARCADO' "${LAB}/llamadas" 2>/dev/null || true)"
LLAMA
chmod 755 "${lab_gui}/llama.sh"
# El mismo frontal pero sin permiso de ejecucion, que es el caso 4.
cp "${gui_py}" "${lab_gui}/sin-permiso.py"
chmod 644 "${lab_gui}/sin-permiso.py"
# Y un frontal que NO pinta nada: solo deja escrito que le han llamado y
# contesta 2 (que es 'no se ha podido abrir la pantalla'). Asi se puede
# preguntar a 'ventana()' si abre el grafico o no, y no solo que la
# respuesta final sea la misma en los dos caminos.
cat >"${lab_gui}/frontal-marcador" <<'MARCA'
#!/bin/bash
printf 'FRONTAL-MARCADO\n' >>"${TITAN_ESPIA}"
exit 2
MARCA
chmod 755 "${lab_gui}/frontal-marcador"
cp "${lab_gui}/frontal-marcador" "${lab_gui}/marcador-sin-permiso"
chmod 644 "${lab_gui}/marcador-sin-permiso"

llamar() { # llamar RUTA_DEL_FRONTAL ARGS... -> una linea
  local gui="$1"; shift
  rm -f "${lab_gui}/llamadas"
  env -u DISPLAY -u WAYLAND_DISPLAY -u WAYLAND_SOCKET \
    TITAN_GUI="${TITAN_GUI:-0}" FAKE_DIALOG_RC="${FAKE_DIALOG_RC:-0}" \
    timeout 60 bash "${lab_gui}/llama.sh" "${RAIZ}" "${lab_gui}" "${gui}" \
    --title T "$@" 2>/dev/null
}
TEXTO_1='rc=0|resp=[RESPUESTA-DEL-TEXTO]|texto=1|marca=0'
comprobar "sin TITAN_GUI se abre la pantalla de texto" "${TEXTO_1}" \
  "$(TITAN_GUI=0 llamar "${gui_py}" --menu "Elige" 18 74 1 gnome GNOME)"
comprobar "con TITAN_GUI=1 pero sin pantalla se cae al texto" "${TEXTO_1}" \
  "$(TITAN_GUI=1 llamar "${gui_py}" --menu "Elige" 18 74 1 gnome GNOME)"
comprobar "el cancelado del texto se propaga tal cual (1, no 0)" \
  'rc=1|resp=[RESPUESTA-DEL-TEXTO]|texto=1|marca=0' \
  "$(TITAN_GUI=1 FAKE_DIALOG_RC=1 llamar "${gui_py}" --yesno "Borrar" 14 70)"
comprobar "con TITAN_GUI=1 pero sin permiso, tambien se cae al texto" \
  "${TEXTO_1}" \
  "$(TITAN_GUI=1 llamar "${lab_gui}/sin-permiso.py" --menu "Elige" 18 74 1 a A)"
comprobar "TITAN_GUI=1 sin el frontal puesto, tampoco pasa nada" \
  "${TEXTO_1}" \
  "$(TITAN_GUI=1 llamar "/no/existe/ventana-gui.py" --msgbox "L" 24 76)"
# Los tres de aqui son los que miran QUIEN se abre. El frontal de mentira
# contesta 2, o sea que al final se acaba en el texto igual que en los
# casos de antes: lo unico que cambia es si ha pasado por el grafico.
comprobar "sin TITAN_GUI, el frontal grafico ni se mira" \
  "${TEXTO_1}" \
  "$(TITAN_GUI=0 llamar "${lab_gui}/frontal-marcador" --msgbox "L" 24 76)"
comprobar "con TITAN_GUI=1 y sin permiso, el grafico no se ejecuta" \
  "${TEXTO_1}" \
  "$(TITAN_GUI=1 llamar "${lab_gui}/marcador-sin-permiso" --msgbox "L" 24 76)"
comprobar "con TITAN_GUI=1 y el frontal ejecutable, si se ejecuta" \
  'rc=0|resp=[RESPUESTA-DEL-TEXTO]|texto=1|marca=1' \
  "$(TITAN_GUI=1 llamar "${lab_gui}/frontal-marcador" --msgbox "L" 24 76)"

# Y el reparto con la pantalla de verdad, dentro de cage: ahora la respuesta
# tiene que ser la del grafico y la pantalla de texto no se abre ni una vez.
if command -v cage >/dev/null 2>&1; then
  rm -f "${lab_gui}/llamadas"
  con_pantalla="$(env XDG_RUNTIME_DIR="${xdg_gui}" WLR_BACKENDS=headless \
    TITAN_GUI=1 TITAN_GUI_PRUEBA=aceptar \
    timeout 120 cage -- bash "${lab_gui}/llama.sh" "${RAIZ}" "${lab_gui}" \
      "${gui_py}" --title T --menu "Elige" 18 74 2 gnome GNOME sway Sway \
      2>/dev/null)"
  comprobar "con pantalla, contesta el grafico" \
    'rc=0|resp=[gnome]|texto=0|marca=0' "${con_pantalla}"
else
  echo "  AVISO: sin 'cage' no se ha comprobado el reparto con pantalla real."
fi

# --- 6p.7. las tres decisiones de 'install.sh --grafico' ---------------------
#
# La funcion se saca del fichero con 'sed' y se llama sola, en una subshell,
# con un 'echo' despues: si hiciera 'exec cage', la subshell desapareceria y no
# imprimiria nada, que es justo como se distingue "ha levantado la pantalla" de
# "ha decidido que no". Los cuatro casos, que son cuatro caminos distintos:
#
#   1. Ya va dentro de cage (TITAN_DENTRO_GRAFICO=1): solo pone TITAN_GUI y NO
#      vuelve a lanzar cage, que si no metia un compositor dentro de otro.
#   2. Hay una sesion grafica de las de verdad (DISPLAY o WAYLAND_DISPLAY): se
#      usa tal cual, sin tocar nada.
#   3. No hay sesion y no hay grafica en /dev/dri: avisa en un par de lineas y
#      sigue en modo de texto, SIN lanzar nada. Sin este camino, 'sudo
#      install.sh --grafico' en una VM sin video se quedaria sin hacer nada y
#      sin decir por que.
#   4. Hay grafica pero no hay cage: tambien avisa y sigue en texto.
fun_gui="${lab_gui}/arranca-gui.sh"
# Las DOS funciones, y en orden, porque 'arranca_grafico' llama a
# 'asegura_asiento': sacar solo la primera daria un fichero que no puede
# funcionar, y el fallo se veria como un fallo del entorno cuando lo que
# faltaria seria del producto (fallo 44).
sed -n '/^asegura_asiento() {/,/^}/p' "${RAIZ}/install.sh" >"${fun_gui}"
sed -n '/^arranca_grafico() {/,/^}/p' "${RAIZ}/install.sh" >>"${fun_gui}"
n_funciones="$(grep -c '^[a-z_]*() {' "${fun_gui}" 2>/dev/null || true)"
n_funciones="${n_funciones:-0}"
if [[ "${n_funciones}" == 2 ]]; then
  ok "las dos funciones de la pantalla se sacan enteras de install.sh"
else
  falla "no se han podido sacar las dos funciones de la pantalla"
  printf '        esperado: asegura_asiento() y arranca_grafico()\n'
  printf '                  en %s\n' "${RAIZ}/install.sh"
  printf '        han salido: %s\n' "${n_funciones}"
fi
if [[ -s "${fun_gui}" ]]; then
  ok "la pantalla se puede probar fuera del install.sh entero"
else
  falla "install.sh no trae nada de la pantalla"
  printf '        esperado: al menos arranca_grafico()\n'
  printf '                  en %s\n' "${RAIZ}/install.sh"
fi
comprobar "arranca_grafico() no se ejecuta sin --grafico" \
  "1" \
  "$(grep -c '\[\[ "\${GRAFICO}" == "1" \]\] && arranca_grafico' \
      "${RAIZ}/install.sh")"
comprobar "--grafico esta entre las opciones que install.sh acepta" "1" \
  "$(grep -c -- '--grafico)    GRAFICO=1 ;;' "${RAIZ}/install.sh")"
comprobar "install.sh --grafico-inventada se rechaza con codigo 2" "2" \
  "$(bash "${RAIZ}/install.sh" --grafico-inventada >/dev/null 2>&1; echo $?)"

if [[ -s "${fun_gui}" ]]; then
  # Un directorio con lo JUSTO que usan las funciones (id, mkdir, chmod, sleep y
  # rm) y sin cage, para poder probar el caso 'sin cage' sin desinstalar nada.
  # 'sleep' lo usa la espera del asiento y 'rm' la limpieza de los bloqueos de
  # Wayland: sin los dos, la funcion se cae antes de decidir nada y el caso
  # parece un fallo del producto cuando es del banco.
  # El PATH de los dos casos de abajo es un directorio con lo JUSTO que usa
  # la funcion, en un caso sin 'cage' y en el otro con un 'cage' de mentira.
  # Con un PATH de mas el caso 'sin cage' no se puede ni plantear:
  # 'command -v cage' lo encontraria en /usr/bin y la rama no se tomaria. Y
  # 'bash' tiene que estar en ese directorio, o el propio 'env' no lo
  # encuentra y no llega a arrancar nada.
  mkdir -p "${lab_gui}/poco"
  for herramienta in bash id mkdir chmod sleep rm; do
    donde="$(command -v "${herramienta}" 2>/dev/null)" && \
      ln -sf "${donde}" "${lab_gui}/poco/${herramienta}"
  done
  # El guion que corre DENTRO de cage. En un heredoc y no metido en el
  # 'bash -c', porque si no hay que anidar comillas de tres niveles y basta con
  # equivocarse una vez con el anidamiento para que el comando entero se
  # trague el comentario que lo separa de sus argumentos.
  #
  # La trampa de EXIT es lo que hace posible mirar el codigo de salida: un
  # 'exit 3' de 'arranca_grafico' se lleva por delante el 'echo' que hay
  # debajo, y sin la trampa el caso no contestaria nada. Tambien hace
  # observable 'con_cage', que antes se resolvia con el 'exec cage'.
  #
  # Y con comillas SENCILLAS en la trampa, y no dobles: entre dobles, el '$?'
  # se expande al DEFINIR la trampa (que es cuando el rc es 0) y no al
  # dispararla, de modo que siempre decia 'RC=0' y la comprobacion del cancelado
  # no podia ver nada.
  guion_dentro_cage() { cat <<'FINO'
trap 'echo "RC=$?"' EXIT
ARGUMENTOS=(--grafico --inventada)
source "$1"; arranca_grafico
echo "GUI=${TITAN_GUI:-0} DENTRO=${TITAN_DENTRO_GRAFICO:-0}"
FINO
  }
  decision() { # decision VARIANTE [PATH] -> todo lo que ha dicho
    local variante="$1"
    case "${variante}" in
      dentro)
        env -u DISPLAY -u WAYLAND_DISPLAY TITAN_DENTRO_GRAFICO=1 \
          bash -c 'source "$1"; arranca_grafico; echo "GUI=${TITAN_GUI:-0}"' \
          _ "${fun_gui}" 2>&1 ;;
      sesion)
        env TITAN_DENTRO_GRAFICO=0 DISPLAY=:9 WAYLAND_DISPLAY= \
          bash -c 'source "$1"; arranca_grafico; echo "GUI=${TITAN_GUI:-0}"' \
          _ "${fun_gui}" 2>&1 ;;
      sin_graficos)
        # /dev/dri se tapa con un tmpfs vacio, para no tocar el equipo: si este
        # equipo no tiene /dev/dri, no hace falta tapar nada. Montar en un
        # directorio del sistema necesita privilegios, y el comprobador se
        # ejecuta unas veces como root y otras como un usuario normal, asi que
        # el espacio de montaje va DENTRO de uno de usuario ('-Urm'): ahi
        # cualquiera es root solo dentro y el montaje se concede. Con '-m' a
        # secas, como usuario normal, 'unshare' dice que no y aqui no se
        # comprobaria nada sin que se note (que es justo lo que hacia esta
        # comprobacion al principio: se ponia en verde porque no se miraba).
        unshare -Urm --propagation private bash -c '
          if [[ -d /dev/dri ]]; then
            mount -t tmpfs none /dev/dri || exit 3
          fi
          unset DISPLAY WAYLAND_DISPLAY TITAN_DENTRO_GRAFICO TITAN_GUI
          export PATH="/usr/bin:/bin"
          source "$1"; arranca_grafico; echo "GUI=${TITAN_GUI:-0}"
        ' _ "${fun_gui}" 2>&1 ;;
      sin_cage)
        # /dev/dri de verdad, pero un PATH donde no esta cage.
        env -u DISPLAY -u WAYLAND_DISPLAY -u TITAN_DENTRO_GRAFICO -u TITAN_GUI \
          PATH="$2" bash -c \
          'source "$1"; arranca_grafico; echo "GUI=${TITAN_GUI:-0}"' \
          _ "${fun_gui}" 2>&1 ;;
      sin_seatd|seatd_malo)
        # Hay grafica y hay cage, pero el asiento no se puede abrir: en el
        # primero porque no esta 'seatd' en el PATH, y en el segundo porque
        # 'seatd' sale bien pero no llega a enlazar su socket. Los dos tienen
        # que acabar en modo de texto y SIN lanzar cage: si se lanzara, en el
        # live se moria con 'No backend was able to open a seat' (fallo 44).
        rm -f "${lab_gui}/asiento.sock"
        env -u DISPLAY -u WAYLAND_DISPLAY -u TITAN_DENTRO_GRAFICO -u TITAN_GUI \
          SEATD_SOCK="${lab_gui}/asiento.sock" PATH="$2" bash -c \
          'source "$1"; arranca_grafico
           echo "GUI=${TITAN_GUI:-0} DENTRO=${TITAN_DENTRO_GRAFICO:-0}"' \
          _ "${fun_gui}" 2>&1 ;;
      con_cage|con_cage_roto|con_cage_cancelado)
        # Un cage de mentira, para ver a quien se lanzaria y con que
        # argumentos. El programa que se lanzaria sale del 'BASH_SOURCE' de
        # esta copia recortada (no es install.sh, porque aqui las funciones
        # viven solas en un fichero), asi que de esa parte no se comprueba
        # nada: lo que se mira es que se llegue a lanzarlo y que los
        # argumentos no se pierdan ni se cambien de orden. 'ARGUMENTOS' es
        # lo que el propio install.sh llena con sus argumentos
        # ('ARGUMENTOS=("$@")'), y aqui se llena a proposito para poder
        # mirar lo que llega al otro extremo: relanzar el instalador sin
        # '--grafico' (que es como se perdia la pantalla al meterse en
        # cage) dejaria la segunda vuelta en modo de texto sin avisar.
        #
        # 'con_cage_roto' es el mismo camino con un cage que sale con 1, que
        # es lo que pasaba de verdad en el live: cage se moria y, como lo
        # lanzaba con 'exec', se llevaba por delante al instalador entero.
        #
        # 'con_cage_cancelado' es el mismo camino con un cage que sale con 3,
        # que es el codigo de 'cancelado'. Lo produce 'cancelar()' en
        # 'lib-comun.sh' cuando se pulsa Esc en una pantalla SIN valor por
        # defecto (la contrasena). Ese 3 sale de la shell que corre DENTRO de
        # cage, asi que llega aqui, y antes de arreglarlo lo que hacia era
        # contarlo como un fallo de cage y VOLVER AL MODO DE TEXTO: el
        # usuario cancelaba y veia empezar otra vez una instalacion (fallo 46).
        case "$1" in
          con_cage_roto)     rc_cage=1 ;;
          con_cage_cancelado) rc_cage=3 ;;
          *)                 rc_cage=0 ;;
        esac
        rm -f "${lab_gui}/cage-llamadas" "${lab_gui}/asiento.sock"
        # La trampa de EXIT del guion de dentro es lo que hace posible mirar el
        # codigo: un 'exit 3' de 'arranca_grafico' se lleva por delante el
        # 'echo' que hay detras, y sin la trampa el caso no contestaria nada.
        # Tambien hace observable 'con_cage', que antes se resolvia con el
        # 'exec cage'. OJO con el comentario: va ANTES del comando y nunca
        # entre una barra de continuacion y su linea siguiente. La barra se
        # quita antes de quitar los comentarios, de modo que un comentario en
        # medio se come el comando entero: aqui 'env' se quedaba sin comando y
        # lo unico que hacia era imprimir el entorno, con lo que todos los
        # casos de cage parecian funcionar sin lanzar nada.
        env -u DISPLAY -u WAYLAND_DISPLAY -u TITAN_DENTRO_GRAFICO -u TITAN_GUI \
          SEATD_SOCK="${lab_gui}/asiento.sock" \
          TITAN_CAGE_RC="${rc_cage}" \
          PATH="$2" bash -c "$(guion_dentro_cage)" _ "${fun_gui}" 2>&1 ;;
    esac
  }
  mkdir -p "${lab_gui}/cage-falso" "${lab_gui}/seatd-falso" \
    "${lab_gui}/seatd-malo"
  cat >"${lab_gui}/cage-falso/cage" <<'FINO'
#!/bin/bash
printf 'CAGE-FALSO args=[%s] dentro=%s gui=%s\n' "$*" \
  "${TITAN_DENTRO_GRAFICO:-0}" "${TITAN_GUI:-0}" >>"${TITAN_CAGE}"
printf 'CAGE-FALSO args=[%s]\n' "$*"
# El codigo de salida es lo que separa 'con_cage' de 'con_cage_roto'. Con
# 'TITAN_CAGE_RC' sin poner sale 0, que es lo que hacia este cage de mentira
# antes de que existiera el caso de cage que muere.
exit "${TITAN_CAGE_RC:-0}"
FINO
  chmod 755 "${lab_gui}/cage-falso/cage"
  # El 'seatd' de mentira tiene que abrir un socket DE VERDAD, porque la
  # funcion mira si el fichero es un socket ('-S') y un fichero vacio no lo
  # es. De bash no hay manera de crear un socket de unix, asi que lo abre
  # python3, que ademas es quien lee de '$SEATD_SOCK' la ruta que le ha dado
  # la funcion (y no '/run/seatd.sock', que en este equipo es otra cosa).
  # Los dos escriben en el MISMO fichero que el cage, que es como se puede
  # mirar cual de los dos va primero.
  python_seatd="$(command -v python3 2>/dev/null || true)"
  if [[ -n "${python_seatd}" ]]; then
    cat >"${lab_gui}/seatd-falso/seatd" <<FINO
#!/bin/bash
printf 'SEATD-FALSO socket=%s\n' "\${SEATD_SOCK:-/run/seatd.sock}" \
  >>"\${TITAN_CAGE}"
"${python_seatd}" -c '
import os, socket, time
p = os.environ["SEATD_SOCK"]
try:
    os.unlink(p)
except OSError:
    pass
socket.socket(socket.AF_UNIX).bind(p)
time.sleep(20)
' &
FINO
    chmod 755 "${lab_gui}/seatd-falso/seatd"
  else
    printf '        OJO: sin python3 no se puede abrir un socket de unix, y\n'
    printf '        los casos con asiento NO se pueden mirar en este equipo.\n'
  fi
  # Y un seatd que sale bien pero nunca abre el socket: es lo que pasa si el
  # servicio no levanta, y la funcion tiene que agotar la espera y caer a
  # texto en vez de lanzar cage a ciegas.
  cat >"${lab_gui}/seatd-malo/seatd" <<'FINO'
#!/bin/bash
printf 'SEATD-FALSO-SIN-SOCKET\n' >>"${TITAN_CAGE}"
exit 0
FINO
  chmod 755 "${lab_gui}/seatd-malo/seatd"
  export TITAN_CAGE="${lab_gui}/cage-llamadas"

  # Cada caso se lanza UNA vez y se guarda lo que ha dicho. Antes se lanzaba
  # tres veces (una por comprobacion) y, lo que es peor, se comparaba la
  # salida de una ejecucion distinta con lo que se esperaba: si el caso no
  # llegaba a imprimir nada, la comprobacion se ponia en rojo sin que se
  # supiera por que. Con la salida a la vista, un caso que no ha corrido se
  # reconoce (no tiene la linea 'GUI=') y se dice en voz alta en vez de
  # contar como un fallo del producto.
  salida_dentro="$(decision dentro)"
  salida_sesion="$(decision sesion)"
  salida_sin_graficos="$(decision sin_graficos)"
  salida_sin_cage="$(decision sin_cage "${lab_gui}/poco")"
  salida_con_cage="$(decision con_cage \
    "${lab_gui}/seatd-falso:${lab_gui}/cage-falso:${lab_gui}/poco")"
  salida_sin_seatd="$(decision sin_seatd \
    "${lab_gui}/cage-falso:${lab_gui}/poco")"
  salida_seatd_malo="$(decision seatd_malo \
    "${lab_gui}/seatd-malo:${lab_gui}/cage-falso:${lab_gui}/poco")"
  salida_con_cage_roto="$(decision con_cage_roto \
    "${lab_gui}/seatd-falso:${lab_gui}/cage-falso:${lab_gui}/poco")"
  salida_con_cage_cancelado="$(decision con_cage_cancelado \
    "${lab_gui}/seatd-falso:${lab_gui}/cage-falso:${lab_gui}/poco")"

  # Y una comprobacion previa que no depende de nada: cada caso tiene que
  # haber llegado a contestAR, no solo a callarse. Salvo el quinto, que decide
  # relanzandose: ahi el 'echo' final no se ejecuta nunca, porque el 'exec
  # cage' se queda con la shell. Su manera de contestar es la linea del cage de
  # mentira, asi que se mira esa. (Con el mismo 'grep' para todos, este caso
  # se ponia en rojo siempre.)
  for caso in dentro sesion sin_graficos sin_cage con_cage sin_seatd \
    seatd_malo con_cage_roto con_cage_cancelado; do
    case "${caso}" in
      dentro) salida="${salida_dentro}" ;;
      sesion) salida="${salida_sesion}" ;;
      sin_graficos) salida="${salida_sin_graficos}" ;;
      sin_cage) salida="${salida_sin_cage}" ;;
      con_cage) salida="${salida_con_cage}" ;;
      sin_seatd) salida="${salida_sin_seatd}" ;;
      seatd_malo) salida="${salida_seatd_malo}" ;;
      con_cage_roto) salida="${salida_con_cage_roto}" ;;
      con_cage_cancelado) salida="${salida_con_cage_cancelado}" ;;
    esac
    if grep -q -e '^GUI=' -e 'CAGE-FALSO' -e 'No esta' \
      -e 'no ha abierto' <<<"${salida}"; then
      ok "el caso '${caso}' ha llegado a decidir"
    else
      # Esto se cuenta como fallo a proposito. Podria avisarse y seguir, pero
      # entonces el caso se quedaria sin comprobar en verde, que es como se
      # cuelan las comprobaciones que no miran nada. Con el fallo delante y el
      # motivo escrito (lo que dijo el entorno, abajo) no hay que adivinar si
      # lo que se ha roto es el producto o el equipo donde se prueba.
      falla "el caso '${caso}' no ha decidido nada, y no ha sido el producto"
      printf '        es este equipo, que no deja montarlo, asi que sus\n'
      printf '        comprobaciones de aqui abajo no valen. Lo que ha dicho\n'
      printf '        el entorno:\n'
      sed 's/^/          /' <<<"${salida}" | head -3
    fi
  done

  comprobar "dentro de cage, solo pone TITAN_GUI (no mete otro cage)" "1" \
    "$(grep -c '^GUI=1' <<<"${salida_dentro}")"
  comprobar "dentro de cage no lanza otro compositor" "0" \
    "$(grep -c 'CAGE-FALSO' <<<"${salida_dentro}")"
  comprobar "con una sesion grafica puesta, se usa sin tocar nada" "1" \
    "$(grep -c '^GUI=1' <<<"${salida_sesion}")"
  comprobar "con una sesion grafica puesta, no lanza nada" "0" \
    "$(grep -c 'CAGE-FALSO' <<<"${salida_sesion}")"
  comprobar "sin grafica en /dev/dri, avisa y sigue en modo de texto" "1" \
    "$(grep -c 'No hay dispositivo de grafica' <<<"${salida_sin_graficos}")"
  comprobar "sin grafica en /dev/dri, no levanta ninguna pantalla" "1" \
    "$(grep -c '^GUI=0' <<<"${salida_sin_graficos}")"
  comprobar "sin grafica, tampoco lanza cage" "0" \
    "$(grep -c 'CAGE-FALSO' <<<"${salida_sin_graficos}")"
  comprobar "sin cage en el sistema, avisa y sigue en modo de texto" "1" \
    "$(grep -c 'No esta .cage' <<<"${salida_sin_cage}")"
  comprobar "sin cage en el sistema, no queda en TITAN_GUI" "1" \
    "$(grep -c '^GUI=0' <<<"${salida_sin_cage}")"
  comprobar "con grafica y con cage, levanta la pantalla y se relanza" \
    "1" "$(grep -c 'CAGE-FALSO' <<<"${salida_con_cage}")"
  comprobar "al relanzarse, los argumentos llegan enteros y en orden" "1" \
    "$(grep -c 'CAGE-FALSO args=\[.* --grafico --inventada\]' \
        "${lab_gui}/cage-llamadas" || true)"

  # --- el asiento, que es la mitad del fallo 44 ------------------------------
  # Sin asiento, cage se moria en el live con 'No backend was able to open a
  # seat' ANTES de dibujar nada, y como lo lanzaba con 'exec', el instalador se
  # iba con el. Estos cinco casos son los que lo cuentan.
  comprobar "sin seatd avisa y sigue en modo de texto" "1" \
    "$(grep -c 'No esta .seatd' <<<"${salida_sin_seatd}" || true)"
  comprobar "sin seatd no se queda pensando que hay ventana" "1" \
    "$(grep -c '^GUI=0' <<<"${salida_sin_seatd}" || true)"
  comprobar "sin seatd no lanza cage" "0" \
    "$(grep -c 'CAGE-FALSO' <<<"${salida_sin_seatd}" || true)"
  comprobar "seatd que no abre el socket avisa y sigue en texto" "1" \
    "$(grep -c 'no ha abierto' <<<"${salida_seatd_malo}" || true)"
  comprobar "seatd que no abre el socket tampoco lanza cage" "0" \
    "$(grep -c 'CAGE-FALSO' <<<"${salida_seatd_malo}" || true)"
  comprobar "con asiento abierto, el asiento se abre antes de lanzar cage" \
    "1" "$(awk '/^SEATD-FALSO /{s=NR} /^CAGE-FALSO/{c=NR}
            END{print (s>0 && c>0 && s<c) ? 1 : 0}' \
        "${lab_gui}/cage-llamadas" 2>/dev/null || true)"
  comprobar "el hijo de dentro de cage sabe que va dentro" "1" \
    "$(grep -c 'CAGE-FALSO .*dentro=1 gui=1' \
        "${lab_gui}/cage-llamadas" || true)"

  # --- y si cage no arranca, tampoco se pierde el instalador -----------------
  # Este es el otro medio del fallo 44, y el que se ve el usuario: con 'exec',
  # cage se quedaba con la shell, de modo que al morir el instalador entero
  # desaparecia sin decir nada. Ahora cage es un hijo, y aqui se comprueba que
  # al fallar se vuelve a texto, se dice con que codigo salio, y la shell de
  # este instalador se queda SIN la pantalla puesta (si se quedara con
  # TITAN_GUI=1, el instalador de texto de abajo creeria que hay ventana y no
  # tendria donde preguntar).
  comprobar "si cage falla, avisa y sigue en modo de texto" "1" \
    "$(grep -c 'no ha podido levantarse' <<<"${salida_con_cage_roto}" || true)"
  comprobar "si cage falla, el aviso dice con que codigo salio" "1" \
    "$(grep -c 'ha salido con' <<<"${salida_con_cage_roto}" || true)"
  comprobar "si cage falla, no se queda creyendo que hay ventana" "1" \
    "$(grep -c '^GUI=0' <<<"${salida_con_cage_roto}" || true)"
  comprobar "si cage falla, no se queda marcado como dentro de cage" "1" \
    "$(grep -c 'DENTRO=0' <<<"${salida_con_cage_roto}" || true)"
  # Y que cage NO se lleve la shell, que es el aviso de esta seccion. Sin esto,
  # volver a poner un 'exec cage' dejaria el resto de comprobaciones en verde y
  # el instalador desapareceria otra vez.
  comprobar "el instalador no se queda con la shell al lanzar cage" "0" \
    "$(grep -cE '^[[:space:]]*exec[[:space:]]+cage' "${RAIZ}/install.sh" \
        2>/dev/null || true)"
  # El socket tiene que ser el que mira libseat, no uno inventado aqui: si
  # 'asegura_asiento' mirara otro, abriria un asiento que cage no ve.
  # --- lo que sale con 3 de dentro no es un fallo de cage (fallo 46) --------
  # Un 3 aqui es el codigo de 'cancelado' de 'lib-comun.sh', no un fallo del
  # compositor. Las tres cosas que NO pueden pasar: que se diga que cage ha
  # fallado, que se vuelva al modo de texto (que instalaria otra vez sin que
  # nadie lo pidiera), y que se salga con algo que no sea 3.
  comprobar "un cancelado de dentro no se cuenta como fallo de cage" "0" \
    "$(grep -c 'ha salido con' <<<"${salida_con_cage_cancelado}" || true)"
  comprobar "un cancelado de dentro no vuelve al modo de texto" "0" \
    "$(grep -c 'Se sigue en modo de texto' \
        <<<"${salida_con_cage_cancelado}" || true)"
  comprobar "un cancelado de dentro sale con el codigo de cancelado" "1" \
    "$(grep -c '^RC=3$' <<<"${salida_con_cage_cancelado}" || true)"

  comprobar "el asiento se busca donde lo busca libseat" "1" \
    "$(grep -c 'SEATD_SOCK:-/run/seatd.sock' "${RAIZ}/install.sh" \
        2>/dev/null || true)"
  unset TITAN_CAGE
fi

# --- 6p.8. lo que se va en la ISO, que no es lo que hay en el arbol ----------
# El frontal se importa para probarlo, y Python deja el '.pyc' al lado del
# '.py'. Como el '.py' que se importa es el del ARBOL DE LA ISO, el
# '__pycache__' se cuela en el arbol, y archiso se lo lleva tal cual al
# squashfs: la ISO lleva un '__pycache__' de root dentro de '/root/instalador'
# y el recorrido se cuela un fichero de mas. Con 'sys.dont_write_bytecode' el
# comprobador no lo crea,
# pero el '__pycache__' que ya habia se queda hasta que se borre a mano, asi que
# aqui se mira que no haya ninguno en TODO el arbol de la ISO.
pycs="$(find "${DISTRO}/iso/titan/airootfs" \( -name '__pycache__' -o \
  -name '*.pyc' \) | head -5 | tr '\n' ' ')"
comprobar "el arbol de la ISO no lleva '__pycache__' ni '.pyc'" "0" \
  "$(printf '%s' "${pycs}" | wc -w | tr -d ' ')"
# Y que en la carpeta del instalador no haya nada mas que las nueve librerias y
# el frontal. Con el '__pycache__' dentro, el recuento de ficheros daba 11 y el
# informe de la pasada de UEFI salia en rojo sin que faltara nada de verdad.
nueve_lib='^(lib-apps|lib-comun|lib-escritorios|menus|paso-base'
nueve_lib="${nueve_lib}|paso-cerrar|paso-chroot|paso-disco|paso-red)\.sh\$"
de_sobra="$(cd "${RAIZ}/instalador" && ls -A |
  grep -cvE "${nueve_lib}|^ventana-gui\.py\$")"
comprobar "en instalador/ no hay nada mas que 9 librerias y el frontal" "0" \
  "${de_sobra}"
comprobar "el frontal es el unico '.py' del instalador" "1" \
  "$(find "${RAIZ}/instalador" -maxdepth 1 -name '*.py' | wc -l | tr -d ' ')"

# El laboratorio entero se va, como los de las otras secciones. cage deja cosas
# en XDG_RUNTIME_DIR (que esta dentro del laboratorio) y los ficheros del espia
# son unos cuantos, pero lo que mas pesa es el arbol de '/root' que se copia
# para probar el frontal sin permiso de ejecucion.
rm -rf "${lab_gui}"

# --- resultado ----------------------------------------------------------------

echo
if (( fallos )); then
  echo "RESULTADO: ${fallos} fallos"
  exit 1
fi
echo "RESULTADO: todo correcto"
