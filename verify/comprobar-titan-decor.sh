#!/bin/bash
# Checks the titan-decor Wayfire plugin (Titan bar with traffic lights):
#  - every option the code reads ("titan-decor/...") exists in its XML
#    (if one is missing, Wayfire fails when loading the plugin);
#  - wayfire.ini loads it instead of Wayfire's "decoration" (two bars);
#  - kitty hides its own bar only in Wayfire.
# Usage: ./verify/comprobar-titan-decor.sh

set -u
raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fuentes="${raiz}/apps/wayfire-titan/titan-decor"
xml="${raiz}/iso/titan/airootfs/usr/share/wayfire/metadata/titan-decor.xml"
ini="${raiz}/iso/titan/airootfs/etc/skel/.config/wayfire.ini"
perfil="${raiz}/iso/titan/airootfs/etc/profile.d/15-titan-grafico.sh"
kitty="${raiz}/iso/titan/airootfs/etc/xdg/kitty/kitty.conf"
fallos=0
ok()    { printf 'OK    %s\n' "$*"; }
fallo() { printf 'FALLO %s\n' "$*"; fallos=$((fallos + 1)); }

if xmllint --noout "${xml}" 2>/dev/null; then ok "titan-decor.xml is valid XML"; else fallo "titan-decor.xml is not valid"; fi
grep -q '<plugin name="titan-decor">' "${xml}" && ok "the XML declares the titan-decor plugin" || fallo "the XML doesn't declare <plugin name=\"titan-decor\">"

for opcion in $(grep -ohE '"titan-decor/[a-z_]+"' "${fuentes}"/*.cpp "${fuentes}"/*.hpp | tr -d '"' | sed 's|titan-decor/||' | sort -u); do
  if grep -q "<option name=\"${opcion}\"" "${xml}"; then
    ok "option ${opcion} in the XML"
  else
    fallo "the code reads titan-decor/${opcion} but it isn't in the XML"
  fi
done
grep -q '"decoration/' "${fuentes}"/*.cpp "${fuentes}"/*.hpp && fallo "the code still reads options from \"decoration/\"" || ok "doesn't read Wayfire's decoration options"

lista="$(sed -n '/^plugins *=/,/^[^ ]/p' "${ini}")"
grep -qw 'titan-decor' <<<"${lista}" && ok "wayfire.ini loads titan-decor" || fallo "wayfire.ini doesn't load titan-decor"
grep -qE '^\s+decoration\s*\\?$' <<<"${lista}" && fallo "wayfire.ini still loads decoration (there would be two bars)" || ok "wayfire.ini doesn't load decoration"
grep -q 'forced_views = app_id is "kitty"' "${ini}" && ok "titan-decor decorates kitty" || fallo "missing forced_views for kitty"

grep -q 'KITTY_CONF_DECORACION="hide_window_decorations yes"' "${perfil}" && ok "Wayfire session hides kitty's bar" || fallo "15-titan-grafico.sh doesn't export KITTY_CONF_DECORACION"
grep -q '^envinclude KITTY_CONF_\*' "${kitty}" && ok "kitty.conf applies KITTY_CONF_*" || fallo "kitty.conf lacks envinclude KITTY_CONF_*"
grep -q '^hide_window_decorations' "${kitty}" && fallo "kitty.conf hides the bar always (in labwc it would have none)" || ok "kitty.conf doesn't hide the bar in labwc"

echo "---"
if [ "${fallos}" -eq 0 ]; then echo "comprobar-titan-decor: 0 FALLO"; exit 0; fi
echo "comprobar-titan-decor: ${fallos} FALLO"; exit 1
