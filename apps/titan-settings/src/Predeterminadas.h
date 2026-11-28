// Inti OS - Ajustes > Aplicaciones predeterminadas: con qué app se abre cada
// tipo de cosa (navegador, correo, PDF, fotos...). Como "Aplicaciones
// predeterminadas" de Windows. Se guarda en ~/.config/mimeapps.list de la
// persona (estándar freedesktop); no toca el sistema ni pide contraseña.
#pragma once

#include <QObject>
#include <QVariantList>

class Predeterminadas : public QObject
{
    Q_OBJECT
    // [{id, nombre, detalle, simbolo, actual, opciones: [{valor, texto}]}]
    Q_PROPERTY(QVariantList tipos READ tipos NOTIFY cambiado)

public:
    explicit Predeterminadas(QObject *parent = nullptr);
    QVariantList tipos() const { return m_tipos; }

    Q_INVOKABLE void recargar();
    // desktop = nombre del .desktop, p. ej. "firefox.desktop"
    Q_INVOKABLE bool elegir(const QString &id, const QString &desktop);

signals:
    void cambiado();

private:
    QVariantList m_tipos;
};
