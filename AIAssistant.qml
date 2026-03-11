import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Quickshell
import qs.Widgets
import qs.Common

//import ChatList

Item {
    id: root

    implicitWidth: 480
    implicitHeight: 640

    Component.onCompleted: console.info("[AIAssistant UI Plugin] ready, service:", aiService)
    onAiServiceChanged: console.info("[AIAssistant UI Plugin] service changed:", aiService)
    onVisibleChanged: {
        if (!visible) {
            // Force menu teardown when the panel is hidden/toggled off.
            // This avoids stale popup/dropdown internals when reopened.
            showSettingsMenu = false;
            showOverflowMenu = false;
        }
    }

    required property var aiService
    required property bool isExpanded
    property bool historyOpen: false
    property bool showSettingsMenu: false
    property bool showOverflowMenu: false
    property string transientHint: ""
    property real nowMs: Date.now()
    readonly property real panelTransparency: SettingsData.popupTransparency
    readonly property bool hasApiKey: !!(aiService && aiService.resolveApiKey && aiService.resolveApiKey().length > 0)
    readonly property bool hasMessages: (aiService.messageCount ?? 0) > 0
    readonly property int streamElapsedSeconds: (aiService.isStreaming && (aiService.streamStartedAtMs ?? 0) > 0) ? Math.max(0, Math.floor((nowMs - aiService.streamStartedAtMs) / 1000)) : 0
    signal hideRequested
    signal expandRequested(expand: bool)

    function showTemporaryHint(text) {
        transientHint = text || "";
        hintResetTimer.restart();
    }

    function openSettingsAndFocusApiKey() {
        showSettingsMenu = true;
        Qt.callLater(() => {
            const panel = settingsPanelLoader.item;
            if (panel && panel.focusApiKeyField)
                panel.focusApiKeyField();
        });
    }

    function startNewChat() {
        if (aiService.isStreaming ?? false) {
            showTemporaryHint(I18n.tr("Stop current response first."));
            return;
        }

        if ((aiService.messageCount ?? 0) > 0) {
            aiService.createNewChat();
        }
    }

    function sendCurrentMessage() {
        if (!composer.text || composer.text.trim().length === 0)
            return;
        if (!aiService) {
            console.warn("[AIAssistant UI] service unavailable");
            return;
        }
        console.log("[AIAssistant UI] sendCurrentMessage");
        aiService.sendMessage(composer.text.trim());
        composer.text = "";
    }

    function getFullChatHistory() {
        const svc = aiService;
        if (!svc || !svc.messagesModel)
            return "";
        const model = svc.messagesModel;
        let history = "";
        for (let i = 0; i < model.count; i++) {
            const m = model.get(i);
            if (m.role === "user" || m.role === "assistant") {
                const label = m.role === "user" ? "User" : "Assistant";
                const content = m.content || "";
                if (content.trim().length > 0) {
                    history += label + ": " + content + "\n\n";
                }
            }
        }
        return history.trim();
    }

    function copyFullChat() {
        const text = getFullChatHistory();
        if (!text)
            return;
        Quickshell.execDetached(["wl-copy", text]);
    }

    function privacyNote() {
        const provider = aiService.provider ?? "openai";
        const baseUrl = aiService.baseUrl ?? "";
        const isRemote = provider !== "custom" || (!baseUrl.includes("localhost") && !baseUrl.includes("127.0.0.1"));

        if (isRemote)
            return I18n.tr("Remote provider (%1): avoid sensitive data.").arg(provider.toUpperCase());
        return I18n.tr("Local endpoint detected.");
    }

    function prefillPrompt(prompt) {
        composer.text = prompt;
        composer.forceActiveFocus();
    }

    Timer {
        id: streamTimer
        interval: 300
        repeat: true
        running: aiService.isStreaming
        onTriggered: nowMs = Date.now()
    }

    Timer {
        id: hintResetTimer
        interval: 2500
        repeat: false
        onTriggered: transientHint = ""
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingM

        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            spacing: Theme.spacingS

            Rectangle {
                radius: Theme.cornerRadius
                color: Theme.surfaceVariant
                implicitHeight: Theme.fontSizeSmall * 1.6
                Layout.preferredWidth: providerLabel.implicitWidth + Theme.spacingM
                Layout.alignment: Qt.AlignVCenter

                StyledText {
                    id: providerLabel
                    anchors.centerIn: parent
                    text: (aiService.provider || "openai").toUpperCase()
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }

            Rectangle {
                implicitWidth: 10
                implicitHeight: 10
                radius: 5
                color: aiService.isOnline ? Theme.success : Theme.surfaceVariantText
                Layout.alignment: Qt.AlignVCenter
            }

            Rectangle {
                visible: aiService.isStreaming
                radius: Theme.cornerRadius
                color: Theme.surfaceVariant
                implicitHeight: Theme.fontSizeSmall * 1.6
                Layout.preferredWidth: streamingHeaderText.implicitWidth + Theme.spacingM
                Layout.alignment: Qt.AlignVCenter

                StyledText {
                    id: streamingHeaderText
                    anchors.centerIn: parent
                    text: I18n.tr("Generating… %1s").arg(streamElapsedSeconds)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }

            Rectangle {
                visible: !aiService.isStreaming && transientHint.length > 0
                radius: Theme.cornerRadius
                color: Theme.surfaceVariant
                implicitHeight: Theme.fontSizeSmall * 1.6
                Layout.preferredWidth: transientHeaderText.implicitWidth + Theme.spacingM
                Layout.alignment: Qt.AlignVCenter

                StyledText {
                    id: transientHeaderText
                    anchors.centerIn: parent
                    text: transientHint
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }

            Item {
                Layout.fillWidth: true
            }

            DankActionButton {
                iconName: "add"
                tooltipText: I18n.tr("New chat")
                enabled: !(aiService.isStreaming ?? false)
                onClicked: startNewChat()
            }
            DankActionButton {
                iconName: "side_navigation"
                tooltipText: "Toggle History"
                // If the parent slideout is expandable, we show the toggle
                onClicked: {
                    if (!root.isExpanded && !root.historyOpen) {
                        root.expandRequested(true);
                    }
                    root.historyOpen = !root.historyOpen;
                }
            }

            DankActionButton {
                iconName: "more_vert"
                tooltipText: I18n.tr("More")
                onClicked: showOverflowMenu = !showOverflowMenu
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.spacingM

            // --- LEFT PANEL: Messages + Empty State ---
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.cornerRadius
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, root.panelTransparency)
                border.color: Theme.surfaceVariantAlpha
                border.width: 1
                clip: true

                // Message List (Visible when there are messages)
                MessageList {
                    id: list
                    anchors.fill: parent
                    visible: hasMessages
                    messages: aiService.messagesModel
                    aiService: root.aiService
                    useMonospace: aiService.useMonospace
                    onCopySuccess: showTemporaryHint(I18n.tr("Copied to clipboard."))
                }

                // Empty State (Visible when no messages)
                Column {
                    anchors.centerIn: parent
                    width: parent.width * 0.86
                    spacing: Theme.spacingM
                    visible: !hasMessages

                    StyledText {
                        width: parent.width
                        text: !hasApiKey ? I18n.tr("Configure a provider and API key to start chatting.") : I18n.tr("Start a conversation.")
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    StyledText {
                        width: parent.width
                        text: privacyNote()
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceTextMedium
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Row {
                        spacing: Theme.spacingS
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: !hasApiKey

                        DankButton {
                            text: I18n.tr("Open Settings")
                            iconName: "settings"
                            onClicked: showSettingsMenu = true
                        }

                        DankButton {
                            text: I18n.tr("Paste API Key")
                            iconName: "vpn_key"
                            onClicked: {
                                openSettingsAndFocusApiKey();
                                showTemporaryHint(I18n.tr("Press Ctrl+V in the API key field."));
                            }
                        }
                    }

                    Flow {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: hasApiKey

                        DankButton {
                            text: I18n.tr("Summarize clipboard")
                            iconName: "summarize"
                            onClicked: prefillPrompt(I18n.tr("Summarize the clipboard text into concise bullets."))
                        }

                        DankButton {
                            text: I18n.tr("Draft reply")
                            iconName: "edit"
                            onClicked: prefillPrompt(I18n.tr("Draft a concise, professional reply to this message:"))
                        }

                        DankButton {
                            text: I18n.tr("Explain error")
                            iconName: "bug_report"
                            onClicked: prefillPrompt(I18n.tr("Explain this error and provide a fix:"))
                        }
                    }
                }
            }

            // --- RIGHT PANEL: Chat List ---
            Rectangle {
                Layout.preferredWidth: root.historyOpen ? parent.width * 0.35 : 0
                Layout.fillHeight: true

                opacity: root.historyOpen ? 1 : 0
                radius: Theme.cornerRadius
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, root.panelTransparency)
                border.color: Theme.surfaceVariantAlpha
                border.width: root.historyOpen ? 1 : 0
                clip: true
                //visible: root.historyOpen

                Behavior on Layout.preferredWidth {
                    NumberAnimation {
                        duration: 300
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: 250
                    }
                }

                ChatList {
                    anchors.fill: parent
                    aiService: root.aiService
                }
            }
        }
        Item {
            id: composerRow
            Layout.fillWidth: true
            Layout.preferredHeight: 116

            Rectangle {
                id: composerContainer
                anchors.fill: parent
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                border.color: composer.activeFocus ? Theme.primary : Theme.outlineMedium
                border.width: composer.activeFocus ? 2 : 1

                Behavior on border.color {
                    ColorAnimation {
                        duration: Theme.shortDuration
                        easing.type: Theme.standardEasing
                    }
                }

                Behavior on border.width {
                    NumberAnimation {
                        duration: Theme.shortDuration
                        easing.type: Theme.standardEasing
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingS
                    anchors.rightMargin: Theme.spacingS
                    anchors.topMargin: Theme.spacingXS
                    anchors.bottomMargin: Theme.spacingXS
                    spacing: Theme.spacingXS

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ScrollView {
                            id: scrollView
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingS
                            anchors.rightMargin: Theme.spacingS
                            anchors.topMargin: Theme.spacingXS
                            anchors.bottomMargin: Theme.spacingXS
                            clip: true
                            padding: 0
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                            TextArea {
                                id: composer
                                implicitWidth: scrollView.availableWidth
                                wrapMode: TextArea.Wrap
                                background: Rectangle {
                                    color: "transparent"
                                }
                                font.pixelSize: Theme.fontSizeMedium
                                font.family: Theme.fontFamily
                                font.weight: Theme.fontWeight
                                color: Theme.surfaceText
                                Material.accent: Theme.primary
                                padding: 0
                                leftPadding: 2
                                rightPadding: 2
                                topPadding: 2
                                bottomPadding: 2

                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Escape) {
                                        hideRequested();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) {
                                        startNewChat();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        if (event.modifiers & Qt.ShiftModifier) {
                                            // Shift+Enter: insert newline (default behavior)
                                            event.accepted = false;
                                        } else {
                                            // Enter alone: send message
                                            event.accepted = true;
                                            sendCurrentMessage();
                                        }
                                    }
                                }
                            }
                        }

                        StyledText {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingS
                            anchors.rightMargin: Theme.spacingS
                            anchors.topMargin: Theme.spacingXS
                            anchors.bottomMargin: Theme.spacingXS
                            text: I18n.tr("Ask anything…")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.outlineButton
                            verticalAlignment: Text.AlignTop
                            visible: composer.text.length === 0
                            wrapMode: Text.Wrap
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingS

                        Item {
                            Layout.fillWidth: true
                        }

                        DankActionButton {
                            iconName: "send"
                            tooltipText: I18n.tr("Send")
                            enabled: composer.text && composer.text.trim().length > 0 && !aiService.isStreaming
                            visible: !aiService.isStreaming
                            buttonSize: 36
                            iconSize: 18
                            onClicked: sendCurrentMessage()
                        }

                        DankActionButton {
                            iconName: "stop"
                            tooltipText: I18n.tr("Stop")
                            enabled: aiService.isStreaming
                            visible: aiService.isStreaming
                            buttonSize: 36
                            iconSize: 18
                            iconColor: Theme.error
                            onClicked: aiService.cancel()
                        }
                    }
                }
            }
        }
    }

    Loader {
        id: settingsPanelLoader
        anchors.fill: parent
        // Recreate settings panel each time it is opened.
        // Keeping a hidden instance mounted causes DankDropdown to stop handling
        // interaction after the first open/close cycle (see issue #2).
        active: showSettingsMenu
        sourceComponent: settingsPanelComponent
    }

    Component {
        id: settingsPanelComponent

        AIAssistantSettings {
            anchors.fill: parent
            isVisible: true
            onCloseRequested: showSettingsMenu = false
            pluginId: "aiAssistant"
            aiService: root.aiService
        }
    }

    MouseArea {
        anchors.fill: parent
        visible: showOverflowMenu
        onClicked: showOverflowMenu = false

        Rectangle {
            id: overflowMenuPopup
            x: parent.width - width - Theme.spacingM
            y: Theme.spacingXL + Theme.spacingM
            width: 200
            height: menuColumn.height + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainer
            border.width: 1
            border.color: Theme.outlineMedium

            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            Column {
                id: menuColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                DankButton {
                    text: showSettingsMenu ? I18n.tr("Hide settings") : I18n.tr("Settings")
                    iconName: "settings"
                    width: parent.width
                    onClicked: {
                        showSettingsMenu = !showSettingsMenu;
                        showOverflowMenu = false;
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.outlineMedium
                }

                DankButton {
                    text: I18n.tr("Copy entire chat")
                    iconName: "content_copy"
                    width: parent.width
                    enabled: (aiService.messageCount ?? 0) > 0
                    onClicked: {
                        copyFullChat();
                        showOverflowMenu = false;
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.outlineMedium
                }

                DankButton {
                    text: I18n.tr("Close")
                    iconName: "close"
                    width: parent.width
                    onClicked: {
                        showOverflowMenu = false;
                        root.hideRequested();
                    }
                }
            }
        }
    }
}
