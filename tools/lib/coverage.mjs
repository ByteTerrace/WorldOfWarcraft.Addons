// Statement coverage of the addons for the test verb's --coverage: which statements the tests ran.
//
// The worker's line hook (test-worker.mjs) records, per chunk ("@Addon/File.lua"), the lines each
// function ran, keyed by the line the function is defined on (Lua's linedefined; 0 for the file
// itself), so a nested function's lines never count for the code around it. A statement is
// covered when a line it owns ran in the function that holds it:
//   * a simple statement (local, assignment, call, return, a named function) owns its
//     lines, first to last; a nested function's body runs as that function, so it doesn't count
//   * if and elseif own their condition's lines, while its condition's, repeat its until
//     condition's, and a for loop its header's; their bodies are statements of their own
//   * `local x` without a value (or with nil) and `do ... end` are left out: Lua compiles no
//     instruction for them on their own line, so no line ever runs for them. So is `break`: in
//     `if a or b then break end` Lua jumps from `a` straight out of the loop, so its line runs
//     only on some of the ways it's reached
// Lines are the hook's granularity: statements that share a line share its hit, so a one-line
// `if not ready then return end` counts its return as covered whenever its condition ran.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { parse } from "./lua-scope.mjs";

const range = (node) => ({ first: node.loc.start.line, last: node.loc.end.line });
const span = (nodes) => ({ first: nodes[0].loc.start.line, last: nodes[nodes.length - 1].loc.end.line });

// The coverage items of a Lua source: [{ owner, first, last }], owner the line its function is
// defined on (0 for the chunk), first..last the lines that count for it.
export function coverageItems(text) {
    const items = [];
    const add = (owner, lines) => items.push({ owner, ...lines });
    const block = (owner, body) => {
        for (const node of body) statement(owner, node);
    };
    const nested = (node) => walkFunctions(node, (fn) => block(fn.loc.start.line, fn.body));
    function statement(owner, node) {
        switch (node.type) {
            case "LocalStatement":
                if (node.init.length > 0 && !node.init.every((value) => value.type === "NilLiteral")) add(owner, range(node));
                nested(node);
                return;
            case "AssignmentStatement":
            case "CallStatement":
            case "ReturnStatement":
                add(owner, range(node));
                nested(node);
                return;
            case "BreakStatement":
                return;
            case "FunctionDeclaration":
                add(owner, range(node));
                block(node.loc.start.line, node.body);
                return;
            case "IfStatement":
                for (const clause of node.clauses) {
                    if (clause.condition) {
                        add(owner, range(clause.condition));
                        nested(clause.condition);
                    }
                    block(owner, clause.body);
                }
                return;
            case "WhileStatement":
                add(owner, range(node.condition));
                nested(node.condition);
                block(owner, node.body);
                return;
            case "RepeatStatement":
                block(owner, node.body);
                add(owner, range(node.condition));
                nested(node.condition);
                return;
            case "ForNumericStatement": {
                const header = [node.start, node.end, ...(node.step ? [node.step] : [])];
                add(owner, span(header));
                header.forEach(nested);
                block(owner, node.body);
                return;
            }
            case "ForGenericStatement":
                add(owner, span(node.iterators));
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
    block(0, parse(text).body);
    return items;
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

// Reads the hook's hits ("<source>\t<owner>\t<line>,<line>..." lines, from any number of jobs)
// into Map(source -> Map(owner -> Set(line))).
export function mergeHits(texts) {
    const hits = new Map();
    for (const text of texts) {
        for (const line of text.split("\n")) {
            if (!line) continue;
            const [source, owner, lines] = line.split("\t");
            if (!hits.has(source)) hits.set(source, new Map());
            const owners = hits.get(source);
            if (!owners.has(Number(owner))) owners.set(Number(owner), new Set());
            const set = owners.get(Number(owner));
            for (const n of lines.split(",")) set.add(Number(n));
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
            const items = coverageItems(readFileSync(join(addon.dir, file), "utf8")).sort((a, b) => a.first - b.first);
            const runs = [];
            let covered = 0;
            let open = null;
            for (const item of items) {
                const ran = owners.get(item.owner);
                let hit = false;
                for (let line = item.first; ran && !hit && line <= item.last; line++) hit = ran.has(line);
                if (hit) {
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
