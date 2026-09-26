local addonName, ns = ...

-- Krew: share fun moments with friends in your group who also run the toolkit.
--
--   Hello      when you group up, Krew members greet each other; a card shows who's here.
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
-- Neither passes a "|" or a control character: someone else's message never puts a link,
-- texture or color on your screen.
--
-- Krew members are the group members whose hello you heard; one who leaves the group leaves the
-- Krew on the next roster update.

local Prefix = "TLKKrew1"
local HelloCooldown = 30
local RollCallDelay = 2
local MaxText = 60     -- longest text accepted from a message
local MaxLevel = 200   -- the highest level accepted from a message
local MaxStars = 99999 -- the most stars accepted from a message
local KrewIcon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"
local PartyUnits, RaidUnits = {}, {}
for i = 1, 40 do
    PartyUnits[i], RaidUnits[i] = "party" .. i, "raid" .. i
end

local GetNumGroupMembers, GetTime, IsInGroup, IsInRaid, SOUNDKIT = GetNumGroupMembers, GetTime, IsInGroup, IsInRaid, SOUNDKIT
local pairs, tonumber, type, wipe = pairs, tonumber, type, wipe
local concat, sort = table.concat, table.sort

local Addon = ns.Addon
local Names = ByteTerrace.Names
local ShowCard = ns.Cards.Show

local Members = {} -- [name] = true for group members running the toolkit
local Present = {} -- scratch: [name] = true for the group's members, while pruning Members
local RollCallTimer -- pending timer that merges a burst of hellos into one card
local LastHello = -HelloCooldown
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

local function KrewNames()
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

local function SendHello()
    LastHello = GetTime()
    Messages:Send("HELLO", Addon.Version or "?")
end

local function SayHello()
    if GetTime() - LastHello >= HelloCooldown then
        SendHello()
    end
end

-- Drops Krew members who left the group. While any member's name is unreadable, nobody is dropped.
local function Prune()
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

local function Listen(module)
    module:Listen(Messages, "HELLO", function(sender)
        if Members[sender] then
            return
        end
        Members[sender] = true
        if Krew:Get("hello") then
            Krew:Cancel(RollCallTimer)
            RollCallTimer = Krew:After(RollCallDelay, ShowRollCall)
        end
        SendHello() -- new senders learn about us; Members prevents ping-pong
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
                Prune()
                SayHello()
            end
        end)
        module:On("GROUP_LEFT", function()
            wipe(Members)
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
        RollCallTimer = nil -- the module's timers stop with it
    end,
})
Messages = Krew.Comms
ns.Krew = Messages
ns.KrewFields = { CleanText = CleanText, CleanCount = CleanCount }
