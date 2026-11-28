QT += quick quickcontrols2 gui network
CONFIG += c++17 warn_on
TEMPLATE = app
TARGET = titan-calc

DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000

INCLUDEPATH += src ../titan-common
QML_IMPORT_PATH += ../titan-theme/qml

SOURCES += \
    src/main.cpp \
    src/CalcBackend.cpp \
    ../titan-common/ThemeManager.cpp

HEADERS += \
    src/CalcBackend.h \
    ../titan-common/ThemeManager.h

RESOURCES += resources.qrc

DESTDIR = .

