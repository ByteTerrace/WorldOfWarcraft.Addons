// Static gates over every addon. Each finding is `path:line: RULE message`, and any finding fails. A
// method call counts in each form it takes: obj:M(), and obj.M(obj) or obj["M"](obj) passing its
// receiver first.
//
//   PARSE     every .lua parses as Lua 5.1.
//   TOC       the TOC lists every .lua in the addon folder, once, and only files that exist. Every
//             dependency (## Dependencies, ## RequiredDeps, ## Dep*) is an addon here. ## Interface
//             (a comma-separated list) includes the installed Forever client's, or without an
//             install the one the API snapshot's build implies (1.60.1 is 16001), and check
//             says which it used. An addon's TOC is <Name>_Forever.toc or <Name>_Camelot.toc,
//             since the client loads both suffixes. The tools read _Forever.toc when a folder has
//             both, and a folder with both is reported, since which one the client loads isn't
//             documented. A top-level folder with a .toc but neither is reported, since the client
//             won't load it.
//   GLOBAL    a global read names something the client dump or a loaded addon defines (also through
//             _G.X, getfenv().X, and getglobal("X")). A global write is declared: SavedVariables,
//             SavedVariablesPerCharacter, AddonCompartmentFunc, SLASH_*, or ## X-Globals. That
//             covers `X = `, `_G.X = `, `_G["X"] = `, getfenv() indexing, rawset(_G, "X", v), and
//             setglobal("X", v). A write with a dynamic key, getfenv(level) for a level other than
//             0 or 1, setfenv, and loadstring/load need `-- global: <why>`. Assigning into a client
//             global's members (`string.trimall = `, `C_GamePad.X = `) is a finding (the
//             SlashCmdList and StaticPopupDialogs registries excepted), and so is a CreateFrame
//             name literal that collides with a client global.
//   MEMBER    every static member chain rooted at a client global exists in the snapshot, through
//             local aliases and string-literal indexes: C_GamePad.SetVibration, Enum.PowerType.Energy.
//             So does a client table's method called with `:` (C_GamePad:SetVibration()).
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
//             tainted code. An anchoring getter (GetWidth, GetStringHeight, ...) counts when the
//             file calls any such setter, since any secret aspect can make anchoring secret. So a file
//             that never feeds secrets to widgets can read its frames' sizes and ids. In a handler
//             passed as a function literal to On / RegisterEvent / SetScript("OnEvent") /
//             HookScript("OnEvent"), a parameter carrying a non-unit field of a secret-flagged
//             event's payload (or a local the handler's `...` fills at its top) can't be compared,
//             computed with, indexed, called, or branched on without such a guard. An annotated call
//             assigned to an existing local covers the call, not that local's later uses.
//   PROTECTED a function forbidden to addon code (tools/api/forbidden.json) is never called or taken
//             as a value, and a protected global (IsProtectedFunction) taken as a value needs
//             `-- protected: <why>`, because calls through the value skip the guard. A call to a
//             restricted function (HasRestrictions), a HasRestrictions method on any receiver, or a
//             protected method on a frame from a Secure template is dominated by an
//             InCombatLockdown() test whose branch returns, sits in a `not InCombatLockdown()`
//             branch, or is annotated `-- protected: <why>`. The test counts directly, or through a
//             never-reassigned local of the same function holding its result. A Secure frame is
//             followed through locals, aliases, and fields, and in a file that creates a Secure
//             frame, any receiver not proven non-Secure counts as one. A closure doesn't inherit
//             its definer's guard.
//
//   FRAMEWORK in an addon built on ByteTerrace_Core, no call to a client API the framework owns
//             (C_Timer's timers, addon message sending, logged too, and prefixes, PlaySoundFile,
//             settings and settings-category registration), nor one taken as a value, and no handler
//             for CHAT_MSG_ADDON or CHAT_MSG_ADDON_LOGGED: the framework's versions own their
//             lifetime and the client's rules, and a second implementation is a defect.
//   ARGS      a call to a documented client function (its `Arguments` in the snapshot), directly
//             or through a never-reassigned alias, passes no more arguments than the docs declare
//             and none fewer than the last one they don't mark Nilable or give a Default (a
//             LuaValueReference takes nil). A call whose last argument is a call or `...` passes an
//             unknown count and isn't judged. `:` calls and widget methods aren't judged either,
//             because the gate doesn't know a receiver's widget type and the docs can't state
//             overloads. The snapshot
//             doesn't record repeating arguments (StrideIndex), so a function whose last argument
//             is a LuaValueReference or LuaValueVariant (Mixin, scrub) is judged only before it.
//
//   An annotation is a `--` line comment on the construct's line, or alone on the line above.
//   The gates don't see dynamic reads (_G[k]), values that cross files or function calls, or
//   handlers that aren't function literals. Guards are per function and don't flow out of loops.
//   NAMING    Puck's C# naming, mapped to Lua (docs/Conventions.md): file-level locals (top level,
//             or in a top-level `do` block) and every function or method are PascalCase (constants
//             too: MaxQueue, never MAX_QUEUE), including a local declared ahead and given a function
//             later. Locals inside functions, loops, and branches, along with parameters and loop
//             variables, are camelCase. An alias keeps the name of what it aliases (local floor = math.floor),
//             a file's own `local addonName, ns = ...` is exempt, and so are metamethods (__index).
//   COMMENT   no banner dividers (four or more of - = * # _ ~) and no debt markers (TODO, FIXME,
//             HACK, XXX, KLUDGE, REVISIT in capitals, or "for now"), as Puck's comment-smell gate.
//             Each paragraph of full-line comments is a sentence: a capital letter, a digit, or
//             code first, and . ! ? or : last. Verbatim lines and the gates' annotations are kept
//             as written.
//   HYGIENE   luacheck's warnings, as far as a parser decides them: a local, local function, or loop
//             variable nothing reads (a local function only its own body calls counts as unused);
//             a parameter nothing reads (remove it, or rename it to _ when a later parameter or
//             `...` is read and it keeps its position; callbacks too); a local, parameter, or loop
//             variable that shadows or redefines a visible local of the same file (a callback's
//             `state` may shadow an outer `state`, docs/Conventions.md); a statement after one that
//             always leaves its block (`do return end`, an if whose every branch, else included,
//             returns or breaks); an empty if, elseif, or else branch, do block, or loop body (an empty
//             function is a no-op callback, allowed); and a value assigned to a local that a later
//             statement of the same block overwrites before anything reads it (straight-line code,
//             and only locals no closure references). `_`, names starting with `_`, and a file's own
//             `local addonName, ns = ...` are exempt.
//   FORMAT    every addon's Lua and the tests' Lua is what the format verb writes (Puck's formatter
//             passes, mapped to Lua: docs/Conventions.md#formatting). A finding names the file's
//             first line that would change.
//   LENGTH    no file exceeds MAX_LINES.
//   STYLE     LF line endings, a final newline, no tabs, and no trailing whitespace.
//
//   Beyond the addons, tools/ and tests/ get LENGTH and STYLE. The tests' Lua (tests/*.lua and
//   tests/harness, not the deliberately bad tests/fixtures) also gets NAMING, COMMENT, and HYGIENE,
//   and GLOBAL as the runner's Lua sees it (tools/lib/check-tests.mjs).
//
// Snapshot truth: when the snapshot has a client dump, a global or member counts as known only if
// the dump has it. Documented-only names don't. Without a dump, the documented API is the fallback.

import { checkStyleRules } from "../lib/check-style.mjs";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { checkLua } from "../lib/check-lua.mjs";
import { checkTestGlobals } from "../lib/check-tests.mjs";
import { COVERAGE_LUA } from "../lib/coverage.mjs";
import { PRELUDE } from "../lib/prelude.mjs";
import { findAddons, findAmbiguousAddons, findMisnamedAddons, readForbidden, repoRoot, splitList, toPosix } from "../lib/repo.mjs";
import { DEFAULT_WOW_ROOT, buildOf, findForeverInstall, interfaceOf } from "../lib/wow.mjs";
import { formatFiles, formatRepository } from "./format.mjs";

export const options = {
    quiet: { type: "boolean", default: false },
    "wow-root": { type: "string", default: DEFAULT_WOW_ROOT },
};

const MAX_LINES = 1000;

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
    // its returns follow, whether it's protected or restricted, and the aspects each setter can
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
    // Refused to addon code at any time, so no combat guard helps: IsProtectedFunction globals and
    // what the client refused in game (tools/api/forbidden.json).
    const forbiddenFunctions = new Map();
    for (const [name, entry] of Object.entries(snapshot.functions)) {
        if (entry.IsProtectedFunction) forbiddenFunctions.set(name, "IsProtectedFunction");
        else if (entry.HasRestrictions) protectedFunctions.set(name, "HasRestrictions");
    }
    for (const name of Object.keys(readForbidden())) forbiddenFunctions.set(name, "in-game evidence in tools/api/forbidden.json");
    return {
        build: buildOf(snapshot.source?.globals),
        hasDump, globals, members, functions: snapshot.functions, events: new Set(Object.keys(snapshot.events)),
        eventEntries: snapshot.events, methodSecrets, aspectSetters, protectedMethods, restrictedMethods, protectedFunctions,
        forbiddenFunctions,
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

// The interface every TOC's ## Interface must include, and what it came from: the installed
// client's (wowRoot), else the one the API snapshot's build implies (so the check runs where no
// client is, as in CI), else none. { interface, source, label } or { interface: null, source }.
export function expectedInterface(wowRoot, api) {
    try {
        const install = findForeverInstall(wowRoot);
        return { interface: install.interface, source: `the installed client ${install.version}`, label: "the installed client" };
    } catch {
        const value = api.build ? interfaceOf(api.build) : null;
        if (value === null) return { interface: null, source: "no client found and no build in the API snapshot" };
        return { interface: value, source: `no client found; the API snapshot's build ${api.build}`, label: "the API snapshot's client" };
    }
}

// Returns the findings (empty when every gate passes). root and clientInterface exist for the
// gate's own tests, which run it over fixture addons. wowRoot is the install to read the client
// interface from (deploy passes its --wow-root), and apiPath the API snapshot.
export async function runChecks({ quiet = false, root = repoRoot, clientInterface, wowRoot = DEFAULT_WOW_ROOT, apiPath } = {}) {
    const findings = [];
    const report = (file, line, rule, message) => findings.push(`${toPosix(relative(root, file))}:${line}: ${rule} ${message}`);
    const api = loadApi(apiPath);
    const addons = findAddons(root);
    const byName = new Map(addons.map((addon) => [addon.name, addon]));

    const expected = clientInterface === undefined
        ? expectedInterface(wowRoot, api)
        : { interface: clientInterface, source: "given", label: "the installed client" };
    if (!quiet) {
        console.log(expected.interface === null
            ? `Interface check skipped (${expected.source})`
            : `Interface check against ${expected.interface} (${expected.source})`);
    }

    for (const name of findMisnamedAddons(root)) {
        const toc = readdirSync(join(root, name)).find((f) => f.toLowerCase().endsWith(".toc"));
        report(join(root, name, toc), 1, "TOC", `${name} has no ${name}_Forever.toc or ${name}_Camelot.toc, so the Forever client won't load it`);
    }
    for (const { name, files: [read, ...ignored] } of findAmbiguousAddons(root)) {
        for (const toc of ignored) {
            report(join(root, name, toc), 1, "TOC", `${name} also has ${read}, which the tools read; which one the client loads isn't documented, so keep one`);
        }
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
        if (expected.interface !== null && !interfaces.includes(expected.interface)) {
            report(tocPath, 1, "TOC", `## Interface ${metadata.Interface} but ${expected.label} is ${expected.interface}`);
        }
        for (const dependency of dependencies) {
            if (!byName.has(dependency)) report(tocPath, 1, "TOC", `dependency ${dependency} is not an addon in this repository`);
        }
        const onDisk = readdirSync(dir, { recursive: true }).map(toPosix).filter((f) => f.endsWith(".lua"));
        const listed = new Set();
        for (const file of files) {
            if (listed.has(file)) report(tocPath, 1, "TOC", `lists ${file} twice, so the client would run it twice`);
            else if (!existsSync(join(dir, file))) report(tocPath, 1, "TOC", `lists ${file}, which does not exist`);
            listed.add(file);
        }
        for (const file of onDisk) {
            if (!files.includes(file)) report(join(dir, file), 1, "TOC", `not listed in ${addon.tocFile}`);
        }

        const allowedWrites = new Set([...addon.savedVariables, ...exported.get(addon.name)]);
        if (metadata.AddonCompartmentFunc) allowedWrites.add(metadata.AddonCompartmentFunc);
        const known = new Set([...api.globals, ...allowedWrites]);
        for (const dependency of dependencies) for (const name of exported.get(dependency) ?? []) known.add(name);

        const writes = [];
        for (const file of [...listed].filter((f) => f.endsWith(".lua") && existsSync(join(dir, f)))) {
            const path = join(dir, file);
            const text = readFileSync(path, "utf8");
            checkStyle(text, path, report);
            checkLua(path, text, { api, known, clientGlobal, writes, framework: dependencies.includes("ByteTerrace_Core") }, report);
            checkStyleRules(path, text, report);
        }
        for (const write of writes) {
            if (!allowedWrites.has(write.name) && !write.name.startsWith("SLASH_")) {
                report(write.file, write.line, "GLOBAL", `write to undeclared global ${write.name} (declare it in ## X-Globals)`);
            }
        }
    }

    if (root === repoRoot) {
        const testLua = [];
        for (const dir of ["tools", "tests"]) {
            for (const file of readdirSync(join(root, dir), { recursive: true }).map(toPosix)) {
                const skip = file.startsWith("api/") || file.startsWith("fixtures/");
                if (!/\.(mjs|lua|json)$/.test(file) || skip) continue;
                const path = join(root, dir, file);
                const text = readFileSync(path, "utf8");
                checkStyle(text, path, report);
                if (dir === "tests" && file.endsWith(".lua")) {
                    checkStyleRules(path, text, report);
                    testLua.push({ path, text });
                }
            }
        }
        // The globals the runner hands the tests' Lua from JavaScript (lua.ctx.__name).
        const libDir = join(root, "tools", "lib");
        const handed = new Set(readdirSync(libDir).filter((file) => file.endsWith(".mjs"))
            .flatMap((file) => [...readFileSync(join(libDir, file), "utf8").matchAll(/lua\.ctx\.(\w+)/g)].map((match) => match[1])));
        checkTestGlobals(testLua, [PRELUDE, COVERAGE_LUA], handed, report);
        for (const finding of formatFindings(root)) report(join(root, finding.path), finding.line, finding.rule, finding.message);
    }

    if (!quiet) {
        for (const finding of findings) console.log(finding);
        console.log(findings.length ? `${findings.length} finding(s)` : `check passed (${addons.length} addons)`);
    }
    return findings;
}

/** What the format verb would change under root: { path, line, message } per file, nothing written. */
export function formatFindings(root) {
    return formatRepository({ files: formatFiles(root), check: true, root }).findings;
}

export async function run(values) {
    return (await runChecks({ quiet: values.quiet, wowRoot: values["wow-root"] })).length === 0 ? 0 : 1;
}
