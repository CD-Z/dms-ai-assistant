.pragma library

/**
 * Splits markdown into an array of segments:
 *   { type: "markdown", content: "..." }
 *   { type: "code",     lang: "...", content: "..." }
 */
function parse(md) {
    const segments = [];
    const fence = /^```([^\n]*)\n([\s\S]*?)^```/gm;
    let last = 0;
    let match;

    while ((match = fence.exec(md)) !== null) {
        if (match.index > last) {
            const text = md.slice(last, match.index).trim();
            if (text) segments.push({ type: "markdown", content: text });
        }
        segments.push({
            type: "code",
            lang: match[1].trim() || "text",
            content: match[2]  // keep trailing newline for display
        });
        last = match.index + match[0].length;
    }

    const tail = md.slice(last).trim();
    if (tail) segments.push({ type: "markdown", content: tail });

    return segments;
}
