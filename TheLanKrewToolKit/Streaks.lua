local addonName, ns = ...

-- Streaks: an Unreal Tournament announcer for your killing blows on players (ByteTerrace_Core's kills fact,
-- kills.blows), shared with the Krew. A kill counts for whoever landed it, as in Unreal, not for everyone the honorable
-- kill credits.
--
--   First blood  your first killing blow of the session, unless a Krew member drew it first.
--   Multi kills  kills each within MultiKillWindow of the last: double (2), multi (3), mega (4),
--                ultra (5), monster (6), ludicrous (7), holy shit (8 and on).
--   Sprees       kills without dying: killing spree (5), rampage (10), dominating (15),
--                unstoppable (20), godlike (25), wicked sick (30).
-- A kill announces one of them: a spree it reaches, else a multi kill, else first blood. You see it as a raid warning
-- and hear its sound (Streaks.* settings; the master sound switch applies). With Streaks.share on, the Krew sees your
-- first blood, each spree, and the end of a spree when you die, with who ended it when the death recap names them (the
-- death fact's death.killer). A Krew member's first blood takes yours for the session. Krew messages only show a raid
-- warning. Whether first blood is drawn, and your kills since you last died, are saved per character, so a /reload
-- continues the session; the next login, or switching streaks off, starts them over.

-- the largest count accepted from a Krew message
local MaxCount = 9999

local MultiKills = {
    { file = "DoubleKill", key = "doubleKill", label = "Double kill", word = "double" },
    { file = "MultiKill", key = "multiKill", label = "Multi kill", word = "multi" },
    { file = "MegaKill", key = "megaKill", label = "Mega kill", word = "mega" },
    { file = "UltraKill", key = "ultraKill", label = "Ultra kill", word = "ultra" },
    { file = "MonsterKill", key = "monsterKill", label = "Monster kill", word = "monster" },
    { file = "LudicrousKill", key = "ludicrousKill", label = "Ludicrous kill", word = "ludicrous" },
    { file = "HolyShit", key = "holyShit", label = "Holy shit", word = "holy" },
}

-- seconds between kills; Unreal's 4 is too short for WoW's fights
local MultiKillWindow = 10
-- kills: a shorter run ending isn't news
local SpreeEndMinimum = 5

local Sprees = {
    { file = "KillingSpree", key = "killingSpree", kills = 5, label = "Killing spree", says = "is on a killing spree", word = "spree" },
    { file = "Rampage", key = "rampage", kills = 10, label = "Rampage", says = "is on a rampage", word = "rampage" },
    { file = "Dominating", key = "dominating", kills = 15, label = "Dominating", says = "is dominating", word = "dominating" },
    { file = "Unstoppable", key = "unstoppable", kills = 20, label = "Unstoppable", says = "is unstoppable", word = "unstoppable" },
    { file = "Godlike", key = "godlike", kills = 25, label = "Godlike", says = "is godlike", word = "godlike" },
    { file = "WickedSick", key = "wickedSick", kills = 30, label = "Wicked sick", says = "is wicked sick", word = "wicked" },
}

local GetTime, IsLoggedIn, tostring = GetTime, IsLoggedIn, tostring
local min = math.min

local Addon = ns.Addon
local Alert, Krew = ns.Cards.Alert, ns.Krew
local CleanCount, CleanText = ns.KrewFields.CleanCount, ns.KrewFields.CleanText
local MultiKeys, SpreeAt, SpreeByKey, SpreeKeys = {}, {}, {}, {}
local SoundBank = ns.SoundBank

for i, spree in ipairs(Sprees) do
    SpreeAt[spree.kills] = spree
    SpreeByKey[spree.key] = spree
    SpreeKeys[i] = spree.key
    SoundBank:Define(spree.key, { file = spree.file, label = spree.label, row = "Streaks.sprees", word = spree.word })
end

for i, multi in ipairs(MultiKills) do
    MultiKeys[i] = multi.key
    SoundBank:Define(multi.key, { file = multi.file, label = multi.label, row = "Streaks.multiKills", word = multi.word })
end

SoundBank:Define("firstBlood", { file = "FirstBlood", label = "First blood", row = "Streaks.firstBlood", word = "first" })

-- the spree your last death ended, until its killer is known
local EndedAt
-- GetTime() of your last killing blow
local LastKillAt
-- kills in the current multi kill
local Multi = 0
local StreaksModule

local function OnMessage(sender, fields)
    local event, count = fields[1], CleanCount(fields[2], MaxCount)

    if not count then
        return
    end

    local spree = SpreeByKey[event]

    if event == "firstBlood" then
        StreaksModule:Set("firstBloodTaken", true)
        Alert(sender .. " drew first blood!")
    elseif event == "ended" then
        local killer = CleanText(fields[3])

        Alert(("%s's spree ended at %d kills%s."):format(sender, count, ((killer ~= "") and (" by " .. killer)) or ""))
    elseif spree then
        Alert(("%s %s! (%d kills)"):format(sender, spree.says, count))
    end
end

local function Share(event, count, killer)
    if StreaksModule:Get("share") then
        Krew:Send("STREAK", { event, tostring(count), killer })
    end
end

-- What added killing blows announce: a spree they reach, else a multi kill, else first blood.
local function OnKill(added)
    local now = GetTime()

    Multi = (((LastKillAt and ((now - LastKillAt) <= MultiKillWindow)) and (Multi + 1)) or 1)
    LastKillAt = now
    local streak = (StreaksModule:Get("streak") + added)

    StreaksModule:Set("streak", streak)
    local first = not StreaksModule:Get("firstBloodTaken")

    StreaksModule:Set("firstBloodTaken", true)
    local spree = SpreeAt[streak]

    if spree then
        Alert(("%s! %d kills without dying."):format(spree.label, streak))
        SoundBank:Play(spree.key)
        Share(spree.key, streak)
    elseif Multi >= 2 then
        local multi = MultiKills[min(Multi - 1, #MultiKills)]

        Alert(multi.label .. "!")
        SoundBank:Play(multi.key)
    elseif first then
        Alert("First blood!")
        SoundBank:Play("firstBlood")
        Share("firstBlood", 1)
    end
end

-- Reports the spree your last death ended; killer is who ended it, "" when unknown.
local function ReportEnd(killer)
    if EndedAt then
        local by = (((killer ~= "") and (" " .. killer .. " ended it.")) or "")

        Addon:Print(("Your spree ended at %d kills.%s"):format(EndedAt, by))
        Share("ended", EndedAt, ((killer ~= "") and killer) or nil)
        EndedAt = nil
    end
end

-- A death ends the streak and any multi kill at once; its report waits for the killer.
local function OnDeath()
    -- an earlier death whose killer never came
    ReportEnd("")
    local streak = StreaksModule:Get("streak")

    EndedAt = (((streak >= SpreeEndMinimum) and streak) or nil)
    StreaksModule:Set("streak", 0)
    Multi, LastKillAt = 0, nil
end

-- A new session: no first blood yet, and no kills.
local function StartOver()
    StreaksModule:Set("firstBloodTaken", false)
    StreaksModule:Set("streak", 0)
end

StreaksModule = Addon:Module("Streaks", {
    description = "Unreal Tournament's announcer for your world PvP killing blows: first blood, multi kills and killing sprees. Kills in battlegrounds, arenas or other instances do not count.",
    label = "Kill streaks",
    OnDisable = function()
        StartOver()
        Multi, LastKillAt, EndedAt = 0, nil, nil
    end,
    OnEnable = function(module)
        if IsLoggedIn() then
            -- switched on mid-session
            StartOver()
        end

        module:On("PLAYER_ENTERING_WORLD", function(isInitialLogin)
            if isInitialLogin then
                StartOver()
            end
        end)

        module:Listen(Krew, "STREAK", OnMessage)

        module:OnIncrease("kills.blows", function(_, count, previous)
            OnKill(count - previous)
        end)

        module:OnIncrease("death.count", OnDeath)

        module:OnIncrease("death.attributed", function(state)
            ReportEnd(((state:Get("death.killerKind") == "self") and "") or state:Get("death.killer"))
        end)
    end,
    page = "Sounds",
    state = {
        SoundBank:Row("firstBlood", "First blood", "Your first killing blow on a player this session, unless a Krew member drew it first.", { "firstBlood" }),
        SoundBank:Row("multiKills", "Multi kills", ("Killing blows each within %d seconds of the last: double kill and up."):format(MultiKillWindow), MultiKeys),
        SoundBank:Row("sprees", "Killing sprees", "Every 5 killing blows without dying, from killing spree to wicked sick.", SpreeKeys),
        { default = true,
            description = "Your Krew sees a raid warning for your first blood, each spree, and when a spree of 5 or more ends.",
            kind = "boolean", label = "Share my sprees with the Krew", name = "share" },
        { default = false, kind = "boolean", name = "firstBloodTaken", scope = "character" },
        { default = 0, kind = "number", min = 0, name = "streak", scope = "character", step = 1 },
    },
    uses = { "kills", "death" },
})
