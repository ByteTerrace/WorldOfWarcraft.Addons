// Builds the zip players install: dist/<AddOn>-<Version>.zip, holding each shipped addon's folder
// as committed at HEAD, ready to extract into Interface\AddOns. Only committed files ship, so
// players' own sounds (ignored by git) never do.
//
//   The package is every addon without ## X-DevOnly, or --addon <name>... and the addons they
//   depend on. It's named after the one addon nothing else in it depends on, with its version. A
//   dev-only addon, an uncommitted change in a shipped folder, or a TOC file that isn't committed
//   is an error. Before building, package runs the gates: `check`, then `test` (skip the tests
//   with --no-test).
//
//   Versions: when HEAD is tagged vX.Y.Z (`git describe --tags --exact-match`), every shipped
//   addon's ## Version is X.Y.Z; otherwise each keeps its own ## Version with -dev+<short sha>
//   added (0.1.0-dev+79e5013). Either way the version is written into the zipped TOCs only, never
//   the working tree. A tag that isn't exactly vX.Y.Z counts as no tag.
//
//   The named addon's folder in the zip also holds CHANGELOG.txt: the subjects of the commits
//   since the previous vX.Y.Z tag (the one before HEAD's own, when HEAD is tagged), newest first,
//   merges left out; every commit's when there's no earlier tag.

import { spawnSync } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { findAddons, isDevOnly, repoRoot, toPosix } from "../lib/repo.mjs";
import { writeZip } from "../lib/zip.mjs";
import { runChecks } from "./check.mjs";
import { selectAddons } from "./deploy.mjs";
import { run as runTests } from "./test.mjs";

export const options = {
    addon: { type: "string", multiple: true },
    "no-test": { type: "boolean", default: false },
};

export const DIST = join(repoRoot, "dist");

// The release tags package reads: git's glob for them, and the exact form a release tag has.
const TAG_GLOB = "v[0-9]*.[0-9]*.[0-9]*";
const RELEASE_TAG = /^v(\d+\.\d+\.\d+)$/;

function git(args, options = {}) {
    const result = spawnSync("git", args, { cwd: repoRoot, encoding: "utf8", maxBuffer: 256 * 1024 * 1024, ...options });
    if (result.status !== 0) throw new Error(`git ${args.join(" ")}: ${String(result.stderr).trim()}`);
    return result.stdout;
}

// git's answer, trimmed, or null when it fails (no such tag, no parent commit).
function gitOrNull(args) {
    try {
        return git(args).trim() || null;
    } catch {
        return null;
    }
}

// What ships and under which name, or why it can't: { addons, name, version, errors }.
// tracked: the repo paths committed at HEAD; dirty: repo paths with uncommitted changes.
export function planPackage(all, names, tracked, dirty) {
    const errors = [];
    const unknown = (names ?? []).filter((name) => !all.some((addon) => addon.name === name));
    if (unknown.length) {
        return { addons: [], errors: [`Unknown addon(s): ${unknown.join(", ")}.`] };
    }
    const addons = names ? selectAddons(all, names) : all.filter((addon) => !isDevOnly(addon));
    for (const addon of addons) {
        if (isDevOnly(addon)) errors.push(`${addon.name} is ## X-DevOnly and never ships.`);
    }
    // A shipped addon whose dependency stays behind wouldn't load for the player.
    const shipped = new Set(addons.map((addon) => addon.name));
    for (const addon of addons) {
        for (const dependency of addon.dependencies) {
            if (!shipped.has(dependency)) errors.push(`${addon.name} depends on ${dependency}, which the package leaves out.`);
        }
    }
    const needed = new Set(addons.flatMap((addon) => addon.dependencies));
    const tops = addons.filter((addon) => !needed.has(addon.name));
    if (tops.length !== 1) {
        errors.push(`The package needs one addon nothing else in it depends on, to name it; found ${tops.map((addon) => addon.name).join(", ") || "none"}.`);
    }
    const trackedSet = new Set(tracked);
    for (const addon of addons) {
        const files = [addon.tocFile, ...addon.files].map((file) => `${addon.name}/${toPosix(file)}`);
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

// An addon's shipped version: X.Y.Z when tag (HEAD's, or null) is exactly vX.Y.Z, else its TOC's
// ## Version (tocVersion) plus -dev+<commit>; null when there's neither a tag nor a ## Version.
export function releaseVersion(tag, tocVersion, commit) {
    const release = RELEASE_TAG.exec(tag ?? "")?.[1];
    if (release) return release;
    return tocVersion ? `${tocVersion}-dev+${commit}` : null;
}

// A TOC's text with its ## Version line set to version (added after the last leading ## line
// when there's none). Every other line stays as it is.
export function stampVersion(text, version) {
    const lines = text.split("\n");
    const at = lines.findIndex((line) => /^##\s*Version\s*:/.test(line));
    if (at >= 0) {
        lines[at] = `## Version: ${version}`;
    } else {
        let last = -1;
        while (last + 1 < lines.length && /^##/.test(lines[last + 1])) last++;
        lines.splice(last + 1, 0, `## Version: ${version}`);
    }
    return lines.join("\n");
}

// CHANGELOG.txt: the package's name and version, then each commit subject (newest first) since
// the previous release tag (since, or null for every commit).
export function changelogText({ name, version, since, subjects }) {
    const heading = since ? `Changes since ${since}:` : "Changes:";
    const items = subjects.length ? subjects.map((subject) => `- ${subject}`) : ["- No changes."];
    return [`${name} ${version}`, "", heading, ...items, ""].join("\n");
}

// HEAD's release tag (git describe --tags --exact-match), or null.
export function headTag() {
    const tag = gitOrNull(["describe", "--tags", "--exact-match", "--match", TAG_GLOB, "HEAD"]);
    return RELEASE_TAG.test(tag ?? "") ? tag : null;
}

// The release tag before HEAD: before HEAD's own when tagged is true. null when there's none.
export function previousTag(tagged) {
    return gitOrNull(["describe", "--tags", "--abbrev=0", "--match", TAG_GLOB, tagged ? "HEAD^" : "HEAD"]);
}

// The non-merge commit subjects after since (a tag, or null for all) up to HEAD, newest first.
export function commitSubjects(since) {
    return git(["log", "--no-merges", "--format=%s", since ? `${since}..HEAD` : "HEAD"]).split("\n").filter(Boolean);
}

// Every committed file under the given folders at HEAD: [{ path, data }] (data a Buffer).
function committedFiles(folders) {
    const blobs = git(["ls-tree", "-r", "-z", "HEAD", "--", ...folders]).split("\0").filter(Boolean)
        .map((line) => /^\d+ (\w+) ([0-9a-f]+)\t(.*)$/s.exec(line))
        .filter((match) => match && match[1] === "blob")
        .map((match) => ({ sha: match[2], path: match[3] }));
    const out = spawnSync("git", ["cat-file", "--batch"], {
        cwd: repoRoot, input: blobs.map((blob) => blob.sha).join("\n") + "\n", maxBuffer: 256 * 1024 * 1024,
    });
    if (out.status !== 0) throw new Error(`git cat-file --batch: ${String(out.stderr).trim()}`);
    const bytes = out.stdout;
    let at = 0;
    return blobs.map((blob) => {
        const headerEnd = bytes.indexOf(0x0a, at);
        const size = Number(bytes.toString("utf8", at, headerEnd).split(" ")[2]);
        const data = bytes.subarray(headerEnd + 1, headerEnd + 1 + size);
        at = headerEnd + 1 + size + 1;
        return { path: blob.path, data: Buffer.from(data) };
    });
}

// The zip's bytes and name for a plan (planPackage) at HEAD: each shipped addon's committed
// folder with its TOC's ## Version stamped, plus <name>/CHANGELOG.txt. { bytes, file, version }.
export function buildPackage(plan, { tag = headTag(), commit = git(["rev-parse", "--short", "HEAD"]).trim() } = {}) {
    const version = releaseVersion(tag, plan.version, commit);
    const tocs = new Map(plan.addons.map((addon) => [`${addon.name}/${addon.tocFile}`, releaseVersion(tag, addon.metadata.Version, commit)]));
    const files = committedFiles(plan.addons.map((addon) => addon.name)).map((file) => {
        const stamped = tocs.get(file.path);
        return stamped ? { path: file.path, data: Buffer.from(stampVersion(file.data.toString("utf8"), stamped), "utf8") } : file;
    });
    const since = previousTag(Boolean(tag));
    const changelog = `${plan.name}/CHANGELOG.txt`;
    const entries = [...files.filter((file) => file.path !== changelog),
        { path: changelog, data: changelogText({ name: plan.name, version, since, subjects: commitSubjects(since) }) }];
    const date = new Date(Number(git(["log", "-1", "--format=%ct", "HEAD"]).trim()) * 1000);
    return { bytes: writeZip(entries, date), file: `${plan.name}-${version}.zip`, version };
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

    const built = buildPackage(plan);
    mkdirSync(DIST, { recursive: true });
    const path = join(DIST, built.file);
    rmSync(path, { force: true });
    writeFileSync(path, built.bytes);
    const commit = git(["rev-parse", "--short", "HEAD"]).trim();
    console.log(`Packaged ${plan.addons.map((addon) => addon.name).join(", ")} ${built.version} at ${commit} -> ${path}`);
    return 0;
}
