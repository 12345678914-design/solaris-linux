#!/usr/bin/env bash
# ==============================================================================
# Script de comprobación integral del escritorio Titan Linux y sus componentes
# Valida la compilación, carga de QML offscreen, sintaxis y binarios desplegados.
# ==============================================================================

set -euo pipefail

ROJO='\033[0;31m'
VERDE='\033[0;32m'
AZUL='\033[0;34m'
SIN_COLOR='\033[0m'

fallos=0
exitos=0

function reportar_ok() {
    local componente="$1"
    local detalle="$2"
    echo -e "[ ${VERDE}OK${SIN_COLOR} ] ${componente}: ${detalle}"
    exitos=$((exitos + 1))
}

function reportar_fallo() {
    local componente="$1"
    local error="$2"
    echo -e "[ ${ROJO}FALLO${SIN_COLOR} ] ${componente}: ${error}"
    fallos=$((fallos + 1))
}

echo -e "${AZUL}=== COMPROBACIÓN INTEGRAL DE COMPONENTES DEL ESCRITORIO ===${SIN_COLOR}"

# 1. Comprobación de titan-shell (TopBar, Dock, Launcher, DesktopIcons, ControlCenter, WorkspacesView)
if out=$(apps/titan-shell/titan-shell --comprobar 2>&1); then
    reportar_ok "titan-shell" "QML, capas LayerShell y componentes (Dock, TopBar, CC, Workspaces) cargados con éxito"
else
    reportar_fallo "titan-shell" "Fallo al inicializar: ${out}"
fi

# 2. Comprobación de titan-finder (FileList, Sidebar, Diálogos de propiedades, etc.)
if out=$(apps/titan-finder/titan-finder --comprobar 2>&1); then
    reportar_ok "titan-finder" "Árbol QML de Finder y explorador de archivos cargados sin errores"
else
    reportar_fallo "titan-finder" "Fallo al inicializar: ${out}"
fi

# 3. Comprobación de titan-fotos (Visor, cuadrícula, zoom)
if out=$(apps/titan-fotos/titan-fotos --comprobar 2>&1); then
    reportar_ok "titan-fotos" "Visor de imágenes QML verificado"
else
    reportar_fallo "titan-fotos" "Fallo al inicializar: ${out}"
fi

# 4. Comprobación de titan-musica (Reproductor, lista)
if out=$(apps/titan-musica/titan-musica --comprobar 2>&1); then
    reportar_ok "titan-musica" "Reproductor de audio verificado"
else
    reportar_fallo "titan-musica" "Fallo al inicializar: ${out}"
fi

# 5. Comprobación de titan-settings (Ajustes de sistema)
if out=$(apps/titan-settings/titan-settings --comprobar 2>&1); then
    reportar_ok "titan-settings" "Ventana de Ajustes del Sistema QML verificada"
else
    reportar_fallo "titan-settings" "Fallo al inicializar: ${out}"
fi

# 6. Comprobación de titan-terminal
if out=$(apps/titan-terminal/titan-terminal --comprobar 2>&1); then
    reportar_ok "titan-terminal" "Terminal validada"
else
    reportar_fallo "titan-terminal" "Fallo al inicializar: ${out}"
fi

# 7. Comprobación de titan-acerca
cmd_acerca="apps/titan-acerca/titan-acerca"
[ -f "apps/titan-acerca/build/titan-acerca" ] && [ ! -f "$cmd_acerca" -o "apps/titan-acerca/build/titan-acerca" -nt "$cmd_acerca" ] && cmd_acerca="apps/titan-acerca/build/titan-acerca"
if out=$("$cmd_acerca" --comprobar 2>&1); then
    reportar_ok "titan-acerca" "Acerca de este Mac/Sistema verificado"
else
    reportar_fallo "titan-acerca" "Fallo al inicializar: ${out}"
fi

# 8. Comprobación de titan-desktop
cmd_desktop="apps/titan-desktop/titan-desktop"
[ -f "apps/titan-desktop/build/titan-desktop" ] && [ ! -f "$cmd_desktop" -o "apps/titan-desktop/build/titan-desktop" -nt "$cmd_desktop" ] && cmd_desktop="apps/titan-desktop/build/titan-desktop"
if out=$("$cmd_desktop" --comprobar 2>&1); then
    reportar_ok "titan-desktop" "Configuración y backend de escritorio validados"
else
    reportar_fallo "titan-desktop" "Fallo al inicializar: ${out}"
fi

# 9. Comprobación de titan-calc
if out=$(apps/titan-calc/titan-calc --comprobar 2>&1); then
    reportar_ok "titan-calc" "Calculadora QML validada offscreen"
else
    reportar_fallo "titan-calc" "Fallo al inicializar: ${out}"
fi

# 10. Comprobación de titan-calendar
if out=$(apps/titan-calendar/titan-calendar --comprobar 2>&1); then
    reportar_ok "titan-calendar" "Calendario QML validado offscreen"
else
    reportar_fallo "titan-calendar" "Fallo al inicializar: ${out}"
fi

# 11. Comprobación de titan-clock
if out=$(apps/titan-clock/titan-clock --comprobar 2>&1); then
    reportar_ok "titan-clock" "Reloj y cronómetro QML validados offscreen"
else
    reportar_fallo "titan-clock" "Fallo al inicializar: ${out}"
fi

# 12. Comprobación de titan-video
if out=$(apps/titan-video/titan-video --comprobar 2>&1); then
    reportar_ok "titan-video" "Reproductor multimedia de video QML validado offscreen"
else
    reportar_fallo "titan-video" "Fallo al inicializar: ${out}"
fi

# 13. Comprobación de titan-installer (Instalador Nativo Inti OS)
if out=$(apps/titan-installer/titan-installer --comprobar 2>&1); then
    reportar_ok "titan-installer" "Instalador nativo gráfico QML validado offscreen"
else
    reportar_fallo "titan-installer" "Fallo al inicializar: ${out}"
fi

# 14. Pruebas de funcionamiento (sin pantalla)
echo -e "\n${AZUL}=== PRUEBAS DE FUNCIONAMIENTO ===${SIN_COLOR}"
DATOS="verify/datos"
TMPV=$(mktemp -d)
trap 'rm -rf "$TMPV"' EXIT

# Se puede apuntar a binarios compilados en otro sitio: FOTOS_BIN=..., INSTALADOR_BIN=...
fotos_bin="${FOTOS_BIN:-apps/titan-fotos/titan-fotos}"
instalador_bin="${INSTALADOR_BIN:-apps/titan-installer/titan-installer}"

# 14.1 Fotos lee el EXIF (fecha de captura, cámara, exposición, GPS)
if command -v magick >/dev/null 2>&1; then
    magick -size 64x48 gradient:blue-orange "$TMPV/prueba.jpg"
    python3 "$DATOS/poner-exif.py" "$TMPV/prueba.jpg"
    exif=$("$fotos_bin" --exif "$TMPV/prueba.jpg" 2>&1 || true)
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
         "$instalador_bin" --comprobar 2>&1 || true)
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

# 13. Comprobación de binarios sincronizados en airootfs
echo -e "\n${AZUL}=== COMPROBACIÓN DE BINARIOS EN AIROOTFS ===${SIN_COLOR}"
binarios=(
    "titan-shell"
    "titan-finder"
    "titan-fotos"
    "titan-musica"
    "titan-settings"
    "titan-terminal"
    "titan-acerca"
    "titan-desktop"
    "titan-panel"
    "titan-calc"
    "titan-calendar"
    "titan-clock"
    "titan-video"
    "titan-installer"
)

for b in "${binarios[@]}"; do
    ruta="iso/titan/airootfs/usr/local/bin/${b}"
    if [[ -x "${ruta}" ]]; then
        reportar_ok "airootfs/${b}" "Binario presente y ejecutable"
    else
        reportar_fallo "airootfs/${b}" "El binario no existe o no tiene permisos de ejecución"
    fi
done

# 10. Comprobación de enlaces de compatibilidad en customize_airootfs.sh
echo -e "\n${AZUL}=== COMPROBACIÓN DE CUSTOMIZE_AIROOTFS ===${SIN_COLOR}"
if bash verify/comprobar-customize.sh >/dev/null 2>&1; then
    reportar_ok "customize_airootfs.sh" "Sintaxis y reglas de inicio validadas"
else
    reportar_fallo "customize_airootfs.sh" "Fallo en verificación de customize"
fi

echo -e "\n${AZUL}=== RESUMEN ===${SIN_COLOR}"
echo "Total de pruebas exitosas: ${exitos}"
echo "Total de fallos: ${fallos}"

if [[ ${fallos} -gt 0 ]]; then
    exit 1
fi

exit 0
