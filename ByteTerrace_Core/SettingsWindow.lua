-- SettingsWindow: the addon's own settings window, drawn from ByteTerrace.SettingsPages
-- (Settings.lua): the page list on the left, the chosen page's sections and controls on the
-- right. The bare slash command toggles it. It's an ordinary insecure frame, so it opens in
-- combat too, and it never touches Blizzard's settings panel, whose close an addon's taint turns
-- into a client freeze for controller players (see Settings.lua).
--
-- Controls are plain buttons, textures and font strings:
--   boolean  a box that holds a check while on; a click flips it.
--   enum     a button showing the value's label; left click moves to the next value, right
--            click to the previous one.
--   number   "-" and "+" step by the row's step, within its min and max.
-- Every change goes through State:Set as one batch, so a locked row is refused with a message
-- and keeps its value. A change made anywhere refreshes that row's control while the window
-- shows; a hidden window does no widget work. Hovering a setting shows its description.
--
-- The frame is built the first time the window opens, and sized to the page it shows. Drag the
-- title to move it; the close button or the command hides it.
--
--   ByteTerrace.NewSettingsWindow(addon, pages)  the window for SettingsPages' pages
--   window:Toggle(), window:Show(page?), window:Hide(), window:IsShown()
--   window:Page()                                 the index of the page it shows
-- Public members: Frame (nil until first shown), Pages, and Controls ([row id] = the row's
-- control button: its Label is the value shown, Check the boolean's check, Minus and Plus the
-- number's steppers).

local Width = 620
local NavWidth = 160
local Pad = 16
local TitleHeight = 44
local RowHeight = 28
local HeaderHeight = 30
local NavButtonHeight = 26
local ControlWidth = 170
local Solid = "Interface\\Buttons\\WHITE8X8"
local Border = "Interface\\Tooltips\\UI-Tooltip-Border"

local ByteTerrace = ByteTerrace
local CreateFrame, GameTooltip, UIParent = CreateFrame, GameTooltip, UIParent
local ipairs, tostring = ipairs, tostring
local floor = math.floor

local SettingsWindow = {}
SettingsWindow.__index = SettingsWindow

-- A value as the window shows it: an enum's label, a number without trailing zeros.
local function ValueText(spec, value)
    if spec.values then
        return spec.valueLabels and spec.valueLabels[value] or tostring(value)
    end
    if spec.kind == "number" then
        return ("%g"):format(value)
    end
    return tostring(value)
end

-- A flat button with a label, the window's one button style.
local function NewButton(parent, width, text)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, 22)
    button:SetBackdrop({ bgFile = Solid, edgeFile = Solid, edgeSize = 1 })
    button:SetBackdropColor(0.16, 0.15, 0.2, 1)
    button:SetBackdropBorderColor(0.42, 0.4, 0.5, 1)
    button.Label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.Label:SetPoint("CENTER")
    button.Label:SetText(text or "")
    return button
end

-- The next or previous enum value, wrapping around.
local function StepEnum(spec, value, delta)
    local count = #spec.values
    for i, candidate in ipairs(spec.values) do
        if candidate == value then
            return spec.values[(i - 1 + delta) % count + 1]
        end
    end
    return spec.values[1]
end

-- A number stepped by the row's step, kept within its bounds.
local function StepNumber(spec, value, delta)
    local step = spec.step or 1
    local stepped = value + delta * step
    if spec.min and stepped < spec.min then
        stepped = spec.min
    end
    if spec.max and stepped > spec.max then
        stepped = spec.max
    end
    local base = spec.min or 0
    return base + floor((stepped - base) / step + 0.5) * step
end

--- Creates the window; its frame is built the first time it shows.
---@param addon table the AddOn
---@param pages table[] ByteTerrace.SettingsPages(addon)
---@return table window
local function NewSettingsWindow(addon, pages)
    return setmetatable({
        Pages = pages, Controls = {}, m_addon = addon, m_page = 1, m_refreshers = {}, m_containers = {},
        m_navButtons = {}, m_heights = {},
    }, SettingsWindow)
end

-- Writes a row from the window: one batch, refused with a message while the row is locked.
local function Write(window, entry, value)
    local addon, state = window.m_addon, window.m_addon.State
    if state:IsLocked(entry.id) then
        addon:Print(entry.spec.label .. " is locked.")
        return
    end
    addon:Batch(function()
        state:Set(entry.id, value)
    end)
end

-- Shows a row's description while the pointer is over it.
local function AttachTooltip(region, spec)
    region:SetScript("OnEnter", function()
        GameTooltip:SetOwner(region, "ANCHOR_RIGHT")
        GameTooltip:SetText(spec.label, 1, 0.82, 0)
        if spec.description then
            GameTooltip:AddLine(spec.description, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    region:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- Builds one setting row's label and control, and returns the function that shows its value.
local function BuildRow(window, row, entry)
    local state, spec, id = window.m_addon.State, entry.spec, entry.id
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 0, 0)
    label:SetPoint("RIGHT", -(ControlWidth + 12), 0)
    label:SetJustifyH("LEFT")
    label:SetText(spec.label)
    row:EnableMouse(true)
    AttachTooltip(row, spec)
    local control, Refresh
    if spec.kind == "boolean" then
        control = NewButton(row, 22)
        control:SetPoint("RIGHT", -(ControlWidth - 22), 0)
        control.Check = control:CreateTexture(nil, "ARTWORK")
        control.Check:SetTexture(Solid)
        control.Check:SetVertexColor(1, 0.82, 0, 1)
        control.Check:SetPoint("TOPLEFT", 5, -5)
        control.Check:SetPoint("BOTTOMRIGHT", -5, 5)
        control:SetScript("OnClick", function()
            Write(window, entry, not state.Values[id])
        end)
        Refresh = function()
            control.Check:SetShown(state.Values[id] == true)
        end
    elseif spec.values then
        control = NewButton(row, ControlWidth)
        control:SetPoint("RIGHT")
        control:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        control:SetScript("OnClick", function(_, button)
            Write(window, entry, StepEnum(spec, state.Values[id], button == "RightButton" and -1 or 1))
        end)
        Refresh = function()
            control.Label:SetText(ValueText(spec, state.Values[id]))
        end
    else
        control = CreateFrame("Frame", nil, row)
        control:SetSize(ControlWidth, 22)
        control:SetPoint("RIGHT")
        control.Minus = NewButton(control, 26, "-")
        control.Minus:SetPoint("LEFT")
        control.Plus = NewButton(control, 26, "+")
        control.Plus:SetPoint("RIGHT")
        control.Label = control:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        control.Label:SetPoint("CENTER")
        control.Minus:SetScript("OnClick", function()
            Write(window, entry, StepNumber(spec, state.Values[id], -1))
        end)
        control.Plus:SetScript("OnClick", function()
            Write(window, entry, StepNumber(spec, state.Values[id], 1))
        end)
        Refresh = function()
            control.Label:SetText(ValueText(spec, state.Values[id]))
        end
    end
    AttachTooltip(control, spec)
    window.Controls[id] = control
    return function()
        Refresh()
        label:SetAlpha(state:IsLocked(id) and 0.5 or 1)
    end
end

-- Builds one page's rows in their own container, and returns the container's height.
local function BuildPage(window, content, page)
    local container = CreateFrame("Frame", nil, content)
    container:SetPoint("TOPLEFT")
    container:SetPoint("TOPRIGHT")
    local y = 0
    for _, entry in ipairs(page.entries) do
        if entry.header then
            local header = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            header:SetPoint("TOPLEFT", 0, -(y + 10))
            header:SetText(entry.header)
            y = y + HeaderHeight
        else
            local row = CreateFrame("Frame", nil, container)
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", 0, -y)
            row:SetHeight(RowHeight)
            local refresh = BuildRow(window, row, entry)
            window.m_refreshers[#window.m_refreshers + 1] = refresh
            local watched = { entry.id }
            if entry.spec.lockId then
                watched[2] = entry.spec.lockId
            end
            window.m_addon.State:Watch(watched, function()
                if window.Frame:IsShown() then
                    refresh()
                end
            end, true)
            y = y + RowHeight
        end
    end
    container:SetHeight(y)
    container:Hide()
    return container, y
end

-- Shows page i: its container, its nav button marked, and the window sized to fit.
local function ShowPage(window, index)
    window.m_page = index
    for i, container in ipairs(window.m_containers) do
        container:SetShown(i == index)
        window.m_navButtons[i]:SetBackdropBorderColor(i == index and 1 or 0.42, i == index and 0.82 or 0.4,
            i == index and 0 or 0.5, 1)
    end
    local navHeight = #window.Pages * NavButtonHeight
    local height = window.m_heights[index] > navHeight and window.m_heights[index] or navHeight
    window.Frame:SetHeight(TitleHeight + height + Pad)
end

-- Builds the frame: the backdrop, the title bar (dragging moves the window), the close button,
-- the page list and every page.
local function Build(window)
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    window.Frame = frame
    frame:SetFrameStrata("DIALOG")
    frame:SetWidth(Width)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({ bgFile = Solid, edgeFile = Border, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    frame:SetBackdropColor(0.05, 0.05, 0.07, 0.96)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    frame.Title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.Title:SetPoint("TOPLEFT", Pad, -Pad)
    frame.Title:SetText(window.m_addon.Title)
    frame.Close = NewButton(frame, 60, "Close")
    frame.Close:SetPoint("TOPRIGHT", -Pad + 4, -Pad + 4)
    frame.Close:SetScript("OnClick", function() window:Hide() end)
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", Pad + NavWidth + Pad, -TitleHeight)
    content:SetPoint("BOTTOMRIGHT", -Pad, Pad)
    for i, page in ipairs(window.Pages) do
        local nav = NewButton(frame, NavWidth, page.name)
        nav:SetPoint("TOPLEFT", Pad, -(TitleHeight + (i - 1) * NavButtonHeight))
        nav:SetScript("OnClick", function() ShowPage(window, i) end)
        window.m_navButtons[i] = nav
        window.m_containers[i], window.m_heights[i] = BuildPage(window, content, page)
    end
end

--- Shows the window on a page (the last one shown, else the main page).
---@param page integer? the page's index in Pages
function SettingsWindow:Show(page)
    if not self.Frame then
        Build(self)
    end
    for _, refresh in ipairs(self.m_refreshers) do
        refresh()
    end
    ShowPage(self, page or self.m_page)
    self.Frame:Show()
end

--- Hides the window.
function SettingsWindow:Hide()
    if self.Frame then
        self.Frame:Hide()
    end
end

--- Whether the window shows.
---@return boolean
function SettingsWindow:IsShown()
    return self.Frame ~= nil and self.Frame:IsShown()
end

--- Shows the window if it's hidden, else hides it.
function SettingsWindow:Toggle()
    if self:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

--- The index of the page the window shows (or last showed).
---@return integer
function SettingsWindow:Page()
    return self.m_page
end

ByteTerrace.NewSettingsWindow = NewSettingsWindow
