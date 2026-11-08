QT += quick quickcontrols2
CONFIG += c++17 warn_on release
QMAKE_CXXFLAGS_RELEASE += -O3 -pipe -fno-plt
QMAKE_LFLAGS_RELEASE += -Wl,-O1,--as-needed
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