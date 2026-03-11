#pragma once
#include <QObject>
#include <QVariantList>
#include <QString>

class MarkdownParser : public QObject {
    Q_OBJECT
public:
    explicit MarkdownParser(QObject *parent = nullptr);
    Q_INVOKABLE QVariantList parse(const QString &markdown) const;
};
