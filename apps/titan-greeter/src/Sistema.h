#ifndef TITAN_GREETER_SISTEMA_H
#define TITAN_GREETER_SISTEMA_H

// Lo poco del sistema que necesita la pantalla de inicio: fondo, energia y
// recordar con que usuario se entro la ultima vez.

#include <QFile>
#include <QObject>
#include <QProcess>
#include <QString>

class Sistema : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString fondo READ fondo CONSTANT)
    Q_PROPERTY(QString ultimoUsuario READ ultimoUsuario CONSTANT)
    Q_PROPERTY(QString nombreSistema READ nombreSistema CONSTANT)

public:
    explicit Sistema(QObject *parent = nullptr) : QObject(parent) {}

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
};

#endif
