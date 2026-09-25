import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

export const TOC_SUFFIX = "_Camelot.toc";

// An addon is a top-level folder holding <Name>_Camelot.toc.
export function findAddons(root = repoRoot) {
    return readdirSync(root, { withFileTypes: true })
        .filter((entry) => entry.isDirectory() && existsSync(join(root, entry.name, entry.name + TOC_SUFFIX)))
        .map((entry) => readToc(entry.name, root));
}

export function readToc(name, root = repoRoot) {
    const dir = join(root, name);
    const tocPath = join(dir, name + TOC_SUFFIX);
    const metadata = {};
    const files = [];
    for (const raw of readFileSync(tocPath, "utf8").split("\n")) {
        const line = raw.trim();
        const meta = /^## ([^:]+):\s*(.*)$/.exec(line);
        if (meta) {
            metadata[meta[1]] = meta[2];
        } else if (line && !line.startsWith("#")) {
            files.push(line.replaceAll("\\", "/"));
        }
    }
    return { name, dir, tocPath, metadata, files };
}

export function toPosix(path) {
    return path.replaceAll("\\", "/");
}
