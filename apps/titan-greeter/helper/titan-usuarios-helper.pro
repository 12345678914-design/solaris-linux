QT = core
CONFIG += c++17 warn_on release console
CONFIG -= app_bundle
TEMPLATE = app
TARGET = titan-usuarios-helper
SOURCES += main.cpp
LIBS += -lpam
DESTDIR = .
