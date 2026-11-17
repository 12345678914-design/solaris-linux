# /etc/profile.d/15-titan-grafico.sh
# shellcheck shell=bash
#
# Titan Linux - arranque del escritorio grafico con Titan Shell (Qt Quick)
#
# Compositor:
#   wayfire  sesion inmersiva (animaciones, desenfoque real). Por defecto si
#            hay GPU con aceleracion 3D.
#   labwc    respaldo ligero: VMs, sin 3D, nomodeset/titan.compat, o si
#            Wayfire no arranca.
# Forzar uno: TITAN_DESKTOP=wayfire|labwc|plasma, o en la linea del kernel
# titan.wayfire / titan.labwc.

# Sistema instalado: greetd inicia la sesion y llama a este fichero desde
# /usr/lib/titan/titan-arranque-grafico con TITAN_DESDE_GREETD=1 (no es una
# shell interactiva ni hace falta que sea tty1). En el live, tty1 con
# entrada automatica, como siempre.
if [ -z "${TITAN_DESDE_GREETD:-}" ]; then
  case $- in
    *i*) ;;
    *) return 0 ;;
  esac

  [ "$(tty 2>/dev/null)" = "/dev/tty1" ] || return 0
fi
[ -n "${TMUX:-}" ] && return 0
[ -n "${TITAN_GRAFICO:-}" ] && return 0
[ -e /etc/titan/modo-texto ] && return 0
TITAN_CMDLINE="${TITAN_CMDLINE:-/proc/cmdline}"
TITAN_DRM_DIR="${TITAN_DRM_DIR:-/dev/dri}"
TITAN_DRM="${TITAN_DRM:-}"
grep -qw 'titan.texto' "${TITAN_CMDLINE}" 2>/dev/null && return 0

if [ -z "${TITAN_DRM}" ]; then
  intentos=0
  while [ "${intentos}" -lt 12 ]; do
    for drm in "${TITAN_DRM_DIR}"/card* "${TITAN_DRM_DIR}"/render* /dev/fb0; do
      if [ -e "${drm}" ]; then
        TITAN_DRM="${drm}"
        break
      fi
    done
    [ -n "${TITAN_DRM}" ] && break
    intentos=$((intentos + 1))
    sleep 0.5
  done
fi

if [ ! -e "${TITAN_DRM}" ]; then
  echo "Aviso: no hay dispositivo de grafica (/dev/dri o /dev/fb0); consola de texto."
  return 0
fi

if ! command -v dbus-run-session >/dev/null 2>&1; then
  echo "Aviso: falta dbus-run-session; se sigue en consola de texto."
  return 0
fi

# Selección de sesión: labwc/titan-shell (por defecto) o KDE Plasma 6 si se solicita
SESION_DESKTOP="labwc"
if [ "${TITAN_DESKTOP:-}" = "plasma" ] && command -v startplasma-wayland >/dev/null 2>&1; then
  SESION_DESKTOP="plasma"
fi

if [ "${SESION_DESKTOP}" = "plasma" ]; then
  TITAN_GRAFICO=1
  export TITAN_GRAFICO
  export XDG_SESSION_TYPE=wayland
  export XDG_CURRENT_DESKTOP=KDE
  export KDE_SESSION_VERSION=6
  export QT_QPA_PLATFORM="wayland;xcb"
  export GDK_BACKEND="wayland,x11"
  export MOZ_ENABLE_WAYLAND=1

  case "${LANG:-}" in
    ""|C|POSIX) export LANG=es_ES.UTF-8 ;;
  esac

  echo "Iniciando Inti OS (KDE Plasma 6 Wayland)..."
  dbus-run-session -- startplasma-wayland 2>&1 | tee /tmp/plasma.log
  codigo_salida=${PIPESTATUS[0]}
  if [ $codigo_salida -ne 0 ] && [ -s /tmp/plasma.log ]; then
    echo "Aviso: KDE Plasma finalizó con código ${codigo_salida}."
    tail -n 25 /tmp/plasma.log
  fi
  echo "El escritorio se ha cerrado. Volviendo a la consola de texto."
  return 0
fi

for programa in labwc titan-desktop; do
  if ! command -v "${programa}" >/dev/null 2>&1; then
    echo "Aviso: falta ${programa}; se sigue en consola de texto."
    return 0
  fi
done

TITAN_GRAFICO=1
export TITAN_GRAFICO
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Titan:labwc

# Asegurar que DISPLAY no esté predefinido para que labwc inicialice el backend nativo
unset DISPLAY

# 1. Detección de arranque en modo compatibilidad forzada (nomodeset, titan.compat, safe_graphics)
ES_COMPAT=0
if grep -qE '(titan\.compat|nomodeset|safe_graphics)' "${TITAN_CMDLINE}" 2>/dev/null; then
  ES_COMPAT=1
fi

# 2. Detección de máquina virtual (QEMU, KVM, VMware, VirtualBox, Hyper-V, Xen)
ES_VM=0
if command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt -q; then
  ES_VM=1
fi

# 3. Detección de ausencia de acelerador 3D por hardware (ej. simpledrm, bochs, efifb, sin renderD*)
SIN_ACCEL_3D=0
if [ ! -e /dev/dri/renderD* ]; then
  SIN_ACCEL_3D=1
fi

# 3.1 Detección detallada de GPUs físicas (Intel, AMD, NVIDIA) y estado de drivers
ES_INTEL=0
ES_AMD=0
ES_NVIDIA=0
NVIDIA_PROPIETARIO=0
NVIDIA_NOUVEAU=0

if command -v lspci >/dev/null 2>&1; then
  lspci | grep -qiE "(vga|display).*intel" && ES_INTEL=1
  lspci | grep -qiE "(vga|display).*(amd|ati|radeon)" && ES_AMD=1
  lspci | grep -qiE "(vga|3d).*nvidia" && ES_NVIDIA=1
fi

# Verificar si el driver privativo de NVIDIA (nvidia/nvidia-drm) está realmente cargado en el kernel y activo
if [ -d /sys/module/nvidia_drm ] && { [ -e /dev/nvidia0 ] || [ -e /dev/nvidiactl ]; }; then
  NVIDIA_PROPIETARIO=1
  ES_NVIDIA=1
elif [ -d /sys/module/nouveau ]; then
  NVIDIA_NOUVEAU=1
fi

ES_HIBRIDA=0
if [ "${ES_NVIDIA}" -eq 1 ] && { [ "${ES_INTEL}" -eq 1 ] || [ "${ES_AMD}" -eq 1 ]; }; then
  ES_HIBRIDA=1
fi

# En híbridas (Intel/AMD + NVIDIA), buscar la tarjeta DRM de la integrada (Intel: 0x8086, AMD: 0x1002)
IGPU_CARD=""
if [ "${ES_HIBRIDA}" -eq 1 ]; then
  for card_dir in /sys/class/drm/card[0-9]; do
    [ -d "${card_dir}" ] || continue
    vendor_file="${card_dir}/device/vendor"
    if [ -f "${vendor_file}" ]; then
      vendor=$(cat "${vendor_file}" 2>/dev/null)
      if [ "${vendor}" = "0x8086" ] || [ "${vendor}" = "0x1002" ]; then
        IGPU_CARD="$(basename "${card_dir}")"
        break
      fi
    fi
  done
fi

# Detectar qué tarjeta DRM tiene conectada físicamente la pantalla (eDP-1 en laptop, HDMI/DP en sobremesa)
CARD_PANTALLA=""
for status_file in /sys/class/drm/card*-*/status; do
  if [ -f "${status_file}" ] && grep -q "^connected" "${status_file}" 2>/dev/null; then
    CARD_PANTALLA="$(echo "${status_file}" | sed -E 's|.*/(card[0-9]+)-.*|\1|')"
    break
  fi
done

# 4. Asignación de hilos de renderizado por software según núcleos de CPU (óptimo para Intel Celeron)
NCORES=$(nproc 2>/dev/null || echo 2)
export LP_NUM_THREADS="${NCORES}"

aplicar_capa_compatibilidad() {
  export WLR_RENDERER=pixman
  # En una VM el cursor va por hardware: la GPU virtual (virtio, vmwgfx, qxl)
  # tiene plano de cursor y el visor (QEMU, VirtualBox, VMware) lo muestra
  # como el puntero del anfitrion. Con cursor por software se veian DOS
  # flechas: la que dibuja el compositor y la del visor. Si no hay plano de
  # cursor, wlroots ya dibuja el cursor por software sin ayuda.
  if [ "${ES_VM:-0}" -eq 1 ]; then
    unset WLR_NO_HARDWARE_CURSORS
  else
    export WLR_NO_HARDWARE_CURSORS=1
  fi
  export LIBGL_ALWAYS_SOFTWARE=1
  export QT_QUICK_BACKEND=software
  export QSG_RHI_BACKEND=software
  export QSG_RENDER_LOOP=basic
  export MESA_GL_VERSION_OVERRIDE=3.3
  export MESA_GLSL_VERSION_OVERRIDE=330
}

if [ "${ES_COMPAT}" -eq 1 ] || [ "${ES_VM}" -eq 1 ] || [ "${SIN_ACCEL_3D}" -eq 1 ]; then
  echo "Titan Linux: activando capa de compatibilidad universal (renderizado por software/pixman)..."
  aplicar_capa_compatibilidad
else
  # En hardware real con GPU física (Intel, AMD, NVIDIA)
  export WLR_NO_HARDWARE_CURSORS=1
  if [ "${ES_HIBRIDA}" -eq 1 ]; then
    echo "Titan Linux: Laptop con gráficos híbridos detectada (Intel/AMD + NVIDIA)."
    echo "-> Asignando pantalla principal a la GPU integrada (PRIME Offload disponible para NVIDIA)."
    target_card="${IGPU_CARD:-${CARD_PANTALLA}}"
    if [ -n "${target_card}" ] && [ -e "/dev/dri/${target_card}" ]; then
      export WLR_DRM_DEVICES="/dev/dri/${target_card}"
    fi
    # No forzar variables de NVIDIA a nivel global para que el escritorio corra sobre la iGPU (Mesa)
  elif [ "${ES_NVIDIA}" -eq 1 ]; then
    if [ "${NVIDIA_PROPIETARIO}" -eq 1 ]; then
      echo "Titan Linux: GPU NVIDIA detectada con driver privativo activo (nvidia-drm)..."
      export LIBVA_DRIVER_NAME=nvidia
      export __GLX_VENDOR_LIBRARY_NAME=nvidia
      # IMPORTANTE: No fijar GBM_BACKEND=nvidia-drm (Mesa 21.2+ lo maneja internamente; fijarlo rompe labwc, Qt y Firefox)
      unset GBM_BACKEND 2>/dev/null || true
    else
      echo "Titan Linux: GPU NVIDIA detectada operando con driver abierto y estable (Nouveau/Mesa)..."
      # Driver abierto Nouveau: renderizado 100% nativo vía Mesa. No forzar variables privativas.
      unset __GLX_VENDOR_LIBRARY_NAME 2>/dev/null || true
      unset GBM_BACKEND 2>/dev/null || true
      unset LIBVA_DRIVER_NAME 2>/dev/null || true
    fi
  else
    echo "Titan Linux: GPU Intel/AMD detectada - aceleración OpenGL/Vulkan nativa vía Mesa."
  fi
fi

export QT_QPA_PLATFORM="wayland;xcb"
export GDK_BACKEND="wayland,x11"
export MOZ_ENABLE_WAYLAND=1
export MOZ_GTK_TITLEBAR_DECORATION=system

case "${LANG:-}" in
  ""|C|POSIX) export LANG=C.UTF-8 ;;
esac

# 5. Compositor: Wayfire (inmersivo) solo con aceleracion 3D real; necesita
#    OpenGL ES y no tiene renderizado por software como labwc (pixman).
COMPOSITOR="labwc"
if command -v wayfire >/dev/null 2>&1 && [ -f "${HOME}/.config/wayfire.ini" ]; then
  if [ "${ES_COMPAT}" -eq 0 ] && [ "${ES_VM}" -eq 0 ] && [ "${SIN_ACCEL_3D}" -eq 0 ]; then
    COMPOSITOR="wayfire"
  fi
  # VM con GPU virtual 3D (virgl: virtio-vga-gl; vmwgfx con 3D): tiene nodo
  # de render, asi que tambien puede. Si Wayfire no arranca, se cae a labwc.
  if [ "${ES_COMPAT}" -eq 0 ] && [ -e /dev/dri/renderD128 ]; then
    COMPOSITOR="wayfire"
  fi
  if grep -qw 'titan.wayfire' "${TITAN_CMDLINE}" 2>/dev/null || [ "${TITAN_DESKTOP:-}" = "wayfire" ]; then
    [ -e /dev/dri/renderD128 ] && COMPOSITOR="wayfire"
  fi
fi
if grep -qw 'titan.labwc' "${TITAN_CMDLINE}" 2>/dev/null || [ "${TITAN_DESKTOP:-}" = "labwc" ]; then
  COMPOSITOR="labwc"
fi

codigo_salida=1
if [ "${COMPOSITOR}" = "wayfire" ]; then
  # labwc lee ~/.config/labwc/environment; Wayfire no, asi que se exporta aqui.
  export XDG_CURRENT_DESKTOP=Titan:wayfire
  # Si se forzo Wayfire en una VM con virgl, quitar la capa por software.
  unset WLR_RENDERER LIBGL_ALWAYS_SOFTWARE QSG_RENDER_LOOP MESA_GL_VERSION_OVERRIDE MESA_GLSL_VERSION_OVERRIDE
  export QT_QUICK_BACKEND=rhi
  export QSG_RHI_BACKEND=opengl
  export QT_WAYLAND_DISABLE_WINDOWDECORATION=0
  # Con preferred_decoration_mode=client, Firefox dibuja su barra redondeada.
  export MOZ_GTK_TITLEBAR_DECORATION=client
  export NO_AT_BRIDGE=1
  echo "Iniciando Inti OS (sesión inmersiva con Wayfire)..."
  dbus-run-session -- wayfire 2>&1 | tee /tmp/wayfire.log
  codigo_salida=${PIPESTATUS[0]}
  if [ $codigo_salida -ne 0 ]; then
    echo "Aviso: Wayfire finalizó con código ${codigo_salida}; se usa labwc."
    tail -n 15 /tmp/wayfire.log
    export XDG_CURRENT_DESKTOP=Titan:labwc
    export MOZ_GTK_TITLEBAR_DECORATION=system
    unset QT_QUICK_BACKEND QSG_RHI_BACKEND
    [ "${ES_VM}" -eq 1 ] && aplicar_capa_compatibilidad
    COMPOSITOR="labwc"
  fi
fi

if [ "${COMPOSITOR}" = "labwc" ]; then
echo "Iniciando Titan Linux (interfaz gráfica estilo macOS con labwc)..."
dbus-run-session -- labwc 2>&1 | tee /tmp/labwc.log
codigo_salida=${PIPESTATUS[0]}

# Fallback automático: si labwc falló con el motor acelerado, reintentar automáticamente con compatibilidad software
if [ $codigo_salida -ne 0 ] && [ "${ES_COMPAT}" -eq 0 ] && [ "${ES_VM}" -eq 0 ] && [ "${SIN_ACCEL_3D}" -eq 0 ]; then
  echo "Aviso: fallo de inicialización acelerada (código ${codigo_salida}). Reintentando con capa de compatibilidad..."
  unset GBM_BACKEND 2>/dev/null || true
  unset __GLX_VENDOR_LIBRARY_NAME 2>/dev/null || true
  unset LIBVA_DRIVER_NAME 2>/dev/null || true
  unset WLR_DRM_DEVICES 2>/dev/null || true
  aplicar_capa_compatibilidad
  dbus-run-session -- labwc 2>&1 | tee -a /tmp/labwc.log
  codigo_salida=${PIPESTATUS[0]}
fi

if [ $codigo_salida -ne 0 ] && [ -s /tmp/labwc.log ]; then
  echo "Aviso: labwc finalizó con código ${codigo_salida}. Registro de error:"
  tail -n 25 /tmp/labwc.log
fi
fi

echo "El escritorio se ha cerrado. Volviendo a la consola de texto."
