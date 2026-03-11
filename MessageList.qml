pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Common

Item {
    id: root
    clip: true
    property var messages: null
    property var aiService: null
    property bool stickToBottom: true
    property bool useMonospace: false
    signal copySuccess

    Connections {
        target: root.messages
        function onCountChanged() {
            // Only react to single-message appends (streaming + user sends).
            // Bulk loads are handled by onMessagesReplaced below.
            if (root.stickToBottom && root.messages.count > 0)
                Qt.callLater(() => listView.positionViewAtEnd());
        }
    }

    Connections {
        target: root.aiService
        function onIsStreamingChanged() {
            if (root.aiService && !root.aiService.isStreaming)
                scrollSettleTimer.restart();
        }
        function onMessagesReplaced() {
            // After a chat switch or load, jump immediately.
            root.stickToBottom = true;
            Qt.callLater(() => listView.positionViewAtEnd());
        }
    }

    Timer {
        id: scrollSettleTimer
        interval: 32
        repeat: false
        onTriggered: listView.positionViewAtEnd()
    }

    ListView {
        id: listView
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        model: root.messages
        spacing: Theme.spacingM
        clip: true

        // Reuse delegate Item instances instead of destroy/recreate.
        // Biggest single win for a chat list with heavy delegates.
        // MessageBubble must handle property resets cleanly (it does,
        // since all its content is driven by bound properties).
        reuseItems: true

        // Keep ~3 screens worth of delegates alive above and below.
        // Avoids re-parsing markdown on fast scrolls.
        cacheBuffer: height > 0 ? height * 5 : 2000

        // Pre-render slightly outside the visible rect to reduce
        // blank flashes when flinging quickly.
        displayMarginBeginning: 64
        displayMarginEnd: 64

        pixelAligned: true

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        // Restore stickToBottom tracking.
        onContentYChanged: {
            const maxY = Math.max(0, contentHeight - height);
            root.stickToBottom = contentY >= maxY - 20;
        }

        onContentHeightChanged: {
            if (root.stickToBottom)
                Qt.callLater(() => positionViewAtEnd());
        }

        onModelChanged: {
            Qt.callLater(() => {
                root.stickToBottom = true;
                positionViewAtEnd();
            });
        }

        delegate: Item {
            id: wrapper
            width: listView.width

            required property int index
            required property string role
            required property string content
            required property string id
            required property int status

            // Expose previousRole as a model role instead of calling
            // messages.get() in a binding. Add it when you append to
            // the model:
            //   messages.append({
            //     ...,
            //     previousRole: messages.count > 0
            //       ? messages.get(messages.count - 1).role
            //       : ""
            //   })
            //
            // Then declare it here:
            required property string previousRole

            readonly property bool roleChanged: previousRole.length > 0 && previousRole !== role
            readonly property int topGap: roleChanged ? Theme.spacingM : 0

            implicitHeight: bubble.implicitHeight + topGap

            // Reset state when the delegate is reused for a different
            // model index (required when reuseItems: true).
            ListView.onReused: {
                // Properties are already rebound by the required
                // property system — nothing extra needed unless
                // MessageBubble has internal animation state you
                // want to reset.
            }

            MessageBubble {
                id: bubble
                width: parent.width
                y: wrapper.topGap
                messageId: wrapper.id
                role: wrapper.role
                text: wrapper.content
                status: wrapper.status
                useMonospace: root.useMonospace

                onCopySuccess: root.copySuccess()

                onRegenerateRequested: messageId => {
                    if (root.aiService?.regenerateFromMessageId)
                        root.aiService.regenerateFromMessageId(messageId);
                }
            }
        }
    }
}
