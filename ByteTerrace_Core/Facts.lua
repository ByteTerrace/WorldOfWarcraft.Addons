-- Facts: game state that several modules rule over, published as runtime (unpersisted) rows.
-- Each fact is a module whose event adapter is the only code that reads the WoW API; every
-- reader works from the row. A fact never holds a secret: an adapter whose API can return one
-- checks issecretvalue and keeps the last known value.
--
--   combat.active  true while the player is in combat. Set on PLAYER_REGEN_DISABLED, before
--                  InCombatLockdown() turns true.
--   afk.active     true while the player is flagged AFK.

local ByteTerrace = ByteTerrace
local issecretvalue, UnitAffectingCombat, UnitIsAFK = issecretvalue, UnitAffectingCombat, UnitIsAFK

ByteTerrace.Facts = {
    combat = {
        toggle = false,
        state = { { name = "active", kind = "boolean", default = false, persist = false } },
        OnEnable = function(module)
            local active = module:Id("active")
            local state = module.addon.state
            module:On("PLAYER_ENTERING_WORLD", function()
                state:Set(active, UnitAffectingCombat("player") and true or false)
            end)
            module:On("PLAYER_REGEN_DISABLED", function()
                state:Set(active, true)
            end)
            module:On("PLAYER_REGEN_ENABLED", function()
                state:Set(active, false)
            end)
        end,
    },
    afk = {
        toggle = false,
        state = { { name = "active", kind = "boolean", default = false, persist = false } },
        OnEnable = function(module)
            local active = module:Id("active")
            local state = module.addon.state
            local function Update()
                -- UnitIsAFK is secret during chat messaging lockdown; keep the last known value then.
                local afk = UnitIsAFK("player")
                if not issecretvalue(afk) then
                    state:Set(active, afk and true or false)
                end
            end
            module:On("PLAYER_ENTERING_WORLD", Update)
            module:On("PLAYER_FLAGS_CHANGED", Update, "player")
        end,
    },
}
