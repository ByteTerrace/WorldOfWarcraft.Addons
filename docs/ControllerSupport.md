# WoW: Forever controller support — addon developer reference

Forever is the first WoW flavor with a native controller UI. It's labelled alpha in game, so re-verify against the source when the client build changes. The framework's own controller layer (positional sources, labels, binding maps) is described in [Architecture](Architecture.md#input).

**Sources**

- Blizzard UI source mirror, `forever` branch: <https://github.com/Gethe/wow-ui-source/tree/forever>. The relevant folders are `Interface/AddOns/Blizzard_Gamepad*`, `Blizzard_SharedXML/InputUtil.lua` and `Blizzard_SettingsDefinitions_Shared/Gamepad.lua`.
- The API snapshot in `tools/api/forever.json`, generated from that source's documentation by `tlk api-sync`.

## Blizzard's addons

| Addon | Loads in Forever | Role |
| --- | --- | --- |
| `Blizzard_Gamepad` | Yes (`AllowLoadGameType: camelot`) | Mode switching, radial menu, reticle, input legend, modifiers |
| `Blizzard_GamepadActionBars` | Yes | The gamepad action bars |
| `Blizzard_GamepadTargeting` | Yes | Bumper targeting, target action bars |
| `Blizzard_GamepadSharedUtility` | Yes | Binding stack, prompts, frame focus manager |
| `Blizzard_GamepadSmartNavigation` | Yes | D-pad navigation of UI panels |
| `Blizzard_GamepadSoftCursor` | **No** (mainline only) | — |

None is load-on-demand. They always load and check the interface style at runtime.

## Enabling and detecting controller mode

- **Master switch:** the CVar `InputDeviceInterfaceStyle`, `Mkb` or `Gamepad` (Options > Gamepad). It defaults to gamepad on handhelds.
- **Is the controller UI on?** `InputUtil.IsGamepadUIEnabled()`, which checks `C_InputInterfaceStyle.GetCurrentStyle() == Enum.InputDeviceInterfaceType.Gamepad`.
- **Mode changes:** the event `INPUT_DEVICE_INTERFACE_TRANSITION(newMode, oldMode)`, or Blizzard's registry:

  ```lua
  local key = {}
  InputUtil.RegisterForInterfaceTransitions(key)
  InputUtil.RegisterGamepadInit(key, function() --[[entered gamepad UI]] end)
  InputUtil.RegisterGamepadUninit(key, function() --[[left gamepad UI]] end)
  -- also RegisterGamepadSetup (runs once), RegisterMKBInit/Uninit/Setup
  ```

  An Init registered while that mode is already active fires immediately.
- `IsUsingGamepad()` only means the last input came from the pad; `C_GamePad.IsEnabled()` only means gamepad input is enabled. Blizzard's UI decides the mode by interface style, not by these two.
- **Device events:** `GAME_PAD_CONNECTED`, `GAME_PAD_DISCONNECTED`, `GAME_PAD_ACTIVE_CHANGED(isActive)`, `GAME_PAD_CONFIGS_CHANGED`, `GAME_PAD_POWER_CHANGED(powerLevel)`.
- **Temporary CVars on entering gamepad mode:** Blizzard sets soft targeting (enemy on, friend off, interact range 20, arcs) and camera follow/centering with `C_CVar.SetTempCVar`, and removes them on leaving (`Blizzard_Gamepad/Core.lua:14-41`). Don't permanently override these in gamepad mode.

## Default control scheme

| Input | Does |
| --- | --- |
| D-pad + face buttons | 8 action slots on the active bar (d-pad = slots 1-4, face = 5-8) |
| LT held / RT held / both | Left / Right / Bottom bar; nothing held = Top bar |
| Top bar face buttons | Reserved: Interact, Inspect, Back, Jump |
| LB / RB | Friendly / hostile targeting. Tap = tab-target; hold = targeting action bar (party, assist, markers, last enemy) |
| LB + RB | HUD modifier: shortcuts bar (page, objectives, chat, sheathe, buffs, bags) |
| Shoulder + trigger, same side | Class flyout (stances, pet commands) |
| Start (`OPENRADIAL`) | Radial main menu: 8 segments × 3 pages, right stick selects |
| Select (`TOGGLEUIFOCUS`) | Moves focus between the game and open UI panels |
| L3 / R3 | Autorun / ping |

- Bars have 3 pages (a 4th only for possess), so there are 4 bars × 8 slots per page.
- Stance and possess bars can replace a chosen bar via the `GamepadStanceBarOverride` / `GamepadPossessBarOverride` CVars.
- The modifiers are internally `SHIFT` (left) and `CTRL` (right).

Button key names: `PAD1` (bottom) `PAD2` (right) `PAD3` (left) `PAD4` (top), `PADDUP/DDOWN/DLEFT/DRIGHT`, `PADLSHOULDER`, `PADRSHOULDER`, `PADLTRIGGER`, `PADRTRIGGER`, `PADLSTICK`, `PADRSTICK`, `PADBACK`, `PADFORWARD`, `PADSOCIAL`.

## Extension points (plain Lua, usable by addons)

**React to state:**
- `GamepadMode.RegisterInputModifierStateChangeCallback(cb, owner)` and `RegisterTargetModifierStateChanged(...)`.
- Queries: `IsLeftModifierDown()`, `IsRightModifierDown()`, `IsTargetingModifierDown(flag)`.
- `GamepadMainActionBarFramePageUnit:AddPageChangeCallback(fn)` and `:RegisterActiveActionBarUpdatedCallback(cb, owner)`.
- EventRegistry: `Gamepad.ShowMainMenu`, `Gamepad.HideMainMenu`, `Gamepad.RefreshFrameFocus`, `Gamepad.PreferredGamepadInteractTargetChanged`.

**Button glyphs:**
- Label style comes from `C_GamePad.GetDeviceMappedState(C_GamePad.GetActiveDeviceID()).labelStyle`: `Letters` (Xbox), `Shapes` (PlayStation), `Reverse` (Switch) or `Generic`.
- Get the atlas with `InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture("PAD1")` (e.g. `gamepad-xbox1-...`).
- Templates: `InputIconTextureFrameTemplate` and `InputPromptOneIconWithTextTemplate`. `GamepadMode.AddGamepadIconToButton(button, key)` adds a glyph to a button.

**Make your own panel navigable:**
- Call `GamepadMode.FrameControlsManager:FrameShown(frame)` in OnShow and `:FrameHidden(frame)` in OnHide. Panels opened with `ShowUIPanel` get this automatically.
- SmartNavigation auto-scans child Buttons, EditBoxes and frames with mouse scripts. Tune it with `smartNavigationCanFocus`, `smartNavigationIgnored` and similar fields, and optional `OnSmartNavSelect` / `OnSmartNavClick` / `SmartNavigationCloseHandler` methods.

**Button prompt footer ("(A) Select (B) Back"):**

```lua
local footer = GamepadSharedUtility.CreatePromptedBindingFooter(frame, "MyFooter")
footer:AddStandardSelectPrompt(); footer:AddStandardBackPrompt()
footer:AddPromptedBinding(GamepadSharedUtility.CreatePromptedBinding(GAMEPAD_FACE_TOP, function(down) end, "Sort"))
footer:Finalize(); footer:ShowAndActivateBindings()
```

**Custom input:**
- `GamepadMode.CreateBindingGroup("X")` with `:AddFunctionBinding(key, fn)`, `:AddAxisBinding(GAMEPAD_STICK_RIGHT, fn)` and `:BlockDpad()`, then `GamepadMode.ActivateBindingGroup(g)` / `DeactivateBindingGroup(g)`.
- The whole stack is built on `SetOverrideBinding(UIParent, ...)`, so **only activate groups out of combat**. Never call `ClearOverrideBindings(UIParent)`; it wipes Blizzard's entire gamepad stack.

**Radial menu:**
- `GamepadRadial:ActivateRadial({ header = ..., buttons = { handler, ... } })` shows a custom page.
- A handler is a table with `Attach(segment)`, `Detach()`, `IsEnabled()`, `Trigger()` (return true to close) and `GetLabel()`.
- The main menu's right page has empty slots (3, 4, 6, 7, 8) in `GamepadRadial.mainMenuPages`. Radial entries are insecure: fine for UI actions, but they can't cast or target.

**Raw input on your own frame:**
- `frame:EnableGamePadButton(true)` plus an `OnGamePadButtonDown(self, button)` script. `EnableGamePadStick` plus `OnGamePadStick`.
- Only the frame that took the down event gets the up event, so pass presses on unless you really mean to consume them.

**Hardware:**
- `C_GamePad.SetVibration(type, intensity)` and `StopVibration()`. The client takes `"High"`, `"Low"`, `"LTrigger"` and `"RTrigger"` without an error (probe `gamePad.vibration`), but only `High` and `Low` are felt on the controllers tried so far; the trigger types did nothing. Use `High` and `Low`. A vibration stops by itself after a moment (seen in game with `/btdev rumble High 1`), so `StopVibration` is only needed to cut one short.
- `SetLedColor(color)`, `GetLedColor()` and `ClearLedColor()` (DualSense light bar).
- `GetPowerLevel()`, an `Enum.GamePadPowerLevel`. `GAME_PAD_POWER_CHANGED` fires as the battery drains (Medium and Critical seen, probe `input.events`), and `GAME_PAD_ACTIVE_CHANGED(isActive)` when a controller becomes active; neither fired before the world loaded.
- Blizzard's UI uses none of these, so they're free for addons.

## Restrictions

- The action and targeting buttons are secure. **Safe:** read state, reskin textures. **Taints and breaks in combat:** replacing methods, or calling `SetID`/`SetAttribute`/`Show`/`Hide`/`SetParent` on Blizzard's gamepad buttons and bars.
- **Don't hook the controller UI's managers.** `hooksecurefunc` on `GamepadMode.FrameControlsManager` or `SmartNavigation` methods broke Blizzard's own calls to them: Lua errors "attempt to call a nil value" at `FrameControlsManager.lua:226` (`self:FrameHidden`) and `PromptedBindingFooter.lua:397` (`SmartNavigation:UnregisterCallback`).
- **A blocked action freezes controller players.** Hiding a "blocked from an action" popup makes the controller UI call the protected `SetPreferredGamepadInteractTarget`; if an addon's taint still reaches it, that call is blocked too and the popups loop until the client freezes.
- **Keep controller focus off addon controls in Blizzard's settings panel.** `SmartNavigation` remembers the focused control; an addon's settings control (or a panel addon code opened) carries its taint, so closing the panel reads it and starts that loop. Mark an addon's canvas page ignored (`frame.smartNavigationIgnored = true`, covering every child) and register no setting controls, or keep the settings in the addon's own window (see [Architecture](Architecture.md#secret-values)).
- `SimulateMouseClick/Down/Up/Wheel` and `SetCursorPosition` work from addon code **once per gamepad hardware event**.
- `C_GamePad.SetConfig`, `ApplyConfigs`, `DeleteConfig` and `AddSDLMapping` are restricted.
- Secret values still apply. Your own primary power (energy, mana) is secret, in combat and out; its maximum is not. Combo points are documented as never secret; the `power.comboPoints` probes check that in game.
