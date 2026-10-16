// The clones verb: lists structurally identical code in the Lua the format verb owns (every addon's
// and the tests', not tests/fixtures), heaviest cluster first (tools/lib/clones.mjs). It reports,
// and deciding which copies to merge is left to review.
//
//   clones [paths...] [--min-tokens <n>] [--min-statements <n>] [--json]
//
// --json prints one JSON record per cluster. It exits 0 whatever it finds, or 2 on a usage error.

import { readFileSync } from "node:fs";
import { relative, resolve } from "node:path";
import { DefaultMinStatements, DefaultMinTokens, findClones } from "../lib/clones.mjs";
import { repoRoot, toPosix } from "../lib/repo.mjs";
import { formatFiles } from "./format.mjs";

export const options = {
    json: { type: "boolean", default: false },
    "min-statements": { type: "string", default: String(DefaultMinStatements) },
    "min-tokens": { type: "string", default: String(DefaultMinTokens) },
};

export async function run(values, positionals) {
    const minTokens = Number(values["min-tokens"]);
    const minStatements = Number(values["min-statements"]);
    if (!Number.isInteger(minTokens) || minTokens < 1 || !Number.isInteger(minStatements) || minStatements < 1) {
        console.error("--min-tokens and --min-statements take a whole number of at least 1");
        return 2;
    }
    const wanted = positionals.map((path) => toPosix(resolve(path)));
    const files = formatFiles().filter((file) => !wanted.length || wanted.some((path) => toPosix(file) === path || toPosix(file).startsWith(`${path}/`)));
    if (!files.length) {
        console.error(`No Lua file the clones verb reads is under ${positionals.join(", ")}`);
        return 2;
    }
    const sources = files.map((file) => ({ path: toPosix(relative(repoRoot, file)), text: readFileSync(file, "latin1") }));
    const clusters = findClones(sources, { minStatements, minTokens });
    if (values.json) {
        for (const found of clusters) console.log(JSON.stringify(found));
        return 0;
    }
    for (const found of clusters) {
        const exact = found.exact ? `, ${found.exact} token for token` : "";
        console.log(`${found.members.length} copies of ${found.weight} tokens${exact}:`);
        for (const member of found.members) console.log(`  ${member.path}:${member.start}-${member.end} ${member.kind} ${member.name}`);
    }
    const copies = clusters.reduce((sum, found) => sum + found.members.length - 1, 0);
    console.log(`${clusters.length} clusters, ${copies} extra copies, in ${files.length} files`);
    return 0;
}
