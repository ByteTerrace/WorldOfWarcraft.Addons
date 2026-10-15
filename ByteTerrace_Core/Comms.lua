-- Comms: hidden addon messages between players in your group who run the same addon. A module
-- declares them (comms = { prefix = "MyAddon1", interval?, queue? }) and uses module.Comms:
--
--   Send(kind, fields, urgent)  queues "KIND" or "KIND:field<tab>field..." for the group.
--   Ready()                     whether a message sent now would go out.
--   Listen(kind, fn)            fn(sender, fields) for each valid message of kind; sender is the
--                               sender's full name ("First Last", Names.lua) and fields an array
--                               of strings. Returns a handle for Unlisten; feature code uses
--                               module:Listen(comms, kind, fn) in OnEnable for automatic teardown.
--
-- Nothing is sent or received while the module is stopped: its handler and pending send go with
-- it, and the queue empties. CHAT_MSG_ADDON is registered only while you're in a group, since
-- nothing outside one can reach a listener: solo, other addons' messages cost nothing.
--
-- It plays by Blizzard's addon rules (no "excessive use of the chat system"), so every feature
-- that talks to the group gets them without having to know them:
--   * Your own group only (party, raid, instance chat), never whispers, public channels or
--     visible chat; received messages must arrive on a group channel too.
--   * At most one message per interval (default and least 1 second: the client regains one
--     message a second per prefix, so a faster transport only meets its throttle) from a small
--     bounded queue (default 8): beyond it messages are dropped, never retried forever. When the
--     client answers with a throttle, the message stays queued for the next turn.
--   * A number field goes as tostring writes it; one that wouldn't read back as itself is refused.
--   * Nothing during chat messaging lockdown (encounters, Mythic+, PvP matches). The queue is
--     dropped then, and when you leave your group: what it held would be stale later.
--   * A payload that arrives secret (lockdown) is ignored, as boss mods do; so are your own
--     messages, which the client echoes back.
--   * Messages are parsed strictly: an uppercase kind, then tab-separated fields. A message longer
--     than the client's limit is a caller bug and raises an error.

local MaxMessage = 255 -- bytes: the client's limit for one addon message
local MaxPrefix = 16   -- bytes: the client's limit for a prefix
local MinInterval = 1 -- seconds: the client regains one message a second per prefix
local Separator = "\t"
local GroupChannels = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
local ChatRestrictions = {
    [Enum.AddOnRestrictionType.Encounter] = true,
    [Enum.AddOnRestrictionType.ChallengeMode] = true,
    [Enum.AddOnRestrictionType.PvPMatch] = true,
    [Enum.AddOnRestrictionType.Map] = true,
    [Enum.AddOnRestrictionType.Chat] = true,
}

local ByteTerrace = ByteTerrace
local Report, SafeCall = ByteTerrace.Report, ByteTerrace.SafeCall
local Names = ByteTerrace.Names
local C_ChatInfo, Enum, GetTime = C_ChatInfo, Enum, GetTime
local IsInGroup, IsInRaid, LE_PARTY_CATEGORY_INSTANCE = IsInGroup, IsInRaid, LE_PARTY_CATEGORY_INSTANCE
local issecretvalue, pairs, tostring, type, wipe = issecretvalue, pairs, tostring, type, wipe
local concat, insert, remove = table.concat, table.insert, table.remove
local huge = math.huge

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
    if type(text) ~= "string" or #text > MaxMessage or text:find("[%z\r\n]") then
        return nil
    end
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

local function ValidKind(kind)
    return not issecretvalue(kind) and type(kind) == "string" and kind:find("^%u+$") ~= nil
end

-- Both scalar and array fields use this path before any concatenation or string conversion. A
-- number goes as tostring writes it (%.14g), so one that wouldn't read back as itself (a large
-- ID, 0.1 + 0.2) is refused: send it as a string.
local function EncodeField(value, addonName)
    if issecretvalue(value) then
        error(addonName .. ": message field cannot hold a secret value", 3)
    end
    local kind = type(value)
    if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then
        error(addonName .. ": message field must be a string, number or boolean", 3)
    end
    if kind == "number" and (value ~= value or value == huge or value == -huge) then
        error(addonName .. ": message field must be finite", 3)
    end
    local text = tostring(value)
    if kind == "number" and tonumber(text) ~= value then
        error(addonName .. ": message field number " .. text .. " doesn't survive as text; send it as a string", 3)
    end
    if text:find("[%z\t\r\n]") then
        error(addonName .. ": message field holds a NUL, tab or line break", 3)
    end
    return text
end

local function DropQueue(self)
    self.m_module:Cancel(self.m_timer)
    self.m_timer = nil
    wipe(self.m_queue)
end

-- Sends the queue's first message, or waits for the interval. The queue holds a message whenever
-- this runs: Send pumps after queueing, and emptying the queue cancels the pending pump.
local function Pump(self)
    self.m_timer = nil
    local channel = Channel()
    if not channel or C_ChatInfo.InChatMessagingLockdown() then
        DropQueue(self)
        return
    end
    local wait = self.m_lastSent + self.m_interval - GetTime()
    if wait > 0 then
        self.m_timer = self.m_module:After(wait, self.m_pump)
        return
    end
    local result = C_ChatInfo.SendAddonMessage(self.m_prefix, self.m_queue[1], channel)
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
    if type(prefix) ~= "string" or #prefix < 1 or #prefix > MaxPrefix or prefix:find("[%z\t\r\n]") then
        problems[#problems + 1] = ("prefix must be a string of 1 to %d bytes"):format(MaxPrefix)
    end
    if type(interval) ~= "number" or interval ~= interval or interval < MinInterval or interval == huge then
        problems[#problems + 1] = ("interval must be at least %d second: the client regains one message a second"):format(MinInterval)
    end
    if type(queue) ~= "number" or queue < 1 or queue % 1 ~= 0 then
        problems[#problems + 1] = "queue must be a positive whole number"
    end
    ByteTerrace.Refuse(addon.Name .. " comms for " .. module.Name, problems)
    local self = setmetatable({
        m_module = module, m_prefix = prefix, m_interval = interval, m_limit = queue,
        m_queue = {}, m_listeners = {}, m_lastSent = -interval, m_open = false, m_session = 0,
    }, Comms)
    self.m_pump = function() Pump(self) end
    return self
end

--- Starts receiving: registers the prefix, and the module's CHAT_MSG_ADDON handler while you're
--- in a group. The module calls it as it starts.
function Comms:Open()
    -- Registered once per UI session: after a restart of the module it's a duplicate, which is fine.
    local result, results = C_ChatInfo.RegisterAddonMessagePrefix(self.m_prefix), Enum.RegisterAddonMessagePrefixResult
    if result ~= results.Success and result ~= results.DuplicatePrefix then
        local reason = result == results.MaxPrefixes and "MaxPrefixes" or "InvalidPrefix"
        Report(("%s: message prefix %s can't be registered: %s"):format(self.m_module.Addon.Name, self.m_prefix, reason))
    end
    local me = Names.Mine() -- nil while secret; looked up again then
    local module, prefix, listeners = self.m_module, self.m_prefix, self.m_listeners
    self.m_open = true
    self.m_session = self.m_session + 1
    local session = self.m_session
    local function Receive(received, text, channel, sender)
        -- Every addon's messages arrive here; the prefix test comes first, so theirs cost one check.
        if issecretvalue(received) or received ~= prefix then
            return
        end
        if issecretvalue(text) or issecretvalue(channel) or issecretvalue(sender) or not GroupChannels[channel] then
            return
        end
        if not self:Ready() or type(sender) ~= "string" or sender == "" or sender:find("[|%c]") then
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
                if not self.m_open or self.m_session ~= session then
                    break
                end
                local handle = list[i]
                if not handle.dead then
                    SafeCall(handle.fn, name, fields)
                end
            end
        end
    end
    local hearing -- the CHAT_MSG_ADDON handle, while you're in a group
    local function FollowGroup()
        if Channel() then
            hearing = hearing or module:On("CHAT_MSG_ADDON", Receive)
        elseif hearing then
            module:Off(hearing)
            hearing = nil
        end
    end
    module:On("GROUP_JOINED", FollowGroup)
    module:On("GROUP_ROSTER_UPDATE", FollowGroup)
    module:On("GROUP_LEFT", function()
        DropQueue(self)
        FollowGroup()
    end)
    FollowGroup()
    module:On("ADDON_RESTRICTION_STATE_CHANGED", function(restriction, state)
        -- Activating arrives before InChatMessagingLockdown reflects the restriction.
        if ChatRestrictions[restriction] and state ~= Enum.AddOnRestrictionState.Inactive then
            DropQueue(self)
        end
    end)
end

--- Stops sending: the queue empties. The module calls it as it stops, which also removes the
--- handler and the pending send.
function Comms:Close()
    self.m_open = false
    DropQueue(self)
end

--- Queues a message for the group. Dropped while the module is stopped, when you're not in a
--- group, during chat lockdown, or when the queue is full.
---@param kind string uppercase letters only
---@param fields any? a plain string, finite number, boolean, or a dense array of these
---@param urgent boolean? goes to the front of the queue
function Comms:Send(kind, fields, urgent)
    local addonName = self.m_module.Addon.Name
    if not ValidKind(kind) then
        error(addonName .. ": message kind must be plain uppercase letters", 2)
    end
    local text = kind
    if issecretvalue(fields) then
        error(addonName .. ": message field cannot hold a secret value", 2)
    end
    if type(fields) == "table" then
        local encoded, count = {}, 0
        for key in pairs(fields) do
            if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > #fields then
                error(addonName .. ": message fields must be a dense array", 2)
            end
            count = count + 1
        end
        if count ~= #fields then
            error(addonName .. ": message fields must be a dense array", 2)
        end
        for i = 1, #fields do
            encoded[i] = EncodeField(fields[i], addonName)
        end
        if count > 0 then
            text = kind .. ":" .. concat(encoded, Separator)
        end
    elseif fields ~= nil then
        text = kind .. ":" .. EncodeField(fields, addonName)
    end
    if #text > MaxMessage then
        error(("%s: message %s is longer than %d bytes"):format(addonName, kind, MaxMessage), 2)
    end
    if not self:Ready() then
        DropQueue(self)
        return
    end
    if #self.m_queue >= self.m_limit then
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
--- is isolated: an error in one doesn't stop the others. Feature modules use Module:Listen to
--- own the subscription. New listeners begin with the next delivery.
---@param kind string
---@param fn fun(sender: string, fields: string[])
---@return table handle for Unlisten
function Comms:Listen(kind, fn)
    if not ValidKind(kind) or type(fn) ~= "function" then
        error("Listen needs an uppercase message kind and a function", 2)
    end
    local list = self.m_listeners[kind]
    local copy = {}
    for i = 1, #(list or {}) do
        copy[i] = list[i]
    end
    local handle = { kind = kind, fn = fn }
    copy[#copy + 1] = handle
    self.m_listeners[kind] = copy
    return handle
end

--- Removes a listener immediately, including from a delivery already in progress. Removing one
--- twice finds nothing to remove the second time.
---@param handle table from Listen
function Comms:Unlisten(handle)
    handle.dead = true
    local list, copy = self.m_listeners[handle.kind], {}
    for i = 1, #(list or {}) do
        if not list[i].dead then
            copy[#copy + 1] = list[i]
        end
    end
    self.m_listeners[handle.kind] = #copy > 0 and copy or nil
end

--- How many messages wait to be sent.
---@return integer
function Comms:Queued()
    return #self.m_queue
end
