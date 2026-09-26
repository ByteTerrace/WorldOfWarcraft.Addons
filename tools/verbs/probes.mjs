// Calibration probes (ByteTerrace_DevTools' probe files, Probes.lua and the files it names): what
// the real client answered, kept in tools/api/probes.json for tests/probes.test.lua (format:
// tools/lib/probes.mjs).
//
//   node tools/tlk.mjs probes                     a report: each probe, what it needs, the client's
//                                                 and the harness's answers, and whether they match;
//                                                 then what's left to do in game
//   node tools/tlk.mjs probes --import [file]     merges the records `/btdev probe` saved into the
//                                                 snapshot. The file defaults to the installed
//                                                 client's WTF/Account/<account>/SavedVariables/
//                                                 ByteTerrace_DevTools.lua when one account has it.
//   node tools/tlk.mjs probes --check             exits 1 when the snapshot is stale: a record from
//                                                 another client build than the API snapshot's
//                                                 (tools/api/forever.json), for a probe
//                                                 ByteTerrace_DevTools no longer defines, or made
//                                                 by another version of its probe.
//
// An import replaces each imported probe's record, keeps the others, and drops records of probes
// that no longer exist or were made by another version of their probe (Probes.lua's header). A record that isn't { build, context = { combat, restrictions }, result }
// is refused.

import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { loadSnapshot, withHarness } from "../lib/harness.mjs";
import {
    ENCODE_JSON, PROBES_PATH, buildNumber, buildOf, isCurrent, readDefinitions, readProbes, readRecords, serializeProbes, stableJson,
} from "../lib/probes.mjs";
import { repoRoot } from "../lib/repo.mjs";
import { DEFAULT_WOW_ROOT, findForeverInstall } from "../lib/wow.mjs";

export const options = {
    import: { type: "boolean", default: false },
    check: { type: "boolean", default: false },
    out: { type: "string", default: PROBES_PATH },
    api: { type: "string", default: join(repoRoot, "tools", "api", "forever.json") },
    flavor: { type: "string" },
    "wow-root": { type: "string", default: DEFAULT_WOW_ROOT },
};

const SAVED_VARIABLES = "ByteTerrace_DevTools.lua";

// The installed client's DevTools SavedVariables, when exactly one account has them.
function defaultRecordsFile(values) {
    const flavor = values.flavor ?? findForeverInstall(values["wow-root"]).flavor;
    const accounts = join(values["wow-root"], flavor, "WTF", "Account");
    const found = (existsSync(accounts) ? readdirSync(accounts) : [])
        .map((account) => join(accounts, account, "SavedVariables", SAVED_VARIABLES))
        .filter((file) => existsSync(file));
    if (found.length === 1) return found[0];
    if (found.length === 0) {
        throw new Error(`no ${SAVED_VARIABLES} under ${accounts}; in game type /btdev probe, then /reload`);
    }
    throw new Error(`${found.length} accounts have ${SAVED_VARIABLES}; pass the one to import:\n  ${found.join("\n  ")}`);
}

// Why a record can't be imported, or null.
function recordProblem(record) {
    if (!record || typeof record !== "object") return "isn't a table";
    if (!buildOf(record.build)) return "has no build";
    const context = record.context;
    if (!context || typeof context.combat !== "boolean" || typeof context.restrictions !== "string") return "has no context";
    if (!record.result || typeof record.result !== "object") return "has no result";
    if (record.version !== undefined && !(Number.isInteger(record.version) && record.version >= 2)) return "has a bad version";
    return null;
}

function apiBuild(apiPath) {
    try {
        return buildOf(JSON.parse(readFileSync(apiPath, "utf8")).source?.globals);
    } catch {
        return null;
    }
}

// The closing to-do: how many probes still need a result in game, grouped by what they need.
function printToDo(definitions, probes) {
    const groups = new Map();
    for (const definition of definitions) {
        if (isCurrent(definition, probes[definition.name])) continue;
        groups.set(definition.labels, [...(groups.get(definition.labels) ?? []), definition.name]);
    }
    const pending = [...groups.values()].reduce((sum, names) => sum + names.length, 0);
    if (!pending) {
        console.log(`Every probe (${definitions.length}) has an observed result.`);
        return;
    }
    const setups = [...groups.keys()].sort().map((labels) => `${labels} (${groups.get(labels).length})`).join(", ");
    console.log(`To do in game: ${pending} of ${definitions.length} probes need a result. Type /btdev probe in each `
        + `situation: ${setups}; /btdev probe list says what each one means. Then /reload and tlk probes --import.`);
}

// A record value, compact: { secret = true, type = "string" } as secret(string), tables as k=v.
function compact(value) {
    if (value === undefined) return "-";
    if (value && typeof value === "object") {
        if (value.secret === true && typeof value.type === "string" && Object.keys(value).length === 2) return `secret(${value.type})`;
        return "{" + Object.keys(value).sort().map((key) => `${key}=${compact(value[key])}`).join(" ") + "}";
    }
    return typeof value === "string" && /^[^\s={}"]+$/.test(value) ? value : JSON.stringify(value);
}

// Every probe run in the harness (Harness.RunProbe): { [name]: { gap, problem, context, result } }.
async function harnessAnswers(definitions, probesPath) {
    return withHarness(loadSnapshot(), async (lua) => {
        await lua.doString(ENCODE_JSON);
        lua.ctx.__names = definitions.map((definition) => definition.name).join("\n");
        const encoded = await lua.doString(`
            local out = {}
            for name in __names:gmatch("[^\\n]+") do
                local run = Harness.RunProbe(name)
                local record = run.record
                out[name] = {
                    gap = run.gap, problem = run.problem,
                    context = record and record.context, result = record and record.result,
                }
            end
            return __encodeJson(out, "report")
        `);
        if (encoded.startsWith("!")) throw new Error(encoded.slice(1));
        return JSON.parse(encoded);
    }, probesPath);
}

// The report: a table of probe, needs and status, each followed by the client's and the harness's
// answers (one line when they match).
async function report(values, definitions) {
    const { probes } = readProbes(values.out);
    const answers = await harnessAnswers(definitions, values.out);
    const rows = definitions.map((definition) => {
        const observed = isCurrent(definition, probes[definition.name]) ? probes[definition.name] : undefined;
        const answer = answers[definition.name];
        const client = observed && { context: observed.context, result: observed.result };
        const harness = answer.result && { context: answer.context, result: answer.result };
        let status;
        if (answer.gap) status = "harness can't set up";
        else if (answer.problem) status = "harness error";
        else if (!observed) status = "pending";
        else status = stableJson(client) === stableJson(harness) ? "match" : "mismatch";
        return { definition, observed, answer, client, harness, status };
    });
    const nameWidth = Math.max(5, ...definitions.map((definition) => definition.name.length));
    const needsWidth = Math.max(5, ...definitions.map((definition) => definition.labels.length));
    const line = (a, b, c) => `${a.padEnd(nameWidth)}  ${b.padEnd(needsWidth)}  ${c}`;
    console.log(line("Probe", "Needs", "Status"));
    for (const row of rows) {
        console.log(line(row.definition.name, row.definition.labels, row.status));
        const context = (record) => (record.context.combat ? "in combat" : "idle") + (record.context.restrictions === "none" ? "" : `, ${record.context.restrictions}`);
        const show = (label, record) => console.log(`    ${label.padEnd(8)}${compact(record.result)}  [${context(record)}${record.build ? `, ${record.build}` : ""}]`);
        if (row.status === "match") show("both", { ...row.client, build: row.observed.build });
        else {
            if (row.client) show("client", { ...row.client, build: row.observed.build });
            if (row.harness) show("harness", row.harness);
        }
        if (row.answer.gap) console.log(`    ${"harness".padEnd(8)}${row.answer.gap}`);
        if (row.answer.problem) console.log(`    ${"harness".padEnd(8)}${row.answer.problem.replaceAll("\n", " ")}`);
    }
    const counts = {};
    for (const row of rows) counts[row.status] = (counts[row.status] ?? 0) + 1;
    console.log(Object.entries(counts).map(([status, count]) => `${count} ${status}`).join(", ") + ".");
    printToDo(definitions, probes);
    return rows.some((row) => row.status === "mismatch" || row.status === "harness error") ? 1 : 0;
}

async function importRecords(values, positionals, definitions) {
    const file = positionals[0] ?? defaultRecordsFile(values);
    const imported = await readRecords(file);
    const defined = new Map(definitions.map((definition) => [definition.name, definition]));
    const snapshot = readProbes(values.out);
    const versionNote = (name, record) => `made by version ${record.version ?? 1} of the probe, which is now version ${defined.get(name).version}`;
    const counts = { new: 0, changed: 0, unchanged: 0 };
    for (const [name, record] of Object.entries(imported)) {
        if (!defined.has(name)) {
            console.log(`Skipped ${name}: ByteTerrace_DevTools no longer defines it`);
            continue;
        }
        const problem = recordProblem(record);
        if (problem) {
            console.error(`Refused ${name}: the record ${problem}`);
            continue;
        }
        if (!isCurrent(defined.get(name), record)) {
            console.log(`Skipped ${name}: the record was ${versionNote(name, record)}; re-run it in game`);
            continue;
        }
        const clean = { build: record.build, context: { combat: record.context.combat, restrictions: record.context.restrictions }, result: record.result };
        if (record.version !== undefined) clean.version = record.version;
        const previous = snapshot.probes[name];
        if (previous && buildNumber(previous.build) > buildNumber(record.build)) {
            console.log(`Kept ${name}: the file's record is from ${record.build}, older than ${previous.build}`);
            continue;
        }
        counts[!previous ? "new" : stableJson(previous) === stableJson(clean) ? "unchanged" : "changed"]++;
        snapshot.probes[name] = clean;
    }
    for (const name of Object.keys(snapshot.probes)) {
        if (!defined.has(name)) {
            console.log(`Dropped ${name}: ByteTerrace_DevTools no longer defines it`);
            delete snapshot.probes[name];
        } else if (!isCurrent(defined.get(name), snapshot.probes[name])) {
            console.log(`Dropped ${name}: the record was ${versionNote(name, snapshot.probes[name])}`);
            delete snapshot.probes[name];
        }
    }
    const builds = [...new Set(Object.values(snapshot.probes).map((record) => record.build))].sort((a, b) => buildNumber(a) - buildNumber(b));
    if (builds.length > 1) {
        console.warn(`probes: warning: records come from ${builds.join(", ")}; re-run /btdev probe on ${builds.at(-1)} for the older ones`);
    }
    snapshot.build = builds.at(-1) ?? "";
    writeFileSync(values.out, serializeProbes(snapshot));
    console.log(`Imported ${file}: ${counts.new} new, ${counts.changed} changed, ${counts.unchanged} unchanged. Wrote ${values.out}.`);
    printToDo(definitions, snapshot.probes);
    return 0;
}

function checkRecords(values, definitions) {
    const { probes } = readProbes(values.out);
    const defined = new Map(definitions.map((definition) => [definition.name, definition]));
    const build = apiBuild(values.api);
    const stale = [];
    for (const [name, record] of Object.entries(probes)) {
        if (!defined.has(name)) stale.push(`${name}: ByteTerrace_DevTools no longer defines it`);
        else if (!isCurrent(defined.get(name), record)) stale.push(`${name}: made by version ${record.version ?? 1}, the probe is version ${defined.get(name).version}`);
        else if (build && record.build !== build) stale.push(`${name}: recorded on ${record.build}, the API snapshot is ${build}`);
    }
    if (!build) console.warn("probes: warning: the API snapshot names no client build; builds weren't compared");
    printToDo(definitions, probes);
    if (stale.length) {
        console.error(`Stale records (re-run /btdev probe, then tlk probes --import):\n  ${stale.sort().join("\n  ")}`);
        return 1;
    }
    return 0;
}

export async function run(values, positionals) {
    const definitions = await readDefinitions();
    try {
        if (values.import) return await importRecords(values, positionals, definitions);
    } catch (error) {
        console.error(`probes: ${error.message}`);
        return 1;
    }
    if (values.check) return checkRecords(values, definitions);
    return report(values, definitions);
}
