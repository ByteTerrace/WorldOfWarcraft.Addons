// Coverage's own tests (tools/lib/coverage.mjs): which statements count, instrumented code that
// behaves as the original, and the test runner's --coverage report.

import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { COVERAGE_LUA, coverageReport, createCoverage, instrument, mergeHits } from "../tools/lib/coverage.mjs";
import { createLua } from "../tools/lib/lua.mjs";
import { FIXTURES, assert, tlk, withTemp } from "../tools/lib/test-support.mjs";

// Runs source as the Fixture addon's File.lua, instrumented as a coverage job loads it, then
// call (Lua) against what it returned: { value, error, report } with the file's coverage report.
async function runCovered(dir, source, call = "") {
    writeFileSync(join(dir, "File.lua"), source);
    const counter = createCoverage();
    const lua = await createLua();
    try {
        lua.ctx.__instrument = (text, chunkName) => counter.instrument(text, chunkName);
        await lua.doString(COVERAGE_LUA);
        lua.ctx.__source = source;
        const outcome = await lua.doString(`
            __coverageStart()
            local chunk = assert(loadstring(__source, "@Fixture/File.lua"))
            __coverageStop()
            local ok, value = pcall(function()
                local file = chunk("Fixture", {})
                ${call}
            end)
            return (ok and "ok\\t" or "error\\t") .. tostring(value)
        `);
        const [status, value] = outcome.split("\t");
        const hits = mergeHits([counter.hitsText(await lua.doString("return __coverageHits()"))]);
        const [report] = coverageReport(hits, [{ name: "Fixture", dir, files: ["File.lua"] }]);
        return { value: status === "ok" ? value : undefined, error: status === "error" ? value : undefined, report };
    } finally {
        lua.global.close();
    }
}

export const tests = [
    {
        // A nested function's statements count for it, not for the code around it; `local b`
        // compiles to nothing, so it's no statement; an if counts by its condition.
        name: "coverage counts each statement in the function that holds it",
        run: async () => withTemp(async (dir) => {
            writeFileSync(join(dir, "File.lua"), [
                "local a = 1", "local b", "local function f(x)", "    if x then", "        return 1", "    end",
                "    return 2", "end", "local t = { g = function() return 3 end }", "f(a)", "",
            ].join("\n"));
            const ran = ["@Fixture/File.lua\t0\t1:0,3:0,9:0,10:0", "@Fixture/File.lua\t3\t4:7,7:4"];
            const [file] = coverageReport(mergeHits(ran), [{ name: "Fixture", dir, files: ["File.lua"] }]);
            assert(file.file === "Fixture/File.lua" && file.total === 8, `statements: ${JSON.stringify(file)}`);
            assert(file.covered === 6 && file.missed.join(" ") === "5 9", `return 1 and g's body missed: ${JSON.stringify(file)}`);
            const none = coverageReport(new Map(), [{ name: "Fixture", dir, files: ["File.lua"] }])[0];
            assert(none.covered === 0 && none.missed.join(" ") === "1-10", `a run of misses: ${JSON.stringify(none)}`);
        }),
    },
    {
        // The if's condition ran on line 2, but its return didn't: a line hook saw one line run.
        name: "coverage tells apart statements that share a line",
        run: async () => withTemp(async (dir) => {
            const source = ["local function f(ready)", "    if not ready then return end", "    return 1", "end", "return f(true)", ""].join("\n");
            const { value, report } = await runCovered(dir, source, "return file");
            assert(value === "1", `the file still returns f's value: ${value}`);
            assert(report.total === 5 && report.covered === 4 && report.missed.join(" ") === "2", JSON.stringify(report));
        }),
    },
    {
        name: "instrumented code keeps its values, line numbers and chunk name",
        run: async () => withTemp(async (dir) => {
            const source = [
                "local addonName, ns = ...",
                "local function pick(n)",
                "    if n == 1 then return \"one\"",
                "    elseif select(2, false, n == 2) then return \"two\"",
                "    elseif (n) == 3 then return \"three\" end",
                "    local i = 0",
                "    repeat i = i + 1 until (i >= n)",
                "    while i > 0 do i = i - 1 end",
                "    return i",
                "end",
                "(ns).Pick = pick;",
                "(ns).Fail = function() error(\"failed here\") end",
                "return { name = addonName, pick = pick, fail = ns.Fail }",
                "",
            ].join("\n");
            const { value, report } = await runCovered(dir, source,
                "return table.concat({ file.name, file.pick(1), file.pick(2), file.pick(3), file.pick(5) }, \",\")");
            assert(value === "Fixture,one,two,three,0", `values: ${value}`);
            assert(report.missed.join(" ") === "12" && report.covered === report.total - 1, `all but fail's body: ${JSON.stringify(report)}`);
            const failed = await runCovered(dir, source, "file.fail()");
            assert(/^@?Fixture\/File\.lua:12: failed here$/.test(failed.error ?? ""), `error: ${failed.error}`);
            assert(!failed.report.missed.includes("12"), `fail's body ran: ${JSON.stringify(failed.report)}`);
            assert(instrument(source).text.split("\n").length === source.split("\n").length + 1, "one line added, after the last");
            assert(instrument("local x = = 1") === null, "a source that doesn't parse loads as it is");
        }),
    },
    {
        name: "the test runner's --coverage reports the statements the tests reached",
        run: async () => {
            const run = tlk(["test", "--dir", join(FIXTURES, "runner-coverage"), "--coverage"]);
            assert(run.status === 0 && /\b3 passed, 0 failed/.test(run.stdout), run.stdout);
            assert(/^coverage: \d+ of \d+ statements \(\d+\.\d%\)$/m.test(run.stdout), run.stdout);
            // Loading ran Core's top levels but not its functions; nothing ran Krew.
            assert(/^ {2}ByteTerrace_Core\/State\.lua (?!0\.0%)\d+\.\d% \(\d+ missed\): /m.test(run.stdout), run.stdout);
            assert(/^ {2}TheLanKrewToolKit\/Krew\.lua 0\.0% /m.test(run.stdout), run.stdout);
            const plain = tlk(["test", "--dir", join(FIXTURES, "runner-coverage")]);
            assert(!plain.stdout.includes("coverage:"), plain.stdout);
        },
    },
];
