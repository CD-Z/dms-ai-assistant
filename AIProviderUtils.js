// AIProviderUtils.js - Pure functions for provider configuration

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

function computeConfigHash(provider, baseUrl, model) {
    return provider + "|" + baseUrl + "|" + model;
}
