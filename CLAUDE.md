# CLAUDE.md

ByteTerrace World of Warcraft addons for **WoW: Forever** (TOC `_Camelot.toc`, Midnight 12.x API with secret values). The bar is Puck's: correctness and performance proven by gates, not asserted. Read [the architecture](docs/Architecture.md) before touching `ByteTerrace_Core/` or adding a module, and the [README](README.md#development) for the workflow.

## Rules

1. **Build on the framework.** Features are modules on an addon built with `ByteTerrace.NewAddOn` (from `ByteTerrace_Core`). State lives in declared rows, intents are commands, controller input goes through `Input` maps, and events go through `module:On`. A feature that hand-wires frames, SavedVariables, slash parsing or settings duplicates the framework, and that's a defect.
2. **Find it before building it.** Forever is new: verify behavior against Blizzard's Forever UI source (the `forever` branch of Gethe/wow-ui-source) and `tools/api/forever.json`, never against Classic Era memory. A second implementation of something the framework or Blizzard already provides is a defect.
3. **Secret values.** A value from an API with secret flags goes straight to a widget, or is checked with `issecretvalue`. It never enters state, and code never compares it, computes with it or branches on it. Annotate widget sinks with `-- secret: <why>`. Only adapters (event handlers) call the WoW API; rules read rows.
4. **Gates prove observable behavior.**
   - `node tools/tlk.mjs check` and `node tools/tlk.mjs test` must pass before any change is done.
   - A new behavior gets a test that drives the real addon files through the harness.
   - A bug fix gets a test that failed before the fix.
   - Performance is proven with load-independent counts (widget calls per event, registered events), never wall-clock time.
   - What the harness can't model (the real client, rendering, protected actions) is verified by running in game. Say plainly when something hasn't been.
5. **The harness stays honest.** A fake models a real API: its name must exist in the snapshot, and its behavior must match Blizzard's docs. Never loosen a fidelity rule to make a test pass.
6. **Supergreen.** Nothing has shipped. Rename, reshape and delete freely, and update every caller in the same change. No compat shims or migration code: the state loader drops undeclared or invalid saved values by design.
7. **Automation is CLI verbs.** Add a verb to `tools/tlk.mjs`; never add a loose script. Pin dependency versions.
8. **Docs state current behavior in the present tense.** No dates, build numbers or commit SHAs in docs; evidence belongs in commit messages. Update every doc, comment and test that describes a change, in the same change.
9. **LF everywhere** (`.gitattributes`, `.editorconfig`). Never investigate or work around line endings.

## Reporting

End a long run with **Needs you** (decisions or approvals), **Changed** (what landed and how it was verified) and **Found** (defects, risks, follow-ups). Mark anything unverified, and say where you looked.
