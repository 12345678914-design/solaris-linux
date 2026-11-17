#include "InstallerBackend.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <QThread>
#include <QCoreApplication>
#include <QDebug>
#include <sys/sysinfo.h>
#include <unistd.h>

class InstallWorker : public QObject
{
    Q_OBJECT
public:
    QString diskPath;
    QString fsType;
    QString fullName;
    QString userName;
    QString password;
    QString hostname;
    bool autoLogin{false};
    QString timezone;
    QString keymap;
    bool isUefi{true};
    bool manualPartitioning{false};
    QVariantList manualPartitions;

signals:
    void progress(int percent, const QString &message);
    void finished(bool success, const QString &error);

public slots:
    void doInstall()
    {
        // Lo que dijo la ultima orden que fallo, para ensenarlo en la pantalla de
        // error en vez de un "algo ha ido mal" sin pistas.
        QString lastError;

        // Sin limite de tiempo: copiar el sistema a un disco lento o compilar el
        // initramfs puede tardar mas de cinco minutos, y con un limite QProcess
        // mataba la orden a medias y la instalacion seguia como si nada.
        auto runCmd = [&lastError](const QString &cmd, const QStringList &args = QStringList()) -> bool {
            QProcess p;
            p.start(cmd, args);
            if (!p.waitForStarted(15000)) {
                lastError = QStringLiteral("%1: no se ha podido ejecutar (%2)").arg(cmd, p.errorString());
                qWarning() << "Comando no arrancó:" << cmd << args;
                return false;
            }
            p.waitForFinished(-1);
            if (p.exitStatus() != QProcess::NormalExit || p.exitCode() != 0) {
                QString err = QString::fromUtf8(p.readAllStandardError()).trimmed();
                if (err.isEmpty())
                    err = QString::fromUtf8(p.readAllStandardOutput()).trimmed();
                // Las ultimas lineas son las que dicen el motivo.
                const QStringList lines = err.split(QLatin1Char('\n'));
                err = lines.mid(qMax(0, int(lines.size()) - 3)).join(QLatin1Char('\n'));
                lastError = QStringLiteral("%1 %2 (codigo %3): %4")
                                .arg(cmd, args.join(QLatin1Char(' ')))
                                .arg(p.exitCode())
                                .arg(err);
                qWarning() << "Comando falló:" << cmd << args << "Salida de error:" << err;
                return false;
            }
            return true;
        };

        // Un fallo corta la instalacion: se desmonta lo que se haya montado y se
        // dice que orden ha fallado. Antes cada fallo se ignoraba y al final
        // salia "instalacion completada" con un sistema que no arrancaba.
        auto fail = [&](const QString &msg) {
            const QString detail = lastError;
            QProcess::execute(QStringLiteral("umount"), {QStringLiteral("-R"), QStringLiteral("/mnt")});
            emit finished(false, detail.isEmpty() ? msg : msg + QStringLiteral("\n\nDetalle: ") + detail);
        };

        emit progress(5, QStringLiteral("Desmontando particiones anteriores..."));
        // Que /mnt no este montado no es un error.
        QProcess::execute(QStringLiteral("umount"), {QStringLiteral("-R"), QStringLiteral("/mnt")});

        QString sep = (diskPath.contains(QRegularExpression(QStringLiteral("[0-9]$")))) ? QStringLiteral("p") : QString();
        QString efiDev;
        QString rootDev;
        QMap<QString, QString> mountToDev;

        emit progress(10, QStringLiteral("Preparando tabla de particiones del disco..."));

        if (manualPartitioning && !manualPartitions.isEmpty()) {
            // ==========================================
            // MODO PARTICIONAMIENTO MANUAL
            // ==========================================
            QString labelType = isUefi ? QStringLiteral("gpt") : QStringLiteral("msdos");
            if (!runCmd(QStringLiteral("parted"), {QStringLiteral("-s"), diskPath, QStringLiteral("mklabel"), labelType}))
                return fail(QStringLiteral("No se pudo inicializar la tabla ") + labelType + QStringLiteral(" en ") + diskPath);

            int startMb = 1;
            for (int i = 0; i < manualPartitions.size(); ++i) {
                const auto pMap = manualPartitions[i].toMap();
                QString mPoint = pMap[QStringLiteral("mount")].toString();
                int sizeMb = pMap[QStringLiteral("size")].toInt();
                QString pFs = pMap[QStringLiteral("fs")].toString().toLower();
                if (pFs.isEmpty()) pFs = QStringLiteral("ext4");

                QString partNum = QString::number(i + 1);
                QString partDev = diskPath + sep + partNum;

                QString pType = (isUefi || i == 0) ? QStringLiteral("primary") : QStringLiteral("primary");
                QString pPartedFs = (pFs == QStringLiteral("fat32")) ? QStringLiteral("fat32") : ((pFs == QStringLiteral("swap")) ? QStringLiteral("linux-swap") : QStringLiteral("ext4"));

                // 0 significa espacio restante hasta el 100%
                const QString endPos = (sizeMb > 0) ? QString::number(startMb + sizeMb) + QStringLiteral("MiB")
                                                    : QStringLiteral("100%");
                if (!runCmd(QStringLiteral("parted"), {QStringLiteral("-s"), diskPath, QStringLiteral("mkpart"), pType, pPartedFs, QString::number(startMb) + QStringLiteral("MiB"), endPos}))
                    return fail(QStringLiteral("No se pudo crear la partición ") + partNum + QStringLiteral(" (") + mPoint + QStringLiteral(")"));
                if (sizeMb > 0)
                    startMb += sizeMb;

                if (mPoint == QStringLiteral("/boot/efi") && isUefi) {
                    if (!runCmd(QStringLiteral("parted"), {QStringLiteral("-s"), diskPath, QStringLiteral("set"), partNum, QStringLiteral("esp"), QStringLiteral("on")}))
                        return fail(QStringLiteral("No se pudo marcar la partición EFI"));
                    efiDev = partDev;
                } else if (mPoint == QStringLiteral("/")) {
                    rootDev = partDev;
                    if (!isUefi) {
                        if (!runCmd(QStringLiteral("parted"), {QStringLiteral("-s"), diskPath, QStringLiteral("set"), partNum, QStringLiteral("boot"), QStringLiteral("on")}))
                            return fail(QStringLiteral("No se pudo marcar la partición de arranque"));
                    }
                }

                mountToDev[mPoint] = partDev;
            }
        } else {
            // ==========================================
            // MODO AUTOMÁTICO (BORRAR DISCO COMPLETO)
            // ==========================================
            if (isUefi) {
                if (!runCmd(QStringLiteral("parted"), {QStringLiteral("-s"), diskPath, QStringLiteral("mklabel"), QStringLiteral("gpt")}))
                    return fail(QStringLiteral("No se pudo crear la tabla de particiones GPT en ") + diskPath);
                // Partición 1: EFI 512MiB. Partición 2: raíz con el resto.
                if (!runCmd(QStringLiteral("parted"), {QStringLiteral("-s"), diskPath, QStringLiteral("mkpart"), QStringLiteral("EFI"), QStringLiteral("fat32"), QStringLiteral("1MiB"), QStringLiteral("513MiB")}) ||
                    !runCmd(QStringLiteral("parted"), {QStringLiteral("-s"), diskPath, QStringLiteral("set"), QStringLiteral("1"), QStringLiteral("esp"), QStringLiteral("on")}) ||
                    !runCmd(QStringLiteral("parted"), {QStringLiteral("-s"), diskPath, QStringLiteral("mkpart"), QStringLiteral("IntiRoot"), QStringLiteral("ext4"), QStringLiteral("513MiB"), QStringLiteral("100%")}))
                    return fail(QStringLiteral("No se pudieron crear las particiones en ") + diskPath);

                efiDev = diskPath + sep + QStringLiteral("1");
                rootDev = diskPath + sep + QStringLiteral("2");
                mountToDev[QStringLiteral("/boot/efi")] = efiDev;
                mountToDev[QStringLiteral("/")] = rootDev;
            } else {
                if (!runCmd(QStringLiteral("parted"), {QStringLiteral("-s"), diskPath, QStringLiteral("mklabel"), QStringLiteral("msdos")}))
                    return fail(QStringLiteral("No se pudo crear la tabla de particiones MBR en ") + diskPath);
                if (!runCmd(QStringLiteral("parted"), {QStringLiteral("-s"), diskPath, QStringLiteral("mkpart"), QStringLiteral("primary"), QStringLiteral("ext4"), QStringLiteral("1MiB"), QStringLiteral("100%")}) ||
                    !runCmd(QStringLiteral("parted"), {QStringLiteral("-s"), diskPath, QStringLiteral("set"), QStringLiteral("1"), QStringLiteral("boot"), QStringLiteral("on")}))
                    return fail(QStringLiteral("No se pudo crear la partición en ") + diskPath);

                rootDev = diskPath + sep + QStringLiteral("1");
                mountToDev[QStringLiteral("/")] = rootDev;
            }
        }

        if (rootDev.isEmpty())
            return fail(QStringLiteral("No se ha definido ninguna partición con punto de montaje '/' (Raíz)."));

        // Refrescar nodos de bloques
        QThread::msleep(800);
        runCmd(QStringLiteral("partprobe"), {diskPath});
        runCmd(QStringLiteral("udevadm"), {QStringLiteral("settle")});
        QThread::msleep(800);

        emit progress(20, QStringLiteral("Formateando sistemas de archivos..."));

        if (manualPartitioning) {
            for (int i = 0; i < manualPartitions.size(); ++i) {
                const auto pMap = manualPartitions[i].toMap();
                QString mPoint = pMap[QStringLiteral("mount")].toString();
                QString pFs = pMap[QStringLiteral("fs")].toString().toLower();
                QString pDev = mountToDev.value(mPoint);
                if (pDev.isEmpty()) continue;

                bool ok;
                if (pFs == QStringLiteral("fat32")) {
                    ok = runCmd(QStringLiteral("mkfs.fat"), {QStringLiteral("-F32"), pDev});
                } else if (pFs == QStringLiteral("btrfs")) {
                    ok = runCmd(QStringLiteral("mkfs.btrfs"), {QStringLiteral("-f"), QStringLiteral("-L"), QStringLiteral("INTI"), pDev});
                } else if (pFs == QStringLiteral("swap")) {
                    ok = runCmd(QStringLiteral("mkswap"), {QStringLiteral("-L"), QStringLiteral("SWAP"), pDev});
                } else {
                    ok = runCmd(QStringLiteral("mkfs.ext4"), {QStringLiteral("-F"), QStringLiteral("-L"), (mPoint == QStringLiteral("/")) ? QStringLiteral("INTI") : QStringLiteral("DATA"), pDev});
                }
                if (!ok)
                    return fail(QStringLiteral("No se pudo formatear ") + pDev + QStringLiteral(" (") + mPoint + QStringLiteral(")"));
            }
        } else {
            if (isUefi && !efiDev.isEmpty()) {
                if (!runCmd(QStringLiteral("mkfs.fat"), {QStringLiteral("-F32"), efiDev}))
                    return fail(QStringLiteral("No se pudo formatear la partición EFI ") + efiDev);
            }
            const bool rootOk = (fsType == QStringLiteral("btrfs"))
                ? runCmd(QStringLiteral("mkfs.btrfs"), {QStringLiteral("-f"), QStringLiteral("-L"), QStringLiteral("INTI"), rootDev})
                : runCmd(QStringLiteral("mkfs.ext4"), {QStringLiteral("-F"), QStringLiteral("-L"), QStringLiteral("INTI"), rootDev});
            if (!rootOk)
                return fail(QStringLiteral("No se pudo formatear la partición raíz ") + rootDev);
        }

        emit progress(30, QStringLiteral("Montando sistema de archivos raíz..."));
        QDir().mkpath(QStringLiteral("/mnt"));
        if (!runCmd(QStringLiteral("mount"), {rootDev, QStringLiteral("/mnt")}))
            return fail(QStringLiteral("No se pudo montar la partición raíz ") + rootDev);

        emit progress(40, QStringLiteral("Copiando el sistema operativo al disco..."));
        {
            // Es el paso largo (varios GB). Con --info=progress2 rsync dice el
            // porcentaje total, y aqui se reparte entre el 40 y el 65 de la
            // barra; antes la barra se quedaba quieta en el 40 durante minutos.
            QProcess rs;
            rs.start(QStringLiteral("rsync"), {
                QStringLiteral("-aAXH"),
                QStringLiteral("--info=progress2"),
                QStringLiteral("--no-inc-recursive"),
                QStringLiteral("--exclude=/mnt"),
                QStringLiteral("--exclude=/proc"),
                QStringLiteral("--exclude=/sys"),
                QStringLiteral("--exclude=/dev"),
                QStringLiteral("--exclude=/run"),
                QStringLiteral("--exclude=/tmp"),
                QStringLiteral("--exclude=/home/titan/.cache"),
                QStringLiteral("/"),
                QStringLiteral("/mnt")
            });
            if (!rs.waitForStarted(15000)) {
                lastError = QStringLiteral("rsync: no se ha podido ejecutar (%1)").arg(rs.errorString());
                return fail(QStringLiteral("No se pudo copiar el sistema al disco"));
            }
            static const QRegularExpression rePct(QStringLiteral("(\\d+)%"));
            int lastPct = -1;
            QByteArray errBuf;
            while (!rs.waitForFinished(500)) {
                const QString out = QString::fromUtf8(rs.readAllStandardOutput());
                errBuf += rs.readAllStandardError();
                auto it = rePct.globalMatch(out);
                int pct = -1;
                while (it.hasNext())
                    pct = it.next().captured(1).toInt();
                if (pct >= 0 && pct != lastPct) {
                    lastPct = pct;
                    emit progress(40 + pct * 25 / 100,
                                  QStringLiteral("Copiando el sistema operativo al disco... %1%").arg(pct));
                }
            }
            errBuf += rs.readAllStandardError();
            // 24 = "algunos ficheros desaparecieron durante la copia", normal
            // en un sistema vivo (logs, sockets). 23 = algun fichero no se pudo
            // copiar: se da por bueno solo si lo esencial esta (se mira abajo).
            const int code = (rs.exitStatus() == QProcess::NormalExit) ? rs.exitCode() : -1;
            if (code != 0 && code != 23 && code != 24) {
                const QStringList lines = QString::fromUtf8(errBuf).trimmed().split(QLatin1Char('\n'));
                lastError = QStringLiteral("rsync (codigo %1): %2")
                                .arg(code)
                                .arg(lines.mid(qMax(0, int(lines.size()) - 3)).join(QLatin1Char('\n')));
                return fail(QStringLiteral("No se pudo copiar el sistema al disco"));
            }
            if (code != 0)
                qWarning() << "rsync terminó con código" << code << QString::fromUtf8(errBuf).right(2000);
            for (const char *esencial : {"/mnt/usr/bin/bash", "/mnt/usr/lib/os-release", "/mnt/etc/passwd", "/mnt/usr/lib/systemd/systemd"}) {
                if (!QFile::exists(QString::fromLatin1(esencial))) {
                    lastError = QStringLiteral("rsync (codigo %1): falta %2 en el disco de destino")
                                    .arg(code).arg(QString::fromLatin1(esencial));
                    return fail(QStringLiteral("La copia del sistema está incompleta"));
                }
            }
        }

        // Crear directorios esenciales excluidos por rsync con sus permisos correctos
        QDir().mkpath(QStringLiteral("/mnt/tmp"));
        QDir().mkpath(QStringLiteral("/mnt/proc"));
        QDir().mkpath(QStringLiteral("/mnt/sys"));
        QDir().mkpath(QStringLiteral("/mnt/dev"));
        QDir().mkpath(QStringLiteral("/mnt/run"));
        runCmd(QStringLiteral("chmod"), {QStringLiteral("1777"), QStringLiteral("/mnt/tmp")});
        runCmd(QStringLiteral("chmod"), {QStringLiteral("0755"), QStringLiteral("/mnt/run")});
        runCmd(QStringLiteral("chmod"), {QStringLiteral("0755"), QStringLiteral("/mnt/dev")});

        emit progress(65, QStringLiteral("Desplegando kernel en el sistema..."));
        QDir().mkpath(QStringLiteral("/mnt/boot"));

        // En Archiso, los kernels se almacenan fuera de la imagen airootfs
        // en el medio de arranque live (titan/boot/x86_64). Los copiamos a /boot.
        // NOTA: NO copiamos initramfs* del live porque contienen los hooks de CD en vivo (archiso).
        QStringList kernelSearchDirs = {
            QStringLiteral("/run/archiso/bootmnt/titan/boot/x86_64"),
            QStringLiteral("/run/archiso/bootmnt/solaris/boot/x86_64"),
            QStringLiteral("/run/archiso/bootmnt/boot/x86_64"),
            QStringLiteral("/run/archiso/bootmnt/boot"),
            QStringLiteral("/boot")
        };
        for (const QString &kDir : kernelSearchDirs) {
            QDir kd(kDir);
            if (kd.exists()) {
                const auto kFiles = kd.entryList({QStringLiteral("vmlinuz*")}, QDir::Files);
                for (const QString &kFile : kFiles) {
                    runCmd(QStringLiteral("cp"), {QStringLiteral("-af"), kd.absoluteFilePath(kFile), QStringLiteral("/mnt/boot/")});
                }
            }
        }

        if (QDir(QStringLiteral("/mnt/boot")).entryList({QStringLiteral("vmlinuz*")}, QDir::Files).isEmpty()) {
            lastError.clear();
            return fail(QStringLiteral("No se ha encontrado ningún kernel (vmlinuz) en el medio de instalación"));
        }

        // Si existe un paquete de kernel propio en /titan-repo, asegurarse de que quede registrado
        QDir repoDir(QStringLiteral("/titan-repo"));
        if (repoDir.exists()) {
            const auto pkgs = repoDir.entryList({QStringLiteral("linux-titanlinux-*.pkg.tar.zst")}, QDir::Files);
            if (!pkgs.isEmpty()) {
                QString hostPkg = repoDir.absoluteFilePath(pkgs.first());
                QString pkgName = pkgs.first();
                QDir().mkpath(QStringLiteral("/mnt/var/cache/pacman/pkg"));
                runCmd(QStringLiteral("cp"), {QStringLiteral("-f"), hostPkg, QStringLiteral("/mnt/var/cache/pacman/pkg/") + pkgName});
                runCmd(QStringLiteral("arch-chroot"), {QStringLiteral("/mnt"), QStringLiteral("pacman"), QStringLiteral("-U"), QStringLiteral("--noconfirm"), QStringLiteral("--needed"), QStringLiteral("/var/cache/pacman/pkg/") + pkgName});
            }
        }

        // Montar partición EFI y otros puntos de montaje antes de fstab y chroot
        if (isUefi) {
            QString targetEfi = efiDev.isEmpty() ? mountToDev.value(QStringLiteral("/boot/efi")) : efiDev;
            if (!targetEfi.isEmpty()) {
                emit progress(70, QStringLiteral("Montando partición EFI de arranque..."));
                QDir().mkpath(QStringLiteral("/mnt/boot/efi"));
                if (!runCmd(QStringLiteral("mount"), {targetEfi, QStringLiteral("/mnt/boot/efi")}))
                    return fail(QStringLiteral("No se pudo montar la partición EFI ") + targetEfi);
            }
        }

        // Montar puntos de montaje secundarios (ej. /home)
        for (auto it = mountToDev.begin(); it != mountToDev.end(); ++it) {
            QString mPoint = it.key();
            QString dev = it.value();
            if (mPoint == QStringLiteral("/") || mPoint == QStringLiteral("/boot/efi")) continue;
            if (mPoint == QStringLiteral("swap")) {
                runCmd(QStringLiteral("swapon"), {dev});
            } else if (mPoint.startsWith(QLatin1Char('/'))) {
                QDir().mkpath(QStringLiteral("/mnt") + mPoint);
                runCmd(QStringLiteral("mount"), {dev, QStringLiteral("/mnt") + mPoint});
            }
        }

        emit progress(75, QStringLiteral("Generando tabla de particiones fstab..."));
        QDir().mkpath(QStringLiteral("/mnt/etc"));
        QProcess genfstabProc;
        genfstabProc.start(QStringLiteral("genfstab"), {QStringLiteral("-U"), QStringLiteral("/mnt")});
        genfstabProc.waitForFinished(15000);
        QByteArray fstabData = genfstabProc.readAllStandardOutput();
        if (!fstabData.isEmpty()) {
            QFile fstabFile(QStringLiteral("/mnt/etc/fstab"));
            if (fstabFile.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
                fstabFile.write(fstabData);
                fstabFile.close();
            }
        }

        emit progress(80, QStringLiteral("Configurando usuario, hostname y región..."));
        // Hostname
        {
            QFile hFile(QStringLiteral("/mnt/etc/hostname"));
            if (hFile.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
                hFile.write((hostname.isEmpty() ? QStringLiteral("inti") : hostname).toUtf8() + "\n");
                hFile.close();
            }
        }

        // Zona horaria
        if (!timezone.isEmpty()) {
            QString tzPath = QStringLiteral("/usr/share/zoneinfo/") + timezone;
            runCmd(QStringLiteral("arch-chroot"), {QStringLiteral("/mnt"), QStringLiteral("ln"), QStringLiteral("-sf"), tzPath, QStringLiteral("/etc/localtime")});
        }

        // Idioma y consola
        {
            QFile lFile(QStringLiteral("/mnt/etc/locale.conf"));
            if (lFile.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
                lFile.write("LANG=es_ES.UTF-8\nLC_COLLATE=C\n");
                lFile.close();
            }
            QFile vFile(QStringLiteral("/mnt/etc/vconsole.conf"));
            if (vFile.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
                QString km = keymap.isEmpty() ? QStringLiteral("es") : keymap;
                vFile.write("KEYMAP=" + km.toUtf8() + "\n");
                vFile.close();
            }
        }

        // --- Lo que es solo del live -----------------------------------------
        // rsync copia el live tal cual, y el live trae un usuario 'titan' con
        // contrasena 1234, sudo SIN contrasena y entrada automatica en tty1 y en
        // el puerto serie. Nada de eso puede quedarse en un sistema instalado.
        {
            QFile pw(QStringLiteral("/mnt/etc/passwd"));
            if (pw.open(QIODevice::ReadOnly | QIODevice::Text)) {
                const bool hasLiveUser = QString::fromUtf8(pw.readAll()).contains(QRegularExpression(QStringLiteral("(^|\\n)titan:")));
                pw.close();
                if (hasLiveUser && !runCmd(QStringLiteral("arch-chroot"), {QStringLiteral("/mnt"), QStringLiteral("userdel"), QStringLiteral("-f"), QStringLiteral("-r"), QStringLiteral("titan")})) {
                    // '-f' porque el usuario del live es el que tiene la sesion
                    // abierta ahora mismo, y arch-chroot monta el /proc de
                    // verdad: sin '-f' userdel se niega. Y devuelve 12 si no
                    // puede borrar el buzon, que el live no tiene; lo que
                    // importa es que la cuenta se vaya, y eso se mira aqui.
                    QFile pw2(QStringLiteral("/mnt/etc/passwd"));
                    if (pw2.open(QIODevice::ReadOnly | QIODevice::Text) &&
                        QString::fromUtf8(pw2.readAll()).contains(QRegularExpression(QStringLiteral("(^|\\n)titan:"))))
                        return fail(QStringLiteral("No se pudo quitar el usuario del live (titan) del sistema instalado"));
                }
            }
            QDir(QStringLiteral("/mnt/home/titan")).removeRecursively();
            QFile::remove(QStringLiteral("/mnt/etc/sudoers.d/10-titan"));
            QFile::remove(QStringLiteral("/mnt/etc/sudoers.d/20-calamares"));
            QDir(QStringLiteral("/mnt/etc/systemd/system/serial-getty@ttyS0.service.d")).removeRecursively();
            QDir(QStringLiteral("/mnt/etc/systemd/system/getty@tty1.service.d")).removeRecursively();
            // Cada instalacion tiene que tener su propio machine-id. Vacio, systemd
            // genera uno nuevo en el primer arranque.
            QFile mid(QStringLiteral("/mnt/etc/machine-id"));
            if (mid.open(QIODevice::WriteOnly | QIODevice::Truncate))
                mid.close();
        }

        // Creación del usuario. Solo con los grupos que existen en el sistema:
        // con uno que no existe, useradd no crea la cuenta y el sistema se
        // quedaba sin usuario.
        const QString user = userName.trimmed();
        QStringList groups;
        {
            QFile gf(QStringLiteral("/mnt/etc/group"));
            QString content;
            if (gf.open(QIODevice::ReadOnly | QIODevice::Text))
                content = QString::fromUtf8(gf.readAll());
            for (const QString &g : {QStringLiteral("wheel"), QStringLiteral("audio"), QStringLiteral("video"),
                                     QStringLiteral("storage"), QStringLiteral("input"), QStringLiteral("render"),
                                     QStringLiteral("network"), QStringLiteral("power")}) {
                if (content.contains(QRegularExpression(QStringLiteral("(^|\\n)") + g + QStringLiteral(":"))))
                    groups << g;
            }
        }
        if (!groups.contains(QStringLiteral("wheel"))) {
            lastError.clear();
            return fail(QStringLiteral("El sistema copiado no tiene el grupo 'wheel'"));
        }
        QStringList uaArgs = {QStringLiteral("/mnt"), QStringLiteral("useradd"), QStringLiteral("-m"),
                              QStringLiteral("-G"), groups.join(QLatin1Char(',')),
                              QStringLiteral("-s"), QStringLiteral("/bin/bash")};
        if (!fullName.trimmed().isEmpty())
            uaArgs << QStringLiteral("-c") << fullName.trimmed().remove(QLatin1Char(':'));
        uaArgs << user;
        if (!runCmd(QStringLiteral("arch-chroot"), uaArgs))
            return fail(QStringLiteral("No se pudo crear el usuario ") + user);

        // Contraseñas
        {
            QProcess pCh;
            pCh.start(QStringLiteral("arch-chroot"), {QStringLiteral("/mnt"), QStringLiteral("chpasswd")});
            if (!pCh.waitForStarted(15000)) {
                lastError = pCh.errorString();
                return fail(QStringLiteral("No se pudo poner la contraseña"));
            }
            pCh.write(QStringLiteral("%1:%2\nroot:%2\n").arg(user, password).toUtf8());
            pCh.closeWriteChannel();
            pCh.waitForFinished(-1);
            if (pCh.exitStatus() != QProcess::NormalExit || pCh.exitCode() != 0) {
                lastError = QString::fromUtf8(pCh.readAllStandardError()).trimmed();
                return fail(QStringLiteral("No se pudo poner la contraseña"));
            }
        }

        // Inicio de sesión automático: la sesión gráfica la arranca
        // /etc/profile.d/15-titan-grafico.sh al entrar en tty1, así que basta
        // con que agetty entre solo con el usuario nuevo.
        //
        // Es SOLO para el primer arranque: un servicio de un solo uso borra el
        // drop-in (y a sí mismo) en ese arranque. systemd ya ha leído la
        // configuración de getty@tty1 al arrancar, así que borrar el fichero no
        // le afecta hasta el siguiente arranque, que ya pide contraseña. No se
        // usa 'systemctl disable' porque recarga systemd y podría quitar el
        // autologin antes de que tty1 llegue a usarlo.
        // Inicio de sesion grafico multiusuario: greetd con la pantalla de
        // inicio de Inti OS (titan-greeter). Muestra todas las cuentas y deja
        // que un administrador cree usuarios y grupos (titan-usuarios.socket).
        // Si la copia no trae greetd o el greeter, se queda la entrada por tty1.
        const bool usarGreetd = QFile::exists(QStringLiteral("/mnt/usr/bin/greetd")) &&
                                QFile::exists(QStringLiteral("/mnt/usr/local/bin/titan-greeter")) &&
                                QFile::exists(QStringLiteral("/mnt/etc/greetd/config.toml"));
        if (usarGreetd) {
            const QString sysd = QStringLiteral("/mnt/etc/systemd/system");
            QDir().mkpath(sysd + QStringLiteral("/sockets.target.wants"));
            const QString dm = sysd + QStringLiteral("/display-manager.service");
            QFile::remove(dm);
            bool ok = QFile::link(QStringLiteral("/usr/lib/systemd/system/greetd.service"), dm);
            const QString sock = sysd + QStringLiteral("/sockets.target.wants/titan-usuarios.socket");
            QFile::remove(sock);
            if (QFile::exists(sysd + QStringLiteral("/titan-usuarios.socket")))
                QFile::link(QStringLiteral("/etc/systemd/system/titan-usuarios.socket"), sock);
            if (!ok)
                qWarning() << "No se pudo activar greetd; el sistema entrara por tty1.";

            // Primer arranque sin contrasena: [initial_session] de greetd, que
            // un servicio de un solo uso quita en ese mismo arranque.
            if (ok && autoLogin) {
                QFile cfg(QStringLiteral("/mnt/etc/greetd/config.toml"));
                QFile once(sysd + QStringLiteral("/inti-autologin-unavez.service"));
                bool okAuto = cfg.open(QIODevice::Append | QIODevice::Text) &&
                              cfg.write(QStringLiteral("\n# Solo el primer arranque (lo quita inti-autologin-unavez.service).\n"
                                                       "[initial_session]\n"
                                                       "command = \"/usr/lib/titan/titan-arranque-grafico\"\n"
                                                       "user = \"%1\"\n").arg(user).toUtf8()) > 0;
                cfg.close();
                okAuto = okAuto && once.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text) &&
                         once.write("[Unit]\n"
                                    "Description=Inti OS: inicio de sesion automatico solo en el primer arranque\n"
                                    "After=greetd.service\n\n"
                                    "[Service]\n"
                                    "Type=oneshot\n"
                                    "ExecStart=/usr/bin/sed -i -e '/^# Solo el primer arranque/,$d' /etc/greetd/config.toml\n"
                                    "ExecStart=/usr/bin/rm -f /etc/systemd/system/multi-user.target.wants/inti-autologin-unavez.service"
                                    " /etc/systemd/system/inti-autologin-unavez.service\n\n"
                                    "[Install]\n"
                                    "WantedBy=multi-user.target\n") > 0;
                once.close();
                QDir().mkpath(sysd + QStringLiteral("/multi-user.target.wants"));
                const QString link = sysd + QStringLiteral("/multi-user.target.wants/inti-autologin-unavez.service");
                QFile::remove(link);
                okAuto = okAuto && QFile::link(QStringLiteral("/etc/systemd/system/inti-autologin-unavez.service"), link);
                if (!okAuto) {
                    // Sin el servicio que lo quita, la entrada automatica se
                    // quedaria para siempre: se deshace.
                    runCmd(QStringLiteral("sed"), {QStringLiteral("-i"), QStringLiteral("-e"),
                                                   QStringLiteral("/^# Solo el primer arranque/,$d"),
                                                   QStringLiteral("/mnt/etc/greetd/config.toml")});
                    QFile::remove(sysd + QStringLiteral("/inti-autologin-unavez.service"));
                    QFile::remove(link);
                    qWarning() << "No se pudo preparar el inicio de sesion automatico de un solo uso; se omite.";
                }
            }
        }

        if (autoLogin && !usarGreetd) {
            const QString sysd = QStringLiteral("/mnt/etc/systemd/system");
            QDir().mkpath(sysd + QStringLiteral("/getty@tty1.service.d"));
            QDir().mkpath(sysd + QStringLiteral("/multi-user.target.wants"));
            QFile al(sysd + QStringLiteral("/getty@tty1.service.d/10-autologin.conf"));
            QFile once(sysd + QStringLiteral("/inti-autologin-unavez.service"));
            bool ok = al.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text) &&
                      al.write(QStringLiteral("[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin %1 --noclear %I linux\nType=idle\n")
                                   .arg(user).toUtf8()) > 0;
            al.close();
            ok = ok && once.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text) &&
                 once.write("[Unit]\n"
                            "Description=Inti OS: inicio de sesion automatico solo en el primer arranque\n"
                            "After=getty@tty1.service\n\n"
                            "[Service]\n"
                            "Type=oneshot\n"
                            "ExecStart=/usr/bin/rm -f /etc/systemd/system/getty@tty1.service.d/10-autologin.conf"
                            " /etc/systemd/system/multi-user.target.wants/inti-autologin-unavez.service"
                            " /etc/systemd/system/inti-autologin-unavez.service\n\n"
                            "[Install]\n"
                            "WantedBy=multi-user.target\n") > 0;
            once.close();
            const QString link = sysd + QStringLiteral("/multi-user.target.wants/inti-autologin-unavez.service");
            QFile::remove(link);
            ok = ok && QFile::link(QStringLiteral("/etc/systemd/system/inti-autologin-unavez.service"), link);
            if (!ok) {
                // Sin el servicio de un solo uso el autologin se quedaría para
                // siempre: mejor no dejarlo.
                QFile::remove(sysd + QStringLiteral("/getty@tty1.service.d/10-autologin.conf"));
                QFile::remove(sysd + QStringLiteral("/inti-autologin-unavez.service"));
                QFile::remove(link);
                qWarning() << "No se pudo preparar el inicio de sesión automático de un solo uso; se omite.";
            }
        }

        // Sudoers
        {
            QDir().mkpath(QStringLiteral("/mnt/etc/sudoers.d"));
            QFile sFile(QStringLiteral("/mnt/etc/sudoers.d/10-admin"));
            if (sFile.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
                sFile.write("%wheel ALL=(ALL:ALL) ALL\nDefaults lecture = never\n");
                sFile.close();
                runCmd(QStringLiteral("chmod"), {QStringLiteral("0440"), QStringLiteral("/mnt/etc/sudoers.d/10-admin")});
            }
        }

        // Configuración de /etc/default/grub para el sistema instalado
        {
            QFile gDef(QStringLiteral("/mnt/etc/default/grub"));
            if (gDef.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
                gDef.write("GRUB_DEFAULT=0\n"
                           "GRUB_TIMEOUT=5\n"
                           "GRUB_DISTRIBUTOR=\"Inti OS\"\n"
                           "GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet\"\n"
                           "GRUB_CMDLINE_LINUX=\"console=tty0 console=ttyS0,115200n8\"\n"
                           "GRUB_DISABLE_SUBMENU=y\n"
                           "GRUB_TERMINAL_OUTPUT=\"gfxterm console\"\n"
                           "GRUB_GFXMODE=auto\n");
                gDef.close();
            }
        }

        // Configuración de mkinitcpio para el sistema instalado
        // 1. Eliminar cualquier residuo de archiso en mkinitcpio.conf.d
        QDir(QStringLiteral("/mnt/etc/mkinitcpio.conf.d")).removeRecursively();

        // 2. Escribir configuración estándar de mkinitcpio para disco local
        {
            QFile mkConf(QStringLiteral("/mnt/etc/mkinitcpio.conf"));
            if (mkConf.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
                mkConf.write(
                    "MODULES=(virtio_blk virtio_pci virtio_net virtio_scsi ahci nvme ext4 btrfs vfat xfs)\n"
                    "BINARIES=()\n"
                    "FILES=()\n"
                    "HOOKS=(base udev modconf kms keyboard keymap consolefont block filesystems fsck)\n"
                    "COMPRESSION=\"zstd\"\n"
                );
                mkConf.close();
            }
        }

        // 3. Configurar presets para compilar initramfs para cada kernel instalado
        QDir().mkpath(QStringLiteral("/mnt/etc/mkinitcpio.d"));
        if (QFile::exists(QStringLiteral("/mnt/boot/vmlinuz-linux-titanlinux"))) {
            QFile pre(QStringLiteral("/mnt/etc/mkinitcpio.d/linux-titanlinux.preset"));
            if (pre.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
                pre.write(
                    "ALL_config=\"/etc/mkinitcpio.conf\"\n"
                    "ALL_kver=\"/boot/vmlinuz-linux-titanlinux\"\n"
                    "PRESETS=('titan_default')\n"
                    "titan_default_kver=\"/boot/vmlinuz-linux-titanlinux\"\n"
                    "titan_default_config=\"/etc/mkinitcpio.conf\"\n"
                    "titan_default_image=\"/boot/initramfs-linux-titanlinux.img\"\n"
                );
                pre.close();
            }
        }
        if (QFile::exists(QStringLiteral("/mnt/boot/vmlinuz-linux"))) {
            QFile pre(QStringLiteral("/mnt/etc/mkinitcpio.d/linux.preset"));
            if (pre.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
                pre.write(
                    "ALL_config=\"/etc/mkinitcpio.conf\"\n"
                    "ALL_kver=\"/boot/vmlinuz-linux\"\n"
                    "PRESETS=('default')\n"
                    "default_kver=\"/boot/vmlinuz-linux\"\n"
                    "default_config=\"/etc/mkinitcpio.conf\"\n"
                    "default_image=\"/boot/initramfs-linux.img\"\n"
                );
                pre.close();
            }
        }

        emit progress(88, QStringLiteral("Compilando initramfs para el hardware local..."));
        // Compilación directa y garantizada para cada kernel sin depender exclusivamente de presets
        if (QFile::exists(QStringLiteral("/mnt/boot/vmlinuz-linux-titanlinux"))) {
            runCmd(QStringLiteral("arch-chroot"), {
                QStringLiteral("/mnt"),
                QStringLiteral("mkinitcpio"),
                QStringLiteral("-k"), QStringLiteral("/boot/vmlinuz-linux-titanlinux"),
                QStringLiteral("-c"), QStringLiteral("/etc/mkinitcpio.conf"),
                QStringLiteral("-g"), QStringLiteral("/boot/initramfs-linux-titanlinux.img")
            });
        }
        if (QFile::exists(QStringLiteral("/mnt/boot/vmlinuz-linux"))) {
            runCmd(QStringLiteral("arch-chroot"), {
                QStringLiteral("/mnt"),
                QStringLiteral("mkinitcpio"),
                QStringLiteral("-k"), QStringLiteral("/boot/vmlinuz-linux"),
                QStringLiteral("-c"), QStringLiteral("/etc/mkinitcpio.conf"),
                QStringLiteral("-g"), QStringLiteral("/boot/initramfs-linux.img")
            });
        }
        runCmd(QStringLiteral("arch-chroot"), {QStringLiteral("/mnt"), QStringLiteral("mkinitcpio"), QStringLiteral("-P")});

        // Resolver UUID del dispositivo raíz con udev settle y fallback al dev node
        runCmd(QStringLiteral("udevadm"), {QStringLiteral("settle")});
        QProcess blkProc;
        blkProc.start(QStringLiteral("lsblk"), {QStringLiteral("-no"), QStringLiteral("UUID"), rootDev});
        blkProc.waitForFinished(5000);
        QString rUuid = QString::fromUtf8(blkProc.readAllStandardOutput()).trimmed();
        if (rUuid.isEmpty()) {
            blkProc.start(QStringLiteral("blkid"), {QStringLiteral("-c"), QStringLiteral("/dev/null"), QStringLiteral("-s"), QStringLiteral("UUID"), QStringLiteral("-o"), QStringLiteral("value"), rootDev});
            blkProc.waitForFinished(5000);
            rUuid = QString::fromUtf8(blkProc.readAllStandardOutput()).trimmed();
        }
        QString rootParam = !rUuid.isEmpty() ? (QStringLiteral("root=UUID=") + rUuid) : (QStringLiteral("root=") + rootDev);

        // Identificar pares coherentes (kernel, initramfs)
        struct BootEntry {
            QString title;
            QString kernel;
            QString initrd;
        };
        QList<BootEntry> entries;

        if (QFile::exists(QStringLiteral("/mnt/boot/vmlinuz-linux-titanlinux")) &&
            (QFile::exists(QStringLiteral("/mnt/boot/initramfs-linux-titanlinux.img")) ||
             QFile::exists(QStringLiteral("/mnt/boot/initramfs-linux-titanlinux-fallback.img")))) {
            QString iName = QFile::exists(QStringLiteral("/mnt/boot/initramfs-linux-titanlinux.img"))
                ? QStringLiteral("initramfs-linux-titanlinux.img")
                : QStringLiteral("initramfs-linux-titanlinux-fallback.img");
            entries.append({QStringLiteral("Inti OS"), QStringLiteral("vmlinuz-linux-titanlinux"), iName});
        }
        if (QFile::exists(QStringLiteral("/mnt/boot/vmlinuz-linux")) &&
            (QFile::exists(QStringLiteral("/mnt/boot/initramfs-linux.img")) ||
             QFile::exists(QStringLiteral("/mnt/boot/initramfs-linux-fallback.img")))) {
            QString iName = QFile::exists(QStringLiteral("/mnt/boot/initramfs-linux.img"))
                ? QStringLiteral("initramfs-linux.img")
                : QStringLiteral("initramfs-linux-fallback.img");
            QString t = entries.isEmpty() ? QStringLiteral("Inti OS") : QStringLiteral("Inti OS (Kernel de Rescate)");
            entries.append({t, QStringLiteral("vmlinuz-linux"), iName});
        }
        if (entries.isEmpty()) {
            QDir bDir(QStringLiteral("/mnt/boot"));
            const auto kList = bDir.entryList({QStringLiteral("vmlinuz*")}, QDir::Files);
            for (const QString &k : kList) {
                QString flavor = k;
                flavor.remove(QStringLiteral("vmlinuz-"));
                QString matchingInit = QStringLiteral("initramfs-") + flavor + QStringLiteral(".img");
                if (bDir.exists(matchingInit)) {
                    entries.append({QStringLiteral("Inti OS (") + flavor + QStringLiteral(")"), k, matchingInit});
                }
            }
            if (entries.isEmpty()) {
                // Sin initramfs el sistema no arranca: mejor decirlo ahora que
                // dejar una entrada de GRUB que apunta a un fichero que no existe.
                return fail(QStringLiteral("No se pudo generar el initramfs del kernel (mkinitcpio)"));
            }
        }

        emit progress(92, QStringLiteral("Instalando cargador de arranque GRUB y EFI..."));
        // Asegurar que los módulos de GRUB estén en /boot/grub/x86_64-efi/ para comandos como ls, normal, etc.
        QDir().mkpath(QStringLiteral("/mnt/boot/grub/x86_64-efi"));
        runCmd(QStringLiteral("cp"), {QStringLiteral("-rf"), QStringLiteral("/usr/lib/grub/x86_64-efi/"), QStringLiteral("/mnt/boot/grub/")});

        // Construir bloque de entradas para grub
        QString menuEntriesBlock;
        for (const auto &e : entries) {
            menuEntriesBlock += QStringLiteral(
                "menuentry \"%1\" {\n"
                "    insmod part_gpt\n"
                "    insmod part_msdos\n"
                "    insmod ext2\n"
                "    insmod btrfs\n"
                "    insmod xfs\n"
                "    search --no-floppy --file /etc/os-release --set=root\n"
                "    linux /boot/%2 %3 rw loglevel=3 quiet console=tty0 console=ttyS0,115200n8\n"
                "    initrd /boot/%4\n"
                "}\n\n"
            ).arg(e.title, e.kernel, rootParam, e.initrd);
        }

        if (isUefi) {
            runCmd(QStringLiteral("arch-chroot"), {
                QStringLiteral("/mnt"),
                QStringLiteral("grub-install"),
                QStringLiteral("--target=x86_64-efi"),
                QStringLiteral("--efi-directory=/boot/efi"),
                QStringLiteral("--bootloader-id=IntiOS"),
                QStringLiteral("--removable"),
                QStringLiteral("--no-nvram"),
                QStringLiteral("--recheck")
            });

            QDir().mkpath(QStringLiteral("/mnt/boot/efi/EFI/BOOT"));
            QDir().mkpath(QStringLiteral("/mnt/boot/efi/EFI/IntiOS"));

            // Respaldar kernel e initramfs en la partición EFI para garantizar arranque directo bajo cualquier firmware
            for (const auto &e : entries) {
                if (QFile::exists(QStringLiteral("/mnt/boot/") + e.kernel)) {
                    runCmd(QStringLiteral("cp"), {QStringLiteral("-f"), QStringLiteral("/mnt/boot/") + e.kernel, QStringLiteral("/mnt/boot/efi/EFI/BOOT/") + e.kernel});
                }
                if (QFile::exists(QStringLiteral("/mnt/boot/") + e.initrd)) {
                    runCmd(QStringLiteral("cp"), {QStringLiteral("-f"), QStringLiteral("/mnt/boot/") + e.initrd, QStringLiteral("/mnt/boot/efi/EFI/BOOT/") + e.initrd});
                }
            }

            // Configuración directa y autónoma de arranque en la partición EFI (/EFI/BOOT/grub.cfg)
            {
                QFile espCfg(QStringLiteral("/mnt/boot/efi/EFI/BOOT/grub.cfg"));
                if (espCfg.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
                    QString espContent = QStringLiteral(
                        "set default=0\n"
                        "set timeout=5\n"
                        "insmod part_gpt\n"
                        "insmod part_msdos\n"
                        "insmod ext2\n"
                        "insmod btrfs\n"
                        "insmod xfs\n"
                        "insmod fat\n"
                        "insmod all_video\n"
                        "insmod gfxterm\n"
                        "terminal_output gfxterm console\n\n"
                    ) + menuEntriesBlock;
                    espCfg.write(espContent.toUtf8());
                    espCfg.close();
                }
            }

            // Crear configuración de búsqueda de raíz temprana para el standalone EFI
            {
                QFile earlyCfg(QStringLiteral("/mnt/boot/efi/early-grub.cfg"));
                if (earlyCfg.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
                    earlyCfg.write(
                        "insmod part_gpt\n"
                        "insmod part_msdos\n"
                        "insmod fat\n"
                        "insmod ext2\n"
                        "insmod btrfs\n"
                        "insmod xfs\n"
                        "insmod all_video\n"
                        "insmod gfxterm\n"
                        "search --no-floppy --file /EFI/BOOT/grub.cfg --set=efipart\n"
                        "if [ -n \"$efipart\" ]; then\n"
                        "    set root=$efipart\n"
                        "    set prefix=($efipart)/EFI/BOOT\n"
                        "    configfile ($efipart)/EFI/BOOT/grub.cfg\n"
                        "fi\n"
                        "search --no-floppy --set=sysroot --file /etc/os-release\n"
                        "if [ -n \"$sysroot\" ]; then\n"
                        "    set root=$sysroot\n"
                        "    set prefix=($root)/boot/grub\n"
                        "    if [ -f ($root)/boot/grub/grub.cfg ]; then\n"
                        "        configfile ($root)/boot/grub/grub.cfg\n"
                        "    fi\n"
                        "fi\n"
                    );
                    earlyCfg.close();
                }
            }

            // Generar siempre el ejecutable autónomo para asegurar que BOOTX64.EFI existe y funciona 100%
            runCmd(QStringLiteral("arch-chroot"), {
                QStringLiteral("/mnt"),
                QStringLiteral("grub-mkstandalone"),
                QStringLiteral("-O"),
                QStringLiteral("x86_64-efi"),
                QStringLiteral("-o"),
                QStringLiteral("/boot/efi/EFI/BOOT/BOOTX64.EFI"),
                QStringLiteral("--modules=part_gpt part_msdos fat ext2 btrfs xfs search search_fs_uuid search_fs_file search_label configfile normal linux echo test gfxterm all_video font loadenv reboot"),
                QStringLiteral("boot/grub/grub.cfg=/boot/efi/early-grub.cfg")
            });

            if (!QFile::exists(QStringLiteral("/mnt/boot/efi/EFI/BOOT/BOOTX64.EFI")) || QFile(QStringLiteral("/mnt/boot/efi/EFI/BOOT/BOOTX64.EFI")).size() < 1000) {
                runCmd(QStringLiteral("grub-mkstandalone"), {
                    QStringLiteral("-O"),
                    QStringLiteral("x86_64-efi"),
                    QStringLiteral("-o"),
                    QStringLiteral("/mnt/boot/efi/EFI/BOOT/BOOTX64.EFI"),
                    QStringLiteral("--modules=part_gpt part_msdos fat ext2 btrfs xfs search search_fs_uuid search_fs_file search_label configfile normal linux echo test gfxterm all_video font loadenv reboot"),
                    QStringLiteral("boot/grub/grub.cfg=/mnt/boot/efi/early-grub.cfg")
                });
            }

            if (QFile(QStringLiteral("/mnt/boot/efi/EFI/BOOT/BOOTX64.EFI")).size() < 1000)
                return fail(QStringLiteral("No se pudo instalar el cargador de arranque UEFI (BOOTX64.EFI)"));

            runCmd(QStringLiteral("cp"), {QStringLiteral("-f"), QStringLiteral("/mnt/boot/efi/EFI/BOOT/BOOTX64.EFI"), QStringLiteral("/mnt/boot/efi/EFI/BOOT/bootx64.efi")});
            runCmd(QStringLiteral("cp"), {QStringLiteral("-f"), QStringLiteral("/mnt/boot/efi/EFI/BOOT/BOOTX64.EFI"), QStringLiteral("/mnt/boot/efi/EFI/IntiOS/grubx64.efi")});
            QFile::remove(QStringLiteral("/mnt/boot/efi/early-grub.cfg"));
        } else {
            if (!runCmd(QStringLiteral("arch-chroot"), {
                    QStringLiteral("/mnt"),
                    QStringLiteral("grub-install"),
                    QStringLiteral("--target=i386-pc"),
                    diskPath,
                    QStringLiteral("--recheck")}))
                return fail(QStringLiteral("No se pudo instalar GRUB en ") + diskPath);
        }

        emit progress(96, QStringLiteral("Generando configuración de arranque (grub.cfg)..."));
        runCmd(QStringLiteral("arch-chroot"), {
            QStringLiteral("/mnt"),
            QStringLiteral("grub-mkconfig"),
            QStringLiteral("-o"),
            QStringLiteral("/boot/grub/grub.cfg")
        });

        // Verificación y generación de respaldo para grub.cfg
        QFile gCfgFile(QStringLiteral("/mnt/boot/grub/grub.cfg"));
        bool hasMenuEntry = false;
        if (gCfgFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QString gContent = QString::fromUtf8(gCfgFile.readAll());
            hasMenuEntry = gContent.contains(QStringLiteral("menuentry"));
            gCfgFile.close();
        }

        if (!hasMenuEntry) {
            if (gCfgFile.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
                QString fallbackCfg = QStringLiteral(
                    "set default=0\n"
                    "set timeout=5\n"
                    "insmod part_gpt\n"
                    "insmod part_msdos\n"
                    "insmod ext2\n"
                    "insmod btrfs\n"
                    "insmod xfs\n"
                    "insmod fat\n"
                    "insmod all_video\n"
                    "insmod gfxterm\n"
                    "terminal_output gfxterm console\n\n"
                ) + menuEntriesBlock;
                gCfgFile.write(fallbackCfg.toUtf8());
                gCfgFile.close();
            }
        }

        if (isUefi) {
            emit progress(97, QStringLiteral("Configurando entrada UEFI del sistema como prioridad 1..."));
            QString partNum = QStringLiteral("1");
            QRegularExpression reDigits(QStringLiteral("(\\d+)$"));
            auto match = reDigits.match(efiDev);
            if (match.hasMatch()) {
                partNum = match.captured(1);
            }

            // Crear la entrada de Inti OS en el firmware
            runCmd(QStringLiteral("efibootmgr"), {
                QStringLiteral("-c"),
                QStringLiteral("-d"), diskPath,
                QStringLiteral("-p"), partNum,
                QStringLiteral("-L"), QStringLiteral("Inti OS"),
                QStringLiteral("-l"), QStringLiteral("\\EFI\\BOOT\\BOOTX64.EFI")
            });

            // Reordenar BootOrder para colocar Inti OS en la primera posición (index = 0 / prioridad 1)
            QProcess pBoot;
            pBoot.start(QStringLiteral("efibootmgr"));
            if (pBoot.waitForFinished(3000)) {
                QString out = QString::fromUtf8(pBoot.readAllStandardOutput());
                QString intiBootNum;
                const auto lines = out.split(QLatin1Char('\n'));
                for (const QString &line : lines) {
                    if (line.contains(QStringLiteral("Inti OS"), Qt::CaseInsensitive) ||
                        line.contains(QStringLiteral("Titan Linux"), Qt::CaseInsensitive)) {
                        QRegularExpression reBootNum(QStringLiteral("Boot([0-9A-Fa-f]{4})"));
                        auto m = reBootNum.match(line);
                        if (m.hasMatch()) {
                            intiBootNum = m.captured(1);
                            break;
                        }
                    }
                }

                if (!intiBootNum.isEmpty()) {
                    runCmd(QStringLiteral("efibootmgr"), {QStringLiteral("-n"), intiBootNum});

                    QString currOrder;
                    for (const QString &line : lines) {
                        if (line.startsWith(QStringLiteral("BootOrder:"))) {
                            currOrder = line.section(QLatin1Char(':'), 1).trimmed();
                            break;
                        }
                    }
                    if (!currOrder.isEmpty()) {
                        QStringList orders = currOrder.split(QLatin1Char(','), Qt::SkipEmptyParts);
                        orders.removeAll(intiBootNum);
                        orders.prepend(intiBootNum);
                        runCmd(QStringLiteral("efibootmgr"), {QStringLiteral("-o"), orders.join(QLatin1Char(','))});
                    }
                }
            }
        }

        emit progress(98, QStringLiteral("Limpiando temporales y preparando sistema instalado..."));

        // Eliminar completamente el instalador del sistema de destino para que no aparezca tras instalar
        QFile::remove(QStringLiteral("/mnt/usr/share/applications/titan-instalar.desktop"));
        QFile::remove(QStringLiteral("/mnt/usr/share/applications/calamares.desktop"));
        QFile::remove(QStringLiteral("/mnt/usr/local/bin/titan-installer"));
        QFile::remove(QStringLiteral("/mnt/usr/local/bin/instalar"));
        QFile::remove(QStringLiteral("/mnt/etc/skel/Escritorio/instalar.desktop"));
        QFile::remove(QStringLiteral("/mnt/etc/skel/Desktop/instalar.desktop"));

        QDir mntHome(QStringLiteral("/mnt/home"));
        if (mntHome.exists()) {
            const auto users = mntHome.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
            for (const QString &u : users) {
                QFile::remove(QStringLiteral("/mnt/home/") + u + QStringLiteral("/Escritorio/instalar.desktop"));
                QFile::remove(QStringLiteral("/mnt/home/") + u + QStringLiteral("/Desktop/instalar.desktop"));
            }
        }
        QFile::remove(QStringLiteral("/mnt/root/Escritorio/instalar.desktop"));
        QFile::remove(QStringLiteral("/mnt/root/Desktop/instalar.desktop"));
        QDir(QStringLiteral("/mnt/root/instalador")).removeRecursively();

        // Configuración para que Flatpak y Wayland reconozcan las aplicaciones instaladas de la tienda
        {
            QDir().mkpath(QStringLiteral("/mnt/etc/profile.d"));
            QFile xdgProfile(QStringLiteral("/mnt/etc/profile.d/05-xdg-dirs.sh"));
            if (xdgProfile.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
                xdgProfile.write(
                    "#!/bin/sh\n"
                    "export XDG_DATA_DIRS=\"/var/lib/flatpak/exports/share:${HOME}/.local/share/flatpak/exports/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}\"\n"
                );
                xdgProfile.close();
                QFile::setPermissions(QStringLiteral("/mnt/etc/profile.d/05-xdg-dirs.sh"),
                    QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner |
                    QFileDevice::ReadGroup | QFileDevice::ExeGroup |
                    QFileDevice::ReadOther | QFileDevice::ExeOther);
            }

            QFile envFile(QStringLiteral("/mnt/etc/environment"));
            if (envFile.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
                envFile.write("XDG_DATA_DIRS=/var/lib/flatpak/exports/share:/usr/local/share:/usr/share\n");
                envFile.close();
            }

            // Asegurar directorios de exportación de Flatpak
            QDir().mkpath(QStringLiteral("/mnt/var/lib/flatpak/exports/share/applications"));
            QDir().mkpath(QStringLiteral("/mnt/var/lib/flatpak/exports/share/icons"));
        }

        emit progress(99, QStringLiteral("Sincronizando almacenamiento y desmontando..."));
        runCmd(QStringLiteral("sync"));
        runCmd(QStringLiteral("umount"), {QStringLiteral("-R"), QStringLiteral("/mnt")});

        emit progress(100, QStringLiteral("¡Instalación completada con éxito!"));
        emit finished(true, QString());
    }
};

InstallerBackend::InstallerBackend(QObject *parent)
    : QObject(parent)
{
    checkSystemRequirements();
    refreshDisks();
    resetDefaultPartitions();
}

InstallerBackend::~InstallerBackend()
{
    if (m_workerThread) {
        m_workerThread->quit();
        m_workerThread->wait(3000);
        delete m_workerThread;
    }
}

void InstallerBackend::checkSystemRequirements()
{
    // Memoria RAM
    struct sysinfo si;
    if (sysinfo(&si) == 0) {
        m_ramMb = static_cast<int>(si.totalram * si.mem_unit / (1024 * 1024));
    } else {
        m_ramMb = 4096;
    }

    // Modo UEFI vs BIOS
    m_isUefi = QDir(QStringLiteral("/sys/firmware/efi")).exists();

    // Alimentación
    m_hasPower = true;
    QDir powerDir(QStringLiteral("/sys/class/power_supply"));
    if (powerDir.exists()) {
        const auto entries = powerDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QString &entry : entries) {
            if (entry.startsWith(QStringLiteral("BAT"))) {
                QFile statFile(QStringLiteral("/sys/class/power_supply/") + entry + QStringLiteral("/status"));
                if (statFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                    QString st = QString::fromUtf8(statFile.readAll()).trimmed();
                    if (st == QStringLiteral("Discharging")) {
                        QFile capFile(QStringLiteral("/sys/class/power_supply/") + entry + QStringLiteral("/capacity"));
                        if (capFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                            int cap = QString::fromUtf8(capFile.readAll()).trimmed().toInt();
                            if (cap < 20) m_hasPower = false;
                        }
                    }
                }
            }
        }
    }
}

// El disco del que ha arrancado el live (el USB o el DVD). No puede salir en la
// lista: si se elige, se borra el sistema que esta corriendo a mitad de la
// instalacion. Devuelve "" si el live no esta montado desde un disco (copytoram).
static QString liveBootDisk()
{
    QProcess pFind;
    pFind.start(QStringLiteral("findmnt"), {QStringLiteral("-no"), QStringLiteral("SOURCE"), QStringLiteral("/run/archiso/bootmnt")});
    if (!pFind.waitForFinished(3000))
        return QString();
    const QString dev = QString::fromUtf8(pFind.readAllStandardOutput()).trimmed();
    if (dev.isEmpty())
        return QString();
    QProcess pDisk;
    pDisk.start(QStringLiteral("lsblk"), {QStringLiteral("-npo"), QStringLiteral("PKNAME"), dev});
    if (!pDisk.waitForFinished(3000))
        return dev;
    const QString parent = QString::fromUtf8(pDisk.readAllStandardOutput()).trimmed().section(QLatin1Char('\n'), 0, 0);
    return parent.isEmpty() ? dev : parent;
}

void InstallerBackend::refreshDisks()
{
    m_disks.clear();

    // En JSON y no en columnas: con columnas vacias (TRAN en un disco virtio, o
    // MODEL en muchos) los campos se corrian y el modelo acababa como TRAN.
    QProcess proc;
    proc.start(QStringLiteral("lsblk"), {QStringLiteral("-Jdpb"), QStringLiteral("-o"), QStringLiteral("NAME,SIZE,TYPE,TRAN,MODEL,RO")});
    proc.waitForFinished(5000);
    const QJsonArray devices = QJsonDocument::fromJson(proc.readAllStandardOutput())
                                   .object().value(QStringLiteral("blockdevices")).toArray();
    const QString bootDisk = liveBootDisk();
    static const QRegularExpression virtualDev(QStringLiteral("^/dev/(loop|zram|ram|fd|sr)\\d"));

    for (const QJsonValue &v : devices) {
        const QJsonObject d = v.toObject();
        const QString path = d.value(QStringLiteral("name")).toString();
        if (path.isEmpty() || d.value(QStringLiteral("type")).toString() != QStringLiteral("disk"))
            continue;
        if (virtualDev.match(path).hasMatch() || path == bootDisk)
            continue;
        const QJsonValue ro = d.value(QStringLiteral("ro"));
        if (ro.toBool() || ro.toString() == QStringLiteral("1"))
            continue;
        // lsblk da el tamano como numero o como texto segun la version.
        const QJsonValue sizeVal = d.value(QStringLiteral("size"));
        const double bytes = sizeVal.isString() ? sizeVal.toString().toDouble() : sizeVal.toDouble();
        if (bytes < 8.0 * 1024 * 1024 * 1024) // menos de 8 GiB no cabe el sistema
            continue;
        const QString size = QStringLiteral("%1 GB").arg(bytes / 1e9, 0, 'f', bytes >= 100e9 ? 0 : 1);
        const QString tran = d.value(QStringLiteral("tran")).toString().toUpper();
        QString model = d.value(QStringLiteral("model")).toString().trimmed();
        if (model.isEmpty())
            model = QStringLiteral("Disco de Almacenamiento");

        QVariantMap dMap;
        dMap[QStringLiteral("path")] = path;
        dMap[QStringLiteral("size")] = size;
        dMap[QStringLiteral("tran")] = tran;
        dMap[QStringLiteral("model")] = model;
        dMap[QStringLiteral("name")] = tran.isEmpty() ? QStringLiteral("%1 (%2)").arg(path, size)
                                                      : QStringLiteral("%1 (%2 %3)").arg(path, size, tran);
        m_disks.append(dMap);
    }

    if (m_selectedDiskIndex >= m_disks.size()) {
        m_selectedDiskIndex = 0;
    }

    emit disksChanged();
    emit selectedDiskChanged();
}

void InstallerBackend::setCurrentStep(int step)
{
    if (m_currentStep != step) {
        m_currentStep = step;
        emit currentStepChanged();
    }
}

void InstallerBackend::setSelectedDiskIndex(int idx)
{
    if (idx >= 0 && idx < m_disks.size() && m_selectedDiskIndex != idx) {
        m_selectedDiskIndex = idx;
        emit selectedDiskIndexChanged();
        emit selectedDiskChanged();
    }
}

QString InstallerBackend::selectedDiskPath() const
{
    if (m_selectedDiskIndex >= 0 && m_selectedDiskIndex < m_disks.size()) {
        return m_disks[m_selectedDiskIndex].toMap()[QStringLiteral("path")].toString();
    }
    return QString();
}

QString InstallerBackend::selectedDiskName() const
{
    if (m_selectedDiskIndex >= 0 && m_selectedDiskIndex < m_disks.size()) {
        return m_disks[m_selectedDiskIndex].toMap()[QStringLiteral("name")].toString();
    }
    return QStringLiteral("No hay disco seleccionado");
}

QString InstallerBackend::selectedDiskSize() const
{
    if (m_selectedDiskIndex >= 0 && m_selectedDiskIndex < m_disks.size()) {
        return m_disks[m_selectedDiskIndex].toMap()[QStringLiteral("size")].toString();
    }
    return QString();
}

void InstallerBackend::setManualPartitioning(bool manual)
{
    if (m_manualPartitioning != manual) {
        m_manualPartitioning = manual;
        if (m_manualPartitioning && m_manualPartitions.isEmpty()) {
            resetDefaultPartitions();
        }
        emit manualPartitioningChanged();
    }
}

void InstallerBackend::resetDefaultPartitions()
{
    m_manualPartitions.clear();

    if (m_isUefi) {
        QVariantMap pEfi;
        pEfi[QStringLiteral("mount")] = QStringLiteral("/boot/efi");
        pEfi[QStringLiteral("size")] = 512;
        pEfi[QStringLiteral("fs")] = QStringLiteral("fat32");
        m_manualPartitions.append(pEfi);
    }

    QVariantMap pRoot;
    pRoot[QStringLiteral("mount")] = QStringLiteral("/");
    pRoot[QStringLiteral("size")] = 0; // 0 = 100% restante
    pRoot[QStringLiteral("fs")] = QStringLiteral("ext4");
    m_manualPartitions.append(pRoot);

    emit manualPartitionsChanged();
}

void InstallerBackend::addManualPartition(const QString &mountPoint, int sizeMb, const QString &fsType)
{
    QVariantMap p;
    p[QStringLiteral("mount")] = mountPoint;
    p[QStringLiteral("size")] = sizeMb;
    p[QStringLiteral("fs")] = fsType;
    m_manualPartitions.append(p);
    emit manualPartitionsChanged();
}

void InstallerBackend::updateManualPartition(int index, const QString &mountPoint, int sizeMb, const QString &fsType)
{
    if (index >= 0 && index < m_manualPartitions.size()) {
        QVariantMap p = m_manualPartitions[index].toMap();
        p[QStringLiteral("mount")] = mountPoint;
        p[QStringLiteral("size")] = sizeMb;
        p[QStringLiteral("fs")] = fsType;
        m_manualPartitions[index] = p;
        emit manualPartitionsChanged();
    }
}

void InstallerBackend::removeManualPartition(int index)
{
    if (index >= 0 && index < m_manualPartitions.size()) {
        m_manualPartitions.removeAt(index);
        emit manualPartitionsChanged();
    }
}

QString InstallerBackend::validatePartitionPlan() const
{
    if (!m_manualPartitioning) return QString();

    bool hasRoot = false;
    bool hasEfi = false;

    for (const auto &item : m_manualPartitions) {
        const auto map = item.toMap();
        QString m = map[QStringLiteral("mount")].toString();
        if (m == QStringLiteral("/")) hasRoot = true;
        if (m == QStringLiteral("/boot/efi") || m == QStringLiteral("/boot")) hasEfi = true;
    }

    if (!hasRoot) {
        return QStringLiteral("Se requiere definir una partición con punto de montaje '/' (Raíz).");
    }
    if (m_isUefi && !hasEfi) {
        return QStringLiteral("En sistemas UEFI se requiere una partición EFI (/boot/efi) de al menos 512 MB.");
    }
    return QString();
}

void InstallerBackend::openExternalPartitioner()
{
    if (QProcess::startDetached(QStringLiteral("gparted"), {selectedDiskPath()})) return;
    if (QProcess::startDetached(QStringLiteral("partitionmanager"), {})) return;
    QProcess::startDetached(QStringLiteral("kitty"), {QStringLiteral("-e"), QStringLiteral("cfdisk"), selectedDiskPath()});
}

void InstallerBackend::startInstallation(const QString &fsType,
                                        const QString &fullName,
                                        const QString &userName,
                                        const QString &password,
                                        const QString &hostname,
                                        bool autoLogin,
                                        const QString &timezone,
                                        const QString &keymap)
{
    if (m_disks.isEmpty()) {
        m_errorMessage = QStringLiteral("No hay ningún disco seleccionado para la instalación.");
        emit errorMessageChanged();
        return;
    }

    // La interfaz ya lo comprueba; aqui se repite porque un nombre que useradd
    // rechaza deja el sistema instalado sin usuario, y eso no se arregla luego.
    static const QRegularExpression validUser(QStringLiteral("^[a-z_][a-z0-9_-]{0,31}$"));
    if (!validUser.match(userName.trimmed()).hasMatch() || userName.trimmed() == QStringLiteral("root")) {
        m_errorMessage = QStringLiteral("El nombre de usuario '%1' no es válido.").arg(userName);
        emit errorMessageChanged();
        return;
    }
    if (password.isEmpty()) {
        m_errorMessage = QStringLiteral("La contraseña no puede estar vacía.");
        emit errorMessageChanged();
        return;
    }

    if (m_manualPartitioning) {
        QString vError = validatePartitionPlan();
        if (!vError.isEmpty()) {
            m_errorMessage = vError;
            emit errorMessageChanged();
            return;
        }
    }

    m_installing = true;
    m_installSuccess = false;
    m_progressPercent = 0;
    m_progressMessage = QStringLiteral("Iniciando instalador de Inti OS...");
    m_errorMessage.clear();

    emit installingChanged();
    emit progressPercentChanged();
    emit progressMessageChanged();
    emit errorMessageChanged();

    setCurrentStep(5); // Paso de instalación

    if (m_workerThread) {
        m_workerThread->quit();
        m_workerThread->wait(1000);
        delete m_workerThread;
    }

    m_workerThread = new QThread(this);
    m_worker = new InstallWorker();
    m_worker->diskPath = selectedDiskPath();
    m_worker->fsType = fsType.isEmpty() ? QStringLiteral("ext4") : fsType;
    m_worker->fullName = fullName;
    m_worker->userName = userName;
    m_worker->password = password;
    m_worker->hostname = hostname;
    m_worker->autoLogin = autoLogin;
    m_worker->timezone = timezone.isEmpty() ? QStringLiteral("Europe/Madrid") : timezone;
    m_worker->keymap = keymap.isEmpty() ? QStringLiteral("es") : keymap;
    m_worker->isUefi = m_isUefi;
    m_worker->manualPartitioning = m_manualPartitioning;
    m_worker->manualPartitions = m_manualPartitions;

    m_worker->moveToThread(m_workerThread);

    connect(m_workerThread, &QThread::started, m_worker, &InstallWorker::doInstall);
    connect(m_worker, &InstallWorker::progress, this, &InstallerBackend::onWorkerProgress);
    connect(m_worker, &InstallWorker::finished, this, &InstallerBackend::onWorkerFinished);

    m_workerThread->start();
}

void InstallerBackend::onWorkerProgress(int percent, const QString &msg)
{
    m_progressPercent = percent;
    m_progressMessage = msg;
    emit progressPercentChanged();
    emit progressMessageChanged();
}

void InstallerBackend::onWorkerFinished(bool success, const QString &error)
{
    m_installing = false;
    m_installSuccess = success;
    m_errorMessage = error;

    emit installingChanged();
    emit installSuccessChanged();
    emit errorMessageChanged();

    if (success) {
        setCurrentStep(6); // Paso Completado
    }
}

void InstallerBackend::rebootSystem()
{
    // Expulsar el medio USB live de arranque para que no vuelva a cargar la ISO
    QProcess pFind;
    pFind.start(QStringLiteral("findmnt"), {QStringLiteral("-no"), QStringLiteral("SOURCE"), QStringLiteral("/run/archiso/bootmnt")});
    if (pFind.waitForFinished(1000)) {
        QString dev = QString::fromUtf8(pFind.readAllStandardOutput()).trimmed();
        if (!dev.isEmpty()) {
            QProcess pDisk;
            pDisk.start(QStringLiteral("lsblk"), {QStringLiteral("-no"), QStringLiteral("PKNAME"), dev});
            if (pDisk.waitForFinished(1000)) {
                QString pk = QString::fromUtf8(pDisk.readAllStandardOutput()).trimmed();
                QString targetDev = pk.isEmpty() ? dev : (QStringLiteral("/dev/") + pk);
                QProcess::execute(QStringLiteral("eject"), {targetDev});
                QProcess::execute(QStringLiteral("udisksctl"), {QStringLiteral("power-off"), QStringLiteral("-b"), targetDev});
            }
        }
    }
    QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("reboot")});
}

void InstallerBackend::closeInstaller()
{
    QCoreApplication::quit();
}

#include "InstallerBackend.moc"
