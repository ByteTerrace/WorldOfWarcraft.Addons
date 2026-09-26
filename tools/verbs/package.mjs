// Builds the zip players install: dist/<AddOn>-<Version>.zip, holding each shipped addon's folder
// as committed at HEAD, ready to extract into Interface\AddOns. Only committed files ship, so
// players' own sounds (ignored by git) never do.
//
//   The package is every addon without ## X-DevOnly, or --addon <name>... and the addons they
//   depend on. It's named after the one addon nothing else in it depends on, with that addon's
//   ## Version. A dev-only addon, an uncommitted change in a shipped folder, or a TOC file that
//   isn't committed is an error. Before building, package runs the gates: `check`, then `test`
//   (skip the tests with --no-test).

import { spawnSync } from "node:child_process";
import { mkdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { findAddons, repoRoot, toPosix } from "../lib/repo.mjs";
import { runChecks } from "./check.mjs";
import { selectAddons } from "./deploy.mjs";
import { run as runTests } from "./test.mjs";

export const options = {
    addon: { type: "string", multiple: true },
    "no-test": { type: "boolean", default: false },
};

export const DIST = join(repoRoot, "dist");

function git(args) {
    const result = spawnSync("git", args, { cwd: repoRoot, encoding: "utf8" });
    if (result.status !== 0) throw new Error(`git ${args.join(" ")}: ${result.stderr.trim()}`);
    return result.stdout;
}

// What ships and under which name, or why it can't: { addons, name, version, errors }.
// tracked: the repo paths committed at HEAD; dirty: repo paths with uncommitted changes.
export function planPackage(all, names, tracked, dirty) {
    const errors = [];
    const unknown = (names ?? []).filter((name) => !all.some((addon) => addon.name === name));
    if (unknown.length) {
        return { addons: [], errors: [`Unknown addon(s): ${unknown.join(", ")}.`] };
    }
    const addons = names ? selectAddons(all, names) : all.filter((addon) => !addon.metadata["X-DevOnly"]);
    for (const addon of addons) {
        if (addon.metadata["X-DevOnly"]) errors.push(`${addon.name} is ## X-DevOnly and never ships.`);
    }
    const needed = new Set(addons.flatMap((addon) => addon.dependencies));
    const tops = addons.filter((addon) => !needed.has(addon.name));
    if (tops.length !== 1) {
        errors.push(`The package needs one addon nothing else in it depends on, to name it; found ${tops.map((addon) => addon.name).join(", ") || "none"}.`);
    }
    const trackedSet = new Set(tracked);
    for (const addon of addons) {
        const files = [`${addon.name}_Camelot.toc`, ...addon.files].map((file) => `${addon.name}/${toPosix(file)}`);
        for (const file of files) {
            if (!trackedSet.has(file)) errors.push(`${file} is listed in the TOC but not committed.`);
        }
        for (const file of dirty) {
            if (file.startsWith(`${addon.name}/`)) errors.push(`${file} has uncommitted changes; commit them first.`);
        }
    }
    const top = tops.length === 1 ? tops[0] : null;
    const version = top?.metadata.Version;
    if (top && !version) errors.push(`${top.name} has no ## Version.`);
    return { addons, name: top?.name, version, errors };
}

export async function run(values) {
    const all = findAddons();
    const dirs = all.map((addon) => addon.name);
    const tracked = git(["ls-tree", "-r", "--name-only", "HEAD", "--", ...dirs]).split("\n").filter(Boolean);
    const dirty = git(["status", "--porcelain", "--untracked-files=all", "--", ...dirs]).split("\n").filter(Boolean)
        .map((line) => line.slice(3).replace(/^.* -> /, "").replace(/^"|"$/g, ""));
    const plan = planPackage(all, values.addon, tracked, dirty);
    if (plan.errors.length) {
        for (const error of plan.errors) console.error(error);
        return 1;
    }

    if ((await runChecks({ quiet: true })).length > 0) {
        console.error("Checks failed; not packaging. Run `tlk check` for details.");
        return 1;
    }
    if (!values["no-test"] && (await runTests({ timeout: "30" }, [])) !== 0) {
        console.error("Tests failed; not packaging (--no-test skips them).");
        return 1;
    }

    mkdirSync(DIST, { recursive: true });
    const path = join(DIST, `${plan.name}-${plan.version}.zip`);
    rmSync(path, { force: true });
    git(["archive", "--format=zip", "-o", path, "HEAD", "--", ...plan.addons.map((addon) => addon.name)]);
    const commit = git(["rev-parse", "--short", "HEAD"]).trim();
    console.log(`Packaged ${plan.addons.map((addon) => addon.name).join(", ")} at ${commit} -> ${path}`);
    return 0;
}
