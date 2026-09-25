# ByteTerrace — World of Warcraft AddOns

AddOns for **World of Warcraft: Forever**, held to the same correctness and performance bar as Puck.

| AddOn | Description |
| --- | --- |
| [ByteTerrace_Core](ByteTerrace_Core) | The shared framework (Lua global `ByteTerrace`): state, commands, input, events, modules. See [architecture](docs/Architecture.md). |
| [TheLanKrewToolKit](TheLanKrewToolKit) | Utilities for The Lan Krew. |
| [ByteTerrace_DevTools](ByteTerrace_DevTools) | Development only: `/btdev dump` records the client's globals for `tlk api-sync`. Never shipped. |

## WoW: Forever target

| | |
| --- | --- |
| Interface | `16001` (game version 1.60.1) |
| TOC file | `<AddOnName>_Camelot.toc`; the client's game type is `camelot` |
| API | Mainline (Midnight 12.x) UI and API, including secret values; Classic Era APIs don't apply |
| AddOns folder | Detected from the install's `.build.info` (the beta installs to `_classic_beta_`) |

Controller work: see [docs/ControllerSupport.md](docs/ControllerSupport.md).

## Development

Requires Node.js 22+. Every operation is a verb on one CLI:

```powershell
npm install                        # once
node tools/tlk.mjs check           # static gates
node tools/tlk.mjs test            # behavioral tests in real Lua 5.1
node tools/tlk.mjs deploy          # check, then junction-link every addon into the Forever install
```

The addons run straight from this repo. The loop:

| You changed | Do this |
| --- | --- |
| Lua in an existing file | `check` and `test`, then `/reload` in game |
| A TOC (new file, SavedVariables, metadata) | `deploy`, then **restart the game client**; `/reload` doesn't re-read TOCs |
| A new addon folder | `deploy`, then restart the game client |
| A new client build | `deploy` flags a stale `## Interface`; refresh the API snapshot (below) |

Turn on Lua error popups in game once: `/console scriptErrors 1`.

### Gates

`check` reports `path:line: RULE message`, and any finding fails it:

| Rule | What it enforces |
| --- | --- |
| PARSE | Every file parses as Lua 5.1. |
| TOC | The TOC lists exactly the files present, dependencies exist, and `## Interface` matches the installed client. |
| GLOBAL | Every global read exists in the client or a dependency. Every write is declared (SavedVariables, `AddonCompartmentFunc`, `SLASH_*`, `## X-Globals`). |
| MEMBER | `Namespace.member` exists in the API snapshot. |
| EVENT | Every event name is real. |
| SECRET | A call to a function that can return a secret value checks `issecretvalue` in its function, or is annotated `-- secret: <why>`. |
| LENGTH / STYLE | 800-line ceiling; LF, final newline, no tabs, no trailing whitespace. |

`test` runs `tests/*.test.lua` in real Lua 5.1 (WebAssembly) against a fake Forever client (`tests/harness`). The fake is strict:

- Functions that Blizzard's docs flag as secret return values that throw on comparison or arithmetic while the player is in combat.
- Only real events and widget methods exist, and reading an undefined global is an error.
- A test fails on any error reported to the client's error handler.
- Every widget call is counted, so tests can assert how much work each event does.

`tests/*.test.mjs` test the tooling itself; the check gate runs over a fixture with one violation per rule.

### API snapshot

`tools/api/forever.json` is what the gates and harness treat as the real API. It holds every documented function, event and widget method with its secret-value flags, plus every global the installed client exposes and the member names of its tables. Its `source` field records where each half came from. Refresh both halves when the client build changes:

1. Refresh the documented API from Blizzard's Forever UI source (the `forever` branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/forever)):

   ```powershell
   node tools/tlk.mjs api-sync --docs <wow-ui-source>/Interface/AddOns/Blizzard_APIDocumentationGenerated
   ```

2. Refresh the globals from your own client:
   1. With ByteTerrace DevTools enabled, type `/btdev dump`, then `/reload`.
   2. Run:

      ```powershell
      node tools/tlk.mjs api-sync --globals "<WoW>/_classic_beta_/WTF/Account/<account>/SavedVariables/ByteTerrace_DevTools.lua"
      ```

## TheLanKrewToolKit

`/tlk` (or `/lankrew`) opens settings. `/tlk help` lists commands. Any setting can be changed with `/tlk set <setting> <value>` or `/tlk toggle <setting>`.

### Fuck-o-meter

A blown-up energy bar stretched across the middle of the screen, shown whenever your power type is energy (rogues, cat-form druids). Toggle it with `/tlk fom`.

### Sounds

Players bind their own sounds to game moments. The addon ships no audio.

| File (`.ogg` or `.mp3`) | Plays when | Test |
| --- | --- | --- |
| `CombatStart` | You enter combat | `/tlk sound start` |
| `ChooseYourDestiny` | You target a living enemy player (at most every 10 s) | `/tlk sound destiny` |
| `FlawlessVictory` | Your enemy-player target dies while targeted, and you started the fight at full health without taking a hit | `/tlk sound flawless` |
| `FinishHim` | Warriors: Execute becomes usable on your enemy-player target (below 20%) | `/tlk sound finish` |

1. Put the files in `TheLanKrewToolKit\Media\`. Each one is optional.
2. Fully restart the game; the client only sees files that existed at launch.

There's a toggle per sound, a volume channel (Master by default), and an option to fade out the combat start sound when combat ends.

"Flawless victory" never compares health during combat, because health is secret there. It reads your health out of combat, and treats any health change on you in combat as a hit. "Finish him" relies on Execute's usability, so it's warrior-only and silent in Defensive Stance.

### Controller light bar and rumble

- **Light bar:** red in combat, yellow when AFK, green otherwise. It's cleared on logout or when the feature is disabled.
- **Rumble:** strong when combat starts, light when it ends.
