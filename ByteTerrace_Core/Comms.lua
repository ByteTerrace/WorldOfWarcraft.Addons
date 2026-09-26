-- Comms: hidden addon messages between players in your group who run the same addon. A module
-- declares them (comms = { prefix = "MyAddon1", interval?, queue? }) and uses module.Comms:
--
--   Send(kind, fields, urgent)  queues "KIND" or "KIND:field<tab>field..." for the group.
--   Ready()                     whether a message sent now would go out.
--   Listen(kind, fn)            fn(sender, fields) for each valid message of kind; sender is the
--                               sender's full name ("First Last", Names.lua) and fields an array
--                               of strings. Listen any time, from any file.
--
-- Nothing is sent or received while the module is stopped: its handler and pending send go with
-- it, and the queue empties.
--
-- It plays by Blizzard's addon rules (no "excessive use of the chat system"), so every feature
-- that talks to the group gets them without having to know them:
--   * Your own group only (party, raid, instance chat), never whispers, public channels or
--     visible chat; received messages must arrive on a group channel too.
--   * At most one message per interval (default 1 second) from a small bounded queue (default 8):
--     beyond it messages are dropped, never retried forever. When the client answers with a
--     throttle, the message stays queued for the next turn.
--   * Nothing during chat messaging lockdown (encounters, Mythic+, PvP matches). The queue is
--     dropped then, and when you leave your group: what it held would be stale later.
--   * A payload that arrives secret (lockdown) is ignored, as boss mods do; so are your own
--     messages, which the client echoes back.
--   * Messages are parsed strictly: an uppercase kind, then tab-separated fields. A message longer
--     than the client's limit is a caller bug and raises an error.

local MaxMessage = 255 -- bytes: the client's limit for one addon message
local MaxPrefix = 16   -- bytes: the client's limit for a prefix
local Separator = "\t"
local GroupChannels = { PARTY = true, RAID = true, INSTANCE_CHAT = true }

local ByteTerrace = ByteTerrace
local SafeCall = ByteTerrace.SafeCall
local Names = ByteTerrace.Names
local C_ChatInfo, Enum, GetTime = C_ChatInfo, Enum, GetTime
local IsInGroup, IsInRaid, LE_PARTY_CATEGORY_INSTANCE = IsInGroup, IsInRaid, LE_PARTY_CATEGORY_INSTANCE
local issecretvalue, tostring, type, wipe = issecretvalue, tostring, type, wipe
local concat, insert, remove = table.concat, table.insert, table.remove

local Comms = {}
Comms.__index = Comms
ByteTerrace.Comms = Comms

--- The longest message Send accepts, "KIND:" and separators included: the client's limit.
Comms.MaxMessage = MaxMessage

-- The group channel messages go to, or nil when you're not in a group.
local function Channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
    return nil
end

-- Parses "KIND" (no fields) or "KIND:field<tab>field...". Anything else is nil.
local function Parse(text)
    local kind, rest = text:match("^(%u+):(.*)$")
    local fields = {}
    if not kind then
        kind = text:match("^(%u+)$")
        return kind, kind and fields
    end
    for field in (rest .. Separator):gmatch("([^\t]*)\t") do
        fields[#fields + 1] = field
    end
    return kind, fields
end

local function Pump(self)
    self.m_timer = nil
    local message = self.m_queue[1]
    if not message then
        return
    end
    local channel = Channel()
    if not channel or C_ChatInfo.InChatMessagingLockdown() then
        wipe(self.m_queue)
        return
    end
    local wait = self.m_lastSent + self.m_interval - GetTime()
    if wait > 0 then
        self.m_timer = self.m_module:After(wait, self.m_pump)
        return
    end
    local result = C_ChatInfo.SendAddonMessage(self.m_prefix, message, channel)
    self.m_lastSent = GetTime()
    local results = Enum.SendAddonMessageResult
    if result ~= results.AddonMessageThrottle and result ~= results.ChannelThrottle then
        remove(self.m_queue, 1)
    end
    if self.m_queue[1] then
        self.m_timer = self.m_module:After(self.m_interval, self.m_pump)
    end
end

--- Validates a module's comms spec and creates its messages. AddOn:Module calls it.
---@param module table the owning module
---@param spec table { prefix, interval?, queue? }
function ByteTerrace.NewComms(module, spec)
    local addon, problems = module.Addon, {}
    local prefix, interval, queue = spec.prefix, spec.interval or 1, spec.queue or 8
    if type(prefix) ~= "string" or #prefix < 1 or #prefix > MaxPrefix then
        problems[#problems + 1] = ("prefix must be a string of 1 to %d bytes"):format(MaxPrefix)
    end
    if type(interval) ~= "number" or interval <= 0 then
        problems[#problems + 1] = "interval must be a positive number of seconds"
    end
    if type(queue) ~= "number" or queue < 1 or queue % 1 ~= 0 then
        problems[#problems + 1] = "queue must be a positive whole number"
    end
    ByteTerrace.Refuse(addon.Name .. " comms for " .. module.Name, problems)
    local self = setmetatable({
        m_module = module, m_prefix = prefix, m_interval = interval, m_limit = queue,
        m_queue = {}, m_listeners = {}, m_lastSent = -interval, m_open = false,
    }, Comms)
    self.m_pump = function() Pump(self) end
    return self
end

--- Starts receiving: registers the prefix and the module's CHAT_MSG_ADDON handler. The module
--- calls it as it starts.
function Comms:Open()
    C_ChatInfo.RegisterAddonMessagePrefix(self.m_prefix)
    local me = Names.Mine() -- nil while secret; looked up again then
    local prefix, listeners = self.m_prefix, self.m_listeners
    self.m_open = true
    self.m_module:On("CHAT_MSG_ADDON", function(received, text, channel, sender)
        -- Every addon's messages arrive here; the prefix test comes first, so theirs cost one check.
        if issecretvalue(received) or received ~= prefix then
            return
        end
        if issecretvalue(text) or issecretvalue(channel) or issecretvalue(sender) or not GroupChannels[channel] then
            return
        end
        local name = Names.Plain(sender)
        me = me or Names.Mine()
        if name == me then
            return
        end
        local kind, fields = Parse(text)
        local list = kind and listeners[kind]
        if list then
            for i = 1, #list do
                SafeCall(list[i], name, fields)
            end
        end
    end)
    self.m_module:On("GROUP_LEFT", function()
        wipe(self.m_queue)
    end)
end

--- Stops sending: the queue empties. The module calls it as it stops, which also removes the
--- handler and the pending send.
function Comms:Close()
    self.m_open = false
    self.m_timer = nil
    wipe(self.m_queue)
end

--- Queues a message for the group. Dropped while the module is stopped, when you're not in a
--- group, or when the queue is full.
---@param kind string uppercase letters only
---@param fields any? a value or an array of values, joined with tabs
---@param urgent boolean? goes to the front of the queue
function Comms:Send(kind, fields, urgent)
    local addonName = self.m_module.Addon.Name
    if type(kind) ~= "string" or not kind:find("^%u+$") then
        error(("%s: message kind %s must be uppercase letters"):format(addonName, tostring(kind)), 2)
    end
    local text = kind
    if type(fields) == "table" then
        text = kind .. ":" .. concat(fields, Separator)
        for i = 1, #fields do
            if tostring(fields[i]):find("[\t\r\n]") then
                error(("%s: message %s field %d holds a tab or line break"):format(addonName, kind, i), 2)
            end
        end
    elseif fields ~= nil then
        text = kind .. ":" .. tostring(fields)
    end
    if #text > MaxMessage then
        error(("%s: message %s is longer than %d bytes"):format(addonName, kind, MaxMessage), 2)
    end
    if not self.m_open or not Channel() or #self.m_queue >= self.m_limit then
        return
    end
    if urgent then
        insert(self.m_queue, 1, text)
    else
        self.m_queue[#self.m_queue + 1] = text
    end
    if not self.m_timer then
        Pump(self)
    end
end

--- Whether a message sent now would go out: the module runs, you're in a group, and chat
--- messaging isn't locked down.
---@return boolean
function Comms:Ready()
    return self.m_open and Channel() ~= nil and not C_ChatInfo.InChatMessagingLockdown()
end

--- Calls fn(sender, fields) for each valid message of kind while the module runs. Each listener
--- is isolated: an error in one doesn't stop the others.
---@param kind string
---@param fn fun(sender: string, fields: string[])
function Comms:Listen(kind, fn)
    local list = self.m_listeners[kind]
    if not list then
        list = {}
        self.m_listeners[kind] = list
    end
    list[#list + 1] = fn
end

--- How many messages wait to be sent.
---@return integer
function Comms:Queued()
    return #self.m_queue
end
