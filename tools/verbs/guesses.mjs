// The guesses verb: lists the harness's [G] guesses and [C] conservative fallbacks (tests/harness/*.lua), most
// depended on first, so the ones worth a probe are on top (tools/lib/guesses.mjs). It reports and gates nothing.
//
//   guesses [harness files...] [--top <n>] [--json]
//
// Each guess prints as `path:line [G] claim`, then the client names it's about, the shipped addons' files that use
// them, the test files that call the harness methods it models, and the probes that cite it or read the same API.
// Guesses rank by addon files, then test files. --json prints one JSON record per guess. It exits 0, or 2 on a
// usage error.

import { readdirSync, readFileSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { findGuesses, rankGuesses } from "../lib/guesses.mjs";
import { findAddons, isDevOnly, repoRoot, toPosix } from "../lib/repo.mjs";

export const options = {
    json: { type: "boolean", default: false },
    top: { type: "string" },
};

const HARNESS = join(repoRoot, "tests", "harness");
const PROBE_FILES = /^Probes.*\.lua$/;

const read = (path) => readFileSync(path, "latin1");
const repoPath = (path) => toPosix(relative(repoRoot, path));

// Every .lua under dir, as { path, text }.
function luaFiles(dir) {
    return readdirSync(dir, { recursive: true }).map(String).filter((file) => file.endsWith(".lua")).sort()
        .map((file) => ({ path: repoPath(join(dir, file)), text: read(join(dir, file)) }));
}

// Each probe's definition in ByteTerrace_DevTools: its name and the text from its `name = "..."` to the next one's.
function probeDefinitions() {
    const dir = join(repoRoot, "ByteTerrace_DevTools");
    const probes = [];
    for (const file of readdirSync(dir).filter((name) => PROBE_FILES.test(name)).sort()) {
        const text = read(join(dir, file));
        const starts = [...text.matchAll(/\bname = "([a-z][A-Za-z0-9]*(?:\.[A-Za-z0-9]+)+)"/g)];
        starts.forEach((match, i) => {
            probes.push({ name: match[1], text: text.slice(match.index, starts[i + 1]?.index ?? text.length) });
        });
    }
    return probes;
}

export async function run(values, positionals) {
    const top = (values.top === undefined) ? Infinity : Number(values.top);
    if (!(top === Infinity || (Number.isInteger(top) && top > 0))) {
        console.error("--top takes a whole number of at least 1");
        return 2;
    }
    const all = readdirSync(HARNESS).filter((file) => file.endsWith(".lua")).sort().map((file) => join(HARNESS, file));
    const wanted = positionals.map((path) => toPosix(resolve(path)));
    const files = all.filter((file) => !wanted.length || wanted.includes(toPosix(file)));
    if (!files.length) {
        console.error(`No harness file is ${positionals.join(", ")}; the guesses verb reads tests/harness/*.lua`);
        return 2;
    }
    const guesses = files.flatMap((file) => findGuesses(repoPath(file), read(file)));
    const api = JSON.parse(readFileSync(join(repoRoot, "tools", "api", "forever.json"), "utf8"));
    const methods = [...new Set(all.flatMap((file) => [...read(file).matchAll(/function Harness[:.](\w+)/g)].map((m) => m[1])))];
    const addons = findAddons().filter((addon) => !isDevOnly(addon)).flatMap((addon) => luaFiles(addon.dir));
    const testDir = join(repoRoot, "tests");
    const tests = readdirSync(testDir).filter((file) => file.endsWith(".test.lua")).sort()
        .map((file) => ({ path: `tests/${file}`, text: read(join(testDir, file)) }));
    const ranked = rankGuesses(guesses, { addons, api, methods, probes: probeDefinitions(), tests });
    const shown = ranked.slice(0, top);
    if (values.json) {
        for (const guess of shown) {
            const { words: _, ...record } = guess;
            console.log(JSON.stringify(record));
        }
        return 0;
    }
    const list = (items) => (items.length ? items.join(", ") : "none");
    for (const guess of shown) {
        console.log(`${guess.path}:${guess.line} [${guess.marker}] ${guess.claim}`);
        console.log(`    about: ${list(guess.names)}`);
        console.log(`    addons: ${guess.addons.length} (${list(guess.addons)}); tests: ${guess.tests.length}`);
        console.log(`    probes: cited ${list(guess.cited)}; related ${list(guess.related)}`);
    }
    const count = (marker) => ranked.filter((guess) => guess.marker === marker).length;
    console.log(`${ranked.length} guesses (${count("G")} [G], ${count("C")} [C]): ${ranked.filter((g) => g.addons.length).length} about `
        + `API the shipped addons use, ${ranked.filter((g) => g.cited.length).length} cite a probe, `
        + `${ranked.filter((g) => !g.cited.length && g.related.length).length} more have a probe reading the same API.`);
    return 0;
}
