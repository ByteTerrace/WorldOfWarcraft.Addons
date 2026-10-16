local addonName, ns = ...

-- Wishes: the stars a young scholar earns buy wishes from a grown-up, so riddles lead to something that matters in the
-- game. It runs on every character: a child's wishes live on their character, and a grown-up answers from any.
--
--   Wishlist  a grown-up adds a wish with a price (/tlk wish 15 Ride the gryphon together). A child can wish for
--             something too (/tlk wish Get a turtle pet), for a grown-up to price (/tlk price 1 10). An item from a
--             vendor, the auction house, or anywhere else is a shift-click: type /tlk wish, shift-click the item to
--             put its link in, and press Enter. The wish keeps the item, so lists link it and cards show its icon. /tlk wishes lists
--             them with how close the stars are, and /tlk unwish 1 takes one off. At most MaxWishes.
--   Asking    when the stars to spend reach a wish's price, the Owl offers to ask with a question card, and /tlk ask 1
--             asks too. Asking holds the wish's stars, so they can't be spent twice, until a grown-up answers.
--   Answers   a request waits in the account-wide asks records, so a grown-up on the same account sees it as a card at
--             their next login, and in /tlk wishes. When the child named them (/tlk parent First Last) and they're
--             grouped, it also goes to them through the Krew (WISH), and their answer comes straight back (WISHED).
--             Granted (a click, or /tlk grant 1) spends the stars, and Not now (/tlk deny 1) gives them back. The
--             child's character takes up an answer at its next login, or at once from the Krew.
--   Stars     ranks count Scholar.stars, every riddle star ever earned, so spending never lowers one. The stars to
--             spend are those, plus bonus stars a grown-up gave (/tlk star 2 Nice trick!), less those spent and held.
--             Bonus stars aren't riddles solved, so no rank or Krew card claims they were.
--   Grown-ups with a PIN set (ScholarLock.lua), pricing, unwishing, granting, bonus stars, and naming parents need the
--             grown-up: unlocked on the child's character, or the PIN at the end of the command elsewhere. A card
--             can't take a PIN, so then it says which command to type. Without a PIN, anyone is trusted.
--
-- Only the child named as a WISH's grown-up shows it, and only a WISHED from a grown-up the child named counts.
--
--   ns.ScholarWishes.Balance()      the stars to spend
--   ns.ScholarWishes.ReportLines()  the report card's lines about wishes and bonus stars

-- The most bonus stars one /tlk star gives.
local MaxBonus = 10
-- The highest price a wish can have.
local MaxPrice = 999
-- The longest wish, in bytes, so it fits a Krew message.
local MaxText = 60
local MaxWishes = 12
local WishIcon = "Interface\\Icons\\INV_Misc_Gift_02"

local C_Item = C_Item
local concat = table.concat
local GetServerTime = GetServerTime
local ipairs = ipairs
local pairs = pairs
local sort = table.sort
local SOUNDKIT = SOUNDKIT
local tonumber = tonumber
local tostring = tostring

local Addon = ns.Addon
local CleanCount = ns.KrewFields.CleanCount
local CleanText = ns.KrewFields.CleanText
local Names = ByteTerrace.Names
-- The module, assigned at the end of the file.
local Wishes

-- Whether a grown-up is here without asking: no PIN is set, or the challenge is unlocked here.
local function GrownUpHere()
    local state = Addon.State

    return ((state:Get("Scholar.pin") == 0) or (Addon.Modules.Scholar:IsRunning() and not state:Get("Scholar.locked")))
end

-- A wish's card icon: its item's, or a gift.
local function Icon(record)
    return (((record.item > 0) and C_Item.GetItemIconByID(record.item)) or WishIcon)
end

-- Whether the one acting is a grown-up: no PIN is set, the challenge is unlocked here, or pin is the PIN. Says how when
-- it isn't.
local function IsGrownUp(pin, how)
    if GrownUpHere() then
        return true
    end

    if pin and (pin ~= "") then
        return ns.ScholarLock.Try(pin)
    end

    Addon:Print("That's for a grown-up: " .. (how or ("unlock first with " .. Addon.Slash[1] .. " unlock <pin>.")))

    return false
end

-- A wish's words for chat: the item's link when it has one the client knows, so it shows its tooltip, or its text.
local function Label(record)
    local link = ((record.item > 0) and select(2, C_Item.GetItemInfo(record.item)))

    return (link or record.text)
end

-- The child's wishes, in the order they were made, as { key, record }.
local function List()
    local wishes = Wishes.Records.wishes
    local out = {}

    for _, key in ipairs(wishes:Keys()) do
        out[#out + 1] = { key = key, wish = wishes:Get(key) }
    end

    sort(out, function(a, b) return (tonumber(a.key) < tonumber(b.key)) end)

    return out
end

local function Held()
    local held = 0

    for _, entry in ipairs(List()) do
        if entry.wish.asked then
            held = (held + entry.wish.price)
        end
    end

    return held
end

--- Returns the stars to spend: every riddle star and bonus star, less those spent on wishes and held by requests.
---@return number
local function Balance()
    return (((Addon.State:Get("Scholar.stars") + Wishes:Get("bonus")) - Wishes:Get("spent")) - Held())
end

local function Me()
    return (Names.Mine() or "")
end

-- Answers a waiting request, by its key in the asks records.
local function Answer(key, granted, pin, position)
    local asks = Wishes.Records.asks
    local ask = asks:Get(key)

    local how = ("type " .. Addon.Slash[1] .. " " .. ((granted and "grant") or "deny") .. " " .. position
        .. " <your PIN>.")

    if not ask or not IsGrownUp(pin, how) then
        return
    end

    if ask.krew then
        ns.Krew:Send("WISHED", { ask.who, tostring(ask.id), ((granted and "1") or "0") })
        asks:Remove(key)
    else
        asks:Set(key, { answer = ((granted and "granted") or "declined"), by = Me() })
    end

    Addon:Print(((granted and "Granted: ") or "Not now: ") .. ask.who .. "'s wish, " .. ask.text .. ".")
end

-- The nth of the child's wishes, saying so when there's none.
local function Nth(text)
    local entry = List()[tonumber(text or "")]

    if not entry then
        Addon:Print("There's no wish with that number. Type " .. Addon.Slash[1] .. " wishes to see them.")
    end

    return entry
end

-- The parents the child named, as a set of full names.
local function Parents()
    local set = {}

    for name in Wishes:Get("parents"):gmatch("[^,]+") do
        set[(name:gsub("^%s+", ""):gsub("%s+$", ""))] = true
    end

    return set
end

local function NameParent(arg)
    local name = CleanText(arg or "")

    if name == "" then
        Addon:Print("Usage: " .. Addon.Slash[1] .. " parent <First Last>.")
    elseif IsGrownUp() then
        local parents = Parents()
        local names = {}

        parents[name] = ((not parents[name]) or nil)

        for parent in pairs(parents) do
            names[#names + 1] = parent
        end

        sort(names)
        Wishes:Set("parents", concat(names, ", "))

        Addon:Print((parents[name] and ("Wishes now go to " .. name .. " when you're grouped."))
            or ("Wishes no longer go to " .. name .. "."))
    end
end

-- The item a link names, and its name, or nil: what a shift-click puts in chat.
local function ParseItem(text)
    local id = text:match("|Hitem:(%d+)")
    local name = text:match("|h%[(.-)%]|h")

    return (id and name and tonumber(id)), name
end

--- Returns the report card's lines about wishes granted and bonus stars, or none.
---@return string[]
local function ReportLines()
    local lines = {}
    local bonus = Wishes:Get("bonusCount")
    local granted = Wishes:Get("granted")

    if bonus > 0 then
        lines[#lines + 1] = ((((bonus == 1) and "1 bonus star") or (bonus .. " bonus stars")) .. " from a grown-up"
            .. (((Wishes:Get("bonusNote") ~= "") and (", the last for: " .. Wishes:Get("bonusNote"))) or "") .. ".")
    end

    if granted > 0 then
        lines[#lines + 1] = ("Wishes granted: %d, the last: %s."):format(granted, Wishes:Get("lastGranted"))
    end

    return lines
end

-- A grown-up's answer reached the child: Granted spends the wish's stars, and Not now gives them back.
local function Resolve(key, granted)
    local wishes = Wishes.Records.wishes
    local wish = wishes:Get(key)

    Wishes.Records.asks:Remove(Me() .. "#" .. key)

    if not wish or not wish.asked then
        return
    end

    if granted then
        Wishes:Set("spent", Wishes:Get("spent") + wish.price)
        Wishes:Set("granted", Wishes:Get("granted") + 1)
        Wishes:Set("lastGranted", wish.text)
        wishes:Remove(key)

        ns.Cards.Show({ body = (wish.text .. ". Have fun!"), icon = Icon(wish), sound = SOUNDKIT.LFG_REWARDS,
            title = "Wish granted!" })
    else
        wishes:Set(key, { asked = false })
        ns.Cards.Show({ body = (wish.text .. ": your stars are back to spend."), icon = Icon(wish), title = "Not this time" })
    end
end

-- Sends the request for wish key to each parent the child named, through the Krew (only when grouped).
local function SendWish(key, wish)
    if not ns.Krew:Ready() then
        return
    end

    for name in pairs(Parents()) do
        local fields = { name, key, tostring(wish.price), wish.text }

        if wish.item > 0 then
            fields[5] = tostring(wish.item)
        end

        ns.Krew:Send("WISH", fields)
    end
end

local function Stars(count)
    return (((count == 1) and "1 star") or (count .. " stars"))
end

local function AddWish(arg)
    local price, priced = (arg or ""):match("^(%d+)%s+(.+)$")
    local wishes = Wishes.Records.wishes
    local stars = (price and GrownUpHere() and CleanCount(price, MaxPrice))
    -- A grown-up's number is the price. A child's is part of the wish.
    local rest = ((stars and priced) or arg or "")
    local item, name = ParseItem(rest)
    local raw = (name or rest)
    -- Cleaned as the Krew cleans what it receives, so it fits a WISH message.
    local text = CleanText(raw)

    if #raw > MaxText then
        Addon:Print(("Keep a wish under %d letters."):format(MaxText))
    elseif text == "" then
        Addon:Print("Usage: " .. Addon.Slash[1] .. " wish <what you'd like>, or for a grown-up, wish <stars> <what>.")
    elseif wishes:Count() >= MaxWishes then
        Addon:Print("The wishlist is full. A grown-up can take one off with " .. Addon.Slash[1] .. " unwish <number>.")
    else
        local id = (Wishes:Get("nextWish") + 1)

        Wishes:Set("nextWish", id)
        wishes:Set(tostring(id), { item = (item or 0), price = (stars or 0), text = text })

        if stars then
            Addon:Print(("Wish added: %s, for %s."):format(text, Stars(stars)))
        else
            Addon:Print("Wish added to the list: " .. text .. ". A grown-up will set its price.")
        end
    end
end

local function Ask(entry)
    local wish = entry.wish
    local balance = Balance()

    if wish.price == 0 then
        Addon:Print(wish.text .. " needs a grown-up to set its price first.")
    elseif wish.asked then
        Addon:Print("You already asked for " .. wish.text .. ". The Owl is waiting for an answer.")
    elseif balance < wish.price then
        Addon:Print(("%s needs %s, and you have %d to spend. %d to go!"):format(wish.text, Stars(wish.price), balance,
            wish.price - balance))
    else
        Wishes.Records.wishes:Set(entry.key, { asked = true })

        Wishes.Records.asks:Set(Me() .. "#" .. entry.key, {
            answer = "", at = GetServerTime(), id = tonumber(entry.key), item = wish.item, krew = false,
            price = wish.price, text = wish.text, who = Me(),
        })

        SendWish(entry.key, wish)
        Addon:Print("Wish sent! The Owl told your grown-up you'd like: " .. wish.text .. ".")
    end
end

-- When the stars to spend just reached a wish's price, the Owl offers to ask for it: the first such wish only.
local function Offer(gained)
    local balance = Balance()

    for _, entry in ipairs(List()) do
        local wish = entry.wish

        if (wish.price > 0) and not wish.asked and (balance >= wish.price) and ((balance - gained) < wish.price) then
            ns.Cards.Show({
                body = ("Ask a grown-up for %s (%s)? Click to ask."):format(wish.text, Stars(wish.price)),
                icon = Icon(wish), onClick = Wishes:Callback(Ask, entry), title = "You have enough stars!",
            })

            return
        end
    end
end

local function GiveBonus(arg)
    local count, reason = (arg or ""):match("^(%d+)%s*(.*)$")
    local stars = CleanCount(count or "", MaxBonus)

    if not stars then
        Addon:Print(("Usage: %s star <1 to %d> <why>."):format(Addon.Slash[1], MaxBonus))
    elseif IsGrownUp() then
        local before = Balance()

        reason = CleanText(reason or "")
        Wishes:Set("bonus", Wishes:Get("bonus") + stars)
        Wishes:Set("bonusCount", Wishes:Get("bonusCount") + stars)
        Wishes:Set("bonusNote", reason)

        ns.Cards.Show({ body = (((reason ~= "") and reason) or "A grown-up thinks you earned it!"), icon = WishIcon,
            sound = SOUNDKIT.IG_QUEST_LIST_COMPLETE, title = (((stars == 1) and "A bonus star!") or (stars .. " bonus stars!")) })

        Offer(Balance() - before)
    end
end

-- Takes up the answers a grown-up gave on this account while the child was away.
local function TakeAnswers()
    local asks = Wishes.Records.asks
    local me = Me()

    for _, key in ipairs(asks:Keys()) do
        local ask = asks:Get(key)

        if (ask.who == me) and (ask.answer ~= "") then
            Resolve(tostring(ask.id), (ask.answer == "granted"))
        end
    end
end

-- The requests waiting for this grown-up's answer (not this character's own), oldest first, as { key, ask }.
local function Waiting()
    local asks = Wishes.Records.asks
    local me = Me()
    local out = {}

    for _, key in ipairs(asks:Keys()) do
        local ask = asks:Get(key)

        if (ask.answer == "") and (ask.who ~= me) then
            out[#out + 1] = { ask = ask, key = key }
        end
    end

    sort(out, function(a, b) return (a.ask.at < b.ask.at) end)

    return out
end

-- "<number> [pin]" for the grant and deny commands: the request and its key, and the PIN.
local function Request(arg, granted)
    local number, pin = (arg or ""):match("^(%d+)%s*(%d*)$")
    local entry = Waiting()[tonumber(number or "")]

    if not entry then
        Addon:Print("There's no wish waiting with that number. Type " .. Addon.Slash[1] .. " wishes to see them.")
    else
        Answer(entry.key, granted, pin, tonumber(number))
    end
end

-- A question card for a request waiting for this grown-up.
local function ShowRequest(key, ask)
    local position = 1

    for i, entry in ipairs(Waiting()) do
        if entry.key == key then
            position = i
        end
    end

    ns.Cards.Show({
        body = (("%s wishes for %s (%s). Click to grant it, or right-click to decide later (%s wishes)."):format(ask.who,
            ask.text, Stars(ask.price), Addon.Slash[1])),
        icon = Icon(ask), onClick = Wishes:Callback(Answer, key, true, nil, position), title = "A wish!",
    })
end

local function ShowWishes()
    local slash = Addon.Slash[1]
    local scholar = Addon.Modules.Scholar:IsRunning()
    local waiting = Waiting()

    if scholar then
        local balance = Balance()
        local list = List()

        if #list == 0 then
            Addon:Print(("No wishes yet. A grown-up can add one: %s wish 20 Pick our next adventure. You can wish "
                .. "for something too: %s wish <what you'd like>."):format(slash, slash))
        else
            Addon:Print("Your wishes:")
        end

        for i, entry in ipairs(list) do
            local wish = entry.wish
            local status = ("%d of %s."):format(balance, Stars(wish.price))

            if wish.price == 0 then
                status = "waiting for a grown-up to set its price."
            elseif wish.asked then
                status = "asked! Waiting for a grown-up's answer."
            end

            Addon:Print(("%d. %s: %s"):format(i, Label(wish), status))
        end

        Addon:Print(("Stars to spend: %d."):format(balance))
    end

    if (#waiting == 0) and not scholar then
        Addon:Print("No wishes are waiting for an answer.")
    elseif #waiting > 0 then
        Addon:Print("Waiting for your answer:")

        for i, entry in ipairs(waiting) do
            Addon:Print(("%d. %s wishes for %s (%s). %s grant %d, or %s deny %d."):format(i, entry.ask.who,
                Label(entry.ask), Stars(entry.ask.price), slash, i, slash, i))
        end
    end
end

Wishes = Addon:Module("Wishes", {
    commands = {
        { label = "Wish for something, or for a grown-up, add a wish with its price (wish [stars] <what>)",
            name = "wish", run = AddWish, slash = "wish" },
        { label = "Show your wishes and your stars to spend", name = "wishes", run = ShowWishes, slash = "wishes" },
        { label = "Ask a grown-up for a wish (ask <number>)", name = "ask",
            run = function(arg)
                local entry = Nth(arg)

                if entry then
                    Ask(entry)
                end
            end,
            slash = "ask" },
        { label = "Grown-ups: set a wish's price (price <number> <stars>)", name = "price",
            run = function(arg)
                local number, price = (arg or ""):match("^(%d+)%s+(%d+)$")
                local entry = Nth(number)
                local stars = CleanCount(price or "", MaxPrice)

                if entry and stars and IsGrownUp() then
                    Wishes.Records.wishes:Set(entry.key, { price = stars })
                    Addon:Print(("%s now costs %s."):format(entry.wish.text, Stars(stars)))
                end
            end,
            slash = "price" },
        { label = "Grown-ups: take a wish off the list (unwish <number>)", name = "unwish",
            run = function(arg)
                local entry = Nth(arg)

                if entry and IsGrownUp() then
                    Wishes.Records.wishes:Remove(entry.key)
                    Wishes.Records.asks:Remove(Me() .. "#" .. entry.key)
                    Addon:Print("Removed: " .. entry.wish.text .. ".")
                end
            end,
            slash = "unwish" },
        { label = "Grown-ups: grant a wish (grant <number> [pin])", name = "grant",
            run = function(arg) Request(arg, true) end, slash = "grant" },
        { label = "Grown-ups: answer a wish Not now (deny <number> [pin])", name = "deny",
            run = function(arg) Request(arg, false) end, slash = "deny" },
        { label = "Grown-ups: give bonus stars to spend (star <count> <why>)", name = "star", run = GiveBonus,
            slash = "star" },
        { label = "Grown-ups: send this child's wishes to you when grouped (parent <First Last>)", name = "parent",
            run = NameParent, slash = "parent" },
    },
    OnEnable = function(module)
        TakeAnswers()

        for _, entry in ipairs(Waiting()) do
            ShowRequest(entry.key, entry.ask)
        end

        module:OnIncrease("Scholar.stars", function(_, count, previous)
            Offer(count - previous)
        end)

        -- A request meant for this grown-up, from a child in the group.
        module:Listen(ns.Krew, "WISH", function(sender, fields)
            local id = CleanCount(fields[2] or "", 999999)
            local price = CleanCount(fields[3] or "", MaxPrice)
            local text = CleanText(fields[4] or "")
            -- The item the wish is for, when it's one: the fifth field.
            local item = (CleanCount(fields[5] or "", 99999999) or 0)

            if (CleanText(fields[1] or "") == Me()) and id and price and (text ~= "") then
                local key = (sender .. "#" .. id)

                module.Records.asks:Set(key, {
                    answer = "", at = GetServerTime(), id = id, item = item, krew = true, price = price, text = text,
                    who = sender,
                })

                ShowRequest(key, module.Records.asks:Get(key))
            end
        end)

        -- A grown-up's answer, counted only from one the child named.
        module:Listen(ns.Krew, "WISHED", function(sender, fields)
            local id = CleanCount(fields[2] or "", 999999)

            if (CleanText(fields[1] or "") == Me()) and id and Parents()[sender] then
                Resolve(tostring(id), (fields[3] == "1"))
            end
        end)
    end,
    records = {
        -- The child's wishes: what, its price (0 until a grown-up sets one), and whether it's asked for.
        { fields = {
                { default = false, kind = "boolean", name = "asked" },
                -- The item the wish is for, or 0.
                { default = 0, kind = "number", min = 0, name = "item", step = 1 },
                { default = 0, kind = "number", max = MaxPrice, min = 0, name = "price", step = 1 },
                { default = "", kind = "string", name = "text" },
            },
            limit = MaxWishes, name = "wishes", scope = "character" },
        -- Requests, account-wide, by "<child>#<wish>": waiting (answer ""), or answered on this account for the child
        -- to take up. One from the Krew (krew) is answered back through it.
        { evict = "at",
            fields = {
                { default = "", kind = "string", name = "answer", values = { "", "declined", "granted" } },
                { default = 0, kind = "number", min = 0, name = "at" },
                { default = "", kind = "string", name = "by" },
                { default = 0, kind = "number", min = 0, name = "id", step = 1 },
                { default = 0, kind = "number", min = 0, name = "item", step = 1 },
                { default = false, kind = "boolean", name = "krew" },
                { default = 0, kind = "number", max = MaxPrice, min = 0, name = "price", step = 1 },
                { default = "", kind = "string", name = "text" },
                { default = "", kind = "string", name = "who" },
            },
            limit = 50, name = "asks" },
    },
    state = {
        { default = 0, kind = "number", min = 0, name = "bonus", scope = "character", step = 1 },
        { default = 0, kind = "number", min = 0, name = "bonusCount", scope = "character", step = 1 },
        { default = "", kind = "string", name = "bonusNote", scope = "character" },
        { default = 0, kind = "number", min = 0, name = "granted", scope = "character", step = 1 },
        { default = "", kind = "string", name = "lastGranted", scope = "character" },
        { default = 0, kind = "number", min = 0, name = "nextWish", scope = "character", step = 1 },
        { default = "", kind = "string", name = "parents", scope = "character" },
        { default = 0, kind = "number", min = 0, name = "spent", scope = "character", step = 1 },
    },
    toggle = false,
})

ns.ScholarWishes = { Balance = Balance, ReportLines = ReportLines }
