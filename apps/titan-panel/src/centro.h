#ifndef TITAN_CENTRO_H
#define TITAN_CENTRO_H

#include <QString>
#include <QVector>
#include <QWidget>

class Catalogo;
class QGridLayout;
class QLabel;
class QLineEdit;
class QScrollArea;

// Ventana layer-shell de tipo overlay: oscurece todo y deja una tarjeta
// centrada con el catalogo de aplicaciones. En el pie estan las acciones de
// apagado y reinicio, que antes vivian en el boton Salir del escritorio.
class Centro : public QWidget
{
    Q_OBJECT

public:
    explicit Centro(Catalogo *catalogo, QWidget *padre = nullptr);

    void abrir();
    void cerrar();
    bool estaAbierto() const;

protected:
    void paintEvent(QPaintEvent *evento) override;
    void mousePressEvent(QMouseEvent *evento) override;

private slots:
    void filtrar(const QString &texto);
    void lanzar(const QString &id);
    void apagar();
    void reiniciar();

private:
    Catalogo *m_catalogo = nullptr;
    QWidget *m_tarjeta = nullptr;
    QLineEdit *m_busqueda = nullptr;
    QScrollArea *m_desplazamiento = nullptr;
    QWidget *m_contenedor = nullptr;
    QGridLayout *m_rejilla = nullptr;
    QLabel *m_aviso = nullptr;

    void construir();
    void reconstruir();
    void limpiarRejilla();
    void ejecutarOrden(const QString &orden);
};

#endif
