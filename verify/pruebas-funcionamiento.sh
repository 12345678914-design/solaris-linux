#!/usr/bin/env bash
# ==============================================================================
# Pruebas de funcionamiento (sin pantalla) de Fotos, del instalador y de reglas
# del escritorio. build-iso.sh las lanza DESPUÉS de compilar las aplicaciones,
# con los binarios recién compilados.
#   - Fotos: lectura EXIF (titan-fotos --exif).
#   - Instalador: particionado manual sobre un disco simulado con Windows
#     (verify/datos/disco-falso); planear no debe escribir en el disco.
#   - Reglas y paquetes que no deben perderse.
# ==============================================================================

set -uo pipefail
cd "$(dirname "$0")/.."

ROJO='\033[0;31m'
VERDE='\033[0;32m'
AZUL='\033[0;34m'
SIN_COLOR='\033[0m'
fallos=0
exitos=0
reportar_ok() { echo -e "[ ${VERDE}OK${SIN_COLOR} ] $1: $2"; exitos=$((exitos + 1)); }
reportar_fallo() { echo -e "[ ${ROJO}FALLO${SIN_COLOR} ] $1: $2"; fallos=$((fallos + 1)); }

echo -e "${AZUL}=== PRUEBAS DE FUNCIONAMIENTO ===${SIN_COLOR}"
DATOS="verify/datos"
TMPV=$(mktemp -d)
trap 'rm -rf "$TMPV"' EXIT

# Binarios: los que acaba de compilar build-iso.sh (apps/X/build/X); si no,
# apps/X/X. Se pueden forzar con FOTOS_BIN=... e INSTALADOR_BIN=...
binario() {
    local app="$1"
    if [[ -x "apps/${app}/build/${app}" ]]; then echo "apps/${app}/build/${app}"; else echo "apps/${app}/${app}"; fi
}
fotos_bin="${FOTOS_BIN:-$(binario titan-fotos)}"
instalador_bin="${INSTALADOR_BIN:-$(binario titan-installer)}"
# Sin pantalla y con tiempo límite: un binario viejo no debe quedarse abierto
export QT_QPA_PLATFORM=offscreen

# 14.1 Fotos lee el EXIF (fecha de captura, cámara, exposición, GPS)
if command -v magick >/dev/null 2>&1; then
    magick -size 64x48 gradient:blue-orange "$TMPV/prueba.jpg"
    python3 "$DATOS/poner-exif.py" "$TMPV/prueba.jpg"
    exif=$(timeout 20 "$fotos_bin" --exif "$TMPV/prueba.jpg" 2>&1 || true)
    if grep -q "^camara=Canon EOS R6$" <<<"$exif" && grep -q "^fecha=2024-07-14T17:42:05$" <<<"$exif" \
        && grep -q "^exposicion=1/250 s$" <<<"$exif" && grep -q "^lat=-13.15" <<<"$exif"; then
        reportar_ok "fotos/exif" "Cámara, fecha de captura, exposición y GPS leídos"
    else
        reportar_fallo "fotos/exif" "Lectura EXIF incorrecta (¿binario sin recompilar?): ${exif}"
    fi
else
    echo "  (sin ImageMagick: se omite la prueba EXIF de Fotos)"
fi

# 14.2 Instalador: particionado manual sobre un disco simulado con Windows.
#      Debe ver las particiones y el hueco, reutilizar la EFI sin formatear,
#      exigir «Aplicar cambios» y no escribir nada mientras solo se planea.
registro="$TMPV/parted.log"
: > "$registro"
manual=$(PATH="$PWD/$DATOS/disco-falso:$PATH" PARTED_REGISTRO="$registro" TITAN_COMPROBAR_MANUAL=1 \
         timeout 30 "$instalador_bin" --comprobar 2>&1 || true)
if grep -q "^fila=parte|/dev/vda1|Partición EFI" <<<"$manual" && grep -q "^fila=parte|/dev/vda3|Windows|" <<<"$manual" \
    && grep -q "^fila=libre|" <<<"$manual" && grep -q "^fila=parte|/dev/vda4|Recuperación de Windows" <<<"$manual"; then
    reportar_ok "instalador/tabla" "Lee particiones (EFI, Windows, recuperación) y espacio libre"
else
    reportar_fallo "instalador/tabla" "Tabla mal leída: ${manual}"
fi
if grep -q "^resumen=/boot/efi → /dev/vda1 (105 MB): se usa tal cual" <<<"$manual" \
    && grep -q "^pendiente=Crear una partición de .* para /$" <<<"$manual" \
    && grep -q "^plan-con-pendientes=Hay cambios en la tabla sin aplicar" <<<"$manual"; then
    reportar_ok "instalador/plan" "EFI de Windows reutilizada, «/» en el hueco y pide aplicar antes de seguir"
else
    reportar_fallo "instalador/plan" "Plan manual incorrecto: ${manual}"
fi
if [[ ! -s "$registro" ]]; then
    reportar_ok "instalador/sin-escrituras" "Planear no escribe en el disco"
else
    reportar_fallo "instalador/sin-escrituras" "Se escribió en el disco sin confirmar: $(cat "$registro")"
fi

# 14.3 Reglas y piezas que no deben perderse
comprobar_texto() {
    local nombre="$1" archivo="$2" patron="$3" detalle="$4"
    if grep -qE "$patron" "$archivo" 2>/dev/null; then
        reportar_ok "$nombre" "$detalle"
    else
        reportar_fallo "$nombre" "No se encuentra «${patron}» en ${archivo}"
    fi
}
comprobar_texto "finder/mover-en-casa" apps/titan-finder/src/Operaciones.cpp "mover && \(!destinoEnCasa" "Mover solo dentro de la carpeta personal (lo demás se copia)"
comprobar_texto "finder/papelera" apps/titan-finder/qml/FileList.qml "Vaciar Papelera" "Papelera con vaciar y eliminar para siempre"
comprobar_texto "escritorio/quitar" apps/titan-shell/qml/DesktopIcons.qml "Quitar del escritorio" "Menú del icono: «Quitar del escritorio»"
comprobar_texto "shell/tema-sistema" apps/titan-shell/src/main.cpp "setSincronizaSistema\(true\)" "Claro/oscuro sincronizado con GTK/portal (Firefox, OnlyOffice)"
comprobar_texto "ajustes/actualizaciones" apps/titan-settings/src/SettingsBackend.cpp "CHECKUPDATES_DB" "Buscar actualizaciones con checkupdates real"
for paquete in taglib pacman-contrib fakeroot; do
    comprobar_texto "paquetes/${paquete}" iso/titan/packages.x86_64 "^${paquete}$" "Incluido en la ISO"
done

echo -e "\n${AZUL}=== RESUMEN ===${SIN_COLOR}"
echo "Pruebas correctas: ${exitos}"
echo "Fallos: ${fallos}"
[[ ${fallos} -eq 0 ]]
