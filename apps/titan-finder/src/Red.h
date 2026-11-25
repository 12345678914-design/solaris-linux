// Inti OS - Explorador > Red: otros equipos de casa (Windows, Mac, Linux,
// NAS) y sus carpetas compartidas, como "Red" en el Explorador de Windows.
//
// Usa GIO/gvfs (gvfs-smb y wsdd para ver los PCs con Windows). Inti solo
// MIRA la red: no anuncia este equipo a los demás (eso se activa aparte en
// Ajustes > Compartir). Al entrar en una carpeta compartida se monta con
// gvfs y se abre su ruta local (gvfsd-fuse), así todo lo demás funciona igual.
#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>

typedef struct _GMountOperation GMountOperation;

class Red : public QObject
{
    Q_OBJECT
public:
    explicit Red(QObject *parent = nullptr);
    ~Red() override;

    static QString raiz() { return QStringLiteral("network:///"); }
    // network:, smb:, wsdd:, dnssd:, ftp:, sftp: ...
    static bool esRed(const QString &ruta);
    // \\PC\Carpeta (como en Windows) o smb://PC/Carpeta -> URI de GIO; "" si no lo es
    static QString normalizar(const QString &texto);
    // smb://PC/Carpeta: una carpeta compartida (se monta y se abre en local)
    static bool esCarpetaCompartida(const QString &uri);
    // Para la barra de ruta: "PC", "Carpeta"
    static QStringList partes(const QString &uri);

    void listar(const QString &uri);
    void abrir(const QString &uri);
    // Respuesta a credencialesPedidas (aceptar=false cancela)
    void responder(bool aceptar, const QString &usuario, const QString &dominio,
                   const QString &clave, bool anonimo);

signals:
    // entradas: [{name, path, isDir, equipo}]
    void listado(const QString &uri, const QVariantList &entradas, const QString &error);
    void abierto(const QString &uri, const QString &rutaLocal, const QString &error);
    void credencialesPedidas(const QString &mensaje, const QString &usuario,
                             const QString &dominio, bool anonimoPosible);

public:
    // Para las funciones de C de GIO (Red.cpp)
    void montar(const QString &uri, bool despuesListar);
    void pedirCredenciales(GMountOperation *op, const QString &mensaje, const QString &usuario,
                           const QString &dominio, bool anonimo);
    // solo: suelta la operación solo si sigue siendo esa (null = la que haya)
    void soltarOperacion(GMountOperation *solo = nullptr);

private:
    GMountOperation *m_op = nullptr;   // la que espera usuario y contraseña
};
