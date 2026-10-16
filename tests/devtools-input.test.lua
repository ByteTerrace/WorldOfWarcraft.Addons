-- ByteTerrace_DevTools' controller tools: /btdev rumble plays the vibration candidates in turn for gamePad.vibration,
-- or one vibration as typed. The input listener keeps the controller and interface events' payload shapes from load,
-- for input.events.

local function Load()
    local h = Harness.New()

    h.labelStyle = "Letters"
    h:LoadAddon("ByteTerrace_DevTools")

    return h
end

local function Played(h)
    local kinds = {}

    for i, vibration in ipairs(h.vibrations) do
        kinds[i] = (vibration[1] .. "@" .. vibration[2])
    end

    return table.concat(kinds, " ")
end

local function Printed(h)
    return table.concat(h.printed, "\n")
end

test("/btdev rumble plays each candidate for half a second, a second and a half apart, and records them", function()
    local h = Load()

    h:Slash("/btdev rumble")
    eq(Played(h), "High@1", "the first plays at once")
    h:Advance(0.5)
    eq(h.vibrationsStopped, 1, "and stops half a second later")
    h:Advance(1)
    eq(Played(h), "High@1 Low@1")
    h:Advance(3)
    eq(Played(h), "High@1 Low@1 LTrigger@1 RTrigger@1", "in order, each named as it plays")
    h:Advance(1)
    eq(h.vibrationsStopped, 4)
    truthy(Printed(h):find("4/4: RTrigger", 1, true), Printed(h))
    h:Slash("/btdev probe")
    local record = h.env.ByteTerraceDevToolsDB.probes["gamePad.vibration"]

    eq(record.result.accepted, "High,LTrigger,Low,RTrigger")
    eq(record.result.refused, "none")
end)

test("/btdev rumble stop, or another rumble, ends the candidates still to come", function()
    local h = Load()

    h:Slash("/btdev rumble")
    h:Slash("/btdev rumble stop")
    h:Advance(6)
    eq(Played(h), "High@1", "stopping ends the run")
    h:Slash("/btdev rumble")
    h:Advance(0.5)
    h:Slash("/btdev rumble LTrigger 0.3")
    h:Advance(6)
    eq(Played(h), "High@1 High@1 LTrigger@0.3", "the vibration typed isn't cut short by a candidate")
end)

test("/btdev rumble <type> keeps the type's case, and plays until stopped unless given seconds", function()
    local h = Load()

    h:Slash("/btdev rumble LTrigger 0.3")
    eq(Played(h), "LTrigger@0.3")
    h:Advance(60)
    eq(h.vibrationsStopped, 0, "no seconds: it plays until it stops by itself")
    truthy(Printed(h):find("until it stops by itself", 1, true), Printed(h))
    h:Slash("/btdev rumble stop")
    eq(h.vibrationsStopped, 1)
    h:Slash("/btdev rumble High 1 2")
    h:Advance(1)
    h:Slash("/btdev rumble Low 0.5 2")
    h:Advance(1.5)
    eq(h.vibrationsStopped, 1, "the first one's stop doesn't cut the second short")
    h:Advance(0.5)
    eq(h.vibrationsStopped, 2)
end)

test("/btdev rumble refuses an intensity outside 0 to 1 or seconds that aren't positive", function()
    local h = Load()

    h:Slash("/btdev rumble High 2")
    h:Slash("/btdev rumble High 1 -1")
    h:Slash("/btdev rumble High loud")
    eq(#h.vibrations, 0)
    local _, usages = Printed(h):gsub("usage: /btdev rumble", "")

    eq(usages, 3)
end)

test("the input listener keeps each controller and interface event's payloads from load, and which fired before the world", function()
    local h = Harness.New()

    h.labelStyle = "Letters"
    h:LoadFiles("ByteTerrace_DevTools")
    h:Fire("GAME_PAD_CONNECTED")
    h:Login(true, false)
    h:Fire("INPUT_DEVICE_INTERFACE_TRANSITION", h.env.Enum.InputDeviceInterfaceType.Gamepad, h.env.Enum.InputDeviceInterfaceType.Mkb)
    h:Fire("GAME_PAD_POWER_CHANGED", h.env.Enum.GamePadPowerLevel.Low)
    h:Fire("GAME_PAD_ACTIVE_CHANGED", true)
    h:Slash("/btdev probe")
    local result = h.env.ByteTerraceDevToolsDB.probes["input.events"].result

    eq(result.heard, "GAME_PAD_ACTIVE_CHANGED,GAME_PAD_CONNECTED,GAME_PAD_POWER_CHANGED,INPUT_DEVICE_INTERFACE_TRANSITION")
    eq(result.GAME_PAD_CONNECTED.payloads, "none")
    truthy(result.GAME_PAD_CONNECTED.beforeWorld, "connected before the world")
    eq(result.INPUT_DEVICE_INTERFACE_TRANSITION.payloads, "Gamepad,Mkb")
    falsy(result.INPUT_DEVICE_INTERFACE_TRANSITION.beforeWorld)
    eq(result.GAME_PAD_POWER_CHANGED.payloads, "Low")
    eq(result.GAME_PAD_ACTIVE_CHANGED.payloads, "boolean")
end)
