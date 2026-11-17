# Solaris Linux 1.8 — Guía de compilación y puesta en marcha

Este repositorio contiene el código fuente de **Solaris Linux**, una distribución
derivada de Arch Linux con escritorio **Labwc** y aplicaciones gráficas propias
en **Qt 6 / QML** con aspecto macOS.

> Los nombres internos `titan-*` y `linux-titanlinux` se conservan por
> compatibilidad con el árbol de código y los paquetes existentes.

> Este README recoge las instrucciones de `INSTRUCCIONES.md`. La documentación
> técnica ampliada (kernel, ISO, verificaciones y arquitectura) está en
> [`README.en.md`](README.en.md).

## ACTUALIZACIÓN: ABIERTAS COMPATIBILIDADES

Esta versión amplía el soporte de hardware y el arranque en equipos modestos,
máquinas virtuales y GPUs sin aceleración 3D:

- **Nuevos drivers Vulkan**: `vulkan-nouveau` para las GPU NVIDIA con el driver
  libre Nouveau y `vulkan-swrast` como respaldo de renderizado por software.
- **Gráficos**: `mesa`, `vulkan-intel`, `vulkan-radeon`, `intel-media-driver` y
  `libva-intel-driver` para aceleración Intel/AMD; `mesa-utils` para diagnóstico.
- **Firmware**: `linux-firmware`, `linux-firmware-whence`, `sof-firmware`,
  `alsa-firmware` e `intel-ucode` para Wi-Fi, Bluetooth, audio y microcódigo.
- **Red y Bluetooth**: `networkmanager`, `wpa_supplicant`, `iw`, `bluez` y
  `bluez-utils`.
- **Audio**: PipeWire con `pipewire-pulse`, `pipewire-alsa`, `pipewire-jack` y
  `wireplumber`.
- **Modo compatibilidad gráfica**: nueva entrada de arranque (`titan.compat=1
  nomodeset`) para QEMU/KVM, VMware, VirtualBox, Hyper-V, Xen, Intel Celeron y
  equipos sin `/dev/dri/renderD*`. Usa pixman/llvmpipe, fuerza renderizado por
  software y reintenta automáticamente si falla el arranque acelerado.
- **Kernel 6.18.54 LTS**: incluye la base de drivers de Arch Linux (VirtIO,
  NVMe/AHCI, USB, Ethernet Intel/Realtek, Wi-Fi y Bluetooth habituales).

## Contenido del repositorio

- `apps/` — aplicaciones propias: `titan-shell`, `titan-finder`,
  `titan-terminal`, `titan-panel`, `titan-desktop`, `titan-settings`,
  `titan-fotos`, `titan-musica`, `titan-acerca`, `titan-calc`,
  `titan-calendar`, `titan-clock`, `titan-video` y el CLI `titan-cli`.
- `iso/titan/` — perfil de `archiso`, configuración del sistema, tema de Labwc,
  iconos, fondos y scripts del instalador.
- `kernel/linux-titanlinux/` — receta del kernel propio (`PKGBUILD`, parches y
  configuración).
- `scripts/` — compilación de la ISO, arranque en QEMU y verificación.
- `verify/` — comprobadores del instalador, del escritorio y del arranque.
- `config/`, `Makefile`, `setup.sh` — configuración y automatización del build.

**No se versionan** la imagen ISO final, el árbol `build/`, los binarios
compilados, los paquetes del kernel (`*.pkg.tar.zst`), el AppImage de OnlyOffice
ni los archivos comprimidos del proyecto. Se regeneran con los pasos de abajo.

## Requisitos previos

- Una máquina con **Arch Linux** (o una derivada compatible, como CachyOS)
  instalada de forma nativa. El kernel no se puede compilar desde Windows.
- Al menos **8 GB de espacio libre** en disco para la ISO; si además compilas el
  kernel, reserva unos **15 GB** más.
- Conexión a Internet: `mkarchiso` descarga la paquetería base de Arch.
- **Secure Boot desactivado**, o el kernel sin firmar no arrancará.

## Paso 1: instalar las dependencias

Desde la raíz del proyecto:

```bash
make pacman
```

Esto instala, entre otros: `base-devel`, `archiso`, `devtools`,
`arch-install-scripts`, `rust`, `cargo`, `qt6-base`, `qt6-declarative`,
`qt6-wayland`, `qt6-svg`, `qt6-multimedia`, `layer-shell-qt`, `wayland`,
`wayland-protocols`, `tmux`, `qemu-desktop` y `edk2-ovmf`.

## Paso 2: usar mirrors rápidos de Arch (recomendado)

Para evitar que `pacman` se quede colgado en mirrors lentos como
`geo.mirror.pkgbuild.com`:

```bash
sudo sed -i 's|^Server = https://geo.mirror.pkgbuild.com|# Server = https://geo.mirror.pkgbuild.com|' /etc/pacman.d/mirrorlist
```

## Paso 3: compilar la ISO de Solaris Linux

```bash
sudo ./scripts/build-iso.sh
```

El script realiza automáticamente estas tareas:

1. Compila la herramienta CLI en Rust (`apps/titan-cli`).
2. Compila las aplicaciones gráficas en Qt 6:
   - `titan-shell` — barra superior estilo macOS, Dock con zoom y Launchpad.
   - `titan-finder` — explorador de archivos con botones de semáforo.
   - `titan-terminal` — terminal gráfica con pestañas.
   - `titan-panel` y `titan-desktop` — fondo de escritorio y gestor de capas.
   - `titan-settings`, `titan-fotos`, `titan-musica` y `titan-acerca`.
   - `titan-calc`, `titan-calendar`, `titan-clock` y `titan-video`.
3. Busca el paquete del kernel propio en
   `kernel/linux-titanlinux/linux-titanlinux-*.pkg.tar.zst` y lo integra en la
   imagen sin recompilar Linux.
4. Aplica la configuración de **Labwc** (ventanas flotantes, botones semáforo
   rojo/amarillo/verde y atajos de teclado).
5. Genera la ISO final en:

   ```text
   out/solaris-linux-1.8-x86_64.iso
   ```

### Si no existe el paquete del kernel

El paquete precompilado no se incluye en el repositorio por su tamaño. Si
`build-iso.sh` avisa de que no hay kernel propio, la ISO se construye igualmente
con el kernel de Arch. Para incluir el kernel Titan, compílalo antes:

```bash
cd kernel/linux-titanlinux
TITAN_NO_HTMLDOCS=1 makepkg -j"$(nproc)"
cd ../..
```

El resultado (`linux-titanlinux-6.18.54-1-x86_64.pkg.tar.zst`) se detecta solo en
la siguiente ejecución de `./scripts/build-iso.sh`.

También puedes forzar una ISO sin kernel propio mientras iteras:

```bash
sudo ./scripts/build-iso.sh --no-kernel
```

## Paso 4: probar la ISO en QEMU

Si ya tienes la ISO publicada (por ejemplo, después de unir las partes del
release), puedes arrancarla directamente con:

```bash
qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 4096 \
  -machine q35 -device virtio-vga \
  -cdrom "solaris-linux-1.8-x86_64.iso"
```

> `-enable-kvm` requiere `/dev/kvm` y permisos sobre él. Si no está disponible,
> elimina esa opción. `-machine q35` arranca en modo BIOS; para UEFI añade la
> BIOS de OVMF (`-bios /usr/share/edk2/x64/OVMF.4m.fd`).

También puedes usar el script del repositorio, que detecta la ISO compilada:

```bash
./scripts/run-qemu.sh
# o simplemente:
make qemu
```

Si estás dentro de una máquina virtual sin aceleración 3D en el host:

```bash
make qemu-vmware
# o:
TITAN_QEMU_SOFTWARE=1 ./scripts/run-qemu.sh
```

Opciones útiles de `run-qemu.sh`:

```bash
./scripts/run-qemu.sh --bios              # arranque BIOS (syslinux)
./scripts/run-qemu.sh --headless          # consola serie, sin ventana
./scripts/run-qemu.sh --disk 20G          # añade un disco para instalar
./scripts/run-qemu.sh --serial-log boot.log
./scripts/run-qemu.sh --resolution 1366x768
```

La ventana sigue la resolución del monitor del host. Si la detección falla, se
usa 1280x720.

## Verificar la ISO

```bash
./scripts/verify-qemu.sh
./scripts/verify-qemu.sh --bios --timeout 1200
```

El verificador arranca la ISO sin ventana, espera al shell por la consola serie
y ejecuta dentro del sistema las comprobaciones del catálogo de comandos,
`fastfetch`, `titan`, `titan doctor` y una instalación real con `pacman`. Deja
transcripción, informe JSON y capturas en `out/verify/`, y termina con error si
alguna comprobación falla.

También puedes verificar los componentes del escritorio y aplicaciones de la ISO:

```bash
./verify/comprobar-escritorio.sh
```

## Resolución técnica de problemas y compatibilidad NVIDIA / Multi-GPU

### 1. Error «CPU ISA level is lower than required»

#### Causa técnica
Al iniciar aplicaciones gráficas como `titan-acerca`, `titan-desktop`, `titan-calc`, `titan-calendar`,
`titan-clock`, `titan-video` o `titan-installer` (o al correr `./verify/comprobar-escritorio.sh`),
el cargador dinámico de `glibc` (`ld.so`) abortaba la ejecución con:

```text
CPU ISA level is lower than required
```

Este fallo ocurre cuando los binarios ELF fueron enlazados o compilados con marcas
de nivel de microarquitectura x86-64 elevadas (por ejemplo, `x86-64-v4`, común al
usar repositorios optimizados para CachyOS o flags como `-march=x86-64-v4` que requieren
extensiones **AVX-512**).

Si la máquina anfitriona cuenta con procesadores que soportan hasta `x86-64-v3`
(como Intel Core de 12ª, 13ª o 14ª generación con arquitectura híbrida donde los
núcleos E deshabilitan AVX-512, o CPUs AMD anteriores a Zen 4), el procesador no
cumple el requerimiento de la cabecera ELF y la aplicación no puede arrancar.

#### Archivos y líneas modificadas para la solución
- **`Makefile`**:
  - Línea 61: adición de `apps/titan-installer` a la lista de dependencias del objetivo `apps`.
  - Líneas 96 y 107: copia directa de los binarios compatibles compilados en `build/` hacia `apps/titan-desktop` y `apps/titan-acerca`.
  - Líneas 135–139: regla de compilación nativa de `titan-installer` mediante `qmake6` e instalación en `iso/titan/airootfs/usr/local/bin/`.
  - Líneas 181–187: ampliación de la regla `clean` para limpiar ejecutables obsoletos de todas las apps (`titan-calc`, `titan-calendar`, `titan-clock`, `titan-video`, `titan-installer`, etc.).
- **`verify/comprobar-escritorio.sh`**:
  - Líneas 76–79 y 85–88: detección automática y priorización del binario compatible recién generado en `build/` si está más actualizado.
- **`iso/titan/airootfs/usr/local/bin/`**:
  - Reemplazo y actualización de los binarios compilados bajo baseline x86-64 compatible sin dependencias de AVX-512.

---

### 2. Soporte universal para tarjetas NVIDIA (RTX 20/30/40/50 Series) y Multi-GPU

Para garantizar arranque fluido tanto en tarjetas dedicadas NVIDIA modernas como en laptops híbridas (Intel/AMD + NVIDIA) bajo Wayland (`labwc`):

#### Archivos y líneas modificadas para la solución
- **`iso/titan/airootfs/etc/modprobe.d/nvidia.conf`**:
  - Líneas 1–6: configuración de `options nvidia-drm modeset=1 fbdev=1` (obligatorio para framebuffer DRM en Wayland) y `options nvidia NVreg_PreserveVideoMemoryAllocations=1` (gestión de memoria de video y suspensión).
- **`iso/titan/grub/grub.cfg`**:
  - Líneas 60 y 72: inclusión de los parámetros `nvidia-drm.modeset=1 nvidia-drm.fbdev=1` en los comandos de arranque del kernel en UEFI.
- **`iso/titan/syslinux/syslinux-linux.cfg`**:
  - Líneas 13 y 25: inclusión de `nvidia-drm.modeset=1 nvidia-drm.fbdev=1` en los comandos de arranque BIOS.
- **`iso/titan/airootfs/etc/profile.d/15-titan-grafico.sh`**:
  - Líneas 122–125: comprobación proactiva y carga de `nvidia-drm` vía `modprobe` al detectar hardware NVIDIA.
  - Líneas 190–204: detección dinámica de múltiples tarjetas de video (`/sys/class/drm/card*`) y configuración automática de `WLR_DRM_DEVICES="/dev/dri/cardX:/dev/dri/cardY"` para soporte multi-GPU transparente en Wayland.
  - Líneas 210–221: aceleración de hardware para decodificación de video directa con `NVD_BACKEND=direct` y `LIBVA_DRIVER_NAME=nvidia`.

---

### 3. Aislamiento y solución a errores de E/S en la construcción de la ISO (`make iso`)

Durante `mkarchiso`, el kernel del sistema anfitrión podía reportar errores de Entrada/Salida en controladores de red virtuales de sysfs (`/sys/module/realtek/drivers`), o dejar montajes ocupados que colgaban el empaquetado:

#### Archivos y líneas modificadas para la solución
- **`iso/titan/airootfs/root/customize_airootfs.sh`**:
  - Líneas 805–809: desmontaje perezoso (`umount -l`) de `/sys/firmware/efi/efivars` y `/sys` antes de salir del chroot.
- **`scripts/build-iso.sh`**:
  - Líneas 632–652: creación de wrapper defensivo para `find` que descarta fallos espurios de sysfs del host.
  - Líneas 654–674: monitor en segundo plano para liberar montajes virtuales retenidos por el sistema.
  - Líneas 676–686: ejecución de `mkarchiso` dentro de un espacio de nombres privado (`unshare -m --propagation private`) evitando conflictos con los demonios del host.



## Personalización de recursos visuales

Antes de compilar la ISO puedes cambiar los recursos en:

1. **Fondos de pantalla:**
   `iso/titan/airootfs/usr/share/backgrounds/titan/default.png`
2. **Iconos macOS (WhiteSur):**
   `iso/titan/airootfs/usr/share/icons/WhiteSur-dark/`
3. **Fuentes tipográficas (Inter o San Francisco):**
   `iso/titan/airootfs/usr/share/fonts/TTF/`
4. **Decoración de ventanas (Labwc):**
   `iso/titan/airootfs/etc/skel/.config/labwc/` y
   `iso/titan/airootfs/usr/share/themes/Titan-macOS/openbox-3/`

## Comandos útiles

```bash
make help        # lista todos los objetivos
make apps        # compila todas las aplicaciones
make iso         # reconstruye la ISO (equivale a sudo ./scripts/build-iso.sh)
make qemu        # arranca la ISO en QEMU
make clean       # limpia artefactos de compilación
```

## Estructura de compilación

- `out/` — ISO generada, su `.sha256`, capturas e informes de verificación.
- `out_root/` — ISO antigua de Titan Linux (solo se conserva como referencia).
- `build/archiso/` — árbol de trabajo de `mkarchiso` (se borra en cada build).
- `repo/` — repositorio local de paquetes usado durante la compilación.

Estos directorios son artefactos de build y no forman parte del código fuente.

## Créditos y aviso

Solaris Linux es un proyecto derivado de Arch Linux. Los nombres internos
`titan-*` y `linux-titanlinux` se mantienen para no romper paquetes, rutas y
aplicaciones existentes.
