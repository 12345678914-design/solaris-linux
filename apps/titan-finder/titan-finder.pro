QT += quick quickcontrols2 gui
CONFIG += c++17 warn_on
TEMPLATE = app
TARGET = titan-finder

DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000

INCLUDEPATH += src ../titan-common

SOURCES += \
    src/main.cpp \
    src/FinderBackend.cpp \
    ../titan-common/ThemeManager.cpp

HEADERS += \
    src/FinderBackend.h \
    ../titan-common/ThemeManager.h

RESOURCES += resources.qrc

DESTDIR = .
