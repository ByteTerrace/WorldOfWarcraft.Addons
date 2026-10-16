// The harness's guesses (tests/harness/*.lua): each [G] (a guess where the docs are silent) and [C] (a conservative
// fallback) with the claim it makes, the client names the claim is about, and how much depends on it, so the guesses
// worth a probe come first.
//
// A guess's claim is the text from its marker to the end of its sentence or the next marker; a marker in parentheses
// or followed by punctuation ("([G] the order)", "is restricted [C].") marks the sentence it sits in instead. Its
// names are the snapshot's functions and events and the harness's methods the claim mentions, plus the function a
// comment sits directly above (a fake or a Harness method). A namespace member named alone ("GetPowerLevel")
// resolves to the one snapshot function it ends.
//
//   findGuesses(path, text)                  [{ path, line, marker, claim, words, follows }]
//   rankGuesses(guesses, sources)            the guesses with names, addons, tests and probes, most depended on first

const Marker = /\[([GCDE])\]/g;
const SentenceEnd = /[.!?](?=\s|$)/g;
const Word = /[A-Za-z_][A-Za-z0-9_]*(?:[.:][A-Za-z_][A-Za-z0-9_]*)*/g;
const FunctionLine = /^\s*(?:local\s+)?function\s+([\w.:]+)\s*\(|^\s*\[?"?(\w+)"?\]?\s*=\s*function\b/;

// The comment blocks of a Lua file: runs of comment lines, as { text, starts, first, end } where starts[i] is where
// line i of the block begins in text, and first and end are the block's first and last line numbers (1-based).
function commentBlocks(text) {
    const lines = text.split("\n");
    const blocks = [];
    let block = null;
    lines.forEach((raw, index) => {
        const match = /^\s*--+\s?(.*)$/.exec(raw);
        if (!match) {
            if (block) blocks.push(block);
            block = null;
            return;
        }
        block ??= { end: 0, first: index + 1, starts: [], text: "" };
        if (block.text) block.text += " ";
        block.starts.push(block.text.length);
        block.text += match[1].trim();
        block.end = index + 1;
    });
    if (block) blocks.push(block);
    return { blocks, lines };
}

// The 1-based line of the block that holds offset.
function lineAt(block, offset) {
    let line = 0;
    while ((line + 1) < block.starts.length && block.starts[line + 1] <= offset) line++;
    return block.first + line;
}

// Where the sentence holding offset starts and ends in text.
function sentenceAround(text, offset) {
    let start = 0;
    let end = text.length;
    for (const match of text.matchAll(SentenceEnd)) {
        if (match.index < offset) start = match.index + 1;
        else {
            end = match.index + 1;
            break;
        }
    }
    return [start, end];
}

// A claim without its markers: "([G])" goes, "([G]: x" keeps "(x", and a ")" the claim never opened goes too.
function clean(claim) {
    let text = claim.replace(/\(\s*\[[GCDE]\]\s*\)/g, "").replace(/\(\s*\[[GCDE]\]\s*[:,]?\s*/g, "(")
        .replace(/\s*\[[GCDE]\]\s*/g, " ").replace(/\s+/g, " ").replace(/\s+([.,;:)])/g, "$1").trim();
    const opened = (text.match(/\(/g) ?? []).length;
    if ((text.match(/\)/g) ?? []).length > opened) text = text.replace(/\)([.,;]?)$/, "$1");
    return text;
}

export function findGuesses(path, text) {
    const { blocks, lines } = commentBlocks(text);
    const guesses = [];
    for (const block of blocks) {
        const markers = [...block.text.matchAll(Marker)];
        const next = lines[block.end] ?? "";
        const defined = FunctionLine.exec(next);
        const follows = defined ? (defined[1] ?? defined[2]).split(/[.:]/).at(-1) : null;
        markers.forEach((match, i) => {
            if (match[1] !== "G" && match[1] !== "C") return;
            const at = match.index;
            const after = block.text.slice(at + 3);
            const inside = block.text[at - 1] === "(" || /^\s*([.,;:)]|$)/.test(after);
            let claim;
            if (inside) {
                const [start, end] = sentenceAround(block.text, at);
                claim = block.text.slice(start, end);
            } else {
                const stop = Math.min(markers[i + 1]?.index ?? block.text.length, sentenceAround(block.text, at + 3)[1]);
                claim = block.text.slice(at + 3, stop);
            }
            claim = clean(claim);
            guesses.push({ claim, follows, line: lineAt(block, at), marker: match[1], path, words: claim.match(Word) ?? [] });
        });
    }
    return guesses;
}

const escape = (name) => name.replace(/[.:]/g, "\\$&");

// Whether a word can name the client's API: an event (UPPER_CASE) or a function with a capital in it. Lua's own
// library ("format", "table.count") reads as prose.
const ApiShaped = (word) => /^[A-Z][A-Z0-9_]+$/.test(word) || (/[A-Z]/.test(word) && !/^(bit|coroutine|math|os|string|table)\./.test(word));

// The snapshot names, events and Harness methods a guess is about. A member resolves only when it starts with a
// capital, as the client's do.
function namesOf(guess, { events, functions, members, methods }) {
    const names = new Set();
    const add = (word) => {
        const bare = word.replace(/^(h|Harness|self):/, "");
        if ((functions.has(bare) || events.has(bare)) && ApiShaped(bare)) names.add(bare);
        else if (methods.has(bare) && word !== bare) names.add(`h:${bare}`);
        else if (/^[A-Z]/.test(bare) && members.has(bare) && members.get(bare).length === 1) names.add(members.get(bare)[0]);
    };
    for (const word of guess.words) add(word);
    if (guess.follows) {
        if (methods.has(guess.follows)) names.add(`h:${guess.follows}`);
        else add(guess.follows);
    }
    return [...names].sort();
}

// Whether a source mentions a snapshot name: a namespace member by its namespace and its member, an event or a
// global by its word.
function mentions(text, name) {
    const dot = name.indexOf(".");
    if (dot < 0) return new RegExp(`\\b${escape(name)}\\b`).test(text);
    return new RegExp(`\\b${escape(name.slice(0, dot))}\\b`).test(text) && new RegExp(`\\.${escape(name.slice(dot + 1))}\\b`).test(text);
}

// sources: { api: { functions, events }, methods: [Harness method names], addons: [{ path, text }] (shipped addons'
// Lua), tests: [{ path, text }] (test files), probes: [{ name, text }] (each probe's definition) }.
export function rankGuesses(guesses, sources) {
    const functions = new Set(Object.keys(sources.api.functions ?? {}));
    const events = new Set(Object.keys(sources.api.events ?? {}));
    const members = new Map();
    for (const name of functions) {
        const dot = name.indexOf(".");
        if (dot < 0) continue;
        const member = name.slice(dot + 1);
        members.set(member, [...(members.get(member) ?? []), name]);
    }
    const lookup = { events, functions, members, methods: new Set(sources.methods) };
    const probeNames = new Set(sources.probes.map((probe) => probe.name));
    return guesses.map((guess) => {
        const names = namesOf(guess, lookup);
        const api = names.filter((name) => !name.startsWith("h:"));
        const harness = names.filter((name) => name.startsWith("h:")).map((name) => name.slice(2));
        const addons = sources.addons.filter((file) => api.some((name) => mentions(file.text, name))).map((file) => file.path);
        const tests = sources.tests.filter((file) => harness.some((name) => new RegExp(`:${escape(name)}\\(`).test(file.text)))
            .map((file) => file.path);
        const cited = guess.words.filter((word) => probeNames.has(word));
        const related = sources.probes.filter((probe) => !cited.includes(probe.name) && api.some((name) => mentions(probe.text, name)))
            .map((probe) => probe.name);
        return { ...guess, addons, cited, names, related, tests };
    }).sort((a, b) => (b.addons.length - a.addons.length) || (b.tests.length - a.tests.length)
        || a.path.localeCompare(b.path) || (a.line - b.line));
}
