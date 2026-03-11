pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Widgets
import qs.Common

Item {
    id: root

    required property var aiService

    Connections {
        target: root.aiService
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.margins: Theme.spacingS

        model: root.aiService.chatsModel
        clip: true

        delegate: Rectangle {
            id: wrapper
            width: list.width
            implicitHeight: 48
            color: isActive ? "#2a2a2a" : "transparent"

            required property bool isActive
            required property int messageCount
            required property string chatId
            required property string name

            RowLayout {
                implicitHeight: 48
                anchors.fill: parent
                // anchors.margins: Theme.
                spacing: Theme.spacingS

                StyledText {
                    Layout.fillWidth: true
                    text: wrapper.name
                    elide: Text.ElideRight
                    font.bold: wrapper.isActive
                }

                StyledText {
                    text: wrapper.messageCount
                    font.pixelSize: 11
                }

                DankButton {
                    text: "✕"
                    onClicked: root.aiService.deleteChat(wrapper.chatId)
                }
            }

            MouseArea {
                anchors.fill: parent
                z: -1
                onClicked: root.aiService.switchChat(wrapper.chatId)
            }
        }
    }
}
