-- Quest progress you can hear and feel (QuestProgress.lua, Sounds.lua, and Controller.lua): the Owl counts a young
-- scholar's quest objectives aloud, sums up a fight's progress once it ends, and a quest ready to turn in plays the
-- QuestReady sound, flashes the controller's light bar gold, and rumbles lightly.

local Kit = use("scholar")
local Accept = Kit.Accept
local Load = Kit.Load
local LoadKid = Kit.LoadKid

local Wolves = {
    goal = "Bring 8 Tough Wolf Meat to Eagan Peltskinner.", header = "Elwynn Forest", id = 33,
    objectives = { { required = 8, text = "Tough Wolf Meat" } },
    text = "The wolves of Elwynn grow bolder every night.", title = "Wolves Across the Border",
}

local Gold = "1 0.82 0"
local Green = "0 1 0"
local ReadyFile = "Interface\\AddOns\\TheLanKrewToolKit\\Media\\QuestReady.ogg"
local Red = "1 0 0"

-- A young scholar's character (grade 0, so riddles and counts are read aloud) with Wolves accepted.
local function KidWithWolves(extra)
    local settings = { ["Scholar.grade"] = "0" }

    for key, value in pairs(extra or {}) do settings[key] = value end

    local h, addon, ns = LoadKid(settings)

    Accept(h, Wolves)
    h:Advance(1)

    return h, addon, ns
end

-- The light bar's color as "r g b", or "off".
local function Light(h)
    return ((h.led and table.concat(h.led, " ", 1, 3)) or "off")
end

-- What the voice said after the from-th utterance, joined by " | ".
local function Said(h, from)
    local texts = {}

    for i = (from or 0) + 1, #h.spoken do
        texts[#texts + 1] = h.spoken[i].text
    end

    return table.concat(texts, " | ")
end

test("the quest flash and rumble run only while a controller is connected", function()
    local h = Harness.New()
    local addon = h:LoadAddon("TheLanKrewToolKit").Addon
    local modules = addon.Modules

    falsy(modules.QuestFlash:IsRunning(), "no controller, no flash")
    falsy(modules.QuestRumble:IsRunning(), "nor rumble")
    h:ConnectController()
    truthy(modules.QuestFlash:IsRunning(), "a controller plugged in brings them")
    truthy(modules.QuestRumble:IsRunning())
    Accept(h, Wolves)
    h:Advance(1)
    h:ProgressObjective(33, 1, 8)
    h:Advance(1)
    eq(Light(h), Gold)
    h:DisconnectController()
    falsy(modules.QuestFlash:IsRunning(), "and pulling it out ends them")
    falsy(modules.QuestRumble:IsRunning())
end)

test("with no controller and the quest-ready sound off, nothing keeps the quest log read", function()
    local h = Harness.New()
    local addon = h:LoadAddon("TheLanKrewToolKit").Addon

    addon.State:Set("Sounds.questReady", false)
    falsy(addon.Modules.QuestProgress:IsRunning())
    h.apiCalls = {}
    Accept(h, Wolves)
    h:ProgressObjective(33, 1, 3)
    h:Advance(1)
    eq(h:CountApiCalls("C_QuestLog.ReadyForTurnIn"), 0, "no quest progress is read")
end)

test("a count that wouldn't be read aloud doesn't keep the quest log read", function()
    -- Grade 2 with Read riddles aloud for kindergarten and grade 1: nothing is read aloud. With the QuestReady sound,
    -- flash and rumble off too, nothing needs the log's progress.
    local h, addon = LoadKid({ ["Scholar.grade"] = "2" })

    for _, row in ipairs({ "Sounds.questReady", "LightBar.questReady", "Rumble.questReady" }) do
        addon.State:Set(row, false)
    end

    Accept(h, Wolves)
    h:Advance(1)
    h.apiCalls = {}
    h:ProgressObjective(33, 1, 3)
    h:Advance(1)
    eq(h:CountApiCalls("C_QuestLog.GetQuestObjectives"), 0)
    addon.State:Set("Scholar.readAloud", "always")
    h.apiCalls = {}
    h:ProgressObjective(33, 1, 4)
    h:Advance(1)
    truthy(h:CountApiCalls("C_QuestLog.GetQuestObjectives") > 0, "read aloud always, the count is read again")
    truthy(Said(h):find("Tough Wolf Meat: 4 of 8.", 1, true), Said(h))
end)

test("the Owl counts a quest objective as it goes up, and says when the quest is ready to turn in", function()
    local h = KidWithWolves()
    local from = #h.spoken

    eq(Said(h, from), "", "accepting a quest isn't progress")
    h:ProgressObjective(33, 1, 3)
    h:Advance(1)
    eq(Said(h, from), "Tough Wolf Meat: 3 of 8. 5 more to go!")
    from = #h.spoken
    h:ProgressObjective(33, 1, 8)
    h:Advance(1)

    eq(Said(h, from), "Tough Wolf Meat: all 8. Done! Wolves Across the Border is ready to turn in!",
        "the last one and the quest being ready are one sentence")
end)

test("a task done once is just done", function()
    local h = LoadKid({ ["Scholar.grade"] = "0" })

    Accept(h, { id = 34, objectives = { { required = 1, text = "Sit near the campfire", type = "log" } },
        title = "The Great Outdoors" })

    h:Advance(1)
    local from = #h.spoken

    h:ProgressObjective(34, 1, 1)
    h:Advance(1)
    eq(Said(h, from), "Sit near the campfire: done! The Great Outdoors is ready to turn in!")
end)

test("in a fight the log isn't read and the Owl keeps quiet, then sums up what the fight got", function()
    local h = KidWithWolves()
    local from = #h.spoken
    local reads = h:CountApiCalls("C_QuestLog.GetQuestObjectives")

    h:EnterCombat()
    h:ProgressObjective(33, 1, 1)
    h:Advance(1)
    h:ProgressObjective(33, 1, 2)
    h:Advance(1)
    eq(h:CountApiCalls("C_QuestLog.GetQuestObjectives"), reads, "nothing reads the quest log in combat")
    eq(Said(h, from), "", "and nothing is said")
    h:LeaveCombat()
    h:Advance(1)
    eq(Said(h, from), "That fight got you 2 more! Tough Wolf Meat: 2 of 8. 6 more to go!")
end)

test("progress just before a fight starts waits for the fight to end, and the fight's sum includes it", function()
    local h = KidWithWolves()
    local from = #h.spoken
    local reads = h:CountApiCalls("C_QuestLog.GetQuestObjectives")

    h:ProgressObjective(33, 1, 1)
    h:EnterCombat()
    h:Advance(1)
    eq(h:CountApiCalls("C_QuestLog.GetQuestObjectives"), reads, "the reading due as the fight started waits")
    eq(Said(h, from), "", "and nothing is said mid-fight")
    h:LeaveCombat()
    h:Advance(1)
    eq(Said(h, from), "That fight got you 1 more! Tough Wolf Meat: 1 of 8. 7 more to go!")
end)

test("a burst of quest log updates is one reading of the log", function()
    local h = KidWithWolves()
    local reads = h:CountApiCalls("C_QuestLog.GetQuestObjectives")

    for _ = 1, 5 do h:Fire("QUEST_LOG_UPDATE") end

    h:Advance(1)
    eq(h:CountApiCalls("C_QuestLog.GetQuestObjectives") - reads, 1, "one quest in the log, read once")
end)

test("progress made before the reader started, or before a reload, isn't announced as new", function()
    local h = LoadKid({ ["Scholar.grade"] = "0" })
    local partly = { id = 35, objectives = { { have = 2, required = 6, text = "Kobold Candle" } }, title = "Candles" }

    Accept(h, partly)
    h:Advance(1)
    local from = #h.spoken

    eq(Said(h, from), "", "a quest accepted with some done starts from there")
    h:ProgressObjective(35, 1, 4)
    h:Reload()
    h:Advance(1)
    eq(Said(h, from), "", "after a reload, the log is where counting starts")
    h:ProgressObjective(35, 1, 5)
    h:Advance(1)
    eq(Said(h, from), "Kobold Candle: 5 of 6. 1 more to go!")
end)

test("counting follows Read riddles aloud and the challenge, and keeps quiet while a riddle is on screen", function()
    local h, addon = KidWithWolves({ ["Scholar.grade"] = "2" })
    local from = #h.spoken

    h:ProgressObjective(33, 1, 1)
    h:Advance(1)
    eq(Said(h, from), "", "Read riddles aloud is for kindergarten and grade 1 by default")
    addon.State:Set("Scholar.readAloud", "always")
    h:ProgressObjective(33, 1, 2)
    h:Advance(1)
    eq(Said(h, from), "Tough Wolf Meat: 2 of 8. 6 more to go!", "always reads at any grade")
    addon.State:Set("QuestCount.enabled", false)
    from = #h.spoken
    h:ProgressObjective(33, 1, 3)
    h:Advance(1)
    eq(Said(h, from), "", "its own switch turns it off")
    addon.State:Set("QuestCount.enabled", true)
    h:Slash("/tlk puzzle")
    from = #h.spoken
    h:ProgressObjective(33, 1, 4)
    h:Advance(1)
    falsy(Said(h, from):find("Tough Wolf Meat", 1, true), "a riddle on screen isn't talked over")
    addon.State:Set("Scholar.enabled", false)
    falsy(addon.Modules.QuestCount:IsRunning(), "and it's the challenge's, so it stops with it")
end)

test("a quest ready to turn in plays QuestReady, flashes the light bar gold, and rumbles lightly", function()
    local h = Harness.New()

    h.files[ReadyFile] = true
    h.labelStyle = "Letters"
    h:LoadAddon("TheLanKrewToolKit")
    Accept(h, Wolves)
    h:Advance(1)
    eq(Light(h), Green)
    local sounds = #h.sounds
    local rumbles = #h.vibrations

    h:ProgressObjective(33, 1, 7)
    h:Advance(1)
    eq(#h.sounds, sounds, "progress alone isn't ready")
    h:ProgressObjective(33, 1, 8)
    h:Advance(1)
    eq(h.sounds[#h.sounds].path, ReadyFile, "the ready sound plays")
    eq(Light(h), Gold, "the light bar turns gold")
    eq(#h.vibrations, rumbles + 1)
    eq(h.vibrations[#h.vibrations][1], "Low", "a light rumble")
    h:Advance(3)
    eq(Light(h), Green, "then goes back to how things are")
end)

test("combat's red wins over the gold, and the gold doesn't come back once the fight is over", function()
    local h = Harness.New()

    h.labelStyle = "Letters"
    h:LoadAddon("TheLanKrewToolKit")
    Accept(h, Wolves)
    h:Advance(1)
    h:ProgressObjective(33, 1, 8)
    h:Advance(1)
    eq(Light(h), Gold)
    h:EnterCombat()
    eq(Light(h), Red, "combat starts: red")
    h:Advance(5)
    h:LeaveCombat()
    eq(Light(h), Green)
end)

test("each part has its own switch, and with every part off nothing listens to the quest log", function()
    local h, addon = Load()

    h.files[ReadyFile] = true
    addon.State:Set("LightBar.questReady", false)
    Accept(h, Wolves)
    h:Advance(1)
    h:ProgressObjective(33, 1, 8)
    h:Advance(1)
    eq(Light(h), Green, "the light bar's own switch")
    eq(h.sounds[#h.sounds].path, ReadyFile, "the others still go")
    addon.State:Set("Rumble.questReady", false)
    addon.State:Set("Sounds.questReady", false)
    falsy(addon.Modules.QuestProgress:IsRunning(), "nothing uses the reader")
    falsy(addon.Events.Frame:IsEventRegistered("QUEST_LOG_UPDATE"), "so nothing hears the quest log")
end)

test("an objective the client hasn't named yet is counted under its quest's title", function()
    local h = LoadKid({ ["Scholar.grade"] = "0" })

    Accept(h, { id = 36, objectives = { { required = 5, text = "Duskbat Pelt", uncached = true } }, title = "Bat Hunt" })
    h:Advance(1)
    local from = #h.spoken

    h:ProgressObjective(36, 1, 1)
    h:Advance(1)
    eq(Said(h, from), "Bat Hunt: 1 of 5. 4 more to go!")
end)

test("after a reload in a fight, counting starts from where the log is when the fight ends", function()
    local h = KidWithWolves()

    h:EnterCombat()
    h:Reload()
    h:ProgressObjective(33, 1, 2)
    local from = #h.spoken

    h:LeaveCombat()
    h:Advance(1)
    eq(Said(h, from), "", "what the fight gained before the reader started isn't known")
    h:ProgressObjective(33, 1, 3)
    h:Advance(1)
    eq(Said(h, from), "Tough Wolf Meat: 3 of 8. 5 more to go!")
end)
