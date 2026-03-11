// AISessionUtils.js - Pure functions for session and chat management

function migrateSessionData(data) {
    if (data.version >= 3 && data.sessions && typeof data.sessions === "object") {
        return data.sessions;
    } else if (data.version >= 2 && data.sessions && typeof data.sessions === "object") {
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
        return migrated;
    } else {
        const msgs = Array.isArray(data.messages) ? data.messages : [];
        const chatId = "chat-migrated";
        const chatName = autoNameFromMessages(msgs) || "Migrated chat";
        return {
            "legacy-migrated": {
                chats: {},
                activeChatId: chatId
            }
        };
    }
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

function getConfigSession(sessionsByConfig, configHash) {
    if (sessionsByConfig && sessionsByConfig[configHash] && typeof sessionsByConfig[configHash] === "object" && sessionsByConfig[configHash].chats) {
        return sessionsByConfig[configHash];
    }
    return {
        chats: {},
        activeChatId: ""
    };
}

function ensureConfigSession(sessionsByConfig, configHash) {
    if (!sessionsByConfig)
        sessionsByConfig = {};
    if (!sessionsByConfig[configHash] || typeof sessionsByConfig[configHash] !== "object" || !sessionsByConfig[configHash].chats) {
        const next = Object.assign({}, sessionsByConfig);
        next[configHash] = {
            chats: {},
            activeChatId: ""
        };
        return { sessions: next, session: next[configHash] };
    }
    return { sessions: sessionsByConfig, session: sessionsByConfig[configHash] };
}

function createChatEntry(chatId, name, messages) {
    return {
        name: name,
        createdAt: Date.now(),
        messages: messages || []
    };
}

function persistMessages(sessionsByConfig, configHash, chatId, messages, maxStored) {
    if (!configHash || !chatId)
        return sessionsByConfig;

    const msgs = [];
    for (let i = 0; i < messages.length; i++) {
        const m = messages[i];
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
    const capped = msgs.length > maxStored ? msgs.slice(msgs.length - maxStored) : msgs;

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
    return next;
}
