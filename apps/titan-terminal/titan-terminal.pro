QT += quick quickcontrols2
CONFIG += c++17 warn_on
TEMPLATE = app
TARGET = titan-terminal

DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000

INCLUDEPATH += ../titan-common

SOURCES += \
    src/main.cpp \
    ../titan-common/ThemeManager.cpp

HEADERS += \
    ../titan-common/ThemeManager.h

RESOURCES += resources.qrc

DESTDIR = .