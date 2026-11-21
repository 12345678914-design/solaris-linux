QT += quick quickcontrols2 network dbus gui-private
CONFIG += c++17 warn_on release
QMAKE_CXXFLAGS_RELEASE += -O3 -pipe -fno-plt
QMAKE_LFLAGS_RELEASE += -Wl,-O1,--as-needed
TEMPLATE = app
TARGET = titan-shell

DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000

INCLUDEPATH += \
    src \
    ../titan-greeter/src \
    ../titan-panel/src \
    ../titan-common

LIBS += -lLayerShellQtInterface -lwayland-client

SOURCES += \
    src/main.cpp \
    ../titan-greeter/src/Usuarios.cpp \
    src/ShellBackend.cpp \
    src/WindowTracker.cpp \
    src/DockModel.cpp \
    src/LauncherBackend.cpp \
    src/DesktopBackend.cpp \
    src/WayfireIpc.cpp \
    src/ColaApps.cpp \
    src/Mpris.cpp \
    ../titan-common/ThemeManager.cpp \
    ../titan-common/TitanPrefs.cpp \
    ../titan-panel/src/tareas.cpp \
    ../titan-panel/src/wlr-foreign-toplevel-management-unstable-v1-protocol.c

HEADERS += \
    src/ShellBackend.h \
    ../titan-greeter/src/Usuarios.h \
    src/WindowTracker.h \
    src/DockModel.h \
    src/LauncherBackend.h \
    src/DesktopBackend.h \
    src/WayfireIpc.h \
    src/ColaApps.h \
    src/Mpris.h \
    ../titan-common/ThemeManager.h \
    ../titan-common/TitanPrefs.h \
    ../titan-common/TitanBinary.h \
    ../titan-common/TitanDesktopEntry.h \
    ../titan-common/TitanIconoApp.h \
    ../titan-panel/src/tareas.h

RESOURCES += resources.qrc

DESTDIR = .
