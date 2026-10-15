-- Krew: party-only addon messages between friends, within Blizzard's rules.

local Prefix = "TLKKrew1"

local function Load(player)
    local h = Harness.New(player)
    local ns = h:LoadAddon("TheLanKrewToolKit")
    return h, ns.Addon
end

local function Sent(h, kind)
    local count = 0
    for _, message in ipairs(h.addonMessages) do
        if message.prefix == Prefix and (not kind or message.message:find("^" .. kind)) then
            count = count + 1
        end
    end
    return count
end

local function CardText(h)
    local card = rawget(h.env, "TheLanKrewToolKitCard")
    if not (card and card:IsShown()) then
        return nil
    end
    return Reveal(Harness.State(card.Title).text) .. "\n" .. Reveal(Harness.State(card.Body).text)
end

test("nothing is sent outside a group", function()
    local h = Load()
    h.player.level = h.player.level + 1
    h:LevelUp(h.player.level)
    eq(#h.addonMessages, 0)
end)

test("you say hello once per group; hellos that aren't replies get one reply per burst, replies none", function()
    local h = Load()
    h:JoinGroup("party", { "Bob" })
    eq(Sent(h, "HELLO"), 1)
    eq(h.addonMessages[1].chatType, "PARTY")
    eq(h.addonMessages[1].message, "HELLO:0.1.0\t0", "a hello that wants replies")
    h:AddMember("Cara")
    h:Advance(60)
    h:AddMember("Dan")
    eq(Sent(h, "HELLO"), 1, "roster changes don't repeat it")
    h:ReceiveAddonMessage(Prefix, "HELLO:0.1.0\t0", "PARTY", "Cara")
    h:ReceiveAddonMessage(Prefix, "HELLO:0.1.0\t0", "PARTY", "Dan")
    h:Advance(3)
    eq(Sent(h, "HELLO"), 2, "one reply for the burst")
    eq(h.addonMessages[#h.addonMessages].message, "HELLO:0.1.0\t1")
    h:ReceiveAddonMessage(Prefix, "HELLO:0.1.0\t1", "PARTY", "Bob")
    h:Advance(3)
    eq(Sent(h, "HELLO"), 2, "a reply is never answered: no ping-pong")
    h:ReceiveAddonMessage(Prefix, "HELLO:0.1.0\t0", "PARTY", "Cara") -- Cara reloaded
    h:Advance(3)
    eq(Sent(h, "HELLO"), 3, "a member saying hello again hears back")
end)

test("a /reload says hello again, and the Krew answers", function()
    local h = Load()
    h:JoinGroup("party", { "Mom" })
    h:ReceiveAddonMessage(Prefix, "HELLO:0.1.0\t1", "PARTY", "Mom")
    h:Advance(3)
    local before = Sent(h, "HELLO")
    h:Reload()
    h:Advance(3)
    eq(Sent(h, "HELLO"), before + 1, "the reloaded UI says hello")
    h:Slash("/tlk krew")
    eq(h.printed[#h.printed]:match("No Krew members"), "No Krew members", "it knows nobody yet")
    h:ReceiveAddonMessage(Prefix, "HELLO:0.1.0\t1", "PARTY", "Mom")
    h:Slash("/tlk krew")
    truthy(h.printed[#h.printed]:find("The Krew: Mom Doe", 1, true), "Mom's reply tells it")
end)

test("a late joiner learns the existing Krew and syncs their own marks and wars", function()
    local alice, aliceAddon = Load({ name = "Alice" })
    local cara, caraAddon = Load({ name = "Cara" })
    local dana = Load({ name = "Dana" })
    dana:Slash("/tlk mark Enemy Doe")
    dana:Slash("/tlk war Red Dawn")
    alice:JoinGroup("party", { "Cara" })
    cara:JoinGroup("party", { "Alice" })
    local clients, delivered = { alice, cara }, { 0, 0, 0 }
    local function Relay()
        for i, sender in ipairs(clients) do
            while delivered[i] < #sender.addonMessages do
                delivered[i] = delivered[i] + 1
                local message = sender.addonMessages[delivered[i]]
                for j, receiver in ipairs(clients) do
                    if i ~= j then
                        receiver:ReceiveAddonMessage(message.prefix, message.message, message.chatType,
                            sender:FullName(sender.player))
                    end
                end
            end
        end
    end
    Relay()
    for _ = 1, 10 do
        alice:Advance(1)
        cara:Advance(1)
        dana:Advance(1)
        Relay()
    end
    alice:AddMember("Dana")
    cara:AddMember("Dana")
    dana:JoinGroup("party", { "Alice", "Cara" })
    clients[3] = dana
    Relay()
    for _ = 1, 5 do
        for _, client in ipairs(clients) do
            client:Advance(1)
        end
        Relay()
    end
    truthy((CardText(dana) or ""):find("Alice Doe, Cara Doe are running the toolkit too", 1, true))
    dana:Slash("/tlk krew")
    eq(dana.printed[#dana.printed]:match("The Krew: .*$"), "The Krew: Alice Doe (0.1.0), Cara Doe (0.1.0)")
    eq(Sent(dana, "MARKS"), 1, "the returning hello triggers one mark sync")
    eq(Sent(dana, "WARS"), 1, "the burst of replies triggers one war sync")
    for _, addon in ipairs({ aliceAddon, caraAddon }) do
        eq(addon.Modules.Warband.Records.ledger:Field("Enemy Doe", "kind"), "mark")
        truthy(addon.Modules.Warband.Records.wars:Has("Red Dawn-" .. dana.env.GetNormalizedRealmName()))
    end
end)

local function Newer(h)
    local found = {}
    for _, line in ipairs(h.printed) do
        if line:find("A newer TheLanKrewToolKit is out", 1, true) then
            found[#found + 1] = line:match("A newer.*$")
        end
    end
    return found
end

test("/tlk krew lists the version each member runs", function()
    local h = Load()
    h:JoinGroup("party", { "Bob", "Cara", "Dan", "Eve" })
    h:ReceiveAddonMessage(Prefix, "HELLO:0.1.0\t1", "PARTY", "Bob")
    h:ReceiveAddonMessage(Prefix, "HELLO:0.2.0\t1", "PARTY", "Cara")
    h:ReceiveAddonMessage(Prefix, "HELLO:0.0.9\t1", "PARTY", "Dan")
    h:ReceiveAddonMessage(Prefix, "HELLO:1.x|cff\t1", "PARTY", "Eve")
    h:Slash("/tlk krew")
    eq(h.printed[#h.printed]:match("The Krew: .*$"), "The Krew: Bob Doe (0.1.0), Cara Doe (0.2.0), Dan Doe (0.0.9), Eve Doe",
        "an unreadable version is left out")
    eq(#Newer(h), 0, "one member ahead is no news")
    h:ReceiveAddonMessage(Prefix, "HELLO:0.3.0\t1", "PARTY", "Bob") -- Bob updated and reloaded
    h:Slash("/tlk krew")
    truthy(h.printed[#h.printed]:find("Bob Doe (0.3.0)", 1, true), "a later hello updates it")
end)

test("two Krew members on a newer version say so once per group, compared as numbers", function()
    local h = Load()
    h:JoinGroup("party", { "Bob", "Cara", "Dan" })
    h:ReceiveAddonMessage(Prefix, "HELLO:0.10.0\t1", "PARTY", "Bob")
    eq(#Newer(h), 0, "one is not enough")
    h:ReceiveAddonMessage(Prefix, "HELLO:0.9.0\t1", "PARTY", "Cara")
    eq(table.concat(Newer(h), "\n"), "A newer TheLanKrewToolKit is out (2 Krew members run 0.9.0 or newer).",
        "0.10.0 is newer than 0.9.0")
    h:ReceiveAddonMessage(Prefix, "HELLO:0.10.0\t1", "PARTY", "Dan")
    h:ReceiveAddonMessage(Prefix, "HELLO:0.10.0\t0", "PARTY", "Cara")
    eq(#Newer(h), 1, "once per group")
    h:LeaveGroup()
    h:JoinGroup("party", { "Bob", "Cara" })
    h:ReceiveAddonMessage(Prefix, "HELLO:0.2.0\t1", "PARTY", "Bob")
    h:ReceiveAddonMessage(Prefix, "HELLO:0.2.0\t1", "PARTY", "Cara")
    local said = Newer(h)
    eq(#said, 2, "a new group hears it again")
    eq(said[2], "A newer TheLanKrewToolKit is out (2 Krew members run 0.2.0).")
end)

test("a Krew member's hello shows who's here, merged into one card", function()
    local h = Load()
    h:JoinGroup("party", { "Bob", "Cara" })
    h:ReceiveAddonMessage(Prefix, "HELLO:0.1.0", "PARTY", "Bob")
    h:ReceiveAddonMessage(Prefix, "HELLO:0.1.0", "PARTY", "Cara")
    eq(CardText(h), nil, "waits a moment to gather everyone")
    h:Advance(3)
    truthy(CardText(h):find("Bob Doe, Cara Doe are running the toolkit too", 1, true), CardText(h))
end)

test("level-ups and flawless victories are shared; the Krew sees cards", function()
    local h = Load()
    h:JoinGroup("party", { "Bob" })
    h.player.level = h.player.level + 1
    h:LevelUp(h.player.level)
    h:Advance(2)
    eq(Sent(h, "DING:" .. h.player.level), 1)
    h:ReceiveAddonMessage(Prefix, "DING:20", "PARTY", "Bob")
    truthy(CardText(h):find("Ding! Level", 1, true), "our own ding card is still up")
    h:Click(rawget(h.env, "TheLanKrewToolKitCard"))
    truthy(CardText(h):find("Bob Doe hit level 20!", 1, true), CardText(h))
    h:Click(rawget(h.env, "TheLanKrewToolKitCard"))
    local enemy = { name = "Ann", isPlayer = true, canAttack = true, playerControlled = true }
    h:SetTarget(enemy)
    h:EnterCombat()
    enemy.dead = true
    h:Fire("UNIT_HEALTH", "target")
    h:LeaveCombat()
    h:Advance(2)
    eq(Sent(h, "FLAWLESS"), 1, "a flawless victory, once the fight ends")
    h:ReceiveAddonMessage(Prefix, "FLAWLESS", "PARTY", "Bob")
    eq(CardText(h), "Flawless victory!\nBob Doe won a fight without taking a single hit.")
end)

test("a flood of Krew cards is capped", function()
    local h = Load()
    h:JoinGroup("party", { "Bob" })
    h:Echo(false)
    for level = 2, 30 do
        h:ReceiveAddonMessage(Prefix, "DING:" .. level, "PARTY", "Bob")
    end
    local card, shown = rawget(h.env, "TheLanKrewToolKitCard"), 0
    while card:IsShown() and shown < 50 do
        shown = shown + 1
        h:Click(card)
    end
    eq(shown, 7, "the showing card plus six queued")
end)

test("the client's echo of our own message is ours, though it names us with our surname", function()
    local h = Load()
    h:JoinGroup("party", { "Bob" }) -- we say hello; the echo arrives as "Tester Doe", UnitName says "Tester", "Doe"
    h:Advance(3)
    h:Slash("/tlk krew")
    truthy(table.concat(h.printed, " "):find("No Krew members in your group yet.", 1, true), "we're not our own Krew")
end)

test("our own echoed messages and malformed or foreign messages are ignored", function()
    local h = Load()
    h:JoinGroup("party", { "Bob" })
    h:ReceiveAddonMessage(Prefix, "DING:20", "PARTY", h:FullName(h.player))
    h:ReceiveAddonMessage(Prefix, "DING:banana", "PARTY", "Bob")
    h:ReceiveAddonMessage(Prefix, "DING:20", "WHISPER", "Bob")
    h:ReceiveAddonMessage(Prefix, "EXPLODE", "PARTY", "Bob")
    eq(CardText(h), nil)
end)

test("nothing is sent during chat messaging lockdown; stale celebrations are dropped", function()
    local h = Load()
    h:JoinGroup("party", { "Bob" })
    local before = #h.addonMessages
    h:SetRestriction("Encounter", true)
    h.player.level = h.player.level + 1
    h:LevelUp(h.player.level)
    h:Advance(5)
    h:SetRestriction("Encounter", false)
    h:Advance(5)
    eq(#h.addonMessages, before, "not sent then, not replayed later")
end)

test("sends are spaced out, never a burst", function()
    local h = Load()
    h:JoinGroup("party", { "Bob" })
    for _ = 1, 3 do
        h.player.level = h.player.level + 1
        h:LevelUp(h.player.level)
    end
    eq(Sent(h, "DING"), 0, "the hello went first; dings wait their turn")
    h:Advance(1)
    eq(Sent(h, "DING"), 1)
    h:Advance(1)
    eq(Sent(h, "DING"), 2)
end)

test("turning sharing off stops it", function()
    local h, addon = Load()
    addon.State:Set("Krew.shareDings", false)
    h:JoinGroup("party", { "Bob" })
    h:Advance(2)
    h.player.level = h.player.level + 1
    h:LevelUp(h.player.level)
    h:Advance(2)
    eq(Sent(h, "DING"), 0)
end)

test("Krew messages switched off forget the Krew; on again, you say hello again", function()
    local h, addon = Load()
    h:JoinGroup("party", { "Bob" })
    h:Advance(2)
    h:ReceiveAddonMessage(Prefix, "HELLO:0.1.0\t1", "PARTY", "Bob")
    eq(Sent(h, "HELLO"), 1)
    addon.State:Set("Krew.enabled", false)
    addon.State:Set("Krew.enabled", true)
    h:Slash("/tlk krew")
    eq(h.printed[#h.printed]:match("No Krew members in your group yet%.$"), "No Krew members in your group yet.")
    h:Advance(2)
    eq(Sent(h, "HELLO"), 2, "a fresh hello")
end)

test("a card showing when combat starts steps aside until the fight ends", function()
    local h = Load()
    h:JoinGroup("party", { "Bob" })
    h:ReceiveAddonMessage(Prefix, "DING:20", "PARTY", "Bob")
    truthy(CardText(h):find("Bob Doe hit level 20!", 1, true), CardText(h))
    h:EnterCombat()
    eq(CardText(h), nil, "hidden, and so not clickable, in the fight")
    h:Advance(30)
    h:LeaveCombat()
    truthy((CardText(h) or ""):find("Bob Doe hit level 20!", 1, true), "back at the front of the queue")
end)

test("someone who leaves the group leaves the Krew", function()
    local h = Load()
    h:JoinGroup("party", { "Bob", "Cara" })
    h:ReceiveAddonMessage(Prefix, "HELLO:0.1.0", "PARTY", "Bob")
    h:ReceiveAddonMessage(Prefix, "HELLO:0.1.0", "PARTY", "Cara")
    h:RemoveMember("Cara")
    h:Slash("/tlk krew")
    eq(h.printed[#h.printed]:match("The Krew: .*$"), "The Krew: Bob Doe (0.1.0)")
end)

test("addon messages are only heard in a group: solo, every other addon's chatter costs nothing", function()
    local h, addon = Load()
    local frame = addon.Events.Frame
    falsy(frame:IsEventRegistered("CHAT_MSG_ADDON"), "solo")
    h:JoinGroup("party", { "Bob" })
    truthy(frame:IsEventRegistered("CHAT_MSG_ADDON"), "grouped")
    h:LeaveGroup()
    falsy(frame:IsEventRegistered("CHAT_MSG_ADDON"), "solo again")
end)

test("a roster change reads no names while no one in the group is in the Krew", function()
    local h = Load()
    local names = {}
    for i = 1, 19 do
        names[i] = "Raider" .. i
    end
    h:JoinGroup("raid", names)
    h.apiCalls = {}
    h:AddMember("Latecomer")
    eq(h:CountApiCalls("UnitName"), 0)
end)

test("a raid forming reads the roster once, after its burst of updates settles", function()
    local h = Load()
    h:JoinGroup("raid", { "Bob", "Cara" })
    h:ReceiveAddonMessage(Prefix, "HELLO:0.1.0\t1", "PARTY", "Bob")
    h:ReceiveAddonMessage(Prefix, "HELLO:0.1.0\t1", "PARTY", "Cara")
    h:Advance(5)
    h.apiCalls = {}
    for i = 1, 20 do
        h:AddMember("Raider" .. i)
    end
    h:RemoveMember("Cara")
    eq(h:CountApiCalls("UnitName"), 0, "nothing read while the roster is still changing")
    h:Advance(0.5)
    h:AddMember("Latecomer")
    h:Advance(0.5)
    eq(h:CountApiCalls("UnitName"), 0, "an update inside the burst waits for quiet")
    h:Advance(2)
    eq(h:CountApiCalls("UnitName"), h.env.GetNumGroupMembers(), "one pass of unit reads")
    h:Slash("/tlk krew")
    eq(h.printed[#h.printed]:match("The Krew: .*$"), "The Krew: Bob Doe (0.1.0)", "Cara left; Bob stays")
end)

test("the Krew listed mid-burst is the group as it is", function()
    local h = Load()
    h:JoinGroup("raid", { "Bob", "Cara" })
    h:ReceiveAddonMessage(Prefix, "HELLO:0.1.0\t1", "PARTY", "Bob")
    h:ReceiveAddonMessage(Prefix, "HELLO:0.1.0\t1", "PARTY", "Cara")
    h:Advance(5)
    h:AddMember("Dan")
    h:RemoveMember("Cara")
    h:Slash("/tlk krew")
    eq(h.printed[#h.printed]:match("The Krew: .*$"), "The Krew: Bob Doe (0.1.0)")
    h.apiCalls = {}
    h:Advance(5)
    eq(h:CountApiCalls("UnitName"), 0, "the pass already ran")
end)

test("levels and stars from the Krew are whole numbers written in digits", function()
    local h = Load()
    h:JoinGroup("party", { "Bob" })
    for _, text in ipairs({ "DING:0x10", "DING:1e1", "DING:inf", "DING:20.0", "DING:-5", "DING:201",
        "SCHOLAR:inf", "SCHOLAR:0x10", "SCHOLAR:1e300", "SCHOLAR:0" }) do
        h:ReceiveAddonMessage(Prefix, text, "PARTY", "Bob")
    end
    eq(CardText(h), nil)
    h:ReceiveAddonMessage(Prefix, "SCHOLAR:3", "PARTY", "Bob")
    truthy(CardText(h):find("That's 3 stars", 1, true), CardText(h))
end)
