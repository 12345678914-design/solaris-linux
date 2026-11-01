#!/usr/bin/env bash
# Comprueba el catalogo de titan-panel y que la barra/el centro se pueden
# pintar sin un compositor. No necesita QEMU; los fallos de layer-shell se
# cubren en verify/comprobar-escritorio-qemu.py.
set -u
export QT_QPA_PLATFORMTHEME=generic

DISTRO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PANEL="${TITAN_PANEL:-${DISTRO}/apps/titan-panel/build/titan-panel}"
CONFIG="${DISTRO}/config/titan-base.conf"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

fallos=0
ok() { printf 'ok: %s\n' "$1"; }
mal() { printf 'FALLO: %s\n' "$1" >&2; fallos=$((fallos + 1)); }

if [[ ! -x "${PANEL}" ]]; then
  echo "FALLO: no existe ${PANEL} (compila titan-panel)" >&2
  exit 1
fi

mkdir -p "${TMP}/apps/sub"
cat >"${TMP}/apps/uno.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Editor de prueba
Name[es]=Editor en espanol
Comment=Prueba del catalogo
Icon=test-icon
Exec=prueba --flag %U
Terminal=false
StartupWMClass=prueba
EOF
cat >"${TMP}/apps/oculta.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=No debe salir
Exec=oculta
NoDisplay=true
EOF
cat >"${TMP}/apps/terminal.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Terminal de prueba
Exec=htop %F
Terminal=true
EOF
cat >"${TMP}/apps/sin-programa.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=No debe salir
Exec=no-existe
TryExec=no-existe-de-verdad
EOF
cat >"${TMP}/apps/sub/anidada.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Anidada
Exec=anidada
EOF

SALIDA="$(TITAN_CONFIG="${CONFIG}" QT_QPA_PLATFORM=offscreen \
  "${PANEL}" --listar-apps "${TMP}/apps" 2>"${TMP}/err")"
ESTADO=$?
[[ ${ESTADO} -eq 0 ]] && ok "el catalogo termina con exito" \
  || mal "el catalogo termino con ${ESTADO}: $(cat "${TMP}/err")"

[[ "$(printf '%s\n' "${SALIDA}" | wc -l)" -eq 3 ]] \
  && ok "se listan las tres entradas visibles" \
  || mal "numero de entradas inesperado: ${SALIDA}"

grep -q '^uno.desktop|Editor en espanol|test-icon|prueba --flag|0|prueba$' \
  <<<"${SALIDA}" \
  && ok "Name[es], Exec sin %U y StartupWMClass" \
  || mal "no se interpreto bien uno.desktop: ${SALIDA}"

grep -q '^terminal.desktop|Terminal de prueba|.*|htop|1|' <<<"${SALIDA}" \
  && ok "Terminal=true conserva el ejecutable" \
  || mal "no se interpreto bien terminal.desktop: ${SALIDA}"

grep -q '^sub-anidada.desktop|Anidada|' <<<"${SALIDA}" \
  && ok "el id de un .desktop anidado usa guiones" \
  || mal "no se encontro la entrada anidada: ${SALIDA}"

! grep -q 'oculta.desktop\|sin-programa.desktop' <<<"${SALIDA}" \
  && ok "NoDisplay y TryExec se filtran" \
  || mal "aparecen entradas que deberian estar ocultas"

COMPROBAR="$(TITAN_CONFIG="${CONFIG}" QT_QPA_PLATFORM=offscreen \
  "${PANEL}" --comprobar 2>"${TMP}/err2")"
[[ $? -eq 0 ]] && ok "titan-panel --comprobar arranca sin grafico" \
  || mal "fallo --comprobar: $(cat "${TMP}/err2")"
for clave in 'barra_alto=56' 'inicio=Inicio' 'centro=900x620' 'columnas=5' \
             'tareas=icono' 'inicio_estilo=icono' \
             'barra_orden=inicio,terminal,archivos,tareas,reloj' \
             'anclada_terminal=kitty' 'anclada_archivos=pcmanfm-qt' \
             'apagar=systemctl poweroff' 'reiniciar=systemctl reboot'; do
  grep -qx "${clave}" <<<"${COMPROBAR}" \
    && ok "--comprobar incluye ${clave}" \
    || mal "falta ${clave} en --comprobar: ${COMPROBAR}"
done

TITAN_CONFIG="${CONFIG}" QT_QPA_PLATFORM=offscreen \
  "${PANEL}" --captura "${TMP}/barra.png" >/dev/null 2>&1
[[ -s "${TMP}/barra.png" ]] && file "${TMP}/barra.png" | grep -q '1280 x 56' \
  && ok "la barra se pinta a 1280x56" \
  || mal "no se pudo pintar la barra"

TITAN_CONFIG="${CONFIG}" QT_QPA_PLATFORM=offscreen \
  "${PANEL}" --captura "${TMP}/centro.png" --centro >/dev/null 2>&1
[[ -s "${TMP}/centro.png" ]] \
  && file "${TMP}/centro.png" | grep -q '1280 x 720' \
  && ok "el centro se pinta a 1280x720" \
  || mal "no se pudo pintar el centro"

if [[ ${fallos} -ne 0 ]]; then
  echo "titan-panel: ${fallos} fallo(s)" >&2
  exit 1
fi
echo "titan-panel: todo correcto"
