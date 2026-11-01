# Titan Linux 0.1 - Guía de Compilación y Puesta en Marcha

Esta carpeta contiene todo el código fuente de **Titan Linux**, sus aplicaciones gráficas en Qt 6 / QML al estilo macOS, la configuración del compositor de ventanas libres **Labwc**, y el paquete del **kernel propio ya compilado** (`linux-titanlinux`).

---

## 📋 Requisitos Previos

- Una máquina con **Arch Linux** instalada.
- Al menos **8 GB de espacio libre** en disco.
- Conexión a Internet (para que `mkarchiso` descargue la paquetería base de Arch).

---

## 🚀 Pasos para Compilar en una Nueva Máquina

### Paso 1: Instalar todas las dependencias
Desde la carpeta raíz del proyecto, ejecuta el siguiente comando:

```bash
make pacman
```

*(Esto instalará automáticamente: `archiso`, `devtools`, `rust`, `cargo`, `qt6-base`, `qt6-declarative`, `qt6-wayland`, `qt6-svg`, `layer-shell-qt`, `wayland`, `tmux`, `qemu-desktop` y `edk2-ovmf`)*.

---

### Paso 2: Asegurar mirrors rápidos de Arch (Recomendado)
Para evitar que `pacman` se quede colgado en mirrors lentos como `geo.mirror.pkgbuild.com`:

```bash
# Comentar mirror geo si está presente en el host:
sudo sed -i 's|^Server = https://geo.mirror.pkgbuild.com|# Server = https://geo.mirror.pkgbuild.com|' /etc/pacman.d/mirrorlist
```

---

### Paso 3: Compilar la ISO de Titan Linux

Ejecuta el script de construcción con permisos de superusuario:

```bash
sudo ./scripts/build-iso.sh
```

**¿Qué hace este script automáticamente?**
1. Compila las herramientas CLI en Rust (`apps/titan-cli`).
2. Compila las aplicaciones gráficas en Qt 6:
   - `titan-shell` (Barra superior estilo Mac, Dock con efecto de zoom y Launchpad).
   - `titan-finder` (Explorador de archivos con botones de semáforo).
   - `titan-terminal` (Terminal gráfica con pestañas).
   - `titan-panel` y `titan-desktop` (Fondo de escritorio y gestor de capas).
   - `titan-acerca` (Ventana de información del sistema).
3. Detecta automáticamente el paquete del kernel propio que ya viene incluido en `kernel/linux-titanlinux/linux-titanlinux-6.18.54-1-x86_64.pkg.tar.zst` y lo integra en la imagen sin necesidad de recompilar Linux.
4. Aplica la configuración de **Labwc** (ventanas libres flotantes, botones semáforo rojo/amarillo/verde y atajos de teclado).
5. Empaqueta la ISO final lista para usar en:
   `out/titan-linux-0.1.0-x86_64.iso`

---

### Paso 4: Probar la ISO en QEMU

Una vez terminada la compilación, puedes probar el sistema ejecutando:

```bash
./scripts/run-qemu.sh
# o simplemente:
make qemu
```

> **Nota:** Si estás dentro de una máquina virtual sin aceleración 3D en el host, ejecuta:
> ```bash
> make qemu-vmware
> # o:
> TITAN_QEMU_SOFTWARE=1 ./scripts/run-qemu.sh
> ```

---

## 🎨 Personalización y Assets (Iconos, Fondos y Fuentes)

Si deseas agregar o cambiar recursos visuales en la ISO antes de compilar:

1. **Fondos de pantalla (Wallpapers):**
   - Ruta: `iso/titan/airootfs/usr/share/backgrounds/titan/default.png`
2. **Iconos macOS (WhiteSur):**
   - Ruta: `iso/titan/airootfs/usr/share/icons/WhiteSur-dark/`
3. **Fuentes tipográficas (Inter o San Francisco):**
   - Ruta: `iso/titan/airootfs/usr/share/fonts/TTF/`
4. **Decoración de ventanas (Labwc):**
   - Ruta: `iso/titan/airootfs/etc/skel/.config/labwc/` y `iso/titan/airootfs/usr/share/themes/Titan-macOS/openbox-3/`
