---
name: forever-probe
description: Ask the real WoW Forever client how it behaves and calibrate the test harness to its answer. This covers deciding that a harness guess needs a probe, writing the probe in ByteTerrace_DevTools (needs, read-only shapes, versions, listeners), handing the in-game run to the user, and reconciling after `tlk probes --import`. Use this whenever the harness and the client might disagree. Examples include a `probes.test.lua` failure or `PEND` line, a `[G]` or `[C]` guess a feature depends on, "is X secret in combat on Forever?", "what does the client fire when...", `/btdev probe` or `/btdev dump` results, a replaced probe record after a new build, or any request to probe, record or confirm client behavior. Use it even when the user only reports that tests broke after an import. Don't use it for building a player-facing feature (forever-feature) or for refreshing the API snapshot's documented half (`tlk api-sync`).
---

# Probing the client and calibrating the harness

The harness is only as honest as its evidence. A probe asks the client one read-only question in a situation both the game and the harness can reach, so the harness's answer can be compared with the client's. Observed answers outrank guesses (CLAUDE.md rule 5): when they disagree, the harness changes, never the record, the probe or the test.

The README's [Probes](../../../README.md#probes) section is the user's procedure, and `ByteTerrace_DevTools/Probes.lua`'s header is the engine's contract. Read both before writing a probe. This skill is the order to work in, and the traps.

## 1. Decide whether it needs a probe

Look before asking:

1. **`tools/api/probes.json`**: `grep -n '"<probe.name>"' tools/api/probes.json`, or run `node tools/tlk.mjs probes` for every probe with its needs, the client's answer and the harness's. A record from the snapshot's build that covers the context you care about (`idle/none`, `combat/Combat`) settles it.
2. **`tools/api/forever.json`**: the documented flags (`SecretReturns`, `SecretWhen*`, `HasRestrictions`, `Nilable`). If the docs settle the behavior, the harness models it as `[D]` and no probe is needed.
3. **The harness's own markers** in `tests/harness/*.lua`: `[D]` documented, `[E]` observed in the client, `[G]` a guess, `[C]` a conservative fallback (secrets.lua). A `[G]` or `[C]` that a feature depends on is the usual reason to probe.

Probe when the docs are silent, ambiguous, or retail-only, and something depends on the answer. Name what depends on it, because that's what the user is spending play time on.

## 2. Write the probe

- **Find its home.** Probes go in `ByteTerrace_DevTools/Probes<Topic>.lua` by topic (`ProbesWorld`, `ProbesUnits`, `ProbesCombat`, `ProbesNames`, `ProbesInput`) through `Probes.Define`. Situations go in `ProbeNeeds.lua`. Touch `Probes.lua` only for engine changes. Run `wc -l` first: LENGTH stops at 1000 lines, so a full file means a new topic file, listed in the DevTools TOC before `DevTools.lua`.
- **Define the need.** A need has a `label`, the `text` the player reads, the session `step` it belongs to (an index into `Probes.Steps`), a `check` against the live client, and a harness `setup(h)` that recreates it. If the harness can't recreate it, give a `harness` reason instead, and its probes run in game only. Reuse an existing need whenever one fits, because each new need is another thing the player has to do.
- **Record shapes, never data.** Build results with the engine's helpers (`Shape`, `Value`, `Text`, `Fields`, `EnumName`, `Joined`): a type, a field list, an empty string, a marker for a secret. Never record a name, an amount or a GUID. Any player's run must compare with any other's, and a secret must become `{ secret = true, type = ... }` after an `issecretvalue` check, never compared or stored.
- **Only read.** A probe never calls a protected or restricted function and never changes game state. If the question needs an action (playing a vibration, registering a sound), keep the action out of `/btdev probe`: give it its own explicit DevTools command (`/btdev rumble`), or undo it within the same run (`auraSound.api`). Say why in the file header.
- **Listen from load** when the answer can't be asked after the fact (events, payloads, orderings). DevTools.lua's listeners pass to a `Probes.Note*` function that keeps sets of shapes, so a shape seen before costs one table lookup on a busy event. Mark such a probe `accumulates = true`, and add it to the engine header's list of accumulating probes.
- **Bump `version` when a result's shape changes.** A record from another version answered a different question. Delete that stale record from `probes.json` in the same change, since `probes --check` fails on it. That's the only hand edit `probes.json` ever takes.
- **Fake every API the probe calls.** Each fake needs a real global in the snapshot, its behavior from Blizzard's docs, and a `[D]` or `[G]` marker. A fake no code calls fails `test`.

## 3. Prove it in the harness

- `tests/probes.test.lua` runs every probe in the harness once for each recorded context. A new probe with no record prints `PEND` and doesn't fail. That's expected until the user plays.
- Test what's new beyond the probe itself through `tests/devtools*.test.lua`: a new command, a listener, merging, a need's setup.
- Run `node tools/tlk.mjs format`, `node tools/tlk.mjs check`, `node tools/tlk.mjs test`, and `node tools/tlk.mjs probes --check`.

## 4. Hand the run to the user

The user plays, and you can't. Give them the exact steps:

- Where in the play session the need falls (the README's numbered steps, the same order as `Probes.Steps`). Update that list in the README in the same change, so `/btdev probe list` and the docs agree.
- What to do there, then `/btdev probe`. Afterwards, a `/reload`, then `node tools/tlk.mjs probes --import`.
- What the probe can't capture and the user has to report themselves (how a vibration felt, whether something looked right).

## 5. Reconcile after an import

1. Run `node tools/tlk.mjs probes` and `node tools/tlk.mjs test probes`. A failing probe prints the context and each field where the client and the harness differ.
2. **Change the harness to match the client.** Never edit the record, loosen the probe, or add `pending()` to make a test pass. Find the harness code that models the behavior, change it, and mark it `[E]` with the probe's name ("`[E]` ... (names.chatSenders)"). Delete the guess's old wording, so no comment still describes it.
3. **Then run the whole suite.** Tests that relied on the guess may now fail, and those failures are the point: they show addon code built on behavior the client doesn't have. Fix the addon code, not the test, and say so in the commit. (When the client's combat edges came in, Kombat's retry loop turned out to wait for an order the client never produces.)
4. **Replaced records.** The import prints `Replaced <probe>` when a result or build changed. Check what reads that behavior. After a new client build, `probes --check --warn-builds` (as CI runs it) lists records from another build.
5. **`PEND`s.** Leave them. List the ones still open under Found, as what's left to do in game.

## 6. Commit and report

Probe commits name what the client said. Example subjects: "Record UNIT_AURA's target token in combat: plain", "Follow the client's combat edges and chat discordInfo", "Probe PvP damage meter secrecy, aura sounds and encounter warnings". The body says:

1. What the client answered, or for a new probe, what it asks and why it matters.
2. What changed in the harness (with its marker), and in the addons as a result.
3. `check passes; N tests pass.`, and for a new probe, that it hasn't run in the client yet.
4. The Co-Authored-By line the session's attribution gives.

End with **Needs you** (the in-game steps), **Changed** and **Found**.
