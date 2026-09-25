-- The harness's fidelity rules for keyboard input, mouse coverage, frame strata and random
-- numbers (tests/harness/input.lua, widgets.lua).

-- Keyboard, mouse, strata ----------------------------------------------------------------

test("keyboard input: a keyboard-enabled frame consumes keys unless it propagates them", function()
    local h = Harness.new()
    local env = h.env
    local log = {}
    local under = env.CreateFrame("Frame")
    under:EnableKeyboard(true)
    under:SetPropagateKeyboardInput(true)
    under:SetScript("OnKeyDown", function(_, key) log[#log + 1] = "under:" .. key end)
    eq(h:Key("W", true), false, "a propagating frame passes the key on")
    eq(h.propagatedKeys[1], "W")
    local top = env.CreateFrame("Frame")
    falsy(top:IsKeyboardEnabled(), "off by default")
    falsy(top:GetPropagateKeyboardInput(), "doesn't propagate by default")
    top:EnableKeyboard(true)
    top:SetScript("OnKeyDown", function(self, key)
        log[#log + 1] = "top:" .. key
        self:SetPropagateKeyboardInput(key ~= "ESCAPE" and key ~= "1") -- decided per key, after the script
    end)
    top:SetScript("OnKeyUp", function(_, key) log[#log + 1] = "topUp:" .. key end)
    truthy(h:Key("1", true), "consumed")
    h:Key("ENTER", true)
    h:Key("ESCAPE", true)
    h:Key("ESCAPE", false)
    eq(table.concat(log, ","), "under:W,top:1,top:ENTER,under:ENTER,top:ESCAPE,topUp:ESCAPE")
    eq(table.concat(h.propagatedKeys, ","), "W,ENTER", "keys nothing consumed")
    top:Hide()
    h:Key("4", true)
    eq(log[#log], "under:4", "hidden frames get nothing")
    local silent = env.CreateFrame("Frame")
    silent:EnableKeyboard(true)
    truthy(h:Key("W", true), "a keyboard-enabled frame without a script still consumes the key")
end)

test("keyboard order follows strata, then level, then creation", function()
    local h = Harness.new()
    local env = h.env
    local order = {}
    local function Receiver(name)
        local f = env.CreateFrame("Frame", nil, env.UIParent)
        f:EnableKeyboard(true)
        f:SetPropagateKeyboardInput(true)
        f:SetScript("OnKeyDown", function() order[#order + 1] = name end)
        return f
    end
    local overlay = Receiver("overlay")
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")
    local low = Receiver("low")
    local high = Receiver("high")
    low:SetFrameLevel(1)
    high:SetFrameLevel(5)
    Receiver("newest")
    h:Key("W", true)
    eq(table.concat(order, ","), "overlay,high,newest,low")
end)

test("EnableKeyboard is blocked in combat only on protected frames; SetPropagateKeyboardInput on any", function()
    local h = Harness.new()
    local env = h.env
    local plain = env.CreateFrame("Frame")
    local secure = env.CreateFrame("Button", nil, nil, "SecureActionButtonTemplate")
    h:EnterCombat()
    plain:EnableKeyboard(true)
    truthy(plain:IsKeyboardEnabled(), "a plain frame enables its keyboard in combat")
    secure:EnableKeyboard(true)
    falsy(secure:IsKeyboardEnabled(), "blocked")
    eq(h.blocked[1], "Button:EnableKeyboard (SimpleFrameAPI)")
    plain:SetPropagateKeyboardInput(true)
    falsy(plain:GetPropagateKeyboardInput(), "HasRestrictions: blocked in lockdown")
    eq(h.blocked[2], "Frame:SetPropagateKeyboardInput (SimpleFrameAPI)")
    truthy(h:Key("W", true), "so the frame keeps consuming keys")
    h:LeaveCombat()
    plain:SetPropagateKeyboardInput(true)
    truthy(plain:GetPropagateKeyboardInput())
end)

test("frame strata and levels: set, inherited, validated", function()
    local h = Harness.new()
    local env = h.env
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    local child = env.CreateFrame("Frame", nil, parent)
    eq(env.UIParent:GetFrameStrata(), "MEDIUM")
    eq(child:GetFrameStrata(), "MEDIUM")
    eq(parent:GetFrameLevel(), 1)
    eq(child:GetFrameLevel(), 2)
    parent:SetFrameStrata("DIALOG")
    parent:SetFrameLevel(10)
    eq(child:GetFrameStrata(), "DIALOG", "children follow their parent")
    eq(child:GetFrameLevel(), 11)
    throws(function() child:SetFrameStrata("SKY") end, "unknown strata")
    throws(function() child:SetFrameLevel(Secret(3)) end, "AllowedWhenUntainted")
    local secure = env.CreateFrame("Frame", nil, nil, "SecureHandlerBaseTemplate")
    h:EnterCombat()
    secure:SetFrameStrata("HIGH")
    eq(secure:GetFrameStrata(), "MEDIUM", "protected: blocked on a protected frame in combat")
end)

test("a visible, mouse-enabled frame covering the screen blocks world clicks", function()
    local h = Harness.new()
    local env = h.env
    falsy(h:WorldClickBlocked())
    local cover = env.CreateFrame("Frame", nil, env.UIParent)
    cover:SetAllPoints(env.UIParent)
    falsy(h:WorldClickBlocked(), "not mouse-enabled")
    cover:EnableMouse(true)
    truthy(h:WorldClickBlocked())
    cover:Hide()
    falsy(h:WorldClickBlocked(), "hidden")
    local corners = env.CreateFrame("Frame", nil, env.UIParent)
    corners:EnableMouse(true)
    corners:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 0, 0)
    corners:SetPoint("BOTTOMRIGHT", env.UIParent, "BOTTOMRIGHT", 0, 0)
    truthy(h:WorldClickBlocked(), "two opposite corners")
    corners:SetPoint("BOTTOMRIGHT", env.UIParent, "BOTTOMRIGHT", -10, 0)
    falsy(h:WorldClickBlocked(), "inset from an edge")
    corners:ClearAllPoints()
    corners:SetSize(200, 200)
    corners:SetPoint("CENTER")
    falsy(h:WorldClickBlocked(), "a dialog")
    local inner = env.CreateFrame("Button", nil, cover)
    inner:SetAllPoints()
    cover:Show()
    cover:EnableMouse(false)
    truthy(h:WorldClickBlocked(), "a mouse-enabled button filling a full-screen frame")
end)

-- Random -----------------------------------------------------------------------------

Harness.DefineAddOn("RandomProbe", { sources = { [[
    local _, ns = ...
    local random = math.random
    ns.Roll = function() return random(1, 6) end
]] } })

test("SeedRandom makes math.random deterministic, even through an addon's local copy", function()
    local h = Harness.new()
    truthy(h.env.math.random, "the client has math.random")
    local ns = h:LoadAddon("RandomProbe")
    h:SeedRandom(42)
    local first = {}
    for i = 1, 20 do first[i] = ns.Roll() end
    h:SeedRandom(42)
    for i = 1, 20 do eq(ns.Roll(), first[i], "roll " .. i) end
    local seen = {}
    for _ = 1, 200 do
        local roll = ns.Roll()
        truthy(roll >= 1 and roll <= 6 and roll == math.floor(roll), "in range")
        seen[roll] = true
    end
    for face = 1, 6 do truthy(seen[face], "face " .. face) end
    local r = h.env.math.random()
    truthy(r >= 0 and r < 1)
    local n = h.env.random(3)
    truthy(n >= 1 and n <= 3, "random is math.random")
    throws(function() h.env.math.random(5, 1) end, "interval is empty")
    local other = Harness.new()
    other:SeedRandom(42)
    eq(other.env.math.random(1, 1000000), (function() h:SeedRandom(42); return h.env.math.random(1, 1000000) end)(),
        "independent of Lua's global random state")
end)
