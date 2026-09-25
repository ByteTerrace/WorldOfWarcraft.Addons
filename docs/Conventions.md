# Lua conventions

ByteTerrace addons follow Puck's C# conventions, mapped to Lua. `node tools/tlk.mjs check` enforces what a parser can decide (the NAMING and COMMENT rules); the rest is review.

## Naming

| What | Style | Example |
| --- | --- | --- |
| Constants (file-level values never reassigned, including lookup tables) | PascalCase | `local MaxQueue = 8` |
| File-level state (Puck's private static fields) | PascalCase | `local Queue = {}` |
| Functions, methods and local functions | PascalCase | `local function Pump()`, `function State:Set()` |
| Locals, parameters and loop variables inside functions | camelCase | `local elapsed`, `for _, key in ipairs(keys)` |
| Public members of an object (read by other files) | PascalCase | `addon.State`, `module.Records` |
| Private members of an object (only its own file) | `m_` + camelCase | `self.m_batchDepth` |
| Members of the addon namespace (`ns`), shared across files | PascalCase | `ns.Krew`, `ns.Cards` |
| Child regions stored on a frame (Blizzard's convention) | PascalCase | `button.Label`, `frame.Title` |
| Keys of declarative data (module and row specs, records, messages, options) | camelCase | `{ name = "alerts", kind = "boolean", default = true }` |
| Row, module and command names (they're data, spoken in slash commands) | camelCase rows, PascalCase modules | `Warband.shareSightings` |

- **Aliases keep their source's name.** `local floor = math.floor`, `local C_Timer = C_Timer`, `local SafeCall = ByteTerrace.SafeCall`. Lua's own library stays lowercase.
- **File-level means the chunk's top level,** or a top-level `do` block that only scopes state. A local inside a top-level loop or branch is a local: camelCase.
- **A function is PascalCase wherever it's declared,** including a local declared ahead and given its function later (`local Pump` then `function Pump()`). Metamethods keep Lua's names (`__index`).
- **Public or private is decided by readers.** A member another file reads is public; tests count as readers, but a test asserts behavior rather than reading an object's private state. Static functions on a type (`State.Admits`) are functions: PascalCase.
- **Plain records aren't objects.** Tables without a metatable that a file builds for its own bookkeeping or hands out as opaque tokens (event handles, watchers, bindings, page records) keep camelCase keys, like declarative data. So do the keys the framework derives onto a copied spec (`valueSet`, `lockId`, `store`).
- **A frame is an object.** Its child regions are PascalCase (Blizzard's convention); any other value stored on a frame follows the member rule: `m_` when only its own file reads it (`row.m_entry`).
- **A shared namespace table is aliased under its own name** (`local Warband = ns.Warband`), never a one-letter name. Its lookup-table members are plural nouns (`Labels`, `Icons`), and an export nobody reads is deleted.
- **A constant built by a helper** (`local HonorPatterns = { Pattern(...) }`) sits right after that helper: the one exception to constants-first.
- **Callback parameters are words, not letters:** `function(module)`, `when = function(state)`. A callback may name its parameter `state` even where an outer `state` holds the same object.
- **Client abbreviations stay capitalized inside PascalCase:** `ExecuteSpellID`, `AFKColor`.
- **A public function a file also uses itself** is a documented `local function`, exported in one table at the end (`ns.Krew = { Send = Send, ... }`); the doc comment goes on the local.
- **A rows table built by a loop is a constant,** so it sits with the constants, not beside its module.
- **A table of functions keyed by data** (dispatch keyed by kind or fact type) keeps its data keys: fill it with local PascalCase functions (`Makers = { objective = FromObjective }`) or assign by string (`Generators["math.add"] = function(state) ... end`), never `function Table.dataKey()`.
- **A file-level local holding a framework object is named for what it is:** `local Scholar` for a module handle, `local Overlay` for a view's root frame, not `Module` or `Frame`.
- **`local addonName, ns = ...`** is how every file starts; both names are exempt.
- **No abbreviations** beyond the client's own (`GUID`, `XP`, `UI`) and loop indexes (`i`, `j`).

## Layout

A file reads top to bottom, like a C# type:

1. **The header:** a `--` comment block that states the file's contract. What it's for, the API it exports, and anything a caller would get wrong without being told (it plays the role of a type's XML summary).
2. **Constants,** then **aliases** of client and library functions.
3. **File-level state.**
4. **Private functions,** in the order a reader needs them (helpers before their callers).
5. **The public API** (what the file puts on `ns` or its object).
6. **The module declaration** (`addon:Module(...)`) and its event wiring, last.

Blank lines separate functions and groups; there are no banner dividers. Indentation is four spaces; lines stay under about 120 characters.

## Comments

The rules are Puck's: a comment earns its place by stating what the code can't, and what a reader would get wrong without it. That means an invariant, a unit, a client quirk with its source, or a coupling the code can't check (name the other side).

- **Public functions and methods** get a `---` doc comment: a sentence of behavior, then `---@param` and `---@return` where they aren't obvious. These are the Lua language server's annotations, Lua's XML docs.
- **No** banner dividers (`-- Section ------`), debt markers (TODO, FIXME, HACK, "for now"), dates, history ("used to", "previously"), reviews or conversations, commented-out code, or capitals for emphasis.
- **Annotations the gates read** stay exactly as they are: `-- secret: <why>`, `-- protected: <why>`, `-- global: <why>`.
- Delete a stale comment rather than replacing it with a longer one.

## Formatting

- One statement per line.
- Parentheses only where they change meaning or break up mixed `and` / `or`.
- Early returns over nested conditions.
- Strings in double quotes. Long string building uses `("%s"):format(...)` or `table.concat`, not chains of `..` across lines.
