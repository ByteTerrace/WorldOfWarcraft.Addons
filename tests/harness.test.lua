-- The harness's own fidelity rules. If these fail, every other test's evidence is suspect.

local function Enemy(fields)
    local unit = { isPlayer = true, canAttack = true }
    for key, value in pairs(fields or {}) do unit[key] = value end
    return unit
end

test("secret values are opaque userdata that refuse every computation", function()
    local h = Harness.New()
    h:EnterCombat()
    local env = h.env
    local health = env.UnitHealth("player")
    truthy(env.issecretvalue(health), "UnitHealth is secret in combat")
    eq(env.type(health), "number", "type() reports the underlying type, like the client")
    throws(function() return health >= 1 end, "compare")
    throws(function() return health >= env.UnitHealth("player") end, "secret")
    throws(function() return health == env.UnitHealth("player") end, "secret")
    throws(function() return health + 1 end, "secret")
    throws(function() return -health end, "secret")
    throws(function() return #health end, "secret")
    throws(function() return health.x end, "secret")
    throws(function() health.x = 1 end, "secret")
    throws(function() return pairs(health) end)
    throws(function() return env.tonumber(health) end, "secret")
    throws(function() env.print("hp", health) end, "secret")
    eq(Reveal(health), 100)
end)

-- secrets.operations: the client lets addon code concatenate, tostring and format a secret, and
-- each result is a secret string.
test("concatenation, tostring and format turn a secret into a secret string", function()
    local h = Harness.New()
    local env = h.env
    local health = env.UnitHealth("player")
    local results = {
        concat = "hp: " .. health, concatRight = health .. " hp", tostring = env.tostring(health),
        format = env.string.format("%d", health), formatGlobal = env.format("%s", health),
        method = ("%d hp"):format(health),
    }
    for name, result in pairs(results) do
        truthy(env.issecretvalue(result), name .. " is secret")
        eq(env.type(result), "string", name .. " is a string")
    end
    eq(Reveal(results.concat), "hp: 100")
    eq(Reveal(results.method), "100 hp")
    eq(("%d"):format(7), "7", "plain formatting is untouched")
    throws(function() return health .. {} end, "concatenate")
    throws(function() return ("%.1s"):format(health) end, "precision")
end)

test("issecretvalue is exact: NaN and plain values aren't secret", function()
    local h = Harness.New()
    falsy(h.env.issecretvalue(0 / 0), "NaN")
    falsy(h.env.issecretvalue(nil))
    falsy(h.env.issecretvalue({}))
    truthy(h.env.issecretvalue(Secret(false)), "a secret false is still secret")
end)

test("wrapping keeps return arity: nil stays nil and trailing values survive", function()
    local h = Harness.New()
    h:EnterCombat()
    h:SetTarget(nil)
    eq(select("#", h.env.UnitClass("target")), 0, "no unit: nothing returned")
    local name, surname = h.env.UnitName("player")
    eq(Reveal(name), "Tester")
    eq(Reveal(surname), Harness.DEFAULT_SURNAME, "the trailing surname survives")
end)

-- GetRaidTargetIndex carries SecretReturns, which is secret always (probed: UnitHealth and
-- UnitHealthPercent, the flag's other users, came back secret with no restriction).
local function Marked(h)
    if h.player.raidTarget ~= 1 then
        h:MarkRaidTarget("player", 1) -- marking the same icon twice would clear it
    end
    return h.env.GetRaidTargetIndex("player")
end

-- UnitIsAFK is secret during chat messaging lockdown (encounter, challenge mode, PvP match,
-- restricted map, chat): the witness for a restriction being enforced.
local function Restricted(h)
    return h.env.issecretvalue(h.env.UnitIsAFK("player"))
end

test("UnitHealth is always secret, for every unit, even with no restriction (probed in game)", function()
    local h = Harness.New()
    truthy(h.env.issecretvalue(h.env.UnitHealth("player")), "your own health")
    h:SetTarget({ name = "Hogger" })
    truthy(h.env.issecretvalue(h.env.UnitHealth("target")), "an NPC's")
    falsy(h.env.issecretvalue(h.env.UnitHealthMax("player")), "your max health is readable")
end)

test("SecretReturns is secret always, even with no restriction (probed in game)", function()
    local h = Harness.New()
    truthy(h.env.issecretvalue(Marked(h)))
end)

test("restriction changes fire Activating, then Active once enforced, and Inactive after", function()
    local h = Harness.New()
    local env = h.env
    local seen = {}
    local frame = env.CreateFrame("Frame")
    frame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    frame:SetScript("OnEvent", function(_, _, kind, state)
        seen[#seen + 1] = ("%d:%d active=%s state=%d secret=%s"):format(kind, state,
            tostring(env.C_RestrictedActions.IsAddOnRestrictionActive(kind)),
            env.C_RestrictedActions.GetAddOnRestrictionState(kind), tostring(Restricted(h)))
    end)
    h:SetRestriction("Encounter", true)
    truthy(env.C_RestrictedActions.IsAddOnRestrictionActive(env.Enum.AddOnRestrictionType.Encounter))
    eq(env.C_RestrictedActions.GetAddOnRestrictionState(env.Enum.AddOnRestrictionType.Encounter), 2)
    h:SetRestriction("Encounter", false)
    eq(table.concat(seen, ","), "1:1 active=false state=1 secret=false,1:2 active=false state=2 secret=true,"
        .. "1:0 active=false state=0 secret=false")
end)

test("secrets held in a table argument count, and LuaValueVariant arguments are read", function()
    local h = Harness.New()
    throws(function() h.env.C_GamePad.SetLedColor(h.env.CreateColor(Secret(1), 0, 0)) end, "secret argument #1 refused")
    eq(h.led, nil)
    local serialize = h:WrapFunction("C_EncodingUtil.SerializeJSON", function() return "{}" end)
    throws(function() serialize(Secret(1)) end, "secret argument #1 refused")
    eq(serialize({ 1 }), "{}")
end)

test("undocumented fakes refuse secret arguments by default", function()
    local h = Harness.New()
    h:AddMedia("x.ogg")
    throws(function() h.env.PlaySoundFile("x.ogg", Secret("Master")) end, "undocumented")
    throws(function() h.env.StopSound(Secret(1)) end, "undocumented")
    throws(function() h.env.PlaySound(Secret(829)) end, "undocumented")
    eq(#h.sounds + #h.stopped + #h.soundKits, 0)
end)

test("RequiresFontStringTextAccess methods return nothing on a fontstring with secret text", function()
    local h = Harness.New()
    local fs = h.env.CreateFrame("Frame"):CreateFontString()
    fs:SetText(Secret("hidden"))
    eq(select("#", fs:FindCharacterIndexAtCoordinate(1, 1)), 0)
end)

test("addon code is tainted: a secret argument is refused unless the API allows it when tainted", function()
    local h = Harness.New()
    h:EnterCombat()
    local health = h.env.UnitHealth("player")
    throws(function() h.env.UnitClass(health) end, "SecretArguments AllowedWhenUntainted")
    throws(function() h.env.GetMoney(health) end, "missing, so NotAllowed")
    local frame = h.env.CreateFrame("Frame")
    throws(function() frame:DesaturateHierarchy(health) end, "NotAllowed")
    truthy(h.env.issecretvalue(health), "issecretvalue takes it by reference")
    local text = frame:CreateFontString()
    text:SetText(health) -- AllowedWhenTainted
    local bar = h.env.CreateFrame("StatusBar")
    bar:SetValue(health)
end)

test("a secret reaching a setter makes that aspect's getters secret until SetToDefaults", function()
    local h = Harness.New()
    local text = h.env.CreateFrame("Frame"):CreateFontString()
    text:SetText("plain")
    falsy(h.env.issecretvalue(text:GetText()))
    text:SetText(Secret("hidden"))
    truthy(h.env.issecretvalue(text:GetText()))
    text:SetText("plain again")
    truthy(h.env.issecretvalue(text:GetText()), "the aspect stays secret")
    truthy(text:HasAnySecretAspect())
    text:SetToDefaults()
    falsy(h.env.issecretvalue(text:GetText()), "cleared")
end)

test("SetFormattedText formats a secret into a secret string", function()
    local h = Harness.New()
    local text = h.env.CreateFrame("Frame"):CreateFontString()
    text:SetFormattedText("%d%%", Secret(42))
    truthy(h.env.issecretvalue(text:GetText()))
    eq(Reveal(text:GetText()), "42%")
end)

-- Blizzard_Game routes ADDON_ACTION_BLOCKED to a "blocked" message and ADDON_ACTION_FORBIDDEN to
-- a popup; the client itself skips the call and the caller keeps running.
local function WatchBlocked(h)
    local seen = {}
    local frame = h.env.CreateFrame("Frame")
    frame:RegisterEvent("ADDON_ACTION_BLOCKED")
    frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    frame:SetScript("OnEvent", function(_, event, addon, fn) seen[#seen + 1] = event .. ":" .. addon .. ":" .. fn end)
    return seen
end

test("protected methods on protected frames are blocked during lockdown: the call does nothing, the caller continues", function()
    local h = Harness.New()
    h:ExpectBlocked(2) -- the calls under test
    local seen = WatchBlocked(h)
    local secure = h.env.CreateFrame("Button", nil, nil, "SecureActionButtonTemplate")
    local holder = h.env.CreateFrame("Frame")
    local child = h.env.CreateFrame("Button", nil, holder, "SecureHandlerBaseTemplate")
    local plain = h.env.CreateFrame("Frame")
    h:EnterCombat()
    local after = false
    secure:Hide()
    after = true
    truthy(after, "code after a blocked call runs")
    truthy(secure:IsShown(), "the blocked Hide did nothing")
    holder:SetPoint("CENTER")
    eq(holder:GetNumPoints(), 0, "a parent of a protected frame is protected")
    plain:Hide()
    plain:SetPoint("CENTER")
    eq(#h.blocked, 2)
    eq(h.blocked[1], "Button:Hide (SimpleFrameAPI)")
    eq(seen[1], "ADDON_ACTION_BLOCKED:AddOn:Button:Hide (SimpleFrameAPI)")
    h:LeaveCombat()
    secure:Hide()
    holder:Hide()
    falsy(child:IsVisible(), "hidden with its parent")
end)

test("opening Blizzard's settings panel from addon code is forbidden: it froze the client on close", function()
    local h = Harness.New()
    h:ExpectBlocked(3) -- the calls under test
    h.env.Settings.OpenToCategory(7)
    h.env.SettingsPanel:OpenToCategory(7)
    h.env.SettingsPanel:Open()
    eq(#h.opened, 0, "nothing opened")
    eq(table.concat(h.forbidden, ","), "C_SettingsUtil.OpenSettingsPanel,SettingsPanel:OpenToCategory,SettingsPanel:Open")
end)

test("Settings layouts: controls join their own category's layout, headers go where they're added", function()
    local h = Harness.New()
    local Settings = h.env.Settings
    local main, mainLayout = Settings.RegisterVerticalLayoutCategory("Main")
    local sub, subLayout = Settings.RegisterVerticalLayoutSubcategory(main, "Sub")
    truthy(main:GetID() ~= sub:GetID(), "each category has its own id")
    local a = Settings.RegisterProxySetting(main, "A", "boolean", "A", false, function() return false end, function() end)
    local b = Settings.RegisterProxySetting(sub, "B", "boolean", "B", false, function() return false end, function() end)
    subLayout:AddInitializer(h.env.CreateSettingsListSectionHeaderInitializer("Top"))
    Settings.CreateCheckbox(sub, b, "tip")
    local header = h.env.CreateSettingsListSectionHeaderInitializer("Head", "tooltip")
    eq(header:GetData().name, "Head")
    eq(header:GetData().tooltip, "tooltip")
    mainLayout:AddInitializer(header)
    Settings.CreateCheckbox(main, a)
    eq(h.settingsPages[1].name, "Main")
    eq(h.settingsPages[1].parent, nil)
    eq(h.settingsPages[1].entries[1].header, "Head")
    eq(h.settingsPages[1].entries[2].variable, "A")
    eq(h.settingsPages[2].parent, "Main")
    eq(h.settingsPages[2].entries[1].header, "Top")
    eq(h.settingsPages[2].entries[2].variable, "B")
    eq(b.control, "checkbox")
    throws(function() Settings.RegisterAddOnCategory(sub) end, "subcategory")
    Settings.RegisterAddOnCategory(main)
    eq(h.category, main)
end)

test("a protected global is forbidden to addon code at any time", function()
    local h = Harness.New()
    h:ExpectBlocked(1) -- the calls under test
    local seen = WatchBlocked(h)
    local ran = false
    local compare = h:WrapFunction("C_TooltipComparison.CompareItem", function() ran = true end)
    compare()
    falsy(ran)
    eq(h.forbidden[1], "C_TooltipComparison.CompareItem")
    eq(seen[1], "ADDON_ACTION_FORBIDDEN:AddOn:C_TooltipComparison.CompareItem")
end)

test("HasRestrictions: a specific marker replaces the lockdown rule, otherwise lockdown blocks", function()
    local h = Harness.New()
    h:ExpectBlocked(1) -- the calls under test
    local calls = 0
    local send = h:WrapFunction("C_ChatInfo.SendChatMessage", function() calls = calls + 1 end)
    local propagate = h.env.CreateFrame("Frame")
    h:EnterCombat()
    send("hi", "PARTY") -- RestrictedForMacroChatMessages: macros only
    eq(calls, 1)
    propagate:SetPropagateKeyboardInput(true) -- HasRestrictions, no marker: blocked in lockdown
    eq(h.blocked[1], "Frame:SetPropagateKeyboardInput (SimpleFrameAPI)")
end)

Harness.DefineAddOn("HarnessProbe", {
    savedVariables = { "ProbeDB" }, savedVariablesPerCharacter = { "ProbeCharDB" },
    sources = { [[
        local _, ns = ...
        ns.atLoad = { db = ProbeDB, char = ProbeCharDB }
        ProbeDB = ProbeDB or { default = true }
        ns.frame = CreateFrame("Frame")
        ns.frame:RegisterEvent("ADDON_LOADED")
        ns.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        ns.frame:SetScript("OnEvent", function(_, event, a, b)
            if event == "ADDON_LOADED" then
                ns.loaded = { db = ProbeDB, char = ProbeCharDB and ProbeCharDB.count, loggedIn = IsLoggedIn() }
                ProbeCharDB = ProbeCharDB or { count = 0 }
                ProbeCharDB.count = ProbeCharDB.count + 1
            else
                ns.world = { a, b, loggedIn = IsLoggedIn() }
            end
        end)
    ]] },
})

test("SavedVariables are nil while files run and assigned before ADDON_LOADED", function()
    local h = Harness.New({ saved = { ProbeDB = { value = 1 }, ProbeCharDB = { count = 4 } } })
    local ns = h:LoadAddon("HarnessProbe")
    eq(ns.atLoad.db, nil, "account table while files run")
    eq(ns.atLoad.char, nil, "per-character table while files run")
    eq(ns.loaded.db.value, 1, "restored value replaces the file's default")
    eq(ns.loaded.char, 4)
    eq(ns.loaded.loggedIn, false, "not logged in during ADDON_LOADED")
    eq(ns.world.loggedIn, true)
end)

test("a missing SavedVariable keeps what the files assigned", function()
    local h = Harness.New()
    local ns = h:LoadAddon("HarnessProbe")
    eq(ns.loaded.db.default, true)
    eq(ns.loaded.char, nil)
end)

test("Reload and Relog write SavedVariables and pass the right login arguments", function()
    local h = Harness.New()
    local ns = h:LoadAddon("HarnessProbe")
    eq(ns.world[1], true)
    eq(ns.world[2], false)
    h:Reload()
    ns = h.ns
    eq(ns.world[1], false, "reload: not an initial login")
    eq(ns.world[2], true, "reload: reloading UI")
    eq(h.env.ProbeCharDB.count, 2, "per-character table carried over")
    local before = h.env.GetServerTime()
    h:Relog(3600)
    eq(h.ns.world[1], true)
    eq(h.ns.world[2], false)
    eq(h.env.GetServerTime() - before, 3600)
    eq(h.env.ProbeCharDB.count, 3)
end)

Harness.DefineAddOn("SerializeProbe", { savedVariables = { "SerDB" }, sources = { [[
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGOUT")
    frame:SetScript("OnEvent", function()
        local shared = { x = 1 }
        SerDB = { a = shared, b = shared, inf = math.huge, nan = 0 / 0, fn = print, frame = frame,
            [true] = "boolean key", [1.5] = "number key", list = { "x", "y" } }
        SerDB.self = SerDB
    end)
]] } })

test("SavedVariables keep only what the client writes: copies, no cycles, no inf or NaN", function()
    local h = Harness.New()
    h:LoadAddon("SerializeProbe")
    h:EnterCombat()
    h:Reload()
    local db = rawget(h.env, "SerDB")
    eq(db.a.x, 1)
    eq(db.b.x, 1)
    falsy(db.a == db.b, "a shared table is written twice, as copies")
    eq(db.self, nil, "a cycle's back-reference isn't written")
    eq(db.inf, nil)
    eq(db.nan, nil)
    eq(db.fn, nil)
    eq(db.frame, nil)
    eq(db[true], nil)
    eq(db[1.5], "number key")
    eq(table.concat(db.list, ","), "x,y")
end)

Harness.DefineAddOn("SecretSaver", { savedVariables = { "LeakDB" }, sources = { [[
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGOUT")
    frame:SetScript("OnEvent", function() LeakDB = { health = UnitHealth("player") } end)
]] } })

Harness.DefineAddOn("SecretKeySaver", { savedVariables = { "KeyDB" }, sources = { [[
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGOUT")
    frame:SetScript("OnEvent", function() KeyDB = { [UnitHealth("player")] = true } end)
]] } })

test("a secret that reaches SavedVariables is an error, not a silent drop", function()
    local h = Harness.New()
    h:LoadAddon("SecretSaver")
    throws(function() h:Reload() end, "a secret value reached SavedVariables")
end)

test("a secret table key that reaches SavedVariables is an error, not a silent drop", function()
    local h = Harness.New()
    h:LoadAddon("SecretKeySaver")
    throws(function() h:Reload() end, "a secret table key reached SavedVariables")
end)

test("a protected call the test didn't expect to be blocked fails it, as the client would show the player", function()
    local h = Harness.New()
    h.env.SetRaidTarget("target", 8)
    truthy((h:UnexpectedErrors() or ""):find("blocked calls (expected 0): SetRaidTarget", 1, true), h:UnexpectedErrors())
    h:ExpectBlocked("SetRaidTarget")
    eq(h:UnexpectedErrors(), nil)
end)

test("Relog ends combat, lockdown and restrictions; Reload keeps them", function()
    local h = Harness.New()
    h:LoadAddon("HarnessProbe")
    h:EnterCombat()
    h:SetRestriction("Map", true)
    h:Reload()
    truthy(h.env.InCombatLockdown(), "a reload in combat is still in combat")
    h:Relog()
    falsy(h.env.InCombatLockdown())
    falsy(h.inCombat)
    falsy(h.env.C_RestrictedActions.IsAddOnRestrictionActive(h.env.Enum.AddOnRestrictionType.Map))
    falsy(Restricted(h))
end)

test("C_Timer callbacks run in due order as time advances, and cancel", function()
    local h = Harness.New()
    local log = {}
    h.env.C_Timer.After(2, function() log[#log + 1] = "after2@" .. h.env.GetTime() end)
    h.env.C_Timer.After(1, function() log[#log + 1] = "after1@" .. h.env.GetTime() end)
    local timer = h.env.C_Timer.NewTimer(1.5, function() log[#log + 1] = "timer" end)
    local cancelled = h.env.C_Timer.NewTimer(1.5, function() log[#log + 1] = "cancelled" end)
    cancelled:Cancel()
    truthy(cancelled:IsCancelled())
    local ticks = 0
    h.env.C_Timer.NewTicker(1, function() ticks = ticks + 1 end, 3)
    h:Advance(0.5)
    eq(#log, 0)
    h:Advance(10)
    eq(table.concat(log, ","), "after1@1,timer,after2@2")
    eq(ticks, 3, "ticker stops after its iterations")
    falsy(timer:IsCancelled())
end)

test("Advance refuses a timer that keeps rescheduling itself", function()
    local h = Harness.New()
    local n = 0
    local function Tick() n = n + 1; h.env.C_Timer.After(0, Tick) end
    h.env.C_Timer.After(0, Tick)
    throws(function() h:Advance(0) end, "keeps rescheduling itself")
    eq(n, Harness.MAX_TIMER_CALLBACKS)
end)

test("a ticker cancels from its own callback, and a callback error is reported", function()
    local h = Harness.New()
    local ticks = 0
    h.env.C_Timer.NewTicker(1, function(self) ticks = ticks + 1; if ticks == 2 then self:Cancel() end end)
    h.env.C_Timer.After(1, function() error("boom") end)
    h:ExpectErrors("boom")
    h:Advance(5)
    eq(ticks, 2)
end)

test("an alpha animation group finishes when time passes its duration", function()
    local h = Harness.New()
    local frame = h.env.CreateFrame("Frame")
    local group = frame:CreateAnimationGroup()
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(0.5)
    fade:SetStartDelay(2)
    group:SetToFinalAlpha(true)
    local finished = 0
    group:SetScript("OnFinished", function() finished = finished + 1 end)
    group:Play()
    truthy(group:IsPlaying())
    h:Advance(2)
    eq(finished, 0)
    h:Advance(0.5)
    eq(finished, 1)
    eq(frame:GetAlpha(), 0)
    group:Play()
    group:Stop()
    h:Advance(5)
    eq(finished, 1, "a stopped group doesn't finish")
end)

test("a dispatch goes to the frames registered when it starts, and handler errors are reported", function()
    local h = Harness.New()
    local late
    local first = h.env.CreateFrame("Frame")
    first:RegisterEvent("PLAYER_TARGET_CHANGED")
    first:SetScript("OnEvent", function()
        late = h.env.CreateFrame("Frame")
        late:RegisterEvent("PLAYER_TARGET_CHANGED")
        late:SetScript("OnEvent", function() late.got = true end)
        error("first handler fails")
    end)
    local second = h.env.CreateFrame("Frame")
    second:RegisterEvent("PLAYER_TARGET_CHANGED")
    second:SetScript("OnEvent", function() second.got = true end)
    h:ExpectErrors("first handler fails")
    h:Fire("PLAYER_TARGET_CHANGED")
    truthy(second.got, "the others still run")
    falsy(late.got, "created during the dispatch")
end)

test("ExpectErrors takes a count or patterns", function()
    local h = Harness.New()
    h:ReportError("alpha")
    h:ReportError("beta")
    h:ExpectErrors(2)
    eq(h:UnexpectedErrors(), nil)
    h:ExpectErrors("beta", "alp")
    eq(h:UnexpectedErrors(), nil)
    h:ExpectErrors("alpha")
    truthy(h:UnexpectedErrors(), "an unmatched error fails")
    h:ExpectErrors("alpha", "beta", "gamma")
    truthy(h:UnexpectedErrors(), "a missing error fails")
    h:ExpectErrors(2)
end)

test("InCombatLockdown is false during PLAYER_REGEN_DISABLED", function()
    local h = Harness.New()
    local seen
    local frame = h.env.CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:SetScript("OnEvent", function() seen = h.env.InCombatLockdown() end)
    h:EnterCombat()
    eq(seen, false)
    eq(h.env.InCombatLockdown(), true)
end)

test("only real API is allowed", function()
    local h = Harness.New()
    local frame = h.env.CreateFrame("Frame")
    throws(function() frame:RegisterEvent("NOT_A_REAL_EVENT") end, "unknown event")
    throws(function() frame:NotARealMethod() end, "no method")
    throws(function() frame:SetVertexColor(1, 1, 1) end, "no method") -- a Region method, not a Frame's
    throws(function() return h.env.NotARealGlobal end, "undefined global")
    eq(h.env.string.dump, nil, "the client has no string.dump")
    throws(function() return h.env.SOUNDKIT.NOT_MODELED end, "SOUNDKIT")
end)

test("unit events respect their unit filter", function()
    local h = Harness.New()
    local count = 0
    local frame = h.env.CreateFrame("Frame")
    frame:RegisterUnitEvent("UNIT_HEALTH", "player")
    frame:SetScript("OnEvent", function() count = count + 1 end)
    h:Fire("UNIT_HEALTH", "target")
    h:Fire("UNIT_HEALTH", "player")
    eq(count, 1)
    eq(Harness.State(frame).calls.RegisterUnitEvent, 1, "widget calls are counted")
end)

test("unit-filtered events with a secret payload are delivered; unit tokens aren't wrapped", function()
    local h = Harness.New()
    local env = h.env
    h:SetTarget({})
    local cast, castUnit = 0, nil
    local f = env.CreateFrame("Frame")
    f:RegisterUnitEvent("UNIT_SPELLCAST_START", "target")
    f:SetScript("OnEvent", function(_, _, unit, guid) cast = cast + 1; castUnit = unit; truthy(env.issecretvalue(guid), "payload") end)
    h:Fire("UNIT_SPELLCAST_START", "target", "guid", 1, 1)
    eq(cast, 1)
    falsy(env.issecretvalue(castUnit), "the unit token stays plain")
    local aura = 0
    local g = env.CreateFrame("Frame")
    g:RegisterUnitEvent("UNIT_AURA", "player")
    g:SetScript("OnEvent", function(_, _, unit, info) aura = aura + 1; truthy(env.issecretvalue(info)); eq(unit, "player") end)
    h:EnterCombat()
    h:Fire("UNIT_AURA", "player", {})
    eq(aura, 1, "UNIT_AURA for the player in combat")
end)

test("widget state lives beside the widget: addon fields never collide with it", function()
    local h = Harness.New()
    local env = h.env
    local b = env.CreateFrame("Button", nil, env.UIParent)
    b.text = b:CreateFontString()
    eq(b:GetText(), nil, "Button:GetText isn't the addon's field")
    local f = env.CreateFrame("Frame")
    f.shown = false
    truthy(f:IsShown(), "an addon field doesn't hide the frame")
    local bar = env.CreateFrame("StatusBar")
    bar.value = 7
    eq(bar:GetValue(), nil)
    bar:SetValue(3)
    eq(bar.value, 7, "the addon's field is untouched")
    eq(Harness.State(bar).value, 3)
    truthy(h:WidgetState(bar) == Harness.State(bar))
    local g = env.CreateFrame("Frame")
    g.events = { PLAYER_TARGET_CHANGED = true }
    local got = 0
    g:SetScript("OnEvent", function() got = got + 1 end)
    h:Fire("PLAYER_TARGET_CHANGED")
    eq(got, 0, "an addon table isn't an event registration")
    eq(Harness.State({}), nil, "a plain table has no widget state")
end)

test("fontstrings measure their text: 7 px per character, 14 px per line, wrapped at their width", function()
    local h = Harness.New()
    local frame = h.env.CreateFrame("Frame")
    frame:SetSize(300, 50)
    local fs = frame:CreateFontString()
    eq(fs:GetStringWidth(), 0)
    eq(fs:GetStringHeight(), 0)
    fs:SetText("hello\nworld!")
    eq(fs:GetStringWidth(), 42)
    eq(fs:GetStringHeight(), 28)
    eq(fs:GetWidth(), 42, "an unsized fontstring is its text's size")
    fs:SetText(string.rep("x", 30))
    fs:SetWidth(70)
    eq(fs:GetStringHeight(), 42, "30 characters wrap at 10 per line")
    eq(fs:GetStringWidth(), 70)
    eq(fs:GetUnboundedStringWidth(), 210)
    fs:SetWordWrap(false)
    eq(fs:GetStringHeight(), 14)
    fs:SetWordWrap(true)
    fs:SetWidth(0)
    fs:SetPoint("LEFT", 16, 0)
    fs:SetPoint("RIGHT", -74, 0)
    eq(fs:GetWidth(), 210, "two anchors on the parent give the width")
    eq(fs:GetStringHeight(), 14)
    frame:SetHeight(80)
    eq(frame:GetHeight(), 80)
    eq(h.env.CreateFrame("Frame"):GetWidth(), 0, "an unsized frame is 0 wide")
    fs:SetText(Secret("hidden"))
    truthy(h.env.issecretvalue(fs:GetStringWidth()), "a secret aspect makes anchoring secret")
end)

test("hovering runs OnEnter and OnLeave on visible mouse-enabled widgets", function()
    local h = Harness.New()
    local button = h.env.CreateFrame("Button")
    local log = {}
    button:SetScript("OnEnter", function(_, motion) log[#log + 1] = "enter:" .. tostring(motion) end)
    button:SetScript("OnLeave", function() log[#log + 1] = "leave" end)
    truthy(h:Hover(button))
    truthy(h:Hover(button, false))
    button:Hide()
    falsy(h:Hover(button), "hidden")
    eq(table.concat(log, ","), "enter:true,leave")
end)

test("gamepad input and IsVisible use effective visibility", function()
    local h = Harness.New()
    local parent = h.env.CreateFrame("Frame")
    local child = h.env.CreateFrame("Frame", nil, parent)
    child:EnableGamePadButton(true)
    local got = 0
    child:SetScript("OnGamePadButtonDown", function() got = got + 1 end)
    parent:Hide()
    truthy(child:IsShown())
    falsy(child:IsVisible())
    h:Gamepad("PAD1", true)
    eq(got, 0, "a hidden parent hides the child")
    eq(h.propagated[1], "PAD1")
    parent:Show()
    h:Gamepad("PAD1", true)
    eq(got, 1)
end)

test("clicks reach visible mouse-enabled widgets; buttons are mouse-enabled", function()
    local h = Harness.New()
    local button = h.env.CreateFrame("Button")
    local clicks = 0
    button:SetScript("OnClick", function(_, which) clicks = clicks + 1; eq(which, "LeftButton") end)
    truthy(h:Click(button))
    local frame = h.env.CreateFrame("Frame")
    local ups = 0
    frame:SetScript("OnMouseUp", function() ups = ups + 1 end)
    falsy(h:Click(frame), "not mouse-enabled")
    frame:EnableMouse(true)
    h:Click(frame)
    eq(clicks, 1)
    eq(ups, 1)
end)

test("UnitCanAttack honors both units", function()
    local h = Harness.New()
    h:SetTarget(Enemy())
    truthy(h.env.UnitCanAttack("player", "target"))
    truthy(h.env.UnitCanAttack("target", "player"))
    falsy(h.env.UnitCanAttack("player", "player"))
    falsy(h.env.UnitCanAttack("player", "focus"), "a unit that doesn't exist")
end)

test("pet, focus, party, mouseover and nameplate units are absent until a test sets them", function()
    local h = Harness.New()
    local env = h.env
    h:EnterCombat()
    falsy(env.UnitExists("focus"))
    falsy(env.issecretvalue(env.UnitExists("focus")), "a missing unit isn't secret")
    eq(select("#", env.UnitClass("party1")), 0)
    h:SetUnit("party1", { isPlayer = true, classFile = "MAGE", inGroup = true, name = "Friend" })
    truthy(env.UnitExists("party1"))
    eq(select(2, env.UnitClass("party1")), "MAGE")
    h:SetUnit("nameplate3", { classFile = "WARRIOR" })
    h:SetRestriction("Encounter", true)
    truthy(env.issecretvalue(env.UnitClass("nameplate3")), "an NPC's identity in an encounter")
    h:SetUnit("nameplate3", nil)
    falsy(env.UnitExists("nameplate3"))
    throws(function() h:SetUnit("boss9", {}) end, "configurable")
end)

test("UnitPowerType returns the token for each type", function()
    local h = Harness.New({ powerType = 1 })
    local _, token = h.env.UnitPowerType("player")
    eq(token, "RAGE")
    for powerType, expected in pairs({ [0] = "MANA", [2] = "FOCUS", [3] = "ENERGY", [6] = "RUNIC_POWER" }) do
        h.player.powerType = powerType
        eq(select(2, h.env.UnitPowerType("player")), expected)
    end
end)

test("strsplit splits on any delimiter character, and honors its limit", function()
    local h = Harness.New()
    eq(table.concat({ h.env.strsplit(", ", "a,b c") }, "|"), "a|b|c")
    eq(table.concat({ h.env.strsplit(":", "a:b:c", 2) }, "|"), "a|b:c")
    eq(table.concat({ h.env.strsplit("%", "x%y") }, "|"), "x|y", "magic characters are literal")
end)

test("session fakes: money, XP, zones, clocks and formatting", function()
    local h = Harness.New({ money = 1234567, level = 12, xp = 300, xpMax = 900, rested = 0 })
    local env = h.env
    eq(env.GetMoney(), 1234567)
    eq(env.GetMoneyString(1234567), "123g 45s 67c")
    eq(env.GetMoneyString(0), "0c")
    eq(env.UnitLevel("player"), 12)
    eq(env.UnitXP("player"), 300)
    eq(env.UnitXPMax("player"), 900)
    eq(env.GetXPExhaustion(), nil, "no rested XP returns nil")
    h.player.rested = 450
    eq(env.GetXPExhaustion(), 450)
    eq(env.GetRealZoneText(), "Elwynn Forest")
    eq(env.SecondsToTime(2 * 3600 + 14 * 60 + 5), "2 Hr 14 Min")
    eq(env.SecondsToTime(90, false, true), "1 Minute 30 Seconds")
    eq(env.date("%Y-%m-%d %H:%M", env.time()), "2025-09-25 12:00")
    eq(env.time({ year = 2025, month = 9, day = 25, hour = 12 }), env.GetServerTime())
    h:Advance(3600)
    eq(env.GetServerTime() - Harness.SERVER_EPOCH, 3600, "Advance moves the server clock")
    eq(env.Enum.PowerType.Energy, 3, "Enum comes from the documented enumerations")
end)

test("sound kits play through PlaySound and C_Sound.PlaySound", function()
    local h = Harness.New()
    local ok, handle = h.env.PlaySound(h.env.SOUNDKIT.LFG_REWARDS)
    truthy(ok)
    h.env.C_Sound.PlaySound(h.env.SOUNDKIT.IG_SPELLBOOK_OPEN, "Master")
    eq(h.soundKits[1].kit, 17316)
    eq(h.soundKits[1].handle, handle)
    eq(h.soundKits[2].kit, 829)
    eq(h.soundKits[2].channel, "Master")
end)

test("a TOC file missing on disk fails that addon's load, not the run", function()
    Harness.DefineAddOn("MissingFileProbe", { sources = { "" }, missing = { "Gone.lua" } })
    local h = Harness.New()
    throws(function() h:LoadFiles("MissingFileProbe") end, "Gone.lua, which doesn't exist")
end)
