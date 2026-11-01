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
  while [ "${intentos}" -lt 10 ]; do
    for drm in "${TITAN_DRM_DIR}"/card* "${TITAN_DRM_DIR}"/render*; do
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

for programa in dbus-run-session labwc titan-desktop; do
  if ! command -v "${programa}" >/dev/null 2>&1; then
    echo "Aviso: falta ${programa}; se sigue en consola de texto."
    return 0
  fi
done

if [ ! -e "${TITAN_DRM}" ]; then
  echo "Aviso: no hay dispositivo de grafica; consola de texto."
  return 0
fi

TITAN_GRAFICO=1
export TITAN_GRAFICO
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Titan:labwc

# Asegurar que DISPLAY no esté predefinido para que labwc inicialice el backend DRM/KMS nativo
unset DISPLAY
export WLR_BACKENDS="drm,libinput"

# Backend por software para compatibilidad completa en QEMU y VMware
export QT_QUICK_BACKEND=software
export QSG_RHI_BACKEND=software
export QT_QPA_PLATFORM="wayland;xcb"
export GDK_BACKEND="wayland,x11"
export MOZ_ENABLE_WAYLAND=1
export MOZ_GTK_TITLEBAR_DECORATION=system

case "${LANG:-}" in
  ""|C|POSIX) export LANG=C.UTF-8 ;;
esac

echo "Iniciando Titan Linux (interfaz gráfica estilo macOS con labwc)..."
dbus-run-session -- labwc >/tmp/labwc.log 2>&1
codigo_salida=$?

if [ $codigo_salida -ne 0 ] && [ -s /tmp/labwc.log ]; then
  echo "Aviso: labwc finalizó con código ${codigo_salida}. Registro de error:"
  tail -n 25 /tmp/labwc.log
fi

echo "El escritorio se ha cerrado. Volviendo a la consola de texto."
