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
if out=$(apps/titan-acerca/titan-acerca --comprobar 2>&1); then
    reportar_ok "titan-acerca" "Acerca de este Mac/Sistema verificado"
else
    reportar_fallo "titan-acerca" "Fallo al inicializar: ${out}"
fi

# 8. Comprobación de titan-desktop
if out=$(apps/titan-desktop/titan-desktop --comprobar 2>&1); then
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

# 13. Comprobación de titan-installer (Instalador Nativo Solaris Linux)
if out=$(apps/titan-installer/titan-installer --comprobar 2>&1); then
    reportar_ok "titan-installer" "Instalador nativo gráfico QML validado offscreen"
else
    reportar_fallo "titan-installer" "Fallo al inicializar: ${out}"
fi

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
