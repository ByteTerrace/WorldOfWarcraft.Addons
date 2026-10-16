-- The wishes window (ScholarWishesView.lua and ScholarWishes.lua): every wish with how close the stars are, and for a
-- grown-up, the requests waiting for an answer, usable with a controller as well as the mouse and keyboard. The D-pad
-- chooses, A asks or grants, X says Not now, and B closes. Those are summons, so they stack over the riddle's buttons
-- and give them back when the window closes. D-pad right opens it from the riddle screen and while a riddle waits in
-- its pill, and /tlk wishes opens it anywhere.

local Kit = use("scholar")
local LoadKid = Kit.LoadKid
local Watch = Kit.Watch

-- A child's character with two priced wishes, enough stars for both, and a controller when pad is set.
local function Child(pad)
    local h, addon, ns = LoadKid({ ["Scholar.missPause"] = "off", ["Scholar.quests"] = false })

    h.labelStyle = ((pad and "Letters") or nil)
    h:Slash("/tlk wish 1 A new pet")
    h:Slash("/tlk wish 1 Pick our next zone")
    addon.State:Set("Scholar.stars", 2)

    return h, addon, ns
end

-- What /tlk wishes prints, without color codes.
local function Listed(h)
    local from = #h.printed

    h:Slash("/tlk wishes")

    local lines = {}

    for i = from + 1, #h.printed do lines[#lines + 1] = h.printed[i] end

    return table.concat(lines, "\n")
end

local function Text(fontString)
    return (fontString:GetText() or "")
end

local function Window(h)
    return rawget(h.env, "TheLanKrewToolKitWishes")
end

test("/tlk wishes opens the wishes window, with each wish and how close the stars are", function()
    local h, addon = Child()

    addon.State:Set("Scholar.stars", 0)
    h:Slash("/tlk wish 15 Ride the gryphon together")
    addon.State:Set("Scholar.stars", 12)
    h:Slash("/tlk wishes")
    local frame = Window(h)

    truthy(frame and frame:IsShown(), "the window opens")
    eq(Text(frame.Rows[3].Label), "Ride the gryphon together")
    eq(Text(frame.Rows[3].Status), "12 of 15 stars")
    eq(Text(frame.Rows[1].Status), "Ready to ask!")
    truthy(Text(frame.Title):find("12 stars to spend", 1, true), Text(frame.Title))
end)

test("with a controller, the D-pad chooses a wish, A asks for it, and B closes the window", function()
    local h, addon = Child(true)

    h:Slash("/tlk wishes")
    local frame = Window(h)

    eq(frame.Selected, 1, "the first wish is chosen")
    h:Gamepad("PADDDOWN", true)
    eq(frame.Selected, 2, "D-pad down chooses the next")
    h:Gamepad("PAD1", true)
    truthy(Listed(h):find("2. Pick our next zone: asked!", 1, true), "A asks for it")
    eq(Text(frame.Rows[2].Status), "Asked! Waiting for an answer")
    h:Gamepad("PAD2", true)
    falsy(frame:IsShown(), "B closes the window")
    local before = #h.propagated

    h:Gamepad("PAD1", true)
    eq(h.propagated[before + 1], "PAD1", "and gives the buttons back to the game")
    eq(addon.State:Get("Scholar.stars"), 2)
end)

test("on the riddle screen, D-pad right opens the wishes over the riddle, and closing them gives the riddle its buttons", function()
    local h, addon, ns = Child(true)
    local shown = Watch(ns)

    h:Slash("/tlk puzzle")
    local puzzle = shown[#shown]

    h:Gamepad("PADDRIGHT", true)
    truthy(Window(h):IsShown(), "the wishes open")
    truthy(rawget(h.env, "TheLanKrewToolKitScholar"):IsShown(), "over the riddle")
    h:Gamepad("PAD2", true)
    falsy(Window(h):IsShown())
    h:Gamepad(({ "PAD1", "PAD2", "PAD3", "PAD4" })[puzzle.answer], true)
    truthy(addon.State:Get("Scholar.solved"), "the riddle has its buttons back")
end)

test("while a riddle waits in its pill, D-pad right opens the wishes", function()
    local h, _, ns = Child(true)

    Watch(ns)
    h:Slash("/tlk puzzle")
    h:Key("L", true)
    h:Gamepad("PADDRIGHT", true)
    truthy(Window(h):IsShown())
end)

test("a grown-up's window lists the requests waiting: A grants one, and X says Not now to another", function()
    local h = Child()

    h:Slash("/tlk ask 1")
    h:Slash("/tlk ask 2")
    h:SwitchCharacter("Mom")
    h.labelStyle = "Letters"
    h:Slash("/tlk wishes")
    local frame = Window(h)

    eq(Text(frame.Rows[1].Label), "Tester Doe wishes for A new pet")
    eq(Text(frame.Rows[1].Status), "1 star")
    h:Gamepad("PAD1", true)
    eq(Text(frame.Rows[1].Label), "Tester Doe wishes for Pick our next zone", "A granted the first, and the next moves up")
    h:Gamepad("PAD3", true)
    eq(frame.Rows[1]:IsShown(), false, "X said Not now to the second")
    truthy(Text(frame.Empty):find("No wishes are waiting", 1, true), Text(frame.Empty))
end)

test("with the mouse, a click chooses a row, and the footer's buttons act on it", function()
    local h = Child()

    h:Slash("/tlk wishes")
    local frame = Window(h)

    h:Click(frame.Rows[2])
    eq(frame.Selected, 2)
    eq(Text(frame.Act.Label), "Ask")
    h:Click(frame.Act)
    eq(Text(frame.Rows[2].Status), "Asked! Waiting for an answer")
    h:Click(frame.Close)
    falsy(frame:IsShown())
end)

test("with a controller, the footer shows the controller UI's glyphs for each action", function()
    local h = Child(true)

    h:Slash("/tlk wishes")
    local frame = Window(h)

    truthy(Text(frame.Act.Label):find("|A:gamepad-xbox1-pad1-normal", 1, true), Text(frame.Act.Label))
    truthy(Text(frame.Close.Label):find("|A:gamepad-xbox1-pad2-normal", 1, true), Text(frame.Close.Label))
end)

test("Up and Down choose, Enter acts, and Esc closes the window as it closes any, and only it", function()
    local h = Child()

    h:Slash("/tlk wishes")
    local frame = Window(h)

    h:Key("DOWN", true)
    eq(frame.Selected, 2)
    h:Key("ENTER", true)
    eq(Text(frame.Rows[2].Status), "Asked! Waiting for an answer")
    local before = #h.propagatedKeys

    h:Key("ESCAPE", true)
    falsy(frame:IsShown(), "Esc closes it")
    eq(#h.propagatedKeys, before, "without opening the game menu too")
    h:Key("W", true)
    eq(#h.propagatedKeys, before + 1, "and other keys are the game's")
end)

test("a fight closes the window and gives the controller back", function()
    local h = Child(true)

    h:Slash("/tlk wishes")
    h:EnterCombat()
    falsy(Window(h):IsShown())
    h:LeaveCombat()
    local before = #h.propagated

    h:Gamepad("PAD1", true)
    eq(h.propagated[before + 1], "PAD1")
end)

test("Up on the keyboard and the D-pad choose the one before, a click on Not now answers a request, and a fight keeps it shut", function()
    local h = Child(true)

    h:Slash("/tlk wishes")
    local frame = Window(h)

    h:Key("DOWN", true)
    h:Key("UP", true)
    eq(frame.Selected, 1, "Up on the keyboard")
    h:Gamepad("PADDDOWN", true)
    h:Gamepad("PADDUP", true)
    eq(frame.Selected, 1, "and on the D-pad")
    h:Slash("/tlk ask 1")
    h:SwitchCharacter("Mom")
    h:Slash("/tlk wishes")
    frame = Window(h)
    h:Click(frame.NotNow)
    truthy(Text(frame.Empty):find("No wishes are waiting", 1, true), "Not now answered it")
    h:Click(frame.Close)
    h:EnterCombat()
    h.ns.ScholarWishes.Open()
    falsy(frame:IsShown(), "it doesn't open in a fight")
end)
