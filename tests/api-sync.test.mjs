// api-sync's own tests: it refuses partial inputs rather than empty the rules, reads what the
// docs and the dump record, and writes the snapshot in its one-entry-per-line format.

import { readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { repoRoot } from "../tools/lib/repo.mjs";
import { FIXTURES, assert, tlk, withTemp } from "../tools/lib/test-support.mjs";
import { MIN_DOC_FUNCTIONS, MIN_GLOBALS, readDocs, readGlobals, serialize } from "../tools/verbs/api-sync.mjs";

// A minimal DevTools dump with `count` function globals plus a nested Enum table.
function writeDump(path, count, skipped = "") {
    const rows = [];
    for (let i = 0; i < count; i++) rows.push(`["Global${i}"] = { ["type"] = "function" },`);
    rows.push(`["Enum"] = { ["type"] = "table", ["members"] = { "PowerType" }, ["tables"] = { ["PowerType"] = { "Energy", "Mana" } } },`);
    rows.push(`["SlashCmdList"] = { ["type"] = "table", ["members"] = { "BYTETERRACEDEVTOOLS", "HELP" } },`);
    writeFileSync(path, `ByteTerraceDevToolsDB = { ["build"] = { ["build"] = "1", ["version"] = "1.60.1" }, ${skipped}["globals"] = {\n${rows.join("\n")}\n} }\n`);
}

export const tests = [
    {
        name: "api-sync refuses a partial dump and one without type fields",
        run: async () => {
            let message = "";
            await readGlobals(join(FIXTURES, "api", "tiny-dump.lua")).catch((error) => { message = error.message; });
            assert(message.includes(`well over ${MIN_GLOBALS}`), `tiny dump: ${message}`);
            message = "";
            await readGlobals(join(FIXTURES, "api", "untyped-dump.lua")).catch((error) => { message = error.message; });
            assert(message.includes("has no type field"), `untyped dump: ${message}`);
            const result = tlk(["api-sync", "--globals", join(FIXTURES, "api", "tiny-dump.lua"), "--out", join(tmpdir(), "tlk-never-written.json")]);
            assert(result.status === 1, `api-sync exits non-zero on a partial dump (got ${result.status})`);
        },
    },
    {
        name: "api-sync refuses docs that can't be the full documentation, rather than empty the rules",
        run: async () => withTemp(async (dir) => {
            let message = "";
            await readDocs(dir).catch((error) => { message = error.message; });
            assert(message.includes(`well over ${MIN_DOC_FUNCTIONS}`), `an empty folder: ${message}`);
            const result = tlk(["api-sync", "--docs", dir, "--out", join(dir, "never-written.json")]);
            assert(result.status === 1 && result.stderr.includes("refusing partial docs"), `${result.status} ${result.stderr}`);
        }),
    },
    {
        // Nilable = true and a Default both mean the position may be nil; the rest may not.
        name: "api-sync records which argument and payload positions may be nil",
        run: async () => withTemp(async (dir) => {
            const filler = Array.from({ length: MIN_DOC_FUNCTIONS }, (_, i) => `{ Name = "F${i}", Type = "Function" },`).join("\n");
            writeFileSync(join(dir, "TestDocumentation.lua"), `APIDocumentation:AddDocumentationTable({
                Name = "Test", Type = "System", Namespace = "C_Test",
                Functions = {
                    { Name = "Speak", Type = "Function", Arguments = {
                        { Name = "voiceID", Type = "number", Nilable = false },
                        { Name = "text", Type = "cstring", Nilable = true },
                        { Name = "overlap", Type = "bool", Nilable = false, Default = false },
                    } },
                    ${filler}
                },
                Events = {
                    { Name = "Said", Type = "Event", LiteralName = "TEST_SAID", Payload = {
                        { Name = "text", Type = "cstring", Nilable = false },
                        { Name = "guid", Type = "WOWGUID", Nilable = true },
                    } },
                },
            })`);
            const docs = await readDocs(dir);
            const speak = docs.functions["C_Test.Speak"];
            assert(JSON.stringify(speak.Arguments) === '["number","cstring","bool"]', JSON.stringify(speak));
            assert(JSON.stringify(speak.ArgumentsNilable) === "[2,3]", JSON.stringify(speak));
            assert(JSON.stringify(docs.events.TEST_SAID.PayloadNilable) === "[2]", JSON.stringify(docs.events.TEST_SAID));
            assert(!("ArgumentsNilable" in docs.functions["C_Test.F0"]), "no arguments, no list");
        }),
    },
    {
        name: "api-sync warns when the dump left out names another addon set",
        run: async () => withTemp(async (dir) => {
            const dump = join(dir, "dump.lua");
            writeDump(dump, MIN_GLOBALS, `["skipped"] = { ["SomeOtherAddon"] = 12, ["ByteTerrace_Core"] = 3 }, `);
            const { skipped } = await readGlobals(dump);
            assert(skipped.SomeOtherAddon === 12 && skipped.ByteTerrace_Core === 3, JSON.stringify(skipped));
            const result = tlk(["api-sync", "--globals", dump, "--out", join(dir, "forever.json")]);
            assert(result.status === 0 && result.stderr.includes("other addons set (SomeOtherAddon: 12)"), result.stderr);
            assert(!result.stderr.includes("ByteTerrace_Core:"), "this repository's own are expected");
        }),
    },
    {
        name: "api-sync reads nested members and writes one entry per line",
        run: async () => withTemp(async (dir) => {
            const dump = join(dir, "dump.lua");
            writeDump(dump, MIN_GLOBALS);
            const { globals, members } = await readGlobals(dump);
            assert(globals.Enum === "table" && members["Enum.PowerType"].join(",") === "Energy,Mana", "Enum.PowerType members");
            const text = serialize({ source: {}, functions: { A: { secret: ["SecretReturns"] }, B: {} }, events: {}, methods: { Api: { M: {} } },
                enums: {}, globals: { A: "function" }, members: { Enum: ["PowerType"] } });
            assert(text.includes('\n  "A": {"secret":["SecretReturns"]},\n  "B": {}\n'), "functions one per line");
            assert(text.includes('\n   "M": {}\n'), "methods one per line");
            JSON.parse(text);
        }),
    },
    {
        name: "the committed snapshot is current with its own serializer",
        run: async () => {
            const path = join(repoRoot, "tools", "api", "forever.json");
            const text = readFileSync(path, "utf8");
            assert(serialize(JSON.parse(text)) === text, "tools/api/forever.json isn't in api-sync's format; re-run api-sync");
        },
    },
];
