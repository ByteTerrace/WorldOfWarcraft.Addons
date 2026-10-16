// The test runner's own tests (tools/verbs/test.mjs), run over the fixture test folders in
// tests/fixtures/runner*: the order files start in, filters, timeouts, test names, and pending tests.

import { join } from "node:path";
import { FIXTURES, assert, tlk } from "../tools/lib/test-support.mjs";
import { orderJobs } from "../tools/verbs/test.mjs";

export const tests = [
    {
        name: "the test runner starts files never timed first, largest first, then the rest longest first",
        run: async () => {
            const order = orderJobs([
                { duration: 400, size: 90000 }, { duration: 5000, size: 3000 }, { size: 2000 }, { duration: 900, size: 100 }, { size: 8000 },
            ]);
            assert(order.join(",") === "4,2,1,3,0", order.join(","));
            assert(orderJobs([]).length === 0, "no jobs");
        },
    },
    {
        // The timeout counts from the end of a worker's setup, so a loaded machine can't time out
        // the quick file. The hanging one never finishes, however long the timeout.
        name: "the test runner fails on an unmatched filter and times out a hanging file without stopping the rest",
        run: async () => {
            const none = tlk(["test", "--dir", join(FIXTURES, "runner"), "no test is named this"]);
            assert(none.status === 1 && none.stdout.includes("No test matches"), `unmatched filter: ${none.status} ${none.stdout}`);
            const hang = tlk(["test", "--dir", join(FIXTURES, "runner"), "--timeout", "1"]);
            assert(hang.status === 1, `hang exits non-zero (got ${hang.status})`);
            assert(/FAIL hang\.test\.lua: timed out after 1s/.test(hang.stdout), hang.stdout);
            assert(/\b3 passed, 1 failed/.test(hang.stdout), hang.stdout);
            const typo = tlk(["test", "tests/facts.test.lua", "tests/nope.test.lua"]);
            assert(typo.status === 1 && typo.stdout.includes("No test file named nope.test.lua"), `a missing file fails: ${typo.stdout}`);
            const either = tlk(["test", "--dir", join(FIXTURES, "runner"), "no such test", "passes"]);
            assert(either.status === 0 && /\b1 passed, 0 failed/.test(either.stdout), `any filter matching counts: ${either.stdout}`);
            const timeout = tlk(["test", "--timeout", "abc"]);
            assert(timeout.status === 2 && timeout.stderr.includes("--timeout must be a positive number"), `${timeout.status} ${timeout.stderr}`);
        },
    },
    {
        name: "the test runner keeps test names with newlines, tabs and backslashes intact",
        run: async () => {
            const run = tlk(["test", "--dir", join(FIXTURES, "runner-names")]);
            assert(/\b4 passed, 1 failed/.test(run.stdout), run.stdout);
            assert(run.stdout.includes('FAIL names.test.lua > "tab\\tin name"'), run.stdout);
            assert(/line one\n {5}line two/.test(run.stdout), run.stdout);
            const filtered = tlk(["test", "--dir", join(FIXTURES, "runner-names"), "with\nnewline"]);
            assert(filtered.status === 0 && /\b1 passed, 0 failed/.test(filtered.stdout), filtered.stdout);
            const slash = tlk(["test", "--dir", join(FIXTURES, "runner-names"), "back\\slash"]);
            assert(slash.status === 0 && /\b1 passed, 0 failed/.test(slash.stdout), slash.stdout);
        },
    },
    {
        name: "the test runner reports pending tests without failing the run",
        run: async () => {
            const run = tlk(["test", "--dir", join(FIXTURES, "runner-pending")]);
            assert(run.status === 0, `pending doesn't fail (got ${run.status}): ${run.stdout}`);
            assert(run.stdout.includes("PEND pending.test.lua > waits: no observation yet"), run.stdout);
            // The fixture's passing test and the runner's two fakes checks.
            assert(/\b3 passed, 0 failed, 1 pending/.test(run.stdout), run.stdout);
        },
    },
    {
        name: "a test file's use(name) runs the kit beside it once and returns its helpers",
        run: async () => {
            const run = tlk(["test", "--dir", join(FIXTURES, "runner-kits")]);
            assert(run.status === 0, `kits pass (got ${run.status}): ${run.stdout}`);
            // The fixture's three tests and the runner's two fakes checks.
            assert(/\b5 passed, 0 failed/.test(run.stdout), run.stdout);
        },
    },
];
