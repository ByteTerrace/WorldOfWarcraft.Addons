# WoW: Forever controller support for addon developers

Forever is the first WoW flavor with a native controller UI. It's labeled alpha in game, so re-verify against the source when the client build changes. The framework's own controller layer (positional sources, labels, and binding maps) is described in [Architecture](Architecture.md#input).

## Sources

- Blizzard UI source mirror, `forever` branch: <https://github.com/Gethe/wow-ui-source/tree/forever>. The relevant paths are `Interface/AddOns/Blizzard_Gamepad*`, `Blizzard_SharedXML/InputUtil.lua`, and `Blizzard_SettingsDefinitions_Shared/Gamepad.lua`.
- The API snapshot in `tools/api/forever.json`, generated from that source's documentation by `tlk api-sync`.

## Blizzard's addons

| Addon | Loads in Forever | Role |
| --- | --- | --- |
| `Blizzard_Gamepad` | Yes (`AllowLoadGameType: camelot`) | Mode switching, radial menu, reticle, input legend, and modifiers |
| `Blizzard_GamepadActionBars` | Yes | The controller action bars |
| `Blizzard_GamepadTargeting` | Yes | Bumper targeting and target action bars |
| `Blizzard_GamepadSharedUtility` | Yes | Binding stack, prompts, and frame focus manager |
| `Blizzard_GamepadSmartNavigation` | Yes | D-pad navigation of UI panels |
| `Blizzard_GamepadSoftCursor` | No (mainline only) | — |

None is load-on-demand. They always load, and check the interface style at runtime.

## Enable and detect controller mode

- **Master switch:** the CVar `InputDeviceInterfaceStyle`, set to `Mkb` or `Gamepad` (**Options** > **Gamepad**). It defaults to `Gamepad` on handhelds.
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
- **Not the mode:** `IsUsingGamepad()` only means the last input came from the controller. `C_GamePad.IsEnabled()` only means controller input is enabled. Blizzard's UI decides the mode by interface style, not by these two.
- **Device events:** `GAME_PAD_CONNECTED`, `GAME_PAD_DISCONNECTED`, `GAME_PAD_ACTIVE_CHANGED(isActive)`, `GAME_PAD_CONFIGS_CHANGED`, and `GAME_PAD_POWER_CHANGED(powerLevel)`.
- **Temporary CVars on entering controller mode:** Blizzard sets soft targeting (enemy on, friend off, interact range 20, and arcs) and camera follow and centering with `C_CVar.SetTempCVar`, and removes them on leaving (`Blizzard_Gamepad/Core.lua:14-41`). Don't permanently override these in controller mode.

## Default control scheme

| Input | Does |
| --- | --- |
| D-pad + face buttons | 8 action slots on the active bar (d-pad = slots 1-4, face = 5-8) |
| LT held / RT held / both | Left / Right / Bottom bar. Nothing held = Top bar. |
| Top bar face buttons | Reserved: Interact, Inspect, Back, and Jump |
| LB / RB | Friendly / hostile targeting. Tap to tab-target. Hold for the targeting action bar (party, assist, markers, and last enemy). |
| LB + RB | HUD modifier: shortcuts bar (page, objectives, chat, sheathe, buffs, and bags) |
| Shoulder + trigger, same side | Class flyout (stances, pet commands) |
| Start (`OPENRADIAL`) | Radial main menu: 8 segments × 3 pages, right stick selects |
| Select (`TOGGLEUIFOCUS`) | Moves focus between the game and open UI panels |
| L3 / R3 | Autorun / ping |

- Bars have three pages (a fourth only for possess), so there are four bars of eight slots per page.
- Stance and possess bars can replace a chosen bar through the `GamepadStanceBarOverride` and `GamepadPossessBarOverride` CVars.
- The modifiers are internally `SHIFT` (left) and `CTRL` (right).

The button key names are `PAD1` (bottom), `PAD2` (right), `PAD3` (left), `PAD4` (top), `PADDUP`, `PADDDOWN`, `PADDLEFT`, `PADDRIGHT`, `PADLSHOULDER`, `PADRSHOULDER`, `PADLTRIGGER`, `PADRTRIGGER`, `PADLSTICK`, `PADRSTICK`, `PADBACK`, `PADFORWARD`, and `PADSOCIAL`.

## Extension points

These are plain Lua, and addons can use them.

### React to state

- `GamepadMode.RegisterInputModifierStateChangeCallback(cb, owner)` and `RegisterTargetModifierStateChanged(...)`.
- Queries: `IsLeftModifierDown()`, `IsRightModifierDown()`, and `IsTargetingModifierDown(flag)`.
- `GamepadMainActionBarFramePageUnit:AddPageChangeCallback(fn)` and `:RegisterActiveActionBarUpdatedCallback(cb, owner)`.
- EventRegistry: `Gamepad.ShowMainMenu`, `Gamepad.HideMainMenu`, `Gamepad.RefreshFrameFocus`, and `Gamepad.PreferredGamepadInteractTargetChanged`.

### Show button glyphs

- The label style comes from `C_GamePad.GetDeviceMappedState(C_GamePad.GetActiveDeviceID()).labelStyle`: `Letters` (Xbox), `Shapes` (PlayStation), `Reverse` (Switch), or `Generic`.
- Get the atlas with `InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture("PAD1")` (for example, `gamepad-xbox1-...`).
- Templates: `InputIconTextureFrameTemplate` and `InputPromptOneIconWithTextTemplate`. `GamepadMode.AddGamepadIconToButton(button, key)` adds a glyph to a button.

### Make your own panel navigable

- Call `GamepadMode.FrameControlsManager:FrameShown(frame)` in `OnShow` and `:FrameHidden(frame)` in `OnHide`. Panels opened with `ShowUIPanel` get this automatically.
- `SmartNavigation` scans child buttons, edit boxes, and frames with mouse scripts on its own. Tune it with `smartNavigationCanFocus`, `smartNavigationIgnored`, and similar fields, and with the optional `OnSmartNavSelect`, `OnSmartNavClick`, and `SmartNavigationCloseHandler` methods.

### Add a button prompt footer

A footer shows prompts such as "(A) Select (B) Back":

```lua
local footer = GamepadSharedUtility.CreatePromptedBindingFooter(frame, "MyFooter")
footer:AddStandardSelectPrompt(); footer:AddStandardBackPrompt()
footer:AddPromptedBinding(GamepadSharedUtility.CreatePromptedBinding(GAMEPAD_FACE_TOP, function(down) end, "Sort"))
footer:Finalize(); footer:ShowAndActivateBindings()
```

### Add custom input

1. Create a group with `GamepadMode.CreateBindingGroup("X")`.
2. Add bindings with `:AddFunctionBinding(key, fn)` and `:AddAxisBinding(GAMEPAD_STICK_RIGHT, fn)`, and block the D-pad with `:BlockDpad()`.
3. Activate the group with `GamepadMode.ActivateBindingGroup(g)`, and deactivate it with `DeactivateBindingGroup(g)`.

> [!IMPORTANT]
> The whole stack is built on `SetOverrideBinding(UIParent, ...)`, so activate groups only out of combat. Never call `ClearOverrideBindings(UIParent)`: it wipes Blizzard's entire controller stack.

An addon can bind a single button without Blizzard's binding groups: `SetOverrideBindingClick(ownFrame, false, key, buttonName, mouseButton)` on its own frame, cleared with `ClearOverrideBindings(ownFrame)`. A non-priority override wins over the button's normal binding (Select's `TOGGLEUIFOCUS`, for example), and Blizzard's priority overrides still win over it. ByteTerrace_Core's `Input:Summon` does this out of combat only, and clears it during `PLAYER_REGEN_DISABLED`, while combat lockdown is still off. Whether the client blocks an addon's override binding change in combat isn't documented, so it's never tried.

### Add a radial menu page

- `GamepadRadial:ActivateRadial({ header = ..., buttons = { handler, ... } })` shows a custom page.
- A handler is a table with `Attach(segment)`, `Detach()`, `IsEnabled()`, `Trigger()` (return true to close), and `GetLabel()`.
- The main menu's right page has empty slots (3, 4, 6, 7, and 8) in `GamepadRadial.mainMenuPages`. Radial entries are insecure: fine for UI actions, but they can't cast or target.

### Read raw input on your own frame

- For buttons, call `frame:EnableGamePadButton(true)` and give the frame an `OnGamePadButtonDown(self, button)` script. For sticks, use `EnableGamePadStick` and `OnGamePadStick`.
- Only the frame that took the down event gets the up event.
- A frame that takes controller buttons takes all of them. The client ignores the script's return value, so the frame can't pass a button on to the game (seen in game under the Scholar's riddle), and taking the controller is modal. To bind one button and leave the others to the player, use an override binding instead, as `Input:Summon` does (see [Architecture](Architecture.md#input)).

### Use the hardware

- `C_GamePad.SetVibration(type, intensity)` and `StopVibration()`. The client takes `"High"`, `"Low"`, `"LTrigger"`, and `"RTrigger"` without an error (probe `gamePad.vibration`). Only `High` and `Low` are felt on the controllers tried so far, and the trigger types did nothing. Use `High` and `Low`. A vibration stops by itself after a moment (seen in game with `/btdev rumble High 1`), so `StopVibration` is only needed to cut one short.
- `SetLedColor(color)`, `GetLedColor()`, and `ClearLedColor()` (DualSense light bar).
- `GetPowerLevel()` returns an `Enum.GamePadPowerLevel`. `GAME_PAD_POWER_CHANGED` fires as the battery drains (Medium and Critical seen, probe `input.events`), and `GAME_PAD_ACTIVE_CHANGED(isActive)` fires when a controller becomes active. Neither fired before the world loaded.
- Blizzard's UI uses none of these, so they're free for addons.

## Restrictions

> [!WARNING]
> A blocked action freezes controller players. Hiding a "blocked from an action" popup makes the controller UI call the protected `SetPreferredGamepadInteractTarget`. If an addon's taint still reaches it, that call is blocked too, and the popups loop until the game freezes.

- **Keep controller focus off addon controls in Blizzard's settings panel.** `SmartNavigation` remembers the focused control. An addon's settings control (or a panel addon code opened) carries its taint, so closing the panel reads it and starts that loop. Mark an addon's canvas page ignored (`frame.smartNavigationIgnored = true`, covering every child) and register no setting controls, or keep the settings in the addon's own window (see [Architecture](Architecture.md#secret-values)).
- **Leave the secure buttons alone.** The action and targeting buttons are secure. Reading their state and reskinning their textures is safe. Replacing their methods, or calling `SetID`, `SetAttribute`, `Show`, `Hide`, or `SetParent` on Blizzard's controller buttons and bars, taints them and breaks them in combat.
- **Don't hook the controller UI's managers.** `hooksecurefunc` on `GamepadMode.FrameControlsManager` or `SmartNavigation` methods broke Blizzard's own calls to them, with the Lua error "attempt to call a nil value" at `FrameControlsManager.lua:226` (`self:FrameHidden`) and `PromptedBindingFooter.lua:397` (`SmartNavigation:UnregisterCallback`).
- `SimulateMouseClick`, `SimulateMouseDown`, `SimulateMouseUp`, `SimulateMouseWheel`, and `SetCursorPosition` work from addon code once per controller hardware event.
- `C_GamePad.SetConfig`, `ApplyConfigs`, `DeleteConfig`, and `AddSDLMapping` are restricted.
- Secret values still apply. Your own primary power (energy, mana) is secret, in combat and out. Its maximum isn't. Combo points are documented as never secret, and the `power.comboPoints` probes check that in game.
