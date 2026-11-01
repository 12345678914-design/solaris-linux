#pragma once

#include <QObject>
#include <QString>
#include <QSocketNotifier>

class TerminalBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString output READ output NOTIFY outputChanged)

public:
    explicit TerminalBackend(QObject *parent = nullptr);
    ~TerminalBackend() override;

    QString output() const;

    Q_INVOKABLE void writeInput(const QString &text);
    Q_INVOKABLE void sendInterrupt();
    Q_INVOKABLE void clearOutput();

signals:
    void outputChanged();
    void terminalError(const QString &message);

private:
    void readAvailable();
    void appendOutput(const QString &text);

    int m_masterFd = -1;
    int m_childPid = -1;
    QSocketNotifier *m_notifier = nullptr;
    QString m_output;
};
