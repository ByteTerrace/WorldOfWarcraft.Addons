local addonName, ns = ...

-- WarbandMenus: Warband in Blizzard's UI, the right-click menu on other players and unit tooltips,
-- and the ledger's listings in chat.
--
--   Warband.MenuEntries(root, info)  adds the Krew's choices for a player to a menu description
--                                    (the unit popup, and the nearby-enemies window's menu).
--   Warband.EnableMenus()            hooks the menus and tooltips on the first call; menu and
--   Warband.DisableMenus()           tooltip hooks can't be removed, so these only gate them.
--   Warband.PrintLedger()            lists the ledger and the wars (/tlk ledger).
--   Warband.PrintRival(arg)          your record against a player (/tlk rival).

-- The unit popup menus for other players (Blizzard_UnitPopup: "MENU_UNIT_" .. which). Nameplates
-- open none.
local MenuTags = { "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER" }

local ipairs, print = ipairs, print
local sort = table.sort
local UnitExists = UnitExists

local Addon = ns.Addon
local Warband = ns.Warband

local Active, Hooked = false, false

local function MenuSubject(contextData)
    local unit = (contextData and contextData.unit)

    if unit and UnitExists(unit) then
        return Warband.Identify(unit)
    end
    -- UnitPopupManager fills name and surname from UnitNameUnmodified; a chat link's name is
    -- already the full name (Blizzard_UnitPopupShared). A secret surname leaves no full name.
    local name = (contextData and contextData.name)
    local surname = (contextData and contextData.surname)

    if issecretvalue(name) or issecretvalue(surname) or (type(name) ~= "string") or (name == "") then
        return nil
    end
    local key = Warband.KeyOf(ByteTerrace.Names.Full(name, surname))

    return ((Warband.ValidKey(key) and Warband.Known(key)) or nil)
end

--- Adds the Krew's choices for a player to a menu: mark, grudge, glory, forgive, and war or peace
--- with their guild, leaving out what the ledger already says. Each choice runs in one state
--- batch and expires when Warband stops, even if it starts again before the menu closes.
---@param root table a menu description
---@param info table the player (Warband.Identify)
function Warband.MenuEntries(root, info)
    local key = info.key
    local kind = (Warband.Ledger:Has(key) and Warband.Ledger:Field(key, "kind"))
    local module = Warband.Module

    root:CreateTitle("The Lan Krew")
    if kind ~= "mark" then
        root:CreateButton("Mark for death", module:Callback(Warband.Mark, info))
    end
    if (kind ~= "grudge") and (kind ~= "mark") then
        root:CreateButton("Hold a grudge", module:Callback(Warband.HoldGrudge, info, false))
    end
    if kind ~= "glory" then
        root:CreateButton("Grant glory", module:Callback(Warband.Glory, info))
    end
    if kind then
        root:CreateButton("Forgive", module:Callback(Warband.Forgive, key))
    end
    local guild = (info.guild or "")

    if guild ~= "" then
        local name = Warband.GuildName(guild)

        if Warband.Wars:Has(guild) then
            root:CreateButton("Make peace with <" .. name .. ">", module:Callback(Warband.MakePeace, guild))
        else
            root:CreateButton("War on <" .. name .. ">", module:Callback(Warband.DeclareWar, guild))
        end
    end
end

local function AddMenuEntries(_, root, contextData)
    if not Active then
        return
    end
    local info = MenuSubject(contextData)

    if not info or (info.key == Warband.MyKey()) then
        return
    end
    root:CreateDivider()
    Warband.MenuEntries(root, info)
end

local function AddTooltipLines(tooltip)
    if not Active or (tooltip ~= GameTooltip) then
        return
    end
    local _, unit = tooltip:GetUnit()

    if issecretvalue(unit) or not unit then
        return
    end
    local info = Warband.IdentifyNow(unit)

    if not info then
        return
    end
    local key = info.key
    local status = Warband.Status(key, info.guild)
    local ledger, people = Warband.Ledger, Warband.People

    if status == "glory" then
        local by = ledger:Field(key, "by")

        tooltip:AddLine(Warband.Labels.glory .. (((by ~= "") and (" (" .. by .. ")")) or ""), 0.25, 0.75, 1)
    elseif status == "war" then
        tooltip:AddLine(Warband.Labels.war .. ": <" .. Warband.GuildName(info.guild) .. ">", 1, 0.5, 0)
    elseif status then
        local by = (((status == "mark") and ledger:Field(key, "by")) or "")

        tooltip:AddLine(Warband.Labels[status] .. (((by ~= "") and (" (" .. by .. ")")) or ""), 1, 0.25, 0.125)
    end
    if people:Has(key) and (status or ((people:Field(key, "kills") + people:Field(key, "deaths")) > 0)) then
        tooltip:AddLine(Warband.Score(key) .. " - seen " .. people:Field(key, "sightings") .. " times", 0.8, 0.8, 0.8)
    end
end

--- Turns the menu entries and tooltip lines on, hooking them on the first call.
function Warband.EnableMenus()
    Active = true
    if Hooked then
        return
    end
    Hooked = true
    for _, tag in ipairs(MenuTags) do
        Menu.ModifyMenu(tag, AddMenuEntries)
    end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, AddTooltipLines)
end

--- Turns the menu entries and tooltip lines off. The hooks stay, doing nothing.
function Warband.DisableMenus()
    Active = false
end

--- Lists the ledger, marks first and the most recently seen first within a kind, then the wars.
function Warband.PrintLedger()
    local ledger, people, wars = Warband.Ledger, Warband.People, Warband.Wars
    local keys = ledger:Keys()

    if (#keys == 0) and (wars:Count() == 0) then
        Addon:Print("The ledger is empty. Mark someone with " .. Addon.Slash[1] .. " mark.")
        return
    end
    sort(keys, function(a, b)
        local rankA, rankB = Warband.Order[ledger:Field(a, "kind")], Warband.Order[ledger:Field(b, "kind")]

        if rankA ~= rankB then
            return (rankA < rankB)
        end
        return (people:Field(a, "seen") > people:Field(b, "seen"))
    end)
    Addon:Print(("The ledger (%d of %d):"):format(#keys, ledger.Limit))
    for _, key in ipairs(keys) do
        local kind, zone = ledger:Field(key, "kind"), people:Field(key, "zone")
        local line = ("  " .. Warband.Labels[kind] .. ": " .. Warband.Describe(key))

        if kind ~= "glory" then
            line = (line .. " - " .. Warband.Score(key))
        end
        if zone ~= "" then
            line = (line .. " - last seen in " .. zone)
        end
        print(line)
    end
    for _, guild in ipairs(wars:Keys()) do
        print(("  At war: <%s> - Krew %d : %d them"):format(Warband.GuildName(guild), wars:Field(guild, "kills"), wars:Field(guild, "deaths")))
    end
end

--- Prints your record against a player: a typed name, or your target (Warband.Subject).
---@param arg string?
function Warband.PrintRival(arg)
    local people = Warband.People
    local subject = Warband.Subject(arg)
    local key = (subject and people:Has(subject.key) and subject.key)

    if not key then
        return Addon:Print("No record of " .. ((subject and subject.key) or "them") .. " yet.")
    end
    local guild, status = people:Field(key, "guild"), Warband.Status(key)

    Addon:Print(Warband.Describe(key) .. (((guild ~= "") and (" of <" .. Warband.GuildName(guild) .. ">")) or "")
        .. ((status and (" - " .. Warband.Labels[status])) or ""))
    local zone = people:Field(key, "zone")

    print(("  %s. Seen %d times, last in %s."):format(Warband.Score(key), people:Field(key, "sightings"),
        ((zone ~= "") and zone) or "parts unknown"))
end
