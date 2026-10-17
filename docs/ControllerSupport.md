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
- Get the atlases with `InputIconTextureSetUtility.GetActiveInputIconButtonTextures("PAD1")`: five states for the active family, Normal first (for example, `gamepad-xbox1-buttona-normal`), or nil for a key it doesn't map (`PADSOCIAL`, or a modified key like `SHIFT-PAD1`). Don't use `GetNormalActiveInputIconButtonTexture`: it indexes that nil and errors (`Blizzard_SharedXML/Shared/InputIcons/InputIconTexture.lua`).
- Without a controller, or in the mouse and keyboard style, the family is Generic, which is the Xbox art.
- `CreateAtlasMarkup(atlas, width, height)` makes the inline text markup. ByteTerrace_Core's `Input.Glyph(source, size)` does both, and `Input.Prompt(source, size)` falls back to the printed name.
- These lookups only read the controller UI's tables, so they taint nothing. Templates: `InputIconTextureFrameTemplate` and `InputPromptOneIconWithTextTemplate`. `GamepadMode.AddGamepadIconToButton(button, key)` adds a glyph to a button, but it replaces the button's `OnEnable` and `OnDisable` scripts, so use it only on your own buttons.

### Make your own panel navigable

- Call `GamepadMode.FrameControlsManager:FrameShown(frame)` in `OnShow` and `:FrameHidden(frame)` in `OnHide`. Panels opened with `ShowUIPanel` get this automatically.
- `SmartNavigation` scans child buttons, edit boxes, and frames with mouse scripts on its own. Tune it with `smartNavigationCanFocus`, `smartNavigationIgnored`, and similar fields, and with the optional `OnSmartNavSelect`, `OnSmartNavClick`, and `SmartNavigationCloseHandler` methods.

### Don't use Blizzard's binding groups or prompt footers from addon code

> [!WARNING]
> Blizzard's binding groups (`GamepadMode.CreateBindingGroup`, `ActivateBindingGroup`, `DeactivateBindingGroup`, and `AddFunctionBinding`) and prompt footers with binding functions (`GamepadSharedUtility.CreatePromptedBindingFooter` and `CreatePromptedBinding`) lead to the protected `SetPreferredGamepadInteractTarget`, which blocks from addon code and can loop the blocked-action popups until the game freezes.

The path: activating or deactivating a group changes the binding stack, which calls its listeners directly (`InputBindingManager.lua`, `CheckCoreBindingActive`). One of them, the main action bar's focus state (`Blizzard_GamepadActionBars/MainActionBarFrame.lua`), calls `UpdateInteractIcons`, the only caller of `SetPreferredGamepadInteractTarget`. Addon code that writes the stack also leaves tainted slots that Blizzard reads later, for example on a target change. A footer with a binding function builds such a group. Blizzard uses these everywhere, but only from its own secure code. Never call `ClearOverrideBindings(UIParent)` either: it wipes Blizzard's entire controller stack.

An addon can bind a single button without Blizzard's binding groups: `SetOverrideBindingClick(ownFrame, false, key, buttonName, mouseButton)` on its own frame, cleared with `ClearOverrideBindings(ownFrame)`. A non-priority override wins over the button's normal binding (Select's `TOGGLEUIFOCUS`, for example), and Blizzard's priority overrides still win over it. ByteTerrace_Core's `Input:Summon` does this out of combat only, and clears it during `PLAYER_REGEN_DISABLED`, while combat lockdown is still off. Whether the client blocks an addon's override binding change in combat isn't documented, so it's never tried.

### Don't add radial menu entries

The radial main menu (Start) has no supported way to add an entry. Writing into `GamepadRadial.mainMenuPages` or `segmentOptions`, or calling `GamepadRadial:ActivateRadial` with a custom page, taints the radial's segment handlers. Every later close then runs tainted, through the radial's binding group, to `SetPreferredGamepadInteractTarget`. That holds even for a close with B or Start (`Blizzard_Gamepad/UI/Radials/GamepadRadial.lua`, `OnHide`).

### Hear the radial menu

The radial fires EventRegistry's `Gamepad.ShowMainMenu` last as it shows, and `Gamepad.HideMainMenu` as it hides, with no arguments. EventRegistry calls each callback through `securecallfunction` (`Blizzard_SharedXMLBase/CallbackRegistry.lua`), so an addon's callback can't taint the radial. Keep the callback to the addon's own frames and state: hiding or reshaping the radial from it would run the radial's own code from addon code. Scholar's riddle steps aside into its pill this way, as it does for Esc.

### Read raw input on your own frame

- For buttons, call `frame:EnableGamePadButton(true)` and give the frame an `OnGamePadButtonDown(self, button)` script. For sticks, use `EnableGamePadStick` and `OnGamePadStick`.
- Only the frame that took the down event gets the up event.
- A frame that takes controller buttons takes all of them. The client ignores the script's return value, so the frame can't pass a button on to the game (seen in game under the Scholar's riddle), and taking the controller is modal. To bind one button and leave the others to the player, use an override binding instead, as `Input:Summon` does (see [Architecture](Architecture.md#input)).

### Use the hardware

- `C_GamePad.SetVibration(type, intensity)` and `StopVibration()`. The client takes `"High"`, `"Low"`, `"LTrigger"`, and `"RTrigger"` without an error (probe `gamePad.vibration`). Only `High` and `Low` are felt on the controllers tried so far, and the trigger types did nothing. Use `High` and `Low`. A vibration stops by itself after a moment (seen in game with `/btdev rumble High 1`), so `StopVibration` is only needed to cut one short.
- `SetLedColor(color)`, `GetLedColor()`, and `ClearLedColor()` (DualSense light bar).
- Whether a controller is connected: Core's `controller` fact (`controller.connected`), from `GetDeviceMappedState(GetActiveDeviceID())`, which is nil without one. `GAME_PAD_CONNECTED` and `GAME_PAD_DISCONNECTED` fire with no payload (probe `input.events`).
- `GetPowerLevel()` returns an `Enum.GamePadPowerLevel`. `GAME_PAD_POWER_CHANGED` fires as the battery drains (Medium and Critical seen, probe `input.events`), and `GAME_PAD_ACTIVE_CHANGED(isActive)` fires when a controller becomes active. Neither fired before the world loaded.
- Blizzard's UI uses none of these, so they're free for addons.

## Restrictions

> [!WARNING]
> A blocked action freezes controller players. Hiding a "blocked from an action" popup makes the controller UI call the protected `SetPreferredGamepadInteractTarget`. If an addon's taint still reaches it, that call is blocked too, and the popups loop until the game freezes.

- **Keep controller focus off every addon frame.** `SmartNavigation` remembers the focused control. An addon's control carries its taint, so a later read starts that loop, whether the control is a settings page in Blizzard's panel or the addon's own window. Mark each top-level addon frame ignored (`frame.smartNavigationIgnored = true`, which covers every child), and take its controller input through override bindings on the addon's own button (`Input:Summon`). Register no setting controls in Blizzard's panel either, and keep the settings in the addon's own window (see [Architecture](Architecture.md#secret-values)).
- **Add nothing to Blizzard's menus in the controller interface style.** As a menu shows, `FrameControlsManager:FrameShown` activates a binding group for it (`Blizzard_Menu/Menu.lua`, `MenuProxy.OnShow`). When the menu holds an addon's entries (`Menu.ModifyMenu`), or addon code opened it, that runs tainted. Its protected `SetOverrideBindingClick` calls are blocked, and the half-built binding set stays in the binding stack. From then on, every read of the stack is tainted, including `UpdateInteractIcons` on each target change, which calls `SetPreferredGamepadInteractTarget`. The popups repeat until the game freezes. That's the path `taint.log` recorded when a target frame's menu with Warband's entries opened in a fight. `ByteTerrace.Input.IsControllerUI()` says when the style is on: add the entries only when it isn't, and give controller players another way, such as a slash command.
- **Name what was blocked.** ByteTerrace_Core says in chat, once per function, any action the client blocks that names a ByteTerrace addon (`ADDON_ACTION_BLOCKED` and `ADDON_ACTION_FORBIDDEN`), and `/tlk debug status` lists them. For the full path, turn on `/console taintLog 1` and read `Logs/taint.log`. Choose **Disable** on the popup, not **Ignore**: an ignored block can repeat until the game freezes.
- **Leave the secure buttons alone.** The action and targeting buttons are secure. Reading their state and reskinning their textures is safe. Replacing their methods, or calling `SetID`, `SetAttribute`, `Show`, `Hide`, or `SetParent` on Blizzard's controller buttons and bars, taints them and breaks them in combat.
- **Don't hook the controller UI's managers.** `hooksecurefunc` on `GamepadMode.FrameControlsManager` or `SmartNavigation` methods broke Blizzard's own calls to them, with the Lua error "attempt to call a nil value" at `FrameControlsManager.lua:226` (`self:FrameHidden`) and `PromptedBindingFooter.lua:397` (`SmartNavigation:UnregisterCallback`).
- `SimulateMouseClick`, `SimulateMouseDown`, `SimulateMouseUp`, `SimulateMouseWheel`, and `SetCursorPosition` work from addon code once per controller hardware event.
- `C_GamePad.SetConfig`, `ApplyConfigs`, `DeleteConfig`, and `AddSDLMapping` are restricted.
- Secret values still apply. Your own primary power (energy, mana) is secret, in combat and out. Its maximum isn't. Combo points are documented as never secret, and the `power.comboPoints` probes check that in game.
