// Behavioral tests: tests/*.test.lua run in real Lua 5.1 against the fake client in
// tests/harness, and tests/*.test.mjs test the tooling itself. Each test file runs in its own
// worker thread (and Lua VM) with a timeout, so a hang fails that file instead of the run; files
// start longest first, by how long each took last time (orderJobs). The
// timeout counts from when the worker finishes its setup (Lua VM, snapshot, harness, test file),
// which has its own, generous limit (SETUP_MS), so load on the machine can't fail a quick test.
//
//   node tools/tlk.mjs test [filters... | test files...] [--timeout <seconds>] [--dir <folder>] [--coverage]
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
//
// --coverage also reports which statements of the addons' files the Lua tests that ran reached
// (tools/lib/coverage.mjs says what counts): the total, then each file with statements none of
// them reached, and those statements' lines. It's a report, not a gate: the run's status is the
// tests'. It instruments the addons' files as they load, which slows the Lua tests a little.

import { availableParallelism } from "node:os";
import { mkdirSync, readdirSync, readFileSync, renameSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { Worker } from "node:worker_threads";
import { coverageReport, mergeHits } from "../lib/coverage.mjs";
import { findAddons, repoRoot, toPosix } from "../lib/repo.mjs";

export const options = {
    timeout: { type: "string", default: "30" }, // seconds per test file
    dir: { type: "string" },                    // test folder (default tests/); the runner's own tests use a fixture
    coverage: { type: "boolean" },              // report the addon statements the tests reached
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

// How long each job took the last time it ran whole, { [jobKey]: ms }, in npm's cache folder
// (node_modules/.cache, never committed): the runner starts the longest first.
const DURATIONS = join(repoRoot, "node_modules", ".cache", "tlk", "test-durations.json");

const jobKey = (job) => (job.file ? toPosix(relative(repoRoot, job.file)) : job.label);

function readDurations() {
    try {
        return JSON.parse(readFileSync(DURATIONS, "utf8"));
    } catch {
        return {};
    }
}

// Merges into the file through a rename, so runs finishing together (the runner's own tests
// start runs of their own) never leave it half written. Ordering is all it's for: a failed
// write is ignored.
function writeDurations(update) {
    try {
        mkdirSync(dirname(DURATIONS), { recursive: true });
        const temporary = `${DURATIONS}.${process.pid}`;
        writeFileSync(temporary, JSON.stringify({ ...readDurations(), ...update }, null, 1));
        renameSync(temporary, DURATIONS);
    } catch {
        // The next run orders by size instead.
    }
}

// The order to start jobs in ([{ duration, size }] -> indexes): those never timed first, largest
// file first (a new test file is likely the one being worked on, and its cost is unknown), then
// the rest longest first, so the slowest file doesn't start last and hold up the run. File size
// alone predicts badly: a small .test.mjs that runs the CLI outlasts most Lua files.
export function orderJobs(estimates) {
    const unknown = (e) => e.duration === undefined;
    return estimates.map((_, i) => i).sort((a, b) => {
        const x = estimates[a];
        const y = estimates[b];
        if (unknown(x) !== unknown(y)) return unknown(x) ? -1 : 1;
        return unknown(x) ? y.size - x.size : y.duration - x.duration;
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
        kind: file.endsWith(".mjs") ? "mjs" : "lua", label: file, file: join(dir, file), filter, coverage: values.coverage === true,
    }))];

    const outcomes = new Array(jobs.length);
    const known = readDurations();
    const keys = jobs.map(jobKey);
    const order = orderJobs(jobs.map((job, i) => ({ duration: known[keys[i]], size: job.file ? statSync(job.file).size : 0 })));
    const elapsed = {};
    let next = 0;
    const lanes = Array.from({ length: Math.min(jobs.length, Math.max(1, availableParallelism() - 1)) }, async () => {
        while (next < order.length) {
            const index = order[next++];
            const start = performance.now();
            outcomes[index] = await runJob(jobs[index], timeoutMs);
            elapsed[keys[index]] = Math.round(performance.now() - start);
        }
    });
    await Promise.all(lanes);
    // A filtered run times part of each file, so only whole files are recorded.
    if (!filter) writeDurations(elapsed);

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
    if (values.coverage) printCoverage(outcomes.map((outcome) => outcome.coverage ?? ""));
    console.log(`${passed} passed, ${failed} failed${pending ? `, ${pending} pending` : ""}`);
    return failed ? 1 : 0;
}

const percent = (covered, total) => `${total ? ((covered / total) * 100).toFixed(1) : "100.0"}%`;

function printCoverage(texts) {
    const files = coverageReport(mergeHits(texts), findAddons());
    const total = files.reduce((sum, file) => sum + file.total, 0);
    const covered = files.reduce((sum, file) => sum + file.covered, 0);
    console.log(`coverage: ${covered} of ${total} statements (${percent(covered, total)})`);
    for (const file of files.filter((f) => f.missed.length > 0)) {
        console.log(`  ${file.file} ${percent(file.covered, file.total)} (${file.total - file.covered} missed): ${file.missed.join(", ")}`);
    }
}
