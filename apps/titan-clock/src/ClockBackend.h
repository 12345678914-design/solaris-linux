#pragma once

#include <QObject>
#include <QTimer>
#include <QDateTime>
#include <QElapsedTimer>
#include <QVariantList>
#include <QVariantMap>

class ClockBackend : public QObject {
    Q_OBJECT
    // Local / World Clock
    Q_PROPERTY(QString currentTime READ currentTime NOTIFY timeChanged)
    Q_PROPERTY(QString currentDate READ currentDate NOTIFY timeChanged)
    Q_PROPERTY(int hours READ hours NOTIFY timeChanged)
    Q_PROPERTY(int minutes READ minutes NOTIFY timeChanged)
    Q_PROPERTY(int seconds READ seconds NOTIFY timeChanged)
    Q_PROPERTY(QVariantList worldClocks READ worldClocks NOTIFY worldClocksChanged)

    // Stopwatch
    Q_PROPERTY(QString stopwatchTime READ stopwatchTime NOTIFY stopwatchChanged)
    Q_PROPERTY(bool stopwatchRunning READ stopwatchRunning NOTIFY stopwatchChanged)
    Q_PROPERTY(QVariantList stopwatchLaps READ stopwatchLaps NOTIFY stopwatchLapsChanged)

    // Timer
    Q_PROPERTY(int timerRemainingSeconds READ timerRemainingSeconds NOTIFY timerChanged)
    Q_PROPERTY(int timerTotalSeconds READ timerTotalSeconds NOTIFY timerChanged)
    Q_PROPERTY(QString timerDisplay READ timerDisplay NOTIFY timerChanged)
    Q_PROPERTY(bool timerRunning READ timerRunning NOTIFY timerChanged)

    // Alarms
    Q_PROPERTY(QVariantList alarms READ alarms NOTIFY alarmsChanged)

public:
    explicit ClockBackend(QObject *parent = nullptr);

    QString currentTime() const;
    QString currentDate() const;
    int hours() const { return QTime::currentTime().hour(); }
    int minutes() const { return QTime::currentTime().minute(); }
    int seconds() const { return QTime::currentTime().second(); }
    QVariantList worldClocks() const;

    QString stopwatchTime() const;
    bool stopwatchRunning() const { return m_stopwatchRunning; }
    QVariantList stopwatchLaps() const { return m_stopwatchLaps; }

    int timerRemainingSeconds() const { return m_timerRemainingSeconds; }
    int timerTotalSeconds() const { return m_timerTotalSeconds; }
    QString timerDisplay() const;
    bool timerRunning() const { return m_timerRunning; }

    QVariantList alarms() const { return m_alarms; }

    // World clock
    Q_INVOKABLE void addWorldCity(const QString &city, const QString &tzId);
    Q_INVOKABLE void removeWorldCity(int index);

    // Stopwatch controls
    Q_INVOKABLE void startStopwatch();
    Q_INVOKABLE void pauseStopwatch();
    Q_INVOKABLE void resetStopwatch();
    Q_INVOKABLE void lapStopwatch();

    // Timer controls
    Q_INVOKABLE void startTimer(int totalSeconds);
    Q_INVOKABLE void pauseTimer();
    Q_INVOKABLE void resumeTimer();
    Q_INVOKABLE void resetTimer();

    // Alarm controls
    Q_INVOKABLE void addAlarm(const QString &timeStr, const QString &label, const QString &days);
    Q_INVOKABLE void toggleAlarm(int index, bool enabled);
    Q_INVOKABLE void removeAlarm(int index);

signals:
    void timeChanged();
    void worldClocksChanged();
    void stopwatchChanged();
    void stopwatchLapsChanged();
    void timerChanged();
    void timerFinished();
    void alarmsChanged();
    void alarmTriggered(const QString &label);

private slots:
    void onClockTick();
    void onStopwatchTick();
    void onTimerTick();

private:
    void loadData();
    void saveData();

    QTimer *m_clockTimer;
    QTimer *m_swTimer;
    QTimer *m_cdTimer;

    // Stopwatch state
    QElapsedTimer m_elapsedTimer;
    qint64 m_accumulatedMs;
    bool m_stopwatchRunning;
    QVariantList m_stopwatchLaps;

    // Timer state
    int m_timerTotalSeconds;
    int m_timerRemainingSeconds;
    bool m_timerRunning;

    // World clocks: List of {city: "...", tzId: "...", offset: "..."}
    QVariantList m_worldClocks;

    // Alarms: List of {time: "07:00", label: "Despertador", enabled: true, days: "Lun-Vie"}
    QVariantList m_alarms;

    QString m_storagePath;
};

