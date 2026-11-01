#!/usr/bin/env bash
#
# integrar-onlyoffice-appimage.sh
# Integra el AppImage oficial de ONLYOFFICE en TITAN Linux (local y en la ISO).
#
set -euo pipefail

DEST_ISO="iso/titan/airootfs/opt/onlyoffice/DesktopEditors.AppImage"
DEST_LOCAL_APPIMAGE="${HOME}/.local/bin/DesktopEditors.AppImage"
DEST_LOCAL_WRAPPER="${HOME}/.local/bin/onlyoffice-desktopeditors"

mkdir -p "iso/titan/airootfs/opt/onlyoffice"
mkdir -p "${HOME}/.local/bin"

ORIGEN="${1:-}"

if [[ -z "${ORIGEN}" ]]; then
    # Buscar en ubicaciones comunes
    for c in \
        "${HOME}/Descargas/DesktopEditors-x86_64.AppImage" \
        "${HOME}/Downloads/DesktopEditors-x86_64.AppImage" \
        "${HOME}/Descargas/DesktopEditors.AppImage" \
        "${HOME}/Downloads/DesktopEditors.AppImage" \
        ./DesktopEditors-x86_64.AppImage \
        ./DesktopEditors.AppImage; do
        if [[ -f "${c}" ]]; then
            ORIGEN="${c}"
            break
        fi
    done
fi

if [[ -z "${ORIGEN}" || ! -f "${ORIGEN}" ]]; then
    echo "=========================================================="
    echo "  Integrador de ONLYOFFICE AppImage para TITAN Linux"
    echo "=========================================================="
    echo "No se encontró ningún archivo AppImage automáticamente."
    echo ""
    echo "Descárgalo desde la página oficial:"
    echo "  https://github.com/ONLYOFFICE/DesktopEditors/releases/latest/download/DesktopEditors-x86_64.AppImage"
    echo ""
    echo "Y luego ejecuta este script pasándole la ruta:"
    echo "  ./scripts/integrar-onlyoffice-appimage.sh ~/Descargas/DesktopEditors-x86_64.AppImage"
    echo "=========================================================="
    exit 1
fi

echo "-> Integrando ONLYOFFICE desde: ${ORIGEN}"

# Copiar a la estructura de la ISO
cp -f "${ORIGEN}" "${DEST_ISO}"
chmod 755 "${DEST_ISO}"
echo "  [OK] Copiado a la imagen ISO: ${DEST_ISO}"

# Copiar al entorno local del usuario para pruebas directas
cp -f "${ORIGEN}" "${DEST_LOCAL_APPIMAGE}"
chmod 755 "${DEST_LOCAL_APPIMAGE}"
cp -f "iso/titan/airootfs/usr/local/bin/onlyoffice-desktopeditors" "${DEST_LOCAL_WRAPPER}"
chmod 755 "${DEST_LOCAL_WRAPPER}"
echo "  [OK] Copiado a tu sistema local: ${DEST_LOCAL_WRAPPER}"

echo ""
echo "-> ONLYOFFICE listo:"
echo "   - Para probar localmente: ejecuta 'onlyoffice-desktopeditors' o abre el icono del Escritorio."
echo "   - Para generar la ISO con la app incluida: ejecuta 'make iso'."
