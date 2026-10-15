local addonName, ns = ...

-- Calibration probes about the client itself and the world around the player: chat colors and
-- strings, fonts, realm, faction, guild, map, quest dialogs and the quest log, text to speech, XP,
-- resting and flights, bags, vendors and trainers, the controller, and the textures the addons draw.
-- Probes.lua's header is the contract; ProbeNeeds.lua defines the needs named here.

-- Every texture the addons draw (TheLanKrewToolKit's views, cards and ScholarPictures' ItemIcons),
-- for textures.used; keep it in step with those files. MissingTexture names no file, so its
-- answer shows what a missing file looks like.
local TexturePaths = {
    "Interface\\Buttons\\WHITE8X8",
    "Interface\\Tooltips\\UI-Tooltip-Border",
    "Interface\\TargetingFrame\\UI-StatusBar",
    "Interface\\CharacterFrame\\TempPortraitAlphaMask",
    "Interface\\Common\\VoiceChat-Speaker",
    "Interface\\RAIDFRAME\\ReadyCheck-Ready",
    "Interface\\RAIDFRAME\\ReadyCheck-NotReady",
    "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
    "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2",
    "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",
    "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4",
    "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5",
    "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
    "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",
    "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
    "Interface\\Icons\\Ability_Hunter_Pet_Owl",
    "Interface\\Icons\\INV_Misc_Book_09",
    "Interface\\Icons\\Spell_Holy_SurgeOfLight",
    "Interface\\Icons\\Ability_Warrior_BattleShout",
    "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend",
    "Interface\\Icons\\Ability_Rogue_Eviscerate",
    "Interface\\Icons\\Ability_Warrior_Rampage",
    "Interface\\Icons\\Ability_Hunter_MarkedForDeath",
    "Interface\\Icons\\Achievement_PVP_H_01",
    "Interface\\Icons\\Ability_Hunter_SniperShot",
    "Interface\\Icons\\INV_Misc_Food_19",
    "Interface\\Icons\\INV_Misc_Fish_02",
    "Interface\\Icons\\INV_Misc_Gem_Ruby_01",
    "Interface\\Icons\\INV_Potion_51",
    "Interface\\Icons\\INV_Ammo_Arrow_02",
    "Interface\\Icons\\INV_Scroll_03",
    "Interface\\Icons\\INV_Mushroom_11",
    "Interface\\Icons\\INV_Misc_Gear_01",
}
local MissingTexture = "Interface\\ByteTerrace\\NoSuchTexture"

-- The labelStyle values ByteTerrace_Core/Input.lua has labels for (its Labels table).
local KnownLabelStyles = { Letters = true, Shapes = true, Reverse = true }

local Probes = ns.Probes
local Marker, Value, Shape, Text = Probes.Marker, Probes.Value, Probes.Shape, Probes.Text
local Byte, Fields, Joined = Probes.Byte, Probes.Fields, Probes.Joined
local FirstBagItem = Probes.FirstBagItem

-- textures.used's frame (made on its first run) and its texture per path.
local TextureFrame
local Textures = {}

-- The quest log's first quest (not a header) and its log index, or nil; and whether a header
-- came before it.
local function FirstQuest()
    local sawHeader = false
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and info.isHeader then
            sawHeader = true
        elseif info then
            return info, i, sawHeader
        end
    end
    return nil, nil, sawHeader
end

-- The open quest dialog's GetQuestID and its NPC's name (UnitName("questnpc"), what QuestFrame
-- titles itself with), as shapes.
local function QuestIdentity()
    local questID = GetQuestID()
    local questNpc = UnitName("questnpc") -- secret: recorded by Shape as a marker
    return {
        questID = Shape(questID), questNpcName = Shape(questNpc),
        hasQuestID = not issecretvalue(questID) and type(questID) == "number" and questID > 0,
    }
end

-- What SetTexture answers for a path on a hidden texture of its own, and what the texture reports
-- afterwards.
local function TextureAnswer(path)
    local texture = Textures[path]
    if not texture then
        if not TextureFrame then
            TextureFrame = CreateFrame("Frame")
            TextureFrame:Hide()
        end
        texture = TextureFrame:CreateTexture()
        Textures[path] = texture
    end
    local set = texture:SetTexture(path)
    local fileID = texture:GetTextureFileID()
    return {
        set = Value(set), fileID = Shape(fileID),
        hasFileID = not issecretvalue(fileID) and type(fileID) == "number" and fileID ~= 0,
        filePath = Text(texture:GetTextureFilePath()),
    }
end

Probes.Define({
    {
        name = "chatTypeInfo.raidWarning",
        needs = {},
        run = function()
            local info = ChatTypeInfo.RAID_WARNING
            return {
                r = Byte(info.r), g = Byte(info.g), b = Byte(info.b), sticky = Value(info.sticky),
                hasMetatable = getmetatable(ChatTypeInfo) ~= nil,
            }
        end,
    },
    {
        name = "globalStrings.honor",
        needs = { "enUS" },
        run = function()
            return {
                COMBATLOG_HONORGAIN = COMBATLOG_HONORGAIN, COMBATLOG_HONORGAIN_NO_RANK = COMBATLOG_HONORGAIN_NO_RANK,
                COMBATLOG_HONORAWARD = COMBATLOG_HONORAWARD,
            }
        end,
    },
    {
        name = "classColors",
        needs = {},
        run = function()
            local classes, colorStr = {}, {}
            for className, color in pairs(RAID_CLASS_COLORS) do
                classes[#classes + 1] = className
                colorStr[className] = Value(color.colorStr)
            end
            table.sort(classes)
            return { classes = table.concat(classes, ","), colorStr = colorStr }
        end,
    },
    {
        name = "fonts.scholar",
        needs = {},
        harness = "the harness has no font objects (ScholarView names them only as templates)",
        run = function()
            local function ObjectType(font)
                return type(font) == "table" and font:GetObjectType() or type(font)
            end
            return { Game18Font = ObjectType(Game18Font), Game24Font = ObjectType(Game24Font), Game30Font = ObjectType(Game30Font) }
        end,
    },
    {
        name = "realm.normalized",
        needs = {},
        -- Both names are plain strings once the player can type (neither API has secret flags).
        run = function()
            local normalized, realm = GetNormalizedRealmName(), GetRealmName()
            return {
                normalized = Shape(normalized), realm = Shape(realm), hasSpaceOrHyphen = normalized:find("[%s%-]") ~= nil,
                isRealmWithoutSpacesOrHyphens = normalized == (realm:gsub("[%s%-]", "")),
            }
        end,
    },
    {
        name = "faction.player",
        needs = {},
        run = function()
            local group, localized = UnitFactionGroup("player")
            local known = group == "Alliance" or group == "Horde"
            return {
                group = Shape(group), localized = Shape(localized), isAllianceOrHorde = known,
                localizedIsGlobalString = known and localized == (group == "Alliance" and FACTION_ALLIANCE or FACTION_HORDE),
            }
        end,
    },
    {
        name = "guild.player",
        needs = { "guild" },
        run = function()
            local guildName, rankName, rankIndex, realm = GetGuildInfo("player")
            return { guildName = Shape(guildName), rankName = Shape(rankName), rankIndex = Shape(rankIndex), realm = Shape(realm) }
        end,
    },
    {
        name = "map.player",
        needs = { "openWorld" },
        run = function()
            local mapID = C_Map.GetBestMapForUnit("player")
            local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
            local result = { mapID = Shape(mapID), position = Shape(position), instanceType = Value(select(2, IsInInstance())) }
            if type(position) == "table" then
                result.hasGetXY = type(position.GetXY) == "function"
                if result.hasGetXY then
                    local x, y = position:GetXY()
                    result.inUnitSquare = type(x) == "number" and type(y) == "number" and x >= 0 and x <= 1 and y >= 0 and y <= 1
                end
            end
            return result
        end,
    },
    {
        name = "chat.lockdownIdle",
        needs = { "idle" },
        run = function()
            return { inChatMessagingLockdown = Value(C_ChatInfo.InChatMessagingLockdown()) }
        end,
    },
    {
        name = "tts.voices",
        needs = {},
        run = function()
            local voices = C_VoiceChat.GetTtsVoices()
            local first = type(voices) == "table" and voices[1] or nil
            return {
                voices = Shape(voices), hasVoices = first ~= nil, fields = first and Fields(first) or nil,
                voiceID = first and Shape(first.voiceID) or nil, voiceName = first and Shape(first.name) or nil,
            }
        end,
    },
    {
        name = "xp.player",
        needs = {},
        run = function()
            local exhaustion = GetXPExhaustion()
            local exhaustionShape = issecretvalue(exhaustion) and Marker(exhaustion)
                or ((exhaustion == nil or type(exhaustion) == "number") and "number or nil" or type(exhaustion))
            return { xp = Shape(UnitXP("player")), xpMax = Shape(UnitXPMax("player")), exhaustion = exhaustionShape }
        end,
    },
    {
        -- DBM checks external sounds with C_UIFileAsset.IsKnownFile before playing them; this asks
        -- whether it knows loose files in an addon's folder, a shipped file, and a missing one.
        name = "sound.knownFile",
        needs = {},
        harness = "the harness doesn't know which files the client has",
        run = function()
            local known = C_UIFileAsset.IsKnownFile
            return {
                addonLua = Value(known("Interface\\AddOns\\ByteTerrace_DevTools\\DevTools.lua")),
                addonToc = Value(known("Interface\\AddOns\\ByteTerrace_DevTools\\ByteTerrace_DevTools_Camelot.toc")),
                shipped = Value(known("Interface\\Buttons\\WHITE8X8")),
                missing = Value(known("Interface\\AddOns\\ByteTerrace_DevTools\\NoSuchFile.ogg")),
            }
        end,
    },
    {
        name = "textures.used",
        needs = {},
        harness = "the harness doesn't know which texture files the client has",
        run = function()
            local result = { [MissingTexture] = TextureAnswer(MissingTexture) }
            for _, path in ipairs(TexturePaths) do
                result[path] = TextureAnswer(path)
            end
            return result
        end,
    },
    {
        name = "quest.offer",
        needs = { "questOffer" },
        run = function()
            return { title = Text(GetTitleText()), questText = Text(GetQuestText()), objectiveText = Text(GetObjectiveText()) }
        end,
    },
    {
        name = "quest.turnIn",
        needs = { "questTurnIn" },
        run = function()
            return { title = Text(GetTitleText()), rewardText = Text(GetRewardText()) }
        end,
    },
    {
        name = "quest.offerIdentity",
        needs = { "questOffer" },
        run = function()
            local result = QuestIdentity()
            local npc = UnitName("npc") -- secret: recorded by Shape as a marker
            result.npcName = Shape(npc)
            return result
        end,
    },
    {
        name = "quest.turnInIdentity",
        needs = { "questTurnIn" },
        run = QuestIdentity,
    },
    {
        name = "questLog.entry",
        needs = { "questLog" },
        run = function()
            local numShownEntries, numQuests = C_QuestLog.GetNumQuestLogEntries()
            local info, _, sawHeader = FirstQuest()
            local quest = info or {}
            return {
                numShownEntries = Shape(numShownEntries), numQuests = Shape(numQuests), hasHeader = sawHeader,
                info = Fields(info), isHeader = Shape(quest.isHeader), questID = Shape(quest.questID),
                title = Text(quest.title), level = Shape(quest.level),
            }
        end,
    },
    {
        name = "questLog.objectives",
        needs = { "questLog" },
        accumulates = true,
        run = function()
            local first, types = nil, {}
            for i = 1, C_QuestLog.GetNumQuestLogEntries() do
                local info = C_QuestLog.GetInfo(i)
                if info and not info.isHeader then
                    for _, objective in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                        first = first or objective
                        if not issecretvalue(objective.type) and type(objective.type) == "string" then
                            types[objective.type] = true
                        end
                    end
                end
            end
            if not first then
                return { hasObjectives = false }
            end
            return {
                hasObjectives = true, fields = Fields(first), text = Text(first.text), type = Text(first.type),
                numFulfilled = Shape(first.numFulfilled), numRequired = Shape(first.numRequired),
                finished = Shape(first.finished), objectiveType = Shape(first.objectiveType), types = Joined(types),
            }
        end,
    },
    {
        -- Where objective texts put their count: "leading" ("0/8 Wolf Pelt"), "trailing" ("Wolf
        -- Pelt: 0/8") or "none", over every objective in the log.
        name = "questLog.countForm",
        needs = { "questLog" },
        accumulates = true,
        run = function()
            local forms = {}
            for i = 1, C_QuestLog.GetNumQuestLogEntries() do
                local info = C_QuestLog.GetInfo(i)
                if info and not info.isHeader then
                    for _, objective in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                        local text = objective.text
                        if not issecretvalue(text) and type(text) == "string" then
                            forms[text:find("^%d+/%d+ ") and "leading" or text:find(": %d+/%d+$") and "trailing"
                                or "none"] = true
                        end
                    end
                end
            end
            return { forms = Joined(forms) }
        end,
    },
    {
        name = "questLog.text",
        needs = { "questLog" },
        run = function()
            local info, index = FirstQuest()
            if not info then
                return { quest = "none" }
            end
            -- The log index form, as QuestMapFrame calls it: it doesn't touch the selected quest.
            local description, objectives = GetQuestLogQuestText(index)
            return {
                description = Text(description), objectives = Text(objectives),
                titleForQuestID = Text(C_QuestLog.GetTitleForQuestID(info.questID)),
                selectedQuest = Shape(C_QuestLog.GetSelectedQuest()),
            }
        end,
    },
    {
        name = "bags.firstItem",
        needs = { "bagItem" },
        run = function()
            local info = FirstBagItem()
            local itemID = info.itemID
            local result = {
                fields = Fields(info), itemID = Shape(itemID), stackCount = Shape(info.stackCount),
                hyperlink = Text(info.hyperlink), itemName = Text(info.itemName), iconFileID = Shape(info.iconFileID),
            }
            if issecretvalue(itemID) or type(itemID) ~= "number" then
                return result
            end
            result.maxStackSize = Shape(C_Item.GetItemMaxStackSizeByID(itemID))
            result.itemInfoReturns = select("#", C_Item.GetItemInfo(itemID))
            result.itemStackCount = Shape((select(8, C_Item.GetItemInfo(itemID))))
            result.sellPrice = Shape((select(11, C_Item.GetItemInfo(itemID))))
            return result
        end,
    },
    {
        name = "merchant.firstItem",
        needs = { "merchant" },
        run = function()
            local info = C_MerchantFrame.GetItemInfo(1)
            local item = type(info) == "table" and info or {}
            return {
                numItems = Shape(GetMerchantNumItems()), info = Shape(info), fields = Fields(info), name = Text(item.name),
                price = Shape(item.price), stackCount = Shape(item.stackCount), numAvailable = Shape(item.numAvailable),
                isPurchasable = Shape(item.isPurchasable), hasExtendedCost = Shape(item.hasExtendedCost),
                texture = Shape(item.texture),
            }
        end,
    },
    {
        name = "trainer.services",
        needs = { "trainer" },
        -- Forever's GetTrainerServiceInfo returns name, serviceType ("available", "unavailable",
        -- "used"), texture, reqLevel, serviceSubText, category, and GetTrainerServiceCost returns
        -- moneyCost, isProfession (Blizzard_TrainerUI/Mainline/Blizzard_TrainerUI.lua).
        run = function()
            local count = GetNumTrainerServices()
            local serviceTypes, available = {}, nil
            if not issecretvalue(count) and type(count) == "number" then
                for i = 1, count do
                    local _, serviceType = GetTrainerServiceInfo(i)
                    if not issecretvalue(serviceType) and type(serviceType) == "string" then
                        serviceTypes[serviceType] = true
                        available = available or (serviceType == "available" and i or nil)
                    end
                end
            end
            local result = { count = Shape(count), serviceTypes = Joined(serviceTypes),
                greeting = Text(GetTrainerGreetingText()), isTradeskill = Shape(IsTradeskillTrainer()),
                trainerType = Shape(C_Trainer.GetTrainerType()), hasAvailable = available ~= nil }
            if available then
                local name, _, texture, reqLevel, subText, category = GetTrainerServiceInfo(available)
                local moneyCost, isProfession = GetTrainerServiceCost(available)
                result.name, result.texture, result.reqLevel = Text(name), Shape(texture), Shape(reqLevel)
                result.subText, result.category = Text(subText), Shape(category)
                result.moneyCost, result.isProfession = Shape(moneyCost), Shape(isProfession)
                result.description = Text(GetTrainerServiceDescription(available))
            end
            return result
        end,
    },
    {
        name = "gamePad.device",
        needs = { "controller" },
        run = function()
            local deviceID = C_GamePad.GetActiveDeviceID()
            local state = C_GamePad.GetDeviceMappedState(deviceID)
            local style = type(state) == "table" and state.labelStyle or nil
            local known = not issecretvalue(style) and type(style) == "string" and KnownLabelStyles[style] == true
            return {
                deviceID = Shape(deviceID), state = Shape(state), fields = Fields(state), labelStyle = Text(style),
                isKnownLabelStyle = known, unknownLabelStyle = not known and Value(style) or nil,
            }
        end,
    },
    {
        name = "gamePad.settings",
        needs = { "controller" },
        harness = "the harness doesn't fake IsGamePadFreelookEnabled or C_GamePad.IsEnabled",
        run = function()
            return { freelook = Shape(IsGamePadFreelookEnabled()), enabled = Shape(C_GamePad.IsEnabled()) }
        end,
    },
    {
        name = "resting.player",
        needs = { "resting" },
        run = function() return { isResting = Shape(IsResting()) } end,
    },
    {
        name = "taxi.player",
        needs = { "onTaxi" },
        run = function() return { onTaxi = Shape(UnitOnTaxi("player")) } end,
    },
})
