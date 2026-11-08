#include "CalendarBackend.h"
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

void CalendarBackend::addEvent(const QString &title, const QString &timeStr, const QString &description) {
    if (title.trimmed().isEmpty()) return;
    QString key = m_selectedDate.toString("yyyy-MM-dd");
    QVariantList evList = m_allEvents.value(key).toList();
    
    QVariantMap item;
    item["title"] = title.trimmed();
    item["time"] = timeStr.trimmed().isEmpty() ? "Todo el día" : timeStr.trimmed();
    item["description"] = description.trimmed();

    evList.append(item);
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

