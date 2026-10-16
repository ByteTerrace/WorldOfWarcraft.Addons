-- Helpers for The Lan Krew ToolKit's end-to-end tests (toolkit, krew, kombat, and the warband tests): loading the
-- addon, a Krew group, enemy players, and what the Krew sends, receives, and shows (cards and raid notices). A test
-- file gets the table with use("toolkit").

-- The players' own sounds folder (TheLanKrewToolKit\Media\), as sound paths name it.
local MediaPath = "Interface\\AddOns\\TheLanKrewToolKit\\Media\\"
local Prefix = "TLKKrew1"

--- Your killing blow on an enemy player: PARTY_KILL(your GUID, theirs).
local function Blow(h, name)
    h:Fire("PARTY_KILL", h.env.UnitGUID("player"), h:GUID({ isPlayer = true, name = name }))
end

--- The card on screen as "Title\nBody", and the card's frame; nil while none shows.
local function Card(h)
    -- The card frame is created lazily with the first card, so it may not exist yet.
    local card = rawget(h.env, "TheLanKrewToolKitCard")

    if not (card and card:IsShown()) then
        return nil
    end

    return (Reveal(Harness.State(card.Title).text) .. "\n" .. Reveal(Harness.State(card.Body).text)), card
end

--- An enemy player unit: a level 60 Alliance rogue named name (Bob by default), with extra's fields on top.
local function Enemy(name, extra)
    local unit = { canAttack = true, classFile = "ROGUE", className = "Rogue", faction = "Alliance", isEnemy = true,
        isPlayer = true, level = 60, name = (name or "Bob"), playerControlled = true }

    for key, value in pairs(extra or {}) do unit[key] = value end

    return unit
end

--- A player's key: Forever's full name (every test player's surname is the harness default).
local function Key(_, name)
    return (name .. " " .. Harness.DEFAULT_SURNAME)
end

--- Warband's ledger collection.
local function Ledger(addon)
    return addon.Modules.Warband.Records.ledger
end

--- A harness with The Lan Krew ToolKit loaded.
---@param player table? Harness.New's player
---@return table h, table addon
local function Load(player)
    local h = Harness.New(player)
    local ns = h:LoadAddon("TheLanKrewToolKit")

    return h, ns.Addon
end

--- The addon loaded in a group with one friend (Mom), so Krew messages go out. Echo is off: tests look at what we send.
---@return table h, table addon
local function Grouped()
    local h, addon = Load()

    h:JoinGroup("party", { "Mom" })
    h:Echo(false)
    h:Advance(2)

    return h, addon
end

--- The raid notices shown so far, one per line.
local function Notices(h)
    local texts = {}

    for _, notice in ipairs(h.raidNotices) do
        texts[#texts + 1] = notice.text
    end

    return table.concat(texts, "\n")
end

--- Warband's people collection.
local function People(addon)
    return addon.Modules.Warband.Records.people
end

--- A Krew message of kind from sender in the party, its fields joined by tabs.
local function Receive(h, sender, kind, ...)
    h:ReceiveAddonMessage(Prefix, kind .. ":" .. table.concat({ ... }, "\t"), "PARTY", sender)
end

--- The Krew messages of one kind ("MARK") we sent, in order, each as "KIND:fields".
local function Sent(h, kind)
    local found = {}

    for _, message in ipairs(h.addonMessages) do
        if (message.prefix == Prefix) and message.message:find("^" .. kind .. ":") then
            found[#found + 1] = message.message
        end
    end

    return found
end

return {
    Blow = Blow, Card = Card, Enemy = Enemy, Grouped = Grouped, Key = Key, Ledger = Ledger, Load = Load,
    MediaPath = MediaPath, Notices = Notices, People = People, Prefix = Prefix, Receive = Receive, Sent = Sent,
}
