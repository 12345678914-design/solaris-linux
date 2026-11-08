#include <QCoreApplication>
#include <QProcess>
#include <QStandardPaths>
#include <iostream>

int main(int argc, char *argv[])
{
    for (int i = 1; i < argc; ++i) {
        if (QString::fromLocal8Bit(argv[i]) == QStringLiteral("--comprobar")) {
            std::cout << "titan-terminal=ok" << std::endl;
            return 0;
        }
    }

    QString kitty = QStandardPaths::findExecutable(QStringLiteral("kitty"));
    if (kitty.isEmpty()) kitty = QStringLiteral("/usr/bin/kitty");

    QStringList args;
    for (int i = 1; i < argc; ++i) {
        args << QString::fromLocal8Bit(argv[i]);
    }

    return QProcess::startDetached(kitty, args) ? 0 : 1;
}
