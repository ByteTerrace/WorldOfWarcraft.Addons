import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

// Functions addon code must never call, though the docs don't mark them IsProtectedFunction, each
// with its in-game evidence (the client refused it, or calling it froze the client):
// { [name]: evidence }. The harness forbids them and the PROTECTED rule reports every call.
export const FORBIDDEN_PATH = join(repoRoot, "tools", "api", "forbidden.json");

export function readForbidden(path = FORBIDDEN_PATH) {
    return existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) : {};
}

// The TOC suffixes the Forever client loads: its game type is Camelot, with Forever as an alias
// (warcraft.wiki.gg, TOC format). The tools read the first one a folder has.
export const TOC_SUFFIXES = ["_Forever.toc", "_Camelot.toc"];

// The Forever TOC file names a folder holds, in TOC_SUFFIXES order: ["Name_Forever.toc", ...].
// Matched exactly, so the answer doesn't depend on the file system's case rules.
export function tocFilesOf(name, root = repoRoot) {
    const files = new Set(readdirSync(join(root, name)));
    return TOC_SUFFIXES.map((suffix) => name + suffix).filter((file) => files.has(file));
}

const topFolders = (root) => readdirSync(root, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && !entry.name.startsWith(".") && entry.name !== "node_modules")
    .map((entry) => entry.name);

// An addon is a top-level folder holding <Name>_Forever.toc or <Name>_Camelot.toc.
export function findAddons(root = repoRoot) {
    return topFolders(root).filter((name) => tocFilesOf(name, root).length > 0).map((name) => readToc(name, root));
}

// Top-level folders that hold a .toc but no Forever TOC, so the Forever client won't load them.
export function findMisnamedAddons(root = repoRoot) {
    return topFolders(root)
        .filter((name) => tocFilesOf(name, root).length === 0)
        .filter((name) => readdirSync(join(root, name)).some((file) => file.toLowerCase().endsWith(".toc")))
        .sort();
}

// Addon folders holding more than one Forever TOC: { name, files } with files in TOC_SUFFIXES
// order. The tools read the first; which one the client loads isn't documented.
export function findAmbiguousAddons(root = repoRoot) {
    return topFolders(root)
        .map((name) => ({ name, files: tocFilesOf(name, root) }))
        .filter((addon) => addon.files.length > 1);
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

// An addon's TOC: its first Forever TOC file (tocFile, its name; tocPath), ## metadata, listed
// files, dependencies and SavedVariables.
export function readToc(name, root = repoRoot) {
    const dir = join(root, name);
    const tocFile = tocFilesOf(name, root)[0];
    if (!tocFile) throw new Error(`${dir} has no ${TOC_SUFFIXES.map((suffix) => name + suffix).join(" or ")}`);
    const tocPath = join(dir, tocFile);
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
        name, dir, tocFile, tocPath, metadata, files,
        dependencies: dependenciesOf(metadata),
        savedVariables: [...splitList(metadata.SavedVariables), ...splitList(metadata.SavedVariablesPerCharacter)],
    };
}

export function toPosix(path) {
    return path.replaceAll("\\", "/");
}
