// The probes verb's own tests (tools/verbs/probes.mjs): importing the client's SavedVariables into
// tools/api/probes.json, refusing broken or outdated records, and the report of client and harness
// answers. Every run writes to a temporary snapshot, never the committed one.

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { PROBES_PATH, luaLiteral, readDefinitions, readRecords, serializeProbes } from "../tools/lib/probes.mjs";
import { FIXTURES, assert, tlk, withTemp } from "../tools/lib/test-support.mjs";

export const tests = [
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
                '      "contexts": { "combat/Combat": true, "idle/none": true }',
                "    },",
                '    "damageMeter.available": {',
                '      "result": { "failureReason": "", "isAvailable": true },',
                '      "contexts": { "idle/none": true }',
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
        name: "probes --import merges an accumulating probe's record into the saved one, never shrinking it",
        run: async () => withTemp(async (dir) => {
            const out = join(dir, "probes.json");
            const contexts = { "idle/none": true };
            writeFileSync(out, serializeProbes({ build: "1.60.1 (70009)", probes: {
                "names.chatSenders": { contexts, result: { CHAT_MSG_SAY: "Aa,Aa Aa" } },
            } }));
            const saved = join(dir, "senders.lua");
            writeFileSync(saved, [
                "ByteTerraceDevToolsDB = { probes = {",
                '    ["names.chatSenders"] = { build = "1.60.1 (70009)", contexts = { ["combat/Combat"] = true },',
                '        result = { CHAT_MSG_SAY = "Aa", CHAT_MSG_CHANNEL = { secret = true, type = "string" } } },',
                "} }",
            ].join("\n"));
            const run = tlk(["probes", "--import", saved, "--out", out]);
            assert(run.status === 0, `${run.stdout}${run.stderr}`);
            const record = JSON.parse(readFileSync(out, "utf8")).probes["names.chatSenders"];
            const result = record.result;
            assert(result.CHAT_MSG_SAY === "Aa,Aa Aa", `what earlier sessions saw stays: ${JSON.stringify(result)}`);
            assert(result.CHAT_MSG_CHANNEL?.secret === true, `and the new session's adds: ${JSON.stringify(result)}`);
            assert(Object.keys(record.contexts).join(" ") === "combat/Combat idle/none", `their contexts join: ${JSON.stringify(record)}`);
        }),
    },
    {
        name: "probes --import adds a new context, changes nothing for a known one, and a new result replaces the record",
        run: async () => withTemp(async (dir) => {
            const out = join(dir, "probes.json");
            const saved = join(dir, "contexts.lua");
            const result = '{ b = 0, g = 72, hasMetatable = true, r = 255, sticky = 0 }';
            const importOne = (contexts, recorded = result) => {
                writeFileSync(saved, `ByteTerraceDevToolsDB = { probes = { ["chatTypeInfo.raidWarning"] = { build = "1.60.1 (70009)", contexts = ${contexts}, result = ${recorded} } } }`);
                const run = tlk(["probes", "--import", saved, "--out", out]);
                assert(run.status === 0, `${run.stdout}${run.stderr}`);
                return { stdout: run.stdout, text: readFileSync(out, "utf8") };
            };
            const record = (text) => JSON.parse(text).probes["chatTypeInfo.raidWarning"];
            const first = importOne('{ ["idle/none"] = true }');
            assert(first.stdout.includes("1 new, 0 changed, 0 unchanged"), first.stdout);
            const widened = importOne('{ ["combat/Combat"] = true }');
            assert(widened.stdout.includes("0 new, 1 changed, 0 unchanged"), `a new context is a change: ${widened.stdout}`);
            assert(Object.keys(record(widened.text).contexts).join(" ") === "combat/Combat idle/none", widened.text);
            const again = importOne('{ ["idle/none"] = true }');
            assert(again.stdout.includes("0 new, 0 changed, 1 unchanged") && again.text === widened.text,
                `a known context alone changes nothing: ${again.stdout}`);
            const replaced = importOne('{ ["idle/none"] = true }', '{ b = 0, g = 0, hasMetatable = true, r = 255, sticky = 0 }');
            assert(replaced.stdout.includes("0 new, 1 changed, 0 unchanged"), replaced.stdout);
            assert(replaced.stdout.includes("Replaced chatTypeInfo.raidWarning: its result changed, so it now holds only idle/none, not combat/Combat"),
                replaced.stdout);
            assert(Object.keys(record(replaced.text).contexts).join(" ") === "idle/none" && record(replaced.text).result.g === 0, replaced.text);
        }),
    },
    {
        name: "probes --import refuses broken records, drops unknown probes and keeps strings intact",
        run: async () => withTemp(async (dir) => {
            const out = join(dir, "probes.json");
            const contexts = { "idle/none": true };
            writeFileSync(out, serializeProbes({ build: "1.60.1 (69000)", probes: {
                "no.longerDefined": { build: "1.60.1 (69000)", contexts, result: {} },
                "classColors": { build: "1.60.1 (69000)", contexts, result: { classes: "MAGE" } },
            } }));
            const saved = join(dir, "edge-cases.lua");
            writeFileSync(saved, [
                "ByteTerraceDevToolsDB = { probes = {",
                '    ["unknown.probe"] = { build = "1.60.1 (70009)", contexts = { ["idle/none"] = true }, result = {} },',
                '    ["tts.voices"] = { build = "1.60.1 (70009)", result = {} },',
                '    ["chat.lockdownIdle"] = { build = "1.60.1 (70009)", context = { combat = false, restrictions = "none" }, result = {} },',
                '    ["chatTypeInfo.raidWarning"] = { build = "1.60.1 (70009)", contexts = { ["asleep/none"] = true }, result = {} },',
                '    ["damageMeter.available"] = {',
                '        build = "1.60.1 (70009)", contexts = { ["idle/none"] = true },',
                '        result = { failureReason = "tab\\there \\"quoted\\" \\\\ back", isAvailable = false },',
                "    },",
                "} }",
            ].join("\n"));
            const run = tlk(["probes", "--import", saved, "--out", out]);
            assert(run.status === 0, `import exits 0 (got ${run.status}): ${run.stdout}${run.stderr}`);
            assert(run.stdout.includes("Skipped unknown.probe") && run.stdout.includes("Dropped no.longerDefined"), run.stdout);
            assert(run.stderr.includes("Refused tts.voices: the record has no contexts"), run.stderr);
            assert(run.stdout.includes("Skipped 1 record saved in the old one-context format (chat.lockdownIdle): DevTools replaces each the next time its probe runs."), `a lone context isn't read: ${run.stdout}`);
            assert(!run.stderr.includes("chat.lockdownIdle"), `nor refused one by one: ${run.stderr}`);
            assert(run.stderr.includes('Refused chatTypeInfo.raidWarning: the record has a bad context "asleep/none"'), run.stderr);
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
            assert(literal === '{["a"]={["c"]=true,["d"]=1.5},["b"]="x\\009y"}', literal);
            // An escape is always three digits, so a digit after it can't join it.
            for (const [text, expected] of [["line\n2", '"line\\0102"'], ['say "5"', '"say \\0345\\034"'], ["a\\9", '"a\\0929"']]) {
                assert(luaLiteral(text) === expected, `${JSON.stringify(text)}: ${luaLiteral(text)}`);
            }
        }),
    },
    {
        name: "probes --import skips and drops records made by another version of their probe",
        run: async () => withTemp(async (dir) => {
            const out = join(dir, "probes.json");
            const contexts = { "idle/none": true };
            const recap = { hasRecapEvents: true };
            // deathRecap.events is past version 1, and a record without a version is version 1's.
            const version = (await readDefinitions()).find((probe) => probe.name === "deathRecap.events").version;
            assert(version >= 2, `deathRecap.events is version ${version}`);
            writeFileSync(out, serializeProbes({ build: "1.60.1 (70009)", probes: {
                "deathRecap.events": { contexts, result: recap },
            } }));
            const saved = join(dir, "versions.lua");
            writeFileSync(saved, [
                "ByteTerraceDevToolsDB = { probes = {",
                '    ["deathRecap.events"] = { build = "1.60.1 (70009)", contexts = { ["idle/none"] = true }, result = {} },',
                "} }",
            ].join("\n"));
            const api = join(dir, "api.json");
            writeFileSync(api, JSON.stringify({ source: { globals: "ByteTerrace_DevTools dump, client 1.60.1 (70009)" } }));
            const check = tlk(["probes", "--check", "--out", out, "--api", api]);
            assert(check.status === 1 && check.stderr.includes(`deathRecap.events: made by version 1, the probe is version ${version}`),
                `${check.status} ${check.stderr}`);
            const run = tlk(["probes", "--import", saved, "--out", out]);
            assert(run.status === 0, `import exits 0 (got ${run.status}): ${run.stdout}${run.stderr}`);
            assert(run.stdout.includes(`Skipped deathRecap.events: the record was made by version 1 of the probe, which is now version ${version}`), run.stdout);
            assert(run.stdout.includes("Dropped deathRecap.events"), run.stdout);
            assert(!("deathRecap.events" in JSON.parse(readFileSync(out, "utf8")).probes), "the old version's record is gone");
            writeFileSync(saved, [
                "ByteTerraceDevToolsDB = { probes = {",
                `    ["deathRecap.events"] = { build = "1.60.1 (70009)", version = ${version}, contexts = { ["idle/none"] = true }, result = {} },`,
                "} }",
            ].join("\n"));
            const current = tlk(["probes", "--import", saved, "--out", out]);
            assert(current.stdout.includes("1 new"), current.stdout);
            const text = readFileSync(out, "utf8");
            assert(JSON.parse(text).probes["deathRecap.events"].version === version && serializeProbes(JSON.parse(text)) === text, text);
        }),
    },
    {
        // CI can't re-run a probe in game: another build is a warning there, but a record of a
        // probe that's gone (or of another probe version) still fails.
        name: "probes --check --warn-builds warns about records from another build and still fails on orphaned ones",
        run: async () => withTemp(async (dir) => {
            const out = join(dir, "probes.json");
            const api = join(dir, "api.json");
            writeFileSync(api, JSON.stringify({ source: { globals: "ByteTerrace_DevTools dump, client 1.60.1 (70374)" } }));
            const contexts = { "idle/none": true };
            const raidWarning = { build: "1.60.1 (70009)", contexts, result: { b: 0, g: 72, hasMetatable: true, r: 255, sticky: 0 } };
            writeFileSync(out, serializeProbes({ build: "1.60.1 (70374)", probes: { "chatTypeInfo.raidWarning": raidWarning } }));
            const strict = tlk(["probes", "--check", "--out", out, "--api", api]);
            assert(strict.status === 1 && strict.stderr.includes("chatTypeInfo.raidWarning: recorded on 1.60.1 (70009), the API snapshot is 1.60.1 (70374)"),
                `--check alone fails on another build: ${strict.status} ${strict.stderr}`);
            const warned = tlk(["probes", "--check", "--warn-builds", "--out", out, "--api", api]);
            assert(warned.status === 0, `another build only warns (got ${warned.status}): ${warned.stderr}`);
            assert(warned.stderr.includes("probes: warning: records from another build")
                && warned.stderr.includes("chatTypeInfo.raidWarning: recorded on 1.60.1 (70009)") && !warned.stderr.includes("Stale records"), warned.stderr);
            writeFileSync(out, serializeProbes({ build: "1.60.1 (70374)", probes: {
                "chatTypeInfo.raidWarning": raidWarning,
                "no.longerDefined": { contexts, result: { value: 1 } },
            } }));
            const orphaned = tlk(["probes", "--check", "--warn-builds", "--out", out, "--api", api]);
            assert(orphaned.status === 1 && orphaned.stderr.includes("no.longerDefined: ByteTerrace_DevTools no longer defines it"),
                `${orphaned.status} ${orphaned.stderr}`);
            assert(!/Stale records[^]*chatTypeInfo/.test(orphaned.stderr), `another build stays a warning: ${orphaned.stderr}`);
            const alone = tlk(["probes", "--warn-builds", "--out", out, "--api", api]);
            assert(alone.status === 2 && alone.stderr.includes("--warn-builds goes with --check"), `${alone.status} ${alone.stderr}`);
        }),
    },
    {
        name: "probes reports each probe's client and harness answers and their status",
        run: async () => withTemp(async (dir) => {
            const out = join(dir, "probes.json");
            const contexts = { "idle/none": true };
            writeFileSync(out, serializeProbes({ build: "1.60.1 (70009)", probes: {
                "chatTypeInfo.raidWarning": { contexts, result: { b: 0, g: 72, hasMetatable: true, r: 255, sticky: 0 } },
                "damageMeter.available": { contexts, result: { failureReason: "disabled", isAvailable: false } },
            } }));
            const run = tlk(["probes", "--out", out]);
            assert(run.status === 1, `a mismatch exits 1 (got ${run.status}): ${run.stdout}${run.stderr}`);
            assert(/chatTypeInfo\.raidWarning +anywhere +match\n {4}both +\{b=0 g=72 hasMetatable=true r=255 sticky=0\}/.test(run.stdout), run.stdout);
            assert(/damageMeter\.available +anywhere +mismatch\n {4}client +\{failureReason=disabled isAvailable=false\}.*\n {4}harness +\{failureReason="" isAvailable=true\}/.test(run.stdout), run.stdout);
            assert(/quest\.offer +quest offer open +pending/.test(run.stdout), run.stdout);
            assert(/bags\.firstItem +item in backpack +harness can't set up/.test(run.stdout), run.stdout);
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
