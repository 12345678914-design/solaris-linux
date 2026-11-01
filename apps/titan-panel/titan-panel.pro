# Titan Panel: barra inferior y centro de aplicaciones (Qt 6 Widgets).
#
# Compilar y probar:
#   qmake6 && make -j
#   QT_QPA_PLATFORM=offscreen ./titan-panel --comprobar
#   QT_QPA_PLATFORM=offscreen ./titan-panel --captura /tmp/barra.png
#
# LayerShellQt y wayland-client se instalan en la ISO. El protocolo
# wlr-foreign-toplevel se genera con wayland-scanner y se guarda en src/
# para que la compilacion no dependa de la version del compositor.

QT += widgets
CONFIG += c++17 warn_on
TEMPLATE = app
TARGET = titan-panel

DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000

INCLUDEPATH += \
    src \
    ../titan-desktop/src \
    ../titan-common

LIBS += -lwayland-client -lLayerShellQtInterface

SOURCES += \
    src/main.cpp \
    src/panel.cpp \
    src/centro.cpp \
    src/catalogo.cpp \
    src/tareas.cpp \
    src/iconos.cpp \
    src/wlr-foreign-toplevel-management-unstable-v1-protocol.c \
    ../titan-common/layershell.cpp \
    ../titan-desktop/src/config.cpp

HEADERS += \
    src/panel.h \
    src/centro.h \
    src/catalogo.h \
    src/tareas.h \
    src/iconos.h \
    src/wlr-foreign-toplevel-management-unstable-v1-client-protocol.h \
    ../titan-common/layershell.h \
    ../titan-desktop/src/config.h
