// titan-terminal: la terminal de Inti OS. Abre kitty (o, si falta, otra
// terminal instalada) traduciendo las opciones al formato de cada una.
//
//   titan-terminal                      terminal en la carpeta actual
//   titan-terminal -d DIR               terminal en DIR (también --directory)
//   titan-terminal -e ORDEN [ARGS...]   ejecuta ORDEN (estilo xterm; -x igual)
//   titan-terminal -e "htop -d 5"       la orden también puede ir en un solo texto
//   titan-terminal --hold -e ORDEN      no cerrar la ventana al terminar ORDEN
//
// kitty no tiene '-e': antes se le pasaba tal cual y las apps de terminal
// (htop, vim...) lanzadas desde el lanzador o el escritorio no se abrían.
#include <QCoreApplication>
#include <QDir>
#include <QProcess>
#include <QStandardPaths>
#include <iostream>

namespace {

struct Peticion {
    QString directorio;
    QStringList orden;
    bool mantener = false;
    bool simular = false;   // --simular: mostrar la orden en vez de abrirla (pruebas)
    QStringList extra;   // opciones propias de kitty que se pasan tal cual
};

void ayuda()
{
    std::cout << "Uso: titan-terminal [-d DIR] [--hold] [-e ORDEN [ARGS...]]\n"
                 "  -d, --directory DIR   abrir en DIR\n"
                 "  -e, -x ORDEN          ejecutar ORDEN en la terminal\n"
                 "      --hold            no cerrar al terminar ORDEN\n"
                 "      --comprobar       comprobar la instalación\n";
}

QStringList argsTerminal(const QString &programa, const Peticion &p)
{
    const QString base = QDir(programa).dirName();
    QStringList a;
    if (base == QStringLiteral("kitty")) {
        if (!p.directorio.isEmpty()) a << QStringLiteral("--directory") << p.directorio;
        if (p.mantener) a << QStringLiteral("--hold");
        a << p.extra;
        a << p.orden;
    } else if (base == QStringLiteral("foot")) {
        if (!p.directorio.isEmpty()) a << (QStringLiteral("--working-directory=") + p.directorio);
        if (p.mantener) a << QStringLiteral("--hold");
        a << p.orden;
    } else if (base == QStringLiteral("alacritty")) {
        if (!p.directorio.isEmpty()) a << QStringLiteral("--working-directory") << p.directorio;
        if (p.mantener) a << QStringLiteral("--hold");
        if (!p.orden.isEmpty()) a << QStringLiteral("-e") << p.orden;
    } else if (base == QStringLiteral("konsole")) {
        if (!p.directorio.isEmpty()) a << QStringLiteral("--workdir") << p.directorio;
        if (p.mantener) a << QStringLiteral("--hold");
        if (!p.orden.isEmpty()) a << QStringLiteral("-e") << p.orden;
    } else {   // xterm y compatibles
        if (p.mantener) a << QStringLiteral("-hold");
        if (!p.orden.isEmpty()) a << QStringLiteral("-e") << p.orden;
    }
    return a;
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    const QStringList args = app.arguments().mid(1);

    Peticion p;
    for (int i = 0; i < args.size(); ++i) {
        const QString &a = args.at(i);
        if (a == QStringLiteral("--comprobar")) {
            std::cout << "titan-terminal=ok" << std::endl;
            return 0;
        } else if (a == QStringLiteral("-h") || a == QStringLiteral("--help")) {
            ayuda();
            return 0;
        } else if ((a == QStringLiteral("-d") || a == QStringLiteral("--directory") ||
                    a == QStringLiteral("--working-directory")) && i + 1 < args.size()) {
            p.directorio = args.at(++i);
        } else if (a.startsWith(QStringLiteral("--directory=")) || a.startsWith(QStringLiteral("--working-directory="))) {
            p.directorio = a.section(QLatin1Char('='), 1);
        } else if (a == QStringLiteral("--simular")) {
            p.simular = true;
        } else if (a == QStringLiteral("--hold")) {
            p.mantener = true;
        } else if (a == QStringLiteral("-e") || a == QStringLiteral("-x") || a == QStringLiteral("--")) {
            p.orden = args.mid(i + 1);
            break;
        } else if (a.startsWith(QLatin1Char('-'))) {
            p.extra << a;   // opción de kitty: se respeta
        } else {
            p.orden = args.mid(i);   // "titan-terminal htop": como kitty
            break;
        }
    }
    // "-e 'htop -d 5'": la orden entera llegó en un solo argumento
    if (p.orden.size() == 1 && p.orden.first().contains(QLatin1Char(' ')))
        p.orden = QProcess::splitCommand(p.orden.first());

    if (!p.directorio.isEmpty() && !QDir(p.directorio).exists()) {
        std::cerr << "titan-terminal: no existe la carpeta " << p.directorio.toStdString() << std::endl;
        return 1;
    }

    for (const char *nombre : {"kitty", "foot", "alacritty", "konsole", "xterm"}) {
        const QString prog = QStandardPaths::findExecutable(QString::fromLatin1(nombre));
        if (prog.isEmpty())
            continue;
        const QString dir = p.directorio.isEmpty() ? QDir::currentPath() : p.directorio;
        if (p.simular) {
            std::cout << prog.toStdString();
            for (const QString &x : argsTerminal(prog, p)) std::cout << " [" << x.toStdString() << "]";
            std::cout << "  (en " << dir.toStdString() << ")" << std::endl;
            return 0;
        }
        return QProcess::startDetached(prog, argsTerminal(prog, p), dir) ? 0 : 1;
    }
    std::cerr << "titan-terminal: no hay ninguna terminal instalada (kitty, foot, alacritty, konsole, xterm)" << std::endl;
    return 1;
}
