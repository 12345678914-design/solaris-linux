# /etc/profile.d/15-titan-grafico.sh
# shellcheck shell=bash
#
# Titan Linux - arranque del escritorio grafico con Labwc y Titan Shell (Qt Quick)

case $- in
  *i*) ;;
  *) return 0 ;;
esac

[ "$(tty 2>/dev/null)" = "/dev/tty1" ] || return 0
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

  echo "Iniciando Solaris (KDE Plasma 6 Wayland)..."
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

# 4. Asignación de hilos de renderizado por software según núcleos de CPU (óptimo para Intel Celeron)
NCORES=$(nproc 2>/dev/null || echo 2)
export LP_NUM_THREADS="${NCORES}"

aplicar_capa_compatibilidad() {
  export WLR_RENDERER=pixman
  export WLR_NO_HARDWARE_CURSORS=1
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
  # En hardware real con GPU física (Intel, AMD, NVIDIA), usar aceleración normal con cursor visible garantizado
  export WLR_NO_HARDWARE_CURSORS=1
fi

export QT_QPA_PLATFORM="wayland;xcb"
export GDK_BACKEND="wayland,x11"
export MOZ_ENABLE_WAYLAND=1
export MOZ_GTK_TITLEBAR_DECORATION=system

case "${LANG:-}" in
  ""|C|POSIX) export LANG=C.UTF-8 ;;
esac

echo "Iniciando Titan Linux (interfaz gráfica estilo macOS con labwc)..."
dbus-run-session -- labwc 2>&1 | tee /tmp/labwc.log
codigo_salida=${PIPESTATUS[0]}

# Fallback automático: si labwc falló con el motor acelerado, reintentar automáticamente con compatibilidad software
if [ $codigo_salida -ne 0 ] && [ "${ES_COMPAT}" -eq 0 ] && [ "${ES_VM}" -eq 0 ] && [ "${SIN_ACCEL_3D}" -eq 0 ]; then
  echo "Aviso: fallo de inicialización acelerada (código ${codigo_salida}). Reintentando con capa de compatibilidad..."
  aplicar_capa_compatibilidad
  dbus-run-session -- labwc 2>&1 | tee -a /tmp/labwc.log
  codigo_salida=${PIPESTATUS[0]}
fi

if [ $codigo_salida -ne 0 ] && [ -s /tmp/labwc.log ]; then
  echo "Aviso: labwc finalizó con código ${codigo_salida}. Registro de error:"
  tail -n 25 /tmp/labwc.log
fi

echo "El escritorio se ha cerrado. Volviendo a la consola de texto."
