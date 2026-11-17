#!/usr/bin/env bash
# shellcheck disable=SC2034
#
# Inti OS 1.8 - archiso profile (FASE 5 del proyecto).
#
# Live ISO de Inti OS. El sistema arranca con systemd dentro de la
# imagen, entra con autologin en tty1 (y en ttyS0, para QEMU headless) y
# ofrece el comando basico de Linux mas `titan` / `fastfetch`.
#
# Variables de entorno que fija scripts/build-iso.sh:
#   TITAN_VERSION   version de la ISO (por defecto 1.8)
#   TITAN_CODENAME  apodo de la release
#   TITAN_REPO      ruta del repositorio local con linux-titanlinux

iso_name="inti-os"
iso_label="INTI_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Inti OS Project <https://github.com/solaris-linux>"
iso_application="Inti OS"
iso_version="${TITAN_VERSION:-1.8}"
install_dir="titan"
buildmodes=('iso')
bootmodes=('bios.syslinux'
           'uefi.grub')
pacman_conf="pacman.conf"
# EROFS: solo lectura y muy compacto; el initramfs de archiso lo monta y lo
# superpone con overlayfs, asi que el sistema vivo sigue siendo escribible.
airootfs_image_type="erofs"
airootfs_image_tool_options=('-zlzma,109' -E 'ztailpacking')
bootstrap_tarball_compression=(xz -9e)
# archiso copia el airootfs del perfil con 'cp -af --no-preserve=ownership,mode'
# ANTES de instalar los paquetes, y luego aplica solo los modos de esta tabla.
# Cualquier fichero del perfil que necesite permisos tiene que aparecer aqui:
# sin esta entrada, /usr/local/bin/titan llega a la ISO como 0644 y el usuario
# recibe un "Permiso denegado" al ejecutarlo.
file_permissions=(
  ["/usr/local/bin/titan"]="0:0:755"
  # El escritorio Qt. Igual que el CLI: archiso copia el airootfs sin conservar
  # los permisos, y sin esta entrada llega 0644 y tty1 se queda en texto por un
  # "no se puede ejecutar" que no tiene nada que ver con la grafica.
  ["/usr/local/bin/titan-desktop"]="0:0:755"
  # La barra inferior y el centro de aplicaciones. Mismo motivo: sin el modo
  # 0755 el autostart de labwc no puede ejecutarla y la barra no aparece.
  ["/usr/local/bin/titan-panel"]="0:0:755"
  # La app Acerca tambien se lanza desde el centro de aplicaciones; sin
  # 0755 el catalogo la muestra pero el clic no arranca nada.
  ["/usr/local/bin/titan-acerca"]="0:0:755"
  # /root a 0750 como en el paquete 'filesystem'; si no, pacman avisa de que los
  # permisos del directorio no cuadran con su .MTREE.
  ["/root/"]="0:0:750"
  ["/usr/local/bin/titan-shell"]="0:0:755"
  ["/usr/local/bin/titan-sesion"]="0:0:755"
  # Inicio de sesion del sistema instalado (greetd + cage + titan-greeter) y
  # el servicio root que crea usuarios y grupos.
  ["/usr/local/bin/titan-greeter"]="0:0:755"
  ["/usr/local/bin/titan-usuarios-helper"]="0:0:755"
  ["/usr/lib/titan/titan-greeter-sesion"]="0:0:755"
  ["/usr/lib/titan/titan-arranque-grafico"]="0:0:755"
  ["/usr/local/bin/titan-finder"]="0:0:755"
  ["/usr/local/bin/titan-fotos"]="0:0:755"
  ["/usr/local/bin/titan-musica"]="0:0:755"
  ["/usr/local/bin/titan-terminal"]="0:0:755"
  ["/usr/local/bin/titan-settings"]="0:0:755"
  ["/usr/local/bin/onlyoffice-desktopeditors"]="0:0:755"
  ["/opt/onlyoffice/DesktopEditors.AppImage"]="0:0:755"
  ["/etc/skel/.config/labwc/autostart"]="0:0:755"
  ["/usr/local/bin/prime-run"]="0:0:755"
  ["/usr/local/bin/instalar"]="0:0:755"
  ["/root/instalador/instalar"]="0:0:755"
  ["/usr/local/bin/titan-installer"]="0:0:755"
  # Escritorio completo (bloqueo, inactividad, capturas, cortafuegos, etc.)
  ["/usr/local/bin/titan-bloquear"]="0:0:755"
  ["/usr/local/bin/titan-bloquear-avisar"]="0:0:755"
  ["/usr/local/bin/titan-inactividad"]="0:0:755"
  ["/usr/local/bin/titan-captura"]="0:0:755"
  ["/usr/local/bin/titan-elegir-pantalla"]="0:0:755"
  ["/usr/local/bin/titan-cortafuegos"]="0:0:755"
  ["/usr/local/bin/titan-actualizaciones"]="0:0:755"
  ["/usr/local/bin/titan-arranque-seguro"]="0:0:755"
  ["/usr/local/bin/titan-huella"]="0:0:755"
  ["/usr/local/bin/titan-instantaneas"]="0:0:755"
  ["/usr/local/bin/titan-polkit"]="0:0:755"
  ["/usr/local/bin/titan-lector"]="0:0:755"
  ["/etc/sudoers.d/20-calamares"]="0:0:0440"
)
