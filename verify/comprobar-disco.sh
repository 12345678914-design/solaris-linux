#!/bin/bash
# ---------------------------------------------------------------------------
# Titan Linux -- prueba de verdad del paso de disco, con un disco de mentira
#
# El paso de disco es el UNICO que destruye datos, y por eso casi todo lo suyo
# son Partidas, formateos y montajes: cosas que se pueden probar en un equipo
# normal sin tocar ningun disco. Este script hace exactamente eso.
#
# Crea un fichero de 20 GiB (es un fichero disperso, no ocupa ese sitio), le
# pone encima un device loop con particiones, y llama al MISMO codigo del
# instalador: particionar_auto, particiones_de, formatear, montar y genfstab.
# Despues comprueba que lo que el instalador dice que ha hecho existe de verdad.
#
# Asi se han encontrado fallos que con una maquina virtual no se ven enseguida:
# el codigo de particion se leia de la columna equivocada de 'sgdisk -p' (el
# tamano son dos palabras, asi que no era el campo quinto), y las particiones de
# un disco NVMe se buscaban como '/dev/nvme0n12'.
#
# Solo toca su propio fichero y su propio device loop. Borra las dos cosas al
# terminar, incluso si falla.
#
#   distro/verify/comprobar-disco.sh
#
# Necesita root (para el device loop) y las herramientas que usa el instalador:
# gptfdisk (sgdisk) y btrfs-progs. Si no estan, se salta la parte que no puede
# hacer en vez de fallar.
# ---------------------------------------------------------------------------
set -uo pipefail

AQUI="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DISTRO="$(dirname -- "${AQUI}")"
RAIZ="${DISTRO}/iso/titan/airootfs/root"

fallos=0
ok()    { printf '  OK    %s\n' "$1"; }
falla() { printf '  FALLO %s\n' "$1"; fallos=$((fallos + 1)); }
saltar(){ printf '  ----  %s\n' "$1"; }

echo "== 1. lo que hace falta =="
if (( EUID != 0 )); then
  echo "  ESTE SCRIPT NECESITA ROOT (device loop). Se salta."
  exit 0
fi
for t in sgdisk losetup mkfs.fat mkfs.ext4 genfstab; do
  if ! command -v "${t}" >/dev/null 2>&1; then
    echo "  falta '${t}': el live si lo lleva, este equipo no. Se salta."
    exit 0
  fi
done
ok "root y herramientas basicas"
TIENE_BTRFS=0
if command -v mkfs.btrfs >/dev/null 2>&1 && command -v btrfs >/dev/null 2>&1; then
  TIENE_BTRFS=1
  ok "btrfs-progs: se puede probar tambien el btrfs"
else
  saltar "sin btrfs-progs: solo se probara ext4 (falta el paquete btrfs-progs)"
fi

# --- el disco de mentira -----------------------------------------------------

TRAB="$(mktemp -d -t titan-disco.XXXXXX)"
IMAGEN="${TRAB}/disco.img"
LOOP=""
limpiar() {
  if [[ -n "${DESTINO}" ]]; then
    swapoff "${DESTINO}" 2>/dev/null || true
    umount -R "${DESTINO}" 2>/dev/null || true
  fi
  umount "${ESP}" 2>/dev/null || true
  [[ -n "${LOOP}" ]] && losetup -d "${LOOP}" 2>/dev/null
  rm -rf -- "${TRAB}"
}
trap limpiar EXIT

# El destino se pone en un directorio de trabajo propio, NUNCA en /mnt: si algo
# se montase en el sitio de la instalacion de verdad, este script no lo hace.
# (El '/mnt' del instalador se sobreescribe DESPUES de leer el modulo, porque
# 'montar' usa la variable global ESP_MNT tal cual esta.)
DESTINO="${TRAB}/mnt"

truncate -s 20G "${IMAGEN}"
# Con '-f' porque si no, a partir de util-linux 2.42 losetup se cree que esta
# en modo de consulta y dice que esas opciones no valen.
LOOP="$(losetup -P -f --show "${IMAGEN}")" || { echo "  no se ha podido crear el device loop"; exit 1; }
echo
echo "== 2. particionado (UEFI, zram) =="

export AUTO=1 TITAN_SILENCIO=1 LOG="${TRAB}/log"
# shellcheck source=/dev/null
source "${RAIZ}/instalador/lib-comun.sh"
# shellcheck source=/dev/null
source "${RAIZ}/instalador/lib-escritorios.sh"
# shellcheck source=/dev/null
source "${RAIZ}/instalador/paso-disco.sh"
# shellcheck source=/dev/null
source "${RAIZ}/instalador/paso-base.sh"

# El instalador monta la particion de arranque en ESP_MNT, que viene siendo
# /mnt/boot/efi. Aqui se cambia para que la prueba no monte nada en el sistema.
DESTINO="${TRAB}/mnt"
ESP_MNT="${DESTINO}/boot/efi"
ESP="${ESP_MNT}"

E=()
E[disco]="${LOOP}"
E[swap]="zram"
E[escritorio]="gnome"
E[fs]="ext4"

if ! particionar_auto "${LOOP}" zram ""; then
  falla "particionar_auto ha fallado"
else
  ok "particionar_auto ha partitionado ${LOOP}"
fi

# Lo que el instalador dice que ha hecho, comprobar que existe de verdad.
if [[ -n "${E[part_raiz]:-}" && -b "${E[part_raiz]}" ]]; then
  ok "la particion de raiz existe como bloque: ${E[part_raiz]}"
else
  falla "la particion de raiz no existe: [${E[part_raiz]:-nada}]"
fi
if [[ -n "${E[part_esp]:-}" && -b "${E[part_esp]}" ]]; then
  ok "la particion de arranque existe como bloque: ${E[part_esp]}"
else
  falla "la particion de arranque no existe: [${E[part_esp]:-nada}]"
fi
# En UEFI la de arranque tiene que ser EF00; en BIOS, EF02 de 1 MiB. Ahora mismo
# el equipo arranca en UEFI, asi que solo se comprueba el codigo de la de aqui.
codigo_esp="$(sgdisk -p "${LOOP}" | numero_de_particion EF00)"
[[ -n "${codigo_esp}" ]] && ok "la tabla GPT tiene una particion EF00 (arranque UEFI)" \
                        || falla "la tabla GPT no tiene ninguna particion EF00"
# Y la de linux tiene que estar en la ultima particion, que es lo que aprovecha
# el particionado automatico para que quepa todo.
[[ "$(numero_de_particion 8300 < <(sgdisk -p "${LOOP}"))" == "2" ]] \
  && ok "la particion de linux es la ultima" \
  || falla "la particion de linux no es la ultima"

echo
echo "== 3. lo que ve quien instala antes de borrar =="
aviso="$(particiones_de "${LOOP}")"
printf '        %s\n' "${aviso}"
if [[ "${aviso}" == *"${LOOP}p1"* && "${aviso}" == *"${LOOP}p2"* ]]; then
  ok "el aviso ensena las dos particiones con su nombre y su tamano"
else
  falla "el aviso no ensena bien las particiones: [${aviso}]"
fi

echo
echo "== 4. formato y montaje =="
if formatear ext4 "${E[part_raiz]}" "${E[part_esp]}" ""; then
  ok "formatear (ext4)"
else
  falla "formatear ha fallado"
fi
if montar ext4 "${E[part_raiz]}" "${E[part_esp]}" ""; then
  ok "montar (ext4)"
else
  falla "montar ha fallado"
fi
findmnt -n "${DESTINO}" >/dev/null 2>&1 && ok "el destino esta montado" \
                                     || falla "el destino NO esta montado"
findmnt -n "${ESP}"     >/dev/null 2>&1 && ok "la particion de arranque esta montada" \
                                     || falla "la particion de arranque NO esta montada"

# --- btrfs: los subvolumenes -------------------------------------------------
if (( TIENE_BTRFS )); then
  echo
  echo "== 5. btrfs: los subvolumenes =="
  umount -R "${DESTINO}" 2>/dev/null || true
  umount "${ESP}" 2>/dev/null || true
  if formatear btrfs "${E[part_raiz]}" "${E[part_esp]}" ""; then
    ok "formatear (btrfs)"
  else
    falla "formatear (btrfs) ha fallado"
  fi
  if montar btrfs "${E[part_raiz]}" "${E[part_esp]}" ""; then
    ok "montar (btrfs) con los tres subvolumenes"
  else
    falla "montar (btrfs) ha fallado"
  fi
  for sv in "" /home /var; do
    if findmnt -n "${DESTINO}${sv}" >/dev/null 2>&1; then
      ok "montado el subvolumen ${sv:-@}"
    else
      falla "no esta montado el subvolumen ${sv:-@}"
    fi
  done
  # Lo que se acaba de montar tiene que existir de verdad, no solo estar en la
  # tabla de montajes.
  for sv in @ @home @var; do
    if btrfs subvolume show "${DESTINO}" 2>/dev/null | grep -q .; then :; fi
  done
  btrfs subvolume list "${DESTINO}" 2>/dev/null | grep -q "path .*@home" \
    && ok "el subvolumen @home existe de verdad" || falla "no existe el subvolumen @home"
  btrfs subvolume list "${DESTINO}" 2>/dev/null | grep -q "path .*@var" \
    && ok "el subvolumen @var existe de verdad" || falla "no existe el subvolumen @var"
  echo "  aviso: con btrfs, mount -o subvol=@ falla si antes no se ha creado"
  echo "         '@' (mkfs.btrfs no lo crea). Es lo que se comprueba aqui."
fi

# --- el fstab ----------------------------------------------------------------
echo
echo "== 6. el fstab que se genera =="
salida_fstab="$(genfstab -U "${DESTINO}" 2>/dev/null)"
printf '%s\n' "${salida_fstab}" | grep -v '^#' | grep -v '^$' | sed 's/^/        /'

comprobar_fstab() { # comprobar_fstab QUE HAY QUE VER EN EL FSTAB
  if grep -qE "$1" <<<"${salida_fstab}"; then ok "$2"; else
    falla "$2"; printf '        no aparece: %s\n' "$1"
  fi
}
comprobar_fstab $'\t/[[:space:]]+\t' "sale la raiz"
comprobar_fstab '/boot/efi'       "sale la particion de arranque"
comprobar_fstab 'UUID='           "las fuentes son UUID, no /dev/sdX"

# Y lo que NO tiene que salir: los swap de la maquina donde se prueba. genfstab
# mete TODOS los swap que encuentra, sin mirar si estan bajo el destino (su
# bloque de swap esta aparte, leyendo /proc/swaps). En el live eso arrastra el
# swap del propio live al sistema instalado, donde ese dispositivo no existira.
n_swap_crudo="$(awk -F'\t' '$3 ~ /^swap/' <<<"${salida_fstab}" | wc -l)"
if (( n_swap_crudo > 0 )); then
  swap_en_fstab="$(awk -F'\t' '$3 ~ /^swap/' <<<"${salida_fstab}" | head -1)"
  printf '        genfstab ha metido %s swap del equipo: %s\n' "${n_swap_crudo}" "${swap_en_fstab}"
fi
filtrado="$(filtrar_fstab "${salida_fstab}" "")"
if awk -F'\t' '$3 ~ /^swap/' <<<"${filtrado}" | grep -q .; then
  falla "el filtro de swap del instalador no quita los swap ajenos"
else
  ok "el filtro quita los swap que no son del disco nuevo (se eligio zram)"
fi
# Y que no rompa el resto de lineas por el camino.
n_lineas_crudo="$(grep -cv '^$' <<<"${salida_fstab}")"
n_lineas_filtrado="$(grep -cv '^$' <<<"${filtrado}")"
if (( n_lineas_filtrado < n_lineas_crudo )); then
  ok "el filtro quita ${n_lineas_crudo} lineas y deja las demas"
else
  ok "el filtro no ha tenido que quitar nada (no habia swap ajenos)"
fi

# --- resultado ----------------------------------------------------------------

echo
if (( fallos )); then
  echo "RESULTADO: ${fallos} fallos"
  exit 1
fi
echo "RESULTADO: todo correcto"
