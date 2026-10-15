// The CLI's own tests: tools/tlk.mjs refuses to run on a missing or stale node_modules, saying to
// run `npm ci`, and the harness loader runs every file in tests/harness.

import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { staleDependencies } from "../tools/lib/dependencies.mjs";
import { HARNESS_FILES } from "../tools/lib/harness.mjs";
import { repoRoot } from "../tools/lib/repo.mjs";
import { assert, withTemp } from "../tools/lib/test-support.mjs";

const lock = (packages) => JSON.stringify({ lockfileVersion: 3, packages: { "": { name: "x" }, ...packages } });

function install(root, name, version) {
    mkdirSync(join(root, "node_modules", name), { recursive: true });
    writeFileSync(join(root, "node_modules", name, "package.json"), JSON.stringify({ name, version }));
}

export const tests = [
    {
        name: "node_modules is stale when a locked package is missing or at another version",
        run: async () => withTemp(async (dir) => {
            writeFileSync(join(dir, "package-lock.json"), lock({
                "node_modules/luaparse": { version: "0.3.1", dev: true },
                "node_modules/@types/emscripten": { version: "1.41.6", dev: true },
                "node_modules/fsevents": { version: "2.3.3", optional: true },
            }));
            const missing = staleDependencies(dir);
            assert(missing.join(" | ") === "luaparse: not installed | @types/emscripten: not installed", missing.join(" | "));
            install(dir, "luaparse", "0.3.0");
            install(dir, "@types/emscripten", "1.41.6");
            assert(staleDependencies(dir).join(" | ") === "luaparse: 0.3.0 installed, 0.3.1 locked", staleDependencies(dir).join(" | "));
            install(dir, "luaparse", "0.3.1");
            assert(staleDependencies(dir).length === 0, "an optional package may be absent");
            assert(staleDependencies(repoRoot).length === 0, `this checkout's install: ${staleDependencies(repoRoot).join("; ")}`);
        }),
    },
    {
        // A copy of the CLI's entry with this repository's lockfile and no node_modules.
        name: "tlk says to run npm ci, instead of crashing, when node_modules is missing",
        run: async () => withTemp(async (dir) => {
            mkdirSync(join(dir, "tools", "lib"), { recursive: true });
            for (const file of ["tlk.mjs", "lib/dependencies.mjs", "lib/repo.mjs"]) {
                copyFileSync(join(repoRoot, "tools", file), join(dir, "tools", file));
            }
            copyFileSync(join(repoRoot, "package-lock.json"), join(dir, "package-lock.json"));
            const run = spawnSync(process.execPath, [join(dir, "tools", "tlk.mjs"), "check"], { encoding: "utf8", cwd: dir });
            assert(run.status === 2, `exits 2 (got ${run.status}): ${run.stderr}`);
            assert(run.stderr.includes("Run `npm ci`") && run.stderr.includes("luaparse: not installed"), run.stderr);
            assert(!run.stderr.includes("ERR_MODULE_NOT_FOUND"), run.stderr);
        }),
    },
    {
        name: "the harness loader lists exactly the files in tests/harness",
        run: async () => {
            const onDisk = readdirSync(join(repoRoot, "tests", "harness")).filter((f) => f.endsWith(".lua")).sort();
            const listed = [...HARNESS_FILES].sort();
            assert(new Set(HARNESS_FILES).size === HARNESS_FILES.length, `listed twice: ${HARNESS_FILES.join(", ")}`);
            assert(listed.join(",") === onDisk.join(","), `HARNESS_FILES: ${listed.join(", ")}; tests/harness: ${onDisk.join(", ")}`);
        },
    },
];
