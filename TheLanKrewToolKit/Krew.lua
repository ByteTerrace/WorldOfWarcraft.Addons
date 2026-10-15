local addonName, ns = ...

-- Krew: share fun moments with friends in your group who also run the toolkit.
--
--   Hello      when you group up (or /reload in a group), you say hello once: "HELLO:<version>\t0".
--              Each hello that isn't a reply gets one reply ("...\t1") within ReplyDelay, a burst
--              of them one between them, and a reply gets none, so two Krews never ping-pong. A
--              card shows who's here.
--   Ding       your level-ups appear as a card for the rest of the Krew.
--   Flawless   so do your flawless victories (Victory.flawlessWins, Kombat.lua).
--   Scholar    and the riddles a young scholar solves (Scholar.stars).
--
-- ns.Krew is the Krew module's Comms (ByteTerrace_Core's Comms.lua): every feature that talks to
-- the Krew (Warband's marks, sightings and rallies; Streaks' sprees) sends and listens through it,
-- so they all play by Blizzard's addon rules the same way: hidden messages to your own group only,
-- rare and rate-limited, never during chat messaging lockdown, parsed strictly, and never heard
-- or sent while the Krew module is off. Received messages only ever show a card or an alert,
-- update the ledger, or (a rally, with Warband.rallyWaypoint on) set a map waypoint; none acts on
-- your behalf.
--
-- ns.KrewFields cleans the fields of received messages for every feature that listens:
--   CleanText(text)         a zone, subzone or name to show, or "".
--   CleanCount(text, max)   a whole number from 1 to max written in digits, or nil.
--   MaxLevel                the highest level a message may carry.
-- Neither passes a "|" or a control character: someone else's message never puts a link,
-- texture or color on your screen.
--
-- Krew members are the group members whose hello you heard; one who leaves the group leaves the
-- Krew once the roster settles: a raid forming fires a burst of roster updates, and the roster is
-- read once, PruneDelay after the last of them. Showing or listing the Krew reads it first.

local Prefix = "TLKKrew1"
local ReplyDelay = 1 -- seconds that gather a burst of hellos into one reply
local RollCallDelay = 2
local PruneDelay = 1 -- seconds without a roster update that end a burst of them
local MaxText = 60     -- longest text accepted from a message
local MaxLevel = 200   -- the highest level accepted from a message
local MaxStars = 99999 -- the most stars accepted from a message
local KrewIcon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"
local PartyUnits, RaidUnits = {}, {}
for i = 1, 40 do
    PartyUnits[i], RaidUnits[i] = "party" .. i, "raid" .. i
end

local GetNumGroupMembers, GetTime, IsInGroup, IsInRaid = GetNumGroupMembers, GetTime, IsInGroup, IsInRaid
local SOUNDKIT = SOUNDKIT
local next, pairs, tonumber, type, wipe = next, pairs, tonumber, type, wipe
local concat, sort = table.concat, table.sort

local Addon = ns.Addon
local Names = ByteTerrace.Names
local ShowCard = ns.Cards.Show

local Members = {} -- [name] = true for group members running the toolkit
local Present = {} -- scratch: [name] = true for the group's members, while pruning Members
local RollCallTimer -- pending timer that merges a burst of hellos into one card
local ReplyTimer    -- pending timer that answers a burst of hellos with one reply
local PruneTimer    -- pending timer that prunes Members once a burst of roster updates settles
local RosterAt = 0  -- GetTime() of the last roster update
local Said = false  -- you said hello to this group
local Krew, Messages -- the module, and its Comms (ns.Krew)

--- A text field from a message (a zone, a subzone, a name), or "" when it's missing, longer than
--- MaxText, or holds a "|" or a control character.
---@param text string?
---@return string
local function CleanText(text)
    if type(text) ~= "string" or #text > MaxText or text:find("[|%c]") then
        return ""
    end
    return text
end

--- A count from a message: a whole number from 1 to max written in digits only (no sign,
--- exponent, hex or "inf"), or nil.
---@param text string?
---@param max integer
---@return integer?
local function CleanCount(text, max)
    if type(text) ~= "string" or #text > 9 or not text:find("^%d+$") then
        return nil
    end
    local count = tonumber(text)
    return (count >= 1 and count <= max) and count or nil
end

-- Drops Krew members who left the group. While any member's name is unreadable, nobody is dropped.
-- With no Krew members there's no one to drop, and no name to read.
local function Prune()
    if next(Members) == nil then
        return
    end
    wipe(Present)
    local raid, count = IsInRaid(), GetNumGroupMembers()
    local units = raid and RaidUnits or PartyUnits
    if not raid then
        count = count - 1 -- party tokens leave out the player
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
    local quiet = GetTime() - RosterAt
    if quiet < PruneDelay then
        PruneTimer = Krew:After(PruneDelay - quiet, PruneWhenQuiet)
        return
    end
    PruneTimer = nil
    Prune()
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

local function ShowRollCall()
    RollCallTimer = nil
    local names = KrewNames()
    if #names > 0 then
        ShowCard({ icon = KrewIcon, sound = SOUNDKIT.READY_CHECK, title = "The Krew is here!",
            body = concat(names, ", ") .. (#names == 1 and " is" or " are") .. " running the toolkit too." })
    end
end

local function SendHello(reply)
    Messages:Send("HELLO", { Addon.Version or "?", reply and "1" or "0" })
end

-- Says hello to this group, once; a group the messages can't reach yet (lockdown) waits for the
-- next roster update.
local function SayHello()
    if not Said and Messages:Ready() then
        Said = true
        SendHello(false)
    end
end

-- A roster update: the roster is pruned once updates stop for PruneDelay. One timer serves a
-- burst; it waits out the updates that came after it was set.
local function RosterChanged()
    RosterAt = GetTime()
    if not PruneTimer and next(Members) ~= nil then
        PruneTimer = Krew:After(PruneDelay, PruneWhenQuiet)
    end
end

local function Listen(module)
    module:Listen(Messages, "HELLO", function(sender, fields)
        if not Members[sender] then
            Members[sender] = true
            if Krew:Get("hello") then
                Krew:Cancel(RollCallTimer)
                RollCallTimer = Krew:After(RollCallDelay, ShowRollCall)
            end
        end
        if fields[2] ~= "1" and not ReplyTimer then
            ReplyTimer = Krew:After(ReplyDelay, function()
                ReplyTimer = nil
                SendHello(true)
            end)
        end
    end)

    module:Listen(Messages, "DING", function(sender, fields)
        local level = CleanCount(fields[1], MaxLevel)
        if level then
            ShowCard({ icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight", sound = SOUNDKIT.LFG_REWARDS,
                title = sender .. " hit level " .. level .. "!", body = "Cheer them on! The Krew levels up together." })
        end
    end)

    module:Listen(Messages, "FLAWLESS", function(sender)
        ShowCard({ icon = "Interface\\Icons\\Ability_Warrior_BattleShout", sound = SOUNDKIT.RAID_WARNING,
            title = "Flawless victory!", body = sender .. " won a fight without taking a single hit." })
    end)

    module:Listen(Messages, "SCHOLAR", function(sender, fields)
        local stars = CleanCount(fields[1], MaxStars)
        if stars then
            ShowCard({ icon = "Interface\\Icons\\INV_Misc_Book_09", sound = SOUNDKIT.IG_QUEST_LIST_COMPLETE,
                title = sender .. " solved a riddle!", body = "That's " .. stars .. (stars == 1 and " star" or " stars") .. " of wisdom. Brilliant!" })
        end
    end)
end

Krew = Addon:Module("Krew", {
    label = "Krew messages",
    page = "Krew",
    description = "Share fun moments with friends in your group who also run the toolkit. Group only, rare and rate-limited, and never during dungeon, raid or PvP lockdown.",
    comms = { prefix = Prefix },
    state = {
        { name = "hello", kind = "boolean", default = true, label = "Show who's in the Krew",
            description = "When you group up, a card shows which friends run the toolkit too." },
        { name = "shareDings", kind = "boolean", default = true, label = "Share my level-ups",
            description = "Your Krew sees a card when you level up." },
        { name = "shareFlawless", kind = "boolean", default = true, label = "Share my flawless victories",
            description = "Your Krew sees a card when you win a flawless victory (needs the Flawless victory sound on)." },
        { name = "shareScholar", kind = "boolean", default = true, label = "Share solved riddles",
            description = "Your Krew sees a card when you solve a Scholar's challenge riddle." },
    },
    commands = {
        { name = "list", slash = "krew", label = "Show who in your group runs the toolkit", run = function()
            local names = KrewNames()
            Addon:Print(#names > 0 and ("The Krew: " .. concat(names, ", ")) or "No Krew members in your group yet.")
        end },
    },
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
            Said = false
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
    OnDisable = function()
        wipe(Members)
        Said = false
        RollCallTimer, ReplyTimer, PruneTimer = nil, nil, nil -- the module's timers stop with it
    end,
})
Messages = Krew.Comms
ns.Krew = Messages
ns.KrewFields = { CleanText = CleanText, CleanCount = CleanCount, MaxLevel = MaxLevel }
