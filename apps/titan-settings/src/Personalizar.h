// Inti OS - Ajustes > Apariencia: temas (los que trae Inti y los que guarda
// cada persona). Un tema junta claro/oscuro, color de acento, fondo de
// pantalla, posicion y tamano del Dock y estilo de la barra de menus.
// Los temas propios van en ~/.config/titan/temas/<id>.conf.
#pragma once

#include <QObject>
#include <QVariantList>

class TitanPrefs;

class Personalizar : public QObject
{
    Q_OBJECT
    // [{id, nombre, propio, oscuro, acento, fondo, dockPosicion, dockTamano, barraEstilo, actual}]
    Q_PROPERTY(QVariantList temas READ temas NOTIFY temasCambiados)

public:
    explicit Personalizar(TitanPrefs *prefs, QObject *parent = nullptr);

    QVariantList temas() const { return m_temas; }

    Q_INVOKABLE void recargar();
    // Guarda como tema todo lo que hay ahora; devuelve texto de error o "".
    Q_INVOKABLE QString guardarTema(const QString &nombre);
    Q_INVOKABLE void aplicarTema(const QString &id);
    Q_INVOKABLE void borrarTema(const QString &id);
    // Apps que han mandado notificaciones (las apunta titan-shell):
    // [{clave, nombre, icono}]
    Q_INVOKABLE QVariantList appsNotificadoras() const;

signals:
    void temasCambiados();

private:
    QString carpeta() const;
    QVariantMap actual() const;

    TitanPrefs *m_prefs;
    QVariantList m_temas;
};
