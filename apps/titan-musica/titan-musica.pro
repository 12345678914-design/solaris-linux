QT += quick quickcontrols2 multimedia gui
CONFIG += c++17 warn_on
TEMPLATE = app
TARGET = titan-musica

DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000

INCLUDEPATH += src ../titan-common

SOURCES += \
    src/main.cpp \
    src/MusicaBackend.cpp \
    ../titan-common/ThemeManager.cpp

HEADERS += \
    src/MusicaBackend.h \
    ../titan-common/ThemeManager.h

RESOURCES += resources.qrc

DESTDIR = .

