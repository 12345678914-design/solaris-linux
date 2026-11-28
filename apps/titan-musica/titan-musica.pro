QT += quick quickcontrols2 multimedia gui dbus concurrent network
CONFIG += c++17 warn_on release link_pkgconfig
PKGCONFIG += taglib
QMAKE_CXXFLAGS_RELEASE += -O3 -pipe -fno-plt
QMAKE_LFLAGS_RELEASE += -Wl,-O1,--as-needed
TEMPLATE = app
TARGET = titan-musica

DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000

INCLUDEPATH += src ../titan-common

SOURCES += \
    src/main.cpp \
    src/Biblioteca.cpp \
    src/MusicaBackend.cpp \
    src/Mpris.cpp \
    ../titan-common/ThemeManager.cpp

HEADERS += \
    src/Biblioteca.h \
    src/MusicaBackend.h \
    src/Mpris.h \
    ../titan-common/ThemeManager.h

RESOURCES += resources.qrc

DESTDIR = .
