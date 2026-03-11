import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Common
import aiAssistan.markdown
import qs.Widgets

Item {
    id: root
    property string role: "assistant"
    property string messageId: ""
    property string text: ""
    property string status: "ok" // ok|streaming|error
    property bool useMonospace: false
    signal regenerateRequested(string messageId)
    signal copySuccess

    readonly property bool isUser: role === "user"
    readonly property real bubbleMaxWidth: isUser ? Math.max(240, Math.floor(width * 0.82)) : width
    readonly property color userBubbleFill: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
    readonly property color userBubbleBorder: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3)
    readonly property color assistantBubbleFill: Theme.surfaceContainer
    readonly property color assistantBubbleBorder: Theme.outline
    readonly property var segments: useMarkdownRendering ? MarkdownParser.parse(root.text) : []

    readonly property var themeColors: ({
            "codeBg": Theme.surfaceContainerHigh,
            "blockquoteBg": Theme.withAlpha(Theme.surfaceContainerHighest, 0.5),
            "blockquoteBorder": Theme.outlineVariant,
            "inlineCodeBg": Theme.withAlpha(Theme.onSurface, 0.1)
        })

    readonly property bool useMarkdownRendering: !isUser && status !== "streaming"

    width: parent ? parent.width : implicitWidth
    implicitHeight: bubble.implicitHeight

    Rectangle {
        id: bubble
        width: Math.min(root.bubbleMaxWidth, root.width)
        x: root.isUser ? (root.width - width) : 0
        radius: Theme.cornerRadius
        color: root.isUser ? root.userBubbleFill : root.assistantBubbleFill
        border.color: status === "error" ? Theme.error : (root.isUser ? root.userBubbleBorder : root.assistantBubbleBorder)
        border.width: 1

        implicitHeight: contentColumn.implicitHeight + Theme.spacingM * 2
        height: implicitHeight

        Behavior on x {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }

        Column {
            id: contentColumn
            x: Theme.spacingM
            y: Theme.spacingM
            width: parent.width - Theme.spacingM * 2
            spacing: Theme.spacingS

            RowLayout {
                id: headerRow
                width: parent.width
                spacing: Theme.spacingXS

                // assistant: [icon][chip][spacer][regenerate][copy]
                // user:      [spacer][chip][icon]
                Item {
                    Layout.fillWidth: root.isUser
                }

                Rectangle {
                    radius: Theme.cornerRadius
                    color: root.isUser ? Theme.withAlpha(Theme.primary, 0.14) : Theme.surfaceVariant
                    Layout.preferredHeight: Theme.fontSizeSmall * 1.6
                    Layout.preferredWidth: headerText.implicitWidth + Theme.spacingS * 2

                    StyledText {
                        id: headerText
                        anchors.centerIn: parent
                        text: root.isUser ? I18n.tr("You") : I18n.tr("Assistant")
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        color: root.isUser ? Theme.primary : Theme.surfaceVariantText
                    }
                }

                Rectangle {
                    width: 18
                    height: 18
                    radius: 9
                    color: root.isUser ? Theme.withAlpha(Theme.primary, 0.20) : Theme.surfaceVariant
                    border.width: 1
                    border.color: root.isUser ? Theme.withAlpha(Theme.primary, 0.35) : Theme.surfaceVariantAlpha

                    DankIcon {
                        anchors.centerIn: parent
                        name: root.isUser ? "person" : "smart_toy"
                        size: 14
                        color: root.isUser ? Theme.primary : Theme.surfaceVariantText
                    }
                }

                Item {
                    Layout.fillWidth: !root.isUser
                }

                DankActionButton {
                    visible: !root.isUser && root.status === "ok"
                    iconName: "refresh"
                    buttonSize: 24
                    iconSize: 14
                    backgroundColor: "transparent"
                    iconColor: Theme.surfaceVariantText
                    tooltipText: I18n.tr("Regenerate")
                    onClicked: {
                        root.regenerateRequested(root.messageId);
                    }
                }

                DankActionButton {
                    visible: !root.isUser && root.status === "ok"
                    iconName: "content_copy"
                    buttonSize: 24
                    iconSize: 14
                    backgroundColor: "transparent"
                    iconColor: Theme.surfaceVariantText
                    tooltipText: I18n.tr("Copy")
                    enabled: (root.text || "").trim().length > 0
                    onClicked: {
                        Quickshell.execDetached(["wl-copy", root.text]);
                        root.copySuccess();
                    }
                }
            }

            Item {
                width: 1
                height: Theme.spacingS
            }

            StyledText {
                visible: root.status === "error"
                text: I18n.tr("Error")
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.error
                width: parent.width
            }

            Loader {
                width: parent.width
                sourceComponent: root.useMarkdownRendering ? segmentedRenderer : plainRenderer
            }

            Component {
                id: plainRenderer
                TextArea {
                    text: root.text
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeMedium
                    font.family: root.useMonospace ? Theme.monoFontFamily : Theme.fontFamily
                    color: status === "error" ? Theme.error : Theme.surfaceText
                    readOnly: true
                    selectByMouse: true
                    selectionColor: Theme.primary
                    selectedTextColor: Theme.onPrimary
                    background: null
                    leftPadding: 4
                    rightPadding: 4
                }
            }

            Component {
                id: segmentedRenderer
                Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    Repeater {
                        model: root.segments

                        delegate: Loader {
                            required property var modelData
                            width: parent.width
                            sourceComponent: {
                                switch (modelData.type) {
                                case "code":
                                    return codeBlock;
                                case "table":
                                    return tableBlock;
                                default:
                                    return markdownBlock;
                                }
                            }

                            // Pass data into the loaded item
                            onLoaded: {
                                item.segmentData = modelData;
                                item.parentWidth = width;
                            }
                        }
                    }
                }
            }
            Component {
                id: markdownBlock

                Text {
                    property var segmentData
                    property real parentWidth: 0

                    width: parentWidth
                    text: segmentData ? segmentData.content : ""
                    textFormat: Text.MarkdownText
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeMedium
                    font.family: Theme.fontFamily
                    color: Theme.surfaceText
                }
            }

            Component {
                id: codeBlock

                Rectangle {
                    property var segmentData
                    property real parentWidth: 0

                    width: parentWidth
                    implicitHeight: codeColumn.implicitHeight
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    border.color: Theme.outline
                    border.width: 1

                    Column {
                        id: codeColumn
                        width: parent.width

                        // Header: Language + Copy Button
                        Rectangle {
                            width: parent.width
                            height: langLabel.implicitHeight + Theme.spacingXS * 2
                            color: Theme.withAlpha(Theme.onSurface, 0.06)
                            radius: Theme.cornerRadius
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: parent.radius
                                color: parent.color
                            }

                            RowLayout {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: Theme.spacingS
                                    rightMargin: Theme.spacingS
                                }
                                StyledText {
                                    id: langLabel
                                    text: segmentData ? segmentData.lang : ""
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    Layout.fillWidth: true
                                }
                                DankActionButton {
                                    iconName: "content_copy"
                                    buttonSize: 20
                                    iconSize: 12
                                    backgroundColor: "transparent"
                                    iconColor: Theme.surfaceVariantText
                                    onClicked: {
                                        if (segmentData) {
                                            Quickshell.execDetached(["wl-copy", segmentData.content]);
                                            root.copySuccess();
                                        }
                                    }
                                }
                            }
                        }

                        // Code Container
                        Flickable {
                            id: codeFlicker
                            width: parent.width
                            // Force the Flickable to be exactly as tall as the text
                            height: codeTextArea.implicitHeight
                            contentWidth: codeTextArea.implicitWidth
                            contentHeight: codeTextArea.implicitHeight

                            // This property belongs to Flickable, not ScrollView
                            flickableDirection: Flickable.HorizontalFlick
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true

                            TextArea {
                                id: codeTextArea
                                text: segmentData ? segmentData.content : ""
                                textFormat: Text.PlainText
                                wrapMode: Text.NoWrap
                                font.pixelSize: Theme.fontSizeMedium
                                font.family: Theme.monoFontFamily
                                color: Theme.surfaceText
                                readOnly: true
                                selectByMouse: true
                                selectionColor: Theme.primary
                                selectedTextColor: Theme.onPrimary
                                background: null
                                leftPadding: Theme.spacingS
                                rightPadding: Theme.spacingS
                                topPadding: Theme.spacingS
                                bottomPadding: Theme.spacingS
                            }

                            ScrollBar.horizontal: ScrollBar {
                                active: codeFlicker.moving
                                policy: ScrollBar.AsNeeded
                            }
                        }
                    }
                }
            }

            Component {
                id: tableBlock

                Rectangle {
                    property var segmentData
                    property real parentWidth: 0

                    width: parentWidth
                    implicitHeight: tableColumn.implicitHeight
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    border.color: Theme.outline
                    border.width: 1
                    clip: true

                    Column {
                        id: tableColumn
                        width: parent.width

                        // Header row
                        Row {
                            width: parent.width
                            readonly property var headers: segmentData ? segmentData.headers : []
                            readonly property real cellWidth: headers.length > 0 ? Math.floor(width / headers.length) : width

                            Repeater {
                                model: parent.headers
                                Rectangle {
                                    width: parent.cellWidth
                                    height: headerCell.implicitHeight + Theme.spacingXS * 2
                                    color: Theme.withAlpha(Theme.onSurface, 0.08)

                                    // Right border between cells
                                    Rectangle {
                                        anchors.right: parent.right
                                        width: 1
                                        height: parent.height
                                        color: Theme.outline
                                        visible: index < parent.parent.headers.length - 1
                                    }

                                    StyledText {
                                        id: headerCell
                                        anchors {
                                            left: parent.left
                                            right: parent.right
                                            verticalCenter: parent.verticalCenter
                                            leftMargin: Theme.spacingS
                                            rightMargin: Theme.spacingS
                                        }
                                        text: modelData
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Medium
                                        color: Theme.surfaceText
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }
                        }

                        // Divider
                        Rectangle {
                            width: parent.width
                            height: 1
                            color: Theme.outline
                        }

                        // Data rows
                        Repeater {
                            model: segmentData ? segmentData.rows : []

                            Column {
                                required property var modelData
                                required property int index
                                width: parent.width

                                // Row
                                Row {
                                    width: parent.width
                                    readonly property int colCount: segmentData ? segmentData.headers.length : 0
                                    readonly property real cellWidth: colCount > 0 ? Math.floor(width / colCount) : width

                                    Repeater {
                                        model: modelData
                                        Rectangle {
                                            width: parent.cellWidth
                                            height: dataCell.implicitHeight + Theme.spacingXS * 2
                                            // Alternating row tint
                                            color: (index % 2 === 0) ? "transparent" : Theme.withAlpha(Theme.onSurface, 0.03)

                                            Rectangle {
                                                anchors.right: parent.right
                                                width: 1
                                                height: parent.height
                                                color: Theme.outline
                                                visible: index < parent.parent.colCount - 1
                                            }

                                            StyledText {
                                                id: dataCell
                                                anchors {
                                                    left: parent.left
                                                    right: parent.right
                                                    verticalCenter: parent.verticalCenter
                                                    leftMargin: Theme.spacingS
                                                    rightMargin: Theme.spacingS
                                                }
                                                text: modelData
                                                font.pixelSize: Theme.fontSizeMedium
                                                color: Theme.surfaceText
                                                wrapMode: Text.Wrap
                                            }
                                        }
                                    }
                                }

                                // Row divider (skip after last row)
                                Rectangle {
                                    width: parent.width
                                    height: 1
                                    color: Theme.withAlpha(Theme.outline, 0.5)
                                    visible: index < (segmentData ? segmentData.rows.length - 1 : 0)
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                visible: status === "streaming"
                radius: Theme.cornerRadius
                color: Theme.surfaceVariant
                height: Theme.fontSizeSmall * 1.6
                width: streamingText.implicitWidth + Theme.spacingS * 2
                x: root.isUser ? (parent.width - width) : 0

                StyledText {
                    id: streamingText
                    anchors.centerIn: parent
                    text: I18n.tr("Streaming…")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }
        }
    }
}
