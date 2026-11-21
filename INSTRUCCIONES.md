# TITAN LINUX / INTI OS (1.8.0) - GUÍA MAESTRA DE COMANDOS E INSTRUCCIONES

Esta guía contiene todos los comandos y procedimientos necesarios para mantener el proyecto **al corriente, compilarlo, verificarlo, probarlo en máquina virtual y generar la imagen ISO final**.

---

## 📋 1. Requisitos Previos e Instalación de Dependencias

El proyecto está diseñado para compilarse y mantenerse sobre cualquier sistema basado en **Arch Linux** o **CachyOS**.

### Instalar todas las herramientas de compilación
Ejecuta en la raíz del proyecto:

```bash
make deps
```

*(O de forma directa mediante `pacman`):*
```bash
sudo pacman -S --needed \
  base-devel git cmake archiso devtools arch-install-scripts \
  erofs-utils mtools dosfstools rust cargo qt6-base qt6-declarative \
  qt6-wayland qt6-svg qt6-multimedia layer-shell-qt wayland \
  wayland-protocols tmux qemu-desktop edk2-ovmf
```

---

## 🔍 2. Verificación de Salud del Proyecto (Tests Automatizados)

Antes de realizar cambios o compilar la ISO, ejecuta la suite de verificación para asegurarte de que ningún componente tenga errores de sintaxis, dependencias rotas o capas QML defectuosas:

```bash
# 1. Comprobación integral del escritorio (11 apps, QML, binarios y LayerShell)
./verify/comprobar-escritorio.sh

# 2. Comprobación de reglas del sistema base (customize_airootfs)
./verify/comprobar-customize.sh

# 3. Comprobación de telemetría de hardware (Acerca de este Mac/Sistema)
./verify/comprobar-acerca.sh
```

> **Resultado esperado:**  
> `Total de pruebas exitosas: 28`  
> `Total de fallos: 0`

---

## 🛠️ 3. Compilación de Aplicaciones

El código fuente de todas las aplicaciones reside en `apps/`. Cada aplicación se compila e instala automáticamente en `iso/titan/airootfs/usr/local/bin/`.

### Compilar toda la suite de aplicaciones a la vez:
```bash
make apps
```

### Compilar una aplicación específica de forma individual:
Si modificas el código de una sola aplicación (por ejemplo en su archivo `.qml` o `.cpp`), puedes compilarla individualmente para ahorrar tiempo:

```bash
# Titan Shell (TopBar, Dock, Dynamic Island, Launcher, Pantalla de Bloqueo)
cd apps/titan-shell && qmake6 titan-shell.pro && make -j$(nproc)
install -m 0755 titan-shell ../../iso/titan/airootfs/usr/local/bin/ && cd ../..

# Titan Finder (Explorador de archivos con selección elástica)
cd apps/titan-finder && qmake6 titan-finder.pro && make -j$(nproc)
install -m 0755 titan-finder ../../iso/titan/airootfs/usr/local/bin/ && cd ../..

# Titan Settings (Panel de Ajustes: Wi-Fi, Bluetooth, Idioma, Pantalla)
cd apps/titan-settings && qmake6 titan-settings.pro && make -j$(nproc)
install -m 0755 titan-settings ../../iso/titan/airootfs/usr/local/bin/ && cd ../..

# Titan Installer (Instalador gráfico con prioridad UEFI 1 y expulsión USB)
cd apps/titan-installer && qmake6 titan-installer.pro && make -j$(nproc)
install -m 0755 titan-installer ../../iso/titan/airootfs/usr/local/bin/ && cd ../..

# Titan Fotos (Visor de imágenes)
cd apps/titan-fotos && qmake6 titan-fotos.pro && make -j$(nproc)
install -m 0755 titan-fotos ../../iso/titan/airootfs/usr/local/bin/ && cd ../..

# Titan Música (Reproductor de audio con metadatos)
cd apps/titan-musica && qmake6 titan-musica.pro && make -j$(nproc)
install -m 0755 titan-musica ../../iso/titan/airootfs/usr/local/bin/ && cd ../..

# Titan Terminal
cd apps/titan-terminal && qmake6 titan-terminal.pro && make -j$(nproc)
install -m 0755 titan-terminal ../../iso/titan/airootfs/usr/local/bin/ && cd ../..

# Herramienta CLI en Rust (titan)
cd apps/titan-cli && cargo build --release
install -m 0755 target/release/titan ../../iso/titan/airootfs/usr/local/bin/ && cd ../..
```

---

## 💿 4. Construcción de la Imagen ISO (*Bootable Live ISO*)

Para construir la imagen ISO híbrida completa (con el kernel propio `linux-titanlinux`, Labwc, Titan Shell, instalador y aplicaciones preinstaladas):

```bash
sudo make iso
```
*(O de forma directa: `sudo ./scripts/build-iso.sh`)*

### ¿Qué hace este comando automáticamente?
1. Limpia cualquier montaje huérfano de compilaciones anteriores de forma recursiva y segura (`umount -R`).
2. Sincroniza el repositorio local del kernel propio (`kernel/linux-titanlinux/linux-titanlinux-6.18.54-1-x86_64.pkg.tar.zst`).
3. Construye el sistema raíz (`airootfs`) mediante `mkarchiso`.
4. Aplica las configuraciones de Labwc, temas visuales *Titan-macOS*, iconos y reglas de hardware.
5. Deposita la imagen ISO terminada en la carpeta:  
   `out/inti-os-1.8-x86_64.iso` (o `out/titan-linux-*.iso`).

---

## 🖥️ 5. Prueba de la ISO en Máquina Virtual (QEMU con UEFI)

Puedes probar la imagen recién construida directamente en tu escritorio sin reiniciar la computadora física:

### Arranque con aceleración estándar:
```bash
make qemu
# o directamente:
./scripts/run-qemu.sh
```

### Arranque con compatibilidad por software (ideal dentro de VMs o entornos sin GPU 3D):
```bash
make qemu-vmware
# o directamente:
TITAN_QEMU_SOFTWARE=1 ./scripts/run-qemu.sh
```

---

## 💾 6. Grabar la ISO en una Memoria USB para Instalación Real

Una vez generada la ISO, puedes grabarla en un pendrive USB para instalar Inti OS en cualquier PC o laptop física:

### Método 1: Por terminal con `dd` (El más recomendado y limpio):
Identifica tu memoria USB con `lsblk` (por ejemplo `/dev/sdb`, **nunca el disco principal `/dev/nvme0n1` o `/dev/sda`**):

```bash
sudo dd if=out/inti-os-1.8-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```
*(Reemplaza `/dev/sdX` por la letra real de tu memoria USB).*

### Método 2: Por interfaz gráfica:
- En Linux/Windows: Puedes usar **BalenaEtcher**, **Raspberry Pi Imager** o **Rufus** (en modo *DD Image*).
- O copiar el archivo `.iso` directamente dentro de una memoria formateada con **Ventoy**.

---

## ⚙️ 7. Mantenimiento del Kernel Propio (`linux-titanlinux`)

El kernel propio se encuentra en `kernel/linux-titanlinux/`.  
**Nota:** El proyecto ya incluye el kernel precompilado (`linux-titanlinux-6.18.54-1-x86_64.pkg.tar.zst`), por lo que **no necesitas compilarlo cada vez que construyes la ISO**.

Si deseas modificar el kernel, aplicar parches o actualizarlo:
```bash
cd kernel/linux-titanlinux

# Modificar opciones del kernel
make menuconfig

# Recompilar el paquete completo con makepkg
makepkg -s -f

cd ../..
```

---

## 🧹 8. Limpieza de Almacenamiento y Archivos Temporales

Para liberar gigabytes de espacio ocupado por compilaciones pasadas o temporales:

```bash
# 1. Limpiar objetos de compilación en apps/
make clean

# 2. Eliminar ISOs antiguas generadas
rm -f out/*.iso
rm -rf out_root/

# 3. Eliminar discos virtuales temporales de prueba QEMU
rm -f run/*.raw run/*.qcow2

# 4. Eliminar directorios temporales de compilación Qt
find apps -name "build" -type d -exec rm -rf {} + 2>/dev/null
```

---

## 📦 9. Empaquetar el Proyecto para Respaldo o Traslado en ZIP

Para transportar todo el código fuente y el kernel compilado a otra máquina (sin incluir ISOs pesadas de varios gigabytes):

```bash
cd /home/isai/Proyectos && zip -r -1 /home/isai/titan-linux.zip titan-linux \
  -x "*.git*" \
  -x "*.iso" \
  -x "*.raw" \
  -x "*.qcow2" \
  -x "*__pycache__*" \
  -x "*.pyc" \
  -x "titan-linux/out/*" \
  -x "titan-linux/out_root/*" \
  -x "titan-linux/apps/*/build/*" \
  -x "titan-linux/apps/titan-cli/target/*"
```
El archivo quedará listo en `/home/isai/titan-linux.zip` (~975 MB).

---

## 🆘 10. Solución a Problemas Frecuentes

### 1. `Quedan montajes dentro de /home/.../build/archiso`:
Si cancelaste una compilación de ISO con `Ctrl + C`, quedan submontajes de chroot colgados.  
`build-iso.sh` ahora los desmonta automáticamente, pero si necesitas forzarlo manualmente como root:
```bash
sudo umount -R /home/isai/Proyectos/build/archiso/x86_64/airootfs/sys/firmware/efi/efivars 2>/dev/null || true
sudo umount -R /home/isai/Proyectos/build/archiso/x86_64/airootfs/proc 2>/dev/null || true
sudo umount -R /home/isai/Proyectos/build/archiso/x86_64/airootfs/sys 2>/dev/null || true
sudo umount -R /home/isai/Proyectos/build/archiso/x86_64/airootfs/dev 2>/dev/null || true
sudo rm -rf /home/isai/Proyectos/build/archiso
```

### 2. Error en tarjeta NVIDIA al arrancar:
El sistema ya cuenta con detección automática. En el menú de GRUB simplemente presiona **Enter** en la Opción 1. Si tu portátil es un modelo antiguo problemático, selecciona la **Opción 2: Modo compatibilidad gráfica**.
