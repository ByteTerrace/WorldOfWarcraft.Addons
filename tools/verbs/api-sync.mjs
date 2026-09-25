// Builds tools/api/forever.json, the API snapshot the static gate and the test harness read.
//
//   --docs <dir>     Blizzard_APIDocumentationGenerated from the Forever UI source. Supplies every
//                    documented function, event and widget method with its secret-value metadata.
//   --globals <file> ByteTerrace_DevTools SavedVariables from `/btdev dump` in the installed client.
//                    Supplies every global the client exposes (including Lua-defined ones such as
//                    CreateColor, Settings, UIParent) and the member names of its tables.
//
// The documentation files are executed in real Lua 5.1 against a stub APIDocumentation that
// captures what they register, so the snapshot is exactly what the client documents.
//
// Snapshot format (one entry per line, so diffs stay readable):
//
//   "functions": { "UnitHealth": {"secret":["SecretReturns"],"SecretArguments":"AllowedWhenUntainted"}, ... }
//   "events":    { "UNIT_HEALTH": {}, ... }
//   "methods":   { "SimpleFontStringAPI": { "GetText": {"SecretReturnsForAspect":["Text"]}, ... }, ... }
//   "enums":     { "PowerType": {"Mana":0,"Rage":1,...}, ... }     (documented Enum.* tables)
//   "globals":   { "UnitHealth": "function", ... }
//   "members":   { "Enum": ["PowerType", ...], "Enum.PowerType": ["Energy", ...], ... }
//
// An entry holds only what the docs state: `secret` (the Secret* predicate flags, sorted),
// `SecretArguments` (verbatim), `IsProtectedFunction`, `HasRestrictions`, the argument (or event
// payload) types as `Arguments` / `Payload`, and the aspect lists `SecretArgumentsAddAspect` /
// `SecretReturnsForAspect` (Enum.SecretAspect names), and `Preconditions`: the Requires* /
// Restricted* precondition markers set on the entry (RequiresFontStringTextAccess,
// RestrictedForMacroChatMessages, ...; SecretPredicatesDocumentation defines them). A nested
// table's members are keyed by its dotted path ("Enum.PowerType"). The docs half is functions,
// events, methods and enums; the globals half is globals and members.

import { execFileSync } from "node:child_process";
import { readdirSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { findAddons, repoRoot } from "../lib/repo.mjs";
import { createLua } from "../lib/lua.mjs";

export const options = {
    docs: { type: "string" },
    globals: { type: "string" },
    out: { type: "string", default: join(repoRoot, "tools", "api", "forever.json") },
};

// A real client exposes tens of thousands of globals; anything far smaller is a broken dump.
export const MIN_GLOBALS = 10000;

const CAPTURE = `
    local captured, names = {}, setmetatable({}, { __mode = "k" })
    local function proxy(name)
        local mt = {}
        local p = setmetatable({}, mt)
        names[p] = name
        mt.__index = function(t, k) local v = proxy(name .. "." .. tostring(k)); rawset(t, k, v); return v end
        local function arith() return proxy(name) end
        mt.__add, mt.__sub, mt.__mul, mt.__div, mt.__unm = arith, arith, arith, arith, arith
        return p
    end
    Enum, Constants = proxy("Enum"), proxy("Constants")
    APIDocumentation = { AddDocumentationTable = function(_, t) captured[#captured + 1] = t end }
    __proxyName = function(p) return names[p] end
    return captured
`;

const ENCODE = `
    local function quote(s) return (string.format("%q", s):gsub("\\\\\\n", "\\\\n")) end
    local function list(t)
        local q = {}
        for i, v in ipairs(t) do q[i] = quote(v) end
        return "[" .. table.concat(q, ",") .. "]"
    end
    local function aspects(t)
        local out = {}
        for i, v in ipairs(t) do
            local name = __proxyName(v) or tostring(v)
            out[i] = (name:gsub("^Enum%.SecretAspect%.", ""))
        end
        table.sort(out)
        return out
    end
    local ASPECT_KEYS = { SecretArgumentsAddAspect = true, SecretReturnsForAspect = true }
    local function entry(t)
        local secret, parts = {}, {}
        for k, v in pairs(t) do
            if type(k) == "string" and k:sub(1, 6) == "Secret" and k ~= "SecretArguments" and not ASPECT_KEYS[k] and v == true then
                secret[#secret + 1] = k
            end
        end
        table.sort(secret)
        if #secret > 0 then parts[#parts + 1] = '"secret":' .. list(secret) end
        if t.SecretArguments ~= nil then parts[#parts + 1] = '"SecretArguments":' .. quote(tostring(t.SecretArguments)) end
        if t.IsProtectedFunction then parts[#parts + 1] = '"IsProtectedFunction":true' end
        if t.HasRestrictions then parts[#parts + 1] = '"HasRestrictions":true' end
        for _, key in ipairs({ "Arguments", "Payload" }) do
            if type(t[key]) == "table" and #t[key] > 0 then
                local types = {}
                for i, argument in ipairs(t[key]) do types[i] = tostring(argument.Type) end
                parts[#parts + 1] = quote(key) .. ":" .. list(types)
            end
        end
        for _, key in ipairs({ "SecretArgumentsAddAspect", "SecretReturnsForAspect" }) do
            if type(t[key]) == "table" then parts[#parts + 1] = quote(key) .. ":" .. list(aspects(t[key])) end
        end
        local preconditions = {}
        for k, v in pairs(t) do
            if type(k) == "string" and (k:find("^Requires%u") or k:find("^Restricted%u")) and v == true then
                preconditions[#preconditions + 1] = k
            end
        end
        table.sort(preconditions)
        if #preconditions > 0 then parts[#parts + 1] = '"Preconditions":' .. list(preconditions) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    local lines = {}
    for _, system in ipairs(__captured) do
        for _, f in ipairs(system.Functions or {}) do
            if system.Type == "ScriptObject" then
                lines[#lines + 1] = "M\\t" .. system.Name .. "\\t" .. f.Name .. "\\t" .. entry(f)
            else
                -- A function may override its system's namespace ("" = a global, like InCombatLockdown).
                local ns = f.Namespace or system.Namespace
                if ns == "" then ns = nil end
                lines[#lines + 1] = "F\\t" .. (ns and (ns .. "." .. f.Name) or f.Name) .. "\\t\\t" .. entry(f)
            end
        end
        for _, e in ipairs(system.Events or {}) do
            lines[#lines + 1] = "E\\t" .. e.LiteralName .. "\\t\\t" .. entry(e)
        end
        for _, t in ipairs(system.Tables or {}) do
            if t.Type == "Enumeration" then
                local fields = {}
                for _, field in ipairs(t.Fields or {}) do
                    if type(field.EnumValue) == "number" then
                        fields[#fields + 1] = quote(field.Name) .. ":" .. string.format("%.17g", field.EnumValue)
                    end
                end
                lines[#lines + 1] = "N\\t" .. t.Name .. "\\t\\t{" .. table.concat(fields, ",") .. "}"
            end
        end
    end
    return table.concat(lines, "\\n")
`;

export async function readDocs(dir) {
    const lua = await createLua();
    try {
        await lua.doString(`__captured = (function() ${CAPTURE} end)()`);
        for (const file of readdirSync(dir).filter((f) => f.endsWith(".lua")).sort()) {
            await lua.doString(readFileSync(join(dir, file), "utf8"));
        }
        const encoded = await lua.doString(ENCODE);
        const docs = { functions: {}, events: {}, methods: {}, enums: {} };
        for (const line of encoded.split("\n")) {
            const [kind, name, method, json] = line.split("\t");
            const entry = JSON.parse(json);
            if (kind === "F") docs.functions[name] = entry;
            else if (kind === "E") docs.events[name] = entry;
            else if (kind === "N") docs.enums[name] = entry;
            else (docs.methods[name] ??= {})[method] = entry;
        }
        return docs;
    } finally {
        lua.global.close();
    }
}

// The build a wow-ui-source checkout documents: its commits are titled "<version> (<build>)".
function docsBuild(dir) {
    try {
        const subject = execFileSync("git", ["-C", dir, "log", "-1", "--format=%s"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
        return /\d+\.\d+\.\d+ \(\d+\)/.exec(subject)?.[0] ?? null;
    } catch {
        return null;
    }
}

// Reads ByteTerrace_DevTools SavedVariables:
//   ByteTerraceDevToolsDB = { build = {...}, globals = { [name] = { type =, members =, tables = } } }
// where `tables` (optional) maps a member name to that nested table's member names. Rows cross
// from Lua as tab-separated lines, so member names need no escaping; names containing control
// characters are skipped. Throws on a dump that can't be a real client's.
export async function readGlobals(file) {
    const lua = await createLua();
    try {
        await lua.doString(readFileSync(file, "utf8"));
        const encoded = await lua.doString(`
            local db, lines = ByteTerraceDevToolsDB, {}
            if type(db) ~= "table" or type(db.globals) ~= "table" or type(db.build) ~= "table" then
                return "!ByteTerraceDevToolsDB has no build or globals table"
            end
            local function clean(s) return type(s) == "string" and not s:find("[%c]") end
            local function names(list)
                local out = {}
                for _, m in ipairs(type(list) == "table" and list or {}) do
                    if clean(m) then out[#out + 1] = m end
                end
                return table.concat(out, "\\31")
            end
            lines[1] = tostring(db.build.version) .. " (" .. tostring(db.build.build) .. ")"
            for name, entry in pairs(db.globals) do
                if clean(name) then
                    if type(entry) ~= "table" or type(entry.type) ~= "string" then
                        return "!global " .. name .. " has no type field"
                    end
                    lines[#lines + 1] = "G\\t" .. name .. "\\t" .. entry.type .. "\\t" .. (name ~= "_G" and names(entry.members) or "")
                    for key, nested in pairs(type(entry.tables) == "table" and entry.tables or {}) do
                        if clean(key) then
                            lines[#lines + 1] = "T\\t" .. name .. "." .. key .. "\\t\\t" .. names(nested)
                        end
                    end
                end
            end
            return table.concat(lines, "\\n")
        `);
        if (encoded.startsWith("!")) throw new Error(`${file}: ${encoded.slice(1)}`);
        const [build, ...rows] = encoded.split("\n");
        const globals = {};
        const members = {};
        for (const row of rows) {
            const [kind, name, type, list] = row.split("\t");
            if (kind === "G") globals[name] = type;
            if (list) members[name] = list.split("\x1f").sort();
        }
        const count = Object.keys(globals).length;
        if (count < MIN_GLOBALS) {
            throw new Error(`${file}: only ${count} globals (a real client has well over ${MIN_GLOBALS}); refusing a partial dump`);
        }
        return { build, globals, members };
    } finally {
        lua.global.close();
    }
}

function declaredNames(addon) {
    const m = addon.metadata;
    return [m.SavedVariables, m.SavedVariablesPerCharacter, m["X-Globals"], m.AddonCompartmentFunc]
        .join(",").split(",").map((s) => s.trim()).filter(Boolean);
}

// The SlashCmdList key an addon's framework registers (AddOn:RegisterSlash).
function slashKey(addon) {
    return addon.name.toUpperCase().replace(/[^A-Z0-9]/g, "");
}

// Globals the addons in this repository create, which a dump taken with them loaded contains:
// SavedVariables, ## X-Globals, AddonCompartmentFunc, their SLASH_ aliases, and anything named
// with an addon's folder name as its prefix (named frames). The snapshot is the client's API only.
export function isRepoOwned(name, addons) {
    return addons.some((addon) => declaredNames(addon).includes(name) || name.startsWith(addon.name)
        || name.startsWith("SLASH_" + slashKey(addon)));
}

// Keys this repository's addons add to the client's tables (SlashCmdList.THELANKREWTOOLKIT).
// A dump taken before DevTools filtered members with issecurevariable(table, key) contains them.
export function isRepoOwnedMember(table, key, addons) {
    return addons.some((addon) => (table === "SlashCmdList" && key === slashKey(addon)) || key.startsWith(addon.name));
}

function sortKeys(object) {
    return Object.fromEntries(Object.keys(object).sort().map((k) => [k, object[k]]));
}

// One entry per line: diffs stay readable and the file stays compact.
export function serialize(snapshot) {
    const line = (indent) => ([k, v]) => `${indent}${JSON.stringify(k)}: ${JSON.stringify(v)}`;
    const section = (object) => "{\n" + Object.entries(object).map(line("  ")).join(",\n") + "\n }";
    const methods = "{\n" + Object.entries(snapshot.methods)
        .map(([api, entries]) => `  ${JSON.stringify(api)}: {\n` + Object.entries(entries).map(line("   ")).join(",\n") + "\n  }")
        .join(",\n") + "\n }";
    return "{\n"
        + ` "source": ${JSON.stringify(snapshot.source)},\n`
        + ` "functions": ${section(snapshot.functions)},\n`
        + ` "events": ${section(snapshot.events)},\n`
        + ` "methods": ${methods},\n`
        + ` "enums": ${section(snapshot.enums)},\n`
        + ` "globals": ${section(snapshot.globals)},\n`
        + ` "members": ${section(snapshot.members)}\n`
        + "}\n";
}

const buildOf = (source) => /\d+\.\d+\.\d+ \(\d+\)/.exec(source ?? "")?.[0] ?? null;

export async function run(values) {
    if (!values.docs && !values.globals) {
        console.error("api-sync needs --docs and/or --globals.");
        return 2;
    }
    let snapshot = { source: {}, functions: {}, events: {}, methods: {}, enums: {}, globals: {}, members: {} };
    try {
        snapshot = { ...snapshot, ...JSON.parse(readFileSync(values.out, "utf8")) };
    } catch {
        // First sync.
    }
    let dump;
    if (values.globals) {
        try {
            dump = await readGlobals(values.globals);
        } catch (error) {
            console.error(`api-sync: ${error.message}`);
            return 1;
        }
    }
    if (values.docs) {
        const docs = await readDocs(values.docs);
        snapshot.functions = sortKeys(docs.functions);
        snapshot.events = sortKeys(docs.events);
        snapshot.methods = sortKeys(Object.fromEntries(Object.entries(docs.methods).map(([k, v]) => [k, sortKeys(v)])));
        snapshot.enums = sortKeys(docs.enums);
        const build = docsBuild(values.docs);
        if (!build) console.warn("api-sync: warning: couldn't read the docs' build from their git checkout");
        snapshot.source = { ...snapshot.source, docs: `Blizzard_APIDocumentationGenerated (Gethe/wow-ui-source, forever)${build ? `, ${build}` : ""}` };
    }
    if (dump) {
        const addons = findAddons();
        const dropped = Object.keys(dump.globals).filter((name) => isRepoOwned(name, addons));
        for (const name of dropped) {
            delete dump.globals[name];
            delete dump.members[name];
        }
        if (dropped.length) console.log(`Dropped ${dropped.length} globals owned by this repository's addons: ${dropped.sort().join(", ")}`);
        for (const [table, list] of Object.entries(dump.members)) {
            const kept = list.filter((key) => !isRepoOwnedMember(table, key, addons));
            if (kept.length !== list.length) {
                console.log(`Dropped ${list.length - kept.length} member(s) of ${table} owned by this repository's addons`);
                dump.members[table] = kept;
            }
        }
        snapshot.globals = sortKeys(dump.globals);
        snapshot.members = sortKeys(dump.members);
        snapshot.source = { ...snapshot.source, globals: `ByteTerrace_DevTools dump, client ${dump.build}` };
    }
    const docsBuildText = buildOf(snapshot.source.docs);
    const globalsBuild = buildOf(snapshot.source.globals);
    if (docsBuildText && globalsBuild && docsBuildText !== globalsBuild) {
        console.warn(`api-sync: warning: docs are from ${docsBuildText} but globals are from ${globalsBuild}; refresh both halves`);
    }
    mkdirSync(join(values.out, ".."), { recursive: true });
    writeFileSync(values.out, serialize(snapshot));
    console.log(`Wrote ${values.out}: ${Object.keys(snapshot.functions).length} functions, `
        + `${Object.keys(snapshot.events).length} events, ${Object.keys(snapshot.globals).length} globals.`);
    return 0;
}
