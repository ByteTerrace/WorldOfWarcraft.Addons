# ByteTerrace addon architecture

Every ByteTerrace addon is built on `ByteTerrace_Core`, a shared framework addon (Lua global `ByteTerrace`) modeled on Puck's command, input, and state systems. An addon calls `ByteTerrace.NewAddOn` and declares *modules*. Each module declares its *state rows*, *commands*, and *bindings*, and reacts to *events* and *state changes*. The framework compiles the declarations once when the addon loads, and after that the hot paths index flat arrays.

```
WoW events ──► Events ──► adapters (the only code that calls the WoW API)
                              │  write non-secret facts
                              ▼
slash / keys / ──► Commands ──► State rows ──► one publish per event ──► watchers & rules ──► effects
controller (Input)               (typed, validated, versioned)                              (widgets, sounds, LEDs)
settings window ───────────────────┘
```

## State

State lives in declared rows: `{ name, kind = "boolean" | "number" | "string", default, values?, valueLabels?, min?, max?, step?, persist?, scope?, lockedBy?, label?, description?, section? }`. A module's rows are named `<Module>.<name>`, and both parts are identifiers. Specs are copied when declared, so the caller's tables are never changed, and one spec can be shared by several addons.

- **Compile once.** When the addon loads, rows are sorted by name and given dense integer ids, so the ids don't depend on declaration order. Every declaration is validated, and all problems are reported together. Numeric bounds must be finite and ordered, and a step must be finite and positive. Declaring once the addon starts loading is an error, even after a refused start.
- **One admission path.** Every write goes through `State:Set`, which checks kind, enum, bounds, and finiteness. It refuses secret values, because rules compute over rows. Defaults and saved values use the same secret-safe admission check, including record fields. Writing the plain value a row already holds returns before schema validation, the common case in handlers.
- **Persistence.** Persisted rows load from the addon's SavedVariables (`scope = "account"`, the default) or its per-character SavedVariables (`scope = "character"`, which needs `savedVariablePerCharacter`).
  - A saved value that no longer validates is reset to the default. So is a key under a declared module that no row declares (a renamed row).
  - A key under a module this load didn't declare is kept, so a module whose file failed to load keeps its settings.
  - Only non-default values are stored, so changing a default takes effect.
- **Locks.** `lockedBy = "<Module>.<row>"` names a boolean row. While it's true, `State:Set` refuses the locked row, `/set` and `/toggle` print that it's locked, and its settings control reverts. `State:IsLocked(ref)` tells callers ahead of time. Compile refuses a `lockedBy` that doesn't name a boolean row.
- **Change and publication.** A row changes only if its value at publish differs from its baseline. The baseline is the row's value when the batch first touched it. For a watcher registered later in the same batch, the baseline is the row's value when that watcher registered, until that row's next publish round. So a watcher never reacts to a write made before it existed, and it hears every change after.
  - Each event dispatch, each command run, and each `addon:Batch(fn)` is one batch. After the batch, one publication pass runs every watcher whose rows changed, once each, in registration order.
  - Writes made by watchers publish in a further round. A batch still scheduling watchers after eight rounds is reported instead of looping. Its writes still count.
  - Rules that recursively register initial callbacks are bounded too. Excess pending rules are removed and reported rather than leaking into the next batch.
  - An unbalanced `EndBatch` is an error, including one a watcher calls beyond its own `BeginBatch`. It can't close the publish that runs it, so later writes still publish.
- **Rules.** `Rule{ reads, when, changed, initial }` is a verdict over rows. `changed(active, state)` runs when the verdict flips (edge semantics). With `initial`, it also runs once with the first verdict.
  - A rule registered inside a batch (a module starting, say) takes its first verdict when that batch publishes. So what modules do while starting doesn't depend on the order they were declared in.

### Settings

The settings window is generated from labeled persisted rows, and organized so a player finds a setting by name. Compile refuses a labeled row with no fitting control. The controls are:

- a checkbox for a boolean
- a dropdown listing an enum's values (the view's own, not Blizzard's menu, which takes controller focus as it opens)
- `-` and `+` steppers for a bounded number

The window is laid out like this:

- **Pages.** The main page is named by the addon's title, and a module whose `page` is that title joins it. A module with `page = "<name>"` puts its settings on a page of that name. The main page comes first, and the others follow alphabetically, listed down the window's left side and under the addon's category in Blizzard's settings panel.
- **Sections.** A setting's section is its row's `section`, else the last section an earlier row of its module named, else the module's `section`, else its `label`. Modules can share a section by naming the same one. A section that repeats its page's name, or a module with neither, puts its settings at the top of the page, under no header. On a page, the top comes first, then the sections alphabetically, and the addon's own (`addon.debug`'s "Advanced") last.
- **Settings.** Within a section, settings are alphabetical by label. A section's first-declared setting stays first when it's a module's on/off switch, so the switch leads what it turns on. Names sort ignoring case.
- **Hosts.** One view draws the pages, and it moves to whichever host shows it. In Blizzard's settings panel (Esc > **Options** > **AddOns**), each page is a canvas page: the main page is the addon's category, and every other page is a subcategory under it, so Blizzard's list picks the page. The bare slash command toggles the addon's own window, an ordinary frame, so it opens in combat too, and addon code never opens Blizzard's panel. In either host:
  - Every change goes through `State:Set`, and a locked row is refused with a message.
  - A change made elsewhere refreshes the page that shows.
  - Only that page's rows are watched, so a hidden view or page costs nothing until it shows.
  - A page taller than its host scrolls in it, clipped, a row a notch of the mouse wheel or a row a step of its scroll bar's thumb (the client's own `Slider`), and always shows whole rows. Each step moves the page by whole screen pixels (`PixelUtil.GetNearestPixelSize`), so 1-pixel borders stay sharp at any UI scale. A section's header sits next to the first setting under it. The window grows with its page up to the screen's height, less a margin.
  - The controls' column is as wide as the widest dropdown choice needs, and the window as wide as the longest label beside it.
- **Controller-safe.** Each canvas is marked ignored for the controller UI's navigation (`smartNavigationIgnored`, which covers every child), and the addon registers no Blizzard setting controls. On Forever, controller focus on an addon's control taints what the controller UI remembers, and closing the panel then freezes the game. With the controller UI on, the canvas pages are for the mouse, and the window is the way in.

## Records

A module's `records = { { name, fields, limit, evict?, scope? } }` declares a keyed collection, `module.Records.<name>`. It's for data that's one entry per thing (a ledger of players, say) rather than one value.

- **Fields** are declared like rows (`kind`, `default`, `values`, `min`, `max`, and `step`). Every write goes through the same admission check, secrets included.
- **Access.** `Set(key, fields)` validates everything before writing anything, and merges into the record. `Field(key, name)` reads one value, defaulting for an absent record. `Get`, `Has`, `Keys`, `Count`, and `Remove` do the rest.
- **Keys** are plain strings of 1 to 64 bytes (an accented letter takes two).
- **Limit.** At `limit`, a new key evicts the record with the lowest `evict` field (a last-seen time, say), skipping keys the optional `keep(key)` protects. Without `evict`, or when every key is kept, a full collection refuses new keys. A `keep` function that errors protects nothing, and the error reaches the error handler: it can't stop the addon loading.
- **Version row.** The collection is also a runtime number row of the same name that moves on every change. So watchers and rules react to it, and it publishes with its batch. Evicting and inserting a replacement is one change: watchers see the complete collection, never a temporary vacancy.
- **Persistence.** The collection lives under its name in the addon's SavedVariables (by `scope`), storing only fields that differ from their defaults. Loading drops records that aren't tables or have bad keys, and resets fields that no longer validate.

## Events

There's one dispatcher frame per addon, and handlers are registered through `module:On(event, fn, unit)`.

- An event is registered with the client only while some handler wants it, and the registration is touched only when what's wanted changes. A stopped module therefore costs nothing.
- Unit filters compile to `RegisterUnitEvent` when at most two units are wanted and every handler filters. A payload unit token that's itself secret is never compared. Filtered handlers don't receive it, while unfiltered handlers still do.
- Handler lists are copy-on-write: registering allocates, and dispatching never does. `Off` takes effect immediately, including for the rest of a dispatch in progress.
- Each handler is isolated with `ByteTerrace.SafeCall`, WoW's argument-passing `xpcall`. An error reaches the client's error handler with its own stack, and the other handlers still run.

## Commands

A command is a named intent, `{ name, label, run(arg, phase, source), slash?, held? }`. Slash text, key bindings, controller buttons, and settings all run the same definition.

- **Compile.** Command specs are copied at declaration and sorted into ids. Compile refuses missing callbacks or labels, duplicate names, duplicate slash words, and slash words that aren't lowercase single words. Validation sees the actual callback. Activation checks happen in the command dispatcher.
- **Batches.** Each run is one state batch, so a command that writes several rows publishes once.
- **Phases.** Every command gets `"down"`. Held commands also get `"up"` and `"cancel"`.
- **Module commands** run only while their module runs. Otherwise, the player is told it's turned off. A command marked `always` runs regardless, for example one that turns its own module on.
- **Built-in commands:** bare slash (open settings), `help`, `version`, `debug` (see [Diagnostics](#diagnostics)), `set <setting> <value>`, and `toggle <setting>`. `set` and `toggle` only reach settings (labeled, persisted rows), never internal rows.
- **Slash aliases:** an alias another addon already registered is reported and skipped. The addon still starts.
- **Limit:** commands are insecure. They drive the addon's own UI and state, never protected actions such as casting or targeting.

## Input

Controller sources are named by position (`gamepad.south`), never by printed letter. `Input.Label(source)` gives the connected family's printed name: A on Xbox, Cross on PlayStation, and B on Switch. `Input.Glyph(source, size)` gives the button's own art as the controller UI draws it, as inline text markup, or nil when the client has no art for it. `Input.Prompt(source, size)` gives the glyph, or the printed name without one. A feature shows a controller button with `Prompt`.

- **Maps.** A binding is `{ map, source, command }`, and a map binds one module's commands (or the addon's own). Compile refuses a map that mixes modules. `SetActiveMaps` activates exactly the maps it's given, and when two of them bind a source, the later one wins. A module that stops deactivates its maps, even when its own `OnDisable` fails, so a stopped feature never keeps the controller.
- **Capture.** While any bound button is active, a capture frame takes every controller button: bound ones run their commands, and the rest do nothing. The client ignores a controller script's return value, so capture can't pass a button on to the game (seen in game under Scholar's riddle), and an active map is modal for the controller.
  - The frame is parentless, so hiding the UI doesn't stop capture.
  - `EnableGamePadButton` is flagged protected, but, as with `Show` and `Hide`, that only restricts Secure frames. So capture works in combat.
- **Summons.** `Input:Summon(module, source, command)` binds one button to a command without capture, so every other button stays the player's. It's a non-priority override binding (`SetOverrideBindingClick`) to the addon's summon button, so Blizzard's own priority bindings, such as an open panel's buttons, still win. It works only for a running module and out of combat lockdown, and returns whether it took. Combat starting ends every summon during `PLAYER_REGEN_DISABLED`, before lockdown (the `combat.edges` probe), and a stopping module's summons end with it. Summons of one button stack: the latest wins, and the same module and command summoned again moves back to the top. `Input:Dismiss(module, source, command)` ends exactly that summon, and the button goes to the one below it, or back to the game. A summon runs its command on the press only, since whether the client clicks a binding on its release is unknown, so a summon can't be `held`. A summon is how a feature offers the controller without taking it: Cards summons Select to focus a question card, and Scholar's riddle summons its own buttons, so Start and every other button stay the game's.
- **Sharing the maps.** `Input:ActiveMaps()` returns the active maps' names, so a feature can add or remove its own map and keep the others.
- **Latching.** A release always goes to the command its press went to. A held command whose map is deactivated while its button is down gets `"cancel"`. When its own press changed the maps, the cancel comes after that press's `"down"` returns. A held command has no slash word: slash text only presses.

## Modules and facts

`addon:Module(name, spec)` declares a module. A module with a `label` gets an `<Module>.enabled` row, and its checkbox appears in the settings window. Its `page` and `section` place its settings (see [Settings](#settings)).

- **Switch options.** `default` sets the enabled row's default (true unless given). `scope` and `lockedBy` apply to it like any row, so `scope = "character"` makes a module per character, and a lock can keep it on.
- **Atomic declarations.** Rows, records, commands, bindings, and comms are prepared before anything is registered. A declaration that raises leaves no partial module or ownership of saved keys behind, and can be retried with a corrected spec. Startup validates commands and bindings before normalizing saved rows and records.
- **Activation.** A module runs while its enabled row is true and its optional `active = { reads, when }` rule holds. That's how a module depends on other rows: a sound's module runs only while the Sounds master switch and that sound's toggle are on.
- **Ownership.** Everything a module creates through `module:On`, `:Watch`, `:OnIncrease`, `:Rule`, `:Listen`, `:After`, and `:Every` belongs to it and is torn down when it stops. Ownership is established before an initial watcher or rule callback can stop the module. `module:Off(handle)` releases the dead callback immediately, keeping teardown work proportional to live registrations.
- **Deferred UI actions.** Use `module:Callback(fn, ...)` for menu choices and card actions created while the module runs. It binds the given arguments, preserves nil arguments, ignores the UI's invocation arguments, and runs the action as one isolated state batch. It returns no value, preserving Blizzard's default menu response. The callback expires when this activation stops, and stays inert after a restart. `module:IsRunning()` excludes teardown too.
- **Timers.** `module:After(seconds, fn)` and `module:Every(seconds, fn)` run `fn` as one state batch, isolated like a handler, and never after the module stops. So a retry scheduled by a feature the player switched off doesn't fire. `module:Cancel(timer)` cancels one early. Scheduling on a stopped module is an error.
- **Rising counts.** `module:OnIncrease(row, fn)` runs `fn(state, count, previous)` when a count row goes up. It's how a feature reacts to something that happened (a kill, a death) rather than to a value. A count that falls (a stopped module resetting its rows) is only remembered.
- **Demand dependencies.** A module with `demand = true` (and `toggle = false`, no `active` rule) runs only while a running module names it in `uses = { ... }`. A user's dependencies start before its `OnEnable`, so their rows hold real values for its first reading, and their handlers for an event run before its own. They stop after the last user stops. Start refuses a `uses` that names an unknown or non-demand module, or forms a cycle.
- **Runtime rows reset.** When a module stops, its runtime (`persist = false`) rows return to their defaults, so no reader ever sees stale facts.
- **Isolated starts.** A module that fails to start is reported, tears down its resources, resets runtime rows, and releases acquired dependencies. Unrelated modules still start. A failed dependency prevents its user's `OnEnable` from running. Starting and stopping each form one state batch. A stop remains in progress through dependency teardown, so cleanup can't restart its owner midway through.
- **Reserved names:** `addon` and the fact names.
- **Stopping through the row.** Switching a module off through its row takes effect when that batch publishes, like any write. `module:SetEnabled(false)` stops it immediately.

### Facts

*Facts* are shared runtime rows. An addon opts in with `facts = { ... }`. A fact's adapter is the only code that reads its API. Facts are declared first and take their real value the moment they're enabled, so a `/reload` in combat doesn't look like combat starting to any rule.

- `combat` and `afk` always run: `combat.active` and `afk.active`.
- `target`, `kills`, `death`, and `restriction` are demand facts, running only while a module that uses them runs:
  - `target`: what your target is (`target.serial`, `enemyPlayer`, `formidable`, `alive`, `died`, and `duelEnded`). A health event only re-reads whether it lives (one API call). Attackability and rank re-read on the events that change them.
  - `kills`: honorable kills and their victim (`kills.honorable` and `kills.victim`), and your world PvP killing blows from `PARTY_KILL` (`kills.blows`). Killing blows with secret GUIDs in instances don't count.
  - `death`: your deaths (`death.count`) and your killer from Blizzard's death recap (`death.killer`, `killerKind`, `killerClass`, `killerFaction`, `killerSpell`, and `killerDamage`). They're published with `death.attributed`, which rises once per death even when the killer stays unknown.
  - `restriction`: which addon restrictions are in force (`restriction.combat`, `encounter`, `challengeMode`, `pvpMatch`, `map`, and `chat`). Activating counts as in force, since Forever sends Combat Activating and no Active. The rows start from `C_RestrictedActions.IsAddOnRestrictionActive`. Comms reads the restriction event itself rather than this fact, because it empties its queue during that event, and a fact row changes only after it.

## Group messages

A module's `comms = { prefix, interval?, queue? }` gives it `module.Comms`: `Send(kind, fields, urgent)` and `Ready()`.

- **Subscribe** in the receiving feature's `OnEnable` with `module:Listen(comms, kind, fn)`, where `fn(sender, fields)` gets each valid message of that kind. The transport can belong to another module (the toolkit shares `ns.Krew`).
- **Subscriptions are removed automatically** when the receiving feature stops. The lower-level `comms:Listen` returns a handle for `comms:Unlisten` when manual ownership is needed.

Every feature that talks to the group plays by Blizzard's addon message rules the same way:

- **Your own group only:** party, raid, or instance chat. Received messages must arrive on a group channel.
- **At most one message per `interval`,** from a bounded queue:
  - The interval defaults to 1 second, and that's also its least: the client regains one message a second per prefix.
  - The queue holds eight by default. Beyond it, messages are dropped, and debug output names them.
  - An urgent message goes to the front. Into a full queue, it takes the place of the newest message that isn't urgent.
  - A client throttle keeps the message queued for the next turn. `GeneralError` keeps it for up to three such answers, and `AddOnMessageLockdown` clears the queue.
  - A send that raises is reported through the error handler and leaves the queue, which keeps going.
  - A prefix the client won't register (too many prefixes) is reported.
- **Nothing during chat messaging lockdown.** An activating or active Encounter, ChallengeMode, PvPMatch, Map, or Chat restriction, or leaving the group, immediately clears the queue and cancels its pending send, even if lockdown ends before the next send deadline. Combat alone and inactive restriction events leave the queue intact. Sending rechecks lockdown.
- **Secret payloads (lockdown) are ignored,** and so are your own messages the client echoes. `CHAT_MSG_ADDON` is registered only while you're in a group, and the prefix is tested first. So other addons' messages cost nothing solo, and one check grouped.
- **Messages are parsed strictly:** an uppercase kind, then tab-separated fields.
  - Scalar fields and dense arrays use one encoder. It takes plain strings, finite numbers, and booleans only, without NUL, tab, or line break characters inside a field.
  - A number goes as `tostring` writes it, so one that wouldn't read back as itself (a large ID, `0.1 + 0.2`) is refused. Send it as a string.
  - An empty array sends a bare kind.
  - Secrets, malformed arrays, and messages longer than 255 bytes are caller bugs, and raise before sending.
- **Nothing is sent or received while the transport is stopped.** Listener removal takes effect during the current delivery. Additions wait until the next delivery. Stopping or restarting the transport inside a listener ends the old delivery.

## Sounds

`ByteTerrace.NewSoundBank(addon, { master, channel, folder? })` plays player-supplied sounds. An addon ships no audio: players drop files named after each sound into its media folder, and numbered copies are variants picked at random. Which files exist comes from `C_UIFileAsset.IsKnownFile`. The bank has these methods:

- `Define`
- `Row`: a setting row naming the files
- `IsOn`
- `Play`, with an optional cooldown
- `WhileOn`: an active rule for a module that only serves some sounds
- `Stop`
- `Test`: the test command, which says why nothing played

## Diagnostics

The built-in `debug` command shows what an addon is doing on a player's machine:

- `debug` toggles debug output (`AddOn:Debug` lines in chat).
- `debug status` shows modules running and stopped (demand modules with their users), events registered, watchers, pending timers, records, queued messages, and the errors `SafeCall` has caught.
- `debug events` shows each registered event with its dispatches, handlers, and unit filter, busiest first, and then publishes and watcher runs.
- `debug work` shows each module's work since load or reset, busiest first: event handler calls, timer callbacks, state-change callbacks (watchers and rules), commands, message deliveries, and deferred actions. `addon` is what the framework ran for no module (built-in commands, starting and stopping modules). While profiling, each line also shows the milliseconds that module's callbacks took.
- `debug rows <text>` shows every row whose name contains the text, runtime rows included, with value and version.
- `debug trace <text>` prints each published change of the matching rows until `debug trace off`. Untraced rows cost nothing.
- `debug cpu` shows the client's addon profiler for this addon, and its memory. The profiler shows time per frame (recent, session, peak, and in encounters), its share of the game's time as Blizzard's AddOn list computes it, and frames over 1 to 100 milliseconds.
- `debug profile` toggles profiling, which is off by default. While it's on, each dispatched callback is timed with `debugprofilestop`, and its time is added to its module, starting from zero. A callback's time includes what it runs synchronously, so a message listener's time also counts in the transport's event handler. While it's off, nothing is timed, and the event dispatcher is exactly the counting one.
- `debug reset` zeroes the counts. The counts are always kept: an integer increment per dispatch and per publish, and a field increment on the work record each handler, watcher, timer, command, and listener holds. That's no allocation, and the tests prove it.

## Secret values

Forever runs the Midnight (12.x) API, where combat values such as health and primary power are *secret*. Addons can display a secret value, but can't compare it, compute with it, or branch on it.

- **Display:** a secret value goes straight to a widget (`StatusBar:SetValue`, `FontString:SetText`) and never enters state.
- **Logic:** logic reads facts that adapters derive from APIs that aren't secret. Where an API can return a secret, the adapter checks `issecretvalue` and keeps the last known value.
- **Blocked actions freeze controller players.** On Forever with the controller UI on, hiding a "blocked from an action" popup makes the controller UI run the same protected call again. If the addon's taint still reaches it, that call is blocked too, and the popups loop until the game freezes. So an addon must never cause a blocked action (the harness fails any test with an unexpected one).
- **Blizzard's settings panel is off limits.** The controller UI remembers the control its focus is on. If that control belongs to an addon (the addon registered it), or addon code opened the panel, its taint is in what the controller UI remembers. Closing the panel reads it, `SetPreferredGamepadInteractTarget` is blocked, and the loop above starts. So addon code never opens the panel, and the settings view sits in it only as a canvas the controller UI ignores.
- **Enforcement:** the check gate and the test harness enforce these rules (see [Development](../README.md#development)).

## Performance

Performance is judged by load-independent counts, not wall-clock time. The tests assert:

- widget calls per event, such as one `SetValue` per power event and no range update per tick
- which events are registered, such as no power events for a class without energy, no usability polling for non-warriors or for a warrior without a living enemy player target, and no target events once every target sound is switched off
- registration churn, such as one unregister when a module with five handlers stops

In code:

- Cache globals as file-level locals.
- Resolve row ids once, and read `state.Values[id]` in hot paths.
- Create no closures or tables inside event handlers.
- Read in a hot handler only what that event can change (the target fact's health handler reads one API). Tests assert API calls per event with `h:CountApiCalls`.
- Test the cheapest disqualifier first on busy events (`CHAT_MSG_ADDON` carries every addon's messages).

The check gate's FRAMEWORK rule keeps addons on the framework. An addon that depends on `ByteTerrace_Core` can't call `C_Timer`'s timers, send addon messages or register prefixes, call `PlaySoundFile`, register settings itself, or handle `CHAT_MSG_ADDON`.

## Add a module

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
        module:OnIncrease("kills.blows", function() ... end) -- needs uses = { "kills" }
    end,
})
```

To finish a new module:

1. List the file in the TOC.
2. Add behavioral tests to `tests/`.
3. Run `node tools/tlk.mjs test --coverage <your test files>`. It lists the module's statements your tests never reach.
4. Run `node tools/tlk.mjs check` and `node tools/tlk.mjs test`.

Register shared messages with `module:Listen` inside `OnEnable`, and bind deferred menu or card actions with `module:Callback`. These methods provide lifetime checks and batching at the boundary, so feature handlers only implement their behavior. For example, a running module can create a menu choice with `root:CreateButton("Mark", module:Callback(Mark, info))`. Stopping the module expires that choice automatically.
