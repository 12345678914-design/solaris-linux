# Titan Linux 0.1 — Guía de compilación y puesta en marcha

Este repositorio contiene el código fuente de **Titan Linux**, una distribución
derivada de Arch Linux con escritorio **Labwc** y aplicaciones gráficas propias
en **Qt 6 / QML** con aspecto macOS.

> Este README recoge las instrucciones de `INSTRUCCIONES.md`. La documentación
> técnica ampliada (kernel, ISO, verificaciones y arquitectura) está en
> [`README.en.md`](README.en.md).

## Contenido del repositorio

- `apps/` — aplicaciones propias: `titan-shell`, `titan-finder`,
  `titan-terminal`, `titan-panel`, `titan-desktop`, `titan-settings`,
  `titan-fotos`, `titan-musica`, `titan-acerca` y el CLI `titan-cli`.
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

## Paso 3: compilar la ISO de Titan Linux

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
3. Busca el paquete del kernel propio en
   `kernel/linux-titanlinux/linux-titanlinux-*.pkg.tar.zst` y lo integra en la
   imagen sin recompilar Linux.
4. Aplica la configuración de **Labwc** (ventanas flotantes, botones semáforo
   rojo/amarillo/verde y atajos de teclado).
5. Genera la ISO final en:

   ```text
   out_root/titan-linux-0.1.0-x86_64.iso
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

- `out/` — capturas, transcripciones e informes de verificación.
- `out_root/` — ISO generada y su `.sha256`.
- `build/archiso/` — árbol de trabajo de `mkarchiso` (se borra en cada build).
- `repo/` — repositorio local de paquetes usado durante la compilación.

Estos directorios son artefactos de build y no forman parte del código fuente.

## Créditos y aviso

Titan Linux es un proyecto derivado de Arch Linux. «Titan Linux» ya existe como
distribución basada en Ubuntu; no hay conflicto técnico, pero conviene elegir un
nombre distinto antes de publicar el proyecto de forma oficial.
