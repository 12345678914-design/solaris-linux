QT += quick quickcontrols2 network
CONFIG += c++17 warn_on release
QMAKE_CXXFLAGS_RELEASE += -O2 -pipe
TEMPLATE = app
TARGET = titan-greeter

SOURCES += \
    src/main.cpp \
    src/GreetdCliente.cpp \
    src/Usuarios.cpp

HEADERS += \
    src/GreetdCliente.h \
    src/Sistema.h \
    src/Usuarios.h

RESOURCES += titan-greeter.qrc

DESTDIR = .
