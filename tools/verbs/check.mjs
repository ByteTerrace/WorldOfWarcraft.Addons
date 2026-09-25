// Static gates over every addon. Each finding is `path:line: RULE message`; any finding fails.
//
//   PARSE     every .lua parses as Lua 5.1.
//   TOC       the TOC lists every .lua in the addon folder and only files that exist; every
//             dependency (## Dependencies, ## RequiredDeps, ## Dep*) is an addon here; ## Interface
//             (a comma-separated list) includes the installed Forever client's; a top-level folder
//             with a .toc but no <Name>_Camelot.toc is reported (the client won't load it).
//   GLOBAL    a global read names something the client dump or a loaded addon defines (also via
//             _G.X, getfenv().X and getglobal("X")). A global write is declared: SavedVariables,
//             SavedVariablesPerCharacter, AddonCompartmentFunc, SLASH_*, or ## X-Globals; that
//             covers `X = `, `_G.X = `, `_G["X"] = `, getfenv() indexing, rawset(_G, "X", v) and
//             setglobal("X", v). A write with a dynamic key, getfenv(level) for a level other than
//             0 or 1, setfenv and loadstring/load need `-- global: <why>`. Assigning into a client
//             global's members (`string.trimall = `, `C_GamePad.X = `) is a finding (the
//             SlashCmdList and StaticPopupDialogs registries excepted), and so is a CreateFrame
//             name literal that collides with a client global.
//   MEMBER    every static member chain rooted at a client global exists in the snapshot, through
//             local aliases and string-literal indexes: C_GamePad.SetVibration, Enum.PowerType.Energy.
//   EVENT     an event name passed to On / RegisterEvent / RegisterUnitEvent / Fire / ... is a real
//             event, whether a literal or a file-level constant local.
//   SECRET    a call to a function that can return a secret is annotated `-- secret: <why>`, sits
//             directly inside issecretvalue(...), or assigns its results to fresh locals, never
//             reassigned, each of whose uses a guard dominates (tools/lib/lua-flow.mjs): an
//             issecretvalue(x) test whose branch returns, a `not issecretvalue(x)` branch, the
//             short-circuit side of `issecretvalue(x) or ...`, or canaccessvalue(x). Passing such a
//             function as a value (pcall(UnitHealth, ...), t.f = UnitHealth, a reassigned alias)
//             needs the annotation too. A widget getter (obj:M() or obj.M(...), or obj.M as a
//             value) counts when its file calls a setter that can give that aspect a secret for
//             tainted code; an anchoring getter (GetWidth, GetStringHeight, ...) when the file
//             calls any such setter, since any secret aspect can make anchoring secret. So a file
//             that never feeds secrets to widgets can read its frames' sizes and ids. In a handler
//             passed as a function literal to On / RegisterEvent / SetScript("OnEvent"), a
//             parameter carrying a non-unit field of a secret-flagged event's payload can't be
//             compared, computed with, indexed, called or branched on without such a guard.
//   PROTECTED a call to a protected or restricted function (IsProtectedFunction / HasRestrictions,
//             and Blizzard Lua wrappers of them such as Settings.OpenToCategory), a HasRestrictions
//             method on any receiver, or a protected method on a frame from a Secure template
//             (followed through locals, aliases and fields; in a file that creates a Secure frame,
//             any receiver not proven non-Secure) is dominated by an InCombatLockdown() test whose
//             branch returns, sits in a `not InCombatLockdown()` branch, or is annotated
//             `-- protected: <why>`. A closure doesn't inherit its definer's guard.
//
//   An annotation is a `--` line comment on the construct's line, or alone on the line above.
//   Not seen: dynamic reads (_G[k]), values that cross files or function calls, and handlers
//   that aren't function literals. Guards are per function and don't flow out of loops.
//   NAMING    Puck's C# naming, mapped to Lua (docs/Conventions.md): file-level locals (top level,
//             or in a top-level `do` block) and every function or method are PascalCase (constants
//             too: MaxQueue, never MAX_QUEUE), including a local declared ahead and given a function
//             later; locals inside functions, loops and branches, parameters and loop variables are
//             camelCase. An alias keeps the name of what it aliases (local floor = math.floor),
//             `local addonName, ns = ...` is exempt, and so are metamethods (__index).
//   COMMENT   no banner dividers (four or more of - = * # _ ~) and no debt markers (TODO, FIXME,
//             HACK, XXX, KLUDGE, REVISIT in capitals, or "for now"), as Puck's comment-smell gate.
//   LENGTH    no file exceeds MAX_LINES.
//   STYLE     LF line endings, final newline, no tabs, no trailing whitespace.
//
// Snapshot truth: when the snapshot has a client dump, a global or member counts as known only if
// the dump has it; documented-only names don't. Without a dump, the documented API is the fallback.

import { checkStyleRules } from "../lib/check-style.mjs";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { checkLua } from "../lib/check-lua.mjs";
import { findAddons, findMisnamedAddons, repoRoot, splitList, toPosix } from "../lib/repo.mjs";
import { DEFAULT_WOW_ROOT, findForeverInstall } from "../lib/wow.mjs";

export const options = {
    quiet: { type: "boolean", default: false },
    "wow-root": { type: "string", default: DEFAULT_WOW_ROOT },
};

const MAX_LINES = 800;
// Blizzard Lua functions that call a restricted C function (Blizzard_Settings.lua).
const RESTRICTED_WRAPPERS = { "Settings.OpenToCategory": "C_SettingsUtil.OpenSettingsPanel" };

export function loadApi(path = join(repoRoot, "tools", "api", "forever.json")) {
    const snapshot = JSON.parse(readFileSync(path, "utf8"));
    const hasDump = Object.keys(snapshot.globals ?? {}).length > 0;
    const globals = new Set();
    const members = new Map();
    const addMembers = (table, keys) => {
        const set = members.get(table) ?? new Set();
        for (const key of keys) set.add(key);
        members.set(table, set);
    };
    if (hasDump) {
        for (const name of Object.keys(snapshot.globals)) globals.add(name);
        for (const [table, keys] of Object.entries(snapshot.members ?? {})) addMembers(table, keys);
    } else {
        for (const name of Object.keys(snapshot.functions)) {
            const dot = name.indexOf(".");
            if (dot < 0) globals.add(name);
            else {
                globals.add(name.slice(0, dot));
                addMembers(name.slice(0, dot), [name.slice(dot + 1)]);
            }
        }
        globals.add("Enum");
        addMembers("Enum", Object.keys(snapshot.enums ?? {}));
    }
    // Documented enumerations stand in for Enum.X members the dump didn't record.
    for (const [name, fields] of Object.entries(snapshot.enums ?? {})) {
        if (members.get("Enum")?.has(name) && !members.has(`Enum.${name}`)) addMembers(`Enum.${name}`, Object.keys(fields));
    }
    // Per method name (across widget APIs): its secret flags (anchoring kept apart), the aspects
    // its returns follow, whether it's protected or restricted; and the aspects each setter can
    // make secret for tainted code (SecretArguments "AllowedWhenTainted" + SecretArgumentsAddAspect).
    const methodSecrets = new Map();
    const aspectSetters = new Map();
    const protectedMethods = new Set();
    const restrictedMethods = new Set();
    for (const entries of Object.values(snapshot.methods)) {
        for (const [method, entry] of Object.entries(entries)) {
            const flags = (entry.secret ?? []).filter((flag) => flag !== "SecretWhenAnchoringSecret");
            const anchoring = (entry.secret ?? []).includes("SecretWhenAnchoringSecret");
            if (flags.length || anchoring || entry.SecretReturnsForAspect?.length) {
                const info = methodSecrets.get(method) ?? { flags: new Set(), anchoring: false, aspects: new Set() };
                for (const flag of flags) info.flags.add(flag);
                info.anchoring ||= anchoring;
                for (const aspect of entry.SecretReturnsForAspect ?? []) info.aspects.add(aspect);
                methodSecrets.set(method, info);
            }
            if (entry.SecretArguments === "AllowedWhenTainted" && entry.SecretArgumentsAddAspect?.length) {
                const set = aspectSetters.get(method) ?? new Set();
                for (const aspect of entry.SecretArgumentsAddAspect) set.add(aspect);
                aspectSetters.set(method, set);
            }
            if (entry.IsProtectedFunction) protectedMethods.add(method);
            if (entry.HasRestrictions) restrictedMethods.add(method);
        }
    }
    const protectedFunctions = new Map();
    for (const [name, entry] of Object.entries(snapshot.functions)) {
        if (entry.IsProtectedFunction) protectedFunctions.set(name, "IsProtectedFunction");
        else if (entry.HasRestrictions) protectedFunctions.set(name, "HasRestrictions");
    }
    for (const [wrapper, target] of Object.entries(RESTRICTED_WRAPPERS)) protectedFunctions.set(wrapper, `calls ${target}`);
    return {
        hasDump, globals, members, functions: snapshot.functions, events: new Set(Object.keys(snapshot.events)),
        eventEntries: snapshot.events, methodSecrets, aspectSetters, protectedMethods, restrictedMethods, protectedFunctions,
    };
}

function checkStyle(text, file, report) {
    if (text.includes("\r")) report(file, 1, "STYLE", "CRLF line endings (LF only)");
    if (text.length && !text.endsWith("\n")) report(file, text.split("\n").length, "STYLE", "missing final newline");
    text.split("\n").forEach((line, i) => {
        if (line.includes("\t")) report(file, i + 1, "STYLE", "tab character");
        if (/[ \t]+$/.test(line)) report(file, i + 1, "STYLE", "trailing whitespace");
    });
    const lines = text.split("\n").length - 1;
    if (lines > MAX_LINES) report(file, MAX_LINES, "LENGTH", `${lines} lines exceeds ${MAX_LINES}`);
}

// Returns the findings (empty when every gate passes). root and clientInterface exist for the
// gate's own tests, which run it over fixture addons; wowRoot is the install to read the client
// interface from (deploy passes its --wow-root).
export async function runChecks({ quiet = false, root = repoRoot, clientInterface, wowRoot = DEFAULT_WOW_ROOT, apiPath } = {}) {
    const findings = [];
    const report = (file, line, rule, message) => findings.push(`${toPosix(relative(root, file))}:${line}: ${rule} ${message}`);
    const api = loadApi(apiPath);
    const addons = findAddons(root);
    const byName = new Map(addons.map((addon) => [addon.name, addon]));

    if (clientInterface === undefined) {
        try {
            clientInterface = findForeverInstall(wowRoot).interface;
        } catch {
            clientInterface = null;
        }
    }
    if (clientInterface === null && !quiet) console.log("Interface check skipped (no client found)");

    for (const name of findMisnamedAddons(root)) {
        const toc = readdirSync(join(root, name)).find((f) => f.toLowerCase().endsWith(".toc"));
        report(join(root, name, toc), 1, "TOC", `${name} has no ${name}_Camelot.toc, so the Forever client won't load it`);
    }

    const exported = new Map(addons.map((addon) => [addon.name, splitList(addon.metadata["X-Globals"])]));
    const addonOwned = new Set();
    for (const addon of addons) {
        for (const name of [...addon.savedVariables, ...exported.get(addon.name)]) addonOwned.add(name);
        if (addon.metadata.AddonCompartmentFunc) addonOwned.add(addon.metadata.AddonCompartmentFunc);
    }
    const clientGlobal = (name) => api.globals.has(name) && !addonOwned.has(name);

    for (const addon of addons) {
        const { dir, tocPath, metadata, files, dependencies } = addon;
        checkStyle(readFileSync(tocPath, "utf8"), tocPath, report);
        const interfaces = splitList(metadata.Interface).map(Number);
        if (clientInterface && !interfaces.includes(clientInterface)) {
            report(tocPath, 1, "TOC", `## Interface ${metadata.Interface} but the installed client is ${clientInterface}`);
        }
        for (const dependency of dependencies) {
            if (!byName.has(dependency)) report(tocPath, 1, "TOC", `dependency ${dependency} is not an addon in this repository`);
        }
        const onDisk = readdirSync(dir, { recursive: true }).map(toPosix).filter((f) => f.endsWith(".lua"));
        for (const file of files) {
            if (!existsSync(join(dir, file))) report(tocPath, 1, "TOC", `lists ${file}, which does not exist`);
        }
        for (const file of onDisk) {
            if (!files.includes(file)) report(join(dir, file), 1, "TOC", `not listed in ${addon.name}_Camelot.toc`);
        }

        const allowedWrites = new Set([...addon.savedVariables, ...exported.get(addon.name)]);
        if (metadata.AddonCompartmentFunc) allowedWrites.add(metadata.AddonCompartmentFunc);
        const known = new Set([...api.globals, ...allowedWrites]);
        for (const dependency of dependencies) for (const name of exported.get(dependency) ?? []) known.add(name);

        const writes = [];
        for (const file of files.filter((f) => f.endsWith(".lua") && existsSync(join(dir, f)))) {
            const path = join(dir, file);
            const text = readFileSync(path, "utf8");
            checkStyle(text, path, report);
            checkLua(path, text, { api, known, clientGlobal, writes }, report);
            checkStyleRules(path, text, report);
        }
        for (const write of writes) {
            if (!allowedWrites.has(write.name) && !write.name.startsWith("SLASH_")) {
                report(write.file, write.line, "GLOBAL", `write to undeclared global ${write.name} (declare it in ## X-Globals)`);
            }
        }
    }

    if (root === repoRoot) {
        for (const dir of ["tools", "tests"]) {
            for (const file of readdirSync(join(root, dir), { recursive: true }).map(toPosix)) {
                const skip = file.startsWith("api/") || file.startsWith("fixtures/");
                if (/\.(mjs|lua|json)$/.test(file) && !skip) checkStyle(readFileSync(join(root, dir, file), "utf8"), join(root, dir, file), report);
            }
        }
    }

    if (!quiet) {
        for (const finding of findings) console.log(finding);
        console.log(findings.length ? `${findings.length} finding(s)` : `check passed (${addons.length} addons)`);
    }
    return findings;
}

export async function run(values) {
    return (await runChecks({ quiet: values.quiet, wowRoot: values["wow-root"] })).length === 0 ? 0 : 1;
}
