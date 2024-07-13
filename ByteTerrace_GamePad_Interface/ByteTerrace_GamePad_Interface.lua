if (nil == ByteTerrace.GamePad) then
    ByteTerrace.GamePad = {}
end

---@type string
local addOnName = select(1, ...)
local jumpButton = CreateFrame("Button", "ByteTerraceGamePadJumpButton", UIParent, "ActionButtonTemplate, SecureActionButtonTemplate")
local secureHeader = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")

local ActionButton_OverrideRangeIndicator
local Events_OnGamePadActiveChanged
local Events_OnPlayerEnteringWorld
local Events_OnPlayerFlagsChanged
local Events_OnPlayerRegenDisabled
local Events_OnPlayerRegenEnabled
local GamePad_InitializeUserInterface
local Player_GetStatusIndicatorColor
local System_GetAddOnSettings
local System_GetDefaultAddOnSettings
local System_SetAddOnSettings

ActionButton_OverrideRangeIndicator = function(self, actionButtonType)
    local gamePadIcon = self.gamePadIcon
    local hotKey = self.HotKey

    if ((nil ~= gamePadIcon) and (nil ~= hotKey)) then
        local _, _, _, offsetX, offsetY = gamePadIcon.texture:GetPoint()

        if ((0 == offsetX) and (0 == offsetY)) then
            offsetY = (System_GetAddOnSettings().GamePad.ActionBars.ButtonSize * 0.4375)
        end

        hotKey:ClearAllPoints()
        hotKey:Hide()
        hotKey:SetDrawLayer("OVERLAY")
        hotKey:SetJustifyH("CENTER")
        hotKey:SetJustifyV("MIDDLE")
        hotKey:SetParent(gamePadIcon)
        hotKey:SetPoint("CENTER", ((offsetX * 0.3) + 0.5), (offsetY * 0.3))
        hotKey:SetScale(1.25)
        hotKey:SetText(_G["RANGE_INDICATOR"])
    end
end
Events_OnGamePadActiveChanged = function ()
    local addonSettings = System_GetAddOnSettings()
    local gamePadButtons = addonSettings.GamePad.Buttons
    local gamePadType = "Generic"
    local iconTextureMap = ByteTerrace.GamePad.IconTextureMap
    local themeBasePath = ("Interface/AddOns/" .. addOnName .. "/Assets/Themes/juliocacko_alt")

    for deviceId in ipairs(C_GamePad:GetAllDeviceIDs()) do
        local _, rawState = pcall(C_GamePad.GetDeviceRawState, deviceId)

        if (nil ~= rawState) then
            local deviceType = addonSettings.GamePad.VendorIdMap[rawState.vendorID]

            if ("DualSense" == deviceType) then
                gamePadButtons.Select.Binding = "PADSOCIAL"
                gamePadType = "Sony PlayStation"
            elseif ("NintendoSwitchPro" == deviceType) then
                gamePadButtons.Select.Binding = "PADBACK"
                gamePadType = "Nintendo Switch"
            elseif ("XboxSeriesX" == deviceType) then
                gamePadButtons.Select.Binding = "PADBACK"
                gamePadType = "Microsoft Xbox"
            end
        end
    end

    iconTextureMap[0] = (themeBasePath .. "/Generic/dpad_up")
    iconTextureMap[1] = (themeBasePath .. "/Generic/dpad_right")
    iconTextureMap[2] = (themeBasePath .. "/Generic/dpad_down")
    iconTextureMap[3] = (themeBasePath .. "/Generic/dpad_left")
    iconTextureMap[4] = (themeBasePath .. "/" .. gamePadType .. "/l1")
    iconTextureMap[5] = (themeBasePath .. "/Generic/l3")
    iconTextureMap[6] = (themeBasePath .. "/" .. gamePadType .. "/bpad_up")
    iconTextureMap[7] = (themeBasePath .. "/" .. gamePadType .. "/bpad_left")
    iconTextureMap[8] = (themeBasePath .. "/" .. gamePadType .. "/bpad_down")
    iconTextureMap[9] = (themeBasePath .. "/" .. gamePadType .. "/bpad_right")
    iconTextureMap[10] = (themeBasePath .. "/" .. gamePadType .. "/r1")
    iconTextureMap[11] = (themeBasePath .. "/Generic/r3")

    for i = 0, 11 do
        local texture = iconTextureMap[i]

        _G[("ActionButton" .. (i + 1))].gamePadIcon.texture:SetTexture(texture)

        if (8 == i) then
            jumpButton.gamePadIcon.texture:SetTexture(texture)
        end
    end
end
Events_OnPlayerEnteringWorld = function (isInitialLogin, isReloadingUi)
    if (isInitialLogin or isReloadingUi) then
        ---@diagnostic disable-next-line: param-type-mismatch
        UIParent:UnregisterEvent("EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED")

        ByteTerrace.Console.SetVariables(System_GetAddOnSettings().Camera.ConsoleVariables)
    end

    ResetView(5)
    SetView(5)
    CameraZoomOut(50.0)
    CameraZoomIn(1.25)
    SaveView(5)
    Events_OnPlayerFlagsChanged()
end
Events_OnPlayerFlagsChanged = function (unitTarget)
    C_GamePad.SetLedColor(Player_GetStatusIndicatorColor(ByteTerrace.Colors, IsChatAFK(), ByteTerrace.Player.IsInCombat))
end
Events_OnPlayerRegenDisabled = function ()
    ByteTerrace.Player.IsInCombat = true
    C_GamePad.SetVibration("High", 1.0)
    Events_OnPlayerFlagsChanged()
end
Events_OnPlayerRegenEnabled = function ()
    ByteTerrace.Player.IsInCombat = false
    C_GamePad.SetVibration("Low", 0.5)
    Events_OnPlayerFlagsChanged()
end
GamePad_InitializeUserInterface = function (gamePadSettings, jumpButton, parentFrame)
    -- Update frame strata of multi-bar frames so that the gamepad icon has the highest z-index.
    _G["MultiBarBottomLeft"]:SetFrameStrata("LOW")
    _G["MultiBarBottomRight"]:SetFrameStrata("LOW")
    _G["MultiBarLeft"]:SetFrameStrata("LOW")
    _G["MultiBarRight"]:SetFrameStrata("LOW")

    parentFrame:SetPoint("BOTTOM", gamePadSettings.ActionBars.OffsetX, gamePadSettings.ActionBars.OffsetY)

    local buttonSize = gamePadSettings.ActionBars.ButtonSize
    local buttonSizeTimes2 = (buttonSize * 2)
    local buttonSizeTimes3 = (buttonSize * 3)
    local buttonSizeTimes4 = (buttonSize * 4)
    local xPadding = 60
    local yPadding = 0

    for i = 0, 59 do
        local actionBarName = "ActionButton"
        local alpha = gamePadSettings.ActionBars.AlphaWhenActive
        local iMod2 = (i % 2)
        local iMod6 = (i % 6)
        local iMod12 = (i % 12)
        local isReflection = (5 < iMod12)
        local xOffset = (((((1 == iMod6) or (3 == iMod6) or (4 == iMod6)) and ((1 == iMod6) and buttonSizeTimes2 or buttonSizeTimes4) or buttonSizeTimes3) + xPadding) * (isReflection and 1 or -1))
        local yOffset = (((1 == iMod2) and 0 or (buttonSize + yPadding)) * ((((0 == iMod6) or (4 == iMod6))) and 1 or -1))

        if ((i > 11) and (i < 24)) then
            actionBarName = "MultiBarBottomLeftButton"
            alpha = gamePadSettings.ActionBars.AlphaWhenPassive
            xOffset = (xOffset + (buttonSizeTimes2 * (isReflection and 1 or -1)))
            yOffset = (yOffset - buttonSize)
        elseif ((i > 23) and (i < 36)) then
            actionBarName = "MultiBarBottomRightButton"
            alpha = gamePadSettings.ActionBars.AlphaWhenPassive
            xOffset = (xOffset + (buttonSizeTimes3 * (isReflection and -1 or 1)))
            yOffset = yOffset
        elseif ((i > 35) and (i < 48)) then
            actionBarName = "MultiBarLeftButton"
            alpha = gamePadSettings.ActionBars.AlphaWhenPassive
            xOffset = (xOffset + (buttonSizeTimes2 * (isReflection and 1 or -1)))
            yOffset = (yOffset + buttonSizeTimes2)
        elseif ((i > 47) and (i < 60)) then
            actionBarName = "MultiBarRightButton"
            alpha = gamePadSettings.ActionBars.AlphaWhenPassive
            xOffset = (xOffset + (buttonSize * (isReflection and -1 or 1)))
            yOffset = (yOffset + buttonSizeTimes2)
        end

        local actionButton = _G[(actionBarName .. (iMod12 + 1))]

        actionButton:ClearAllPoints()
        actionButton:SetAlpha(alpha)
        actionButton:SetPoint("CENTER", parentFrame, "CENTER", xOffset, yOffset)

        if (i < 12) then
            if (nil == actionButton.gamePadIcon) then
                local gamePadIcon = CreateFrame("Frame", (actionButton:GetName() .. "GamePadIcon"), actionButton)

                gamePadIcon:SetFrameLevel(actionButton:GetFrameLevel() + 1)
                gamePadIcon:SetPoint("CENTER", actionButton, "CENTER", 0, 0)
                gamePadIcon:SetScale(actionButton:GetScale())
                gamePadIcon:SetSize(actionButton:GetSize())

                actionButton.gamePadIcon = gamePadIcon
                gamePadIcon.texture = gamePadIcon:CreateTexture(nil, "OVERLAY")
            end

            local baseOffset = (buttonSize * 0.4375)
            local gamePadIconTexture = actionButton.gamePadIcon.texture
            local gamePadIconTextureOffsetX = (((1 == iMod6) and baseOffset or (((3 == iMod6) or (4 == iMod12) or (10 == iMod12)) and -baseOffset or 0)) * (isReflection and -1 or 1))
            local gamePadIconTextureOffsetY = (((0 == iMod6) or (4 == iMod12) or (10 == iMod12)) and baseOffset or ((2 == iMod6) and -baseOffset or 0))

            gamePadIconTexture:SetAlpha(0.85)
            gamePadIconTexture:SetPoint("CENTER", gamePadIconTextureOffsetX, gamePadIconTextureOffsetY)
            gamePadIconTexture:SetSize(24, 24)

            if ((5 < i) and (10 > i)) then
                gamePadIconTexture:SetMask("Interface/Masks/CircleMaskScalable")
            end

            if ((4 == i) or (8 == i) or (10 == i)) then
                actionButton:Hide()
                actionButton:SetAttribute("statehidden", true);

                if ((8 == i) and (nil ~= jumpButton)) then
                    if (nil == jumpButton.gamePadIcon) then
                        local gamePadIcon = CreateFrame("Frame", (jumpButton:GetName() .. "GamePadIcon"), jumpButton)

                        gamePadIcon:SetFrameLevel(jumpButton:GetFrameLevel() + 1)
                        gamePadIcon:SetPoint("CENTER", jumpButton, "CENTER", 0, 0)
                        gamePadIcon:SetScale(jumpButton:GetScale())
                        gamePadIcon:SetSize(jumpButton:GetSize())

                        jumpButton.gamePadIcon = gamePadIcon
                        gamePadIcon.texture = gamePadIcon:CreateTexture(nil, "OVERLAY")
                    end

                    gamePadIconTexture = jumpButton.gamePadIcon.texture

                    gamePadIconTexture:SetAlpha(0.85)
                    gamePadIconTexture:SetMask("Interface/Masks/CircleMaskScalable")
                    gamePadIconTexture:SetPoint("CENTER", gamePadIconTextureOffsetX, gamePadIconTextureOffsetY)
                    gamePadIconTexture:SetSize(24, 24)
                    jumpButton.icon:SetTexture("Interface/Icons/Ability_Rogue_FleetFooted")
                    jumpButton:SetAllPoints(actionButton)
                    jumpButton:SetScale(actionButton:GetScale())
                    jumpButton:SetSize(actionButton:GetSize())
                end
            end
        end
    end

    if ByteTerrace.System.IsClassic() then
        _G["ActionBarDownButton"]:SetPoint("LEFT", _G["MainMenuBarTexture2"], "LEFT", -(_G["ActionBarDownButton"]:GetWidth() * 0.225), -(_G["ActionBarDownButton"]:GetHeight() * 0.325))
        _G["ActionBarUpButton"]:SetPoint("LEFT", _G["MainMenuBarTexture2"], "LEFT", -(_G["ActionBarUpButton"]:GetWidth() * 0.225), (_G["ActionBarUpButton"]:GetHeight() * 0.265))
        CharacterMicroButton:ClearAllPoints()
        CharacterMicroButton:SetPoint("CENTER", _G["MainMenuBarTexture2"], "CENTER", -(CharacterMicroButton:GetWidth() * 2.575), 9)
        MainMenuBar:SetWidth(MainMenuBar:GetWidth() * 0.5)
        _G["MainMenuBarLeftEndCap"]:Hide()
        _G["MainMenuBarPageNumber"]:SetPoint("LEFT", _G["MainMenuBarTexture2"], "LEFT", (MainMenuBar:GetWidth() * 0.0515), -0.5)
        _G["MainMenuBarRightEndCap"]:Hide()
        _G["MainMenuBarTexture0"]:Hide()
        _G["MainMenuBarTexture1"]:Hide()
        _G["MainMenuBarTexture2"]:SetPoint("CENTER", -(_G["MainMenuBarTexture2"]:GetWidth() * 0.5), 0)
        _G["MainMenuBarTexture3"]:SetPoint("CENTER", (_G["MainMenuBarTexture3"]:GetWidth() * 0.5), 0)
        _G["MainMenuExpBar"]:SetPoint("CENTER", (_G["MainMenuExpBar"]:GetWidth() * 0.5), 0)
        _G["MainMenuExpBar"]:SetWidth(_G["MainMenuExpBar"]:GetWidth() * 0.5)
        _G["ReputationWatchBar"]:SetPoint("CENTER", (_G["ReputationWatchBar"]:GetWidth() * 0.5), 0)
        _G["ReputationWatchBar"]:SetWidth(_G["ReputationWatchBar"]:GetWidth() * 0.5)
        _G["ReputationWatchBar"].StatusBar:SetPoint("CENTER", (_G["ReputationWatchBar"].StatusBar:GetWidth() * 0.5), 0)
        _G["ReputationWatchBar"].StatusBar:SetWidth(_G["ReputationWatchBar"].StatusBar:GetWidth() * 0.5)
        ByteTerrace.UserInterface.ForceHide(_G["MainMenuXPBarTexture0"])
        ByteTerrace.UserInterface.ForceHide(_G["MainMenuXPBarTexture3"])
        ByteTerrace.UserInterface.ForceHide(_G["ReputationWatchBar"].StatusBar.WatchBarTexture2)
        ByteTerrace.UserInterface.ForceHide(_G["ReputationWatchBar"].StatusBar.WatchBarTexture3)
        ByteTerrace.UserInterface.ForceHide(_G["ReputationWatchBar"].StatusBar.XPBarTexture2)
        ByteTerrace.UserInterface.ForceHide(_G["ReputationWatchBar"].StatusBar.XPBarTexture3)
    end
end
Player_GetStatusIndicatorColor = function (colors, isAwayFromKeyboard, isInCombat)
    return (isInCombat and colors.IsInCombat or (isAwayFromKeyboard and colors.IsAwayFromKeyboard or colors.IsNeutral))
end
System_GetAddOnSettings = function ()
    return _G[addOnName]
end
System_GetDefaultAddOnSettings = function ()
    local settings = {
        Camera = {
            ConsoleVariables = {
                CameraKeepCharacterCentered = false,
                test_cameraDynamicPitch = 1.0,
                test_cameraDynamicPitchBaseFovPad = 0.875,
                test_cameraDynamicPitchBaseFovPadDownScale = 1.0,
                test_cameraHeadMovementStrength = 1.0,
                test_cameraHeadMovementMovingStrength = 1.0,
                test_cameraOverShoulder = 0.475,
                test_cameraTargetFocusInteractEnable = true,
                test_cameraTargetFocusInteractStrengthPitch = 0.75,
                test_cameraTargetFocusInteractStrengthYaw = 1.0,
            },
        },
        GamePad = {
            ActionBars = {
                AlphaWhenActive = 1.0,
                AlphaWhenPassive = 0.65,
                ButtonSize = 45,
                OffsetX = 0,
                OffsetY = 220,
            },
            Buttons = {
                PadShoulderLeft = {
                    States = {
                        [1] = { Binding = "TARGETNEARESTENEMY", },
                        [2] = { Binding = "TARGETNEARESTFRIEND", },
                        [3] = { Binding = "UNBOUND", },
                    },
                },
                PadShoulderRight = {
                    States = {
                        [1] = { Binding = "INTERACTMOUSEOVER", },
                        [2] = { Binding = "TOGGLEAUTORUN", },
                        [3] = { Binding = "FLIPCAMERAYAW", },
                    },
                },
                Select = {
                    Binding = "PADSOCIAL",
                    States = {
                        [1] = { Binding = "TOGGLEWORLDMAP", },
                        [2] = { Binding = "OPENALLBAGS", },
                        [3] = { Binding = "TOGGLECHARACTER0", },
                        [4] = { Binding = "TOGGLESOCIAL", },
                        [5] = { Binding = "TOGGLESPELLBOOK", },
                    },
                },
                Start = {
                    Binding = "PADFORWARD",
                    States = {
                        [1] = { Binding = "TOGGLEGAMEMENU", },
                        [2] = { Binding = "TOGGLEGAMEMENU", },
                        [3] = { Binding = "TOGGLEGAMEMENU", },
                        [4] = { Binding = "TOGGLEGAMEMENU", },
                        [5] = { Binding = "TOGGLEGAMEMENU", },
                    },
                },
            },
            ConsoleVariables = {
                GamePadAnalogMovement = true,
                GamePadCameraPitchSpeed = 1.5,
                GamePadCameraYawSpeed = 2.25,
                GamePadCursorAutoDisableJump = true,
                GamePadCursorAutoDisableSticks = "2",
                GamePadCursorAutoEnable = false,
                GamePadCursorCenteredEmulation = false,
                GamePadCursorCentering = false,
                GamePadCursorForTargeting = false,
                GamePadCursorLeftClick = "NONE",
                GamePadCursorOnLogin = true,
                GamePadCursorRightClick = "NONE",
                GamePadEmulateAlt = "NONE",
                GamePadEmulateCtrl = "NONE",
                GamePadEmulateShift = "NONE",
                GamePadEmulateTapWindowMs = 350,
                GamePadEnable = true,
                GamePadFaceMovementMaxAngle = 115.0,
                GamePadFaceMovementMaxAngleCombat = 115.0,
                GamePadFactionColor = false,
                GamePadOverlapMouseMs = 2000,
                GamePadRunThreshold = 0.65,
                GamePadStickAxisButtons = false,
                GamePadTankTurnSpeed = 0.0,
                GamePadTouchCursorEnable = false,
                GamePadTurnWithCamera = "2",
                GamePadVibrationStrength = 1.0,
                SoftTargetEnemy = "1",
                SoftTargetEnemyArc = "1",
                SoftTargetEnemyRange = 30.0,
                SoftTargetFriend = "1",
                SoftTargetFriendArc = "1",
                SoftTargetFriendRange = 10.0,
                SoftTargetForce = "0",
                SoftTargetInteract = "1",
                SoftTargetInteractArc = "1",
                SoftTargetInteractRange = 2.5,
            },
            VendorIdMap = {
                [1118] = "XboxSeriesX",          -- Official Xbox Series X Controller: Bluetooth/USBC
                [1356] = "DualSense",            -- Official PlayStation 5 DualSense Controller: Bluetooth/USBC
                [1406] = "NintendoSwitchPro",    -- Official Nintendo Switch Pro Controller: Bluetooth/USBC
            },
        },
    }

    if ByteTerrace.System.IsClassic() then
        settings.GamePad.ActionBars.ButtonSize = 40
    end

    return settings
end
System_SetAddOnSettings = function (settings)
    _G[addOnName] = settings
end

ByteTerrace.Events.Register({
    ADDON_LOADED = function ()
        local addOnSettings = System_GetAddOnSettings()

        if (nil == addOnSettings) then
            addOnSettings = System_GetDefaultAddOnSettings()

            System_SetAddOnSettings(addOnSettings)
        end

        GamePad_InitializeUserInterface(addOnSettings.GamePad, jumpButton, secureHeader)
        Events_OnGamePadActiveChanged()
    end,
    PLAYER_ENTERING_WORLD = Events_OnPlayerEnteringWorld,
    PLAYER_FLAGS_CHANGED = Events_OnPlayerFlagsChanged,
    PLAYER_REGEN_DISABLED = Events_OnPlayerRegenDisabled,
    PLAYER_REGEN_ENABLED = Events_OnPlayerRegenEnabled,
})

secureHeader:SetAttribute("_onstate-actionbar", [[
    local actionButton5 = self:GetFrameRef("ActionButton5")
    local actionButton9 = self:GetFrameRef("ActionButton9")
    local actionButton11 = self:GetFrameRef("ActionButton11")
    local currentActionBarPage = self:GetAttribute("state-actionbar")
    --local jumpButton = self:GetFrameRef("JumpButton")

    if (1 == currentActionBarPage) then
        actionButton5:Hide()
        actionButton9:Disable()
        actionButton9:Hide()
        actionButton11:Hide()
        --jumpButton:Show()
    else
        actionButton9:Enable()
        actionButton9:Show()
        --jumpButton:Hide()

        if (3 == currentActionBarPage) then
            actionButton5:Show()
            actionButton11:Show()
        elseif (4 == currentActionBarPage) then
            actionButton5:Show()
            actionButton11:Show()
        elseif (5 == currentActionBarPage) then
            actionButton5:Hide()
            actionButton11:Hide()
        elseif (6 == currentActionBarPage) then
            actionButton5:Hide()
            actionButton11:Hide()
        end
    end
]])
secureHeader:SetFrameRef("ActionButton5", _G["ActionButton5"])
secureHeader:SetFrameRef("ActionButton9", _G["ActionButton9"])
secureHeader:SetFrameRef("ActionButton11", _G["ActionButton11"])

if (nil ~= jumpButton) then
    secureHeader:SetFrameRef("JumpButton", jumpButton)

    hooksecurefunc("AscendStop", function () jumpButton:SetButtonState("NORMAL") end)
    hooksecurefunc("JumpOrAscendStart", function () jumpButton:SetButtonState("PUSHED") end)
end

ByteTerrace.GamePad.IconTextureMap = {}
ByteTerrace.Player = {
    IsInCombat = InCombatLockdown(),
}

RegisterAttributeDriver(secureHeader, "state-actionbar", "[bar:1] 1;[bar:3] 3;[bar:4] 4;[bar:5] 5;[bar:6] 6;")

if ByteTerrace.System.IsClassic() then
    hooksecurefunc("ActionButton_UpdateHotkeys", ActionButton_OverrideRangeIndicator)
end
