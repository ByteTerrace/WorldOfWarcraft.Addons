import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

export const DEFAULT_WOW_ROOT = "C:/Program Files (x86)/World of Warcraft";

// WoW: Forever reports game version 1.60+; Classic Era is 1.15.x.
function isForever(major, minor) {
    return major === 1 && minor >= 60;
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
        const [major, minor, patch] = fields.Version.split(".").map(Number);
        if (isForever(major, minor)) {
            return {
                product: fields.Product,
                version: fields.Version,
                interface: major * 10000 + minor * 100 + patch,
                flavor: flavorFolder(fields.Product),
                root: wowRoot,
            };
        }
    }
    throw new Error(`No WoW: Forever build (1.60+) in ${buildInfo}.`);
}
