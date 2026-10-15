-- The harness's fidelity rules for frame visibility scripts and moving frames
-- (tests/harness/widgets.lua, h:Drag in tests/harness/input.lua).

local function Recorder(log, name)
    return function() log[#log + 1] = name end
end

test("OnShow and OnHide run when visibility changes, for the frame and its visible descendants", function()
    local h = Harness.New()
    local env = h.env
    local log = {}
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    local child = env.CreateFrame("Frame", nil, parent)
    local hidden = env.CreateFrame("Frame", nil, child)

    hidden:Hide()
    for name, frame in pairs({ child = child, hidden = hidden, parent = parent }) do
        frame:SetScript("OnShow", Recorder(log, name .. "+"))
        frame:SetScript("OnHide", Recorder(log, name .. "-"))
    end
    parent:Show()
    eq(#log, 0, "showing a shown frame runs nothing")
    parent:Hide()
    eq(table.concat(log, ","), "parent-,child-", "the frame first, then descendants that were visible")
    log = {}
    for name, frame in pairs({ child = child, hidden = hidden, parent = parent }) do
        frame:SetScript("OnShow", Recorder(log, name .. "+"))
        frame:SetScript("OnHide", Recorder(log, name .. "-"))
    end
    hidden:Show()
    eq(#log, 0, "showing under a hidden parent doesn't make it visible")
    truthy(hidden:IsShown())
    falsy(hidden:IsVisible())
    parent:SetShown(true)
    eq(table.concat(log, ","), "parent+,child+,hidden+")
    child:SetShown(false)
    eq(table.concat(log, ","), "parent+,child+,hidden+,child-,hidden-")
end)

test("an error in OnHide is reported and the rest still run", function()
    local h = Harness.New()
    local env = h.env
    local parent = env.CreateFrame("Frame")
    local child = env.CreateFrame("Frame", nil, parent)
    local ran = false

    parent:SetScript("OnHide", function() error("boom") end)
    child:SetScript("OnHide", function() ran = true end)
    h:ExpectErrors("boom")
    parent:Hide()
    truthy(ran)
end)

local function Movable(h)
    local env = h.env
    local frame = env.CreateFrame("Frame", "HarnessMover", env.UIParent)

    frame:SetSize(100, 20)
    frame:SetPoint("CENTER", env.UIParent, "CENTER", 10, 20)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    return frame
end

test("dragging runs OnMouseDown, OnDragStart and OnDragStop, not OnMouseUp or OnClick, and moves the frame", function()
    local h = Harness.New()
    local env = h.env
    local frame = Movable(h)
    local log, stopped = {}, nil

    frame:SetScript("OnMouseDown", function(_, button) log[#log + 1] = ("down:" .. button) end)
    frame:SetScript("OnMouseUp", Recorder(log, "up"))
    frame:SetScript("OnDragStart", function(self, button)
        log[#log + 1] = ("start:" .. button)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        log[#log + 1] = "stop"
        self:StopMovingOrSizing()
        stopped = { self:GetPoint(1) }
    end)
    falsy(frame:IsUserPlaced())
    truthy(h:Drag(frame, -100, 50))
    eq(table.concat(log, ","), "down:LeftButton,start:LeftButton,stop")
    eq(stopped[1], "CENTER")
    eq(stopped[2], env.UIParent)
    eq(stopped[3], "CENTER")
    eq(stopped[4], -90)
    eq(stopped[5], 70)
    truthy(frame:IsUserPlaced(), "StartMoving marks the frame user placed")
    eq(frame:GetNumPoints(), 1)
end)

test("only a visible, mouse-enabled frame dragged with a registered button starts a drag", function()
    local h = Harness.New()
    local frame = Movable(h)
    local starts = 0

    frame:SetScript("OnDragStart", function() starts = (starts + 1) end)
    falsy(h:Drag(frame, 5, 5, "RightButton"), "not registered")
    frame:RegisterForDrag("LeftButton", "RightButton")
    truthy(h:Drag(frame, 5, 5, "RightButton"))
    frame:RegisterForDrag()
    falsy(h:Drag(frame, 5, 5), "no arguments clear the registration")
    frame:RegisterForDrag("LeftButton")
    frame:EnableMouse(false)
    falsy(h:Drag(frame, 5, 5), "dragging needs the mouse enabled")
    frame:EnableMouse(true)
    frame:Hide()
    falsy(h:Drag(frame, 5, 5), "a hidden frame")
    eq(starts, 1)
    local _, _, _, x, y = frame:GetPoint(1)

    eq(x, 10, "without StartMoving the frame stays")
    eq(y, 20)
end)

test("StartMoving needs a movable frame; a moving frame follows the mouse until it stops or hides", function()
    local h = Harness.New()
    local frame = Movable(h)

    frame:SetMovable(false)
    falsy(frame:IsMovable())
    throws(function() frame:StartMoving() end, "Frame is not movable")
    frame:SetMovable(true)
    truthy(frame:IsMovable())
    frame:SetScript("OnDragStart", frame.StartMoving)
    h:Drag(frame, 1, 1)
    frame:SetScript("OnDragStart", nil)
    h:Drag(frame, 1, 1)
    local _, _, _, x = frame:GetPoint(1)

    eq(x, 12, "still moving: the next drag moves it too")
    frame:Hide()
    frame:Show()
    h:Drag(frame, 1, 1)
    _, _, _, x = frame:GetPoint(1)
    eq(x, 12, "hiding stopped the move")
    frame:SetClampedToScreen(true)
    truthy(frame:IsClampedToScreen())
    frame:SetUserPlaced(false)
    falsy(frame:IsUserPlaced())
end)

test("moving a protected frame is blocked in combat lockdown", function()
    local h = Harness.New()

    h:ExpectBlocked(2) -- the calls under test
    local env = h.env
    local secure = env.CreateFrame("Button", nil, env.UIParent, "SecureActionButtonTemplate")

    secure:SetMovable(true)
    h:EnterCombat()
    secure:StartMoving()
    secure:SetClampedToScreen(true)
    eq(#h.blocked, 2)
    falsy(Harness.State(secure).moving)
    falsy(secure:IsClampedToScreen())
end)

test("GetChildren lists child frames and GetRegions the regions, in creation order", function()
    local h = Harness.New()
    local env = h.env
    local parent = env.CreateFrame("Frame")
    local a = env.CreateFrame("Frame", nil, parent)
    local text = parent:CreateFontString()
    local b = env.CreateFrame("Button", nil, parent)
    local texture = parent:CreateTexture()

    parent:CreateAnimationGroup()
    local children = { parent:GetChildren() }

    eq(#children, 2)
    eq(children[1], a)
    eq(children[2], b)
    eq(parent:GetNumChildren(), 2)
    local regions = { parent:GetRegions() }

    eq(regions[1], text)
    eq(regions[2], texture)
    eq(parent:GetNumRegions(), 2)
    eq(select("#", a:GetChildren()), 0)
end)

test("mask textures attach to textures once each, and translation and scale animations keep their settings", function()
    local h = Harness.New()
    local frame = h.env.CreateFrame("Frame")
    local texture = frame:CreateTexture()
    local mask = frame:CreateMaskTexture()

    mask:SetTexture("Interface\CharacterFrame\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    texture:AddMaskTexture(mask)
    texture:AddMaskTexture(mask)
    eq(texture:GetNumMaskTextures(), 1)
    eq(texture:GetMaskTexture(1), mask)
    texture:RemoveMaskTexture(mask)
    eq(texture:GetNumMaskTextures(), 0)
    local group = frame:CreateAnimationGroup()
    local move = group:CreateAnimation("Translation")

    move:SetOffset(8, -2)
    eq(select(2, move:GetOffset()), -2)
    local grow = group:CreateAnimation("Scale")

    grow:SetScaleTo(1.3, 1.3)
    eq(grow:GetScaleTo(), 1.3)
    throws(function() group:CreateAnimation("Wobble") end, "unsupported animation type")
end)

test("a scroll frame scrolls its child: the range is the child's height less its own, never below 0", function()
    local h = Harness.New()
    local env = h.env
    local scroll = env.CreateFrame("ScrollFrame", nil, env.UIParent)

    scroll:SetSize(300, 200)
    local child = env.CreateFrame("Frame", nil, scroll)

    child:SetSize(300, 500)
    eq(scroll:GetVerticalScrollRange(), 0, "no child yet")
    scroll:SetScrollChild(child)
    eq(scroll:GetScrollChild(), child)
    eq(scroll:GetVerticalScrollRange(), 300)
    eq(scroll:GetVerticalScroll(), 0)
    scroll:SetVerticalScroll(120)
    eq(scroll:GetVerticalScroll(), 120)
    child:SetHeight(150)
    eq(scroll:GetVerticalScrollRange(), 0, "a child shorter than the frame doesn't scroll")
    truthy(scroll:IsObjectType("Frame"), "a scroll frame is a frame")
end)
