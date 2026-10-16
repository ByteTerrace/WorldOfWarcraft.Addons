---
name: forever-feature
description: Build, change, fix, or polish a player-facing feature in a ByteTerrace WoW Forever addon, from the request to a committed change proven by the gates. Covers TheLanKrewToolKit features (Scholar riddles and its window, the quest book, quest progress and read-aloud, Warband, Krew, Kombat, sounds, the Fuck-o-meter, cards, the journal, controller lights and rumble, and the settings window) and any ByteTerrace_Core capability a feature needs (rows, records, facts, commands, Input maps and summons, comms, and diagnostics). Use this whenever the user asks to add, change, remove, or fix something a player would notice, such as a setting, a slash command, a controller binding, an alert, a riddle kind, a sound, a group message, or a window. Use it too when they send a screenshot of something that looks wrong ("this still overflows at the top"), ask for a layout, polish, or UX pass on a window or the settings, or only describe the player's experience ("kids should hear the riddle", "the child can spam answers until one's right", "warn me when a rogue I marked shows up"). Don't use it for probe or harness calibration work, refreshing the API snapshot, or changes to the tlk verbs themselves.
---

# Build a feature on ByteTerrace

A feature is done when:
- the harness proves its behavior
- the gates pass
- every doc that describes it is current
- it's committed with a message that says what was and wasn't verified

CLAUDE.md holds the rules. This skill is the order to apply them in, and the places features usually go wrong.

Read [docs/Architecture.md](../../../docs/Architecture.md) before designing. It's the contract for every framework piece named below, and this skill doesn't repeat it.

## 1. Pin down what the player observes

Restate the request as behavior someone could check in game:

- What triggers it: an event, a command, a button, a count rising, a timer.
- What the player sees or hears, and when it stops.
- Which setting controls it, and that setting's default and page.
- How it behaves in combat, under a restriction (encounter, PvP match, or chat lockdown), with the controller UI on, and grouped versus solo.
- **What happens when something it relies on is missing.** That might be a text-to-speech voice, game sound, a controller, a group, a quest in the log, or a setting that takes away the way to answer. Choose a behavior: leave the feature out, fall back, or say why nothing happened. Don't let it half-work, because a player can't tell a missing dependency from a broken addon.
- **How a player gets around it.** Children are the main players here, and a child finds the fastest way to the reward: mashing a button, guessing every answer, closing and reopening a window, or reloading mid-wait. Decide what each shortcut does. The Scholar's pause after a wrong answer (`missPause`) is the model: guessing costs time, so guessing stops paying. Closing a shortcut means keeping everything that sets its cost, not only the visible part. A pause that survives a reload but forgets how many misses lengthened it still pays to guess.

This list becomes your tests in step 4, so a vague item here becomes an untested behavior later.

Then find it before building it:

1. **The latest code.** Run `git status`, `git fetch`, and `git log --oneline HEAD..origin/main` first. Other sessions often work in this checkout or push to main from their own. Your branch can be behind main, and a commit from an hour ago may already have half of what you're about to build, or have changed the text your tests expect. When main is ahead, bring the branch up to date before you design, and build on what's there.
2. **The framework.** Does Architecture.md already offer it under another name? For example: a demand fact for the target, `OnIncrease` for "when a kill happens", or `Callback` for a menu action.
3. **The toolkit.** Does a module already own adjacent behavior (`ns.Cards`, `ns.Krew`, `ns.ScholarVoice`, the sound bank, the journal, or the quest book)? Extend it rather than adding a parallel one.
4. **Blizzard's Forever UI.** Look on the `forever` branch of Gethe/wow-ui-source.
5. **The snapshot.** `tools/api/forever.json` holds one entry per line, so `grep '"<Name>"' tools/api/forever.json` shows an API's secret flags, restrictions, and `Nilable` arguments. `tools/api/probes.json` holds what the client answered, and outranks the docs. `tools/api/forbidden.json` holds what broke in game.

If the feature depends on client behavior that neither the docs nor a probe settles, the harness is guessing. Name it as a probe candidate in the report, and don't stack more assumptions on top of the guess.

## 2. Decide whether to stop and ask

Build straight through when the request is clear. Stop and ask first when the answer is the user's to give:

- **Player-facing choices without an obvious default.** For example: a setting's default, a slash word, the wording a child reads or hears, or which sound plays.
- **A Core change**, such as a new framework API, fact, or built-in command. It shapes every later feature.
- **What other players' clients receive**, such as a new comms kind or a changed field order. Group members may run an older version.

When you ask, put your recommendation first and say why in a line, so the user can accept it with one click. For everything else, choose, build, and list the choice under **Needs you**, so it's cheap to reverse. If the request reads two ways, say which reading you built.

The addons run only on the user's machine, so reshape freely. When a clearer name exists, rename the row. The state loader drops a declared module's old key, so that setting returns to its default. Say so in the commit.

## 3. Design on the framework

Map each behavior from step 1 onto a declaration:

| The feature needs | Use |
| --- | --- |
| A setting | A labeled persisted row. `page` and `section` place it. |
| One entry per thing (a player, a skill) | `records`, with a `limit` and an `evict` field |
| An intent from slash, keys, controller, or settings | A command |
| The controller, while a window is up | An Input map (`held` for press and release), added to the others through `Input:ActiveMaps()` |
| One controller button, without taking the controller | `Input:Summon`. It works only out of combat, and combat ends it. |
| Reacting to the client | `module:On` in an adapter that writes non-secret rows. Rules and watchers read the rows. |
| Combat, target, kills, death, or restrictions | The fact, through `uses = { ... }` for demand facts |
| "When X happens" | A count row and `module:OnIncrease` |
| Talking to the group | `comms`, with `module:Listen` in `OnEnable` |
| A menu or card action | `module:Callback` |
| Delays, repeats, and pauses | `module:After` and `module:Every` |
| Sounds | The sound bank (`ByteTerrace.NewSoundBank`) |

- **Expect the layout test to change.** A new labeled row changes `tests/toolkit.test.lua`'s one-line-per-page listing of the settings window. Update that expectation in the same change.
- **Name settings for what they do.** The settings window sorts pages, sections, and settings alphabetically. Each section is led by the switch that turns its feature on. A player finds a setting by its label, so the label says what happens ("Share my solved riddles", "At every level-up"). The row's name says it too: `sightingAlerts`, not `alerts`. Use a `values` list, which the window shows as a dropdown, when there are more than two choices. Share a section with a related module rather than making a section of one setting.
- **Split deciding from wiring.** Put pure logic in its own file of functions over plain tables, the way `ScholarSkills.lua` "only decides". Test those functions directly, and keep the module file small.
- **Plan the counts now.** Choose the load-independent numbers that will prove the feature is cheap. For example: events registered only while it runs, API calls per event, widget calls per event, and nothing while it's off.
- **Name the secret values up front.** Decide which values come from secret-flagged APIs, and which widget each one goes to, before `check` finds them.

When the feature needs Core, build the general mechanism in `ByteTerrace_Core`, with framework tests and an Architecture.md update, and keep the feature-specific part in the toolkit.

### Windows and layout

Layout is where a feature looks finished in the harness and wrong in game. Work out the arithmetic in code you can test, then check it against the user's screenshot.

- **Measure in the frame's own units.** A parentless frame isn't scaled by the UI scale, but UIParent's sizes are in UIParent's units. Convert through the effective scales, the way `ScholarView.lua`'s `ScreenHeight` does. Otherwise a window that fits at one UI scale overflows at another.
- **Fix the parts, and give the flexible part what's left.** Size the header, the footer, and the buttons first. Then give the scrolling or growing part the remaining room, with a floor.
- **Snap scrolling text to whole lines.** One line is `GetLineHeight()` plus `GetSpacing()`. A box that isn't a whole number of lines cuts the descenders off its last line.
- **Test the geometry.** The harness models `SetScale`, `GetEffectiveScale`, `GetLineHeight`, and `GetSpacing`. First work out what actually changes the window's layout, because a crowded screen is often not caused by what the player blames. The riddle screen, for example, ignores the UI scale, so its layout changes only with the screen's shape and with which footer buttons show. Then prove the window fits in each case that changes it, with its longest text, and that adding your part leaves the rest where it was.
- **Iterate on screenshots.** The harness can't render. After a `/reload`, ask the user for a screenshot and read all of it: clipping at the top and bottom, alignment between rows, padding that differs from side to side, contrast, and text that runs into a border. Polish means consistent insets, aligned edges, and a clear focus, before decoration.

## 4. Write the tests first, then the code

Turn step 1's list into tests before writing the code that makes them pass, and run them to see them fail. That's the cheapest proof a test can fail, and it never needs a revert later, which can be refused over your own uncommitted changes. For a bug fix, the test fails on the code as it is. Record which tests failed in the commit.

- **Name tests as sentences of behavior** ("a heard riddle says only its word, even with read-aloud off, never shows it, and its button is Hear it again"). They're what a reviewer reads first.
- **Start from a kit.** Use `use("toolkit")`, `use("scholar")`, or `use("framework")` for Core. A helper that two test files need goes in `tests/kits/`.
- **Drive it like a player.** Use `h:Slash`, `h:Click`, `h:Fire`, `h:Advance`, `h:EnterCombat`, `h:SetUnit`, `h:JoinGroup`, and `h:ReceiveAddonMessage`. The README's [harness section](../../../README.md#the-test-harness) lists the rest.
- **Prove the cost with counts.** Use `h:CountCalls(method)`, `h:CountApiCalls(name)`, and `addon.Events.Frame:IsEventRegistered(event)`, including that switching the module off unregisters what it registered.
- **Cover the hard cases.** Test these:
  - in combat, where secret values are secret
  - across `h:Reload()` and `h:Relog()`, for anything persisted
  - the case from step 1 where something is missing
  - each shortcut from step 1, done the way a child would: twice in a row, and right after a reload
- **Add a missing fake only for a real global.** Mark its behavior `[D]` (documented), `[G]` (guessed), or `[E]` (observed). A `[G]` that the feature leans on is a probe candidate.

Then write the code, following [docs/Conventions.md](../../../docs/Conventions.md):

- **Keep the parentheses.** The user prefers full parenthesization for clarity and strictness, and `format` writes it. Don't strip parentheses or brackets to shorten a line.
- **Update file headers.** When a file's contract changes, its header changes too.
- **A new file goes in the TOC.** In game, that means restarting the game, not only a `/reload`: the client reads TOCs only at startup. The addons are linked as whole folders, so the new file is already there. `deploy` is only needed for an addon that isn't linked yet.
- **Keep files under LENGTH's 1000 lines.** Run `wc -l` on each file you grow. When your change would take a file past the limit, first split it along a real seam in a commit of its own, the way `ScholarSettings.lua`, `ScholarFrame.lua`, and `WarbandMessages.lua` were split out. A change that fits doesn't need a split, because a split adds a TOC line and so a game restart. When a file is within about 50 lines of the limit, say so under Found.
- Run `node tools/tlk.mjs format`.

Finish with `node tools/tlk.mjs check`, then `node tools/tlk.mjs test --coverage <your test files>` for statements nothing reached, then the full `node tools/tlk.mjs test`. Note the pass count.

## 5. Update every doc in the same change

Prose follows the Writing section of Conventions.md: Microsoft's style, in the user's voice. That means the present tense, "you", contractions, the serial comma, and no "should".

- **README.md:** the feature's section under "TheLanKrewToolKit", covering behavior, settings, and commands. When you add a settings page, update the README's list of pages too.
- **TheLanKrewToolKit/README.txt:** the players' guide. Update it whenever a player would notice the change, such as a new command or something a parent turns on. Use plain words for someone who has never seen the code. This is the doc most often missed.
- **docs/Architecture.md** for Core changes, and **docs/ControllerSupport.md** for anything learned about Forever's controller UI.
- **Comments, file headers, and test names** that describe the old behavior.

Then grep the repository for every name you changed, removed, or renumbered: row names, labels, slash words, constants, and numbers quoted in prose.

## 6. Commit and report

Commit on the current branch. The subject is a plain sentence of what the player gets, with no `feat:`-style prefix and no trailing period ("Read Scholar's riddles aloud for young children, and add heard riddles"). The body is prose wrapped near 76 columns, in this order:

1. What the feature does, in the player's terms. Bullets are fine when it has several parts.
2. What a reviewer needs about the design: new rows or records, what moved or was deleted, and any renamed row whose setting returns to its default.
3. "Tests drive the real addon:", then the behaviors proven and which tests failed first.
4. `check passes; N tests pass.` with the real N.
5. What was verified in game, or `Not run in game.`
6. The Co-Authored-By line the session's attribution gives.

End with **Needs you**, **Changed**, and **Found**. Under Changed, give an in-game checklist:

- A game restart if a TOC changed, and `deploy` only for an addon not linked yet. Otherwise, a `/reload`.
- The steps to see each behavior from step 1, including the case where something is missing and the shortcuts a child would try.
- What to screenshot, for a window or layout change.
- `/tlk debug status`, to confirm nothing errored.

The harness can't show rendering, layout, taint, or how a voice or sound comes across. Name which of those the feature depends on.
