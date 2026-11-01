#!/usr/bin/env bash
#
# verify-qemu.sh - prueba automatica de la ISO de Titan Linux en QEMU.
#
# Arranca la ISO sin ventana, espera a la shell, ejecuta el catalogo de
# comandos basicos de Linux, fastfetch y el CLI titan dentro del sistema, y
# comprueba que la salida de cada uno es la correcta. Ademas guarda una captura
# de la consola y un informe en JSON.
#
# Uso:
#   ./scripts/verify-qemu.sh                 # UEFI + OVMF
#   ./scripts/verify-qemu.sh --bios          # BIOS + syslinux
#   ./scripts/verify-qemu.sh --timeout 1200  # maquina lenta
#
# Codigo de salida: 0 si todo pasa, 1 si algun comando falla.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISTRO="$(cd "${HERE}/.." && pwd)"
OUT_DIR="${TITAN_OUT:-${DISTRO}/out}"

shopt -s nullglob
isos=("${OUT_DIR}"/titan-linux-*.iso)
shopt -u nullglob
if (( ! ${#isos[@]} )); then
  printf 'No hay ninguna ISO en %s. Antes: scripts/build-iso.sh\n' "${OUT_DIR}" >&2
  exit 1
fi
iso="$(ls -t "${isos[@]}" | head -n1)"

exec python3 "${HERE}/titan-verify.py" --iso "${iso}" "$@"
