-- The kills fact (Facts.lua): your kills of players, for features that react to them. A demand
-- fact: it runs only while a module that uses it runs (uses = { "kills" }). React to a kill with
-- module:OnIncrease on a count.
--
--   kills.honorable  honorable kills this session, one per kill message. The client gives addons no
--                    combat log; CHAT_MSG_COMBAT_HONOR_GAIN is how it says you got credit for a
--                    kill, and everyone in your group nearby gets the same credit, whoever landed it.
--   kills.victim     the last honorable kill's victim as the message printed it (a player's
--                    "First Last", Names.lua). It's set in the same publish that bumps
--                    kills.honorable.
--   kills.blows      your killing blows on players this session (yours or your pet's), from
--                    PARTY_KILL, the event killing-blow addons read since the combat log closed. Its
--                    GUIDs are secret while unit identity is restricted (in instances); those don't
--                    count.
--   kills.streak     killing blows since you last died (or since the fact started).

local ByteTerrace = ByteTerrace
local issecretvalue, type, UnitGUID = issecretvalue, type, UnitGUID
local ipairs = ipairs

-- A Lua pattern from a client format string ("%s dies (Honorable Kill: %s). ..."): each %s is a
-- capture, so the first capture is the victim's name.
local function Pattern(formatString)
    if type(formatString) ~= "string" then
        return nil
    end
    local pattern = formatString:gsub("%%%d+%$([sd])", "%%%1") -- "%1$s" (another locale's order) is "%s"
    pattern = pattern:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    pattern = pattern:gsub("%%s", "(.-)"):gsub("%%d", "%%d+")
    return "^" .. pattern .. "$"
end

local HonorPatterns = { Pattern(COMBATLOG_HONORGAIN), Pattern(COMBATLOG_HONORGAIN_NO_RANK) }

-- The victim's name in an honorable kill message, or nil (bonus honor names no one).
local function Victim(text)
    for _, pattern in ipairs(HonorPatterns) do
        local victim = text:match(pattern)
        if victim and victim ~= "" then
            return victim
        end
    end
    return nil
end

ByteTerrace.Facts.kills = {
    toggle = false,
    demand = true,
    state = {
        { name = "honorable", kind = "number", default = 0, persist = false },
        { name = "victim", kind = "string", default = "", persist = false },
        { name = "blows", kind = "number", default = 0, persist = false },
        { name = "streak", kind = "number", default = 0, persist = false },
    },
    OnEnable = function(module)
        local state = module.Addon.State
        local honorable, victim = module:Id("honorable"), module:Id("victim")
        local blows, streak = module:Id("blows"), module:Id("streak")

        module:On("CHAT_MSG_COMBAT_HONOR_GAIN", function(text)
            local name = not issecretvalue(text) and type(text) == "string" and Victim(text)
            if name then
                state:Set(victim, name)
                state:Set(honorable, state.Values[honorable] + 1)
            end
        end)
        module:On("PARTY_KILL", function(attackerGUID, targetGUID)
            if issecretvalue(attackerGUID) or issecretvalue(targetGUID) or type(targetGUID) ~= "string"
                or not targetGUID:find("^Player%-") then
                return
            end
            local me, pet = UnitGUID("player"), UnitGUID("pet")
            if issecretvalue(me) or issecretvalue(pet) then
                return
            end
            if attackerGUID ~= me and (pet == nil or attackerGUID ~= pet) then
                return -- a groupmate's blow
            end
            state:Set(streak, state.Values[streak] + 1)
            state:Set(blows, state.Values[blows] + 1)
        end)
        module:On("PLAYER_DEAD", function()
            state:Set(streak, 0)
        end)
    end,
}
