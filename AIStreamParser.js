// AIStreamParser.js - Pure functions for parsing streaming responses

function parseProviderDelta(provider, jsonText, debugEnabled) {
    try {
        const data = JSON.parse(jsonText);
        if (debugEnabled) {
            console.info(provider, jsonText);
        }
        if (debugEnabled && provider === "gemini") {
            console.log("[AIAssistantService] gemini chunk:", JSON.stringify(data).slice(0, 200));
        }

        let delta = "";
        let finalized = false;

        if (provider === "anthropic") {
            delta = data.delta?.text || "";
            if (data.stop_reason)
                finalized = true;
        } else if (provider === "gemini") {
            const chunks = Array.isArray(data) ? data : [data];
            chunks.forEach(chunk => {
                const candidate = chunk.candidates?.[0];
                const parts = candidate?.content?.parts || [];
                let hasContent = false;
                parts.forEach(p => {
                    if (p.text) {
                        hasContent = true;
                        delta += p.text;
                    }
                });
                const finishReason = candidate?.finishReason;
                if (finishReason && finishReason !== "FINISH_REASON_UNSPECIFIED") {
                    finalized = true;
                }
                if (chunk.usageMetadata && !hasContent) {
                    finalized = true;
                }
            });
        } else {
            // openai / custom
            const deltas = data.choices?.[0]?.delta?.content;
            if (Array.isArray(deltas)) {
                deltas.forEach(d => {
                    if (d.text)
                        delta += d.text;
                });
            } else if (typeof deltas === "string") {
                delta = deltas;
            }
            if (data.choices?.[0]?.finish_reason) {
                finalized = true;
            }
        }

        return { delta: delta, finalized: finalized };
    } catch (e) {
        return { delta: "", finalized: false };
    }
}

function extractNonStreamingAssistantText(provider, bodyText) {
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

function handleStatusFooter(text) {
    const marker = "\nDMS_STATUS:";
    const idx = text.lastIndexOf(marker);
    if (idx >= 0) {
        return {
            body: text.substring(0, idx),
            status: parseInt(text.substring(idx + marker.length))
        };
    }
    return { body: text, status: 0 };
}
