local addonName, ns = ...

-- WarbandDeaths: who killed you, for the Krew's grudges. ByteTerrace_Core's death fact reads your killer from
-- Blizzard's death recap (death.killer and the rows beside it). This file turns it into a rivalry record and a card.
--
--   A player        their kill of you counts in their rivalry record (and their guild's war tally),
--                   and a card names them and the killing blow: "Slain by Bob. Ambush for 700."
--   A creature      nothing: there's no one to hold a grudge against. Nor for your own blow.
--   Unknown or pet  a card asks about the prime suspect (Warband.TakeFoe): "Slain by Bob?"
-- On either card, a left-click holds a grudge with the Krew and a right-click lets it go. The cards need
-- Warband.askWhoKilledMe, but the record counts regardless.

local SOUNDKIT = SOUNDKIT

local Addon = ns.Addon
local ShowCard = ns.Cards.Show
local Warband = ns.Warband
local KeyOf = Warband.KeyOf

-- The prime suspect taken at PLAYER_DEAD, or nil for none.
local Suspect
-- Whether the prime suspect was taken at PLAYER_DEAD, for a killer not known yet.
local Taken = false

local function Ask(info, title, body, counted)
    ShowCard({
        body = (body .. "Click to hold a grudge; the Krew will remember. Right-click to let it go."),
        icon = "Interface\\Icons\\Ability_Warrior_Rampage",
        onClick = Warband.Module:Callback(Warband.HoldGrudge, info, true, counted), sound = SOUNDKIT.RAID_WARNING,
        title = title,
    })
end

-- "Ambush for 700. " or "A melee hit for 700. ", or "" when the blow is unknown.
local function Blow(state)
    local spell = state:Get("death.killerSpell")
    local damage = state:Get("death.killerDamage")

    if damage <= 0 then
        return ""
    end

    if spell ~= "" then
        return ("%s for %d. "):format(spell, damage)
    end

    return ("A melee hit for %d. "):format(damage)
end

-- The player the recap names, with what the suspect adds when it's the same person.
local function KillerInfo(state, suspect)
    local key = KeyOf(state:Get("death.killer"))

    local info = { class = state:Get("death.killerClass"), faction = state:Get("death.killerFaction"), guild = "",
        key = key, level = 0 }

    if suspect and (suspect.key == key) then
        info.level, info.guild = suspect.level, suspect.guild
        info.class = (((info.class ~= "") and info.class) or suspect.class)
        info.faction = (((info.faction ~= "") and info.faction) or suspect.faction)
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
    local kind = state:Get("death.killerKind")
    local prompt = state:Get("Warband.askWhoKilledMe")

    if kind == "player" then
        local info = KillerInfo(state, suspect)

        Warband.Remember(info.key, info)
        Warband.CountDeath(info.key)

        if prompt then
            Ask(info, "Slain by " .. info.key, Blow(state) .. Warband.Score(info.key) .. ". ", true)
        end
    elseif (kind ~= "npc") and (kind ~= "self") and suspect and prompt then
        local history = ((Warband.People:Has(suspect.key) and (Warband.Score(suspect.key) .. ". ")) or "")

        Ask(suspect, "Slain by " .. suspect.key .. "?", history, false)
    end
end

Addon:Module("Slain", {
    active = { reads = { "Warband.enabled" }, when = function(state) return state:Get("Warband.enabled") end },
    OnDisable = function()
        Taken, Suspect = false, nil
    end,
    OnEnable = function(module)
        -- The death fact's PLAYER_DEAD handler runs first (a module's dependencies start before it). When it already
        -- named the killer, OnKiller took the suspect then. Otherwise, the handler takes it now, before you target
        -- someone else.
        module:On("PLAYER_DEAD", function()
            if module:Get("death.attributed") < module:Get("death.count") then
                Taken, Suspect = true, Warband.TakeFoe()
            end
        end)

        module:OnIncrease("death.attributed", OnKiller)
    end,
    toggle = false,
    uses = { "death" },
})
