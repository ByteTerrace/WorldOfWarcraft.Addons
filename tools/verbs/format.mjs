// The format verb: rewrites the repository's Lua to its one canonical form (tools/lib/format-lua.mjs,
// Puck's formatter passes mapped to Lua). It covers every addon's Lua and the tests' Lua, not
// tests/fixtures, whose files are deliberately as they are.
//
//   format [paths...] [--check] [--only <pass,...>]
//
// --check writes nothing and exits 1 when a file would change, naming the first line that would.
// A file that doesn't parse, or that a pass would break, exits 2 and is left alone.

import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { FormatError, PASSES, firstDifference, formatLua } from "../lib/format-lua.mjs";
import { findAddons, repoRoot, toPosix } from "../lib/repo.mjs";

export const options = {
    check: { type: "boolean", default: false },
    only: { type: "string" },
};

/** Every Lua file the format verb owns under root, as absolute paths, sorted. */
export function formatFiles(root = repoRoot) {
    const files = [];
    const add = (dir, keep = () => true) => {
        for (const file of readdirSync(dir, { recursive: true }).map(toPosix)) {
            if (file.endsWith(".lua") && keep(file)) files.push(join(dir, file));
        }
    };
    for (const addon of findAddons(root)) add(addon.dir);
    if (existsSync(join(root, "tests"))) add(join(root, "tests"), (file) => !file.startsWith("fixtures/"));
    return files.sort();
}

/**
 * Formats each file; returns its findings ({ path, line, message }) and the files it changed.
 * @param {{ files: string[], check?: boolean, passes?: string[], root?: string }} options
 */
export function formatRepository({ files, check = false, passes = PASSES, root = repoRoot }) {
    const findings = [];
    const changed = [];
    for (const file of files) {
        const path = toPosix(relative(root, file));
        // As bytes (Lua's view of a file): UTF-8 text round-trips exactly.
        const text = readFileSync(file, "latin1");
        let formatted;
        try {
            formatted = formatLua(text, passes);
        } catch (error) {
            if (!(error instanceof FormatError)) throw error;
            findings.push({ path, line: 1, message: error.message, broken: true });
            continue;
        }
        if (formatted === text) continue;
        changed.push(path);
        if (check) findings.push({ path, line: firstDifference(text, formatted), message: "isn't formatted: run node tools/tlk.mjs format" });
        else writeFileSync(file, formatted, "latin1");
    }
    return { findings, changed };
}

export async function run(values, positionals) {
    const passes = values.only ? values.only.split(",").map((pass) => pass.trim()) : PASSES;
    const unknown = passes.filter((pass) => !PASSES.includes(pass));
    if (unknown.length) {
        console.error(`Unknown pass ${unknown.join(", ")}; the passes are ${PASSES.join(", ")}`);
        return 2;
    }
    const all = formatFiles();
    const wanted = positionals.map((path) => toPosix(resolve(path)));
    const files = wanted.length ? all.filter((file) => wanted.some((path) => toPosix(file) === path || toPosix(file).startsWith(`${path}/`))) : all;
    if (wanted.length && !files.length) {
        console.error(`No Lua file the format verb owns is under ${positionals.join(", ")}`);
        return 2;
    }
    const { findings, changed } = formatRepository({ files, check: values.check, passes });
    for (const finding of findings) console.log(`${finding.path}:${finding.line}: FORMAT ${finding.message}`);
    if (findings.some((finding) => finding.broken)) return 2;
    if (values.check) {
        console.log(findings.length ? `${findings.length} of ${files.length} files aren't formatted` : `${files.length} files formatted`);
        return findings.length ? 1 : 0;
    }
    for (const path of changed) console.log(`Formatted ${path}`);
    console.log(`${changed.length} of ${files.length} files changed`);
    return 0;
}
