// Helpers for the tooling's own tests (tests/*.test.mjs): assertions, a temporary folder, and
// running the CLI as a child process the way a developer does.

import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { repoRoot } from "./repo.mjs";

export const FIXTURES = join(repoRoot, "tests", "fixtures");

export function assert(condition, message) {
    if (!condition) throw new Error(message);
}

// Fails with what's missing and what's unexpected when two lists of findings differ.
export function assertSame(actual, expected) {
    const missing = expected.filter((f) => !actual.includes(f));
    const unexpected = actual.filter((f) => !expected.includes(f));
    if (missing.length || unexpected.length) {
        throw new Error(`missing: ${JSON.stringify(missing)} unexpected: ${JSON.stringify(unexpected)}`);
    }
}

// Runs fn(dir) with a fresh temporary folder, removed afterwards.
export async function withTemp(fn) {
    const dir = mkdtempSync(join(tmpdir(), "tlk-test-"));
    try {
        return await fn(dir);
    } finally {
        rmSync(dir, { recursive: true, force: true });
    }
}

// Runs `node tools/tlk.mjs <args>` from the repository root: { status, stdout, stderr }.
export function tlk(args, options = {}) {
    return spawnSync(process.execPath, [join(repoRoot, "tools", "tlk.mjs"), ...args], { encoding: "utf8", cwd: repoRoot, ...options });
}

// Captures what fn prints with console.log: { result, lines }.
export async function captureLog(fn) {
    const lines = [];
    const log = console.log;
    console.log = (line) => lines.push(String(line));
    try {
        return { result: await fn(), lines };
    } finally {
        console.log = log;
    }
}
