# Lua conventions

ByteTerrace addons follow Puck's C# conventions, mapped to Lua. `node tools/tlk.mjs check` enforces what a parser can decide (the NAMING, COMMENT, FORMAT and ORDER rules); the rest is review.

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

- **Aliases keep their source's name.** `local floor = math.floor`, `local C_Spell = C_Spell`, `local SafeCall = ByteTerrace.SafeCall`. Lua's own library stays lowercase.
- **File-level means the chunk's top level,** or a top-level `do` block that only scopes state. A local inside a top-level loop or branch is a local: camelCase.
- **A function is PascalCase wherever it's declared,** including a local declared ahead and given its function later (`local Pump` then `function Pump()`). Metamethods keep Lua's names (`__index`).
- **Public or private is decided by readers.** A member another file reads is public; tests count as readers, but a test asserts behavior rather than reading an object's private state. Static functions on a type (`State.Admits`) are functions: PascalCase.
- **Plain records aren't objects.** Tables without a metatable that a file builds for its own bookkeeping or hands out as opaque tokens (event handles, watchers, bindings, page records) keep camelCase keys, like declarative data. So do the keys the framework derives onto a copied spec (`valueSet`, `lockId`, `store`).
- **A frame is an object.** Its child regions are PascalCase (Blizzard's convention); any other value stored on a frame follows the member rule: `m_` when only its own file reads it (`row.m_entry`).
- **A shared namespace table is aliased under its own name** (`local Warband = ns.Warband`), never a one-letter name. Its lookup-table members are plural nouns (`Labels`, `Icons`), and an export nobody reads is deleted.
- **A constant built by a helper** (`local HonorPatterns = { Pattern(...) }`) sits right after that helper: the one exception to constants-first.
- **Callback parameters are words, not letters:** `function(module)`, `when = function(state)`. A callback may name its parameter `state` even where an outer `state` holds the same object.
- **Client abbreviations stay capitalized inside PascalCase:** `ExecuteSpellID`, `AFKColor`.
- **A public function a file also uses itself** is a documented `local function`, exported in one table at the end (`ns.Puzzles = { Grades = Grades, Generate = Generate, Kit = Kit }`); the doc comment goes on the local.
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

Blank lines separate functions and groups; there are no banner dividers. Within a group, `format` alphabetizes. Indentation is four spaces.

## Comments

The rules are Puck's: a comment earns its place by stating what the code can't, and what a reader would get wrong without it. That means an invariant, a unit, a client quirk with its source, or a coupling the code can't check (name the other side).

- **Public functions and methods** get a `---` doc comment: a sentence of behavior, then `---@param` and `---@return` where they aren't obvious. These are the Lua language server's annotations, Lua's XML docs.
- **Comments are sentences:** capitalized (or starting with code: `` `level` ``, `ns.Krew`), ending with a period, on their own lines above what they describe. A label that only names the value below it is deleted; a fragment becomes a sentence that says what the code can't. `check`'s COMMENT rule enforces the capital and the period.
- **No** banner dividers (`-- Section ------`), debt markers (TODO, FIXME, HACK, "for now"), dates, history ("used to", "previously"), reviews or conversations, commented-out code, or capitals for emphasis.
- **Annotations the gates read** stay exactly as they are: `-- secret: <why>`, `-- protected: <why>`, `-- global: <why>`.
- Delete a stale comment rather than replacing it with a longer one.

## Formatting

`node tools/tlk.mjs format` writes the one canonical form, and `check`'s FORMAT rule fails a file it would change. Its passes are Puck's `puck format` passes, mapped to Lua, plus the habits Puck's own code keeps that its formatter doesn't write (blank lines around blocks and before a `return`, no trailing comments, comments filled toward 120 columns, members in alphabetical order):

| Pass | Rewrite |
| --- | --- |
| `trailing-comments` | A comment after code moves onto its own line above that code, at the line's indentation. |
| `paren-clarity` | Every binary and logical expression is parenthesized for explicit precedence: `local visible = (UnitPowerType("player") == Energy)`, `if (a == nil) or (a == "ENERGY") then`. It stays bare where something already delimits it: its own parentheses, an `if`, `elseif`, `while` or `until` condition, a call's arguments, an index's brackets and a numeric `for`'s bounds. An operand of the same `and`, `or` or `..` stays bare, so `a and b and c` is one flat group. Unary operators are left alone. |
| `init-order` | A table constructor whose every field is `name = value` is sorted alphabetically by name, ignoring case (`commands`, `label`, `OnEnable`), when no value calls anything. In a constructor with a field to a line, the comment lines directly above a field move with it. Across lines, fields that each had a line keep one, and packed fields are packed again up to 120 columns. |
| `trailing-comma` | A multi-line table constructor's last field ends with a comma. |
| `split-locals` | A `local` that declares several names gets a line per name (`local floor = math.floor`, then `local max = math.max`), when it gives each name its own value or none, and no value reads a name declared before it in the same statement. A call that returns several values (`local h, addon, ns = LoadKid()`) and `local addonName, ns = ...` stay as they are. |
| `export-order` | A run of file-level `Table.member = value` lines (values are names or literals) is sorted by target, each line's own pairs first. |
| `local-order` | A run of file-level `local` statements on consecutive lines (no values that call anything or hold a function) is sorted by name; the comment lines directly above a statement are its own and move with it. A statement never moves past one whose value reads it, or past one that it read as a global before. A blank line or a call ends the run, so blank lines are how a file keeps groups apart. |
| `function-order` | A run of file-level functions (local functions, locals holding one, and functions stored in tables), each with its comment lines, is sorted: local ones first, then the rest, each alphabetically. A function never moves past one whose name it reads, so a helper stays above its callers. Any other statement, or a comment with a blank line after it, ends the run. |
| `decl-spacing` | One blank line between a run of `local` statements and the statement after it, unless a comment leads that statement. |
| `block-spacing` | One blank line before and after a block (`if`, a loop, `do`, a function) or a statement spanning lines, and before a `return` or `break`, between statements of one block, above the later statement's comment lines. |
| `member-spacing` | One blank line between a file-level function and its neighbors, above the function's leading comment. |
| `comment-fill` | A paragraph of full-line comments (plain prose: no lists, aligned columns or annotations) fills its lines up to 120 columns. A line starting in lower case after one that ends a sentence is a note of its own. |
| `string-merge` | `"a" .. "b"` of two double-quoted literals on one line becomes one literal. |
| `blank-lines` | No more than one blank line in a row, and none at the start of a file. |

Like Puck's, the reordering passes move nothing a comment could be misattached by, the result must parse, and running them again changes nothing. `format --check` writes nothing; `--only <pass,...>` runs some of them.

A constructor `init-order` won't sort (a value calls something, or a comment sits between packed fields) is check's ORDER finding: sort it by hand, or say why its order matters with `-- order: <why>` on its line or alone above it (a table grouped under section comments, say). `format --sort-calls` sorts the calling ones too; a call can change what another field reads, so its diff is for review.

Review covers the rest:

- One statement per line.
- Early returns over nested conditions.
- Strings in double quotes. Long string building uses `("%s"):format(...)` or `table.concat`, not chains of `..` across lines.
- Lines stay under about 120 characters.
