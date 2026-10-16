-- Units of the fake client beyond the player and target: enemy players, nameplates, mouseover, the player's death,
-- combo points, raid target icons, realms, and aura sounds (see wow.lua for the rest).
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
--   "rare", "trivial", or "minus"; level -1 is a skull-level unit), comboPoints (the player's on
--   this unit; set through h:SetComboPoints), boss (UnitIsBossMob),
--   and guild, guildRank,
--   guildRankIndex, and guildRealm (nil = the player's realm) for a guild member (Harness.New
--   takes the same four for the player).
-- The secret predicates (secrets.lua) stay authoritative: a player-controlled unit's name, class, race, and GUID are
-- readable. An NPC's identity is secret.
--
-- Modeling decisions ([D] documented, [G] a guess where the docs are silent):
--   Nameplates  [D] NAME_PLATE_UNIT_ADDED / _REMOVED carry the unit in nameplateN form (the event
--               docs). h:AddNamePlate takes the lowest free nameplate1-40 token. [G] The unit stays
--               readable while NAME_PLATE_UNIT_REMOVED dispatches and stops existing after it (namePlates.events asks the client).
--               [G] Each token has its own NamePlate frame, created hidden (NAME_PLATE_CREATED) the
--               first time the token is used in a UI session. [E] It carries Blizzard's UnitFrame
--               child (namePlate.enemyNPC), a plain Frame here: its bars and texts aren't modeled.
--               Forbidden nameplates aren't modeled.
--               [G] The client recycles plates and shows or hides the base frame itself
--               (Blizzard_NamePlates never calls Show or Hide on it, and NamePlateBaseMixin
--               checks IsVisible): h:AddNamePlate shows the token's plate before
--               NAME_PLATE_UNIT_ADDED, and h:RemoveNamePlate hides it after
--               NAME_PLATE_UNIT_REMOVED, once the unit is gone (namePlates.events). Frames an addon parents to a plate
--               hide and show with it, running OnHide / OnShow like any visibility change
--               (widgets.lua). A recycled plate is the same frame, so its children come back.
--   Mouseover   [D] UPDATE_MOUSEOVER_UNIT fires when the mouseover changes to a unit, and not when
--               it clears (warcraft.wiki.gg: "Does not fire when UnitExists('mouseover') becomes
--               nil"). h:SetMouseover models a 3D unit in the world.
--   Death       [D] PLAYER_DEAD on death; releasing fires PLAYER_ALIVE (the player is a ghost);
--               coming back to life as a ghost fires PLAYER_UNGHOST, and a resurrection before
--               releasing fires PLAYER_ALIVE (warcraft.wiki.gg event pages). [E] PLAYER_DEAD
--               dispatches while combat lockdown and the restrictions still hold, with
--               UnitAffectingCombat("player") already false for the dead player
--               (death.combatState), then combat ends like h:LeaveCombat. [G] A revive restores
--               full health.
--   Flights     [D] Taking a flight path takes the character's control (PLAYER_CONTROL_LOST) and
--               landing gives it back (PLAYER_CONTROL_GAINED); UnitOnTaxi("player") is true in
--               between. [G] Control goes before UnitOnTaxi turns true, and comes back after it
--               turns false. h:TakeFlight() and h:Land().
--   Raid icons  SetRaidTarget is forbidden to addon code (verified in game; see
--               Harness.FORBIDDEN_IN_GAME in secrets.lua, and the wiki says it's protected from
--               12.0.0). Players set icons through Blizzard's UI. Nothing reads them, so icons
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
--               englishRace, sex, name, and realmName ("" on your own realm) (warcraft.wiki.gg
--               API_GetPlayerInfoByGUID). [G] The client knows every player unit a test gave a
--               GUID (sex defaults to 2), and nothing about any other GUID.
--   Realms      [D] GetNormalizedRealmName drops spaces and hyphens.
--   Guilds      [D] GetGuildInfo(unit) returns guildName, guildRankName, guildRankIndex (0 = guild
--               master), realm, and nothing for a unit in no guild or no unit (warcraft.wiki.gg
--               API_GetGuildInfo). [E] The realm of your own guild is a string, not the nil the
--               page gives (guild.player). [G] It's "" on your own realm; version 2 of the probe
--               asks which string it is. It's C API
--               (Ketho/BlizzardInterfaceResources' forever GlobalAPI) the docs don't cover, so it
--               takes no secret arguments and [G] returns no secrets: players' identity isn't
--               secret anyway, and an NPC has no guild. [G] The rank defaults to "Member", index 1.
--               The client only knows a nearby unit's guild. The harness answers for any unit.
--               [D] IsInGuild() (no secret flags) is whether the player has a guild. Guild
--               rosters and PLAYER_GUILD_UPDATE aren't modeled.
--   Aura sounds [D] C_UnitAuras.AddAuraSound(trigger, sound) registers a sound for an aura event
--               and returns its auraSoundID (Nilable), and RemoveAuraSound(auraSoundID) undoes it
--               (UnitAuraDocumentation). trigger is an Enum.UnitAuraSoundTrigger value; sound is a
--               UnitAuraSoundInfo: unitToken and spellID (not Nilable), soundFileName,
--               soundFileID, outputChannel, and throttleSeconds (Nilable). [D] A throttleSeconds
--               outside 0 to 5 "rejects registration": no ID. [G] A trigger that isn't an enum
--               value, or a sound without its unitToken or spellID, is an error; the sound file
--               isn't checked when it registers; IDs count up from 1 per harness; removing an ID
--               that isn't registered does nothing. Registrations are kept in h.auraSounds
--               ([auraSoundID] = { trigger, sound }). [G] HasRestrictions without a marker:
--               blocked during combat lockdown (secrets.lua). Playing the sounds on aura events
--               isn't modeled.

Harness.MAX_NAMEPLATES = 40
local ServerId = 5000

-- Each raceFile's enUS race name, for the races Forever characters can be.
local Races = {
    Dwarf = "Dwarf", Gnome = "Gnome", Human = "Human", NightElf = "Night Elf", Orc = "Orc", Scourge = "Undead",
    Tauren = "Tauren", Troll = "Troll",
}

Harness.RACES = Races

-- FACTION_ALLIANCE and FACTION_HORDE (GlobalStrings, enUS).
local Factions = { Alliance = "Alliance", Horde = "Horde" }

Harness.FACTIONS = Factions

-- Unit fields and per-harness unit state, from Harness.New's player spec.
function Harness:InitUnits(player)
    self.player.faction = (player.faction or "Alliance")
    self.player.race = (player.race or "Human")
    self.player.guild, self.player.guildRealm = player.guild, player.guildRealm
    self.player.guildRank, self.player.guildRankIndex = player.guildRank, player.guildRankIndex
    self.guidSerial = 0
    -- The unit table each GUID was given to, by GUID.
    self.guidUnits = {}
    -- Each auraSoundID's { trigger, sound } (C_UnitAuras.AddAuraSound).
    self.auraSounds = {}
    self.auraSoundSerial = 0
end

-- The aura sound throttle's documented bounds, in seconds (UnitAuraSoundInfo.throttleSeconds).
local AuraSoundThrottle = { max = 5, min = 0 }

-- C_UnitAuras.AddAuraSound (see the header): the new auraSoundID, or nil when it's rejected.
local function AddAuraSound(h, trigger, sound)
    local known = false

    for _, value in pairs(h.env.Enum.UnitAuraSoundTrigger) do
        known = (known or (value == trigger))
    end

    if not known then
        error("C_UnitAuras.AddAuraSound: bad argument #1 (trigger must be an Enum.UnitAuraSoundTrigger value)", 3)
    end

    if (type(sound) ~= "table") or (type(sound.unitToken) ~= "string") or (type(sound.spellID) ~= "number") then
        error("C_UnitAuras.AddAuraSound: bad argument #2 (sound must be a UnitAuraSoundInfo with unitToken and spellID)", 3)
    end

    local throttle = sound.throttleSeconds

    if (throttle ~= nil) and ((type(throttle) ~= "number") or (throttle < AuraSoundThrottle.min) or (throttle > AuraSoundThrottle.max)) then
        return nil
    end

    h.auraSoundSerial = (h.auraSoundSerial + 1)
    local copy = {}

    for key, value in pairs(sound) do copy[key] = value end

    h.auraSounds[h.auraSoundSerial] = { sound = copy, trigger = trigger }

    return h.auraSoundSerial
end

-- The active nameplate token showing this unit table, or nil.
local function PlateTokenFor(h, unit)
    for i = 1, Harness.MAX_NAMEPLATES do
        local token = ("nameplate" .. i)

        if (unit ~= nil) and (h.units[token] == unit) then
            return token
        end
    end
end

-- Every token that can name a unit, in the client's order (see the header).
local function Tokens()
    local tokens = { "player", "target", "focus", "mouseover", "pet", "vehicle" }

    for i = 1, 4 do tokens[#tokens + 1] = ("party" .. i) end

    for i = 1, 40 do tokens[#tokens + 1] = ("raid" .. i) end

    for i = 1, Harness.MAX_NAMEPLATES do tokens[#tokens + 1] = ("nameplate" .. i) end

    return tokens
end

-- Gives the unit (a unit table, as h:SetUnit takes it) the lowest free nameplateN token, fires NAME_PLATE_CREATED for a
-- new plate frame, shows the plate, fires NAME_PLATE_UNIT_ADDED(token), and returns the token.
function Harness:AddNamePlate(unit)
    assert(type(unit) == "table", "AddNamePlate: pass a unit table")

    for i = 1, Harness.MAX_NAMEPLATES do
        local token = ("nameplate" .. i)

        if not self.units[token] then
            self.units[token] = Harness.FillUnit(unit)
            self:SetWidgetShown(self:NamePlateFrame(token), true)
            self:Fire("NAME_PLATE_UNIT_ADDED", token)

            return token
        end
    end

    error("AddNamePlate: all " .. Harness.MAX_NAMEPLATES .. " nameplate tokens are in use", 2)
end

-- The player dies: PLAYER_DEAD (still in combat, if they were), then afterDeath() if given (what reaches the damage
-- meter after it), then combat ends.
function Harness:Die(afterDeath)
    assert(not self.player.dead and not self.player.ghost, "Die: the player is already dead")
    self.player.dead, self.player.health = true, 0
    self:Fire("PLAYER_DEAD")

    if afterDeath then
        afterDeath()
    end

    if self.inCombat then
        self:LeaveCombat()
    end
end

-- A unit's GUID, assigned on first use unless the test gave one. A player known only by GUID (a killer, a victim) is a
-- Forever character too, so it gets the default surname.
function Harness:GUID(unit)
    if unit.isPlayer and (unit.surname == nil) then
        unit.surname = Harness.DEFAULT_SURNAME
    end

    if unit.guid == nil then
        self.guidSerial = (self.guidSerial + 1)

        if unit.isPlayer then
            unit.guid = ("Player-%d-%08X"):format(ServerId, self.guidSerial)
        else
            unit.guid = ("Creature-0-%d-0-1-%d-%010X"):format(ServerId, unit.npcID or 0, self.guidSerial)
        end
    end

    self.guidUnits[unit.guid] = unit

    return unit.guid
end

-- A heal on the player: UNIT_HEALTH, then UNIT_COMBAT("player", "HEAL", "", amount, 2).
function Harness:HealPlayer(amount)
    self.player.health = math.min(self.player.health + amount, self.player.maxHealth)
    self:Fire("UNIT_HEALTH", "player")
    self:Fire("UNIT_COMBAT", "player", "HEAL", "", amount, 2)
end

-- A hit on the player: health drops by amount, then UNIT_HEALTH and UNIT_COMBAT("player", "WOUND", flagText, amount,
-- schoolMask 1) fire, as the client sends them for a hit (Blizzard's player frame shows hits from UNIT_COMBAT). [G] The
-- order of the two events. flagText defaults to "", or "ABSORB", "BLOCK", "RESIST", "CRITICAL", "GLANCING", "CRUSHING".
function Harness:HitPlayer(amount, flagText)
    self.player.health = math.max(self.player.health - amount, 0)
    self:Fire("UNIT_HEALTH", "player")
    self:Fire("UNIT_COMBAT", "player", "WOUND", flagText or "", amount, 1)
end

-- The flight lands: UnitOnTaxi("player") is false, then PLAYER_CONTROL_GAINED.
function Harness:Land()
    assert(self.player.onTaxi, "Land: not flying")
    self.player.onTaxi = false
    self:Fire("PLAYER_CONTROL_GAINED")
end

-- The player reaches level: h.player.level, then PLAYER_LEVEL_UP with the documented payload ([D] UnitDocumentation:
-- level, then nine deltas, the last spiritDelta; [G] the deltas are 0).
function Harness:LevelUp(level)
    self.player.level = level
    self:Fire("PLAYER_LEVEL_UP", level, 0, 0, 0, 0, 0, 0, 0, 0, 0)
end

-- Moves the player's combo points, with their count, to another unit and fires COMBO_TARGET_CHANGED (no power event).
function Harness:MoveComboPoints(unit)
    local holder = assert(self.comboHolder, "MoveComboPoints: no unit holds combo points")

    unit.comboPoints, holder.comboPoints = holder.comboPoints, 0
    self.comboHolder = unit
    self:Fire("COMBO_TARGET_CHANGED")
end

-- The token's plate frame, created hidden (with NAME_PLATE_CREATED) the first time this UI session uses it.
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

-- Releases the spirit: the player becomes a ghost (UnitIsDeadOrGhost, not UnitIsDead), and PLAYER_ALIVE fires.
function Harness:ReleaseSpirit()
    assert(self.player.dead, "ReleaseSpirit: the player isn't dead")
    self.player.dead, self.player.ghost = false, true
    self:Fire("PLAYER_ALIVE")
end

-- Fires NAME_PLATE_UNIT_REMOVED(token) while the unit still exists, removes it, then hides the plate.
function Harness:RemoveNamePlate(token)
    assert((type(token) == "string") and token:find("^nameplate%d+$") and self.units[token],
        "RemoveNamePlate: " .. tostring(token) .. " isn't an active nameplate")

    self:Fire("NAME_PLATE_UNIT_REMOVED", token)
    self.units[token] = nil
    self:SetWidgetShown(self:NamePlateFrame(token), false)
end

-- Comes back to life at full health: PLAYER_UNGHOST from a ghost, PLAYER_ALIVE before releasing.
function Harness:Revive()
    local player = self.player

    assert(player.dead or player.ghost, "Revive: the player is alive")
    local wasGhost = player.ghost

    player.dead, player.ghost, player.health = false, false, player.maxHealth
    self:Fire((wasGhost and "PLAYER_UNGHOST") or "PLAYER_ALIVE")
end

-- Sets the player's combo points on the current target and fires UNIT_POWER_FREQUENT.
function Harness:SetComboPoints(count)
    assert(self.target, "SetComboPoints: there's no target to hold them")

    if self.comboHolder and (self.comboHolder ~= self.target) then
        self.comboHolder.comboPoints = 0
    end

    self.target.comboPoints, self.comboHolder = count, self.target
    self:Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
end

-- Sets the "mouseover" unit (nil clears it). A unit fires UPDATE_MOUSEOVER_UNIT; clearing fires nothing, like the
-- client.
function Harness:SetMouseover(unit)
    self.units.mouseover = ((unit and Harness.FillUnit(unit)) or nil)

    if unit then
        self:Fire("UPDATE_MOUSEOVER_UNIT")
    end
end

-- The player takes a flight path: PLAYER_CONTROL_LOST, then UnitOnTaxi("player") is true.
function Harness:TakeFlight()
    assert(not self.player.onTaxi, "TakeFlight: already flying")
    self:Fire("PLAYER_CONTROL_LOST")
    self.player.onTaxi = true
end

-- The unit fakes, merged into the env (env.lua) before it wraps them.
function Harness:UnitFakes()
    local h = self

    local function Unit(token) return h:Unit(token) end

    local function Hostile(a, b, field)
        if (a == b) or not Unit(a) or not Unit(b) then return false end

        local other = (((a == "player") and Unit(b)) or ((b == "player") and Unit(a)) or nil)

        if not other then return false end

        if (field == "isEnemy") and (other.isEnemy ~= nil) then return other.isEnemy end

        return (other.canAttack == true)
    end

    return {
        C_NamePlate = {
            GetNamePlateForUnit = function(token)
                local plate = PlateTokenFor(h, Unit(token))

                return ((plate and h:NamePlateFrame(plate)) or nil)
            end,
        },
        C_UnitAuras = {
            AddAuraSound = function(trigger, sound) return AddAuraSound(h, trigger, sound) end,
            RemoveAuraSound = function(auraSoundID) h.auraSounds[auraSoundID] = nil end,
        },
        GetGuildInfo = function(u)
            local unit = Unit(u)

            if not unit or (unit.guild == nil) then return end

            local realm = (unit.guildRealm or "")

            if Harness.NormalizeRealm(realm) == Harness.NormalizeRealm(h.player.realm) then
                realm = ""
            end

            return unit.guild, (unit.guildRank or "Member"), (unit.guildRankIndex or 1), realm
        end,
        GetNormalizedRealmName = function() return Harness.NormalizeRealm(h.player.realm) end,
        GetRealmName = function() return h.player.realm end,
        IsInGuild = function() return (h.player.guild ~= nil) end,
        -- Forbidden to addons (tools/api/forbidden.json), so it never runs.
        SetRaidTarget = function() end,
        UnitAffectingCombat = function(u)
            local unit = Unit(u)

            -- The dead aren't affecting combat (see Death in the header).
            if unit == h.player then return (h.inCombat and not h.player.dead) end

            return ((unit ~= nil) and (unit.inCombat == true))
        end,
        -- Hostility is modeled against the player: the other unit's canAttack (isEnemy).
        UnitCanAttack = function(a, b) return Hostile(a, b, "canAttack") end,
        UnitFactionGroup = function(u)
            local unit = Unit(u)

            if not unit or (unit.faction == nil) then return end

            assert(Factions[unit.faction], "UnitFactionGroup: unknown faction " .. tostring(unit.faction))

            return unit.faction, Factions[unit.faction]
        end,
        UnitGUID = function(u)
            local unit = Unit(u)

            return ((unit and h:GUID(unit)) or nil)
        end,
        UnitIsDead = function(u)
            local unit = Unit(u)

            return ((unit ~= nil) and (unit.dead == true))
        end,
        UnitIsDeadOrGhost = function(u)
            local unit = Unit(u)

            return ((unit ~= nil) and ((unit.dead == true) or (unit.ghost == true)))
        end,
        UnitIsEnemy = function(a, b) return Hostile(a, b, "isEnemy") end,
        UnitOnTaxi = function(u)
            local unit = Unit(u)

            return ((unit == h.player) and (h.player.onTaxi == true))
        end,
        UnitPlayerControlled = function(u)
            local unit = Unit(u)

            return ((unit ~= nil) and (unit.playerControlled == true))
        end,
    }
end

-- The first token naming the unit with this GUID, or nil.
function Harness:UnitTokenForGUID(guid)
    guid = Reveal(guid)

    for _, token in ipairs(Tokens()) do
        local unit = self:Unit(token)

        if unit and (self:GUID(unit) == guid) then
            return token
        end
    end
end
