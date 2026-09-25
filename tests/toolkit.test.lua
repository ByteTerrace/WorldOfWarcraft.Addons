-- TheLanKrewToolKit behavior, end to end through the real addon files.

local MEDIA = "Interface\\AddOns\\TheLanKrewToolKit\\Media\\"

local function Load(player)
    local h = Harness.new(player)
    local ns = h:LoadAddon("TheLanKrewToolKit")
    return h, ns.addon
end

local function EnemyPlayer(fields)
    local unit = { isPlayer = true, canAttack = true }
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

-- Load and settings -----------------------------------------------------------

test("loads cleanly and builds its settings panel", function()
    local h = Load()
    eq(table.concat(h.settingsOrder, ","), table.concat({
        "TheLanKrewToolKit_FuckOMeter.enabled",
        "TheLanKrewToolKit_Sounds.enabled", "TheLanKrewToolKit_Sounds.channel",
        "TheLanKrewToolKit_Sounds.combatStart", "TheLanKrewToolKit_Sounds.stopOnCombatEnd",
        "TheLanKrewToolKit_Sounds.chooseYourDestiny", "TheLanKrewToolKit_Sounds.flawlessVictory",
        "TheLanKrewToolKit_Sounds.finishHim",
        "TheLanKrewToolKit_LightBar.enabled", "TheLanKrewToolKit_Rumble.enabled",
        "TheLanKrewToolKit_addon.debug",
    }, ","))
end)

-- Fuck-o-meter -------------------------------------------------------------

test("fuck-o-meter shows for energy users and passes secret energy straight to the widgets", function()
    local h = Load({ class = "ROGUE", powerType = 3 })
    local meter = h.env.TheLanKrewToolKitFuckOMeter
    truthy(meter:IsShown())
    h:EnterCombat()
    h.player.power[3] = 42
    h:ResetCalls()
    h:Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
    truthy(h.env.issecretvalue(meter.bar.value), "value arrived as a secret")
    eq(Reveal(meter.bar.value), 42)
    eq(Reveal(meter.value.text), 42)
    eq(meter.bar.calls.SetValue, 1, "one SetValue per power event")
    eq(meter.bar.calls.SetMinMaxValues, nil, "range isn't touched on power ticks")
end)

test("fuck-o-meter ignores other power types and stays unregistered for non-energy users", function()
    local h = Load({ class = "MAGE", powerType = 0 })
    local meter = h.env.TheLanKrewToolKitFuckOMeter
    falsy(meter:IsShown())
    local addon = h.ns.addon
    falsy(addon.events.frame:IsEventRegistered("UNIT_POWER_FREQUENT"), "no power events without energy")
    h.player.powerType = 3
    h:Fire("UNIT_DISPLAYPOWER", "player")
    truthy(meter:IsShown(), "cat form shows it")
    h:ResetCalls()
    h:Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    eq(meter.bar.calls.SetValue, nil, "mana ticks don't touch the bar")
end)

test("fom toggles the meter off and removes its events", function()
    local h = Load()
    local meter = h.env.TheLanKrewToolKitFuckOMeter
    h:Slash("/tlk fom")
    falsy(meter:IsShown())
    falsy(h.ns.addon.events.frame:IsEventRegistered("UNIT_POWER_FREQUENT"))
    eq(h.env.TheLanKrewToolKitDB["FuckOMeter.enabled"], false, "persisted")
end)

-- Sounds -------------------------------------------------------------------

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

test("combat start respects its toggle and the channel setting", function()
    local h, addon = Load()
    h:AddMedia(MEDIA .. "CombatStart.ogg")
    h:Slash("/tlk set Sounds.channel SFX")
    h:EnterCombat()
    eq(h.sounds[1].channel, "SFX")
    h:LeaveCombat()
    addon.state:Set("Sounds.combatStart", false)
    h:EnterCombat()
    eq(Played(h, "CombatStart.ogg"), 1, "disabled sound doesn't play")
end)

test("choose your destiny plays on targeting a living enemy player, at most every 10 seconds", function()
    local h = Load()
    h:AddMedia(MEDIA .. "ChooseYourDestiny.ogg")
    h:SetTarget({ isPlayer = false, canAttack = true })
    h:SetTarget({ isPlayer = true, canAttack = false })
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

test("flawless victory: full health at the start, no hits, enemy player target dies", function()
    local h = Load()
    h:AddMedia(MEDIA .. "FlawlessVictory.ogg")
    local enemy = EnemyPlayer()
    h:SetTarget(enemy)
    h:EnterCombat()
    enemy.dead = true
    h:Fire("UNIT_HEALTH", "target")
    eq(Played(h, "FlawlessVictory.ogg"), 1)
end)

test("flawless victory is lost after taking a hit in combat, even if healed", function()
    local h = Load()
    h:AddMedia(MEDIA .. "FlawlessVictory.ogg")
    local enemy = EnemyPlayer()
    h:SetTarget(enemy)
    h:EnterCombat()
    h.player.health = 80
    h:Fire("UNIT_HEALTH", "player")
    h.player.health = 100
    h:Fire("UNIT_HEALTH", "player")
    enemy.dead = true
    h:Fire("UNIT_HEALTH", "target")
    eq(Played(h, "FlawlessVictory.ogg"), 0)
end)

test("flawless victory needs full health going in, and never fires for a selected corpse", function()
    local h = Load()
    h:AddMedia(MEDIA .. "FlawlessVictory.ogg")
    h.player.health = 90
    h:Fire("UNIT_HEALTH", "player")
    local enemy = EnemyPlayer()
    h:SetTarget(enemy)
    h:EnterCombat()
    enemy.dead = true
    h:Fire("UNIT_HEALTH", "target")
    eq(Played(h, "FlawlessVictory.ogg"), 0, "not full at the start")
    h:LeaveCombat()
    h.player.health = 100
    h:Fire("UNIT_HEALTH", "player")
    local corpse = EnemyPlayer({ dead = true })
    h:SetTarget(corpse)
    h:Fire("UNIT_HEALTH", "target")
    eq(Played(h, "FlawlessVictory.ogg"), 0, "corpse")
    corpse.dead = false
    h:Fire("UNIT_HEALTH", "target")
    corpse.dead = true
    h:Fire("UNIT_HEALTH", "target")
    eq(Played(h, "FlawlessVictory.ogg"), 1, "resurrected, then died while targeted")
end)

test("finish him: warriors, once per entry into Execute range, re-armed per target", function()
    local h = Load({ class = "WARRIOR", powerType = 1 })
    h:AddMedia(MEDIA .. "FinishHim.ogg")
    h:SetTarget(EnemyPlayer())
    h:EnterCombat()
    h:Fire("SPELL_UPDATE_USABLE")
    eq(Played(h, "FinishHim.ogg"), 0, "above 20%")
    h.usable.Execute = { false, true } -- in range, not enough rage: still in range
    h:Fire("SPELL_UPDATE_USABLE")
    eq(Played(h, "FinishHim.ogg"), 1)
    h.usable.Execute = { true, false }
    h:Fire("SPELL_UPDATE_USABLE")
    eq(Played(h, "FinishHim.ogg"), 1, "still in range: once")
    h:SetTarget(EnemyPlayer())
    eq(Played(h, "FinishHim.ogg"), 2, "a new target in range announces again")
end)

test("finish him never runs for other classes", function()
    local h = Load({ class = "ROGUE" })
    h:AddMedia(MEDIA .. "FinishHim.ogg")
    h.usable.Execute = { true, false }
    h:SetTarget(EnemyPlayer())
    falsy(h.ns.addon.events.frame:IsEventRegistered("SPELL_UPDATE_USABLE"), "no usability polling")
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

test("disabling sounds unregisters every sound event", function()
    local h, addon = Load({ class = "WARRIOR", powerType = 1 })
    addon.state:Set("Sounds.enabled", false)
    local frame = addon.events.frame
    falsy(frame:IsEventRegistered("PLAYER_TARGET_CHANGED"))
    falsy(frame:IsEventRegistered("SPELL_UPDATE_USABLE"))
    falsy(frame:IsEventRegistered("UNIT_HEALTH"))
end)

-- Controller ---------------------------------------------------------------

test("light bar is green, red in combat, yellow when AFK, and cleared when disabled", function()
    local h, addon = Load()
    eq(table.concat(h.led, ","), "0,1,0")
    h:EnterCombat()
    eq(table.concat(h.led, ","), "1,0,0", "red as combat starts, before lockdown")
    h:LeaveCombat()
    h.player.afk = true
    h:Fire("PLAYER_FLAGS_CHANGED", "player")
    eq(table.concat(h.led, ","), "1,1,0")
    addon.state:Set("LightBar.enabled", false)
    eq(h.led, nil)
end)

test("rumble is strong entering combat and light leaving it, never at login", function()
    local h = Load()
    eq(#h.vibrations, 0)
    h:EnterCombat()
    h:LeaveCombat()
    eq(h.vibrations[1][1], "High")
    eq(h.vibrations[2][1], "Low")
end)
