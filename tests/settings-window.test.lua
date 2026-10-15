-- The addon's settings view (ByteTerrace_Core/SettingsWindow.lua): its two hosts, page layout,
-- controls, state changes and bare slash commands. Blizzard's panel gets one canvas page that the
-- controller UI ignores and no setting controls, whose focus freezes the client on close
-- (tools/api/forbidden.json).

local function NewAddOn()
    local h = Harness.New()
    h:LoadFiles("ByteTerrace_Core")
    h.declared.TestDB = true
    local addon = h.env.ByteTerrace.NewAddOn({ name = "TestApp", title = "Test App", savedVariable = "TestDB",
        slash = { "/test" } })
    addon:Module("Meter", { label = "Meter", description = "A meter.", state = {
        { name = "size", kind = "string", default = "wide", values = { "wide", "wider", "widest" },
            valueLabels = { wide = "Wide", wider = "Wider", widest = "Widest" }, label = "Size" },
        { name = "volume", kind = "number", default = 0.5, min = 0, max = 1, step = 0.25, label = "Volume" },
    } })
    addon:Module("Riddles", { label = "Riddles", page = "Riddles", state = {
        { name = "locked", kind = "boolean", default = false, persist = false },
        { name = "minutes", kind = "number", default = 30, min = 10, max = 120, step = 5, label = "Minutes",
            lockedBy = "Riddles.locked" },
    } })
    h:Fire("ADDON_LOADED", "TestApp")
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

test("Blizzard's panel gets one canvas page, kept out of controller focus, and no controls of its own", function()
    local h, addon = NewAddOn()
    local window = addon.SettingsWindow
    eq(h.category.name, "Test App")
    eq(h.category.canvas, window.Canvas, "the page is the view's canvas")
    truthy(window.Canvas.smartNavigationIgnored, "SmartNavigation ignores the canvas and every child")
    -- Blizzard setting controls, whose focus froze controller players, aren't in the harness at all.
    eq(#h.categories, 1, "one page; the view draws its own subpages")
end)

test("the view moves to whichever host shows it, and works in both", function()
    local h, addon = NewAddOn()
    local window, state = addon.SettingsWindow, addon.State
    window.Canvas:Show()
    local box = window.Controls[state:Id("Meter.enabled")]
    truthy(box:IsVisible(), "the canvas shows the view")
    box:Click()
    falsy(state:Get("Meter.enabled"))
    window.Canvas:Hide()
    window:Show()
    truthy(box:IsVisible(), "the window shows the same view")
    falsy(box.Check:IsShown(), "and the change made on the canvas")
    window:Hide()
    window.Canvas:Show()
    truthy(box:IsVisible(), "back on the canvas")
    eq(h:CountCalls("SetParent") > 0, true)
end)

test("the toolkit registers its canvas page and no Blizzard setting controls", function()
    local h = Harness.New()
    local addon = h:LoadAddon("TheLanKrewToolKit").Addon
    eq(h.category.name, addon.Title)
    truthy(addon.SettingsWindow.Canvas.smartNavigationIgnored)
    eq(#h.categories, 1)
end)

test("window and external writes each refresh the changed control once", function()
    local h, addon = NewAddOn()
    local window, state = addon.SettingsWindow, addon.State
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

test("an enum button steps forward on a left click and back on a right click, wrapping", function()
    local _, addon = NewAddOn()
    local window, state = addon.SettingsWindow, addon.State
    window:Show()
    local button = window.Controls[state:Id("Meter.size")]
    eq(button.Label:GetText(), "Wide")
    button:Click("LeftButton")
    eq(state:Get("Meter.size"), "wider")
    eq(button.Label:GetText(), "Wider")
    button:Click("RightButton")
    button:Click("RightButton")
    eq(state:Get("Meter.size"), "widest", "back from the first value wraps to the last")
end)

test("number steppers move by the row's step and stop at its bounds", function()
    local _, addon = NewAddOn()
    local window, state = addon.SettingsWindow, addon.State
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
    local window, state = addon.SettingsWindow, addon.State
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
    local window, state = addon.SettingsWindow, addon.State
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
    local window, state = addon.SettingsWindow, addon.State
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
    for _, child in ipairs({ window.View:GetChildren() }) do
        local label = rawget(child, "Label") -- the content frame has none
        if label and label:GetText() == "Riddles" then
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
    truthy(movedX ~= x or movedY ~= y, "it moved")
end)

test("the view moving into Blizzard's panel closes the window rather than leaving it empty", function()
    local _, addon = NewAddOn()
    local window = addon.SettingsWindow
    window:Show()
    window.Canvas:Show()
    falsy(window:IsShown(), "no empty window over the panel")
    truthy(window.Controls[addon.State:Id("Meter.enabled")]:IsVisible(), "the panel shows the settings")
end)

test("closing the window while Blizzard's panel shows gives the panel its view back", function()
    local _, addon = NewAddOn()
    local window = addon.SettingsWindow
    window.Canvas:Show()
    window:Show()
    window:Hide()
    local box = window.Controls[addon.State:Id("Meter.enabled")]
    truthy(box:IsVisible(), "not a blank page")
    eq(window.View:GetParent(), window.Canvas)
end)

test("number steppers stay on the row's grid and inside its bounds, whatever the bounds", function()
    local h = Harness.New()
    h:LoadFiles("ByteTerrace_Core")
    h.declared.TestDB = true
    local addon = h.env.ByteTerrace.NewAddOn({ name = "TestApp", title = "Test App", savedVariable = "TestDB", slash = { "/test" } })
    addon:Module("M", { toggle = false, state = {
        { name = "share", kind = "number", default = 0.8, min = 0, max = 1, step = 0.4, label = "Share" },
        { name = "free", kind = "number", default = 2, min = 0.5, max = 2.5, label = "Free" },
    } })
    h:Fire("ADDON_LOADED", "TestApp")
    local window, state = addon.SettingsWindow, addon.State
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
    local addon = h.env.ByteTerrace.NewAddOn({ name = "TestApp", title = "Test App", savedVariable = "TestDB", slash = { "/test" } })
    addon:Module("M", { label = "M", page = "Test App" })
    h:Fire("ADDON_LOADED", "TestApp")
    eq(#addon.SettingsWindow.Pages, 1)
end)
