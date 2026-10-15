// One test job, run in a worker thread by tools/verbs/test.mjs. Posts { ready: true } once its
// setup is done (the parent's timeout starts then), then { results: [{ name, ok, pending, err }] }
// or { error }. A pending result passed nothing and failed nothing: the Lua test called
// pending(reason), and err holds the reason. Jobs:
//   { kind: "lua", file, filter, coverage }
//                                   a tests/*.test.lua file in a fresh Lua 5.1 VM with the harness;
//                                   with coverage, the addons' files load instrumented and the
//                                   message also carries coverage: the statements its tests ran
//                                   in them (see tools/lib/coverage.mjs)
//   { kind: "mjs", file, filter }   a tests/*.test.mjs module exporting tests = [{ name, run }]
//   { kind: "fakes", filter }       every harness fake names a global (or member) the client dump has,
//                                   and every fake function is one an addon calls
// filter is a list of filters (see matches), or null for every test.

import { existsSync, readFileSync } from "node:fs";
import { basename, join } from "node:path";
import { pathToFileURL } from "node:url";
import { parentPort, workerData } from "node:worker_threads";
import { COVERAGE_LUA, createCoverage } from "./coverage.mjs";
import { loadSnapshot, withHarness } from "./harness.mjs";
import { parse, stringValue, walk } from "./lua-scope.mjs";
import { findAddons, readForbidden } from "./repo.mjs";

const PRELUDE = `
    local tests = {}
    function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end
    local function show(v) if type(v) == "string" then return string.format("%q", v) end return tostring(Reveal(v)) end
    function eq(actual, expected, message)
        actual = Reveal(actual)
        if actual ~= expected then
            error((message and (message .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual), 2)
        end
    end
    function truthy(value, message) if not Reveal(value) then error((message or "expected truthy") .. ", got " .. show(value), 2) end end
    function falsy(value, message) if Reveal(value) then error((message or "expected falsy") .. ", got " .. show(value), 2) end end
    function throws(fn, pattern, message)
        local ok, err = pcall(fn)
        if ok then error((message or "expected an error"), 2) end
        if pattern and not tostring(err):find(pattern) then error("error " .. show(err) .. " does not match " .. show(pattern), 2) end
    end
    -- pending(reason) ends a test that can't decide anything yet: it neither passes nor fails.
    local PendingMeta = {}
    function pending(reason) error(setmetatable({ reason = tostring(reason) }, PendingMeta), 0) end
    -- Names and errors cross to JS one per line, tab-separated: backslash, tab, CR and LF are escaped.
    local ESCAPES = { ["\\\\"] = "\\\\\\\\", ["\\t"] = "\\\\t", ["\\r"] = "\\\\r", ["\\n"] = "\\\\n" }
    local function escape(s) return (tostring(s):gsub("[\\\\\\t\\r\\n]", ESCAPES)) end
    function __names()
        local names = {}
        for i, t in ipairs(tests) do names[i] = escape(t.name) end
        return table.concat(names, "\\n")
    end
    -- Status per test: 1 passed, 0 failed, 2 pending. With __coverageOn, the addons' files the
    -- tests load are instrumented (COVERAGE_LUA, tools/lib/coverage.mjs).
    function __run(selected)
        if __coverageOn then __coverageStart() end
        local lines = {}
        for _, t in ipairs(tests) do
            if selected[t.name] then
                Harness.created = {}
                local ok, err = pcall(t.fn)
                local status = ok and "1" or "0"
                if not ok and getmetatable(err) == PendingMeta then
                    ok, status, err = true, "2", err.reason
                end
                if ok then
                    for _, h in ipairs(Harness.created) do
                        local problem = h:UnexpectedErrors()
                        if problem then
                            ok, status, err = false, "0", problem
                            break
                        end
                    end
                end
                local detail = status == "1" and "" or escape(err)
                lines[#lines + 1] = status .. "\\t" .. escape(t.name) .. "\\t" .. detail
            end
        end
        if __coverageOn then __coverageStop() end
        return table.concat(lines, "\\n")
    end
`;

// A job's filters are substrings of "<file> > <test name>"; a test matching any of them runs.
const matches = (filters, label, name) => !filters?.length || filters.some((filter) => `${label} > ${name}`.includes(filter));

// Undoes the prelude's escape(): \\ \t \r \n.
const unescape = (text) => text.replace(/\\(.)/g, (_, c) => ({ t: "\t", r: "\r", n: "\n" })[c] ?? c);

// Setup (a Lua VM, the snapshot, the harness, the test file) is done: the parent starts this
// job's timeout now, so a slow start under load can't eat a test's time.
const ready = () => parentPort.postMessage({ ready: true });

async function runLua(job, snapshot) {
    const label = basename(job.file);
    let coverage = "";
    const counter = job.coverage ? createCoverage() : null;
    const results = await withHarness(snapshot, async (lua) => {
        await lua.doString(PRELUDE);
        if (counter) {
            lua.ctx.__instrument = (source, chunkName) => counter.instrument(source, chunkName);
            await lua.doString(COVERAGE_LUA);
        }
        await lua.doString(readFileSync(job.file, "utf8"));
        const names = ((await lua.doString("return __names()")) ?? "").split("\n").filter(Boolean).map(unescape);
        const selected = names.filter((name) => matches(job.filter, label, name));
        if (selected.length === 0) return [];
        ready();
        lua.ctx.__selected = Object.fromEntries(selected.map((name) => [name, true]));
        lua.ctx.__coverageOn = job.coverage === true;
        const encoded = await lua.doString("return __run(__selected)");
        if (counter) coverage = counter.hitsText(await lua.doString("return __coverageHits()"));
        return encoded ? encoded.split("\n").map((line) => {
            const [status, name, err] = line.split("\t");
            return { ok: status !== "0", pending: status === "2", name: unescape(name), err: unescape(err ?? "") };
        }) : [];
    });
    return { results, coverage };
}

async function runModule(job) {
    const label = basename(job.file);
    const { tests } = await import(pathToFileURL(job.file).href);
    ready();
    const results = [];
    for (const test of tests.filter((t) => matches(job.filter, label, t.name))) {
        try {
            await test.run();
            results.push({ name: test.name, ok: true, err: "" });
        } catch (error) {
            results.push({ name: test.name, ok: false, err: String(error?.message ?? error) });
        }
    }
    return results;
}

const FAKES_TEST = "every fake names a real client global";

// Members of client tables the dump records no members for, each with the Blizzard source that
// defines it. Only these pass without a recorded member list; any other member still fails.
// ChatTypeInfo has a metatable in game and fills its entries on first read, so a dump (which
// walks keys) finds none; ChatTypeInfo.RAID_WARNING was read in game.
const UNRECORDED_MEMBERS = {
    ChatTypeInfo: { RAID_WARNING: "Blizzard_ChatFrameBase/Shared/ChatTypeInfoConstants.lua" },
};

const CALLED_TEST = "every fake function is called by an addon";

// Fake functions no addon names, each with why the harness has it anyway: Blizzard's UI code that
// the harness runs on the addons' behalf calls them, or Lua the client exposes.
const UNCALLED_FAKES = {};

// Every name the addons' code mentions: identifiers, and the identifier-shaped words in string
// literals (a probe can name an API by string). Comments don't count.
function addonIdentifiers() {
    const names = new Set();
    for (const addon of findAddons()) {
        for (const file of addon.files.filter((f) => f.endsWith(".lua"))) {
            const path = join(addon.dir, file);
            if (!existsSync(path)) continue;
            walk(parse(readFileSync(path, "utf8")), (node) => {
                if (node.type === "Identifier") names.add(node.name);
                const text = stringValue(node);
                if (text) for (const word of text.match(/[A-Za-z_][A-Za-z0-9_]*/g) ?? []) names.add(word);
            });
        }
    }
    return names;
}

// A fake that isn't in the client dump models an API that doesn't exist; a fake function no addon
// calls (by its last dotted segment) models nothing the addons need.
async function runFakes(job, snapshot) {
    const checkNames = matches(job.filter, "harness", FAKES_TEST);
    const checkCalls = matches(job.filter, "harness", CALLED_TEST);
    if (!checkNames && !checkCalls) return [];
    const { globals, members } = snapshot.raw;
    const memberSets = new Map(Object.entries(members).map(([name, keys]) => [name, new Set(keys)]));
    const [names, functions] = await withHarness(snapshot, async (lua) => {
        ready();
        return [await lua.doString("return Harness.FakeNames()"), await lua.doString("return Harness.FakeFunctionNames()")];
    });
    const results = [];
    if (checkNames) {
        const missing = names.split("\n").filter((name) => {
            const dot = name.indexOf(".");
            if (dot < 0) return !(name in globals);
            const table = name.slice(0, dot);
            const member = name.slice(dot + 1);
            if (!memberSets.has(table) && UNRECORDED_MEMBERS[table]?.[member]) return !(table in globals);
            return !memberSets.get(table)?.has(member);
        });
        results.push({
            name: FAKES_TEST,
            ok: missing.length === 0,
            err: missing.length ? `not in the client dump: ${missing.join(", ")}` : "",
        });
    }
    if (checkCalls) {
        const called = addonIdentifiers();
        const forbidden = readForbidden();
        const uncalled = functions.split("\n").filter(Boolean).filter((name) =>
            !called.has(name.split(".").pop()) && !(name in forbidden) && !(name in UNCALLED_FAKES));
        results.push({
            name: CALLED_TEST,
            ok: uncalled.length === 0,
            err: uncalled.length ? `no addon calls these fakes (delete them, with their tests): ${uncalled.join(", ")}` : "",
        });
    }
    return results;
}

try {
    const job = workerData;
    let outcome;
    if (job.kind === "mjs") {
        outcome = { results: await runModule(job) };
    } else {
        const snapshot = loadSnapshot();
        outcome = job.kind === "fakes" ? { results: await runFakes(job, snapshot) } : await runLua(job, snapshot);
    }
    parentPort.postMessage(outcome);
} catch (error) {
    parentPort.postMessage({ error: String(error?.stack ?? error) });
}
