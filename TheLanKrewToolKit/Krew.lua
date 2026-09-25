local addonName, ns = ...

-- Krew: share fun moments with friends in your group who also run the toolkit.
--
--   Hello      when you group up, Krew members greet each other; a card shows who's here.
--   Ding       your level-ups appear as a card for the rest of the Krew.
--   Flawless   so do your flawless victories (Victory.flawlessWins, Kombat.lua).
--   Scholar    and the riddles a young scholar solves (Scholar.stars).
--
-- Other features talk to the Krew through ns.Krew (Warband's marks, sightings and rallies; Streaks' sprees):
--   ns.Krew.Send(kind, fields, urgent)  queues a message for the group.
--   ns.Krew.Ready()                     whether a message sent now would go out.
--   ns.Krew.Listen(kind, fn)            fn(sender, fields, module) for each valid message of kind.
-- Nothing is sent or received while the Krew module is off.
--
-- Playing by Blizzard's add-on rules (no "excessive use of the chat system"):
--   * Hidden addon messages to your own group only (party, raid, instance). Never whispers,
--     public channels, or visible chat.
--   * Sent only on rare events, never on a timer; at most one message per SendInterval, with a
--     small bounded queue (anything beyond it is dropped, not retried forever).
--   * Never during chat messaging lockdown (encounters, Mythic+, PvP matches, dungeons and raids).
--     A celebration that can't be sent then is dropped: it would be stale later.
--   * Received messages only ever show a card. They're parsed strictly, must come from your group,
--     and never trigger any action. One that arrives secret (chat lockdown) is ignored.

local Prefix = "TLKKrew1"
local MaxMessage = 255 -- bytes: the client's limit for one addon message
local Separator = "\t"
local SendInterval = 1
local MaxQueue = 8
local HelloCooldown = 30
local RollCallDelay = 2
local KrewIcon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"
local GroupChannels = { PARTY = true, RAID = true, INSTANCE_CHAT = true }

local Ambiguate, C_ChatInfo, C_Timer, GetTime = Ambiguate, C_ChatInfo, C_Timer, GetTime
local IsInGroup, IsInRaid, SOUNDKIT, UnitName = IsInGroup, IsInRaid, SOUNDKIT, UnitName
local issecretvalue, tonumber, tostring, type = issecretvalue, tonumber, tostring, type
local concat, insert, sort = table.concat, table.insert, table.sort
local SafeCall = ByteTerrace.SafeCall

local Addon = ns.Addon
local ShowCard = ns.Cards.Show

local Enabled = false
local Queue = {} -- outbound message texts; [1] goes next
local PumpTimer -- pending timer for the next send
local LastSent = -SendInterval
local Members = {} -- [name] = true for group members running the toolkit
local RollCallTimer -- pending timer that merges a burst of hellos into one card
local LastHello = -HelloCooldown
local Listeners = {} -- [kind] = array of fn(sender, fields, module)

local function MyName()
    local name = UnitName("player")
    if issecretvalue(name) then
        return nil
    end
    return name
end

local function Channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
end

local function Pump()
    PumpTimer = nil
    local message = Queue[1]
    if not message then
        return
    end
    local channel = Channel()
    if not channel or C_ChatInfo.InChatMessagingLockdown() then
        wipe(Queue) -- nobody to tell, or not allowed now: celebrations don't keep
        return
    end
    local wait = LastSent + SendInterval - GetTime()
    if wait > 0 then
        PumpTimer = C_Timer.NewTimer(wait, Pump)
        return
    end
    local result = C_ChatInfo.SendAddonMessage(Prefix, message, channel)
    LastSent = GetTime()
    if result == Enum.SendAddonMessageResult.AddonMessageThrottle
        or result == Enum.SendAddonMessageResult.ChannelThrottle then
        PumpTimer = C_Timer.NewTimer(SendInterval, Pump) -- the client asked us to slow down: keep it queued
        return
    end
    table.remove(Queue, 1)
    if Queue[1] then
        PumpTimer = C_Timer.NewTimer(SendInterval, Pump)
    end
end

--- Queues "KIND" or "KIND:field<tab>field..." for the group. Dropped when the Krew is off, there's
--- no group or the queue is full. A message longer than MaxMessage is a caller bug and raises an
--- error.
---@param kind string uppercase letters only
---@param fields any? a value or an array of values, joined with tabs
---@param urgent boolean? goes to the front of the queue
local function Send(kind, fields, urgent)
    if not Enabled or not Channel() or #Queue >= MaxQueue then
        return
    end
    local text = kind
    if type(fields) == "table" then
        text = kind .. ":" .. concat(fields, Separator)
    elseif fields ~= nil then
        text = kind .. ":" .. tostring(fields)
    end
    if #text > MaxMessage then
        error(addonName .. ": Krew message " .. kind .. " is longer than " .. MaxMessage .. " bytes", 2)
    end
    if urgent then
        insert(Queue, 1, text)
    else
        Queue[#Queue + 1] = text
    end
    if not PumpTimer then
        Pump()
    end
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

local function SayHello()
    local now = GetTime()
    if now - LastHello >= HelloCooldown then
        LastHello = now
        Send("HELLO", Addon.Version or "?")
    end
end

-- Parses "KIND" or "KIND:field<tab>field...". Anything else is ignored.
local function Parse(text)
    local kind, rest = text:match("^(%u+):?(.*)$")
    if not kind then
        return nil
    end
    local fields = {}
    for field in (rest .. Separator):gmatch("([^\t]*)\t") do
        fields[#fields + 1] = field
    end
    return kind, fields
end

--- Calls fn for each valid message of kind from the group while the Krew module runs. Each
--- listener is isolated: an error in one doesn't stop the others.
---@param kind string
---@param fn function fn(sender, fields, module): sender is the short name, fields an array of strings
local function Listen(kind, fn)
    local list = Listeners[kind]
    if not list then
        list = {}
        Listeners[kind] = list
    end
    list[#list + 1] = fn
end

--- Whether a message sent now would go out: the Krew is on, you're in a group, and chat messaging
--- isn't locked down.
---@return boolean
local function Ready()
    return Enabled and Channel() ~= nil and not C_ChatInfo.InChatMessagingLockdown()
end

local Handlers = {
    HELLO = function(sender, _, module)
        if not Members[sender] then
            Members[sender] = true
            if module:Get("hello") then
                if RollCallTimer then
                    RollCallTimer:Cancel()
                end
                RollCallTimer = C_Timer.NewTimer(RollCallDelay, ShowRollCall)
            end
            SayHello() -- so they learn about us too (the cooldown stops ping-pong)
        end
    end,
    DING = function(sender, fields)
        local level = tonumber(fields[1])
        if level and level >= 1 and level <= 200 and level == math.floor(level) then
            ShowCard({ icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight", sound = SOUNDKIT.LFG_REWARDS,
                title = sender .. " hit level " .. level .. "!", body = "Cheer them on! The Krew levels up together." })
        end
    end,
    FLAWLESS = function(sender)
        ShowCard({ icon = "Interface\\Icons\\Ability_Warrior_BattleShout", sound = SOUNDKIT.RAID_WARNING,
            title = "Flawless victory!", body = sender .. " won a fight without taking a single hit." })
    end,
    SCHOLAR = function(sender, fields)
        local stars = tonumber(fields[1])
        if stars and stars >= 1 and stars == math.floor(stars) then
            ShowCard({ icon = "Interface\\Icons\\INV_Misc_Book_09", sound = SOUNDKIT.IG_QUEST_LIST_COMPLETE,
                title = sender .. " solved a riddle!", body = "That's " .. stars .. (stars == 1 and " star" or " stars") .. " of wisdom. Brilliant!" })
        end
    end,
}
for kind, fn in pairs(Handlers) do
    Listen(kind, fn)
end

ns.Krew = { Send = Send, Listen = Listen, Ready = Ready }

Addon:Module("Krew", {
    label = "Krew messages",
    page = "Krew",
    description = "Share fun moments with friends in your group who also run the toolkit. Group only, rare and rate-limited, and never during dungeon, raid or PvP lockdown.",
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
        C_ChatInfo.RegisterAddonMessagePrefix(Prefix)
        local me = MyName()
        Enabled = true

        module:On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
            if issecretvalue(prefix) or issecretvalue(text) or issecretvalue(channel) or issecretvalue(sender) then
                return -- chat reaches addons as secrets during lockdown; boss mods drop those too
            end
            if prefix ~= Prefix or not GroupChannels[channel] then
                return
            end
            local name = Ambiguate(sender, "none")
            if name == me then
                return -- our own message, echoed back by the client
            end
            local kind, fields = Parse(text)
            local list = kind and Listeners[kind]
            if list then
                for i = 1, #list do
                    SafeCall(list[i], name, fields, module)
                end
            end
        end)
        module:On("GROUP_JOINED", SayHello)
        module:On("GROUP_ROSTER_UPDATE", function()
            if IsInGroup() then
                SayHello()
            end
        end)
        module:On("GROUP_LEFT", function()
            wipe(Members)
            wipe(Queue)
        end)
        module:On("PLAYER_LEVEL_UP", function(level)
            if module:Get("shareDings") then
                Send("DING", level)
            end
        end)
        -- Counters only ever share when they go up (a stopped module resets its counter to 0).
        local victories, stars = module:Get("Victory.flawlessWins"), module:Get("Scholar.stars")
        module:Watch({ "Victory.flawlessWins" }, function(state)
            local now = state:Get("Victory.flawlessWins")
            if now > victories and module:Get("shareFlawless") then
                Send("FLAWLESS")
            end
            victories = now
        end, true)
        module:Watch({ "Scholar.stars" }, function(state)
            local now = state:Get("Scholar.stars")
            if now > stars and module:Get("shareScholar") then
                Send("SCHOLAR", now)
            end
            stars = now
        end, true)
        if IsInGroup() then
            SayHello()
        end
    end,
    OnDisable = function()
        Enabled = false
        wipe(Members)
        wipe(Queue)
        if PumpTimer then
            PumpTimer:Cancel()
            PumpTimer = nil
        end
        if RollCallTimer then
            RollCallTimer:Cancel()
            RollCallTimer = nil
        end
    end,
})
