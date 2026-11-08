QT += quick quickcontrols2 multimedia

CONFIG += c++17

SOURCES += \
    src/main.cpp \
    src/VideoBackend.cpp \
    ../titan-common/ThemeManager.cpp

HEADERS += \
    src/VideoBackend.h \
    ../titan-common/ThemeManager.h

RESOURCES += \
    resources.qrc

target.path = /usr/local/bin
INSTALLS += target

INCLUDEPATH += src ../titan-common

