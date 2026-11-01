#!/usr/bin/env bash
#
# run-qemu.sh - arranca la ISO de Titan Linux en QEMU.
#
# Uso:
#   ./scripts/run-qemu.sh                 # UEFI (OVMF), ventana grafica
#   ./scripts/run-qemu.sh --bios          # BIOS con syslinux
#   ./scripts/run-qemu.sh --headless      # sin ventana, consola por serie
#   ./scripts/run-qemu.sh --disk 20G      # anade un disco de 20G para instalar
#   ./scripts/run-qemu.sh --resolution 1366x768  # fuerza la pantalla
#   ./scripts/run-qemu.sh --serial-log r.log   # guarda la consola serie en r.log
#                                          # (funciona con y sin ventana)
#
# La pantalla se detecta en el host (niri, wlr-randr, xrandr o DRM). No se
# fija 1920x1080: en un monitor de 1366x768 se usa 1366x768 y en uno de
# 1920x1080 se usa 1920x1080. TITAN_QEMU_RESOLUCION hace lo mismo que
# --resolution.
#
# Para comprobar la ISO sin mirar, usa scripts/verify-qemu.sh, que ademas
# ejecuta comandos dentro del sistema y verifica el resultado.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISTRO="$(cd "${HERE}/.." && pwd)"
OUT_DIR="${TITAN_OUT:-${DISTRO}/out}"
RUN_DIR="${TITAN_RUN:-${DISTRO}/run}"

firmware=uefi
headless=0
memory=8192
cpus=2
disk=""
serial_log=""
resolution=""
screenshot=""
software=0

red()  { printf '\033[1;31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[1;32m%s\033[0m\n' "$*"; }
yel()  { printf '\033[1;33m%s\033[0m\n' "$*"; }
info() { printf '\033[0;36m==>\033[0m %s\n' "$*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bios)       firmware=bios; shift ;;
    --uefi)       firmware=uefi; shift ;;
    --headless)   headless=1; shift ;;
    --software)   software=1; shift ;;
    --screenshot)
      if [[ $# -ge 2 && ! "$2" =~ ^-- ]]; then
        screenshot="$2"
        shift 2
      else
        screenshot="${OUT_DIR}/capturas/pantalla-qemu.png"
        shift
      fi
      ;;
    --memory)     memory="$2"; shift 2 ;;
    --cpus)       cpus="$2"; shift 2 ;;
    --disk)       disk="$2"; shift 2 ;;
    --resolution) resolution="$2"; shift 2 ;;
    --serial-log) serial_log="$2"; shift 2 ;;
    -h|--help)    sed -n '3,20p' "$0"; exit 0 ;;
    *) red "Opcion desconocida: $1"; exit 1 ;;
  esac
done

command -v qemu-system-x86_64 >/dev/null || { red "Falta qemu-system-x86_64"; exit 1; }

shopt -s nullglob
isos=("${OUT_DIR}"/titan-linux-*.iso)
shopt -u nullglob
(( ${#isos[@]} )) || { red "No hay ninguna ISO en ${OUT_DIR}. Antes: scripts/build-iso.sh"; exit 1; }
iso="$(ls -t "${isos[@]}" | head -n1)"
info "ISO: ${iso}"

if [[ -n "${resolution}" ]]; then
  TITAN_QEMU_RESOLUCION="${resolution}" \
    "${HERE}/detectar-resolucion.sh" >/dev/null || exit 1
  deteccion="forzada"
else
  resolution="$("${HERE}/detectar-resolucion.sh")"
  deteccion="detectada"
fi
ancho="${resolution%%x*}"
alto="${resolution##*x}"
if [[ ! "${ancho}" =~ ^[0-9]+$ || ! "${alto}" =~ ^[0-9]+$ ]]; then
  red "Resolucion no valida: ${resolution}"
  exit 1
fi
info "pantalla: ${ancho}x${alto} (${deteccion})"

mkdir -p "${RUN_DIR}"

# Delegar a modo captura si se solicitó
if [[ -n "${screenshot}" ]]; then
  info "Modo captura de pantalla: guardando prueba en ${screenshot}"
  mkdir -p "$(dirname "${screenshot}")"
  exec "${DISTRO}/verify/comprobar-escritorio-qemu.py" \
    --iso "${iso}" \
    --out "$(dirname "${screenshot}")" \
    --resolution "${ancho}x${alto}"
fi

args=(
  -m "${memory}M"
  -smp "${cpus}"
  -device "virtio-vga,xres=${ancho},yres=${alto}"
  -cdrom "${iso}"
)

# Aceleración KVM con fallback seguro a TCG
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
  args+=(-enable-kvm -cpu host)
else
  yel "AVISO: KVM no disponible o sin permisos en /dev/kvm; usando aceleración TCG (-cpu max)."
  args+=(-machine "q35,accel=tcg" -cpu max)
fi

if [[ "$firmware" == uefi ]]; then
  code=""
  for c in "/usr/share/edk2/x64/OVMF_CODE.4m.fd" \
           "/usr/share/edk2/x64/OVMF_CODE.fd" \
           "/usr/share/OVMF/OVMF_CODE.fd" \
           "/usr/share/ovmf/x64/OVMF_CODE.fd"; do
    if [[ -r "$c" ]]; then code="$c"; break; fi
  done

  vars_template=""
  for v in "/usr/share/edk2/x64/OVMF_VARS.4m.fd" \
           "/usr/share/edk2/x64/OVMF_VARS.fd" \
           "/usr/share/OVMF/OVMF_VARS.fd" \
           "/usr/share/ovmf/x64/OVMF_VARS.fd"; do
    if [[ -r "$v" ]]; then vars_template="$v"; break; fi
  done

  if [[ -z "$code" || -z "$vars_template" ]]; then
    yel "AVISO: No se encontró firmware OVMF para UEFI. Cambiando a BIOS automáticamente."
    firmware=bios
  else
    vars="${RUN_DIR}/OVMF_VARS.fd"
    [[ -f "$vars" ]] || cp -- "$vars_template" "$vars"
    args+=(
      -drive "if=pflash,format=raw,unit=0,readonly=on,file=${code}"
      -drive "if=pflash,format=raw,unit=1,file=${vars}"
    )
    info "arranque: UEFI (OVMF)"
  fi
fi

if [[ "$firmware" == bios ]]; then
  info "arranque: BIOS (syslinux)"
fi

if [[ -n "$disk" ]]; then
  disk_img="${RUN_DIR}/titan-${disk}.qcow2"
  [[ -f "$disk_img" ]] || qemu-img create -q -f qcow2 "$disk_img" "$disk"
  args+=(-drive "if=virtio,format=qcow2,file=${disk_img}")
  info "disco: ${disk_img} (${disk})"
fi

# Detección de entorno gráfico para prevenir fallos si se lanza sin display
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" && $headless -eq 0 ]]; then
  yel "AVISO: No se detectó display gráfico activo (DISPLAY/WAYLAND_DISPLAY vacío). Cambiando a --headless."
  headless=1
fi

if [[ "$software" == "1" || "${TITAN_QEMU_SOFTWARE:-0}" == "1" ]]; then
  default_display="gtk,zoom-to-fit=on,show-menubar=off"
else
  default_display="gtk,gl=on,zoom-to-fit=on,show-menubar=off"
fi

if (( headless )); then
  if [[ -n "$serial_log" ]]; then
    args+=(-display none -serial "file:${serial_log}")
  else
    args+=(-nographic)
  fi
  info "sin ventana; la consola esta en serie (115200). Ctrl-a x para salir."
elif [[ -n "$serial_log" ]]; then
  # Con ventana y transcripcion a la vez: la consola serie va al fichero y el
  # monitor se queda en el terminal, que es lo comodo para hacer screendump.
  args+=(-display "${TITAN_QEMU_DISPLAY:-${default_display}}"
         -serial "file:${serial_log}" -monitor stdio)
  info "ventana grafica; consola serie en ${serial_log}."
  info "monitor de QEMU en el terminal: Ctrl-a x para salir."
else
  args+=(-display "${TITAN_QEMU_DISPLAY:-${default_display}}"
         -serial mon:stdio)
  info "ventana grafica; Ctrl-a x para salir de la consola de QEMU."
fi

grn "arrancando Titan Linux en QEMU"
exec qemu-system-x86_64 "${args[@]}"
