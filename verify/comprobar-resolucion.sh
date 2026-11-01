#!/usr/bin/env bash
# Comprueba la deteccion de resolucion de scripts/detectar-resolucion.sh y
# que las lineas de arranque no vuelvan a fijar 1280x720/1920x1080 a mano.
# No arranca QEMU.
set -u

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECTAR="${RAIZ}/scripts/detectar-resolucion.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

fallos=0
ok() { printf 'ok: %s\n' "$1"; }
mal() { printf 'FALLO: %s\n' "$1" >&2; fallos=$((fallos + 1)); }

if [[ ! -x "${DETECTAR}" ]]; then
  echo "FALLO: no existe ${DETECTAR}" >&2
  exit 1
fi

mkdir -p "${TMP}/bin" "${TMP}/drm/card0-eDP-1" \
  "${TMP}/drm/card0-HDMI-A-1" "${TMP}/vacio"

printf '#!/bin/sh\nexit 1\n' >"${TMP}/bin/niri"
printf '#!/bin/sh\nexit 1\n' >"${TMP}/bin/wlr-randr"
printf '#!/bin/sh\nexit 1\n' >"${TMP}/bin/xrandr"
chmod +x "${TMP}/bin/niri" "${TMP}/bin/wlr-randr" \
  "${TMP}/bin/xrandr"

probar() {
  local nombre="$1" esperado="$2"
  shift 2
  local salida
  salida="$(PATH="${TMP}/bin:/usr/bin:/bin" "$@" \
    "${DETECTAR}" 2>"${TMP}/err")"
  if [[ "${salida}" == "${esperado}" ]]; then
    ok "${nombre}"
  else
    mal "${nombre}: ${salida:-<vacio>} (esperado ${esperado})"
  fi
}

cat >"${TMP}/bin/niri" <<'FIN'
#!/bin/sh
if [ "$1" = "msg" ] && [ "$2" = "-j" ]; then
  cat <<'JSON'
{"eDP-1":{"logical":{"width":1366,"height":768}},
 "HDMI-A-1":{"logical":{"width":1920,"height":1080}}}
JSON
  exit 0
fi
exit 1
FIN
chmod +x "${TMP}/bin/niri"
probar "niri elige la salida mayor" "1920x1080" \
  env NIRI_SOCKET=/tmp/falso

printf '#!/bin/sh\nexit 1\n' >"${TMP}/bin/niri"
chmod +x "${TMP}/bin/niri"
cat >"${TMP}/bin/wlr-randr" <<'FIN'
#!/bin/sh
[ "$1" = "--json" ] || exit 1
cat <<'JSON'
[{"name":"eDP-1","enabled":true,
  "current_mode":{"width":2560,"height":1440}}]
JSON
FIN
chmod +x "${TMP}/bin/wlr-randr"
probar "wlr-randr lee el modo actual" "2560x1440" env

printf '#!/bin/sh\nexit 1\n' >"${TMP}/bin/wlr-randr"
chmod +x "${TMP}/bin/wlr-randr"
cat >"${TMP}/bin/xrandr" <<'FIN'
#!/bin/sh
echo "Screen 0: minimum 8 x 8, current 1600 x 900, maximum 32767 x 32767"
FIN
chmod +x "${TMP}/bin/xrandr"
probar "xrandr lee la pantalla actual" "1600x900" env

printf '#!/bin/sh\nexit 1\n' >"${TMP}/bin/xrandr"
chmod +x "${TMP}/bin/xrandr"
printf 'connected\n' >"${TMP}/drm/card0-eDP-1/status"
printf '1366x768\n1024x768\n' >"${TMP}/drm/card0-eDP-1/modes"
printf 'disconnected\n' >"${TMP}/drm/card0-HDMI-A-1/status"
printf '1920x1080\n' >"${TMP}/drm/card0-HDMI-A-1/modes"
probar "DRM usa el modo de la salida conectada" "1366x768" \
  env TITAN_DRM_DIR="${TMP}/drm"

probar "sin datos usa 1280x720" "1280x720" \
  env TITAN_DRM_DIR="${TMP}/vacio"

probar "TITAN_QEMU_RESOLUCION se respeta" "1920x1080" \
  env TITAN_QEMU_RESOLUCION=1920x1080

if PATH="${TMP}/bin:/usr/bin:/bin" TITAN_QEMU_RESOLUCION=1920 \
    "${DETECTAR}" >/dev/null 2>&1; then
  mal "una resolucion invalida deberia fallar"
else
  ok "una resolucion invalida falla"
fi

grep -q 'detectar-resolucion.sh' "${RAIZ}/scripts/run-qemu.sh" \
  && grep -q 'virtio-vga,xres=' "${RAIZ}/scripts/run-qemu.sh" \
  && ! grep -q 'xres=1920' "${RAIZ}/scripts/run-qemu.sh" \
  && ok "run-qemu detecta y pasa la resolucion a virtio-vga" \
  || mal "run-qemu no usa la deteccion dinamica"

if grep -Eq '^[[:space:]]*linux /.*video=|^APPEND .*video=' \
    "${RAIZ}/iso/titan/grub/grub.cfg" \
    "${RAIZ}/iso/titan/syslinux/syslinux-linux.cfg"; then
  mal "las lineas de arranque todavia fijan video="
else
  ok "las lineas de arranque no fijan video="
fi

if [[ ${fallos} -ne 0 ]]; then
  echo "resolucion: ${fallos} fallo(s)" >&2
  exit 1
fi
echo "resolucion: todo correcto"
