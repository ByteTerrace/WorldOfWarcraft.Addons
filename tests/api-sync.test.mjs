// api-sync's own tests: it refuses partial inputs rather than empty the rules, reads what the
// docs and the dump record, and writes the snapshot in its one-entry-per-line format. --latest
// runs against fixture checkouts and files, never GitHub.

import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { repoRoot } from "../tools/lib/repo.mjs";
import { FIXTURES, assert, tlk, withTemp } from "../tools/lib/test-support.mjs";
import {
    FOREVER_VERSION_URL, MIN_DOC_FUNCTIONS, MIN_GLOBALS, latestBuild, readDocs, readGlobals, serialize, sourceBuild,
} from "../tools/verbs/api-sync.mjs";

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
        // The client names some globals after a table's address, which changes every session.
        name: "api-sync leaves out globals named after an address",
        run: async () => withTemp(async (dir) => {
            const dump = join(dir, "dump.lua");
            writeDump(dump, MIN_GLOBALS);
            const text = readFileSync(dump, "utf8").replace('["Enum"]', '["table: 000001F161607270"] = { ["type"] = "table" },\n["TWO-HANDED_AXES"] = { ["type"] = "string" },\n["Enum"]');
            writeFileSync(dump, text);
            const { globals } = await readGlobals(dump);
            assert(!("table: 000001F161607270" in globals), "an address isn't a name code can use");
            assert(globals["TWO-HANDED_AXES"] === "string", "other names the client really has stay");
        }),
    },
    {
        name: "api-sync reads a build from wow-ui-source's version.txt or a commit title",
        run() {
            assert(sourceBuild("1.60.1.70374\n") === "1.60.1 (70374)", sourceBuild("1.60.1.70374\n"));
            assert(sourceBuild("1.60.1 (70374)") === "1.60.1 (70374)", "a commit title");
            assert(sourceBuild("") === null && sourceBuild("1.60.1") === null && sourceBuild("<html>1.60.1.70374 x</html>") === null, "nothing else");
            assert(FOREVER_VERSION_URL.includes("Gethe/wow-ui-source/forever/version.txt"), FOREVER_VERSION_URL);
        },
    },
    {
        // The fixture checkout's version.txt says 1.60.2 (71000).
        name: "api-sync --latest exits 0 when the snapshot's docs build is the branch's newest, 1 when it differs, 2 when unreadable",
        run: async () => withTemp(async (dir) => {
            const out = join(dir, "forever.json");
            const docs = (build) => JSON.stringify({ source: { docs: `Blizzard_APIDocumentationGenerated (Gethe/wow-ui-source, forever), ${build}` } });
            const checkout = join(FIXTURES, "api", "wow-ui-source");
            writeFileSync(out, docs("1.60.1 (70374)"));
            const stale = tlk(["api-sync", "--latest", "--source", checkout, "--out", out]);
            assert(stale.status === 1, `a newer build exits 1 (got ${stale.status}): ${stale.stdout}${stale.stderr}`);
            assert(stale.stderr.includes("the forever branch of Gethe/wow-ui-source is at 1.60.2 (71000)") && stale.stderr.includes("documents 1.60.1 (70374)")
                && stale.stderr.includes("api-sync --docs"), stale.stderr);
            writeFileSync(out, docs("1.60.2 (71000)"));
            const current = tlk(["api-sync", "--latest", "--source", join(checkout, "version.txt"), "--out", out]);
            assert(current.status === 0 && current.stdout.includes("documents 1.60.2 (71000), the forever branch's newest build"), `${current.status} ${current.stdout}${current.stderr}`);
            assert(readFileSync(out, "utf8") === docs("1.60.2 (71000)"), "--latest writes nothing");
            const title = join(dir, "title.txt");
            writeFileSync(title, "1.60.2 (71000)\n");
            assert(tlk(["api-sync", "--latest", "--source", title, "--out", out]).status === 0, "a commit title");
            writeFileSync(title, "no build here\n");
            const unreadable = tlk(["api-sync", "--latest", "--source", title, "--out", out]);
            assert(unreadable.status === 2 && unreadable.stderr.includes("no build in"), `${unreadable.status} ${unreadable.stderr}`);
            writeFileSync(out, JSON.stringify({ source: {} }));
            const undocumented = tlk(["api-sync", "--latest", "--source", checkout, "--out", out]);
            assert(undocumented.status === 2 && undocumented.stderr.includes("records no docs build"), `${undocumented.status} ${undocumented.stderr}`);
            assert(tlk(["api-sync", "--source", checkout, "--out", out]).status === 2, "--source needs --latest");
        }),
    },
    {
        // A checkout without version.txt: its HEAD commit's title, as wow-ui-source titles them.
        name: "api-sync --latest reads a checkout's HEAD commit title when it has no version.txt",
        run: async () => withTemp(async (dir) => {
            const git = (...args) => {
                const result = spawnSync("git", ["-C", dir, "-c", "user.name=tlk", "-c", "user.email=tlk@example.invalid", ...args], { encoding: "utf8" });
                assert(result.status === 0, `git ${args.join(" ")}: ${result.stderr}`);
            };
            git("init", "--quiet");
            git("commit", "--quiet", "--allow-empty", "-m", "1.60.3 (72000)");
            assert(await latestBuild(dir) === "1.60.3 (72000)", "the commit title");
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
