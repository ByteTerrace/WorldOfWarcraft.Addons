-- Keyboard, mouse coverage and random numbers of the fake client (see wow.lua for the rest).
--
--   * h:Key(key, down) dispatches OnKeyDown/OnKeyUp to visible, keyboard-enabled frames, topmost
--     first (strata, then level, then newest). A frame that doesn't propagate keyboard input
--     (the default) consumes the key; unconsumed keys land in h.propagatedKeys.
--   * h:WorldClickBlocked() is true while a visible, mouse-enabled frame covers the screen.
--   * h:Drag(frame, dx, dy [, button]) drags a frame with the mouse (see Harness:Drag).
--   * h:SeedRandom(n) makes the env's math.random (and random) deterministic.

-- Keyboard -----------------------------------------------------------------

-- Presses (down = true) or releases a keyboard key like "W", "1", "ESCAPE" or "ENTER". Visible
-- frames (every ancestor shown) with the keyboard enabled get it topmost first: higher frame
-- strata, then higher frame level, then newest. Each runs its OnKeyDown (or OnKeyUp) script if it
-- has one; one that doesn't propagate keyboard input (SetPropagateKeyboardInput(false), the
-- default) consumes the key, read after its script runs, so a script may decide per key. One that
-- propagates passes it on. A key no frame consumes goes to the game's bindings and is recorded
-- in h.propagatedKeys. Returns whether a frame consumed it.
function Harness:Key(key, down)
    local script = down and "OnKeyDown" or "OnKeyUp"
    local receivers = {}
    for i, frame in ipairs(self.frames) do
        if Harness.State(frame).keyboardEnabled and self:IsVisibleWidget(frame) then
            receivers[#receivers + 1] = { frame = frame, strata = self:FrameStrataIndex(frame), level = self:FrameLevel(frame), index = i }
        end
    end
    table.sort(receivers, function(a, b)
        if a.strata ~= b.strata then return a.strata > b.strata end
        if a.level ~= b.level then return a.level > b.level end
        return a.index > b.index
    end)
    for _, receiver in ipairs(receivers) do
        local frame = receiver.frame
        local state = Harness.State(frame)
        if state.keyboardEnabled and self:IsVisibleWidget(frame) then -- an earlier script may change either
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

-- Mouse coverage -----------------------------------------------------------

-- Whether a region covers the whole screen: it is UIParent, or it is anchored (SetAllPoints, or
-- two opposite corners on the same corners, flush or outside) to a region that does.
local function CoversScreen(h, region, depth)
    if type(region) == "string" then
        region = rawget(h.env, region)
    end
    local s = type(region) == "table" and Harness.State(region)
    if not s or depth > 20 then
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
    -- sx, sy: the sign an offset may have to stay flush or push the corner outward.
    local function Corner(point, sx, sy)
        local p = byPoint[point]
        if p and p.relativePoint == point and p.x * sx >= 0 and p.y * sy >= 0 then
            return p.relativeTo or s.parent
        end
    end
    for _, pair in ipairs({ { "TOPLEFT", -1, 1, "BOTTOMRIGHT", 1, -1 }, { "TOPRIGHT", 1, 1, "BOTTOMLEFT", -1, -1 } }) do
        local a, b = Corner(pair[1], pair[2], pair[3]), Corner(pair[4], pair[5], pair[6])
        if a ~= nil and a == b and CoversScreen(h, a, depth + 1) then
            return true
        end
    end
    return false
end

-- True when a visible, mouse-enabled frame covers the screen, so a click can't reach the world.
-- A simple model: covering is SetAllPoints(UIParent) or corner anchors to it (see CoversScreen);
-- a frame sized to the screen with SetSize, alpha, strata and hit rect insets aren't considered.
function Harness:WorldClickBlocked()
    for _, frame in ipairs(self.frames) do
        local state = Harness.State(frame)
        if state.mouseEnabled and self:IsVisibleWidget(frame) and CoversScreen(self, frame, 0) then
            return true
        end
    end
    return false
end

-- Dragging -------------------------------------------------------------------

-- Drags a frame with the mouse button (default "LeftButton") by dx, dy. Only a visible,
-- mouse-enabled frame that registered the button with RegisterForDrag starts a drag ([D]
-- RegisterForDrag's page: dragging needs EnableMouse, since OnDragStart doesn't imply it). The
-- press runs OnMouseDown(frame, button) ([G]), then OnDragStart(frame, button); if the frame is
-- then moving (StartMoving), it follows the mouse: each anchor shifts by dx, dy (widgets.lua's
-- header says why). The release runs OnDragStop(frame); OnMouseUp and OnClick don't run ([D]
-- "Blocks OnMouseUp and OnClick when dragging with a registered button"). A frame the scripts
-- leave moving keeps following the mouse until StopMovingOrSizing, so a later h:Drag moves it
-- again. Returns whether the drag started.
function Harness:Drag(frame, dx, dy, button)
    button = button or "LeftButton"
    local s = Harness.State(frame)
    if not self:IsVisibleWidget(frame) or not s.mouseEnabled or not (s.dragButtons and s.dragButtons[button]) then
        return false
    end
    if s.scripts.OnMouseDown then self:Protect(s.scripts.OnMouseDown, frame, button) end
    if s.scripts.OnDragStart then self:Protect(s.scripts.OnDragStart, frame, button) end
    if s.moving then
        s.allPoints = nil -- the anchors now carry offsets
        for _, p in ipairs(s.points) do
            p.x, p.y = p.x + (dx or 0), p.y + (dy or 0)
        end
    end
    if s.scripts.OnDragStop then self:Protect(s.scripts.OnDragStop, frame) end
    return true
end

-- Random -------------------------------------------------------------------

-- Makes the env's math.random (and random) deterministic from seed n: the harness's own linear
-- congruential generator (Numerical Recipes' 32-bit constants), independent of Lua's global
-- math.random state, so the same seed gives the same sequence in every test. Before the first
-- SeedRandom, math.random is Lua's own. An addon's local copy of math.random follows too.
function Harness:SeedRandom(n)
    assert(type(n) == "number", "SeedRandom: the seed must be a number")
    self.rng = math.floor(n) % 4294967296
end

-- The generator's next value in [0, 1).
function Harness:NextRandom()
    self.rng = (1664525 * self.rng + 1013904223) % 4294967296
    return self.rng / 4294967296
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
    return m + math.floor(r * (n - m + 1))
end
