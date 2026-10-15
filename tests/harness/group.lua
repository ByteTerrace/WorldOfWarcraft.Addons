-- Groups and addon messages of the fake client (see wow.lua for the rest).
--
-- Group model: h.group = { kind = nil | "party" | "raid" | "instance", guid, members = { unit, ... } }. Each member is
-- a harness unit table (name, surname, realm, unit, plus FillUnit's defaults and classFile = "WARRIOR" unless given): a
-- player-controlled group member, so identity APIs don't make it secret. Tokens follow the client's rules:
--   * a party (or an instance group of up to 4 others) gives party1-4 in member order;
--   * a raid (or a larger instance group) gives raid1..raidN in member order and the player the
--     next raid index; subgroups fill five at a time in raid order, and party1-4 are the other
--     members of the player's subgroup (member.partyUnit).
-- A party holds at most 4 others and a raid 39. A token set with h:SetUnit wins over the group's.
-- LE_PARTY_CATEGORY_HOME (1) covers party and raid, LE_PARTY_CATEGORY_INSTANCE (2) the instance group; the harness
-- models one group at a time. Removing the last member disbands the group (GROUP_LEFT), like the client. partyGUID is a
-- deterministic stand-in ("Party-0-<hex>"). Joining or leaving fires RAID_TARGET_UPDATE after GROUP_ROSTER_UPDATE (its
-- event page says it fires when the player joins or leaves a party or raid).
--
-- Addon messages (C_ChatInfo), from ChatInfoDocumentation and the community's API pages:
--   * RegisterAddonMessagePrefix returns Enum.RegisterAddonMessagePrefixResult: InvalidPrefix
--     for an empty or longer than 16 character prefix, DuplicatePrefix, MaxPrefixes past 512.
--     Registration is client-wide and lasts for the UI session (a reload or relog clears it).
--   * SendAddonMessage(prefix, message [, chatType = "PARTY"] [, target]) checks, in order:
--       InvalidPrefix        empty, not a string, or longer than 16 characters. Sending doesn't
--                            need a registered prefix (only receiving does), like the client.
--       InvalidMessage       longer than 255 bytes, or holds a NUL byte
--       InvalidChatType      not PARTY, RAID, INSTANCE_CHAT, GUILD, OFFICER or WHISPER. CHANNEL,
--                            SAY and YELL aren't modeled: calling with them is a harness error.
--       AddOnMessageLockdown C_ChatInfo.InChatMessagingLockdown() (the SecretInChatMessagingLockdown
--                            restrictions: Encounter, ChallengeMode, PvPMatch, Map, Chat)
--       NotInGroup           PARTY outside a home group, RAID outside a home raid, INSTANCE_CHAT
--                            outside an instance group
--       NotInGuild           GUILD or OFFICER while the player has no guild (h.player.guild)
--       TargetRequired       WHISPER without a target
--       AddonMessageThrottle the prefix's allowance is spent. Model: each prefix holds up to 10
--                            messages and regains 1 per second of h.time (the documented
--                            defaults since the per-prefix throttle covers every chat type; the
--                            server can change them). Only a successful send spends allowance.
--     Every call is recorded in h.addonMessages = { { prefix, message, chatType, target, result } }
--     (chatType resolved, so nil records "PARTY").
--   * h:AnswerAddonMessages(answer, count) fails the next count sends that pass every check above
--     (default 1). answer is the SendAddonMessageResult name the client hands back instead of
--     Success: GeneralError (the documented catch-all), or AddOnMessageLockdown (lockdown taking
--     hold between the caller's check and the send). "raise" makes the call raise a Lua error
--     instead, as the client does for an argument it can't take; a raising call isn't recorded.
--     A failed send spends no allowance and isn't echoed.
--   * Echo: the client delivers your own PARTY, RAID, INSTANCE_CHAT, GUILD and OFFICER messages
--     (and a whisper to yourself) back to you through CHAT_MSG_ADDON, with your own name as the
--     sender, so an addon must ignore its own messages. The harness echoes by default
--     (h:Echo(false) turns it off) and delivers the echo on the next h:Advance, like a server
--     round trip, never inside the SendAddonMessage call.
--   * h:ReceiveAddonMessage fires CHAT_MSG_ADDON only for a registered prefix, like the client:
--     prefix, text, channel, sender (Harness:FullName: "First Last", "-Realm" only for another realm), target
--     (for WHISPER the sender, per the event's documentation; otherwise ""), zoneChannelID 0,
--     localID 0, name "", instanceID 0.

-- LE_PARTY_CATEGORY_HOME / _INSTANCE
Harness.PARTY_CATEGORY = { HOME = 1, INSTANCE = 2 }
Harness.MAX_PREFIX_LENGTH, Harness.MAX_ADDON_MESSAGE_BYTES, Harness.MAX_PREFIXES = 16, 255, 512
Harness.ADDON_THROTTLE = { allowance = 10, perSecond = 1 }

local ChatTypes = { GUILD = true, INSTANCE_CHAT = true, OFFICER = true, PARTY = true, RAID = true, WHISPER = true }
local Echoed = { GUILD = true, INSTANCE_CHAT = true, OFFICER = true, PARTY = true, RAID = true }
local GroupKinds = { instance = true, party = true, raid = true }
local UnmodeledChatTypes = { CHANNEL = true, SAY = true, YELL = true }

local function CheckSize(_, kind, count)
    local limit = (((kind == "party") and 4) or 39)

    assert(count <= limit, ("a %s holds at most %d members besides the player, got %d"):format(kind, limit, count))
end

-- Whether the client hands this send back to the sender.
local function Echoes(h, chatType, target)
    if Echoed[chatType] then
        return true
    end

    return ((chatType == "WHISPER") and ((h:FullName(target) == h:FullName(h.player)) or (h:FullName(target) == h.player.name)))
end

local function Member(h, spec)
    local unit = (((type(spec) == "table") and spec) or {})

    if type(spec) == "string" then
        local name, realm = spec:match("^([^%-]+)%-(.+)$")
        local first, surname = (name or spec):match("^(%S+) (.+)$")

        unit.name, unit.surname, unit.realm = (first or name or spec), surname, realm
    end

    assert((type(unit.name) == "string") and (unit.name ~= ""), "a group member needs a name")
    unit.realm = (unit.realm or h.player.realm)
    unit.isPlayer, unit.playerControlled, unit.inGroup = true, true, true
    unit.classFile = (unit.classFile or "WARRIOR")

    return Harness.FillUnit(unit)
end

-- Assigns every member's tokens (see the header).
local function Retoken(h)
    local g = h.group

    g.playerUnit = nil

    if not h:GroupIsRaid() then
        for i, member in ipairs(g.members) do
            member.unit, member.partyUnit, member.subgroup = ("party" .. i), nil, nil
        end

        return
    end

    local playerIndex = (#g.members + 1)

    g.playerUnit = ("raid" .. playerIndex)
    local playerSubgroup, partyIndex = math.ceil(playerIndex / 5), 0

    for i, member in ipairs(g.members) do
        member.unit, member.subgroup, member.partyUnit = ("raid" .. i), math.ceil(i / 5), nil

        if member.subgroup == playerSubgroup then
            partyIndex = (partyIndex + 1)
            member.partyUnit = ("party" .. partyIndex)
        end
    end
end

local function ValidPrefix(prefix)
    return ((type(prefix) == "string") and (prefix ~= "") and (#prefix <= Harness.MAX_PREFIX_LENGTH))
end

-- The Enum.SendAddonMessageResult name a send gets.
local function SendResult(h, prefix, message, chatType, target)
    if not ValidPrefix(prefix) then
        return "InvalidPrefix"
    end

    if (type(message) ~= "string") or (#message > Harness.MAX_ADDON_MESSAGE_BYTES) or message:find("\0", 1, true) then
        return "InvalidMessage"
    end

    if UnmodeledChatTypes[chatType] then
        error("C_ChatInfo.SendAddonMessage: chat type " .. chatType .. " isn't modeled by the harness", 4)
    end

    if not ChatTypes[chatType] then
        return "InvalidChatType"
    end

    if h:InChatMessagingLockdown() then
        return "AddOnMessageLockdown"
    end

    local home = Harness.PARTY_CATEGORY.HOME

    if ((chatType == "PARTY") and not h:InGroupCategory(home))
        or ((chatType == "RAID") and not (h:InGroupCategory(home) and h:GroupIsRaid()))
        or ((chatType == "INSTANCE_CHAT") and not h:InGroupCategory(Harness.PARTY_CATEGORY.INSTANCE)) then
        return "NotInGroup"
    end

    if ((chatType == "GUILD") or (chatType == "OFFICER")) and (h.player.guild == nil) then
        return "NotInGuild"
    end

    if (chatType == "WHISPER") and ((type(target) ~= "string") or (target == "")) then
        return "TargetRequired"
    end

    if h:AddonAllowance(prefix) < 1 then
        return "AddonMessageThrottle"
    end

    return "Success"
end

-- GetNormalizedRealmName's form: no spaces or hyphens.
function Harness.NormalizeRealm(realm)
    return (tostring(realm):gsub("[%s%-]", ""))
end

-- Adds a member ("First", "First Last", either with "-Realm", or a unit table) and fires GROUP_ROSTER_UPDATE.
function Harness:AddMember(name)
    assert(self.group.kind, "AddMember: not in a group")
    local member = Member(self, name)

    assert(not self:FindMember(member.name .. "-" .. member.realm), "AddMember: already a member: " .. member.name)
    CheckSize(self, ((self.group.kind == "party") and "party") or "raid", #self.group.members + 1)
    self.group.members[#self.group.members + 1] = member
    Retoken(self)
    self:Fire("GROUP_ROSTER_UPDATE")
end

-- The prefix's remaining allowance at h.time, regenerated since it was last spent.
function Harness:AddonAllowance(prefix)
    local bucket = self.throttle[prefix]
    local model = Harness.ADDON_THROTTLE

    if not bucket then
        return model.allowance
    end

    return math.min(model.allowance, bucket.allowance + ((self.time - bucket.time) * model.perSecond))
end

-- The C_ChatInfo addon message fakes, merged into the env's C_ChatInfo.
function Harness:AddonMessageFakes()
    local h = self

    local function Result(enumName, name)
        return __snapshot.enums[enumName][name]
    end

    return {
        InChatMessagingLockdown = function()
            return h:InChatMessagingLockdown()
        end,
        RegisterAddonMessagePrefix = function(prefix)
            if not ValidPrefix(prefix) then
                return Result("RegisterAddonMessagePrefixResult", "InvalidPrefix")
            elseif h.prefixes[prefix] then
                return Result("RegisterAddonMessagePrefixResult", "DuplicatePrefix")
            elseif #h.prefixOrder >= Harness.MAX_PREFIXES then
                return Result("RegisterAddonMessagePrefixResult", "MaxPrefixes")
            end

            h.prefixes[prefix] = true
            h.prefixOrder[#h.prefixOrder + 1] = prefix

            return Result("RegisterAddonMessagePrefixResult", "Success")
        end,
        SendAddonMessage = function(prefix, message, chatType, target)
            chatType = (chatType or "PARTY")
            local name = SendResult(h, prefix, message, chatType, target)
            local failure = h.addonAnswer

            if (name == "Success") and failure and (failure.count > 0) then
                failure.count = (failure.count - 1)

                if failure.answer == "raise" then
                    error("C_ChatInfo.SendAddonMessage: the client raised (h:AnswerAddonMessages)", 2)
                end

                name = failure.answer
            end

            local result = Result("SendAddonMessageResult", name)

            h.addonMessages[#h.addonMessages + 1] = {
                chatType = chatType, message = message, prefix = prefix, result = result, target = target,
            }

            if name == "Success" then
                h.throttle[prefix] = { allowance = (h:AddonAllowance(prefix) - 1), time = h.time }

                if h.echo and Echoes(h, chatType, target) then
                    local sender = h:FullName(h.player)

                    h:Schedule(0, function()
                        h:ReceiveAddonMessage(prefix, message, chatType, sender)
                    end)
                end
            end

            return result
        end,
    }
end

-- Fails the next count sends that would succeed (see the header).
function Harness:AnswerAddonMessages(answer, count)
    assert((answer == "raise") or ((answer ~= "Success") and __snapshot.enums.SendAddonMessageResult[answer]),
        "AnswerAddonMessages: answer must be a failing SendAddonMessageResult name or \"raise\"")

    self.addonAnswer = { answer = answer, count = (count or 1) }
end

-- Turns echo of your own group messages on (the default, like the client) or off.
function Harness:Echo(enabled)
    self.echo = (enabled ~= false)
end

-- The member with this name ("First", "First Last" or either with "-Realm"), and its index.
function Harness:FindMember(name)
    local full = self:FullName(name)

    for i, member in ipairs(self.group.members) do
        local memberFull = self:FullName(member)

        if (memberFull == full) or (self:FullName(member.name .. "-" .. member.realm) == full) then
            return member, i
        end
    end
end

-- A chat sender as the client writes it: the full name, "First Last" ([E] names.chatSenders), with "-Realm" only for
-- another realm ([G]: regionally unique names need no realm). name is a sender ("First Last", "First Last-Realm") or a
-- unit table.
function Harness:FullName(name)
    if type(name) == "table" then
        name = (Harness.DisplayName(name) .. "-" .. (name.realm or self.player.realm))
    end

    local full, realm = name:match("^([^%-]+)%-(.+)$")

    full = (full or name)

    if realm and (Harness.NormalizeRealm(realm) ~= Harness.NormalizeRealm(self.player.realm)) then
        return (full .. "-" .. Harness.NormalizeRealm(realm))
    end

    return full
end

-- The group's LE_PARTY_CATEGORY, or nil outside a group.
function Harness:GroupCategory()
    local kind = self.group.kind

    if not kind then
        return nil
    end

    return (((kind == "instance") and Harness.PARTY_CATEGORY.INSTANCE) or Harness.PARTY_CATEGORY.HOME)
end

function Harness:GroupIsRaid()
    local g = self.group

    return ((g.kind == "raid") or ((g.kind == "instance") and (#g.members > 4)))
end

-- The unit table a group token names (the player's own raid token included), or nil.
function Harness:GroupUnit(token)
    local g = self.group

    if not g.kind then
        return nil
    end

    if token == g.playerUnit then
        return self.player
    end

    for _, member in ipairs(g.members) do
        if (member.unit == token) or (member.partyUnit == token) then
            return member
        end
    end
end

-- The chat messaging lockdown (SecretInChatMessagingLockdown's restrictions).
function Harness:InChatMessagingLockdown()
    return (Harness.PREDICATES.SecretInChatMessagingLockdown(self) == true)
end

-- In a group of the category (nil = any).
function Harness:InGroupCategory(category)
    local current = self:GroupCategory()

    return ((current ~= nil) and ((category == nil) or (category == current)))
end

-- Joins a group of kind ("party", "raid" or "instance") with the given members (each "Name", "First Last", either with
-- "-Realm", or a unit table with a name), then fires GROUP_JOINED(category, partyGUID) and GROUP_ROSTER_UPDATE.
function Harness:JoinGroup(kind, names)
    assert(GroupKinds[kind], "JoinGroup: kind must be party, raid or instance, got " .. tostring(kind))
    assert(not self.group.kind, "JoinGroup: already in a group (LeaveGroup first)")
    names = (names or {})
    CheckSize(self, ((kind == "party") and "party") or "raid", #names)
    local members = {}

    for i, spec in ipairs(names) do
        members[i] = Member(self, spec)
    end

    self.partySerial = (self.partySerial + 1)
    self.group.kind, self.group.members = kind, members
    self.group.guid = ("Party-0-%016X"):format(self.partySerial)
    Retoken(self)
    self:Fire("GROUP_JOINED", self:GroupCategory(), self.group.guid)
    self:Fire("GROUP_ROSTER_UPDATE")
    self:Fire("RAID_TARGET_UPDATE")
end

-- Leaves the group: GROUP_LEFT(category, partyGUID), then GROUP_ROSTER_UPDATE.
function Harness:LeaveGroup()
    assert(self.group.kind, "LeaveGroup: not in a group")
    local category, guid = self:GroupCategory(), self.group.guid

    self.group.kind, self.group.members, self.group.guid, self.group.playerUnit = nil, {}, nil, nil
    self:Fire("GROUP_LEFT", category, guid)
    self:Fire("GROUP_ROSTER_UPDATE")
    self:Fire("RAID_TARGET_UPDATE")
end

-- Delivers an addon message from another client: CHAT_MSG_ADDON with the full documented payload, only when the prefix
-- is registered. sender is written as the client writes it (Harness:FullName); a group member named by first name
-- ("Mom") sends as their full name. Returns whether it was delivered.
function Harness:ReceiveAddonMessage(prefix, text, channel, sender, target)
    if not self.prefixes[prefix] then
        return false
    end

    local member = (self.group.kind and self:FindMember(sender))

    -- a member named by first name: their full name
    sender = ((member and self:FullName(member)) or self:FullName(sender))

    if target == nil then
        target = (((channel == "WHISPER") and sender) or "")
    end

    self:Fire("CHAT_MSG_ADDON", prefix, text, channel, sender, target, 0, 0, "", 0)

    return true
end

-- Removes a member and fires GROUP_ROSTER_UPDATE; removing the last one disbands the group (LeaveGroup's events).
function Harness:RemoveMember(name)
    local _, index = self:FindMember(name)

    assert(index, "RemoveMember: not a member: " .. tostring(name))

    if #self.group.members == 1 then
        return self:LeaveGroup()
    end

    table.remove(self.group.members, index)
    Retoken(self)
    self:Fire("GROUP_ROSTER_UPDATE")
end
