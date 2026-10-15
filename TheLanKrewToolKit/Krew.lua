local addonName, ns = ...

-- Krew: share fun moments with friends in your group who also run the toolkit.
--
--   Hello      when you group up (or /reload in a group), you say hello once: "HELLO:<version>\t0".
--              Each hello that isn't a reply gets one reply ("...\t1") within ReplyDelay, a burst
--              of them one between them, and a reply gets none, so two Krews never ping-pong. A
--              card shows who's here, and /tlk krew lists them with the version each runs. Once
--              per group, when NewerQuorum members run a newer version than yours (compared as
--              numbers, major.minor.patch), chat says so.
--   Ding       your level-ups appear as a card for the rest of the Krew.
--   Flawless   so do your flawless victories (Victory.flawlessWins, Kombat.lua).
--   Scholar    and the riddles a young scholar solves (Scholar.stars).
--
-- ns.Krew is the Krew module's Comms (ByteTerrace_Core's Comms.lua): every feature that talks to the Krew (Warband's
-- marks, sightings and rallies; Streaks' sprees) sends and listens through it, so they all play by Blizzard's addon
-- rules the same way: hidden messages to your own group only, rare and rate-limited, never during chat messaging
-- lockdown, parsed strictly, and never heard or sent while the Krew module is off. Received messages only ever show a
-- card or an alert, update the ledger, or (a rally, with Warband.rallyWaypoint on) set a map waypoint; none acts on
-- your behalf.
--
-- ns.KrewFields cleans the fields of received messages for every feature that listens:
--   CleanText(text)         a zone, subzone or name to show, or "".
--   CleanCount(text, max)   a whole number from 1 to max written in digits, or nil.
--   MaxLevel                the highest level a message may carry.
-- Neither passes a "|" or a control character: someone else's message never puts a link, texture or color on your
-- screen.
--
-- Krew members are the group members whose hello you heard; one who leaves the group leaves the Krew once the roster
-- settles: a raid forming fires a burst of roster updates, and the roster is read once, PruneDelay after the last of
-- them. Showing or listing the Krew reads it first.

local KrewIcon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"
-- The highest level accepted from a message.
local MaxLevel = 200
-- The most stars accepted from a message.
local MaxStars = 99999
-- The longest text, in bytes, accepted from a message.
local MaxText = 60
-- How many Krew members on a newer version make it worth saying so.
local NewerQuorum = 2
local PartyUnits, RaidUnits = {}, {}
local Prefix = "TLKKrew1"
-- How long, in seconds, without a roster update ends a burst of them.
local PruneDelay = 1
-- How long, in seconds, a burst of hellos gathers before one reply.
local ReplyDelay = 1
local RollCallDelay = 2

for i = 1, 40 do
    PartyUnits[i], RaidUnits[i] = ("party" .. i), ("raid" .. i)
end

local concat, sort = table.concat, table.sort
local GetNumGroupMembers, GetTime, IsInGroup, IsInRaid = GetNumGroupMembers, GetTime, IsInGroup, IsInRaid
local ipairs, next, pairs, tonumber, type, wipe = ipairs, next, pairs, tonumber, type, wipe
local SOUNDKIT = SOUNDKIT

local Addon = ns.Addon
local Names = ByteTerrace.Names
local ShowCard = ns.Cards.Show

-- Krew is the module and Messages is its Comms (ns.Krew), both assigned at the end of the file.
local Krew, Messages
-- Maps each member running the toolkit, by name, to the version its hello named ("" when unreadable).
local Members = {}
-- Scratch space while pruning Members: maps each of the group's members, by name, to true.
local Present = {}
-- The pending timer that prunes Members once a burst of roster updates settles.
local PruneTimer
-- The pending timer that answers a burst of hellos with one reply.
local ReplyTimer
-- The pending timer that merges a burst of hellos into one card.
local RollCallTimer
-- The GetTime() of the last roster update.
local RosterAt = 0
-- Whether you said hello to this group.
local Said = false
-- Whether this group heard that a newer version is out.
local ToldNewer = false

--- A count from a message: a whole number from 1 to max written in digits only (no sign, exponent, hex or "inf"), or
--- nil.
---@param text string?
---@param max integer
---@return integer?
local function CleanCount(text, max)
    if (type(text) ~= "string") or (#text > 9) or not text:find("^%d+$") then
        return nil
    end

    local count = tonumber(text)

    return ((((count >= 1) and (count <= max)) and count) or nil)
end

--- A text field from a message (a zone, a subzone, a name), or "" when it's missing, longer than MaxText, or holds a
--- "|" or a control character.
---@param text string?
---@return string
local function CleanText(text)
    if (type(text) ~= "string") or (#text > MaxText) or text:find("[|%c]") then
        return ""
    end

    return text
end

-- A version from a message, "major.minor.patch" in digits (at most 6 each), or "".
local function CleanVersion(text)
    if (type(text) ~= "string") or not text:find("^%d%d?%d?%d?%d?%d?%.%d%d?%d?%d?%d?%d?%.%d%d?%d?%d?%d?%d?$") then
        return ""
    end

    return text
end

-- Compares two versions CleanVersion accepts, part by part as numbers: below 0 when a is older, 0 when they're equal,
-- above 0 when a is newer.
local function CompareVersions(a, b)
    local a1, a2, a3 = a:match("^(%d+)%.(%d+)%.(%d+)$")
    local b1, b2, b3 = b:match("^(%d+)%.(%d+)%.(%d+)$")
    local major, minor = (tonumber(a1) - tonumber(b1)), (tonumber(a2) - tonumber(b2))

    if major ~= 0 then
        return major
    end

    if minor ~= 0 then
        return minor
    end

    return (tonumber(a3) - tonumber(b3))
end

-- Drops Krew members who left the group. While any member's name is unreadable, nobody is dropped. With no Krew members
-- there's no one to drop, and no name to read.
local function Prune()
    if next(Members) == nil then
        return
    end

    wipe(Present)
    local raid, count = IsInRaid(), GetNumGroupMembers()
    local units = ((raid and RaidUnits) or PartyUnits)

    if not raid then
        -- Party tokens leave out the player.
        count = (count - 1)
    end

    for i = 1, count do
        local name = Names.OfUnit(units[i])

        if not name then
            return
        end

        Present[name] = true
    end

    for name in pairs(Members) do
        if not Present[name] then
            Members[name] = nil
        end
    end
end

-- The pending prune, once the roster has been quiet for PruneDelay.
local function PruneWhenQuiet()
    local quiet = (GetTime() - RosterAt)

    if quiet < PruneDelay then
        PruneTimer = Krew:After(PruneDelay - quiet, PruneWhenQuiet)

        return
    end

    PruneTimer = nil
    Prune()
end

-- A roster update: the roster is pruned once updates stop for PruneDelay. One timer serves a burst; it waits out the
-- updates that came after it was set.
local function RosterChanged()
    RosterAt = GetTime()

    if not PruneTimer and (next(Members) ~= nil) then
        PruneTimer = Krew:After(PruneDelay, PruneWhenQuiet)
    end
end

local function SendHello(reply)
    Messages:Send("HELLO", { (Addon.Version or "?"), ((reply and "1") or "0") })
end

-- Says hello to this group, once; a group the messages can't reach yet (lockdown) waits for the next roster update.
local function SayHello()
    if not Said and Messages:Ready() then
        Said = true
        SendHello(false)
    end
end

-- Runs a pending prune now, so a reader of Members sees the group as it is.
local function Settle()
    if PruneTimer then
        Krew:Cancel(PruneTimer)
        PruneTimer = nil
        Prune()
    end
end

local function KrewNames()
    Settle()
    local names = {}

    for name in pairs(Members) do
        names[#names + 1] = name
    end

    sort(names)

    return names
end

-- "Bob Doe (0.2.0), Cara Doe": the Krew and the versions they run, for /tlk krew.
local function KrewList()
    local names = KrewNames()

    for i, name in ipairs(names) do
        local version = Members[name]

        names[i] = (((version ~= "") and ("%s (%s)"):format(name, version)) or name)
    end

    return concat(names, ", ")
end

-- Says once per group that a newer version is out, when NewerQuorum Krew members run one: the oldest of their versions,
-- and "or newer" when they don't all run it. Only a hello naming a newer version (heard) counts them, so other hellos
-- read no roster.
local function NoticeNewer(heard)
    local mine = CleanVersion(Addon.Version)

    if ToldNewer or (mine == "") or (heard == "") or (CompareVersions(heard, mine) <= 0) then
        return
    end

    Settle()
    local count, oldest, mixed = 0, nil, false

    for _, version in pairs(Members) do
        if (version ~= "") and (CompareVersions(version, mine) > 0) then
            count = (count + 1)
            mixed = (mixed or ((oldest ~= nil) and (version ~= oldest)))

            if not oldest or (CompareVersions(version, oldest) < 0) then
                oldest = version
            end
        end
    end

    if count >= NewerQuorum then
        ToldNewer = true

        Addon:Print(("A newer %s is out (%d Krew members run %s%s)."):format(addonName, count, oldest,
            (mixed and " or newer") or ""))
    end
end

local function ShowRollCall()
    RollCallTimer = nil
    local names = KrewNames()

    if #names > 0 then
        ShowCard({ body = (concat(names, ", ") .. (((#names == 1) and " is") or " are") .. " running the toolkit too."),
            icon = KrewIcon, sound = SOUNDKIT.READY_CHECK, title = "The Krew is here!" })
    end
end

local function Listen(module)
    module:Listen(Messages, "HELLO", function(sender, fields)
        local version, known = CleanVersion(fields[1]), (Members[sender] ~= nil)

        Members[sender] = version

        if not known and Krew:Get("hello") then
            Krew:Cancel(RollCallTimer)
            RollCallTimer = Krew:After(RollCallDelay, ShowRollCall)
        end

        NoticeNewer(version)

        if (fields[2] ~= "1") and not ReplyTimer then
            ReplyTimer = Krew:After(ReplyDelay, function()
                ReplyTimer = nil
                SendHello(true)
            end)
        end
    end)

    module:Listen(Messages, "DING", function(sender, fields)
        local level = CleanCount(fields[1], MaxLevel)

        if level then
            ShowCard({ body = "Cheer them on! The Krew levels up together.",
                icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight", sound = SOUNDKIT.LFG_REWARDS,
                title = (sender .. " hit level " .. level .. "!") })
        end
    end)

    module:Listen(Messages, "FLAWLESS", function(sender)
        ShowCard({ body = (sender .. " won a fight without taking a single hit."),
            icon = "Interface\\Icons\\Ability_Warrior_BattleShout", sound = SOUNDKIT.RAID_WARNING,
            title = "Flawless victory!" })
    end)

    module:Listen(Messages, "SCHOLAR", function(sender, fields)
        local stars = CleanCount(fields[1], MaxStars)

        if stars then
            ShowCard({ body = ("That's " .. stars .. (((stars == 1) and " star") or " stars") .. " of wisdom. Brilliant!"),
                icon = "Interface\\Icons\\INV_Misc_Book_09", sound = SOUNDKIT.IG_QUEST_LIST_COMPLETE,
                title = (sender .. " solved a riddle!") })
        end
    end)
end

Krew = Addon:Module("Krew", {
    commands = {
        { label = "Show who in your group runs the toolkit", name = "list",
            run = function()
                local list = KrewList()

                Addon:Print(((list ~= "") and ("The Krew: " .. list)) or "No Krew members in your group yet.")
            end,
            slash = "krew" },
    },
    comms = { prefix = Prefix },
    description = "Share fun moments with friends in your group who also run the toolkit. Group only, rare and rate-limited, and never during dungeon, raid or PvP lockdown.",
    label = "Krew messages",
    OnDisable = function()
        wipe(Members)
        Said, ToldNewer = false, false
        -- The module's timers stop with it.
        RollCallTimer, ReplyTimer, PruneTimer = nil, nil, nil
    end,
    OnEnable = function(module)
        Listen(module)
        module:On("GROUP_JOINED", SayHello)

        module:On("GROUP_ROSTER_UPDATE", function()
            if IsInGroup() then
                RosterChanged()
                SayHello()
            end
        end)

        module:On("GROUP_LEFT", function()
            wipe(Members)
            Said, ToldNewer = false, false
        end)

        module:On("PLAYER_LEVEL_UP", function(level)
            if module:Get("shareDings") then
                Messages:Send("DING", level)
            end
        end)

        -- The counters rise once per victory or star.
        module:OnIncrease("Victory.flawlessWins", function()
            if module:Get("shareFlawless") then
                Messages:Send("FLAWLESS")
            end
        end)

        module:OnIncrease("Scholar.stars", function(_, stars)
            if module:Get("shareScholar") then
                Messages:Send("SCHOLAR", stars)
            end
        end)

        if IsInGroup() then
            SayHello()
        end
    end,
    page = "Krew",
    state = {
        { default = true, description = "When you group up, a card shows which friends run the toolkit too.",
            kind = "boolean", label = "Show who's in the Krew", name = "hello" },
        { default = true, description = "Your Krew sees a card when you level up.", kind = "boolean",
            label = "Share my level-ups", name = "shareDings" },
        { default = true,
            description = "Your Krew sees a card when you win a flawless victory (needs the Flawless victory sound on).",
            kind = "boolean", label = "Share my flawless victories", name = "shareFlawless" },
        { default = true, description = "Your Krew sees a card when you solve a Scholar's challenge riddle.",
            kind = "boolean", label = "Share solved riddles", name = "shareScholar" },
    },
})

Messages = Krew.Comms
ns.Krew = Messages
ns.KrewFields = { CleanCount = CleanCount, CleanText = CleanText, MaxLevel = MaxLevel }
