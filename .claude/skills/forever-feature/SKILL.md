---
name: forever-feature
description: Build or change a player-facing feature in a ByteTerrace WoW Forever addon, from the request to a committed change proven by the gates. Covers TheLanKrewToolKit features (Scholar riddles, Warband, Krew, Kombat, sounds, the Fuck-o-meter, cards, the journal, controller lights and rumble) and any ByteTerrace_Core capability a feature needs (rows, records, facts, commands, Input maps, comms, diagnostics). Use this whenever the user asks to add, change or remove something a player would notice, such as a setting, a slash command, a controller binding, an alert, a riddle kind, a sound, a group message or a window. Use it even when they only describe what the player should experience ("kids should hear the riddle", "warn me when a rogue I marked shows up"). Don't use it for probe or harness calibration work, refreshing the API snapshot, or changes to the tlk verbs themselves.
---

# Building a feature on ByteTerrace

A feature is done when its behavior is proven through the harness, the gates pass, every doc that describes it is current, and it's committed with a message that says what was and wasn't verified. CLAUDE.md holds the rules; this skill is the order to apply them in, and the places features usually go wrong.

Read [docs/Architecture.md](../../../docs/Architecture.md) before designing. It's the contract for every framework piece named below, and this skill doesn't repeat it.

## 1. Pin down what the player observes

Restate the request as behavior someone could check in game:

- What triggers it: an event, a command, a button, a count rising, a timer.
- What the player sees or hears, and when it stops.
- Which setting controls it, and that setting's default and page.
- How it behaves in combat, under a restriction (encounter, PvP match, chat lockdown), with the controller UI on, and grouped versus solo.
- **What happens when something it relies on is missing.** That might be a text-to-speech voice, game sound, a controller, a group, a quest in the log, or a setting that takes away the way to answer. Choose a behavior: leave the feature out, fall back, or say why nothing happened. Don't let it half-work, because a player can't tell a missing dependency from a broken addon.

This list becomes your tests in step 4, so a vague item here becomes an untested behavior later.

Then find it before building it:

1. **The framework.** Does Architecture.md already offer it under another name? For example: a demand fact for the target, `OnIncrease` for "when a kill happens", or `Callback` for a menu action.
2. **The toolkit.** Does a module already own adjacent behavior (`ns.Cards`, `ns.Krew`, the sound bank, the journal)? Extend it rather than adding a parallel one.
3. **Blizzard's Forever UI.** Look on the `forever` branch of Gethe/wow-ui-source.
4. **The snapshot.** `tools/api/forever.json` holds one entry per line, so `grep '"<Name>"' tools/api/forever.json` shows an API's secret flags, restrictions and `Nilable` arguments. `tools/api/probes.json` holds what the client actually answered and outranks the docs. `tools/api/forbidden.json` holds what broke in game.

If the feature depends on client behavior that neither the docs nor a probe settles, the harness is guessing. Name it as a probe candidate in the report, and don't stack more assumptions on top of the guess.

## 2. Decide whether to stop and ask

Build straight through when the request is clear. Stop and ask first when the answer is the user's to give:

- **Player-facing choices without an obvious default.** For example: a setting's default, a slash word, the wording a child reads or hears, or which sound plays.
- **A Core change**, such as a new framework API, fact or built-in command. It shapes every later feature.
- **What other players' clients receive**, such as a new comms kind or a changed field order. Group members may run an older version.

For everything else, choose, build, and list the choice under **Needs you** so it's cheap to reverse. If the request reads two ways, say which reading you built. A renamed or removed row resets that setting for anyone who saved it, so mention it.

## 3. Design on the framework

Map each behavior from step 1 onto a declaration:

| The feature needs | Use |
| --- | --- |
| A setting | A labelled persisted row; `page` and `section` place it |
| One entry per thing (a player, a skill) | `records`, with a `limit` and an `evict` field |
| An intent from slash, keys, controller or settings | A command, with an Input map for controller buttons (`held` for press and release) |
| Reacting to the client | `module:On` in an adapter that writes non-secret rows; rules and watchers read the rows |
| Combat, target, kills, death or restrictions | The fact, via `uses = { ... }` for demand facts |
| "When X happens" | A count row and `module:OnIncrease` |
| Talking to the group | `comms`, with `module:Listen` in `OnEnable` |
| A menu or card action | `module:Callback` |
| Delays and repeats | `module:After` and `module:Every` |
| Sounds | The sound bank (`ByteTerrace.NewSoundBank`) |

- **Split deciding from wiring.** Put pure logic in its own file of functions over plain tables, the way `ScholarSkills.lua` "only decides". Test those functions directly, and keep the module file small.
- **Plan the counts now.** Choose the load-independent numbers that will prove the feature is cheap. For example: events registered only while it runs, API calls per event, widget calls per event, and nothing while it's off.
- **Name the secret values up front.** Decide which values come from secret-flagged APIs, and which widget each one goes to, before `check` finds them.

When the feature needs Core, build the general mechanism in `ByteTerrace_Core`, with framework tests and an Architecture.md update, and keep the feature-specific part in the toolkit.

## 4. Write the tests first, then the code

Turn step 1's list into tests before writing the code that makes them pass, and run them to see them fail. That's the cheapest proof a test can fail, and it never needs a revert later, which can be refused over your own uncommitted changes. For a bug fix, the test fails on the code as it is. Record which tests failed in the commit.

- **Name tests as sentences of behavior** ("a heard riddle says only its word, even with read-aloud off, never shows it, and its button is Hear it again"). They're what a reviewer reads first.
- **Start from a kit.** Use `use("toolkit")`, `use("scholar")`, or `use("framework")` for Core. A helper that two test files need goes in `tests/kits/`.
- **Drive it like a player.** Use `h:Slash`, `h:Click`, `h:Fire`, `h:Advance`, `h:EnterCombat`, `h:SetUnit`, `h:JoinGroup` and `h:ReceiveAddonMessage`. The README's harness section lists the rest.
- **Prove the cost with counts.** Use `h:CountCalls(method)`, `h:CountApiCalls(name)` and `addon.Events.Frame:IsEventRegistered(event)`, including that switching the module off unregisters what it registered.
- **Cover the hard cases.** Test in combat, so secret values really are secret, and across `h:Reload()` and `h:Relog()` for anything persisted. Test the case from step 1 where something is missing.
- **Add a missing fake only for a real global.** Mark its behavior `[D]` (documented), `[G]` (guessed) or `[E]` (observed). A `[G]` that the feature leans on is a probe candidate.

Then write the code, following [docs/Conventions.md](../../../docs/Conventions.md):

- **Update file headers.** When a file's contract changes, its header changes too.
- **A new file goes in the TOC.** In game, that means a client restart, not just `/reload`: the client reads TOCs only at startup. The addons are linked as whole folders, so the new file is already there; `deploy` is only needed for an addon that isn't linked yet.
- **Keep files under LENGTH's 1000 lines.** Run `wc -l` on each file you grow. When one would cross the limit, split it along a real seam in the same change, like `WarbandMessages.lua` and `ScholarView.lua` were.
- Run `node tools/tlk.mjs format`.

Finish with `node tools/tlk.mjs check`, then `node tools/tlk.mjs test --coverage <your test files>` for statements nothing reached, then the full `node tools/tlk.mjs test`. Note the pass count.

## 5. Update every doc in the same change

- **README.md:** the feature's section under "TheLanKrewToolKit", covering behavior, settings and commands.
- **TheLanKrewToolKit/README.txt:** the players' guide. Update it whenever a player would notice the change, such as a new command or something a parent turns on. Use plain words for someone who has never seen the code. This is the doc most often missed.
- **docs/Architecture.md** for Core changes, and **docs/ControllerSupport.md** for anything learned about Forever's controller UI.
- **Comments, file headers and test names** that describe the old behavior.

Then grep the repository for every name you changed, removed or renumbered (row names, slash words, constants, numbers quoted in prose).

## 6. Commit and report

Commit on the current branch. The subject is a plain sentence of what the player gets, with no `feat:`-style prefix and no trailing period ("Read Scholar's riddles aloud for young children, and add heard riddles"). The body is prose wrapped near 76 columns, in this order:

1. What the feature does, in the player's terms. Bullets are fine when it has several parts.
2. What a reviewer needs about the design: new rows or records, what moved or was deleted, and any saved key that's now unread.
3. "Tests drive the real addon:", then the behaviors proven and which tests failed first.
4. `check passes; N tests pass.` with the real N.
5. What was verified in game, or `Not run in game.`
6. The Co-Authored-By line the session's attribution gives.

End with **Needs you**, **Changed** and **Found**. Under Changed, give an in-game checklist:

- A client restart if a TOC changed (and `deploy` only for an addon not linked yet); otherwise `/reload`.
- The steps to see each behavior from step 1, including the case where something is missing.
- `/tlk debug status`, to confirm nothing errored.

The harness can't show rendering, layout, taint, or how a voice or sound comes across. Name which of those the feature depends on.
