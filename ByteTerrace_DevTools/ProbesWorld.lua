local addonName, ns = ...

-- Calibration probes about the client itself and the world around the player: chat colors and strings, addon messages,
-- fonts, realm, faction, guild, map, quest dialogs and the quest log, text to speech, XP, resting and flights, bags,
-- vendors and trainers, and the textures the addons draw. Probes.lua's header is the contract, and ProbeNeeds.lua
-- defines the needs named here.

-- Every texture the addons draw (TheLanKrewToolKit's views, cards and ScholarPictures' ItemIcons), for textures.used.
-- Keep it in step with those files. MissingTexture names no file, so its answer shows what a missing file looks like.
local MissingTexture = "Interface\\ByteTerrace\\NoSuchTexture"

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

local Probes = ns.Probes
local Byte = Probes.Byte
local Fields = Probes.Fields
local FirstBagItem = Probes.FirstBagItem
local Joined = Probes.Joined
local Marker = Probes.Marker
local Shape = Probes.Shape
local Text = Probes.Text
local Value = Probes.Value

-- textures.used's frame (made on its first run) and its texture per path.
local TextureFrame
local Textures = {}

-- Returns the quest log's first quest (not a header) and its log index, or nil, and whether a header came before it.
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

-- Returns the open quest dialog's GetQuestID and its NPC's name (UnitName("questnpc"), what QuestFrame titles itself
-- with), as shapes.
local function QuestIdentity()
    local questID = GetQuestID()
    -- secret: recorded by Shape as a marker
    local questNpc = UnitName("questnpc")

    return {
        hasQuestID = (not issecretvalue(questID) and (type(questID) == "number") and (questID > 0)),
        questID = Shape(questID), questNpcName = Shape(questNpc),
    }
end

-- Returns a number's sign ("positive", "zero", or "negative"), its type when it isn't one, or the marker for a secret.
local function Sign(value)
    if issecretvalue(value) then
        return Marker(value)
    elseif type(value) ~= "number" then
        return type(value)
    end

    return (((value > 0) and "positive") or ((value < 0) and "negative") or "zero")
end

-- Returns what SetTexture answers for a path on a hidden texture of its own, and what the texture reports afterwards.
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
        fileID = Shape(fileID), filePath = Text(texture:GetTextureFilePath()),
        hasFileID = (not issecretvalue(fileID) and (type(fileID) == "number") and (fileID ~= 0)), set = Value(set),
    }
end

Probes.Define({
    {
        name = "chatTypeInfo.raidWarning",
        needs = {},
        run = function()
            local info = ChatTypeInfo.RAID_WARNING

            return {
                b = Byte(info.b), g = Byte(info.g), hasMetatable = (getmetatable(ChatTypeInfo) ~= nil),
                r = Byte(info.r), sticky = Value(info.sticky),
            }
        end,
    },
    {
        name = "globalStrings.honor",
        needs = { "enUS" },
        run = function()
            return {
                COMBATLOG_HONORAWARD = COMBATLOG_HONORAWARD, COMBATLOG_HONORGAIN = COMBATLOG_HONORGAIN,
                COMBATLOG_HONORGAIN_NO_RANK = COMBATLOG_HONORGAIN_NO_RANK,
            }
        end,
    },
    {
        name = "classColors",
        needs = {},
        run = function()
            local classes = {}
            local colorStr = {}

            for className, color in pairs(RAID_CLASS_COLORS) do
                classes[#classes + 1] = className
                colorStr[className] = Value(color.colorStr)
            end

            table.sort(classes)

            return { classes = table.concat(classes, ","), colorStr = colorStr }
        end,
    },
    {
        harness = "the harness has no font objects (ScholarView names them only as templates)",
        name = "fonts.scholar",
        needs = {},
        run = function()
            local function ObjectType(font)
                return (((type(font) == "table") and font:GetObjectType()) or type(font))
            end

            return { Game18Font = ObjectType(Game18Font), Game24Font = ObjectType(Game24Font), Game30Font = ObjectType(Game30Font) }
        end,
    },
    {
        name = "realm.normalized",
        needs = {},
        -- Both names are plain strings once the player can type (neither API has secret flags).
        run = function()
            local normalized = GetNormalizedRealmName()
            local realm = GetRealmName()

            return {
                hasSpaceOrHyphen = (normalized:find("[%s%-]") ~= nil),
                isRealmWithoutSpacesOrHyphens = (normalized == (realm:gsub("[%s%-]", ""))),
                normalized = Shape(normalized), realm = Shape(realm),
            }
        end,
    },
    {
        name = "faction.player",
        needs = {},
        run = function()
            local group, localized = UnitFactionGroup("player")
            local known = ((group == "Alliance") or (group == "Horde"))

            return {
                group = Shape(group), isAllianceOrHorde = known, localized = Shape(localized),
                localizedIsGlobalString = (known and (localized == (((group == "Alliance") and FACTION_ALLIANCE) or FACTION_HORDE))),
            }
        end,
    },
    {
        -- What GetGuildInfo("player") answers. Its realm is "empty", "normalized" (GetNormalizedRealmName's form),
        -- "display" (GetRealmName's), "other", or a secret marker: WarbandUtil's guild keys add your normalized realm
        -- to an empty one, so a display name here would file your own guild under a second key.
        name = "guild.player",
        needs = { "guild" },
        run = function()
            local guildName, rankName, rankIndex, realm = GetGuildInfo("player")
            local form = Text(realm)

            if form == "text" then
                -- secret: Text checked realm with issecretvalue, so it's a plain string here
                form = (((realm == GetNormalizedRealmName()) and "normalized") or ((realm == GetRealmName()) and "display")
                    or "other")
            end

            return { guildName = Shape(guildName), rankIndex = Shape(rankIndex), rankName = Shape(rankName), realm = form }
        end,
        version = 2,
    },
    {
        name = "map.player",
        needs = { "openWorld" },
        run = function()
            local mapID = C_Map.GetBestMapForUnit("player")
            local position = (mapID and C_Map.GetPlayerMapPosition(mapID, "player"))
            local result = { instanceType = Value(select(2, IsInInstance())), mapID = Shape(mapID), position = Shape(position) }

            if type(position) == "table" then
                result.hasGetXY = (type(position.GetXY) == "function")

                if result.hasGetXY then
                    local x, y = position:GetXY()

                    result.inUnitSquare = ((type(x) == "number") and (type(y) == "number") and (x >= 0) and (x <= 1) and (y >= 0) and (y <= 1))
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
        accumulates = true,
        harness = "it asks whether others' addon messages arrive; h:ReceiveAddonMessage sends what a test says",
        -- Whether CHAT_MSG_ADDON arrives during a restriction, and whether any field is secret then (its docs give it
        -- no secret flags, but ByteTerrace_Core's Comms.lua guards it anyway): heard holds each field's shapes per
        -- restriction text a message came under, and restrictionsSeen every restriction active since load, so one seen
        -- with no messages heard under it says none arrived.
        name = "comms.addonMessageInLockdown",
        needs = { "messagingRestricted" },
        run = function()
            return { heard = Probes.JoinSets(Probes.AddonMessages), restrictionsSeen = Joined(Probes.Restricted.seen) }
        end,
    },
    {
        name = "tts.voices",
        needs = {},
        run = function()
            local voices = C_VoiceChat.GetTtsVoices()
            local first = (((type(voices) == "table") and voices[1]) or nil)

            return {
                fields = ((first and Fields(first)) or nil), hasVoices = (first ~= nil),
                voiceID = ((first and Shape(first.voiceID)) or nil), voiceName = ((first and Shape(first.name)) or nil),
                voices = Shape(voices),
            }
        end,
    },
    {
        name = "xp.player",
        needs = {},
        run = function()
            local exhaustion = GetXPExhaustion()

            local exhaustionShape = ((issecretvalue(exhaustion) and Marker(exhaustion))
                or ((((exhaustion == nil) or (type(exhaustion) == "number")) and "number or nil") or type(exhaustion)))

            return { exhaustion = exhaustionShape, xp = Shape(UnitXP("player")), xpMax = Shape(UnitXPMax("player")) }
        end,
    },
    {
        harness = "the harness doesn't model XP at the max level (UnitXPMax answers whatever a test set)",
        -- What UnitXP and UnitXPMax answer once there's no next level: TheLanKrewToolKit's Journal.lua takes a
        -- UnitXPMax of 0 or less as no rested percentage.
        name = "xp.atMaxLevel",
        needs = { "maxLevel" },
        run = function()
            return { xp = Sign(UnitXP("player")), xpMax = Sign(UnitXPMax("player")) }
        end,
    },
    {
        harness = "the harness doesn't know which files the client has",
        -- DBM checks external sounds with C_UIFileAsset.IsKnownFile before playing them. This asks whether it knows
        -- loose files in an addon's folder, a shipped file, and a missing one.
        name = "sound.knownFile",
        needs = {},
        run = function()
            local known = C_UIFileAsset.IsKnownFile

            return {
                addonLua = Value(known("Interface\\AddOns\\ByteTerrace_DevTools\\DevTools.lua")),
                addonToc = Value(known("Interface\\AddOns\\ByteTerrace_DevTools\\ByteTerrace_DevTools_Camelot.toc")),
                missing = Value(known("Interface\\AddOns\\ByteTerrace_DevTools\\NoSuchFile.ogg")),
                shipped = Value(known("Interface\\Buttons\\WHITE8X8")),
            }
        end,
    },
    {
        harness = "the harness doesn't know which texture files the client has",
        name = "textures.used",
        needs = {},
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
            return { objectiveText = Text(GetObjectiveText()), questText = Text(GetQuestText()), title = Text(GetTitleText()) }
        end,
    },
    {
        name = "quest.turnIn",
        needs = { "questTurnIn" },
        run = function()
            return { rewardText = Text(GetRewardText()), title = Text(GetTitleText()) }
        end,
    },
    {
        name = "quest.offerIdentity",
        needs = { "questOffer" },
        run = function()
            local result = QuestIdentity()
            -- secret: recorded by Shape as a marker
            local npc = UnitName("npc")

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
            local quest = (info or {})

            return {
                hasHeader = sawHeader, info = Fields(info), isHeader = Shape(quest.isHeader),
                level = Shape(quest.level), numQuests = Shape(numQuests), numShownEntries = Shape(numShownEntries),
                questID = Shape(quest.questID), title = Text(quest.title),
            }
        end,
    },
    {
        accumulates = true,
        name = "questLog.objectives",
        needs = { "questLog" },
        run = function()
            local first = nil
            local types = {}

            for i = 1, C_QuestLog.GetNumQuestLogEntries() do
                local info = C_QuestLog.GetInfo(i)

                if info and not info.isHeader then
                    for _, objective in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                        first = (first or objective)

                        if not issecretvalue(objective.type) and (type(objective.type) == "string") then
                            types[objective.type] = true
                        end
                    end
                end
            end

            if not first then
                return { hasObjectives = false }
            end

            return {
                fields = Fields(first), finished = Shape(first.finished), hasObjectives = true,
                numFulfilled = Shape(first.numFulfilled), numRequired = Shape(first.numRequired),
                objectiveType = Shape(first.objectiveType), text = Text(first.text), type = Text(first.type),
                types = Joined(types),
            }
        end,
    },
    {
        accumulates = true,
        -- Where objective texts put their count: "leading" ("0/8 Wolf Pelt"), "trailing" ("Wolf Pelt: 0/8"), or "none",
        -- over every objective in the log.
        name = "questLog.countForm",
        needs = { "questLog" },
        run = function()
            local forms = {}

            for i = 1, C_QuestLog.GetNumQuestLogEntries() do
                local info = C_QuestLog.GetInfo(i)

                if info and not info.isHeader then
                    for _, objective in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                        local text = objective.text

                        if not issecretvalue(text) and (type(text) == "string") then
                            forms[(text:find("^%d+/%d+ ") and "leading") or (text:find(": %d+/%d+$") and "trailing")
                                or "none"] = true
                        end
                    end
                end
            end

            return { forms = Joined(forms) }
        end,
    },
    {
        accumulates = true,
        -- What C_QuestLog.ReadyForTurnIn answers for each quest in the log, by its objectives: "finished" (all done),
        -- "unfinished", "none" (a quest without objectives), or "secret", then a colon and the answer's shape ("true",
        -- "false", "nil", or "secret"). QuestProgress.lua's ready quests rest on the harness's guess that it's true
        -- exactly when every objective is finished.
        name = "questLog.readyForTurnIn",
        needs = { "questLog" },
        run = function()
            local answers = {}

            for i = 1, C_QuestLog.GetNumQuestLogEntries() do
                local info = C_QuestLog.GetInfo(i)

                if info and not info.isHeader then
                    local objectives = (C_QuestLog.GetQuestObjectives(info.questID) or {})
                    local done = (((#objectives == 0) and "none") or "finished")

                    for _, objective in ipairs(objectives) do
                        if issecretvalue(objective.finished) then
                            done = "secret"
                        elseif (done ~= "secret") and not objective.finished then
                            done = "unfinished"
                        end
                    end

                    local ready = C_QuestLog.ReadyForTurnIn(info.questID)

                    answers[done .. ":" .. ((issecretvalue(ready) and "secret") or tostring(ready))] = true
                end
            end

            return { answers = Joined(answers) }
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
                selectedQuest = Shape(C_QuestLog.GetSelectedQuest()),
                titleForQuestID = Text(C_QuestLog.GetTitleForQuestID(info.questID)),
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
                fields = Fields(info), hyperlink = Text(info.hyperlink), iconFileID = Shape(info.iconFileID),
                itemID = Shape(itemID), itemName = Text(info.itemName), stackCount = Shape(info.stackCount),
            }

            if issecretvalue(itemID) or (type(itemID) ~= "number") then
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
            local item = (((type(info) == "table") and info) or {})

            return {
                fields = Fields(info), hasExtendedCost = Shape(item.hasExtendedCost), info = Shape(info),
                isPurchasable = Shape(item.isPurchasable), name = Text(item.name),
                numAvailable = Shape(item.numAvailable), numItems = Shape(GetMerchantNumItems()),
                price = Shape(item.price), stackCount = Shape(item.stackCount), texture = Shape(item.texture),
            }
        end,
    },
    {
        name = "trainer.services",
        needs = { "trainer" },
        -- Forever's GetTrainerServiceInfo returns name, serviceType ("available", "unavailable", or "used"), texture,
        -- reqLevel, serviceSubText, and category, and GetTrainerServiceCost returns moneyCost and isProfession
        -- (Blizzard_TrainerUI/Mainline/Blizzard_TrainerUI.lua).
        run = function()
            local count = GetNumTrainerServices()
            local serviceTypes = {}
            local available = nil

            if not issecretvalue(count) and (type(count) == "number") then
                for i = 1, count do
                    local _, serviceType = GetTrainerServiceInfo(i)

                    if not issecretvalue(serviceType) and (type(serviceType) == "string") then
                        serviceTypes[serviceType] = true
                        available = (available or (((serviceType == "available") and i) or nil))
                    end
                end
            end

            local result = { count = Shape(count), greeting = Text(GetTrainerGreetingText()),
                hasAvailable = (available ~= nil), isTradeskill = Shape(IsTradeskillTrainer()),
                serviceTypes = Joined(serviceTypes), trainerType = Shape(C_Trainer.GetTrainerType()) }

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
