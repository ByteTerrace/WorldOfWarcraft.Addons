---@type string
local addOnName = select(1, ...)
local api = ByteTerrace
local bindingButton
local isBindingUpdatePending = false
---@param secureButton ButtonFromTemplate
local initializeDriver = function (secureButton)
    secureButton:EnableGamePadButton(true)
    secureButton:RegisterForClicks("AnyDown", "AnyUp")
    secureButton:SetAttribute("action", 1)
    secureButton:SetAttribute("ActionBarPage-State1", 1)
    secureButton:SetAttribute("ActionBarPage-State2", 6)
    secureButton:SetAttribute("ActionBarPage-State3", 5)
    secureButton:SetAttribute("ActionBarPage-State4", 4)
    secureButton:SetAttribute("ActionBarPage-State5", 3)
    secureButton:SetAttribute("type", "actionbar")
    ---@diagnostic disable-next-line: undefined-field
    secureButton:WrapScript(secureButton, "OnClick", [[
        local modifier1 = self:GetAttribute("Modifier1-Input")
        local modifier2 = self:GetAttribute("Modifier2-Input")
        local stateIndex = 1

        if (not down) then
            self:SetAttribute(modifier1, false)
            self:SetAttribute(modifier2, false)
        else
            self:SetAttribute(button, true)

            if (modifier1 == button) then
                if self:GetAttribute(modifier2) then
                    stateIndex = 4
                else
                    stateIndex = 2
                end
            elseif (modifier2 == button) then
                if self:GetAttribute(modifier1) then
                    stateIndex = 5
                else
                    stateIndex = 3
                end
            end
        end

        self:SetAttribute("action", self:GetAttribute("ActionBarPage-State" .. tostring(stateIndex)))

        for i = 1, self:GetAttribute("ActionBinding-Count") do
            local stateAction = self:GetAttribute("Action" .. tostring(i) .. "-State" .. tostring(stateIndex))

            if (nil ~= stateAction) then
                self:SetBinding(true, self:GetAttribute("Action" .. tostring(i) .. "-Input"), stateAction)
            end
        end
    ]])

    if api.System.IsMainline() then
        secureButton:SetAttribute("pressAndHoldAction", true)
        secureButton:SetAttribute("typerelease", "actionbar")
    end
end
---@generic FrameTemplateType
---@param bindings table<string, any>
---@param secureButton ButtonFromTemplate
local setBindings = function (bindings, secureButton)
    if (InCombatLockdown()) then
        isBindingUpdatePending = true

        return
    end

    local actionCount = 0
    local bindingOverrides
    local gamePadType = select(2, api.GamePad.GetType(1))

    if (nil ~= gamePadType) then
        bindingOverrides = gamePadType.BindingOverrides
    end

    SetOverrideBindingClick(secureButton, true, bindings.Modifier1.Input, secureButton:GetName(), bindings.Modifier1.Input)
    SetOverrideBindingClick(secureButton, true, bindings.Modifier2.Input, secureButton:GetName(), bindings.Modifier2.Input)

    for bindingName, bindingTable in pairs(bindings) do
        local input = bindingTable.Input
        local states = bindingTable.States

        if (nil ~= bindingOverrides[input]) then
            input = bindingOverrides[input]
        end

        secureButton:SetAttribute((bindingName .. "-Input"), input)

        if (nil ~= states) then
            actionCount = (actionCount + 1)

            for stateIndex, stateValue in ipairs(states) do
                if (1 == stateIndex) then
                    SetOverrideBinding(secureButton, true, input, stateValue)
                end

                secureButton:SetAttribute((bindingName .. "-State".. tostring(stateIndex)), stateValue)
            end
        end
    end

    secureButton:SetAttribute("ActionBinding-Count", actionCount)
end

api.Events.Register({
    ADDON_LOADED = function (name)
        if (addOnName == name) then
            local addOnSettings = _G[addOnName]

            if (nil == addOnSettings) then
                addOnSettings = {
                    Bindings = {
                        Action1 = {
                            Input = "PADDUP",
                            States = {
                                [1] = "ACTIONBUTTON1",
                            },
                        },
                        Action2 = {
                            Input = "PADDRIGHT",
                            States = {
                                [1] = "ACTIONBUTTON2",
                            },
                        },
                        Action3 = {
                            Input = "PADDDOWN",
                            States = {
                                [1] = "ACTIONBUTTON3",
                            },
                        },
                        Action4 = {
                            Input = "PADDLEFT",
                            States = {
                                [1] = "ACTIONBUTTON4",
                            },
                        },
                        Action5 = {
                            Input = "PADLSHOULDER",
                            States = {
                                [1] = "TARGETNEARESTENEMY",
                                [2] = "TARGETNEARESTFRIEND",
                                [3] = "UNBOUND",
                                [4] = "ACTIONBUTTON5",
                                [5] = "ACTIONBUTTON5",
                            },
                        },
                        Action6 = {
                            Input = "PADLSTICK",
                            States = {
                                [1] = "ACTIONBUTTON6",
                            },
                        },
                        Action7 = {
                            Input = "PAD4",
                            States = {
                                [1] = "ACTIONBUTTON7",
                            },
                        },
                        Action8 = {
                            Input = "PAD3",
                            States = {
                                [1] = "ACTIONBUTTON8",
                            },
                        },
                        Action9 = {
                            Input = "PAD1",
                            States = {
                                [1] = "JUMP",
                                [2] = "ACTIONBUTTON9",
                                [3] = "ACTIONBUTTON9",
                                [4] = "ACTIONBUTTON9",
                                [5] = "ACTIONBUTTON9",
                            },
                        },
                        Action10 = {
                            Input = "PAD2",
                            States = {
                                [1] = "ACTIONBUTTON10",
                            },
                        },
                        Action11 = {
                            Input = "PADRSHOULDER",
                            States = {
                                [1] = "INTERACTMOUSEOVER",
                                [2] = "TOGGLEAUTORUN",
                                [3] = "FLIPCAMERAYAW",
                                [4] = "ACTIONBUTTON11",
                                [5] = "ACTIONBUTTON11",
                            },
                        },
                        Action12 = {
                            Input = "PADRSTICK",
                            States = {
                                [1] = "ACTIONBUTTON12",
                            },
                        },
                        Action13 = {
                            Input = "PADBACK",
                            States = {
                                [1] = "TOGGLEWORLDMAP",
                                [2] = "OPENALLBAGS",
                                [3] = "TOGGLECHARACTER0",
                                [4] = "TOGGLESOCIAL",
                                [5] = "TOGGLESPELLBOOK",
                            },
                        },
                        Action14 = {
                            Input = "PADFORWARD",
                            States = {
                                [1] = "TOGGLEGAMEMENU",
                                [2] = "TOGGLEGAMEMENU",
                                [3] = "TOGGLEGAMEMENU",
                                [4] = "TOGGLEGAMEMENU",
                                [5] = "TOGGLEGAMEMENU",
                            },
                        },
                        Action15 = {
                            Input = "PADSOCIAL",
                        },
                        Action16 = {
                            Input = "PADSYSTEM",
                        },
                        Modifier1 = {
                            Input = "PADLTRIGGER",
                        },
                        Modifier2 = {
                            Input = "PADRTRIGGER",
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
                }

                _G[addOnName] = addOnSettings
            end

            bindingButton = CreateFrame("Button", "ByteTerraceGamePadBindingsButton", UIParent, "SecureActionButtonTemplate, SecureHandlerStateTemplate")

            setBindings(addOnSettings.Bindings, bindingButton)
            initializeDriver(bindingButton)
        end
    end,
    GAME_PAD_CONNECTED = function()
        setBindings(_G[addOnName].Bindings, bindingButton)
    end,
    PLAYER_ENTERING_WORLD = function (isInitialLogin, isReloadingUi)
        if (isInitialLogin or isReloadingUi) then
            api.Console.SetVariables(_G[addOnName].ConsoleVariables)
        end
    end,
    PLAYER_REGEN_ENABLED = function ()
        if (isBindingUpdatePending) then
            setBindings(_G[addOnName].Bindings, bindingButton)
        end
    end,
})
