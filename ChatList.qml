pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Widgets
import qs.Common

Item {
    id: root

    required property var aiService

    Connections {
        target: root.aiService
    }
    // Button {
    //     Layout.fillWidth: true
    //     text: "＋ New chat"
    //     onClicked: root.aiService.createNewChat()
    // }

    ListView {
        id: list
        anchors.fill: parent
        anchors.margins: Theme.spacingS

        model: root.aiService.chatsModel
        clip: true
        Component.onCompleted: {
            console.info("test");
        }

        delegate: Rectangle {
            id: wrapper
            width: list.width
            implicitHeight: 48
            color: isActive ? "#2a2a2a" : "transparent"

            required property bool isActive
            required property int messageCount
            required property string chatId
            required property string name

            // Moved console log to onCompleted for cleaner debugging
            Component.onCompleted: {
                console.info(messageCount, isActive, chatId, name);
            }

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
