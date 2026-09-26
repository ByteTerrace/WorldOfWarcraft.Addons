-- ByteTerrace facts: the demand facts (target, kills, death) run only while used, and cost as
-- little as their events allow.

-- A harness with the framework and an addon declaring every fact, with one module (User) that
-- uses the demand facts while its switch is on. Not yet started.
local function NewAddOn()
    local h = Harness.New()
    h:LoadFiles("ByteTerrace_Core")
    h.declared.TestDB = true
    rawset(h.env, "TestDB", h.saved.TestDB)
    local addon = h.env.ByteTerrace.NewAddOn({ name = "TestApp", savedVariable = "TestDB", slash = { "/test" },
        facts = { "combat", "afk", "target", "kills", "death" } })
    addon:Module("User", { label = "User", uses = { "target", "kills", "death" } })
    return h, addon
end

local function Start(h)
    h:Fire("ADDON_LOADED", "TestApp")
end

local function EnemyPlayer()
    return { name = "Bob", isPlayer = true, canAttack = true, playerControlled = true }
end

test("demand facts register nothing while no module uses them", function()
    local h, addon = NewAddOn()
    Start(h)
    local frame = addon.Events.Frame
    truthy(frame:IsEventRegistered("PARTY_KILL"))
    truthy(frame:IsEventRegistered("UNIT_HEALTH"))
    addon.State:Set("User.enabled", false)
    for _, event in ipairs({ "UNIT_HEALTH", "PLAYER_TARGET_CHANGED", "PARTY_KILL", "PLAYER_DEAD",
        "CHAT_MSG_COMBAT_HONOR_GAIN", "DUEL_FINISHED" }) do
        falsy(frame:IsEventRegistered(event), event)
    end
    truthy(frame:IsEventRegistered("PLAYER_REGEN_DISABLED"), "the combat fact always runs")
end)

test("the target's health events cost one API call each", function()
    local h, addon = NewAddOn()
    Start(h)
    local enemy = EnemyPlayer()
    h:SetTarget(enemy)
    truthy(addon.State:Get("target.enemyPlayer"))
    h.apiCalls = {}
    for _ = 1, 5 do
        h:Fire("UNIT_HEALTH", "target")
    end
    local reads = {}
    for name, count in pairs(h.apiCalls) do
        if name ~= "issecretvalue" then
            reads[#reads + 1] = name .. "=" .. count
        end
    end
    eq(table.concat(reads, " "), "UnitIsDeadOrGhost=5", "nothing else is read while the target lives")
    enemy.dead = true
    h:Fire("UNIT_HEALTH", "target")
    truthy(addon.State:Get("target.died"), "an enemy player dying while targeted")
    falsy(addon.State:Get("target.alive"))
end)

test("a player who becomes attackable is an enemy by their next health change", function()
    local h, addon = NewAddOn()
    Start(h)
    local duelist = EnemyPlayer()
    duelist.canAttack = false
    h:SetTarget(duelist)
    falsy(addon.State:Get("target.enemyPlayer"))
    duelist.canAttack = true -- a duel starts; say the client fires nothing else
    h:Fire("UNIT_HEALTH", "target")
    truthy(addon.State:Get("target.enemyPlayer"))
end)

test("an enemy that stops being attackable as it dies still died while targeted", function()
    local h, addon = NewAddOn()
    Start(h)
    local enemy = EnemyPlayer()
    h:SetTarget(enemy)
    enemy.dead, enemy.canAttack = true, false
    h:Fire("UNIT_FLAGS", "target")
    truthy(addon.State:Get("target.died"))
    falsy(addon.State:Get("target.enemyPlayer"))
end)

test("a corpse you select never died while targeted; a resurrection clears a death", function()
    local h, addon = NewAddOn()
    Start(h)
    local enemy = EnemyPlayer()
    enemy.dead = true
    h:SetTarget(enemy)
    falsy(addon.State:Get("target.died"))
    enemy.dead = false
    h:Fire("UNIT_HEALTH", "target")
    truthy(addon.State:Get("target.alive"))
    enemy.dead = true
    h:Fire("UNIT_HEALTH", "target")
    truthy(addon.State:Get("target.died"))
    enemy.dead = false
    h:Fire("UNIT_HEALTH", "target")
    falsy(addon.State:Get("target.died"))
end)

test("killing blows count yours and your pet's on players; a death resets the streak", function()
    local h, addon = NewAddOn()
    Start(h)
    local me = h.env.UnitGUID("player")
    local victim = h:GUID({ name = "Bob", isPlayer = true })
    h:Fire("PARTY_KILL", me, victim)
    h:Fire("PARTY_KILL", h:GUID({ name = "Ann", isPlayer = true }), victim) -- a groupmate's blow
    h:Fire("PARTY_KILL", me, h:GUID({ name = "Wolf" })) -- a creature
    eq(addon.State:Get("kills.blows"), 1)
    eq(addon.State:Get("kills.streak"), 1)
    h:Die()
    eq(addon.State:Get("kills.streak"), 0)
    eq(addon.State:Get("kills.blows"), 1)
    eq(addon.State:Get("death.count"), 1)
end)

test("a killing blow whose GUIDs are secret (a PvP match hides identities) isn't counted", function()
    local h, addon = NewAddOn()
    Start(h)
    local me = h.env.UnitGUID("player")
    h:SetRestriction("PvPMatch", true)
    h:Fire("PARTY_KILL", me, h:GUID({ name = "Bob", isPlayer = true }))
    eq(addon.State:Get("kills.blows"), 0)
    h:SetRestriction("PvPMatch", false)
    h:Fire("PARTY_KILL", me, h:GUID({ name = "Bob", isPlayer = true }))
    eq(addon.State:Get("kills.blows"), 1, "counted again outside the match")
end)

test("the death fact's recap retries stop when no module uses it any more", function()
    local h, addon = NewAddOn()
    Start(h)
    h:Die()
    eq(addon.State:Get("death.count"), 1)
    addon.State:Set("User.enabled", false)
    eq(addon.State:Get("death.count"), 0, "its rows reset")
    h:Advance(60)
    eq(addon.State:Get("death.attributed"), 0, "no retry fired after it stopped")
end)
