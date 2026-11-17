# Titan Linux - Makefile central
# Qt Quick/QML UI moderno al estilo macOS

SHELL := /bin/bash
APPS := apps
DISTRO := $(shell pwd)

# Paquetes de Arch necesarios para compilar el sistema completo (ISO, kernel y apps Qt)
PACMAN_DEPS := \
	base-devel \
	git \
	cmake \
	archiso \
	devtools \
	arch-install-scripts \
	erofs-utils \
	mtools \
	dosfstools \
	rust \
	cargo \
	qt6-base \
	qt6-declarative \
	qt6-wayland \
	qt6-svg \
	qt6-multimedia \
	layer-shell-qt \
	wayland \
	wayland-protocols \
	tmux \
	qemu-desktop \
	edk2-ovmf

.PHONY: all help pacman deps apps apps/titan-shell apps/titan-finder apps/titan-fotos apps/titan-musica apps/titan-terminal apps/titan-cli apps/titan-desktop apps/titan-panel apps/titan-acerca apps/titan-settings apps/titan-calc apps/titan-calendar apps/titan-clock apps/titan-video apps/titan-greeter apps/titan-polkit apps/titan-installer apps/wayfire-titan build run run-software qemu qemu-gl qemu-vmware screenshot iso clean

all: apps

help:
	@echo "============================================"
	@echo " Titan Linux - Development & Build System"
	@echo "============================================"
	@echo ""
	@echo "  make pacman       -> Instalar paquetes necesarios para compilar"
	@echo "  make deps         -> Alias de make pacman"
	@echo "  make apps         -> Compilar todas las aplicaciones (Qt y Rust)"
	@echo "  make build        -> Alias de make apps"
	@echo "  make run          -> Ejecutar titan-shell en Wayland"
	@echo "  make run-software -> Forzar QT_QUICK_BACKEND=software (VMware/VMs)"
	@echo "  make qemu         -> Lanzar ISO con configuración actual"
	@echo "  make qemu-vmware  -> Lanzar ISO con backend software forzado"
	@echo "  make screenshot   -> Arrancar QEMU y tomar captura de pantalla de prueba"
	@echo "  make iso          -> Reconstruir ISO completa"
	@echo "  make clean        -> Limpiar builds"
	@echo ""

pacman:
	@echo "Instalando paquetes de Arch/CachyOS necesarios para compilar Titan Linux..."
	sudo pacman -S --needed $(PACMAN_DEPS)

deps: pacman

apps: apps/titan-shell apps/titan-finder apps/titan-fotos apps/titan-musica apps/titan-terminal apps/titan-cli apps/titan-desktop apps/titan-panel apps/titan-acerca apps/titan-settings apps/titan-calc apps/titan-calendar apps/titan-clock apps/titan-video apps/titan-greeter apps/titan-polkit apps/titan-installer apps/wayfire-titan
	@# Ver scripts/fijar-isa-baseline.py: en CachyOS v4 todo sale marcado "necesita v4"
	@python3 -I scripts/fijar-isa-baseline.py $$(find iso/titan/airootfs/usr/local/bin iso/titan/airootfs/usr/lib/titan iso/titan/airootfs/usr/lib/wayfire -type f -exec sh -c 'head -c4 "$$1" | grep -q ELF && echo "$$1"' _ {} \; 2>/dev/null)

apps/titan-shell:
	@echo "Compilando titan-shell..."
	cd $(APPS)/titan-shell && qmake6 titan-shell.pro && make -j$(shell nproc)
	install -m 0755 $(APPS)/titan-shell/titan-shell iso/titan/airootfs/usr/local/bin/

apps/titan-finder:
	@echo "Compilando titan-finder..."
	cd $(APPS)/titan-finder && qmake6 titan-finder.pro && make -j$(shell nproc)
	install -m 0755 $(APPS)/titan-finder/titan-finder iso/titan/airootfs/usr/local/bin/

apps/titan-fotos:
	@echo "Compilando titan-fotos..."
	cd $(APPS)/titan-fotos && qmake6 titan-fotos.pro && make -j$(shell nproc)
	install -m 0755 $(APPS)/titan-fotos/titan-fotos iso/titan/airootfs/usr/local/bin/

apps/titan-musica:
	@echo "Compilando titan-musica..."
	cd $(APPS)/titan-musica && qmake6 titan-musica.pro && make -j$(shell nproc)
	install -m 0755 $(APPS)/titan-musica/titan-musica iso/titan/airootfs/usr/local/bin/

apps/titan-terminal:
	@echo "Compilando titan-terminal..."
	cd $(APPS)/titan-terminal && qmake6 titan-terminal.pro && make -j$(shell nproc)
	install -m 0755 $(APPS)/titan-terminal/titan-terminal iso/titan/airootfs/usr/local/bin/

apps/titan-cli:
	@echo "Compilando titan-cli..."
	cd $(APPS)/titan-cli && cargo build --release
	install -m 0755 $(APPS)/titan-cli/target/release/titan iso/titan/airootfs/usr/local/bin/

apps/titan-desktop:
	@echo "Compilando titan-desktop..."
	mkdir -p $(APPS)/titan-desktop/build && cd $(APPS)/titan-desktop/build && qmake6 .. && make -j$(shell nproc)
	cp -f $(APPS)/titan-desktop/build/titan-desktop $(APPS)/titan-desktop/titan-desktop
	install -m 0755 $(APPS)/titan-desktop/build/titan-desktop iso/titan/airootfs/usr/local/bin/

apps/titan-panel:
	@echo "Compilando titan-panel..."
	mkdir -p $(APPS)/titan-panel/build && cd $(APPS)/titan-panel/build && qmake6 .. && make -j$(shell nproc)
	install -m 0755 $(APPS)/titan-panel/build/titan-panel iso/titan/airootfs/usr/local/bin/

apps/titan-acerca:
	@echo "Compilando titan-acerca..."
	mkdir -p $(APPS)/titan-acerca/build && cd $(APPS)/titan-acerca/build && qmake6 .. && make -j$(shell nproc)
	cp -f $(APPS)/titan-acerca/build/titan-acerca $(APPS)/titan-acerca/titan-acerca
	install -m 0755 $(APPS)/titan-acerca/build/titan-acerca iso/titan/airootfs/usr/local/bin/

apps/titan-installer:
	@echo "Compilando titan-installer..."
	cd $(APPS)/titan-installer && qmake6 titan-installer.pro && make -j$(shell nproc)
	install -m 0755 $(APPS)/titan-installer/titan-installer iso/titan/airootfs/usr/local/bin/

apps/titan-settings:
	@echo "Compilando titan-settings..."
	cd $(APPS)/titan-settings && qmake6 titan-settings.pro && make -j$(shell nproc)
	install -m 0755 $(APPS)/titan-settings/titan-settings iso/titan/airootfs/usr/local/bin/

apps/titan-calc:
	@echo "Compilando titan-calc..."
	cd $(APPS)/titan-calc && qmake6 titan-calc.pro && make -j$(shell nproc)
	install -m 0755 $(APPS)/titan-calc/titan-calc iso/titan/airootfs/usr/local/bin/

apps/titan-calendar:
	@echo "Compilando titan-calendar..."
	cd $(APPS)/titan-calendar && qmake6 titan-calendar.pro && make -j$(shell nproc)
	install -m 0755 $(APPS)/titan-calendar/titan-calendar iso/titan/airootfs/usr/local/bin/

apps/titan-clock:
	@echo "Compilando titan-clock..."
	cd $(APPS)/titan-clock && qmake6 titan-clock.pro && make -j$(shell nproc)
	install -m 0755 $(APPS)/titan-clock/titan-clock iso/titan/airootfs/usr/local/bin/

apps/titan-video:
	@echo "Compilando titan-video..."
	cd $(APPS)/titan-video && qmake6 titan-video.pro && make -j$(shell nproc)
	install -m 0755 $(APPS)/titan-video/titan-video iso/titan/airootfs/usr/local/bin/

# Pantalla de inicio de sesion (greetd) y servicio de usuarios y grupos
apps/titan-greeter:
	@echo "Compilando titan-greeter..."
	cd $(APPS)/titan-greeter && qmake6 titan-greeter.pro && make -j$(shell nproc)
	cd $(APPS)/titan-greeter/helper && qmake6 titan-usuarios-helper.pro && make -j$(shell nproc)
	install -m 0755 $(APPS)/titan-greeter/titan-greeter iso/titan/airootfs/usr/local/bin/
	install -m 0755 $(APPS)/titan-greeter/helper/titan-usuarios-helper iso/titan/airootfs/usr/local/bin/

# Ventana de contrasena de administrador (agente de polkit)
apps/titan-polkit:
	@echo "Compilando titan-polkit..."
	mkdir -p $(APPS)/titan-polkit/build && cd $(APPS)/titan-polkit/build && qmake6 .. && make -j$(shell nproc)
	install -m 0755 $(APPS)/titan-polkit/build/titan-polkit iso/titan/airootfs/usr/local/bin/

# Plugins de Wayfire propios (titan-wobbly-guard: sin gelatina al redimensionar)
apps/wayfire-titan:
	@echo "Compilando plugins de Wayfire..."
	./scripts/build-wayfire-plugins.sh

build: apps

run:
	@echo "Ejecutando titan-shell..."
	cd $(APPS)/titan-shell && ./titan-shell

run-software:
	@echo "Ejecutando con backend software (VMware compatible)..."
	cd $(APPS)/titan-shell && QT_QUICK_BACKEND=software QSG_RHI_BACKEND=software ./titan-shell

qemu:
	@echo "Lanzando ISO con QEMU..."
	./scripts/run-qemu.sh

qemu-gl:
	@echo "Lanzando ISO con GPU virtual 3D (virgl): sesión inmersiva con Wayfire..."
	TITAN_QEMU_GL=1 ./scripts/run-qemu.sh

qemu-vmware:
	@echo "Lanzando ISO con configuración VMware compatible..."
	TITAN_QEMU_SOFTWARE=1 ./scripts/run-qemu.sh

screenshot:
	@echo "Lanzando QEMU y tomando captura de pantalla en out/capturas/..."
	./scripts/run-qemu.sh --screenshot

iso:
	@echo "Reconstruyendo ISO con titan-shell..."
	sudo ./scripts/build-iso.sh

onlyoffice:
	@./scripts/integrar-onlyoffice-appimage.sh

clean:
	@echo "Limpiando builds..."
	@find $(APPS) -name 'Makefile' -not -path '*/titan-cli/*' -delete
	@find $(APPS) -name '*.o' -delete
	@find $(APPS) -name 'moc_*' -delete
	@find $(APPS) -name 'qrc_*' -delete
	@find $(APPS)/titan-shell -name 'titan-shell' -type f -executable -delete
	@find $(APPS)/titan-finder -name 'titan-finder' -type f -executable -delete
	@find $(APPS)/titan-fotos -name 'titan-fotos' -type f -executable -delete
	@find $(APPS)/titan-musica -name 'titan-musica' -type f -executable -delete
	@find $(APPS)/titan-terminal -name 'titan-terminal' -type f -executable -delete
	@find $(APPS)/titan-settings -name 'titan-settings' -type f -executable -delete
	@find $(APPS)/titan-calc -name 'titan-calc' -type f -executable -delete
	@find $(APPS)/titan-calendar -name 'titan-calendar' -type f -executable -delete
	@find $(APPS)/titan-clock -name 'titan-clock' -type f -executable -delete
	@find $(APPS)/titan-video -name 'titan-video' -type f -executable -delete
	@find $(APPS)/titan-installer -name 'titan-installer' -type f -executable -delete
	@rm -rf $(APPS)/titan-polkit/build
	@find $(APPS)/titan-desktop -maxdepth 1 -name 'titan-desktop' -type f -executable -delete
	@find $(APPS)/titan-acerca -maxdepth 1 -name 'titan-acerca' -type f -executable -delete
	@rm -rf $(APPS)/titan-desktop/build $(APPS)/titan-panel/build $(APPS)/titan-acerca/build
	@cargo clean --manifest-path $(APPS)/titan-cli/Cargo.toml 2>/dev/null || true
	@echo "Limpio."
