#ifndef TITAN_GREETER_SISTEMA_H
#define TITAN_GREETER_SISTEMA_H

// Lo poco del sistema que necesita la pantalla de inicio: fondo, energia y
// recordar con que usuario se entro la ultima vez.

#include <QFile>
#include <QHash>
#include <QObject>
#include <QRegularExpression>
#include <QVariantMap>
#include <QProcess>
#include <QString>

class Sistema : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString fondo READ fondo CONSTANT)
    Q_PROPERTY(QString ultimoUsuario READ ultimoUsuario CONSTANT)
    Q_PROPERTY(QString nombreSistema READ nombreSistema CONSTANT)
    // Pantalla de inicio extra de "Cambiar de usuario" (titan-otro-usuario@N)
    Q_PROPERTY(bool modoCambio READ modoCambio CONSTANT)
    // Cuentas con una sesion ya abierta: {usuario: id de sesion de logind}
    Q_PROPERTY(QVariantMap sesiones READ sesiones NOTIFY sesionesCambiadas)

public:
    explicit Sistema(QObject *parent = nullptr) : QObject(parent)
    {
        // Consola de esta pantalla (para pararla al volver a una sesion)
        m_vt = qEnvironmentVariable("XDG_VTNR");
        if (m_vt.isEmpty()) {
            QFile f(QStringLiteral("/sys/class/tty/tty0/active"));
            if (f.open(QIODevice::ReadOnly))
                m_vt = QString::fromLatin1(f.readAll()).trimmed().remove(QStringLiteral("tty"));
        }
        actualizarSesiones();
    }

    bool modoCambio() const { return qEnvironmentVariableIsSet("TITAN_GREETER_CAMBIO"); }
    QVariantMap sesiones() const { return m_sesiones; }

    Q_INVOKABLE void actualizarSesiones()
    {
        QVariantMap nuevas;
        QProcess lista;
        lista.start(QStringLiteral("loginctl"), {QStringLiteral("list-sessions"), QStringLiteral("--no-legend")});
        if (lista.waitForFinished(2000)) {
            const QStringList lineas = QString::fromUtf8(lista.readAllStandardOutput()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
            for (const QString &l : lineas) {
                const QString id = l.trimmed().section(QRegularExpression(QStringLiteral("\\s+")), 0, 0);
                if (id.isEmpty())
                    continue;
                QProcess ver;
                ver.start(QStringLiteral("loginctl"), {QStringLiteral("show-session"), id, QStringLiteral("-p"), QStringLiteral("Name"),
                                                       QStringLiteral("-p"), QStringLiteral("Class"), QStringLiteral("-p"), QStringLiteral("Type"),
                                                       QStringLiteral("-p"), QStringLiteral("Remote")});
                if (!ver.waitForFinished(2000))
                    continue;
                QHash<QString, QString> p;
                for (const QString &kv : QString::fromUtf8(ver.readAllStandardOutput()).split(QLatin1Char('\n'), Qt::SkipEmptyParts))
                    p.insert(kv.section(QLatin1Char('='), 0, 0), kv.section(QLatin1Char('='), 1));
                // Solo sesiones graficas de personas en este equipo
                if (p.value(QStringLiteral("Class")) == QLatin1String("user") && p.value(QStringLiteral("Remote")) != QLatin1String("yes")
                    && (p.value(QStringLiteral("Type")) == QLatin1String("wayland") || p.value(QStringLiteral("Type")) == QLatin1String("x11")))
                    nuevas.insert(p.value(QStringLiteral("Name")), id);
            }
        }
        if (nuevas != m_sesiones) {
            m_sesiones = nuevas;
            emit sesionesCambiadas();
        }
    }

    // Volver a la sesion abierta de esa cuenta: se ve su pantalla de bloqueo,
    // que pide su contrasena. Si esta es la pantalla extra, se cierra.
    Q_INVOKABLE bool irASesion(const QString &usuario)
    {
        const QString id = m_sesiones.value(usuario).toString();
        if (id.isEmpty())
            return false;
        if (QProcess::execute(QStringLiteral("loginctl"), {QStringLiteral("activate"), id}) != 0)
            return false;
        static const QRegularExpression vtValida(QStringLiteral("^(8|9|10|11|12)$"));
        if (modoCambio() && vtValida.match(m_vt).hasMatch())
            QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("stop"), QStringLiteral("--no-block"),
                                                                 QStringLiteral("titan-otro-usuario@") + m_vt + QStringLiteral(".service")});
        return true;
    }

    static QString ficheroUltimo() { return QStringLiteral("/var/lib/titan-greeter/ultimo-usuario"); }

    QString fondo() const
    {
        const QString propio = qEnvironmentVariable("TITAN_GREETER_FONDO");
        if (!propio.isEmpty() && QFile::exists(propio))
            return propio;
        for (const QString &f : {QStringLiteral("/etc/titan/greeter-fondo.jpg"),
                                 QStringLiteral("/usr/share/titan/wallpaper.jpg")}) {
            if (QFile::exists(f))
                return f;
        }
        return {};
    }

    QString ultimoUsuario() const
    {
        QFile f(ficheroUltimo());
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
            return {};
        return QString::fromUtf8(f.readLine(64)).trimmed();
    }

    QString nombreSistema() const { return QStringLiteral("Inti OS"); }

    Q_INVOKABLE void recordarUsuario(const QString &usuario)
    {
        QFile f(ficheroUltimo());
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
            f.write(usuario.toUtf8() + '\n');
    }

    Q_INVOKABLE void apagar() { QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("poweroff")}); }
    Q_INVOKABLE void reiniciar() { QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("reboot")}); }
    Q_INVOKABLE void suspender() { QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("suspend")}); }

signals:
    void sesionesCambiadas();

private:
    QVariantMap m_sesiones;
    QString m_vt;
};

#endif
