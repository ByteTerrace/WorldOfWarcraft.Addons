-- The addon's own settings window (ByteTerrace_Core/SettingsWindow.lua): what the bare slash
-- command opens instead of Blizzard's settings panel, which froze the Forever client when an
-- addon opened it (tools/api/forbidden.json).

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

test("the window's pages are the settings panel's pages, main page first", function()
    local h, addon = NewAddOn()
    local names, panel = {}, {}
    for i, page in ipairs(addon.SettingsWindow.Pages) do
        names[i] = page.name
    end
    for i, page in ipairs(h.settingsPages) do
        panel[i] = page.name
    end
    eq(table.concat(names, ","), "Test App,Riddles")
    eq(table.concat(names, ","), table.concat(panel, ","))
end)

test("a checkbox flips its row, and a change made elsewhere shows while the window is open", function()
    local h, addon = NewAddOn()
    local window, state = addon.SettingsWindow, addon.State
    window:Show()
    local box = window.Controls[state:Id("Meter.enabled")]
    truthy(box.Check:IsShown(), "on by default")
    box:Click()
    falsy(state:Get("Meter.enabled"))
    falsy(box.Check:IsShown())
    h:Slash("/test toggle Meter.enabled")
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

test("a locked row refuses the window's change and says so", function()
    local h, addon = NewAddOn()
    local window, state = addon.SettingsWindow, addon.State
    window:Show(2)
    state:Set("Riddles.locked", true)
    window.Controls[state:Id("Riddles.minutes")].Plus:Click()
    eq(state:Get("Riddles.minutes"), 30)
    truthy(h.printed[#h.printed]:find("Minutes is locked", 1, true), h.printed[#h.printed])
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

test("a hidden window does no widget work when its rows change", function()
    local h, addon = NewAddOn()
    local window, state = addon.SettingsWindow, addon.State
    window:Show()
    window:Hide()
    local before = h:CountCalls("SetText") + h:CountCalls("SetShown")
    state:Set("Meter.size", "wider")
    state:Set("Meter.enabled", false)
    eq(h:CountCalls("SetText") + h:CountCalls("SetShown"), before)
    window:Show()
    eq(window.Controls[state:Id("Meter.size")].Label:GetText(), "Wider", "shown values catch up when it opens")
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
