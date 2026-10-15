-- SettingsWindow: the addon's settings, drawn from ByteTerrace.SettingsPages (Settings.lua) as
-- one view: the page list on the left, the chosen page's sections and controls on the right. The
-- view has two hosts, and moves to whichever shows it:
--   * Blizzard's settings panel, as the addon's canvas page (Esc > Options > AddOns). The canvas
--     is marked ignored for the controller UI's SmartNavigation (smartNavigationIgnored, which
--     covers every child), so controller focus never lands on an addon control there: on Forever
--     that taints what the controller UI remembers, and closing the panel then freezes the client
--     (tools/api/forbidden.json). With the controller UI on, the page is for the mouse.
--   * The addon's own window, which the bare slash command toggles. It's an ordinary insecure
--     frame, so it opens in combat too, and addon code never has to open Blizzard's panel.
--
-- Controls are plain buttons, textures and font strings:
--   boolean  a box that holds a check while on; a click flips it.
--   enum     a button showing the value's label; left click moves to the next value, right
--            click to the previous one.
--   number   "-" and "+" step by the row's step, within its min and max.
-- Every change goes through State:Set as one batch, so a locked row is refused with a message
-- and keeps its value. A change made anywhere refreshes that row's control while its page shows;
-- only the shown page's rows are watched, so a hidden view or page costs nothing and catches up
-- when it shows. Hovering a setting shows its description.
--
-- The view is built the first time a host shows it. The window is sized to the page it shows;
-- drag it to move it, and the close button or the command hides it.
--
--   ByteTerrace.NewSettingsWindow(addon, pages)  the settings for SettingsPages' pages
--   window:Register()                             registers the canvas page with Blizzard's panel
--   window:Toggle(), window:Show(page?), window:Hide(), window:IsShown()   the standalone window
--   window:Page()                                 the index of the page the view shows
-- Public members: Frame (the window, nil until first shown), Canvas (the settings-panel page),
-- View (nil until first shown), Pages, and Controls ([row id] = the row's control button: its
-- Label is the value shown, Check the boolean's check, Minus and Plus the number's steppers).

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
local CanvasInset = 16

local ByteTerrace = ByteTerrace
local CreateFrame, GameTooltip, Settings, UIParent = CreateFrame, GameTooltip, Settings, UIParent
local ipairs, tostring, wipe = ipairs, tostring, wipe
local floor, max, min = math.floor, math.max, math.min

local SettingsWindow = {}
SettingsWindow.__index = SettingsWindow

-- A value as the window shows it: an enum's label, a number without trailing zeros. Only enums
-- and numbers show text; a boolean shows a check.
local function ValueText(spec, value)
    if spec.values then
        return spec.valueLabels and spec.valueLabels[value] or tostring(value)
    end
    return ("%g"):format(value)
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

-- The next or previous enum value, wrapping around. State admits only the row's values, so value
-- is one of them.
local function StepEnum(spec, value, delta)
    local count = #spec.values
    for i, candidate in ipairs(spec.values) do
        if candidate == value then
            return spec.values[(i - 1 + delta) % count + 1]
        end
    end
end

-- A number one step from value. With a step, it moves along the row's grid (multiples of step
-- from min) and stops at the last grid value inside the bounds, so State always admits it;
-- without one it moves by 1 and stops at min and max.
local function StepNumber(spec, value, delta)
    local low, high, step = spec.min, spec.max, spec.step
    if not step then
        local stepped = value + delta
        return (low and stepped < low and low) or (high and stepped > high and high) or stepped
    end
    local base = low or 0
    local index = floor((value - base) / step + 0.5) + delta
    if high then
        index = min(index, floor((high - base) / step + 1e-9))
    end
    if low then
        index = max(index, 0)
    end
    return base + index * step
end

--- Creates the window; its frame is built the first time it shows.
---@param addon table the AddOn
---@param pages table[] ByteTerrace.SettingsPages(addon)
---@return table window
local function NewSettingsWindow(addon, pages)
    local window = setmetatable({
        Pages = pages, Controls = {}, m_addon = addon, m_page = 1, m_rows = {}, m_watchers = {}, m_containers = {},
        m_navButtons = {}, m_heights = {},
    }, SettingsWindow)
    return window
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

-- Builds page index's rows in their own container, and returns the container's height. Each row
-- goes in m_rows[index] as { watched = its row and lock ids, refresh }.
local function BuildPage(window, content, page, index)
    local rows = {}
    window.m_rows[index] = rows
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
            local watched = { entry.id }
            if entry.spec.lockId then
                watched[2] = entry.spec.lockId
            end
            rows[#rows + 1] = { watched = watched, refresh = BuildRow(window, row, entry) }
            y = y + RowHeight
        end
    end
    container:SetHeight(y)
    container:Hide()
    return container, y
end

-- Watches the shown page's rows while the view shows, refreshing them now: a hidden view, and
-- every other page, cost nothing when their rows change.
local function Follow(window)
    local state, watchers = window.m_addon.State, window.m_watchers
    for i = 1, #watchers do
        state:Unwatch(watchers[i])
    end
    wipe(watchers)
    if not window.View:IsVisible() then
        return
    end
    for _, row in ipairs(window.m_rows[window.m_page]) do
        row.refresh()
        watchers[#watchers + 1] = state:Watch(row.watched, row.refresh, true)
    end
end

-- Shows page i: its container, its nav button marked, the window sized to fit, and its rows
-- followed.
local function ShowPage(window, index)
    window.m_page = index
    for i, container in ipairs(window.m_containers) do
        container:SetShown(i == index)
        window.m_navButtons[i]:SetBackdropBorderColor(i == index and 1 or 0.42, i == index and 0.82 or 0.4,
            i == index and 0 or 0.5, 1)
    end
    if window.m_host == window.Frame then
        local navHeight = #window.Pages * NavButtonHeight
        local height = window.m_heights[index] > navHeight and window.m_heights[index] or navHeight
        window.Frame:SetHeight(TitleHeight + height + Pad)
    end
    Follow(window)
end

-- Builds the view: the page list and every page, on a frame either host can hold.
local function BuildView(window)
    local view = CreateFrame("Frame", nil, UIParent)
    window.View = view
    view:Hide()
    view:SetScript("OnShow", function() Follow(window) end)
    view:SetScript("OnHide", function() Follow(window) end)
    local content = CreateFrame("Frame", nil, view)
    content:SetPoint("TOPLEFT", NavWidth + Pad, 0)
    content:SetPoint("BOTTOMRIGHT")
    for i, page in ipairs(window.Pages) do
        local nav = NewButton(view, NavWidth, page.name)
        nav:SetPoint("TOPLEFT", 0, -((i - 1) * NavButtonHeight))
        nav:SetScript("OnClick", function() ShowPage(window, i) end)
        window.m_navButtons[i] = nav
        window.m_containers[i], window.m_heights[i] = BuildPage(window, content, page, i)
    end
end

-- Builds the window: the backdrop, the title (dragging moves the window) and the close button.
local function BuildFrame(window)
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
end

-- Moves the view into a host (the window or the canvas) and shows its page, refreshed. The window
-- the view leaves closes, rather than standing empty.
local function Present(window, host, page)
    if not window.View then
        BuildView(window)
    end
    local view = window.View
    if window.m_host ~= host then
        if window.m_host == window.Frame and window.Frame then
            window.Frame:Hide()
        end
        window.m_host = host
        view:SetParent(host)
        view:ClearAllPoints()
        if host == window.Frame then
            view:SetPoint("TOPLEFT", Pad, -TitleHeight)
            view:SetPoint("BOTTOMRIGHT", -Pad, Pad)
        else
            view:SetPoint("TOPLEFT", CanvasInset, -CanvasInset)
            view:SetPoint("BOTTOMRIGHT", -CanvasInset, CanvasInset)
        end
    end
    ShowPage(window, page or window.m_page)
    view:Show()
end

--- Registers the view's canvas page with Blizzard's settings panel, where it shows under
--- Esc > Options > AddOns. Controller focus is kept out of it (see the header).
function SettingsWindow:Register()
    local canvas = CreateFrame("Frame", nil, UIParent)
    self.Canvas = canvas
    canvas:Hide()
    canvas.smartNavigationIgnored = true -- SmartNavigation_IsFrameIgnored: the canvas and its children
    canvas:SetScript("OnShow", function() Present(self, canvas) end)
    local category = Settings.RegisterCanvasLayoutCategory(canvas, self.m_addon.Title)
    Settings.RegisterAddOnCategory(category)
end

--- Shows the window on a page (the last one shown, else the main page).
---@param page integer? the page's index in Pages
function SettingsWindow:Show(page)
    if not self.Frame then
        BuildFrame(self)
    end
    Present(self, self.Frame, page)
    self.Frame:Show()
end

--- Hides the window. When Blizzard's panel shows the canvas, the view goes back to it.
function SettingsWindow:Hide()
    if self.Frame then
        self.Frame:Hide()
    end
    if self.Canvas and self.Canvas:IsVisible() and self.m_host ~= self.Canvas then
        Present(self, self.Canvas)
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

--- The index of the page the view shows (or last showed).
---@return integer
function SettingsWindow:Page()
    return self.m_page
end

ByteTerrace.NewSettingsWindow = NewSettingsWindow
