// The probe snapshot, tools/api/probes.json: what the real client answered to each calibration
// probe (ByteTerrace_DevTools' probe files, probeFiles below), recorded in game by `/btdev probe`
// and imported by `tlk probes --import`. tests/probes.test.lua compares the harness's answers with it.
//
// Format: pretty-printed JSON, probes sorted by name, each record's result first, then the context
// it ran in. The file's build is the newest record's; a record from another build names its own.
//
//   {
//     "build": "1.60.1 (70009)",
//     "probes": {
//       "chatTypeInfo.raidWarning": {
//         "result": { "b": 0, "g": 72, "hasMetatable": true, "r": 255, "sticky": 0 },
//         "context": { "combat": false, "restrictions": "none" }
//       },
//       ...
//     }
//   }

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { createLua } from "./lua.mjs";
import { readToc, repoRoot } from "./repo.mjs";

export const PROBES_PATH = join(repoRoot, "tools", "api", "probes.json");

// The probe files: the files ByteTerrace_DevTools' TOC lists before DevTools.lua (the in-game
// commands, which need the client), as [{ name, path }] in load order.
export function probeFiles(root = repoRoot) {
    const toc = readToc("ByteTerrace_DevTools", root);
    const end = toc.files.indexOf("DevTools.lua");
    return toc.files.slice(0, end < 0 ? toc.files.length : end).map((name) => ({ name, path: join(toc.dir, name) }));
}

// The snapshot, or an empty one when the file doesn't exist yet. Every record comes back with its
// build filled in.
export function readProbes(path = PROBES_PATH) {
    if (!existsSync(path)) return { build: "", probes: {} };
    const snapshot = JSON.parse(readFileSync(path, "utf8"));
    const build = snapshot.build ?? "";
    const probes = {};
    for (const [name, record] of Object.entries(snapshot.probes ?? {})) probes[name] = { build, ...record };
    return { build, probes };
}

// JSON with every object's keys sorted, for comparing values.
export function stableJson(value) {
    if (Array.isArray(value)) return "[" + value.map(stableJson).join(",") + "]";
    if (value && typeof value === "object") {
        return "{" + Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(",") + "}";
    }
    return JSON.stringify(value);
}

const WIDTH = 110;
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

// A value with sorted keys (or the given order): on one line when it fits in WIDTH at this indent,
// else one key per line.
function pretty(value, indent, forceOpen = false, keys = null) {
    if (!isObject(value)) return JSON.stringify(value);
    const order = keys ?? Object.keys(value).sort();
    if (order.length === 0) return "{}";
    const inner = indent + "  ";
    const entries = order.map((key) => [key, pretty(value[key], inner)]);
    const inline = "{ " + entries.map(([key, text]) => `${JSON.stringify(key)}: ${text}`).join(", ") + " }";
    if (!forceOpen && !inline.includes("\n") && indent.length + inline.length <= WIDTH) return inline;
    return "{\n" + entries.map(([key, text]) => `${inner}${JSON.stringify(key)}: ${text}`).join(",\n") + `\n${indent}}`;
}

// The snapshot as the committed file writes it (see the header): a record's build appears only
// when it differs from the file's.
export function serializeProbes(snapshot) {
    const build = snapshot.build ?? "";
    const records = Object.keys(snapshot.probes).sort().map((name) => {
        const { result, context, build: own } = snapshot.probes[name];
        const record = own && own !== build ? { result, context, build: own } : { result, context };
        return `    ${JSON.stringify(name)}: ${pretty(record, "    ", true, Object.keys(record))}`;
    });
    const probes = records.length ? "{\n" + records.join(",\n") + "\n  }" : "{}";
    return `{\n  "build": ${JSON.stringify(build)},\n  "probes": ${probes}\n}\n`;
}

// A Lua string literal: printable ASCII as is, everything else as a decimal escape.
function luaString(text) {
    let out = "\"";
    for (const byte of Buffer.from(text, "utf8")) {
        const c = String.fromCharCode(byte);
        out += byte >= 32 && byte < 127 && c !== "\"" && c !== "\\" ? c : `\\${byte}`;
    }
    return out + "\"";
}

// A JSON value (objects, strings, numbers, booleans) as a Lua table constructor. Arrays and null
// don't occur in probe records and are refused.
export function luaLiteral(value) {
    if (typeof value === "string") return luaString(value);
    if (typeof value === "number") {
        if (!Number.isFinite(value)) throw new Error(`luaLiteral: ${value} isn't finite`);
        return String(value);
    }
    if (typeof value === "boolean") return String(value);
    if (value && typeof value === "object" && !Array.isArray(value)) {
        return "{" + Object.keys(value).sort().map((key) => `[${luaString(key)}]=${luaLiteral(value[key])}`).join(",") + "}";
    }
    throw new Error(`luaLiteral: unsupported value ${JSON.stringify(value)}`);
}

// Lua that encodes a value of the kind a record holds (string keys; strings, booleans, finite
// numbers and tables of them) as JSON, or returns "!" and the problem.
export const ENCODE_JSON = `
    local function quote(s)
        return '"' .. s:gsub('[%c"\\\\]', function(c)
            if c == '"' then return '\\\\"' elseif c == "\\\\" then return "\\\\\\\\" end
            return string.format("\\\\u%04x", c:byte())
        end) .. '"'
    end
    local encode
    function encode(value, path)
        local kind = type(value)
        if kind == "string" then return quote(value)
        elseif kind == "boolean" then return tostring(value)
        elseif kind == "number" then
            if value ~= value or value == math.huge or value == -math.huge then error(path .. " isn't finite", 0) end
            return string.format("%.17g", value)
        elseif kind ~= "table" then error(path .. " is a " .. kind, 0) end
        local keys = {}
        for key in pairs(value) do
            if type(key) ~= "string" then error(path .. " has a key that isn't a string", 0) end
            keys[#keys + 1] = key
        end
        table.sort(keys)
        local parts = {}
        for i, key in ipairs(keys) do parts[i] = quote(key) .. ":" .. encode(value[key], path .. "." .. key) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    __encodeJson = function(value, path)
        local ok, result = pcall(encode, value, path)
        if ok then return result end
        return "!" .. result
    end
`;

// The probe records in a ByteTerrace_DevTools SavedVariables file: { [name]: record }, empty when
// the file holds none. Throws on a file that isn't one, or on a record it can't encode.
export async function readRecords(file) {
    const lua = await createLua();
    try {
        await lua.doString(ENCODE_JSON);
        await lua.doString(readFileSync(file, "utf8"));
        const encoded = await lua.doString(`
            local db = ByteTerraceDevToolsDB
            if type(db) ~= "table" then return "!no ByteTerraceDevToolsDB table" end
            if db.probes == nil then return "{}" end
            return __encodeJson(db.probes, "probes")
        `);
        if (encoded.startsWith("!")) throw new Error(`${file}: ${encoded.slice(1)}`);
        return JSON.parse(encoded);
    } finally {
        lua.global.close();
    }
}

// The probe definitions, in run order: [{ name, needs (the needs' texts joined with " + "), labels
// (their short labels, or "anywhere"), harnessGap (why the harness can't run it, or "") }].
// The probe files run in plain Lua: at load they only define data and functions.
export async function readDefinitions(files = probeFiles()) {
    const lua = await createLua();
    try {
        await lua.doString("__ns = {}");
        for (const file of files) {
            lua.ctx.__source = readFileSync(file.path, "utf8");
            lua.ctx.__chunkName = "@ByteTerrace_DevTools/" + file.name;
            await lua.doString(`assert(loadstring(__source, __chunkName))("ByteTerrace_DevTools", __ns)`);
        }
        const encoded = await lua.doString(`
            local ns = __ns
            local lines = {}
            for i, probe in ipairs(ns.Probes.List) do
                lines[i] = table.concat({ probe.name, ns.Probes.NeedsText(probe), ns.Probes.NeedsLabel(probe),
                    ns.Probes.HarnessGap(probe) or "" }, "\\t")
            end
            return table.concat(lines, "\\n")
        `);
        return encoded.split("\n").filter(Boolean).map((line) => {
            const [name, needs, labels, harnessGap] = line.split("\t");
            return { name, needs, labels, harnessGap };
        });
    } finally {
        lua.global.close();
    }
}

// The build a source string or record names, "1.60.1 (70009)", or null.
export const buildOf = (text) => /\d+\.\d+\.\d+ \(\d+\)/.exec(text ?? "")?.[0] ?? null;

// Orders builds by their build number.
export const buildNumber = (build) => Number(/\((\d+)\)/.exec(build ?? "")?.[1] ?? 0);
