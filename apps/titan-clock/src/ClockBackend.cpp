#include "ClockBackend.h"
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QTimeZone>
#include <QProcess>

ClockBackend::ClockBackend(QObject *parent)
    : QObject(parent),
      m_accumulatedMs(0),
      m_stopwatchRunning(false),
      m_timerTotalSeconds(300),
      m_timerRemainingSeconds(300),
      m_timerRunning(false)
{
    QString configDir = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + "/titan";
    QDir().mkpath(configDir);
    m_storagePath = configDir + "/clock_data.json";

    // Regular 1-second clock tick
    m_clockTimer = new QTimer(this);
    connect(m_clockTimer, &QTimer::timeout, this, &ClockBackend::onClockTick);
    m_clockTimer->start(1000);

    // Stopwatch tick (approx 30fps for smooth ms)
    m_swTimer = new QTimer(this);
    connect(m_swTimer, &QTimer::timeout, this, &ClockBackend::onStopwatchTick);

    // Timer tick (1 sec)
    m_cdTimer = new QTimer(this);
    connect(m_cdTimer, &QTimer::timeout, this, &ClockBackend::onTimerTick);

    loadData();

    if (m_worldClocks.isEmpty()) {
        QVariantMap ny, tk, ld, md;
        ny["city"] = "Nueva York"; ny["tzId"] = "America/New_York";
        tk["city"] = "Tokio";      tk["tzId"] = "Asia/Tokyo";
        ld["city"] = "Londres";    ld["tzId"] = "Europe/London";
        md["city"] = "Madrid";     md["tzId"] = "Europe/Madrid";
        m_worldClocks.append(ny);
        m_worldClocks.append(tk);
        m_worldClocks.append(ld);
        m_worldClocks.append(md);
    }
}

QString ClockBackend::currentTime() const {
    return QTime::currentTime().toString("HH:mm:ss");
}

QString ClockBackend::currentDate() const {
    return QDate::currentDate().toString("dddd, d 'de' MMMM 'de' yyyy");
}

QVariantList ClockBackend::worldClocks() const {
    QVariantList list;
    QDateTime nowUtc = QDateTime::currentDateTimeUtc();
    for (const auto &v : m_worldClocks) {
        QVariantMap map = v.toMap();
        QString tzId = map.value("tzId").toString();
        QTimeZone tz(tzId.toUtf8());
        if (tz.isValid()) {
            QDateTime dt = nowUtc.toTimeZone(tz);
            map["time"] = dt.toString("HH:mm");
            map["date"] = dt.toString("d MMM");
            int offsetHours = tz.offsetFromUtc(nowUtc) / 3600;
            map["offset"] = QString("%1%2 HRS").arg(offsetHours >= 0 ? "+" : "").arg(offsetHours);
        } else {
            map["time"] = "--:--";
            map["date"] = "--";
            map["offset"] = "+0 HRS";
        }
        list.append(map);
    }
    return list;
}

void ClockBackend::addWorldCity(const QString &city, const QString &tzId) {
    if (city.trimmed().isEmpty()) return;
    QVariantMap map;
    map["city"] = city.trimmed();
    map["tzId"] = tzId.trimmed();
    m_worldClocks.append(map);
    saveData();
    emit worldClocksChanged();
}

void ClockBackend::removeWorldCity(int index) {
    if (index >= 0 && index < m_worldClocks.size()) {
        m_worldClocks.removeAt(index);
        saveData();
        emit worldClocksChanged();
    }
}

// Stopwatch
QString ClockBackend::stopwatchTime() const {
    qint64 totalMs = m_accumulatedMs;
    if (m_stopwatchRunning) {
        totalMs += m_elapsedTimer.elapsed();
    }
    int ms = (totalMs % 1000) / 10;
    int s = (totalMs / 1000) % 60;
    int m = (totalMs / 60000) % 60;
    int h = (totalMs / 3600000);
    if (h > 0) {
        return QString("%1:%2:%3.%4")
            .arg(h, 2, 10, QChar('0'))
            .arg(m, 2, 10, QChar('0'))
            .arg(s, 2, 10, QChar('0'))
            .arg(ms, 2, 10, QChar('0'));
    }
    return QString("%1:%2.%3")
        .arg(m, 2, 10, QChar('0'))
        .arg(s, 2, 10, QChar('0'))
        .arg(ms, 2, 10, QChar('0'));
}

void ClockBackend::startStopwatch() {
    if (!m_stopwatchRunning) {
        m_stopwatchRunning = true;
        m_elapsedTimer.start();
        m_swTimer->start(33); // ~30 fps
        emit stopwatchChanged();
    }
}

void ClockBackend::pauseStopwatch() {
    if (m_stopwatchRunning) {
        m_accumulatedMs += m_elapsedTimer.elapsed();
        m_stopwatchRunning = false;
        m_swTimer->stop();
        emit stopwatchChanged();
    }
}

void ClockBackend::resetStopwatch() {
    m_stopwatchRunning = false;
    m_swTimer->stop();
    m_accumulatedMs = 0;
    m_stopwatchLaps.clear();
    emit stopwatchChanged();
    emit stopwatchLapsChanged();
}

void ClockBackend::lapStopwatch() {
    if (m_stopwatchRunning || m_accumulatedMs > 0) {
        QVariantMap lap;
        lap["lapNum"] = m_stopwatchLaps.size() + 1;
        lap["time"] = stopwatchTime();
        m_stopwatchLaps.prepend(lap);
        emit stopwatchLapsChanged();
    }
}

// Timer
QString ClockBackend::timerDisplay() const {
    int h = m_timerRemainingSeconds / 3600;
    int m = (m_timerRemainingSeconds % 3600) / 60;
    int s = m_timerRemainingSeconds % 60;
    if (h > 0) {
        return QString("%1:%2:%3")
            .arg(h, 2, 10, QChar('0'))
            .arg(m, 2, 10, QChar('0'))
            .arg(s, 2, 10, QChar('0'));
    }
    return QString("%1:%2")
        .arg(m, 2, 10, QChar('0'))
        .arg(s, 2, 10, QChar('0'));
}

void ClockBackend::startTimer(int totalSeconds) {
    if (totalSeconds <= 0) totalSeconds = 300;
    m_timerTotalSeconds = totalSeconds;
    m_timerRemainingSeconds = totalSeconds;
    m_timerRunning = true;
    m_cdTimer->start(1000);
    emit timerChanged();
}

void ClockBackend::pauseTimer() {
    m_timerRunning = false;
    m_cdTimer->stop();
    emit timerChanged();
}

void ClockBackend::resumeTimer() {
    if (m_timerRemainingSeconds > 0) {
        m_timerRunning = true;
        m_cdTimer->start(1000);
        emit timerChanged();
    }
}

void ClockBackend::resetTimer() {
    m_timerRunning = false;
    m_cdTimer->stop();
    m_timerRemainingSeconds = m_timerTotalSeconds;
    emit timerChanged();
}

// Alarms
void ClockBackend::addAlarm(const QString &timeStr, const QString &label, const QString &days) {
    if (timeStr.trimmed().isEmpty()) return;
    QVariantMap alarm;
    alarm["time"] = timeStr.trimmed();
    alarm["label"] = label.trimmed().isEmpty() ? "Alarma" : label.trimmed();
    alarm["days"] = days.trimmed().isEmpty() ? "Todos los días" : days.trimmed();
    alarm["enabled"] = true;
    m_alarms.append(alarm);
    saveData();
    emit alarmsChanged();
}

void ClockBackend::toggleAlarm(int index, bool enabled) {
    if (index >= 0 && index < m_alarms.size()) {
        QVariantMap map = m_alarms[index].toMap();
        map["enabled"] = enabled;
        m_alarms[index] = map;
        saveData();
        emit alarmsChanged();
    }
}

void ClockBackend::removeAlarm(int index) {
    if (index >= 0 && index < m_alarms.size()) {
        m_alarms.removeAt(index);
        saveData();
        emit alarmsChanged();
    }
}

void ClockBackend::onClockTick() {
    emit timeChanged();
    emit worldClocksChanged();

    // Check alarms
    QString currentHM = QTime::currentTime().toString("HH:mm");
    if (QTime::currentTime().second() == 0) {
        for (const auto &v : m_alarms) {
            QVariantMap a = v.toMap();
            if (a.value("enabled").toBool() && a.value("time").toString() == currentHM) {
                QString label = a.value("label").toString();
                emit alarmTriggered(label);
                QProcess::startDetached("notify-send", {"-i", "alarm", "Titan Reloj - Alarma", label});
                QProcess::startDetached("canberra-gtk-play", {"-i", "alarm-clock-elapsed"});
            }
        }
    }
}

void ClockBackend::onStopwatchTick() {
    emit stopwatchChanged();
}

void ClockBackend::onTimerTick() {
    if (m_timerRemainingSeconds > 0) {
        m_timerRemainingSeconds--;
        emit timerChanged();
        if (m_timerRemainingSeconds == 0) {
            m_timerRunning = false;
            m_cdTimer->stop();
            emit timerFinished();
            QProcess::startDetached("notify-send", {"-i", "alarm", "Titan Reloj", "¡El temporizador ha terminado!"});
            QProcess::startDetached("canberra-gtk-play", {"-i", "complete"});
        }
    }
}

void ClockBackend::loadData() {
    QFile file(m_storagePath);
    if (!file.open(QIODevice::ReadOnly)) return;

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (doc.isObject()) {
        QJsonObject root = doc.object();
        if (root.contains("worldClocks") && root["worldClocks"].isArray()) {
            m_worldClocks = root["worldClocks"].toArray().toVariantList();
        }
        if (root.contains("alarms") && root["alarms"].isArray()) {
            m_alarms = root["alarms"].toArray().toVariantList();
        }
    }
}

void ClockBackend::saveData() {
    QJsonObject root;
    root["worldClocks"] = QJsonArray::fromVariantList(m_worldClocks);
    root["alarms"] = QJsonArray::fromVariantList(m_alarms);

    QFile file(m_storagePath);
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    }
}

