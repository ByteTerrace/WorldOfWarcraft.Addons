// Behavioral tests: tests/*.test.lua run in real Lua 5.1 against the fake client in
// tests/harness. Each test file gets a fresh VM; each test builds its own Harness.
//
// A test file calls test(name, fn). Assertions: eq(actual, expected, message),
// truthy(value, message), falsy(value, message), throws(fn, pattern, message).

import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { findAddons, repoRoot } from "../lib/repo.mjs";
import { createLua } from "../lib/lua.mjs";

export const options = {};

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
    function __run()
        local lines = {}
        for _, t in ipairs(tests) do
            Harness.created = {}
            local ok, err = pcall(t.fn)
            if ok then
                for _, h in ipairs(Harness.created) do
                    if #h.errors ~= h.expectedErrors then
                        ok, err = false, "reported errors (expected " .. h.expectedErrors .. "): " .. table.concat(h.errors, " | ")
                    end
                end
            end
            local detail = ok and "" or (tostring(err):gsub("[\\t\\n]", " "))
            lines[#lines + 1] = (ok and "1" or "0") .. "\\t" .. t.name .. "\\t" .. detail
        end
        return table.concat(lines, "\\n")
    end
`;

function loadSnapshot() {
    // Lua sees name -> number of secret flags (0 = never secret); arrays don't cross into Lua 1-based.
    const snapshot = JSON.parse(readFileSync(join(repoRoot, "tools", "api", "forever.json"), "utf8"));
    const counts = (table) => Object.fromEntries(Object.entries(table).map(([name, flags]) => [name, flags.length]));
    return {
        functions: counts(snapshot.functions),
        events: counts(snapshot.events),
        methods: Object.fromEntries(Object.entries(snapshot.methods).map(([api, methods]) => [api, counts(methods)])),
    };
}

function loadAddons() {
    const addons = {};
    for (const addon of findAddons()) {
        addons[addon.name] = {
            files: addon.files.filter((f) => f.endsWith(".lua")),
            sources: addon.files.filter((f) => f.endsWith(".lua")).map((f) => readFileSync(join(addon.dir, f), "utf8")),
            metadata: addon.metadata,
            savedVariables: (addon.metadata.SavedVariables ?? "").split(",").map((s) => s.trim()).filter(Boolean),
        };
    }
    return addons;
}

async function runFile(file, snapshot, addons) {
    const lua = await createLua();
    try {
        lua.ctx.__snapshot = snapshot;
        lua.ctx.__addons = addons;
        for (const harnessFile of ["wow.lua", "env.lua"]) {
            await lua.doString(readFileSync(join(repoRoot, "tests", "harness", harnessFile), "utf8"));
        }
        await lua.doString(PRELUDE);
        await lua.doString(readFileSync(file, "utf8"));
        const encoded = await lua.doString("return __run()");
        return encoded ? encoded.split("\n").map((line) => {
            const [ok, name, err] = line.split("\t");
            return { ok: ok === "1", name, err };
        }) : [];
    } finally {
        lua.global.close();
    }
}

// tests/*.test.mjs export `tests = [{ name, run }]` for tooling (e.g. the check gate).
async function runModule(file) {
    const { tests } = await import(pathToFileURL(file).href);
    const results = [];
    for (const test of tests) {
        try {
            await test.run();
            results.push({ name: test.name, ok: true, err: "" });
        } catch (error) {
            results.push({ name: test.name, ok: false, err: String(error?.message ?? error) });
        }
    }
    return results;
}

export async function run(_values, positionals) {
    const filter = positionals[0];
    const dir = join(repoRoot, "tests");
    const files = readdirSync(dir).filter((f) => f.endsWith(".test.lua") || f.endsWith(".test.mjs")).sort();
    const snapshot = loadSnapshot();
    const addons = loadAddons();
    let passed = 0;
    let failed = 0;
    for (const file of files) {
        let results;
        try {
            results = file.endsWith(".mjs") ? await runModule(join(dir, file)) : await runFile(join(dir, file), snapshot, addons);
        } catch (error) {
            console.log(`FAIL ${file}: ${error}`);
            failed++;
            continue;
        }
        for (const result of results) {
            const name = `${file} > ${result.name}`;
            if (filter && !name.includes(filter)) continue;
            if (result.ok) {
                passed++;
            } else {
                failed++;
                console.log(`FAIL ${name}\n     ${result.err}`);
            }
        }
    }
    console.log(`${passed} passed, ${failed} failed`);
    return failed ? 1 : 0;
}
