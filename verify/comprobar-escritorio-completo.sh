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
# build-iso.sh corre como root (sudo) y el repositorio es del usuario: git se
# niega a leer un repositorio de otro dueño ("dubious ownership") y las
# comprobaciones con git fallarían, o peor, pasarían sin mirar nada.
git() { command git -c safe.directory="$PWD" "$@"; }
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
          efibootmgr parted wlsunset sound-theme-freedesktop wlr-randr brightnessctl
          nvidia-open-dkms dkms linux-headers gnome-text-editor zip 7zip unrar file-roller
          gparted xorg-xhost wf-recorder wtype apparmor
          openboard xournalpp libreoffice-fresh libreoffice-fresh-es pdfarranger obs-studio
          kdenlive auto-multiple-choice joplin-desktop obsidian anki calibre kalzium kstars
          kmplot kig geogebra stellarium gcompris-qt gutenprint foomatic-db
          foomatic-db-engine foomatic-db-ppds hplip switcheroo-control qemu-guest-agent
          firefox-i18n-es-es firefox-i18n-es-mx ttf-carlito ttf-caladea
          thunderbird thunderbird-i18n-es-es snapshot wayvnc)
faltan=()
for p in "${paquetes[@]}"; do
    grep -qxF "$p" iso/titan/packages.x86_64 || faltan+=("$p")
done
if ((${#faltan[@]} == 0)); then ok "packages.x86_64 lleva los ${#paquetes[@]} paquetes"; else fallo "faltan en packages.x86_64: ${faltan[*]}"; fi

# Que existan en los repositorios de la ISO (core/extra/cachyos), si se puede mirar.
if lista=$(pacman -Sl core extra cachyos 2>/dev/null) && [[ -n "$lista" ]]; then
    desconocidos=()
    for p in "${paquetes[@]}"; do
        grep -qE "^[a-z-]+ ${p//+/\\+} " <<<"$lista" || desconocidos+=("$p")
    done
    if ((${#desconocidos[@]} == 0)); then ok "todos estan en Arch core/extra"
    else fallo "no estan en core/extra/cachyos: ${desconocidos[*]}"; fi
else
    aviso "sin pacman -Sl: no se comprueba que los paquetes existan en los repositorios"
fi

# ------------------------------------------------------------------ scripts
echo -e "${AZUL}--- Scripts de usr/local/bin${SC}"
scripts=(titan-bloquear titan-bloquear-avisar titan-inactividad titan-captura
         titan-elegir-pantalla titan-cortafuegos titan-actualizaciones titan-arranque-seguro
         titan-huella titan-instantaneas titan-lector titan-sesion
         titan-pantallas titan-luz-nocturna titan-acento titan-grabar)
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

# ------------------------------------------------------------------ comparacion 2026-11-18
echo -e "${AZUL}--- Lo que faltaba frente a Ubuntu/Fedora (2026-11-18)${SC}"
P=iso/titan/packages.x86_64
no_contiene "$P" '^nvidia-open$' "NVIDIA por DKMS (nvidia-open a secas solo vale para el kernel de Arch)"
contiene scripts/build-iso.sh 'extra_packages\+=\(linux-titanlinux-headers\)' "cabeceras del kernel propio en la ISO (DKMS)"
contiene scripts/build-iso.sh 'args\+=\(-p "\$\{extra_packages\[\*\]\}"\)' "mkarchiso -p recibe todos los paquetes en un argumento"
contiene "${RAIZ}/root/instalador/paso-base.sh" 'nvidia-open-dkms' "instalador de consola: NVIDIA por DKMS"
contiene "${RAIZ}/root/instalador/paso-base.sh" 'cabeceras/linux-titanlinux-headers' "instalador de consola: instala las cabeceras del kernel propio"
M="${RAIZ}/etc/xdg/mimeapps.list"
contiene "$M" '^text/plain=org.gnome.TextEditor.desktop' "los .txt se abren en el Editor de texto (no en vim)"
contiene "$M" '^application/zip=org.gnome.FileRoller.desktop' "los .zip se abren en File Roller"
F=apps/titan-finder
contiene "$F/src/Operaciones.cpp" 'void FinderBackend::comprimir' "Finder: Comprimir"
contiene "$F/src/Operaciones.cpp" 'void FinderBackend::extraer' "Finder: Extraer aquí"
contiene "$F/qml/FileList.qml" 'var accion = fila.modelData.a' "Finder: las opciones del menú se ejecutan (antes se perdían al cerrarlo)"
contiene "${RAIZ}/etc/skel/.config/wayfire.ini" 'command_grabar = titan-grabar' "Super+Mayús+5 graba la pantalla (Wayfire)"
contiene "${RAIZ}/etc/skel/.config/labwc/rc.xml" 'titan-grabar' "Super+Mayús+5 graba la pantalla (labwc)"
[[ -f "${RAIZ}/usr/share/applications/titan-grabar.desktop" ]] && ok "lanzador Grabar pantalla" || fallo "falta titan-grabar.desktop"
T=apps/titan-teclado
[[ -f "$T/titan-teclado.pro" && -f "$T/qml/Teclado.qml" ]] && ok "titan-teclado (teclado en pantalla)" || fallo "falta apps/titan-teclado"
contiene "$T/src/main.cpp" 'KeyboardInteractivityNone' "el teclado en pantalla no quita el foco a la app"
contiene scripts/build-iso.sh 'build_qt_app titan-teclado' "build-iso compila titan-teclado"
grep -qE '\["/usr/local/bin/titan-teclado"\]="0:0:755"' iso/titan/profiledef.sh && ok "titan-teclado en profiledef.sh" || fallo "titan-teclado no esta en profiledef.sh"
contiene apps/titan-settings/qml/AccesibilidadView.qml 'setTecladoPantalla' "Ajustes > Accesibilidad: interruptor del teclado en pantalla"
contiene "${BIN}/titan-sesion" 'TECLADO=1' "el teclado en pantalla se recuerda al iniciar sesión"
LSM='lsm=landlock,lockdown,yama,integrity,apparmor,bpf'
contiene apps/titan-installer/src/InstallerBackend.cpp "GRUB_CMDLINE_LINUX=.*${LSM}" "AppArmor activo en el sistema instalado (GRUB)"
contiene iso/titan/grub/grub.cfg "$LSM" "AppArmor activo en el live (GRUB)"
contiene iso/titan/syslinux/syslinux-linux.cfg "$LSM" "AppArmor activo en el live (syslinux)"
contiene kernel/linux-titanlinux/config.x86_64 '^CONFIG_SECURITY_APPARMOR=y' "el kernel propio trae AppArmor"
contiene "${RAIZ}/root/customize_airootfs.sh" 'apparmor.service systemd-oomd.service' "servicios apparmor y systemd-oomd activados"
contiene "${RAIZ}/etc/systemd/system/user@.service.d/10-titan-oomd.conf" 'ManagedOOMMemoryPressure=kill' "systemd-oomd vigila la sesión del usuario"
no_contiene iso/titan/grub/grub.cfg 'Titan Linux' "menú de arranque con el nombre Inti OS (GRUB)"
no_contiene iso/titan/syslinux/syslinux-linux.cfg 'Titan Linux' "menú de arranque con el nombre Inti OS (syslinux)"

# ------------------------------------------------------------------ tienda: Discover
echo -e "${AZUL}--- App Store: Discover (2026-11-18)${SC}"
contiene "$P" '^discover$' "Discover en la ISO"
no_contiene "$P" '^gnome-software$' "GNOME Software fuera (una sola tienda)"
no_contiene "$P" '^packagekit-qt6$' "sin packagekit-qt6 (Discover no gestiona los paquetes de Arch)"
DW="${BIN}/plasma-discover"
if [[ -x "$DW" ]] && sh -n "$DW" && grep -qE '\["/usr/local/bin/plasma-discover"\]="0:0:755"' iso/titan/profiledef.sh && ! git check-ignore -q "$DW"; then
    ok "envoltorio plasma-discover: sintaxis, permisos, profiledef.sh y git"
else
    fallo "envoltorio plasma-discover (sintaxis, permisos, profiledef.sh o .gitignore)"
fi
contiene "$DW" 'flatpak-backend,fwupd-backend' "Discover solo con Flatpak y firmware"
contiene "$DW" 'QT_QPA_PLATFORMTHEME=gtk3' "Discover sigue el modo claro/oscuro"
contiene apps/titan-common/ThemeManager.cpp 'glib-2.0/settings' "el cambio de modo llega a Discover (iconos breeze/breeze-dark)"
contiene apps/titan-shell/src/DockModel.cpp 'QStringLiteral\("plasma-discover"\)\);' "el Dock abre Discover"
contiene apps/titan-shell/src/DockModel.cpp 'org.gnome.Software' "un Dock guardado con GNOME Software pasa a Discover"
contiene apps/titan-shell/src/LauncherBackend.cpp '"plasma-discover"' "el lanzador abre Discover"
no_contiene apps/titan-shell/src/LauncherBackend.cpp '"gnome-software"' "el lanzador ya no abre GNOME Software"
contiene "${RAIZ}/root/customize_airootfs.sh" 'org.kde.discover.desktop' "Discover se llama App Store en el menú"
contiene "${RAIZ}/etc/profile.d/15-titan-grafico.sh" '\. /etc/profile.d/flatpak.sh' "la sesión ve las apps Flatpak (Lanzar, menú, Abrir con)"

# ------------------------------------------------------------------ bloqueo e isla
echo -e "${AZUL}--- Notificaciones en el bloqueo e Isla Dinámica (2026-11-18)${SC}"
SH=apps/titan-shell
contiene "$SH/qml/LockScreen.qml" 'AvisosBloqueo' "bloqueo QML (live): música y notificaciones"
contiene "$SH/qml/LockScreen.qml" 'oculto: lockScreenRoot.panelUsuarios \|\| lockScreenRoot.confirmarCambio' "al cambiar de usuario se ocultan los avisos"
contiene "$SH/qml/AvisosBloqueo.qml" 'tarjetasQueCaben' "las que no caben hasta el perfil se acoplan en iconos"
contiene "$SH/resources.qrc" 'qml/AvisosBloqueo.qml' "AvisosBloqueo.qml en el qrc"
contiene "$SH/resources.qrc" 'qml/Caratula.qml' "Caratula.qml en el qrc"
contiene "$SH/resources.qrc" 'qml/BotonMedio.qml' "BotonMedio.qml en el qrc"
contiene "$SH/src/ShellBackend.cpp" 'titan-avisos-bloqueo' "el shell pasa los avisos al bloqueo seguro"
contiene "$SH/src/ShellBackend.cpp" 'XDG_RUNTIME_DIR' "avisos en la carpeta privada del usuario"
contiene apps/titan-common/TitanPrefs.cpp 'Notificaciones/bloqueo' "preferencia: todo / sin contenido / nada"
contiene apps/titan-settings/qml/NotificacionesView.qml 'Notificaciones/bloqueo' "opción en Ajustes > Notificaciones"
contiene "${BIN}/titan-bloquear" 'titan-avisos-module' "gtklock carga el módulo de notificaciones"
contiene scripts/build-iso.sh 'titan-avisos-module.so' "build-iso compila el módulo de gtklock"
contiene apps/titan-avisos-bloqueo/avisos.c 'GTK_POLICY_EXTERNAL' "el módulo nunca agranda la ventana de bloqueo"
contiene "${RAIZ}/usr/share/titan/gtklock/estilo.css" '#titan-aviso ' "estilo de las tarjetas en gtklock"
if command -v pkg-config >/dev/null && pkg-config --exists gtk+-3.0 gmodule-export-2.0 && \
   make -s -C apps/titan-avisos-bloqueo SALIDA="$(mktemp -d)/m.so" CFLAGS="-O2 -Wall -Wextra -Wno-unused-parameter -Werror" >/dev/null 2>&1; then
    ok "el módulo de gtklock compila sin avisos"
else
    fallo "el módulo de gtklock no compila (o faltan las cabeceras de GTK 3)"
fi
contiene "$SH/qml/DynamicIsland.qml" 'dynamicIslandRoot.musicaAbierta . 360' "isla: tamaño final sin el id que tapa la propiedad"
no_contiene "$SH/qml/DynamicIsland.qml" 'wallpaperPath' "isla: sin capa de fondo recortada en cada fotograma"
contiene "$SH/qml/DynamicIsland.qml" 'barra.suena && barra.visible' "isla: las barras solo se animan si se ven"
contiene "$SH/qml/Shell.qml" 'function ajustar' "isla: la ventana no cambia de tamaño en cada fotograma"
contiene "$SH/src/ShellBackend.cpp" 'm_islandQueue = m_islandActive' "isla: contador real «+N»"

# ------------------------------------------------------------------ ofimática
echo -e "${AZUL}--- Ofimática: ONLYOFFICE (AppImage, no está en los repos de Arch)${SC}"
contiene scripts/build-iso.sh 'DesktopEditors-x86_64.AppImage' "build-iso descarga ONLYOFFICE si falta"
contiene scripts/build-iso.sh 'es_appimage "\$\{OO\}.parte"' "comprueba que lo descargado es un AppImage"
contiene iso/titan/profiledef.sh '/opt/onlyoffice/DesktopEditors.AppImage"\]="0:0:755"' "el AppImage es ejecutable en la ISO"
if git ls-files --error-unmatch "${BIN}/onlyoffice-desktopeditors" >/dev/null 2>&1; then
    ok "lanzador de ONLYOFFICE en git"
else
    fallo "el lanzador de ONLYOFFICE no está en git"
fi
OO="${RAIZ}/opt/onlyoffice/DesktopEditors.AppImage"
if [[ -s "$OO" ]]; then
    ok "AppImage de ONLYOFFICE presente ($(du -h "$OO" | cut -f1))"
else
    aviso "AppImage de ONLYOFFICE ausente: build-iso lo descargará"
fi

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

# ------------------------------------------------------- teclas y Alt+Tab
echo -e "${AZUL}--- Teclas especiales, Super+D, Alt+Tab y Launchpad (2026-11-19)${SC}"
SH=apps/titan-shell
WI=iso/titan/airootfs/etc/skel/.config/wayfire.ini
RC=iso/titan/airootfs/etc/skel/.config/labwc/rc.xml
for k in KEY_VOLUMEUP KEY_VOLUMEDOWN KEY_MUTE KEY_MICMUTE KEY_BRIGHTNESSUP KEY_BRIGHTNESSDOWN \
         KEY_KBDILLUMUP KEY_PLAYPAUSE KEY_NEXTSONG KEY_PREVIOUSSONG KEY_CALC; do
    contiene "$WI" "binding_[a-z_]+ = ${k}\$" "Wayfire: tecla ${k}"
done
contiene "$WI" '^repeatable_binding_volumen_subir' "Wayfire: volumen se repite si se deja pulsada"
contiene "$RC" 'XF86AudioRaiseVolume.*--tecla volumen-subir' "labwc: teclas de volumen"
contiene "$RC" 'XF86MonBrightnessUp.*--tecla brillo-subir' "labwc: teclas de brillo"
contiene "$SH/src/main.cpp" '"--tecla"' "titan-shell --tecla"
contiene "$SH/src/ShellBackend.cpp" 'mostrarIndicador\(QStringLiteral\("volumen"\)' "la isla muestra el volumen"
contiene "$SH/src/ShellBackend.cpp" 'mostrarIndicador\(QStringLiteral\("brillo"\)' "la isla muestra el brillo"
contiene "$SH/qml/DynamicIsland.qml" 'indicadorVista' "indicador de nivel en la Isla Dinamica"
contiene "$SH/src/main.cpp" 'procesar\(\);' "IPC: no se pierden ordenes seguidas"
contiene "$WI" '^toggle_showdesktop = none' "Super+D de Wayfire desactivado (restauraba todo al abrir una app)"
contiene "$WI" 'command_ver_escritorio = titan-shell --tecla escritorio' "Super+D: mostrar escritorio de titan-shell"
contiene "$RC" 'W-d.*--tecla escritorio' "labwc: Super+D"
contiene "$SH/src/WindowTracker.cpp" 'void WindowTracker::mostrarEscritorio' "mostrar escritorio sin restaurar al abrir"
contiene "$WI" '^activate = none' "fast-switcher sin Alt+Tab"
contiene "$WI" 'command_alt_tab = titan-shell --tecla alt-tab' "Alt+Tab de titan-shell"
contiene "$SH/resources.qrc" 'qml/CambiadorVentanas.qml' "CambiadorVentanas.qml en el qrc"
contiene "$SH/src/main.cpp" 'KeyboardInteractivityExclusive' "Alt+Tab toma el teclado (para ver soltar Alt)"
contiene "$SH/src/WindowTracker.cpp" 'm_recientes.prepend' "Alt+Tab en orden de uso"
contiene iso/titan/airootfs/etc/profile.d/15-titan-grafico.sh 'Teclas especiales' "migracion de teclas para usuarios existentes"
contiene "$SH/src/LauncherBackend.cpp" 'static bool esInterna' "Launchpad: entradas internas ocultas"
contiene "$SH/src/LauncherBackend.cpp" 'static QString categoriaDe' "Launchpad: categorias"
contiene "$SH/qml/Launcher.qml" 'filaCategorias' "Launchpad: fila de categorias"
contiene "$SH/src/LauncherBackend.cpp" 'QCollator' "Launchpad: orden alfabetico"
contiene apps/titan-common/TitanTinte.h 'id.mid\(barra\)\.startsWith' "icono tintado desde el disco (App Store en el Dock)"
contiene "$SH/src/DockModel.cpp" 'org.kde.discover"\)\) \{' "Dock: App Store guardada pasa al icono interno"
contiene iso/titan/airootfs/root/customize_airootfs.sh 'switcheroo-control.service' "switcheroo-control activado"

echo -e "${AZUL}--- Comparado con Ubuntu/Fedora (2026-11-19): hora, TRIM, teclado, raton ---${SC}"
CA=iso/titan/airootfs/root/customize_airootfs.sh
contiene "$CA" 'systemd-timesyncd.service' "hora en punto por NTP (timesyncd)"
contiene "$CA" 'fstrim.timer' "TRIM semanal de los SSD"
contiene "$CA" 'paccache.timer' "limpieza de la cache de pacman"
TD=iso/titan/airootfs/usr/local/bin/titan-distribucion
if [[ -x "$TD" ]] && bash -n "$TD"; then ok "titan-distribucion (teclado del escritorio)"; else fallo "titan-distribucion falta o no es valido"; fi
contiene iso/titan/airootfs/etc/X11/xorg.conf.d/00-keyboard.conf 'XkbLayout' "distribucion del teclado del live"
contiene apps/titan-installer/src/InstallerBackend.cpp '00-keyboard.conf' "el instalador guarda el teclado del escritorio"
contiene apps/titan-installer/src/InstallerBackend.cpp 'la-latin1' "latam en consola es la-latin1"
contiene iso/titan/airootfs/etc/profile.d/15-titan-grafico.sh 'titan-distribucion --sistema' "la sesion aplica el teclado del sistema"
contiene iso/titan/airootfs/usr/lib/titan/titan-greeter-sesion 'XKB_DEFAULT_LAYOUT' "pantalla de inicio con el teclado del sistema"
contiene apps/titan-settings/qml/TecladoView.qml 'setDistribucion' "Ajustes: cambiar la distribucion"
contiene apps/titan-settings/resources.qrc 'qml/RatonView.qml' "Ajustes: Raton y panel tactil"
contiene "$WI" '^disable_touchpad_while_typing = true' "panel tactil sin clics de la palma"
contiene apps/titan-common/ThemeManager.cpp 'leerTemaDelDisco' "modo claro/oscuro a GTK/Firefox sin carreras"
contiene apps/titan-common/TitanIconoApp.h 'desktopDeAppId' "mismo icono en lanzador, Dock y escritorio"
contiene "$SH/src/DesktopBackend.cpp" 'X-Flatpak' "quitar del escritorio las apps desinstaladas"
contiene "$WI" '^  titan-gestos' "gestos del panel tactil (plugin titan-gestos)"
contiene iso/titan/airootfs/usr/share/wayfire/metadata/titan-gestos.xml 'arriba_3' "metadatos de titan-gestos"
contiene apps/wayfire-titan/titan-gestos.cpp 'wlr_pointer_swipe_end_event' "titan-gestos escucha el panel tactil"
contiene iso/titan/airootfs/etc/profile.d/15-titan-grafico.sh 'titan-gestos' "gestos para usuarios existentes"
contiene apps/titan-settings/qml/RatonView.qml 'Gestos con tres y cuatro dedos' "Ajustes: gestos"
contiene iso/titan/airootfs/etc/xdg/mimeapps.list '^x-scheme-handler/mailto=org.mozilla.Thunderbird' "la tecla Correo y los enlaces mailto abren Thunderbird"
contiene iso/titan/airootfs/usr/local/bin/titan-raton-labwc '<libinput>' "raton y panel tactil tambien en labwc"
contiene iso/titan/airootfs/usr/local/bin/titan-sesion 'titan-raton-labwc' "labwc recibe los ajustes del raton al entrar"
contiene apps/titan-settings/src/Sistema.cpp 'titan-raton-labwc' "Ajustes copia el raton a labwc"
contiene iso/titan/airootfs/usr/local/bin/titan-avisos-fallos 'fc2e22bc6ee647b6b90729ab34a250b1' "aviso cuando una app se cierra sola"
contiene iso/titan/airootfs/etc/systemd/user/titan-avisos-fallos.service 'titan-avisos-fallos' "servicio del aviso de cierres"
contiene iso/titan/airootfs/root/customize_airootfs.sh 'titan-avisos-fallos.service' "aviso de cierres activado para cada usuario"
contiene iso/titan/airootfs/usr/local/bin/titan-escritorio-remoto 'enable_pam=true' "escritorio remoto cifrado y con la contrasena de la cuenta"
contiene iso/titan/airootfs/usr/local/bin/titan-cortafuegos '5900/tcp' "el cortafuegos abre el escritorio remoto solo si se comparte"
contiene apps/titan-settings/qml/CompartirView.qml 'setEscritorioRemoto' "Ajustes > Compartir"
contiene iso/titan/airootfs/usr/local/bin/titan-actualizar-sistema 'noconfirm --ask=4' "actualizar sin preguntas"
contiene iso/titan/airootfs/usr/local/bin/titan-actualizar-sistema 'systemd-run' "la actualizacion sigue aunque se cierre Ajustes"
contiene iso/titan/airootfs/usr/share/polkit-1/actions/org.intios.sistema.policy 'titan-actualizar-sistema' "permiso para actualizar con contrasena en ventana"
contiene apps/titan-settings/qml/GeneralView.qml 'Mostrar detalles' "Ajustes: barra de progreso y registro de la actualizacion"
contiene apps/titan-settings/qml/CompartirView.qml 'instalarComponente' "Ajustes > Compartir: boton Instalar en vez de la terminal"
contiene apps/titan-settings/qml/CompartirView.qml 'Abrir el puerto' "Ajustes > Compartir: boton Abrir el puerto"
contiene iso/titan/airootfs/usr/local/bin/titan-componente 'wayvnc) echo' "titan-componente solo instala lo de su lista"
contiene iso/titan/airootfs/usr/share/polkit-1/actions/org.intios.sistema.policy 'org.intios.componentes' "instalar componentes pide la contrasena en ventana"
contiene iso/titan/airootfs/usr/local/bin/titan-avisos-fallos 'Volver a abrir' "aviso de cierre con botones Volver a abrir y Ver detalles"
contiene iso/titan/airootfs/etc/pacman.conf '^Include = /etc/pacman.d/titan-servidores' "pacman usa los servidores de Inti (estable / al dia)"
contiene iso/titan/airootfs/usr/local/bin/titan-actualizar-sistema 'archive.archlinux.org/repos' "actualizaciones estables: Arch de hace 7 dias"
contiene iso/titan/airootfs/root/customize_airootfs.sh 'titan-fecha-actualizaciones.timer' "la fecha estable avanza cada dia"
contiene iso/titan/airootfs/usr/local/bin/titan-actualizar-sistema 'WAYFIRE_API_ABI_VERSION_MACRO' "Wayfire se retiene si rompe los plugins de Inti"
contiene iso/titan/airootfs/usr/share/titan/wayfire-abi '^[0-9]' "ABI de Wayfire de los plugins apuntada"
contiene iso/titan/airootfs/usr/local/bin/titan-actualizar-sistema 'archlinux.org/feeds/news' "avisos de Arch antes de actualizar"
contiene apps/titan-settings/qml/GeneralView.qml 'Actualizar igualmente' "Ajustes ensena los avisos de Arch"
contiene iso/titan/airootfs/usr/local/bin/titan-actualizar-sistema 'pacnew' ".pacnew apuntados en el registro"
contiene paquetes/inti/PKGBUILD 'package_inti-apps' "receta de los paquetes de Inti"
contiene scripts/construir-repo-inti.sh 'repo-add' "script que construye el repositorio [inti]"
contiene scripts/build-iso.sh 'construir-repo-inti.sh' "la ISO construye los paquetes de Inti"
contiene iso/titan/airootfs/root/customize_airootfs.sh 'pacman -U --dbonly' "la ISO registra los paquetes de Inti sin copiar ficheros"
contiene iso/titan/airootfs/etc/pacman.conf 'inti-repo/releases/download/paquetes' "repositorio [inti] preparado en pacman.conf"
contiene paquetes/inti-keyring/PKGBUILD 'keyrings/inti.gpg' "paquete de la clave de firma"
contiene paquetes/inti/PKGBUILD '_solo_live' "el instalador no va en los paquetes (no reaparece al actualizar)"
contiene apps/titan-installer/src/InstallerBackend.cpp 'etc/pacman.d/gnupg' "cada equipo instalado genera su propio llavero de pacman"
contiene iso/titan/airootfs/usr/local/bin/titan-actualizar-sistema 'inti-wayfire-plugins"' "se retienen los plugins de Inti si son para otro Wayfire"
contiene iso/titan/airootfs/etc/firefox/policies/policies.json 'DisableTelemetry' "Firefox sin telemetría ni estudios"
contiene iso/titan/airootfs/etc/thunderbird/policies/policies.json 'DisableTelemetry' "Thunderbird sin telemetría"
contiene apps/titan-shell/src/ColaApps.cpp 'kEsperaVentanaMs' "las apps se abren de una en una (ColaApps)"
contiene apps/titan-shell/qml/Shell.qml 'cursorWindow' "indicador de apertura junto al puntero"
contiene apps/titan-shell/src/DockModel.cpp 'Solo rebotan las apps que están en el Dock' "el Dock no añade iconos temporales"
contiene iso/titan/airootfs/etc/skel/.config/wayfire.ini 'include_minimized = true' "3 dedos arriba también muestra las ventanas minimizadas"
contiene iso/titan/airootfs/etc/profile.d/15-titan-grafico.sh 'include_minimized = true' "migración de la vista de ventanas para usuarios existentes"
contiene iso/titan/airootfs/usr/local/bin/titan-rendimiento 'quitar_plugin blur' "modo equipo ligero (titan-rendimiento)"
contiene iso/titan/airootfs/usr/local/bin/titan-sesion 'titan-rendimiento inicio' "el equipo ligero se decide solo la primera vez"
contiene apps/titan-settings/qml/EnergiaView.qml 'Equipo ligero' "interruptor de equipo ligero en Ajustes"
contiene iso/titan/airootfs/etc/skel/.config/wayfire.ini 'minimize_animation = zoom' "minimizar rápido (zoom de 0,2 s)"
contiene apps/titan-shell/qml/WorkspacesView.qml 'Sin barra superior en esta vista' "selector de escritorios sin barra, solo la hora"
contiene apps/titan-finder/qml/FileList.qml 'function posMenu' "menú del Finder junto al puntero, se da la vuelta en los bordes"
contiene apps/titan-finder/qml/FileList.qml 'Nuevo documento' "Finder: Nuevo documento desde el clic derecho"
contiene apps/titan-finder/src/FinderBackend.cpp 'aplicacionesPara' "Finder: Abrir con"
contiene apps/titan-shell/qml/Dock.qml 'Fondo opaco' "menú del Dock opaco"
contiene apps/titan-common/ThemeManager.cpp 'SIEMPRE en "Adwaita"' "Firefox: modo oscuro solo por color-scheme (como GNOME)"
contiene apps/titan-shell/src/main.cpp 'aplicarIdioma' "idioma al momento, sin cerrar sesión"
contiene iso/titan/airootfs/usr/local/bin/titan-bloquear 'userswitch-command' "bloqueo: botón Cambiar de usuario"
contiene iso/titan/airootfs/etc/systemd/system/titan-otro-usuario@.service 'cambio.toml' "cambiar de usuario: otra pantalla de inicio"
contiene iso/titan/airootfs/etc/polkit-1/rules.d/50-titan-cambiar-usuario.rules 'titan-otro-usuario@' "cambiar de usuario: polkit solo para esa unidad"
contiene apps/titan-greeter/src/Sistema.h 'irASesion' "inicio: volver a una sesión abierta"
contiene apps/titan-shell/qml/Launcher.qml 'onMenuPedido' "menú de inicio: clic derecho en cada app"
contiene apps/titan-shell/src/LauncherBackend.cpp 'Desktop Action ' "menú de inicio: acciones propias de la app (Nueva ventana...)"
contiene iso/titan/airootfs/usr/share/polkit-1/actions/org.intios.sistema.policy 'titan-desinstalar' "desinstalar con contraseña (polkit)"
contiene iso/titan/airootfs/usr/share/titan/wallpapers/CREDITOS.txt 'Machu Picchu' "fondos nuevos con créditos"
contiene apps/titan-theme/qml/TitanTheme.qml 'readonly property bool opaco: true' "ventanas de las apps opacas (como Windows y Tahoe)"
contiene apps/titan-theme/qml/TitanTheme.qml 'Modo oscuro en NEGRO' "modo oscuro negro"
contiene apps/titan-theme/qml/TitanWindow.qml 'border.color: rootWindow.active . titanTheme.accent' "borde de ventana con el acento (apps de Inti)"
contiene apps/wayfire-titan/titan-decor/deco-theme.cpp 'titan_accent' "borde con el acento (ventanas con marco de Wayfire)"
contiene iso/titan/airootfs/usr/local/bin/titan-acento 'window.csd { outline' "borde con el acento (apps GTK)"
contiene apps/titan-calc/qml/TitanTheme.qml 'readonly property bool opaco: true' "copia del tema al día (calc)"
contiene apps/titan-shell/qml/DesktopIcons.qml 'si no' "menú del escritorio se da la vuelta en los bordes"
contiene iso/titan/airootfs/usr/local/bin/titan-informe 'Solo LEE' "informe de prueba del equipo (titan-informe)"
contiene paquetes/inti/PKGBUILD 'qt6-base>=' "las apps de Inti piden el Qt con el que se compilaron"
contiene iso/titan/airootfs/usr/local/bin/titan-actualizar-sistema 'esperan a la próxima actualización' "si falta ese Qt, las apps de Inti esperan sin romper la actualización"
contiene scripts/build-iso.sh 'env -u INTI_CLAVE' "la ISO no pide la contraseña de la clave al construirse"
contiene iso/titan/airootfs/usr/local/bin/titan-idioma 'grep -qFx' "titan-idioma solo acepta idiomas de la lista del sistema"
contiene iso/titan/airootfs/usr/share/polkit-1/actions/org.intios.sistema.policy 'org.intios.idioma' "instalar un idioma pide la contrasena en ventana"
contiene apps/titan-settings/src/SettingsBackend.cpp 'titan-idioma' "Ajustes cambia el idioma sin sudo en segundo plano"
contiene iso/titan/airootfs/usr/local/bin/titan-actualizaciones 'titan-settings --actualizar' "el aviso de actualizaciones empieza a actualizar al pulsar"

contiene iso/titan/airootfs/usr/local/bin/titan-sesion 'Registros de ESTA cuenta' "registros de la sesion por cuenta (cambiar de usuario no deja el fondo azul)"
contiene iso/titan/airootfs/usr/local/bin/titan-sesion 'try-restart xdg-desktop-portal' "el portal de apariencia arranca con el entorno de la sesion"
contiene iso/titan/airootfs/usr/share/xdg-desktop-portal/portals.conf 'default=gtk' "portales por defecto aunque falte XDG_CURRENT_DESKTOP"
contiene apps/titan-settings/qml/VentanasView.qml 'Cambiar estilo de ventana' "Ajustes > Ventanas: cambiar estilo de ventana"
contiene apps/titan-settings/src/SettingsBackend.cpp 'add\(QStringLiteral\("Ventanas"' "sección Ventanas en Ajustes"
contiene apps/titan-common/ThemeManager.cpp 'estiloValido' "el estilo de ventana solo acepta nombres de la lista"
contiene apps/titan-theme/qml/TitanWindow.qml 'source: titanTheme.ficheroBotones' "las apps de Inti cargan solo el estilo de botones elegido"
contiene apps/wayfire-titan/titan-decor/decoration.cpp 'inotify_add_watch' "Wayfire cambia los botones al momento (sin cerrar ventanas)"
contiene apps/wayfire-titan/titan-decor/estilo-botones.cpp 'crear_estilo_windows' "Wayfire: un estilo de botones por fichero"
contiene iso/titan/airootfs/usr/local/bin/titan-estilo-ventanas 'actual|windows|circulos|acento|capsula|contorno|color' "titan-estilo-ventanas solo acepta estilos de la lista"
contiene iso/titan/airootfs/usr/local/bin/titan-acento 'titan-estilo-ventanas' "los iconos de labwc siguen el acento y el modo"
contiene iso/titan/profiledef.sh 'titan-estilo-ventanas' "titan-estilo-ventanas ejecutable en la ISO"
contiene iso/titan/airootfs/etc/skel/.config/gtk-3.0/gtk.css 'titan-ventanas.css' "GTK 3 importa el estilo de ventana"
contiene iso/titan/airootfs/etc/skel/.config/gtk-4.0/gtk.css 'titan-ventanas.css' "GTK 4 importa el estilo de ventana"
contiene iso/titan/airootfs/usr/share/titan/ventanas/actual/estilo.conf 'labwc=' "estilo actual: GTK y labwc"
contiene iso/titan/airootfs/usr/share/titan/ventanas/windows/estilo.conf 'labwc=' "estilo windows: GTK y labwc"
contiene iso/titan/airootfs/usr/share/titan/ventanas/circulos/estilo.conf 'labwc=' "estilo circulos: GTK y labwc"
contiene iso/titan/airootfs/usr/share/titan/ventanas/acento/estilo.conf 'labwc=' "estilo acento: GTK y labwc"
contiene iso/titan/airootfs/usr/share/titan/ventanas/capsula/estilo.conf 'labwc=' "estilo capsula: GTK y labwc"
contiene iso/titan/airootfs/usr/share/titan/ventanas/contorno/estilo.conf 'labwc=' "estilo contorno: GTK y labwc"
contiene iso/titan/airootfs/usr/share/titan/ventanas/color/estilo.conf 'labwc=' "estilo color: GTK y labwc"
contiene apps/titan-calc/resources.qrc 'qml/botones/BotonesAcento.qml' "copia de los botones al día (calc)"
contiene apps/titan-calendar/resources.qrc 'qml/botones/BotonesAcento.qml' "copia de los botones al día (calendar)"
contiene apps/titan-clock/resources.qrc 'qml/botones/BotonesAcento.qml' "copia de los botones al día (clock)"
contiene apps/titan-installer/resources.qrc 'qml/botones/BotonesAcento.qml' "copia de los botones al día (installer)"
contiene apps/titan-video/resources.qrc 'qml/botones/BotonesAcento.qml' "copia de los botones al día (video)"
contiene iso/titan/airootfs/usr/local/bin/titan-appimage 'AI002' "AppImage: solo acepta AppImage de verdad (marca AI)"
contiene iso/titan/airootfs/usr/local/bin/titan-appimage 'unsquashfs' "AppImage: nombre e icono se leen sin ejecutarlo"
contiene iso/titan/airootfs/usr/local/bin/titan-appimage 'inti-appimage-\*\.desktop' "AppImage: quitar solo borra lo que instaló"
contiene iso/titan/airootfs/usr/share/titan/appimage/Pregunta.qml 'Abrir solo esta vez' "AppImage: ventana Instalar / Abrir solo esta vez"
contiene iso/titan/airootfs/etc/xdg/mimeapps.list 'application/vnd.appimage=inti-appimage.desktop' "AppImage: doble clic desde Firefox y otras apps"
contiene apps/titan-finder/src/FinderBackend.cpp 'titan-appimage' "AppImage: doble clic en el Finder"
contiene apps/titan-shell/src/DesktopBackend.cpp 'titan-appimage' "AppImage: doble clic en el escritorio"
contiene apps/titan-shell/src/LauncherBackend.cpp 'esAppImage' "AppImage: Desinstalar desde el menú de inicio"
contiene apps/titan-shell/src/main.cpp 'recargar-apps' "el menú de inicio se actualiza al instalar"
contiene iso/titan/profiledef.sh 'titan-appimage' "titan-appimage ejecutable en la ISO"
contiene iso/titan/airootfs/usr/share/applications/titan-finder.desktop 'Name=Explorador de archivos' "Explorador de archivos: nombre nuevo en el menú"
contiene apps/titan-finder/qml/Finder.qml 'BarraComandos' "Explorador: barra de comandos (Nuevo, Cortar, Copiar, Pegar...)"
contiene apps/titan-finder/qml/Finder.qml 'PanelDetalles' "Explorador: panel de detalles con vista previa"
contiene apps/titan-finder/qml/FileList.qml 'miniatura' "Explorador: fotos en miniatura en la vista de iconos"
contiene apps/titan-finder/src/FinderBackend.cpp 'PicturesLocation' "Explorador: carpetas del usuario en español (xdg-user-dirs)"
contiene iso/titan/airootfs/etc/skel/.config/labwc/rc.xml 'Explorador de archivos' "labwc: el Explorador sin doble barra de título"
contiene apps/titan-finder/src/Explorador.cpp 'void FinderBackend::deshacer' "Explorador: Deshacer (Ctrl+Z) mover, copiar, renombrar, Papelera"
contiene apps/titan-finder/qml/FileList.qml 'Key_Z' "Explorador: Ctrl+Z"
contiene apps/titan-finder/qml/FileList.qml 'function moverSeleccion' "Explorador: moverse con las flechas, Inicio, Fin, RePág"
contiene apps/titan-finder/qml/FileList.qml 'function saltarALetra' "Explorador: escribir una letra salta al archivo"
contiene apps/titan-finder/src/Explorador.cpp 'buscarEnSubcarpetas' "Explorador: la búsqueda mira dentro de las subcarpetas"
contiene apps/titan-finder/src/Explorador.cpp 'recently-used.xbel' "Explorador: Recientes de verdad (estándar freedesktop)"
contiene apps/titan-finder/src/Explorador.cpp 'void FinderBackend::anclar' "Explorador: Anclar a Acceso rápido"
contiene apps/titan-finder/src/FinderBackend.cpp 'Carpeta personal' "Explorador: Carpeta personal en el panel izquierdo"
contiene apps/titan-monitor/qml/Grafica.qml 'theme.accent' "Monitor de recursos: gráficas con el color de acento"
contiene apps/titan-monitor/qml/VistaProcesos.qml 'Finalizar tarea' "Monitor de recursos: Finalizar tarea"
contiene apps/titan-monitor/src/MonitorBackend.cpp 'criticos()' "Monitor: no deja cerrar lo que sostiene el escritorio"
contiene apps/titan-monitor/src/MonitorBackend.cpp 'Hidden=%1' "Monitor: aplicaciones de inicio sin contraseña ni borrar nada"
contiene scripts/build-iso.sh 'build_qt_app titan-monitor' "Monitor de recursos se compila en la ISO"
contiene iso/titan/airootfs/etc/skel/.config/wayfire.ini 'command_monitor = titan-monitor' "Ctrl+Mayús+Esc abre el Monitor (Wayfire)"
contiene iso/titan/airootfs/etc/skel/.config/labwc/rc.xml 'C-S-Escape' "Ctrl+Mayús+Esc abre el Monitor (labwc)"
contiene iso/titan/airootfs/etc/skel/.config/wayfire.ini '<alt> KEY_F4' "Alt+F4 cierra la ventana (Wayfire), además de Win+Q"
contiene iso/titan/airootfs/etc/skel/.config/wayfire.ini 'command_seguridad = titan-shell --tecla seguridad' "Ctrl+Alt+Supr abre la pantalla de seguridad"
contiene iso/titan/airootfs/etc/skel/.config/wayfire.ini 'command_ajustes_win = titan-shell --tecla ajustes' "Win+I abre Ajustes"
contiene iso/titan/airootfs/etc/skel/.config/wayfire.ini 'command_portapapeles' "Win+V: historial del portapapeles"
contiene iso/titan/airootfs/etc/skel/.config/wayfire.ini 'command_emojis' "Win+.: emojis"
contiene iso/titan/airootfs/etc/skel/.config/wayfire.ini 'command_atajos' "Win+F1: lista de atajos"
contiene iso/titan/airootfs/etc/skel/.config/labwc/rc.xml 'C-A-Delete' "labwc: Ctrl+Alt+Supr, Win+I/V/./F1"
contiene apps/titan-shell/src/Portapapeles.cpp 'passwordManagerHint' "Portapapeles: no guarda lo que marcan los gestores de contraseñas"
contiene apps/titan-shell/src/Portapapeles.h 'nunca en el disco' "Portapapeles: solo en memoria"
contiene apps/titan-shell/qml/PanelSistema.qml 'Cambiar de usuario' "Ctrl+Alt+Supr: bloquear, cambiar de usuario, cerrar sesión, apagar"
contiene apps/titan-shell/datos/emojis.json 'Corazón rojo' "Emojis con nombres en español"
contiene apps/titan-shell/qml/DesktopIcons.qml 'Abrir en el Explorador' "Escritorio: menú con el nombre nuevo del Explorador"
contiene apps/titan-shell/qml/DesktopIcons.qml 'text: "Ctrl' "Escritorio: atajos de Windows (no ⌘)"
contiene apps/titan-shell/qml/DesktopIcons.qml 'Nueva carpeta' "Escritorio: Nueva carpeta con clic derecho"
contiene apps/titan-bienvenida/qml/Bienvenida.qml 'Estilo Windows' "Bienvenida: elegir botones estilo Windows"
contiene iso/titan/airootfs/etc/xdg/autostart/titan-bienvenida.desktop 'primera-vez' "Bienvenida: solo la primera vez"
contiene scripts/build-iso.sh 'build_qt_app titan-bienvenida' "Bienvenida se compila en la ISO"
contiene iso/titan/airootfs/usr/local/bin/titan-exe 'pkexec /usr/local/bin/titan-componente instalar wine' "Programas .exe: Wine con la ventana de contraseña"
contiene iso/titan/airootfs/usr/local/bin/titan-componente 'wine) echo' "titan-componente: Wine en la lista permitida"
contiene iso/titan/airootfs/etc/xdg/mimeapps.list 'application/x-ms-dos-executable=inti-exe.desktop' "Programas .exe: doble clic desde Firefox y otras apps"
contiene apps/titan-finder/src/FinderBackend.cpp 'titan-exe' "Programas .exe: doble clic en el Explorador"
contiene apps/titan-shell/src/DesktopBackend.cpp 'titan-exe' "Programas .exe: doble clic en el escritorio"
contiene iso/titan/profiledef.sh 'titan-exe' "titan-exe ejecutable en la ISO"
contiene iso/titan/airootfs/usr/share/doc/inti/manual.html '<kbd>Q</kbd> &nbsp;o&nbsp;' "Manual: atajos de Inti (Win+Q, Win+F, Win+Mayús+F, Win+↑)"
contiene iso/titan/airootfs/usr/local/bin/titan-manual 'manual.html' "Manual de usuario en el menú de inicio"
contiene iso/titan/airootfs/usr/local/bin/titan-paquete 'NUNCA se ejecutan los scripts' "Paquetes .deb/.rpm: nunca se ejecutan sus scripts de instalación"
contiene iso/titan/airootfs/usr/local/bin/titan-paquete 'flatpak search' "Paquetes .deb/.rpm: primero se busca en la App Store"
contiene iso/titan/airootfs/usr/local/bin/titan-paquete 'chmod ug-s' "Paquetes .deb/.rpm: sin permisos setuid"
contiene iso/titan/airootfs/usr/local/bin/titan-paquete 'inti-paquete-\*\.desktop) ;;' "Paquetes .deb/.rpm: quitar solo borra lo que instaló"
contiene iso/titan/airootfs/etc/xdg/mimeapps.list 'application/vnd.debian.binary-package=inti-paquete.desktop' "Paquetes .deb: doble clic desde Firefox y otras apps"
contiene iso/titan/airootfs/etc/xdg/mimeapps.list 'application/x-rpm=inti-paquete.desktop' "Paquetes .rpm: doble clic desde Firefox y otras apps"
contiene apps/titan-finder/src/FinderBackend.cpp 'titan-paquete' "Paquetes .deb/.rpm: doble clic en el Explorador"
contiene apps/titan-shell/src/DesktopBackend.cpp 'titan-paquete' "Paquetes .deb/.rpm: doble clic en el escritorio"
contiene apps/titan-shell/src/LauncherBackend.cpp 'esPaqueteCuenta' "Paquetes .deb/.rpm: Desinstalar desde el menú de inicio"
contiene iso/titan/profiledef.sh 'titan-paquete' "titan-paquete ejecutable en la ISO"
contiene apps/titan-shell/src/LauncherBackend.cpp 'kAjustes' "Buscador del menú de inicio: encuentra ajustes"
contiene apps/titan-shell/src/LauncherBackend.cpp 'buscarEnCasa' "Buscador del menú de inicio: encuentra archivos (local, sin indexador)"
contiene apps/titan-shell/qml/Launcher.qml 'otrosResultados' "Buscador del menú de inicio: muestra ajustes y archivos"
contiene apps/titan-settings/src/Predeterminadas.cpp 'Default Applications' "Ajustes: aplicaciones predeterminadas (mimeapps.list de la persona)"
contiene apps/titan-settings/src/SettingsBackend.cpp 'Aplicaciones predeterminadas' "Ajustes: página de aplicaciones predeterminadas en la barra"
contiene apps/titan-shell/src/DesktopBackend.cpp 'abrirConElegida' "Escritorio: respeta la app predeterminada elegida"
contiene apps/titan-finder/src/FinderBackend.cpp 'abrirConElegida' "Explorador: respeta la app predeterminada elegida"
contiene iso/titan/airootfs/etc/skel/.config/wayfire.ini '<super> KEY_TAB' "Win+Tab: ver todas las ventanas"
contiene iso/titan/airootfs/etc/skel/.config/wayfire.ini 'binding_herramientas = <super> KEY_X' "Win+X: menú de herramientas"
contiene iso/titan/airootfs/etc/skel/.config/wayfire.ini 'binding_proyectar = <super> KEY_P' "Win+P: proyectar"
contiene apps/titan-shell/qml/PanelSistema.qml 'modosProyeccion' "Panel Proyectar (Win+P)"
contiene iso/titan/profiledef.sh 'titan-proyectar' "titan-proyectar ejecutable en la ISO"
contiene apps/titan-settings/src/Dispositivos.cpp 'set-sink-input-volume' "Sonido: volumen por aplicación (mezclador)"
contiene apps/titan-settings/qml/SonidoView.qml 'Volumen de las aplicaciones' "Sonido: sección del mezclador"
contiene apps/titan-finder/src/Red.cpp 'g_file_mount_enclosing_volume' "Explorador > Red: entra en carpetas compartidas (gvfs)"
contiene apps/titan-finder/src/Red.cpp 'G_PASSWORD_SAVE_FOR_SESSION' "Explorador > Red: la contraseña no se guarda en disco"
contiene apps/titan-finder/src/FinderBackend.cpp 'Red::raiz()' "Explorador: Red en la barra lateral"
contiene apps/titan-finder/qml/FileList.qml 'credDialog' "Explorador > Red: pide usuario y contraseña"
contiene iso/titan/packages.x86_64 '^gvfs-wsdd$' "Red: ver los PC con Windows (gvfs-wsdd, solo descubrir)"
contiene apps/titan-finder/qml/Pestanas.qml 'application/x-inti-pestana' "Explorador: pestañas que se arrastran entre ventanas"
contiene apps/titan-finder/src/FinderBackend.cpp 'FinderBackend::recibirPestana' "Explorador: juntar pestañas de otra ventana"
contiene apps/titan-finder/src/FinderBackend.cpp 'FinderBackend::separarPestana' "Explorador: separar una pestaña en ventana nueva"
contiene apps/titan-finder/qml/Finder.qml 'sequence: "Ctrl\+T"; onActivated: finderBackend.nuevaPestana' "Explorador: Ctrl+T abre una pestaña"
contiene apps/titan-finder/qml/Finder.qml 'Ctrl\+Alt\+T' "Explorador: la Terminal pasa a Ctrl+Alt+T"
contiene apps/titan-finder/resources.qrc 'qml/Pestanas.qml' "Explorador: Pestanas.qml en los recursos"
contiene iso/titan/airootfs/etc/skel/.config/wayfire.ini '^  simple-tile \\$' "Mosaico: plugin simple-tile cargado"
contiene iso/titan/airootfs/etc/skel/.config/wayfire.ini '^tile_by_default = none$' "Mosaico: apagado por defecto (fácil como Windows)"
contiene iso/titan/airootfs/etc/skel/.config/wayfire.ini '^key_toggle = <super> <shift> KEY_T$' "Mosaico: Win+Mayús+T no choca con Win+T (Terminal)"
contiene iso/titan/airootfs/etc/skel/.config/wayfire.ini '^key_toggle_maximized = none$' "Mosaico: Win+M sigue siendo Minimizar"
contiene apps/titan-settings/src/Sistema.cpp 'titan-polkit' "Mosaico: la ventana de contraseña siempre flota"
contiene apps/titan-settings/qml/VentanasView.qml 'sistema.setMosaico' "Mosaico: interruptor en Ajustes > Ventanas"
contiene apps/titan-shell/qml/Shell.qml 'objectName: "esquinaWindow"' "Barra: esquina inferior derecha abre los escritorios"
contiene apps/titan-shell/qml/Shell.qml 'duration: 2500' "Barra: la esquina espera 2,5 s"
no_contiene apps/titan-shell/qml/TopBar.qml 'hotCornerWorkspaces' "Barra: sin esquina superior derecha"
contiene apps/titan-shell/qml/TopBar.qml 'windowTracker.mostrarEscritorio' "Barra: botón Mostrar el escritorio junto a la campana"
contiene apps/titan-shell/qml/TopBar.qml 'shellBackend.toggleCalendario' "Barra: la fecha abre el calendario"
contiene apps/titan-shell/qml/TopBar.qml 'model: shellBackend.workspaces' "Barra: números de escritorio en el centro"
contiene apps/titan-shell/resources.qrc 'qml/Calendario.qml' "Barra: Calendario.qml en los recursos"
contiene apps/titan-shell/src/main.cpp 'calendarioWindow' "Barra: capa del calendario"
contiene iso/titan/airootfs/etc/skel/.config/wayfire.ini '^workspace_switch_after = -1$' "Ventanas: acoplar al borde no cambia de escritorio"
contiene iso/titan/airootfs/etc/skel/.config/wayfire.ini '^binding_mover_3 = <super> <shift> KEY_3$' "Escritorios: Win+Mayús+número mueve la ventana"
no_contiene iso/titan/airootfs/etc/skel/.config/wayfire.ini '^binding_grabar = <super> <shift> KEY_5$' "Escritorios: Win+Mayús+5 ya no graba (choca con mover)"
contiene iso/titan/airootfs/etc/skel/.config/labwc/rc.xml 'SendToDesktop' "labwc: Win+Mayús+número mueve la ventana"
contiene iso/titan/airootfs/usr/local/bin/titan-sesion 'migracion-escritorios-1' "Cuentas antiguas: wayfire.ini puesto al día al entrar"
contiene apps/titan-shell/src/main.cpp 'tecla mover-' "titan-shell: mover la ventana al escritorio N"
contiene apps/titan-shell/qml/Dock.qml 'windowTracker.hasTiledWindow' "Dock: se esconde con una ventana acoplada"
contiene apps/titan-shell/src/WayfireIpc.cpp 'view-tiled' "Dock: escucha cuándo se acopla una ventana"
contiene apps/titan-theme/qml/TitanWindow.qml 'minimumWidth: 420' "Apps de Inti: caben en media pantalla"
no_contiene apps/titan-fotos/qml/Fotos.qml 'minimumWidth: 820' "Fotos: cabe en media pantalla"
no_contiene apps/titan-musica/qml/Musica.qml 'minimumWidth: 860' "Música: cabe en media pantalla"
contiene apps/titan-finder/qml/Finder.qml 'anchoPlegarBarra: 720' "Explorador: barra lateral en iconos al estar acoplado"
contiene apps/titan-settings/src/Dispositivos.cpp 'resolucionesHabituales' "Pantallas: resoluciones habituales además de las anunciadas"
contiene apps/titan-settings/src/Dispositivos.cpp '"--custom-mode"' "Pantallas: las no anunciadas se aplican como modo personalizado"
contiene apps/titan-settings/qml/PantallasView.qml 'Mostrar más resoluciones' "Pantallas: opción para resoluciones mayores"
contiene iso/titan/airootfs/etc/mkinitcpio.conf.d/archiso.conf 'kms plymouth' "Arranque: animación de carga también en el USB (gancho plymouth)"
contiene iso/titan/grub/grub.cfg 'titanlinux.* quiet splash' "Arranque: sin líneas de systemd en el USB (quiet splash)"
contiene iso/titan/airootfs/root/customize_airootfs.sh 'Title=Apagando' "Apagado y reinicio con la animación de carga"
contiene iso/titan/airootfs/root/customize_airootfs.sh 'plymouth/themes/titan/throbber' "El initramfs del USB se rehace si no trae la animación"
[ -f iso/titan/airootfs/usr/share/titan/plymouth/throbber-0060.png ] && ok "Animación: 60 fotogramas del círculo de puntos" || fallo "Faltan los fotogramas de la animación"
contiene apps/titan-installer/qml/InstallerWindow.qml 'component Presentacion' "Instalador: diapositivas de Inti OS mientras instala"
contiene apps/titan-shell/qml/BootSplash.qml 'width: 150' "Logo de Inti más grande al entrar"
# titan-sin-3d: tarjeta con nodo de render pero que acaba en llvmpipe = sin aceleración
_t3d=$(mktemp -d); mkdir -p "$_t3d/dri" "$_t3d/bin"; : > "$_t3d/dri/renderD128"
printf '#!/bin/sh\necho "OpenGL core profile renderer: llvmpipe (LLVM 19, 256 bits)"\n' > "$_t3d/bin/eglinfo"; chmod +x "$_t3d/bin/eglinfo"
PATH="$_t3d/bin:$PATH" TITAN_DRM_DIR="$_t3d/dri" sh iso/titan/airootfs/usr/lib/titan/titan-sin-3d \
  && ok "titan-sin-3d: tarjeta sin driver 3D (llvmpipe) va en modo sin aceleración" || fallo "titan-sin-3d no detecta llvmpipe"
printf '#!/bin/sh\necho "OpenGL core profile renderer: Mesa Intel(R) UHD Graphics"\n' > "$_t3d/bin/eglinfo"
PATH="$_t3d/bin:$PATH" TITAN_DRM_DIR="$_t3d/dri" sh iso/titan/airootfs/usr/lib/titan/titan-sin-3d \
  && fallo "titan-sin-3d toma una tarjeta con 3D por una sin aceleración" || ok "titan-sin-3d: tarjeta con 3D sigue con aceleración"
rm -rf "$_t3d"
contiene iso/titan/airootfs/etc/profile.d/15-titan-grafico.sh 'titan-sin-3d' "Sesión: usa titan-sin-3d para elegir labwc/Wayfire"
contiene iso/titan/airootfs/usr/lib/titan/titan-greeter-sesion 'titan-sin-3d' "Inicio de sesión: modo software si la tarjeta no tiene 3D"
# Resolución de arranque (tarjetas sin driver): solo valores de la lista
_tg=$(mktemp -d); printf 'GRUB_DEFAULT=0\nGRUB_GFXMODE=auto\n' > "$_tg/grub"
TITAN_GRUB_DEF="$_tg/grub" bash iso/titan/airootfs/usr/local/bin/titan-resolucion-arranque poner 1024x768 \
  && grep -q '^GRUB_GFXMODE="1024x768,auto"$' "$_tg/grub" && grep -q '^GRUB_GFXPAYLOAD_LINUX=keep$' "$_tg/grub" \
  && ok "titan-resolucion-arranque pone la resolución de GRUB y la pasa a Linux" || fallo "titan-resolucion-arranque no escribe GRUB_GFXMODE"
TITAN_GRUB_DEF="$_tg/grub" bash iso/titan/airootfs/usr/local/bin/titan-resolucion-arranque poner '1024x768;id' 2>/dev/null \
  && fallo "titan-resolucion-arranque acepta valores fuera de la lista" || ok "titan-resolucion-arranque rechaza valores fuera de la lista"
rm -rf "$_tg"
contiene iso/titan/airootfs/usr/share/polkit-1/actions/org.intios.sistema.policy 'titan-resolucion-arranque' "Resolución de arranque: pide la contraseña (polkit)"
contiene apps/titan-installer/src/InstallerBackend.cpp 'GRUB_GFXPAYLOAD_LINUX=keep' "Instalado: Linux arranca con la resolución de GRUB (sin driver no cae a texto)"
contiene apps/titan-settings/src/Dispositivos.cpp 'salidaSinDriver' "Pantallas: detecta tarjetas sin driver (simpledrm/efifb)"
echo
echo -e "${AZUL}=== RESUMEN ===${SC}"
echo "Correctas: ${exitos}   Avisos: ${avisos}   Fallos: ${fallos}"
((fallos == 0))
