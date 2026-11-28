// Inti OS - Música: lectura de la biblioteca (etiquetas con TagLib, carátulas,
// letras y caché para no releer lo que no ha cambiado).
#pragma once

#include <QHash>
#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QVector>

#include <atomic>

struct Pista
{
    QString ruta;
    QString titulo;
    QString artista;
    QString artistaAlbum;
    QString album;
    QString genero;
    QString formato;
    QString portada;      // ruta local de la imagen, o vacía
    int anio = 0;
    int numero = 0;
    int disco = 0;
    int kbps = 0;
    int hz = 0;
    qint64 duracion = 0;  // ms
    qint64 mtime = 0;     // s
    qint64 tam = 0;

    QString artistaDeAlbum() const { return artistaAlbum.isEmpty() ? artista : artistaAlbum; }
    QString claveAlbum() const { return artistaDeAlbum() + QChar(0x1f) + album; }
    QVariantMap aMapa() const;
    QJsonObject aJson() const;
    static Pista deJson(const QJsonObject &o);
};

namespace Biblioteca {

QStringList filtros();
bool esAudio(const QString &ruta);
// Lee etiquetas, duración y carátula (embebida o cover.jpg de la carpeta).
Pista leer(const QString &ruta);
// Recorre las carpetas (y los archivos sueltos) reutilizando la caché.
QVector<Pista> escanear(const QStringList &carpetas, const QStringList &sueltos, const std::atomic_bool *cancelar);
QString carpetaCache();
// Escribe título, artista, álbum, artistaAlbum, genero, anio, numero.
bool guardarEtiquetas(const QString &ruta, const QVariantMap &campos, QString *error);
// [{ms, texto}] desde un .lrc al lado del archivo o la etiqueta LYRICS.
// ms = -1 si la letra no lleva tiempos.
QVariantList letra(const QString &ruta);
QString tiempo(qint64 ms);
QString duracionLarga(qint64 ms);

} // namespace Biblioteca
