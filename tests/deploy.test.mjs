// deploy's and package's own tests. Link handling is tested as pure functions over paths, and
// end to end only against an AddOns folder in a temporary directory, never the real install.

import { existsSync, mkdirSync, rmSync, symlinkSync } from "node:fs";
import { dirname, join } from "node:path";
import { repoRoot } from "../tools/lib/repo.mjs";
import { FIXTURES, assert, tlk, withTemp } from "../tools/lib/test-support.mjs";
import { classifyLink, compareTargets, normalizeTarget, parseWorktrees, selectAddons } from "../tools/verbs/deploy.mjs";
import { planPackage } from "../tools/verbs/package.mjs";

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
        // The addon in another worktree is this repo's own; another addon's folder, or a folder
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
            const addon = (name, dependencies = [], metadata = {}) =>
                ({ name, dependencies, files: ["Main.lua"], metadata: { Version: "1.2.0", ...metadata } });
            const all = [addon("Core"), addon("Kit", ["Core"]), addon("Dev", [], { "X-DevOnly": "true" })];
            const tracked = ["Core/Core_Camelot.toc", "Core/Main.lua", "Kit/Kit_Camelot.toc", "Kit/Main.lua", "Dev/Dev_Camelot.toc", "Dev/Main.lua"];
            const names = (plan) => plan.addons.map((a) => a.name).sort().join(",");
            const plan = planPackage(all, undefined, tracked, []);
            assert(plan.errors.length === 0, plan.errors.join("; "));
            assert(names(plan) === "Core,Kit" && plan.name === "Kit" && plan.version === "1.2.0", `${names(plan)} ${plan.name} ${plan.version}`);
            assert(names(planPackage(all, ["Kit"], tracked, [])) === "Core,Kit", "--addon brings its dependencies");
            const errors = (names, tracked, dirty) => planPackage(all, names, tracked, dirty).errors.join(" | ");
            assert(errors(["Dev"], tracked, []).includes("Dev is ## X-DevOnly"), "a dev-only addon never ships");
            assert(errors(["Nope"], tracked, []).includes("Unknown addon(s): Nope"), "unknown names");
            assert(errors(undefined, tracked.filter((f) => f !== "Kit/Main.lua"), []).includes("Kit/Main.lua is listed in the TOC but not committed"), "uncommitted TOC file");
            assert(errors(undefined, tracked, ["Core/Main.lua"]).includes("Core/Main.lua has uncommitted changes"), "dirty shipped folder");
            assert(errors(undefined, tracked, ["Dev/Main.lua"]) === "", "a dirty dev folder doesn't matter");
            const withDev = [addon("Lib", [], { "X-DevOnly": "" }), addon("App", ["Lib"])];
            const devErrors = planPackage(withDev, undefined, ["Lib/Lib_Camelot.toc", "Lib/Main.lua", "App/App_Camelot.toc", "App/Main.lua"], []).errors.join(" | ");
            assert(devErrors.includes("App depends on Lib, which the package leaves out"), `a bare X-DevOnly still keeps Lib out, and App can't ship without it: ${devErrors}`);
            all.push(addon("Other"));
            assert(errors(undefined, tracked.concat("Other/Other_Camelot.toc", "Other/Main.lua"), []).includes("one addon nothing else in it depends on"), "two tops can't name it");
        },
    },
];
