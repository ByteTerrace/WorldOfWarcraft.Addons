# ByteTerrace World of Warcraft addons

Addons for **World of Warcraft: Forever**, held to the same correctness and performance bar as Puck.

| Addon | Description |
| --- | --- |
| [ByteTerrace_Core](ByteTerrace_Core) | The shared framework (Lua global `ByteTerrace`): state, commands, input, events, and modules. See [the architecture](docs/Architecture.md). |
| [TheLanKrewToolKit](TheLanKrewToolKit) | Utilities for The Lan Krew. |
| [ByteTerrace_DevTools](ByteTerrace_DevTools) | Development only (`## X-DevOnly`), and never shipped. `/btdev dump` records the client's globals for `tlk api-sync`, and `/btdev probe` records the client's answers to calibration probes for `tlk probes`. |

## WoW: Forever target

| What | Value |
| --- | --- |
| Interface | `16001` (game version 1.60.1) |
| TOC file | `<AddOnName>_Camelot.toc` or `<AddOnName>_Forever.toc` |
| API | Mainline (Midnight 12.x) UI and API, including secret values. Classic Era APIs don't apply. |
| AddOns folder | Detected from the install's `.build.info` (the beta installs to `_classic_beta_`) |

The client's game type is `camelot`, with `forever` as an alias. These addons use `_Camelot.toc`. When a folder has both TOC files, the tools read `_Forever.toc`.

For controller work, see [Controller support](docs/ControllerSupport.md).

## Development

You need Node.js 22 or later. Every operation is a verb on one CLI:

```powershell
npm ci                             # once, and after package-lock.json changes (tlk says when)
node tools/tlk.mjs check           # static gates
node tools/tlk.mjs format          # rewrite the Lua to its one form (--check only reports)
node tools/tlk.mjs clones          # structurally identical Lua, heaviest first (Puck's clone scan)
node tools/tlk.mjs guesses         # the harness's guesses, the ones most worth a probe first
node tools/tlk.mjs test            # behavioral tests in real Lua 5.1 (filters or test files narrow it)
node tools/tlk.mjs test --coverage # the same, then which addon statements the Lua tests reached
node tools/tlk.mjs deploy          # check and test, then junction-link every addon (--no-test skips tests)
node tools/tlk.mjs package         # check and test, then zip the committed addons for players, in dist/
```

`clones` lists code that matches token for token once names and literals are set aside: function bodies, and blocks of four or more statements outside a copied function. A match has 30 tokens or more. `--min-tokens` and `--min-statements` change those limits. It reports and gates nothing: which copies to merge is review.

`guesses` lists every `[G]` guess and `[C]` conservative fallback in `tests/harness/*.lua`. For each one, it shows:

- what it claims
- the client functions, events, and harness methods the claim names, and the fake or method the comment sits above
- how many of the shipped addons' files use that API, and how many test files call those methods
- the probes that cite it or read the same API

The most depended on come first, so the top of the list is what to probe next (see [Probes](#probes)). `--top <n>` shortens it, and `--json` prints one record per guess. It reports and gates nothing.

`package` ships every addon without `## X-DevOnly` (DevTools has it), as committed at HEAD. So it refuses uncommitted changes in a shipped folder, and a shipped addon whose dependency stays behind. Players' own sounds, which git ignores, never ship. The zip is named after the addon nothing else depends on, with its `## Version`, and extracts straight into `Interface\AddOns`. Its players' guide is [TheLanKrewToolKit/README.txt](TheLanKrewToolKit/README.txt).

When HEAD is tagged `vX.Y.Z`, every shipped addon's `## Version` in the zip is X.Y.Z. Otherwise, it's the TOC's version plus `-dev+<short sha>`. Only the zip changes, never the working tree. The named addon's folder holds `CHANGELOG.txt`: the commit subjects since the previous tag. Pushing a `vX.Y.Z` tag runs the gates and publishes a GitHub Release with the zip (`release.yml`). Every pull request uploads the zip as an artifact.

`deploy --addon <name>` includes the full dependency chain regardless of directory order. `deploy --unlink --addon <name>` removes only the explicitly selected addon's link.

`deploy` treats a link to the same addon in another worktree of this repository as its own. It repoints the link to this checkout and says from where to where, and `--unlink` removes it. A dangling link to the same addon inside or beside a worktree (one since removed) counts too.

`.github/workflows/gates.yml` runs `npm ci`, `check`, and `test` on Windows for every push and pull request, with the Node version in `.node-version`.

The addons run straight from this repo. After a change, do this:

| You changed | Do this |
| --- | --- |
| Lua in an existing file | Run `check` and `test`, then type `/reload` in game. |
| A TOC (a new file, SavedVariables, or metadata) | Run `deploy`, then restart the game. `/reload` doesn't re-read TOCs. |
| A new addon folder | Run `deploy`, then restart the game. |
| A new client build | Run `deploy`, which flags a stale `## Interface`, and [refresh the API snapshot](#refresh-the-snapshot). |

Turn on Lua error popups once: in game, type `/console scriptErrors 1`.

### Gates

`check` reports `path:line: RULE message`, and any finding fails it. A method call counts in every form it takes: `obj:M()`, and `obj.M(obj)` or `obj["M"](obj)` passing the receiver first. An annotation (`-- secret: <why>`, `-- protected: <why>`, or `-- global: <why>`) is a `--` line comment on the construct's line, or alone on the line above it.

| Rule | What it enforces |
| --- | --- |
| PARSE | Every file parses as Lua 5.1. |
| TOC | Every addon folder has one TOC that lists its files and matches the client. See [TOC](#toc). |
| GLOBAL | Every global read exists, and every global write is declared. See [GLOBAL](#global). |
| MEMBER | Full member chains (`Enum.PowerType.Energy` or `C_Spell["X"]`, including through local aliases) exist in the snapshot. So does a client table's method called with `:` (`C_GamePad:X()`). |
| EVENT | Every event name passed to an event method is real, whether a literal or a file-level constant. None registered (`On`, `RegisterEvent`, or `RegisterUnitEvent`) is restricted to Blizzard's code (`HasRestrictions`, such as the combat log events). |
| SECRET | A call that can return a secret is guarded or annotated, and so is comparing or computing with its value. See [SECRET](#secret). |
| PROTECTED | A forbidden function is never called, and a call that combat lockdown can block is guarded. See [PROTECTED](#protected). |
| NAMING | Puck's naming, mapped to Lua ([conventions](docs/Conventions.md)). See [NAMING](#naming). |
| COMMENT | Comments are sentences, with no banner dividers or debt markers. See [COMMENT](#comment). |
| HYGIENE | luacheck's warnings, as far as a parser decides them. See [HYGIENE](#hygiene). |
| ARGS | A call to a documented client function passes a number of arguments its documentation allows. See [ARGS](#args). |
| FRAMEWORK | An addon that depends on `ByteTerrace_Core` leaves the client APIs the framework owns to the framework. See [FRAMEWORK](#framework). |
| FORMAT | Every addon's Lua and the tests' Lua (not `tests/fixtures`) is what `node tools/tlk.mjs format` writes: Puck's formatter passes, mapped to Lua ([conventions](docs/Conventions.md#formatting)). A finding names the file's first line that would change. |
| ORDER | A table constructor whose every field is `name = value` lists them alphabetically, ignoring case, or says why not with `-- order: <why>` on its line or alone above it. `format` sorts the ones whose values call nothing. `format --sort-calls` sorts the rest, for a reviewed diff. |
| LENGTH / STYLE | A 1000-line ceiling. LF, a final newline, no tabs, and no trailing whitespace. |

#### TOC

- Every addon folder has a `_Forever.toc` or a `_Camelot.toc`, not both, since which one the client loads isn't documented.
- The TOC lists exactly the files present, each once.
- Its dependencies (`Dependencies`, `RequiredDeps`, and `Dep*`) exist.
- `## Interface` matches the installed client. With none installed, it matches the interface the API snapshot's build implies (1.60.1 is 16001). `check` prints which it used, or that it skipped.

#### GLOBAL

- Every global read exists in the client dump or a dependency, including reads through `_G.X`, `getfenv().X`, and `getglobal("X")`.
- Every write is declared: SavedVariables, SavedVariablesPerCharacter, `AddonCompartmentFunc`, `SLASH_*`, or `## X-Globals`. That holds whether it's written as `X =`, or through `_G`, `rawset`, `setglobal`, or `getfenv()`.
- A write with a dynamic key, `getfenv` with a level other than 0 or 1, `setfenv`, and `loadstring` need `-- global: <why>`.
- It also flags assignments into client tables, and frame names that collide with client globals.

#### SECRET

A call to a function that can return a secret must be guarded or annotated. That holds whether the call is direct, through a never-reassigned alias, or through `getglobal`. The call passes when it:

- is annotated
- sits directly inside `issecretvalue(...)`
- assigns its results to fresh locals that are never reassigned, and whose every use is dominated by a test

These tests count:

- an `issecretvalue(x)` that returns early when true
- a `not issecretvalue(x)` branch
- the right side of `issecretvalue(x) or ...`
- `canaccessvalue(x)`

A check after a use, a discarded check, or storing the value before the check doesn't count.

The annotation covers the call, not every later use. A local it fills can still be passed on, stored, or indexed (a structure's fields). Comparing or computing with it, testing it, or keying a table with it needs its own guard or annotation, whether the local is fresh or an existing one the call is assigned to.

Passing such a function (or a secret-returning method, `obj.GetValue`) as a value needs the annotation.

A widget getter, called with `:` or `.`, counts only when its file calls a setter that can make that aspect secret. For size and anchor getters, any such setter counts. So getters on frames a file never feeds secrets to, and getters on plain tables, pass.

Event handlers have a rule of their own. In a handler passed as a function literal to `On`, `RegisterEvent`, `SetScript("OnEvent")`, or `HookScript("OnEvent")`, a parameter carrying a secret event payload field can't be used unguarded. Neither can a local the handler's `...` fills (`local text = ...`). Unguarded, it can't be compared, computed with, indexed, used as a table key, or branched on, including through the result of an `and` or `or`.

#### PROTECTED

A function forbidden to addon code at any time is never called, since no guard helps. Those are:

- protected globals (`IsProtectedFunction`)
- the functions the client refused, or that froze it, in game (`tools/api/forbidden.json`, which the harness reads too), such as `Settings.OpenToCategory` and `SettingsPanel:OpenToCategory`

Taking one as a value (an alias, `pcall(SetRaidTarget, ...)`) is refused too. Taking a protected global as a value needs `-- protected: <why>`, since its calls skip the guard.

A call that can be blocked during combat lockdown passes when it:

- is dominated by an `InCombatLockdown()` test that returns early, either directly or through a never-reassigned local of the same function that holds its result
- sits in a `not InCombatLockdown()` branch
- is annotated

A discarded `InCombatLockdown()` doesn't count. A closure doesn't inherit its definer's guard, nor a local its definer kept. The calls this covers are:

- restricted functions (`HasRestrictions`)
- `HasRestrictions` methods (`SetPropagateKeyboardInput`) on any receiver
- protected methods on a frame from a Secure template, followed through locals, aliases, and fields

In a file that creates a Secure frame, a protected method on any receiver the gate can't prove non-Secure (a parameter, say) needs the guard too.

#### NAMING

- Functions, methods, and file-level locals are PascalCase, constants included: `MaxQueue`, never `MAX_QUEUE`. So is a local declared ahead and given a function later.
- Locals inside functions, loops, and branches, parameters, and loop variables are camelCase.
- Aliases keep their source's name (`local floor = math.floor`).
- A file's own `local addonName, ns = ...` and metamethods are exempt. Any other local filled from `...` follows the rules.
- Member names are review, not gate.

#### COMMENT

- No banner dividers (four or more of `- = * # _ ~`). A `---` doc comment's third dash doesn't count.
- No debt markers (`TODO`, `FIXME`, `HACK`, `XXX`, `KLUDGE`, `REVISIT`, or "for now").
- Every paragraph of full-line comments is a sentence. It starts with a capital letter, a digit, or code (`` `level` ``, `ns.Krew`, `h:Fire`, `powerToken`, or a path), and its last line ends with `.`, `!`, `?`, or `:`.
- Kept as written: lines whose text starts two or more spaces after `-- ` (aligned columns, a header's items, and `---@param` continuations), `---@` annotations, list items, and the annotations the gates read (`secret:`, `protected:`, `global:`, and `order:`).

#### HYGIENE

- A local, local function, or loop variable is read, and so is a parameter. A local function only its own body calls is unused. An unused parameter is removed, or renamed `_` when a later parameter or `...` is read, callbacks included.
- A local, parameter, or loop variable doesn't shadow or redefine a visible local of the same file. A callback's `state` may shadow an outer `state`.
- No statement follows one that always leaves its block (`do return end`, or an `if` whose every branch, `else` included, returns or breaks).
- No `if`, `elseif`, or `else` branch, `do` block, or loop body is empty. An empty function is a no-op callback.
- No value assigned to a local is overwritten by a later statement of the same block before anything reads it. That covers straight-line code, and locals no closure references.
- `_`, names starting with `_`, and a file's own `local addonName, ns = ...` are exempt.

#### ARGS

- A call to a documented client function, directly or through a never-reassigned alias, passes no more arguments than its documentation declares. It passes none fewer than the last one the documentation doesn't mark `Nilable` or give a `Default`. A `LuaValueReference` takes nil.
- A call whose last argument is a call or `...` isn't judged, and neither are `:` calls and widget methods.
- The snapshot doesn't record repeating arguments. So a function whose last argument is a `LuaValueReference` or `LuaValueVariant` (`Mixin`, `scrub`) is judged only on the arguments before it.

#### FRAMEWORK

An addon that depends on `ByteTerrace_Core` doesn't call a client API the framework owns, or take one as a value:

- `C_Timer`'s timers
- addon message sending (logged too) and prefixes
- `PlaySoundFile`
- settings and settings-category registration

It doesn't handle `CHAT_MSG_ADDON` or `CHAT_MSG_ADDON_LOGGED` either. Module timers, comms, and the sound bank handle timers, messages, and sounds. Settings come from declared rows, drawn in the addon's own window.

#### What check covers in the tests

NAMING, COMMENT, HYGIENE, LENGTH, and STYLE also cover the tests' Lua: `tests/*.test.lua`, `tests/kits`, and `tests/harness`, not the deliberately bad `tests/fixtures`. LENGTH and STYLE also cover `tools/` and the tests' JavaScript.

GLOBAL covers the tests' Lua in its own form. The tests' Lua runs in the test runner's Lua, where an undefined global reads nil, so every global it reads is one of these:

- Lua 5.1's
- the runner's: its preludes, and the values it hands the Lua as `lua.ctx.__name`
- one that some tests' Lua file assigns

#### What check can't see

- dynamic reads (`_G[name]`, `getglobal(name)`)
- values that cross files or functions (a Secure frame or a secret handed to another file, or an event name passed to a wrapper)
- secrets reaching state through a callee
- handlers that aren't function literals

Its guard analysis is per function, and doesn't follow loops or `goto`.

#### The test harness

`test` runs `tests/*.test.lua` in real Lua 5.1 (WebAssembly) against a fake Forever client (`tests/harness`).

- Each file runs in its own worker, with a timeout that starts after the worker's setup.
- Files start longest first, by their last whole run's time (kept in `node_modules/.cache`).
- Helpers more than one test file needs live in a kit. `tests/kits/<name>.lua` returns a table of them, and `use("<name>")` in a test file runs it once and returns it.

The fake is strict:

- **Secret values** are opaque, and throw on comparison, arithmetic, length, indexing, `tonumber`, and `print`. As in the client, concatenation, `tostring`, and `format` (including `("%d"):format(x)`) accept them and return secret strings. A precision on `%s` is refused. Lua can't catch what the client refuses of a boolean test (a secret boolean), `== plainValue`, a secret compared with itself, or a secret table key. The SECRET rule covers those.
- **When values are secret** follows each flag's predicate under a restriction model: combat, encounter, challenge mode, PvP match, restricted map, and chat lockdown. Some predicates follow Blizzard's documented text. Others are conservative fallbacks where the docs are silent (`SecretReturns`, anchoring, threat, and unknown flags), and `tests/harness/secrets.lua` lists which. Some flags depend on the unit (player-controlled, in your group). A unit the test hasn't set (`h:SetUnit` for pet, focus, party, mouseover, and nameplates) doesn't exist, so it isn't secret.
- **Restriction changes** fire `ADDON_RESTRICTION_STATE_CHANGED`: Activating before the restriction applies, Active once it does, and Inactive after it lifts. Combat follows what the client did (probe `combat.edges`). Entering combat, `PLAYER_REGEN_DISABLED` comes first, then Combat Activating, and no Active. Leaving, Combat Inactive comes before `PLAYER_REGEN_ENABLED`, so the damage meter is readable by then.
- **Addon code is tainted,** so passing a secret (or a table holding one) to an API errors unless its documented `SecretArguments` allows it. Undocumented client functions (`PlaySoundFile`, `PlaySound`, and `StopSound`) refuse secrets.
- **Blocked calls** do nothing, fire `ADDON_ACTION_BLOCKED`, and land in `h.blocked`. The caller keeps running, like the client.
  - A blocked call fails the test, as the client shows the player it, unless the test expects it (`h:ExpectBlocked(count or patterns)`).
  - Protected methods on protected frames and `HasRestrictions` functions are blocked during combat lockdown.
  - Protected globals and the functions in `tools/api/forbidden.json` are always forbidden (`ADDON_ACTION_FORBIDDEN`). Registering a restricted event (`HasRestrictions`, such as `COMBAT_LOG_EVENT_UNFILTERED`) is forbidden the same way, and registers nothing.
  - The docs don't say what `HasRestrictions` means. Lockdown is the harness's guess, unless the entry names a specific restriction (`RestrictedForMacroChatMessages` applies to macros, so addon calls pass).
- **SavedVariables** are nil while an addon's files run, and restored right before its `ADDON_LOADED`. `h:Reload()` and `h:Relog()` write them the way the client does: numbers, strings, booleans, and tables of them, as copies, without cycles, NaN, or inf. A secret value or a secret table key there is an error. A relog ends combat and restrictions.
- **Only real APIs exist:** events, widget methods, and fakes that name real client globals. Reading an undefined global is an error.
  - Only what the addons and probes call is faked. A fake nothing calls is deleted, with its tests. `test` checks it: a fake function (a global, or a member of a global table) whose name appears nowhere in the addons' code (identifiers and strings, not comments) fails, unless `tools/api/forbidden.json` names it, since those fakes exist to refuse the call.
  - Lua's own functions are exempt, and so are widget methods. Every documented method of a widget type exists and counts its calls, and the getters with behaviors are how tests read widget state.
  - A documented function refuses a nil argument the docs don't mark `Nilable` or give a `Default`. A `LuaValueReference` takes any value. Widget methods are exempt, since the docs can't state overloads like `SetPoint("CENTER")`.
  - `h:Fire` refuses a payload with more values than the event documents, a nil (or a missing value) where the docs say `Nilable = false`, a secret in an event without secret flags, or a number, string, or boolean where the docs say another of those. `h:FireChat(event, text, sender)` and `h:LevelUp(level)` fire full payloads.
- **A test fails** on any error reported to the client's error handler.
- **Every widget call and API call is counted,** so tests can assert how much work each event does (`h:CountCalls(method)`, `h:CountApiCalls(name)`). Widget state lives beside the widget (`Harness.State(widget)`), so addon fields never collide with it. `h.profiler` holds what `C_AddOnProfiler` and `GetAddOnMemoryUsage` answer. `h.workTime` is the milliseconds the current frame's work has taken. `debugprofilestop()` answers `h.time * 1000 + h.workTime`, so a test charges a handler time by adding to it.
- **Groups and addon messages:** `h:JoinGroup(kind, names)`, `h:AddMember`, `h:RemoveMember`, and `h:LeaveGroup` fire the client's group events, and give members party or raid tokens (`h:SetUnit` tokens win over them).
  - `C_ChatInfo.SendAddonMessage` checks, in order: the prefix, the message, the chat type, messaging lockdown (encounter, challenge mode, PvP match, restricted map, and chat, but not combat alone), group membership, and then a per-prefix throttle of 10 messages that regains one per second.
  - Sent messages land in `h.addonMessages` with their result. Your own group messages echo back on the next `h:Advance` (`h:Echo(false)` turns that off). `h:ReceiveAddonMessage(prefix, text, channel, sender)` delivers one from someone else.
  - Names follow Forever, as probed in game. Players have a surname (`Harness.DEFAULT_SURNAME` unless a test gives one), and `UnitName` returns first name and surname. Senders are "First Last" (`h:FullName`), with "-Realm" only for another realm.
- **Keyboard:** `h:Key(key, down)` offers a key to keyboard-enabled frames topmost first (strata, then level, then newest). A frame consumes it unless its propagate flag is set after its script runs. Unconsumed keys land in `h.propagatedKeys`. `h:WorldClickBlocked()` says whether a mouse-enabled frame covers UIParent.
- **Guilds:** unit tables and `Harness.New` take `guild`, `guildRank`, `guildRankIndex`, and `guildRealm` (nil means the player's realm). `GetGuildInfo` returns name, rank, rank index, and another realm's name, and nothing without a guild. GUILD addon messages need the player's guild.
- **Damage meter:** every combat is a `C_DamageMeter` session. Current is the latest, and Overall is all of them. Expired stays empty after ordinary fights, as it did in game.
  - `h:MeterFight{ name, duration, sources }` scripts a fight (amounts, spells, and deaths with `C_DeathRecap` recaps), then leaves combat, or dies if the player's source died.
  - A recap's events are combat log events like the game's. Melee `SWING_DAMAGE` carries no spell fields, while `SPELL_DAMAGE` carries spell identity and avoidable and deadly flags. A spell's `details.unit` makes that unit the attacker, GUID and all (`GetPlayerInfoByGUID` knows it).
  - Recap probes compare common event fields and the killing blow's common shape. Separate probes wait for swing or spell damage before checking its spell fields.
  - In combat, every damage-meter field is secret except the documented never-secret ones.
- **Frames:** `OnShow` and `OnHide` run when visibility changes, children included. `h:Drag(frame, dx, dy)` runs `OnMouseDown`, `OnDragStart`, and `OnDragStop` for a movable, mouse-enabled frame registered for the button. Its anchors shift by the drag, where the client re-anchors to the nearest screen corner. A `ScrollFrame` scrolls its child: its range is the child's height less its own. `h:MouseWheel(frame, delta)` turns the wheel over a frame with the wheel enabled. `UIParent` is 1366 x 768, the screen at UI scale 1.
- **Speech:** `C_VoiceChat.SpeakText` and `C_CombatAudioAlert.SpeakText` land in `h.spoken`. Combat audio alerts speak only when the player turned them on (`h.combatAudioAlerts`).
- **Quests:** `h:OfferQuest(spec, giver)` opens a giver's offer panel, and `h:AcceptQuest()` accepts it. `h:AutoAcceptQuest(spec)` is an area trigger's quest, straight into the log with no dialog. `h:OpenTurnIn(id, ender, reward)` and `h:CompleteQuest()` turn one in. `h:ProgressObjective(id, index, have)` sets how many of an objective are done, as killing or looting does. The dialog's texts, `GetQuestID`, the `questnpc` unit, and the quest log (`C_QuestLog`, `GetQuestLogQuestText`) answer as the quest probes recorded in game. An accumulating probe matches when the harness shows nothing the client's sessions didn't.
- **World PvP:**
  - `h:AddNamePlate(unit)` and `h:RemoveNamePlate(token)` fire the nameplate events. A plate shows before `NAME_PLATE_UNIT_ADDED` and hides after `NAME_PLATE_UNIT_REMOVED`, with any frames parented to it.
  - `h:SetMouseover(unit)` fires `UPDATE_MOUSEOVER_UNIT`. Clearing it fires nothing, like the client.
  - `h:Die()`, `h:ReleaseSpirit()`, and `h:Revive()` fire `PLAYER_DEAD`, `PLAYER_ALIVE`, and `PLAYER_UNGHOST` as the client does, and death ends combat.
  - `SetRaidTarget` is forbidden to addon code, as the client refused it in game.
  - `h:HonorKill(victim, rank, honor)` fires the honor message with Forever's enUS text.
  - A unit's `classification` field answers `UnitClassification`. `h:SetComboPoints(n)` puts your combo points on the target and fires `UNIT_POWER_FREQUENT`, as Blizzard's combo frame expects.
- **Maps:** `h:SetLocation{ zone, subZone, mapID, x, y, instance }` fires the zone events. `h:AddMap(id, spec)` declares a map, and a map the test hasn't added doesn't exist. The user waypoint lands in `h.waypoint`.
- **Blizzard UI:** `h:OpenMenu(tag, contextData)` and `h:OpenTargetMenu()` run `Menu.ModifyMenu` callbacks, and return a menu you can `:Click(text)`. `h:ShowUnitTooltip(token)` runs the unit tooltip post calls, with the lines in `Harness.State(GameTooltip).lines`. Raid warnings land in `h.raidNotices`. `MenuUtil.CreateContextMenu` opens a menu that `h:OpenContextMenu()` returns. `RAID_CLASS_COLORS` holds each class's `r`, `g`, `b`, and `colorStr`.
- **Settings:** `Settings.RegisterCanvasLayoutCategory` makes a category whose page is the addon's own frame, and `Settings.RegisterAddOnCategory` lists it under Esc > **Options** > **AddOns**. `h.categories` lists every category registered, and `h.category` is the listed one. Opening Blizzard's panel from addon code is forbidden.
- **Randomness** is the harness's own seeded generator (`h:SeedRandom(n)`), behind both `random` and `math.random`, so tests are repeatable.
- **Sizes are stand-ins:** 7 pixels per character and 14 pixels per line, so layout arithmetic runs.

#### Coverage

`test --coverage` lists, per addon file, the statements no Lua test reached, by line. It instruments each addon file as it loads:

- a hit counter per statement
- conditions wrapped so they keep their value
- every line number and chunk name kept

So statements that share a line are told apart: `if not ready then return end` counts its return only when it returned. A nested function's statements count for it alone. It's a report, not a gate, and it costs about as much as a plain run.

What `test` can't show: the real client's rendering, layout, taint propagation, hardware-event rules, and per-spell secrecy exceptions. Its formatting fakes (`GetMoneyString`, `SecondsToTime`) aren't Blizzard's exact output. Verify those in game.

#### Tooling tests

`tests/*.test.mjs` test the tooling itself:

- The check gate runs over fixtures with one violation per rule, and one for each allowed construct.
- They also cover `api-sync`, the `probes` verb, the test runner (its job order too), coverage, the CLI's dependency check, and deploy's argument, link, and worktree handling.

### API snapshot

`tools/api/forever.json` is what the gates and harness treat as the real API. It has two halves, one entry per line:

- **Documented half,** from Blizzard's docs: every function, event, and widget method, plus the documented enums. An entry holds:
  - its secret flags and `SecretArguments` policy
  - its protection and restriction flags
  - its precondition markers (`Requires*`, `Restricted*`)
  - its aspects
  - its argument and payload types, and which of them may be nil
- **Globals half,** from a dump of your client: every global the client itself defines, and the member names of its tables. Enum members go one level deeper. Anything an addon set is found by taint and excluded.

The documented half says which flags an API has. What a flag means comes from Blizzard's predicate text. `tests/harness/secrets.lua` marks the harness's reading of each as documented or conservative.

The snapshot's `source` field records where each half came from. `api-sync` checks a dump:

- It refuses an implausibly small dump.
- It warns when the two halves come from different builds.
- It warns when globals the last snapshot had are missing from the dump, grouped by their first word ("Achievement (371)"), since that's what a load-on-demand window closed for this dump looks like.
- It leaves out globals the client names after an address ("table: 000001F161607270"), which change every session.

`node tools/tlk.mjs api-sync --latest` compares the snapshot's docs build with the forever branch's `version.txt`. It exits with 0 when current, 1 when stale, and 2 when unreadable. `--source <checkout or file>` reads it locally. `build-watch.yml` runs it weekly, and opens or updates an issue when it's stale.

#### Refresh the snapshot

Refresh both halves when the client build changes:

1. Refresh the documented API from Blizzard's Forever UI source (the `forever` branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/forever)):

   ```powershell
   node tools/tlk.mjs api-sync --docs <wow-ui-source>/Interface/AddOns/Blizzard_APIDocumentationGenerated
   ```

2. Refresh the globals from your own client:
   1. Enable ByteTerrace DevTools, and disable every addon that isn't ByteTerrace's. The dump leaves out every name an addon touched, so another addon that replaced a client global would leave it out of the snapshot. `api-sync` warns when the dump skipped anything for an addon outside this repository.
   2. Open the achievement window, and any other load-on-demand Blizzard window whose names an addon uses. A load-on-demand window's globals exist only once it has opened.
   3. Type `/btdev dump`, then type `/reload`. On entering the world, DevTools says when the saved dump is from another build than the client's.
   4. Run:

      ```powershell
      node tools/tlk.mjs api-sync --globals "<WoW>/_classic_beta_/WTF/Account/<account>/SavedVariables/ByteTerrace_DevTools.lua"
      ```

### Probes

When the harness has to guess how the client behaves, a probe asks the client. ByteTerrace DevTools defines each probe once:

- what it needs (a target, a quest dialog, or combat)
- a read-only question
- a harness setup that recreates the need

`Probes.lua` is the engine, and `ProbeNeeds.lua` holds the situations. `ProbesWorld.lua`, `ProbesUnits.lua`, `ProbesCombat.lua`, `ProbesNames.lua`, `ProbesInput.lua`, and `ProbesOrder.lua` hold the probes. The game runs the files through DevTools, and the harness runs the same files, so both answer the same question in the same situation.

Answers record shapes (a type, a secret marker, or a color's bytes), never character-specific data. `auraSound.api` is the one probe that registers something: an aura sound, removed again in the same run.

Some probes can't ask after the fact, so DevTools listens for these from the moment it loads:

- `UNIT_COMBAT` and `UNIT_AURA` on the player and the target
- the kill events
- chat senders and their `discordInfo`
- addon messages
- the steps into and out of combat: `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED`, and the Combat restriction's changes, with what `InCombatLockdown`, `UnitAffectingCombat`, and `IsAddOnRestrictionActive` said at each
- leaving combat in a PvP match: the damage meter's totals then, and 5 seconds later
- `ENCOUNTER_START` and `ENCOUNTER_WARNING`
- the controller and interface events (`GAME_PAD_*` and `INPUT_DEVICE_INTERFACE_TRANSITION`), with whether each fired before the world loaded
- `PLAYER_DEAD` and `DAMAGE_METER_CURRENT_SESSION_UPDATED`, with combat's state as each dispatches
- `NAME_PLATE_UNIT_ADDED` and `NAME_PLATE_UNIT_REMOVED`, with whether the plate is shown and its unit exists
- `QUEST_TURNED_IN`, with whether the quest's title stays known

DevTools keeps only the set of shapes each has shown, so a shape seen before costs one table lookup. It follows the restrictions in force from `ADDON_RESTRICTION_STATE_CHANGED`, so the aura and addon-message listeners key what they hear by them without asking the client.

#### Run the probes

1. Play with DevTools enabled. Every 5 seconds, it records each probe whose needs are met and that has no answer yet for this build in the situation you're in (idle or in combat, and the restrictions in force). It names the new and changed ones in chat. An accumulating probe merges what it saw each time.
   - `/btdev probe auto off` stops that, and `/btdev probe auto on` starts it again.
   - `/btdev probe` records at once, and lists what the skipped probes need, in play-session order.
   - `/btdev probe list` shows what's still missing, grouped under the same steps.
   - On entering the world, DevTools says how many probes still have no answer for this build.

   One session in a starting zone covers most of them. Stay in each step's situation for 5 seconds, or type `/btdev probe` there:

   1. **Anywhere:** right after you log in, with a quest in your log and your hearthstone in your backpack.
      - With a controller connected, press one of its buttons first. Then type `/btdev rumble`, note what each of its four vibrations felt like (or that you felt nothing), and type the probe command again. Do that with each controller you have: each one's answers add to `gamePad.controllers`.
      - Once someone has spoken in say or General, type the command again for the chat probes.
   2. **At a quest giver:**
      1. Press Shift+V for friendly nameplates, and face the quest giver.
      2. Target them.
      3. Open a quest you haven't accepted.
      4. Later, open a quest turn-in's reward panel, before you select **Complete Quest**.
      5. Complete the quest.
   3. **At a vendor or trainer:** open the vendor's window, then your class trainer's.
   4. **Fighting mobs:**
      1. Target a mob out of combat, then pull it.
      2. Press V for enemy nameplates.
      3. Trade a few blows, so the combat feed has something to show, and let a buff or debuff land on you or the mob (a class spell or the mob's own).
      4. Type the command mid-fight.
      5. Kill the mob yourself, and type the command again right away, before the next pull.
      6. Kill a second mob, and type the command once combat ends, for the order of the steps out of combat.
   5. **After a mob kills you:** let one win, wait 5 seconds, and type the command while you're dead or a ghost.
   6. **Later:** these can wait until you leave the starting zone.
      - Be in each of these situations: resting in an inn, on a flight path, in a party, in a guild, targeting an enemy player, targeting an enemy hunter while they Feign Death, targeting a mob in a dungeon between pulls, on a rogue or a cat-form druid (combo points), and on a character at the max level.
      - For the addon-message probe, run a dungeon (a boss fight too, if you can) in a party with someone running The Lan Krew ToolKit. After you leave, still grouped and without a `/reload` in between, type the command.
      - In a battleground or arena, fight until you've dealt damage, leave combat, wait 5 seconds, and type the command while still in the match.
      - For the encounter-warning probe, pull a dungeon or raid boss, and type the command during or after the fight.

2. Type `/reload`, then import the answers:

   ```powershell
   node tools/tlk.mjs probes --import    # the installed client's SavedVariables; or pass the file
   ```

   The answers land in `tools/api/probes.json`, sorted by probe, with the client build. Each record lists the contexts its result was confirmed in, such as `idle/none` or `combat/Combat`: combat lockdown, then the active restrictions. The import updates records this way:
   - The same result in a new context adds that context. In a known context, nothing changes.
   - A different result, or a newer build, replaces the record, and the earlier contexts go with it. The import prints `Replaced <probe>`.
   - An accumulating probe's answer merges into the record already there from the same build, and so do its contexts, so a session that saw less never shrinks it.
   - A record in the one-context format, which holds a single context rather than a set, is skipped until its probe runs again. The import names those records in one line.
3. Run `node tools/tlk.mjs probes`. It prints each probe with its needs, the client's and the harness's answers, and whether they match, then what's left to do in game.

`probes --check` fails when an answer comes from another build than the API snapshot, from a probe that no longer exists, or from another version of its probe. `probes --check --warn-builds`, as CI runs it, only warns about another build.

#### Probe what can't be read

What a vibration feels like can't be probed, so `/btdev rumble` is a tester as well. `/btdev rumble <type> [intensity 0-1] [seconds]` plays one vibration, exactly as typed, and stops it after the seconds. Without the seconds, it plays until it stops by itself, which answers whether the client stops a vibration on its own. `/btdev rumble stop` stops it.

`input.events` hears switching the interface style (**Options** > **Gamepad**), unplugging and replugging a controller, and a battery change.

#### Probe versions and results

A probe whose result changes shape declares a higher `version`. A record made by another version answered a different question, so `/btdev probe list` asks for it again, the import skips and drops it, and the tests treat the probe as unanswered.

`tests/probes.test.lua` runs every probe in the harness, once for each context its record holds, and it must match in every one. A probe whose answer differs from the client's fails, with the differing fields. Fix the harness, and mark the behavior `[E]`.

A probe is pending when it has no answer, or when the harness can't run it (bags, vendors, trainers, flights, font objects, texture files, others' addon messages during a restriction, and XP at the max level). `test` prints it as `PEND`, and it doesn't fail the run. Any test can call `pending(reason)` the same way.

## TheLanKrewToolKit

Type `/tlk` (or `/lankrew`) to show or hide the settings window. The addon-menu button does too.

The main page holds the Fuck-o-meter, the session journal, and debug output. The **Controller**, **Krew**, **Scholar's challenge**, **Sounds**, and **Warband** pages sit under it. Every page lists its settings alphabetically, in sections, each led by the switch that turns its feature on. The same settings sit in Blizzard's settings, under Esc > **Options** > **AddOns** > **The Lan Krew ToolKit**.

> [!WARNING]
> With a controller, use `/tlk`. The controller can't reach the settings in Blizzard's panel: controller focus on an addon's controls there freezes the game.

`/tlk help` lists commands. To change any setting, type `/tlk set <setting> <value>` or `/tlk toggle <setting>`.

If something seems off, these commands show what the addon is doing (see [Diagnostics](docs/Architecture.md#diagnostics)):

- `/tlk debug status` shows which features are running, and any errors caught.
- `/tlk debug events` shows what the addon listens to, and how often.
- `/tlk debug work` shows which features do the most work, and, after `/tlk debug profile`, how long it takes.
- `/tlk debug cpu` shows its share of the game's time and memory.
- `/tlk debug trace <setting or fact>` prints changes as they happen.

### Fuck-o-meter

The Fuck-o-meter is a blown-up energy bar stretched across the middle of the screen. It shows whenever your power type is energy (rogues and cat-form druids). The bar glides to each new value rather than jumping. To toggle it, type `/tlk fom`.

### Sounds

Players bind their own sounds to game moments. The addon ships no audio. To add a sound:

1. Put the files in `TheLanKrewToolKit\Media\`, as `.ogg` or `.mp3`. Each one is optional.
2. Fully restart the game.

> [!IMPORTANT]
> The client only sees files that existed at launch, so a new sound file needs a full restart of the game.

If a sound has both an `.ogg` and an `.mp3` file, the `.ogg` wins.

**Variants:** numbered copies such as `FinishHim2.ogg` up to `FinishHim5.ogg` add variety. Each time a sound plays, one of its files is picked at random. Give `CombatStart` a few, and every fight gets a track from your battle playlist.

To test your sounds:

- `/tlk sound <name>` plays one at random.
- `/tlk sound <name> 2` plays that variant.
- `/tlk sound` lists every name.

The addon asks the client which of your files exist, so a test that plays nothing tells a missing file from a muted channel.

The settings have a toggle per sound (or per family, like the combo points), a volume channel (**Master** by default), and an option to fade out the combat start sound when combat ends. The master switch silences them all. A switched-off sound registers no events at all.

| File | Plays when | Test |
| --- | --- | --- |
| `CombatStart` | You enter combat | `start` |
| `QuestReady` | One of your quests is ready to turn in | `quest` |

#### Mortal Kombat

| File | Plays when | Test |
| --- | --- | --- |
| `ChooseYourDestiny` | A living enemy player becomes your target, or your target becomes attackable (a duel starts). At most every 10 seconds. | `destiny` |
| `TestYourMight` | A living elite, rare elite, world boss, boss, or skull-level enemy becomes your target, including a player far above your level. It plays instead of destiny. At most every 10 seconds. | `might` |
| `FinishHim` | Your enemy-player target is in finishing range, once per target. Warriors: Execute becomes usable (below 20%). Rogues and druids: 5 combo points. | `finish` |
| `ComboPoint1` to `ComboPoint5` | Rogues and druids: each combo point you add. On an enemy player, finish him takes the fifth. | `combo1` to `combo5` |
| `FlawlessVictory` | Your enemy-player target dies, or yields a duel, during a fight in which you haven't been hit | `flawless` |
| `Fatality` | Your enemy-player target dies in your fight after finish him | `fatality` |
| `SuperbVictory` | Any other kill of your enemy-player target in your fight | `superb` |
| `DeathTaunt` | You die | `taunt` |

A kill plays one victory sound: flawless, else fatality, else superb, whichever is first and switched on. A kill someone else makes while you're out of combat plays nothing.

"Flawless victory" means you took no damage in the fight. Addons can never read your health in Forever (it's hidden even out of combat), so a hit is what Blizzard's own player frame shows as one:

- Heals and regeneration don't count, and neither does a hit a shield fully absorbed.
- A hit in the second before the game says combat started (an ambush) counts.

The sound plays at the kill. The victory itself counts when the fight ends, once Blizzard's damage meter confirms you took no damage. The meter can keep its numbers hidden a moment after a fight, so the check waits for them. The Krew hears about confirmed victories only.

**Duels:** a duel ends at 1 HP rather than death, and the client doesn't tell addons who won. Winning one without taking a hit counts, since you can't lose a duel you weren't hit in. A duel you were hit in plays nothing, and fleeing out of bounds doesn't count. The client doesn't say whose duel ended either, so a duel counts only when your opponent was already your target as the duel started.

For warriors, "finish him" relies on Execute being usable, so it's silent in Defensive Stance. It doesn't fire when you merely lack rage, and neither switching stances nor a `/reload` repeats it.

Combo points sit on the target, as in Blizzard's own combo frame. So switching targets starts the count over, and so do points that move to another unit. For classes without a finisher, finish him, fatality, and the combo callouts cost nothing.

An enemy hunter's Feign Death may look like a death to the client, so it can trigger a victory sound.

#### Kill streaks

Kill streaks are an Unreal Tournament announcer for your world PvP killing blows (your pet's count too), with a raid warning on your screen for each. Kills in battlegrounds, arenas, or other instances don't count. As in Unreal, a kill belongs to whoever landed it. An honorable kill credits everyone in your group nearby, so it isn't what streaks count.

| Moment | Files | When |
| --- | --- | --- |
| First blood | `FirstBlood` | Your first killing blow of the session, unless a Krew member drew it first |
| Multi kills | `DoubleKill`, `MultiKill`, `MegaKill`, `UltraKill`, `MonsterKill`, `LudicrousKill`, `HolyShit` | 2 to 8 or more kills, each within 10 seconds of the last |
| Sprees | `KillingSpree`, `Rampage`, `Dominating`, `Unstoppable`, `Godlike`, `WickedSick` | 5, 10, 15, 20, 25, and 30 kills without dying |

A kill announces one moment: a spree it reaches, else a multi kill, else first blood. The Krew sees a raid warning for your first blood and each spree. It hears when a spree of five or more ends, and who ended it when the client says. Kill streaks can be switched off, and so can sharing them.

### Controller light bar and rumble

On the **Controller** page, under **Light bar** and **Rumble**:

- **Light bar:** red in combat, yellow when AFK, and green otherwise. It's cleared on logout or when the feature is disabled.
- **Rumble:** strong when combat starts, and light when it ends. It's stopped on logout or when the feature is disabled.
- **Quest ready:** when one of your quests is ready to turn in, the light bar turns gold for three seconds and the controller rumbles lightly. Each has its own setting under the light bar and the rumble. Combat's red wins over the gold.

The addon reads your quest log's objectives once for each burst of quest log updates, and never in combat: progress made in a fight is read when the fight ends. Quests already in your log when the addon starts, or after a `/reload`, count from where they are.

### Cards

The journal, the Krew, Warband, and the Scholar's challenge celebrate (and ask questions) with cards at the top of the screen, one at a time.

- **Cards never interrupt a fight.** One earned mid-combat appears when combat ends. One showing when combat starts steps aside, and comes back first when combat ends.
- **Hover over a card to keep it.** Select it to dismiss it and see the next. Otherwise, it hides after 12 seconds.
- **At most six wait in line.** Beyond that, new ones are dropped.

Some cards ask a question, like Warband's grudge card. Select the card to answer yes, or right-click it to answer no. With a controller, the card says how:

1. Press Select (**View** on Xbox, **Create** on PlayStation) while the question shows. The card holds still and takes the controller.
2. Press A (Cross on PlayStation) for yes, or B (Circle) for no. Press Select again to let go without answering.

Until you press Select, every button does what it always does. A fight takes the card away, and it comes back, unanswered, when the fight ends.

### Session journal

The journal celebrates your play, per character, with cards.

- **Welcome back:** at login after 30 minutes or more away, a card recalls your last session: where you were, how long you played, quests turned in, gold earned, and levels reached. It also shows how much rested XP you built up while away. A `/reload` or loading screen doesn't show it, and a reload continues the session.
- **Ding!** At level-up, a card sums up the level you finished: time played at that level, quests, gold, and trips to the spirit healer (or "not a single death!"). Every tenth level and max level get a milestone line. Until your first ding with the journal installed, it counts "since the journal started".
- **`/tlk journal`** shows this session's highlights so far.

Each card can be switched off in settings. Turning the journal off keeps the played time so far.

### Krew

Friends in your group who also run the toolkit share fun moments, each as a card:

- **Roll call:** when you group up, a card shows who else runs the toolkit. `/tlk krew` lists them and the version each runs. When two or more of them run a newer version than yours, chat says so once per group. Someone who leaves the group leaves the list once the roster settles, a second after the last change.
- **Ding:** your level-ups.
- **Flawless:** your flawless victories (needs the "Flawless victory" sound on).
- **Kill streaks:** your first blood and sprees, as raid warnings (see [Sounds](#sounds)).
- **Scholar:** riddles solved in the Scholar's challenge.

Warband's marks, grudges, sightings, rallies, and intel travel the same way. Each can be switched off, and turning Krew messages off stops all of it. It plays by Blizzard's addon rules, which forbid excessive use of the chat system:

- It uses hidden addon messages to your own party, raid, or instance group only. It never whispers, and never uses public channels or visible chat.
- It sends only on rare events, never on a timer, and at most one message a second. A queue of up to eight holds the rest. A rally goes first, and takes a waiting message's place when the queue is full. Anything beyond that is dropped.
- It never sends during chat messaging lockdown (encounters, Mythic+, and PvP matches). A celebration that can't go out then is dropped rather than sent late.
- Received messages are parsed strictly, and must come from your group. They only ever show a card or raid warning, update the Warband ledger, or set a map waypoint. None acts on your behalf.

### Warband

Warband is world PvP for a Krew that takes the war seriously. An account-wide ledger remembers three kinds of people, and the Krew can go to war with whole guilds. All of it is shared with the Krew:

| Kind | How someone gets there | What it means |
| --- | --- | --- |
| Grudge | They killed one of us (see the card below). Or `/tlk grudge` on your target or a name. | The Krew tallies their kills of us against ours of them: `Krew 3 : 5 Bob`. |
| Mark for death | `/tlk mark` on your target or a name. `/tlk unmark` lifts it (they stay a grudge). | The Krew hunts them. |
| Champion | `/tlk glory` on your target or a name. Works on either faction. | Someone the Krew aids. |
| Guild at war | `/tlk war` on your target (their guild) or `/tlk war <guild name>`. `/tlk peace <guild>` ends it. | Every member counts as an enemy of the Krew, with a tally of kills each way. |

When an enemy player kills you, a card names them and the killing blow ("Slain by Bob. Ambush for 700."). Left-click the card to hold the grudge, or right-click it to let it go.

Your three most recent marks (and wars) reach Krew members who join the group later, come back, or reload. They're packed into as few messages as fit, however many members say hello at once.

`/tlk ledger` lists everyone and every war, and `/tlk forgive <name>` removes someone. The right-click menu on a player offers the same choices, including war on their guild. A typed name can be in any case: `/tlk mark cara doe` finds Cara Doe in the ledger or among the enemies you've met, and a guild name finds a guild at war or one you've seen.

The ledger holds up to 300 people, and never forgets anyone on its own. When it's full, a new mark, grudge, or champion (yours or the Krew's) is turned away with a message in chat, and nothing is sent, until you forgive someone to make room.

**Rivalry records:** every enemy player you meet gets a record: class, level, guild, times seen, where, and the score against them. Times seen counts at most once a minute, and always the first time, even right after you mark someone by name. `/tlk rival <name>` shows the record, and tooltips show the score of anyone the Krew has fought. Ledger people's records are always kept. Past 1,000 records, the 100 strangers you've seen least recently make room.

**Nameplate badges:** marked enemies wear a skull above their nameplate, grudges a cross, members of a guild at war a square, and champions a star. The ledger is shared, so the whole Krew sees the same badges. They're your own markers: the game doesn't let addons set real raid icons.

**Nearby enemies:** a small window lists the enemy players you and your Krew have seen in the last 2 minutes, marked ones first, with class colors, level, how long ago, and who saw them. Right-click a name for the Krew's choices. Drag the window to move it. It shows itself when there's someone to list. New enemies you see are shared with the Krew in one batch, at most every 10 seconds.

- **Sightings:** when a ledger player's nameplate appears, or you target or mouse over them, a raid warning says so. The Krew hears where you saw them. A champion in a fight asks the Krew for aid.
  - Each person alerts at most once every 90 seconds.
  - In a brawl, the alerts that follow one within 3 seconds merge into one summary with one sound ("3 more grudges nearby: Bob Doe, Cara Doe, Dan Doe"). It lists marks first, then grudges, guilds at war, and champions. Your Krew still hears about every sighting.
  - A guild at war showing up in numbers raises one warning, not one per member.
- **Vengeance:** an honorable kill on a marked or grudge enemy settles the score for everyone, counted once however many of you got credit. Kills of anyone else count quietly in their record.
- **Rally:** `/tlk rally` calls the Krew to you. They get a raid warning and a map waypoint to your position.
- **Enemy gatherings:** when five or more enemy players show up on your nameplates within a minute in one place (a subzone), the Krew gets a card saying how many and where. Selecting it sets a waypoint. That's how to find the other faction's world events. There's one report per place every 5 minutes: once a Krew member has reported a gathering, the rest of the Krew neither sees it again nor reports it themselves.

Tips:

- Turn on enemy nameplates. Sightings and gatherings see what they see.
- Put `/tlk rally` and `/tlk mark` in macros on your action bars, so a controller can press them too.
- Sharing needs Krew messages on. Nothing is shared during battlegrounds, arenas, dungeons, or raids (chat messaging lockdown).

The client gives addons no combat log, but Blizzard's death recap names your killer: the killing blow's attacker, spell, and damage. Their kill of you counts in their record on its own, and it's always your choice on the card that makes it a grudge. A creature's kill asks nothing.

When the recap can't say (the damage meter is off, or a pet or totem landed the blow), the card asks "Slain by Bob?" about the enemy player you had targeted, or last targeted in the 30 seconds before. Only your choice on the card counts it.

Enemy names are readable outside PvP matches. Every message from the Krew is checked before use, and no escape codes from it reach the screen.

### Scholar's challenge

The Scholar's challenge asks young players riddles about their own quests, plus math and reading, set up by a parent. It's off by default and set per character, so turn it on for your child's characters only.

Math and reading alternate between quest riddles. Quest riddles, math, and reading can each be switched off. Many riddles use the character's own name, class, zone, and gold.

> [!NOTE]
> It's meant to be fun, not a hard limit. A controller's sticks still move the character, and a determined child can disable the addon at character select. For hard limits, use Blizzard's parental controls (play time limits in Battle.net account settings).

#### Quest riddles

Quest riddles are preferred: two in a row, then a math or reading riddle takes a turn, across a `/reload` too.

A quest riddle asks about the newest quest your child has accepted or turned in since it was last asked about. With none waiting, it asks about an older one for review: the one asked about longest ago. It asks one of these:

- who gave it
- who took it and where
- what it asked for (an item to bring, an enemy to defeat, or something to do), and how many
- which quest a giver gave
- a word missing from its text (English clients only)

What it asked for comes first, and the same kind of question doesn't come twice in a row about one quest.

Wrong answers come from your child's other quests first, then from the starting lands of your child's faction. A wrong answer is never one that's also true: not the zone around the right place, nor another quest the same giver gave or might have given (one nobody saw given).

Quests count from the moment they're shown. That includes ones an area trigger accepts without showing their text: those are in the quest log, so open it and read. Quests already in the log when the challenge is turned on are remembered too, for review. The last 30 quests are remembered, per character, while the challenge is on. With only quest riddles on, every riddle is about a quest, and one that comes due before any quest waits for the first.

It's an open-book test. **Quest book** (H, or the left shoulder) shows the quest on the riddle screen, as your child saw it, on a page below the riddle, which stays in view. The page scrolls when the quest is long. A quest too long for the screen scrolls like the quest log: with the mouse wheel, the Up and Down arrows, or the D-pad (hold it to keep going). A slim bar shows where you are, and the riddle never grows taller than the screen: when a long hint appears, the page gets shorter to make room. A quest's text is kept whole, as the quest log shows it. A quest that started from an item or an object (a wanted poster, say) reads "Started from" it, and one turned in at an object reads "Turned in at" it: riddles that ask who gave a quest, or who took it in, only ever ask about people.

Each wrong answer says why. One from another quest names it ("Marshal Dughan gave you a different quest: "The Fargodeep Mine"."). Who took a quest is always a choice for who gave it, and where it ended for where it began: the mix-up a reader makes. The hint says where in the quest book to look, a second miss walks to the line, and the answer comes with the line it's on.

A title that holds the answer's words ("Wolves Across the Border", for Tough Wolf Meat) isn't shown beside the question unless every choice shares them. A missing word's wrong answers are words of its kind: a noun for a noun, a place for a place.

#### When riddles come

A riddle comes after a set number of minutes of play (30 by default, 10 to 120) and, optionally, at each level-up. Play time is saved per character, so relogging doesn't skip a riddle. Time AFK, or with every subject switched off, doesn't count.

Once half the minutes are played, a good moment brings the next riddle early. Each of these can be switched off:

- a flight path (free time)
- a quest turned in (the riddle asks about it while it's fresh)
- a death (waiting to come back)

A riddle never comes in combat. It waits for the fight to end, and one on screen steps aside when a fight starts and comes back after. It doesn't come over Blizzard's windows either: a riddle that comes due while a quest dialog, gossip, a vendor, the mailbox, a bank, the auction house, a trainer, or the flight map is open waits for it to close. One already on screen stays.

`/tlk scholar` shows stars and the time to the next riddle. `/tlk puzzle` asks one now.

#### How a riddle works

The riddle covers the screen, and holds the mouse and keyboard until it's solved. Answer by pressing 1-4, by selecting an answer, or with the controller's face buttons. **Gate** mode must be solved. **Gentle** mode offers **Skip** after one wrong try.

Every riddle teaches. A wrong pick says why that answer is tempting but not it ("That's what you get if you add instead"), and each miss climbs a hint ladder:

1. the strategy
2. a worked first step
3. the working itself, with the right answer glowing, so the child finishes on the right idea

**Need a hint?** gives the rung the riddle is on. A right answer always shows the working, with praise for the strategy used, or for sticking with it after a miss. It never praises being smart.

After a miss, the answers left wait a moment before they can be picked, so trying every answer in a row doesn't work and the hint gets read. Each waiting answer's keycap counts the seconds down, and the wait grows with each miss on the riddle. **Need a hint?**, **Read aloud**, the quest book, and **Skip** still work while the answers wait. **Pause after a wrong answer**, under **Answers** on the **Scholar's challenge** page, sets it:

| Setting | After the first, second, and third miss |
| --- | --- |
| **Short** (the default) | 2, 4, and 6 seconds |
| **Long** | 4, 7, and 10 seconds |
| **Off** | No wait |

The choices can't be guessed by position. The mistake the riddle is about is always one of the choices. Among four numbers, the answer is a middle one no more often than that mistake's place allows: two times in three, where chance is one in two.

#### Math riddles

Math riddles offer the answer a known mistake gives:

- leaving out a carry or the trade of a ten
- adding instead of taking away or multiplying
- the bottom of a fraction
- longer-is-bigger for decimals
- working left to right
- counting by ones

Some kinds have mistakes of their own:

- **Place value** offers the digit for its worth (4 for the 4 in 347), the worth one place over, digits swapped or written in the order they were said, and 36 for 3 hundreds and 6 ones.
- **Clocks** offer half past read as :50 and a quarter as :25 (minutes counted like copper), quarter to read as quarter past, the hands swapped, the long hand's number read as minutes, an end time that forgets the new hour, and a length of time worked as if an hour had 100 minutes.
- **Number lines** offer a number that shares the target's first digit but sits farther off, and the jumps counted instead of what they're worth.

Each has a worked first step, and an explanation that shows the working: the carry, the partial products, or a percent built from a tenth, a half, or a quarter.

While the quest book holds a quest, math riddles count with it:

- how many more an objective needs ("Your quest book says Marshal McBride wants 10 Kobold Vermin defeated. Say you've defeated 8 so far.")
- two objectives' total
- what a vendor pays for a quest's items, sometimes added to your child's own copper
- how many quests are still to turn in

Math also covers place value, telling time (flight paths, boats, and dungeon runs), and the number line, from kindergarten up. Through grade 3, a star on a number line is drawn as a line with its ticks and labeled ends.

#### Reading riddles

Reading riddles offer the mix-ups real children make:

- **Rhymes** offer a word that starts the same but ends differently.
- **First-sound and heard-letter riddles** offer a letter whose sound is close (b and p, short e and short i, but never k for c).
- **Sight words** sit among real look-alikes (was and saw; the, they, and then; to, too, and two). A heart word's hint names the part that breaks the rules.
- **Letter teams** (sh, ch, th, wh, ck, and ng) blend a word's sounds, find the word that starts or ends with a team's sound, name the letters that spell a word's first or last sound, and show a word's sounds one by one. The wrong choices keep only one of the team's letters (sip or hip for ship), put another team or a near sound in its place (chip; fin for thin; rink for ring), or split the team into two sounds.
- **Blends** blend the sounds of words like flag, stop, and hand, or add a missing sound to a word. They always offer the word with a letter of the blend dropped.
- **Word scrambles** have wrong choices that share all but a letter with the answer, and a clue that waits for the second miss.
- **Stories** ask what happened, and also why, in what order, what a word means, and what the story is mostly about. Grades 2 and 3 read short stories of two to four sentences, with a question the story answers and one it only shows. Grades 4 to 6 read longer ones.

#### The riddle screen

The Owl Sage asks. The header shows the stars, a bar toward the next rank ("5 more to Journeyman"), and the streak. The story sits above the question, which has its own band, and numbers and target words are highlighted. For small numbers in the early grades, the riddle is drawn with the items it counts: bags of apples, two piles to join, or a pile with some crossed out. The big answers each have their key on a raised keycap. A wrong answer shakes, and the right one turns green while a "+1" rises.

- **Need a hint?** is free: the streak survives. On a quest riddle, it's the quest book, which stays beside the feedback after a wrong answer.
- **Read aloud** speaks the riddle and its choices with the game's text-to-speech voice. It reads a blank as "blank", and a spelling riddle's choices letter by letter. With the quest book open, it reads the book. After an answer or a hint, it reads the feedback.

#### For children still learning to read

Riddles are said aloud as they appear, with each choice and the key that picks it ("Press A for cat"). The **Read riddles aloud** setting decides when: kindergarten and grade 1 by default, always, or only when asked. Hovering over a choice says it again.

Kindergarten and grade 1 also get riddles that are heard, not read:

- The Owl Sage says a word, and the child picks the word they heard, or the letter it starts with, from the written choices.
- They also hear short stories, and answer who did something, what happened, how someone felt, or what came first. Each choice is said with its key after the story.

The word or story never appears on screen, and **Read aloud** becomes **Hear it again**. Speech uses the player's text-to-speech voice, rate, and volume. With no voice, nothing is said, and no heard riddle is asked.

The Owl reads quests aloud too, following **Read riddles aloud**. When a quest dialog opens, it says who's speaking and the quest's name, then reads the offer's story and what to do, the turn-in's question, or the words when it's turned in ("Eagan Peltskinner says: Wolves Across the Border. ..."). Closing the dialog stops it. Type `/tlk read` to hear the open quest again, whatever the setting says. **Read quests aloud**, under **Reading aloud** on the **Scholar's challenge** page, turns it off.

The Owl also counts quest progress aloud, following **Read riddles aloud**:

- When an objective goes up: "Tough Wolf Meat: 3 of 8. 5 more to go!" The last one is "all 8. Done!", and a one-step task is "done!"
- After a fight, it sums up what the fight got: "That fight got you 2 more! Tough Wolf Meat: 2 of 8. 6 more to go!" It keeps quiet during the fight.
- When a quest is ready to turn in: "Wolves Across the Border is ready to turn in!"

It keeps quiet while a riddle is on screen. **Count quest progress aloud**, under **Reading aloud** on the **Scholar's challenge** page, turns it off. It's behind the parent lock like the other challenge settings.

#### Controllers and keyboards

Every button shows its key for the device you're using.

| Action | Controller | Keyboard |
| --- | --- | --- |
| Answer | Face buttons | 1-4 |
| Ask for the hint | Left shoulder | H |
| Read aloud | Right shoulder | R |
| Skip (Gentle mode, after a try) | Back | Esc |
| Scroll an open quest book | D-pad | Up and Down arrows |

#### Difficulty and practice

Riddles are written for a chosen grade, and adapt within it, math and reading each on their own:

- Every third riddle in a row answered right on the first try makes that subject's riddles harder.
- Two misses on one riddle make them easier.
- Quest riddles never change the difficulty.

**Practice that remembers:** each skill (adding, skip counting, rhymes, spelling, who gave a quest, and so on) is tracked per character, the way flash cards are reviewed.

- A riddle answered right on the first try moves its skill up a box (five in all), and a miss sends it back to the first.
- A skill comes due again after 1, 2, 4, 8, or 16 more riddles of its subject, by its box, so a missed skill comes back at the next one.
- The next math or reading riddle favors new skills and due ones, the lower their box the likelier. A skill in box 3 or above that isn't due yet sits out.
- A math fact a riddle asked (7 × 8, 9 + 6) is remembered the same way, so a missed fact comes back as itself, not only as another multiplication riddle.
- The last 40 riddles shown aren't repeated, across a `/reload` too.

**Stretch riddles:** about one math or reading riddle in five comes from a grade or two above, at its easiest. Like the classic learning games, it raises the bar with a child's progress, not their age. A stretch riddle:

- is tagged STRETCH
- gives its help a rung sooner: the first miss already shows the worked step, and the second shows the working, with the answer glowing
- is worth two stars
- never makes the child's own riddles easier when it's missed

#### Rewards

A riddle earns a star, and there are streaks and scholar ranks (Apprentice, Journeyman, Adept, Sage, and Archmage), each with a card.

#### Parent lock

- `/tlk lock <pin>` (4 to 8 digits) locks every Scholar setting, including the on switch, in slash commands and the settings window.
- `/tlk unlock <pin>` unlocks it for the session (a `/reload` keeps it unlocked). It locks again at the next login.
- While it's locked, the PIN can't be changed. Unlock first.
- After three wrong PINs, unlocking waits a minute, even across a `/reload`.
- The PIN is saved as a hash. That keeps it from sitting in the file as-is, but it isn't real security.

#### Report card

`/tlk report` shows a parent how it's going: riddles answered, and the share right on the first try. Then, for math, reading, and quests, it shows:

- the level
- the skills mastered (box 4 or above)
- the skills being worked on: the last first try missed, so it comes right back, or, after three riddles, fewer than half of the last five were right
- the five most recent misses, with the answer chosen and the right one

## License

Dual-licensed under [Apache-2.0](LICENSE-APACHE-2.0.txt) or [MIT](LICENSE-MIT.txt), at your option.
