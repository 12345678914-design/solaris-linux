#ifndef TITAN_ESCRITORIO_H
#define TITAN_ESCRITORIO_H

#include <QWidget>
#include <QPixmap>
#include <QSize>
#include <QFileSystemWatcher>
#include <QVariantAnimation>

// Fondo del escritorio de Titan con transición suave estilo macOS.
class Escritorio : public QWidget
{
    Q_OBJECT

public:
    explicit Escritorio(QWidget *padre = nullptr);

public slots:
    void cargarFondo();
    void cambiarFondo(const QString &ruta);

protected:
    void paintEvent(QPaintEvent *evento) override;

private:
    QString m_rutaActual;
    QPixmap m_fondo;
    QPixmap m_fondoEscalado;
    QPixmap m_fondoPrevio;
    QPixmap m_fondoPrevioEscalado;
    QSize m_tamanoPrevio;
    QFileSystemWatcher *m_watcher;
    QVariantAnimation *m_anim;
    qreal m_progresoTransicion = 1.0;
};

#endif
