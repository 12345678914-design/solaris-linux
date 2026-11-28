#include "Personalizar.h"

#include "ThemeManager.h"
#include "TitanPrefs.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QRegularExpression>
#include <QSettings>
#include <QUrl>

namespace {

QVariantMap tema(const QString &id, const QString &nombre, bool oscuro, const QString &acento,
                 const QString &dock, const QString &barra)
{
    return {{QStringLiteral("id"), id}, {QStringLiteral("nombre"), nombre}, {QStringLiteral("propio"), false},
            {QStringLiteral("oscuro"), oscuro}, {QStringLiteral("acento"), acento}, {QStringLiteral("fondo"), QString()},
            {QStringLiteral("dockPosicion"), dock}, {QStringLiteral("dockTamano"), 36},
            {QStringLiteral("barraEstilo"), barra}};
}

// Los que trae Inti: no cambian el fondo (fondo vacio = el que haya).
QVariantList temasDeInti()
{
    return {
        tema(QStringLiteral("inti-claro"), QStringLiteral("Inti Claro"), false, QStringLiteral("#0071e3"), QStringLiteral("abajo"), QStringLiteral("transparente")),
        tema(QStringLiteral("inti-noche"), QStringLiteral("Inti Noche"), true, QStringLiteral("#5e5ce6"), QStringLiteral("abajo"), QStringLiteral("vidrio")),
        tema(QStringLiteral("atardecer"), QStringLiteral("Atardecer"), false, QStringLiteral("#ff9500"), QStringLiteral("abajo"), QStringLiteral("vidrio")),
        tema(QStringLiteral("bosque"), QStringLiteral("Bosque"), true, QStringLiteral("#34c759"), QStringLiteral("izquierda"), QStringLiteral("transparente")),
        tema(QStringLiteral("grafito"), QStringLiteral("Grafito"), true, QStringLiteral("#8e8e93"), QStringLiteral("abajo"), QStringLiteral("solido")),
        tema(QStringLiteral("rosa"), QStringLiteral("Rosa"), false, QStringLiteral("#ff2d55"), QStringLiteral("abajo"), QStringLiteral("transparente")),
    };
}

} // namespace

Personalizar::Personalizar(TitanPrefs *prefs, QObject *parent)
    : QObject(parent)
    , m_prefs(prefs)
{
    recargar();
    // "actual" depende del tema y de las preferencias.
    connect(ThemeManager::instance(), &ThemeManager::themeChanged, this, &Personalizar::recargar);
    connect(ThemeManager::instance(), &ThemeManager::wallpaperChanged, this, &Personalizar::recargar);
    connect(m_prefs, &TitanPrefs::cambiado, this, &Personalizar::recargar);
}

QString Personalizar::carpeta() const
{
    return QDir::homePath() + QStringLiteral("/.config/titan/temas");
}

QVariantMap Personalizar::actual() const
{
    auto *tm = ThemeManager::instance();
    return {{QStringLiteral("oscuro"), tm->isDark()}, {QStringLiteral("acento"), tm->accent().toLower()},
            {QStringLiteral("fondo"), tm->wallpaper()},
            {QStringLiteral("dockPosicion"), m_prefs->s(QStringLiteral("Dock/posicion"))},
            {QStringLiteral("dockTamano"), m_prefs->i(QStringLiteral("Dock/tamano"))},
            {QStringLiteral("barraEstilo"), m_prefs->s(QStringLiteral("Barra/estilo"))}};
}

void Personalizar::recargar()
{
    QVariantList lista = temasDeInti();
    QDir dir(carpeta());
    const auto ficheros = dir.entryInfoList({QStringLiteral("*.conf")}, QDir::Files, QDir::Time | QDir::Reversed);
    for (const QFileInfo &fi : ficheros) {
        QSettings s(fi.absoluteFilePath(), QSettings::IniFormat);
        s.beginGroup(QStringLiteral("Tema"));
        lista << QVariantMap{
            {QStringLiteral("id"), fi.completeBaseName()},
            {QStringLiteral("nombre"), s.value(QStringLiteral("nombre"), fi.completeBaseName()).toString()},
            {QStringLiteral("propio"), true},
            {QStringLiteral("oscuro"), s.value(QStringLiteral("oscuro")).toBool()},
            {QStringLiteral("acento"), s.value(QStringLiteral("acento"), QStringLiteral("#0071e3")).toString()},
            {QStringLiteral("fondo"), s.value(QStringLiteral("fondo")).toString()},
            {QStringLiteral("dockPosicion"), s.value(QStringLiteral("dockPosicion"), QStringLiteral("abajo")).toString()},
            {QStringLiteral("dockTamano"), s.value(QStringLiteral("dockTamano"), 36).toInt()},
            {QStringLiteral("barraEstilo"), s.value(QStringLiteral("barraEstilo"), QStringLiteral("transparente")).toString()},
        };
    }
    // Marca el que coincide con lo que hay ahora.
    const QVariantMap a = actual();
    for (int i = 0; i < lista.size(); ++i) {
        QVariantMap t = lista[i].toMap();
        bool igual = t.value(QStringLiteral("oscuro")).toBool() == a.value(QStringLiteral("oscuro")).toBool()
                     && t.value(QStringLiteral("acento")).toString().toLower() == a.value(QStringLiteral("acento")).toString()
                     && t.value(QStringLiteral("dockPosicion")).toString() == a.value(QStringLiteral("dockPosicion")).toString()
                     && t.value(QStringLiteral("barraEstilo")).toString() == a.value(QStringLiteral("barraEstilo")).toString();
        if (t.value(QStringLiteral("propio")).toBool())
            igual = igual && t.value(QStringLiteral("fondo")).toString() == a.value(QStringLiteral("fondo")).toString()
                    && t.value(QStringLiteral("dockTamano")).toInt() == a.value(QStringLiteral("dockTamano")).toInt();
        t[QStringLiteral("actual")] = igual;
        // Miniatura del fondo (el actual si el tema no lleva).
        const QString fondo = t.value(QStringLiteral("fondo")).toString();
        t[QStringLiteral("fondoUrl")] = QUrl::fromLocalFile(fondo.isEmpty() ? a.value(QStringLiteral("fondo")).toString() : fondo).toString();
        lista[i] = t;
    }
    m_temas = lista;
    emit temasCambiados();
}

QString Personalizar::guardarTema(const QString &nombre)
{
    const QString n = nombre.trimmed();
    if (n.isEmpty())
        return QStringLiteral("Escribe un nombre para el tema");
    if (n.size() > 40)
        return QStringLiteral("El nombre es demasiado largo");
    // id: el nombre en minusculas, sin acentos ni simbolos.
    QString id = n.normalized(QString::NormalizationForm_D).toLower();
    id.remove(QRegularExpression(QStringLiteral("[^a-z0-9 _-]")));
    id = id.simplified().replace(QLatin1Char(' '), QLatin1Char('-'));
    if (id.isEmpty())
        id = QStringLiteral("tema-") + QString::number(QDateTime::currentSecsSinceEpoch());
    for (const QVariant &v : temasDeInti()) {
        if (v.toMap().value(QStringLiteral("id")).toString() == id)
            id += QStringLiteral("-propio");
    }
    QDir().mkpath(carpeta());
    const QVariantMap a = actual();
    QSettings s(carpeta() + QLatin1Char('/') + id + QStringLiteral(".conf"), QSettings::IniFormat);
    s.beginGroup(QStringLiteral("Tema"));
    s.setValue(QStringLiteral("nombre"), n);
    for (auto it = a.constBegin(); it != a.constEnd(); ++it)
        s.setValue(it.key(), it.value());
    s.endGroup();
    s.sync();
    if (s.status() != QSettings::NoError)
        return QStringLiteral("No se pudo guardar el tema");
    recargar();
    return QString();
}

void Personalizar::aplicarTema(const QString &id)
{
    for (const QVariant &v : std::as_const(m_temas)) {
        const QVariantMap t = v.toMap();
        if (t.value(QStringLiteral("id")).toString() != id)
            continue;
        auto *tm = ThemeManager::instance();
        tm->setIsDark(t.value(QStringLiteral("oscuro")).toBool());
        tm->setAccent(t.value(QStringLiteral("acento")).toString());
        const QString fondo = t.value(QStringLiteral("fondo")).toString();
        if (!fondo.isEmpty() && QFile::exists(fondo))
            tm->setWallpaper(fondo);
        m_prefs->poner(QStringLiteral("Dock/posicion"), t.value(QStringLiteral("dockPosicion")));
        m_prefs->poner(QStringLiteral("Barra/estilo"), t.value(QStringLiteral("barraEstilo")));
        if (t.value(QStringLiteral("propio")).toBool())
            m_prefs->poner(QStringLiteral("Dock/tamano"), t.value(QStringLiteral("dockTamano")));
        recargar();
        return;
    }
}

void Personalizar::borrarTema(const QString &id)
{
    if (id.contains(QLatin1Char('/')) || id.startsWith(QLatin1Char('.')))
        return;
    QFile::remove(carpeta() + QLatin1Char('/') + id + QStringLiteral(".conf"));
    recargar();
}

QVariantList Personalizar::appsNotificadoras() const
{
    QVariantList r;
    QSettings s(QDir::homePath() + QStringLiteral("/.config/titan/notificaciones-apps.conf"), QSettings::IniFormat);
    s.beginGroup(QStringLiteral("apps"));
    for (const QString &clave : s.childGroups()) {
        QString icono = s.value(clave + QStringLiteral("/icono")).toString();
        if (icono.startsWith(QLatin1Char('/')))
            icono = QUrl::fromLocalFile(icono).toString();
        else if (!icono.startsWith(QStringLiteral("file:")) && !icono.startsWith(QStringLiteral("qrc:")))
            icono.clear();
        r << QVariantMap{{QStringLiteral("clave"), clave},
                         {QStringLiteral("nombre"), s.value(clave + QStringLiteral("/nombre"), clave).toString()},
                         {QStringLiteral("icono"), icono}};
    }
    std::sort(r.begin(), r.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("nombre")).toString().compare(b.toMap().value(QStringLiteral("nombre")).toString(), Qt::CaseInsensitive) < 0;
    });
    return r;
}
