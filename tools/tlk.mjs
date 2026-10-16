#!/usr/bin/env node
// Repository automation. Every operation is a verb here; there are no loose scripts.
//
//   node tools/tlk.mjs check [--quiet] [--wow-root <path>]           static gates over every addon
//   node tools/tlk.mjs test [filter | files...] [--timeout <s>] [--dir <folder>] [--coverage] behavioral tests in real Lua 5.1
//   node tools/tlk.mjs clones [paths...] [--min-tokens <n>] [--min-statements <n>] [--json]   duplicated code
//   node tools/tlk.mjs deploy [--unlink] [--no-test] [--addon <name>]... [--wow-root <path>] [--flavor <_folder_>]
//   node tools/tlk.mjs guesses [harness files...] [--top <n>] [--json]   the harness guesses worth a probe, ranked
//   node tools/tlk.mjs format [paths...] [--check] [--only <pass,...>]    the Lua's one canonical form
//   node tools/tlk.mjs package [--addon <name>]... [--no-test]            the zip players install, in dist/
//   node tools/tlk.mjs api-sync [--docs <Blizzard_APIDocumentationGenerated dir>] [--globals <dump>]
//   node tools/tlk.mjs api-sync --latest [--source <wow-ui-source checkout | file>]   is the snapshot's build the newest?
//   node tools/tlk.mjs probes [--import [<SavedVariables file>]] [--check [--warn-builds]] [--wow-root <path>] [--flavor <_folder_>]
//
// Before any verb loads, node_modules must match package-lock.json; when it doesn't, tlk says to
// run `npm ci` and exits 2.

import { parseArgs } from "node:util";
import { staleDependencies } from "./lib/dependencies.mjs";
import { repoRoot } from "./lib/repo.mjs";

const verbs = {
    "api-sync": () => import("./verbs/api-sync.mjs"),
    check: () => import("./verbs/check.mjs"),
    clones: () => import("./verbs/clones.mjs"),
    guesses: () => import("./verbs/guesses.mjs"),
    deploy: () => import("./verbs/deploy.mjs"),
    format: () => import("./verbs/format.mjs"),
    package: () => import("./verbs/package.mjs"),
    probes: () => import("./verbs/probes.mjs"),
    test: () => import("./verbs/test.mjs"),
};

const [verb, ...rest] = process.argv.slice(2);
const load = verbs[verb];
if (!load) {
    console.error(`usage: tlk <${Object.keys(verbs).join("|")}> [options]`);
    process.exit(2);
}

const stale = staleDependencies(repoRoot);
if (stale.length) {
    console.error(`node_modules doesn't match package-lock.json (${stale.join("; ")}).\nRun \`npm ci\` in ${repoRoot}, then try again.`);
    process.exit(2);
}

const module = await load();
const { values, positionals } = parseArgs({ args: rest, options: module.options ?? {}, allowPositionals: true });
process.exitCode = (await module.run(values, positionals)) ?? 0;
