#!/usr/bin/env bash
# shellcheck disable=SC2034
#
# Titan Linux 0.1 - archiso profile (FASE 5 del proyecto).
#
# Live ISO de Titan Linux. El sistema arranca con systemd dentro de la
# imagen, entra con autologin en tty1 (y en ttyS0, para QEMU headless) y
# ofrece el comando basico de Linux mas `titan` / `fastfetch`.
#
# Variables de entorno que fija scripts/build-iso.sh:
#   TITAN_VERSION   version de la ISO (por defecto 0.1.0)
#   TITAN_CODENAME  apodo de la release
#   TITAN_REPO      ruta del repositorio local con linux-titanlinux

iso_name="titan-linux"
iso_label="TITAN_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Titan Linux Project <https://github.com/titan-linux>"
iso_application="Titan Linux"
iso_version="${TITAN_VERSION:-0.1.0}"
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
  # La pantalla grafica del instalador. Sin esta entrada llega a la ISO como
  # 0644, y 'ventana()' la busca con '-x' para decidir si puede abrirla: con el
  # permiso que no tiene se cae al modo de texto sin dar ninguna pista, y en
  # una maquina con tarjeta el usuario ve como el instalador grafico no existe.
  ["/root/instalador/ventana-gui.py"]="0:0:755"
  # /root a 0750 como en el paquete 'filesystem'; si no, pacman avisa de que los
  # permisos del directorio no cuadran con su .MTREE.
  ["/root/"]="0:0:750"
  ["/usr/local/bin/titan-shell"]="0:0:755"
  ["/usr/local/bin/titan-finder"]="0:0:755"
  ["/usr/local/bin/titan-fotos"]="0:0:755"
  ["/usr/local/bin/titan-musica"]="0:0:755"
  ["/usr/local/bin/titan-terminal"]="0:0:755"
  ["/usr/local/bin/titan-settings"]="0:0:755"
  ["/usr/local/bin/onlyoffice-desktopeditors"]="0:0:755"
  ["/opt/onlyoffice/DesktopEditors.AppImage"]="0:0:755"
  ["/etc/skel/.config/labwc/autostart"]="0:0:755"
)
