import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "./AIApiAdapters.js" as AIApiAdapters

Item {
    id: root

    property string pluginId: "aiAssistant"

    Component.onCompleted: {
        console.info("[AIAssistantService Plugin] ready");
        loadSettings();
        mkdirProcess.running = true;
    }

    readonly property string baseDir: Paths.strip(StandardPaths.writableLocation(StandardPaths.GenericStateLocation) + "/DankMaterialShell/plugins/aiAssistant")
    readonly property string sessionPath: baseDir + "/session.json"
    property bool sessionLoaded: false
    property string providerConfigHash: ""
    property var sessionsByConfig: ({})
    property bool suppressConfigChange: false
    property int maxStoredMessages: 50

    property ListModel messagesModel: ListModel {}
    property ListModel chatsModel: ListModel {}
    property string activeChatId: ""
    property int messageCount: messagesModel.count
    property bool isStreaming: false
    property bool isOnline: false
    property string activeStreamId: ""
    property real streamStartedAtMs: 0
    property string lastUserText: ""
    property int lastHttpStatus: 0

    // Settings
    property var providers: ({})
    property string provider: "openai"
    property string baseUrl: "https://api.openai.com"
    property string model: "gpt-5.2"
    property real temperature: 0.7
    property int maxTokens: 4096
    property int timeout: 30
    property string apiKey: ""
    property bool saveApiKey: false
    property string sessionApiKey: ""
    property string apiKeyEnvVar: ""
    property bool useMonospace: false

    readonly property bool debugEnabled: (Quickshell.env("DMS_LOG_LEVEL") || "").toLowerCase() === "debug"

    onProviderChanged: handleConfigChanged()
    onBaseUrlChanged: handleConfigChanged()
    onModelChanged: handleConfigChanged()

    // ── Provider defaults ──────────────────────────────────────────

    function defaultsForProvider(id) {
        switch (id) {
        case "anthropic":
            return {
                baseUrl: "https://api.anthropic.com",
                model: "claude-sonnet-4-5",
                apiKey: "",
                saveApiKey: false,
                apiKeyEnvVar: "",
                temperature: 0.7,
                maxTokens: 4096,
                timeout: 30
            };
        case "gemini":
            return {
                baseUrl: "https://generativelanguage.googleapis.com",
                model: "gemini-3-flash-preview",
                apiKey: "",
                saveApiKey: false,
                apiKeyEnvVar: "",
                temperature: 0.7,
                maxTokens: 4096,
                timeout: 30
            };
        case "custom":
            return {
                baseUrl: "https://api.openai.com",
                model: "gpt-5.2",
                apiKey: "",
                saveApiKey: false,
                apiKeyEnvVar: "",
                temperature: 0.7,
                maxTokens: 4096,
                timeout: 30
            };
        default:
            return {
                baseUrl: "https://api.openai.com",
                model: "gpt-5.2",
                apiKey: "",
                saveApiKey: false,
                apiKeyEnvVar: "",
                temperature: 0.7,
                maxTokens: 4096,
                timeout: 30
            };
        }
    }

    function normalizedProfile(id, raw) {
        const defaults = defaultsForProvider(id);
        const p = raw || {};
        return {
            baseUrl: String(p.baseUrl || defaults.baseUrl).trim(),
            model: String(p.model || defaults.model).trim(),
            apiKey: String(p.apiKey || "").trim(),
            saveApiKey: !!p.saveApiKey,
            apiKeyEnvVar: String(p.apiKeyEnvVar || "").trim(),
            temperature: typeof p.temperature === "number" ? p.temperature : defaults.temperature,
            maxTokens: typeof p.maxTokens === "number" ? p.maxTokens : defaults.maxTokens,
            timeout: typeof p.timeout === "number" ? p.timeout : defaults.timeout
        };
    }

    function mergedProviders(rawProviders) {
        const base = {
            openai: normalizedProfile("openai", null),
            anthropic: normalizedProfile("anthropic", null),
            gemini: normalizedProfile("gemini", null),
            custom: normalizedProfile("custom", null)
        };
        if (!rawProviders || typeof rawProviders !== "object")
            return base;
        const ids = ["openai", "anthropic", "gemini", "custom"];
        for (let i = 0; i < ids.length; i++) {
            const id = ids[i];
            if (rawProviders[id] && typeof rawProviders[id] === "object") {
                base[id] = normalizedProfile(id, rawProviders[id]);
            }
        }
        return base;
    }

    function syncLegacySnapshot(activeProfile) {
        PluginService.savePluginData(pluginId, "provider", provider);
        PluginService.savePluginData(pluginId, "baseUrl", activeProfile.baseUrl);
        PluginService.savePluginData(pluginId, "model", activeProfile.model);
        PluginService.savePluginData(pluginId, "apiKey", activeProfile.apiKey);
        PluginService.savePluginData(pluginId, "saveApiKey", activeProfile.saveApiKey);
        PluginService.savePluginData(pluginId, "apiKeyEnvVar", activeProfile.apiKeyEnvVar);
        PluginService.savePluginData(pluginId, "temperature", activeProfile.temperature);
        PluginService.savePluginData(pluginId, "maxTokens", activeProfile.maxTokens);
        PluginService.savePluginData(pluginId, "timeout", activeProfile.timeout);
    }

    // ── Settings load ──────────────────────────────────────────────

    function loadSettings() {
        suppressConfigChange = true;
        const selectedProvider = String(PluginService.loadPluginData(pluginId, "provider", "openai")).trim() || "openai";
        const providerId = ["openai", "anthropic", "gemini", "custom"].includes(selectedProvider) ? selectedProvider : "openai";
        const rawProviders = PluginService.loadPluginData(pluginId, "providers", null);
        let nextProviders = mergedProviders(rawProviders);

        if (!rawProviders || typeof rawProviders !== "object") {
            const legacyProfile = {
                baseUrl: String(PluginService.loadPluginData(pluginId, "baseUrl", defaultsForProvider(providerId).baseUrl)).trim(),
                model: String(PluginService.loadPluginData(pluginId, "model", defaultsForProvider(providerId).model)).trim(),
                temperature: PluginService.loadPluginData(pluginId, "temperature", 0.7),
                maxTokens: PluginService.loadPluginData(pluginId, "maxTokens", 4096),
                timeout: PluginService.loadPluginData(pluginId, "timeout", 30),
                apiKey: String(PluginService.loadPluginData(pluginId, "apiKey", "")).trim(),
                saveApiKey: PluginService.loadPluginData(pluginId, "saveApiKey", false),
                apiKeyEnvVar: String(PluginService.loadPluginData(pluginId, "apiKeyEnvVar", "")).trim()
            };
            nextProviders[providerId] = normalizedProfile(providerId, legacyProfile);
            PluginService.savePluginData(pluginId, "providers", nextProviders);
            syncLegacySnapshot(nextProviders[providerId]);
        }

        providers = nextProviders;
        provider = providerId;

        const active = providers[provider] || normalizedProfile(provider, null);
        baseUrl = active.baseUrl;
        model = active.model;
        temperature = active.temperature;
        maxTokens = active.maxTokens;
        timeout = active.timeout;
        apiKey = active.apiKey;
        saveApiKey = active.saveApiKey;
        apiKeyEnvVar = active.apiKeyEnvVar;
        useMonospace = PluginService.loadPluginData(pluginId, "useMonospace", false);
        suppressConfigChange = false;

        const currentHash = computeConfigHash();
        if (providerConfigHash !== currentHash)
            switchConfigHistory(currentHash);
    }

    Connections {
        target: PluginService
        function onPluginDataChanged(pId) {
            if (pId !== root.pluginId)
                return;
            loadSettings();
        }
    }

    Process {
        id: mkdirProcess
        command: ["mkdir", "-p", root.baseDir]
        running: false
        onExited: code => {
            if (code === 0 && !sessionLoaded) {
                sessionFile.path = sessionPath;
            }
        }
    }

    FileView {
        id: sessionFile
        path: ""
        blockWrites: true
        atomicWrites: true

        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (data.version >= 3 && data.sessions && typeof data.sessions === "object") {
                    // v3 native format
                    sessionsByConfig = data.sessions;
                } else if (data.version >= 2 && data.sessions && typeof data.sessions === "object") {
                    // Migrate v2 → v3: each config had a
                    // flat message array, wrap into a single
                    // chat per config.
                    const migrated = {};
                    const keys = Object.keys(data.sessions);
                    for (let i = 0; i < keys.length; i++) {
                        const k = keys[i];
                        const msgs = Array.isArray(data.sessions[k]) ? data.sessions[k] : [];
                        const chatId = "chat-migrated";
                        const chatName = autoNameFromMessages(msgs) || "Migrated chat";
                        migrated[k] = {
                            chats: {},
                            activeChatId: chatId
                        };
                        migrated[k].chats[chatId] = {
                            name: chatName,
                            createdAt: Date.now(),
                            messages: msgs
                        };
                    }
                    sessionsByConfig = migrated;
                } else {
                    // Very old format: single message array
                    const legacyHash = data.providerConfigHash || computeConfigHash();
                    const msgs = Array.isArray(data.messages) ? data.messages : [];
                    const chatId = "chat-migrated";
                    const chatName = autoNameFromMessages(msgs) || "Migrated chat";
                    sessionsByConfig = {};
                    sessionsByConfig[legacyHash] = {
                        chats: {},
                        activeChatId: chatId
                    };
                    sessionsByConfig[legacyHash].chats[chatId] = {
                        name: chatName,
                        createdAt: Date.now(),
                        messages: msgs
                    };
                }
            } catch (e) {
                sessionsByConfig = {};
            }

            sessionLoaded = true;
            switchConfigHistory(computeConfigHash());
        }

        onLoadFailed: {
            sessionsByConfig = {};
            sessionLoaded = true;
            switchConfigHistory(computeConfigHash());
        }
    }

    // ── Config hash & history switching ────────────────────────────

    function computeConfigHash() {
        return provider + "|" + baseUrl + "|" + model;
    }

    function getConfigSession(configHash) {
        if (sessionsByConfig && sessionsByConfig[configHash] && typeof sessionsByConfig[configHash] === "object" && sessionsByConfig[configHash].chats) {
            return sessionsByConfig[configHash];
        }
        return {
            chats: {},
            activeChatId: ""
        };
    }

    function ensureConfigSession(configHash) {
        if (!sessionsByConfig)
            sessionsByConfig = {};
        if (!sessionsByConfig[configHash] || typeof sessionsByConfig[configHash] !== "object" || !sessionsByConfig[configHash].chats) {
            const next = Object.assign({}, sessionsByConfig);
            next[configHash] = {
                chats: {},
                activeChatId: ""
            };
            sessionsByConfig = next;
        }
        return sessionsByConfig[configHash];
    }

    function persistCurrentMessagesForChat() {
        const configHash = providerConfigHash || computeConfigHash();
        const chatId = activeChatId;
        if (!configHash || !chatId)
            return;

        const msgs = [];
        for (let i = 0; i < messagesModel.count; i++) {
            const m = messagesModel.get(i);
            if ((m.role === "user" || m.role === "assistant") && m.status !== "streaming") {
                msgs.push({
                    role: m.role,
                    content: m.content,
                    timestamp: m.timestamp,
                    id: m.id,
                    status: m.status
                });
            }
        }
        const capped = msgs.length > maxStoredMessages ? msgs.slice(msgs.length - maxStoredMessages) : msgs;

        const next = Object.assign({}, sessionsByConfig);
        const session = next[configHash] || {
            chats: {},
            activeChatId: chatId
        };
        const chats = Object.assign({}, session.chats);

        if (chats[chatId]) {
            chats[chatId] = Object.assign({}, chats[chatId], {
                messages: capped
            });
        } else {
            chats[chatId] = {
                name: autoNameFromMessages(capped) || "New chat",
                createdAt: Date.now(),
                messages: capped
            };
        }

        session.chats = chats;
        session.activeChatId = chatId;
        next[configHash] = session;
        sessionsByConfig = next;
    }

    function switchConfigHistory(nextHash) {
        if (!nextHash)
            return;

        const previousHash = providerConfigHash;
        if (previousHash && previousHash !== nextHash)
            persistCurrentMessagesForChat();

        providerConfigHash = nextHash;
        const session = getConfigSession(nextHash);
        let targetChatId = session.activeChatId || "";

        // If target chat doesn't exist or is empty,
        // pick first available or create new
        if (!targetChatId || !session.chats[targetChatId]) {
            const chatIds = Object.keys(session.chats || {});
            targetChatId = chatIds.length > 0 ? chatIds[0] : "";
        }

        if (targetChatId && session.chats[targetChatId]) {
            activeChatId = targetChatId;
            loadMessages(session.chats[targetChatId].messages || []);
        } else {
            // No chats exist yet — create one
            const newId = createNewChatInternal(nextHash);
            activeChatId = newId;
            messagesModel.clear();
            lastUserText = "";
        }

        refreshChatsModel();
        saveSession();
    }

    function handleConfigChanged() {
        if (suppressConfigChange)
            return;
        const current = computeConfigHash();
        if (providerConfigHash && providerConfigHash !== current) {
            switchConfigHistory(current);
        } else {
            providerConfigHash = current;
            saveSession();
        }
    }

    // ── Multi-chat management ──────────────────────────────────────

    function createNewChatInternal(configHash) {
        const chatId = "chat-" + Date.now();
        const next = Object.assign({}, sessionsByConfig);
        const session = next[configHash] || {
            chats: {},
            activeChatId: ""
        };
        const chats = Object.assign({}, session.chats);
        chats[chatId] = {
            name: "New chat",
            createdAt: Date.now(),
            messages: []
        };
        session.chats = chats;
        session.activeChatId = chatId;
        next[configHash] = session;
        sessionsByConfig = next;
        return chatId;
    }

    function createNewChat() {
        if (isStreaming && chatFetcher.running)
            return;

        persistCurrentMessagesForChat();
        const configHash = providerConfigHash || computeConfigHash();
        const newId = createNewChatInternal(configHash);

        activeChatId = newId;
        messagesModel.clear();
        lastUserText = "";
        isStreaming = false;
        activeStreamId = "";
        streamStartedAtMs = 0;

        refreshChatsModel();
        saveSession();
    }

    function switchChat(chatId) {
        if (!chatId || chatId === activeChatId)
            return;
        if (isStreaming && chatFetcher.running)
            return;

        persistCurrentMessagesForChat();

        const configHash = providerConfigHash || computeConfigHash();
        const session = getConfigSession(configHash);
        const chat = session.chats ? session.chats[chatId] : null;
        if (!chat)
            return;

        // Update activeChatId in session
        const next = Object.assign({}, sessionsByConfig);
        if (next[configHash])
            next[configHash].activeChatId = chatId;
        sessionsByConfig = next;

        activeChatId = chatId;
        isStreaming = false;
        activeStreamId = "";
        streamStartedAtMs = 0;
        loadMessages(chat.messages || []);

        refreshChatsModel();
        saveSession();
    }

    function deleteChat(chatId) {
        if (!chatId)
            return;
        if (isStreaming && chatFetcher.running && chatId === activeChatId)
            return;

        const configHash = providerConfigHash || computeConfigHash();
        const next = Object.assign({}, sessionsByConfig);
        const session = next[configHash];
        if (!session || !session.chats || !session.chats[chatId])
            return;

        const chats = Object.assign({}, session.chats);
        delete chats[chatId];
        session.chats = chats;

        const remainingIds = Object.keys(chats);

        if (chatId === activeChatId) {
            // Switch to another chat or create a new one
            if (remainingIds.length > 0) {
                const switchTo = remainingIds[0];
                session.activeChatId = switchTo;
                activeChatId = switchTo;
                loadMessages(chats[switchTo].messages || []);
            } else {
                const newId = createNewChatInternal(configHash);
                activeChatId = newId;
                messagesModel.clear();
                lastUserText = "";
            }
            isStreaming = false;
            activeStreamId = "";
            streamStartedAtMs = 0;
        } else {
            if (remainingIds.length === 0) {
                const newId = createNewChatInternal(configHash);
                activeChatId = newId;
                messagesModel.clear();
                lastUserText = "";
            }
        }

        next[configHash] = session;
        sessionsByConfig = next;
        refreshChatsModel();
        saveSession();
    }

    function renameChat(chatId, newName) {
        if (!chatId || !newName)
            return;
        const configHash = providerConfigHash || computeConfigHash();
        const next = Object.assign({}, sessionsByConfig);
        const session = next[configHash];
        if (!session || !session.chats || !session.chats[chatId])
            return;

        const chats = Object.assign({}, session.chats);
        chats[chatId] = Object.assign({}, chats[chatId], {
            name: newName.trim()
        });
        session.chats = chats;
        next[configHash] = session;
        sessionsByConfig = next;

        refreshChatsModel();
        saveSession();
    }

    function autoNameFromMessages(msgs) {
        if (!Array.isArray(msgs))
            return "";
        for (let i = 0; i < msgs.length; i++) {
            if (msgs[i] && msgs[i].role === "user" && (msgs[i].content || "").trim().length > 0) {
                const text = msgs[i].content.trim();
                return text.length > 40 ? text.substring(0, 40) + "…" : text;
            }
        }
        return "";
    }

    function refreshChatsModel() {
        chatsModel.clear();
        const configHash = providerConfigHash || computeConfigHash();
        const session = getConfigSession(configHash);
        const chats = session.chats || {};
        const ids = Object.keys(chats);

        // Sort by createdAt descending (newest first)
        ids.sort(function (a, b) {
            return ((chats[b].createdAt || 0) - (chats[a].createdAt || 0));
        });

        for (let i = 0; i < ids.length; i++) {
            const id = ids[i];
            const chat = chats[id];
            chatsModel.append({
                chatId: id,
                name: chat.name || "New chat",
                createdAt: chat.createdAt || 0,
                messageCount: (chat.messages || []).length,
                isActive: id === activeChatId
            });
        }
    }

    // ── Messages ───────────────────────────────────────────────────

    function loadMessages(msgs) {
        messagesModel.clear();
        for (let i = 0; i < msgs.length; i++) {
            const m = msgs[i];
            if (!m || !m.role || !m.content)
                continue;
            messagesModel.append({
                role: m.role,
                content: m.content,
                timestamp: m.timestamp || Date.now(),
                id: m.id || m.role + "-" + Date.now() + "-" + i,
                status: m.status || "ok"
            });
        }
        lastUserText = findLastUserText();
    }

    function saveSession() {
        persistCurrentMessagesForChat();

        if (!sessionLoaded || !sessionFile.path)
            return;

        const currentHash = providerConfigHash || computeConfigHash();
        const data = {
            version: 3,
            providerConfigHash: currentHash,
            sessions: sessionsByConfig || {}
        };
        sessionFile.setText(JSON.stringify(data, null, 2));
    }

    function clearHistory(saveNow) {
        messagesModel.clear();
        isStreaming = false;
        activeStreamId = "";
        streamStartedAtMs = 0;
        isOnline = false;
        lastUserText = "";
        if (saveNow)
            saveSession();
    }

    // ── API key resolution ─────────────────────────────────────────

    function resolveApiKey() {
        const p = provider;

        function scopedEnv(id) {
            switch (id) {
            case "anthropic":
                return (Quickshell.env("DMS_ANTHROPIC_API_KEY") || "");
            case "gemini":
                return (Quickshell.env("DMS_GEMINI_API_KEY") || "");
            case "custom":
                return (Quickshell.env("DMS_CUSTOM_API_KEY") || "");
            default:
                return (Quickshell.env("DMS_OPENAI_API_KEY") || "");
            }
        }

        function commonEnv(id) {
            switch (id) {
            case "anthropic":
                return (Quickshell.env("ANTHROPIC_API_KEY") || "");
            case "gemini":
                return (Quickshell.env("GEMINI_API_KEY") || "");
            case "custom":
                return "";
            default:
                return (Quickshell.env("OPENAI_API_KEY") || "");
            }
        }

        const sKey = sessionApiKey || "";
        const svKey = saveApiKey ? apiKey || "" : "";
        const customEnvName = (apiKeyEnvVar || "").trim();
        const customEnv = customEnvName ? Quickshell.env(customEnvName) || "" : "";
        const common = commonEnv(p);
        const scoped = scopedEnv(p);

        return (sKey || svKey || customEnv || common || scoped || "");
    }

    // ── Sending / streaming ────────────────────────────────────────

    function sendMessage(text) {
        if (!text || text.trim().length === 0)
            return;
        if (isStreaming && chatFetcher.running) {
            markError(activeStreamId, "Please wait until the current response " + "finishes.");
            return;
        }
        startStreaming(text.trim(), true);
    }

    function retryLast() {
        if (isStreaming && chatFetcher.running)
            return;
        const text = lastUserText || findLastUserText();
        if (!text)
            return;
        startStreaming(text, false);
    }

    function regenerateFromMessageId(messageId) {
        if (!messageId || (isStreaming && chatFetcher.running))
            return;

        const assistantIdx = findIndexById(messageId);
        if (assistantIdx < 0) {
            retryLast();
            return;
        }

        const target = messagesModel.get(assistantIdx);
        if (!target || target.role !== "assistant") {
            retryLast();
            return;
        }

        let userText = "";
        for (let i = assistantIdx - 1; i >= 0; i--) {
            const m = messagesModel.get(i);
            if (m && m.role === "user" && m.status === "ok" && (m.content || "").trim().length > 0) {
                userText = m.content;
                break;
            }
        }
        if (!userText) {
            retryLast();
            return;
        }

        for (let i = messagesModel.count - 1; i >= assistantIdx; i--) {
            messagesModel.remove(i, 1);
        }
        lastUserText = userText;
        startStreaming(userText, false);
    }

    function startStreaming(text, addUser) {
        const now = Date.now();
        const streamId = "assistant-" + now;

        if (addUser) {
            messagesModel.append({
                role: "user",
                content: text,
                timestamp: now,
                id: "user-" + now,
                status: "ok"
            });
            lastUserText = text;

            // Auto-name the chat from the first user
            // message if still "New chat"
            autoNameCurrentChat(text);
        }

        messagesModel.append({
            role: "assistant",
            content: "",
            timestamp: now + 1,
            id: streamId,
            status: "streaming"
        });
        activeStreamId = streamId;
        isStreaming = true;
        streamStartedAtMs = now;
        lastHttpStatus = 0;

        const payload = buildPayload(text);
        const curlCmd = buildCurlCommand(payload);
        console.info(curlCmd);
        if (!curlCmd) {
            markError(streamId, "No API key or provider configuration.");
            return;
        }

        streamCollector.lastLen = 0;
        streamBuffer = "";
        chatFetcher.command = curlCmd;
        chatFetcher.running = true;
        saveSession();
    }

    function autoNameCurrentChat(userText) {
        if (!activeChatId)
            return;
        const configHash = providerConfigHash || computeConfigHash();
        const session = getConfigSession(configHash);
        const chat = session.chats ? session.chats[activeChatId] : null;
        if (!chat)
            return;
        // Only auto-name if it's still the default name
        if (chat.name !== "New chat")
            return;
        const name = userText.trim().length > 40 ? userText.trim().substring(0, 40) + "…" : userText.trim();
        renameChat(activeChatId, name);
    }

    function cancel() {
        if (!isStreaming)
            return;
        chatFetcher.running = false;
        markError(activeStreamId, "Cancelled");
    }

    function findIndexById(msgId) {
        for (let i = 0; i < messagesModel.count; i++) {
            const itm = messagesModel.get(i);
            if (itm.id === msgId)
                return i;
        }
        return -1;
    }

    function markError(streamId, message) {
        const idx = findIndexById(streamId);
        if (idx >= 0) {
            messagesModel.setProperty(idx, "content", message);
            messagesModel.setProperty(idx, "status", "error");
        }
        isStreaming = false;
        activeStreamId = "";
        streamStartedAtMs = 0;
        saveSession();
    }

    function updateStreamContent(streamId, deltaText) {
        if (!deltaText)
            return;
        const idx = findIndexById(streamId);
        if (idx >= 0) {
            const cur = messagesModel.get(idx).content || "";
            messagesModel.setProperty(idx, "content", cur + deltaText);
            messagesModel.setProperty(idx, "status", "streaming");
        }
    }

    function getMessageContentById(msgId) {
        const idx = findIndexById(msgId);
        if (idx >= 0)
            return messagesModel.get(idx).content || "";
        return "";
    }

    function setMessageContentById(msgId, text) {
        const idx = findIndexById(msgId);
        if (idx >= 0) {
            messagesModel.setProperty(idx, "content", text || "");
        }
    }

    function finalizeStream(streamId) {
        const idx = findIndexById(streamId);
        if (idx >= 0) {
            messagesModel.setProperty(idx, "status", "ok");
        }
        isStreaming = false;
        activeStreamId = "";
        streamStartedAtMs = 0;
        isOnline = true;
        if (debugEnabled) {
            const text = getMessageContentById(streamId);
            const preview = (text || "").replace(/\s+/g, " ").slice(0, 300);
            console.log("[AIAssistantService] response finalized" + " chars=", (text || "").length, "preview=", preview);
        }
        saveSession();
        refreshChatsModel();
    }

    // ── Payload / curl ─────────────────────────────────────────────

    function buildPayload(latestText) {
        const msgs = [];
        let needUser = false;
        let turns = 0;
        const maxTurns = 20;

        for (let i = messagesModel.count - 1; i >= 0; i--) {
            const m = messagesModel.get(i);
            if (!m || m.status !== "ok")
                continue;
            if (m.role !== "user" && m.role !== "assistant")
                continue;

            if (!needUser) {
                if (m.role === "assistant" && m.content && m.content.trim().length > 0) {
                    msgs.unshift({
                        role: "assistant",
                        content: m.content
                    });
                    needUser = true;
                }
            } else {
                if (m.role === "user" && m.content && m.content.trim().length > 0) {
                    msgs.unshift({
                        role: "user",
                        content: m.content
                    });
                    needUser = false;
                    turns++;
                    if (turns >= maxTurns)
                        break;
                }
            }
        }

        msgs.push({
            role: "user",
            content: latestText
        });
        return {
            provider: provider,
            baseUrl: baseUrl,
            model: model,
            temperature: temperature,
            max_tokens: maxTokens,
            messages: msgs,
            stream: true,
            timeout: timeout
        };
    }

    function buildCurlCommand(payload) {
        const key = resolveApiKey();
        if (!key)
            return null;

        const req = AIApiAdapters.buildRequest(provider, payload, key);
        if (debugEnabled && req) {
            const redactedUrl = (req.url || "").replace(key, "[REDACTED]");
            console.log("[AIAssistantService] request provider=", provider, "url=", redactedUrl);
            console.log("[AIAssistantService] request body" + "(preview)=", (req.body || "").slice(0, 800));
        }

        return AIApiAdapters.buildCurlCommand(provider, payload, key);
    }

    // ── Stream parsing ─────────────────────────────────────────────

    property string streamBuffer: ""

    function handleStreamChunk(chunk) {
        let buffer = streamBuffer + chunk;
        const parts = buffer.split(/\r?\n/);

        if (buffer.length > 0 && !buffer.endsWith("\n") && !buffer.endsWith("\r")) {
            streamBuffer = parts.pop();
        } else {
            streamBuffer = "";
        }

        for (let i = 0; i < parts.length; i++) {
            const line = parts[i].trim();
            if (!line)
                continue;

            if (line === "data: [DONE]" || line === "data:[DONE]") {
                finalizeStream(activeStreamId);
                continue;
            }

            if (line.startsWith("data:")) {
                const jsonPart = line.substring(5).trim();
                parseProviderDelta(jsonPart);
            }
        }
    }

    function parseProviderDelta(jsonText) {
        try {
            const data = JSON.parse(jsonText);
            if (debugEnabled) {
                console.info(provider, jsonText);
            }
            if (debugEnabled && provider === "gemini") {
                console.log("[AIAssistantService] gemini chunk:", JSON.stringify(data).slice(0, 200));
            }
            if (provider === "anthropic") {
                const delta = data.delta?.text || "";
                if (delta)
                    updateStreamContent(activeStreamId, delta);
                if (data.stop_reason)
                    finalizeStream(activeStreamId);
            } else if (provider === "gemini") {
                const chunks = Array.isArray(data) ? data : [data];
                chunks.forEach(chunk => {
                    const candidate = chunk.candidates?.[0];
                    const parts = candidate?.content?.parts || [];
                    let hasContent = false;
                    parts.forEach(p => {
                        if (p.text) {
                            hasContent = true;
                            updateStreamContent(activeStreamId, p.text);
                        }
                    });
                    const finishReason = candidate?.finishReason;
                    if (finishReason && finishReason !== "FINISH_REASON_UNSPECIFIED") {
                        finalizeStream(activeStreamId);
                    }
                    if (chunk.usageMetadata && !hasContent) {
                        finalizeStream(activeStreamId);
                    }
                });
            } else {
                // openai / custom
                const deltas = data.choices?.[0]?.delta?.content;
                if (Array.isArray(deltas)) {
                    deltas.forEach(d => {
                        if (d.text)
                            updateStreamContent(activeStreamId, d.text);
                    });
                } else if (typeof deltas === "string") {
                    updateStreamContent(activeStreamId, deltas);
                }
                if (data.choices?.[0]?.finish_reason) {
                    finalizeStream(activeStreamId);
                }
            }
        } catch (e) {
            // ignore malformed chunks
        }
    }

    function handleStreamFinished(text) {
        const match = text.match(/DMS_STATUS:(\d+)/);
        if (match) {
            lastHttpStatus = parseInt(match[1]);
        }

        function stripStatusFooter(fullText) {
            const marker = "\nDMS_STATUS:";
            const idx = fullText.lastIndexOf(marker);
            if (idx >= 0)
                return fullText.substring(0, idx);
            return fullText;
        }

        const bodyText = stripStatusFooter(text || "").trim();
        const bodyPreview = bodyText.length > 0 ? bodyText.slice(0, 600) : "";

        if (isStreaming) {
            const existing = getMessageContentById(activeStreamId);
            if ((!existing || existing.length === 0) && bodyText && lastHttpStatus > 0 && lastHttpStatus < 400) {
                const parsed = extractNonStreamingAssistantText(bodyText);
                if (parsed && parsed.length > 0) {
                    setMessageContentById(activeStreamId, parsed);
                }
            }
        }

        if (lastHttpStatus >= 400 && isStreaming) {
            const msg = bodyPreview ? "Request failed (HTTP " + lastHttpStatus + "): " + bodyPreview : "Request failed (HTTP " + lastHttpStatus + ")";
            markError(activeStreamId, msg);
            return;
        }

        if (isStreaming) {
            finalizeStream(activeStreamId);
        }
    }

    function extractNonStreamingAssistantText(bodyText) {
        try {
            const data = JSON.parse(bodyText);
            if (provider === "anthropic") {
                const content = data.content;
                if (Array.isArray(content)) {
                    let out = "";
                    for (let i = 0; i < content.length; i++) {
                        const c = content[i];
                        if (c && c.text)
                            out += c.text;
                    }
                    return out;
                }
                return data.text || "";
            }
            if (provider === "gemini") {
                const chunks = Array.isArray(data) ? data : [data];
                let out = "";
                chunks.forEach(chunk => {
                    const parts = chunk.candidates?.[0]?.content?.parts || [];
                    parts.forEach(p => {
                        if (p && p.text)
                            out += p.text;
                    });
                });
                return out;
            }
            const msg = data.choices?.[0]?.message?.content;
            if (typeof msg === "string")
                return msg;
            const text = data.choices?.[0]?.text;
            if (typeof text === "string")
                return text;
        } catch (e) {
            // ignore
        }
        return "";
    }

    function findLastUserText() {
        for (let i = messagesModel.count - 1; i >= 0; i--) {
            const m = messagesModel.get(i);
            if (m.role === "user" && m.status === "ok")
                return m.content;
        }
        return "";
    }

    // ── Curl process ───────────────────────────────────────────────

    Process {
        id: chatFetcher
        running: false

        stdout: StdioCollector {
            id: streamCollector
            property int lastLen: 0

            onTextChanged: {
                const newData = text.substring(lastLen);
                lastLen = text.length;
                handleStreamChunk(newData);
            }

            onStreamFinished: {
                handleStreamFinished(text);
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0 && isStreaming) {
                markError(activeStreamId, "Request failed (exit " + exitCode + ")");
            }
        }
    }
}
