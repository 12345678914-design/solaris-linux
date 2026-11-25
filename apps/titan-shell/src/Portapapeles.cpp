#include "Portapapeles.h"

#include <QSettings>
#include <QStandardPaths>
#include <QTimer>

namespace {
// Tras cerrar el panel, el compositor devuelve el teclado a la ventana de
// antes; se espera un poco para que el pegado llegue a ella.
constexpr int kEsperaFoco = 220;

QSettings ajustes()
{
    return QSettings(QStringLiteral("titan"), QStringLiteral("portapapeles"));
}
}

Portapapeles::Portapapeles(QObject *parent)
    : QObject(parent)
{
    m_activo = ajustes().value(QStringLiteral("historial"), false).toBool();
    connect(&m_vigia, &QProcess::readyReadStandardOutput, this, &Portapapeles::leer);
    if (m_activo)
        vigilar();
}

Portapapeles::~Portapapeles()
{
    if (m_vigia.state() != QProcess::NotRunning) {
        m_vigia.kill();
        m_vigia.waitForFinished(500);
    }
}

void Portapapeles::setActivo(bool a)
{
    if (a == m_activo)
        return;
    m_activo = a;
    QSettings s(QStringLiteral("titan"), QStringLiteral("portapapeles"));
    s.setValue(QStringLiteral("historial"), a);
    if (a) {
        vigilar();
    } else {
        m_vigia.kill();
        m_elementos.clear();
        emit elementosChanged();
    }
    emit activoChanged();
}

void Portapapeles::vigilar()
{
    if (m_vigia.state() != QProcess::NotRunning
        || QStandardPaths::findExecutable(QStringLiteral("wl-paste")).isEmpty())
        return;
    // Una línea en base64 por cada cosa copiada (solo texto, hasta 20 kB).
    static const QString guion = QStringLiteral(
        "t=$(wl-paste -l 2>/dev/null); "
        "case \"$t\" in *passwordManagerHint*) exit 0;; esac; "
        "case \"$t\" in *text/plain*|*UTF8_STRING*|*TEXT*|*STRING*) "
        "wl-paste -n -t text 2>/dev/null | head -c 20000 | base64 -w0; echo;; esac");
    m_vigia.start(QStringLiteral("wl-paste"), {QStringLiteral("--watch"), QStringLiteral("sh"), QStringLiteral("-c"), guion});
}

void Portapapeles::leer()
{
    m_resto += m_vigia.readAllStandardOutput();
    bool cambio = false;
    int fin;
    while ((fin = m_resto.indexOf('\n')) >= 0) {
        const QByteArray linea = m_resto.left(fin).trimmed();
        m_resto.remove(0, fin + 1);
        const QString texto = QString::fromUtf8(QByteArray::fromBase64(linea));
        if (texto.trimmed().isEmpty())
            continue;
        // Lo mismo otra vez (o lo que se acaba de pegar desde aquí) sube arriba
        m_elementos.removeAll(texto);
        m_elementos.prepend(texto);
        while (m_elementos.size() > kMaximo)
            m_elementos.removeLast();
        cambio = true;
    }
    if (cambio)
        emit elementosChanged();
}

void Portapapeles::pegar(int indice)
{
    if (indice < 0 || indice >= m_elementos.size())
        return;
    const QString texto = m_elementos.at(indice);
    QProcess copiar;
    copiar.start(QStringLiteral("wl-copy"), {QStringLiteral("--")});
    if (!copiar.waitForStarted(1000))
        return;
    copiar.write(texto.toUtf8());
    copiar.closeWriteChannel();
    copiar.waitForFinished(1500);
    QTimer::singleShot(kEsperaFoco, this, [] {
        QProcess::startDetached(QStringLiteral("wtype"),
                                {QStringLiteral("-M"), QStringLiteral("ctrl"), QStringLiteral("v"),
                                 QStringLiteral("-m"), QStringLiteral("ctrl")});
    });
}

void Portapapeles::quitar(int indice)
{
    if (indice < 0 || indice >= m_elementos.size())
        return;
    m_elementos.removeAt(indice);
    emit elementosChanged();
}

void Portapapeles::borrarTodo()
{
    m_elementos.clear();
    emit elementosChanged();
}

void Portapapeles::escribir(const QString &texto)
{
    if (texto.isEmpty())
        return;
    QTimer::singleShot(kEsperaFoco, this, [texto] {
        QProcess::startDetached(QStringLiteral("wtype"), {QStringLiteral("--"), texto});
    });
}
