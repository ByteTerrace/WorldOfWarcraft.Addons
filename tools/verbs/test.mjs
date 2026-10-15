// Behavioral tests: tests/*.test.lua run in real Lua 5.1 against the fake client in
// tests/harness, and tests/*.test.mjs test the tooling itself. Each test file runs in its own
// worker thread (and Lua VM) with a timeout, so a hang fails that file instead of the run. The
// timeout counts from when the worker finishes its setup (Lua VM, snapshot, harness, test file),
// which has its own, generous limit (SETUP_MS), so load on the machine can't fail a quick test.
//
//   node tools/tlk.mjs test [filters... | test files...] [--timeout <seconds>] [--dir <folder>]
//
// Test file paths (tests/krew.test.lua) run exactly those files, and one that doesn't exist
// fails the run. Otherwise each filter is a substring of "<file> > <test name>"; the tests
// matching any of them run. Filters or files that match nothing fail the run, and so does a
// --timeout that isn't a positive number of seconds. Besides the files, the run checks that every harness fake
// names a global the client dump has ("harness > every fake names a real client global").
//
// A Lua test file calls test(name, fn). Assertions: eq(actual, expected, message),
// truthy(value, message), falsy(value, message), throws(fn, pattern, message). A test fails when
// a harness it created saw errors it didn't declare with h:ExpectErrors(count | patterns...).
// pending(reason) ends a test that can't decide anything yet (a probe with no observed result):
// it prints "PEND <file> > <name>: <reason>", counts as pending, and doesn't fail the run.

import { availableParallelism } from "node:os";
import { readdirSync } from "node:fs";
import { join, resolve } from "node:path";
import { Worker } from "node:worker_threads";
import { repoRoot } from "../lib/repo.mjs";

export const options = {
    timeout: { type: "string", default: "30" }, // seconds per test file
    dir: { type: "string" },                    // test folder (default tests/); the runner's own tests use a fixture
};

const WORKER = new URL("../lib/test-worker.mjs", import.meta.url);
const SETUP_MS = 120000;
const FAKES_JOB = "harness";

function runJob(job, timeoutMs) {
    return new Promise((resolve) => {
        const worker = new Worker(WORKER, { workerData: job });
        let settled = false;
        const finish = (outcome) => {
            if (settled) return;
            settled = true;
            clearTimeout(timer);
            worker.terminate();
            resolve(outcome);
        };
        let timer = setTimeout(() => finish({ error: `setup timed out after ${SETUP_MS / 1000}s` }), SETUP_MS);
        worker.on("message", (message) => {
            if (!message.ready) return finish(message);
            clearTimeout(timer);
            timer = setTimeout(() => finish({ error: `timed out after ${timeoutMs / 1000}s` }), timeoutMs);
        });
        worker.once("error", (error) => finish({ error: String(error?.stack ?? error) }));
        worker.once("exit", (code) => finish({ error: `worker exited with code ${code} before reporting` }));
    });
}

// A test name as printed: quoted when it holds control characters, so the output stays one line.
const display = (name) => (/[\x00-\x1f]/.test(name) ? JSON.stringify(name) : name);

export async function run(values, positionals) {
    const isFile = (arg) => /\.test\.(lua|mjs)$/.test(arg);
    const only = new Set(positionals.filter(isFile).map((arg) => arg.replaceAll("\\", "/").split("/").pop()));
    const filters = positionals.filter((arg) => !isFile(arg));
    const filter = filters.length ? filters : null;
    const timeoutMs = Number(values.timeout) * 1000;
    if (!(timeoutMs > 0)) {
        console.error(`--timeout must be a positive number of seconds (got "${values.timeout}")`);
        return 2;
    }
    const dir = values.dir ? resolve(values.dir) : join(repoRoot, "tests");
    const present = readdirSync(dir).filter((f) => f.endsWith(".test.lua") || f.endsWith(".test.mjs"));
    const missing = [...only].filter((file) => !present.includes(file));
    if (missing.length) {
        console.log(`No test file named ${missing.join(", ")}.`);
        return 1;
    }
    const files = present.filter((f) => only.size === 0 || only.has(f)).sort();
    const jobs = [...(only.size === 0 ? [{ kind: "fakes", label: FAKES_JOB, filter }] : []), ...files.map((file) => ({
        kind: file.endsWith(".mjs") ? "mjs" : "lua", label: file, file: join(dir, file), filter,
    }))];

    const outcomes = new Array(jobs.length);
    let next = 0;
    const lanes = Array.from({ length: Math.min(jobs.length, Math.max(1, availableParallelism() - 1)) }, async () => {
        while (next < jobs.length) {
            const index = next++;
            outcomes[index] = await runJob(jobs[index], timeoutMs);
        }
    });
    await Promise.all(lanes);

    let passed = 0;
    let failed = 0;
    let pending = 0;
    let matched = 0;
    jobs.forEach((job, i) => {
        const outcome = outcomes[i];
        if (outcome.error) {
            failed++;
            console.log(`FAIL ${job.label}: ${outcome.error}`);
            return;
        }
        for (const result of outcome.results) {
            matched++;
            if (result.pending) {
                pending++;
                console.log(`PEND ${job.label} > ${display(result.name)}: ${result.err.replaceAll("\n", " ")}`);
            } else if (result.ok) {
                passed++;
            } else {
                failed++;
                console.log(`FAIL ${job.label} > ${display(result.name)}\n     ${result.err.replaceAll("\n", "\n     ")}`);
            }
        }
    });
    if ((filter || only.size > 0) && matched === 0) {
        console.log(`No test matches "${filter ? filters.join("\" or \"") : [...only].join(" ")}".`);
        return 1;
    }
    console.log(`${passed} passed, ${failed} failed${pending ? `, ${pending} pending` : ""}`);
    return failed ? 1 : 0;
}
