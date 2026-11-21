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
# plugin (vuelve la gelatina al redimensionar y la barra de Wayfire).
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
  # wlroots-full.hpp incluye wlr/render/vulkan.h, que pide las cabeceras de
  # Vulkan aunque los plugins no lo usen. Si no estan en el sistema (p. ej.
  # tras quitar vulkan-headers como paquete huerfano) se bajan al SDK.
  if [[ ! -f /usr/include/vulkan/vulkan_core.h && ! -f "${sdk}/usr/include/vulkan/vulkan_core.h" ]]; then
    mkdir -p "${sdk}/paquetes"
    for u in $(pacman -Sp vulkan-headers 2>/dev/null); do
      f="${sdk}/paquetes/$(basename "${u}")"
      [[ -f "${f}" ]] || curl -fsSL -o "${f}" "${u}" || { aviso "no se pudo descargar ${u}"; continue; }
      bsdtar -xf "${f}" -C "${sdk}" usr/include 2>/dev/null || true
    done
    [[ -f "${sdk}/usr/include/vulkan/vulkan_core.h" ]] || aviso "faltan las cabeceras de Vulkan (paquete vulkan-headers)"
  fi
  for p in pixman-1 wayland-server cairo pango pangocairo libdrm xkbcommon; do
    if pkg-config --exists "${p}"; then
      read -r -a extra <<<"$(pkg-config --cflags "${p}")"
      cflags+=("${extra[@]}")
    fi
  done
fi

# Bibliotecas que usan los plugins de dibujo (titan-decor: cairo + pango).
libs=()
if pkg-config --exists pangocairo cairo 2>/dev/null; then
  read -r -a libs <<<"$(pkg-config --libs pangocairo cairo)"
fi

install -d -m 0755 "${destino}"
estado=0
compilar() {
  local nombre="$1"; shift
  if g++ -std=c++17 -O2 -fPIC -shared -DWLR_USE_UNSTABLE "${cflags[@]}" \
       -o "${destino}/lib${nombre}.so" "$@" "${libs[@]}"; then
    chmod 0755 "${destino}/lib${nombre}.so"
    echo "[wayfire-titan] lib${nombre}.so -> ${destino}"
  else
    aviso "fallo al compilar ${nombre}"
    estado=1
  fi
}

# Un plugin por fichero (titan-wobbly-guard.cpp) ...
for fuente in "${fuentes}"/*.cpp; do
  [[ -e "${fuente}" ]] || continue
  compilar "$(basename "${fuente}" .cpp)" "${fuente}"
done
# ... o por carpeta con varios .cpp (titan-decor/).
for carpeta in "${fuentes}"/*/; do
  carpeta="${carpeta%/}"
  compgen -G "${carpeta}/*.cpp" >/dev/null || continue
  compilar "$(basename "${carpeta}")" "${carpeta}"/*.cpp
done

# Version de ABI de Wayfire con la que se han compilado: titan-actualizar-sistema
# retiene Wayfire si una actualizacion trae otra (los plugins no cargarian).
for inc in "${cflags[@]}"; do
  cabecera="${inc#-I}/wayfire/plugin.hpp"
  [[ "${inc}" == -I* && -f "${cabecera}" ]] || continue
  abi="$(sed -n "s/.*WAYFIRE_API_ABI_VERSION_MACRO[[:space:]]*\([0-9']*\).*/\1/p" "${cabecera}" | tr -d "'" | head -n 1)"
  if [[ -n "${abi}" && "${destino}" == "${raiz}/iso/titan/airootfs/usr/lib/wayfire" ]]; then
    install -d -m 0755 "${raiz}/iso/titan/airootfs/usr/share/titan"
    printf '%s\n' "${abi}" > "${raiz}/iso/titan/airootfs/usr/share/titan/wayfire-abi"
    echo "[wayfire-titan] ABI de Wayfire ${abi} -> usr/share/titan/wayfire-abi"
  fi
  break
done

# Un fallo de compilacion si se senala (es un error del codigo, no del entorno).
exit "${estado}"
