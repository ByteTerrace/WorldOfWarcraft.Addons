-- The sound bank's variants, the Mortal Kombat announcer and the Unreal Tournament kill streaks,
-- end to end through the real addon files.

local MediaPath = "Interface\\AddOns\\TheLanKrewToolKit\\Media\\"
local Prefix = "TLKKrew1"

local function Load(player)
    local h = Harness.New(player)
    local ns = h:LoadAddon("TheLanKrewToolKit")
    return h, ns.Addon
end

local function Media(h, ...)
    for i = 1, select("#", ...) do
        h:AddMedia(MediaPath .. select(i, ...))
    end
end

local function EnemyPlayer(fields)
    local unit = { name = "Bob", isPlayer = true, canAttack = true, playerControlled = true }
    for key, value in pairs(fields or {}) do unit[key] = value end
    return unit
end

-- The media files played, in order, as one line: "FinishHim.ogg Fatality.ogg".
local function Heard(h)
    local names = {}
    for _, sound in ipairs(h.sounds) do
        names[#names + 1] = sound.path:sub(#MediaPath + 1)
    end
    return table.concat(names, " ")
end

local function Notices(h)
    local texts = {}
    for _, notice in ipairs(h.raidNotices) do
        texts[#texts + 1] = notice.text
    end
    return table.concat(texts, "\n")
end

local function Sent(h, kind)
    local found = {}
    for _, message in ipairs(h.addonMessages) do
        if message.prefix == Prefix and message.message:find("^" .. kind .. ":") then
            found[#found + 1] = message.message
        end
    end
    return found
end

-- Your killing blow on an enemy player: PARTY_KILL(your GUID, theirs).
local function Blow(h, name)
    h:Fire("PARTY_KILL", h.env.UnitGUID("player"), h:GUID({ name = name, isPlayer = true }))
end

-- A fight with an enemy player that dies while targeted; hit makes it not flawless.
local function Kill(h, enemy, hit)
    if not h.inCombat then
        h:EnterCombat()
    end
    if hit then
        h:HitPlayer(10)
    end
    enemy.dead = true
    h:Fire("UNIT_HEALTH", "target")
end

test("a sound plays one of its present variants at random, and /tlk sound can pick one", function()
    local h = Load()
    h:SeedRandom(3)
    Media(h, "FinishHim.ogg", "FinishHim3.mp3")
    for _ = 1, 20 do
        h:Slash("/tlk sound finish")
    end
    local base, third = select(2, Heard(h):gsub("FinishHim%.ogg", "")), select(2, Heard(h):gsub("FinishHim3%.mp3", ""))
    eq(base + third, 20, "every play found a present variant")
    truthy(base > 0 and third > 0, "both variants play")
    h.sounds = {}
    h:Slash("/tlk sound finish 3")
    eq(Heard(h), "FinishHim3.mp3")
    h:Slash("/tlk sound finish 2")
    truthy(h.printed[#h.printed]:find("Put FinishHim2.ogg", 1, true), "a missing variant names its file")
end)

test("test your might plays for elites, bosses and skull-level foes, instead of destiny", function()
    local h = Load()
    Media(h, "TestYourMight.ogg", "ChooseYourDestiny.ogg")
    h:SetTarget({ canAttack = true })
    h:SetTarget({ canAttack = false, classification = "elite" })
    eq(Heard(h), "", "a normal foe and a friendly elite: silent")
    h:SetTarget({ canAttack = true, classification = "elite" })
    eq(Heard(h), "TestYourMight.ogg")
    h:Advance(11)
    h:SetTarget(EnemyPlayer({ level = -1 }))
    eq(Heard(h), "TestYourMight.ogg TestYourMight.ogg", "a skull-level player: might, not destiny")
    h:Advance(11)
    h:SetTarget({ canAttack = true, classification = "worldboss", dead = true })
    eq(Heard(h), "TestYourMight.ogg TestYourMight.ogg", "a dead boss: silent")
end)

test("without a test your might file, a skull-level player still gets destiny", function()
    local h = Load()
    Media(h, "ChooseYourDestiny.ogg")
    h:SetTarget(EnemyPlayer({ level = -1 }))
    eq(Heard(h), "ChooseYourDestiny.ogg")
end)

test("rogues hear each combo point, and finish him at five on an enemy player", function()
    local h = Load({ classFile = "ROGUE", powerType = 3 })
    Media(h, "ComboPoint1.ogg", "ComboPoint2.ogg", "ComboPoint3.ogg", "ComboPoint4.ogg", "ComboPoint5.ogg", "FinishHim.ogg")
    h:SetTarget(EnemyPlayer())
    for points = 1, 5 do
        h:SetComboPoints(points)
    end
    eq(Heard(h), "ComboPoint1.ogg ComboPoint2.ogg ComboPoint3.ogg ComboPoint4.ogg FinishHim.ogg")
    h:SetComboPoints(0)
    h:SetComboPoints(0)
    eq(#h.sounds, 5, "spending them is silent")
    h:SetTarget({ canAttack = true })
    h:SetComboPoints(4)
    h:SetComboPoints(5)
    eq(Heard(h):match("%S+$"), "ComboPoint5.ogg", "a creature's fifth point is a plain callout")
end)

test("combo callouts are rogues' and druids' only, and switch off with their setting", function()
    local h, addon = Load({ classFile = "WARRIOR", powerType = 1 })
    falsy(addon.Events.Frame:IsEventRegistered("UNIT_POWER_FREQUENT"), "warriors have no combo points")
    h, addon = Load({ classFile = "DRUID", powerType = 0 }) -- caster form: the fuck-o-meter stays off
    Media(h, "ComboPoint1.ogg")
    h:SetTarget({ canAttack = true })
    h:SetComboPoints(1)
    eq(Heard(h), "ComboPoint1.ogg")
    addon.State:Set("Kombat.comboPoints", false)
    addon.State:Set("Kombat.finishHim", false)
    addon.State:Set("Kombat.fatality", false)
    falsy(addon.Events.Frame:IsEventRegistered("UNIT_POWER_FREQUENT"), "nothing needs combo points")
end)

test("a kill after finish him is a fatality; flawless still comes first", function()
    local h = Load({ classFile = "WARRIOR", powerType = 1 })
    Media(h, "FinishHim.ogg", "Fatality.ogg", "FlawlessVictory.ogg", "SuperbVictory.ogg")
    local enemy = EnemyPlayer()
    h:SetTarget(enemy)
    h.usable.Execute = { true, false }
    h:Fire("SPELL_UPDATE_USABLE")
    Kill(h, enemy, true)
    eq(Heard(h), "FinishHim.ogg Fatality.ogg")
    h:LeaveCombat()
    h:Advance(5) -- the last fight's hit is long past
    h.sounds = {}
    enemy = EnemyPlayer()
    h:SetTarget(enemy)
    h:Fire("SPELL_UPDATE_USABLE")
    Kill(h, enemy, false)
    eq(Heard(h), "FinishHim.ogg FlawlessVictory.ogg", "untouched: flawless")
end)

test("any other kill in your fight is a superb victory; kills out of combat are silent", function()
    local h = Load()
    Media(h, "SuperbVictory.ogg", "Fatality.ogg")
    local enemy = EnemyPlayer()
    h:SetTarget(enemy)
    enemy.dead = true
    h:Fire("UNIT_HEALTH", "target")
    eq(Heard(h), "", "someone else's kill")
    enemy = EnemyPlayer()
    h:SetTarget(enemy)
    Kill(h, enemy, true)
    eq(Heard(h), "SuperbVictory.ogg", "no finisher: never a fatality")
end)

test("a death taunt plays when you die", function()
    local h, addon = Load()
    Media(h, "DeathTaunt.ogg", "DeathTaunt2.ogg")
    h:Die()
    truthy(Heard(h):find("^DeathTaunt2?%.ogg$"), Heard(h))
    h:Revive()
    addon.State:Set("Kombat.deathTaunt", false)
    falsy(addon.Events.Frame:IsEventRegistered("PLAYER_DEAD") and addon.Modules.DeathTaunt.Enabled, "off")
    h:Die()
    eq(#h.sounds, 1)
end)

test("the master switch silences every Kombat sound", function()
    local h, addon = Load()
    Media(h, "ChooseYourDestiny.ogg", "DeathTaunt.ogg")
    addon.State:Set("Sounds.enabled", false)
    h:SetTarget(EnemyPlayer())
    h:Die()
    eq(Heard(h), "")
end)

test("killing blows announce first blood, multi kills and sprees", function()
    local h = Load()
    Media(h, "FirstBlood.ogg", "DoubleKill.ogg", "MultiKill.ogg", "KillingSpree.ogg")
    Blow(h, "Ann")
    eq(Heard(h), "FirstBlood.ogg")
    h:Advance(5)
    Blow(h, "Ben")
    h:Advance(5)
    Blow(h, "Cid")
    eq(Heard(h), "FirstBlood.ogg DoubleKill.ogg MultiKill.ogg")
    h:Advance(30)
    Blow(h, "Dee")
    eq(#h.sounds, 3, "a lone kill after first blood: silent")
    h:Advance(30)
    Blow(h, "Eve")
    eq(Heard(h):match("%S+$"), "KillingSpree.ogg", "five without dying")
    eq(Notices(h), "First blood!\nDouble kill!\nMulti kill!\nKilling spree! 5 kills without dying.")
end)

test("dying ends the spree; bonus honor isn't a kill", function()
    local h, addon = Load()
    Media(h, "KillingSpree.ogg")
    for i = 1, 4 do
        Blow(h, "Foe" .. i)
        h:Advance(20)
    end
    h:AwardHonor(100)
    eq(addon.State:Get("kills.streak"), 4)
    h:Die()
    eq(addon.State:Get("kills.streak"), 0)
    h:Revive()
    Blow(h, "Foe5")
    eq(#h.sounds, 0, "the spree started over")
end)

test("the Krew hears your first blood, sprees and a spree's end, and yours yields to theirs", function()
    local h, addon = Load()
    h:JoinGroup("party", { "Mom" })
    h:Echo(false)
    h:Advance(2)
    h:ReceiveAddonMessage(Prefix, "STREAK:firstBlood\t1", "PARTY", "Mom")
    eq(Notices(h), "Mom Doe drew first blood!")
    for i = 1, 5 do
        Blow(h, "Foe" .. i)
        h:Advance(20)
    end
    eq(#Sent(h, "STREAK"), 1, "first blood was Mom's")
    eq(Sent(h, "STREAK")[1], "STREAK:killingSpree\t5")
    h:Die()
    h:Advance(4) -- no death recap: after the wait, the spree ends with no killer named
    eq(Sent(h, "STREAK")[2], "STREAK:ended\t5")
    h:ReceiveAddonMessage(Prefix, "STREAK:rampage\t10", "PARTY", "Mom")
    truthy(Notices(h):find("Mom Doe is on a rampage! (10 kills)", 1, true))
    h:ReceiveAddonMessage(Prefix, "STREAK:rampage\tlots", "PARTY", "Mom")
    h:ReceiveAddonMessage(Prefix, "STREAK:rampage\t1e1", "PARTY", "Mom")
    h:ReceiveAddonMessage(Prefix, "STREAK:rampage\t0x0A", "PARTY", "Mom")
    h:ReceiveAddonMessage(Prefix, "STREAK:nonsense\t3", "PARTY", "Mom")
    eq(select(2, Notices(h):gsub("\n", "")), 2, "malformed messages show nothing")
    addon.State:Set("Streaks.share", false)
    h:Revive()
    for i = 6, 10 do
        Blow(h, "Foe" .. i)
        h:Advance(20)
    end
    eq(#Sent(h, "STREAK"), 2, "sharing off")
end)

test("streaks and Warband both off: honor messages aren't even registered", function()
    local h, addon = Load()
    addon.State:Set("Warband.enabled", false)
    truthy(addon.Events.Frame:IsEventRegistered("CHAT_MSG_COMBAT_HONOR_GAIN"), "streaks still listen")
    addon.State:Set("Streaks.enabled", false)
    falsy(addon.Events.Frame:IsEventRegistered("CHAT_MSG_COMBAT_HONOR_GAIN"))
end)

test("a duel you were hit in may be one you lost: it plays nothing", function()
    local h = Load({ classFile = "MAGE", powerType = 0 })
    Media(h, "SuperbVictory.ogg", "FlawlessVictory.ogg")
    h:SetTarget(EnemyPlayer())
    h:EnterCombat()
    h:HitPlayer(h.player.health - 1)
    h:Fire("DUEL_FINISHED") -- you lost at 1 HP; your opponent is alive and still attackable
    eq(Heard(h), "")
end)

test("the fifth combo point calls out again on a second build, and when finish him has no file", function()
    local h = Load({ classFile = "ROGUE", powerType = 3 })
    Media(h, "ComboPoint1.ogg", "ComboPoint2.ogg", "ComboPoint3.ogg", "ComboPoint4.ogg", "ComboPoint5.ogg", "FinishHim.ogg")
    h:SetTarget(EnemyPlayer())
    for points = 1, 5 do
        h:SetComboPoints(points)
    end
    h:SetComboPoints(0)
    h.sounds = {}
    for points = 1, 5 do
        h:SetComboPoints(points)
    end
    eq(Heard(h), "ComboPoint1.ogg ComboPoint2.ogg ComboPoint3.ogg ComboPoint4.ogg ComboPoint5.ogg", "finish him was the first build's")
    h = Load({ classFile = "ROGUE", powerType = 3 })
    Media(h, "ComboPoint4.ogg", "ComboPoint5.ogg")
    h:SetTarget(EnemyPlayer())
    h:SetComboPoints(4)
    h:SetComboPoints(5)
    eq(Heard(h), "ComboPoint4.ogg ComboPoint5.ogg", "no FinishHim file")
end)

test("a death ends the spree and the multi kill at once, even before the recap names the killer", function()
    local h = Load()
    h:JoinGroup("party", { "Mom" })
    h:Echo(false)
    h:Advance(2)
    Media(h, "DoubleKill.ogg")
    for i = 1, 7 do
        Blow(h, "Foe" .. i)
        h:Advance(20)
    end
    Blow(h, "Foe8")
    h:Advance(3)
    h:Die()
    h:Advance(1)
    Blow(h, "Foe9") -- the group's kill, credited while you're dead
    h:Advance(4)
    eq(Heard(h), "", "a death between two kills ends the multi kill")
    local sent = Sent(h, "STREAK")
    eq(sent[#sent], "STREAK:ended\t8", "the Krew hears the 8-kill spree ended")
end)

test("a kill streak counts your killing blows and your pet's, not a groupmate's or a creature's", function()
    local h, addon = Load()
    local pet = { name = "Wolf", playerControlled = true }
    h:SetUnit("pet", pet)
    local mom = { name = "Mom", isPlayer = true }
    h:HonorKill("Ann", "Private", 10) -- honor credit for a groupmate's kill
    h:Fire("PARTY_KILL", h:GUID(mom), h:GUID({ name = "Ben", isPlayer = true }))
    h:Fire("PARTY_KILL", h.env.UnitGUID("player"), h:GUID({ name = "Kobold" }))
    eq(addon.State:Get("kills.blows"), 0)
    eq(addon.State:Get("kills.honorable"), 1, "the honor credit still counts for Warband")
    h:Fire("PARTY_KILL", h:GUID(pet), h:GUID({ name = "Cid", isPlayer = true }))
    Blow(h, "Dee")
    eq(addon.State:Get("kills.blows"), 2)
    eq(addon.State:Get("kills.streak"), 2)
end)

test("a sound test tells a muted channel from a missing file", function()
    local h = Load()
    Media(h, "FinishHim.ogg")
    h.mutedChannels.Master = true
    h:Slash("/tlk sound finish")
    truthy(h.printed[#h.printed]:find("though its file is there", 1, true), h.printed[#h.printed])
    h:Slash("/tlk sound fatality")
    truthy(h.printed[#h.printed]:find("Put Fatality.ogg", 1, true), h.printed[#h.printed])
end)

test("points that move off the target count as gone, so building again calls out from one", function()
    local h = Load({ classFile = "ROGUE", powerType = 3 })
    Media(h, "ComboPoint1.ogg", "ComboPoint3.ogg")
    h:SetTarget(EnemyPlayer())
    h:SetComboPoints(3)
    h:MoveComboPoints({ name = "Kobold Vermin", canAttack = true })
    eq(h.env.GetComboPoints("player", "target"), 0)
    h:SetComboPoints(1)
    eq(Heard(h), "ComboPoint3.ogg ComboPoint1.ogg")
end)
