-- Facts: game state that several modules rule over, published as runtime (unpersisted) rows. Each fact is a module
-- whose event adapter is the only code that reads the WoW API. Every reader works from the row. No fact holds a secret:
-- an adapter whose API can return one checks issecretvalue and keeps the last known value.
--
-- An addon opts in with NewAddOn's facts = { ... }. Facts are declared before its own modules, so they're enabled first
-- and hold their real value before any other module's rules take their first reading. A /reload in combat must not look
-- like combat starting.
--
--   combat.active  true while the player is in combat. Set on PLAYER_REGEN_DISABLED, before
--                  InCombatLockdown() turns true.
--   afk.active     true while the player is flagged AFK.
--
-- Demand facts run only while a module that uses them runs (uses = { "target" }), so a fact no running feature reads
-- registers nothing:
--   target  what your target is (FactsTarget.lua).
--   kills   your honorable kills and killing blows (FactsKills.lua).
--   death   your deaths and who dealt them (FactsDeath.lua).
--   restriction  which addon restrictions are in force (FactsRestriction.lua).

local ByteTerrace = ByteTerrace
local InCombatLockdown = InCombatLockdown
local issecretvalue = issecretvalue
local UnitAffectingCombat = UnitAffectingCombat
local UnitIsAFK = UnitIsAFK

ByteTerrace.Facts = {
    afk = {
        OnEnable = function(module)
            local active = module:Id("active")
            local state = module.Addon.State

            local function Update()
                -- UnitIsAFK is secret during chat messaging lockdown, so the adapter keeps the last known value then.
                local afk = UnitIsAFK("player")

                if not issecretvalue(afk) then
                    state:Set(active, (afk and true) or false)
                end
            end

            module:On("PLAYER_ENTERING_WORLD", Update)
            module:On("PLAYER_FLAGS_CHANGED", Update, "player")
            Update()
        end,
        state = { { default = false, kind = "boolean", name = "active", persist = false } },
        toggle = false,
    },
    combat = {
        OnEnable = function(module)
            local active = module:Id("active")
            local state = module.Addon.State

            local function Update()
                state:Set(active, ((InCombatLockdown() or UnitAffectingCombat("player")) and true) or false)
            end

            module:On("PLAYER_ENTERING_WORLD", Update)

            module:On("PLAYER_REGEN_DISABLED", function()
                state:Set(active, true)
            end)

            module:On("PLAYER_REGEN_ENABLED", function()
                state:Set(active, false)
            end)

            Update()
        end,
        state = { { default = false, kind = "boolean", name = "active", persist = false } },
        toggle = false,
    },
}
