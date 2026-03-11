#include "MarkdownParser.h"
#include "md4c.h"
#include <QByteArray>
#include <QStack>
#include <QVariantMap>
#include <QVariantList>

// ── Segment kinds ─────────────────────────────────────────────────────────────

enum class SegKind { Code, Table };

struct RawSegment {
    SegKind kind;

    // Source byte range in the original UTF-8 input
    MD_OFFSET start = 0;
    MD_OFFSET end   = 0;

    // Code
    QString lang;
    QString codeContent;

    // Table
    QStringList         headers;
    QList<QStringList>  rows;
};

// ── Parser state ──────────────────────────────────────────────────────────────

struct ParserState {
    const char *src     = nullptr;
    MD_SIZE     srcSize = 0;

    QList<RawSegment> segments;

    // Depth tracking so we ignore nested blocks
    int  codeDepth  = 0;
    int  tableDepth = 0;
    int  thDepth    = 0;
    int  tdDepth    = 0;
    bool inHead     = false;

    RawSegment current;

    // For content accumulation (code text, cell text)
    QString cellBuf;
    QString codeBuf;

    // Current block's start offset — md4c doesn't give it directly,
    // so we reconstruct via the source pointer delta trick below.
    // Instead we use a lightweight pre-scan (see parse() below) to
    // find fence/table offsets, then md4c only parses table content.
};

// ── Callbacks ─────────────────────────────────────────────────────────────────

static int enterBlock(MD_BLOCKTYPE type, void *detail, void *userdata)
{
    auto *st = static_cast<ParserState *>(userdata);

    switch (type) {
    case MD_BLOCK_CODE:
        if (st->codeDepth++ == 0) {
            auto *d = static_cast<MD_BLOCK_CODE_DETAIL *>(detail);
            st->current       = {};
            st->current.kind  = SegKind::Code;
            st->current.lang  = d->lang.size
                ? QString::fromUtf8(d->lang.text,
                                    static_cast<int>(d->lang.size)).trimmed()
                : QStringLiteral("text");
            st->codeBuf.clear();
        }
        break;

    case MD_BLOCK_TABLE:
        if (st->tableDepth++ == 0) {
            st->current         = {};
            st->current.kind    = SegKind::Table;
        }
        break;

    case MD_BLOCK_THEAD:
        st->inHead = true;
        break;

    case MD_BLOCK_TBODY:
        st->inHead = false;
        break;

    case MD_BLOCK_TR:
        if (st->tableDepth > 0 && !st->inHead)
            st->current.rows.append(QStringList{});
        break;

    case MD_BLOCK_TH:
        ++st->thDepth;
        st->cellBuf.clear();
        break;

    case MD_BLOCK_TD:
        ++st->tdDepth;
        st->cellBuf.clear();
        break;

    default:
        break;
    }
    return 0;
}

static int leaveBlock(MD_BLOCKTYPE type, void * /*detail*/, void *userdata)
{
    auto *st = static_cast<ParserState *>(userdata);

    switch (type) {
    case MD_BLOCK_CODE:
        if (--st->codeDepth == 0) {
            st->current.codeContent = st->codeBuf;
            st->segments.append(st->current);
        }
        break;

    case MD_BLOCK_TABLE:
        if (--st->tableDepth == 0)
            st->segments.append(st->current);
        break;

    case MD_BLOCK_TH:
        if (--st->thDepth == 0)
            st->current.headers.append(st->cellBuf.trimmed());
        break;

    case MD_BLOCK_TD:
        if (--st->tdDepth == 0) {
            if (!st->current.rows.isEmpty())
                st->current.rows.last().append(st->cellBuf.trimmed());
        }
        break;

    default:
        break;
    }
    return 0;
}

static int enterSpan(MD_SPANTYPE, void *, void *) { return 0; }
static int leaveSpan(MD_SPANTYPE, void *, void *) { return 0; }

static int textCallback(MD_TEXTTYPE type, const MD_CHAR *text,
                        MD_SIZE size, void *userdata)
{
    auto   *st  = static_cast<ParserState *>(userdata);
    QString str = QString::fromUtf8(text, static_cast<int>(size));

    if (st->codeDepth > 0) {
        st->codeBuf += str;
        return 0;
    }

    if (st->thDepth > 0 || st->tdDepth > 0) {
        st->cellBuf += str;
        return 0;
    }

    return 0;
}

// ── Pre-scanner: find byte ranges of fenced code blocks and tables ─────────────
//
// md4c's callbacks don't expose source offsets directly. We do one cheap
// linear scan to record where each code fence and table block starts and
// ends, so we can slice the original source for markdown segments.

struct BlockRange {
    SegKind   kind;
    int       start; // byte offset in UTF-8 source
    int       end;
};

static QList<BlockRange> findBlockRanges(const QByteArray &src)
{
    QList<BlockRange> ranges;
    const char *data = src.constData();
    int         len  = src.size();
    int         i    = 0;

    while (i < len) {
        // ── Fenced code block ─────────────────────────────────────────────────
        // Look for ``` at the start of a line (after optional spaces)
        if ((i == 0 || data[i - 1] == '\n')) {
            int j = i;
            while (j < len && data[j] == ' ') ++j; // up to 3 leading spaces

            char fence = (j < len) ? data[j] : 0;
            if (fence == '`' || fence == '~') {
                int fenceLen = 0;
                while (j + fenceLen < len && data[j + fenceLen] == fence)
                    ++fenceLen;

                if (fenceLen >= 3) {
                    // Find the closing fence
                    int blockStart = i;
                    // Skip to end of opening fence line
                    int k = j + fenceLen;
                    while (k < len && data[k] != '\n') ++k;
                    if (k < len) ++k; // skip newline

                    bool closed = false;
                    while (k < len) {
                        // Check for closing fence at line start
                        int l = k;
                        while (l < len && data[l] == ' ') ++l;
                        int cl = 0;
                        while (l + cl < len && data[l + cl] == fence) ++cl;
                        if (cl >= fenceLen) {
                            // Valid closing fence — skip to end of line
                            while (l + cl < len && data[l + cl] != '\n')
                                ++cl;
                            int blockEnd = l + cl;
                            if (blockEnd < len && data[blockEnd] == '\n')
                                ++blockEnd;
                            ranges.append({ SegKind::Code,
                                            blockStart, blockEnd });
                            i = blockEnd;
                            closed = true;
                            break;
                        }
                        // Skip to next line
                        while (k < len && data[k] != '\n') ++k;
                        if (k < len) ++k;
                    }
                    if (!closed) i = k;
                    continue;
                }
            }
        }

        // ── Table block ───────────────────────────────────────────────────────
        // Detect a table by looking for a line that starts with '|'
        // followed by a separator line (|---|).
        if ((i == 0 || data[i - 1] == '\n') && i < len && data[i] == '|') {
            // Check next non-empty line for separator
            int k = i;
            while (k < len && data[k] != '\n') ++k;
            if (k < len) {
                int sepStart = k + 1;
                int s = sepStart;
                // Separator line must contain only |, -, :, space
                bool isSep = true;
                bool hasDash = false;
                while (s < len && data[s] != '\n') {
                    char c = data[s];
                    if (c == '-') hasDash = true;
                    else if (c != '|' && c != ':' && c != ' ' && c != '\t') {
                        isSep = false;
                        break;
                    }
                    ++s;
                }
                if (isSep && hasDash) {
                    int blockStart = i;
                    int t = s;
                    if (t < len) ++t; // skip separator newline
                    // Consume all following lines that start with '|'
                    while (t < len) {
                        if (data[t] == '|') {
                            while (t < len && data[t] != '\n') ++t;
                            if (t < len) ++t;
                        } else {
                            break;
                        }
                    }
                    ranges.append({ SegKind::Table, blockStart, t });
                    i = t;
                    continue;
                }
            }
        }

        // Advance to next line
        while (i < len && data[i] != '\n') ++i;
        if (i < len) ++i;
    }

    return ranges;
}

// ── Public API ────────────────────────────────────────────────────────────────

MarkdownParser::MarkdownParser(QObject *parent) : QObject(parent) {}

QVariantList MarkdownParser::parse(const QString &markdown) const
{
    if (markdown.trimmed().isEmpty()) return {};

    QByteArray utf8 = markdown.toUtf8();

    // 1. Find raw byte ranges of code/table blocks
    QList<BlockRange> ranges = findBlockRanges(utf8);

    // 2. Run md4c to get structured table/code data
    ParserState st;
    st.src     = utf8.constData();
    st.srcSize = static_cast<MD_SIZE>(utf8.size());

    MD_PARSER parser{};
    parser.flags       = MD_FLAG_TABLES
                       | MD_FLAG_STRIKETHROUGH
                       | MD_FLAG_TASKLISTS
                       | MD_FLAG_LATEXMATHSPANS;
    parser.enter_block = enterBlock;
    parser.leave_block = leaveBlock;
    parser.enter_span  = enterSpan;
    parser.leave_span  = leaveSpan;
    parser.text        = textCallback;

    md_parse(utf8.constData(), st.srcSize, &parser, &st);

    // 3. Build final segment list by interleaving raw source slices
    //    with structured code/table data
    QVariantList result;
    int          srcPos       = 0;
    int          structIdx    = 0; // index into st.segments

    for (const BlockRange &range : ranges) {
        // Markdown text before this block
        if (range.start > srcPos) {
            QString slice = QString::fromUtf8(
                utf8.constData() + srcPos,
                range.start - srcPos
            ).trimmed();
            if (!slice.isEmpty()) {
                QVariantMap seg;
                seg["type"]    = "markdown";
                seg["content"] = slice;
                result.append(seg);
            }
        }

        // The structured segment from md4c (same order as ranges)
        if (structIdx < st.segments.size()) {
            const RawSegment &rs = st.segments[structIdx++];
            QVariantMap seg;

            if (rs.kind == SegKind::Code) {
                seg["type"]    = "code";
                seg["lang"]    = rs.lang;
                seg["content"] = rs.codeContent;
            } else {
                seg["type"] = "table";
                seg["headers"] = QVariant(rs.headers);
                QVariantList rows;
                for (const QStringList &row : rs.rows)
                    rows.append(QVariant(row));
                seg["rows"] = rows;
            }
            result.append(seg);
        }

        srcPos = range.end;
    }

    // Trailing markdown after the last block
    if (srcPos < utf8.size()) {
        QString tail = QString::fromUtf8(
            utf8.constData() + srcPos,
            utf8.size() - srcPos
        ).trimmed();
        if (!tail.isEmpty()) {
            QVariantMap seg;
            seg["type"]    = "markdown";
            seg["content"] = tail;
            result.append(seg);
        }
    }

    return result;
}
