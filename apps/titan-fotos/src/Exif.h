// Inti OS - Fotos: lector EXIF mínimo (sin dependencias). Lee lo que se
// enseña en el panel de información: fecha de captura, cámara, exposición,
// apertura, ISO, distancia focal, flash y coordenadas GPS. Vale para JPEG
// (APP1), PNG (chunk eXIf) y WebP (chunk EXIF).
#pragma once

#include <QDateTime>
#include <QString>
#include <QVariantMap>

namespace Exif {
// Claves: fecha (QDateTime), camara, objetivo, exposicion, apertura, iso,
// focal, flash, lat, lon (double). Vacío si no hay EXIF.
QVariantMap leer(const QString &ruta);
// Segmento APP1 (EXIF) de un JPEG, listo para insertarlo en otro JPEG, con la
// orientación puesta a 1 (la foto guardada ya va girada). Vacío si no hay.
QByteArray segmentoParaCopia(const QString &ruta);
}
