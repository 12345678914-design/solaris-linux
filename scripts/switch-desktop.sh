#!/bin/bash
#
# switch-desktop.sh - Conmutador entre KDE Plasma y Titan-Shell (Labwc)
#
# Permite alternar fácilmente el entorno de escritorio configurado
# tanto en el sistema de desarrollo como en la imagen live de Solaris.
#

set -euo pipefail

DESTINO_LIVE="/home/isai/Proyectos/titan-linux/iso/titan/airootfs"
MARKER_FILE="${DESTINO_LIVE}/etc/titan/escritorio-titan-shell"

uso() {
    echo "Uso: $0 {kde|titan-shell|status}"
    echo ""
    echo "Opciones:"
    echo "  kde          Activa KDE Plasma 6 (macOS Look & Feel) como escritorio principal."
    echo "  titan-shell  Restaura Titan-Shell (Labwc + Qt Quick Shell a medida)."
    echo "  status       Muestra cuál escritorio está activo por defecto."
    exit 1
}

accion="${1:-status}"

case "${accion}" in
    kde)
        rm -f "${MARKER_FILE}"
        echo "✓ Escritorio cambiado a: KDE Plasma 6 (Solaris macOS Edition)"
        echo "  - Splash Screen: Logo Solaris con barra minimalista"
        echo "  - Panel superior: Menú global, reloj y bandeja del sistema"
        echo "  - Panel inferior: Dock flotante estilo macOS con salto de iconos"
        ;;
    titan-shell|labwc)
        mkdir -p "$(dirname "${MARKER_FILE}")"
        touch "${MARKER_FILE}"
        echo "✓ Escritorio cambiado a: Titan-Shell (Labwc + Qt Quick Shell)"
        echo "  - Entorno personalizado ligero a medida"
        ;;
    status)
        if [ -f "${MARKER_FILE}" ]; then
            echo "Escritorio activo: Titan-Shell (Labwc + Qt Quick Shell)"
        else
            echo "Escritorio activo: KDE Plasma 6 (Solaris macOS Edition)"
        fi
        ;;
    *)
        uso
        ;;
esac

