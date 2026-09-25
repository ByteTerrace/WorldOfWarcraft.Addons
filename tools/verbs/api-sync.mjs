// Builds tools/api/forever.json, the API snapshot the static gate and the test harness read.
//
//   --docs <dir>     Blizzard_APIDocumentationGenerated from the Forever UI source. Supplies every
//                    documented function and event, including the "secret when..." flags.
//   --globals <file> ByteTerrace_DevTools SavedVariables from `/btdev dump` in the installed client.
//                    Supplies every global the client exposes (including Lua-defined ones such as
//                    CreateColor, Settings, UIParent) and the member names of its tables.
//
// The documentation files are executed in real Lua 5.1 against a stub APIDocumentation that
// captures what they register, so the snapshot is exactly what the client documents.

import { readdirSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { findAddons, repoRoot } from "../lib/repo.mjs";
import { createLua } from "../lib/lua.mjs";

export const options = {
    docs: { type: "string" },
    globals: { type: "string" },
    out: { type: "string", default: join(repoRoot, "tools", "api", "forever.json") },
};


const CAPTURE = `
    local captured = {}
    local function proxy(name)
        local mt = {}
        local p = setmetatable({}, mt)
        mt.__index = function(t, k) local v = proxy(name .. "." .. tostring(k)); rawset(t, k, v); return v end
        local function arith() return proxy(name) end
        mt.__add, mt.__sub, mt.__mul, mt.__div, mt.__unm = arith, arith, arith, arith, arith
        return p
    end
    Enum, Constants = proxy("Enum"), proxy("Constants")
    APIDocumentation = { AddDocumentationTable = function(_, t) captured[#captured + 1] = t end }
    return captured
`;

async function readDocs(dir) {
    const lua = await createLua();
    try {
        await lua.doString(`__captured = (function() ${CAPTURE} end)()`);
        for (const file of readdirSync(dir).filter((f) => f.endsWith(".lua")).sort()) {
            await lua.doString(readFileSync(join(dir, file), "utf8"));
        }
        const json = await lua.doString(`
            local fns, evs, methods = {}, {}, {}
            local function flags(t)
                local list = {}
                for k, v in pairs(t) do
                    if type(k) == "string" and k:sub(1, 6) == "Secret" and k:sub(1, 15) ~= "SecretArguments" and v then
                        list[#list + 1] = k
                    end
                end
                table.sort(list)
                return list
            end
            local function quote(s) return '"' .. s .. '"' end
            local function list(t) local q = {}; for i, v in ipairs(t) do q[i] = quote(v) end; return "[" .. table.concat(q, ",") .. "]" end
            for _, system in ipairs(__captured) do
                if system.Type == "ScriptObject" then
                    -- Widget methods (e.g. SimpleStatusBarAPI.SetValue), keyed by API name.
                    local entries = {}
                    for _, f in ipairs(system.Functions or {}) do
                        entries[#entries + 1] = quote(f.Name) .. ":" .. list(flags(f))
                    end
                    methods[#methods + 1] = quote(system.Name) .. ":{" .. table.concat(entries, ",") .. "}"
                else
                    local ns = system.Namespace
                    for _, f in ipairs(system.Functions or {}) do
                        local name = ns and (ns .. "." .. f.Name) or f.Name
                        fns[#fns + 1] = quote(name) .. ":" .. list(flags(f))
                    end
                end
                for _, e in ipairs(system.Events or {}) do
                    evs[#evs + 1] = quote(e.LiteralName) .. ":" .. list(flags(e))
                end
            end
            return "{" .. '"functions":{' .. table.concat(fns, ",") .. '},"events":{' .. table.concat(evs, ",")
                .. '},"methods":{' .. table.concat(methods, ",") .. "}}"
        `);
        return JSON.parse(json);
    } finally {
        lua.global.close();
    }
}

// Reads ByteTerrace_DevTools SavedVariables: ByteTerraceDevToolsDB = { build = {...},
// globals = { [name] = { type =, members = } } }. Rows cross from Lua as tab-separated lines,
// so member names need no escaping; names containing control characters are skipped.
async function readGlobals(file) {
    const lua = await createLua();
    try {
        await lua.doString(readFileSync(file, "utf8"));
        const encoded = await lua.doString(`
            local db, lines = ByteTerraceDevToolsDB, {}
            local function clean(s) return type(s) == "string" and not s:find("[%c]") end
            lines[1] = tostring(db.build.version) .. " (" .. tostring(db.build.build) .. ")"
            for name, entry in pairs(db.globals) do
                if clean(name) then
                    local members = {}
                    if name ~= "_G" then
                        for _, m in ipairs(entry.members or {}) do
                            if clean(m) then members[#members + 1] = m end
                        end
                    end
                    lines[#lines + 1] = name .. "\\t" .. entry.type .. "\\t" .. table.concat(members, "\\31")
                end
            end
            return table.concat(lines, "\\n")
        `);
        const [build, ...rows] = encoded.split("\n");
        const globals = {};
        const members = {};
        for (const row of rows) {
            const [name, type, list] = row.split("\t");
            globals[name] = type;
            if (list) members[name] = list.split("\x1f").sort();
        }
        return { build, globals, members };
    } finally {
        lua.global.close();
    }
}

// Globals the addons in this repository create, which a dump taken with them loaded contains:
// SavedVariables, ## X-Globals, AddonCompartmentFunc, their SLASH_ aliases, and anything named
// with an addon's folder name as its prefix (named frames). The snapshot is the client's API only.
function isRepoOwned(name, addons) {
    return addons.some((addon) => {
        const m = addon.metadata;
        const declared = [m.SavedVariables, m["X-Globals"], m.AddonCompartmentFunc].join(",").split(",").map((s) => s.trim());
        const slashKey = "SLASH_" + addon.name.toUpperCase().replace(/[^A-Z0-9]/g, "");
        return declared.includes(name) || name.startsWith(addon.name) || name.startsWith(slashKey);
    });
}

function sortKeys(object) {
    return Object.fromEntries(Object.keys(object).sort().map((k) => [k, object[k]]));
}

// One entry per line: diffs stay readable and the file stays compact.
function serialize(snapshot) {
    const section = (object) => "{\n" + Object.entries(object).map(([k, v]) => `  ${JSON.stringify(k)}: ${JSON.stringify(v)}`).join(",\n") + "\n }";
    const methods = "{\n" + Object.entries(snapshot.methods).map(([k, v]) => `  ${JSON.stringify(k)}: ${JSON.stringify(v)}`).join(",\n") + "\n }";
    return "{\n"
        + ` "source": ${JSON.stringify(snapshot.source)},\n`
        + ` "functions": ${section(snapshot.functions)},\n`
        + ` "events": ${section(snapshot.events)},\n`
        + ` "methods": ${methods},\n`
        + ` "globals": ${section(snapshot.globals)},\n`
        + ` "members": ${section(snapshot.members)}\n`
        + "}\n";
}

export async function run(values) {
    if (!values.docs && !values.globals) {
        console.error("api-sync needs --docs and/or --globals.");
        return 2;
    }
    let snapshot = { source: {}, functions: {}, events: {}, methods: {}, globals: {}, members: {} };
    try {
        snapshot = { ...snapshot, ...JSON.parse(readFileSync(values.out, "utf8")) };
    } catch {
        // First sync.
    }
    if (values.docs) {
        const docs = await readDocs(values.docs);
        snapshot.functions = sortKeys(docs.functions);
        snapshot.events = sortKeys(docs.events);
        snapshot.methods = sortKeys(Object.fromEntries(Object.entries(docs.methods).map(([k, v]) => [k, sortKeys(v)])));
        snapshot.source = { ...snapshot.source, docs: "Blizzard_APIDocumentationGenerated (Gethe/wow-ui-source, forever)" };
    }
    if (values.globals) {
        const dump = await readGlobals(values.globals);
        const addons = findAddons();
        const dropped = Object.keys(dump.globals).filter((name) => isRepoOwned(name, addons));
        for (const name of dropped) {
            delete dump.globals[name];
            delete dump.members[name];
        }
        if (dropped.length) console.log(`Dropped ${dropped.length} globals owned by this repository's addons: ${dropped.sort().join(", ")}`);
        snapshot.globals = sortKeys(dump.globals);
        snapshot.members = sortKeys(dump.members);
        snapshot.source = { ...snapshot.source, globals: `ByteTerrace_DevTools dump, client ${dump.build}` };
    }
    mkdirSync(join(values.out, ".."), { recursive: true });
    writeFileSync(values.out, serialize(snapshot));
    console.log(`Wrote ${values.out}: ${Object.keys(snapshot.functions).length} functions, `
        + `${Object.keys(snapshot.events).length} events, ${Object.keys(snapshot.globals).length} globals.`);
    return 0;
}

