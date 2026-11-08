#include "CalcBackend.h"
#include <cmath>

CalcBackend::CalcBackend(QObject *parent)
    : QObject(parent)
    , m_display(QStringLiteral("0"))
    , m_expression(QString())
    , m_firstOperand(0.0)
    , m_waitingForSecondOperand(false)
    , m_memory(0.0)
    , m_hasMemory(false)
    , m_isScientific(false)
{
}

void CalcBackend::setIsScientific(bool scientific)
{
    if (m_isScientific != scientific) {
        m_isScientific = scientific;
        emit isScientificChanged();
    }
}

double CalcBackend::currentVal() const
{
    return m_display.toDouble();
}

void CalcBackend::setDisplay(double val)
{
    if (std::isnan(val) || std::isinf(val)) {
        m_display = QStringLiteral("Error");
    } else {
        // Formato limpio sin ceros residuales
        QString str = QString::number(val, 'g', 12);
        if (str == QStringLiteral("-0")) str = QStringLiteral("0");
        m_display = str;
    }
    emit displayChanged();
}

void CalcBackend::inputDigit(const QString &digit)
{
    if (m_display == QStringLiteral("Error") || m_waitingForSecondOperand) {
        m_display = digit;
        m_waitingForSecondOperand = false;
    } else if (m_display == QStringLiteral("0")) {
        m_display = digit;
    } else {
        if (m_display.length() < 16) {
            m_display += digit;
        }
    }
    emit displayChanged();
}

void CalcBackend::inputDot()
{
    if (m_waitingForSecondOperand || m_display == QStringLiteral("Error")) {
        m_display = QStringLiteral("0.");
        m_waitingForSecondOperand = false;
        emit displayChanged();
        return;
    }
    if (!m_display.contains(QLatin1Char('.'))) {
        m_display += QLatin1Char('.');
        emit displayChanged();
    }
}

void CalcBackend::inputOperator(const QString &op)
{
    if (!m_pendingOp.isEmpty() && !m_waitingForSecondOperand) {
        calculate();
    }
    m_firstOperand = currentVal();
    m_pendingOp = op;
    m_waitingForSecondOperand = true;
    m_expression = QString::number(m_firstOperand, 'g', 10) + QLatin1Char(' ') + op;
    emit expressionChanged();
}

void CalcBackend::calculate()
{
    if (m_pendingOp.isEmpty()) return;

    double second = currentVal();
    double result = 0.0;

    if (m_pendingOp == QStringLiteral("+")) {
        result = m_firstOperand + second;
    } else if (m_pendingOp == QStringLiteral("−") || m_pendingOp == QStringLiteral("-")) {
        result = m_firstOperand - second;
    } else if (m_pendingOp == QStringLiteral("×") || m_pendingOp == QStringLiteral("*")) {
        result = m_firstOperand * second;
    } else if (m_pendingOp == QStringLiteral("÷") || m_pendingOp == QStringLiteral("/")) {
        if (second == 0.0) {
            m_display = QStringLiteral("Error");
            m_expression.clear();
            m_pendingOp.clear();
            emit displayChanged();
            emit expressionChanged();
            return;
        }
        result = m_firstOperand / second;
    } else if (m_pendingOp == QStringLiteral("^")) {
        result = std::pow(m_firstOperand, second);
    }

    m_expression = QString::number(m_firstOperand, 'g', 10) + QLatin1Char(' ') + m_pendingOp + QLatin1Char(' ') + QString::number(second, 'g', 10) + QStringLiteral(" =");
    emit expressionChanged();

    m_firstOperand = result;
    m_pendingOp.clear();
    m_waitingForSecondOperand = true;
    setDisplay(result);
}

void CalcBackend::clear()
{
    m_display = QStringLiteral("0");
    m_expression.clear();
    m_firstOperand = 0.0;
    m_pendingOp.clear();
    m_waitingForSecondOperand = false;
    emit displayChanged();
    emit expressionChanged();
}

void CalcBackend::deleteLast()
{
    if (m_waitingForSecondOperand || m_display == QStringLiteral("Error")) {
        clear();
        return;
    }
    if (m_display.length() > 1) {
        m_display.chop(1);
    } else {
        m_display = QStringLiteral("0");
    }
    emit displayChanged();
}

void CalcBackend::toggleSign()
{
    double val = currentVal();
    setDisplay(-val);
}

void CalcBackend::percent()
{
    double val = currentVal();
    setDisplay(val / 100.0);
}

void CalcBackend::sqrtOp()
{
    double val = currentVal();
    if (val < 0.0) {
        m_display = QStringLiteral("Error");
        emit displayChanged();
    } else {
        setDisplay(std::sqrt(val));
    }
}

void CalcBackend::sqrOp()
{
    double val = currentVal();
    setDisplay(val * val);
}

void CalcBackend::invOp()
{
    double val = currentVal();
    if (val == 0.0) {
        m_display = QStringLiteral("Error");
        emit displayChanged();
    } else {
        setDisplay(1.0 / val);
    }
}

void CalcBackend::constPi()
{
    setDisplay(M_PI);
    m_waitingForSecondOperand = false;
}

void CalcBackend::constE()
{
    setDisplay(M_E);
    m_waitingForSecondOperand = false;
}

void CalcBackend::trigSin()
{
    double val = currentVal();
    setDisplay(std::sin(val));
}

void CalcBackend::trigCos()
{
    double val = currentVal();
    setDisplay(std::cos(val));
}

void CalcBackend::trigTan()
{
    double val = currentVal();
    setDisplay(std::tan(val));
}

void CalcBackend::log10Op()
{
    double val = currentVal();
    if (val <= 0.0) {
        m_display = QStringLiteral("Error");
        emit displayChanged();
    } else {
        setDisplay(std::log10(val));
    }
}

void CalcBackend::lnOp()
{
    double val = currentVal();
    if (val <= 0.0) {
        m_display = QStringLiteral("Error");
        emit displayChanged();
    } else {
        setDisplay(std::log(val));
    }
}

void CalcBackend::memoryClear()
{
    m_memory = 0.0;
    m_hasMemory = false;
    emit memoryChanged();
}

void CalcBackend::memoryRecall()
{
    if (m_hasMemory) {
        setDisplay(m_memory);
        m_waitingForSecondOperand = false;
    }
}

void CalcBackend::memoryAdd()
{
    m_memory += currentVal();
    m_hasMemory = true;
    emit memoryChanged();
}

void CalcBackend::memorySubtract()
{
    m_memory -= currentVal();
    m_hasMemory = true;
    emit memoryChanged();
}

