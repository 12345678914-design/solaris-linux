// Inti OS - Instalador: particionado manual sobre la tabla REAL del disco.
//
//  - Se lee lo que hay (parted + lsblk): particiones, su formato, etiqueta y
//    para qué parecen servir (EFI, Windows, Linux...), y los huecos libres.
//  - Editar una partición existente es SOLO información: punto de montaje,
//    formatear o no y con qué. No toca el disco; se usa al instalar.
//  - Borrar, crear en un hueco o empezar una tabla nueva quedan pendientes;
//    «Aplicar cambios» (tras confirmar en la interfaz) los escribe con parted.
#include "InstallerBackend.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <QThread>
#include <algorithm>
#include <cmath>

namespace {

QString nodo(const QString &disco, int numero)
{
    const bool conP = disco.contains(QRegularExpression(QStringLiteral("[0-9]$")));
    return disco + (conP ? QStringLiteral("p") : QString()) + QString::number(numero);
}

QString gb(double mib)
{
    const double g = mib * 1.048576 / 1000.0;
    if (g >= 1)
        return QStringLiteral("%1 GB").arg(g, 0, 'f', g >= 100 ? 0 : 1);
    return QStringLiteral("%1 MB").arg(qRound(mib * 1.048576));
}

QString ejecutar(const QString &prog, const QStringList &args, bool *ok = nullptr, int ms = 30000)
{
    QProcess p;
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
    p.setProcessEnvironment(env);
    p.start(prog, args);
    const bool fin = p.waitForFinished(ms);
    if (ok)
        *ok = fin && p.exitStatus() == QProcess::NormalExit && p.exitCode() == 0;
    const QString err = QString::fromUtf8(p.readAllStandardError()).trimmed();
    return fin && p.exitCode() == 0 ? QString::fromUtf8(p.readAllStandardOutput()) : err;
}

QString nombreFs(const QString &fs)
{
    if (fs == QLatin1String("vfat") || fs == QLatin1String("fat32") || fs == QLatin1String("fat16"))
        return QStringLiteral("FAT32");
    if (fs == QLatin1String("ntfs"))
        return QStringLiteral("NTFS");
    if (fs == QLatin1String("swap") || fs.startsWith(QLatin1String("linux-swap")))
        return QStringLiteral("swap");
    if (fs == QLatin1String("crypto_LUKS"))
        return QStringLiteral("cifrada (LUKS)");
    return fs.isEmpty() ? QStringLiteral("sin formato") : fs;
}

bool esLinuxFs(const QString &fs)
{
    return fs == QLatin1String("ext4") || fs == QLatin1String("ext3") || fs == QLatin1String("btrfs") || fs == QLatin1String("xfs");
}

} // namespace

// ---------------------------------------------------------------- leer

void InstallerBackend::leerTablaManual()
{
    m_partes.clear();
    m_borrar.clear();
    m_nuevas.clear();
    m_tablaNueva = false;
    m_tipoTabla = QStringLiteral("unknown");
    m_discoMb = 0;
    const QString disco = selectedDiskPath();
    if (disco.isEmpty()) {
        rehacerTablaManual();
        return;
    }

    // Formato, etiqueta y si está montada (lsblk)
    QHash<QString, QJsonObject> info;
    const QJsonArray dispositivos = QJsonDocument::fromJson(ejecutar(QStringLiteral("lsblk"),
        {QStringLiteral("-Jpb"), QStringLiteral("-o"), QStringLiteral("NAME,FSTYPE,LABEL,PARTLABEL,MOUNTPOINT,SIZE"), disco}).toUtf8())
        .object().value(QStringLiteral("blockdevices")).toArray();
    for (const QJsonValue &d : dispositivos)
        for (const QJsonValue &h : d.toObject().value(QStringLiteral("children")).toArray())
            info.insert(h.toObject().value(QStringLiteral("name")).toString(), h.toObject());

    // Tabla (parted, en MiB y en inglés para poder leerla)
    const QString salida = ejecutar(QStringLiteral("parted"), {QStringLiteral("-m"), QStringLiteral("-s"), disco, QStringLiteral("unit"),
                                                              QStringLiteral("MiB"), QStringLiteral("print")});
    auto mib = [](QString v) { return v.remove(QStringLiteral("MiB")).toDouble(); };
    for (QString l : salida.split(QLatin1Char('\n'))) {
        l = l.trimmed();
        if (l.endsWith(QLatin1Char(';')))
            l.chop(1);
        const QStringList c = l.split(QLatin1Char(':'));
        if (c.size() >= 6 && c.at(0).startsWith(QLatin1Char('/'))) {
            m_discoMb = mib(c.at(1));
            m_tipoTabla = c.at(5);
            continue;
        }
        bool esNumero = false;
        const int n = c.value(0).toInt(&esNumero);
        if (!esNumero || c.size() < 5)
            continue;
        const QString nd = nodo(disco, n);
        const QJsonObject i = info.value(nd);
        QVariantMap p;
        p[QStringLiteral("numero")] = n;
        p[QStringLiteral("nodo")] = nd;
        p[QStringLiteral("inicio")] = mib(c.at(1));
        p[QStringLiteral("fin")] = mib(c.at(2));
        p[QStringLiteral("tamano")] = mib(c.at(3));
        QString fs = i.value(QStringLiteral("fstype")).toString();
        if (fs.isEmpty())
            fs = c.at(4) == QLatin1String("fat32") ? QStringLiteral("vfat") : c.at(4).startsWith(QLatin1String("linux-swap")) ? QStringLiteral("swap") : c.at(4);
        p[QStringLiteral("fsActual")] = fs;
        p[QStringLiteral("etiqueta")] = i.value(QStringLiteral("label")).toString();
        const QString nombre = c.value(5);
        const QString flags = c.value(6);
        p[QStringLiteral("flags")] = flags;
        p[QStringLiteral("montada")] = i.value(QStringLiteral("mountpoint")).toString();
        // Para qué parece servir
        QString uso;
        const QString todo = (nombre + QLatin1Char(' ') + i.value(QStringLiteral("label")).toString() + QLatin1Char(' ')
                              + i.value(QStringLiteral("partlabel")).toString()).toLower();
        if (flags.contains(QLatin1String("esp")))
            uso = QStringLiteral("Partición EFI (arranque)");
        else if (flags.contains(QLatin1String("msftres")))
            uso = QStringLiteral("Reservada de Microsoft");
        else if (flags.contains(QLatin1String("bios_grub")))
            uso = QStringLiteral("Arranque BIOS (bios_grub)");
        else if (fs == QLatin1String("ntfs"))
            uso = todo.contains(QLatin1String("recover")) || todo.contains(QLatin1String("recupera")) || flags.contains(QLatin1String("diag"))
                      ? QStringLiteral("Recuperación de Windows") : QStringLiteral("Windows");
        else if (fs == QLatin1String("swap"))
            uso = QStringLiteral("Intercambio");
        else if (esLinuxFs(fs))
            uso = QStringLiteral("Linux");
        else if (fs == QLatin1String("crypto_LUKS"))
            uso = QStringLiteral("Cifrada");
        else if (fs == QLatin1String("vfat"))
            uso = QStringLiteral("Datos");
        p[QStringLiteral("uso")] = uso;
        m_partes << p;
    }

    // Las asignaciones de particiones que ya no existen se olvidan
    QSet<QString> nodos;
    for (const QVariantMap &p : std::as_const(m_partes))
        nodos.insert(p.value(QStringLiteral("nodo")).toString());
    for (auto it = m_asign.begin(); it != m_asign.end();)
        it = nodos.contains(it.key()) ? std::next(it) : m_asign.erase(it);

    rehacerTablaManual();
}

// Filas para la interfaz: particiones (marcadas si se borran), nuevas y huecos.
void InstallerBackend::rehacerTablaManual()
{
    struct Tramo { double ini, fin; QVariantMap fila; };
    QList<Tramo> tramos;
    QList<QPair<double, double>> ocupado;

    if (!m_tablaNueva) {
        for (const QVariantMap &p : std::as_const(m_partes)) {
            QVariantMap f = p;
            const QString nd = p.value(QStringLiteral("nodo")).toString();
            const QVariantMap a = m_asign.value(nd);
            const bool borrar = m_borrar.contains(p.value(QStringLiteral("numero")).toInt());
            f[QStringLiteral("tipo")] = QStringLiteral("parte");
            f[QStringLiteral("borrar")] = borrar;
            f[QStringLiteral("montaje")] = borrar ? QString() : a.value(QStringLiteral("montaje")).toString();
            f[QStringLiteral("formatear")] = a.value(QStringLiteral("formatear")).toBool();
            f[QStringLiteral("fs")] = a.value(QStringLiteral("fs"), QStringLiteral("ext4")).toString();
            f[QStringLiteral("fsTexto")] = nombreFs(p.value(QStringLiteral("fsActual")).toString());
            f[QStringLiteral("tamanoTexto")] = gb(p.value(QStringLiteral("tamano")).toDouble());
            const double ini = p.value(QStringLiteral("inicio")).toDouble(), fin = p.value(QStringLiteral("fin")).toDouble();
            tramos << Tramo{ini, fin, f};
            if (!borrar)
                ocupado << qMakePair(ini, fin);
        }
    }
    for (int i = 0; i < m_nuevas.size(); ++i) {
        const QVariantMap &n = m_nuevas.at(i);
        QVariantMap f;
        f[QStringLiteral("tipo")] = QStringLiteral("nueva");
        f[QStringLiteral("indiceNueva")] = i;
        const double ini = n.value(QStringLiteral("inicio")).toDouble(), fin = n.value(QStringLiteral("fin")).toDouble();
        f[QStringLiteral("inicio")] = ini;
        f[QStringLiteral("fin")] = fin;
        f[QStringLiteral("tamano")] = fin - ini;
        f[QStringLiteral("tamanoTexto")] = gb(fin - ini);
        f[QStringLiteral("montaje")] = n.value(QStringLiteral("montaje"));
        f[QStringLiteral("fs")] = n.value(QStringLiteral("fs"));
        f[QStringLiteral("formatear")] = true;
        f[QStringLiteral("nodo")] = QStringLiteral("Nueva");
        f[QStringLiteral("fsTexto")] = nombreFs(n.value(QStringLiteral("fs")).toString());
        tramos << Tramo{ini, fin, f};
        ocupado << qMakePair(ini, fin);
    }

    // Huecos: lo que no ocupa nada (alineado a 1 MiB; GPT reserva el final)
    std::sort(ocupado.begin(), ocupado.end());
    const double finUtil = m_discoMb > 0 ? std::floor(m_discoMb) - 1 : 0;
    double cursor = 1;
    auto hueco = [&](double a, double b) {
        a = std::ceil(a);
        b = std::floor(b);
        if (b - a < 2)
            return;
        QVariantMap f;
        f[QStringLiteral("tipo")] = QStringLiteral("libre");
        f[QStringLiteral("inicio")] = a;
        f[QStringLiteral("fin")] = b;
        f[QStringLiteral("tamano")] = b - a;
        f[QStringLiteral("tamanoTexto")] = gb(b - a);
        f[QStringLiteral("nodo")] = QStringLiteral("Libre");
        tramos << Tramo{a, b, f};
    };
    for (const auto &o : std::as_const(ocupado)) {
        if (o.first > cursor)
            hueco(cursor, o.first);
        cursor = qMax(cursor, o.second);
    }
    if (finUtil > cursor)
        hueco(cursor, finUtil);

    std::sort(tramos.begin(), tramos.end(), [](const Tramo &a, const Tramo &b) {
        return a.ini < b.ini || (a.ini == b.ini && a.fila.value(QStringLiteral("tipo")).toString() < b.fila.value(QStringLiteral("tipo")).toString());
    });
    m_tabla.clear();
    for (Tramo &t : tramos) {
        t.fila[QStringLiteral("proporcion")] = m_discoMb > 0 ? (t.fin - t.ini) / m_discoMb : 0.0;
        m_tabla << t.fila;
    }
    emit tablaManualChanged();
}

// ---------------------------------------------------------------- editar

void InstallerBackend::editarParticion(int fila, const QString &montaje0, bool formatear, const QString &fs0)
{
    if (fila < 0 || fila >= m_tabla.size())
        return;
    const QVariantMap f = m_tabla.at(fila).toMap();
    const QString tipo = f.value(QStringLiteral("tipo")).toString();
    const QString montaje = montaje0 == QLatin1String("(no usar)") ? QString() : montaje0;
    QString fs = fs0.isEmpty() ? QStringLiteral("ext4") : fs0;

    // Un punto de montaje solo en una partición: se quita de las demás
    const int estaNueva = tipo == QLatin1String("nueva") ? f.value(QStringLiteral("indiceNueva")).toInt() : -1;
    auto liberar = [&](const QString &m, const QString &excepto) {
        if (m.isEmpty())
            return;
        for (auto it = m_asign.begin(); it != m_asign.end(); ++it)
            if (it.key() != excepto && it.value().value(QStringLiteral("montaje")).toString() == m)
                it.value()[QStringLiteral("montaje")] = QString();
        for (int k = 0; k < m_nuevas.size(); ++k)
            if (k != estaNueva && m_nuevas.at(k).value(QStringLiteral("montaje")).toString() == m)
                m_nuevas[k][QStringLiteral("montaje")] = QString();
    };

    if (tipo == QLatin1String("nueva")) {
        const int i = estaNueva;
        if (montaje == QLatin1String("/boot/efi")) fs = QStringLiteral("fat32");
        else if (montaje == QLatin1String("swap")) fs = QStringLiteral("swap");
        else if (fs == QLatin1String("fat32") || fs == QLatin1String("swap")) fs = QStringLiteral("ext4");
        liberar(montaje, QString());
        m_nuevas[i][QStringLiteral("montaje")] = montaje;
        m_nuevas[i][QStringLiteral("fs")] = fs;
        rehacerTablaManual();
        return;
    }
    if (tipo != QLatin1String("parte") || f.value(QStringLiteral("borrar")).toBool() || !f.value(QStringLiteral("montada")).toString().isEmpty())
        return;

    const QString nd = f.value(QStringLiteral("nodo")).toString();
    const QString actual = f.value(QStringLiteral("fsActual")).toString();
    // Reglas para que lo que se elige funcione
    if (montaje == QLatin1String("/")) {
        formatear = true; // la raíz siempre se formatea
        if (fs != QLatin1String("ext4") && fs != QLatin1String("btrfs") && fs != QLatin1String("xfs"))
            fs = QStringLiteral("ext4");
    } else if (montaje == QLatin1String("/boot/efi")) {
        if (actual != QLatin1String("vfat"))
            formatear = true;
        fs = QStringLiteral("fat32");
    } else if (montaje == QLatin1String("swap")) {
        if (actual != QLatin1String("swap"))
            formatear = true;
        fs = QStringLiteral("swap");
    } else if (!montaje.isEmpty()) {
        if (!esLinuxFs(actual))
            formatear = true;
        if (fs == QLatin1String("fat32") || fs == QLatin1String("swap"))
            fs = QStringLiteral("ext4");
    } else {
        formatear = false;
    }
    liberar(montaje, nd);
    QVariantMap a;
    a[QStringLiteral("montaje")] = montaje;
    a[QStringLiteral("formatear")] = formatear;
    a[QStringLiteral("fs")] = fs;
    m_asign[nd] = a;
    rehacerTablaManual();
}

void InstallerBackend::marcarBorrar(int fila, bool borrar)
{
    if (fila < 0 || fila >= m_tabla.size())
        return;
    const QVariantMap f = m_tabla.at(fila).toMap();
    if (f.value(QStringLiteral("tipo")).toString() != QLatin1String("parte") || !f.value(QStringLiteral("montada")).toString().isEmpty())
        return;
    const int n = f.value(QStringLiteral("numero")).toInt();
    if (borrar) {
        m_borrar.insert(n);
        m_asign.remove(f.value(QStringLiteral("nodo")).toString());
    } else {
        // Si una partición nueva ya ocupa su sitio, no se puede deshacer.
        const double ini = f.value(QStringLiteral("inicio")).toDouble(), fin = f.value(QStringLiteral("fin")).toDouble();
        for (const QVariantMap &nv : std::as_const(m_nuevas))
            if (nv.value(QStringLiteral("inicio")).toDouble() < fin && nv.value(QStringLiteral("fin")).toDouble() > ini)
                return;
        m_borrar.remove(n);
    }
    rehacerTablaManual();
}

void InstallerBackend::crearEnHueco(int fila, int tamanoMb, const QString &montaje0, const QString &fs0)
{
    if (fila < 0 || fila >= m_tabla.size())
        return;
    const QVariantMap f = m_tabla.at(fila).toMap();
    if (f.value(QStringLiteral("tipo")).toString() != QLatin1String("libre"))
        return;
    const double ini = f.value(QStringLiteral("inicio")).toDouble();
    const double finHueco = f.value(QStringLiteral("fin")).toDouble();
    const double fin = tamanoMb > 0 ? qMin(finHueco, ini + tamanoMb) : finHueco;
    QVariantMap n;
    n[QStringLiteral("inicio")] = ini;
    n[QStringLiteral("fin")] = fin;
    n[QStringLiteral("montaje")] = QString();
    n[QStringLiteral("fs")] = QStringLiteral("ext4");
    m_nuevas << n;
    rehacerTablaManual();
    // montaje y formato con las mismas reglas que al editar
    for (int i = 0; i < m_tabla.size(); ++i) {
        const QVariantMap r = m_tabla.at(i).toMap();
        if (r.value(QStringLiteral("tipo")).toString() == QLatin1String("nueva") && r.value(QStringLiteral("indiceNueva")).toInt() == m_nuevas.size() - 1) {
            editarParticion(i, montaje0, true, fs0);
            break;
        }
    }
}

void InstallerBackend::quitarNueva(int fila)
{
    if (fila < 0 || fila >= m_tabla.size())
        return;
    const QVariantMap f = m_tabla.at(fila).toMap();
    if (f.value(QStringLiteral("tipo")).toString() != QLatin1String("nueva"))
        return;
    m_nuevas.removeAt(f.value(QStringLiteral("indiceNueva")).toInt());
    rehacerTablaManual();
}

void InstallerBackend::tablaNueva()
{
    for (const QVariantMap &p : std::as_const(m_partes))
        if (!p.value(QStringLiteral("montada")).toString().isEmpty())
            return; // hay algo en uso: no se puede borrar todo
    m_tablaNueva = true;
    m_borrar.clear();
    m_nuevas.clear();
    m_asign.clear();
    rehacerTablaManual();
}

void InstallerBackend::descartarCambios()
{
    m_tablaNueva = false;
    m_borrar.clear();
    m_nuevas.clear();
    rehacerTablaManual();
}

QStringList InstallerBackend::cambiosPendientes() const
{
    QStringList c;
    const QString disco = selectedDiskPath();
    if (m_tablaNueva)
        c << QStringLiteral("Crear una tabla de particiones %1 nueva en %2 (se pierde TODO lo que hay en el disco)")
                 .arg(m_isUefi ? QStringLiteral("GPT") : QStringLiteral("MBR"), disco);
    for (const QVariantMap &p : m_partes)
        if (!m_tablaNueva && m_borrar.contains(p.value(QStringLiteral("numero")).toInt())) {
            QString que = p.value(QStringLiteral("uso")).toString();
            if (!p.value(QStringLiteral("etiqueta")).toString().isEmpty())
                que += (que.isEmpty() ? QString() : QStringLiteral(", ")) + QStringLiteral("«%1»").arg(p.value(QStringLiteral("etiqueta")).toString());
            c << QStringLiteral("Borrar %1 (%2%3) y todo su contenido")
                     .arg(p.value(QStringLiteral("nodo")).toString(), gb(p.value(QStringLiteral("tamano")).toDouble()),
                          que.isEmpty() ? QString() : QStringLiteral(", ") + que);
        }
    for (const QVariantMap &n : m_nuevas) {
        const QString m = n.value(QStringLiteral("montaje")).toString();
        c << QStringLiteral("Crear una partición de %1 (%2)%3")
                 .arg(gb(n.value(QStringLiteral("fin")).toDouble() - n.value(QStringLiteral("inicio")).toDouble()),
                      nombreFs(n.value(QStringLiteral("fs")).toString()), m.isEmpty() ? QString() : QStringLiteral(" para ") + m);
    }
    return c;
}

// Lo que hará la instalación con cada partición asignada (para el resumen).
QStringList InstallerBackend::resumenManual() const
{
    QStringList r;
    for (const QVariant &v : m_tabla) {
        const QVariantMap f = v.toMap();
        const QString m = f.value(QStringLiteral("montaje")).toString();
        if (m.isEmpty())
            continue;
        const bool fmt = f.value(QStringLiteral("formatear")).toBool();
        r << QStringLiteral("%1 → %2 (%3): %4").arg(m, f.value(QStringLiteral("nodo")).toString(), f.value(QStringLiteral("tamanoTexto")).toString(),
                                                   fmt ? QStringLiteral("se formatea en ") + nombreFs(f.value(QStringLiteral("fs")).toString())
                                                       : QStringLiteral("se usa tal cual (") + f.value(QStringLiteral("fsTexto")).toString() + QLatin1Char(')'));
    }
    return r;
}

QVariantList InstallerBackend::asignacionesManual() const
{
    QVariantList l;
    for (const QVariant &v : m_tabla) {
        const QVariantMap f = v.toMap();
        if (f.value(QStringLiteral("tipo")).toString() != QLatin1String("parte") || f.value(QStringLiteral("montaje")).toString().isEmpty())
            continue;
        QVariantMap a;
        a[QStringLiteral("nodo")] = f.value(QStringLiteral("nodo"));
        a[QStringLiteral("montaje")] = f.value(QStringLiteral("montaje"));
        a[QStringLiteral("formatear")] = f.value(QStringLiteral("formatear"));
        a[QStringLiteral("fs")] = f.value(QStringLiteral("fs"));
        l << a;
    }
    return l;
}

// ---------------------------------------------------------------- aplicar

QString InstallerBackend::aplicarCambios()
{
    const QString disco = selectedDiskPath();
    if (disco.isEmpty())
        return QStringLiteral("No hay ningún disco elegido.");
    if (cambiosPendientes().isEmpty())
        return QString();
    bool ok = false;
    QString salida;
    auto fallo = [&](const QString &que) {
        const QString detalle = salida.trimmed().section(QLatin1Char('\n'), -1);
        leerTablaManual();
        return detalle.isEmpty() ? que : que + QStringLiteral(": ") + detalle;
    };

    if (m_tablaNueva) {
        salida = ejecutar(QStringLiteral("parted"), {QStringLiteral("-s"), disco, QStringLiteral("mklabel"),
                                                     m_isUefi ? QStringLiteral("gpt") : QStringLiteral("msdos")}, &ok);
        if (!ok)
            return fallo(QStringLiteral("No se pudo crear la tabla de particiones"));
    } else {
        QList<int> borrar(m_borrar.begin(), m_borrar.end());
        std::sort(borrar.begin(), borrar.end(), std::greater<int>());
        for (int n : std::as_const(borrar)) {
            salida = ejecutar(QStringLiteral("parted"), {QStringLiteral("-s"), disco, QStringLiteral("rm"), QString::number(n)}, &ok);
            if (!ok)
                return fallo(QStringLiteral("No se pudo borrar %1").arg(nodo(disco, n)));
        }
    }

    const bool gpt = m_tablaNueva ? m_isUefi : m_tipoTabla == QLatin1String("gpt");
    QList<QVariantMap> nuevas = m_nuevas;
    std::sort(nuevas.begin(), nuevas.end(), [](const QVariantMap &a, const QVariantMap &b) {
        return a.value(QStringLiteral("inicio")).toDouble() < b.value(QStringLiteral("inicio")).toDouble();
    });
    struct Hecha { double inicio; QVariantMap plan; };
    QList<Hecha> hechas;
    for (const QVariantMap &n : std::as_const(nuevas)) {
        const QString m = n.value(QStringLiteral("montaje")).toString();
        const QString fs = n.value(QStringLiteral("fs")).toString();
        const QString fsParted = fs == QLatin1String("fat32") ? QStringLiteral("fat32") : fs == QLatin1String("swap") ? QStringLiteral("linux-swap")
                                 : fs == QLatin1String("btrfs") ? QStringLiteral("btrfs") : QStringLiteral("ext4");
        const QString nombre = !gpt ? QStringLiteral("primary")
                               : m == QLatin1String("/boot/efi") ? QStringLiteral("EFI")
                               : m == QLatin1String("/") ? QStringLiteral("IntiRoot")
                               : m == QLatin1String("/home") ? QStringLiteral("IntiHome")
                               : m == QLatin1String("swap") ? QStringLiteral("IntiSwap") : QStringLiteral("Inti");
        const double ini = n.value(QStringLiteral("inicio")).toDouble(), fin = n.value(QStringLiteral("fin")).toDouble();
        salida = ejecutar(QStringLiteral("parted"), {QStringLiteral("-s"), QStringLiteral("-a"), QStringLiteral("optimal"), disco, QStringLiteral("mkpart"), nombre, fsParted,
                                                     QString::number(qint64(ini)) + QStringLiteral("MiB"), QString::number(qint64(fin)) + QStringLiteral("MiB")}, &ok);
        if (!ok)
            return fallo(QStringLiteral("No se pudo crear la partición de %1").arg(gb(fin - ini)));
        hechas << Hecha{ini, n};
    }

    ejecutar(QStringLiteral("partprobe"), {disco});
    ejecutar(QStringLiteral("udevadm"), {QStringLiteral("settle")});
    QThread::msleep(400);

    // Volver a leer y pasar lo planeado a las particiones nuevas (por su inicio)
    leerTablaManual();
    for (const Hecha &h : std::as_const(hechas)) {
        for (const QVariantMap &p : std::as_const(m_partes)) {
            if (std::abs(p.value(QStringLiteral("inicio")).toDouble() - h.inicio) > 2.5)
                continue;
            const int num = p.value(QStringLiteral("numero")).toInt();
            const QString m = h.plan.value(QStringLiteral("montaje")).toString();
            if (m == QLatin1String("/boot/efi") && gpt)
                ejecutar(QStringLiteral("parted"), {QStringLiteral("-s"), disco, QStringLiteral("set"), QString::number(num), QStringLiteral("esp"), QStringLiteral("on")});
            if (m == QLatin1String("/") && !gpt)
                ejecutar(QStringLiteral("parted"), {QStringLiteral("-s"), disco, QStringLiteral("set"), QString::number(num), QStringLiteral("boot"), QStringLiteral("on")});
            QVariantMap a;
            a[QStringLiteral("montaje")] = m;
            a[QStringLiteral("formatear")] = true;
            a[QStringLiteral("fs")] = h.plan.value(QStringLiteral("fs"));
            m_asign[p.value(QStringLiteral("nodo")).toString()] = a;
            break;
        }
    }
    leerTablaManual(); // con las marcas (esp/boot) ya puestas
    refreshDisks();
    return QString();
}
