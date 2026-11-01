#ifndef TITAN_CONFIG_H
#define TITAN_CONFIG_H

#include <QHash>
#include <QString>

// Variables globales de personalizacion del sistema.
//
// Se leen una vez de /etc/titan/base.conf (o de la ruta que diga la variable
// de entorno TITAN_CONFIG) y se consultan desde toda la aplicacion. Cambiar
// el nombre de la distribucion o el usuario es editar ese fichero, no tocar
// codigo.
class Config
{
public:
    static const Config &instancia();

    QString soNombre() const;
    QString soVersion() const;
    QString soId() const;
    QString usuario() const;
    QString hostname() const;
    QString terminal() const;
    QString explorador() const;
    QString escritorio() const;
    QString apagar() const;
    QString reiniciar() const;
    QString fondoColor1() const;
    QString fondoColor2() const;

    int barraAlto() const;
    QString barraFondo() const;
    double barraAlfa() const;
    QString barraAcento() const;
    QString inicioTexto() const;

    int centroAncho() const;
    int centroAlto() const;
    int centroColumnas() const;
    double centroOscuridad() const;

    QString rutaCargada() const;

private:
    Config();
    void cargar();
    QString valor(const QString &clave, const QString &defecto) const;

    QHash<QString, QString> m_valores;
    QString m_ruta;
};

#endif
