#pragma once

#include <QObject>
#include <QDate>
#include <QVariantList>
#include <QVariantMap>

class CalendarBackend : public QObject {
    Q_OBJECT
    Q_PROPERTY(int currentYear READ currentYear WRITE setCurrentYear NOTIFY dateChanged)
    Q_PROPERTY(int currentMonth READ currentMonth WRITE setCurrentMonth NOTIFY dateChanged)
    Q_PROPERTY(QString monthName READ monthName NOTIFY dateChanged)
    Q_PROPERTY(QDate selectedDate READ selectedDate WRITE setSelectedDate NOTIFY selectedDateChanged)
    Q_PROPERTY(QVariantList daysInMonth READ daysInMonth NOTIFY dateChanged)
    Q_PROPERTY(QVariantList selectedDateEvents READ selectedDateEvents NOTIFY eventsChanged)

public:
    explicit CalendarBackend(QObject *parent = nullptr);

    int currentYear() const { return m_currentDate.year(); }
    int currentMonth() const { return m_currentDate.month(); }
    QString monthName() const;
    QDate selectedDate() const { return m_selectedDate; }

    void setCurrentYear(int year);
    void setCurrentMonth(int month);
    void setSelectedDate(const QDate &date);

    QVariantList daysInMonth() const;
    QVariantList selectedDateEvents() const;

    Q_INVOKABLE void nextMonth();
    Q_INVOKABLE void prevMonth();
    Q_INVOKABLE void goToToday();
    Q_INVOKABLE void addEvent(const QString &title, const QString &timeStr, const QString &description);
    Q_INVOKABLE void deleteEvent(int index);

signals:
    void dateChanged();
    void selectedDateChanged();
    void eventsChanged();

private:
    void loadEvents();
    void saveEvents();

    QDate m_currentDate;
    QDate m_selectedDate;
    QVariantMap m_allEvents; // date_str (yyyy-MM-dd) -> QVariantList of maps
    QString m_storagePath;
};

