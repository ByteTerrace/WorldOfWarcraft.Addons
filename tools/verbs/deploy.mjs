// Junction-links each addon into the Forever install's AddOns folder. A junction needs no
// admin rights and the game reads straight from the repo: save, then /reload in game.
// TOC changes (new files, SavedVariables) need a full client restart.
//
//   Before linking, deploy runs the gates: `check`, then `test` (skip the tests with --no-test).
//   --addon <name> limits it to those addons and the addons they depend on (linking the toolkit
//   links ByteTerrace_Core too). An unknown name is an error. The AddOns folder must exist.
//
//   A link to the same addon in another worktree of this repository (`git worktree list`) is this
//   repo's own too: deploy repoints it to this checkout and says from where to where. So is a
//   dangling link to the same addon in a folder inside or beside a worktree: a worktree since
//   removed (git no longer lists it).
//
//   --unlink removes only links that point at this repo's addon folders, in this checkout or any
//   of its worktrees (dangling ones included), and reports every link it leaves alone (pointing
//   elsewhere, or at a path that differs only in case).

import { execFileSync } from "node:child_process";
import { existsSync, lstatSync, readlinkSync, rmdirSync, symlinkSync } from "node:fs";
import { basename, dirname, isAbsolute, join, relative, resolve } from "node:path";
import { findAddons, repoRoot } from "../lib/repo.mjs";
import { DEFAULT_WOW_ROOT, findForeverInstall } from "../lib/wow.mjs";
import { runChecks } from "./check.mjs";
import { run as runTests } from "./test.mjs";

export const options = {
    addon: { type: "string", multiple: true },
    flavor: { type: "string" },
    "no-test": { type: "boolean", default: false },
    unlink: { type: "boolean", default: false },
    "wow-root": { type: "string", default: DEFAULT_WOW_ROOT },
};

// A readlink result as a comparable absolute path: without the \\?\ (or \??\) prefix Windows
// puts on junction targets, resolved against the link's folder when relative, and without a
// trailing separator.
export function normalizeTarget(raw, linkPath, platform = process.platform) {
    let target = raw.replace(/^\\\\\?\\|^\\\?\?\\/, "");
    if (platform === "win32" && /^UNC\\/i.test(target)) target = "\\\\" + target.slice(4);
    target = resolve(dirname(linkPath), target);
    return target.length > 3 ? target.replace(/[\\/]+$/, "") : target;
}

// "same": the link points at expected; "case": only letter case differs (on Windows the same
// folder, but not the path this repo manages); "other": somewhere else.
export function compareTargets(target, expected, platform = process.platform) {
    const a = resolve(target).replace(/[\\/]+$/, "");
    const b = resolve(expected).replace(/[\\/]+$/, "");
    if (a === b) return "same";
    if (a.toLowerCase() === b.toLowerCase()) return platform === "win32" ? "case" : "other";
    return "other";
}

// The worktree folders `git worktree list --porcelain` names (bare repositories left out), as
// absolute paths.
export function parseWorktrees(porcelain) {
    const roots = [];
    for (const record of porcelain.split(/\n\s*\n/)) {
        const lines = record.split("\n").map((line) => line.trim());
        const path = lines.find((line) => line.startsWith("worktree "))?.slice("worktree ".length);
        if (path && !lines.includes("bare")) roots.push(resolve(path));
    }
    return roots;
}

// This repository's worktrees, this checkout among them, or only this checkout without git.
function repoWorktrees() {
    try {
        return parseWorktrees(execFileSync("git", ["worktree", "list", "--porcelain"], { cwd: repoRoot, encoding: "utf8" }));
    } catch {
        return [repoRoot];
    }
}

// What a link's target is to this checkout: compareTargets' "same", "case" or "other", or
// "worktree" (with worktree, its root) when it's the same addon's folder in another worktree. A
// dangling link (its target gone) to the same addon in a folder inside or beside a worktree was
// a worktree since removed: { kind: "worktree", worktree, removed: true }.
export function classifyLink(target, expected, worktrees, { platform = process.platform, dangling = false } = {}) {
    const match = compareTargets(target, expected, platform);
    if (match !== "other") return { kind: match };
    const name = basename(expected);
    const worktree = worktrees.find((root) => compareTargets(target, join(root, name), platform) === "same");
    if (worktree) return { kind: "worktree", worktree };
    const root = dirname(resolve(target));
    const inside = (folder, parent) => {
        const path = relative(parent, folder);
        return path !== "" && !path.startsWith("..") && !isAbsolute(path);
    };
    const former = dangling && basename(resolve(target)) === name && worktrees.some((tree) =>
        inside(root, tree) || compareTargets(dirname(root), dirname(tree), platform) === "same");
    return former ? { kind: "worktree", worktree: root, removed: true } : { kind: "other" };
}

function linkTarget(path) {
    try {
        const stat = lstatSync(path);
        return { exists: true, target: stat.isSymbolicLink() ? normalizeTarget(readlinkSync(path), path) : null };
    } catch {
        return { exists: false, target: null };
    }
}

// Linking includes dependencies. Unlinking selects only the addons explicitly requested.
export function selectAddons(all, names, includeDependencies = true) {
    const wanted = new Set(names ?? all.map((addon) => addon.name));
    if (names && includeDependencies) {
        const byName = new Map(all.map((addon) => [addon.name, addon]));
        // Set iteration visits newly added entries too. Already visited names can't cycle.
        for (const name of wanted) {
            for (const dependency of byName.get(name)?.dependencies ?? []) wanted.add(dependency);
        }
    }
    return all.filter((addon) => wanted.has(addon.name));
}

export async function run(values) {
    const all = findAddons();
    const unknown = (values.addon ?? []).filter((name) => !all.some((addon) => addon.name === name));
    if (unknown.length) {
        console.error(`Unknown addon(s): ${unknown.join(", ")}. Addons here: ${all.map((addon) => addon.name).join(", ")}.`);
        return 1;
    }
    let flavor = values.flavor;
    if (!flavor) {
        const install = findForeverInstall(values["wow-root"]);
        flavor = install.flavor;
        console.log(`Forever ${install.version} (${install.product}) -> ${flavor}, interface ${install.interface}`);
    }
    const addOnsDir = join(values["wow-root"], flavor, "Interface", "AddOns");
    if (!existsSync(addOnsDir)) {
        console.error(`No AddOns folder at ${addOnsDir}; start the game once so it creates it.`);
        return 1;
    }
    const addons = selectAddons(all, values.addon, !values.unlink);

    if (!values.unlink && (await runChecks({ quiet: true, wowRoot: values["wow-root"] })).length > 0) {
        console.error("Checks failed; not deploying. Run `tlk check` for details.");
        return 1;
    }
    if (!values.unlink && !values["no-test"] && (await runTests({ timeout: "30" }, [])) !== 0) {
        console.error("Tests failed; not deploying (--no-test skips them).");
        return 1;
    }

    let failed = false;
    const worktrees = repoWorktrees();
    for (const addon of addons) {
        const destination = join(addOnsDir, addon.name);
        const { exists, target } = linkTarget(destination);
        const isDangling = Boolean(target) && !existsSync(target);
        const link = target ? classifyLink(target, addon.dir, worktrees, { dangling: isDangling }) : null;
        const match = link?.kind ?? null;
        const dangling = isDangling ? " (dangling)" : "";
        const where = link?.removed ? `a removed worktree, ${link.worktree}` : `worktree ${link?.worktree}`;

        if (values.unlink) {
            if (match === "same") {
                rmdirSync(destination); // removes the junction only, never the repo files
                console.log(`Unlinked ${addon.name}`);
            } else if (match === "worktree") {
                rmdirSync(destination);
                console.log(`Unlinked ${addon.name}: linked to ${target}${dangling}, in ${where}`);
            } else if (match === "case") {
                console.log(`Skipped  ${addon.name}: links to ${target}, which differs from ${addon.dir} only in case; remove it manually`);
            } else if (match === "other") {
                console.log(`Skipped  ${addon.name}: links to ${target}, not this repo`);
            } else if (exists) {
                console.log(`Skipped  ${addon.name}: ${destination} is a real folder, not a link`);
            }
        } else if (match === "same") {
            console.log(`OK      ${addon.name} (already linked)`);
        } else if (match === "worktree") {
            rmdirSync(destination);
            symlinkSync(addon.dir, destination, "junction");
            console.log(`Relinked ${addon.name}: ${destination} from ${target}${dangling} (${where}) to ${addon.dir}`);
        } else if (exists) {
            const why = target ? `links to ${target}` : "is a real folder";
            console.error(`Refusing to overwrite ${destination} (${why}); remove it manually first.`);
            failed = true;
        } else {
            symlinkSync(addon.dir, destination, "junction");
            console.log(`Linked  ${addon.name} -> ${destination}`);
        }
    }
    return failed ? 1 : 0;
}
