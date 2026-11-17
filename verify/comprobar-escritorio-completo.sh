#!/usr/bin/env bash
# ==============================================================================
# Inti OS - comprueba lo que se anadio para estar a la altura de Ubuntu/Fedora:
# polkit, llavero, bloqueo seguro, inactividad, capturas, compartir pantalla,
# impresion, cortafuegos, puntos de restauracion, VPN, Plymouth, Secure Boot,
# accesibilidad, metodos de entrada y el instalador (cifrado, junto a Windows).
#
# Sin root y sin arrancar nada: paquetes, scripts (sintaxis, permisos en
# profiledef.sh, que esten en git), configuraciones y lo que el codigo tiene
# que hacer. La parte grafica se prueba aparte (Wayfire sin pantalla).
#
#   verify/comprobar-escritorio-completo.sh
# ==============================================================================
set -uo pipefail

cd "$(dirname "$0")/.."
RAIZ="iso/titan/airootfs"
BIN="${RAIZ}/usr/local/bin"

ROJO='\033[0;31m'; VERDE='\033[0;32m'; AMARILLO='\033[0;33m'; AZUL='\033[0;34m'; SC='\033[0m'
fallos=0; exitos=0; avisos=0
ok()    { echo -e "[ ${VERDE}OK${SC} ] $1"; exitos=$((exitos + 1)); }
fallo() { echo -e "[ ${ROJO}FALLO${SC} ] $1"; fallos=$((fallos + 1)); }
aviso() { echo -e "[ ${AMARILLO}AVISO${SC} ] $1"; avisos=$((avisos + 1)); }
contiene() {   # contiene FICHERO PATRON DESCRIPCION
    if grep -qE -- "$2" "$1" 2>/dev/null; then ok "$3"; else fallo "$3 (no se encuentra '$2' en $1)"; fi
}
no_contiene() {
    if grep -qE -- "$2" "$1" 2>/dev/null; then fallo "$3 ('$2' sigue en $1)"; else ok "$3"; fi
}

echo -e "${AZUL}=== ESCRITORIO COMPLETO: comprobaciones ===${SC}"

# ------------------------------------------------------------------ paquetes
echo -e "${AZUL}--- Paquetes${SC}"
paquetes=(polkit-qt6 gnome-keyring libsecret xdg-desktop-portal-wlr xdg-desktop-portal-gtk
          grim slurp wl-clipboard libnotify gtklock gtklock-userinfo-module
          gtklock-powerbar-module gtklock-playerctl-module swayidle wlopm playerctl
          cups cups-pk-helper cups-browsed cups-filters system-config-printer ipp-usb
          sane sane-airscan simple-scan avahi nss-mdns ntfs-3g exfatprogs gvfs gvfs-mtp
          gvfs-smb gnome-disk-utility smartmontools power-profiles-daemon upower ufw
          snapper snap-pac grub-btrfs inotify-tools btrfs-assistant timeshift noto-fonts
          noto-fonts-cjk xdg-user-dirs networkmanager-openvpn networkmanager-openconnect
          wireguard-tools modemmanager usb_modeswitch gst-libav gst-plugins-ugly sbctl
          plymouth orca speech-dispatcher espeak-ng fcitx5 fcitx5-qt fcitx5-gtk
          fcitx5-configtool fcitx5-chinese-addons fcitx5-mozc fcitx5-hangul hunspell
          hunspell-es_any hunspell-en_us fprintd bolt pacman-contrib cryptsetup os-prober
          efibootmgr parted wlsunset sound-theme-freedesktop wlr-randr brightnessctl)
faltan=()
for p in "${paquetes[@]}"; do
    grep -qxF "$p" iso/titan/packages.x86_64 || faltan+=("$p")
done
if ((${#faltan[@]} == 0)); then ok "packages.x86_64 lleva los ${#paquetes[@]} paquetes"; else fallo "faltan en packages.x86_64: ${faltan[*]}"; fi

# Que existan en los repositorios de la ISO (core/extra/cachyos), si se puede mirar.
if lista=$(pacman -Sl core extra 2>/dev/null) && [[ -n "$lista" ]]; then
    desconocidos=()
    for p in "${paquetes[@]}"; do
        grep -qE "^[a-z-]+ ${p//+/\\+} " <<<"$lista" || desconocidos+=("$p")
    done
    if ((${#desconocidos[@]} == 0)); then ok "todos estan en Arch core/extra"
    else fallo "no estan en core/extra: ${desconocidos[*]}"; fi
else
    aviso "sin pacman -Sl: no se comprueba que los paquetes existan en los repositorios"
fi

# ------------------------------------------------------------------ scripts
echo -e "${AZUL}--- Scripts de usr/local/bin${SC}"
scripts=(titan-bloquear titan-bloquear-avisar titan-inactividad titan-captura
         titan-elegir-pantalla titan-cortafuegos titan-actualizaciones titan-arranque-seguro
         titan-huella titan-instantaneas titan-lector titan-sesion
         titan-pantallas titan-luz-nocturna titan-acento)
for s in "${scripts[@]}"; do
    f="${BIN}/${s}"
    if [[ ! -f "$f" ]]; then fallo "${s}: no existe"; continue; fi
    interprete=$(head -1 "$f")
    case "$interprete" in
        *bash*) comprobador=(bash -n) ;;
        *) comprobador=(sh -n) ;;
    esac
    if ! error=$("${comprobador[@]}" "$f" 2>&1); then fallo "${s}: error de sintaxis: ${error}"; continue; fi
    [[ -x "$f" ]] || { fallo "${s}: no es ejecutable"; continue; }
    grep -qE "\[\"/usr/local/bin/${s}\"\]=\"0:0:755\"" iso/titan/profiledef.sh || { fallo "${s}: falta en profiledef.sh con 0:0:755"; continue; }
    if git check-ignore -q "$f"; then fallo "${s}: .gitignore lo ignora (no llegaria al repositorio)"; continue; fi
    ok "${s}: sintaxis, permisos, profiledef.sh y git"
done
grep -qE '\["/usr/local/bin/titan-polkit"\]="0:0:755"' iso/titan/profiledef.sh \
    && ok "titan-polkit en profiledef.sh" || fallo "titan-polkit no esta en profiledef.sh"

if command -v shellcheck >/dev/null 2>&1; then
    errores=$(cd "$BIN" && shellcheck -S error "${scripts[@]}" 2>&1)
    if [[ -z "$errores" ]]; then ok "shellcheck: sin errores"; else fallo "shellcheck:\n${errores}"; fi
else
    aviso "shellcheck no esta instalado"
fi

# Nada de ficheros temporales con nombre fijo en /tmp (ataques con enlaces).
if grep -nE '/tmp/[A-Za-z._-]+\$\$' "${BIN}"/titan-* >/dev/null 2>&1; then
    fallo "algun script usa /tmp/nombre.\$\$: $(grep -lE '/tmp/[A-Za-z._-]+\$\$' "${BIN}"/titan-* | xargs -n1 basename | tr '\n' ' ')"
else
    ok "los scripts no usan ficheros temporales predecibles en /tmp"
fi

# ------------------------------------------------------------------ bloqueo e inactividad
echo -e "${AZUL}--- Bloqueo, inactividad y capturas${SC}"
for f in config.ini diseno.ui estilo.css; do
    [[ -s "${RAIZ}/usr/share/titan/gtklock/${f}" ]] && ok "gtklock/${f}" || fallo "falta usr/share/titan/gtklock/${f}"
done
command -v xmllint >/dev/null 2>&1 && {
    xmllint --noout "${RAIZ}/usr/share/titan/gtklock/diseno.ui" 2>/dev/null && ok "diseno.ui es XML valido" || fallo "diseno.ui no es XML valido"
}
contiene "${RAIZ}/usr/share/titan/gtklock/config.ini" '^\[userinfo\]' "gtklock: opciones del modulo de usuario en su grupo"
contiene "${BIN}/titan-bloquear" -- '--daemonize' "titan-bloquear usa --daemonize (no -d, que es ambiguo)"
contiene "${BIN}/titan-bloquear" '/run/archiso' "titan-bloquear no bloquea el live (sin contrasena)"
contiene "${BIN}/titan-inactividad" 'before-sleep' "titan-inactividad bloquea antes de suspender"
contiene "${BIN}/titan-inactividad" 'swayidle -w' "titan-inactividad espera al bloqueo (-w)"
WF="${RAIZ}/etc/skel/.config/wayfire.ini"
# La lista de plugins sigue en varias lineas (terminadas en '\').
if awk '/^plugins *=/{dentro=1} dentro{print; if ($0 !~ /\\$/) exit}' "$WF" | grep -qw 'session-lock'; then
    ok "wayfire.ini carga session-lock (ext-session-lock)"
else
    fallo "wayfire.ini no carga el plugin session-lock"
fi
contiene "$WF" 'titan-bloquear' "wayfire.ini: Super+L con titan-bloquear"
contiene "$WF" 'titan-captura' "wayfire.ini: atajos de captura"
contiene "$WF" 'KEY_SYSRQ' "wayfire.ini: tecla Impr Pant"
contiene "$WF" 'titan-lector' "wayfire.ini: Super+Alt+S (lector de pantalla)"
LB="${RAIZ}/etc/skel/.config/labwc/rc.xml"
command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$LB" 2>/dev/null && ok "labwc rc.xml es XML valido" || fallo "labwc rc.xml no es XML valido"; }
contiene "$LB" 'titan-captura' "labwc: atajos de captura"
contiene "$LB" 'titan-bloquear' "labwc: Super+L con titan-bloquear"
contiene "${BIN}/titan-sesion" 'titan-polkit' "la sesion arranca el agente de polkit"
contiene "${BIN}/titan-sesion" 'titan-inactividad' "la sesion arranca titan-inactividad"
contiene "${BIN}/titan-sesion" 'xdg-desktop-autostart.target' "la sesion procesa /etc/xdg/autostart"
contiene "${BIN}/titan-sesion" -- '--systemd' "la sesion exporta el entorno a systemd (portales)"

# ------------------------------------------------------------------ portales y polkit
echo -e "${AZUL}--- Portales y polkit${SC}"
PC="${RAIZ}/usr/share/xdg-desktop-portal/titan-portals.conf"
contiene "$PC" 'org.freedesktop.impl.portal.ScreenCast=wlr' "compartir pantalla con xdg-desktop-portal-wlr"
contiene "$PC" 'org.freedesktop.impl.portal.Secret=gnome-keyring' "portal de secretos con gnome-keyring"
contiene "${RAIZ}/etc/xdg/xdg-desktop-portal-wlr/config" 'titan-elegir-pantalla' "eleccion de pantalla para compartir"
POL="${RAIZ}/usr/share/polkit-1/actions/org.intios.sistema.policy"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$POL" 2>/dev/null && ok "politica de polkit es XML valido" || fallo "politica de polkit no es XML valido"
fi
for a in cortafuegos huella arranque-seguro instantaneas; do
    contiene "$POL" "org.intios.${a}\"" "accion de polkit org.intios.${a}"
done
contiene "${RAIZ}/etc/polkit-1/rules.d/49-titan-live.rules" 'isInGroup\("wheel"\)' "regla de polkit del live"
contiene apps/titan-installer/src/InstallerBackend.cpp '49-titan-live.rules' "el instalador quita la regla de polkit del live"
contiene Makefile '^apps/titan-polkit:' "Makefile compila titan-polkit"
contiene scripts/build-iso.sh 'build_qt_app titan-polkit' "build-iso.sh compila titan-polkit"

# ------------------------------------------------------------------ servicios y PAM
echo -e "${AZUL}--- Servicios, llavero, mDNS, Plymouth${SC}"
CU="${RAIZ}/root/customize_airootfs.sh"
bash -n "$CU" && ok "customize_airootfs.sh: sintaxis" || fallo "customize_airootfs.sh: error de sintaxis"
for u in cups.socket avahi-daemon.service power-profiles-daemon.service ModemManager.service ufw.service titan-cortafuegos.service; do
    contiene "$CU" "$u" "se activa ${u}"
done
no_contiene "$CU" 'titan-cortafuegos.service grub-btrfsd' "grub-btrfsd no se activa en el live (no tiene btrfs)"
contiene "$CU" 'gnome-keyring-daemon.socket' "llavero por usuario (socket)"
contiene "$CU" 'pam_gnome_keyring' "PAM abre el llavero al entrar"
contiene "$CU" 'mdns_minimal' "nss-mdns para impresoras y equipos .local"
contiene "$CU" 'Theme=titan' "tema de Plymouth"
contiene "$CU" 'titan-actualizaciones.timer' "aviso de actualizaciones"
contiene "${RAIZ}/etc/systemd/system/titan-cortafuegos.service" 'ConditionPathExists=!' "el cortafuegos inicial solo se pone una vez"
contiene "${RAIZ}/etc/systemd/user/titan-actualizaciones.timer" 'OnUnitActiveSec' "temporizador de actualizaciones periodico"
for f in org.fcitx.Fcitx5.desktop spice-vdagent.desktop; do
    contiene "${RAIZ}/etc/skel/.config/autostart/${f}" '^Hidden=true' "autostart ${f} oculto (se arranca a demanda)"
done

# ------------------------------------------------------------------ titan-shell
echo -e "${AZUL}--- titan-shell${SC}"
SB=apps/titan-shell/src/ShellBackend.cpp
if awk '/^bool ShellBackend::isLiveSystem/,/^}/' "$SB" | grep -v '^ *//' | grep -q 'titan-build.env'; then
    fallo "isLiveSystem() mira /etc/titan-build.env: en el sistema instalado el bloqueo aceptaria cualquier contrasena"
else
    ok "isLiveSystem() solo mira /run/archiso"
fi
contiene "$SB" 'titan-bloquear' "lockScreen() usa el bloqueo seguro"
contiene "$SB" 'emit ActionInvoked' "notificaciones con botones (ActionInvoked)"
contiene "$SB" 'emit NotificationClosed' "notificaciones: NotificationClosed"
[[ -f apps/titan-shell/src/Mpris.cpp ]] && ok "MPRIS en la Isla Dinamica" || fallo "falta apps/titan-shell/src/Mpris.cpp"
contiene apps/titan-shell/titan-shell.pro 'Mpris.cpp' "Mpris.cpp se compila"

# ------------------------------------------------------------------ titan-settings
echo -e "${AZUL}--- titan-settings${SC}"
for v in EnergiaView BloqueoView SeguridadView AccesibilidadView TecladoView ImpresorasView RestaurarView VpnView AlmacenamientoView; do
    if [[ -f "apps/titan-settings/qml/${v}.qml" ]] && grep -q "qml/${v}.qml" apps/titan-settings/resources.qrc; then
        ok "Ajustes: ${v}"
    else
        fallo "Ajustes: falta ${v}.qml o no esta en resources.qrc"
    fi
done
contiene apps/titan-settings/src/main.cpp '"--seccion"' "titan-settings acepta '--seccion X'"

# ------------------------------------------------------------------ preferencias del escritorio
echo -e "${AZUL}--- Ajustes con datos reales (Dock, barra, acento, usuarios, redes)${SC}"
for f in TitanPrefs.h TitanPrefs.cpp; do
    [[ -f apps/titan-common/$f ]] && ok "titan-common/$f" || fallo "falta apps/titan-common/$f"
done
for app in titan-shell titan-settings; do
    contiene apps/$app/$app.pro 'TitanPrefs.cpp' "$app compila TitanPrefs (shell.conf compartido)"
done
contiene apps/titan-shell/src/main.cpp 'Dock/posicion' "el shell reancla el Dock (abajo/izquierda/derecha)"
contiene apps/titan-shell/src/main.cpp 'Barra/visible' "el shell oculta la barra de menus si se pide"
contiene apps/titan-shell/qml/Dock.qml 'Dock/tamano' "Dock: tamano de iconos"
contiene apps/titan-shell/qml/Dock.qml 'Dock/ocultarAuto' "Dock: ocultar automaticamente"
contiene apps/titan-shell/qml/TopBar.qml 'Barra/estilo' "barra de menus: transparente/vidrio/solida"
contiene apps/titan-shell/qml/ControlCenter.qml 'noMolestar' "Centro de control: No molestar"
contiene apps/titan-shell/src/ShellBackend.cpp 'noMolestarActivo' "notificaciones: No molestar y Concentracion"
contiene apps/titan-shell/src/ShellBackend.cpp 'Notificaciones/apps/' "notificaciones: permiso por app"
for v in PantallasView SonidoView EscritorioDockView BarraMenusView CentroControlView NotificacionesView ConcentracionView UsuariosView Campo Deslizador Desplegable; do
    if [[ -f "apps/titan-settings/qml/${v}.qml" ]] && grep -q "qml/${v}.qml" apps/titan-settings/resources.qrc; then
        ok "Ajustes: ${v}"
    else
        fallo "Ajustes: falta ${v}.qml o no esta en resources.qrc"
    fi
done
# Ninguna seccion de la barra lateral cae ya en la pagina de relleno.
for sec in "Pantallas" "Sonido" "Escritorio y Dock" "Barra de menús" "Centro de control" "Notificaciones" "Concentración" "Usuarios y grupos"; do
    contiene apps/titan-settings/qml/SettingsWindow.qml "\"${sec}\": " "Ajustes: seccion real '${sec}'"
done
H=apps/titan-greeter/helper/main.cpp
contiene "$H" 'cambiar-mi-clave' "usuarios: cada persona cambia su contrasena (sin ser admin)"
contiene "$H" 'SO_PEERCRED' "usuarios: cambiar-mi-clave comprueba quien pregunta (SO_PEERCRED)"
contiene "$H" 'borrar-usuario' "usuarios: un administrador puede borrar cuentas"
contiene "$H" 'No puedes borrar tu propia cuenta' "usuarios: nadie borra su propia cuenta"
C=apps/titan-settings/src/Conexiones.cpp
contiene "$C" 'connection", "edit"|QStringLiteral\("edit"\)' "Wi-Fi: la contrasena va por stdin (no en la lista de procesos)"
contiene "$C" '"delete"' "Wi-Fi: olvidar red"
contiene "$C" '"trust"' "Bluetooth: confiar al emparejar (se reconecta solo)"
contiene "$C" '"remove"' "Bluetooth: olvidar dispositivo"
contiene apps/titan-common/ThemeManager.cpp 'titan-acento' "el acento llega a GTK/kitty/bloqueo (titan-acento)"
contiene apps/titan-common/ThemeManager.cpp 'QPalette::Highlight' "el acento colorea la seleccion de Qt"
for v in gtk-3.0 gtk-4.0; do
    contiene "${RAIZ}/etc/skel/.config/$v/gtk.css" 'titan-acento.css' "$v importa el acento"
    [[ -s "${RAIZ}/etc/skel/.config/$v/titan-acento.css" ]] && ok "$v/titan-acento.css por defecto" || fallo "falta skel $v/titan-acento.css"
done
contiene "${RAIZ}/etc/xdg/kitty/kitty.conf" 'kitty-acento.conf' "kitty incluye el acento"
contiene "${BIN}/titan-bloquear" 'accent=' "pantalla de bloqueo con el acento"
contiene "${BIN}/titan-sesion" 'titan-pantallas' "la sesion aplica las pantallas guardadas"
contiene "${BIN}/titan-sesion" 'titan-luz-nocturna' "la sesion arranca la luz nocturna"
contiene "${BIN}/titan-sesion" 'titan-acento' "la sesion aplica el acento"
# Sin azules fijos en lo que tiene que seguir al acento.
azules=$(grep -rnoE '"#(0071e3|0a84ff|007aff)"' apps/titan-finder/qml apps/titan-settings/qml/{Wallpaper,General,Wifi,Bluetooth}View.qml apps/titan-shell/qml/Dock.qml apps/titan-shell/qml/WallpaperPicker.qml 2>/dev/null)
[[ -z "$azules" ]] && ok "Finder, Ajustes y Dock usan el acento (sin azules fijos)" || fallo "azules fijos: $azules"

# ------------------------------------------------------------------ instalador
echo -e "${AZUL}--- Instalador${SC}"
IB=apps/titan-installer/src/InstallerBackend.cpp
contiene "$IB" 'GRUB_DISABLE_OS_PROBER=false' "os-prober: Windows aparece en GRUB"
contiene "$IB" 'luksFormat' "cifrado LUKS"
contiene "$IB" -- '--key-file=-' "la clave de cifrado va por stdin (no en la lista de procesos)"
contiene "$IB" 'cryptdevice=UUID=' "cryptdevice por UUID"
contiene "$IB" '"encrypt"' "hook encrypt"
contiene "$IB" '"plymouth"' "hook plymouth"
contiene "$IB" 'splash' "parametro splash"
contiene "$IB" 'console=ttyS0,115200n8 console=tty0' "console=tty0 la ultima (Plymouth)"
no_contiene "$IB" 'search --no-floppy --file /etc/os-release' "GRUB ya no busca /etc/os-release (podia arrancar otro Linux)"
contiene "$IB" 'search --no-floppy --fs-uuid' "GRUB busca el arranque por UUID"
contiene "$IB" 'LC_ALL"\), QStringLiteral\("C"\)' "parted se lee en ingles (LC_ALL=C)"
contiene "$IB" 'formatearEsp' "junto a Windows no se formatea la ESP"
contiene "$IB" 'snapper' "snapper en btrfs"
contiene "$IB" 'grub-btrfs-overlayfs' "arrancar instantaneas (overlayfs)"
no_contiene "$IB" 'EFI/BOOT/" \+ e.kernel' "los kernels ya no se copian a la ESP"

# ------------------------------------------------------------------ binarios ISA
if [[ -x scripts/fijar-isa-baseline.py ]] || [[ -f scripts/fijar-isa-baseline.py ]]; then
    elfs=()
    for f in "${BIN}"/*; do
        [[ -f "$f" ]] && head -c4 "$f" 2>/dev/null | grep -q 'ELF' && elfs+=("$f")
    done
    if ((${#elfs[@]})); then
        if python3 scripts/fijar-isa-baseline.py --comprobar "${elfs[@]}" >/dev/null 2>&1; then
            ok "binarios de usr/local/bin: nivel ISA x86-64 baseline (${#elfs[@]})"
        else
            fallo "algun binario de usr/local/bin pide mas que x86-64 baseline (scripts/fijar-isa-baseline.py)"
        fi
    fi
fi

echo
echo -e "${AZUL}=== RESUMEN ===${SC}"
echo "Correctas: ${exitos}   Avisos: ${avisos}   Fallos: ${fallos}"
((fallos == 0))
