// The WoW: Forever client: its install (.build.info), its builds ("1.60.1 (70374)") and the TOC
// interface number a game version implies.

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

export const DEFAULT_WOW_ROOT = "C:/Program Files (x86)/World of Warcraft";

// WoW: Forever reports game version 1.60 or later, and Classic Era reports 1.15.x.
function isForever(major, minor) {
    return major === 1 && minor >= 60;
}

// The build a source string or record names, "1.60.1 (70009)", or null.
export const buildOf = (text) => /\d+\.\d+\.\d+ \(\d+\)/.exec(text ?? "")?.[0] ?? null;

// The ## Interface number of a game version ("1.60.1" or a build "1.60.1 (70374)"): 16001.
export function interfaceOf(version) {
    const [major, minor, patch] = /^(\d+)\.(\d+)\.(\d+)/.exec(version)?.slice(1).map(Number) ?? [];
    return major === undefined ? null : major * 10000 + minor * 100 + patch;
}

// Blizzard's install folder for a product: "wow" is _retail_, "wow_x" is _x_.
function flavorFolder(product) {
    return product === "wow" ? "_retail_" : `_${product.slice("wow_".length)}_`;
}

// Reads <root>/.build.info (pipe-separated, "Name!TYPE:size" headers) and returns the Forever install.
export function findForeverInstall(wowRoot = DEFAULT_WOW_ROOT) {
    const buildInfo = join(wowRoot, ".build.info");
    if (!existsSync(buildInfo)) {
        throw new Error(`No .build.info in ${wowRoot}; pass --wow-root.`);
    }
    const [header, ...rows] = readFileSync(buildInfo, "utf8").split(/\r?\n/).filter(Boolean);
    const columns = header.split("|").map((column) => column.split("!")[0]);
    for (const row of rows) {
        const fields = Object.fromEntries(row.split("|").map((value, i) => [columns[i], value]));
        const [major, minor] = fields.Version.split(".").map(Number);
        if (isForever(major, minor)) {
            return {
                product: fields.Product,
                version: fields.Version,
                interface: interfaceOf(fields.Version),
                flavor: flavorFolder(fields.Product),
                root: wowRoot,
            };
        }
    }
    throw new Error(`No WoW: Forever build (1.60+) in ${buildInfo}.`);
}
