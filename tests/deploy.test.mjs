// deploy's and package's own tests. Link handling is tested as pure functions over paths, and
// end to end only against an AddOns folder in a temporary directory, never the real install.
// package's versions, changelog, and zip are pure functions, and its build reads HEAD without
// writing anywhere.

import { existsSync, mkdirSync, readFileSync, rmSync, symlinkSync } from "node:fs";
import { dirname, join } from "node:path";
import { findAddons, repoRoot } from "../tools/lib/repo.mjs";
import { FIXTURES, assert, tlk, withTemp } from "../tools/lib/test-support.mjs";
import { crc32, readZip, writeZip } from "../tools/lib/zip.mjs";
import { classifyLink, compareTargets, normalizeTarget, parseWorktrees, selectAddons } from "../tools/verbs/deploy.mjs";
import { buildPackage, changelogText, planPackage, releaseVersion, stampVersion } from "../tools/verbs/package.mjs";

const ADDON = "TheLanKrewToolKit";

export const tests = [
    {
        name: "deploy refuses an unknown addon name",
        run: async () => {
            const result = tlk(["deploy", "--addon", "NoSuchAddon", "--flavor", "_none_", "--wow-root", join(FIXTURES, "no-such-install")]);
            assert(result.status === 1 && result.stderr.includes("Unknown addon(s): NoSuchAddon"), `${result.status} ${result.stderr}`);
        },
    },
    {
        name: "deploy selects transitive dependencies regardless of directory order, but unlink stays exact",
        run() {
            const all = [
                { name: "Foundation", dependencies: [] },
                { name: "Shared", dependencies: ["Foundation"] },
                { name: "Toolkit", dependencies: ["Shared"] },
                { name: "Unrelated", dependencies: [] },
            ];
            const names = (addons) => addons.map((addon) => addon.name).sort().join(",");
            assert(names(selectAddons(all, ["Toolkit"])) === "Foundation,Shared,Toolkit", "the full dependency chain");
            assert(names(selectAddons(all, ["Toolkit"], false)) === "Toolkit", "unlink doesn't remove shared dependencies");
            all[0].dependencies.push("Toolkit");
            assert(names(selectAddons(all, ["Toolkit"])) === "Foundation,Shared,Toolkit", "cycles terminate");
        },
    },
    {
        name: "deploy normalizes link targets before comparing them",
        run: async () => {
            const link = join(repoRoot, "links", "Addon");
            assert(normalizeTarget("\\\\?\\" + join(repoRoot, "Addon") + "\\", link) === join(repoRoot, "Addon"), "\\\\?\\ prefix and trailing separator");
            assert(normalizeTarget(join("..", "Addon"), link) === join(repoRoot, "Addon"), "relative to the link's folder");
            assert(compareTargets(join(repoRoot, "Addon"), join(repoRoot, "Addon") + "/") === "same", "trailing separator");
            assert(compareTargets(join(repoRoot, "addon"), join(repoRoot, "Addon"), "win32") === "case", "case-only difference on Windows");
            assert(compareTargets(join(repoRoot, "addon"), join(repoRoot, "Addon"), "linux") === "other", "case matters elsewhere");
            assert(compareTargets(join(repoRoot, "Other"), join(repoRoot, "Addon")) === "other", "elsewhere");
        },
    },
    {
        name: "deploy reads this repository's worktrees from git's porcelain list, leaving out bare ones",
        run: async () => {
            const main = join(repoRoot, "..", "main");
            const feature = join(repoRoot, "..", "feature");
            const porcelain = [
                `worktree ${main.replaceAll("\\", "/")}`, "HEAD 1111111111111111111111111111111111111111", "branch refs/heads/main", "",
                `worktree ${feature.replaceAll("\\", "/")}`, "HEAD 2222222222222222222222222222222222222222", "branch refs/heads/feature", "prunable gitdir file points to non-existent location", "",
                `worktree ${join(repoRoot, "..", "bare.git").replaceAll("\\", "/")}`, "bare", "",
            ].join("\n");
            const roots = parseWorktrees(porcelain);
            assert(roots.join("|") === [main, feature].join("|"), roots.join("|"));
            assert(parseWorktrees("").length === 0, "no git output, no worktrees");
        },
    },
    {
        // The addon in another worktree is this repo's own. Another addon's folder, or a folder
        // outside every worktree, isn't. A dangling link beside or inside a worktree was one.
        name: "deploy treats a link to the same addon in any worktree of this repository as its own",
        run: async () => {
            const main = join(repoRoot, "..", "main");
            const here = join(main, ".claude", "worktrees", "here");
            const other = join(main, ".claude", "worktrees", "other");
            const worktrees = [main, here, other];
            const expected = join(here, ADDON);
            const kind = (target, options) => classifyLink(target, expected, worktrees, options);
            assert(kind(expected).kind === "same", "this checkout");
            assert(kind(join(here, ADDON.toLowerCase()), { platform: "win32" }).kind === "case", "case only");
            const elsewhere = kind(join(other, ADDON));
            assert(elsewhere.kind === "worktree" && elsewhere.worktree === other && !elsewhere.removed, JSON.stringify(elsewhere));
            assert(kind(join(main, ADDON)).worktree === main, "the main worktree");
            assert(kind(join(other, "ByteTerrace_Core")).kind === "other", "another addon's folder");
            assert(kind(join(repoRoot, "..", "..", "elsewhere", ADDON)).kind === "other", "outside every worktree");
            const gone = join(main, ".claude", "worktrees", "gone", ADDON);
            assert(kind(gone).kind === "other", "a live link into an unlisted folder is someone else's");
            const removed = kind(gone, { dangling: true });
            assert(removed.kind === "worktree" && removed.removed && removed.worktree === dirname(gone), JSON.stringify(removed));
            assert(kind(join(dirname(main), "sibling", ADDON), { dangling: true }).removed, "beside a worktree");
            assert(kind(join(repoRoot, "..", "..", "elsewhere", ADDON), { dangling: true }).kind === "other", "dangling, but nowhere near");
        },
    },
    {
        name: "deploy --unlink removes this repo's links in a temporary AddOns folder and leaves the rest",
        run: async () => withTemp(async (dir) => {
            const addOns = join(dir, "_test_", "Interface", "AddOns");
            mkdirSync(addOns, { recursive: true });
            symlinkSync(join(repoRoot, ADDON), join(addOns, ADDON), "junction");
            const foreign = join(dir, "elsewhere", "ByteTerrace_Core");
            mkdirSync(foreign, { recursive: true });
            symlinkSync(foreign, join(addOns, "ByteTerrace_Core"), "junction");
            rmSync(foreign, { recursive: true });
            // A worktree since removed, inside this checkout: the link dangles.
            const gone = join(repoRoot, ".tlk-test-removed-worktree", "ByteTerrace_DevTools");
            mkdirSync(gone, { recursive: true });
            symlinkSync(gone, join(addOns, "ByteTerrace_DevTools"), "junction");
            rmSync(dirname(gone), { recursive: true });
            const run = tlk(["deploy", "--unlink", "--flavor", "_test_", "--wow-root", dir]);
            assert(run.status === 0, `${run.status} ${run.stdout} ${run.stderr}`);
            assert(run.stdout.includes(`Unlinked ${ADDON}\n`) && !existsSync(join(addOns, ADDON)), run.stdout);
            assert(existsSync(join(repoRoot, ADDON, `${ADDON}_Camelot.toc`)), "the repo's files stay");
            assert(run.stdout.includes(`Unlinked ByteTerrace_DevTools: linked to ${gone} (dangling), in a removed worktree, ${dirname(gone)}`), run.stdout);
            assert(run.stdout.includes(`Skipped  ByteTerrace_Core: links to ${foreign}, not this repo`), run.stdout);
        }),
    },
    {
        name: "package ships the committed, non-dev addons, named after the one nothing depends on",
        run() {
            const addon = (name, dependencies = [], metadata = {}, tocFile = `${name}_Camelot.toc`) =>
                ({ name, dependencies, tocFile, files: ["Main.lua"], metadata: { Version: "1.2.0", ...metadata } });
            const all = [addon("Core", [], {}, "Core_Forever.toc"), addon("Kit", ["Core"]), addon("Dev", [], { "X-DevOnly": "true" })];
            const tracked = ["Core/Core_Forever.toc", "Core/Main.lua", "Kit/Kit_Camelot.toc", "Kit/Main.lua", "Dev/Dev_Camelot.toc", "Dev/Main.lua"];
            const names = (plan) => plan.addons.map((a) => a.name).sort().join(",");
            const plan = planPackage(all, undefined, tracked, []);
            assert(plan.errors.length === 0, plan.errors.join("; "));
            assert(names(plan) === "Core,Kit" && plan.name === "Kit" && plan.version === "1.2.0", `${names(plan)} ${plan.name} ${plan.version}`);
            assert(names(planPackage(all, ["Kit"], tracked, [])) === "Core,Kit", "--addon brings its dependencies");
            const errors = (names, tracked, dirty) => planPackage(all, names, tracked, dirty).errors.join(" | ");
            assert(errors(["Dev"], tracked, []).includes("Dev is ## X-DevOnly"), "a dev-only addon never ships");
            assert(errors(["Nope"], tracked, []).includes("Unknown addon(s): Nope"), "unknown names");
            assert(errors(undefined, tracked.filter((f) => f !== "Kit/Main.lua"), []).includes("Kit/Main.lua is listed in the TOC but not committed"), "uncommitted TOC file");
            assert(errors(undefined, tracked.filter((f) => f !== "Core/Core_Forever.toc"), []).includes("Core/Core_Forever.toc is listed in the TOC but not committed"),
                "the TOC itself, under its own suffix");
            assert(errors(undefined, tracked, ["Core/Main.lua"]).includes("Core/Main.lua has uncommitted changes"), "dirty shipped folder");
            assert(errors(undefined, tracked, ["Dev/Main.lua"]) === "", "a dirty dev folder doesn't matter");
            const withDev = [addon("Lib", [], { "X-DevOnly": "" }), addon("App", ["Lib"])];
            const devErrors = planPackage(withDev, undefined, ["Lib/Lib_Camelot.toc", "Lib/Main.lua", "App/App_Camelot.toc", "App/Main.lua"], []).errors.join(" | ");
            assert(devErrors.includes("App depends on Lib, which the package leaves out"), `a bare X-DevOnly still keeps Lib out, and App can't ship without it: ${devErrors}`);
            all.push(addon("Other"));
            assert(errors(undefined, tracked.concat("Other/Other_Camelot.toc", "Other/Main.lua"), []).includes("one addon nothing else in it depends on"), "two tops can't name it");
        },
    },
    {
        name: "package versions a tagged HEAD by its vX.Y.Z tag, and anything else as the TOC's version -dev+<sha>",
        run() {
            assert(releaseVersion("v1.4.2", "0.1.0", "abc1234") === "1.4.2", "the tag wins over the TOC");
            assert(releaseVersion(null, "0.1.0", "abc1234") === "0.1.0-dev+abc1234", "untagged");
            for (const tag of ["v1.4", "1.4.2", "v1.4.2-rc1", "release"]) {
                assert(releaseVersion(tag, "0.1.0", "abc1234") === "0.1.0-dev+abc1234", `${tag} isn't a release tag`);
            }
            assert(releaseVersion("v2.0.0", undefined, "abc1234") === "2.0.0" && releaseVersion(null, undefined, "abc1234") === null, "no ## Version");
            const toc = "## Interface: 16001\n## Title: Kit\n## Version: 0.1.0\n## Notes: v: 1\n\nMain.lua\n";
            assert(stampVersion(toc, "1.4.2") === toc.replace("0.1.0", "1.4.2"), stampVersion(toc, "1.4.2"));
            const bare = "## Interface: 16001\n## Title: Kit\n\nMain.lua\n";
            assert(stampVersion(bare, "1.4.2") === "## Interface: 16001\n## Title: Kit\n## Version: 1.4.2\n\nMain.lua\n", stampVersion(bare, "1.4.2"));
        },
    },
    {
        name: "package's changelog lists the commit subjects since the previous release tag",
        run() {
            const text = changelogText({ name: "Kit", version: "1.4.2", since: "v1.4.1", subjects: ["Fix the bar", "Add a card"] });
            assert(text === "Kit 1.4.2\n\nChanges since v1.4.1:\n- Fix the bar\n- Add a card\n", text);
            assert(changelogText({ name: "Kit", version: "0.1.0-dev+abc1234", since: null, subjects: ["First"] }) === "Kit 0.1.0-dev+abc1234\n\nChanges:\n- First\n", "no earlier tag");
            assert(changelogText({ name: "Kit", version: "1.4.2", since: "v1.4.1", subjects: [] }).endsWith("- No changes.\n"), "nothing since");
        },
    },
    {
        name: "zip archives read back as written, with a directory entry for every folder",
        run() {
            const bytes = writeZip([{ path: "Kit/Kit_Camelot.toc", data: "## Title: Kit\n" }, { path: "Kit/Media/a.ogg", data: Buffer.from([0, 1, 2, 255]) }],
                new Date(Date.UTC(2026, 9, 15, 12, 30, 10)));
            const files = readZip(bytes);
            assert(files.map((file) => file.path).join(",") === "Kit/Kit_Camelot.toc,Kit/Media/a.ogg", files.map((file) => file.path).join(","));
            assert(files[0].data.toString("utf8") === "## Title: Kit\n" && files[1].data.equals(Buffer.from([0, 1, 2, 255])), "contents");
            assert(bytes.includes(Buffer.from("Kit/Media/")), "folder entries");
            assert(writeZip([{ path: "a/b.txt", data: "x" }], new Date(0)).equals(writeZip([{ path: "a/b.txt", data: "x" }], new Date(0))), "deterministic");
            assert(crc32(Buffer.from("123456789")) === 0xcbf43926, "the standard CRC-32 check value");
        },
    },
    {
        // The real repository at HEAD: the version reaches the zipped TOC and never the working tree.
        name: "package stamps the zipped TOCs and adds CHANGELOG.txt, leaving the working tree alone",
        run() {
            const core = findAddons().find((addon) => addon.name === "ByteTerrace_Core");
            const before = readFileSync(core.tocPath);
            const plan = { addons: [core], name: core.name, version: core.metadata.Version };
            for (const [tag, version] of [["v9.8.7", "9.8.7"], [null, `${core.metadata.Version}-dev+abc1234`]]) {
                const built = buildPackage(plan, { tag, commit: "abc1234" });
                assert(built.file === `ByteTerrace_Core-${version}.zip` && built.version === version, built.file);
                const files = new Map(readZip(built.bytes).map((file) => [file.path, file.data.toString("utf8")]));
                const toc = files.get(`ByteTerrace_Core/${core.tocFile}`);
                assert(toc.includes(`\n## Version: ${version}\n`) && !toc.includes(`## Version: ${core.metadata.Version}\n`), toc);
                const changelog = files.get("ByteTerrace_Core/CHANGELOG.txt");
                assert(changelog.startsWith(`ByteTerrace_Core ${version}\n\nChanges`) && changelog.includes("\n- "), changelog);
                assert([...files.keys()].every((path) => path.startsWith("ByteTerrace_Core/")), [...files.keys()].join(","));
            }
            assert(readFileSync(core.tocPath).equals(before), "the working tree's TOC is unchanged");
        },
    },
];
