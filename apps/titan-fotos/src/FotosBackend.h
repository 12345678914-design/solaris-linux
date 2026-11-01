#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QFileSystemWatcher>

class FotosBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList photos READ photos NOTIFY photosChanged)
    Q_PROPERTY(QVariantList categories READ categories CONSTANT)
    Q_PROPERTY(QString currentCategory READ currentCategory WRITE selectCategory NOTIFY categoryChanged)
    Q_PROPERTY(int currentIndex READ currentIndex WRITE selectPhoto NOTIFY currentPhotoChanged)
    Q_PROPERTY(QVariantMap currentPhoto READ currentPhoto NOTIFY currentPhotoChanged)
    Q_PROPERTY(QString searchQuery READ searchQuery WRITE setSearchQuery NOTIFY searchQueryChanged)
    Q_PROPERTY(int count READ count NOTIFY photosChanged)
    Q_PROPERTY(qreal zoomFactor READ zoomFactor WRITE setZoomFactor NOTIFY zoomFactorChanged)
    Q_PROPERTY(int rotationAngle READ rotationAngle NOTIFY rotationAngleChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY photosChanged)

public:
    explicit FotosBackend(QObject *parent = nullptr);
    ~FotosBackend() override = default;

    QVariantList photos() const { return m_filteredPhotos; }
    QVariantList categories() const { return m_categories; }
    QString currentCategory() const { return m_currentCategory; }
    int currentIndex() const { return m_currentIndex; }
    QVariantMap currentPhoto() const;
    QString searchQuery() const { return m_searchQuery; }
    int count() const { return m_filteredPhotos.size(); }
    qreal zoomFactor() const { return m_zoomFactor; }
    int rotationAngle() const { return m_rotationAngle; }
    QString statusText() const;

    void setSearchQuery(const QString &query);
    void setZoomFactor(qreal factor);

public slots:
    Q_INVOKABLE void selectCategory(const QString &category);
    Q_INVOKABLE void selectPhoto(int index);
    Q_INVOKABLE void nextPhoto();
    Q_INVOKABLE void previousPhoto();
    Q_INVOKABLE void rotateClockwise();
    Q_INVOKABLE void rotateCounterClockwise();
    Q_INVOKABLE void zoomIn();
    Q_INVOKABLE void zoomOut();
    Q_INVOKABLE void resetZoom();
    Q_INVOKABLE bool setAsWallpaper(const QString &filePath = QString());
    Q_INVOKABLE void openInFinder(const QString &filePath = QString());
    Q_INVOKABLE void refresh();

signals:
    void photosChanged();
    void categoryChanged();
    void currentPhotoChanged();
    void searchQueryChanged();
    void zoomFactorChanged();
    void rotationAngleChanged();

private:
    void initCategories();
    void scanDirectories();
    void filterPhotos();
    QString formatBytes(qint64 bytes) const;

    QVariantList m_allPhotos;
    QVariantList m_filteredPhotos;
    QVariantList m_categories;
    QString m_currentCategory;
    int m_currentIndex;
    QString m_searchQuery;
    qreal m_zoomFactor;
    int m_rotationAngle;
    QFileSystemWatcher *m_watcher;
};

