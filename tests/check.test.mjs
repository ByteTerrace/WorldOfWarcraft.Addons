// The check gate's own tests. It runs over fixture addons (tests/fixtures/check): BadAddon has one
// violation per marked line, GoodAddon exercises every allowed construct, LegacyAddon has no
// Forever TOC, and FrameworkAddon (built on a stub ByteTerrace_Core) reaches past the framework.
// The findings must be exactly EXPECTED, so a rule that stops firing (or starts misfiring) fails.
// tests/fixtures/toc holds one addon per Forever TOC suffix and one with both.

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { loadAddons } from "../tools/lib/harness.mjs";
import { findAddons } from "../tools/lib/repo.mjs";
import { FIXTURES, assert, assertSame, captureLog, withTemp } from "../tools/lib/test-support.mjs";
import { buildOf, interfaceOf } from "../tools/lib/wow.mjs";
import { formatFindings, loadApi, runChecks } from "../tools/verbs/check.mjs";

const SECRET_CALL = "check issecretvalue on each result before any use or annotate \"-- secret: <why>\"";
const SECRET_VALUE = "and is passed as a value, so its results skip the call-site check; annotate \"-- secret: <why>\"";
const SECRET_PAYLOAD = "check issecretvalue before comparing, computing or branching on it, or annotate \"-- secret: <why>\"";
const PROTECTED = "guard it with an InCombatLockdown() test that returns early (or a `not InCombatLockdown()` branch), or annotate \"-- protected: <why>\"";
const BLOCKED = (name, why) => `PROTECTED ${name} can be blocked during combat lockdown (${why}); ${PROTECTED}`;
const OPAQUE = (what) => `GLOBAL ${what}; annotate "-- global: <why>"`;
const FENV = OPAQUE("getfenv with a level other than 0 or 1 reaches another function's environment");
const UNDECLARED = (name) => `GLOBAL write to undeclared global ${name} (declare it in ## X-Globals)`;
const INTO = (name) => `GLOBAL assignment into client global ${name}; annotate "-- global: <why>" if intended`;
const B = "BadAddon/Bad.lua";
const B2 = "BadAddon/Bad2.lua";
const B3 = "BadAddon/Bad3.lua";
const FORBIDDEN = (name) => `PROTECTED ${name} is forbidden to addon code at any time (in-game evidence in tools/api/forbidden.json)`;
const BS = "BadAddon/BadStyle.lua";
const BANNER = "COMMENT banner divider: let the code's structure and doc comments do that work";
const DEBT = (marker) => `COMMENT debt marker "${marker}": do the work, or say what's true today`;
const HP = `UnitHealth can return a secret (SecretReturns); ${SECRET_CALL}`;
const BH = "BadAddon/BadHygiene.lua";
const KEEP = "rename it to _, since a later one is read and keeps its position";
const BA = "BadAddon/BadArgs.lua";
const UNNILABLE = (count, argument) => `passes ${count} arguments but argument #${argument} isn't nilable in its documentation`;

const FW = "FrameworkAddon/Framework.lua";
const TIMERS = "use a module timer (module:After, module:Every), which runs as a batch and stops with its module";
const COMMS = "use a module's comms (comms = { prefix }), which keeps Blizzard's addon message rules";

const EXPECTED = [
    "LegacyAddon/LegacyAddon.toc:1: TOC LegacyAddon has no LegacyAddon_Forever.toc or LegacyAddon_Camelot.toc, so the Forever client won't load it",
    "BadAddon/BadAddon_Camelot.toc:1: TOC ## Interface 11507 but the installed client is 16001",
    "BadAddon/BadAddon_Camelot.toc:1: TOC dependency MissingAddon is not an addon in this repository",
    "BadAddon/BadAddon_Camelot.toc:1: TOC dependency AlsoMissing is not an addon in this repository",
    "BadAddon/BadAddon_Camelot.toc:1: TOC dependency ThirdMissing is not an addon in this repository",
    "BadAddon/BadAddon_Camelot.toc:1: TOC lists Bad3.lua twice, so the client would run it twice",
    "BadAddon/BadAddon_Camelot.toc:1: TOC lists Missing.lua, which does not exist",
    "BadAddon/Orphan.lua:1: TOC not listed in BadAddon_Camelot.toc",
    `${B}:5: EVENT unknown event NOT_A_REAL_EVENT`,
    `${B}:6: SECRET UnitHealth can return a secret (SecretReturns); ${SECRET_CALL}`,
    `${B}:7: MEMBER C_GamePad.NotARealFunction is not in the API snapshot`,
    `${B}:8: GLOBAL read of unknown global NotARealGlobal`,
    `${B}:9: ${UNDECLARED("LeakedGlobal")}`,
    `${B}:13: STYLE trailing whitespace`,
    `${B}:14: SECRET UnitHealth can return a secret (SecretReturns); ${SECRET_CALL}`,
    `${B}:17: SECRET UnitHealth can return a secret (SecretReturns); ${SECRET_CALL}`,
    `${B}:19: SECRET UnitHealth can return a secret (SecretReturns) ${SECRET_VALUE}`,
    `${B}:21: SECRET UnitHealth can return a secret (SecretReturns) ${SECRET_VALUE}`,
    `${B}:23: SECRET :GetText() can return a secret (Text aspect); ${SECRET_CALL}`,
    `${B}:25: SECRET UnitClass can return a secret (SecretWhenUnitIdentityRestricted); ${SECRET_CALL}`,
    `${B}:28: ${UNDECLARED("LeakedViaG")}`,
    `${B}:29: ${UNDECLARED("LeakedViaIndex")}`,
    `${B}:30: GLOBAL global write with a dynamic key; annotate "-- global: <why>"`,
    `${B}:31: ${UNDECLARED("LeakedViaFenv")}`,
    `${B}:32: ${UNDECLARED("LeakedViaRawset")}`,
    `${B}:33: ${UNDECLARED("LeakedViaSetglobal")}`,
    `${B}:34: GLOBAL read of unknown global NotARealGlobal2`,
    `${B}:35: ${INTO("string.trimall")}`,
    `${B}:36: ${INTO("C_GamePad.Hijack")}`,
    `${B}:37: GLOBAL frame name UIParent collides with a client global`,
    `${B}:38: GLOBAL read of unknown global NotARealGlobal3`,
    `${B}:39: GLOBAL read of unknown global ToggleCollision`,
    `${B}:40: MEMBER Enum.PowerType.NotAPowerType is not in the API snapshot`,
    `${B}:42: MEMBER Enum.PowerType.AlsoNotAPowerType is not in the API snapshot`,
    `${B}:43: MEMBER C_Spell.NotASpellFunction is not in the API snapshot`,
    `${B}:44: MEMBER C_Macro.SetMacroExecuteLineCallback is not in the API snapshot`,
    `${B}:45: MEMBER string.dump is not in the API snapshot`,
    `${B}:47: EVENT unknown event NOT_REAL_EITHER`,
    `${B}:48: PROTECTED Settings.OpenToCategory is forbidden to addon code at any time (in-game evidence in tools/api/forbidden.json); no combat guard helps, so don't call it`,
    `${B}:49: ${BLOCKED("C_AuctionHouse.PlaceBid", "HasRestrictions")}`,
    `${B}:51: ${BLOCKED(":SetPoint()", "protected method on a Secure frame")}`,
    `${B}:53: ${INTO("string.Helper")}`,
    // Round two: annotations, real guards, aliases, dot calls, environments, protection.
    `${B2}:4: SECRET ${HP}`, // a trailing annotation on the line above doesn't cover this line
    `${B2}:6: SECRET ${HP}`, // a block comment isn't an annotation
    `${B2}:8: SECRET UnitHealth can return a secret (SecretReturns) ${SECRET_VALUE}`, // alias later reassigned
    `${B2}:9: SECRET UnitHealthMax can return a secret (SecretWhenUnitHealthMaxRestricted) ${SECRET_VALUE}`,
    `${B2}:13: SECRET ${HP}`, // used before the check
    `${B2}:20: SECRET ${HP}`, // stored before the check
    `${B2}:25: SECRET ${HP}`, // check result discarded
    `${B2}:30: SECRET ${HP}`, // result local reassigned
    `${B2}:36: SECRET ${HP}`, // guarded branch doesn't exit
    `${B2}:42: SECRET :GetValue() can return a secret (BarValue aspect); ${SECRET_CALL}`,
    `${B2}:43: SECRET .GetValue can return a secret (BarValue aspect) ${SECRET_VALUE}`,
    `${B2}:44: SECRET ${HP}`, // getglobal("UnitHealth")
    `${B2}:45: ${FENV}`,
    `${B2}:46: ${OPAQUE("loadstring compiles code the gate can't see")}`,
    `${B2}:47: ${OPAQUE("setfenv changes a function's environment")}`,
    `${B2}:48: ${FENV}`,
    `${B2}:52: ${BLOCKED("C_AuctionHouse.PlaceBid", "HasRestrictions")}`, // InCombatLockdown() discarded
    `${B2}:56: ${BLOCKED("C_AuctionHouse.PlaceBid", "HasRestrictions")}`, // the lockdown branch doesn't return
    `${B2}:60: ${BLOCKED("C_AuctionHouse.PlaceBid", "HasRestrictions")}`, // a closure runs later
    `${B2}:64: ${BLOCKED(":SetPoint()", "protected method on a Secure frame")}`, // through a field
    `${B2}:67: ${BLOCKED(":Show()", "protected method on a Secure frame")}`, // through an alias
    `${B2}:68: ${BLOCKED(":Hide()", "protected method on a frame not proven non-Secure, in a file that creates Secure frames")}`,
    `${B2}:71: ${BLOCKED(":SetPropagateKeyboardInput()", "HasRestrictions")}`, // any receiver
    `${B2}:75: SECRET CHAT_MSG_AFK payload parameter text can be secret (SecretInChatMessagingLockdown); ${SECRET_PAYLOAD}`,
    `${B2}:78: SECRET CHAT_MSG_AFK payload parameter text can be secret (SecretInChatMessagingLockdown); ${SECRET_PAYLOAD}`,
    `${B2}:79: SECRET CHAT_MSG_AFK payload parameter text can be secret (SecretInChatMessagingLockdown); ${SECRET_PAYLOAD}`, // copied
    `${B2}:80: SECRET CHAT_MSG_AFK payload parameter text can be secret (SecretInChatMessagingLockdown); ${SECRET_PAYLOAD}`, // stored
    `${B2}:81: SECRET CHAT_MSG_AFK payload parameter text can be secret (SecretInChatMessagingLockdown); ${SECRET_PAYLOAD}`, // tabled
    `${B2}:82: SECRET ${HP}`, // \`_\` only discards what nothing reads
    `${B2}:85: PROTECTED SetRaidTarget is forbidden to addon code at any time (in-game evidence in tools/api/forbidden.json); no combat guard helps, so don't call it`,
    `${B2}:87: SECRET CHAT_MSG_AFK payload parameter text can be secret (SecretInChatMessagingLockdown); ${SECRET_PAYLOAD}`, // a table key
    `${B2}:88: SECRET CHAT_MSG_AFK payload parameter text can be secret (SecretInChatMessagingLockdown); ${SECRET_PAYLOAD}`, // out of an and/or
    `${B2}:91: SECRET cur holds UnitPower's result; the annotation on line 90 covers the call, not this use, which errors on a secret: check issecretvalue before it, or annotate "-- secret: <why>"`,
    `${B2}:94: EVENT COMBAT_LOG_EVENT_UNFILTERED is restricted to Blizzard's code; registering it is refused (ADDON_ACTION_FORBIDDEN)`,
    `${B2}:95: PROTECTED SettingsPanel:OpenToCategory is forbidden to addon code at any time (in-game evidence in tools/api/forbidden.json); no combat guard helps, so don't call it`,
    `${B3}:4: EVENT unknown event NOT_A_REAL_EVENT_X`,
    `${B3}:5: EVENT COMBAT_LOG_EVENT_UNFILTERED is restricted to Blizzard's code; registering it is refused (ADDON_ACTION_FORBIDDEN)`,
    `${B3}:6: ${FORBIDDEN("SettingsPanel:Open")}; no combat guard helps, so don't call it`,
    `${B3}:7: ${FORBIDDEN("SettingsPanel:Open")}; no combat guard helps, so don't call it`,
    `${B3}:8: ${FORBIDDEN("SettingsPanel:Open")}; don't take it as a value`,
    `${B3}:9: ${FORBIDDEN("SetRaidTarget")}; don't take it as a value`,
    `${B3}:10: MEMBER C_GamePad.NotARealFunction is not in the API snapshot`,
    `${B3}:13: SECRET CHAT_MSG_AFK payload parameter text can be secret (SecretInChatMessagingLockdown); ${SECRET_PAYLOAD}`,
    `${B3}:19: SECRET CHAT_MSG_AFK payload parameter said can be secret (SecretInChatMessagingLockdown); ${SECRET_PAYLOAD}`,
    `${B3}:25: SECRET Health holds UnitHealth's result; the annotation on line 24 covers the call, not this use, which errors on a secret: check issecretvalue before it, or annotate "-- secret: <why>"`,
    `${B3}:30: SECRET :GetText() can return a secret (Text aspect); ${SECRET_CALL}`,
    `${B3}:32: ${BLOCKED(":SetPoint()", "protected method on a Secure frame")}`,
    `${B3}:38: ${BLOCKED("C_AuctionHouse.PlaceBid", "HasRestrictions")}`,
    // Naming and comments (GoodAddon/GoodStyle.lua holds the allowed constructs).
    `${BS}:3: NAMING constant 'MAX_ITEMS' should be PascalCase (MaxItems)`,
    `${BS}:4: NAMING file-level local 'itemCount' should be PascalCase (ItemCount)`,
    `${BS}:5: NAMING function 'helper' should be PascalCase (Helper)`,
    `${BS}:7: NAMING method 'on_event' should be PascalCase (OnEvent)`,
    `${BS}:8: NAMING parameter 'Count' should be camelCase (count)`,
    `${BS}:10: NAMING local 'Total' should be camelCase (total)`,
    `${BS}:11: NAMING loop variable 'Index' should be camelCase (index)`,
    `${BS}:14: NAMING loop variable 'Key' should be camelCase (key)`,
    `${BS}:16: NAMING local 'Doubled' should be camelCase (doubled)`, // a top-level loop's locals are locals
    `${BS}:19: NAMING function 'later' should be PascalCase (Later)`, // declared ahead, given a function below
    `${BS}:20: NAMING function 'later' should be PascalCase (Later)`,
    `${BS}:21: ${BANNER}`,
    `${BS}:22: ${DEBT("TODO")}`,
    `${BS}:23: ${DEBT("for now")}`,
    `${BS}:26: NAMING local 'BAD_VALUE' should be camelCase (badValue)`,
    // Hygiene (GoodAddon/GoodHygiene.lua holds the allowed constructs).
    `${BH}:3: HYGIENE unused local Unread: nothing reads it`,
    `${BH}:4: HYGIENE unused local function Uncalled: nothing calls or reads it`,
    `${BH}:5: HYGIENE unused local function Recurse: only its own body calls it`,
    `${BH}:6: HYGIENE unused parameter first: ${KEEP}`,
    `${BH}:7: HYGIENE unused parameter second: remove it`,
    `${BH}:8: HYGIENE unused parameter first: ${KEEP}`, // `...` is read after it
    `${BH}:10: HYGIENE unused parameter self: ${KEEP}`, // a callback's signature is the caller's
    `${BH}:11: HYGIENE unused loop variable index: rename it to _`,
    `${BH}:12: HYGIENE unused loop variable value: remove it`,
    `${BH}:13: HYGIENE unused loop variable key: ${KEEP}`,
    `${BH}:14: HYGIENE unused local First: nothing reads it; ${KEEP}`,
    `${BH}:15: HYGIENE unused local Written: nothing reads it`, // assigned, never read
    `${BH}:17: HYGIENE parameter value shadows the parameter value on line 17; rename one`,
    `${BH}:18: HYGIENE loop variable entry shadows the loop variable entry on line 18; rename one`,
    `${BH}:21: HYGIENE local Level shadows the local Level on line 19; rename one`,
    `${BH}:26: HYGIENE local Twice redefines the local Twice on line 24; rename one`,
    `${BH}:28: HYGIENE parameter self shadows the implicit self of the method on line 27; rename it`,
    `${BH}:32: HYGIENE unreachable code: the statement on line 31 always leaves this block`, // do return end
    `${BH}:36: HYGIENE unreachable code: the statement on line 35 always leaves this block`, // every branch returns
    `${BH}:40: HYGIENE unreachable code: the statement on line 39 always leaves this block`, // do break end
    `${BH}:42: HYGIENE empty if branch`,
    `${BH}:43: HYGIENE empty elseif branch`,
    `${BH}:44: HYGIENE empty else branch`,
    `${BH}:45: HYGIENE empty do block`,
    `${BH}:46: HYGIENE empty loop body`,
    `${BH}:47: HYGIENE empty loop body`,
    `${BH}:48: HYGIENE empty loop body`,
    `${BH}:50: HYGIENE the value assigned to total is overwritten on line 51 before anything reads it`,
    // Argument counts of documented functions.
    `${BA}:5: ARGS InCombatLockdown passes 1 argument but its documentation declares 0`,
    `${BA}:6: ARGS C_Spell.GetSpellName ${UNNILABLE(0, "1 (SpellIdentifier)")}`,
    `${BA}:7: ARGS C_Spell.GetSpellName passes 2 arguments but its documentation declares 1`, // through an alias
    `${BA}:8: ARGS C_Spell.GetSpellName ${UNNILABLE(0, "1 (SpellIdentifier)")}`, // a string-literal index
    `${BA}:9: ARGS GetTime passes 1 argument but its documentation declares 0`, // a string call
    `${BA}:10: ARGS Mixin ${UNNILABLE(0, "1 (LuaValueVariant)")}`, // before a repeating argument
    `${BA}:11: ARGS C_CVar.GetCVar passes 2 arguments but its documentation declares 1`, // a nil literal counts
    `${FW}:7: FRAMEWORK C_Timer.After belongs to the framework; ${TIMERS}`,
    `${FW}:8: FRAMEWORK C_Timer.NewTicker belongs to the framework; ${TIMERS}`,
    `${FW}:9: FRAMEWORK CHAT_MSG_ADDON belongs to the framework; ${COMMS}`,
    `${FW}:10: FRAMEWORK C_ChatInfo.SendAddonMessage belongs to the framework; ${COMMS}`,
    `${FW}:11: FRAMEWORK PlaySoundFile belongs to the framework; use a sound bank (ByteTerrace.NewSoundBank)`,
    `${FW}:12: FRAMEWORK C_Timer.NewTimer belongs to the framework; ${TIMERS}`,
    `${FW}:14: FRAMEWORK C_ChatInfo.SendAddonMessageLogged belongs to the framework; ${COMMS}`,
    `${FW}:15: FRAMEWORK CHAT_MSG_ADDON_LOGGED belongs to the framework; ${COMMS}`,
    `${FW}:16: FRAMEWORK Settings.RegisterVerticalLayoutCategory belongs to the framework; use declared rows: the framework generates the settings panel`,
    `${FW}:17: FRAMEWORK Settings.RegisterCanvasLayoutCategory belongs to the framework; use declared rows: the framework generates the settings panel`,
];

const NO_INSTALL = join(FIXTURES, "no-such-install");
const interfaceFindings = (findings) => findings.filter((f) => f.includes("## Interface"));

export const tests = [
    {
        name: "check reports exactly the planted violations, and nothing for allowed constructs",
        run: async () => {
            assertSame(await runChecks({ quiet: true, root: join(FIXTURES, "check"), clientInterface: 16001 }), EXPECTED);
        },
    },
    {
        // The client loads <Name>_Forever.toc and <Name>_Camelot.toc; with both, the tools read
        // _Forever.toc (its ## Title says so) and check reports the other.
        name: "check, findAddons and the harness read either Forever TOC suffix, and check reports a folder with both",
        run: async () => {
            const root = join(FIXTURES, "toc");
            const addons = findAddons(root);
            const summary = addons.map((addon) => `${addon.name}:${addon.tocFile}:${addon.metadata.Title}`).sort().join(" | ");
            assert(summary === "BothAddon:BothAddon_Forever.toc:From Forever | CamelotAddon:CamelotAddon_Camelot.toc:Camelot Addon"
                + " | ForeverAddon:ForeverAddon_Forever.toc:Forever Addon", summary);
            const loaded = loadAddons(root);
            assert(Object.keys(loaded).sort().join(",") === "BothAddon,CamelotAddon,ForeverAddon", Object.keys(loaded).join(","));
            assert(loaded.BothAddon.metadata.Version === "0.2.0" && loaded.ForeverAddon.files.join(",") === "Main.lua", JSON.stringify(loaded.BothAddon));
            assertSame(await runChecks({ quiet: true, root, clientInterface: 16001 }), [
                "BothAddon/BothAddon_Camelot.toc:1: TOC BothAddon also has BothAddon_Forever.toc, which the tools read; which one the client loads isn't documented, so keep one",
            ]);
        },
    },
    {
        name: "a game version maps to its TOC interface number",
        run: async () => {
            assert(interfaceOf("1.60.1 (70374)") === 16001, `1.60.1: ${interfaceOf("1.60.1 (70374)")}`);
            assert(interfaceOf("1.15.7") === 11507 && interfaceOf("2.5.12") === 20512, "Classic numbering");
            assert(interfaceOf("no version") === null, "no version, no number");
        },
    },
    {
        // CI has no client: the committed snapshot's build stands in for it, and check says so.
        name: "check compares ## Interface with the API snapshot's build when no client is found, and says which it used",
        run: async () => {
            const build = loadApi().build;
            assert(build === buildOf(build) && build !== null, `the committed snapshot names its build: ${build}`);
            const { result, lines } = await captureLog(() => runChecks({ root: join(FIXTURES, "check"), wowRoot: NO_INSTALL }));
            const expected = interfaceOf(build);
            assertSame(interfaceFindings(result), [`BadAddon/BadAddon_Camelot.toc:1: TOC ## Interface 11507 but the API snapshot's client is ${expected}`]);
            const said = `Interface check against ${expected} (no client found; the API snapshot's build ${build})`;
            assert(lines.includes(said), `printed: ${lines.slice(0, 3).join(" | ")}`);
        },
    },
    {
        name: "check follows the snapshot's build, and skips the interface check (saying so) when it names none",
        run: async () => withTemp(async (dir) => {
            const docsOnly = JSON.parse(readFileSync(join(FIXTURES, "api", "nodump.json"), "utf8"));
            const later = join(dir, "later.json");
            writeFileSync(later, JSON.stringify({ ...docsOnly, source: { globals: "ByteTerrace_DevTools dump, client 1.61.2 (80000)" } }));
            const run = await captureLog(() => runChecks({ root: join(FIXTURES, "check"), wowRoot: NO_INSTALL, apiPath: later }));
            assert(interfaceFindings(run.result).length === 4, `every fixture TOC says 16001 or 11507, not 16102: ${interfaceFindings(run.result).join(" | ")}`);
            assert(run.lines.includes("Interface check against 16102 (no client found; the API snapshot's build 1.61.2 (80000))"), run.lines[0]);
            const none = await captureLog(() => runChecks({ root: join(FIXTURES, "check"), wowRoot: NO_INSTALL, apiPath: join(FIXTURES, "api", "nodump.json") }));
            assert(interfaceFindings(none.result).length === 0, "no build, no interface finding");
            assert(none.lines.includes("Interface check skipped (no client found and no build in the API snapshot)"), none.lines[0]);
        }),
    },
    {
        name: "snapshot truth: with a dump only dumped names are known; without one the docs are the fallback",
        run: async () => {
            const api = loadApi();
            assert(api.hasDump, "the committed snapshot has a dump");
            assert(!api.globals.has("ToggleCollision"), "documented but not in the dump");
            assert(api.members.get("string").has("format") && !api.members.get("string").has("dump"), "stdlib from the dump");
            const docsOnly = loadApi(join(FIXTURES, "api", "nodump.json"));
            assert(!docsOnly.hasDump && docsOnly.globals.has("UnitHealth") && docsOnly.members.get("C_Spell").has("GetSpellName"), "docs fallback");
            assert(docsOnly.members.get("Enum.PowerType").has("Energy"), "documented enumerations");
        },
    },
    {
        name: "check holds a file to 1000 lines",
        run: async () => withTemp(async (dir) => {
            mkdirSync(join(dir, "LongAddon"));
            writeFileSync(join(dir, "LongAddon", "LongAddon_Camelot.toc"), "## Interface: 16001\n## Title: Long Addon\n\nMain.lua\n");
            const body = (count) => `local addonName, ns = ...\n${"print(addonName, ns)\n".repeat(count - 1)}`;
            writeFileSync(join(dir, "LongAddon", "Main.lua"), body(1000));
            assertSame(await runChecks({ quiet: true, root: dir, clientInterface: 16001 }), []);
            writeFileSync(join(dir, "LongAddon", "Main.lua"), body(1001));
            assertSame(await runChecks({ quiet: true, root: dir, clientInterface: 16001 }), ["LongAddon/Main.lua:1000: LENGTH 1001 lines exceeds 1000"]);
        }),
    },
    {
        // check runs FORMAT over the repository root only; formatFindings is what it reports.
        name: "check's FORMAT names a file's first line the format verb would change, and leaves fixtures alone",
        run: async () => withTemp(async (dir) => {
            mkdirSync(join(dir, "tests", "fixtures"), { recursive: true });
            writeFileSync(join(dir, "tests", "kept.test.lua"), "local a = 1\n\nprint(a)\n");
            writeFileSync(join(dir, "tests", "loose.test.lua"), "local a = 1\nprint(a == 1)\n");
            writeFileSync(join(dir, "tests", "fixtures", "bad.lua"), "local a = 1\nprint(a)\n");
            const findings = formatFindings(dir).map((finding) => `${finding.path}:${finding.line}`);
            assertSame(findings, ["tests/loose.test.lua:2"]);
        }),
    },
];
