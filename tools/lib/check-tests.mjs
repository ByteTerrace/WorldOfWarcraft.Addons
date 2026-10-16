// The GLOBAL rule for the tests' Lua: every global read is one that world defines. The tests' Lua
// (tests/*.lua, tests/kits, and tests/harness) runs in the test runner's Lua, not the client's.
// That world is Lua 5.1's own library, the runner's preludes (tools/lib/test-worker.mjs and
// coverage.mjs) such as test, eq, and use, the values the runner hands the Lua
// (lua.ctx.__snapshot and the rest), and every global some tests' Lua file assigns. An undefined
// global reads nil there, so a misspelled or moved name fails far from its cause.

import { analyze, parse, walk } from "./lua-scope.mjs";

const LuaGlobals = new Set([
    "_G", "_VERSION", "assert", "collectgarbage", "coroutine", "debug", "dofile", "error", "gcinfo", "getfenv",
    "getmetatable", "io", "ipairs", "load", "loadfile", "loadstring", "math", "module", "newproxy", "next", "os",
    "package", "pairs", "pcall", "print", "rawequal", "rawget", "rawset", "require", "select", "setfenv",
    "setmetatable", "string", "table", "tonumber", "tostring", "type", "unpack", "xpcall",
]);

/**
 * The globals a chunk reads ({ name, line }) and writes (names), by Lua's scoping.
 * @param {string} text
 */
export function globalAccesses(text) {
    const ast = parse(text);
    const scope = analyze(ast);
    const reads = [];
    const writes = new Set();
    walk(ast.body, (node, ancestors) => {
        if ((node.type !== "Identifier") || scope.bindingOf(node)) return;
        const parent = ancestors[ancestors.length - 1];
        const isName = ((parent?.type === "MemberExpression") && (parent.identifier === node))
            || ((parent?.type === "TableKeyString") && (parent.key === node))
            || ((parent?.type === "FunctionDeclaration") && parent.parameters.includes(node));
        if (isName) return;
        const isWrite = ((parent?.type === "AssignmentStatement") && parent.variables.includes(node))
            || ((parent?.type === "FunctionDeclaration") && (parent.identifier === node));
        if (isWrite) writes.add(node.name);
        else reads.push({ line: node.loc.start.line, name: node.name });
    });
    return { reads, writes };
}

/**
 * Reports each read of a global the tests' world doesn't define.
 * @param {{ path: string, text: string }[]} files the tests' Lua files
 * @param {string[]} preludes the Lua the runner runs before them
 * @param {Iterable<string>} handed the globals the runner sets from JavaScript
 * @param {(file: string, line: number, rule: string, message: string) => void} report
 */
export function checkTestGlobals(files, preludes, handed, report) {
    const defined = new Set([...LuaGlobals, ...handed]);
    const accesses = [];
    for (const source of [...preludes.map((text) => ({ path: null, text })), ...files]) {
        let found;
        try {
            found = globalAccesses(source.text);
        } catch {
            continue; // PARSE (or the runner) reports it
        }
        for (const name of found.writes) defined.add(name);
        if (source.path) accesses.push({ path: source.path, reads: found.reads });
    }
    for (const { path, reads } of accesses) {
        for (const { line, name } of reads) {
            if (!defined.has(name)) report(path, line, "GLOBAL", `read of ${name}, which nothing in the tests' Lua, the runner or Lua defines`);
        }
    }
}
