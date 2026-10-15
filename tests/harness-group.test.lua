-- The harness's fidelity rules for groups and addon messages (tests/harness/group.lua).

local function Watch(h, ...)
    local seen = {}
    local frame = h.env.CreateFrame("Frame")
    for _, event in ipairs({ ... }) do
        frame:RegisterEvent(event)
    end
    frame:SetScript("OnEvent", function(_, event, ...)
        local parts = { event }
        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring(Reveal((select(i, ...))))
        end
        seen[#seen + 1] = table.concat(parts, ":")
    end)
    return seen
end

test("joining a party fires GROUP_JOINED with its category and GUID, then GROUP_ROSTER_UPDATE", function()
    local h = Harness.New()
    local env = h.env
    local seen = Watch(h, "GROUP_JOINED", "GROUP_LEFT", "GROUP_ROSTER_UPDATE")
    falsy(env.IsInGroup())
    eq(env.GetNumGroupMembers(), 0)
    h:JoinGroup("party", { "Bob", "Cara-Other Realm" })
    eq(seen[1], "GROUP_JOINED:1:" .. h.group.guid)
    eq(seen[2], "GROUP_ROSTER_UPDATE")
    truthy(env.IsInGroup())
    truthy(env.IsInGroup(Harness.PARTY_CATEGORY.HOME))
    falsy(env.IsInGroup(env.LE_PARTY_CATEGORY_INSTANCE))
    falsy(env.IsInRaid())
    eq(env.GetNumGroupMembers(), 3, "the player counts")
    eq(env.GetNumGroupMembers(env.LE_PARTY_CATEGORY_INSTANCE), 0)
    eq(h.group.members[1].unit, "party1")
    local guid = h.group.guid
    h:LeaveGroup()
    eq(seen[3], "GROUP_LEFT:1:" .. guid)
    eq(seen[4], "GROUP_ROSTER_UPDATE")
    falsy(env.IsInGroup())
    falsy(env.UnitExists("party1"))
    throws(function() h:LeaveGroup() end, "not in a group")
end)

test("group members are named, existing, identity-accessible units, even in combat", function()
    local h = Harness.New({ realm = "Home Realm" })
    local env = h.env
    h:JoinGroup("party", { "Bob", "Cara Smith-OtherRealm" })
    h:EnterCombat()
    truthy(env.UnitExists("party1"))
    falsy(env.UnitExists("party3"))
    local name, surname = env.UnitName("party1")
    falsy(env.issecretvalue(name), "group members aren't identity-restricted")
    eq(name, "Bob")
    eq(surname, Harness.DEFAULT_SURNAME, "a member named by first name gets the default surname")
    eq(table.concat({ env.UnitName("party2") }, ","), "Cara,Smith", "another realm's member: first and surname, no realm")
    eq(table.concat({ env.UnitFullName("party2") }, ","), "Cara,Smith", "UnitFullName: no realm either")
    eq(table.concat({ env.UnitFullName("player") }, ","), "Tester," .. Harness.DEFAULT_SURNAME,
        "UnitFullName gives the player's surname, not their realm")
    eq(select(2, env.UnitName("player")), Harness.DEFAULT_SURNAME)
    falsy(env.issecretvalue(env.UnitClass("party1")))
end)

test("members come and go with GROUP_ROSTER_UPDATE; the last one leaving disbands the group", function()
    local h = Harness.New()
    local env = h.env
    h:JoinGroup("party", { "Bob" })
    local seen = Watch(h, "GROUP_LEFT", "GROUP_ROSTER_UPDATE")
    h:AddMember("Cara")
    eq(table.concat(seen, ","), "GROUP_ROSTER_UPDATE")
    eq(env.UnitName("party2"), "Cara")
    h:RemoveMember("Bob")
    eq(env.UnitName("party1"), "Cara", "tokens close up")
    falsy(env.UnitExists("party2"))
    throws(function() h:RemoveMember("Zed") end, "not a member")
    throws(function() h:AddMember("Cara") end, "already a member")
    h:AddMember("Dan"); h:AddMember("Eve"); h:AddMember("Fay")
    throws(function() h:AddMember("Gus") end, "at most 4")
    h:RemoveMember("Cara"); h:RemoveMember("Dan"); h:RemoveMember("Eve")
    h:RemoveMember("Fay")
    eq(seen[#seen - 1], "GROUP_LEFT:1:" .. "Party-0-0000000000000001")
    falsy(env.IsInGroup())
end)

test("raids give raid tokens, the player a raid index too, and party tokens for the player's subgroup", function()
    local h = Harness.New()
    local env = h.env
    local names = {}
    for i = 1, 7 do names[i] = "M" .. i end
    h:JoinGroup("raid", names)
    truthy(env.IsInRaid())
    truthy(env.IsInRaid(Harness.PARTY_CATEGORY.HOME))
    eq(env.GetNumGroupMembers(), 8)
    eq(env.UnitName("raid1"), "M1")
    eq(env.UnitName("raid8"), "Tester", "the player's own raid token")
    eq(env.UnitName("party1"), "M6", "the player's subgroup (raid6-10)")
    eq(env.UnitName("party2"), "M7")
    falsy(env.UnitExists("party3"))
end)

test("instance groups are LE_PARTY_CATEGORY_INSTANCE, and a raid past five", function()
    local h = Harness.New()
    local env = h.env
    local seen = Watch(h, "GROUP_JOINED")
    h:JoinGroup("instance", { "A", "B", "C", "D" })
    eq(seen[1]:match("^GROUP_JOINED:(%d)"), "2")
    truthy(env.IsInGroup(env.LE_PARTY_CATEGORY_INSTANCE))
    falsy(env.IsInGroup(Harness.PARTY_CATEGORY.HOME))
    falsy(env.IsInRaid())
    eq(env.UnitName("party4"), "D")
    h:AddMember("E")
    truthy(env.IsInRaid(env.LE_PARTY_CATEGORY_INSTANCE))
    eq(env.UnitName("raid5"), "E")
    throws(function() h:JoinGroup("party", {}) end, "already in a group")
end)

local function Result(h, name) return h.env.Enum.SendAddonMessageResult[name] end

test("prefixes register once, up to 16 characters", function()
    local h = Harness.New()
    local chatInfo, results = h.env.C_ChatInfo, h.env.Enum.RegisterAddonMessagePrefixResult
    eq(chatInfo.RegisterAddonMessagePrefix("Krew"), results.Success)
    eq(chatInfo.RegisterAddonMessagePrefix("Krew"), results.DuplicatePrefix)
    eq(chatInfo.RegisterAddonMessagePrefix(""), results.InvalidPrefix)
    eq(chatInfo.RegisterAddonMessagePrefix(string.rep("x", 17)), results.InvalidPrefix)
    eq(chatInfo.RegisterAddonMessagePrefix(string.rep("x", 16)), results.Success)
    truthy(h.prefixes.Krew)
    falsy(h.prefixes.Other)
    eq(#h.prefixOrder, 2)
    h:Reload()
    eq(h.env.C_ChatInfo.RegisterAddonMessagePrefix("Krew"), results.Success, "a new UI session starts with none")
end)

test("SendAddonMessage validates prefix, message and chat type, and records every call", function()
    local h = Harness.New()
    local chatInfo = h.env.C_ChatInfo
    h:JoinGroup("party", { "Bob" })
    eq(chatInfo.SendAddonMessage("Unregistered", "hi"), Result(h, "Success"), "sending needs no registration, only receiving does")
    eq(chatInfo.SendAddonMessage(string.rep("p", 17), "hi", "PARTY"), Result(h, "InvalidPrefix"))
    eq(chatInfo.SendAddonMessage("", "hi", "PARTY"), Result(h, "InvalidPrefix"))
    eq(chatInfo.SendAddonMessage("K", string.rep("m", 256), "PARTY"), Result(h, "InvalidMessage"))
    eq(chatInfo.SendAddonMessage("K", string.rep("m", 255), "PARTY"), Result(h, "Success"))
    eq(chatInfo.SendAddonMessage("K", "a\0b", "PARTY"), Result(h, "InvalidMessage"))
    eq(chatInfo.SendAddonMessage("K", "hi", "BOGUS"), Result(h, "InvalidChatType"))
    eq(chatInfo.SendAddonMessage("K", "hi", "WHISPER"), Result(h, "TargetRequired"))
    eq(chatInfo.SendAddonMessage("K", "hi", "GUILD"), Result(h, "NotInGuild"))
    throws(function() chatInfo.SendAddonMessage("K", "hi", "SAY") end, "isn't modeled")
    local first = h.addonMessages[1]
    eq(first.prefix, "Unregistered")
    eq(first.chatType, "PARTY", "the default chat type is recorded")
    eq(first.result, 0)
    eq(#h.addonMessages, 9, "a harness error records nothing")
    throws(function() chatInfo.SendAddonMessage("K", Secret("hi"), "PARTY") end, "NotAllowed")
end)

test("group chat types need that group", function()
    local h = Harness.New()
    local chatInfo = h.env.C_ChatInfo
    for _, chatType in ipairs({ "PARTY", "RAID", "INSTANCE_CHAT" }) do
        eq(chatInfo.SendAddonMessage("K", "hi", chatType), Result(h, "NotInGroup"), chatType .. " outside a group")
    end
    h:JoinGroup("party", { "Bob" })
    eq(chatInfo.SendAddonMessage("K", "hi", "PARTY"), Result(h, "Success"))
    eq(chatInfo.SendAddonMessage("K", "hi", "RAID"), Result(h, "NotInGroup"), "a party isn't a raid")
    eq(chatInfo.SendAddonMessage("K", "hi", "INSTANCE_CHAT"), Result(h, "NotInGroup"))
    h:LeaveGroup()
    h:JoinGroup("instance", { "Bob" })
    eq(chatInfo.SendAddonMessage("K", "hi", "PARTY"), Result(h, "NotInGroup"), "an instance group isn't a home party")
    eq(chatInfo.SendAddonMessage("K", "hi", "INSTANCE_CHAT"), Result(h, "Success"))
end)

test("chat messaging lockdown refuses sends: encounter, challenge mode, PvP, map, chat; not combat", function()
    local h = Harness.New()
    local chatInfo = h.env.C_ChatInfo
    h:JoinGroup("party", { "Bob" })
    h:EnterCombat()
    falsy(chatInfo.InChatMessagingLockdown(), "combat alone")
    eq(chatInfo.SendAddonMessage("K", "hi"), Result(h, "Success"))
    h:LeaveCombat()
    for _, name in ipairs({ "Encounter", "ChallengeMode", "PvPMatch", "Map", "Chat" }) do
        h:SetRestriction(name, true)
        truthy(chatInfo.InChatMessagingLockdown(), name)
        eq(chatInfo.SendAddonMessage("K", "hi"), Result(h, "AddOnMessageLockdown"), name)
        h:SetRestriction(name, false)
    end
    falsy(chatInfo.InChatMessagingLockdown())
end)

test("each prefix may burst 10 messages and regains 1 per second; refused sends cost nothing", function()
    local h = Harness.New()
    local chatInfo = h.env.C_ChatInfo
    h:JoinGroup("party", { "Bob" })
    for i = 1, 10 do
        eq(chatInfo.SendAddonMessage("K", "m" .. i), Result(h, "Success"), "burst " .. i)
    end
    eq(chatInfo.SendAddonMessage("K", "m11"), Result(h, "AddonMessageThrottle"))
    eq(chatInfo.SendAddonMessage("Other", "x"), Result(h, "Success"), "the throttle is per prefix")
    h:Advance(0.5)
    eq(chatInfo.SendAddonMessage("K", "m12"), Result(h, "AddonMessageThrottle"), "half a message regained")
    h:Advance(0.5)
    eq(chatInfo.SendAddonMessage("K", "m13"), Result(h, "Success"))
    eq(chatInfo.SendAddonMessage("K", "m14"), Result(h, "AddonMessageThrottle"))
    h:Advance(100)
    for i = 1, 10 do
        chatInfo.SendAddonMessage("K", "again" .. i)
    end
    eq(chatInfo.SendAddonMessage("K", "over"), Result(h, "AddonMessageThrottle"), "regains up to 10, no more")
end)

test("received addon messages reach only registered prefixes, with the full documented payload", function()
    local h = Harness.New({ realm = "Home Realm" })
    local got = {}
    local frame = h.env.CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(_, _, ...) got[#got + 1] = { n = select("#", ...), ... } end)
    falsy(h:ReceiveAddonMessage("Krew", "hi", "PARTY", "Bob Doe"), "unregistered: not delivered")
    eq(#got, 0)
    h.env.C_ChatInfo.RegisterAddonMessagePrefix("Krew")
    truthy(h:ReceiveAddonMessage("Krew", "hi", "PARTY", "Bob Doe-Home Realm"))
    local p = got[1]
    eq(p.n, 9)
    eq(table.concat({ p[1], p[2], p[3], p[4], "[" .. p[5] .. "]", p[6], p[7], "[" .. p[8] .. "]", p[9] }, "|"),
        "Krew|hi|PARTY|Bob Doe|[]|0|0|[]|0", "a sender on your realm is \"First Last\" with no realm")
    h:ReceiveAddonMessage("Krew", "psst", "WHISPER", "Cara Doe-Elsewhere")
    eq(got[2][4], "Cara Doe-Elsewhere", "another realm's sender keeps its realm")
    eq(got[2][5], "Cara Doe-Elsewhere", "a whisper's target is the sender, per the event's doc")
end)

test("your own group messages echo back on the next Advance, never during the send", function()
    local h = Harness.New()
    local chatInfo = h.env.C_ChatInfo
    chatInfo.RegisterAddonMessagePrefix("Krew")
    local got = {}
    local frame = h.env.CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(_, _, _, text, channel, sender) got[#got + 1] = text .. "@" .. channel .. "<" .. sender end)
    h:JoinGroup("party", { "Bob" })
    chatInfo.SendAddonMessage("Krew", "hello", "PARTY")
    eq(#got, 0, "not inside the call")
    h:Advance(0)
    eq(got[1], "hello@PARTY<Tester Doe", "from yourself, by your full name with no realm")
    chatInfo.SendAddonMessage("Unheard", "x", "PARTY")
    chatInfo.SendAddonMessage("Krew", "to bob", "WHISPER", "Bob Doe")
    chatInfo.SendAddonMessage("Krew", "to me", "WHISPER", "Tester Doe")
    h:Advance(0)
    eq(#got, 2, "an unregistered prefix and a whisper to someone else don't come back")
    eq(got[2], "to me@WHISPER<Tester Doe")
    h:Echo(false)
    chatInfo.SendAddonMessage("Krew", "quiet", "PARTY")
    h:Advance(1)
    eq(#got, 2, "echo off")
end)
