# Titan Desktop: escritorio basico en Qt 6 (Widgets).
#
# Compilar y probar:
#   qmake6 && make -j
#   ./titan-desktop --comprobar
#   QT_QPA_PLATFORM=offscreen ./titan-desktop --autocerrar

QT += widgets network
CONFIG += c++17 warn_on
TEMPLATE = app
TARGET = titan-desktop

DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000

SOURCES += \
    src/main.cpp \
    src/escritorio.cpp \
    src/config.cpp \
    ../titan-common/layershell.cpp

HEADERS += \
    src/escritorio.h \
    src/config.h \
    ../titan-common/layershell.h

RESOURCES += resources.qrc

INCLUDEPATH += ../titan-common
LIBS += -lLayerShellQtInterface
