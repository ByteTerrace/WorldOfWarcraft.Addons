-- Units of the fake client beyond the player and target: enemy players, nameplates, mouseover,
-- the player's death, combo points, raid target icons and realms (see wow.lua for the rest).
--
-- A unit table (h.player, h:SetTarget, h:SetUnit, h:AddNamePlate, h:SetMouseover) holds:
--   name, surname (players default to Harness.DEFAULT_SURNAME; UnitName returns name, surname,
--   as Forever does), realm (nil = the player's realm; only chat senders and GUID lookups show it),
--   class (the classFile, "WARRIOR"; UnitClass returns className, classFile, classID), level,
--   race (the raceFile, "Human"; GetPlayerInfoByGUID returns its enUS name and it), faction ("Alliance"
--   or "Horde"; UnitFactionGroup returns it and its enUS name; nil = none), isPlayer,
--   playerControlled (defaults to isPlayer), canAttack and isEnemy (relative to the player;
--   isEnemy defaults to canAttack), inCombat (UnitAffectingCombat; the player's is h.inCombat),
--   dead, ghost, health, maxHealth, inGroup, guid (generated on first use when absent),
--   classification (UnitClassification: "normal" when unset; "elite", "rareelite", "worldboss",
--   "rare", "trivial" or "minus"; level -1 is a skull-level unit), comboPoints (the player's on
--   this unit; set through h:SetComboPoints), boss (UnitIsBossMob),
--   and guild, guildRank,
--   guildRankIndex and guildRealm (nil = the player's realm) for a guild member (Harness.New
--   takes the same four for the player).
-- The secret predicates (secrets.lua) stay authoritative: a player-controlled unit's name, class,
-- race and GUID are readable; an NPC's identity is secret.
--
-- Modeling decisions ([D] documented, [G] a guess where the docs are silent):
--   Nameplates  [D] NAME_PLATE_UNIT_ADDED / _REMOVED carry the unit in nameplateN form (the event
--               docs). h:AddNamePlate takes the lowest free nameplate1-40 token. [G] The unit stays
--               readable while NAME_PLATE_UNIT_REMOVED dispatches and stops existing after it.
--               [G] Each token has its own NamePlate frame, created hidden (NAME_PLATE_CREATED) the
--               first time the token is used in a UI session. [E] It carries Blizzard's UnitFrame
--               child (namePlate.enemyNPC), a plain Frame here: its bars and texts aren't modeled.
--               Forbidden nameplates aren't modeled.
--               [G] The client recycles plates and shows or hides the base frame itself
--               (Blizzard_NamePlates never calls Show or Hide on it, and NamePlateBaseMixin
--               checks IsVisible): h:AddNamePlate shows the token's plate before
--               NAME_PLATE_UNIT_ADDED, and h:RemoveNamePlate hides it after
--               NAME_PLATE_UNIT_REMOVED, once the unit is gone. Frames an addon parents to a plate
--               hide and show with it, running OnHide / OnShow like any visibility change
--               (widgets.lua); a recycled plate is the same frame, so its children come back.
--   Mouseover   [D] UPDATE_MOUSEOVER_UNIT fires when the mouseover changes to a unit, and not when
--               it clears (warcraft.wiki.gg: "Does not fire when UnitExists('mouseover') becomes
--               nil"). h:SetMouseover models a 3D unit in the world.
--   Death       [D] PLAYER_DEAD on death; releasing fires PLAYER_ALIVE (the player is a ghost);
--               coming back to life as a ghost fires PLAYER_UNGHOST, and a resurrection before
--               releasing fires PLAYER_ALIVE (warcraft.wiki.gg event pages). [G] PLAYER_DEAD
--               dispatches while combat lockdown still holds, then combat ends like h:LeaveCombat;
--               a revive restores full health.
--   Raid icons  SetRaidTarget is forbidden to addon code (verified in game; see
--               Harness.FORBIDDEN_IN_GAME in secrets.lua, and the wiki says it's protected from
--               12.0.0). Players set icons through Blizzard's UI; nothing reads them, so icons
--               aren't modeled.
--   Combo points [D] They sit on the target: Blizzard's Forever ComboFrame reads
--               GetComboPoints("player", "target") on UNIT_POWER_FREQUENT and PLAYER_TARGET_CHANGED.
--               GetComboPoints(unit, target) answers the target unit's comboPoints when unit is
--               the player, else 0. h:SetComboPoints(n) sets them on the current target and fires
--               UNIT_POWER_FREQUENT("player", "COMBO_POINTS"). [G] Points stay on the unit they
--               were built on: retargeting shows the new target's (usually 0). [D] When they move
--               to another unit they keep their count and no power event fires, only
--               COMBO_TARGET_CHANGED (Blizzard's Forever TargetBoundComboPointBar listens for it);
--               h:MoveComboPoints(unit) moves them.
--   GUIDs       [D] "Player-<server>-<id>" and "Creature-0-<server>-0-<zone>-<npcID>-<spawn>"
--               (the UnitGUID page's format). [G] The ids are deterministic stand-ins.
--               A GUID's unit (h:UnitTokenForGUID) is the first token that names it, in the order
--               player, target, focus, mouseover, pet, vehicle, party, raid, nameplate ([G]).
--               [D] GetPlayerInfoByGUID(guid) returns localizedClass, englishClass, localizedRace,
--               englishRace, sex, name and realmName ("" on your own realm) (warcraft.wiki.gg
--               API_GetPlayerInfoByGUID). [G] The client knows every player unit a test gave a
--               GUID (sex defaults to 2), and nothing about any other GUID.
--   Realms      [D] GetNormalizedRealmName drops spaces and hyphens.
--   Guilds      [D] GetGuildInfo(unit) returns guildName, guildRankName, guildRankIndex (0 = guild
--               master), realm (nil for the player's own realm), and nothing for a unit in no
--               guild or no unit (warcraft.wiki.gg API_GetGuildInfo). It's C API
--               (Ketho/BlizzardInterfaceResources' forever GlobalAPI) the docs don't cover, so it
--               takes no secret arguments and [G] returns no secrets: players' identity isn't
--               secret anyway, and an NPC has no guild. [G] The rank defaults to "Member", index 1.
--               The client only knows a nearby unit's guild; the harness answers for any unit.
--               [D] IsInGuild() (no secret flags) is whether the player has a guild. Guild
--               rosters and PLAYER_GUILD_UPDATE aren't modeled.

Harness.MAX_NAMEPLATES = 40
local ServerId = 5000

-- Each raceFile's enUS race name, for the races Forever characters can be.
local Races = {
    Human = "Human", Orc = "Orc", Dwarf = "Dwarf", NightElf = "Night Elf", Scourge = "Undead", Tauren = "Tauren",
    Gnome = "Gnome", Troll = "Troll",
}
Harness.RACES = Races

-- FACTION_ALLIANCE and FACTION_HORDE (GlobalStrings, enUS).
local Factions = { Alliance = "Alliance", Horde = "Horde" }
Harness.FACTIONS = Factions

-- Unit fields and per-harness unit state, from Harness.New's player spec.
function Harness:InitUnits(player)
    self.player.faction = player.faction or "Alliance"
    self.player.race = player.race or "Human"
    self.player.guild, self.player.guildRealm = player.guild, player.guildRealm
    self.player.guildRank, self.player.guildRankIndex = player.guildRank, player.guildRankIndex
    self.guidSerial = 0
    self.guidUnits = {} -- [guid] = the unit table it was given to
end

-- A unit's GUID, assigned on first use unless the test gave one. A player known only by GUID (a
-- killer, a victim) is a Forever character too, so it gets the default surname.
function Harness:GUID(unit)
    if unit.isPlayer and unit.surname == nil then
        unit.surname = Harness.DEFAULT_SURNAME
    end
    if unit.guid == nil then
        self.guidSerial = self.guidSerial + 1
        if unit.isPlayer then
            unit.guid = ("Player-%d-%08X"):format(ServerId, self.guidSerial)
        else
            unit.guid = ("Creature-0-%d-0-1-%d-%010X"):format(ServerId, unit.npcID or 0, self.guidSerial)
        end
    end
    self.guidUnits[unit.guid] = unit
    return unit.guid
end

-- Every token that can name a unit, in the client's order (see the header).
local function Tokens(h)
    local tokens = { "player", "target", "focus", "mouseover", "pet", "vehicle" }
    for i = 1, 4 do tokens[#tokens + 1] = "party" .. i end
    for i = 1, 40 do tokens[#tokens + 1] = "raid" .. i end
    for i = 1, Harness.MAX_NAMEPLATES do tokens[#tokens + 1] = "nameplate" .. i end
    return tokens
end

-- The first token naming the unit with this GUID, or nil.
function Harness:UnitTokenForGUID(guid)
    guid = Reveal(guid)
    for _, token in ipairs(Tokens(self)) do
        local unit = self:Unit(token)
        if unit and self:GUID(unit) == guid then
            return token
        end
    end
end

-- Gives the unit (a unit table, as h:SetUnit takes it) the lowest free nameplateN token, fires
-- NAME_PLATE_CREATED for a new plate frame, shows the plate, fires NAME_PLATE_UNIT_ADDED(token)
-- and returns the token.
function Harness:AddNamePlate(unit)
    assert(type(unit) == "table", "AddNamePlate: pass a unit table")
    for i = 1, Harness.MAX_NAMEPLATES do
        local token = "nameplate" .. i
        if not self.units[token] then
            self.units[token] = Harness.FillUnit(unit)
            self:SetWidgetShown(self:NamePlateFrame(token), true)
            self:Fire("NAME_PLATE_UNIT_ADDED", token)
            return token
        end
    end
    error("AddNamePlate: all " .. Harness.MAX_NAMEPLATES .. " nameplate tokens are in use", 2)
end

-- Fires NAME_PLATE_UNIT_REMOVED(token) while the unit still exists, removes it, then hides the plate.
function Harness:RemoveNamePlate(token)
    assert(type(token) == "string" and token:find("^nameplate%d+$") and self.units[token],
        "RemoveNamePlate: " .. tostring(token) .. " isn't an active nameplate")
    self:Fire("NAME_PLATE_UNIT_REMOVED", token)
    self.units[token] = nil
    self:SetWidgetShown(self:NamePlateFrame(token), false)
end

-- The token's plate frame, created hidden (with NAME_PLATE_CREATED) the first time this UI
-- session uses it.
function Harness:NamePlateFrame(token)
    local frame = self.namePlateFrames[token]
    if not frame then
        frame = self:CreateWidget("NamePlate", nil, nil)
        frame.UnitFrame = self:CreateWidget("Frame", nil, frame)
        Harness.State(frame).shown = false
        self.namePlateFrames[token] = frame
        self:Fire("NAME_PLATE_CREATED", frame)
    end
    return frame
end

-- The active nameplate token showing this unit table, or nil.
local function PlateTokenFor(h, unit)
    for i = 1, Harness.MAX_NAMEPLATES do
        local token = "nameplate" .. i
        if unit ~= nil and h.units[token] == unit then
            return token
        end
    end
end

-- Sets the "mouseover" unit (nil clears it). A unit fires UPDATE_MOUSEOVER_UNIT; clearing fires
-- nothing, like the client.
function Harness:SetMouseover(unit)
    self.units.mouseover = unit and Harness.FillUnit(unit) or nil
    if unit then
        self:Fire("UPDATE_MOUSEOVER_UNIT")
    end
end

-- A hit on the player: health drops by amount, then UNIT_HEALTH and UNIT_COMBAT("player", "WOUND",
-- flagText, amount, schoolMask 1) fire, as the client sends them for a hit (Blizzard's player
-- frame shows hits from UNIT_COMBAT). [G] The order of the two events. flagText defaults to "",
-- or "ABSORB", "BLOCK", "RESIST", "CRITICAL", "GLANCING", "CRUSHING".
function Harness:HitPlayer(amount, flagText)
    self.player.health = math.max(self.player.health - amount, 0)
    self:Fire("UNIT_HEALTH", "player")
    self:Fire("UNIT_COMBAT", "player", "WOUND", flagText or "", amount, 1)
end

-- A heal on the player: UNIT_HEALTH, then UNIT_COMBAT("player", "HEAL", "", amount, 2).
function Harness:HealPlayer(amount)
    self.player.health = math.min(self.player.health + amount, self.player.maxHealth)
    self:Fire("UNIT_HEALTH", "player")
    self:Fire("UNIT_COMBAT", "player", "HEAL", "", amount, 2)
end

-- Sets the player's combo points on the current target and fires UNIT_POWER_FREQUENT.
function Harness:SetComboPoints(count)
    assert(self.target, "SetComboPoints: there's no target to hold them")
    if self.comboHolder and self.comboHolder ~= self.target then
        self.comboHolder.comboPoints = 0
    end
    self.target.comboPoints, self.comboHolder = count, self.target
    self:Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
end

-- Moves the player's combo points, with their count, to another unit and fires
-- COMBO_TARGET_CHANGED (no power event).
function Harness:MoveComboPoints(unit)
    local holder = assert(self.comboHolder, "MoveComboPoints: no unit holds combo points")
    unit.comboPoints, holder.comboPoints = holder.comboPoints, 0
    self.comboHolder = unit
    self:Fire("COMBO_TARGET_CHANGED")
end

-- The player dies: PLAYER_DEAD (still in combat, if they were), then combat ends.
function Harness:Die()
    assert(not self.player.dead and not self.player.ghost, "Die: the player is already dead")
    self.player.dead, self.player.health = true, 0
    self:Fire("PLAYER_DEAD")
    if self.inCombat then
        self:LeaveCombat()
    end
end

-- Releases the spirit: the player becomes a ghost (UnitIsDeadOrGhost, not UnitIsDead); PLAYER_ALIVE.
function Harness:ReleaseSpirit()
    assert(self.player.dead, "ReleaseSpirit: the player isn't dead")
    self.player.dead, self.player.ghost = false, true
    self:Fire("PLAYER_ALIVE")
end

-- Comes back to life at full health: PLAYER_UNGHOST from a ghost, PLAYER_ALIVE before releasing.
function Harness:Revive()
    local player = self.player
    assert(player.dead or player.ghost, "Revive: the player is alive")
    local wasGhost = player.ghost
    player.dead, player.ghost, player.health = false, false, player.maxHealth
    self:Fire(wasGhost and "PLAYER_UNGHOST" or "PLAYER_ALIVE")
end

-- The unit fakes, merged into the env (env.lua) before it wraps them.
function Harness:UnitFakes()
    local h = self
    local function Unit(token) return h:Unit(token) end
    local function Hostile(a, b, field)
        if a == b or not Unit(a) or not Unit(b) then return false end
        local other = a == "player" and Unit(b) or b == "player" and Unit(a) or nil
        if not other then return false end
        if field == "isEnemy" and other.isEnemy ~= nil then return other.isEnemy end
        return other.canAttack == true
    end
    return {
        -- Hostility is modeled against the player: the other unit's canAttack (isEnemy).
        UnitCanAttack = function(a, b) return Hostile(a, b, "canAttack") end,
        UnitIsEnemy = function(a, b) return Hostile(a, b, "isEnemy") end,
        UnitPlayerControlled = function(u)
            local unit = Unit(u)
            return unit ~= nil and unit.playerControlled == true
        end,
        UnitIsDead = function(u)
            local unit = Unit(u)
            return unit ~= nil and unit.dead == true
        end,
        UnitIsDeadOrGhost = function(u)
            local unit = Unit(u)
            return unit ~= nil and (unit.dead == true or unit.ghost == true)
        end,
        UnitAffectingCombat = function(u)
            local unit = Unit(u)
            if unit == h.player then return h.inCombat end
            return unit ~= nil and unit.inCombat == true
        end,
        UnitFactionGroup = function(u)
            local unit = Unit(u)
            if not unit or unit.faction == nil then return end
            assert(Factions[unit.faction], "UnitFactionGroup: unknown faction " .. tostring(unit.faction))
            return unit.faction, Factions[unit.faction]
        end,
        UnitGUID = function(u)
            local unit = Unit(u)
            return unit and h:GUID(unit) or nil
        end,
        SetRaidTarget = function() end, -- forbidden to addons (tools/api/forbidden.json): never runs
        GetRealmName = function() return h.player.realm end,
        GetGuildInfo = function(u)
            local unit = Unit(u)
            if not unit or unit.guild == nil then return end
            local realm = unit.guildRealm
            if realm ~= nil and Harness.NormalizeRealm(realm) == Harness.NormalizeRealm(h.player.realm) then
                realm = nil
            end
            return unit.guild, unit.guildRank or "Member", unit.guildRankIndex or 1, realm
        end,
        IsInGuild = function() return h.player.guild ~= nil end,
        GetNormalizedRealmName = function() return Harness.NormalizeRealm(h.player.realm) end,
        C_NamePlate = {
            GetNamePlateForUnit = function(token)
                local plate = PlateTokenFor(h, Unit(token))
                return plate and h:NamePlateFrame(plate) or nil
            end,
        },
    }
end
