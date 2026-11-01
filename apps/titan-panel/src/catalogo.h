#ifndef TITAN_CATALOGO_H
#define TITAN_CATALOGO_H

#include <QString>
#include <QStringList>
#include <QVector>

// Una entrada de /usr/share/applications ya interpretada. El Exec que se
// guarda ya no lleva codigos de campo (%f, %U, etc.): se puede ejecutar tal
// cual con QProcess::splitCommand.
struct Aplicacion
{
    QString id;
    QString ruta;
    QString nombre;
    QString comentario;
    QString icono;
    QString exec;
    QString wmClass;
    bool terminal = false;
};

// Catalogo de aplicaciones del sistema. Lee los directorios XDG y se queda
// con la primera definicion de cada id, para que ~/.local/share gane sobre
// /usr/share.
class Catalogo
{
public:
    void cargar();
    void cargarDesde(const QStringList &directorios);

    QVector<Aplicacion> aplicaciones() const;
    QString iconoParaAppId(const QString &appId) const;
    const Aplicacion *buscarPorAppId(const QString &appId) const;

    static QString limpiarExec(const QString &exec);
    static bool lanzar(const Aplicacion &app, const QString &terminal,
                       QString *error);

private:
    QVector<Aplicacion> m_aplicaciones;
};

#endif
