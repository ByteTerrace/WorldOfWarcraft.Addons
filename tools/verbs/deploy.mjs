// Junction-links each addon into the Forever install's AddOns folder. A junction needs no
// admin rights and the game reads straight from the repo: save, then /reload in game.
// TOC changes (new files, SavedVariables) need a full client restart.

import { lstatSync, readlinkSync, rmdirSync, symlinkSync } from "node:fs";
import { join, resolve } from "node:path";
import { findAddons } from "../lib/repo.mjs";
import { DEFAULT_WOW_ROOT, findForeverInstall } from "../lib/wow.mjs";
import { runChecks } from "./check.mjs";

export const options = {
    addon: { type: "string", multiple: true },
    flavor: { type: "string" },
    unlink: { type: "boolean", default: false },
    "wow-root": { type: "string", default: DEFAULT_WOW_ROOT },
};

function linkTarget(path) {
    try {
        const stat = lstatSync(path);
        return { exists: true, target: stat.isSymbolicLink() ? resolve(readlinkSync(path)) : null };
    } catch {
        return { exists: false, target: null };
    }
}

export async function run(values) {
    let flavor = values.flavor;
    if (!flavor) {
        const install = findForeverInstall(values["wow-root"]);
        flavor = install.flavor;
        console.log(`Forever ${install.version} (${install.product}) -> ${flavor}, interface ${install.interface}`);
    }
    const addOnsDir = join(values["wow-root"], flavor, "Interface", "AddOns");
    const addons = findAddons().filter((addon) => !values.addon || values.addon.includes(addon.name));

    if (!values.unlink && (await runChecks({ quiet: true })).length > 0) {
        console.error("Checks failed; not deploying. Run `tlk check` for details.");
        return 1;
    }

    let failed = false;
    for (const addon of addons) {
        const destination = join(addOnsDir, addon.name);
        const { exists, target } = linkTarget(destination);
        const ours = target === resolve(addon.dir);

        if (values.unlink) {
            if (ours) {
                rmdirSync(destination); // removes the junction only, never the repo files
                console.log(`Unlinked ${addon.name}`);
            }
        } else if (ours) {
            console.log(`OK      ${addon.name} (already linked)`);
        } else if (exists) {
            console.error(`Refusing to overwrite existing ${destination}; remove it manually first.`);
            failed = true;
        } else {
            symlinkSync(addon.dir, destination, "junction");
            console.log(`Linked  ${addon.name} -> ${destination}`);
        }
    }
    return failed ? 1 : 0;
}
