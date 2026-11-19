// Inti OS - preferencias del escritorio compartidas entre Ajustes y titan-shell.
//
// Un solo fichero, ~/.config/titan/shell.conf (INI), con grupos:
//   [Dock]            posicion (abajo|izquierda|derecha), tamano (32-64),
//                     ampliacion, ocultarAuto, visible
//   [Barra]           visible, estilo (transparente|vidrio|solido), reloj24h,
//                     segundos, fecha, diaSemana, bateriaPorcentaje,
//                     iconoWifi, iconoBluetooth, iconoFondo
//   [Centro]          conectividad, energia, brillo, sonido, noMolestar
//   [Notificaciones]  vistaPrevia, sonido, noMolestar, apps/<app>=false,
//                     bloqueo (todo|sinContenido|nada: en la pantalla de bloqueo)
//   [Concentracion]   programado, desde (HH:mm), hasta (HH:mm)
//   [Escritorio]      iconos
//
// Ajustes escribe con poner(); titan-shell vigila el fichero y se actualiza en
// vivo. En QML: `prefs.version, prefs.v("Dock/posicion")` (leer `version`
// hace que la expresion se reevalue al cambiar el fichero).
#pragma once

#include <QObject>
#include <QVariant>
#include <QVariantMap>

class QFileSystemWatcher;
class QTimer;

class TitanPrefs : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int version READ version NOTIFY cambiado)

public:
    explicit TitanPrefs(QObject *parent = nullptr);

    int version() const { return m_version; }

    // Valor de "Grupo/clave" (o el valor por defecto de la tabla).
    Q_INVOKABLE QVariant v(const QString &clave) const;
    Q_INVOKABLE bool b(const QString &clave) const { return v(clave).toBool(); }
    Q_INVOKABLE int i(const QString &clave) const { return v(clave).toInt(); }
    Q_INVOKABLE QString s(const QString &clave) const { return v(clave).toString(); }
    Q_INVOKABLE void poner(const QString &clave, const QVariant &valor);
    Q_INVOKABLE void quitar(const QString &clave);

    // Todas las claves de un grupo con prefijo (p. ej. "Notificaciones/apps").
    Q_INVOKABLE QVariantMap grupo(const QString &prefijo) const;

    // Concentracion: no molestar ahora mismo (manual o por horario).
    Q_INVOKABLE bool noMolestarActivo() const;

    static QString ruta();
    static QVariant porDefecto(const QString &clave);

signals:
    void cambiado();

private:
    void recargar();
    void vigilar();

    QVariantMap m_valores;
    int m_version = 0;
    QFileSystemWatcher *m_vigia = nullptr;
    QTimer *m_retraso = nullptr;
};
