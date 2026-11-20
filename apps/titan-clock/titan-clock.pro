QT += quick quickcontrols2 network

CONFIG += c++17

SOURCES += \
    src/main.cpp \
    src/ClockBackend.cpp \
    ../titan-common/ThemeManager.cpp

HEADERS += \
    src/ClockBackend.h \
    ../titan-common/ThemeManager.h

RESOURCES += \
    resources.qrc

target.path = /usr/local/bin
INSTALLS += target

INCLUDEPATH += src ../titan-common

