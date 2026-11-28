# INFORME TÉCNICO DE INGENIERÍA: CREACIÓN DE UN SISTEMA OPERATIVO BASADO EN EL KERNEL DE LINUX

**Proyecto:** Titan Linux / Inti OS  
**Versión del Entorno:** Titan Shell 1.8.0  
**Fecha de Publicación:** 14 de Noviembre de 2026  
**Autor:** Equipo de Desarrollo de Titan Linux  

---

## 1. Introducción y Fundamentos Arquitectónicos

Crear un sistema operativo desde cero utilizando el kernel de Linux no significa programar un núcleo desde cero, sino diseñar, ensamblar, compilar e integrar todos los subsistemas necesarios para transformar un **núcleo monolítico** en una plataforma funcional, productiva y coherente para el usuario final.

El kernel de Linux, por sí solo, es únicamente un administrador de recursos: gestiona la memoria, asigna tiempo de CPU a los hilos, interactúa con el hardware mediante controladores y expone una interfaz estandarizada de llamadas al sistema (*syscalls*). Para convertir este núcleo en un sistema operativo completo se requiere una jerarquía estricta de componentes interconectados:

```
+-----------------------------------------------------------------+
|                   APLICACIONES DE USUARIO                       |
|   (Finder, Ajustes, Navegador, Reproductor, Terminal, etc.)     |
+-----------------------------------------------------------------+
|              ENTORNO DE ESCRITORIO / SHELL (QML/Qt6)            |
|         (TopBar, Dock, Dynamic Island, Launcher, GlassPanel)     |
+-----------------------------------------------------------------+
|            SERVIDOR GRÁFICO / COMPOSITOR WAYLAND                |
|                    (Labwc / wlroots / KMS / DRM)                |
+-----------------------------------------------------------------+
|                      SISTEMA BASE / USERLAND                    |
|       (systemd, D-Bus, Udev, NetworkManager, Coreutils, Glibc)  |
+-----------------------------------------------------------------+
|                         INITRAMFS / INIT                        |
|                  (Montaje del Rootfs, Carga de Módulos)         |
+-----------------------------------------------------------------+
|                     KERNEL DE LINUX PROPIO                      |
|          (Drivers DRM, Planificador, VFS, Memoria, Red)         |
+-----------------------------------------------------------------+
|                     GESTOR DE ARRANQUE (GRUB)                   |
|                        (Firmware UEFI / BIOS)                   |
+-----------------------------------------------------------------+
|                            HARDWARE                             |
|              (CPU, RAM, GPU Intel/AMD/NVIDIA, NVMe, Wi-Fi)      |
+-----------------------------------------------------------------+
```

---

## 2. Metodología para Crear un Sistema Operativo desde Cero usando Linux

Para construir un sistema operativo desde cero se deben seguir nueve fases de ingeniería:

### Fase 1: Cadena de Herramientas de Compilación (*Toolchain*)
Antes de compilar el sistema, se requiere una cadena cruzada (*cross-toolchain*) aislada del sistema anfitrión:
- **Compiladores:** `gcc`, `g++`, `clang` y `rustc` (el kernel de Linux moderno soporta subsistemas en Rust).
- **Herramientas binarias:** `binutils` (`ld`, `as`, `ar`, `strip`, `objdump`).
- **Biblioteca de C estándar:** `glibc` o `musl` (provee las primitivas que conectan el software de usuario con las syscalls del kernel).
- **Herramientas de construcción:** `make`, `cmake`, `qmake6`, `ninja`, `pkg-config`, `cargo`.

### Fase 2: Configuración y Compilación del Kernel de Linux
Se descarga el árbol de código fuente oficial desde [kernel.org](https://www.kernel.org). Se genera el archivo de configuración `.config`, se ajustan los parámetros de rendimiento, planificador, compresión y controladores embebidos, y se compila generando el binario comprimido `vmlinuz` y los módulos dinámicos `.ko`.

### Fase 3: Jerarquía del Sistema de Ficheros (*FHS*) y Rootfs
Se crea la estructura canónica del estándar FHS (*Filesystem Hierarchy Standard*):
- `/bin`, `/sbin`, `/lib`, `/lib64` (generalmente enlazados simbólicamente a sus equivalentes dentro de `/usr` en sistemas modernos *UsrMerge*).
- `/usr` (código fuente, librerías compartidas y binarios del sistema).
- `/etc` (configuración del sistema y demonios).
- `/var` (datos variables, logs, caches de paquetes).
- `/dev` (nodos de dispositivos manejados por `udev`).
- `/proc` y `/sys` (pseudo-sistemas de ficheros virtuales del kernel para introspección y control en tiempo de ejecución).
- `/run` y `/tmp` (almacenamiento volátil en memoria RAM mediante `tmpfs`).

### Fase 4: El Sistema de Inicio (*Init System* / PID 1)
Cuando el kernel termina su inicialización en hardware, lanza el proceso con ID 1. Este proceso es responsable de:
- Inicializar dispositivos en paralelo y cargar reglas dinámicas de hardware (`systemd-udevd`).
- Configurar el reloj del hardware, el nombre de equipo (*hostname*) y los montajes de discos (`/etc/fstab`).
- Levantar los sockets de comunicación inter-proceso (`dbus`).
- Iniciar los servicios de red (`NetworkManager`, `iwd`), sonido (`pipewire`, `wireplumber`) y gestión de sesiones de usuario (`systemd-logind`).

### Fase 5: Servidor Gráfico y Compositor Wayland
Atrás quedó el legado de X11. Un sistema operativo moderno implementa la arquitectura Wayland:
- **KMS (*Kernel Mode Setting*) y DRM (*Direct Rendering Manager*):** El kernel toma el control de la resolución y búferes de vídeo nativos directamente en el arranque.
- **EGL / GBM (*Generic Buffer Management*):** API para asignar y compartir superficies gráficas aceleradas entre la GPU y los clientes.
- **Compositor:** En nuestro caso se eligió **Labwc** (basado en la biblioteca modular `wlroots`), el cual ofrece una integración ultraligera, soporte estricto para protocolos Wayland, bajo consumo de memoria RAM y configuración declarativa en XML.

### Fase 6: Entorno de Escritorio y Capa de Shell (*Desktop Environment*)
Se construye la interfaz con la que interactuará el usuario. Se emplea **Qt 6**, **QML (Qt Modeling Language)** y **LayerShellQt** (protocolo `wlr-layer-shell` de Wayland) para fijar paneles, barras y escritorios directamente contra las capas del compositor con aceleración por hardware.

### Fase 7: Aplicaciones Nativas del Ecosistema
Un sistema operativo necesita herramientas para tareas fundamentales: navegación por ficheros, configuración del sistema, instalación de paquetes, terminal, visor multimedia y reproducción de audio/vídeo. Todas deben compartir un diseño visual unificado, temas coherentes y respuestas a eventos de hardware (conexión de redes, inserción de USBs, batería, brillo y volumen).

### Fase 8: Instalador y Gestor de Arranque
Para que el sistema sea desplegable en discos físicos:
- Se desarrollan scripts o aplicaciones gráficas capaces de particionar discos en esquemas GPT o MBR, formatear en sistemas de archivos modernos (`ext4`, `btrfs`), instalar el sistema base mediante `pacstrap` o descompresión de imagen, y configurar usuarios y contraseñas.
- Se instala y configura **GRUB** en modo dual: UEFI (`BOOTX64.EFI`) y BIOS tradicional (`i386-pc`), y se inscribe la entrada en las variables NVRAM de la placa base mediante `efibootmgr`.

### Fase 9: Creación del Medio de Instalación (*Live ISO*)
Se empaqueta el sistema en una imagen híbrida ISO 9660:
- Utiliza **OverlayFS** para superponer un sistema de archivos de escritura en memoria RAM (`tmpfs`) sobre un sistema de archivos base comprimido de solo lectura (**EROFS** o **SquashFS**).
- Permite probar el sistema completo en modo "Live" directamente desde una memoria USB antes de instalarlo en el almacenamiento permanente.

---

## 3. Lo que se ha Hecho Hasta Ahora en el Proyecto Titan Linux / Inti OS

A lo largo del desarrollo del proyecto se han implementado hitos fundamentales de ingeniería:

### 3.1. Núcleo Personalizado `linux-titanlinux`
- Se construyó el paquete del kernel basado en la rama LTS 6.18 (`6.18.54-1-titanlinux`).
- Se aplicaron parches de estabilidad, control de espacios de nombres de usuario no privilegiados (`CLONE_NEWUSER`) y optimización de asignaciones atómicas en el controlador gráfico `amdgpu`.
- Se configuró con `PREEMPT_DYNAMIC` para balancear rendimiento en escritorio y latencia interactiva baja.
- Se compilaron y empaquetaron tanto el kernel como las cabeceras completas (`linux-titanlinux-headers`).

### 3.2. Pila Gráfica de Vanguardia con Labwc y LayerShellQt
- Se configuró **Labwc** como compositor Wayland ligero con atajos de teclado y gestos idénticos a macOS (Super+Espacio para Spotlight/Launchpad, Alt+Tab para selector de ventanas, Super+T para Terminal, Super+Q para cerrar ventana).
- Se diseñó el tema nativo `Titan-macOS` con soporte de esquinas redondeadas (`cornerRadius: 10`) y botones de ventana alineados a la izquierda (`close,iconify,max:`).
- Se corrigieron los argumentos obsoletos de previsualización en `rc.xml` eliminando cualquier error de inicialización gráfica.

### 3.3. Entorno de Escritorio Nativo: `titan-shell` (1.8.0)
- **TopBar:** Barra superior flotante con menú del sistema, integración con Dynamic Island para estado de reproducción, indicadores de volumen, batería, red, selector de temas y reloj inteligente.
- **Dock Flotante:** Efecto de magnificación interactivo al pasar el cursor, indicadores de aplicaciones abiertas, badges de estado y persistencia de aplicaciones favoritas.
- **Dynamic Island:** Notificador dinámico en píldora que se expande para alertas del sistema, cambios de volumen y control de música multimedia.
- **Launcher / Launchpad:** Rejilla completa con animaciones suaves para buscar y lanzar todas las aplicaciones de escritorio `.desktop`.
- **Selector de Fondos y Temas:** Capacidad de alternar al instante entre fondos de pantalla dinámicos y entre **Modo Claro** y **Modo Oscuro** con atajo global `Super + Shift + D`.
- **Pantalla de Bloqueo (`LockScreen.qml`):** Bloqueo seguro activado por inactividad o atajo `Super + L`, con autenticación y desenfoque del escritorio.
- **Botón de Candado en Menú de Apagado:** Acceso directo a la pantalla de bloqueo junto a suspender, reiniciar y apagar.
- **Animación de Carga Inicial (`BootSplash.qml`):** Cortina protectora que opaca la pantalla mientras el servidor gráfico termina de cargar la geometría del escritorio, evitando parpadeos visuales al arrancar.

### 3.4. Componente de Diseño Unificado: `GlassPanel.qml`
- Se integró el componente de vidrio esmerilado (*Liquid Glass*) en **todas** las aplicaciones del proyecto:
  - Desenfoque traslúcido reactivo al tema (*blur* y *noise texture*).
  - Bordes con iluminación especular interior y exterior (`glow`).
  - Degradados adaptativos para Modo Claro (blanco traslúcido) y Modo Oscuro (grafito profundo).
  - Protección absoluta contra dimensiones nulas (`width <= 0 || height <= 0`) en buffers offscreen para evitar advertencias de OpenGL/Mesa.

### 3.5. Suite Completa de Aplicaciones Nativas en Qt6/C++
1. **`titan-finder`:** Gestor de archivos estilo macOS con barra lateral rápida, panel de navegación por migas de pan (*breadcrumbs*), selector de archivos con rectángulo visual elástico para selección múltiple, integración de iconos nativos `.icns`, visor de carpetas y arrastre seguro.
2. **`titan-settings`:** Centro de control del sistema:
   - **Wi-Fi:** Escaneo en vivo con `nmcli`, visualización de intensidad de señal y cifrado, conexión mediante diálogo de contraseña integrado y conmutador general de radio.
   - **Bluetooth:** Control de hardware mediante `bluetoothctl` y `rfkill`, escaneo de dispositivos y conexión interactiva.
   - **Idioma del Sistema:** Conmutador multilingüe entre Español (`es_ES.UTF-8`), Inglés (`en_US.UTF-8`) y Quechua (`quz_PE.UTF-8`), con ejecución en caliente de `locale-gen`, actualización de `/etc/locale.conf` y exportación de variables.
3. **`titan-installer`:** Instalador gráfico nativo:
   - Detección automática de discos físicos NVMe, SSD y HDD.
   - Instalación desatendida o manual con particionado EFI/Root.
   - **Prioridad UEFI 1:** Configuración de `efibootmgr` anteponiendo Inti OS en el índice 0 del `BootOrder` y fijando `BootNext` para que el equipo arranque de inmediato al sistema instalado.
   - **Expulsión USB:** Detección de la unidad live `/run/archiso/bootmnt` y llamada a `eject` y `udisksctl power-off` al pulsar "Reiniciar Ahora", permitiendo retirar el pendrive sin reinfecciones del instalador.
4. **`titan-fotos`:** Visor de imágenes optimizado con soporte para zoom, rotación y galería rápida.
5. **`titan-musica`:** Reproductor de audio con integración en la TopBar e isla dinámica.
6. **`titan-terminal`:** Terminal Wayland translúcida de baja latencia con fuentes vectoriales y esquemas de color adaptativos.
7. **`titan-calc`:** Calculadora con diseño GlassPanel.
8. **`titan-calendar`:** Calendario interactivo con vista mensual y agenda.
9. **`titan-clock`:** Reloj mundial, alarmas y cronómetro con precisión de milisegundos.
10. **`titan-video`:** Reproductor de vídeo con aceleración por hardware VA-API.
11. **`titan-acerca`:** Ventana de especificaciones del equipo (procesador, memoria RAM, GPU, versión de kernel y almacenamiento).

### 3.6. Blindaje de Controladores Gráficos (NVIDIA, Intel, AMD, Laptops Híbridas)
- Se corrigió la inicialización en `/etc/profile.d/15-titan-grafico.sh`:
  - Se sustituyó la detección ciega por `lspci` por una verificación del estado real de los módulos del kernel (`/sys/module/nvidia_drm` y `/dev/nvidia0`).
  - Si la máquina tiene NVIDIA pero corre con el kernel propio o GPUs anteriores a Turing (GTX 10xx, 9xx, 7xx), se delega de forma segura en **Nouveau + Mesa**, evitando fallos críticos de EGL.
  - En portátiles con gráficos híbridos (Intel/AMD + NVIDIA), la pantalla principal se ancla a la tarjeta integrada (`WLR_DRM_DEVICES`), dejando la tarjeta dedicada disponible para aceleración bajo demanda mediante el script `prime-run`.
  - Se eliminó la variable obsoleta `GBM_BACKEND=nvidia-drm` que causaba bloqueos y parpadeos en Wayland y Firefox.
  - Se implementó un aislamiento de variables en las capas de autorecuperación: si el motor acelerado falla, se limpian las variables del entorno y se levanta el escritorio automáticamente con el backend por software (`pixman` / `llvmpipe`), impidiendo que el usuario quede en pantalla negra.

### 3.7. Infraestructura de Empaquetado y Verificación
- Automatización de compilación con `Makefile` y scripts especializados (`scripts/build-iso.sh`, `scripts/run-qemu.sh`).
- Corrección de desmontajes limpios de submontajes huérfanos (`umount -R`) en caso de compilación cancelada.
- Suite de pruebas de regresión automatizada (`verify/comprobar-escritorio.sh`, `verify/comprobar-customize.sh`, `verify/comprobar-acerca.sh`), con **28 de 28 pruebas superadas con éxito**.
- Empaquetado completo del código fuente y binarios del kernel en `titan-linux.zip` (975 MB), listo para su traslado y despliegue en otras estaciones de desarrollo.

---

## 4. Pasos Detallados Ejecutados para Llegar Hasta Aquí

A continuación se detalla la secuencia cronológica y técnica de los pasos implementados para construir la versión actual del sistema operativo:

### Paso 1: Preparación del Entorno Anfitrión y Dependencias Maestras
1. Se seleccionó una distribución base compatible con Arch Linux (**CachyOS**) como estación de desarrollo.
2. Se estructuró el script `setup.sh` y el `Makefile` central con la lista exhaustiva de dependencias:
   - Compiladores y herramientas base: `base-devel`, `git`, `cmake`, `rust`, `cargo`.
   - Herramientas de empaquetado de ISO: `archiso`, `devtools`, `arch-install-scripts`, `erofs-utils`, `mtools`, `dosfstools`.
   - Ecosistema gráfico Qt 6 y Wayland: `qt6-base`, `qt6-declarative`, `qt6-wayland`, `qt6-svg`, `qt6-multimedia`, `layer-shell-qt`, `wayland`, `wayland-protocols`.
   - Emulación y verificación: `qemu-desktop`, `edk2-ovmf`, `tmux`.

### Paso 2: Creación, Parcheo y Compilación del Kernel Propio (`linux-titanlinux`)
1. Se creó el directorio de empaquetado `kernel/linux-titanlinux/` tomando como referencia upstream el paquete oficial `linux-lts`.
2. Se renombró el `pkgbase` a `linux-titanlinux` para generar la versión identificativa `6.18.54-1-titanlinux`.
3. Se integraron parches de estabilidad del kernel:
   - `0001-add-sysctl-to-allow-disabling-unprivileged-CLONE_NEW.patch`: control de seguridad sobre contenedores no privilegiados.
   - `0002` y `0003` para `drm/amdgpu`: eliminación de alocaciones de memoria críticas en el manejador de interrupciones para evitar bloqueos del cursor en GPUs AMD.
   - `0004-modfinal-strip-module-debug-info.patch`: desbroce de símbolos de depuración en módulos para reducir el tamaño final en disco.
4. Se configuró `config.x86_64` deshabilitando `CONFIG_LOCALVERSION_AUTO` y activando `CONFIG_PREEMPT_DYNAMIC`.
5. Se compiló el kernel generando los paquetes instalables:
   - `linux-titanlinux-6.18.54-1-x86_64.pkg.tar.zst` (157 MB).
   - `linux-titanlinux-headers-6.18.54-1-x86_64.pkg.tar.zst` (74 MB).

### Paso 3: Estructuración del Perfil de la ISO y Sistema Raíz (Airootfs)
1. Se configuró la estructura de Archiso en `iso/titan/` con `profiledef.sh` (definiendo permisos de arranque, squashfs/erofs, formato de etiqueta `TITAN_...`).
2. Se editó `iso/titan/pacman.conf` para inyectar el repositorio local `[titan]` con la ruta `%TITAN_REPO%`, permitiendo que el instalador de la ISO incluya el kernel propio sin requerir conexión a internet.
3. Se crearon los menús de arranque dual en `iso/titan/grub/grub.cfg` (UEFI) y `iso/titan/syslinux/syslinux-linux.cfg` (BIOS MBR), configurando:
   - Opción 1 (Por defecto): Kernel propio `linux-titanlinux` con `nvidia-drm.modeset=1`.
   - Opción 2: Modo de compatibilidad gráfica universal con `titan.compat=1 modprobe.blacklist=nouveau`.
   - Opción 3: Modo de rescate con el kernel oficial de Arch.
4. Se pobló `iso/titan/airootfs/` con las configuraciones del sistema esqueleto (`/etc/skel/`), reglas de D-Bus, variables de sesión de usuario y binarios precompilados en `/usr/local/bin/`.

### Paso 4: Implementación de Labwc como Servidor Gráfico Wayland
1. Se adoptó **Labwc** para reemplazar servidores X11 pesados y compositores monolíticos.
2. Se redactó el archivo de configuración `iso/titan/airootfs/etc/skel/.config/labwc/rc.xml`:
   - Configuración de combinaciones de teclas estilo macOS (`Super_L` para Launcher, `W-t` para Terminal, `W-q` para cerrar, `A-Tab` para cambio de ventana).
   - Reglas de centrado automático (`<placement><policy>center</policy></placement>`) para evitar ventanas fuera de vista.
   - Reglas de decoraciones de ventana específicas para compatibilidad con ONLYOFFICE, navegadores y diálogos de guardado.
3. Se creó el tema visual `Titan-macOS` en `themerc` con botones de ventana a la izquierda y esquinas redondeadas.
4. Se corrigió un error de sintaxis en `rc.xml` que emitía una barra roja de advertencia en pantalla, eliminando los argumentos `<preview>` obsoletos en las acciones `NextWindow` y `PreviousWindow`.
5. Se redactó `autostart` para orquestar la inicialización en segundo plano de PipeWire, WirePlumber, sincronización de batería, desbloqueo de Wi-Fi y los procesos de `titan-desktop` y `titan-shell`.

### Paso 5: Programación del Entorno de Escritorio `titan-shell` (1.8.0)
1. Se desarrolló la arquitectura central en C++ (`main.cpp`, `ShellBackend.cpp`, `DesktopBackend.cpp`, `WindowTracker.cpp`, `DockModel.cpp`) utilizando Qt 6 y la librería `LayerShellQt`.
2. Se programó la barra superior flotante (`TopBar.qml`): integración de reloj mundial, menús de estado, controles de volumen y brillo, y Dynamic Island.
3. Se programó el Dock flotante (`Dock.qml`): cálculo de magnificación parabólica suave al desplazar el cursor, indicadores luminosos de procesos activos y badges de notificación.
4. Se programó el menú de inicio y catálogo de programas (`Launcher.qml`): filtrado en tiempo real de aplicaciones `.desktop` con animación de desvanecimiento suave.
5. Se programó la cortina de arranque (`BootSplash.qml`): pantalla de carga opaca que cubre la pantalla mientras el compositor estabiliza el escritorio, previniendo parpadeos iniciales.
6. Se programó la pantalla de bloqueo (`LockScreen.qml`): interfaz de autenticación con desenfoque de fondo y botón de candado integrado en el menú de apagado.
7. Se programó el conmutador de tema visual Claro / Oscuro con atajo global `Super + Shift + D`.

### Paso 6: Creación e Integración Universal del Componente `GlassPanel.qml`
1. Se diseñó el componente reusable `GlassPanel.qml` en QML/QtQuick para proveer la estética de vidrio esmerilado (*Liquid Glass*):
   - Desenfoque dinámico gaussiano con textura microscópica antirruido.
   - Reflejos especulares en los bordes y gradientes traslúcidos reactivos al tema claro u oscuro.
2. Se desplegó `GlassPanel.qml` en **todos** los directorios de aplicaciones (`apps/titan-*/qml/GlassPanel.qml`).
3. Se actualizaron los archivos `.qrc` (`resources.qrc`) en cada aplicación para compilar el componente dentro del binario.
4. Se añadieron salvaguardas de seguridad en el renderizado offscreen (`width > 0 && height > 0`) para erradicar advertencias en controladores Mesa/OpenGL ante ventanas minimizadas.

### Paso 7: Desarrollo de la Suite Nativa de 11 Aplicaciones
1. **`titan-finder`:** Se programó el explorador de archivos con panel lateral de acceso rápido (Inicio, Descargas, Documentos, USB), navegación por migas de pan (*breadcrumbs*), selector visual rectangular elástico para selección múltiple con el ratón y soporte de arrastrar y soltar.
2. **`titan-settings`:** Se desarrolló el panel de configuración central con navegación por categorías estilo macOS.
3. **`titan-installer`:** Se desarrolló el instalador nativo tanto en interfaz gráfica (`InstallerWindow.qml`) como en script CLI (`paso-base.sh`).
4. **`titan-terminal`:** Emulador de terminal acelerado por GPU con fondo translúcido y paleta de colores CachyOS/Titan.
5. **`titan-fotos`:** Visor de imágenes ligero con visor de metadatos EXIF.
6. **`titan-musica`:** Reproductor de música local con lectura de etiquetas ID3 y enlace con Dynamic Island.
7. **`titan-calc`:** Calculadora moderna con interfaz GlassPanel.
8. **`titan-calendar`:** Calendario interactivo con vistas mensuales y agenda.
9. **`titan-clock`:** Reloj con cronómetro y hora mundial.
10. **`titan-video`:** Reproductor de vídeo con aceleración por hardware.
11. **`titan-acerca`:** Ventana de especificaciones de hardware (CPU, RAM, GPU, versión de kernel y almacenamiento).

### Paso 8: Implementación de Conectividad Real e Idiomas en Ajustes
1. **Wi-Fi Interactivo (`WifiView.qml` y `SettingsBackend.cpp`):**
   - Se conectó el backend con la API de `nmcli`.
   - Se implementó el escaneo periódico en segundo plano de puntos de acceso, visualización de intensidad de señal, icono de candado para redes seguras y diálogo modal integrado para ingresar la contraseña WPA/WPA2.
2. **Bluetooth Interactivo (`BluetoothView.qml`):**
   - Se integró el control de encendido/apagado mediante `rfkill` y escaneo de periféricos mediante `bluetoothctl`.
3. **Soporte Multilingüe en Tiempo de Ejecución:**
   - Se implementó el conmutador de idiomas en `GeneralView.qml` con soporte para Español (`es_ES.UTF-8`), Inglés (`en_US.UTF-8`) y Quechua (`quz_PE.UTF-8`).
   - El backend descomenta la línea correspondiente en `/etc/locale.gen`, ejecuta `sudo locale-gen`, actualiza `/etc/locale.conf` y `~/.config/locale.conf`, y reexporta las variables `LANG` y `LC_ALL`.

### Paso 9: Perfeccionamiento del Arranque UEFI y Expulsión del USB Instalador
1. **Prioridad 1 en UEFI con `efibootmgr`:**
   - En `InstallerBackend.cpp` y `paso-base.sh`, tras la instalación de GRUB en la partición ESP (`/boot`), se ejecuta `efibootmgr` para localizar la entrada de Inti OS, anteponer su identificador en el primer lugar de la cadena `BootOrder` (índice 0) y marcarlo como `BootNext`.
2. **Expulsión Física del USB al Reiniciar:**
   - Se programó la rutina `rebootSystem()` en el instalador: detecta la unidad física de la que arrancó el sistema live (`/run/archiso/bootmnt`), desmonta los puntos de montaje del pendrive y emite `eject` y `udisksctl power-off` antes de ejecutar `systemctl reboot`. Esto garantiza que la placa base salte directamente al disco duro sin volver a cargar la ISO.

### Paso 10: Depuración y Blindaje contra Fallos Gráficos en Tarjetas NVIDIA
1. Se diagnosticaron los fallos críticos de pantalla negra en hardware con NVIDIA:
   - Detección engañosa por bus PCI (`lspci`) que forzaba variables propietarias aun cuando el módulo del kernel no había cargado o cuando la GPU era antigua (GTX 10xx/9xx/7xx).
   - Bloqueos causados por la variable obsoleta `GBM_BACKEND=nvidia-drm`.
2. Se reescribió la lógica en `/etc/profile.d/15-titan-grafico.sh`:
   - Verificación de la presencia real del módulo en memoria (`/sys/module/nvidia_drm` y `/dev/nvidia0`).
   - Si el driver privativo no está activo, el sistema delega de forma segura en **Nouveau + Mesa** sin forzar variables incompatibles.
   - En portátiles híbridos (Intel/AMD + NVIDIA Optimus), la sesión de Wayland se ancla automáticamente al controlador DRM de la gráfica integrada (`WLR_DRM_DEVICES`), dejando la tarjeta dedicada disponible para aceleración bajo demanda con `prime-run`.
   - Se eliminó `GBM_BACKEND=nvidia-drm` permitiendo que Mesa 21.2+ seleccione el backend óptimo.
   - Se blindó la capa de autorecuperación: ante un fallo de inicialización acelerada, se limpian las variables del entorno y se levanta el escritorio automáticamente con el backend por software (`pixman` / `llvmpipe`).

### Paso 11: Corrección de Scripts de Construcción de la ISO (`build-iso.sh`)
1. Se resolvió el bloqueo en la reconstrucción de la ISO provocado por submontajes de chroot huérfanos (`/proc`, `/sys`, `/dev`, `/run`): se programó un bucle recursivo de desmontaje limpio con `umount -R` ordenado de adentro hacia afuera.
2. Se corrigió un error de variable sin asignar (`quedan=""`) bajo el modo estricto de Bash (`set -euo pipefail`).

### Paso 12: Aseguramiento de Calidad y Suite de Verificación
1. Se ejecutó la suite de pruebas automatizadas:
   - `./verify/comprobar-escritorio.sh`: comprobación de carga offscreen de QML, presencia de capas LayerShell y ejecutables de las 11 aplicaciones (**28 de 28 pruebas aprobadas, 0 fallos**).
   - `./verify/comprobar-customize.sh`: validación sintáctica de scripts de personalización (**4 de 4 pruebas aprobadas**).
   - `./verify/comprobar-acerca.sh`: verificación de telemetría de hardware en la ventana Acerca (**Todo correcto**).

### Paso 13: Empaquetado y Preparación para Portabilidad
1. Se depuraron los archivos temporales de compilación en `apps/*/build`.
2. Se empaquetó el código fuente íntegro, el perfil de la ISO y los paquetes precompilados del kernel en un archivo comprimido portátil: [titan-linux.zip](file:///home/isai/Proyectos/titan-linux/titan-linux.zip) (975 MB), excluyendo imágenes ISO y discos virtuales para optimizar el tamaño.

---

## 5. Qué Debería Considerarse al Compilar el Kernel de Linux

La compilación del kernel es el paso de mayor impacto en el rendimiento, estabilidad y compatibilidad de un sistema operativo. A continuación se detallan los aspectos técnicos críticos que deben considerarse:

### 5.1. Configuración del Núcleo (`.config`)
- **Controladores Embebidos (`=y`) vs Módulos Dinámicos (`=m`):**
  - Todo controlador indispensable para acceder a la raíz del disco **debe ir embebido (`=y`) o estar garantizado dentro del initramfs**: controladores de almacenamiento NVMe (`CONFIG_BLK_DEV_NVME`), SATA/AHCI (`CONFIG_SATA_AHCI`), controladores de bus USB (`CONFIG_USB_XHCI_HCD`), el sistema de archivos raíz (`CONFIG_EXT4_FS`, `CONFIG_BTRFS_FS`) y tablas de particiones (`CONFIG_EFI_PARTITION`).
  - Todo lo demás (tarjetas de sonido, Bluetooth, Wi-Fi, adaptadores de red secundarios) debe configurarse como módulo dinámico (`=m`) para no saturar la memoria RAM del sistema con código no utilizado.
- **Controladores Gráficos (DRM / KMS):**
  - Asegurar la activación de `CONFIG_DRM_KMS_HELPER=y` y `CONFIG_DRM_FBDEV_EMULATION=y` para que el kernel proporcione una consola gráfica fluida desde el primer segundo de arranque.
  - Habilitar `CONFIG_DRM_I915`, `CONFIG_DRM_XE`, `CONFIG_DRM_AMDGPU` y `CONFIG_DRM_NOUVEAU` como módulos (`=m`).
  - Habilitar `CONFIG_DRM_SIMPLEDRM=y` para garantizar vídeo en cualquier máquina virtual o hardware UEFI genérico que use el GOP (*Graphics Output Protocol*).

### 5.2. Planificación y Latencia Interactiva (*Preemption Models*)
- **`CONFIG_PREEMPT_NONE` vs `CONFIG_PREEMPT_VOLUNTARY` vs `CONFIG_PREEMPT` (Low-Latency Desktop):**
  - Para servidores se prefiere rendimiento bruto de cómputo (*throughput*).
  - Para un sistema operativo con interfaz de escritorio rica (animaciones fluidas a 60/120 Hz, audio sin cortes por buffer underrun), se debe elegir **`CONFIG_PREEMPT_DYNAMIC`** y arrancar con `preempt=full` o `preempt=voluntary`.
- **Frecuencia del Temporizador (`CONFIG_HZ`):**
  - Para escritorio interactivo se recomienda `CONFIG_HZ=1000` o `CONFIG_HZ=300` (muy usado en kernels modernos para optimizar balance entre respuesta y ahorro de energía en baterías de laptops).
  - Activar `CONFIG_NO_HZ_FULL=y` o `CONFIG_NO_HZ_IDLE=y` para que los núcleos en reposo no despierten innecesariamente.

### 5.3. Compatibilidad de Módulos Externos (*Vermagic* y *Modversions*)
- **Discrepancia de Versión (*Vermagic*):**
  - Si compilas un kernel con un nombre personalizado (ej. `6.18.54-titanlinux`), los paquetes binarios precompilados por terceros (como el driver oficial `nvidia` o `virtualbox-host-modules` de Arch) **no se cargarán** porque buscan la ruta `/usr/lib/modules/<version-exacta-de-arch>/`.
  - **Estrategia recomendada:** O bien se habilita **DKMS** (*Dynamic Kernel Module Support*) para compilar automáticamente los módulos sobre el kernel del sistema durante la instalación, o bien se distribuyen controladores abiertos universales (`nouveau`, `amdgpu`, `iris`) dentro del árbol del sistema.
- **`CONFIG_MODVERSIONS`:**
  - Habilitar el versionado de símbolos permite que algunos módulos sigan funcionando ante cambios menores de parches dentro de la misma versión del kernel.

### 5.4. Microcódigo y Firmware
- El kernel por sí solo no puede corregir fallos de silicio o vulnerabilidades de ejecución especulativa (Spectre, Meltdown, Downfall).
- Es obligatorio incorporar en la partición `/boot` los paquetes de microcódigo:
  - `intel-ucode.img` para CPUs Intel.
  - `amd-ucode.img` para CPUs AMD.
- El gestor de arranque (GRUB o systemd-boot) debe cargar el initrd de microcódigo **antes** del initrd principal (`initrd /intel-ucode.img /initramfs.img`).

### 5.5. Depuración y Reducción del Tamaño del Kernel
- Dejar activas las banderas de depuración (`CONFIG_DEBUG_INFO=y`) produce imágenes de kernel de más de 1.5 GB y ralentiza la compilación hasta 5 veces.
- **Recomendación:** Desactivar `CONFIG_DEBUG_INFO` o usar `CONFIG_DEBUG_INFO_REDUCED=y` y aplicar `strip --strip-unneeded` en los módulos `.ko` al generar el paquete.
- Comprimir los módulos en formato **Zstandard** (`CONFIG_MODULE_COMPRESS_ZSTD=y`): proporciona descompresión ultrarrápida al vuelo con un ratio de compresión superior a gzip.

### 5.6. Optimización del Proceso de Compilación en el Host
- **Paralelismo:** Utilizar siempre `make -j$(nproc)` para saturar todos los núcleos disponibles.
- **Memoria RAM:** Cada hilo de compilación con GCC o Clang puede consumir entre 1.5 GB y 2 GB de RAM (especialmente en fases como la generación de LTO o compilación de subsistemas masivos como drivers de AMDGPU). Si la máquina tiene poca RAM, limitar a `-j$(( $(nproc) / 2 ))` para evitar que el demonio OOM (*Out of Memory*) mate el compilador.
- **Ccache:** Instalar y habilitar `ccache` para que las recompilaciones subsecuentes tarden menos de 3 minutos.

---

## 6. Qué Debería Hacerse a Continuación (Hoja de Ruta y Próximos Pasos)

Para que Titan Linux / Inti OS alcance un nivel de madurez equivalente a distribuciones comerciales de primer nivel, se recomienda implementar las siguientes fases:

```
+---------------------------------------------------------------------------------+
|                         HOJA DE RUTA DE DESARROLLO                              |
+---------------------------------------------------------------------------------+
|  1. INFRAESTRUCTURA      | Repositorio binario remoto con firma de paquetes GPG |
|  2. COMPATIBILIDAD GPU   | Automatización DKMS para drivers privativos NVIDIA   |
|  3. ARRANQUE Y SESIÓN    | Gestor de inicio de sesión gráfico (Greeter nativo)  |
|  4. SEGURIDAD AVANZADA   | Firma de binarios para UEFI Secure Boot (Shim/MOK)   |
|  5. APLICACIONES / TIENDA| Soporte integrado de Flatpak con portales Wayland    |
|  6. INTERNACIONALIZACIÓN | Motor QTranslator dinámico en tiempo de ejecución    |
+---------------------------------------------------------------------------------+
```

### 6.1. Repositorio Binario Propio con Firma Criptográfica
- **Objetivo:** Permitir que los usuarios reciban actualizaciones de `titan-shell`, el kernel y las aplicaciones sin necesidad de reinstalar la ISO.
- **Acción:**
  1. Configurar un servidor web seguro (Nginx/Cloudflare) que aloje la base de datos `titan.db.tar.gz`.
  2. Generar un par de claves GPG del proyecto para firmar los paquetes (`pacman-key --add`).
  3. Añadir el repositorio a `/etc/pacman.conf` en el sistema instalado.

### 6.2. Automatización DKMS para Drivers NVIDIA y Módulos Fuera de Árbol
- **Objetivo:** Permitir que usuarios con tarjetas NVIDIA de última generación instalen los controladores privativos más recientes con un solo clic.
- **Acción:**
  - Instalar `dkms` y el paquete `linux-titanlinux-headers` en el sistema final.
  - Crear un servicio que compile automáticamente el módulo privativo de NVIDIA tras cualquier actualización del kernel, vinculándolo con la lógica híbrida de `15-titan-grafico.sh`.

### 6.3. Gestor de Acceso Gráfico (*Display Manager / Greeter*)
- **Objetivo:** Eliminar el auto-login de consola y ofrecer una pantalla de bienvenida gráfica profesional multi-usuario antes de levantar la sesión de escritorio.
- **Acción:**
  - Integrar un *greeter* nativo con estilo Liquid Glass (basado en `greetd` o `SDDM`) que cargue directamente sobre Wayland sin requerir dependencias de X11.

### 6.4. Certificación y Firma para UEFI Secure Boot
- **Objetivo:** Permitir que la ISO y el sistema instalado arranquen en cualquier ordenador nuevo sin obligar al usuario a desactivar Secure Boot en la BIOS/UEFI.
- **Acción:**
  - Integrar el cargador `shim` firmado por Microsoft.
  - Implementar inscripción de claves de máquina MOK (*Machine Owner Key*) para firmar automáticamente `vmlinuz-linux-titanlinux` y sus módulos.

### 6.5. Ecosistema de Software Sandboxed (Flatpak + XDG Desktop Portals)
- **Objetivo:** Dar acceso inmediato a miles de aplicaciones modernas (Spotify, Steam, OBS Studio, Telegram, LibreOffice, Blender) sin ensuciar la base del sistema operativo.
- **Acción:**
  - Habilitar el repositorio Flathub por defecto.
  - Configurar `xdg-desktop-portal-wlr` o un portal personalizado para que las apps aisladas soliciten acceso transparente al selector de archivos nativo de Titan Finder, la cámara y el audio.

### 6.6. Motor de Traducción Dinámica en Tiempo de Ejecución
- **Objetivo:** Que el selector de idiomas de `titan-settings` cambie los textos de toda la interfaz gráfica de `titan-shell` y las apps al instante sin reiniciar la sesión.
- **Acción:**
  - Compilar catálogos de traducción `.ts` a `.qm` con `lrelease`.
  - Conectar una señal en `ThemeManager` o `SettingsBackend` que invoque `qApp->installTranslator(&translator)` en todas las instancias QML.

---

## 7. Conclusión

El proyecto **Titan Linux / Inti OS** ha superado la etapa teórica y cuenta con una arquitectura de sistema operativo sólida, moderna y verificada:
1. Posee su propio **kernel Linux optimizado** (`linux-titanlinux`).
2. Implementa un **servidor gráfico de última generación basado en Wayland** (`labwc`), eliminando el legado obsoleto de X11.
3. Cuenta con un **entorno de escritorio nativo completo** (`titan-shell` 1.8.0) con diseño moderno Liquid Glass, dock inteligente, barra superior, isla dinámica, pantalla de bloqueo y una suite integral de 11 aplicaciones propias.
4. Ha resuelto problemas complejos de la industria como la gestión de **gráficos híbridos NVIDIA Optimus**, arranque UEFI prioritario y desmontaje limpio de medios USB.

Siguiendo la hoja de ruta descrita para la automatización de repositorios remotos y la integración de Flatpak, el sistema operativo se encuentra en una posición inmejorable para competir como una de las distribuciones de escritorio más estables, elegantes y completas del ecosistema Linux.
