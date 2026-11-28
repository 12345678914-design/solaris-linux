#include "Teclado.h"

#include <QGuiApplication>
#include <QProcess>

void Teclado::wtype(const QStringList &medio, const QStringList &modificadores)
{
    QStringList args;
    for (const QString &m : modificadores)
        args << QStringLiteral("-M") << m;
    args += medio;
    for (const QString &m : modificadores)
        args << QStringLiteral("-m") << m;
    QProcess::startDetached(QStringLiteral("wtype"), args);
}

void Teclado::texto(const QString &t, const QStringList &modificadores)
{
    if (t.isEmpty())
        return;
    // "--": que un "-" escrito no se tome por una opción de wtype
    wtype({QStringLiteral("--"), t}, modificadores);
}

void Teclado::tecla(const QString &nombre, const QStringList &modificadores)
{
    wtype({QStringLiteral("-k"), nombre}, modificadores);
}

void Teclado::salir()
{
    QGuiApplication::quit();
}
