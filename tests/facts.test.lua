-- ByteTerrace facts: the demand facts (target, kills, death) run only while used, and cost as little as their events
-- allow.

local Kit = use("framework")

local Start = Kit.Start

local function EnemyPlayer()
    return { canAttack = true, isPlayer = true, name = "Bob", playerControlled = true }
end

-- A harness with the framework and an addon declaring every fact, with one module (User) that uses the demand facts
-- while its switch is on. Not yet started.
local function NewAddOn()
    local h = Harness.New()

    h:LoadFiles("ByteTerrace_Core")
    h.declared.TestDB = true
    rawset(h.env, "TestDB", h.saved.TestDB)

    local addon = h.env.ByteTerrace.NewAddOn({ facts = { "combat", "afk", "target", "kills", "death" },
        name = "TestApp", savedVariable = "TestDB", slash = { "/test" } })

    addon:Module("User", { label = "User", uses = { "target", "kills", "death" } })

    return h, addon
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
            reads[#reads + 1] = (name .. "=" .. count)
        end
    end

    eq(table.concat(reads, " "), "UnitIsDeadOrGhost=5", "nothing else is read while the target lives")
    enemy.dead = true
    h:Fire("UNIT_HEALTH", "target")
    truthy(addon.State:Get("target.died"), "an enemy player dying while targeted")
    falsy(addon.State:Get("target.alive"))
end)

-- What one step read, as "Api=count ..." in name order (issecretvalue left out).
local function Reads(h, step)
    h.apiCalls = {}
    step()
    local reads = {}

    for name, count in pairs(h.apiCalls) do
        if name ~= "issecretvalue" then
            reads[#reads + 1] = (name .. "=" .. count)
        end
    end

    table.sort(reads)

    return table.concat(reads, " ")
end

test("a target is read once when chosen; a flag change re-reads attackability, not rank", function()
    local h, addon = NewAddOn()

    Start(h)
    local elite = { canAttack = true, classification = "elite", name = "Ogre" }

    eq(Reads(h, function() h:SetTarget(elite) end),
        "UnitCanAttack=1 UnitClassification=1 UnitExists=1 UnitIsDeadOrGhost=1 UnitIsPlayer=1")

    truthy(addon.State:Get("target.formidable"))
    elite.canAttack = false
    eq(Reads(h, function() h:Fire("UNIT_FLAGS", "target") end), "UnitCanAttack=1 UnitExists=1 UnitIsDeadOrGhost=1")
    falsy(addon.State:Get("target.formidable"), "no longer attackable")
    elite.canAttack = true
    eq(Reads(h, function() h:Fire("UNIT_FACTION", "target") end), "UnitCanAttack=1 UnitExists=1 UnitIsDeadOrGhost=1")
    truthy(addon.State:Get("target.formidable"), "attackable again, and still elite")
    elite.classification = "normal"
    h:Fire("UNIT_CLASSIFICATION_CHANGED", "target")
    falsy(addon.State:Get("target.formidable"), "a rank change re-reads the rank")
    h:SetTarget({ boss = true, canAttack = true, name = "Overlord" })
    truthy(addon.State:Get("target.formidable"), "a boss mob is formidable whatever its classification")
end)

test("a player who becomes attackable is an enemy by their next health change", function()
    local h, addon = NewAddOn()

    Start(h)
    local duelist = EnemyPlayer()

    duelist.canAttack = false
    h:SetTarget(duelist)
    falsy(addon.State:Get("target.enemyPlayer"))
    -- a duel starts; say the client fires nothing else
    duelist.canAttack = true
    h:Fire("UNIT_HEALTH", "target")
    truthy(addon.State:Get("target.enemyPlayer"))
end)

test("a duel ends only for the target that became attackable while you targeted it", function()
    local h, addon = NewAddOn()

    Start(h)
    -- a bystander of the other faction, attackable from the start
    h:SetTarget(EnemyPlayer())
    -- someone else's duel, or a declined request
    h:Fire("DUEL_FINISHED")
    falsy(addon.State:Get("target.duelEnded"), "not your duel")
    local duelist = EnemyPlayer()

    duelist.canAttack = false
    h:SetTarget(duelist)
    -- the duel starts
    duelist.canAttack = true
    h:Fire("UNIT_FLAGS", "target")
    h:Fire("DUEL_OUTOFBOUNDS")
    -- back before the countdown ran out: no forfeit
    h:Fire("DUEL_INBOUNDS")
    h:Fire("DUEL_FINISHED")
    truthy(addon.State:Get("target.duelEnded"), "your duel")
end)

test("a duel you flee out of bounds doesn't end as a fought duel", function()
    local h, addon = NewAddOn()

    Start(h)
    local duelist = EnemyPlayer()

    duelist.canAttack = false
    h:SetTarget(duelist)
    duelist.canAttack = true
    h:Fire("UNIT_FLAGS", "target")
    h:Fire("DUEL_OUTOFBOUNDS")
    h:Fire("DUEL_FINISHED")
    falsy(addon.State:Get("target.duelEnded"))
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

test("killing blows count yours on players, not a groupmate's or a creature's, and survive a death", function()
    local h, addon = NewAddOn()

    Start(h)
    local me = h.env.UnitGUID("player")
    local victim = h:GUID({ isPlayer = true, name = "Bob" })

    h:Fire("PARTY_KILL", me, victim)
    -- a groupmate's blow
    h:Fire("PARTY_KILL", h:GUID({ isPlayer = true, name = "Ann" }), victim)
    -- a creature
    h:Fire("PARTY_KILL", me, h:GUID({ name = "Wolf" }))
    eq(addon.State:Get("kills.blows"), 1)
    h:Die()
    eq(addon.State:Get("kills.blows"), 1)
    eq(addon.State:Get("death.count"), 1)
end)

test("a killing blow whose GUIDs are secret (a PvP match hides identities) isn't counted", function()
    local h, addon = NewAddOn()

    Start(h)
    local me = h.env.UnitGUID("player")

    h:SetRestriction("PvPMatch", true)
    h:Fire("PARTY_KILL", me, h:GUID({ isPlayer = true, name = "Bob" }))
    eq(addon.State:Get("kills.blows"), 0)
    h:SetRestriction("PvPMatch", false)
    h:Fire("PARTY_KILL", me, h:GUID({ isPlayer = true, name = "Bob" }))
    eq(addon.State:Get("kills.blows"), 1, "counted again outside the match")
end)

test("a death whose recap holds no events is attributed to no one, at once", function()
    local h, addon = NewAddOn()

    Start(h)
    h:MeterFight({ duration = 5, sources = { { death = {}, unit = "player" } } })
    eq(addon.State:Get("death.count"), 1)
    eq(addon.State:Get("death.attributed"), 1, "the recap was there, so there's nothing to wait for")
    eq(addon.State:Get("death.killer"), "")
    eq(addon.State:Get("death.killerKind"), "")
    eq(addon.State:Get("death.killerDamage"), 0)
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

-- An addon whose one module (User) uses the restriction fact while its switch is on. Not yet started.
local function RestrictionAddOn()
    local h = Harness.New()

    h:LoadFiles("ByteTerrace_Core")
    h.declared.TestDB = true
    rawset(h.env, "TestDB", h.saved.TestDB)

    local addon = h.env.ByteTerrace.NewAddOn({ facts = { "restriction" }, name = "TestApp", savedVariable = "TestDB",
        slash = { "/test" } })

    addon:Module("User", { label = "User", uses = { "restriction" } })

    return h, addon
end

local RestrictionRows = { ChallengeMode = "challengeMode", Chat = "chat", Combat = "combat", Encounter = "encounter",
    Map = "map", PvPMatch = "pvpMatch" }

local function Restricted(addon)
    local active = {}

    for _, row in ipairs({ "challengeMode", "chat", "combat", "encounter", "map", "pvpMatch" }) do
        if addon.State:Get("restriction." .. row) then
            active[#active + 1] = row
        end
    end

    return table.concat(active, " ")
end

test("each restriction's row turns true as it activates and false when it's lifted, reading no API", function()
    local h, addon = RestrictionAddOn()

    Start(h)
    local frame = addon.Events.Frame

    truthy(frame:IsEventRegistered("ADDON_RESTRICTION_STATE_CHANGED"))
    h.apiCalls = {}

    for restriction, row in pairs(RestrictionRows) do
        local seen

        local watcher = addon.State:Watch({ addon.State:Id("restriction." .. row) }, function(state)
            seen = state:Get("restriction." .. row)
        end, true)

        h:SetRestriction(restriction, true)
        eq(Restricted(addon), row, restriction .. " is in force")
        truthy(seen, restriction .. " published")
        h:SetRestriction(restriction, false)
        eq(Restricted(addon), "", restriction .. " lifted")
        addon.State:Unwatch(watcher)
    end

    h:EnterCombat()
    eq(Restricted(addon), "combat", "Forever sends Combat Activating and no Active: Activating counts")
    h:LeaveCombat()
    eq(Restricted(addon), "")

    for name in pairs(h.apiCalls) do
        eq(name, "issecretvalue", "events read no API but State's secret check")
    end

    addon.State:Set("User.enabled", false)
    falsy(frame:IsEventRegistered("ADDON_RESTRICTION_STATE_CHANGED"), "nothing registered while unused")
end)

test("the restriction rows start from the client's state: a /reload in an encounter is no encounter starting", function()
    local h, addon = RestrictionAddOn()

    h:SetRestriction("Encounter", true)
    h:EnterCombat()
    Start(h)
    eq(Restricted(addon), "combat encounter")
    eq(h.apiCalls["C_RestrictedActions.IsAddOnRestrictionActive"], 6, "one read per restriction")
    addon.State:Set("User.enabled", false)
    eq(Restricted(addon), "", "rows reset while unused")
    h:SetRestriction("Encounter", false)
    addon.State:Set("User.enabled", true)
    eq(Restricted(addon), "combat", "a restart reads them again")
end)
