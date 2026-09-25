# ByteTerrace addon architecture

Every ByteTerrace addon is built on `ByteTerrace_Core`, a shared framework addon (Lua global `ByteTerrace`) modeled on Puck's command, input and state systems. An addon calls `ByteTerrace.NewAddOn` and declares **modules**. Each module declares its **state rows**, **commands** and **bindings**, and reacts to **events** and **state changes**. The framework compiles the declarations once when the addon loads, and the hot paths index flat arrays after that.

```
WoW events ──► Events ──► adapters (the only code that calls the WoW API)
                              │  write non-secret facts
                              ▼
slash / keys / ──► Commands ──► State rows ──► one publish per event ──► watchers & rules ──► effects
controller (Input)               (typed, validated, versioned)                              (widgets, sounds, LEDs)
settings panel ────────────────────┘
```

## State

State lives in declared rows: `{ name, kind = "boolean" | "number" | "string", default, values?, valueLabels?, min?, max?, step?, persist?, scope?, lockedBy?, label?, description?, section? }`. A module's rows are named `<Module>.<name>`; both parts are identifiers. Specs are copied when declared, so the caller's tables are never changed and one spec can be shared by several addons.

- **Compile once.** When the addon loads, rows are sorted by name and given dense integer ids, so the ids don't depend on declaration order. Every declaration is validated, and all problems are reported together. Declaring after compile is an error.
- **One admission path.** Every write goes through `State:Set`, which checks kind, enum, bounds and finiteness, and refuses secret values because rules compute over rows. Writing the value a row already holds returns before any validation, the common case in handlers.
- **Persistence.** Persisted rows load from the addon's SavedVariables (`scope = "account"`, the default) or its per-character SavedVariables (`scope = "character"`, which needs `savedVariablePerCharacter`).
  - A saved value that no longer validates is reset to the default, and so is a key under a declared module that no row declares (a renamed row).
  - A key under a module this load didn't declare is kept, so a module whose file failed to load keeps its settings.
  - Only non-default values are stored, so changing a default takes effect.
- **Locks.** `lockedBy = "<Module>.<row>"` names a boolean row. While it's true, `State:Set` refuses the locked row, `/set` and `/toggle` print that it's locked, and its settings control reverts. `State:IsLocked(ref)` tells callers ahead of time. Compile refuses a `lockedBy` that doesn't name a boolean row.
- **Change and publication.** A row changes only if its value at publish differs from its baseline. The baseline is the row's value when the batch first touched it, or, for a watcher registered later in the same batch, its value when that watcher registered. So a watcher never reacts to a write made before it existed.
  - Each event dispatch, each command run and each `addon:Batch(fn)` is one batch. After the batch, one publication pass runs every watcher whose rows changed, once each, in registration order.
  - Writes made by watchers publish in a further round. A batch still scheduling watchers after 8 rounds is reported instead of looping; its writes still count.
  - An unbalanced `EndBatch` is an error.
- **Rules.** `Rule{ reads, when, changed, initial }` is a verdict over rows. `changed(active, state)` runs when the verdict flips (edge semantics); with `initial` it also runs once with the first verdict.
  - A rule registered inside a batch (a module starting, say) takes its first verdict when that batch publishes, so what modules do while starting doesn't depend on the order they were declared in.
- **Settings.** The options panel is generated from labeled persisted rows, in declaration order: a checkbox for booleans, a dropdown for enums, and a slider for bounded numbers. Compile refuses a labeled row with no fitting control.
  - **Pages.** The addon's category, named by its title, is the main page. A module with `page = "<name>"` puts its settings on a subcategory of that name; subcategories appear in the order their first settings are declared. Only the main category is registered as the addon's category, and the client lists the subcategories under it.
  - **Sections.** On its page, a module's settings sit under a header: the module's `section`, or else its `label`. A row with `section = "<text>"` starts a new header before that row. A header that would repeat its page's name is left out. `addon.debug` is declared last, under an "Advanced" header, so it closes the main page.
  - Controls are proxy settings, so a panel change goes through `State:Set` like any other write.
  - A change made elsewhere refreshes the control.
  - The panel opens after combat if asked for during lockdown.

## Records

A module's `records = { { name, fields, limit, evict?, scope? } }` declares a keyed collection, `module.Records.<name>`, for data that's one entry per thing (a ledger of players, say) rather than one value.

- **Fields** are declared like rows (`kind`, `default`, `values`, `min` / `max` / `step`), and every write goes through the same admission check, secrets included. `Set(key, fields)` validates everything before writing anything and merges into the record. `Field(key, name)` reads one value, defaulting for an absent record. `Get`, `Has`, `Keys`, `Count`, `Remove` and `Clear` do the rest. Keys are plain strings of 1 to 64 characters.
- **Limit.** At `limit`, a new key evicts the record with the lowest `evict` field (a last-seen time, say), skipping keys the optional `keep(key)` protects. Without `evict`, or when every key is kept, a full collection refuses new keys.
- **Version row.** The collection is also a runtime number row of the same name that moves on every change, so watchers and rules react to it and it publishes with its batch.
- **Persistence.** The collection lives under its name in the addon's SavedVariables (by `scope`), storing only fields that differ from their defaults. Loading drops records that aren't tables or have bad keys, and resets fields that no longer validate.

## Events

There is one dispatcher frame per addon, and handlers are registered through `module:On(event, fn, unit)`.

- An event is registered with the client only while some handler wants it, and the registration is touched only when what's wanted changes. A stopped module therefore costs nothing.
- Unit filters compile to `RegisterUnitEvent` when at most two units are wanted. A payload unit token that is itself secret is never compared; filtered handlers just don't receive it.
- Handler lists are copy-on-write: registering allocates, dispatching never does. `Off` takes effect immediately, including for the rest of a dispatch in progress.
- Each handler is isolated with `ByteTerrace.SafeCall`, WoW's argument-passing `xpcall`. An error reaches the client's error handler with its own stack, and the other handlers still run.

## Commands

A command is a named intent, `{ name, label, run(arg, phase, source), slash?, held? }`. Slash text, key bindings, controller buttons and settings all run the same definition.

- **Compile.** Commands are sorted into ids. Duplicate names, duplicate slash words, and slash words that aren't lowercase single words are refused.
- **Batches.** Each run is one state batch, so a command that writes several rows publishes once.
- **Phases.** Every command gets `"down"`. Held commands also get `"up"` and `"cancel"`.
- **Module commands** run only while their module runs; otherwise the player is told it's turned off. A command marked `always` runs regardless, e.g. one that turns its own module on.
- **Built-in commands:** bare slash (open settings), `help`, `version`, `debug`, `set <setting> <value>`, and `toggle <setting>`. `set` and `toggle` only reach settings (labeled, persisted rows), never internal rows.
- **Slash aliases:** an alias another addon already registered is reported and skipped; the addon still starts.
- **Limit:** commands are insecure. They drive the addon's own UI and state, never protected actions such as casting or targeting.

## Input

Controller sources are named by position (`gamepad.south`), never by printed letter. `Input.Label(source)` gives the connected family's printed name: A on Xbox, Cross on PlayStation, B on Switch.

- **Maps.** A binding is `{ map, source, command }`. `SetActiveMaps` activates maps: several maps form an overlay, one map is modal.
- **Capture.** While any bound button is active, a capture frame takes those buttons and every other button propagates to the game.
  - The frame is parentless, so hiding the UI doesn't stop capture.
  - `EnableGamePadButton` is flagged protected, but like `Show` and `Hide` that only restricts Secure frames, so capture works in combat.
- **Latching.** A release always goes to the command its press went to. A held command whose map is deactivated while its button is down gets `"cancel"`.

## Modules and facts

`addon:Module(name, spec)` declares a module. A module with a `label` gets an `<Module>.enabled` row, and its checkbox appears in the settings panel. Its `page` and `section` place its settings (see Settings above).

- **Switch options.** `default` sets the enabled row's default (true unless given). `scope` and `lockedBy` apply to it like any row, so `scope = "character"` makes a module per character, and a lock can keep it on.
- **Activation.** A module runs while its enabled row is true and its optional `active = { reads, when }` rule holds. That's how a module depends on other rows: a sound's module runs only while the Sounds master switch and that sound's toggle are on.
- **Ownership.** Everything a module creates through `module:On`, `:Watch` and `:Rule` belongs to it and is torn down in one pass when it stops.
- **Runtime rows reset.** When a module stops, its runtime (`persist = false`) rows return to their defaults, so no reader ever sees stale facts.
- **Isolated starts.** A module that fails to start is reported and the rest still start.
- **Reserved names:** `addon` and the fact names.
- **Stopping through the row.** Switching a module off through its row takes effect when that batch publishes, like any write; `module:SetEnabled(false)` stops it immediately.

**Facts** are shared runtime rows, such as `combat.active` and `afk.active`. An addon opts in with `facts = { ... }`. A fact's adapter is the only code that reads its API. Facts are declared first and take their real value the moment they're enabled, so a `/reload` in combat doesn't look like combat starting to any rule.

## Secret values

Forever runs the Midnight (12.x) API, where combat values such as health and primary power are *secret*. Addons can display a secret value but can't compare it, compute with it, or branch on it.

- **Display:** a secret value goes straight to a widget (`StatusBar:SetValue`, `FontString:SetText`) and never enters state.
- **Logic:** logic reads facts that adapters derive from APIs that aren't secret. Where an API can return a secret, the adapter checks `issecretvalue` and keeps the last known value.
- **Restricted calls:** opening the settings panel is restricted in combat, so it's deferred until combat ends.
- **Enforcement:** the check gate and the test harness enforce these rules (see [Development](../README.md#development)).

## Performance

Performance is judged by load-independent counts, not wall-clock time. The tests assert:

- widget calls per event, such as one `SetValue` per power event and no range update per tick;
- which events are registered, such as no power events for a class without energy, no usability polling for non-warriors, and no target events once every target sound is switched off;
- registration churn, such as one unregister when a module with five handlers stops.

In code:

- Cache globals as file-level locals.
- Resolve row ids once and read `state.Values[id]` in hot paths.
- Create no closures or tables inside event handlers.

## Adding a module

```lua
local addonName, ns = ...

ns.Addon:Module("Example", {
    label = "Example", description = "What the checkbox does.",
    page = "Examples", -- optional: its own settings subcategory
    state = { { name = "mode", kind = "string", default = "a", values = { "a", "b" }, label = "Mode" } },
    commands = { { name = "cycle", slash = "example", label = "Cycle the mode", run = function() ... end } },
    OnEnable = function(module)
        local combat = module:Id("combat.active")
        module:Rule({ reads = { combat }, when = function(state) return state.Values[combat] end,
            changed = function(active) ... end })
    end,
})
```

To finish a new module:

1. List the file in the TOC.
2. Add behavioral tests to `tests/`.
3. Run `node tools/tlk.mjs check` and `node tools/tlk.mjs test`.
