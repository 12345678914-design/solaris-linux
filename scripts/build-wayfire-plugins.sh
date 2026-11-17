#!/bin/bash
# Compila los plugins de Wayfire propios de Inti OS (apps/wayfire-titan) y los
# deja en el perfil de la ISO (airootfs/usr/lib/wayfire).
#
# No hace falta tener Wayfire instalado en la maquina de compilacion: si no
# hay cabeceras en el sistema, descarga (sin instalar) los paquetes wayfire,
# wf-config, wlroots0.20 y glm de los repositorios configurados en pacman y
# compila contra ellos. Son las mismas versiones que lleva la ISO.
#
# Si algo falla, avisa y sale con 0: la sesion Wayfire funciona igual sin el
# plugin (solo vuelve la gelatina al redimensionar).
#
# Uso: ./scripts/build-wayfire-plugins.sh [directorio-destino]

set -u

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fuentes="${raiz}/apps/wayfire-titan"
destino="${1:-${raiz}/iso/titan/airootfs/usr/lib/wayfire}"
sdk="${raiz}/build/wayfire-sdk"

aviso() { printf '\033[33m[wayfire-titan] %s\033[0m\n' "$*" >&2; }

cflags=()
if pkg-config --exists wayfire 2>/dev/null; then
  read -r -a cflags <<<"$(pkg-config --cflags wayfire)"
else
  if [[ ! -f "${sdk}/usr/include/wayfire/plugin.hpp" ]]; then
    mkdir -p "${sdk}/paquetes"
    urls="$(pacman -Sp wayfire wf-config wlroots0.20 glm 2>/dev/null)" || urls=""
    if [[ -z "${urls}" ]]; then
      aviso "pacman -Sp no devolvio paquetes; no se compila titan-wobbly-guard"
      exit 0
    fi
    for u in ${urls}; do
      f="${sdk}/paquetes/$(basename "${u}")"
      [[ -f "${f}" ]] || curl -fsSL -o "${f}" "${u}" || { aviso "no se pudo descargar ${u}"; exit 0; }
      bsdtar -xf "${f}" -C "${sdk}" usr/include usr/lib/pkgconfig 2>/dev/null || true
    done
  fi
  cflags=(-I"${sdk}/usr/include" -I"${sdk}/usr/include/wlroots-0.20")
  for p in pixman-1 wayland-server cairo pango libdrm xkbcommon; do
    if pkg-config --exists "${p}"; then
      read -r -a extra <<<"$(pkg-config --cflags "${p}")"
      cflags+=("${extra[@]}")
    fi
  done
fi

install -d -m 0755 "${destino}"
estado=0
for fuente in "${fuentes}"/*.cpp; do
  nombre="$(basename "${fuente}" .cpp)"
  if g++ -std=c++17 -O2 -fPIC -shared -DWLR_USE_UNSTABLE "${cflags[@]}" \
       -o "${destino}/lib${nombre}.so" "${fuente}"; then
    chmod 0755 "${destino}/lib${nombre}.so"
    echo "[wayfire-titan] lib${nombre}.so -> ${destino}"
  else
    aviso "fallo al compilar ${nombre}"
    estado=1
  fi
done

# Un fallo de compilacion si se senala (es un error del codigo, no del entorno).
exit "${estado}"
