// Statement coverage of the addons for the test verb's --coverage: which statements the tests ran.
//
// A coverage job loads each addon file instrumented (instrument below): every statement counts
// its own hits, so statements that share a line are told apart, and a nested function's
// statements never count for the code around it. The items, each keyed by the line its function
// is defined on (owner; 0 for the file itself) and the line and column it starts at:
//   * a simple statement (local, assignment, call, return, a named function) counts when it's
//     reached, by a hit marker in front of it; it spans its lines, first to last
//   * an if counts by its condition, which runs whenever the if is reached, so its marker sits
//     in front of the if; an elseif's and a repeat's until condition are wrapped, keeping their
//     value, and count each time they're evaluated; a while counts its condition and a for loop
//     its header, both marked in front of the loop; their bodies are statements of their own
//   * `local x` without a value (or with nil), `do ... end` and `break` are left out: they do
//     nothing a test could miss on their own
//
// Instrumenting keeps every line number and the chunk name ("@Addon/File.lua"), so errors and
// tracebacks read as they do uninstrumented. The file becomes the body of a function that a
// loader chunk returns, given the hit counts as its one upvalue (a marker is `H[i]=H[i]+1;`, a
// wrapped condition `H.t(i, cond)`), all inserted on existing lines: no function gains a local
// and each gains at most that one upvalue, within Lua 5.1's limits (200 locals, 60 upvalues).

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { parse } from "./lua-scope.mjs";

const range = (node) => ({ first: node.loc.start.line, last: node.loc.end.line, column: node.loc.start.column });
const span = (nodes) => ({ ...range(nodes[0]), last: nodes[nodes.length - 1].loc.end.line });

// The items with where their marks go: mark "before" (a statement marker at offset at) or "wrap"
// (the condition from at to end).
function collect(ast) {
    const items = [];
    const add = (owner, lines, mark) => items.push({ owner, ...lines, mark });
    const before = (node) => ({ kind: "before", at: node.range[0] });
    const wrap = (node) => ({ kind: "wrap", at: node.range[0], end: node.range[1] });
    const block = (owner, body) => {
        for (const node of body) statement(owner, node);
    };
    const nested = (node) => walkFunctions(node, (fn) => block(fn.loc.start.line, fn.body));
    function statement(owner, node) {
        switch (node.type) {
            case "LocalStatement":
                if (node.init.length > 0 && !node.init.every((value) => value.type === "NilLiteral")) add(owner, range(node), before(node));
                nested(node);
                return;
            case "AssignmentStatement":
            case "CallStatement":
            case "ReturnStatement":
                add(owner, range(node), before(node));
                nested(node);
                return;
            case "BreakStatement":
                return;
            case "FunctionDeclaration":
                add(owner, range(node), before(node));
                block(node.loc.start.line, node.body);
                return;
            case "IfStatement":
                node.clauses.forEach((clause, i) => {
                    if (clause.condition) {
                        add(owner, range(clause.condition), i === 0 ? before(node) : wrap(clause.condition));
                        nested(clause.condition);
                    }
                    block(owner, clause.body);
                });
                return;
            case "WhileStatement":
                add(owner, range(node.condition), before(node));
                nested(node.condition);
                block(owner, node.body);
                return;
            case "RepeatStatement":
                block(owner, node.body);
                add(owner, range(node.condition), wrap(node.condition));
                nested(node.condition);
                return;
            case "ForNumericStatement": {
                const header = [node.start, node.end, ...(node.step ? [node.step] : [])];
                add(owner, span(header), before(node));
                header.forEach(nested);
                block(owner, node.body);
                return;
            }
            case "ForGenericStatement":
                add(owner, span(node.iterators), before(node));
                node.iterators.forEach(nested);
                block(owner, node.body);
                return;
            case "DoStatement":
                block(owner, node.body);
                return;
            default:
                throw new Error(`coverage: unhandled statement ${node.type} at line ${node.loc.start.line}`);
        }
    }
    block(0, ast.body);
    return items;
}

// The coverage items of a Lua source: [{ owner, first, last, column }], owner the line its
// function is defined on (0 for the chunk), first..last its lines, column where it starts.
export function coverageItems(text) {
    return collect(parse(text)).map(({ owner, first, last, column }) => ({ owner, first, last, column }));
}

// An item's key in the hits: "<line>:<column>" of where it starts.
const keyOf = (item) => `${item.first}:${item.column}`;

// The name of the hit counts in instrumented code; nothing in an addon is named this.
const HITS = "__tlkHits";

// A source rewritten to count its items' hits: { text, items }, or null when it doesn't parse
// (loading the original then reports the syntax error). text is a chunk returning the instrumented
// file as a function of the file's own arguments; call it with the counts table (H[i] = 0 for
// each item, and H.t(i, v), which counts item i and returns v).
export function instrument(source) {
    let items;
    try {
        items = collect(parse(source));
    } catch {
        return null;
    }
    const inserts = [];
    items.forEach((item, index) => {
        const id = index + 1;
        if (item.mark.kind === "before") inserts.push({ at: item.mark.at, order: 1, text: ` ${HITS}[${id}]=${HITS}[${id}]+1;` });
        else {
            inserts.push({ at: item.mark.at, order: 2, text: `${HITS}.t(${id},` });
            inserts.push({ at: item.mark.end, order: 0, text: ")" });
        }
    });
    // At one offset: a wrap's ")" closes before anything opens, and a marker goes before a wrap.
    inserts.sort((a, b) => a.at - b.at || a.order - b.order);
    const parts = [];
    let from = 0;
    for (const insert of inserts) {
        parts.push(source.slice(from, insert.at), insert.text);
        from = insert.at;
    }
    parts.push(source.slice(from));
    // `do local _ = ... end` uses the vararg, so Lua 5.1 gives the function no implicit `arg` local.
    const text = `local ${HITS} = ...; return function(...) do local _ = ... end ${parts.join("")}\nend`;
    return { text, items: items.map(({ owner, first, last, column }) => ({ owner, first, last, column })) };
}

// The Lua side of a coverage job: __coverageStart() makes loadstring instrument the addons'
// chunks ("@Addon/File.lua", the names Harness:LoadFiles in tests/harness/wow.lua loads each file
// under) through __instrument (a JS function: source, chunk name -> "<id>\t<count>\n<text>", or
// nil), compiling each distinct source once; __coverageStop() restores it; __coverageHits()
// returns "<id>\t<item>,<item>..." per instrumented source, the items that ran.
export const COVERAGE_LUA = `
    local realLoadstring = loadstring
    local loaded = {}
    local records = {}
    local function CoverageLoadstring(source, chunkName)
        if type(source) ~= "string" or type(chunkName) ~= "string" or not chunkName:find("^@[^/]+/.+%.lua$") then
            return realLoadstring(source, chunkName)
        end
        local byName = loaded[chunkName]
        if not byName then
            byName = {}
            loaded[chunkName] = byName
        end
        local entry = byName[source]
        if not entry then
            local encoded = __instrument(source, chunkName)
            if not encoded then return realLoadstring(source, chunkName) end
            local id, count, text = encoded:match("^(%d+)\\t(%d+)\\n(.*)$")
            local outer, err = realLoadstring(text, chunkName)
            if not outer then return nil, err end
            local hits = {}
            for i = 1, tonumber(count) do hits[i] = 0 end
            hits.t = function(i, v)
                hits[i] = hits[i] + 1
                return v
            end
            entry = { id = id, outer = outer, hits = hits, count = tonumber(count) }
            byName[source] = entry
            records[#records + 1] = entry
        end
        return entry.outer(entry.hits)
    end
    function __coverageStart() loadstring = CoverageLoadstring end
    function __coverageStop() loadstring = realLoadstring end
    function __coverageHits()
        local out = {}
        for _, entry in ipairs(records) do
            local ran = {}
            for i = 1, entry.count do
                if entry.hits[i] > 0 then ran[#ran + 1] = i end
            end
            if #ran > 0 then out[#out + 1] = entry.id .. "\\t" .. table.concat(ran, ",") end
        end
        return table.concat(out, "\\n")
    end
`;

// The JS side of a coverage job: instrument(source, chunkName) for COVERAGE_LUA's __instrument,
// and hitsText(text), which turns __coverageHits()'s output into mergeHits' input.
export function createCoverage() {
    const sources = [];
    return {
        instrument(source, chunkName) {
            const result = instrument(source);
            if (!result) return null;
            sources.push({ chunkName, items: result.items });
            return `${sources.length}\t${result.items.length}\n${result.text}`;
        },
        hitsText(text) {
            const lines = [];
            for (const line of (text ?? "").split("\n")) {
                if (!line) continue;
                const [id, ran] = line.split("\t");
                const { chunkName, items } = sources[Number(id) - 1];
                const byOwner = new Map();
                for (const index of ran.split(",")) {
                    const item = items[Number(index) - 1];
                    if (!byOwner.has(item.owner)) byOwner.set(item.owner, []);
                    byOwner.get(item.owner).push(keyOf(item));
                }
                for (const [owner, keys] of byOwner) lines.push(`${chunkName}\t${owner}\t${keys.join(",")}`);
            }
            return lines.join("\n");
        },
    };
}

// Calls visit(fn) for each function expression in an expression tree, outermost only: its own
// statements (and their functions) are visit's to walk.
function walkFunctions(node, visit) {
    if (!node || typeof node !== "object") return;
    if (Array.isArray(node)) {
        for (const child of node) walkFunctions(child, visit);
        return;
    }
    if (node.type === "FunctionDeclaration") {
        visit(node);
        return;
    }
    for (const [key, value] of Object.entries(node)) {
        if (key !== "loc" && key !== "range") walkFunctions(value, visit);
    }
}

// Reads the hits ("<source>\t<owner>\t<line>:<column>,..." lines, from any number of jobs) into
// Map(source -> Map(owner -> Set("<line>:<column>"))).
export function mergeHits(texts) {
    const hits = new Map();
    for (const text of texts) {
        for (const line of text.split("\n")) {
            if (!line) continue;
            const [source, owner, keys] = line.split("\t");
            if (!hits.has(source)) hits.set(source, new Map());
            const owners = hits.get(source);
            if (!owners.has(Number(owner))) owners.set(Number(owner), new Set());
            const set = owners.get(Number(owner));
            for (const key of keys.split(",")) set.add(key);
        }
    }
    return hits;
}

// Coverage per addon file: [{ file: "Addon/File.lua", total, covered, missed }], every TOC-listed
// Lua file of addons (findAddons' entries) in TOC order. missed holds the uncovered statements as
// runs, "12" or "12-30" (first lines of the run's first and last statements).
export function coverageReport(hits, addons) {
    const files = [];
    for (const addon of addons) {
        for (const file of addon.files.filter((f) => f.endsWith(".lua"))) {
            const name = `${addon.name}/${file}`;
            const owners = hits.get(`@${name}`) ?? new Map();
            const items = coverageItems(readFileSync(join(addon.dir, file), "utf8")).sort((a, b) => a.first - b.first || a.column - b.column);
            const runs = [];
            let covered = 0;
            let open = null;
            for (const item of items) {
                if (owners.get(item.owner)?.has(keyOf(item))) {
                    covered++;
                    open = null;
                } else if (open) {
                    open.last = item.first;
                } else {
                    open = { first: item.first, last: item.first };
                    runs.push(open);
                }
            }
            const missed = runs.map((run) => (run.first === run.last ? `${run.first}` : `${run.first}-${run.last}`));
            files.push({ file: name, total: items.length, covered, missed });
        }
    }
    return files;
}
