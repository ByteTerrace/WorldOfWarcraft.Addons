-- Keyboard, controller state, mouse coverage, and random numbers of the fake client (see wow.lua).
--
--   * h:Key(key, down) dispatches OnKeyDown/OnKeyUp to visible, keyboard-enabled frames, topmost
--     first (strata, then level, then newest). A frame that doesn't propagate keyboard input
--     (the default) consumes the key. Unconsumed keys land in h.propagatedKeys.
--   * h:WorldClickBlocked() is true while a visible, mouse-enabled frame covers the screen.
--   * h:Drag(frame, dx, dy [, button]) drags a frame with the mouse (see Harness:Drag).
--   * h:MouseWheel(frame, delta) turns the mouse wheel over a frame (see Harness:MouseWheel).
--   * h:SeedRandom(n) makes the env's math.random (and random) deterministic.
--   * h:GamePadMappedState(id) supplies the C_GamePad fake's connected controller state.
--   * h:ConnectController(labelStyle) and h:DisconnectController() plug a controller in (Letters by default) and
--     pull it out: h.labelStyle changes, then [E] GAME_PAD_CONNECTED or GAME_PAD_DISCONNECTED fires with no payload
--     (input.events).
--   * h:OpenRadial() and h:CloseRadial() open and close the controller UI's radial main menu (Start), firing
--     EventRegistry's Gamepad.ShowMainMenu and Gamepad.HideMainMenu.
--
-- The controller UI's glyphs and callbacks (Blizzard_SharedXML InputIcons, Blizzard_SharedXMLBase CallbackRegistry and
-- TextureUtil, forever branch):
--   * [D] InputIconTextureSetUtility.GetActiveInputIconButtonTextures(key) returns a button's five state atlases for the
--     active family (labelStyle, Generic without a controller), Normal first, and nothing for a key the client doesn't
--     map (PADSOCIAL, a modified key). [G] The atlas names follow "gamepad-<family>-<key>-<state>" here.
--   * [D] CreateAtlasMarkup(atlas, width, height, x, y) is "|A:atlas:height:width:x:y|a".
--   * [D] EventRegistry:RegisterCallback(event, fn, owner) calls fn(owner, ...) on each trigger, and
--     UnregisterCallback(event, owner) ends it. [D] The trigger calls it behind securecallfunction, so an error is the
--     callback's own.

-- Whether a region covers the whole screen: it is UIParent, or it is anchored (SetAllPoints, or two opposite corners on
-- the same corners, flush or outside) to a region that does.
local function CoversScreen(h, region, depth)
    if type(region) == "string" then
        region = rawget(h.env, region)
    end

    local s = ((type(region) == "table") and Harness.State(region))

    if not s or (depth > 20) then
        return false
    end

    if region == rawget(h.env, "UIParent") then
        return true
    end

    if s.allPoints then
        return CoversScreen(h, s.allPoints, depth + 1)
    end

    local byPoint = {}

    for _, p in ipairs(s.points) do
        byPoint[p.point] = p
    end

    -- An offset whose signs match sx and sy keeps the corner flush or pushes it outward.
    local function Corner(point, sx, sy)
        local p = byPoint[point]

        if p and (p.relativePoint == point) and ((p.x * sx) >= 0) and ((p.y * sy) >= 0) then
            return (p.relativeTo or s.parent)
        end
    end

    for _, pair in ipairs({ { "TOPLEFT", -1, 1, "BOTTOMRIGHT", 1, -1 }, { "TOPRIGHT", 1, 1, "BOTTOMLEFT", -1, -1 } }) do
        local a = Corner(pair[1], pair[2], pair[3])
        local b = Corner(pair[4], pair[5], pair[6])

        if (a ~= nil) and (a == b) and CoversScreen(h, a, depth + 1) then
            return true
        end
    end

    return false
end

-- Plugs a controller in (see the header).
function Harness:ConnectController(labelStyle)
    self.labelStyle = (labelStyle or "Letters")
    self:Fire("GAME_PAD_CONNECTED")
end

-- Pulls the controller out (see the header).
function Harness:DisconnectController()
    self.labelStyle = nil
    self:Fire("GAME_PAD_DISCONNECTED")
end

-- Drags a frame with the mouse button (default "LeftButton") by dx, dy. Only a visible, mouse-enabled frame that
-- registered the button with RegisterForDrag starts a drag ([D] RegisterForDrag's page: dragging needs EnableMouse,
-- since OnDragStart doesn't imply it). The press runs OnMouseDown(frame, button) ([G]), then OnDragStart(frame,
-- button); if the frame is then moving (StartMoving), it follows the mouse: each anchor shifts by dx, dy (widgets.lua's
-- header says why). The release runs OnDragStop(frame). OnMouseUp and OnClick don't run ([D] "Blocks OnMouseUp and
-- OnClick when dragging with a registered button"). A frame the scripts leave moving keeps following the mouse until
-- StopMovingOrSizing, so a later h:Drag moves it again. Returns whether the drag started.
function Harness:Drag(frame, dx, dy, button)
    button = (button or "LeftButton")
    local s = Harness.State(frame)

    if not self:IsVisibleWidget(frame) or not s.mouseEnabled or not (s.dragButtons and s.dragButtons[button]) then
        return false
    end

    if s.scripts.OnMouseDown then self:Protect(s.scripts.OnMouseDown, frame, button) end

    if s.scripts.OnDragStart then self:Protect(s.scripts.OnDragStart, frame, button) end

    if s.moving then
        -- The anchors now carry offsets, so the frame no longer fills its SetAllPoints target.
        s.allPoints = nil

        for _, p in ipairs(s.points) do
            p.x, p.y = (p.x + (dx or 0)), (p.y + (dy or 0))
        end
    end

    if s.scripts.OnDragStop then self:Protect(s.scripts.OnDragStop, frame) end

    return true
end

-- Drags a slider's thumb with the mouse to where value would sit. Only a visible slider takes it. [G] With
-- SetObeyStepOnDrag(true), the thumb stops on the nearest step from the minimum (SetValueStep). The value stays within
-- the bounds, and OnValueChanged runs with userInput true. Returns whether the slider took the drag.
function Harness:DragSliderThumb(slider, value)
    local s = Harness.State(slider)

    if not self:IsVisibleWidget(slider) then
        return false
    end

    local step = s.valueStep

    if s.obeyStepOnDrag and step and (step > 0) then
        local low = (s.min or 0)

        value = (low + (math.floor(((value - low) / step) + 0.5) * step))
    end

    Harness.SetSliderValue(s, slider, value, true)

    return true
end

--- The connected controller's mapped state, or nil for an unavailable device.
function Harness:GamePadMappedState(id)
    if (id ~= 1) or not self.labelStyle then
        return nil
    end

    -- [E] gamePad.device's fields; [D] GamePadMappedState and GamePadStick in GamePadDocumentation.lua (forever). [G] A
    -- neutral pad with six axes and sixteen buttons.
    local buttons = {}
    local axes = {}
    local sticks = {}

    for i = 1, 16 do buttons[i] = false end

    for i = 1, 6 do axes[i] = 0 end

    for i = 1, 2 do sticks[i] = { len = 0, x = 0, y = 0 } end

    return {
        axes = axes, axisCount = #axes, buttonCount = #buttons, buttons = buttons, labelStyle = self.labelStyle,
        name = "Test Controller", stickCount = #sticks, sticks = sticks,
    }
end

-- Presses (down = true) or releases a keyboard key like "W", "1", "ESCAPE", or "ENTER". Visible frames (every ancestor
-- shown) with the keyboard enabled get it topmost first: higher frame strata, then higher frame level, then newest.
-- Each runs its OnKeyDown (or OnKeyUp) script if it has one. One that doesn't propagate keyboard input
-- (SetPropagateKeyboardInput(false), the default) consumes the key, read after its script runs, so a script may decide
-- per key. One that propagates passes it on. A key no frame consumes goes to the game's bindings and is recorded in
-- h.propagatedKeys. Returns whether a frame consumed it.
local Families = { Generic = "xbox1", Letters = "xbox1", Reverse = "switch-128x", Shapes = "ps" }

local GlyphKeys = {
    PAD1 = true, PAD2 = true, PAD3 = true, PAD4 = true, PADBACK = true, PADDDOWN = true, PADDLEFT = true,
    PADDRIGHT = true, PADDUP = true, PADFORWARD = true, PADLSHOULDER = true, PADLSTICK = true, PADLTRIGGER = true,
    PADRSHOULDER = true, PADRSTICK = true, PADRTRIGGER = true,
}

-- Fires an EventRegistry event: every callback, in registration order, each isolated like securecallfunction.
local function Trigger(h, event, ...)
    for _, entry in ipairs(h.registry[event] or {}) do
        local ok, err = pcall(entry.fn, entry.owner, ...)

        if not ok then
            h.errors[#h.errors + 1] = err
        end
    end
end

function Harness:CloseRadial()
    Trigger(self, "Gamepad.HideMainMenu")
end

-- The controller UI's glyph and callback fakes, merged into the env (env.lua).
function Harness:ControllerUIFakes()
    local h = self

    -- A new UI (a /reload) starts with no callbacks, as the client's does.
    h.registry = {}

    return {
        CreateAtlasMarkup = function(atlas, width, height, x, y)
            return ("|A:%s:%d:%d:%d:%d|a"):format(atlas, (height or 0), (width or 0), (x or 0), (y or 0))
        end,
        EventRegistry = {
            RegisterCallback = function(_, event, fn, owner)
                h.registry[event] = (h.registry[event] or {})
                table.insert(h.registry[event], { fn = fn, owner = owner })
            end,
            UnregisterCallback = function(_, event, owner)
                local kept = {}

                for _, entry in ipairs(h.registry[event] or {}) do
                    if entry.owner ~= owner then
                        kept[#kept + 1] = entry
                    end
                end

                h.registry[event] = kept
            end,
        },
        InputIconTextureSetUtility = {
            GetActiveInputIconButtonTextures = function(key)
                if not GlyphKeys[key] then
                    return nil
                end

                local base = ("gamepad-%s-%s-"):format(Families[h.labelStyle or "Generic"] or Families.Generic, key:lower())

                return { (base .. "normal"), (base .. "hover"), (base .. "pressed"), (base .. "active"), (base .. "disabled") }
            end,
        },
    }
end

function Harness:Key(key, down)
    local script = ((down and "OnKeyDown") or "OnKeyUp")
    local receivers = {}

    for i, frame in ipairs(self.frames) do
        if Harness.State(frame).keyboardEnabled and self:IsVisibleWidget(frame) then
            receivers[#receivers + 1] = { frame = frame, index = i, level = self:FrameLevel(frame), strata = self:FrameStrataIndex(frame) }
        end
    end

    table.sort(receivers, function(a, b)
        if a.strata ~= b.strata then return (a.strata > b.strata) end

        if a.level ~= b.level then return (a.level > b.level) end

        return (a.index > b.index)
    end)

    for _, receiver in ipairs(receivers) do
        local frame = receiver.frame
        local state = Harness.State(frame)

        -- An earlier receiver's script may disable this frame's keyboard input or hide it.
        if state.keyboardEnabled and self:IsVisibleWidget(frame) then
            local handler = state.scripts[script]

            if handler then
                self:Protect(handler, frame, key)
            end

            if not state.propagateKeyboard then
                return true
            end
        end
    end

    self.propagatedKeys[#self.propagatedKeys + 1] = key

    return false
end

-- Turns the mouse wheel over a frame: delta 1 is a notch up, -1 a notch down ([D] OnMouseWheel's delta). A visible
-- frame with the mouse wheel enabled runs its OnMouseWheel(frame, delta). [G] The wheel over any other frame does
-- nothing here (the client offers it to the frames beneath). Returns whether the frame took it.
function Harness:MouseWheel(frame, delta)
    local s = Harness.State(frame)

    if not (s.mouseWheel and self:IsVisibleWidget(frame)) then
        return false
    end

    if s.scripts.OnMouseWheel then
        self:Protect(s.scripts.OnMouseWheel, frame, delta)
    end

    return true
end

-- The generator's next value in [0, 1).
function Harness:NextRandom()
    self.rng = (((1664525 * self.rng) + 1013904223) % 4294967296)

    return (self.rng / 4294967296)
end

-- Opens the radial main menu, as Start does with the controller UI on.
function Harness:OpenRadial()
    Trigger(self, "Gamepad.ShowMainMenu")
end

-- Lua 5.1's math.random contract: () -> [0, 1), (m) -> integer in [1, m], (m, n) -> [m, n].
function Harness:Random(...)
    local count = select("#", ...)

    if not self.rng then
        return math.random(...)
    end

    if count > 2 then
        error("wrong number of arguments", 3)
    end

    local r = self:NextRandom()

    if count == 0 then
        return r
    end

    local m, n = ...

    if count == 1 then
        m, n = 1, m
    end

    m, n = math.floor(m), math.floor(n)

    if m > n then
        error(("bad argument #%d to 'random' (interval is empty)"):format(count), 3)
    end

    return (m + math.floor(r * ((n - m) + 1)))
end

-- Makes the env's math.random (and random) deterministic from seed n: the harness's own linear congruential generator
-- (Numerical Recipes' 32-bit constants), independent of Lua's global math.random state, so the same seed gives the same
-- sequence in every test. Before the first SeedRandom, math.random is Lua's own. An addon's local copy of math.random
-- follows too. The seed is stirred by two steps first: a raw seed's first value hardly moves from one seed to the next
-- (seeds 1 to 20 all start near 0.24), so a loop over seeds would see one first draw.
function Harness:SeedRandom(n)
    assert(type(n) == "number", "SeedRandom: the seed must be a number")
    self.rng = (math.floor(n) % 4294967296)
    self:NextRandom()
    self:NextRandom()
end

-- True when a visible, mouse-enabled frame covers the screen, so a click can't reach the world. A simple model:
-- covering is SetAllPoints(UIParent) or corner anchors to it (see CoversScreen). A frame sized to the screen with
-- SetSize, alpha, strata, and hit rect insets aren't considered.
function Harness:WorldClickBlocked()
    for _, frame in ipairs(self.frames) do
        local state = Harness.State(frame)

        if state.mouseEnabled and self:IsVisibleWidget(frame) and CoversScreen(self, frame, 0) then
            return true
        end
    end

    return false
end
