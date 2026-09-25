#!/usr/bin/env node
// Repository automation. Every operation is a verb here; there are no loose scripts.
//
//   node tools/tlk.mjs check [--wow-root <path>]                     static gates over every addon
//   node tools/tlk.mjs test [filter] [--timeout <s>] [--dir <folder>] behavioral tests in real Lua 5.1
//   node tools/tlk.mjs deploy [--unlink] [--no-test] [--addon <name>]... [--wow-root <path>] [--flavor <_folder_>]
//   node tools/tlk.mjs api-sync [--docs <Blizzard_APIDocumentationGenerated dir>] [--globals <dump>]
//   node tools/tlk.mjs probes [--import [<SavedVariables file>]] [--check] [--wow-root <path>] [--flavor <_folder_>]

import { parseArgs } from "node:util";

const verbs = {
    "api-sync": () => import("./verbs/api-sync.mjs"),
    check: () => import("./verbs/check.mjs"),
    deploy: () => import("./verbs/deploy.mjs"),
    probes: () => import("./verbs/probes.mjs"),
    test: () => import("./verbs/test.mjs"),
};

const [verb, ...rest] = process.argv.slice(2);
const load = verbs[verb];
if (!load) {
    console.error(`usage: tlk <${Object.keys(verbs).join("|")}> [options]`);
    process.exit(2);
}

const module = await load();
const { values, positionals } = parseArgs({ args: rest, options: module.options ?? {}, allowPositionals: true });
process.exitCode = (await module.run(values, positionals)) ?? 0;
