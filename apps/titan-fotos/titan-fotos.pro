QT += quick quickcontrols2 gui
CONFIG += c++17 warn_on
TEMPLATE = app
TARGET = titan-fotos

DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000

INCLUDEPATH += src ../titan-common

SOURCES += \
    src/main.cpp \
    src/FotosBackend.cpp \
    ../titan-common/ThemeManager.cpp

HEADERS += \
    src/FotosBackend.h \
    ../titan-common/ThemeManager.h

RESOURCES += resources.qrc

DESTDIR = .

