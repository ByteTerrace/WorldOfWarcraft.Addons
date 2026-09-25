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

State lives in declared rows: `{ name, kind = "boolean" | "number" | "string", default, values?, min?, max?, persist?, label?, description? }`. A module's rows are named `<Module>.<name>`.

- **Compile once.** When the addon loads, rows are sorted by name and given dense integer ids, so the ids don't depend on declaration order. Every declaration is validated, and all problems are reported together. Declaring after compile is an error.
- **One admission path.** Every write goes through `State:Set`, which checks kind, enum, bounds and secrecy. A secret value is refused, because rules compute over rows.
- **Persistence.** Persisted rows load from the addon's SavedVariables. Rows that are no longer declared, and values that no longer validate, are dropped. Only non-default values are stored, so changing a default takes effect.
- **Change and publication.** A row changes only if its value at publish differs from its value when the batch first touched it. Each event dispatch is one batch. After the batch, one publication pass runs every watcher whose rows changed, once each, in registration order. Writes made by watchers publish in a further round. A publish that doesn't settle within 8 rounds is reported instead of looping.
- **Rules.** `Rule{ reads, when, changed }` is a verdict over rows. `changed(active)` runs when the verdict flips (edge semantics).
- **Settings.** The options panel is generated from labeled persisted rows, in declaration order. Its controls are proxy settings, so a panel change goes through `State:Set` like any other write.

## Events

There is one dispatcher frame per addon, and handlers are registered through `module:On(event, fn, unit)`.

- An event is registered with the client only while some handler wants it. A disabled module therefore costs nothing.
- Unit filters compile to `RegisterUnitEvent` when at most two units are wanted.
- Handler lists are copy-on-write: registering allocates, dispatching never does.
- Each handler is isolated. An error is reported through the client's error handler, and the other handlers still run.

## Commands

A command is a named intent, `{ name, label, run(arg, phase, source), slash?, held? }`. Slash text, key bindings, controller buttons and settings all run the same definition.

- **Compile.** Commands are sorted into ids. Duplicate names and slash words are refused.
- **Phases.** Every command gets `"down"`. Held commands also get `"up"` and `"cancel"`.
- **Built-in commands:** bare slash (open settings), `help`, `version`, `debug`, `set <row> <value>`, and `toggle <row>`.
- **Limit:** commands are insecure. They drive the addon's own UI and state, never protected actions such as casting or targeting.

## Input

Controller sources are named by position (`gamepad.south`), never by printed letter. `Input.Label(source)` gives the connected family's printed name: A on Xbox, Cross on PlayStation, B on Switch.

- **Maps.** A binding is `{ map, source, command }`. `SetActiveMaps` activates maps: several maps form an overlay, one map is modal.
- **Capture.** While any bound button is active, a capture frame takes those buttons and every other button propagates to the game.
- **Latching.** A release always goes to the command its press went to. A held command whose map is deactivated while its button is down gets `"cancel"`.

## Modules and facts

`addon:Module(name, spec)` declares a module. A module with a `label` gets an `<Module>.enabled` row, and its checkbox appears in the settings panel. Everything a module creates through `module:On`, `:Watch` and `:Rule` belongs to it and is removed when it's disabled.

**Facts** are shared runtime rows, such as `combat.active` and `afk.active`. An addon opts in with `facts = { ... }`. A fact's adapter is the only code that reads its API.

## Secret values

Forever runs the Midnight (12.x) API, where combat values such as health and primary power are *secret*. Addons can display a secret value but can't compare it, compute with it, or branch on it.

- **Display:** a secret value goes straight to a widget (`StatusBar:SetValue`, `FontString:SetText`) and never enters state.
- **Logic:** logic reads facts that adapters derive from APIs that aren't secret. Where an API can return a secret, the adapter checks `issecretvalue` and keeps the last known value.
- **Enforcement:** the check gate and the test harness enforce both rules (see [Development](../README.md#development)).

## Performance

Performance is judged by load-independent counts, not wall-clock time. The tests assert:

- widget calls per event, such as one `SetValue` per power event and no range update per tick;
- which events are registered, such as no power events for a class without energy and no usability polling for non-warriors.

In code:

- Cache globals as file-level locals.
- Resolve row ids once and read `state.values[id]` in hot paths.
- Create no closures or tables inside event handlers.

## Adding a module

```lua
local addonName, ns = ...

ns.addon:Module("Example", {
    label = "Example", description = "What the checkbox does.",
    state = { { name = "mode", kind = "string", default = "a", values = { "a", "b" }, label = "Mode" } },
    commands = { { name = "cycle", slash = "example", label = "Cycle the mode", run = function() ... end } },
    OnEnable = function(module)
        local combat = module:Id("combat.active")
        module:Rule({ reads = { combat }, when = function(s) return s.values[combat] end,
            changed = function(active) ... end })
    end,
})
```

To finish a new module:

1. List the file in the TOC.
2. Add behavioral tests to `tests/`.
3. Run `node tools/tlk.mjs check` and `node tools/tlk.mjs test`.
