-- The restriction fact (Facts.lua): which of the client's addon restrictions are in force, one boolean row per
-- Enum.AddOnRestrictionType. A demand fact: it runs only while a module that uses it runs (uses = { "restriction" }).
--
--   restriction.combat         Combat
--   restriction.encounter      Encounter
--   restriction.challengeMode  ChallengeMode (Mythic+)
--   restriction.pvpMatch       PvPMatch
--   restriction.map            Map
--   restriction.chat           Chat
--
-- A row turns true on ADDON_RESTRICTION_STATE_CHANGED's Activating or Active and false on its Inactive. Activating
-- counts as in force: the probes saw Forever send Combat Activating and no Active until Inactive (probes.json,
-- combat.edges), and readers act on a restriction as it begins. Starting reads each restriction from
-- C_RestrictedActions.IsAddOnRestrictionActive, so a /reload inside one doesn't read as its start.

-- Each Enum.AddOnRestrictionType name and its row.
local Restrictions = {
    { "Combat", "combat" }, { "Encounter", "encounter" }, { "ChallengeMode", "challengeMode" },
    { "PvPMatch", "pvpMatch" }, { "Map", "map" }, { "Chat", "chat" },
}

local ByteTerrace = ByteTerrace
local C_RestrictedActions, Enum = C_RestrictedActions, Enum
local ipairs = ipairs

local Rows = {}

for i, restriction in ipairs(Restrictions) do
    Rows[i] = { default = false, kind = "boolean", name = restriction[2], persist = false }
end

ByteTerrace.Facts.restriction = {
    demand = true,
    OnEnable = function(module)
        local state, inactive = module.Addon.State, Enum.AddOnRestrictionState.Inactive
        -- [Enum.AddOnRestrictionType value] = row id
        local ids = {}

        for _, restriction in ipairs(Restrictions) do
            local kind = Enum.AddOnRestrictionType[restriction[1]]

            ids[kind] = module:Id(restriction[2])
            state:Set(ids[kind], C_RestrictedActions.IsAddOnRestrictionActive(kind) == true)
        end

        module:On("ADDON_RESTRICTION_STATE_CHANGED", function(restriction, restrictionState)
            local id = ids[restriction]

            if id then
                state:Set(id, restrictionState ~= inactive)
            end
        end)
    end,
    state = Rows,
    toggle = false,
}
