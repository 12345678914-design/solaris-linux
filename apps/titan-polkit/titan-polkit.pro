# Inti OS - agente de polkit: la ventana que pide la contrasena de
# administrador cuando una app la necesita (GNOME Software, impresoras,
# discos, Ajustes...). Sin agente, esas acciones fallan sin decir nada.
QT += quick quickcontrols2 gui
CONFIG += c++17 warn_on release link_pkgconfig
PKGCONFIG += polkit-qt6-agent-1 polkit-qt6-core-1
LIBS += -lLayerShellQtInterface
TEMPLATE = app
TARGET = titan-polkit

INCLUDEPATH += src ../titan-common

SOURCES += \
    src/main.cpp \
    src/Agente.cpp \
    ../titan-common/ThemeManager.cpp

HEADERS += \
    src/Agente.h \
    ../titan-common/ThemeManager.h

RESOURCES += titan-polkit.qrc
DESTDIR = .
