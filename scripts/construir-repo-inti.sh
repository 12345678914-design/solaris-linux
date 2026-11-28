#!/bin/bash
# Construye el repositorio [inti] (apps, herramientas, plugins y tema de
# Inti OS, más el núcleo linux-titanlinux) en build/inti-repo.
#
#   ./scripts/construir-repo-inti.sh             construir (después de 'make apps')
#   ./scripts/construir-repo-inti.sh --publicar  construir y subirlo a GitHub
#
# Firma: con INTI_CLAVE=<id de la clave GPG> firma paquetes y base de datos.
# Sin clave construye igual (para probar en local), pero no deja publicar:
# un sistema instalado solo acepta paquetes de [inti] firmados.
#
# Publicar = subir los ficheros a la versión "paquetes" de las Releases de
# github.com/12345678914-design/inti-repo con 'gh' (hay que haber hecho
# 'gh auth login'). Los sistemas instalados los descargan de:
#   https://github.com/12345678914-design/inti-repo/releases/download/paquetes/
set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_gh="12345678914-design/inti-repo"
etiqueta="paquetes"
salida="${INTI_SALIDA:-${raiz}/build/inti-repo}"
trabajo="${INTI_TRABAJO:-${raiz}/build/inti-paquetes}"
publicar=0
[[ "${1:-}" == "--publicar" ]] && publicar=1

verde() { printf '\033[32m[inti-repo] %s\033[0m\n' "$*"; }
aviso() { printf '\033[33m[inti-repo] %s\033[0m\n' "$*" >&2; }
error() { printf '\033[31m[inti-repo] %s\033[0m\n' "$*" >&2; exit 1; }

for c in makepkg repo-add git; do
  command -v "$c" >/dev/null || error "Falta '$c'"
done

# Sin las apps compiladas el paquete saldría vacío
for f in titan-shell titan-settings; do
  [[ -x "${raiz}/iso/titan/airootfs/usr/local/bin/${f}" ]] ||
    error "Falta ${f} compilado: ejecuta antes 'make apps'"
done

# Versión: 1.8.<número de commits>, siempre creciente en la rama
base="$(sed -n 's/^TITAN_VERSION="${TITAN_VERSION:-\(.*\)}"$/\1/p' "${raiz}/iso/titan/airootfs/root/customize_airootfs.sh" 2>/dev/null | head -n 1)"
[[ -n "${base}" ]] || base="1.8"
version="${INTI_VERSION_FORZADA:-${base}.$(git -C "${raiz}" rev-list --count HEAD)}"
if [[ -n "$(git -C "${raiz}" status --porcelain -- apps iso/titan/airootfs paquetes 2>/dev/null)" ]]; then
  aviso "Hay cambios sin commit: la versión ${version} no corresponde exactamente a un commit"
fi
verde "Versión ${version}"

firmar=()
if [[ -n "${INTI_CLAVE:-}" ]]; then
  firmar=(--sign --key "${INTI_CLAVE}")
  verde "Firmando con la clave ${INTI_CLAVE}"
else
  aviso "Sin INTI_CLAVE: paquetes SIN firmar (solo para probar en local)"
fi

# 1. Paquetes de Inti
rm -rf "${trabajo}"
mkdir -p "${trabajo}" "${salida}"
cp "${raiz}/paquetes/inti/PKGBUILD" "${trabajo}/"
(
  cd "${trabajo}"
  INTI_RAIZ="${raiz}" INTI_VERSION="${version}" PKGDEST="${trabajo}/hechos" \
    BUILDDIR="${trabajo}/build" SRCDEST="${trabajo}/src" \
    makepkg --force --nodeps --noconfirm "${firmar[@]}" >"${trabajo}/makepkg.log" 2>&1
) || { tail -n 20 "${trabajo}/makepkg.log" >&2; error "makepkg falló (registro: ${trabajo}/makepkg.log)"; }

# 1b. La clave pública (inti-keyring), si ya se creó con crear-clave-inti.sh
if [[ -s "${raiz}/paquetes/inti-keyring/inti-trusted" ]]; then
  rm -rf "${trabajo}/keyring" && cp -r "${raiz}/paquetes/inti-keyring" "${trabajo}/keyring"
  (
    cd "${trabajo}/keyring"
    INTI_VERSION="${version}" PKGDEST="${trabajo}/hechos" BUILDDIR="${trabajo}/build" \
      makepkg --force --nodeps --noconfirm "${firmar[@]}" >>"${trabajo}/makepkg.log" 2>&1
  ) || error "makepkg de inti-keyring falló (registro: ${trabajo}/makepkg.log)"
else
  aviso "Aún no hay clave de Inti (scripts/crear-clave-inti.sh): sin inti-keyring"
fi

# 2. Lo que va al repositorio: los paquetes nuevos y el núcleo (si está hecho)
rm -f "${salida}"/*.pkg.tar.zst "${salida}"/*.sig "${salida}"/inti.*
cp "${trabajo}"/hechos/inti-*.pkg.tar.zst* "${salida}/"
nucleo="$(ls -t "${raiz}"/kernel/linux-titanlinux/linux-titanlinux-[0-9]*.pkg.tar.zst 2>/dev/null | head -n 1 || true)"
if [[ -n "${nucleo}" ]]; then
  cp "${nucleo}" "${salida}/"
  cabeceras="${nucleo/linux-titanlinux-/linux-titanlinux-headers-}"
  [[ -f "${cabeceras}" ]] && cp "${cabeceras}" "${salida}/"
  if (( ${#firmar[@]} )); then
    for p in "${salida}"/linux-titanlinux-*.pkg.tar.zst; do
      gpg --batch --yes --detach-sign --local-user "${INTI_CLAVE}" --output "${p}.sig" "${p}"
    done
  fi
else
  aviso "No hay paquete del núcleo compilado: el repositorio sale sin linux-titanlinux"
fi

# 3. Base de datos. GitHub no guarda enlaces simbólicos: se suben copias.
repo_args=()
(( ${#firmar[@]} )) && repo_args=(--sign --key "${INTI_CLAVE}")
repo-add --quiet "${repo_args[@]}" "${salida}/inti.db.tar.gz" "${salida}"/*.pkg.tar.zst
for f in db files; do
  rm -f "${salida}/inti.${f}" "${salida}/inti.${f}.sig"
  cp "${salida}/inti.${f}.tar.gz" "${salida}/inti.${f}"
  [[ -f "${salida}/inti.${f}.tar.gz.sig" ]] && cp "${salida}/inti.${f}.tar.gz.sig" "${salida}/inti.${f}.sig"
done

verde "Repositorio listo en ${salida}:"
( cd "${salida}" && ls -1sh --ignore='*.sig' | sed 's/^/    /' )

(( publicar )) || exit 0

# 4. Publicar en GitHub Releases
(( ${#firmar[@]} )) || error "No se publica sin firmar: define INTI_CLAVE"
command -v gh >/dev/null || error "Falta 'gh' (GitHub CLI)"
gh release view "${etiqueta}" --repo "${repo_gh}" >/dev/null 2>&1 ||
  gh release create "${etiqueta}" --repo "${repo_gh}" --title "Repositorio de paquetes de Inti OS" \
    --notes "Paquetes del repositorio [inti]. Los sistemas Inti OS los descargan solos al actualizar."
mapfile -t nuevos < <(cd "${salida}" && ls -1 -- *.pkg.tar.zst *.pkg.tar.zst.sig inti.db inti.db.sig inti.files inti.files.sig 2>/dev/null)
( cd "${salida}" && gh release upload "${etiqueta}" --repo "${repo_gh}" --clobber "${nuevos[@]}" )
# Quitar de la Release los paquetes de versiones anteriores
while IFS= read -r viejo; do
  printf '%s\n' "${nuevos[@]}" | grep -qxF "${viejo}" ||
    gh release delete-asset "${etiqueta}" "${viejo}" --repo "${repo_gh}" --yes
done < <(gh release view "${etiqueta}" --repo "${repo_gh}" --json assets --jq '.assets[].name')
verde "Publicado: https://github.com/${repo_gh}/releases/tag/${etiqueta}"
