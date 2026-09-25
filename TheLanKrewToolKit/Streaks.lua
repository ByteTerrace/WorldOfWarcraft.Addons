local addonName, ns = ...

-- Streaks: an Unreal Tournament announcer for your killing blows on players (Honor.killingBlows,
-- Honor.lua), shared with the Krew. A kill counts for whoever landed it, as in Unreal, not for
-- everyone the honorable kill credits.
--
--   First blood  your first killing blow of the session, unless a Krew member drew it first.
--   Multi kills  kills each within MultiKillWindow of the last: double (2), multi (3), mega (4),
--                ultra (5), monster (6), ludicrous (7), holy shit (8 and on).
--   Sprees       kills without dying: killing spree (5), rampage (10), dominating (15),
--                unstoppable (20), godlike (25), wicked sick (30).
-- A kill announces one of them: a spree it reaches, else a multi kill, else first blood. You see it
-- as a raid warning and hear its sound (Streaks.* settings; the master sound switch applies). With
-- Streaks.share on, the Krew sees your first blood, each spree, and the end of a spree when you die,
-- with who ended it when the death recap names them (Honor.killer).
-- A Krew member's first blood takes yours for the session. Krew messages only show a raid warning.

local MultiKillWindow = 10 -- seconds between kills; Unreal's 4 is too short for WoW's fights
local SpreeEndMinimum = 5  -- kills: a shorter run ending isn't news
local MaxCount = 9999      -- the largest count accepted from a Krew message
local Sprees = {
    { kills = 5, key = "killingSpree", file = "KillingSpree", word = "spree", label = "Killing spree", says = "is on a killing spree" },
    { kills = 10, key = "rampage", file = "Rampage", word = "rampage", label = "Rampage", says = "is on a rampage" },
    { kills = 15, key = "dominating", file = "Dominating", word = "dominating", label = "Dominating", says = "is dominating" },
    { kills = 20, key = "unstoppable", file = "Unstoppable", word = "unstoppable", label = "Unstoppable", says = "is unstoppable" },
    { kills = 25, key = "godlike", file = "Godlike", word = "godlike", label = "Godlike", says = "is godlike" },
    { kills = 30, key = "wickedSick", file = "WickedSick", word = "wicked", label = "Wicked sick", says = "is wicked sick" },
}
local MultiKills = {
    { key = "doubleKill", file = "DoubleKill", word = "double", label = "Double kill" },
    { key = "multiKill", file = "MultiKill", word = "multi", label = "Multi kill" },
    { key = "megaKill", file = "MegaKill", word = "mega", label = "Mega kill" },
    { key = "ultraKill", file = "UltraKill", word = "ultra", label = "Ultra kill" },
    { key = "monsterKill", file = "MonsterKill", word = "monster", label = "Monster kill" },
    { key = "ludicrousKill", file = "LudicrousKill", word = "ludicrous", label = "Ludicrous kill" },
    { key = "holyShit", file = "HolyShit", word = "holy", label = "Holy shit" },
}

local GetTime, tonumber, tostring = GetTime, tonumber, tostring
local min = math.min

local Addon = ns.Addon
local Krew, Alert, CleanText = ns.Krew, ns.Warband.Alert, ns.Warband.CleanText
local SoundBank = ns.SoundBank
local Define, Row, Play = SoundBank.Define, SoundBank.Row, SoundBank.Play

local SpreeAt, SpreeByKey, SpreeKeys, MultiKeys = {}, {}, {}, {}
for i, spree in ipairs(Sprees) do
    SpreeAt[spree.kills] = spree
    SpreeByKey[spree.key] = spree
    SpreeKeys[i] = spree.key
    Define(spree.key, { file = spree.file, word = spree.word, label = spree.label, row = "Streaks.sprees" })
end
for i, multi in ipairs(MultiKills) do
    MultiKeys[i] = multi.key
    Define(multi.key, { file = multi.file, word = multi.word, label = multi.label, row = "Streaks.multiKills" })
end
Define("firstBlood", { file = "FirstBlood", word = "first", label = "First blood", row = "Streaks.firstBlood" })

local StreaksModule
local FirstBloodTaken = false -- this session's first blood is drawn, by you or the Krew
local Multi = 0               -- kills in the current multi kill
local LastKillAt              -- GetTime() of your last killing blow
local Streak = 0              -- your kills since you last died, as of the last kill
local EndedAt                 -- the spree your last death ended, until its killer is known

local function Share(event, count, killer)
    if StreaksModule:Get("share") then
        Krew.Send("STREAK", { event, tostring(count), killer })
    end
end

-- What a kill announces: a spree it reaches, else a multi kill, else first blood.
local function OnKill(streak)
    local now = GetTime()
    Multi = (LastKillAt and now - LastKillAt <= MultiKillWindow) and Multi + 1 or 1
    LastKillAt, Streak = now, streak
    local first = not FirstBloodTaken
    FirstBloodTaken = true
    local spree = SpreeAt[streak]
    if spree then
        Alert(("%s! %d kills without dying."):format(spree.label, streak))
        Play(spree.key)
        Share(spree.key, streak)
    elseif Multi >= 2 then
        local multi = MultiKills[min(Multi - 1, #MultiKills)]
        Alert(multi.label .. "!")
        Play(multi.key)
    elseif first then
        Alert("First blood!")
        Play("firstBlood")
        Share("firstBlood", 1)
    end
end

-- Reports the spree your last death ended; killer is who ended it, "" when unknown.
local function ReportEnd(killer)
    if EndedAt then
        local by = killer ~= "" and (" " .. killer .. " ended it.") or ""
        Addon:Print(("Your spree ended at %d kills.%s"):format(EndedAt, by))
        Share("ended", EndedAt, killer ~= "" and killer or nil)
        EndedAt = nil
    end
end

-- A death ends the streak and any multi kill at once; its report waits for the killer.
local function OnDeath()
    ReportEnd("") -- an earlier death whose killer never came
    EndedAt = Streak >= SpreeEndMinimum and Streak or nil
    Streak, Multi, LastKillAt = 0, 0, nil
end

StreaksModule = Addon:Module("Streaks", {
    label = "Kill streaks",
    page = "Sounds",
    description = "Unreal Tournament's announcer for your killing blows on players: first blood, multi kills and killing sprees.",
    state = {
        Row("firstBlood", "First blood", "Your first killing blow on a player this session, unless a Krew member drew it first.", { "firstBlood" }),
        Row("multiKills", "Multi kills", ("Killing blows each within %d seconds of the last: double kill and up."):format(MultiKillWindow), MultiKeys),
        Row("sprees", "Killing sprees", "Every 5 killing blows without dying, from killing spree to wicked sick.", SpreeKeys),
        { name = "share", kind = "boolean", default = true, label = "Share my sprees with the Krew",
            description = "Your Krew sees a raid warning for your first blood, each spree, and when a spree of 5 or more ends." },
    },
    OnEnable = function(module)
        local kills, deaths, killedBy = module:Get("Honor.killingBlows"), module:Get("Honor.deaths"), module:Get("Honor.killedBy")
        module:Watch({ "Honor.killingBlows" }, function(state)
            local now = state:Get("Honor.killingBlows")
            if now > kills then
                OnKill(state:Get("Honor.streak"))
            end
            kills = now
        end, true)
        module:Watch({ "Honor.deaths" }, function(state)
            local now = state:Get("Honor.deaths")
            if now > deaths then
                OnDeath()
            end
            deaths = now
        end, true)
        module:Watch({ "Honor.killedBy" }, function(state)
            local now = state:Get("Honor.killedBy")
            if now > killedBy then
                ReportEnd(state:Get("Honor.killerKind") == "self" and "" or state:Get("Honor.killer"))
            end
            killedBy = now
        end, true)
    end,
    OnDisable = function()
        Streak, Multi, LastKillAt, EndedAt = 0, 0, nil, nil
    end,
})

Krew.Listen("STREAK", function(sender, fields)
    local event, count = fields[1], tonumber(fields[2])
    if not StreaksModule.Enabled or not count or count < 1 or count > MaxCount or count % 1 ~= 0 then
        return
    end
    local spree = SpreeByKey[event]
    if event == "firstBlood" then
        FirstBloodTaken = true
        Alert(sender .. " drew first blood!")
    elseif event == "ended" then
        local killer = CleanText(fields[3])
        Alert(("%s's spree ended at %d kills%s."):format(sender, count, killer ~= "" and (" by " .. killer) or ""))
    elseif spree then
        Alert(("%s %s! (%d kills)"):format(sender, spree.says, count))
    end
end)
