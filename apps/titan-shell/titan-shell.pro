QT += quick quickcontrols2 network
CONFIG += c++17 warn_on
TEMPLATE = app
TARGET = titan-shell

DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000

INCLUDEPATH += \
    src \
    ../titan-panel/src \
    ../titan-common

LIBS += -lLayerShellQtInterface -lwayland-client

SOURCES += \
    src/main.cpp \
    src/ShellBackend.cpp \
    src/WindowTracker.cpp \
    src/DockModel.cpp \
    src/LauncherBackend.cpp \
    src/DesktopBackend.cpp \
    ../titan-common/ThemeManager.cpp \
    ../titan-panel/src/tareas.cpp \
    ../titan-panel/src/wlr-foreign-toplevel-management-unstable-v1-protocol.c

HEADERS += \
    src/ShellBackend.h \
    src/WindowTracker.h \
    src/DockModel.h \
    src/LauncherBackend.h \
    src/DesktopBackend.h \
    ../titan-common/ThemeManager.h \
    ../titan-panel/src/tareas.h

RESOURCES += resources.qrc

DESTDIR = .
