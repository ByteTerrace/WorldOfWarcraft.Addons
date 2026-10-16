// Checks whether node_modules holds what package-lock.json pins, before any verb loads a
// dependency. Otherwise a missing or stale install would crash with ERR_MODULE_NOT_FOUND or run
// the wrong version. It uses only Node's own modules, so it works with no node_modules at all.

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

// The installed packages that differ from the lockfile under root, as "name: why" strings. It's
// empty when every non-optional package the lockfile pins is installed at its locked version.
export function staleDependencies(root) {
    const lockPath = join(root, "package-lock.json");
    if (!existsSync(lockPath)) return [];
    const packages = JSON.parse(readFileSync(lockPath, "utf8")).packages ?? {};
    const problems = [];
    for (const [path, entry] of Object.entries(packages)) {
        if (!path.startsWith("node_modules/") || entry.optional || entry.link) continue;
        const name = path.slice(path.lastIndexOf("node_modules/") + "node_modules/".length);
        const manifest = join(root, path, "package.json");
        if (!existsSync(manifest)) {
            problems.push(`${name}: not installed`);
            continue;
        }
        const version = JSON.parse(readFileSync(manifest, "utf8")).version;
        if (version !== entry.version) problems.push(`${name}: ${version} installed, ${entry.version} locked`);
    }
    return problems;
}
