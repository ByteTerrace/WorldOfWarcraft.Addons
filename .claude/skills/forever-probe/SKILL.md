---
name: forever-probe
description: Ask the real WoW Forever client how it behaves, and calibrate the test harness and the API snapshot to its answers. Covers deciding that a harness guess needs a probe, writing the probe in ByteTerrace_DevTools (needs, read-only shapes, versions, and listeners), handing the in-game run to the user, reconciling after `tlk probes --import`, and refreshing after a new client build (`tlk api-sync` from Blizzard's docs and from a `/btdev dump`). Use this whenever the harness and the client might disagree, or the user reports back from a play session. Examples include a `probes.test.lua` failure or `PEND` line, a `[G]` or `[C]` guess a feature depends on, "is X secret in combat on Forever?", "what does the client fire when...", "dump done", "I reloaded", `/btdev probe` or `/btdev dump` results, a new client build, a replaced probe record, ranking guesses with `tlk guesses`, or improving the probes, the probe process, or the dumps themselves. Use it even when the user only reports that tests broke after an import. Don't use it for building a player-facing feature (forever-feature) or for changes to tlk verbs unrelated to probes or the snapshot.
---

# Probe the client and calibrate the harness

The harness is only as honest as its evidence. A probe asks the client one read-only question in a situation both the game and the harness can reach, so the harness's answer can be compared with the client's. Observed answers outrank guesses (CLAUDE.md rule 5). When they disagree, the harness changes, never the record, the probe, or the test.

The README's [Probes](../../../README.md#probes) and [API snapshot](../../../README.md#api-snapshot) sections are the user's procedures, and `ByteTerrace_DevTools/Probes.lua`'s header is the engine's contract. Read them before writing a probe. This skill is the order to work in, and the traps.

## 1. Decide whether it needs a probe

Look before asking:

1. **The latest code.** Run `git fetch` and `git log --oneline HEAD..origin/main`. Other sessions push probes to main, and your branch may be behind it. A probe that already asks your question may be there, or one you'd replace may have just been reworked.
2. **`tools/api/probes.json`**: `grep -n '"<probe.name>"' tools/api/probes.json`, or run `node tools/tlk.mjs probes` for every probe with its needs, the client's answer, and the harness's. A record from the snapshot's build that covers the context you care about (`idle/none`, `combat/Combat`) settles it.
3. **`tools/api/forever.json`**: the documented flags (`SecretReturns`, `SecretWhen*`, `HasRestrictions`, `Nilable`). If the docs settle the behavior, the harness models it as `[D]` and no probe is needed.
4. **The harness's own markers** in `tests/harness/*.lua`: `[D]` documented, `[E]` observed in the client, `[G]` a guess, and `[C]` a conservative fallback (`secrets.lua`). A `[G]` or `[C]` that a feature depends on is the usual reason to probe. `node tools/tlk.mjs guesses` ranks them by how much addon code and how many tests rest on each, and names the probes that already cite one or read its API. Start from the top of that list when the user asks what to probe next.

Probe when the docs are silent, ambiguous, or retail-only, and something depends on the answer. Name what depends on it, because that's what the user is spending play time on.

## 2. Write the probe

- **Find its home.** Probes go in `ByteTerrace_DevTools/Probes<Topic>.lua` by topic through `Probes.Define`:
  - `ProbesWorld`
  - `ProbesUnits`
  - `ProbesCombat`
  - `ProbesNames`
  - `ProbesInput`
  - `ProbesOrder`, for what holds as an event dispatches

  Situations go in `ProbeNeeds.lua`. Touch `Probes.lua` only for engine changes. Run `wc -l` first: LENGTH stops at 1000 lines. A full file means a new topic file, listed in the DevTools TOC before `DevTools.lua`, and in the README's list of probe files.
- **Define the need.** A need has these parts:
  - a `label`
  - the `text` the player reads
  - the session `step` it belongs to, an index into `Probes.Steps`
  - a `check` against the live client
  - a harness `setup(h)` that recreates it

  If the harness can't recreate the need, give a `harness` reason instead of `setup(h)`, and its probes run in game only. Reuse an existing need whenever one fits, because each new need is another thing the player has to do.
- **Record shapes, never data.** Build results with the engine's helpers: `Shape`, `Value`, `Text`, `Fields`, `EnumName`, and `Joined`. A result is a type, a field list, an empty string, or a marker for a secret. Never record a name, an amount, or a GUID, so that any player's run compares with any other's. A secret must become `{ secret = true, type = ... }` after an `issecretvalue` check, and it's never compared or stored.
- **Only read, and stay cheap.**
  - Every 5 seconds, the sweeps run every probe that's still without an answer. They also run each accumulating probe in every sweep where its needs are met. So a need's `check` and an accumulating probe's `run` must be cheap.
  - A probe never calls a protected or restricted function, and never changes game state.
  - If the question needs an action, such as playing a vibration or registering a sound, keep it out of `/btdev probe`. Either give it its own explicit DevTools command (`/btdev rumble`), or undo it within the same run (`auraSound.api`). Say why in the file header.
- **Listen from load** when the answer can't be asked after the fact: events, payloads, orderings, and situations that can end before a sweep sees them. For example, Forever turns an item's quest offer into a tracker popup and closes the dialog at once, so a need that waits for the open dialog never sees it. DevTools.lua's listeners pass to a `Probes.Note*` function that keeps sets of shapes, so a shape seen before costs one table lookup on a busy event. Mark such a probe `accumulates = true`. Add it to the engine header's list of accumulating probes and to the README's list of what DevTools listens for.
- **Keep apart what the question tells apart.** An accumulating probe merges every shape it saw and every context it saw them in. So a record that holds "plain" and "secret", in `idle/none` and `combat/Combat`, can't say which context was secret. When the question is about one context or one variant, key the shapes by it inside the result, or give each its own probe and need.
- **Bump `version` when a result's shape changes.** A record from another version answered a different question. The import drops such a record, but the committed one stays until the user plays again, and `probes --check` fails on it. So delete the stale record from `probes.json` in the same change. That's the only hand edit `probes.json` ever takes.
- **Fake every API the probe calls.** Each fake needs a real global in the snapshot, its behavior from Blizzard's docs, and a `[D]` or `[G]` marker. A fake no code calls fails `test`.

## 3. Prove it in the harness

- `tests/probes.test.lua` runs every probe in the harness once for each recorded context. A new probe with no record prints `PEND` and doesn't fail. That's expected until the user plays.
- Test what's new beyond the probe itself through `tests/devtools*.test.lua`, such as a new command, a listener, merging, or a need's setup.
- Run these:
  1. `node tools/tlk.mjs format`
  2. `node tools/tlk.mjs check`
  3. `node tools/tlk.mjs test`
  4. `node tools/tlk.mjs probes --check`

## 4. Hand the run to the user

The user plays, and you can't. Give them the exact steps:

- **Where it falls.** Say where in the play session the need falls: the README's numbered steps, in the same order as `Probes.Steps`. Update that list in the README in the same change, so `/btdev probe list` and the docs agree.
- **What to do there.** DevTools records a probe within 5 seconds of its needs being met (`/btdev probe auto`), so the player only has to reach the situation and stay there.
  - For a situation the player holds, such as an open quest window or a target, tell them to hold it for 5 seconds.
  - For one that lasts less than 5 seconds, such as the moment of a kill, tell them to type `/btdev probe` right then.
- **Which case to find.** When the guess is about a variant, name the variant that settles it. For example, a quest started from an item or a wanted poster settles how an item-started quest behaves, and an NPC's quest doesn't.
- **What happens after.** The user types `/reload`, and then runs `node tools/tlk.mjs probes --import`. When they say they've reloaded, run the import yourself.
- **What a probe can't capture.** Name what the user has to report themselves, such as how a vibration felt, or whether something looked right.

## 5. Reconcile after an import

1. Run `node tools/tlk.mjs probes` and `node tools/tlk.mjs test probes`. A failing probe prints the context and each field where the client and the harness differ.
2. **Change the harness to match the client.** Never edit the record, loosen the probe, or add `pending()` to make a test pass. Find the harness code that models the behavior, change it, and mark it `[E]` with the probe's name ("`[E]` ... (names.chatSenders)"). Delete the guess's old wording, so no comment still describes it.
3. **Then run the whole suite.** Tests that relied on the guess may now fail. Those failures are the point: they show addon code built on behavior the client doesn't have. Fix the addon code, not the test, and say so in the commit. For example, a retry loop that waits for an event order the client never produces fails once the client's real order is recorded.
4. **Replaced records.** The import prints `Replaced <probe>` when a result or build changed. Check what reads that behavior.
5. **`PEND`s.** Leave them. List the ones still open under Found, as what's left to do in game.

## 6. Refresh after a new client build

`node tools/tlk.mjs api-sync --latest` says whether the snapshot's docs build is stale, and `build-watch.yml` opens an issue weekly when it is. Follow the README's **Refresh the snapshot** procedure:

1. **Confirm the build changed.** Compare these:
   - the installed client's build, in `.build.info` in the game's folder
   - the dump's build, in DevTools' SavedVariables
   - the snapshot's `source` in `tools/api/forever.json`

   A patch can land hours before the user notices it, and the snapshot may already be current. If all three match, nothing needs refreshing. Say so, and go on to the probe records in the last step.
2. Refresh the documented half from the `forever` branch's `Blizzard_APIDocumentationGenerated`.
3. Ask the user for a dump. Their steps:
   1. Enable only ByteTerrace's addons.
   2. Open the achievement window and any other load-on-demand Blizzard window whose names an addon uses.
   3. Type `/btdev dump`, then `/reload`.
4. Run `api-sync --globals` on the dump. Read its warnings:
   - Globals missing from the dump, grouped by first word, mean a load-on-demand window wasn't open. Name that window, and ask for another dump.
   - A global skipped for an addon outside this repository means another addon was enabled.
5. Run `check` and `test`. A global that's gone from the snapshot fails `check` wherever an addon reads it.
6. Run `probes --check --warn-builds`, which lists the records from the old build. Ask the user for a probe session on the new build, and then reconcile as in step 5 of this skill.

Before you hand over any play session, check what the client will load. The game's AddOns folders are junctions into the main checkout, not into a worktree, so the client runs main. A commit that's only on a worktree branch isn't in game yet. Never run `deploy` from a worktree, because it would repoint those junctions. If any TOC changed since the user last started the game, tell them to restart it, not only `/reload`.

## 7. Commit and report

Probe commits name what the client said. Some example subjects:
- "Record UNIT_AURA's target token in combat: plain"
- "Follow the client's combat edges and chat discordInfo"
- "Probe PvP damage meter secrecy, aura sounds and encounter warnings"

The body says:

1. What the client answered, or for a new probe, what it asks and why it matters.
2. What changed in the harness (with its marker), and in the addons as a result.
3. `check passes; N tests pass.`, and for a new probe, that it hasn't run in the client yet.
4. The Co-Authored-By line the session's attribution gives.

End with **Needs you** (the in-game steps), **Changed**, and **Found**.
