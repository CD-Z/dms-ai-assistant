pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Common

Item {
    id: root
    clip: true
    property var messages: null // expects a ListModel
    property var aiService: null
    property bool stickToBottom: true
    property bool useMonospace: false
    signal copySuccess

    Component.onCompleted: console.log("[MessageList] ready")

    // Scroll to bottom when a new message is appended.
    Connections {
        target: root.messages
        function onCountChanged() {
            if (root.stickToBottom) {
                Qt.callLater(() => listView.positionViewAtEnd());
            }
        }
    }

    // Scroll to bottom when streaming ends so the fully-rendered markdown
    // (which can be significantly taller than the streaming plain text) is visible.
    Connections {
        target: root.aiService
        function onIsStreamingChanged() {
            if (root.aiService && !root.aiService.isStreaming) {
                scrollSettleTimer.restart();
            }
        }
    }

    // Give the markdown layout two frames to settle before scrolling.
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

        // 1. Critical: Cache delegates outside the visible area to prevent
        // constant destruction/re-creation during scrolling.
        cacheBuffer: 2000

        // 2. Optimization: Don't force every pixel to be perfectly aligned if
        // it causes stutter, but usually, true is better for text.
        pixelAligned: true

        // 3. Performance: Refine the scrolling logic to avoid excessive calls.
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        delegate: Item {
            id: wrapper
            width: listView.width

            required property int index
            required property string role
            required property string content
            required property string id
            required property int status

            // 4. Optimization: Avoid accessing the model via .get() in a binding.
            // If your model is a C++ model, expose 'previousRole' as a role.
            // If it's a ListModel, this remains a bottleneck.
            readonly property bool roleChanged: {
                if (index === 0)
                    return false;
                // Accessing model data by index is expensive in bindings.
                const prev = root.messages.get(index - 1);
                return prev ? prev.role !== role : false;
            }
            readonly property int topGap: roleChanged ? Theme.spacingM : 0

            implicitHeight: bubble.implicitHeight + topGap

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

                // 5. Remove console.log from delegates. It kills frame rates.
                onRegenerateRequested: messageId => {
                    if (root.aiService?.regenerateFromMessageId) {
                        root.aiService.regenerateFromMessageId(messageId);
                    }
                }
            }
        }
    }
}
