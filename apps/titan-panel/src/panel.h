#ifndef TITAN_PANEL_H
#define TITAN_PANEL_H

#include <QVector>
#include <QWidget>

#include "tareas.h"

class Catalogo;
class Centro;
class QHBoxLayout;
class QLabel;
class QToolButton;

// Barra inferior de Titan. Orden fijo:
//   [Inicio] [ancladas] [ventanas abiertas] ... [reloj]
// Inicio queda en el extremo izquierdo, junto a las aplicaciones ancladas.
// Las ventanas se agrupan por app-id. Un clic activa, restaura o minimiza;
// el menu contextual permite minimizar y cerrar cada ventana.
class Panel : public QWidget
{
    Q_OBJECT

public:
    explicit Panel(Catalogo *catalogo, MonitorTareas *tareas,
                   QWidget *padre = nullptr);
    ~Panel() override;

    void abrirCentro();

protected:
    void paintEvent(QPaintEvent *evento) override;

private slots:
    void actualizarReloj();
    void reconstruirTareas();

private:
    struct Grupo
    {
        QString appId;
        QVector<Ventana> ventanas;
    };

    Catalogo *m_catalogo = nullptr;
    MonitorTareas *m_tareas = nullptr;
    Centro *m_centro = nullptr;

    QToolButton *m_terminal = nullptr;
    QToolButton *m_archivos = nullptr;
    QToolButton *m_inicio = nullptr;
    QWidget *m_zonaTareas = nullptr;
    QHBoxLayout *m_filaTareas = nullptr;
    QLabel *m_reloj = nullptr;
    QString m_firma;

    QToolButton *crearAnclada(const QString &appId,
                              const QString &iconoRespaldo,
                              const QString &texto);
    QVector<Grupo> agrupar() const;
    QString nombreGrupo(const Grupo &grupo) const;
    QString iconoGrupo(const Grupo &grupo) const;
    void limpiarTareas();
    void abrirAnclada(bool terminal);
    void alPulsarGrupo(const Grupo &grupo, QWidget *origen);
    void mostrarMenuGrupo(const Grupo &grupo, QWidget *origen);
    void lanzarPrograma(const QString &programa);
};

#endif
