// The fake client (tests/harness) in a fresh Lua 5.1 VM, for test jobs (test-worker.mjs) and the
// probes verb's report: the API snapshot, this repository's addons and the observed probe records
// go in, then the harness files run in order.

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { createLua } from "./lua.mjs";
import { PROBES_PATH, luaLiteral, readProbes } from "./probes.mjs";
import { findAddons, readForbidden, repoRoot, splitList } from "./repo.mjs";
import { buildOf } from "./wow.mjs";

// The harness files (tests/harness), in the order they run; every file there is one of them.
export const HARNESS_FILES = [
    "wow.lua", "secrets.lua", "layout.lua", "widgets.lua", "input.lua", "group.lua", "units.lua", "world.lua", "ui.lua", "meter.lua",
    "speech.lua", "quests.lua", "env.lua", "probes.lua",
];

// The snapshot crosses into Lua as text, one entry per line (converting ~7000 JS objects into
// Lua tables through wasmoon takes seconds; wow.lua decodes this in milliseconds):
//   F|E|M <tab> name ("Api.Method" for M) <tab> secret flags <tab> SecretArguments <tab>
//     IsProtectedFunction (1/0) <tab> HasRestrictions (1/0) <tab> Arguments <tab> Payload <tab>
//     SecretArgumentsAddAspect <tab> SecretReturnsForAspect <tab> Preconditions <tab>
//     ArgumentsNilable <tab> PayloadNilable (the 1-based positions that may be nil)
//                                                                     (lists comma-separated)
//   N <tab> enum name <tab> Field=value,...
function encodeEntry(kind, name, entry) {
    const list = (value) => (value ?? []).join(",");
    return [kind, name, list(entry.secret), entry.SecretArguments ?? "", entry.IsProtectedFunction ? 1 : 0,
        entry.HasRestrictions ? 1 : 0, list(entry.Arguments), list(entry.Payload), list(entry.SecretArgumentsAddAspect),
        list(entry.SecretReturnsForAspect), list(entry.Preconditions), list(entry.ArgumentsNilable), list(entry.PayloadNilable)].join("\t");
}

export function loadSnapshot() {
    const snapshot = JSON.parse(readFileSync(join(repoRoot, "tools", "api", "forever.json"), "utf8"));
    const lines = [];
    for (const [name, entry] of Object.entries(snapshot.functions)) lines.push(encodeEntry("F", name, entry));
    for (const [name, entry] of Object.entries(snapshot.events)) lines.push(encodeEntry("E", name, entry));
    for (const [api, methods] of Object.entries(snapshot.methods)) {
        for (const [name, entry] of Object.entries(methods)) lines.push(encodeEntry("M", `${api}.${name}`, entry));
    }
    // Only the enumerations the client's Enum actually has (when the dump recorded them).
    const clientEnums = new Set(snapshot.members.Enum ?? Object.keys(snapshot.enums ?? {}));
    for (const [name, fields] of Object.entries(snapshot.enums ?? {})) {
        if (clientEnums.has(name)) lines.push(`N\t${name}\t${Object.entries(fields).map(([k, v]) => `${k}=${v}`).join(",")}`);
    }
    return { raw: snapshot, lua: lines.join("\n") };
}

// The addons the harness loads (findAddons, so either Forever TOC suffix), by name: each one's
// listed Lua files and their sources, the listed files missing on disk, and its TOC metadata.
export function loadAddons(root = repoRoot) {
    const addons = {};
    for (const addon of findAddons(root)) {
        const lua = addon.files.filter((f) => f.endsWith(".lua"));
        // A file the TOC lists but the disk lacks fails that addon's load (Harness:LoadFiles),
        // not every test file: the check gate reports it, and the other addons still load.
        const exists = (f) => existsSync(join(addon.dir, f));
        addons[addon.name] = {
            files: lua,
            sources: lua.map((f) => (exists(f) ? readFileSync(join(addon.dir, f), "utf8") : "")),
            missing: lua.filter((f) => !exists(f)),
            metadata: addon.metadata,
            dependencies: addon.dependencies,
            savedVariables: splitList(addon.metadata.SavedVariables),
            savedVariablesPerCharacter: splitList(addon.metadata.SavedVariablesPerCharacter),
        };
    }
    return addons;
}

// Runs fn(lua) with the harness loaded; probesPath is the observed probe snapshot it sees.
export async function withHarness(snapshot, fn, probesPath = PROBES_PATH) {
    const lua = await createLua();
    try {
        lua.ctx.__snapshot = snapshot.lua;
        lua.ctx.__addons = loadAddons();
        // The observed probe records (tools/api/probes.json) as a Lua table constructor; wow.lua loads it.
        lua.ctx.__probes = luaLiteral(readProbes(probesPath));
        // The client build the API snapshot was dumped from, "1.60.1 (70374)"; GetBuildInfo answers it.
        lua.ctx.__build = buildOf(snapshot.raw.source?.globals) ?? "";
        // Functions refused in game (tools/api/forbidden.json); secrets.lua loads it.
        lua.ctx.__forbidden = luaLiteral(readForbidden());
        for (const file of HARNESS_FILES) {
            await lua.doString(readFileSync(join(repoRoot, "tests", "harness", file), "utf8"));
        }
        return await fn(lua);
    } finally {
        lua.global.close();
    }
}
