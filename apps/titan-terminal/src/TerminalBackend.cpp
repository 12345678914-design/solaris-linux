#include "TerminalBackend.h"
#include <QDebug>
#include <QByteArray>
#include <QProcessEnvironment>

#include <cerrno>
#include <csignal>
#include <cstdlib>
#include <cstring>

#include <fcntl.h>
#include <pty.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

TerminalBackend::TerminalBackend(QObject *parent)
    : QObject(parent)
{
    int slaveFd = -1;

    if (openpty(&m_masterFd, &slaveFd, nullptr, nullptr, nullptr) == -1) {
        emit terminalError(QStringLiteral("No se pudo crear el PTY: %1")
                               .arg(QString::fromLocal8Bit(strerror(errno))));
        return;
    }

    m_childPid = fork();

    if (m_childPid == -1) {
        emit terminalError(QStringLiteral("No se pudo iniciar el shell: %1")
                               .arg(QString::fromLocal8Bit(strerror(errno))));
        close(m_masterFd);
        close(slaveFd);
        m_masterFd = -1;
        return;
    }

    if (m_childPid == 0) {
        close(m_masterFd);

        if (setsid() == -1)
            _exit(126);

        if (ioctl(slaveFd, TIOCSCTTY, 0) == -1)
            _exit(126);

        dup2(slaveFd, STDIN_FILENO);
        dup2(slaveFd, STDOUT_FILENO);
        dup2(slaveFd, STDERR_FILENO);

        if (slaveFd > STDERR_FILENO)
            close(slaveFd);

        const char *shell = getenv("SHELL");
        if (!shell || !*shell)
            shell = "/bin/bash";

        execl(shell, shell, "-i", static_cast<char *>(nullptr));
        execl("/bin/sh", "sh", "-i", static_cast<char *>(nullptr));
        _exit(127);
    }

    close(slaveFd);

    const int flags = fcntl(m_masterFd, F_GETFL, 0);
    if (flags != -1)
        fcntl(m_masterFd, F_SETFL, flags | O_NONBLOCK);

    m_notifier = new QSocketNotifier(
        m_masterFd, QSocketNotifier::Read, this);

    connect(m_notifier, &QSocketNotifier::activated,
            this, [this](auto...) {
                readAvailable();
            });

    // Evita que el shell espere una entrada inicial indefinidamente.
    readAvailable();
}

TerminalBackend::~TerminalBackend()
{
    if (m_notifier)
        m_notifier->setEnabled(false);

    if (m_masterFd >= 0)
        close(m_masterFd);

    if (m_childPid > 0) {
        kill(m_childPid, SIGHUP);
        waitpid(m_childPid, nullptr, WNOHANG);
    }
}

QString TerminalBackend::output() const
{
    return m_output;
}

void TerminalBackend::appendOutput(const QString &text)
{
    if (text.isEmpty())
        return;

    m_output += text;

    // Evita que una sesión prolongada consuma memoria sin límite.
    constexpr qsizetype maxCharacters = 200000;
    if (m_output.size() > maxCharacters)
        m_output.remove(0, m_output.size() - maxCharacters);

    emit outputChanged();
}

void TerminalBackend::readAvailable()
{
    if (m_masterFd < 0)
        return;

    char buffer[8192];

    while (true) {
        const ssize_t count = read(m_masterFd, buffer, sizeof(buffer));

        if (count > 0) {
    qDebug() << "[TITAN PTY] Bytes recibidos:" << count;
    qDebug().noquote()
        << "[TITAN PTY] Salida:"
        << QString::fromLocal8Bit(buffer, count);

    appendOutput(QString::fromLocal8Bit(buffer, count));
    continue;
    }

    if (count == 0) {
        qDebug() << "[TITAN PTY] EOF";
        break;
    }

    if (errno == EINTR)
        continue;

    if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EIO)
        qWarning() << "[TITAN PTY] Error de lectura:" << strerror(errno);

    break;

        if (count == -1 && errno == EINTR)
            continue;

        break;
    }
}

void TerminalBackend::writeInput(const QString &text)
{
    if (m_masterFd < 0 || text.isEmpty())
        return;

    const QByteArray bytes = text.toLocal8Bit();
    qsizetype offset = 0;

    while (offset < bytes.size()) {
        const ssize_t written = write(
            m_masterFd, bytes.constData() + offset,
            static_cast<size_t>(bytes.size() - offset));

        if (written > 0) {
            offset += written;
            continue;
        }

        if (written == -1 && errno == EINTR)
            continue;

        emit terminalError(QStringLiteral("No se pudo escribir en el shell."));
        return;
    }
}

void TerminalBackend::sendInterrupt()
{
    writeInput(QString(1, QChar(3)));
}

void TerminalBackend::clearOutput()
{
    m_output.clear();
    emit outputChanged();
}
