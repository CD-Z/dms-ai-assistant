#include <QQmlExtensionPlugin>
#include <QQmlEngine>
#include "MarkdownParser.h"

class DankMarkdownPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)

public:
    void registerTypes(const char *uri) override {
        qmlRegisterSingletonType<MarkdownParser>(
            uri, 1, 0, "MarkdownParser",
            [](QQmlEngine *, QJSEngine *) -> QObject * {
                return new MarkdownParser();
            }
        );
    }
};

#include "plugin.moc"
