-- The addon's settings view (ByteTerrace_Core/SettingsWindow.lua): its two hosts, page layout, controls, state changes,
-- scrolling, and bare slash commands. Blizzard's panel gets a canvas page per settings page, each ignored by the
-- controller UI, and no setting controls, whose focus freezes the client on close (tools/api/forbidden.json).

local function NewAddOn()
    local h = Harness.New()

    h:LoadFiles("ByteTerrace_Core")
    h.declared.TestDB = true

    local addon = h.env.ByteTerrace.NewAddOn({ name = "TestApp", savedVariable = "TestDB", slash = { "/test" },
        title = "Test App" })

    addon:Module("Meter", { description = "A meter.", label = "Meter",
        state = {
            { default = "wide", kind = "string", label = "Size", name = "size",
                valueLabels = { wide = "Wide", wider = "Wider", widest = "Widest" },
                values = { "wide", "wider", "widest" } },
            { default = 0.5, kind = "number", label = "Volume", max = 1, min = 0, name = "volume", step = 0.25 },
        } })

    addon:Module("Riddles", { label = "Riddles", page = "Riddles", state = {
        { default = false, kind = "boolean", name = "locked", persist = false },
        { default = 30, kind = "number", label = "Minutes", lockedBy = "Riddles.locked", max = 120, min = 10,
            name = "minutes", step = 5 },
    } })

    h:Fire("ADDON_LOADED", "TestApp", false)

    return h, addon
end

test("the bare command toggles the window, in combat too, and never opens Blizzard's panel", function()
    local h, addon = NewAddOn()
    local window = addon.SettingsWindow

    falsy(window:IsShown())
    h:EnterCombat()
    h:Slash("/test")
    truthy(window:IsShown(), "shown during combat lockdown")
    eq(window.Frame.Title:GetText(), "Test App")
    h:Slash("/test")
    falsy(window:IsShown(), "the command hides it again")
    eq(#h.opened, 0, "Blizzard's settings panel is never opened")
end)

test("Blizzard's panel lists the main page as the addon's category and every other page under it", function()
    local h, addon = NewAddOn()
    local window = addon.SettingsWindow

    eq(h.category.name, "Test App")
    eq(h.category, h.categories[1], "the main page is the category the AddOns list shows")
    eq(#h.categories, 2, "one category per page")
    eq(h.categories[2].name, "Riddles")
    eq(h.categories[2].parent, h.categories[1], "the Riddles page is listed under the addon")

    for i, category in ipairs(h.categories) do
        eq(category.canvas, window.Canvases[i], "page " .. i .. " is the view's canvas " .. i)
        -- Blizzard setting controls, whose focus freezes the client for controller players, aren't in the harness.
        truthy(category.canvas.smartNavigationIgnored, "SmartNavigation ignores canvas " .. i .. " and every child")
    end
end)

test("selecting a page in Blizzard's list shows that page in the panel, without the view's own page list", function()
    local h, addon = NewAddOn()
    local window = addon.SettingsWindow
    local state = addon.State

    h:SelectSettingsCategory(h.categories[2])
    truthy(window.Controls[state:Id("Riddles.minutes")]:IsVisible(), "the Riddles page shows")
    falsy(window.Controls[state:Id("Meter.size")]:IsVisible(), "the main page doesn't")
    eq(window:Page(), 2)
    falsy(window.Nav:IsVisible(), "Blizzard's list is the page list; the view doesn't repeat it")
    h:SelectSettingsCategory(h.categories[1])
    truthy(window.Controls[state:Id("Meter.size")]:IsVisible(), "selecting the addon shows the main page")
    falsy(window.Controls[state:Id("Riddles.minutes")]:IsVisible())
    eq(window:Page(), 1)
end)

test("the view moves to whichever host shows it, and works in both", function()
    local h, addon = NewAddOn()
    local window = addon.SettingsWindow
    local state = addon.State

    h:SelectSettingsCategory(h.categories[1])
    local box = window.Controls[state:Id("Meter.enabled")]

    truthy(box:IsVisible(), "the canvas shows the view")
    box:Click()
    falsy(state:Get("Meter.enabled"))
    h.env.SettingsPanel:Hide()
    window:Show()
    truthy(box:IsVisible(), "the window shows the same view")
    truthy(window.Nav:IsVisible(), "with its own page list")
    falsy(box.Check:IsShown(), "and the change made on the canvas")
    window:Hide()
    h:SelectSettingsCategory(h.categories[1])
    truthy(box:IsVisible(), "back on the canvas")
    eq(h:CountCalls("SetParent") > 0, true)
end)

test("the toolkit registers a canvas page per settings page and no Blizzard setting controls", function()
    local h = Harness.New()
    local addon = h:LoadAddon("TheLanKrewToolKit").Addon
    local window = addon.SettingsWindow

    eq(h.category.name, addon.Title)
    eq(#h.categories, #window.Pages)

    for i, page in ipairs(window.Pages) do
        eq(h.categories[i].name, page.name)
        eq(h.categories[i].parent, ((i > 1) and h.category) or nil, page.name)
        truthy(h.categories[i].canvas.smartNavigationIgnored, page.name)
    end
end)

-- An addon whose "Long" page holds count settings, more than any host shows at once.
local function NewLongAddOn(count)
    local h = Harness.New()

    h:LoadFiles("ByteTerrace_Core")
    h.declared.TestDB = true
    local addon = h.env.ByteTerrace.NewAddOn({ name = "TestApp", savedVariable = "TestDB", slash = { "/test" }, title = "Test App" })
    local state = {}

    for i = 1, count do
        state[i] = { default = false, kind = "boolean", label = ("Setting %02d"):format(i), name = ("s%02d"):format(i) }
    end

    addon:Module("Long", { label = "Long", page = "Long", state = state, toggle = false })
    addon:Module("Short", { label = "Short", page = "Short" })
    h:Fire("ADDON_LOADED", "TestApp", false)

    return h, addon
end

test("a page taller than the panel scrolls inside it, clipped, rather than running past its edge", function()
    local h, addon = NewLongAddOn(40)
    local window = addon.SettingsWindow
    local canvas = h.env.SettingsPanel.Container.SettingsCanvas

    h:SelectSettingsCategory(h.categories[2])
    eq(window:Page(), 2)
    eq(Harness.State(window.Scroll).scrollChild, window.Content, "the page is the scroll frame's child, which clips it")
    truthy(h:WidgetHeight(window.Scroll) <= h:WidgetHeight(canvas), "the scroll frame fits the panel")
    truthy(h:WidgetWidth(window.Scroll) <= h:WidgetWidth(canvas))
    eq(h:WidgetWidth(window.Content), h:WidgetWidth(window.Scroll), "the page is as wide as what shows it")
    local range = (h:WidgetHeight(window.Content) - h:WidgetHeight(window.Scroll))

    truthy(range > 0, "40 settings don't fit")
    truthy(window.Thumb:IsVisible(), "the thumb shows there's more")
    truthy(h:MouseWheel(window.Scroll, -1), "the wheel scrolls the page")
    eq(window.Scroll:GetVerticalScroll(), 28, "a row a notch")
    h:MouseWheel(window.Scroll, 1)
    h:MouseWheel(window.Scroll, 1)
    eq(window.Scroll:GetVerticalScroll(), 0, "and stops at the top")

    for _ = 1, 100 do
        h:MouseWheel(window.Scroll, -1)
    end

    eq(window.Scroll:GetVerticalScroll(), range, "and at the bottom, the last setting in view")
    h:SelectSettingsCategory(h.categories[3])
    eq(window.Scroll:GetVerticalScroll(), 0, "another page starts at its top")
    falsy(window.Thumb:IsVisible(), "a page that fits shows no thumb")
    h:MouseWheel(window.Scroll, -1)
    eq(window.Scroll:GetVerticalScroll(), 0, "and doesn't scroll")
end)

test("the window never grows past the screen: a long page scrolls in it", function()
    local h, addon = NewLongAddOn(40)
    local window = addon.SettingsWindow

    window:Show(2)
    truthy(window.Frame:GetHeight() <= h.env.UIParent:GetHeight(), "the window fits the screen")
    eq(Harness.State(window.Scroll).scrollChild, window.Content)
    truthy(h:WidgetHeight(window.Content) > h:WidgetHeight(window.Scroll), "the page scrolls")
    truthy(window.Thumb:IsVisible())
    h:MouseWheel(window.Scroll, -1)
    eq(window.Scroll:GetVerticalScroll(), 28)
    window:Show(3)
    truthy(window.Frame:GetHeight() < h.env.UIParent:GetHeight(), "a short page makes a short window")
    falsy(window.Thumb:IsVisible())
end)

test("scrolling closes an open dropdown rather than leaving it floating", function()
    local h, addon = NewAddOn()
    local window = addon.SettingsWindow

    window:Show()
    h:Click(window.Controls[addon.State:Id("Meter.size")])
    truthy(window.Dropdown:IsShown())
    h:MouseWheel(window.Scroll, -1)
    falsy(window.Dropdown:IsShown())
end)

-- The label of the row that holds a control: the row's first font string.
local function RowLabel(control)
    return (select(1, control:GetParent():GetRegions()))
end

-- A value as a dropdown names it.
local function ValueLabel(spec, value)
    return ((spec.valueLabels and spec.valueLabels[value]) or tostring(value))
end

test("each toolkit setting's label and every dropdown choice fit, in the window and in Blizzard's panel", function()
    local h = Harness.New()
    local addon = h:LoadAddon("TheLanKrewToolKit").Addon
    local window = addon.SettingsWindow
    local state = addon.State

    local function Fits(where)
        for i, page in ipairs(window.Pages) do
            if where == "panel" then h:SelectSettingsCategory(h.categories[i]) else window:Show(i) end

            for _, entry in ipairs(page.entries) do
                local control = (entry.id and window.Controls[entry.id])

                if control then
                    local label = RowLabel(control)
                    local name = (where .. ": " .. entry.name)

                    truthy(label:GetUnboundedStringWidth() <= h:WidgetWidth(label), name .. "'s label fits")

                    for _, value in ipairs(entry.spec.values or {}) do
                        control.Label:SetText(ValueLabel(entry.spec, value))

                        truthy(control.Label:GetUnboundedStringWidth() <= h:WidgetWidth(control.Label),
                            name .. " shows " .. ValueLabel(entry.spec, value) .. " whole")
                    end

                    if entry.spec.values then
                        control.Label:SetText(ValueLabel(entry.spec, state.Values[entry.id]))
                    end
                end
            end
        end
    end

    Fits("window")
    window:Hide()
    Fits("panel")
end)

test("window and external writes each refresh the changed control once", function()
    local h, addon = NewAddOn()
    local window = addon.SettingsWindow
    local state = addon.State

    window:Show()
    local box = window.Controls[state:Id("Meter.enabled")]

    truthy(box.Check:IsShown(), "on by default")
    local calls = Harness.State(box.Check).calls.SetShown

    box:Click()
    falsy(state:Get("Meter.enabled"), "the checkbox flips its row")
    eq(Harness.State(box.Check).calls.SetShown, calls + 1)
    falsy(box.Check:IsShown())
    h:Slash("/test toggle Meter.enabled")
    eq(Harness.State(box.Check).calls.SetShown, calls + 2)
    truthy(box.Check:IsShown(), "a slash change refreshes the open window")
end)

-- The open dropdown list's option labels, in order, with the checked one in brackets.
local function Options(window)
    local texts = {}

    for _, option in ipairs(window.Dropdown.Options) do
        if option:IsShown() then
            local text = option.Label:GetText()

            texts[#texts + 1] = ((option.Check:IsShown() and ("[" .. text .. "]")) or text)
        end
    end

    return table.concat(texts, " ")
end

test("an enum is a dropdown: a click lists every value with the current one checked, and picking one sets it", function()
    local h, addon = NewAddOn()
    local window = addon.SettingsWindow
    local state = addon.State

    window:Show()
    local button = window.Controls[state:Id("Meter.size")]
    local list = window.Dropdown

    eq(button.Label:GetText(), "Wide")
    falsy(list:IsShown(), "closed until clicked")
    truthy(h:Click(button))
    truthy(list:IsVisible(), "a click opens the list")
    eq(Options(window), "[Wide] Wider Widest")
    truthy(h:Click(list.Options[3]))
    eq(state:Get("Meter.size"), "widest")
    eq(button.Label:GetText(), "Widest")
    falsy(list:IsShown(), "picking closes it")
    h:Click(button)
    eq(Options(window), "Wide Wider [Widest]", "the new value is the checked one")
    h:Click(button)
    falsy(list:IsShown(), "clicking the dropdown again closes it")
    h:Click(button)
    truthy(h:Click(list.Catcher), "the view behind the list takes the click")
    falsy(list:IsShown(), "a click elsewhere on the view closes it")
    eq(state:Get("Meter.size"), "widest", "and changes nothing")
    h:Click(button)
    window:Show(2)
    falsy(list:IsShown(), "another page closes it")
    window:Show(1)
    h:Click(button)
    window:Hide()
    falsy(list:IsShown(), "hiding the view closes it")
end)

test("number steppers move by the row's step and stop at its bounds", function()
    local _, addon = NewAddOn()
    local window = addon.SettingsWindow
    local state = addon.State

    window:Show()
    local control = window.Controls[state:Id("Meter.volume")]

    eq(control.Label:GetText(), "0.5")
    control.Plus:Click()
    control.Plus:Click()
    control.Plus:Click()
    eq(state:Get("Meter.volume"), 1, "stops at max")
    eq(control.Label:GetText(), "1")

    for _ = 1, 6 do
        control.Minus:Click()
    end

    eq(state:Get("Meter.volume"), 0, "stops at min")
end)

test("the page list switches pages, and the window fits the page it shows", function()
    local _, addon = NewAddOn()
    local window = addon.SettingsWindow
    local state = addon.State

    window:Show()
    local minutes = window.Controls[state:Id("Riddles.minutes")]

    falsy(minutes:IsVisible(), "the Riddles page is hidden")
    local mainHeight = window.Frame:GetHeight()

    window:Show(2)
    eq(window:Page(), 2)
    truthy(minutes:IsVisible())
    falsy(window.Controls[state:Id("Meter.size")]:IsVisible())
    truthy(window.Frame:GetHeight() < mainHeight, "a shorter page makes a shorter window")
    window:Hide()
    window:Show()
    eq(window:Page(), 2, "it reopens on the last page shown")
end)

test("a hidden window, or a page not shown, costs nothing when its rows change", function()
    local h, addon = NewAddOn()
    local window = addon.SettingsWindow
    local state = addon.State

    window:Show()
    window:Hide()
    h:ResetCalls()
    state:Set("Meter.size", "wider")
    state:Set("Meter.enabled", false)
    eq(h:CountCalls("SetText") + h:CountCalls("SetShown"), 0, "the hidden window does no widget work")
    eq(h:CountCalls("IsVisible"), 0, "nothing asks whether the hidden window shows")
    window:Show(1)
    eq(window.Controls[state:Id("Meter.size")].Label:GetText(), "Wider", "shown values catch up when it opens")
    falsy(window.Controls[state:Id("Meter.enabled")].Check:IsShown())
    h:ResetCalls()
    state:Set("Riddles.minutes", 40)
    eq(h:CountCalls("SetText") + h:CountCalls("IsVisible"), 0, "a row on a page not shown")
    h:ResetCalls()
    window:Show(2)
    eq(window.Controls[state:Id("Riddles.minutes")].Label:GetText(), "40", "it catches up when its page shows")
    eq(h:CountCalls("SetText"), 1, "showing a page refreshes only its own rows")
end)

test("hovering a setting shows its label and description; leaving hides them", function()
    local h, addon = NewAddOn()
    local window = addon.SettingsWindow
    local state = addon.State

    window:Show()
    local tooltip = h.env.GameTooltip

    truthy(h:Hover(window.Controls[state:Id("Meter.enabled")]))
    eq(table.concat(Harness.State(tooltip).lines, "|"), "Meter|A meter.")
    eq(tooltip:GetOwner(), window.Controls[state:Id("Meter.enabled")])
    truthy(tooltip:IsShown())
    truthy(h:Hover(window.Controls[state:Id("Meter.size")]))
    eq(table.concat(Harness.State(tooltip).lines, "|"), "Size", "a setting without a description shows its label")
    truthy(h:Hover(window.Controls[state:Id("Meter.size")], false))
    falsy(tooltip:IsShown())
end)

test("the page list's buttons switch pages, and the close button closes the window", function()
    local h, addon = NewAddOn()
    local window = addon.SettingsWindow

    window:Show()
    local riddles

    for _, child in ipairs({ window.Nav:GetChildren() }) do
        if child.Label:GetText() == "Riddles" then
            riddles = child
        end
    end

    truthy(h:Click(riddles), "the Riddles button is in the page list")
    eq(window:Page(), 2)
    truthy(window.Controls[addon.State:Id("Riddles.minutes")]:IsVisible())
    truthy(h:Click(window.Frame.Close))
    falsy(window:IsShown())
end)

test("the window can be dragged by its frame", function()
    local h, addon = NewAddOn()
    local window = addon.SettingsWindow

    window:Show()
    local _, _, _, x, y = window.Frame:GetPoint(1)

    h:Drag(window.Frame, 40, -20)
    local _, _, _, movedX, movedY = window.Frame:GetPoint(1)

    truthy((movedX ~= x) or (movedY ~= y), "it moved")
end)

test("the view moving into Blizzard's panel closes the window rather than leaving it empty", function()
    local h, addon = NewAddOn()
    local window = addon.SettingsWindow

    window:Show()
    h:SelectSettingsCategory(h.categories[1])
    falsy(window:IsShown(), "no empty window over the panel")
    truthy(window.Controls[addon.State:Id("Meter.enabled")]:IsVisible(), "the panel shows the settings")
end)

test("closing the window while Blizzard's panel shows gives the panel its page back", function()
    local h, addon = NewAddOn()
    local window = addon.SettingsWindow

    h:SelectSettingsCategory(h.categories[2])
    window:Show(1)
    window:Hide()
    local minutes = window.Controls[addon.State:Id("Riddles.minutes")]

    truthy(minutes:IsVisible(), "not a blank page: the Riddles page the panel had selected")
    eq(window.View:GetParent(), window.Canvases[2])
    eq(window:Page(), 2)
    falsy(window.Nav:IsVisible())
end)

test("number steppers stay on the row's grid and inside its bounds, whatever the bounds", function()
    local h = Harness.New()

    h:LoadFiles("ByteTerrace_Core")
    h.declared.TestDB = true
    local addon = h.env.ByteTerrace.NewAddOn({ name = "TestApp", savedVariable = "TestDB", slash = { "/test" }, title = "Test App" })

    addon:Module("M", { state = {
            { default = 0.8, kind = "number", label = "Share", max = 1, min = 0, name = "share", step = 0.4 },
            { default = 2, kind = "number", label = "Free", max = 2.5, min = 0.5, name = "free" },
        },
        toggle = false })

    h:Fire("ADDON_LOADED", "TestApp", false)
    local window = addon.SettingsWindow
    local state = addon.State

    window:Show()
    window.Controls[state:Id("M.share")].Plus:Click()
    eq(state:Get("M.share"), 0.8, "1.2 would pass max: the last step on the grid is 0.8")
    local free = window.Controls[state:Id("M.free")]

    free.Plus:Click()
    eq(state:Get("M.free"), 2.5, "no step: up to max")
    free.Minus:Click()
    free.Minus:Click()
    eq(state:Get("M.free"), 0.5, "and down to min, on no grid")
    free.Plus:Click()
    eq(state:Get("M.free"), 1.5)
end)

test("a module whose page is the addon's own title joins the main page", function()
    local h = Harness.New()

    h:LoadFiles("ByteTerrace_Core")
    h.declared.TestDB = true
    local addon = h.env.ByteTerrace.NewAddOn({ name = "TestApp", savedVariable = "TestDB", slash = { "/test" }, title = "Test App" })

    addon:Module("M", { label = "M", page = "Test App" })
    h:Fire("ADDON_LOADED", "TestApp", false)
    eq(#addon.SettingsWindow.Pages, 1)
end)
