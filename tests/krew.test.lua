-- Krew: party-only addon messages between friends, within Blizzard's rules.

local PREFIX = "TLKKrew1"

local function Load()
    local h = Harness.new()
    local ns = h:LoadAddon("TheLanKrewToolKit")
    return h, ns.Addon
end

local function Sent(h, kind)
    local count = 0
    for _, message in ipairs(h.addonMessages) do
        if message.prefix == PREFIX and (not kind or message.message:find("^" .. kind)) then
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
    h:Fire("PLAYER_LEVEL_UP", h.player.level)
    eq(#h.addonMessages, 0)
end)

test("joining a group says hello once, on the party channel", function()
    local h = Load()
    h:JoinGroup("party", { "Bob" })
    eq(Sent(h, "HELLO"), 1)
    eq(h.addonMessages[1].chatType, "PARTY")
    h:AddMember("Cara")
    eq(Sent(h, "HELLO"), 1, "the hello cooldown stops repeats")
end)

test("a Krew member's hello shows who's here, merged into one card", function()
    local h = Load()
    h:JoinGroup("party", { "Bob", "Cara" })
    h:ReceiveAddonMessage(PREFIX, "HELLO:0.1.0", "PARTY", "Bob")
    h:ReceiveAddonMessage(PREFIX, "HELLO:0.1.0", "PARTY", "Cara")
    eq(CardText(h), nil, "waits a moment to gather everyone")
    h:Advance(3)
    truthy(CardText(h):find("Bob, Cara are running the toolkit too", 1, true), CardText(h))
end)

test("level-ups and flawless victories are shared; the Krew sees cards", function()
    local h = Load()
    h:JoinGroup("party", { "Bob" })
    h.player.level = h.player.level + 1
    h:Fire("PLAYER_LEVEL_UP", h.player.level)
    h:Advance(2)
    eq(Sent(h, "DING:" .. h.player.level), 1)
    h:ReceiveAddonMessage(PREFIX, "DING:20", "PARTY", "Bob")
    truthy(CardText(h):find("Ding! Level", 1, true), "our own ding card is still up")
    h:Click(rawget(h.env, "TheLanKrewToolKitCard"))
    truthy(CardText(h):find("Bob hit level 20!", 1, true), CardText(h))
end)

test("a flood of Krew cards is capped", function()
    local h = Load()
    h:JoinGroup("party", { "Bob" })
    h:Echo(false)
    for level = 2, 30 do
        h:ReceiveAddonMessage(PREFIX, "DING:" .. level, "PARTY", "Bob")
    end
    local card, shown = rawget(h.env, "TheLanKrewToolKitCard"), 0
    while card:IsShown() and shown < 50 do
        shown = shown + 1
        h:Click(card)
    end
    eq(shown, 7, "the showing card plus six queued")
end)

test("our own echoed messages and malformed or foreign messages are ignored", function()
    local h = Load()
    h:JoinGroup("party", { "Bob" })
    h:ReceiveAddonMessage(PREFIX, "DING:20", "PARTY", h.player.name)
    h:ReceiveAddonMessage(PREFIX, "DING:banana", "PARTY", "Bob")
    h:ReceiveAddonMessage(PREFIX, "DING:20", "WHISPER", "Bob")
    h:ReceiveAddonMessage(PREFIX, "EXPLODE", "PARTY", "Bob")
    eq(CardText(h), nil)
end)

test("nothing is sent during chat messaging lockdown; stale celebrations are dropped", function()
    local h = Load()
    h:JoinGroup("party", { "Bob" })
    local before = #h.addonMessages
    h:SetRestriction("Encounter", true)
    h.player.level = h.player.level + 1
    h:Fire("PLAYER_LEVEL_UP", h.player.level)
    h:Advance(5)
    h:SetRestriction("Encounter", false)
    h:Advance(5)
    eq(#h.addonMessages, before, "not sent then, not replayed later")
end)

test("sends are spaced out, never a burst", function()
    local h, addon = Load()
    h:JoinGroup("party", { "Bob" })
    for _ = 1, 3 do
        h.player.level = h.player.level + 1
        h:Fire("PLAYER_LEVEL_UP", h.player.level)
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
    h:Fire("PLAYER_LEVEL_UP", h.player.level)
    h:Advance(2)
    eq(Sent(h, "DING"), 0)
end)

test("a message that arrives secret (chat lockdown) is ignored", function()
    local h = Load()
    h:JoinGroup("party", { "Bob" })
    h:ReceiveAddonMessage(PREFIX, Secret("HELLO:0.1.0"), "PARTY", "Bob")
    h:Advance(3)
    eq(CardText(h), nil)
end)
