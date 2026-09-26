// The tooling's own tests. The check gate runs over fixture addons (tests/fixtures/check): BadAddon
// has one violation per marked line, GoodAddon exercises every allowed construct, LegacyAddon has
// no _Camelot TOC, and FrameworkAddon (built on a stub ByteTerrace_Core) reaches past the framework. The findings must be exactly EXPECTED, so a rule that stops firing (or starts
// misfiring) fails. api-sync, the test runner, deploy's link handling and the probes verb are
// tested here too.

import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { repoRoot } from "../tools/lib/repo.mjs";
import { loadApi, runChecks } from "../tools/verbs/check.mjs";
import { MIN_GLOBALS, readGlobals, serialize } from "../tools/verbs/api-sync.mjs";
import { compareTargets, normalizeTarget, selectAddons } from "../tools/verbs/deploy.mjs";
import { PROBES_PATH, luaLiteral, readRecords, serializeProbes } from "../tools/lib/probes.mjs";

const FIXTURES = join(repoRoot, "tests", "fixtures");
const SECRET_CALL = "check issecretvalue on each result before any use or annotate \"-- secret: <why>\"";
const SECRET_VALUE = "and is passed as a value, so its results skip the call-site check; annotate \"-- secret: <why>\"";
const SECRET_PAYLOAD = "check issecretvalue before comparing, computing or branching on it, or annotate \"-- secret: <why>\"";
const PROTECTED = "guard it with an InCombatLockdown() test that returns early (or a `not InCombatLockdown()` branch), or annotate \"-- protected: <why>\"";
const BLOCKED = (name, why) => `PROTECTED ${name} can be blocked during combat lockdown (${why}); ${PROTECTED}`;
const OPAQUE = (what) => `GLOBAL ${what}; annotate "-- global: <why>"`;
const FENV = OPAQUE("getfenv with a level other than 0 or 1 reaches another function's environment");
const UNDECLARED = (name) => `GLOBAL write to undeclared global ${name} (declare it in ## X-Globals)`;
const INTO = (name) => `GLOBAL assignment into client global ${name}; annotate "-- global: <why>" if intended`;
const B = "BadAddon/Bad.lua";
const B2 = "BadAddon/Bad2.lua";
const BS = "BadAddon/BadStyle.lua";
const BANNER = "COMMENT banner divider: let the code's structure and doc comments do that work";
const DEBT = (marker) => `COMMENT debt marker "${marker}": do the work, or say what's true today`;
const HP = `UnitHealth can return a secret (SecretReturns); ${SECRET_CALL}`;

const FW = "FrameworkAddon/Framework.lua";
const TIMERS = "use a module timer (module:After, module:Every), which runs as a batch and stops with its module";
const COMMS = "use a module's comms (comms = { prefix }), which keeps Blizzard's addon message rules";

const EXPECTED = [
    "LegacyAddon/LegacyAddon.toc:1: TOC LegacyAddon has no LegacyAddon_Camelot.toc, so the Forever client won't load it",
    "BadAddon/BadAddon_Camelot.toc:1: TOC ## Interface 11507 but the installed client is 16001",
    "BadAddon/BadAddon_Camelot.toc:1: TOC dependency MissingAddon is not an addon in this repository",
    "BadAddon/BadAddon_Camelot.toc:1: TOC dependency AlsoMissing is not an addon in this repository",
    "BadAddon/BadAddon_Camelot.toc:1: TOC dependency ThirdMissing is not an addon in this repository",
    "BadAddon/BadAddon_Camelot.toc:1: TOC lists Missing.lua, which does not exist",
    "BadAddon/Orphan.lua:1: TOC not listed in BadAddon_Camelot.toc",
    `${B}:5: EVENT unknown event NOT_A_REAL_EVENT`,
    `${B}:6: SECRET UnitHealth can return a secret (SecretReturns); ${SECRET_CALL}`,
    `${B}:7: MEMBER C_GamePad.NotARealFunction is not in the API snapshot`,
    `${B}:8: GLOBAL read of unknown global NotARealGlobal`,
    `${B}:9: ${UNDECLARED("LeakedGlobal")}`,
    `${B}:13: STYLE trailing whitespace`,
    `${B}:14: SECRET UnitHealth can return a secret (SecretReturns); ${SECRET_CALL}`,
    `${B}:17: SECRET UnitHealth can return a secret (SecretReturns); ${SECRET_CALL}`,
    `${B}:19: SECRET UnitHealth can return a secret (SecretReturns) ${SECRET_VALUE}`,
    `${B}:21: SECRET UnitHealth can return a secret (SecretReturns) ${SECRET_VALUE}`,
    `${B}:23: SECRET :GetText() can return a secret (Text aspect); ${SECRET_CALL}`,
    `${B}:25: SECRET UnitClass can return a secret (SecretWhenUnitIdentityRestricted); ${SECRET_CALL}`,
    `${B}:28: ${UNDECLARED("LeakedViaG")}`,
    `${B}:29: ${UNDECLARED("LeakedViaIndex")}`,
    `${B}:30: GLOBAL global write with a dynamic key; annotate "-- global: <why>"`,
    `${B}:31: ${UNDECLARED("LeakedViaFenv")}`,
    `${B}:32: ${UNDECLARED("LeakedViaRawset")}`,
    `${B}:33: ${UNDECLARED("LeakedViaSetglobal")}`,
    `${B}:34: GLOBAL read of unknown global NotARealGlobal2`,
    `${B}:35: ${INTO("string.trimall")}`,
    `${B}:36: ${INTO("C_GamePad.Hijack")}`,
    `${B}:37: GLOBAL frame name UIParent collides with a client global`,
    `${B}:38: GLOBAL read of unknown global NotARealGlobal3`,
    `${B}:39: GLOBAL read of unknown global ToggleCollision`,
    `${B}:40: MEMBER Enum.PowerType.NotAPowerType is not in the API snapshot`,
    `${B}:42: MEMBER Enum.PowerType.AlsoNotAPowerType is not in the API snapshot`,
    `${B}:43: MEMBER C_Spell.NotASpellFunction is not in the API snapshot`,
    `${B}:44: MEMBER C_Macro.SetMacroExecuteLineCallback is not in the API snapshot`,
    `${B}:45: MEMBER string.dump is not in the API snapshot`,
    `${B}:47: EVENT unknown event NOT_REAL_EITHER`,
    `${B}:48: PROTECTED Settings.OpenToCategory is forbidden to addon code at any time (in-game evidence in tools/api/forbidden.json); no combat guard helps, so don't call it`,
    `${B}:49: ${BLOCKED("C_AuctionHouse.PlaceBid", "HasRestrictions")}`,
    `${B}:51: ${BLOCKED(":SetPoint()", "protected method on a Secure frame")}`,
    `${B}:53: ${INTO("string.Helper")}`,
    // Round two: annotations, real guards, aliases, dot calls, environments, protection.
    `${B2}:4: SECRET ${HP}`, // a trailing annotation on the line above doesn't cover this line
    `${B2}:6: SECRET ${HP}`, // a block comment isn't an annotation
    `${B2}:8: SECRET UnitHealth can return a secret (SecretReturns) ${SECRET_VALUE}`, // alias later reassigned
    `${B2}:9: SECRET UnitHealthMax can return a secret (SecretWhenUnitHealthMaxRestricted) ${SECRET_VALUE}`,
    `${B2}:13: SECRET ${HP}`, // used before the check
    `${B2}:20: SECRET ${HP}`, // stored before the check
    `${B2}:25: SECRET ${HP}`, // check result discarded
    `${B2}:30: SECRET ${HP}`, // result local reassigned
    `${B2}:36: SECRET ${HP}`, // guarded branch doesn't exit
    `${B2}:42: SECRET :GetValue() can return a secret (BarValue aspect); ${SECRET_CALL}`,
    `${B2}:43: SECRET .GetValue can return a secret (BarValue aspect) ${SECRET_VALUE}`,
    `${B2}:44: SECRET ${HP}`, // getglobal("UnitHealth")
    `${B2}:45: ${FENV}`,
    `${B2}:46: ${OPAQUE("loadstring compiles code the gate can't see")}`,
    `${B2}:47: ${OPAQUE("setfenv changes a function's environment")}`,
    `${B2}:48: ${FENV}`,
    `${B2}:52: ${BLOCKED("C_AuctionHouse.PlaceBid", "HasRestrictions")}`, // InCombatLockdown() discarded
    `${B2}:56: ${BLOCKED("C_AuctionHouse.PlaceBid", "HasRestrictions")}`, // the lockdown branch doesn't return
    `${B2}:60: ${BLOCKED("C_AuctionHouse.PlaceBid", "HasRestrictions")}`, // a closure runs later
    `${B2}:64: ${BLOCKED(":SetPoint()", "protected method on a Secure frame")}`, // through a field
    `${B2}:67: ${BLOCKED(":Show()", "protected method on a Secure frame")}`, // through an alias
    `${B2}:68: ${BLOCKED(":Hide()", "protected method on a frame not proven non-Secure, in a file that creates Secure frames")}`,
    `${B2}:71: ${BLOCKED(":SetPropagateKeyboardInput()", "HasRestrictions")}`, // any receiver
    `${B2}:75: SECRET CHAT_MSG_AFK payload parameter text can be secret (SecretInChatMessagingLockdown); ${SECRET_PAYLOAD}`,
    `${B2}:78: SECRET CHAT_MSG_AFK payload parameter text can be secret (SecretInChatMessagingLockdown); ${SECRET_PAYLOAD}`,
    `${B2}:79: SECRET CHAT_MSG_AFK payload parameter text can be secret (SecretInChatMessagingLockdown); ${SECRET_PAYLOAD}`, // copied
    `${B2}:80: SECRET CHAT_MSG_AFK payload parameter text can be secret (SecretInChatMessagingLockdown); ${SECRET_PAYLOAD}`, // stored
    `${B2}:81: SECRET CHAT_MSG_AFK payload parameter text can be secret (SecretInChatMessagingLockdown); ${SECRET_PAYLOAD}`, // tabled
    `${B2}:82: SECRET ${HP}`, // \`_\` only discards what nothing reads
    `${B2}:85: PROTECTED SetRaidTarget is forbidden to addon code at any time (in-game evidence in tools/api/forbidden.json); no combat guard helps, so don't call it`,
    `${B2}:87: SECRET CHAT_MSG_AFK payload parameter text can be secret (SecretInChatMessagingLockdown); ${SECRET_PAYLOAD}`, // a table key
    `${B2}:88: SECRET CHAT_MSG_AFK payload parameter text can be secret (SecretInChatMessagingLockdown); ${SECRET_PAYLOAD}`, // out of an and/or
    `${B2}:91: SECRET cur holds UnitPower's result; the annotation on line 90 covers the call, not this use, which errors on a secret: check issecretvalue before it, or annotate "-- secret: <why>"`,
    `${B2}:94: EVENT COMBAT_LOG_EVENT_UNFILTERED is restricted to Blizzard's code; registering it is refused (ADDON_ACTION_FORBIDDEN)`,
    `${B2}:95: PROTECTED SettingsPanel:OpenToCategory is forbidden to addon code at any time (in-game evidence in tools/api/forbidden.json); no combat guard helps, so don't call it`,
    // Naming and comments (GoodAddon/GoodStyle.lua holds the allowed constructs).
    `${BS}:3: NAMING constant 'MAX_ITEMS' should be PascalCase (MaxItems)`,
    `${BS}:4: NAMING file-level local 'itemCount' should be PascalCase (ItemCount)`,
    `${BS}:5: NAMING function 'helper' should be PascalCase (Helper)`,
    `${BS}:7: NAMING method 'on_event' should be PascalCase (OnEvent)`,
    `${BS}:8: NAMING parameter 'Count' should be camelCase (count)`,
    `${BS}:10: NAMING local 'Total' should be camelCase (total)`,
    `${BS}:11: NAMING loop variable 'Index' should be camelCase (index)`,
    `${BS}:14: NAMING loop variable 'Key' should be camelCase (key)`,
    `${BS}:16: NAMING local 'Doubled' should be camelCase (doubled)`, // a top-level loop's locals are locals
    `${BS}:19: NAMING function 'later' should be PascalCase (Later)`, // declared ahead, given a function below
    `${BS}:20: NAMING function 'later' should be PascalCase (Later)`,
    `${BS}:21: ${BANNER}`,
    `${BS}:22: ${DEBT("TODO")}`,
    `${BS}:23: ${DEBT("for now")}`,
    `${FW}:7: FRAMEWORK C_Timer.After belongs to the framework; ${TIMERS}`,
    `${FW}:8: FRAMEWORK C_Timer.NewTicker belongs to the framework; ${TIMERS}`,
    `${FW}:9: FRAMEWORK CHAT_MSG_ADDON belongs to the framework; ${COMMS}`,
    `${FW}:10: FRAMEWORK C_ChatInfo.SendAddonMessage belongs to the framework; ${COMMS}`,
    `${FW}:11: FRAMEWORK PlaySoundFile belongs to the framework; use a sound bank (ByteTerrace.NewSoundBank)`,
    `${FW}:12: FRAMEWORK C_Timer.NewTimer belongs to the framework; ${TIMERS}`,
];

function assertSame(actual, expected) {
    const missing = expected.filter((f) => !actual.includes(f));
    const unexpected = actual.filter((f) => !expected.includes(f));
    if (missing.length || unexpected.length) {
        throw new Error(`missing: ${JSON.stringify(missing)} unexpected: ${JSON.stringify(unexpected)}`);
    }
}

function assert(condition, message) {
    if (!condition) throw new Error(message);
}

async function withTemp(fn) {
    const dir = mkdtempSync(join(tmpdir(), "tlk-test-"));
    try {
        return await fn(dir);
    } finally {
        rmSync(dir, { recursive: true, force: true });
    }
}

// A minimal DevTools dump with `count` function globals plus a nested Enum table.
function writeDump(path, count) {
    const rows = [];
    for (let i = 0; i < count; i++) rows.push(`["Global${i}"] = { ["type"] = "function" },`);
    rows.push(`["Enum"] = { ["type"] = "table", ["members"] = { "PowerType" }, ["tables"] = { ["PowerType"] = { "Energy", "Mana" } } },`);
    rows.push(`["SlashCmdList"] = { ["type"] = "table", ["members"] = { "BYTETERRACEDEVTOOLS", "HELP" } },`);
    writeFileSync(path, `ByteTerraceDevToolsDB = { ["build"] = { ["build"] = "1", ["version"] = "1.60.1" }, ["globals"] = {\n${rows.join("\n")}\n} }\n`);
}

function tlk(args) {
    return spawnSync(process.execPath, [join(repoRoot, "tools", "tlk.mjs"), ...args], { encoding: "utf8", cwd: repoRoot });
}

export const tests = [
    {
        name: "check reports exactly the planted violations, and nothing for allowed constructs",
        run: async () => {
            assertSame(await runChecks({ quiet: true, root: join(FIXTURES, "check"), clientInterface: 16001 }), EXPECTED);
        },
    },
    {
        name: "check skips the interface check, and says so, when no client is found",
        run: async () => {
            const lines = [];
            const log = console.log;
            console.log = (line) => lines.push(String(line));
            try {
                const findings = await runChecks({ root: join(FIXTURES, "check"), wowRoot: join(FIXTURES, "no-such-install") });
                assert(!findings.some((f) => f.includes("## Interface")), "no interface finding without a client");
            } finally {
                console.log = log;
            }
            assert(lines.includes("Interface check skipped (no client found)"), `printed: ${lines.slice(0, 3).join(" | ")}`);
        },
    },
    {
        name: "snapshot truth: with a dump only dumped names are known; without one the docs are the fallback",
        run: async () => {
            const api = loadApi();
            assert(api.hasDump, "the committed snapshot has a dump");
            assert(!api.globals.has("ToggleCollision"), "documented but not in the dump");
            assert(api.members.get("string").has("format") && !api.members.get("string").has("dump"), "stdlib from the dump");
            const docsOnly = loadApi(join(FIXTURES, "api", "nodump.json"));
            assert(!docsOnly.hasDump && docsOnly.globals.has("UnitHealth") && docsOnly.members.get("C_Spell").has("GetSpellName"), "docs fallback");
            assert(docsOnly.members.get("Enum.PowerType").has("Energy"), "documented enumerations");
        },
    },
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
        // The timeout counts from the end of a worker's setup, so a loaded machine can't time out
        // the quick file; the hanging one never finishes, however long the timeout.
        name: "the test runner fails on an unmatched filter and times out a hanging file without stopping the rest",
        run: async () => {
            const none = tlk(["test", "no test is named this"]);
            assert(none.status === 1 && none.stdout.includes("No test matches"), `unmatched filter: ${none.status} ${none.stdout}`);
            const hang = tlk(["test", "--dir", join(FIXTURES, "runner"), "--timeout", "1"]);
            assert(hang.status === 1, `hang exits non-zero (got ${hang.status})`);
            assert(/FAIL hang\.test\.lua: timed out after 1s/.test(hang.stdout), hang.stdout);
            assert(/\b2 passed, 1 failed/.test(hang.stdout), hang.stdout);
        },
    },
    {
        name: "the test runner keeps test names with newlines, tabs and backslashes intact",
        run: async () => {
            const run = tlk(["test", "--dir", join(FIXTURES, "runner-names")]);
            assert(/\b3 passed, 1 failed/.test(run.stdout), run.stdout);
            assert(run.stdout.includes('FAIL names.test.lua > "tab\\tin name"'), run.stdout);
            assert(/line one\n {5}line two/.test(run.stdout), run.stdout);
            const filtered = tlk(["test", "--dir", join(FIXTURES, "runner-names"), "with\nnewline"]);
            assert(filtered.status === 0 && /\b1 passed, 0 failed/.test(filtered.stdout), filtered.stdout);
            const slash = tlk(["test", "--dir", join(FIXTURES, "runner-names"), "back\\slash"]);
            assert(slash.status === 0 && /\b1 passed, 0 failed/.test(slash.stdout), slash.stdout);
        },
    },
    {
        name: "deploy refuses an unknown addon name",
        run: async () => {
            const result = tlk(["deploy", "--addon", "NoSuchAddon", "--flavor", "_none_", "--wow-root", join(FIXTURES, "no-such-install")]);
            assert(result.status === 1 && result.stderr.includes("Unknown addon(s): NoSuchAddon"), `${result.status} ${result.stderr}`);
        },
    },
    {
        name: "deploy selects transitive dependencies regardless of directory order, but unlink stays exact",
        run() {
            const all = [
                { name: "Foundation", dependencies: [] },
                { name: "Shared", dependencies: ["Foundation"] },
                { name: "Toolkit", dependencies: ["Shared"] },
                { name: "Unrelated", dependencies: [] },
            ];
            const names = (addons) => addons.map((addon) => addon.name).sort().join(",");
            assert(names(selectAddons(all, ["Toolkit"])) === "Foundation,Shared,Toolkit", "the full dependency chain");
            assert(names(selectAddons(all, ["Toolkit"], false)) === "Toolkit", "unlink doesn't remove shared dependencies");
            all[0].dependencies.push("Toolkit");
            assert(names(selectAddons(all, ["Toolkit"])) === "Foundation,Shared,Toolkit", "cycles terminate");
        },
    },
    {
        name: "deploy normalizes link targets before comparing them",
        run: async () => {
            const link = join(repoRoot, "links", "Addon");
            assert(normalizeTarget("\\\\?\\" + join(repoRoot, "Addon") + "\\", link) === join(repoRoot, "Addon"), "\\\\?\\ prefix and trailing separator");
            assert(normalizeTarget(join("..", "Addon"), link) === join(repoRoot, "Addon"), "relative to the link's folder");
            assert(compareTargets(join(repoRoot, "Addon"), join(repoRoot, "Addon") + "/") === "same", "trailing separator");
            assert(compareTargets(join(repoRoot, "addon"), join(repoRoot, "Addon"), "win32") === "case", "case-only difference on Windows");
            assert(compareTargets(join(repoRoot, "addon"), join(repoRoot, "Addon"), "linux") === "other", "case matters elsewhere");
            assert(compareTargets(join(repoRoot, "Other"), join(repoRoot, "Addon")) === "other", "elsewhere");
        },
    },
    {
        name: "the committed snapshot is current with its own serializer",
        run: async () => {
            const path = join(repoRoot, "tools", "api", "forever.json");
            const text = readFileSync(path, "utf8");
            assert(serialize(JSON.parse(text)) === text, "tools/api/forever.json isn't in api-sync's format; re-run api-sync");
        },
    },
    {
        name: "the test runner reports pending tests without failing the run",
        run: async () => {
            const run = tlk(["test", "--dir", join(FIXTURES, "runner-pending")]);
            assert(run.status === 0, `pending doesn't fail (got ${run.status}): ${run.stdout}`);
            assert(run.stdout.includes("PEND pending.test.lua > waits: no observation yet"), run.stdout);
            // The fixture's passing test and the runner's fakes check.
            assert(/\b2 passed, 0 failed, 1 pending/.test(run.stdout), run.stdout);
        },
    },
    {
        name: "probes --import reads the client's SavedVariables layout into the pretty snapshot",
        run: async () => withTemp(async (dir) => {
            const out = join(dir, "probes.json");
            const run = tlk(["probes", "--import", join(FIXTURES, "probes", "client-format.lua"), "--out", out]);
            assert(run.status === 0, `import exits 0 (got ${run.status}): ${run.stdout}${run.stderr}`);
            assert(run.stdout.includes("2 new, 0 changed, 0 unchanged"), run.stdout);
            const text = readFileSync(out, "utf8");
            const expected = [
                "{",
                '  "build": "1.60.1 (70009)",',
                '  "probes": {',
                '    "chatTypeInfo.raidWarning": {',
                '      "result": { "b": 0, "g": 72, "hasMetatable": true, "r": 255, "sticky": 0 },',
                '      "context": { "combat": false, "restrictions": "none" }',
                "    },",
                '    "damageMeter.available": {',
                '      "result": { "failureReason": "", "isAvailable": true },',
                '      "context": { "combat": false, "restrictions": "none" }',
                "    }",
                "  }",
                "}",
                "",
            ].join("\n");
            assert(text === expected, `snapshot:\n${text}`);
            const again = tlk(["probes", "--import", join(FIXTURES, "probes", "client-format.lua"), "--out", out]);
            assert(again.stdout.includes("0 new, 0 changed, 2 unchanged") && readFileSync(out, "utf8") === expected, again.stdout);
        }),
    },
    {
        name: "probes --import refuses broken records, drops unknown probes and keeps strings intact",
        run: async () => withTemp(async (dir) => {
            const out = join(dir, "probes.json");
            const context = { combat: false, restrictions: "none" };
            writeFileSync(out, serializeProbes({ build: "1.60.1 (69000)", probes: {
                "no.longerDefined": { build: "1.60.1 (69000)", context, result: {} },
                "classColors": { build: "1.60.1 (69000)", context, result: { classes: "MAGE" } },
            } }));
            const saved = join(dir, "edge-cases.lua");
            writeFileSync(saved, [
                "ByteTerraceDevToolsDB = { probes = {",
                '    ["unknown.probe"] = { build = "1.60.1 (70009)", context = { combat = false, restrictions = "none" }, result = {} },',
                '    ["tts.voices"] = { build = "1.60.1 (70009)", result = {} },',
                '    ["damageMeter.available"] = {',
                '        build = "1.60.1 (70009)", context = { combat = false, restrictions = "none" },',
                '        result = { failureReason = "tab\\there \\"quoted\\" \\\\ back", isAvailable = false },',
                "    },",
                "} }",
            ].join("\n"));
            const run = tlk(["probes", "--import", saved, "--out", out]);
            assert(run.status === 0, `import exits 0 (got ${run.status}): ${run.stdout}${run.stderr}`);
            assert(run.stdout.includes("Skipped unknown.probe") && run.stdout.includes("Dropped no.longerDefined"), run.stdout);
            assert(run.stderr.includes("Refused tts.voices: the record has no context"), run.stderr);
            assert(run.stderr.includes("records come from 1.60.1 (69000), 1.60.1 (70009)"), run.stderr);
            const text = readFileSync(out, "utf8");
            assert(serializeProbes(JSON.parse(text)) === text, "the snapshot is in its serializer's format");
            const snapshot = JSON.parse(text);
            assert(Object.keys(snapshot.probes).join(",") === "classColors,damageMeter.available", Object.keys(snapshot.probes).join(","));
            assert(snapshot.build === "1.60.1 (70009)", "the file's build is the newest record's");
            assert(snapshot.probes.classColors.build === "1.60.1 (69000)", "an older record names its own build");
            assert(snapshot.probes["damageMeter.available"].build === undefined, "a record of the file's build doesn't repeat it");
            assert(snapshot.probes["damageMeter.available"].result.failureReason === "tab\there \"quoted\" \\ back", text);
            const api = join(dir, "api.json");
            writeFileSync(api, JSON.stringify({ source: { globals: "ByteTerrace_DevTools dump, client 1.60.1 (70009)" } }));
            const check = tlk(["probes", "--check", "--out", out, "--api", api]);
            assert(check.status === 1 && check.stderr.includes("classColors: recorded on 1.60.1 (69000), the API snapshot is 1.60.1 (70009)"),
                `${check.status} ${check.stderr}`);
            const records = await readRecords(saved);
            assert(records["tts.voices"].build === "1.60.1 (70009)", "readRecords returns every record as saved");
            const literal = luaLiteral({ b: "x\ty", a: { c: true, d: 1.5 } });
            assert(literal === '{["a"]={["c"]=true,["d"]=1.5},["b"]="x\\9y"}', literal);
        }),
    },
    {
        name: "probes --import skips and drops records made by another version of their probe",
        run: async () => withTemp(async (dir) => {
            const out = join(dir, "probes.json");
            const context = { combat: false, restrictions: "none" };
            const recap = { hasRecapEvents: true };
            // deathRecap.events is version 2: a record without a version is version 1's.
            writeFileSync(out, serializeProbes({ build: "1.60.1 (70009)", probes: {
                "deathRecap.events": { context, result: recap },
            } }));
            const saved = join(dir, "versions.lua");
            writeFileSync(saved, [
                "ByteTerraceDevToolsDB = { probes = {",
                '    ["deathRecap.events"] = { build = "1.60.1 (70009)", context = { combat = false, restrictions = "none" }, result = {} },',
                "} }",
            ].join("\n"));
            const api = join(dir, "api.json");
            writeFileSync(api, JSON.stringify({ source: { globals: "ByteTerrace_DevTools dump, client 1.60.1 (70009)" } }));
            const check = tlk(["probes", "--check", "--out", out, "--api", api]);
            assert(check.status === 1 && check.stderr.includes("deathRecap.events: made by version 1, the probe is version 2"),
                `${check.status} ${check.stderr}`);
            const run = tlk(["probes", "--import", saved, "--out", out]);
            assert(run.status === 0, `import exits 0 (got ${run.status}): ${run.stdout}${run.stderr}`);
            assert(run.stdout.includes("Skipped deathRecap.events: the record was made by version 1 of the probe, which is now version 2"), run.stdout);
            assert(run.stdout.includes("Dropped deathRecap.events"), run.stdout);
            assert(!("deathRecap.events" in JSON.parse(readFileSync(out, "utf8")).probes), "the old version's record is gone");
            writeFileSync(saved, [
                "ByteTerraceDevToolsDB = { probes = {",
                '    ["deathRecap.events"] = { build = "1.60.1 (70009)", version = 2, context = { combat = false, restrictions = "none" }, result = {} },',
                "} }",
            ].join("\n"));
            const current = tlk(["probes", "--import", saved, "--out", out]);
            assert(current.stdout.includes("1 new"), current.stdout);
            const text = readFileSync(out, "utf8");
            assert(JSON.parse(text).probes["deathRecap.events"].version === 2 && serializeProbes(JSON.parse(text)) === text, text);
        }),
    },
    {
        name: "probes reports each probe's client and harness answers and their status",
        run: async () => withTemp(async (dir) => {
            const out = join(dir, "probes.json");
            const context = { combat: false, restrictions: "none" };
            writeFileSync(out, serializeProbes({ build: "1.60.1 (70009)", probes: {
                "chatTypeInfo.raidWarning": { context, result: { b: 0, g: 72, hasMetatable: true, r: 255, sticky: 0 } },
                "damageMeter.available": { context, result: { failureReason: "disabled", isAvailable: false } },
            } }));
            const run = tlk(["probes", "--out", out]);
            assert(run.status === 1, `a mismatch exits 1 (got ${run.status}): ${run.stdout}${run.stderr}`);
            assert(/chatTypeInfo\.raidWarning +anywhere +match\n {4}both +\{b=0 g=72 hasMetatable=true r=255 sticky=0\}/.test(run.stdout), run.stdout);
            assert(/damageMeter\.available +anywhere +mismatch\n {4}client +\{failureReason=disabled isAvailable=false\}.*\n {4}harness +\{failureReason="" isAvailable=true\}/.test(run.stdout), run.stdout);
            assert(/quest\.offer +quest offer open +harness can't set up/.test(run.stdout), run.stdout);
            const [, pending, total] = /To do in game: (\d+) of (\d+) probes need a result\./.exec(run.stdout) ?? [];
            assert(Number(total) - Number(pending) === 2, run.stdout);
        }),
    },
    {
        name: "the committed probe snapshot is current with its own serializer",
        run: async () => {
            const text = readFileSync(PROBES_PATH, "utf8");
            assert(serializeProbes(JSON.parse(text)) === text, "tools/api/probes.json isn't in the probes verb's format; re-run tlk probes --import");
        },
    },
];
