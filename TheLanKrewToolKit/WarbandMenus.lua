local addonName, ns = ...

-- WarbandMenus: Warband in Blizzard's UI, the right-click menu on other players and unit tooltips.
--
--   Warband.MenuEntries(root, info)  adds the Krew's choices for a player to a menu description
--                                    (the unit popup, and the nearby-enemies window's menu).
--   Warband.EnableMenus()            hooks the menus and tooltips on the first call; menu and
--   Warband.DisableMenus()           tooltip hooks can't be removed, so these only gate them.

-- The unit popup menus for other players (Blizzard_UnitPopup: "MENU_UNIT_" .. which). Nameplates
-- open none.
local MenuTags = { "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER" }

local UnitExists = UnitExists

local Addon = ns.Addon
local Warband = ns.Warband

local Active, Hooked = false, false

local function MenuSubject(contextData)
    local unit = contextData and contextData.unit
    if unit and UnitExists(unit) then
        return Warband.Identify(unit)
    end
    local name = contextData and contextData.name
    if type(name) == "string" and not issecretvalue(name) and name ~= "" then
        local realm = contextData.surname -- the unit popup's realm field
        if type(realm) == "string" and not issecretvalue(realm) and realm ~= "" then
            name = name .. "-" .. realm
        end
        return Warband.Subject(name)
    end
end

--- Adds the Krew's choices for a player to a menu: mark, grudge, glory, forgive, and war or peace
--- with their guild, leaving out what the ledger already says. Each choice runs in one state batch.
---@param root table a menu description
---@param info table the player (Warband.Identify)
function Warband.MenuEntries(root, info)
    local key = info.key
    local kind = Warband.Ledger:Has(key) and Warband.Ledger:Field(key, "kind")
    local function Batched(fn, ...)
        local args = { ... }
        return function()
            Addon:Batch(fn, unpack(args))
        end
    end
    root:CreateTitle("The Lan Krew")
    if kind ~= "mark" then
        root:CreateButton("Mark for death", Batched(Warband.Mark, info))
    end
    if kind ~= "grudge" and kind ~= "mark" then
        root:CreateButton("Hold a grudge", Batched(Warband.HoldGrudge, info, false))
    end
    if kind ~= "glory" then
        root:CreateButton("Grant glory", Batched(Warband.Glory, info))
    end
    if kind then
        root:CreateButton("Forgive", Batched(Warband.Forgive, key))
    end
    local guild = info.guild or ""
    if guild ~= "" then
        local name = Warband.GuildName(guild)
        if Warband.Wars:Has(guild) then
            root:CreateButton("Make peace with <" .. name .. ">", Batched(Warband.MakePeace, guild))
        else
            root:CreateButton("War on <" .. name .. ">", Batched(Warband.DeclareWar, guild))
        end
    end
end

local function AddMenuEntries(_, root, contextData)
    if not Active then
        return
    end
    local info = MenuSubject(contextData)
    if not info or info.key == Warband.MyKey() then
        return
    end
    root:CreateDivider()
    Warband.MenuEntries(root, info)
end

local function AddTooltipLines(tooltip)
    if not Active or tooltip ~= GameTooltip then
        return
    end
    local _, unit = tooltip:GetUnit()
    if issecretvalue(unit) or not unit then
        return
    end
    local info = Warband.Identify(unit)
    if not info then
        return
    end
    local key = info.key
    local status = Warband.Status(key, info.guild)
    local ledger, people = Warband.Ledger, Warband.People
    if status == "glory" then
        local by = ledger:Field(key, "by")
        tooltip:AddLine(Warband.Labels.glory .. (by ~= "" and (" (" .. by .. ")") or ""), 0.25, 0.75, 1)
    elseif status == "war" then
        tooltip:AddLine(Warband.Labels.war .. ": <" .. Warband.GuildName(info.guild) .. ">", 1, 0.5, 0)
    elseif status then
        local by = status == "mark" and ledger:Field(key, "by") or ""
        tooltip:AddLine(Warband.Labels[status] .. (by ~= "" and (" (" .. by .. ")") or ""), 1, 0.25, 0.125)
    end
    if people:Has(key) and (status or people:Field(key, "kills") + people:Field(key, "deaths") > 0) then
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
