#pragma once

#include <QObject>
#include <QString>
#include <cmath>

class CalcBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString display READ display NOTIFY displayChanged)
    Q_PROPERTY(QString expression READ expression NOTIFY expressionChanged)
    Q_PROPERTY(bool hasMemory READ hasMemory NOTIFY memoryChanged)
    Q_PROPERTY(bool isScientific READ isScientific WRITE setIsScientific NOTIFY isScientificChanged)

public:
    explicit CalcBackend(QObject *parent = nullptr);

    QString display() const { return m_display; }
    QString expression() const { return m_expression; }
    bool hasMemory() const { return m_hasMemory; }
    bool isScientific() const { return m_isScientific; }
    void setIsScientific(bool scientific);

    Q_INVOKABLE void inputDigit(const QString &digit);
    Q_INVOKABLE void inputDot();
    Q_INVOKABLE void inputOperator(const QString &op);
    Q_INVOKABLE void calculate();
    Q_INVOKABLE void clear();
    Q_INVOKABLE void deleteLast();
    Q_INVOKABLE void toggleSign();
    Q_INVOKABLE void percent();
    Q_INVOKABLE void sqrtOp();
    Q_INVOKABLE void sqrOp();
    Q_INVOKABLE void invOp();
    Q_INVOKABLE void constPi();
    Q_INVOKABLE void constE();
    Q_INVOKABLE void trigSin();
    Q_INVOKABLE void trigCos();
    Q_INVOKABLE void trigTan();
    Q_INVOKABLE void log10Op();
    Q_INVOKABLE void lnOp();

    Q_INVOKABLE void memoryClear();
    Q_INVOKABLE void memoryRecall();
    Q_INVOKABLE void memoryAdd();
    Q_INVOKABLE void memorySubtract();

signals:
    void displayChanged();
    void expressionChanged();
    void memoryChanged();
    void isScientificChanged();

private:
    void setDisplay(double val);
    double currentVal() const;

    QString m_display;
    QString m_expression;
    double m_firstOperand;
    QString m_pendingOp;
    bool m_waitingForSecondOperand;
    double m_memory;
    bool m_hasMemory;
    bool m_isScientific;
};

