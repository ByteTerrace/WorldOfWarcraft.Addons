# ByteTerrace — World of Warcraft AddOns

AddOns for **World of Warcraft: Forever**, held to the same correctness and performance bar as Puck.

| AddOn | Description |
| --- | --- |
| [ByteTerrace_Core](ByteTerrace_Core) | The shared framework (Lua global `ByteTerrace`): state, commands, input, events, modules. See [architecture](docs/Architecture.md). |
| [TheLanKrewToolKit](TheLanKrewToolKit) | Utilities for The Lan Krew. |
| [ByteTerrace_DevTools](ByteTerrace_DevTools) | Development only (`## X-DevOnly`): `/btdev dump` records the client's globals for `tlk api-sync`, and `/btdev probe` records the client's answers to calibration probes for `tlk probes`. Never shipped. |

## WoW: Forever target

| | |
| --- | --- |
| Interface | `16001` (game version 1.60.1) |
| TOC file | `<AddOnName>_Camelot.toc`; the client's game type is `camelot` |
| API | Mainline (Midnight 12.x) UI and API, including secret values; Classic Era APIs don't apply |
| AddOns folder | Detected from the install's `.build.info` (the beta installs to `_classic_beta_`) |

Controller work: see [docs/ControllerSupport.md](docs/ControllerSupport.md).

## Development

Requires Node.js 22+. Every operation is a verb on one CLI:

```powershell
npm install                        # once
node tools/tlk.mjs check           # static gates
node tools/tlk.mjs test            # behavioral tests in real Lua 5.1 (filters or test files narrow it)
node tools/tlk.mjs test --coverage # the same, then which addon statements the Lua tests reached
node tools/tlk.mjs deploy          # check and test, then junction-link every addon (--no-test skips tests)
node tools/tlk.mjs package         # check and test, then zip the committed addons for players, in dist/
```

`package` ships every addon without `## X-DevOnly` (DevTools has it) as committed at HEAD, so it refuses uncommitted changes in a shipped folder and a shipped addon whose dependency stays behind, and players' own sounds, which git ignores, never ship. The zip is named after the addon nothing else depends on, with its `## Version`, and extracts straight into `Interface\AddOns`. Its players' guide is [TheLanKrewToolKit/README.txt](TheLanKrewToolKit/README.txt).

`deploy --addon <name>` includes the full dependency chain regardless of directory order. `deploy --unlink --addon <name>` removes only the explicitly selected addon's link.

The addons run straight from this repo. The loop:

| You changed | Do this |
| --- | --- |
| Lua in an existing file | `check` and `test`, then `/reload` in game |
| A TOC (new file, SavedVariables, metadata) | `deploy`, then **restart the game client**; `/reload` doesn't re-read TOCs |
| A new addon folder | `deploy`, then restart the game client |
| A new client build | `deploy` flags a stale `## Interface`; refresh the API snapshot (below) |

Turn on Lua error popups in game once: `/console scriptErrors 1`.

### Gates

`check` reports `path:line: RULE message`, and any finding fails it. A method call counts in every form it takes: `obj:M()`, and `obj.M(obj)` or `obj["M"](obj)` passing the receiver first. An annotation (`-- secret: <why>`, `-- protected: <why>`, `-- global: <why>`) is a `--` line comment on the construct's line, or alone on the line above it.

| Rule | What it enforces |
| --- | --- |
| PARSE | Every file parses as Lua 5.1. |
| TOC | Every addon folder has a `_Camelot.toc`. The TOC lists exactly the files present, each once, dependencies (`Dependencies`, `RequiredDeps`, `Dep*`) exist, and `## Interface` matches the installed client (the check says when it's skipped). |
| GLOBAL | Every global read exists in the client dump or a dependency, including reads through `_G.X`, `getfenv().X` and `getglobal("X")`. Every write is declared: SavedVariables, SavedVariablesPerCharacter, `AddonCompartmentFunc`, `SLASH_*`, or `## X-Globals`, whether written as `X =`, through `_G`, `rawset`, `setglobal` or `getfenv()`. A write with a dynamic key, `getfenv` with a level other than 0 or 1, `setfenv` and `loadstring` need `-- global: <why>`. It also flags assignments into client tables and frame names that collide with client globals. |
| MEMBER | Full member chains (`Enum.PowerType.Energy`, `C_Spell["X"]`, through local aliases) exist in the snapshot, and so does a client table's method called with `:` (`C_GamePad:X()`). |
| EVENT | Every event name passed to an event method is real, whether a literal or a file-level constant, and none registered (`On`, `RegisterEvent`, `RegisterUnitEvent`) is restricted to Blizzard's code (`HasRestrictions`, such as the combat log events). |
| SECRET | A call to a function that can return a secret (directly, through a never-reassigned alias, or through `getglobal`) is annotated, sits directly inside `issecretvalue(...)`, or assigns its results to fresh locals that are never reassigned and whose every use is dominated by a test: an `issecretvalue(x)` that returns early when true, a `not issecretvalue(x)` branch, the right side of `issecretvalue(x) or ...`, or `canaccessvalue(x)`. A check after a use, a discarded check, or storing the value before the check doesn't count. The annotation covers the call, not every later use: a local it fills can still be passed on, stored or indexed (a structure's fields), but comparing or computing with it, testing it or keying a table with it needs its own guard or annotation, whether the local is fresh or an existing one the call is assigned to. Passing such a function (or a secret-returning method, `obj.GetValue`) as a value needs the annotation. A widget getter counts, called with `:` or `.`, only when its file calls a setter that can make that aspect secret (for size and anchor getters, any such setter), so getters on frames a file never feeds secrets to, and on plain tables, pass. In a handler passed as a function literal to `On`, `RegisterEvent`, `SetScript("OnEvent")` or `HookScript("OnEvent")`, a parameter carrying a secret event payload field (or a local the handler's `...` fills, `local text = ...`) can't be compared, computed with, indexed, used as a table key or branched on unguarded, including through the result of an `and`/`or`. |
| PROTECTED | A function forbidden to addon code at any time is never called, since no guard helps: protected globals (`IsProtectedFunction`) and the functions the client refused, or that froze it, in game (`tools/api/forbidden.json`, which the harness reads too), such as `Settings.OpenToCategory` and `SettingsPanel:OpenToCategory`; taking one as a value (an alias, `pcall(SetRaidTarget, ...)`) is refused too, and taking a protected global as a value needs `-- protected: <why>`, since its calls skip the guard. A call that can be blocked during combat lockdown is dominated by an `InCombatLockdown()` test that returns early (directly, or through a never-reassigned local of the same function that holds its result), sits in a `not InCombatLockdown()` branch, or is annotated. A discarded `InCombatLockdown()` doesn't count, and a closure doesn't inherit its definer's guard, nor a local its definer kept. That covers restricted functions (`HasRestrictions`), `HasRestrictions` methods (`SetPropagateKeyboardInput`) on any receiver, and protected methods on a frame from a Secure template, followed through locals, aliases and fields. In a file that creates a Secure frame, a protected method on any receiver the gate can't prove non-Secure (a parameter, say) needs the guard too. |
| NAMING | Puck's naming, mapped to Lua ([conventions](docs/Conventions.md)). Functions, methods and file-level locals (constants included: `MaxQueue`, never `MAX_QUEUE`) are PascalCase, and so is a local declared ahead and given a function later. Locals inside functions, loops and branches, parameters and loop variables are camelCase. Aliases keep their source's name (`local floor = math.floor`), and a file's own `local addonName, ns = ...` and metamethods are exempt; any other local filled from `...` follows the rules. Member names are review, not gate. |
| COMMENT | No banner dividers (four or more of `- = * # _ ~`) and no debt markers (`TODO`, `FIXME`, `HACK`, `XXX`, `KLUDGE`, `REVISIT`, "for now"). A `---` doc comment's third dash doesn't count. |
| FRAMEWORK | An addon that depends on `ByteTerrace_Core` doesn't call a client API the framework owns (`C_Timer`'s timers, addon message sending (logged too) and prefixes, `PlaySoundFile`, settings and settings-category registration), take one as a value, or handle `CHAT_MSG_ADDON` or `CHAT_MSG_ADDON_LOGGED`: module timers, comms and the sound bank handle timers, messages and sounds; settings come from declared rows, drawn in the addon's own window. |
| LENGTH / STYLE | 800-line ceiling; LF, final newline, no tabs, no trailing whitespace. |

NAMING, COMMENT, LENGTH and STYLE also cover the tests' Lua (`tests/*.test.lua` and `tests/harness`, not the deliberately bad `tests/fixtures`); LENGTH and STYLE cover `tools/` and the tests' JavaScript.

What `check` can't see: dynamic reads (`_G[name]`, `getglobal(name)`), values that cross files or functions (a Secure frame or a secret handed to another file, an event name passed to a wrapper), secrets reaching state through a callee, and handlers that aren't function literals. Its guard analysis is per function and doesn't follow loops or `goto`.

`test` runs `tests/*.test.lua` in real Lua 5.1 (WebAssembly) against a fake Forever client (`tests/harness`). Each file runs in its own worker with a timeout that starts after the worker's setup. The fake is strict:

- **Secret values** are opaque and throw on comparison, arithmetic, length, indexing, `tonumber` and `print`. As in the client, concatenation, `tostring` and `format` (including `("%d"):format(x)`) accept them and return secret strings; a precision on `%s` is refused. Lua can't catch what the client refuses of a boolean test (a secret boolean), `== plainValue`, a secret compared with itself, or a secret table key; the SECRET rule covers those.
- **When values are secret** follows each flag's predicate under a restriction model: combat, encounter, challenge mode, PvP match, restricted map and chat lockdown. Some predicates follow Blizzard's documented text, others are conservative fallbacks where the docs are silent (`SecretReturns`, anchoring, threat, unknown flags); `tests/harness/secrets.lua` lists which. Some flags depend on the unit (player-controlled, in your group). A unit the test hasn't set (`h:SetUnit` for pet, focus, party, mouseover and nameplates) doesn't exist, so it isn't secret.
- **Restriction changes** fire `ADDON_RESTRICTION_STATE_CHANGED`: Activating before the restriction applies, Active once it does, Inactive after it lifts. Combat follows what the client did (probe `combat.edges`): `PLAYER_REGEN_DISABLED` comes first, then Combat Activating and no Active; leaving, Combat Inactive comes before `PLAYER_REGEN_ENABLED`, so the damage meter is readable by then.
- **Addon code is tainted,** so passing a secret (or a table holding one) to an API errors unless its documented `SecretArguments` allows it. Undocumented client functions (`PlaySoundFile`, `PlaySound`, `StopSound`) refuse secrets.
- **Blocked calls** do nothing, fire `ADDON_ACTION_BLOCKED` and land in `h.blocked`; the caller keeps running, like the client. A blocked call fails the test, as the client shows the player it, unless the test expects it (`h:ExpectBlocked(count or patterns)`). Protected methods on protected frames and `HasRestrictions` functions are blocked during combat lockdown, and protected globals and the functions in `tools/api/forbidden.json` are always forbidden (`ADDON_ACTION_FORBIDDEN`). Registering a restricted event (`HasRestrictions`, such as `COMBAT_LOG_EVENT_UNFILTERED`) is forbidden the same way and registers nothing. The docs don't say what `HasRestrictions` means; lockdown is the harness's guess, unless the entry names a specific restriction (`RestrictedForMacroChatMessages` applies to macros, so addon calls pass).
- **SavedVariables** are nil while an addon's files run and restored just before its `ADDON_LOADED`. `h:Reload()` and `h:Relog()` write them the way the client does: numbers, strings, booleans and tables of them, as copies, without cycles, NaN or inf. A secret value or a secret table key there is an error. A relog ends combat and restrictions.
- **Only real APIs exist:** events, widget methods, and fakes that name real client globals. Reading an undefined global is an error. Only what the addons and probes call is faked: a fake nothing calls is deleted, with its tests. `test` checks it: a fake function (a global, or a member of a global table) whose name appears nowhere in the addons' code (identifiers and strings, not comments) fails, unless `tools/api/forbidden.json` names it, since those fakes exist to refuse the call. Lua's own functions are exempt, and so are widget methods: every documented method of a widget type exists and counts its calls, and the getters with behaviors are how tests read widget state. A documented function refuses a nil argument the docs don't mark `Nilable` or give a `Default` (a `LuaValueReference` takes any value; widget methods are exempt, since the docs can't state overloads like `SetPoint("CENTER")`). `h:Fire` refuses a payload with more values than the event documents, a nil (or a missing value) where the docs say `Nilable = false`, a secret in an event without secret flags, or a number, string or boolean where the docs say another of those; `h:FireChat(event, text, sender)` and `h:LevelUp(level)` fire full payloads.
- **A test fails** on any error reported to the client's error handler.
- **Every widget call and API call is counted,** so tests can assert how much work each event does (`h:CountCalls(method)`, `h:CountApiCalls(name)`). Widget state lives beside the widget (`Harness.State(widget)`), so addon fields never collide with it. `h.profiler` holds what `C_AddOnProfiler` and `GetAddOnMemoryUsage` answer.
- **Groups and addon messages:** `h:JoinGroup(kind, names)`, `h:AddMember`, `h:RemoveMember` and `h:LeaveGroup` fire the client's group events and give members party or raid tokens (`h:SetUnit` tokens win over them). `C_ChatInfo.SendAddonMessage` checks, in order, the prefix, the message, the chat type, messaging lockdown (encounter, challenge mode, PvP match, restricted map, chat; not combat alone), group membership, then a per-prefix throttle of 10 messages that regains one per second. Sent messages land in `h.addonMessages` with their result, and your own group messages echo back on the next `h:Advance` (`h:Echo(false)` turns that off). `h:ReceiveAddonMessage(prefix, text, channel, sender)` delivers one from someone else. Names follow Forever, as probed in game: players have a surname (`Harness.DEFAULT_SURNAME` unless a test gives one), `UnitName` returns first name and surname, and senders are "First Last" (`h:FullName`), with "-Realm" only for another realm.
- **Keyboard:** `h:Key(key, down)` offers a key to keyboard-enabled frames topmost first (strata, then level, then newest). A frame consumes it unless its propagate flag is set after its script runs; unconsumed keys land in `h.propagatedKeys`. `h:WorldClickBlocked()` says whether a mouse-enabled frame covers UIParent.
- **Guilds:** unit tables and `Harness.New` take `guild`, `guildRank`, `guildRankIndex` and `guildRealm` (nil = the player's realm). `GetGuildInfo` returns name, rank, rank index and another realm's name, and nothing without a guild. GUILD addon messages need the player's guild.
- **Damage meter:** every combat is a `C_DamageMeter` session: Current is the latest and Overall all of them; Expired stays empty after ordinary fights, as it did in game. `h:MeterFight{ name, duration, sources }` scripts a fight (amounts, spells, deaths with `C_DeathRecap` recaps), then leaves combat, or dies if the player's source died. A recap's events are combat log events like the game's: melee `SWING_DAMAGE` carries no spell fields, while `SPELL_DAMAGE` carries spell identity and avoidable/deadly flags. A spell's `details.unit` makes that unit the attacker, GUID and all (`GetPlayerInfoByGUID` knows it). Recap probes compare common event fields and the killing blow's common shape; separate probes wait for swing or spell damage before checking its spell fields. In combat every damage-meter field is secret except the documented never-secret ones.
- **Frames:** `OnShow`/`OnHide` run when visibility changes, children included. `h:Drag(frame, dx, dy)` runs `OnMouseDown`, `OnDragStart` and `OnDragStop` for a movable, mouse-enabled frame registered for the button; its anchors shift by the drag, where the client re-anchors to the nearest screen corner. A `ScrollFrame` scrolls its child: its range is the child's height less its own. `h:MouseWheel(frame, delta)` turns the wheel over a frame with the wheel enabled. `UIParent` is 1366 x 768, the screen at UI scale 1.
- **Speech:** `C_VoiceChat.SpeakText` and `C_CombatAudioAlert.SpeakText` land in `h.spoken`; combat audio alerts speak only when the player turned them on (`h.combatAudioAlerts`).
- **Quests:** `h:OfferQuest(spec, giver)` opens a giver's offer panel and `h:AcceptQuest()` accepts it; `h:AutoAcceptQuest(spec)` is an area trigger's quest, straight into the log with no dialog; `h:OpenTurnIn(id, ender, reward)` and `h:CompleteQuest()` turn one in. The dialog's texts, `GetQuestID`, the `questnpc` unit and the quest log (`C_QuestLog`, `GetQuestLogQuestText`) answer as the quest probes recorded in game. An accumulating probe matches when the harness shows nothing the client's sessions didn't.
- **World PvP:** `h:AddNamePlate(unit)` and `h:RemoveNamePlate(token)` fire the nameplate events; a plate shows before `NAME_PLATE_UNIT_ADDED` and hides after `NAME_PLATE_UNIT_REMOVED`, with any frames parented to it. `h:SetMouseover(unit)` fires `UPDATE_MOUSEOVER_UNIT` (clearing it fires nothing, like the client). `h:Die()`, `h:ReleaseSpirit()` and `h:Revive()` fire `PLAYER_DEAD`, `PLAYER_ALIVE` and `PLAYER_UNGHOST` as the client does, and death ends combat. `SetRaidTarget` is forbidden to addon code, as the client refused it in game. `h:HonorKill(victim, rank, honor)` fires the honor message with Forever's enUS text. A unit's `classification` field answers `UnitClassification`, and `h:SetComboPoints(n)` puts your combo points on the target and fires `UNIT_POWER_FREQUENT`, as Blizzard's combo frame expects.
- **Maps:** `h:SetLocation{ zone, subZone, mapID, x, y, instance }` fires the zone events. `h:AddMap(id, spec)` declares a map; a map the test hasn't added doesn't exist. The user waypoint lands in `h.waypoint`.
- **Blizzard UI:** `h:OpenMenu(tag, contextData)` and `h:OpenTargetMenu()` run `Menu.ModifyMenu` callbacks and return a menu you can `:Click(text)`. `h:ShowUnitTooltip(token)` runs the unit tooltip post calls, with the lines in `Harness.State(GameTooltip).lines`. Raid warnings land in `h.raidNotices`. `MenuUtil.CreateContextMenu` opens a menu that `h:OpenContextMenu()` returns. `RAID_CLASS_COLORS` holds each class's `r`, `g`, `b` and `colorStr`.
- **Settings:** `Settings.RegisterCanvasLayoutCategory` makes a category whose page is the addon's own frame, and `Settings.RegisterAddOnCategory` lists it under Esc > Options > AddOns. `h.categories` lists every category registered; `h.category` is the listed one. Opening Blizzard's panel from addon code is forbidden.
- **Randomness** is the harness's own seeded generator (`h:SeedRandom(n)`), behind both `random` and `math.random`, so tests are repeatable.
- **Sizes are stand-ins:** 7 px per character and 14 px per line, so layout arithmetic runs.

`test --coverage` lists, per addon file, the statements no Lua test reached, by line. It counts per function, so a nested function's lines don't count for the code around it, but it sees lines, not statements: statements that share a line share its hit, so `if not ready then return end` counts its return whenever its test ran. It's a report, not a gate, and the line hook makes the run several times slower.

What `test` can't show: the real client's rendering, layout, taint propagation, hardware-event rules and per-spell secrecy exceptions. Its formatting fakes (`GetMoneyString`, `SecondsToTime`) aren't Blizzard's exact output. Verify those in game.

`tests/*.test.mjs` test the tooling itself:
- the check gate runs over fixtures with one violation per rule, and one for each allowed construct;
- they also cover api-sync, the probes verb, the test runner and deploy's argument and link handling.

### API snapshot

`tools/api/forever.json` is what the gates and harness treat as the real API. It has two halves, one entry per line:

- **Documented half,** from Blizzard's docs: every function, event and widget method, with its secret flags, `SecretArguments` policy, protection and restriction flags, precondition markers (`Requires*`, `Restricted*`), aspects, argument and payload types and which of them may be nil, plus the documented enums.
- **Globals half,** from a dump of your client: every global the client itself defines and the member names of its tables. Enum members go one level deeper. Anything an addon set is excluded, found by taint.

The documented half says which flags an API has; what a flag means comes from Blizzard's predicate text, and the harness's reading of each is marked documented or conservative in `tests/harness/secrets.lua`.

The snapshot's `source` field records where each half came from. `api-sync` refuses an implausibly small dump and warns when the two halves come from different builds. Refresh both halves when the client build changes:

1. Refresh the documented API from Blizzard's Forever UI source (the `forever` branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/forever)):

   ```powershell
   node tools/tlk.mjs api-sync --docs <wow-ui-source>/Interface/AddOns/Blizzard_APIDocumentationGenerated
   ```

2. Refresh the globals from your own client:
   1. With ByteTerrace DevTools enabled and every addon that isn't ByteTerrace's disabled, type `/btdev dump`, then `/reload`. The dump leaves out every name an addon touched, so another addon that replaced a client global would leave it out of the snapshot; `api-sync` warns when the dump skipped anything for an addon outside this repository.
   2. Run:

      ```powershell
      node tools/tlk.mjs api-sync --globals "<WoW>/_classic_beta_/WTF/Account/<account>/SavedVariables/ByteTerrace_DevTools.lua"
      ```

### Probes

When the harness has to guess how the client behaves, a probe asks the client. ByteTerrace DevTools defines each probe once: what it needs (a target, a quest dialog, combat), a read-only question, and a harness setup that recreates the need. `Probes.lua` is the engine, `ProbeNeeds.lua` the situations, and `ProbesWorld.lua`, `ProbesUnits.lua`, `ProbesCombat.lua` and `ProbesNames.lua` the probes. The game runs the files through DevTools and the harness runs the same files, so both answer the same question in the same situation. Answers record shapes (a type, a secret marker, a color's bytes), never character-specific data. DevTools also listens from the moment it loads for `UNIT_COMBAT` and `UNIT_AURA` on the player and the target, for the kill events, for chat senders and their `discordInfo`, for addon messages, and for the steps into and out of combat (`PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED` and the Combat restriction's changes, with what `InCombatLockdown`, `UnitAffectingCombat` and `IsAddOnRestrictionActive` said at each), since those probes can't ask after the fact. It keeps only the set of shapes each has shown, so a shape seen before costs one table lookup, and it follows the restrictions in force from `ADDON_RESTRICTION_STATE_CHANGED`, so the aura and addon-message listeners key what they hear by them without asking the client.

1. In game, type `/btdev probe`. It runs every probe whose needs are met, adds the answers to the ones already saved, and lists what the skipped probes need, in play-session order. Set that up and type it again. `/btdev probe list` shows what's still missing, grouped under the same steps.

   One session in a starting zone covers most of them. Type `/btdev probe` at each step:

   1. **Anywhere:** right after logging in, with a quest in your log and your hearthstone in your backpack. With a controller connected, press one of its buttons first. Once someone has spoken in say or General, type it again for the chat probes.
   2. **At a quest giver:** press Shift+V for friendly nameplates and face them, target them, then open a quest you haven't accepted, and later a quest turn-in's reward panel (before you click Complete Quest).
   3. **At a vendor or trainer:** open the vendor's window, then your class trainer's.
   4. **Fighting mobs:** target a mob out of combat, then pull it, press V for enemy nameplates and type the command mid-fight. Trade a few blows first, so the combat feed has something to show, and let a buff or debuff land on you or the mob (a class spell or the mob's own). Kill it yourself and type it again right away, before the next pull, then kill a second mob and type it once combat ends, for the order of the steps out of combat.
   5. **After a mob kills you:** let one win, wait five seconds, and type the command while you're dead or a ghost.
   6. **Later:** resting in an inn, on a flight path, in a party, in a guild, targeting an enemy player, targeting an enemy hunter while they Feign Death, targeting a mob in a dungeon between pulls, on a rogue or a cat-form druid (combo points), and on a character at the max level. For the addon-message probe, run a dungeon (a boss fight too, if you can) in a party with someone running The Lan Krew ToolKit, then type it after you leave, still grouped, without a `/reload` in between. These can wait until you leave the starting zone.

2. `/reload`, then import:

   ```powershell
   node tools/tlk.mjs probes --import    # the installed client's SavedVariables; or pass the file
   ```

   The answers land in `tools/api/probes.json`, sorted by probe, with the client build. An accumulating probe's answer merges into the record already there from the same build, so a session that saw less never shrinks it.
3. `node tools/tlk.mjs probes` prints each probe with its needs, the client's and the harness's answers, and whether they match, then what's left to do in game. `probes --check` fails when an answer comes from another build than the API snapshot, from a probe that no longer exists, or from another version of its probe.

A probe whose result changes shape declares a higher `version`: a record made by another version answered a different question, so `/btdev probe list` asks for it again, the import skips and drops it, and the tests treat the probe as unanswered.

`tests/probes.test.lua` runs every probe in the harness. A probe whose answer differs from the client's fails, with the differing fields; fix the harness and mark the behavior `[E]`. A probe without an answer, or one the harness can't run (bags, vendors, trainers, flights, font objects, texture files, others' addon messages during a restriction, XP at the max level), is pending: `test` prints it as `PEND` and it doesn't fail the run. Any test can call `pending(reason)` the same way.

## TheLanKrewToolKit

`/tlk` (or `/lankrew`) shows or hides the settings window (the addon-menu button does too). The same settings sit in Blizzard's settings under Esc > Options > AddOns > The Lan Krew ToolKit, where the controller can't reach them (controller focus on an addon's controls there freezes the game), so with a controller, use `/tlk`. The main page holds the Fuck-o-meter, the session journal and debug output, and the Sounds, Controller, Krew, Warband and Scholar's challenge pages sit under it. `/tlk help` lists commands. Any setting can be changed with `/tlk set <setting> <value>` or `/tlk toggle <setting>`.

If something seems off, `/tlk debug status` shows which features are running and any errors caught, `/tlk debug events` what the addon listens to and how often, `/tlk debug cpu` its share of the game's time and memory, and `/tlk debug trace <setting or fact>` prints changes as they happen (see [Diagnostics](docs/Architecture.md#diagnostics)).

### Fuck-o-meter

A blown-up energy bar stretched across the middle of the screen, shown whenever your power type is energy (rogues, cat-form druids). Toggle it with `/tlk fom`.

### Sounds

Players bind their own sounds to game moments. The addon ships no audio.

1. Put the files in `TheLanKrewToolKit\Media\`. Each one is optional.
2. Fully restart the game; the client only sees files that existed at launch.

If both files exist, `.ogg` wins. **Variants:** numbered copies such as `FinishHim2.ogg` up to `FinishHim5.ogg` add variety, and each time a sound plays, one of its files is picked at random. Give `CombatStart` a few and every fight gets a track from your battle playlist. `/tlk sound <name>` plays one at random, `/tlk sound <name> 2` plays that variant, and `/tlk sound` lists every name. The addon asks the game which of your files exist, so a test that plays nothing tells a missing file from a muted channel.

There's a toggle per sound (or per family, like the combo points), a volume channel (Master by default), and an option to fade out the combat start sound when combat ends. The master switch silences them all. A switched-off sound registers no events at all.

| File | Plays when | Test |
| --- | --- | --- |
| `CombatStart` | You enter combat | `start` |

**Mortal Kombat:**

| File | Plays when | Test |
| --- | --- | --- |
| `ChooseYourDestiny` | A living enemy player becomes your target, or your target becomes attackable (a duel starts). At most every 10 s | `destiny` |
| `TestYourMight` | A living elite, rare elite, world boss, boss or skull-level enemy becomes your target, including a player far above your level. It plays instead of destiny. At most every 10 s | `might` |
| `FinishHim` | Your enemy-player target is in finishing range, once per target. Warriors: Execute becomes usable (below 20%). Rogues and druids: 5 combo points | `finish` |
| `ComboPoint1` to `ComboPoint5` | Rogues and druids: each combo point you add. On an enemy player, finish him takes the fifth | `combo1` to `combo5` |
| `FlawlessVictory` | Your enemy-player target dies, or yields a duel, during a fight in which you haven't been hit | `flawless` |
| `Fatality` | Your enemy-player target dies in your fight after finish him | `fatality` |
| `SuperbVictory` | Any other kill of your enemy-player target in your fight | `superb` |
| `DeathTaunt` | You die | `taunt` |

A kill plays one victory sound: flawless, else fatality, else superb, whichever is first and switched on. A kill someone else makes while you're out of combat plays nothing.

"Flawless victory" means you took no damage in the fight. Addons can never read your health in Forever (it's hidden even out of combat), so a hit is what Blizzard's own player frame shows as one: heals and regeneration don't count, and neither does a hit a shield fully absorbed. A hit in the second before the game says combat started (an ambush) counts. The sound plays at the kill. The victory itself counts when the fight ends, once Blizzard's damage meter confirms you took no damage; the meter can keep its numbers hidden a moment after a fight, so the check waits for them. The Krew hears about confirmed victories only.
- **Duels:** a duel ends at 1 HP rather than death, and the game doesn't tell addons who won. Winning one without taking a hit counts (you can't lose a duel you weren't hit in); a duel you were hit in plays nothing, and fleeing out of bounds doesn't count. The game doesn't say whose duel ended either, so a duel counts only when your opponent was already your target as the duel started.

For warriors, "finish him" relies on Execute being usable, so it's silent in Defensive Stance. It doesn't fire when you merely lack rage, and neither switching stances nor a `/reload` repeats it. Combo points sit on the target, as in Blizzard's own combo frame, so switching targets starts the count over, and so do points that move to another unit. For classes without a finisher, finish him, fatality and the combo callouts cost nothing.

An enemy hunter's Feign Death may look like a death to the client, so it can trigger a victory sound.

**Kill streaks:** an Unreal Tournament announcer for your world PvP killing blows (your pet's count too), with a raid warning on your screen for each. Kills in battlegrounds, arenas or other instances do not count. As in Unreal, a kill is whoever landed it: an honorable kill credits everyone in your group nearby, so it isn't what streaks count.

| Moment | Files | When |
| --- | --- | --- |
| First blood | `FirstBlood` | Your first killing blow of the session, unless a Krew member drew it first |
| Multi kills | `DoubleKill`, `MultiKill`, `MegaKill`, `UltraKill`, `MonsterKill`, `LudicrousKill`, `HolyShit` | 2 to 8 or more kills, each within 10 seconds of the last |
| Sprees | `KillingSpree`, `Rampage`, `Dominating`, `Unstoppable`, `Godlike`, `WickedSick` | 5, 10, 15, 20, 25 and 30 kills without dying |

A kill announces one moment: a spree it reaches, else a multi kill, else first blood. The Krew sees a raid warning for your first blood and each spree, and hears when a spree of five or more ends, and who ended it when the game says. Kill streaks can be switched off, and so can sharing them.

### Controller light bar and rumble

- **Light bar:** red in combat, yellow when AFK, green otherwise. It's cleared on logout or when the feature is disabled.
- **Rumble:** strong when combat starts, light when it ends. Stopped on logout or when the feature is disabled.

### Cards

The journal, the Krew, Warband and the Scholar's challenge celebrate (and ask questions) with cards at the top of the screen, one at a time. Cards never interrupt a fight: one earned mid-combat appears when combat ends, and one showing when combat starts steps aside and comes back first when it ends. Hover a card to keep it, click to dismiss it and see the next; otherwise it hides after 12 seconds. At most six wait in line; beyond that new ones are dropped.

### Session journal

Celebrates your play, per character, with cards.

- **Welcome back:** at login after 30 minutes or more away, a card recalls your last session: where you were, how long you played, quests turned in, gold earned, levels reached. It also shows how much rested XP you built up while away. A `/reload` or loading screen doesn't show it, and a reload continues the session.
- **Ding!** at level-up, a card sums up the level you just finished: time played at that level, quests, gold, and trips to the spirit healer (or "not a single death!"). Every tenth level and max level get a milestone line. Until your first ding with the journal installed, it counts "since the journal started".
- **`/tlk journal`** shows this session's highlights so far.

Each card can be switched off in settings. Turning the journal off keeps the played time so far.

### Krew

Friends in your group who also run the toolkit share fun moments, each as a card:
- **Roll call:** when you group up, a card shows who else runs the toolkit. `/tlk krew` lists them; someone who leaves the group leaves the list once the roster settles, a second after the last change.
- **Ding:** your level-ups.
- **Flawless:** your flawless victories (needs the "Flawless victory" sound on).
- **Kill streaks:** your first blood and sprees, as raid warnings (see [Sounds](#sounds)).
- **Scholar:** riddles solved in the Scholar's challenge.

Warband's marks, grudges, sightings, rallies and intel travel the same way. Each can be switched off, and turning Krew messages off stops all of it. It plays by Blizzard's add-on rules, which forbid excessive use of the chat system:
- It uses hidden addon messages to your own party, raid or instance group only. It never whispers, and never uses public channels or visible chat.
- It sends only on rare events, never on a timer, and at most one message a second. A queue of up to eight holds the rest, and anything beyond that is dropped.
- It never sends during chat messaging lockdown (encounters, Mythic+, PvP matches). A celebration that can't go out then is dropped rather than sent late.
- Received messages are parsed strictly and must come from your group. They only ever show a card or raid warning, update the Warband ledger, or set a map waypoint; none acts on your behalf.

### Warband

World PvP for a Krew that takes the war seriously. An account-wide ledger remembers three kinds of people, and the Krew can go to war with whole guilds. All of it is shared with the Krew:

| Kind | How someone gets there | What it means |
| --- | --- | --- |
| Grudge | They killed one of us. When an enemy player kills you, a card names them and the killing blow ("Slain by Bob. Ambush for 700."): left-click holds the grudge, right-click lets it go. Or `/tlk grudge` on your target or a name. | The Krew tallies their kills of us against ours of them: `Krew 3 : 5 Bob`. |
| Mark for death | `/tlk mark` on your target or a name. `/tlk unmark` lifts it (they stay a grudge). | The Krew hunts them. Your three most recent marks (and wars) reach Krew members who join the group later, come back, or reload, in one message each however many say hello at once. |
| Champion | `/tlk glory` on your target or a name. Works on either faction. | Someone the Krew aids. |
| Guild at war | `/tlk war` on your target (their guild) or `/tlk war <guild name>`. `/tlk peace <guild>` ends it. | Every member counts as an enemy of the Krew, with a tally of kills each way. |

`/tlk ledger` lists everyone and every war, and `/tlk forgive <name>` removes someone. The right-click menu on a player offers the same choices, including war on their guild. A typed name can be in any case: `/tlk mark cara doe` finds Cara Doe in the ledger or among the enemies you've met, and a guild name finds a guild at war or one you've seen.

The ledger holds up to 300 people and never forgets anyone on its own. When it's full, a new mark, grudge or champion (yours or the Krew's) is turned away with a message in chat, and nothing is sent, until you forgive someone to make room.

**Rivalry records:** every enemy player you meet gets a record: class, level, guild, times seen (at most once a minute, the first time always, even right after you mark someone by name), where, and the score against them. `/tlk rival <name>` shows it, and tooltips show the score of anyone the Krew has fought. Ledger people's records are always kept; past a thousand records, the hundred strangers you've seen least recently make room.

**Nameplate badges:** marked enemies wear a skull above their nameplate, grudges a cross, members of a guild at war a square, and champions a star. The ledger is shared, so the whole Krew sees the same badges. They're your own markers: the game doesn't let addons set real raid icons.

**Nearby enemies:** a small window lists the enemy players you and your Krew have seen in the last two minutes, marked ones first, with class colors, level, how long ago, and who saw them. Right-click a name for the Krew's choices; drag the window to move it. It shows itself when there's someone to list. New enemies you see are shared with the Krew in one batch, at most every ten seconds.

- **Sightings:** when a ledger player's nameplate appears, or you target or mouse over them, a raid warning says so. The Krew hears where you saw them. A champion in a fight asks the Krew for aid. Each person alerts at most once every 90 seconds; in a brawl, the alerts that follow one within 3 seconds merge into one summary with one sound ("3 more grudges nearby: Bob Doe, Cara Doe, Dan Doe"), marks first, then grudges, guilds at war and champions. Your Krew still hears about every sighting. A guild at war showing up in numbers raises one warning, not one per member.
- **Vengeance:** an honorable kill on a marked or grudge enemy settles the score for everyone, counted once however many of you got credit. Kills of anyone else count quietly in their record.
- **Rally:** `/tlk rally` calls the Krew to you. They get a raid warning and a map waypoint to your position.
- **Enemy gatherings:** when five or more enemy players show up on your nameplates within a minute in one place (a subzone), the Krew gets a card saying how many and where. Clicking it sets a waypoint. That's how to find the other faction's world events. One report per place every five minutes: once a Krew member has reported a gathering, the rest of the Krew neither sees it again nor reports it themselves.

Tips:
- Turn on enemy nameplates; sightings and gatherings see what they see.
- Put `/tlk rally` and `/tlk mark` in macros on your action bars, so a controller can press them too.
- Sharing needs Krew messages on. Nothing is shared during battlegrounds, arenas, dungeons or raids (chat messaging lockdown).

The client gives addons no combat log, but Blizzard's death recap names your killer: the killing blow's attacker, spell and damage. Their kill of you counts in their record on its own, and it's always your click that makes it a grudge. A creature's kill asks nothing. When the recap can't say (the damage meter is off, or a pet or totem landed the blow), the card asks "Slain by Bob?" about the enemy player you had targeted, or last targeted in the 30 seconds before, and only a click counts it. Enemy names are readable outside PvP matches. Every message from the Krew is checked before use, and no escape codes from it reach the screen.

### Scholar's challenge

Riddles for young players about their own quests, plus math and reading, set up by a parent. It's off by default and set per character, so turn it on for your child's characters only.

- **Quest riddles are preferred:** two in a row, then a math or reading riddle takes a turn, across a /reload too. A quest riddle asks about the newest quest your child has accepted or turned in since it was last asked about, or, with none waiting, an older one for review (the one asked about longest ago): who gave it, who took it and where, what it asked for (an item to bring, an enemy to defeat, or something to do) and how many, which quest a giver gave, or a word missing from its text (English clients only). What it asked for comes first, and the same kind of question doesn't come twice in a row about one quest. Wrong answers come from your child's other quests first, then from the starting lands of your child's faction, and never one that's also true: not the zone around the right place, nor another quest the same giver gave. Quests count from the moment they're shown, including ones an area trigger accepts without showing their text: those are in the quest log, so open it and read. Quests already in the log when the challenge is turned on are remembered too, for review. It's an open-book test: **Quest book** (H, or the left shoulder) shows the quest on the riddle screen, as your child saw it. A quest too long for the screen scrolls, like the quest log: the mouse wheel, the Up and Down arrows or the D-pad (hold it to keep going), with a slim bar showing where you are; the riddle never grows taller than the screen. A quest's text is kept whole, as the quest log shows it. With only quest riddles on, every riddle is about a quest, and one that comes due before any quest waits for the first. The last 30 quests are remembered, per character, while the challenge is on.

- **When:** after a set number of minutes of play (30 by default, 10 to 120) and, optionally, at each level-up. Play time is saved per character, so relogging doesn't skip a riddle. Time AFK, or with every subject switched off, doesn't count. Once half the minutes are played, a good moment brings the next riddle early: a flight path (free time), a quest turned in (the riddle asks about it while it's fresh), or a death (waiting to come back). Each can be switched off.
- **How:** the riddle covers the screen and holds the mouse and keyboard until it's solved. Answer with 1-4, a click, or the controller's face buttons. **Gate** mode must be solved; **Gentle** mode offers Skip after one wrong try. A wrong answer shows a hint.
- **Never in combat:** a riddle waits for the fight to end. One on screen steps aside when a fight starts and comes back after. Nor over Blizzard's windows: a riddle that comes due while a quest dialog, gossip, a vendor, the mailbox, a bank, the auction house, a trainer or the flight map is open waits for it to close. One already on screen stays.
- **The screen:** the Owl Sage asks. The header shows the stars, a bar toward the next rank ("5 more to Journeyman") and the streak. The story sits above the question, which has its own band; numbers and target words are highlighted. For small numbers in the early grades, the riddle is drawn with the items it counts: bags of apples, two piles to join, or a pile with some crossed out. The big answers each have their key on a raised keycap. A wrong answer shakes, and the right one turns green while a "+1" rises. **Need a hint?** is free (the streak survives; on a quest riddle it's the quest book, which stays beside the feedback after a wrong answer), and **Read aloud** speaks the riddle and its choices with the game's text-to-speech voice (a blank as "blank", and a spelling riddle's choices letter by letter); with the quest book open it reads the book, and after an answer or a hint it reads the feedback.
- **Controllers and keyboards:** the face buttons answer, the left shoulder asks for the hint, the right shoulder reads aloud, and Back skips (Gentle mode, after a try); the D-pad scrolls an open quest book. On a keyboard it's 1-4, H, R and Esc, and the Up and Down arrows scroll the book. Every button shows its key for the device you're using.
- **Riddles** are written for a chosen grade and adapt within it: every third right answer in a row makes them harder, and two misses on one riddle make them easier (math and reading only; quest riddles never change the difficulty). Math and reading alternate between quest riddles, and quest riddles, math and reading can each be switched off. Many use the character's own name, class, zone and gold.
- **Rewards:** a star per riddle, streaks, and scholar ranks (Apprentice, Journeyman, Adept, Sage, Archmage), each with a card.
- **Parent lock:** `/tlk lock <pin>` (4 to 8 digits) locks every Scholar setting, including the on switch, in slash commands and the settings window. `/tlk unlock <pin>` unlocks it for the session (a `/reload` keeps it), and it locks again at the next login. While locked, the PIN can't be changed; unlock first. After three wrong PINs, unlocking waits a minute, even across a `/reload`. The PIN is saved as a hash, which keeps it from sitting in the file as-is but isn't real security.
- `/tlk scholar` shows stars and the time to the next riddle. `/tlk puzzle` asks one now.

It's meant to be fun, not a hard limit. A controller's sticks still move the character, and a determined child can disable the addon at character select. For hard limits, use Blizzard's parental controls (play time limits in Battle.net account settings).

## License

Dual-licensed under [Apache-2.0](LICENSE-APACHE-2.0.txt) or [MIT](LICENSE-MIT.txt), at your option.
