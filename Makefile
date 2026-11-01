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

.PHONY: all help pacman deps apps apps/titan-shell apps/titan-finder apps/titan-fotos apps/titan-musica apps/titan-terminal apps/titan-cli apps/titan-desktop apps/titan-panel apps/titan-acerca apps/titan-settings build run run-software qemu qemu-vmware screenshot iso clean

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

apps: apps/titan-shell apps/titan-finder apps/titan-fotos apps/titan-musica apps/titan-terminal apps/titan-cli apps/titan-desktop apps/titan-panel apps/titan-acerca apps/titan-settings

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
	install -m 0755 $(APPS)/titan-desktop/build/titan-desktop iso/titan/airootfs/usr/local/bin/

apps/titan-panel:
	@echo "Compilando titan-panel..."
	mkdir -p $(APPS)/titan-panel/build && cd $(APPS)/titan-panel/build && qmake6 .. && make -j$(shell nproc)
	install -m 0755 $(APPS)/titan-panel/build/titan-panel iso/titan/airootfs/usr/local/bin/

apps/titan-acerca:
	@echo "Compilando titan-acerca..."
	mkdir -p $(APPS)/titan-acerca/build && cd $(APPS)/titan-acerca/build && qmake6 .. && make -j$(shell nproc)
	install -m 0755 $(APPS)/titan-acerca/build/titan-acerca iso/titan/airootfs/usr/local/bin/

apps/titan-settings:
	@echo "Compilando titan-settings..."
	cd $(APPS)/titan-settings && qmake6 titan-settings.pro && make -j$(shell nproc)
	install -m 0755 $(APPS)/titan-settings/titan-settings iso/titan/airootfs/usr/local/bin/

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
	@rm -rf $(APPS)/titan-desktop/build $(APPS)/titan-panel/build $(APPS)/titan-acerca/build
	@cargo clean --manifest-path $(APPS)/titan-cli/Cargo.toml 2>/dev/null || true
	@echo "Limpio."
