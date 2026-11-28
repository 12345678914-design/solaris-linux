QT += quick quickcontrols2 gui network
CONFIG += c++17 warn_on release
QMAKE_CXXFLAGS_RELEASE += -O3 -pipe -fno-plt
QMAKE_LFLAGS_RELEASE += -Wl,-O1,--as-needed
TEMPLATE = app
TARGET = titan-settings

DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000

INCLUDEPATH += \
    src \
    ../titan-common \
    ../titan-greeter/src

SOURCES += \
    src/main.cpp \
    src/SettingsBackend.cpp \
    src/Sistema.cpp \
    src/Dispositivos.cpp \
    src/Conexiones.cpp \
    src/Personalizar.cpp \
    src/Predeterminadas.cpp \
    ../titan-greeter/src/Usuarios.cpp \
    ../titan-common/TitanPrefs.cpp \
    ../titan-common/ThemeManager.cpp

HEADERS += \
    src/SettingsBackend.h \
    src/Sistema.h \
    src/Dispositivos.h \
    src/Conexiones.h \
    src/Personalizar.h \
    src/Predeterminadas.h \
    ../titan-greeter/src/Usuarios.h \
    ../titan-common/TitanPrefs.h \
    ../titan-common/ThemeManager.h

RESOURCES += resources.qrc

DESTDIR = .

