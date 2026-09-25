// One test job, run in a worker thread by tools/verbs/test.mjs. Posts { ready: true } once its
// setup is done (the parent's timeout starts then), then { results: [{ name, ok, pending, err }] }
// or { error }. A pending result passed nothing and failed nothing: the Lua test called
// pending(reason), and err holds the reason. Jobs:
//   { kind: "lua", file, filter }   a tests/*.test.lua file in a fresh Lua 5.1 VM with the harness
//   { kind: "mjs", file, filter }   a tests/*.test.mjs module exporting tests = [{ name, run }]
//   { kind: "fakes", filter }       every harness fake names a global (or member) the client dump has

import { readFileSync } from "node:fs";
import { basename } from "node:path";
import { pathToFileURL } from "node:url";
import { parentPort, workerData } from "node:worker_threads";
import { loadSnapshot, withHarness } from "./harness.mjs";

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
    -- Status per test: 1 passed, 0 failed, 2 pending.
    function __run(selected)
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
        return table.concat(lines, "\\n")
    end
`;

const matches = (filter, label, name) => !filter || `${label} > ${name}`.includes(filter);

// Undoes the prelude's escape(): \\ \t \r \n.
const unescape = (text) => text.replace(/\\(.)/g, (_, c) => ({ t: "\t", r: "\r", n: "\n" })[c] ?? c);

// Setup (a Lua VM, the snapshot, the harness, the test file) is done: the parent starts this
// job's timeout now, so a slow start under load can't eat a test's time.
const ready = () => parentPort.postMessage({ ready: true });

async function runLua(job, snapshot) {
    const label = basename(job.file);
    return withHarness(snapshot, async (lua) => {
        await lua.doString(PRELUDE);
        await lua.doString(readFileSync(job.file, "utf8"));
        const names = ((await lua.doString("return __names()")) ?? "").split("\n").filter(Boolean).map(unescape);
        const selected = names.filter((name) => matches(job.filter, label, name));
        if (selected.length === 0) return [];
        ready();
        lua.ctx.__selected = Object.fromEntries(selected.map((name) => [name, true]));
        const encoded = await lua.doString("return __run(__selected)");
        return encoded ? encoded.split("\n").map((line) => {
            const [status, name, err] = line.split("\t");
            return { ok: status !== "0", pending: status === "2", name: unescape(name), err: unescape(err ?? "") };
        }) : [];
    });
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

// A fake that isn't in the client dump models an API that doesn't exist.
async function runFakes(job, snapshot) {
    if (!matches(job.filter, "harness", FAKES_TEST)) return [];
    const { globals, members } = snapshot.raw;
    const memberSets = new Map(Object.entries(members).map(([name, keys]) => [name, new Set(keys)]));
    const names = await withHarness(snapshot, (lua) => {
        ready();
        return lua.doString("return Harness.FakeNames()");
    });
    const missing = names.split("\n").filter((name) => {
        const dot = name.indexOf(".");
        if (dot < 0) return !(name in globals);
        const table = name.slice(0, dot);
        const member = name.slice(dot + 1);
        if (!memberSets.has(table) && UNRECORDED_MEMBERS[table]?.[member]) return !(table in globals);
        return !memberSets.get(table)?.has(member);
    });
    return [{
        name: FAKES_TEST,
        ok: missing.length === 0,
        err: missing.length ? `not in the client dump: ${missing.join(", ")}` : "",
    }];
}

try {
    const job = workerData;
    let results;
    if (job.kind === "mjs") {
        results = await runModule(job);
    } else {
        const snapshot = loadSnapshot();
        results = job.kind === "fakes" ? await runFakes(job, snapshot) : await runLua(job, snapshot);
    }
    parentPort.postMessage({ results });
} catch (error) {
    parentPort.postMessage({ error: String(error?.stack ?? error) });
}
