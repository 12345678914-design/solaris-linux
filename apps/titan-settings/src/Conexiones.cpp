#include "Conexiones.h"

#include <QHash>
#include <QProcess>
#include <QRegularExpression>
#include <QSet>
#include <QTimer>
#include <memory>

namespace {

// nmcli -t separa con ':' y escapa ':' y '\' con '\'.
QStringList camposNmcli(const QString &linea)
{
    QStringList r;
    QString actual;
    for (int i = 0; i < linea.size(); ++i) {
        const QChar c = linea.at(i);
        if (c == QLatin1Char('\\') && i + 1 < linea.size()) {
            actual += linea.at(++i);
        } else if (c == QLatin1Char(':')) {
            r << actual;
            actual.clear();
        } else {
            actual += c;
        }
    }
    r << actual;
    return r;
}

QString textoSeguridad(const QString &s)
{
    if (s.isEmpty() || s == QStringLiteral("--"))
        return QString();
    return s;
}

} // namespace

Conexiones::Conexiones(QObject *parent)
    : QObject(parent)
{
}

void Conexiones::correr(const QString &programa, const QStringList &args, Fin fin, int msMax)
{
    auto *p = new QProcess(this);
    auto hecho = std::make_shared<bool>(false);
    connect(p, &QProcess::finished, this, [p, fin, hecho](int codigo, QProcess::ExitStatus estado) {
        if (*hecho)
            return;
        *hecho = true;
        const QString salida = QString::fromUtf8(p->readAllStandardOutput());
        const QString error = QString::fromUtf8(p->readAllStandardError()).trimmed();
        p->deleteLater();
        fin(estado == QProcess::NormalExit ? codigo : -1, salida, error);
    });
    connect(p, &QProcess::errorOccurred, this, [p, fin, hecho, programa](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart || *hecho)
            return;
        *hecho = true;
        p->deleteLater();
        fin(-2, QString(), programa + QStringLiteral(" no esta instalado"));
    });
    QTimer::singleShot(msMax, p, [p]() { p->kill(); });
    p->start(programa, args);
}

void Conexiones::avisar(const QString &t)
{
    m_mensaje = t;
    emit mensajeCambiado();
}

void Conexiones::limpiarMensaje()
{
    avisar(QString());
}

// ------------------------------------------------------------------ Wi-Fi

void Conexiones::leerWifi()
{
    correr(QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("TYPE,STATE"), QStringLiteral("device")},
           [this](int, const QString &dispositivos, const QString &) {
        m_hayWifi = dispositivos.contains(QStringLiteral("wifi:"));
        correr(QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi")},
               [this](int, const QString &radio, const QString &) {
            m_wifiActivo = radio.trimmed() == QStringLiteral("enabled");
            // Perfiles guardados de Wi-Fi
            correr(QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("-f"),
                                             QStringLiteral("NAME,UUID,TYPE,AUTOCONNECT,TIMESTAMP,ACTIVE"),
                                             QStringLiteral("connection"), QStringLiteral("show")},
                   [this](int, const QString &salida, const QString &) {
                QVariantList perfiles;
                for (const QString &l : salida.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                    const QStringList c = camposNmcli(l);
                    if (c.size() < 6 || c[2] != QStringLiteral("802-11-wireless"))
                        continue;
                    perfiles << QVariantMap{
                        {QStringLiteral("nombre"), c[0]},
                        {QStringLiteral("uuid"), c[1]},
                        {QStringLiteral("autoconectar"), c[3] == QStringLiteral("yes")},
                        {QStringLiteral("ultima"), c[4].toLongLong()},
                        {QStringLiteral("activa"), c[5] == QStringLiteral("yes")},
                    };
                }
                leerPerfiles(perfiles, 0, {});
            });
        });
    });
}

// El SSID de cada perfil (el nombre del perfil puede ser otro).
void Conexiones::leerPerfiles(QVariantList perfiles, int i, QVariantList listos)
{
    if (i >= perfiles.size()) {
        std::sort(listos.begin(), listos.end(), [](const QVariant &a, const QVariant &b) {
            return a.toMap().value(QStringLiteral("ultima")).toLongLong() > b.toMap().value(QStringLiteral("ultima")).toLongLong();
        });
        m_conocidas = listos;
        m_redActual.clear();
        for (const QVariant &v : std::as_const(m_conocidas)) {
            if (v.toMap().value(QStringLiteral("activa")).toBool())
                m_redActual = v.toMap().value(QStringLiteral("ssid")).toString();
        }
        unirListas();
        return;
    }
    QVariantMap p = perfiles[i].toMap();
    correr(QStringLiteral("nmcli"), {QStringLiteral("-g"), QStringLiteral("802-11-wireless.ssid"),
                                     QStringLiteral("connection"), QStringLiteral("show"), p.value(QStringLiteral("uuid")).toString()},
           [this, perfiles, i, listos, p](int, const QString &salida, const QString &) mutable {
        QString ssid = salida.trimmed();
        ssid.replace(QStringLiteral("\\:"), QStringLiteral(":"));
        p[QStringLiteral("ssid")] = ssid.isEmpty() ? p.value(QStringLiteral("nombre")).toString() : ssid;
        listos << p;
        leerPerfiles(perfiles, i + 1, listos);
    });
}

void Conexiones::unirListas()
{
    QHash<QString, QString> uuidDe;
    for (const QVariant &v : std::as_const(m_conocidas)) {
        const QVariantMap m = v.toMap();
        if (!uuidDe.contains(m.value(QStringLiteral("ssid")).toString()))
            uuidDe.insert(m.value(QStringLiteral("ssid")).toString(), m.value(QStringLiteral("uuid")).toString());
    }
    QVariantList r;
    for (const QVariant &v : std::as_const(m_escaneadas)) {
        QVariantMap m = v.toMap();
        const QString ssid = m.value(QStringLiteral("ssid")).toString();
        m[QStringLiteral("conocida")] = uuidDe.contains(ssid);
        m[QStringLiteral("uuid")] = uuidDe.value(ssid);
        m[QStringLiteral("conectada")] = m.value(QStringLiteral("conectada")).toBool() || ssid == m_redActual;
        r << m;
    }
    std::stable_sort(r.begin(), r.end(), [](const QVariant &a, const QVariant &b) {
        const QVariantMap x = a.toMap(), y = b.toMap();
        if (x[QStringLiteral("conectada")].toBool() != y[QStringLiteral("conectada")].toBool())
            return x[QStringLiteral("conectada")].toBool();
        if (x[QStringLiteral("conocida")].toBool() != y[QStringLiteral("conocida")].toBool())
            return x[QStringLiteral("conocida")].toBool();
        return x[QStringLiteral("senal")].toInt() > y[QStringLiteral("senal")].toInt();
    });
    m_redes = r;
    emit wifiCambiado();
}

void Conexiones::escanear()
{
    if (m_escaneando)
        return;
    m_escaneando = true;
    emit wifiCambiado();
    correr(QStringLiteral("nmcli"), {QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("rescan")},
           [this](int, const QString &, const QString &) {
        // El escaneo tarda un poco en llenar la lista.
        QTimer::singleShot(1500, this, [this]() {
            correr(QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("IN-USE,SSID,SIGNAL,SECURITY"),
                                             QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("list"),
                                             QStringLiteral("--rescan"), QStringLiteral("no")},
                   [this](int, const QString &salida, const QString &) {
                QVariantList lista;
                QHash<QString, int> indice;
                for (const QString &l : salida.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                    const QStringList c = camposNmcli(l);
                    if (c.size() < 4 || c[1].trimmed().isEmpty())
                        continue;
                    const QString ssid = c[1];
                    const int senal = c[2].toInt();
                    const bool enUso = c[0].trimmed() == QStringLiteral("*");
                    // Varios puntos de acceso con el mismo nombre: el de mas senal.
                    if (indice.contains(ssid)) {
                        QVariantMap m = lista[indice[ssid]].toMap();
                        if (senal > m[QStringLiteral("senal")].toInt())
                            m[QStringLiteral("senal")] = senal;
                        if (enUso)
                            m[QStringLiteral("conectada")] = true;
                        lista[indice[ssid]] = m;
                        continue;
                    }
                    indice.insert(ssid, lista.size());
                    lista << QVariantMap{
                        {QStringLiteral("ssid"), ssid},
                        {QStringLiteral("senal"), senal},
                        {QStringLiteral("seguridad"), textoSeguridad(c[3])},
                        {QStringLiteral("conectada"), enUso},
                    };
                }
                m_escaneadas = lista;
                m_escaneando = false;
                leerWifi();
            });
        });
    }, 15000);
}

void Conexiones::setWifi(bool activo)
{
    correr(QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi"), activo ? QStringLiteral("on") : QStringLiteral("off")},
           [this, activo](int codigo, const QString &, const QString &error) {
        if (codigo != 0)
            avisar(QStringLiteral("No se pudo cambiar el Wi-Fi: ") + error);
        if (activo)
            QTimer::singleShot(1500, this, &Conexiones::escanear);
        else
            m_escaneadas.clear();
        leerWifi();
    });
}

bool Conexiones::esConocida(const QString &ssid) const
{
    for (const QVariant &v : m_conocidas) {
        if (v.toMap().value(QStringLiteral("ssid")).toString() == ssid)
            return true;
    }
    return false;
}

void Conexiones::conectar(const QString &ssid, const QString &clave)
{
    if (ssid.isEmpty() || !m_conectando.isEmpty())
        return;
    if (clave.contains(QLatin1Char('\n')))
        return avisar(QStringLiteral("La contraseña no puede tener saltos de línea"));
    QString uuid;
    for (const QVariant &v : std::as_const(m_conocidas)) {
        if (v.toMap().value(QStringLiteral("ssid")).toString() == ssid) {
            uuid = v.toMap().value(QStringLiteral("uuid")).toString();
            break;
        }
    }
    QString seguridad;
    for (const QVariant &v : std::as_const(m_redes)) {
        if (v.toMap().value(QStringLiteral("ssid")).toString() == ssid)
            seguridad = v.toMap().value(QStringLiteral("seguridad")).toString();
    }

    m_conectando = ssid;
    emit wifiCambiado();
    avisar(QString());

    auto terminar = [this, ssid](bool ok, const QString &error) {
        m_conectando.clear();
        if (ok)
            avisar(QStringLiteral("Conectado a ") + ssid + QStringLiteral(". La contraseña queda guardada."));
        else
            avisar(QStringLiteral("No se pudo conectar a ") + ssid + QStringLiteral(": ") + error);
        leerWifi();
    };

    // Levanta un perfil; si falla y era nuevo, se borra (no deja basura).
    auto levantar = [this, terminar](const QString &id, bool nuevo) {
        correr(QStringLiteral("nmcli"), {QStringLiteral("-w"), QStringLiteral("40"), QStringLiteral("connection"), QStringLiteral("up"), id},
               [this, terminar, id, nuevo](int codigo, const QString &, const QString &error) {
            if (codigo == 0)
                return terminar(true, QString());
            QString e = error;
            if (e.contains(QStringLiteral("Secrets were required")) || e.contains(QStringLiteral("802-11-wireless-security")))
                e = QStringLiteral("la contraseña no es correcta");
            if (nuevo)
                correr(QStringLiteral("nmcli"), {QStringLiteral("connection"), QStringLiteral("delete"), id}, [](int, const QString &, const QString &) {});
            terminar(false, e);
        }, 60000);
    };

    // Pone la contrasena en un perfil sin que aparezca en la lista de procesos.
    auto ponerClave = [this](const QString &id, const QString &c, std::function<void(bool, QString)> luego) {
        auto *p = new QProcess(this);
        connect(p, &QProcess::finished, this, [p, luego](int codigo, QProcess::ExitStatus) {
            const QString err = QString::fromUtf8(p->readAllStandardError() + p->readAllStandardOutput());
            p->deleteLater();
            luego(codigo == 0 && !err.contains(QStringLiteral("Error")), err.trimmed());
        });
        p->start(QStringLiteral("nmcli"), {QStringLiteral("connection"), QStringLiteral("edit"), id});
        p->write(("set 802-11-wireless-security.psk " + c + "\nsave persistent\nquit\n").toUtf8());
        p->closeWriteChannel();
    };

    if (!uuid.isEmpty()) {
        // Red conocida: su perfil ya tiene la contrasena.
        if (clave.isEmpty())
            return levantar(uuid, false);
        ponerClave(uuid, clave, [levantar, uuid, terminar](bool ok, const QString &err) {
            if (!ok)
                return terminar(false, err);
            levantar(uuid, false);
        });
        return;
    }

    if (seguridad.isEmpty()) {
        // Abierta: la crea nmcli.
        correr(QStringLiteral("nmcli"), {QStringLiteral("-w"), QStringLiteral("40"), QStringLiteral("device"), QStringLiteral("wifi"),
                                         QStringLiteral("connect"), ssid},
               [terminar](int codigo, const QString &, const QString &error) { terminar(codigo == 0, error); }, 60000);
        return;
    }
    if (seguridad.contains(QStringLiteral("802.1X"))) {
        m_conectando.clear();
        emit wifiCambiado();
        return avisar(QStringLiteral("Esta red es de empresa (802.1X): configúrala con «Editor de conexiones» (nm-connection-editor)."));
    }
    if (clave.isEmpty()) {
        m_conectando.clear();
        emit wifiCambiado();
        return avisar(QStringLiteral("Escribe la contraseña de ") + ssid);
    }
    // WPA3 solo: SAE. WPA2 (o mixta): PSK.
    const bool sae = seguridad.contains(QStringLiteral("WPA3")) && !seguridad.contains(QStringLiteral("WPA2"))
                     && !seguridad.contains(QStringLiteral("WPA1"));
    correr(QStringLiteral("nmcli"), {QStringLiteral("connection"), QStringLiteral("add"), QStringLiteral("type"), QStringLiteral("wifi"),
                                     QStringLiteral("con-name"), ssid, QStringLiteral("ifname"), QStringLiteral("*"),
                                     QStringLiteral("ssid"), ssid,
                                     QStringLiteral("wifi-sec.key-mgmt"), sae ? QStringLiteral("sae") : QStringLiteral("wpa-psk"),
                                     QStringLiteral("connection.autoconnect"), QStringLiteral("yes")},
           [ponerClave, levantar, terminar, clave](int codigo, const QString &salida, const QString &error) {
        static const QRegularExpression reUuid(QStringLiteral("\\(([0-9a-f-]{36})\\)"));
        const auto m = reUuid.match(salida);
        if (codigo != 0 || !m.hasMatch())
            return terminar(false, error.isEmpty() ? salida : error);
        const QString nuevo = m.captured(1);
        ponerClave(nuevo, clave, [levantar, nuevo, terminar](bool ok, const QString &err) {
            if (!ok)
                return terminar(false, err);
            levantar(nuevo, true);
        });
    });
}

void Conexiones::unirseOculta(const QString &ssid, const QString &clave)
{
    if (ssid.trimmed().isEmpty())
        return avisar(QStringLiteral("Escribe el nombre de la red"));
    if (clave.contains(QLatin1Char('\n')))
        return avisar(QStringLiteral("La contraseña no puede tener saltos de línea"));
    m_conectando = ssid;
    emit wifiCambiado();
    QStringList args{QStringLiteral("connection"), QStringLiteral("add"), QStringLiteral("type"), QStringLiteral("wifi"),
                     QStringLiteral("con-name"), ssid, QStringLiteral("ifname"), QStringLiteral("*"),
                     QStringLiteral("ssid"), ssid, QStringLiteral("802-11-wireless.hidden"), QStringLiteral("yes")};
    if (!clave.isEmpty())
        args << QStringLiteral("wifi-sec.key-mgmt") << QStringLiteral("wpa-psk");
    correr(QStringLiteral("nmcli"), args, [this, ssid, clave](int codigo, const QString &salida, const QString &error) {
        static const QRegularExpression reUuid(QStringLiteral("\\(([0-9a-f-]{36})\\)"));
        const auto m = reUuid.match(salida);
        if (codigo != 0 || !m.hasMatch()) {
            m_conectando.clear();
            avisar(QStringLiteral("No se pudo crear la red: ") + (error.isEmpty() ? salida : error));
            return leerWifi();
        }
        // Ya es conocida: conectar() usa el perfil y le pone la contrasena.
        const QString uuid = m.captured(1);
        m_conocidas << QVariantMap{{QStringLiteral("ssid"), ssid}, {QStringLiteral("uuid"), uuid}, {QStringLiteral("nombre"), ssid}};
        m_conectando.clear();
        conectar(ssid, clave);
    });
}

void Conexiones::desconectar()
{
    for (const QVariant &v : std::as_const(m_conocidas)) {
        const QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("activa")).toBool()) {
            correr(QStringLiteral("nmcli"), {QStringLiteral("connection"), QStringLiteral("down"), m.value(QStringLiteral("uuid")).toString()},
                   [this](int, const QString &, const QString &) { leerWifi(); });
            return;
        }
    }
}

void Conexiones::olvidar(const QString &uuid)
{
    correr(QStringLiteral("nmcli"), {QStringLiteral("connection"), QStringLiteral("delete"), uuid},
           [this](int codigo, const QString &, const QString &error) {
        avisar(codigo == 0 ? QStringLiteral("Red olvidada: se borró su contraseña guardada")
                           : QStringLiteral("No se pudo olvidar la red: ") + error);
        leerWifi();
    });
}

void Conexiones::setAutoconectar(const QString &uuid, bool si)
{
    correr(QStringLiteral("nmcli"), {QStringLiteral("connection"), QStringLiteral("modify"), uuid,
                                     QStringLiteral("connection.autoconnect"), si ? QStringLiteral("yes") : QStringLiteral("no")},
           [this](int codigo, const QString &, const QString &error) {
        if (codigo != 0)
            avisar(QStringLiteral("No se pudo cambiar: ") + error);
        leerWifi();
    });
}

void Conexiones::verClave(const QString &uuid)
{
    correr(QStringLiteral("nmcli"), {QStringLiteral("-s"), QStringLiteral("-g"), QStringLiteral("802-11-wireless-security.psk"),
                                     QStringLiteral("connection"), QStringLiteral("show"), uuid},
           [this, uuid](int codigo, const QString &salida, const QString &error) {
        if (codigo != 0)
            return avisar(QStringLiteral("No se pudo leer la contraseña: ") + error);
        const QString c = salida.trimmed();
        emit claveLeida(uuid, c.isEmpty() ? QStringLiteral("(sin contraseña)") : c);
    }, 120000);
}

// ------------------------------------------------------------------ Bluetooth

void Conexiones::leerBt()
{
    correr(QStringLiteral("bluetoothctl"), {QStringLiteral("show")}, [this](int codigo, const QString &salida, const QString &) {
        m_hayBt = codigo == 0 && salida.contains(QStringLiteral("Controller"));
        m_btActivo = salida.contains(QStringLiteral("Powered: yes"));
        if (!m_hayBt) {
            m_dispositivos.clear();
            emit btCambiado();
            return;
        }
        correr(QStringLiteral("bluetoothctl"), {QStringLiteral("devices")}, [this](int, const QString &salida, const QString &) {
            QStringList macs;
            static const QRegularExpression re(QStringLiteral("^Device ([0-9A-Fa-f:]{17})"));
            for (const QString &l : salida.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                const auto m = re.match(l.trimmed());
                if (m.hasMatch() && !macs.contains(m.captured(1)))
                    macs << m.captured(1);
            }
            leerInfoBt(macs, 0, {});
        });
    });
}

void Conexiones::leerInfoBt(QStringList macs, int i, QVariantList listos)
{
    if (i >= macs.size()) {
        std::stable_sort(listos.begin(), listos.end(), [](const QVariant &a, const QVariant &b) {
            const QVariantMap x = a.toMap(), y = b.toMap();
            if (x[QStringLiteral("conectado")].toBool() != y[QStringLiteral("conectado")].toBool())
                return x[QStringLiteral("conectado")].toBool();
            return x[QStringLiteral("emparejado")].toBool() && !y[QStringLiteral("emparejado")].toBool();
        });
        m_dispositivos = listos;
        emit btCambiado();
        return;
    }
    const QString mac = macs[i];
    correr(QStringLiteral("bluetoothctl"), {QStringLiteral("info"), mac},
           [this, macs, i, listos, mac](int, const QString &salida, const QString &) mutable {
        QVariantMap d{{QStringLiteral("mac"), mac}, {QStringLiteral("nombre"), mac}, {QStringLiteral("bateria"), -1}};
        QString icono;
        for (QString l : salida.split(QLatin1Char('\n'))) {
            l = l.trimmed();
            auto valor = [&l]() { return l.section(QLatin1Char(':'), 1).trimmed(); };
            if (l.startsWith(QStringLiteral("Alias:")))
                d[QStringLiteral("nombre")] = valor();
            else if (l.startsWith(QStringLiteral("Paired:")))
                d[QStringLiteral("emparejado")] = valor() == QStringLiteral("yes");
            else if (l.startsWith(QStringLiteral("Trusted:")))
                d[QStringLiteral("confiable")] = valor() == QStringLiteral("yes");
            else if (l.startsWith(QStringLiteral("Connected:")))
                d[QStringLiteral("conectado")] = valor() == QStringLiteral("yes");
            else if (l.startsWith(QStringLiteral("Icon:")))
                icono = valor();
            else if (l.startsWith(QStringLiteral("Battery Percentage:"))) {
                // "0x5a (90)"
                static const QRegularExpression re(QStringLiteral("\\((\\d+)\\)"));
                const auto m = re.match(l);
                if (m.hasMatch())
                    d[QStringLiteral("bateria")] = m.captured(1).toInt();
            }
        }
        QString tipo = QStringLiteral("Dispositivo");
        if (icono.startsWith(QStringLiteral("audio")))
            tipo = QStringLiteral("Audio");
        else if (icono == QStringLiteral("input-keyboard"))
            tipo = QStringLiteral("Teclado");
        else if (icono == QStringLiteral("input-mouse"))
            tipo = QStringLiteral("Ratón");
        else if (icono == QStringLiteral("input-gaming"))
            tipo = QStringLiteral("Mando");
        else if (icono == QStringLiteral("phone"))
            tipo = QStringLiteral("Teléfono");
        else if (icono == QStringLiteral("computer"))
            tipo = QStringLiteral("Ordenador");
        d[QStringLiteral("icono")] = icono;
        d[QStringLiteral("tipo")] = tipo;
        listos << d;
        leerInfoBt(macs, i + 1, listos);
    }, 8000);
}

void Conexiones::buscarBt()
{
    if (m_buscando)
        return;
    m_buscando = true;
    emit btCambiado();
    correr(QStringLiteral("bluetoothctl"), {QStringLiteral("--timeout"), QStringLiteral("8"), QStringLiteral("scan"), QStringLiteral("on")},
           [this](int, const QString &, const QString &) {
        m_buscando = false;
        leerBt();
    }, 15000);
}

void Conexiones::setBt(bool activo)
{
    auto encender = [this, activo]() {
        correr(QStringLiteral("bluetoothctl"), {QStringLiteral("power"), activo ? QStringLiteral("on") : QStringLiteral("off")},
               [this, activo](int, const QString &salida, const QString &) {
            if (activo && !salida.contains(QStringLiteral("succeeded")))
                avisar(QStringLiteral("No se pudo encender el Bluetooth"));
            leerBt();
        });
    };
    if (activo)
        correr(QStringLiteral("rfkill"), {QStringLiteral("unblock"), QStringLiteral("bluetooth")},
               [encender](int, const QString &, const QString &) { encender(); });
    else
        encender();
}

void Conexiones::conectarBt(const QString &mac)
{
    if (!m_btOcupado.isEmpty())
        return;
    bool emparejado = false;
    QString nombre = mac;
    for (const QVariant &v : std::as_const(m_dispositivos)) {
        const QVariantMap d = v.toMap();
        if (d.value(QStringLiteral("mac")).toString() == mac) {
            emparejado = d.value(QStringLiteral("emparejado")).toBool();
            nombre = d.value(QStringLiteral("nombre")).toString();
        }
    }
    m_btOcupado = mac;
    emit btCambiado();
    avisar(QString());

    auto fin = [this, nombre](bool ok, const QString &texto) {
        m_btOcupado.clear();
        avisar(ok ? nombre + QStringLiteral(" conectado. Queda guardado y se volverá a conectar solo.")
                  : QStringLiteral("No se pudo conectar ") + nombre + QStringLiteral(": ") + texto);
        leerBt();
    };
    auto conectarYa = [this, mac, fin]() {
        correr(QStringLiteral("bluetoothctl"), {QStringLiteral("--timeout"), QStringLiteral("15"), QStringLiteral("connect"), mac},
               [fin](int, const QString &salida, const QString &error) {
            fin(salida.contains(QStringLiteral("Connection successful")),
                error.isEmpty() ? salida.section(QLatin1Char('\n'), -2).trimmed() : error);
        }, 25000);
    };
    if (emparejado)
        return conectarYa();
    // Emparejar (sin PIN: teclados que lo piden mostraran el codigo en su pantalla
    // si la tienen) y confiar, para que se reconecte solo.
    correr(QStringLiteral("bluetoothctl"), {QStringLiteral("--agent"), QStringLiteral("NoInputNoOutput"),
                                            QStringLiteral("--timeout"), QStringLiteral("25"), QStringLiteral("pair"), mac},
           [this, mac, fin, conectarYa](int, const QString &salida, const QString &) {
        if (!salida.contains(QStringLiteral("Pairing successful")) && !salida.contains(QStringLiteral("AlreadyExists")))
            return fin(false, QStringLiteral("no se pudo emparejar (pon el dispositivo en modo de emparejamiento)"));
        correr(QStringLiteral("bluetoothctl"), {QStringLiteral("trust"), mac},
               [conectarYa](int, const QString &, const QString &) { conectarYa(); });
    }, 35000);
}

void Conexiones::desconectarBt(const QString &mac)
{
    correr(QStringLiteral("bluetoothctl"), {QStringLiteral("disconnect"), mac},
           [this](int, const QString &, const QString &) { leerBt(); });
}

void Conexiones::olvidarBt(const QString &mac)
{
    correr(QStringLiteral("bluetoothctl"), {QStringLiteral("remove"), mac},
           [this](int, const QString &salida, const QString &) {
        avisar(salida.contains(QStringLiteral("removed")) ? QStringLiteral("Dispositivo olvidado")
                                                          : QStringLiteral("No se pudo olvidar el dispositivo"));
        leerBt();
    });
}
