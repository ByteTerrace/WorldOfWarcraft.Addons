// Static gates over every addon. Each finding is `path:line: RULE message`; any finding fails.
//
//   PARSE    every .lua parses as Lua 5.1.
//   TOC      the TOC lists every .lua in the addon folder, only files that exist, and only
//            dependencies that exist; ## Interface matches the installed Forever client.
//   GLOBAL   a global read names something the client or a loaded addon defines; a global write
//            is declared (SavedVariables, AddonCompartmentFunc, SLASH_*, or ## X-Globals).
//   MEMBER   Namespace.member exists in the API snapshot (e.g. C_GamePad.SetVibration).
//   EVENT    an event name passed to On / RegisterEvent / RegisterUnitEvent / Fire is a real event.
//   SECRET   a call to a function that can return a secret value is either inside a function that
//            checks issecretvalue, or annotated `-- secret: <why>` on its line or the line above
//            (e.g. "widget sink" when the value goes straight to a widget).
//   LENGTH   no file exceeds MAX_LINES.
//   STYLE    LF line endings, final newline, no tabs, no trailing whitespace.

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import luaparse from "luaparse";
import { findAddons, repoRoot, toPosix } from "../lib/repo.mjs";
import { findForeverInstall } from "../lib/wow.mjs";

export const options = { quiet: { type: "boolean", default: false } };

const MAX_LINES = 800;
const EVENT_METHODS = new Set(["On", "RegisterEvent", "RegisterUnitEvent", "UnregisterEvent", "Fire", "IsEventRegistered"]);

// Lua 5.1 standard library members (the client's own additions come from the snapshot).
const LUA_STDLIB = {
    math: ["abs", "acos", "asin", "atan", "atan2", "ceil", "cos", "cosh", "deg", "exp", "floor", "fmod", "frexp", "huge",
        "ldexp", "log", "log10", "max", "min", "modf", "pi", "pow", "rad", "random", "randomseed", "sin", "sinh", "sqrt", "tan", "tanh"],
    string: ["byte", "char", "dump", "find", "format", "gmatch", "gsub", "len", "lower", "match", "rep", "reverse", "sub", "upper"],
    table: ["concat", "insert", "maxn", "remove", "sort"],
};

function loadApi() {
    const snapshot = JSON.parse(readFileSync(join(repoRoot, "tools", "api", "forever.json"), "utf8"));
    const globals = new Map();
    const define = (name, members) => {
        const entry = globals.get(name) ?? new Set();
        for (const member of members ?? []) entry.add(member);
        globals.set(name, entry);
    };
    for (const name of Object.keys(snapshot.globals)) define(name, snapshot.members[name]);
    for (const [name, members] of Object.entries(LUA_STDLIB)) define(name, members);
    for (const name of Object.keys(snapshot.functions)) {
        const dot = name.indexOf(".");
        if (dot < 0) define(name);
        else define(name.slice(0, dot), [name.slice(dot + 1)]);
    }
    return { globals, functions: snapshot.functions, events: new Set(Object.keys(snapshot.events)) };
}

// The global an expression statically names, seeing through file-level cached locals
// (`local UnitPower = UnitPower`, `local C_Spell = C_Spell`), the idiom hot paths use.
function staticName(node, aliases) {
    if (node.type === "Identifier") return node.isLocal ? (aliases.get(node.name) ?? null) : node.name;
    if (node.type === "MemberExpression" && node.base.type === "Identifier") {
        const base = node.base.isLocal ? aliases.get(node.base.name) : node.base.name;
        return base ? `${base}.${node.identifier.name}` : null;
    }
    return null;
}

// Maps each file-level local initialized from a global (or Global.member) to that name.
function collectAliases(body) {
    const aliases = new Map();
    for (const statement of body) {
        if (statement.type !== "LocalStatement") continue;
        statement.variables.forEach((variable, i) => {
            const init = statement.init[i];
            const name = init && staticName(init, aliases);
            if (name) aliases.set(variable.name, name);
        });
    }
    return aliases;
}

function stringArg(node) {
    return node && node.type === "StringLiteral" ? (node.value ?? node.raw.slice(1, -1)) : null;
}

// Walks an AST, calling visit(node, ancestors) for every node.
function walk(node, visit, ancestors = []) {
    if (!node || typeof node !== "object") return;
    if (Array.isArray(node)) {
        for (const child of node) walk(child, visit, ancestors);
        return;
    }
    if (typeof node.type !== "string") return;
    visit(node, ancestors);
    ancestors.push(node);
    for (const [key, value] of Object.entries(node)) {
        if (key !== "loc" && key !== "range") walk(value, visit, ancestors);
    }
    ancestors.pop();
}

function checkStyle(text, file, report) {
    if (text.includes("\r")) report(file, 1, "STYLE", "CRLF line endings (LF only)");
    if (text.length && !text.endsWith("\n")) report(file, text.split("\n").length, "STYLE", "missing final newline");
    text.split("\n").forEach((line, i) => {
        if (line.includes("\t")) report(file, i + 1, "STYLE", "tab character");
        if (/[ \t]+$/.test(line)) report(file, i + 1, "STYLE", "trailing whitespace");
    });
    const lines = text.split("\n").length - 1;
    if (lines > MAX_LINES) report(file, MAX_LINES, "LENGTH", `${lines} lines exceeds ${MAX_LINES}`);
}

function checkLua(file, text, api, known, report, writes) {
    let ast;
    try {
        ast = luaparse.parse(text, { luaVersion: "5.1", scope: true, locations: true, ranges: true, comments: true });
    } catch (error) {
        report(file, error.line ?? 1, "PARSE", error.message);
        return;
    }
    const lines = text.split("\n");
    const aliases = collectAliases(ast.body);
    const annotated = (line) => /--\s*secret:/.test(lines[line - 1] ?? "") || /--\s*secret:/.test(lines[line - 2] ?? "");

    walk(ast.body, (node, ancestors) => {
        const parent = ancestors[ancestors.length - 1];
        // Global writes.
        if (node.type === "AssignmentStatement" || (node.type === "FunctionDeclaration" && node.identifier && !node.isLocal)) {
            const targets = node.type === "AssignmentStatement" ? node.variables : [node.identifier];
            for (const target of targets) {
                if (target.type === "Identifier" && !target.isLocal) writes.push({ name: target.name, file, line: target.loc.start.line });
            }
        }
        // Global reads and namespace members.
        if (node.type === "Identifier" && !node.isLocal) {
            const isWriteTarget = (parent?.type === "AssignmentStatement" && parent.variables.includes(node))
                || (parent?.type === "FunctionDeclaration" && parent.identifier === node);
            const isMemberName = parent?.type === "MemberExpression" && parent.identifier === node;
            const isTableKey = parent?.type === "TableKeyString" && parent.key === node;
            if (!isWriteTarget && !isMemberName && !isTableKey && !known.has(node.name)) {
                report(file, node.loc.start.line, "GLOBAL", `read of unknown global ${node.name}`);
            }
        }
        if (node.type === "MemberExpression" && node.base.type === "Identifier") {
            const baseName = node.base.isLocal ? aliases.get(node.base.name) : node.base.name;
            const members = baseName && !baseName.includes(".") && api.globals.get(baseName);
            const isWrite = parent?.type === "AssignmentStatement" && parent.variables.includes(node);
            if (members && members.size > 0 && !members.has(node.identifier.name) && !isWrite) {
                report(file, node.loc.start.line, "MEMBER", `${baseName}.${node.identifier.name} is not in the API snapshot`);
            }
        }
        // Events and secrets at call sites.
        if (node.type === "CallExpression" || node.type === "StringCallExpression") {
            const base = node.base;
            if (base.type === "MemberExpression" && EVENT_METHODS.has(base.identifier.name)) {
                const event = stringArg((node.arguments ?? [])[0] ?? node.argument);
                if (event && /^[A-Z][A-Z0-9_]+$/.test(event) && !api.events.has(event)) {
                    report(file, node.loc.start.line, "EVENT", `unknown event ${event}`);
                }
            }
            const name = staticName(base, aliases);
            const flags = name && api.functions[name];
            if (flags && flags.length > 0) {
                const fn = [...ancestors].reverse().find((a) => a.type === "FunctionDeclaration");
                const guarded = fn && text.slice(fn.range[0], fn.range[1]).includes("issecretvalue(");
                if (!guarded && !annotated(node.loc.start.line)) {
                    report(file, node.loc.start.line, "SECRET",
                        `${name} can return a secret (${flags.join(", ")}); check issecretvalue or annotate "-- secret: <why>"`);
                }
            }
        }
    });
}

// Returns the findings (empty when every gate passes). root and clientInterface exist for the
// gate's own tests, which run it over fixture addons.
export async function runChecks({ quiet = false, root = repoRoot, clientInterface } = {}) {
    const findings = [];
    const report = (file, line, rule, message) => findings.push(`${toPosix(relative(root, file))}:${line}: ${rule} ${message}`);
    const api = loadApi();
    const addons = findAddons(root);
    const byName = new Map(addons.map((addon) => [addon.name, addon]));

    if (clientInterface === undefined) {
        try {
            clientInterface = findForeverInstall().interface;
        } catch {
            clientInterface = null; // No local client: the interface check is skipped.
        }
    }

    const exported = new Map(); // addon -> names it declares it exports
    for (const addon of addons) {
        exported.set(addon.name, (addon.metadata["X-Globals"] ?? "").split(",").map((s) => s.trim()).filter(Boolean));
    }

    for (const addon of addons) {
        const { dir, tocPath, metadata, files } = addon;
        checkStyle(readFileSync(tocPath, "utf8"), tocPath, report);
        if (clientInterface && Number(metadata.Interface) !== clientInterface) {
            report(tocPath, 1, "TOC", `## Interface ${metadata.Interface} but the installed client is ${clientInterface}`);
        }
        const dependencies = (metadata.Dependencies ?? "").split(",").map((s) => s.trim()).filter(Boolean);
        for (const dependency of dependencies) {
            if (!byName.has(dependency)) report(tocPath, 1, "TOC", `dependency ${dependency} is not an addon in this repository`);
        }
        const onDisk = readdirSync(dir, { recursive: true }).map(toPosix).filter((f) => f.endsWith(".lua"));
        for (const file of files) {
            if (!existsSync(join(dir, file))) report(tocPath, 1, "TOC", `lists ${file}, which does not exist`);
        }
        for (const file of onDisk) {
            if (!files.includes(file)) report(join(dir, file), 1, "TOC", `not listed in ${addon.name}${"_Camelot.toc"}`);
        }

        const savedVariables = (metadata.SavedVariables ?? "").split(",").map((s) => s.trim()).filter(Boolean);
        const allowedWrites = new Set([...savedVariables, ...exported.get(addon.name)]);
        if (metadata.AddonCompartmentFunc) allowedWrites.add(metadata.AddonCompartmentFunc);
        const known = new Set([...api.globals.keys(), ...allowedWrites]);
        for (const dependency of dependencies) for (const name of exported.get(dependency) ?? []) known.add(name);

        const writes = [];
        for (const file of files.filter((f) => f.endsWith(".lua") && existsSync(join(dir, f)))) {
            const path = join(dir, file);
            const text = readFileSync(path, "utf8");
            checkStyle(text, path, report);
            checkLua(path, text, api, known, report, writes);
        }
        for (const write of writes) {
            if (!allowedWrites.has(write.name) && !write.name.startsWith("SLASH_")) {
                report(write.file, write.line, "GLOBAL", `write to undeclared global ${write.name} (declare it in ## X-Globals)`);
            }
        }
    }

    if (root === repoRoot) {
        for (const dir of ["tools", "tests"]) {
            for (const file of readdirSync(join(root, dir), { recursive: true }).map(toPosix)) {
                const skip = file.startsWith("api/") || file.startsWith("fixtures/");
                if (/\.(mjs|lua|json)$/.test(file) && !skip) checkStyle(readFileSync(join(root, dir, file), "utf8"), join(root, dir, file), report);
            }
        }
    }

    if (!quiet) {
        for (const finding of findings) console.log(finding);
        console.log(findings.length ? `${findings.length} finding(s)` : `check passed (${addons.length} addons)`);
    }
    return findings;
}

export async function run(values) {
    return (await runChecks({ quiet: values.quiet })).length === 0 ? 0 : 1;
}
