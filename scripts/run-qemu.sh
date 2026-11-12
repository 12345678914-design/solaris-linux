#!/usr/bin/env bash
#
# run-qemu.sh - arranca la ISO de Titan Linux en QEMU.
#
# Uso:
#   ./scripts/run-qemu.sh                 # UEFI (OVMF), ventana grafica y disco vacio (30G)
#   ./scripts/run-qemu.sh --installed     # arranca el sistema instalado en el disco (sin ISO live)
#   ./scripts/run-qemu.sh --no-disk       # sin disco duro virtual (solo live)
#   ./scripts/run-qemu.sh --disk 50G      # anade un disco personalizado para instalar
#   ./scripts/run-qemu.sh --usb           # conecta el USB físico insertado en el equipo
#   ./scripts/run-qemu.sh --usb /dev/sda  # conecta un dispositivo USB específico
#   ./scripts/run-qemu.sh --test-usb      # crea y conecta un pendrive virtual de prueba
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
usb_host=""
test_usb=0
serial_log=""
resolution=""
screenshot=""
software=0
no_ethernet=0
no_disk=0
boot_installed=0

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
    --installed|--boot-disk|--no-cdrom|--sin-live) boot_installed=1; shift ;;
    --no-disk|--sin-disco) no_disk=1; shift ;;
    --disk)
      if [[ $# -ge 2 && ! "$2" =~ ^-- ]]; then
        disk="$2"
        shift 2
      else
        disk="30G"
        shift
      fi
      ;;
    --usb)
      if [[ $# -ge 2 && ! "$2" =~ ^-- ]]; then
        usb_host="$2"
        shift 2
      else
        usb_host="auto"
        shift
      fi
      ;;
    --test-usb)   test_usb=1; shift ;;
    --no-ethernet|--sin-ethernet) no_ethernet=1; shift ;;
    --resolution) resolution="$2"; shift 2 ;;
    --serial-log) serial_log="$2"; shift 2 ;;
    -h|--help)    sed -n '3,20p' "$0"; exit 0 ;;
    *) red "Opcion desconocida: $1"; exit 1 ;;
  esac
done

command -v qemu-system-x86_64 >/dev/null || { red "Falta qemu-system-x86_64"; exit 1; }

if (( ! boot_installed )); then
  shopt -s nullglob
  isos=("${OUT_DIR}"/solaris-linux-*.iso)
  shopt -u nullglob
  (( ${#isos[@]} )) || { red "No hay ninguna ISO en ${OUT_DIR}. Antes: scripts/build-iso.sh"; exit 1; }
  iso="$(ls -t "${isos[@]}" | head -n1)"
  info "ISO Live: ${iso}"
fi

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
)

if (( ! boot_installed )); then
  args+=(
    -boot "menu=on,strict=on"
    -drive "file=${iso},media=cdrom,readonly=on,if=none,id=cdrom0"
    -device "ide-cd,drive=cdrom0,bootindex=1"
  )
else
  args+=(-boot "menu=off,strict=on")
  info "modo: Arrancando sistema instalado en disco (--installed, sin ISO live)"
fi

if (( no_ethernet )); then
  args+=(-nic none)
  info "red: Ethernet deshabilitado (-nic none) para pruebas de Wi-Fi"
else
  # VirtIO network adapter con romfile="" para desactivar iPXE/PXE
  args+=(
    -netdev "user,id=net0"
    -device "virtio-net-pci,netdev=net0,romfile="
  )
  info "red: VirtIO activa (PXE boot ROM desactivada)"
fi

# Soporte de audio Intel HDA con detección inteligente de backend en el host
audio_driver="none"
if [[ $headless -eq 0 ]]; then
  if [[ -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/pipewire-0" ]]; then
    audio_driver="pipewire"
  elif [[ -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/pulse/native" ]]; then
    audio_driver="pa"
  elif [[ -c /dev/snd/controlC0 || -d /dev/snd ]]; then
    audio_driver="alsa"
  else
    audio_driver="pa"
  fi
fi
info "audio QEMU: driver=${audio_driver} (Intel HDA duplex)"
args+=(
  -audiodev "${audio_driver},id=snd0"
  -device "intel-hda"
  -device "hda-duplex,audiodev=snd0"
)

# Sincronización de batería del host hacia la máquina virtual
bat_host_cap="$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1 || true)"
bat_host_stat="$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1 || true)"
ac_host_on="$(cat /sys/class/power_supply/A*/online 2>/dev/null | head -n1 || echo 0)"

has_battery_sync=0
bat_sock="${RUN_DIR}/titan-battery.sock"

if [[ -n "${bat_host_cap}" ]]; then
  has_battery_sync=1
  info "sincronización de batería del host: ${bat_host_cap}% (${bat_host_stat})"
  rm -f "${bat_sock}"
  args+=(
    -fw_cfg "name=opt/titan/battery,string=${bat_host_cap}|${bat_host_stat}|${ac_host_on}"
    -chardev "socket,id=batsock,path=${bat_sock},server=on,wait=off"
    -device "virtio-serial"
    -device "virtserialport,chardev=batsock,name=titan.battery"
  )
fi

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
    # Reiniciar siempre las variables NVRAM desde la plantilla para evitar arrastres
    # de secuencias PXE obsoletas o configuraciones rotas de ejecuciones anteriores
    cp -f -- "$vars_template" "$vars"
    args+=(
      -drive "if=pflash,format=raw,unit=0,readonly=on,file=${code}"
      -drive "if=pflash,format=raw,unit=1,file=${vars}"
    )
    info "arranque: UEFI (OVMF limpio)"
  fi
fi

if [[ "$firmware" == bios ]]; then
  info "arranque: BIOS (syslinux)"
fi

if (( ! no_disk )); then
  if [[ -n "$disk" && "$disk" != "30G" && ! "$disk" =~ \.raw$ && ! "$disk" =~ \.qcow2$ ]]; then
    disk_img="${RUN_DIR}/titan-${disk}.raw"
    [[ -f "$disk_img" ]] || qemu-img create -q -f raw "$disk_img" "$disk"
  elif [[ "$disk" =~ \.qcow2$ ]]; then
    disk_img="${disk}"
  else
    disk_img="${RUN_DIR}/disco-vacio.raw"
    [[ -f "$disk_img" ]] || qemu-img create -q -f raw "$disk_img" 30G
  fi

  disk_format="raw"
  [[ "$disk_img" =~ \.qcow2$ ]] && disk_format="qcow2"

  if (( boot_installed )); then
    args+=(
      -drive "file=${disk_img},format=${disk_format},if=none,id=system_disk"
      -device "virtio-blk-pci,drive=system_disk,bootindex=1"
    )
    info "disco instalado conectado: ${disk_img} (arranque primario bootindex=1)"
  else
    args+=(
      -drive "file=${disk_img},format=${disk_format},if=none,id=system_disk"
      -device "virtio-blk-pci,drive=system_disk,bootindex=2"
    )
    info "disco virtual conectado para instalación: ${disk_img} (bootindex=2)"
  fi
fi

# Soporte de dispositivos USB (físico del host o pendrive virtual de prueba)
has_xhci=0

if [[ -n "$usb_host" ]]; then
  if [[ "$usb_host" == "auto" ]]; then
    # Autodetectar primer USB de almacenamiento conectado al host
    usb_target="$(lsblk -dpno PATH,TRAN 2>/dev/null | awk '$2=="usb"{print $1; exit}')"
    if [[ -z "$usb_target" ]]; then
      yel "AVISO: No se detectó ningún USB de almacenamiento conectado al host. Se omite --usb."
    else
      usb_host="$usb_target"
    fi
  fi

  if [[ -n "$usb_host" && "$usb_host" != "auto" ]]; then
    if [[ ! -b "$usb_host" && ! -f "$usb_host" ]]; then
      red "ERROR: El dispositivo o archivo USB '${usb_host}' no existe."
      exit 1
    fi

    if [[ ! -r "$usb_host" || ! -w "$usb_host" ]]; then
      yel "AVISO: '${usb_host}' puede requerir permisos de lectura/escritura."
      yel "       Si QEMU da 'Permission denied', ejecuta: sudo chmod 666 ${usb_host}"
    fi

    if (( ! has_xhci )); then
      args+=(-device qemu-xhci,id=xhci)
      has_xhci=1
    fi

    args+=(
      -drive "id=hostusb,file=${usb_host},format=raw,if=none,cache=none"
      -device "usb-storage,bus=xhci.0,drive=hostusb"
    )
    info "USB del host conectado: ${usb_host}"
  fi
fi

if (( test_usb )); then
  test_usb_img="${RUN_DIR}/titan-test-usb.img"
  if [[ ! -f "$test_usb_img" ]]; then
    info "Creando pendrive virtual de prueba (512M FAT32)..."
    dd if=/dev/zero of="$test_usb_img" bs=1M count=512 status=none
    mkfs.vfat -F 32 -n "TITAN_USB" "$test_usb_img" >/dev/null 2>&1 || true
    if command -v mcopy >/dev/null 2>&1; then
      echo "¡Hola desde Titan Linux! Este es un pendrive USB de prueba." > /tmp/bienvenido_usb.txt
      mcopy -i "$test_usb_img" /tmp/bienvenido_usb.txt ::/bienvenido.txt 2>/dev/null || true
      rm -f /tmp/bienvenido_usb.txt
    fi
  fi

  if (( ! has_xhci )); then
    args+=(-device qemu-xhci,id=xhci)
    has_xhci=1
  fi

  args+=(
    -drive "id=testusb,file=${test_usb_img},format=raw,if=none"
    -device "usb-storage,bus=xhci.0,drive=testusb"
  )
  info "USB virtual de prueba conectado: ${test_usb_img} (TITAN_USB)"
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
if (( has_battery_sync )); then
  qemu-system-x86_64 "${args[@]}" &
  qemu_pid=$!

  # Sincronizador de batería en segundo plano desde el host hacia QEMU
  (
    while kill -0 "$qemu_pid" 2>/dev/null; do
      if [[ -S "${bat_sock}" ]]; then
        c="$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1 || echo 100)"
        s="$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1 || echo Discharging)"
        a="$(cat /sys/class/power_supply/A*/online 2>/dev/null | head -n1 || echo 0)"
        python3 -c "import socket; s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.connect('${bat_sock}'); s.sendall(b'${c}|${s}|${a}\n'); s.close()" 2>/dev/null || true
      fi
      sleep 4
    done
  ) &
  sync_pid=$!

  cleanup() {
    kill "$sync_pid" "$qemu_pid" 2>/dev/null || true
    rm -f "${bat_sock}"
  }
  trap cleanup INT TERM EXIT

  wait "$qemu_pid" 2>/dev/null || true
else
  exec qemu-system-x86_64 "${args[@]}"
fi
