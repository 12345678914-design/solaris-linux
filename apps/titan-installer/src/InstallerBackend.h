#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QThread>

class InstallWorker;

class InstallerBackend : public QObject
{
    Q_OBJECT

    Q_PROPERTY(int currentStep READ currentStep WRITE setCurrentStep NOTIFY currentStepChanged)
    Q_PROPERTY(QVariantList disks READ disks NOTIFY disksChanged)
    Q_PROPERTY(int selectedDiskIndex READ selectedDiskIndex WRITE setSelectedDiskIndex NOTIFY selectedDiskIndexChanged)
    Q_PROPERTY(QString selectedDiskPath READ selectedDiskPath NOTIFY selectedDiskChanged)
    Q_PROPERTY(QString selectedDiskName READ selectedDiskName NOTIFY selectedDiskChanged)
    Q_PROPERTY(QString selectedDiskSize READ selectedDiskSize NOTIFY selectedDiskChanged)

    Q_PROPERTY(int ramMb READ ramMb CONSTANT)
    Q_PROPERTY(bool isUefi READ isUefi CONSTANT)
    Q_PROPERTY(bool hasPower READ hasPower NOTIFY powerChanged)
    Q_PROPERTY(bool reqRamOk READ reqRamOk CONSTANT)
    Q_PROPERTY(bool reqDiskOk READ reqDiskOk NOTIFY disksChanged)
    Q_PROPERTY(bool reqPowerOk READ reqPowerOk NOTIFY powerChanged)

    Q_PROPERTY(bool installing READ installing NOTIFY installingChanged)
    Q_PROPERTY(int progressPercent READ progressPercent NOTIFY progressPercentChanged)
    Q_PROPERTY(QString progressMessage READ progressMessage NOTIFY progressMessageChanged)
    Q_PROPERTY(bool installSuccess READ installSuccess NOTIFY installSuccessChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)

    Q_PROPERTY(bool manualPartitioning READ manualPartitioning WRITE setManualPartitioning NOTIFY manualPartitioningChanged)
    Q_PROPERTY(QVariantList manualPartitions READ manualPartitions NOTIFY manualPartitionsChanged)
    // "borrar" (todo el disco), "junto" (en el hueco libre, al lado de Windows u
    // otro sistema) o "manual"
    Q_PROPERTY(QString modoDisco READ modoDisco WRITE setModoDisco NOTIFY modoDiscoChanged)
    // Cifrado del disco (LUKS2): la contrasena se pide al encender el equipo
    Q_PROPERTY(bool cifrar READ cifrar WRITE setCifrar NOTIFY cifrarChanged)
    Q_PROPERTY(QVariantMap discoElegido READ discoElegido NOTIFY selectedDiskChanged)

public:
    explicit InstallerBackend(QObject *parent = nullptr);
    ~InstallerBackend() override;

    int currentStep() const { return m_currentStep; }
    void setCurrentStep(int step);

    QVariantList disks() const { return m_disks; }
    int selectedDiskIndex() const { return m_selectedDiskIndex; }
    void setSelectedDiskIndex(int idx);

    QString selectedDiskPath() const;
    QString selectedDiskName() const;
    QString selectedDiskSize() const;

    int ramMb() const { return m_ramMb; }
    bool isUefi() const { return m_isUefi; }
    bool hasPower() const { return m_hasPower; }
    bool reqRamOk() const { return m_ramMb >= 1900; }
    bool reqDiskOk() const { return !m_disks.isEmpty(); }
    bool reqPowerOk() const { return m_hasPower; }

    bool installing() const { return m_installing; }
    int progressPercent() const { return m_progressPercent; }
    QString progressMessage() const { return m_progressMessage; }
    bool installSuccess() const { return m_installSuccess; }
    QString errorMessage() const { return m_errorMessage; }

    bool manualPartitioning() const { return m_manualPartitioning; }
    void setManualPartitioning(bool manual);

    QVariantList manualPartitions() const { return m_manualPartitions; }
    Q_INVOKABLE void addManualPartition(const QString &mountPoint, int sizeMb, const QString &fsType);
    Q_INVOKABLE void updateManualPartition(int index, const QString &mountPoint, int sizeMb, const QString &fsType);
    Q_INVOKABLE void removeManualPartition(int index);
    Q_INVOKABLE void resetDefaultPartitions();
    Q_INVOKABLE void openExternalPartitioner();
    Q_INVOKABLE QString validatePartitionPlan() const;

    Q_INVOKABLE void refreshDisks();
    Q_INVOKABLE void setClaveCifrado(const QString &clave);
    Q_INVOKABLE void startInstallation(const QString &fsType,
                                       const QString &fullName,
                                       const QString &userName,
                                       const QString &password,
                                       const QString &hostname,
                                       bool autoLogin,
                                       const QString &timezone,
                                       const QString &keymap);
    Q_INVOKABLE void rebootSystem();
    Q_INVOKABLE void closeInstaller();

    QString modoDisco() const { return m_modoDisco; }
    void setModoDisco(const QString &modo);
    bool cifrar() const { return m_cifrar; }
    void setCifrar(bool cifrar);
    QVariantMap discoElegido() const;

signals:
    void modoDiscoChanged();
    void cifrarChanged();
    void currentStepChanged();
    void disksChanged();
    void selectedDiskIndexChanged();
    void selectedDiskChanged();
    void powerChanged();
    void installingChanged();
    void progressPercentChanged();
    void progressMessageChanged();
    void installSuccessChanged();
    void errorMessageChanged();
    void manualPartitioningChanged();
    void manualPartitionsChanged();

private slots:
    void onWorkerProgress(int percent, const QString &msg);
    void onWorkerFinished(bool success, const QString &error);

private:
    void checkSystemRequirements();

    int m_currentStep{0};
    QVariantList m_disks;
    int m_selectedDiskIndex{0};

    int m_ramMb{0};
    bool m_isUefi{true};
    bool m_hasPower{true};

    bool m_installing{false};
    int m_progressPercent{0};
    QString m_progressMessage;
    bool m_installSuccess{false};
    QString m_errorMessage;

    bool m_manualPartitioning{false};
    QString m_modoDisco{QStringLiteral("borrar")};
    bool m_cifrar{false};
    QString m_claveCifrado;
    bool m_modoElegido{false};   // la persona ya ha elegido modo: no se cambia solo
    void modoPorDefecto();
    QVariantList m_manualPartitions;

    QThread *m_workerThread{nullptr};
    InstallWorker *m_worker{nullptr};
};
