// Inti OS - teclado en pantalla: manda las pulsaciones con wtype.
#pragma once

#include <QObject>
#include <QStringList>

class Teclado : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;
    // Escribe un texto (una letra, "ñ", "€"...). Con modificadores
    // ("ctrl", "alt", "logo") se mantienen pulsados mientras tanto.
    Q_INVOKABLE void texto(const QString &t, const QStringList &modificadores = {});
    // Pulsa una tecla por su nombre XKB: BackSpace, Return, Tab, Left...
    Q_INVOKABLE void tecla(const QString &nombre, const QStringList &modificadores = {});
    Q_INVOKABLE void salir();

private:
    void wtype(const QStringList &medio, const QStringList &modificadores);
};
