# Titan Acerca: informacion del equipo en una ventana Qt 6.
#
# Compilar y probar:
#   qmake6 && make -j
#   ./titan-acerca --comprobar
#   QT_QPA_PLATFORM=offscreen ./titan-acerca --captura /tmp/acerca.png

QT += widgets
CONFIG += c++17 warn_on
TEMPLATE = app
TARGET = titan-acerca

DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000

INCLUDEPATH += \
    src \
    ../titan-desktop/src

SOURCES += \
    src/main.cpp \
    src/acerca.cpp \
    ../titan-desktop/src/config.cpp

HEADERS += \
    src/acerca.h \
    ../titan-desktop/src/config.h
