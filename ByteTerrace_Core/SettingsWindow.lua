-- SettingsWindow: the addon's settings, drawn from ByteTerrace.SettingsPages (Settings.lua) as one view: a page's
-- sections and controls, in a scroll frame that clips them to the host and scrolls a row a notch with the mouse wheel.
-- While the page is taller than the host, a scroll bar at its right edge (the client's own Slider) shows where you are,
-- and dragging its thumb scrolls a whole row at a time. A section's header sits next to the first setting under it. The
-- view has two hosts, and moves to whichever shows it:
--   * Blizzard's settings panel (Esc > Options > AddOns), a canvas page per settings page: the main
--     page is the addon's category, and every other page is a subcategory listed under it, so
--     Blizzard's own list picks the page. Each canvas is marked ignored for the controller UI's
--     SmartNavigation (smartNavigationIgnored, which covers every child), so controller focus
--     never lands on an addon control there: on Forever that taints what the controller UI
--     remembers, and closing the panel then freezes the client (tools/api/forbidden.json). With
--     the controller UI on, the pages are for the mouse.
--   * The addon's own window, which the bare slash command toggles, with the view's own page list
--     on the left. It's an ordinary insecure frame, so it opens in combat too, and addon code
--     never has to open Blizzard's panel.
--
-- The controls' column is as wide as the widest dropdown choice needs, and the window as wide as the longest setting
-- label beside it, so no label or choice is cut short.
--
-- Controls are plain buttons, textures, and font strings:
--   boolean  a box that holds a check while on. Selecting it flips it.
--   enum     a dropdown: a button showing the value's label and a chevron. Selecting it opens the
--            list of every value under it, with the current one checked. Picking one sets it
--            and closes the list, and so does selecting anywhere else on the view or another
--            page, or hiding the view. A locked row says so instead of opening.
--   number   "-" and "+" step by the row's step, within its min and max.
-- The dropdown is the view's own, not Blizzard's (MenuUtil): with the controller UI on, a Blizzard menu takes
-- controller focus as it opens (FrameControlsManager's MenuProxy.OnShow calls FrameShown on it), and, opened from addon
-- code, that taints what the controller UI remembers, as an addon control in the settings panel does. Every change goes
-- through State:Set as one batch, so a locked row is refused with a message and keeps its value. A change made anywhere
-- refreshes that row's control while its page shows. Only the shown page's rows are watched, so a hidden view or page
-- costs nothing and catches up when it shows. Hovering a setting shows its description.
--
-- The view is built the first time a host shows it. The window is sized to the page it shows, up to the screen's height
-- less a margin, and a longer page scrolls in it. Drag it to move it. The close button or the command hides it.
--
--   ByteTerrace.NewSettingsWindow(addon, pages)  the settings for SettingsPages' pages
--   window:Register()                             registers the canvas pages with Blizzard's panel
--   window:Toggle(), window:Show(page?), window:Hide(), window:IsShown()   the standalone window
--   window:Page()                                 the index of the page the view shows
-- Public members: Frame (the window, nil until first shown), Canvases (the settings-panel pages, by page index), View,
-- Nav (the window's page list), Scroll (the scroll frame), Content (its scroll child, holding every page), ScrollBar
-- (the Slider), and Thumb (its thumb texture) (nil until first shown), Pages, Controls, and Dropdown. Controls maps
-- [row id] to the row's control button: its Label is the value shown, Check the boolean's check, and Minus and Plus the
-- number's steppers. Dropdown is the view's dropdown list, nil until the view is built. Its Options are its option
-- buttons, each with a Label and a Check, and Catcher is the click-away layer under it.

local Border = "Interface\\Tooltips\\UI-Tooltip-Border"
local CanvasInset = 16
-- The controls' column is at least this wide.
local ControlWidth = 170
-- A dropdown's room beside its text: 8 to the left, 24 to the right for the chevron, and 6 to spare.
local DropdownInset = 38
-- A section's header sits this far above its row's bottom edge, next to the first setting under it.
local HeaderDrop = 3
-- The room between a setting's label and its control.
local LabelGap = 12
local NavButtonHeight = 26
local NavWidth = 160
-- The height of one option in an open dropdown list.
local OptionHeight = 22
local Pad = 16
-- One row, a setting or a section's header: a page and its scroll frame are whole rows tall, and a notch of the mouse
-- wheel scrolls one, so every scroll position shows whole rows.
local RowHeight = 28
-- The room the window leaves above and below it on the screen.
local ScreenMargin = 24
-- Wide enough to take hold of the thumb.
local ScrollBarWidth = 8
-- The room between the page and its scroll bar.
local ScrollGap = 12
local Solid = "Interface\\Buttons\\WHITE8X8"
-- The scroll thumb is never shorter than this.
local ThumbFloor = 24
local TitleHeight = 44
-- The window is at least this wide.
local Width = 620

local ByteTerrace = ByteTerrace
local ceil = math.ceil
local CreateFrame = CreateFrame
local floor = math.floor
local GameTooltip = GameTooltip
local ipairs = ipairs
local max = math.max
local min = math.min
local PixelUtil = PixelUtil
local Settings = Settings
local tostring = tostring
local UIParent = UIParent
local wipe = wipe

local SettingsWindow = {}

SettingsWindow.__index = SettingsWindow

-- Draws a chevron pointing down at a button's right edge, from two short bars turned a quarter each way, so the button
-- reads as a dropdown.
local function AddChevron(button)
    for i, radians in ipairs({ -0.785, 0.785 }) do
        local bar = button:CreateTexture(nil, "ARTWORK")

        bar:SetTexture(Solid)
        bar:SetVertexColor(1, 0.82, 0, 1)
        bar:SetSize(7, 2)
        bar:SetPoint("RIGHT", -12 + ((i - 1) * 4), 0)
        bar:SetRotation(radians)
    end
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

-- Hides the open dropdown list, if any.
local function CloseList(window)
    local list = window.Dropdown

    if list then
        list:Hide()
        list.Catcher:Hide()
        list.m_id = nil
    end
end

-- Builds the view's dropdown list, hidden: a column of option buttons over the page, and under it a layer over the
-- whole view that closes the list when clicked.
local function BuildList(window, view)
    local catcher = CreateFrame("Button", nil, view)

    catcher:SetAllPoints(view)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetScript("OnClick", function() CloseList(window) end)
    catcher:Hide()
    local list = CreateFrame("Frame", nil, view, "BackdropTemplate")

    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetFrameLevel(catcher:GetFrameLevel() + 10)
    list:SetBackdrop({ bgFile = Solid, edgeFile = Solid, edgeSize = 1 })
    list:SetBackdropColor(0.08, 0.08, 0.11, 0.98)
    list:SetBackdropBorderColor(1, 0.82, 0, 1)
    list:EnableMouse(true)
    list:Hide()
    list.Catcher, list.Options = catcher, {}
    window.Dropdown = list
end

-- Watches the shown page's rows while the view shows, refreshing them now: a hidden view, and every other page, cost
-- nothing when their rows change.
local function Follow(window)
    local state = window.m_addon.State
    local watchers = window.m_watchers

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

-- Creates a flat button with a label, the window's one button style.
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

-- Builds the window: the backdrop, the title (dragging moves the window), and the close button.
local function BuildFrame(window)
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")

    window.Frame = frame
    frame:SetFrameStrata("DIALOG")
    frame:SetWidth(Width)
    frame:SetPoint("CENTER")

    frame:SetBackdrop({ bgFile = Solid, edgeFile = Border, edgeSize = 16,
        insets = { bottom = 4, left = 4, right = 4, top = 4 } })

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

--- Creates the window. Its frame is built the first time it shows.
---@param addon table the AddOn
---@param pages table[] ByteTerrace.SettingsPages(addon)
---@return table window
local function NewSettingsWindow(addon, pages)
    local window = setmetatable({
        Canvases = {}, Controls = {}, m_addon = addon, m_containers = {}, m_controlWidth = ControlWidth, m_heights = {},
        m_labelWidth = 0, m_navButtons = {}, m_offset = 0, m_page = 1, m_range = 0, m_rows = {}, m_watchers = {},
        Pages = pages,
    }, SettingsWindow)

    return window
end

-- Scrolls the page to offset, snapped to a whole row within the page (and that to whole pixels), and moves the scroll
-- bar's thumb there. An open dropdown closes rather than float away from its control.
local function ScrollTo(window, offset)
    CloseList(window)
    offset = max(0, min(floor((offset / RowHeight) + 0.5) * RowHeight, window.m_range))
    window.m_offset = offset
    -- The page moves by whole screen pixels: a row is rarely whole pixels at the UI's scale, and a fraction of one
    -- would blur or drop the controls' 1-pixel borders.
    -- secret: the scroll frame's scale is the UI's own, a plain number
    window.Scroll:SetVerticalScroll(PixelUtil.GetNearestPixelSize(offset, window.Scroll:GetEffectiveScale()))
    window.ScrollBar:SetValue(offset)
end

-- Shows page i: its container, its nav button marked, the window sized to fit it (up to the screen, less a margin), the
-- page scrolled to its top, and its rows followed.
local function ShowPage(window, index)
    window.m_page = index
    CloseList(window)

    for i, container in ipairs(window.m_containers) do
        container:SetShown(i == index)

        window.m_navButtons[i]:SetBackdropBorderColor(((i == index) and 1) or 0.42, ((i == index) and 0.82) or 0.4,
            ((i == index) and 0) or 0.5, 1)
    end

    local height = window.m_heights[index]

    if window.m_host == window.Frame then
        -- secret: UIParent is the client's own screen-sized frame, anchored to nothing an addon sets
        local room = (((UIParent:GetHeight() - (2 * ScreenMargin)) - TitleHeight) - Pad)
        local navHeight = (#window.Pages * NavButtonHeight)

        window.Frame:SetHeight((TitleHeight + min(max(height, navHeight), floor(room / RowHeight) * RowHeight)) + Pad)
    end

    local scroll = window.Scroll

    -- The scroll frame takes as many whole rows as the view has room for.
    -- secret: the view is the addon's own, sized by its anchors to the host
    window.m_viewHeight = (floor(window.View:GetHeight() / RowHeight) * RowHeight)
    scroll:SetHeight(window.m_viewHeight)
    -- secret: plain, as above
    window.Content:SetWidth(scroll:GetWidth())
    window.Content:SetHeight(height)
    -- secret: plain, as above
    window.m_range = max(0, height - window.m_viewHeight)
    -- The scroll bar shows while the page scrolls, its thumb as much of it as the page shows.
    local bar = window.ScrollBar
    local view = window.m_viewHeight
    local range = window.m_range

    bar:SetShown(range > 0)
    window.Thumb:SetHeight(max(ThumbFloor, floor((view * view) / (view + range))))
    bar:SetMinMaxValues(0, range)
    ScrollTo(window, 0)
    Follow(window)
end

-- Returns a number one step from value. With a step, it moves along the row's grid (multiples of step from min) and
-- stops at the last grid value inside the bounds, so State always admits it. Without one, it moves by 1 and stops at
-- min and max.
local function StepNumber(spec, value, delta)
    local low = spec.min
    local high = spec.max
    local step = spec.step

    if not step then
        local stepped = (value + delta)

        return ((low and (stepped < low) and low) or (high and (stepped > high) and high) or stepped)
    end

    local base = (low or 0)
    local index = (floor(((value - base) / step) + 0.5) + delta)

    if high then
        index = min(index, floor(((high - base) / step) + 1e-9))
    end

    if low then
        index = max(index, 0)
    end

    return (base + (index * step))
end

-- Returns a value as the window shows it: an enum's label, or a number without trailing zeros. Only enums and numbers
-- show text. A boolean shows a check.
local function ValueText(spec, value)
    if spec.values then
        return ((spec.valueLabels and spec.valueLabels[value]) or tostring(value))
    end

    return ("%g"):format(value)
end

-- Measures the view's text before its rows are built: the controls' column fits the widest dropdown choice (at least
-- ControlWidth), and m_labelWidth is the longest setting label, which the window makes room for.
local function Measure(window, view)
    local label = view:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local choice = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local labelWidth = 0
    local choiceWidth = 0

    label:Hide()
    choice:Hide()

    for _, page in ipairs(window.Pages) do
        for _, entry in ipairs(page.entries) do
            local spec = entry.spec

            if spec then
                label:SetText(spec.label)
                -- secret: the labels are the rows' own, plain strings
                labelWidth = max(labelWidth, label:GetUnboundedStringWidth())

                for _, value in ipairs(spec.values or {}) do
                    choice:SetText(ValueText(spec, value))
                    -- secret: plain, as above
                    choiceWidth = max(choiceWidth, choice:GetUnboundedStringWidth())
                end
            end
        end
    end

    window.m_labelWidth = ceil(labelWidth)
    window.m_controlWidth = max(ControlWidth, ceil(choiceWidth) + DropdownInset)
end

-- Writes a row from the window: one batch, refused with a message while the row is locked.
local function Write(window, entry, value)
    local addon = window.m_addon
    local state = window.m_addon.State

    if state:IsLocked(entry.id) then
        addon:Print(entry.spec.label .. " is locked.")

        return
    end

    addon:Batch(function()
        state:Set(entry.id, value)
    end)
end

-- Opens the dropdown list under a dropdown's control: an option per value, the current one checked, as wide as its
-- widest label needs. Picking one writes it and closes the list. Selecting the open dropdown again closes it. A locked
-- row says so instead.
local function OpenList(window, entry, control)
    local list = window.Dropdown
    local spec = entry.spec
    local id = entry.id
    local state = window.m_addon.State

    if list.m_id == id then
        CloseList(window)

        return
    end

    if state:IsLocked(id) then
        window.m_addon:Print(spec.label .. " is locked.")

        return
    end

    local width = window.m_controlWidth

    for i, value in ipairs(spec.values) do
        local option = list.Options[i]

        if not option then
            option = NewButton(list, width)
            option.Label:ClearAllPoints()
            option.Label:SetPoint("LEFT", 22, 0)
            option.Check = option:CreateTexture(nil, "ARTWORK")
            option.Check:SetTexture(Solid)
            option.Check:SetVertexColor(1, 0.82, 0, 1)
            option.Check:SetSize(8, 8)
            option.Check:SetPoint("LEFT", 8, 0)
            option:SetPoint("TOPLEFT", 1, -(1 + ((i - 1) * OptionHeight)))
            list.Options[i] = option
        end

        option.Label:SetText(ValueText(spec, value))
        option.Check:SetShown(value == state.Values[id])

        option:SetScript("OnClick", function()
            CloseList(window)
            Write(window, entry, value)
        end)

        option:Show()
        -- secret: option labels are the row's own value labels, plain strings
        width = max(width, option.Label:GetStringWidth() + 34)
    end

    for i = (#spec.values + 1), #list.Options do
        list.Options[i]:Hide()
    end

    for i = 1, #spec.values do
        list.Options[i]:SetWidth(width)
    end

    list:SetSize(width + 2, (#spec.values * OptionHeight) + 2)
    list:ClearAllPoints()
    list:SetPoint("TOPRIGHT", control, "BOTTOMRIGHT", 0, -2)
    list.m_id = id
    list.Catcher:Show()
    list:Show()
end

-- Builds one setting row's label and control, and returns the function that shows its value.
local function BuildRow(window, row, entry)
    local state = window.m_addon.State
    local spec = entry.spec
    local id = entry.id
    local width = window.m_controlWidth
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

    label:SetPoint("LEFT", 0, 0)
    label:SetPoint("RIGHT", -(width + LabelGap), 0)
    label:SetJustifyH("LEFT")
    label:SetText(spec.label)
    row:EnableMouse(true)
    AttachTooltip(row, spec)
    local control
    local Refresh

    if spec.kind == "boolean" then
        control = NewButton(row, 22)
        control:SetPoint("RIGHT", -(width - 22), 0)
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
        control = NewButton(row, width)
        control:SetPoint("RIGHT")
        control.Label:ClearAllPoints()
        control.Label:SetPoint("LEFT", 8, 0)
        control.Label:SetPoint("RIGHT", -24, 0)
        control.Label:SetJustifyH("LEFT")
        control.Label:SetWordWrap(false)
        AddChevron(control)
        control:SetScript("OnClick", function() OpenList(window, entry, control) end)

        Refresh = function()
            control.Label:SetText(ValueText(spec, state.Values[id]))
        end
    else
        control = CreateFrame("Frame", nil, row)
        control:SetSize(width, 22)
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
        label:SetAlpha((state:IsLocked(id) and 0.5) or 1)
    end
end

-- Builds page index's rows in their own container, and returns the container's height. Each row goes in m_rows[index]
-- as { watched = its row and lock ids, refresh }.
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

            header:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 0, -((y + RowHeight) - HeaderDrop))
            header:SetText(entry.header)
            y = (y + RowHeight)
        else
            local row = CreateFrame("Frame", nil, container)

            row:SetPoint("TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", 0, -y)
            row:SetHeight(RowHeight)
            local watched = { entry.id }

            if entry.spec.lockId then
                watched[2] = entry.spec.lockId
            end

            rows[#rows + 1] = { refresh = BuildRow(window, row, entry), watched = watched }
            y = (y + RowHeight)
        end
    end

    container:SetHeight(y)
    container:Hide()

    return container, y
end

-- Builds the view: the window's page list, and every page in a scroll frame with its thumb, on a frame either host can
-- hold.
local function BuildView(window)
    local view = CreateFrame("Frame", nil, UIParent)

    window.View = view
    view:Hide()
    view:SetScript("OnShow", function() Follow(window) end)

    view:SetScript("OnHide", function()
        CloseList(window)
        Follow(window)
    end)

    Measure(window, view)
    local nav = CreateFrame("Frame", nil, view)

    window.Nav = nav
    nav:SetPoint("TOPLEFT")
    nav:SetSize(NavWidth, #window.Pages * NavButtonHeight)
    local scroll = CreateFrame("ScrollFrame", nil, view)

    window.Scroll = scroll
    scroll:SetPoint("TOPRIGHT", -(ScrollGap + ScrollBarWidth), 0)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) ScrollTo(window, window.m_offset - (delta * RowHeight)) end)
    local content = CreateFrame("Frame", nil, scroll)

    window.Content = content
    scroll:SetScrollChild(content)
    -- The scroll bar is the client's own slider, so dragging its thumb is the client's: it steps a row at a time, and
    -- each step scrolls the page there. The wheel scrolls over it too.
    local bar = CreateFrame("Slider", nil, view)

    window.ScrollBar = bar
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(ScrollBarWidth)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", ScrollGap, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", ScrollGap, 0)
    bar:SetValueStep(RowHeight)
    bar:SetObeyStepOnDrag(true)
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", function(_, delta) ScrollTo(window, window.m_offset - (delta * RowHeight)) end)

    -- A drag moves the page; ScrollTo's own SetValue comes back at the offset it set, which is done already.
    bar:SetScript("OnValueChanged", function(_, value)
        -- secret: the value is the addon's own slider's, a plain number
        if value ~= window.m_offset then
            ScrollTo(window, value)
        end
    end)

    local track = bar:CreateTexture(nil, "BACKGROUND")

    track:SetAllPoints(bar)
    track:SetTexture(Solid)
    track:SetVertexColor(1, 0.82, 0, 0.15)
    local thumb = bar:CreateTexture(nil, "ARTWORK")

    window.Thumb = thumb
    thumb:SetTexture(Solid)
    thumb:SetVertexColor(1, 0.82, 0, 0.8)
    thumb:SetWidth(ScrollBarWidth)
    bar:SetThumbTexture(thumb)

    for i, page in ipairs(window.Pages) do
        local button = NewButton(nav, NavWidth, page.name)

        button:SetPoint("TOPLEFT", 0, -((i - 1) * NavButtonHeight))
        button:SetScript("OnClick", function() ShowPage(window, i) end)
        window.m_navButtons[i] = button
        window.m_containers[i], window.m_heights[i] = BuildPage(window, content, page, i)
    end

    BuildList(window, view)
end

-- Moves the view into a host (the window or a canvas) and shows a page there, refreshed. The window has the view's own
-- page list; in Blizzard's panel, its list of categories picks the page. The window the view leaves closes, rather than
-- standing empty.
local function Present(window, host, page)
    if not window.View then
        BuildView(window)
    end

    local view = window.View

    if window.m_host ~= host then
        if (window.m_host == window.Frame) and window.Frame then
            window.Frame:Hide()
        end

        local framed = (host == window.Frame)

        window.m_host = host
        view:SetParent(host)
        view:ClearAllPoints()

        if framed then
            view:SetPoint("TOPLEFT", Pad, -TitleHeight)
            view:SetPoint("BOTTOMRIGHT", -Pad, Pad)

            host:SetWidth(max(Width, ((((((((Pad + NavWidth) + Pad) + window.m_labelWidth) + LabelGap)
                + window.m_controlWidth) + ScrollGap) + ScrollBarWidth) + Pad)))
        else
            view:SetPoint("TOPLEFT", CanvasInset, -CanvasInset)
            view:SetPoint("BOTTOMRIGHT", -CanvasInset, CanvasInset)
        end

        window.Nav:SetShown(framed)
        window.Scroll:SetPoint("TOPLEFT", (framed and (NavWidth + Pad)) or 0, 0)
    end

    ShowPage(window, page or window.m_page)
    view:Show()
end

--- Hides the window. When Blizzard's panel shows one of the canvases, the view goes back to it.
function SettingsWindow:Hide()
    if self.Frame then
        self.Frame:Hide()
    end

    for i, canvas in ipairs(self.Canvases) do
        if canvas:IsVisible() and (self.m_host ~= canvas) then
            Present(self, canvas, i)

            return
        end
    end
end

--- Returns whether the window shows.
---@return boolean
function SettingsWindow:IsShown()
    return ((self.Frame ~= nil) and self.Frame:IsShown())
end

--- Returns the index of the page the view shows (or last showed).
---@return integer
function SettingsWindow:Page()
    return self.m_page
end

--- Registers a canvas page per settings page with Blizzard's settings panel, under Esc > Options > AddOns: the main
--- page as the addon's category, and every other page as a subcategory under it. Controller focus is kept out of each
--- (see the header).
function SettingsWindow:Register()
    local category

    for i, page in ipairs(self.Pages) do
        local canvas = CreateFrame("Frame", nil, UIParent)

        self.Canvases[i] = canvas
        canvas:Hide()
        -- SmartNavigation_IsFrameIgnored skips the canvas and its children.
        canvas.smartNavigationIgnored = true
        canvas:SetScript("OnShow", function() Present(self, canvas, i) end)

        if category then
            Settings.RegisterCanvasLayoutSubcategory(category, canvas, page.name)
        else
            category = Settings.RegisterCanvasLayoutCategory(canvas, self.m_addon.Title)
        end
    end

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

--- Shows the window if it's hidden, and otherwise hides it.
function SettingsWindow:Toggle()
    if self:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

ByteTerrace.NewSettingsWindow = NewSettingsWindow
