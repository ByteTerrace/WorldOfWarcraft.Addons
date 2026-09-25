-- TheLanKrewToolKit behavior, end to end through the real addon files.

local MEDIA = "Interface\\AddOns\\TheLanKrewToolKit\\Media\\"

local function Load(player)
    local h = Harness.new(player)
    local ns = h:LoadAddon("TheLanKrewToolKit")
    return h, ns.Addon
end

local function EnemyPlayer(fields)
    local unit = { isPlayer = true, canAttack = true, playerControlled = true }
    for key, value in pairs(fields or {}) do unit[key] = value end
    return unit
end

local function Played(h, file)
    local count = 0
    for _, sound in ipairs(h.sounds) do
        if sound.path == MEDIA .. file then count = count + 1 end
    end
    return count
end

local function Registered(addon, event)
    return addon.Events.Frame:IsEventRegistered(event)
end

-- Load and settings -----------------------------------------------------------

-- Each settings page as one line: "Name < Parent: [Header] Module.row ...".
local function Pages(h)
    local lines = {}
    for _, page in ipairs(h.settingsPages) do
        local parts = {}
        for _, entry in ipairs(page.entries) do
            parts[#parts + 1] = entry.header and ("[" .. entry.header .. "]") or entry.variable:gsub("^TheLanKrewToolKit_", "")
        end
        lines[#lines + 1] = page.name .. (page.parent and (" < " .. page.parent) or "") .. ": " .. table.concat(parts, " ")
    end
    return lines
end

test("loads cleanly and builds its settings panel, organized into pages and sections", function()
    local h = Load()
    local main = "The Lan Krew ToolKit"
    local expected = {
        main .. ": [Fuck-o-meter] FuckOMeter.enabled"
            .. " [Session journal] Journal.enabled Journal.welcome Journal.ding [Advanced] addon.debug",
        "Sounds < " .. main .. ": Sounds.enabled Sounds.channel Sounds.combatStart Sounds.stopOnCombatEnd"
            .. " [Mortal Kombat] Kombat.chooseYourDestiny Kombat.testYourMight Kombat.finishHim Kombat.comboPoints"
            .. " Kombat.flawlessVictory Kombat.fatality Kombat.superbVictory Kombat.deathTaunt"
            .. " [Kill streaks] Streaks.enabled Streaks.firstBlood Streaks.multiKills Streaks.sprees Streaks.share",
        "Controller < " .. main .. ": [Controller light bar] LightBar.enabled [Controller rumble] Rumble.enabled",
        "Krew < " .. main .. ": [Krew messages] Krew.enabled Krew.hello Krew.shareDings Krew.shareFlawless Krew.shareScholar",
        "Warband < " .. main .. ": [Warband (world PvP)] Warband.enabled Warband.alerts Warband.shareSightings"
            .. " Warband.deathPrompt Warband.rallyWaypoint Warband.intel"
            .. " [Nameplate badges] Badges.enabled [Nearby enemies window] Radar.enabled Radar.share",
        "Scholar's challenge < " .. main .. ": Scholar.enabled [Riddles] Scholar.grade Scholar.math Scholar.reading"
            .. " [When] Scholar.interval Scholar.onLevelUp Scholar.mode",
    }
    local pages = Pages(h)
    for i = 1, math.max(#pages, #expected) do
        eq(pages[i], expected[i], "page " .. i)
    end
    eq(h.category.name, main, "only the main page is registered as the addon's category")
    eq(h.settings["TheLanKrewToolKit_Sounds.channel"].options[2].label, "Sound effects", "friendly channel names")
end)

-- Fuck-o-meter -------------------------------------------------------------

test("fuck-o-meter shows for energy users and passes secret energy straight to the widgets", function()
    local h = Load({ classFile = "ROGUE", powerType = 3 })
    local meter = h.env.TheLanKrewToolKitFuckOMeter
    truthy(meter:IsShown())
    h:EnterCombat()
    h.player.power[3] = 42
    h:ResetCalls()
    h:Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
    truthy(h.env.issecretvalue(Harness.State(meter.Bar).value), "value arrived as a secret")
    eq(Reveal(Harness.State(meter.Bar).value), 42)
    eq(Reveal(Harness.State(meter.Value).text), 42)
    eq(Harness.State(meter.Bar).calls.SetValue, 1, "one SetValue per power event")
    eq(Harness.State(meter.Bar).calls.SetMinMaxValues, nil, "range isn't touched on power ticks")
end)

test("fuck-o-meter ignores other power types and stays unregistered for non-energy users", function()
    local h, addon = Load({ classFile = "DRUID", powerType = 0 })
    addon.State:Set("Kombat.comboPoints", false) -- combo point callouts listen to power too
    addon.State:Set("Kombat.finishHim", false)
    addon.State:Set("Kombat.fatality", false)
    local meter = h.env.TheLanKrewToolKitFuckOMeter
    falsy(meter:IsShown())
    falsy(Registered(addon, "UNIT_POWER_FREQUENT"), "no power events without energy")
    h.player.powerType = 3
    h:Fire("UNIT_DISPLAYPOWER", "player")
    truthy(meter:IsShown(), "cat form shows it")
    h:ResetCalls()
    h:Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    h:Fire("UNIT_MAXPOWER", "player", "MANA")
    eq(Harness.State(meter.Bar).calls.SetValue, nil, "mana ticks don't touch the bar")
    eq(Harness.State(meter.Bar).calls.SetMinMaxValues, nil, "mana max doesn't touch the range")
end)

test("fuck-o-meter re-reads range and value after a loading screen", function()
    local h = Load({ classFile = "ROGUE", powerType = 3 })
    local meter = h.env.TheLanKrewToolKitFuckOMeter
    h.player.powerMax[3] = 120
    h.player.power[3] = 7
    h:Fire("PLAYER_ENTERING_WORLD", false, false)
    eq(Reveal(Harness.State(meter.Bar).max), 120)
    eq(Reveal(Harness.State(meter.Bar).value), 7)
end)

test("fom toggles the meter off and removes its events", function()
    local h, addon = Load()
    addon.State:Set("Sounds.enabled", false) -- combo point callouts listen to power too
    local meter = h.env.TheLanKrewToolKitFuckOMeter
    h:Slash("/tlk fom")
    falsy(meter:IsShown())
    falsy(Registered(addon, "UNIT_POWER_FREQUENT"))
    eq(h.env.TheLanKrewToolKitDB["FuckOMeter.enabled"], false, "persisted")
end)

-- Combat start sound ---------------------------------------------------------

test("combat start plays on entering combat and fades out when it ends", function()
    local h = Load()
    h:AddMedia(MEDIA .. "CombatStart.mp3")
    h:EnterCombat()
    eq(Played(h, "CombatStart.mp3"), 1)
    eq(h.sounds[1].channel, "Master")
    h:LeaveCombat()
    eq(h.stopped[1].handle, h.sounds[1].handle)
    eq(h.stopped[1].fade, 1000)
end)

test("combat start respects its toggle and the channel setting, and stops when turned off mid-play", function()
    local h, addon = Load()
    h:AddMedia(MEDIA .. "CombatStart.ogg")
    h:Slash("/tlk set Sounds.channel SFX")
    h:EnterCombat()
    eq(h.sounds[1].channel, "SFX")
    addon.State:Set("Sounds.combatStart", false)
    eq(h.stopped[1].handle, h.sounds[1].handle, "stopped mid-play")
    h:LeaveCombat()
    h:EnterCombat()
    eq(Played(h, "CombatStart.ogg"), 1, "disabled sound doesn't play")
end)

test("a /reload in combat doesn't replay the combat start sound or rumble", function()
    local h = Harness.new()
    h:AddMedia(MEDIA .. "CombatStart.ogg")
    h.inCombat, h.lockdown = true, true
    h.restrictions.Combat = true
    h:LoadAddon("TheLanKrewToolKit")
    eq(Played(h, "CombatStart.ogg"), 0)
    eq(#h.vibrations, 0)
    eq(table.concat(h.led, ","), "1,0,0", "light bar knows it's combat")
end)

-- Target sounds ----------------------------------------------------------------

test("choose your destiny plays when a living enemy player becomes the target, at most every 10 seconds", function()
    local h = Load()
    h:AddMedia(MEDIA .. "ChooseYourDestiny.ogg")
    h:SetTarget({ isPlayer = false, canAttack = true })
    h:SetTarget({ isPlayer = true, canAttack = false, playerControlled = true })
    h:SetTarget(EnemyPlayer({ dead = true }))
    eq(Played(h, "ChooseYourDestiny.ogg"), 0, "NPC, friendly player, corpse: silent")
    h:SetTarget(EnemyPlayer())
    eq(Played(h, "ChooseYourDestiny.ogg"), 1)
    h:Advance(5)
    h:SetTarget(EnemyPlayer())
    eq(Played(h, "ChooseYourDestiny.ogg"), 1, "cooldown")
    h:Advance(5)
    h:SetTarget(EnemyPlayer())
    eq(Played(h, "ChooseYourDestiny.ogg"), 2)
end)

test("choose your destiny plays when the current target becomes attackable (a duel starts)", function()
    local h = Load()
    h:AddMedia(MEDIA .. "ChooseYourDestiny.ogg")
    local rival = EnemyPlayer({ canAttack = false })
    h:SetTarget(rival)
    eq(Played(h, "ChooseYourDestiny.ogg"), 0)
    rival.canAttack = true
    h:Fire("UNIT_FACTION", "target")
    eq(Played(h, "ChooseYourDestiny.ogg"), 1)
end)

test("flawless victory: no hits, enemy player target dies in the fight", function()
    local h = Load()
    h:AddMedia(MEDIA .. "FlawlessVictory.ogg")
    local enemy = EnemyPlayer()
    h:SetTarget(enemy)
    h:EnterCombat()
    enemy.dead = true
    h:Fire("UNIT_HEALTH", "target")
    eq(Played(h, "FlawlessVictory.ogg"), 1)
end)

test("flawless victory needs a fight you're in", function()
    local h = Load()
    h:AddMedia(MEDIA .. "FlawlessVictory.ogg")
    local enemy = EnemyPlayer()
    h:SetTarget(enemy)
    enemy.dead = true
    h:Fire("UNIT_HEALTH", "target")
    eq(Played(h, "FlawlessVictory.ogg"), 0, "someone else's kill, out of combat")
end)

test("flawless victory is lost after taking a hit in combat, even if healed", function()
    local h = Load()
    h:AddMedia(MEDIA .. "FlawlessVictory.ogg")
    local enemy = EnemyPlayer()
    h:SetTarget(enemy)
    h:EnterCombat()
    h:HitPlayer(20)
    h:HealPlayer(20)
    enemy.dead = true
    h:Fire("UNIT_HEALTH", "target")
    eq(Played(h, "FlawlessVictory.ogg"), 0)
end)

test("heals, regeneration and fully absorbed hits don't break flawless; an ambush just before combat does", function()
    local h = Load()
    h:AddMedia(MEDIA .. "FlawlessVictory.ogg")
    local enemy = EnemyPlayer()
    h:SetTarget(enemy)
    h:EnterCombat()
    h:HealPlayer(10)
    h:Fire("UNIT_HEALTH", "player") -- regeneration: no combat event
    h:HitPlayer(0, "ABSORB")
    enemy.dead = true
    h:Fire("UNIT_HEALTH", "target")
    eq(Played(h, "FlawlessVictory.ogg"), 1)
    h:LeaveCombat()
    h:Advance(5)
    enemy = EnemyPlayer()
    h:SetTarget(enemy)
    h:HitPlayer(30) -- the opening hit lands a moment before the client says combat started
    h:EnterCombat()
    enemy.dead = true
    h:Fire("UNIT_HEALTH", "target")
    eq(Played(h, "FlawlessVictory.ogg"), 1, "ambushed: not flawless")
end)

test("the victory waits for the damage meter's numbers to stop being secret", function()
    local h, addon = Load()
    local enemy = EnemyPlayer()
    h:SetTarget(enemy)
    h:EnterCombat()
    h:MeterAdd({ unit = "player", amounts = { DamageTaken = 50 } })
    enemy.dead = true
    h:Fire("UNIT_HEALTH", "target")
    h:LeaveCombat()
    h:SetRestriction("Combat", true) -- the server's combat outlasts yours for a moment
    eq(addon.State:Get("Victory.flawlessWins"), 0, "waiting")
    h:SetRestriction("Combat", false)
    h:Advance(1)
    eq(addon.State:Get("Victory.flawlessWins"), 0, "the meter saw 50 damage once it could say")
end)

test("starting health doesn't matter (addons can't read it); a selected corpse never counts", function()
    local h = Load()
    h:AddMedia(MEDIA .. "FlawlessVictory.ogg")
    h:HitPlayer(60)
    h:Advance(5) -- out of combat: not part of any fight
    local corpse = EnemyPlayer({ dead = true })
    h:SetTarget(corpse)
    h:EnterCombat()
    h:Fire("UNIT_HEALTH", "target")
    eq(Played(h, "FlawlessVictory.ogg"), 0, "corpse")
    corpse.dead = false
    h:Fire("UNIT_HEALTH", "target")
    corpse.dead = true
    h:Fire("UNIT_HEALTH", "target")
    eq(Played(h, "FlawlessVictory.ogg"), 1, "resurrected, then died while targeted, at 40% health going in")
end)

test("the same target dying twice counts twice", function()
    local h = Load()
    h:AddMedia(MEDIA .. "FlawlessVictory.ogg")
    local enemy = EnemyPlayer()
    h:SetTarget(enemy)
    h:EnterCombat()
    enemy.dead = true
    h:Fire("UNIT_HEALTH", "target")
    enemy.dead = false
    h:Fire("UNIT_HEALTH", "target")
    enemy.dead = true
    h:Fire("UNIT_HEALTH", "target")
    eq(Played(h, "FlawlessVictory.ogg"), 2)
end)

test("finish him: warriors, once per target, when Execute is actually usable", function()
    local h = Load({ classFile = "WARRIOR", powerType = 1 })
    h:AddMedia(MEDIA .. "FinishHim.ogg")
    h:SetTarget(EnemyPlayer())
    h:EnterCombat()
    h.usable.Execute = { false, true } -- not enough rage: not proof of range
    h:Fire("SPELL_UPDATE_USABLE")
    eq(Played(h, "FinishHim.ogg"), 0)
    h.usable.Execute = { true, false }
    h:Fire("SPELL_UPDATE_USABLE")
    eq(Played(h, "FinishHim.ogg"), 1)
    h.usable.Execute = { false, false } -- Defensive Stance
    h:Fire("UPDATE_SHAPESHIFT_FORM")
    h.usable.Execute = { true, false } -- back to Battle Stance
    h:Fire("UPDATE_SHAPESHIFT_FORM")
    eq(Played(h, "FinishHim.ogg"), 1, "a stance dance doesn't repeat it")
    h:SetTarget(EnemyPlayer())
    eq(Played(h, "FinishHim.ogg"), 2, "a new target in range announces again")
end)

test("finish him never runs for classes without a finisher", function()
    local h, addon = Load({ classFile = "MAGE" })
    h:AddMedia(MEDIA .. "FinishHim.ogg")
    h.usable.Execute = { true, false }
    h:SetTarget(EnemyPlayer())
    falsy(Registered(addon, "SPELL_UPDATE_USABLE"), "no usability polling")
    eq(Played(h, "FinishHim.ogg"), 0)
end)

test("sound test reports missing files and plays present ones", function()
    local h = Load()
    h:Slash("/tlk sound finish")
    truthy(h.printed[#h.printed]:find("No sound played", 1, true))
    h:AddMedia(MEDIA .. "FinishHim.ogg")
    h:Slash("/tlk sound finish")
    eq(Played(h, "FinishHim.ogg"), 1)
    h:Slash("/tlk sound")
    truthy(table.concat(h.printed, "\n"):find("destiny - ChooseYourDestiny.ogg or .mp3", 1, true))
end)

test("switched-off sounds cost nothing: their events unregister", function()
    local h, addon = Load({ classFile = "WARRIOR", powerType = 1 })
    addon.State:Set("Warband.enabled", false) -- Warband watches targets too
    truthy(Registered(addon, "PLAYER_TARGET_CHANGED"))
    addon.State:Set("Kombat.finishHim", false)
    truthy(Registered(addon, "SPELL_UPDATE_USABLE"), "fatality still needs to know finishing range")
    addon.State:Set("Kombat.fatality", false)
    falsy(Registered(addon, "SPELL_UPDATE_USABLE"), "finish him and fatality off: no usability polling")
    for _, row in ipairs({ "flawlessVictory", "chooseYourDestiny", "testYourMight", "superbVictory" }) do
        addon.State:Set("Kombat." .. row, false)
    end
    falsy(Registered(addon, "PLAYER_TARGET_CHANGED"), "no target sounds: no target events")
    falsy(Registered(addon, "UNIT_HEALTH"))
    addon.State:Set("Kombat.chooseYourDestiny", true)
    truthy(Registered(addon, "PLAYER_TARGET_CHANGED"))
    addon.State:Set("Sounds.enabled", false)
    falsy(Registered(addon, "PLAYER_TARGET_CHANGED"), "master switch off")
end)

-- Controller ---------------------------------------------------------------

test("light bar is green, red as combat starts (before lockdown), yellow when AFK, cleared when disabled", function()
    local h, addon = Load()
    eq(table.concat(h.led, ","), "0,1,0")
    local seenLockdown
    local probe = h.env.CreateFrame("Frame")
    probe:RegisterEvent("PLAYER_REGEN_DISABLED")
    probe:SetScript("OnEvent", function() seenLockdown = h.env.InCombatLockdown() end)
    h:EnterCombat()
    eq(seenLockdown, false, "the event arrives before lockdown")
    eq(table.concat(h.led, ","), "1,0,0")
    h:LeaveCombat()
    h.player.afk = true
    h:Fire("PLAYER_FLAGS_CHANGED", "player")
    eq(table.concat(h.led, ","), "1,1,0")
    addon.State:Set("LightBar.enabled", false)
    eq(h.led, nil)
end)

test("rumble is strong entering combat and light leaving it, never at login, and stops when disabled", function()
    local h, addon = Load()
    eq(#h.vibrations, 0)
    h:EnterCombat()
    h:LeaveCombat()
    eq(h.vibrations[1][1], "High")
    eq(h.vibrations[2][1], "Low")
    addon.State:Set("Rumble.enabled", false)
    eq(h.vibrationsStopped, 1)
end)

-- Session journal --------------------------------------------------------------

local function CardText(h)
    local card = rawget(h.env, "TheLanKrewToolKitCard") -- created lazily with the first card
    return card and card:IsShown() and (Reveal(Harness.State(card.Title).text) .. "\n" .. Reveal(Harness.State(card.Body).text)) or nil
end

test("the first login ever shows no welcome card", function()
    local h = Load()
    eq(CardText(h), nil)
end)

test("the next login welcomes you back with last session's highlights and rested XP", function()
    local h = Load()
    h.zone = "Stranglethorn Vale"
    h:Advance(2 * 3600 + 14 * 60)
    h:Fire("QUEST_TURNED_IN", 1, 100, 50)
    h:Fire("QUEST_TURNED_IN", 2, 100, 50)
    h.player.money = h.player.money + 452000
    h.player.level = h.player.level + 1
    h:Fire("PLAYER_LEVEL_UP", h.player.level)
    h.player.rested = 0
    h.player.xpMax = 1000
    h:Relog(3 * 86400, function() h.player.rested = 380 end)
    local text = CardText(h)
    truthy(text, "a card is shown")
    truthy(text:find("Welcome back, Tester!", 1, true), text)
    truthy(text:find("You were away 3 Day", 1, true), text) -- the harness SecondsToTime is a stand-in
    truthy(text:find("Rested up: +38% of a level", 1, true), text)
    truthy(text:find("Stranglethorn Vale", 1, true), text)
    truthy(text:find("2 quests", 1, true), text)
    truthy(text:find("reached level", 1, true), text)
end)

test("a /reload continues the session and shows no welcome card", function()
    local h = Load()
    h:Fire("QUEST_TURNED_IN", 1, 100, 50)
    h:Reload()
    eq(CardText(h), nil)
    h:Slash("/tlk journal")
    truthy(CardText(h):find("1 quest", 1, true), CardText(h))
end)

test("a level-up shows a Ding! card for the level you just finished", function()
    local h = Load()
    h:Advance(90 * 60)
    h:Fire("QUEST_TURNED_IN", 1, 100, 50)
    h.player.level = h.player.level + 1
    h:Fire("PLAYER_LEVEL_UP", h.player.level)
    local text = CardText(h)
    truthy(text:find("Ding! Level " .. h.player.level, 1, true), text)
    truthy(text:find("1 quest", 1, true), text)
    truthy(text:find("not a single death", 1, true), text)
end)

test("cards queue, dismiss on click, and hide on their own", function()
    local h = Load()
    h:Slash("/tlk journal")
    h.player.level = h.player.level + 1
    h:Fire("PLAYER_LEVEL_UP", h.player.level)
    truthy(CardText(h):find("This session", 1, true), "first card stays up")
    local card = h.env.TheLanKrewToolKitCard
    h:Click(card)
    truthy(CardText(h):find("Ding!", 1, true), "click shows the next")
    h:Advance(13)
    eq(CardText(h), nil, "hid on its own")
end)

test("card toggles and the module switch are honored", function()
    local h, addon = Load()
    addon.State:Set("Journal.ding", false)
    h.player.level = h.player.level + 1
    h:Fire("PLAYER_LEVEL_UP", h.player.level)
    eq(CardText(h), nil, "ding card off")
    addon.State:Set("Journal.enabled", false)
    falsy(Registered(addon, "QUEST_TURNED_IN"))
end)

-- Round 2 regressions -----------------------------------------------------------

test("a duel won without taking a hit is a flawless victory", function()
    local h = Load()
    h:AddMedia(MEDIA .. "FlawlessVictory.ogg")
    local rival = EnemyPlayer()
    h:SetTarget(rival)
    h:EnterCombat()
    h:Fire("DUEL_FINISHED")
    eq(Played(h, "FlawlessVictory.ogg"), 1)
end)

test("a duel lost by fleeing out of bounds isn't a victory", function()
    local h = Load()
    h:AddMedia(MEDIA .. "FlawlessVictory.ogg")
    h:SetTarget(EnemyPlayer())
    h:EnterCombat()
    h:Fire("DUEL_OUTOFBOUNDS")
    h:Fire("DUEL_FINISHED")
    eq(Played(h, "FlawlessVictory.ogg"), 0)
end)

test("a flawless victory counts when the fight ends and the damage meter confirms no damage taken", function()
    local h, addon = Load()
    h:AddMedia(MEDIA .. "FlawlessVictory.ogg")
    local enemy = EnemyPlayer()
    h:SetTarget(enemy)
    h:EnterCombat()
    enemy.dead = true
    h:Fire("UNIT_HEALTH", "target")
    eq(Played(h, "FlawlessVictory.ogg"), 1, "the sound plays at the kill")
    eq(addon.State:Get("Victory.flawlessWins"), 0, "counted once the fight ends")
    h:LeaveCombat()
    eq(addon.State:Get("Victory.flawlessWins"), 1)
end)

test("damage the live signal missed stops the victory counting, though the sound already played", function()
    local h, addon = Load()
    h:AddMedia(MEDIA .. "FlawlessVictory.ogg")
    local enemy = EnemyPlayer()
    h:SetTarget(enemy)
    h:EnterCombat()
    h:MeterAdd({ unit = "player", amounts = { DamageTaken = 120 } }) -- no UNIT_HEALTH on you: say a shield absorbed it
    enemy.dead = true
    h:Fire("UNIT_HEALTH", "target")
    eq(Played(h, "FlawlessVictory.ogg"), 1)
    h:LeaveCombat()
    eq(addon.State:Get("Victory.flawlessWins"), 0, "the meter saw 120 damage taken")
end)

test("an enemy that stops being attackable as it dies still counts as a kill", function()
    local h = Load()
    h:AddMedia(MEDIA .. "FlawlessVictory.ogg")
    local enemy = EnemyPlayer()
    h:SetTarget(enemy)
    h:EnterCombat()
    enemy.dead, enemy.canAttack = true, false
    h:Fire("UNIT_HEALTH", "target")
    eq(Played(h, "FlawlessVictory.ogg"), 1)
end)

test("turning flawless off mid-fight leaves no stale fight behind", function()
    local h, addon = Load()
    h:AddMedia(MEDIA .. "FlawlessVictory.ogg")
    local enemy = EnemyPlayer()
    h:SetTarget(enemy)
    h:EnterCombat()
    addon.State:Set("Kombat.flawlessVictory", false)
    h:LeaveCombat()
    addon.State:Set("Kombat.flawlessVictory", true)
    enemy.dead = true
    h:Fire("UNIT_HEALTH", "target")
    eq(Played(h, "FlawlessVictory.ogg"), 0, "out of combat, someone else's kill")
end)

test("finish him doesn't replay after a /reload with the same target in range", function()
    local h = Load({ classFile = "WARRIOR", powerType = 1 })
    h:AddMedia(MEDIA .. "FinishHim.ogg")
    h:SetTarget(EnemyPlayer())
    h.usable.Execute = { true, false }
    h:Fire("SPELL_UPDATE_USABLE")
    eq(Played(h, "FinishHim.ogg"), 1)
    h:Reload()
    eq(Played(h, "FinishHim.ogg"), 1)
end)

test("finish him alone never tracks targets for classes without a finisher", function()
    local h, addon = Load({ classFile = "MAGE" })
    addon.State:Set("Warband.enabled", false) -- Warband watches targets too
    for _, row in ipairs({ "flawlessVictory", "chooseYourDestiny", "testYourMight", "superbVictory" }) do
        addon.State:Set("Kombat." .. row, false)
    end
    falsy(Registered(addon, "PLAYER_TARGET_CHANGED"))
end)

test("internal rows aren't settings", function()
    local h = Load()
    h:Slash("/tlk set Journal.sessionQuests 999")
    truthy(h.printed[#h.printed]:find("Usage", 1, true))
    falsy(h.printed[#h.printed]:find("sessionQuests", 1, true), "not listed")
end)

-- Journal, round 2 -------------------------------------------------------------------

test("/tlk journal while the journal is off says so instead of failing", function()
    local h = Harness.new({ saved = { TheLanKrewToolKitDB = { ["Journal.enabled"] = false } } })
    h:LoadAddon("TheLanKrewToolKit")
    h:Slash("/tlk journal")
    truthy(h.printed[#h.printed]:find("turned off", 1, true), h.printed[#h.printed])
end)

test("cards wait out combat", function()
    local h = Load()
    h:EnterCombat()
    h.player.level = h.player.level + 1
    h:Fire("PLAYER_LEVEL_UP", h.player.level)
    eq(CardText(h), nil, "not mid-fight")
    h:LeaveCombat()
    truthy(CardText(h):find("Ding!", 1, true))
end)

test("a short relog doesn't show a trivial welcome card", function()
    local h = Load()
    h:Relog(60)
    eq(CardText(h), nil)
end)

test("a new character's 0 copper is a real baseline", function()
    local h = Harness.new()
    h.player.money = 0
    h:LoadAddon("TheLanKrewToolKit")
    h:Relog(600) -- short: no welcome card ahead of the Ding! card
    h.player.money = 6000
    h.player.level = h.player.level + 1
    h:Fire("PLAYER_LEVEL_UP", h.player.level)
    truthy(CardText(h):find("+60s", 1, true) or CardText(h):find("60 Silver", 1, true) or CardText(h):find("6000", 1, true), CardText(h))
end)

test("the first ding after installing says so, and milestones are celebrated", function()
    local h = Load()
    h.player.level = 10
    h:Fire("PLAYER_LEVEL_UP", 10)
    local text = CardText(h)
    truthy(text:find("Since the journal started", 1, true), text)
    truthy(text:find("milestone", 1, true), text)
end)

test("turning the journal off keeps the played time so far", function()
    local h, addon = Load()
    h:Advance(3600)
    addon.State:Set("Journal.enabled", false)
    addon.State:Set("Journal.enabled", true)
    eq(addon.State:Get("Journal.sessionPlayed"), 3600)
end)

test("enabling the journal later doesn't continue an old session", function()
    local h = Harness.new({ saved = {
        TheLanKrewToolKitDB = { ["Journal.enabled"] = false },
        TheLanKrewToolKitCharDB = { ["Journal.sessionStart"] = 1, ["Journal.sessionSeen"] = 1, ["Journal.sessionQuests"] = 2 },
    } })
    h:LoadAddon("TheLanKrewToolKit")
    h.ns.Addon.State:Set("Journal.enabled", true)
    eq(h.ns.Addon.State:Get("Journal.sessionQuests"), 0)
end)
