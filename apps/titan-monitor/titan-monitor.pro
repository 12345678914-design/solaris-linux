QT += quick quickcontrols2 gui
CONFIG += c++17 warn_on release
QMAKE_CXXFLAGS_RELEASE += -O2 -pipe -fno-plt
QMAKE_LFLAGS_RELEASE += -Wl,-O1,--as-needed
TEMPLATE = app
TARGET = titan-monitor

DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000

INCLUDEPATH += src ../titan-common

SOURCES += \
    src/main.cpp \
    src/MonitorBackend.cpp \
    ../titan-common/ThemeManager.cpp

HEADERS += \
    src/MonitorBackend.h \
    ../titan-common/ThemeManager.h

RESOURCES += resources.qrc

DESTDIR = .
