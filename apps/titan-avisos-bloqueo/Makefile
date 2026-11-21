# Inti OS - modulo de gtklock con las notificaciones (lo compila build-iso.sh)
#   make SALIDA=/ruta/titan-avisos-module.so
CFLAGS ?= -O2 -Wall -Wextra -Wno-unused-parameter
PAQUETES = gtk+-3.0 gmodule-export-2.0 gio-2.0
SALIDA ?= titan-avisos-module.so

$(SALIDA): avisos.c gtklock-module.h
	$(CC) $(CFLAGS) -std=c11 -shared -fPIC -o $@ avisos.c $$(pkg-config --cflags --libs $(PAQUETES))
