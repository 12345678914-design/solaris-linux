QT += quick quickcontrols2 gui network
CONFIG += c++17 warn_on
TEMPLATE = app
TARGET = titan-settings

DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000

INCLUDEPATH += \
    src \
    ../titan-common

SOURCES += \
    src/main.cpp \
    src/SettingsBackend.cpp \
    ../titan-common/ThemeManager.cpp

HEADERS += \
    src/SettingsBackend.h \
    ../titan-common/ThemeManager.h

RESOURCES += resources.qrc

DESTDIR = .

