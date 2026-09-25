// Junction-links each addon into the Forever install's AddOns folder. A junction needs no
// admin rights and the game reads straight from the repo: save, then /reload in game.
// TOC changes (new files, SavedVariables) need a full client restart.
//
//   Before linking, deploy runs the gates: `check`, then `test` (skip the tests with --no-test).
//   --addon <name> limits it to those addons; an unknown name is an error.
//
//   --unlink removes only links that point at this repo's addon folders, and reports every link
//   it leaves alone (pointing elsewhere, or at a path that differs only in case).

import { lstatSync, readlinkSync, rmdirSync, symlinkSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { findAddons } from "../lib/repo.mjs";
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

function linkTarget(path) {
    try {
        const stat = lstatSync(path);
        return { exists: true, target: stat.isSymbolicLink() ? normalizeTarget(readlinkSync(path), path) : null };
    } catch {
        return { exists: false, target: null };
    }
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
    const addons = all.filter((addon) => !values.addon || values.addon.includes(addon.name));

    if (!values.unlink && (await runChecks({ quiet: true, wowRoot: values["wow-root"] })).length > 0) {
        console.error("Checks failed; not deploying. Run `tlk check` for details.");
        return 1;
    }
    if (!values.unlink && !values["no-test"] && (await runTests({ timeout: "30" }, [])) !== 0) {
        console.error("Tests failed; not deploying (--no-test skips them).");
        return 1;
    }

    let failed = false;
    for (const addon of addons) {
        const destination = join(addOnsDir, addon.name);
        const { exists, target } = linkTarget(destination);
        const match = target ? compareTargets(target, addon.dir) : null;

        if (values.unlink) {
            if (match === "same") {
                rmdirSync(destination); // removes the junction only, never the repo files
                console.log(`Unlinked ${addon.name}`);
            } else if (match === "case") {
                console.log(`Skipped  ${addon.name}: links to ${target}, which differs from ${addon.dir} only in case; remove it manually`);
            } else if (match === "other") {
                console.log(`Skipped  ${addon.name}: links to ${target}, not this repo`);
            } else if (exists) {
                console.log(`Skipped  ${addon.name}: ${destination} is a real folder, not a link`);
            }
        } else if (match === "same") {
            console.log(`OK      ${addon.name} (already linked)`);
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
