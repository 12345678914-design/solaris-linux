#include "CalendarBackend.h"
#include <algorithm>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QLocale>

CalendarBackend::CalendarBackend(QObject *parent)
    : QObject(parent),
      m_currentDate(QDate::currentDate()),
      m_selectedDate(QDate::currentDate())
{
    QString configDir = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + "/titan";
    QDir().mkpath(configDir);
    m_storagePath = configDir + "/calendar_events.json";
    loadEvents();
}

QString CalendarBackend::monthName() const {
    static const QStringList months = {
        "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
        "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"
    };
    int m = m_currentDate.month();
    if (m >= 1 && m <= 12) {
        return months[m - 1] + QString(" %1").arg(m_currentDate.year());
    }
    return "";
}

void CalendarBackend::setCurrentYear(int year) {
    if (year != m_currentDate.year()) {
        m_currentDate.setDate(year, m_currentDate.month(), 1);
        emit dateChanged();
    }
}

void CalendarBackend::setCurrentMonth(int month) {
    if (month != m_currentDate.month() && month >= 1 && month <= 12) {
        m_currentDate.setDate(m_currentDate.year(), month, 1);
        emit dateChanged();
    }
}

void CalendarBackend::setSelectedDate(const QDate &date) {
    if (date != m_selectedDate) {
        m_selectedDate = date;
        emit selectedDateChanged();
        emit eventsChanged();
    }
}

void CalendarBackend::nextMonth() {
    m_currentDate = m_currentDate.addMonths(1);
    emit dateChanged();
}

void CalendarBackend::prevMonth() {
    m_currentDate = m_currentDate.addMonths(-1);
    emit dateChanged();
}

void CalendarBackend::goToToday() {
    m_currentDate = QDate::currentDate();
    m_selectedDate = QDate::currentDate();
    emit dateChanged();
    emit selectedDateChanged();
    emit eventsChanged();
}

QVariantList CalendarBackend::daysInMonth() const {
    QVariantList list;
    QDate firstDay(m_currentDate.year(), m_currentDate.month(), 1);
    int daysCount = firstDay.daysInMonth();
    
    // Day of week for 1st of month: 1=Mon, 7=Sun
    int firstDOW = firstDay.dayOfWeek(); // 1 = Monday
    int leadingBlanks = firstDOW - 1;

    // Previous month filler days
    QDate prevMonthDate = firstDay.addMonths(-1);
    int prevDaysCount = prevMonthDate.daysInMonth();

    for (int i = leadingBlanks - 1; i >= 0; --i) {
        int dayNum = prevDaysCount - i;
        QDate d(prevMonthDate.year(), prevMonthDate.month(), dayNum);
        QVariantMap map;
        map["day"] = dayNum;
        map["date"] = d;
        map["isCurrentMonth"] = false;
        map["isToday"] = (d == QDate::currentDate());
        QString dateKey = d.toString("yyyy-MM-dd");
        map["hasEvents"] = m_allEvents.contains(dateKey) && !m_allEvents[dateKey].toList().isEmpty();
        list.append(map);
    }

    // Current month days
    for (int day = 1; day <= daysCount; ++day) {
        QDate d(m_currentDate.year(), m_currentDate.month(), day);
        QVariantMap map;
        map["day"] = day;
        map["date"] = d;
        map["isCurrentMonth"] = true;
        map["isToday"] = (d == QDate::currentDate());
        QString dateKey = d.toString("yyyy-MM-dd");
        map["hasEvents"] = m_allEvents.contains(dateKey) && !m_allEvents[dateKey].toList().isEmpty();
        list.append(map);
    }

    // Trailing days to fill a full grid of 35 or 42 cells (multiple of 7)
    int totalCells = list.size();
    int remainder = 7 - (totalCells % 7);
    if (remainder < 7) {
        QDate nextMonthDate = firstDay.addMonths(1);
        for (int day = 1; day <= remainder; ++day) {
            QDate d(nextMonthDate.year(), nextMonthDate.month(), day);
            QVariantMap map;
            map["day"] = day;
            map["date"] = d;
            map["isCurrentMonth"] = false;
            map["isToday"] = (d == QDate::currentDate());
            QString dateKey = d.toString("yyyy-MM-dd");
            map["hasEvents"] = m_allEvents.contains(dateKey) && !m_allEvents[dateKey].toList().isEmpty();
            list.append(map);
        }
    }

    return list;
}

QVariantList CalendarBackend::selectedDateEvents() const {
    QString key = m_selectedDate.toString("yyyy-MM-dd");
    return m_allEvents.value(key).toList();
}

// "9:5" -> "09:05", "14h" -> "14:00", "" -> "Todo el día". Si no se entiende, se deja tal cual.
QString CalendarBackend::normalizeTime(const QString &timeStr) {
    const QString t = timeStr.trimmed();
    if (t.isEmpty()) return QStringLiteral("Todo el día");
    static const QRegularExpression re(QStringLiteral("^(\\d{1,2})(?:[:.h](\\d{1,2}))?h?$"));
    const auto m = re.match(t);
    if (m.hasMatch()) {
        const int h = m.captured(1).toInt();
        const int min = m.captured(2).isEmpty() ? 0 : m.captured(2).toInt();
        if (h < 24 && min < 60)
            return QStringLiteral("%1:%2").arg(h, 2, 10, QLatin1Char('0')).arg(min, 2, 10, QLatin1Char('0'));
    }
    return t;
}

QString CalendarBackend::timeError(const QString &timeStr) const {
    const QString n = normalizeTime(timeStr);
    if (n == QStringLiteral("Todo el día")) return QString();
    static const QRegularExpression ok(QStringLiteral("^\\d{2}:\\d{2}$"));
    if (ok.match(n).hasMatch() && n.left(2).toInt() < 24 && n.mid(3, 2).toInt() < 60)
        return QString();
    return QStringLiteral("Hora no válida: usa HH:MM (ej. 09:30) o déjala vacía");
}

// Los de todo el día primero; después por hora.
void CalendarBackend::sortDay(QVariantList &list) {
    std::stable_sort(list.begin(), list.end(), [](const QVariant &a, const QVariant &b) {
        const QString ta = a.toMap().value(QStringLiteral("time")).toString();
        const QString tb = b.toMap().value(QStringLiteral("time")).toString();
        const bool da = !ta.contains(QLatin1Char(':'));
        const bool db = !tb.contains(QLatin1Char(':'));
        if (da != db) return da;
        return ta < tb;
    });
}

void CalendarBackend::addEvent(const QString &title, const QString &timeStr, const QString &description) {
    if (title.trimmed().isEmpty() || !timeError(timeStr).isEmpty()) return;
    QString key = m_selectedDate.toString("yyyy-MM-dd");
    QVariantList evList = m_allEvents.value(key).toList();

    QVariantMap item;
    item["title"] = title.trimmed();
    item["time"] = normalizeTime(timeStr);
    item["description"] = description.trimmed();

    evList.append(item);
    sortDay(evList);
    m_allEvents[key] = evList;
    saveEvents();
    emit eventsChanged();
    emit dateChanged();
}

void CalendarBackend::updateEvent(int index, const QString &title, const QString &timeStr, const QString &description) {
    if (title.trimmed().isEmpty() || !timeError(timeStr).isEmpty()) return;
    const QString key = m_selectedDate.toString("yyyy-MM-dd");
    QVariantList evList = m_allEvents.value(key).toList();
    if (index < 0 || index >= evList.size()) return;

    QVariantMap item = evList.at(index).toMap();
    item["title"] = title.trimmed();
    item["time"] = normalizeTime(timeStr);
    item["description"] = description.trimmed();
    evList[index] = item;
    sortDay(evList);
    m_allEvents[key] = evList;
    saveEvents();
    emit eventsChanged();
    emit dateChanged();
}

void CalendarBackend::deleteEvent(int index) {
    QString key = m_selectedDate.toString("yyyy-MM-dd");
    QVariantList evList = m_allEvents.value(key).toList();
    if (index >= 0 && index < evList.size()) {
        evList.removeAt(index);
        if (evList.isEmpty()) {
            m_allEvents.remove(key);
        } else {
            m_allEvents[key] = evList;
        }
        saveEvents();
        emit eventsChanged();
        emit dateChanged();
    }
}

void CalendarBackend::loadEvents() {
    QFile file(m_storagePath);
    if (!file.open(QIODevice::ReadOnly)) return;

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (doc.isObject()) {
        QJsonObject root = doc.object();
        for (auto it = root.begin(); it != root.end(); ++it) {
            QVariantList evList;
            if (it.value().isArray()) {
                QJsonArray arr = it.value().toArray();
                for (const auto &val : arr) {
                    if (val.isObject()) {
                        evList.append(val.toObject().toVariantMap());
                    }
                }
            }
            m_allEvents[it.key()] = evList;
        }
    }
}

void CalendarBackend::saveEvents() {
    QJsonObject root;
    for (auto it = m_allEvents.begin(); it != m_allEvents.end(); ++it) {
        QJsonArray arr;
        QVariantList list = it.value().toList();
        for (const auto &v : list) {
            arr.append(QJsonObject::fromVariantMap(v.toMap()));
        }
        root[it.key()] = arr;
    }

    QFile file(m_storagePath);
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    }
}

