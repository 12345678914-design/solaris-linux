# Inti OS - teclado en pantalla (accesibilidad y pantallas táctiles).
# Una capa de layer-shell abajo que no coge el teclado: lo que se pulsa llega
# a la ventana que tenía el foco, a través de wtype (protocolo de teclado
# virtual de Wayland, que tienen Wayfire y labwc).
QT += quick quickcontrols2 gui network
CONFIG += c++17 warn_on release
LIBS += -lLayerShellQtInterface
TEMPLATE = app
TARGET = titan-teclado

INCLUDEPATH += src ../titan-common

SOURCES += \
    src/main.cpp \
    src/Teclado.cpp \
    ../titan-common/ThemeManager.cpp

HEADERS += \
    src/Teclado.h \
    ../titan-common/ThemeManager.h

RESOURCES += titan-teclado.qrc
DESTDIR = .
