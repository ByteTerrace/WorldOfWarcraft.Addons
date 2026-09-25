local addonName, ns = ...

-- WarbandDeaths: who killed you, for the Krew's grudges. Honor.lua reads your killer from
-- Blizzard's death recap (Honor.killer and the rows beside it); this turns it into a rivalry
-- record and a card.
--
--   A player        their kill of you counts in their rivalry record (and their guild's war tally),
--                   and a card names them and the killing blow: "Slain by Bob. Ambush for 700."
--   A creature      nothing: there's no one to hold a grudge against. Nor for your own blow.
--   Unknown or pet  a card asks about the prime suspect (Warband.TakeFoe): "Slain by Bob?"
-- On either card, a left-click holds a grudge with the Krew and a right-click lets it go. The
-- cards need Warband.deathPrompt; the record counts regardless.

local SOUNDKIT = SOUNDKIT

local Addon = ns.Addon
local Warband = ns.Warband
local ShowCard = ns.Cards.Show
local KeyOf, Short = Warband.KeyOf, Warband.Short

local Taken = false -- the prime suspect was taken at PLAYER_DEAD, for a killer not known yet
local Suspect       -- that suspect, or nil for none

-- "Ambush for 700. " or "A melee hit for 700. ", or "" when the blow is unknown.
local function Blow(state)
    local spell, damage = state:Get("Honor.killerSpell"), state:Get("Honor.killerDamage")
    if damage <= 0 then
        return ""
    end
    if spell ~= "" then
        return ("%s for %d. "):format(spell, damage)
    end
    return ("A melee hit for %d. "):format(damage)
end

local function Ask(info, title, body, counted)
    ShowCard({
        icon = "Interface\\Icons\\Ability_Warrior_Rampage", sound = SOUNDKIT.RAID_WARNING, title = title,
        body = body .. "Click to hold a grudge; the Krew will remember. Right-click to let it go.",
        onClick = function()
            Warband.HoldGrudge(info, true, counted)
        end,
    })
end

-- The player the recap names, with what the suspect adds when it's the same person.
local function KillerInfo(state, suspect)
    local key = KeyOf(state:Get("Honor.killer"))
    local info = { key = key, class = state:Get("Honor.killerClass"), level = 0,
        faction = state:Get("Honor.killerFaction"), guild = "" }
    if suspect and suspect.key == key then
        info.level, info.guild = suspect.level, suspect.guild
        info.class = info.class ~= "" and info.class or suspect.class
        info.faction = info.faction ~= "" and info.faction or suspect.faction
    end
    return info
end

-- Your killer is known, or the recap never came.
local function OnKiller(state)
    local suspect = Suspect
    if not Taken then
        suspect = Warband.TakeFoe()
    end
    Taken, Suspect = false, nil
    local kind, prompt = state:Get("Honor.killerKind"), state:Get("Warband.deathPrompt")
    if kind == "player" then
        local info = KillerInfo(state, suspect)
        Warband.Remember(info.key, info)
        Warband.CountDeath(info.key)
        if prompt then
            Ask(info, "Slain by " .. Short(info.key), Blow(state) .. Warband.Score(info.key) .. ". ", true)
        end
    elseif kind ~= "npc" and kind ~= "self" and suspect and prompt then
        local history = Warband.People:Has(suspect.key) and (Warband.Score(suspect.key) .. ". ") or ""
        Ask(suspect, "Slain by " .. Short(suspect.key) .. "?", history, false)
    end
end

Addon:Module("Slain", {
    toggle = false,
    active = { reads = { "Warband.enabled" }, when = function(state) return state:Get("Warband.enabled") end },
    OnEnable = function(module)
        -- Honor's PLAYER_DEAD handler runs first. When it already named the killer, OnKiller took
        -- the suspect then; otherwise take it now, before you target someone else.
        module:On("PLAYER_DEAD", function()
            if module:Get("Honor.killedBy") < module:Get("Honor.deaths") then
                Taken, Suspect = true, Warband.TakeFoe()
            end
        end)
        local killedBy = module:Get("Honor.killedBy")
        module:Watch({ "Honor.killedBy" }, function(state)
            local now = state:Get("Honor.killedBy")
            if now > killedBy then
                OnKiller(state)
            end
            killedBy = now
        end, true)
    end,
    OnDisable = function()
        Taken, Suspect = false, nil
    end,
})
