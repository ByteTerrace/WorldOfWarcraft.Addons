import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

const TOC_SUFFIX = "_Camelot.toc";

// An addon is a top-level folder holding <Name>_Camelot.toc.
export function findAddons(root = repoRoot) {
    return readdirSync(root, { withFileTypes: true })
        .filter((entry) => entry.isDirectory() && existsSync(join(root, entry.name, entry.name + TOC_SUFFIX)))
        .map((entry) => readToc(entry.name, root));
}

// Top-level folders that hold a .toc but no <Name>_Camelot.toc, so the Forever client won't load them.
export function findMisnamedAddons(root = repoRoot) {
    return readdirSync(root, { withFileTypes: true })
        .filter((entry) => entry.isDirectory() && !entry.name.startsWith(".") && entry.name !== "node_modules")
        .filter((entry) => !existsSync(join(root, entry.name, entry.name + TOC_SUFFIX)))
        .filter((entry) => readdirSync(join(root, entry.name)).some((file) => file.toLowerCase().endsWith(".toc")))
        .map((entry) => entry.name);
}

export function splitList(value) {
    return (value ?? "").split(",").map((s) => s.trim()).filter(Boolean);
}

// The client reads dependencies from ## Dependencies, ## RequiredDeps and any ## Dep* key.
function dependenciesOf(metadata) {
    const names = [];
    for (const [key, value] of Object.entries(metadata)) {
        if (key === "Dependencies" || key === "RequiredDeps" || /^Dep/.test(key)) {
            for (const name of splitList(value)) if (!names.includes(name)) names.push(name);
        }
    }
    return names;
}

export function readToc(name, root = repoRoot) {
    const dir = join(root, name);
    const tocPath = join(dir, name + TOC_SUFFIX);
    const metadata = {};
    const files = [];
    for (const raw of readFileSync(tocPath, "utf8").split("\n")) {
        const line = raw.trim();
        const meta = /^##\s*([^:]+?)\s*:\s*(.*)$/.exec(line);
        if (meta) {
            metadata[meta[1]] = meta[2];
        } else if (line && !line.startsWith("#")) {
            files.push(line.replaceAll("\\", "/"));
        }
    }
    return {
        name, dir, tocPath, metadata, files,
        dependencies: dependenciesOf(metadata),
        savedVariables: [...splitList(metadata.SavedVariables), ...splitList(metadata.SavedVariablesPerCharacter)],
    };
}

export function toPosix(path) {
    return path.replaceAll("\\", "/");
}
